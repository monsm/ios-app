// LockService — 离线管理端核心: 会话令牌生命周期 / 命令执行 / rc 守卫 / 配网编排
// 与 JS services/lock.js 同构: 无条件刷新令牌 (V81 语义) · rc=3 自愈重试 · G1~G8 守卫
import Foundation
import Combine

@MainActor
final class LockService: ObservableObject {
    static let shared = LockService()
    @Published private(set) var connectedMAC: String = ""
    @Published private(set) var lastError: String = ""
    @Published var logs: [String] = []
    /// 包11/740: 原始报文环形记录 (RX 帧 hex), 供诊断页 hex 查看, 不持久化
    @Published private(set) var recentFrames: [String] = []

    private let ble = BLEService.shared
    private var sessionTokenHex: String = "0000"   // 锁端上报令牌的原始 hex — 整串透传 (JS utils/session.js:15 保存 k.val 全串)
    private var tokenExpiryMs: Int64 = 0
    private var curMac: String = ""
    private var pairMac: String?
    private var connectedDeviceId: String = ""  // BLE deviceId (UUID); connectedMAC = 解析出的锁 MAC

    init() {
        ble.onFrame { [weak self] frame in
            Task { @MainActor in self?.handle(frame) }
        }
        ble.bootstrap()
    }

    var debugRaw: Bool { DB.store.getBool("kf_debug_raw") }

    func log(_ level: String, _ msg: String) {
        // 同一份时间戳口径收进 DiagTime (hhmmss 此前零调用, 而这里手写了一份重复实现)
        let t = DiagTime.hhmmss()
        // 原始帧 hex 只进内存环形 recentFrames (诊断页 740 即时查看用): 帧内携带 skey/ekey/PIN 明文
        // (cmd05 换钥 / cmd0A 写密码 / cmd13 录指纹)。任何持久化或可复制出口都必须先脱敏 ——
        // logs 会被诊断页写进剪贴板, DiagLogs 落 kf_diag_logs (全仓无 isExcludedFromBackup → 随系统备份出机)
        // 并被导出中心 rawHexLines + ShareLink 带走。违 AUTOOPEN-PLAN §1「永不记 ekey/skey 明文」。
        let rawFrame = msg.contains("hex=")
        if rawFrame {
            recentFrames.append(msg)
            if recentFrames.count > 60 { recentFrames.removeFirst(recentFrames.count - 60) }
        }
        let shown = rawFrame ? Redact.frameHex(msg) : msg
        logs.append("\(t) [\(level)] \(shown)")
        if logs.count > 200 { logs.removeFirst(logs.count - 200) }
        if level == "warn" || level == "error" { lastError = shown }
        // 包11: 分级日志台账 (153/283/542/543 的解析源), 按 751 保留策略留档
        DiagLogs.append(level, shown, date: DiagLogs.localDay(), time: t)
    }

    // ---------- 连接 ----------
    func connect(deviceId: String) async throws {
        try await ble.connect(deviceId: deviceId)
        connectedDeviceId = deviceId
        connectedMAC = DB.keychains().first(where: { $0.bleId == deviceId })?.mac ?? ""
        DB.lastDevice = deviceId
        log("info", "已连接 " + deviceId)
    }
    func disconnect() {
        rejectWaiter("连接已断开")
        // JS lock.js:112 的 G2: 断链必须清多响应回调, 否则残 collector 会吞掉下次连接的同 cmd 帧
        collector = nil
        collectorCmd = 0
        ble.disconnect()
        connectedDeviceId = ""
        connectedMAC = ""
        curMac = ""
        sessionTokenHex = "0000"
        tokenExpiryMs = 0
    }
    // 幂等按需连接: 已连同一把 → 直接; 缓存 bleId → 直连; 失败 → MAC 扫描解析 (回写缓存)
    func ensureConnected(mac: String) async throws {
        let m = mac.lowercased()
        guard !m.isEmpty else { throw BLEErrorX.msg("未选择门锁 (缺少 MAC)") }
        if connectedMAC == m, ble.connectedMAC == connectedDeviceId, !connectedDeviceId.isEmpty {
            // 已在目标锁上也要绑 curMac: 否则紧随其后的无 mac 参数命令 (setZotp/readLockTime…) 会用
            // **上一次会话留下的另一把锁**的 skey 成帧 —— 第三条成功出口 (扫描解析) 一直是绑的，这两条漏了。
            curMac = m
            return
        }
        if !connectedDeviceId.isEmpty { disconnect() }
        guard let kc = DB.keychain(m) else { throw BLEErrorX.msg("找不到 MAC=\(m) 的钥匙串 (请先配对或导入)") }
        if !kc.bleId.isEmpty {
            do {
                try await connect(deviceId: kc.bleId)
                connectedMAC = m
                curMac = m
                return
            } catch {
                log("warn", "缓存 deviceId 直连失败 (\(error.localizedDescription)), 回退 MAC 扫描解析")
            }
        }
        log("info", "扫描解析 MAC=\(m) (请靠近门锁)")
        let deviceId = try await scanForMAC(m, timeoutMs: 8000)
        // 2026-10-13 对抗式排查: 连接成立后再验一次**锁端自报的身份**, 而不是只认广播字段。
        // scanForMAC 只比对广播厂商段里的 macRaw —— 而广播是**任何设备都能发**的: 攻击者广播一份
        // 含目标 MAC 的厂商段并暴露 6E400001, App 就会连到他, 之后把 cmd03/04 的密文发给他。
        // 原实现在这里把 deviceId 直接写回钥匙串缓存 (kc2.bleId) ⇒ **持久污染**:
        // 之后每次冷启动都从缓存 deviceId 直连攻击者, 连扫描都不走。
        // 修法两段: ① 连上后先读一次状态 (cmd03), 用**锁端自己的响应**对 pid ——
        //   响应比广播难伪造得多; ② 对不上就断开并**不写缓存** (identity mismatch 不落盘)。
        //   钥匙串里没登记 pid (老配对) 时只记警告不拦, 免得把正常用户挡在门外。
        try await connect(deviceId: deviceId)
        do {
            let st = try await getStatus(mac: m)
            let knownPid = kc.pid
            if knownPid > 0, st.pid > 0, st.pid != knownPid {
                disconnect()
                log("warn", "连接后身份不符: 锁端 pid=\(st.pid) 与登记的 pid=\(knownPid) 不一致 → 已断开, 不写缓存")
                throw BLEErrorX.msg("连到的设备与「\(kc.name)」不是同一把锁 (pid 不符)，已断开。附近可能有同名或伪造广播。")
            }
            if knownPid <= 0 { log("warn", "钥匙串未登记 pid, 跳过连接后身份复核 (老配对)") }
        } catch let e as BLEErrorX {
            throw e
        } catch {
            log("warn", "连接后读状态失败 (\(error.localizedDescription)) → 断开, 不写缓存")
            disconnect()
            throw BLEErrorX.msg("连上后读不到锁端状态，已断开重来")
        }
        var kc2 = kc
        kc2.bleId = deviceId
        DB.saveKeychain(kc2)
        connectedMAC = m
        curMac = m   // 仅连接成功后设当前锁 (失败不留残态)
    }
    func scanForMAC(_ macHex: String, timeoutMs: Int) async throws -> String {
        try await ble.startScan(timeoutMs: timeoutMs)
        defer { ble.stopScan() }
        let target = macHex.lowercased()
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        while Date() < deadline {
            if let d = ble.allDiscovered().first(where: { adv in
                guard let a = ZKProtocol.parseAdv(adv.advertisHex), let macRaw = a.macRaw else { return false }
                return macRaw == target || (a.macDisplay?.replacingOccurrences(of: ":", with: "").lowercased() == target)
            }) {
                ble.stopScan()
                log("info", "扫描命中 MAC=\(target) → \(d.deviceId)")
                return d.deviceId
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        ble.stopScan()
        throw BLEErrorX.code(.notFound)
    }

    // ---------- 帧等待 ----------
    struct Waiter {
        var cmd: UInt8
        var cont: CheckedContinuation<ZKProtocol.ParsedFrame, Error>
        var timer: DispatchWorkItem?
    }
    private var waiter: Waiter?
    private var collector: ((ZKProtocol.ParsedFrame) -> Void)?   // 多响应命令 (13 录指纹)
    private var collectorCmd: UInt8 = 0
    private func handle(_ frame: ZKProtocol.ParsedFrame) {
        guard frame.ok else { return }
        if let cb = collector, frame.cmd == collectorCmd { cb(frame); return }
        guard let w = waiter, frame.cmd == w.cmd else { return }
        w.timer?.cancel()
        waiter = nil
        w.cont.resume(returning: frame)
    }
    // 断链/清理时即刻拒绝挂起等待 (JS G1 语义 — 调用方不空等 8s)
    private func rejectWaiter(_ msg: String) {
        if let w = waiter {
            w.timer?.cancel()
            waiter = nil
            w.cont.resume(throwing: BLEErrorX.msg(msg))
        }
    }
    // ---------- 令牌 ----------
    private func ensureToken() async throws {
        log("info", "刷新会话令牌 (cmd 01)")
        let f = try await request(ZKCmdBuilder.cmd01Session(), cmd: 0x01, needToken: false, retries: 3)
        guard let k = f.klvs.first(where: { $0.key == 0x02 }) else {
            throw BLEErrorX.msg("01 响应无令牌")
        }
        // 安全类型 gate 已删: JS lock.js _ensureToken 从不检查 (V81 注释 — Java 发送路径也从不检查),
        // 只要 KLV#02 令牌在就继续。Swift 之前的整串 intHex&3 硬抛会让
        // 安全类型编为 2 字节 (如 "0200"→512&3=0) 或缺 KLV#01 的固件配网必败, 而小程序正常。
        // 旧实现 readU16LE 把令牌截成 2 字节: 锁若上报 4B 令牌, 注入值就是错的 → 所有需令牌写命令必失败
        sessionTokenHex = k.val.lowercased()
        let secs = f.klvs.first(where: { $0.key == 0x03 }).map { UInt16(truncatingIfNeeded: HexKit.readU16LE($0.val, byteOffset: 0)) } ?? 0
        // JS session.js: ttl=0 保留默认 45s — now+0+2s 会立即过期
        if secs > 0 {
            tokenExpiryMs = Int64(Date().timeIntervalSince1970 * 1000) + Int64(secs) * 1000 + 2000
        }
        log("info", "会话令牌就绪 token=\(String(sessionTokenHex.prefix(4)))…(\(sessionTokenHex.count) 位) ttl=\(secs)s")
    }

    // ---------- 请求 (令牌注入 + 重试 + 写失败清 waiter) ----------
    @discardableResult
    private func request(_ cmdObj: ZKCmd, cmd: UInt8, needToken: Bool, retries: Int, timeoutMs: Int = 8000) async throws -> ZKProtocol.ParsedFrame {
        var hex = cmdObj.hex
        // 只读试验模式 (kf_trial_guard): 放行只读命令, 拦死写入/危险命令 — 忠实移植 JS assertReadOnly
        if DB.store.getBool("kf_trial_guard", false) { try ZKProtocol.assertReadOnly(cmd) }
        // 空帧拦截: 密钥/参数非法导致构造失败时绝不发包 (见 ZKProtocol.wrapEnc 的 cipher.isEmpty 约定)
        guard !hex.isEmpty else {
            throw BLEErrorX.msg("\(cmdObj.name) 帧构造失败 (密钥或参数无效), 已中止下发")
        }
        if needToken {
            try await ensureToken()
            hex = ZKProtocol.injectToken(hex, sessionTokenHex)
        }
        var lastErr: Error = BLEErrorX.code(.writeFailed)
        for attempt in 0..<max(1, retries) {
            let frame: ZKProtocol.ParsedFrame
            do {
                log("info", "TX \(cmdObj.name) attempt=\(attempt + 1)/\(retries) needToken=\(needToken)")
                // 先挂 waiter 再写 (防响应早于 waiter 注册)
                let respTask = Task<ZKProtocol.ParsedFrame, Error> { @MainActor in
                    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ZKProtocol.ParsedFrame, Error>) in
                        // 超时定时器与 waiter 绑定 (命中/失败即取消) — 防陈旧定时器误杀下一轮同 cmd 等待
                        let timer = DispatchWorkItem {
                            guard let w = self.waiter, w.cmd == cmd else { return }
                            self.waiter = nil
                            w.cont.resume(throwing: BLEErrorX.code(.responseTimeout))
                        }
                        // 忙判: 已有命令在飞时直接拒绝 (JS lock.js _waitFrame 同款) — 覆盖会让旧 continuation 永不 resume
                        if self.waiter != nil {
                            cont.resume(throwing: BLEErrorX.msg("已有命令在等待响应"))
                            return
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(timeoutMs), execute: timer)
                        self.waiter = Waiter(cmd: cmd, cont: cont, timer: timer)
                    }
                }
                do {
                    if debugRaw { log("info", "TX hex=\(hex)") }
                    try await ble.writeFrameHex(hex)
                } catch {
                    // 写失败: 显式续跑挂起的 waiter (防 continuation 泄漏), 交由上层重试
                    if let w = waiter, w.cmd == cmd {
                        w.timer?.cancel()
                        waiter = nil
                        w.cont.resume(throwing: error)
                    }
                    throw error
                }
                frame = try await respTask.value
                if debugRaw { log("info", "RX cmd=\(String(format: "%02x", frame.cmd)) hex=\(frame.raw)") }
                return frame
            } catch {
                lastErr = error
                // 写类命令 + "指令可能已生效"的失败 = 不重发, 交上层判定 (防止电机连触发/双开)。
                // 旧实现只挡 responseTimeout; 2026-10-13 对抗式排查补上 writeFailed ——
                // writeFailed 是"写入没回确认", 而 BLE 的 write 完全可能是**字节已送到、ack 丢了**,
                // 锁端已经执行了。随后断链自愈 (下面那段) 会重连, 外层 for attempt 再发一次
                // ⇒ 一条 cmd04 被下发两次 = 双开门。防误触的三道保险对第二条真实开门无效。
                if ZKProtocol.writeCmdsBlocked.contains(cmd) {
                    var maybeExecuted = false
                    if case BLEErrorX.code(.responseTimeout) = error { maybeExecuted = true }
                    if case BLEErrorX.code(.writeFailed) = error { maybeExecuted = true }
                    if maybeExecuted {
                        log("warn", "\(cmdObj.name) 写命令失败(响应超时或写失败, 指令可能已生效) → 不重发 (避免重复执行), 交上层判定")
                        break
                    }
                }
                // 只清自己 cmd 的 waiter (JS lock.js 按 ww.cmd === cmd 清理), 不误杀并发中的其他请求
                if let w = waiter, w.cmd == cmd { w.timer?.cancel(); waiter = nil }
                // 断链自愈: 写失败 OR 连接已断 (断链后 writeChar/device 被清 → writeFrameHex 抛 parseFail)
                var brokenLink = ble.connectedMAC.isEmpty || connectedDeviceId.isEmpty
                if case BLEErrorX.code(.writeFailed) = error { brokenLink = true }
                if brokenLink {
                    disconnect()
                    if !curMac.isEmpty { try? await ensureConnected(mac: curMac) }
                }
                log("warn", "cmd \(String(format: "%02x", cmd)) 第 \(attempt + 1) 次失败: \(error.localizedDescription)")
            }
        }
        throw lastErr
    }

    // rc 所在 KLV key (JS lock.js RC_KLV, 勘误后权威表)
    private static let rcKLV: [UInt8: Int] = [
        0x03: 3, 0x04: 3, 0x05: 1, 0x08: 3, 0x0a: 3, 0x0b: 3, 0x0e: 3, 0x12: 3,
        0x13: 3, 0x14: 3, 0x15: 3, 0x16: 3, 0x18: 3, 0x19: 3, 0x20: 3,
        0x21: 3, 0x22: 3, 0x24: 3, 0x25: 3
    ]
    private func extractRc(_ cmd: UInt8, _ resp: ZKProtocol.ParsedFrame) -> Int {
        guard let key = LockService.rcKLV[cmd] else { return 0 }
        guard let k = resp.klvs.first(where: { $0.key == key }) else { return -1 }
        return StatusParser.intHex(k.val)
    }
    struct ExecResult { var frame: ZKProtocol.ParsedFrame; var rc: Int; var klvs: [ZKLV] }

    private func exec(_ cmdObj: ZKCmd, needToken: Bool = true, retries: Int = 3) async throws -> ExecResult {
        let cmd = cmdObj.cmd
        let resp = try await request(cmdObj, cmd: cmd, needToken: needToken, retries: retries)
        let rc = extractRc(cmd, resp)
        // rc=3 (命令过期/令牌失效) → 刷令牌重试一次
        if rc == 3 && needToken {
            log("warn", "\(cmdObj.name) rc=3 → 刷新令牌重试一次")
            sessionTokenHex = "0000"
            let resp2 = try? await request(cmdObj, cmd: cmd, needToken: true, retries: 1)
            if let r2 = resp2 {
                let rc2 = extractRc(cmd, r2)
                if rc2 != 3 { return ExecResult(frame: r2, rc: rc2, klvs: r2.klvs) }
            }
        }
        log("info", "\(cmdObj.name) -> rc=\(rc)")
        return ExecResult(frame: resp, rc: rc, klvs: resp.klvs)
    }
    @discardableResult
    private func execOk(_ cmdObj: ZKCmd, needToken: Bool = true, retries: Int = 3) async throws -> ExecResult {
        let r = try await exec(cmdObj, needToken: needToken, retries: retries)
        // rc = -1 的含义是"该命令按 rcKLV 表本应带 rc KLV, 但回包里没有" (extractRc 只在 cmd 命中表时才返回 -1)。
        // 旧实现把它与 rc=0 同等放行, 于是帧解析错位、密文解不开、固件异常短回包都会被报成"已写入/已删除"。
        // 写命令面按 fail-closed 处理: 拿不到锁端结果就抛错, 让 UI 显示未确认而不是成功。
        if r.rc == -1 {
            throw BLEErrorX.msg("\(cmdObj.name) 回包缺少 rc KLV, 无法确认锁端结果 — 请重试")
        }
        if r.rc != 0 { throw BLEErrorX.msg(StatusParser.rcMessage(r.rc)) }
        return r
    }

    // ---------- 密钥面 ----------
    /// 换钥 (cmd05) 之后任何一步失败: 锁内 skey 已是新值而本机没存钥匙串,
    /// 光报"某步失败"会让用户反复重试却永远配不上 (软砖的成因就是这个信息缺失)。
    static func pairWarning(_ exchanged: Bool, _ msg: String) -> String {
        exchanged ? "密钥已交换 (锁内 skey 已更新), 但 \(msg) — 本机未保存钥匙串, 门锁需重新做键盘重置后再配网" : msg
    }
    private func keys() throws -> (mac: String, skey: String) {
        let kc = DB.keychain(curMac)
        guard let kc, kc.skey.count == 32 else { throw BLEErrorX.msg("钥匙串缺少有效 skey (请先配对或导入)") }
        return (kc.mac.lowercased(), kc.skey.lowercased())
    }

    // ---------- 状态 ----------
    func getStatus(mac: String? = nil) async throws -> LockStatus {
        if let mac { curMac = mac.lowercased() }
        let kc = DB.keychain(curMac)
        var r: ExecResult
        if let kc, !kc.skey.isEmpty {
            let (m, sk) = try keys()
            r = try await exec(ZKCmdBuilder.cmd03StatusWrap(m, sk))
        } else {
            r = try await exec(ZKCmdBuilder.cmd03StatusPlain(curMac), needToken: false)
        }
        let st = StatusParser.parseStatus(r.klvs)
        if st.rc == 0 {
            DB.writeStatus(curMac, st) // 离线快照 (随时可读)
            BatteryCare.sample(curMac, pct: st.powerLevel)   // 包4/45: 电量本地采样埋点 (90 天截断)
            FirmwareHistory.record(mac: curMac, fw: st.firmware)   // 755: 顺带记"哪天读到哪个固件"
        }
        return st
    }
    func readLockTime() async throws -> Int64 {
        let st = try await getStatus()
        guard let t = st.lockTime else { throw BLEErrorX.msg("状态中无锁钟 (KLV#04)") }
        return t
    }

    // ---------- 开锁 ----------
    func unlock(mac: String? = nil, pinDec: String? = nil) async throws -> Int {
        if let mac { curMac = mac.lowercased() }
        guard let kc = DB.keychain(curMac), !kc.skey.isEmpty else { throw BLEErrorX.msg("无钥匙串, 无法开锁") }
        let cred: String
        if !kc.ekey.isEmpty {
            cred = kc.ekey                                     // 配网时已签发
        } else {
            let pin = pinDec ?? kc.pins.first
            guard let pin, !pin.isEmpty else { throw BLEErrorX.msg("无 PIN 可用: 需要 ekey 或 PIN 才能签发开锁凭证") }
            cred = ZKCmdBuilder.buildEkeyOpen(kc.skey.lowercased(), kc.mac.lowercased(), pin)
        }
        guard !cred.isEmpty else { throw BLEErrorX.msg("开锁凭证为空 (ekey/PIN 签发失败), 已中止下发") }
        let r = try await exec(ZKCmdBuilder.cmd04Open(cred, klv01Hex: "0000"), retries: 2)
        return r.rc  // 0 成功; 22 双验继续
    }

    // ---------- 布防 / 时间 / 设置 ----------
    func setDefence(control: Int, startSec: Int, endSec: Int) async throws {
        let (m, sk) = try keys()
        try await execOk(ZKCmdBuilder.cmd25Defence(m, sk, control, startSec, endSec))
    }
    func syncTime() async throws {
        let (m, sk) = try keys()
        var offset: Int64 = 0
        if let lockSec = try? await readLockTime() {
            offset = lockSec - ZKProtocol.nowProtoSeconds()
        } else {
            log("warn", "读锁钟失败, 直接用手机时间")
        }
        let target = ZKProtocol.nowProtoSeconds() + offset
        try await execOk(ZKCmdBuilder.cmd0ESyncTime(m, sk, target))
        DB.saveSyncTime(m, Date().timeIntervalSince1970 * 1000)
    }
    func setSilent(_ on: Bool) async throws {
        let (m, sk) = try keys()
        try await execOk(ZKCmdBuilder.cmd18Volume(m, sk, on))
    }
    /// cmd 20 验证模式 (A/B)。入口在设置-安全模式说明 (拍板 #2, 第六十六批)：**只允许 A→B 变严**,
    /// 且调用方必须回读 verifyMode 才能报成功 (rc=0 只证明命令被接收, 不证明策略变了)。不给 B→A。
    func setValidationMode(_ bMode: Bool) async throws {
        let (m, sk) = try keys()
        try await execOk(ZKCmdBuilder.cmd20ValidationMode(m, sk, bMode))
    }
    func setAutoLock(_ interval: Int) async throws {
        let (m, sk) = try keys()
        try await execOk(ZKCmdBuilder.cmd24AutoLock(m, sk, interval))
    }
    func setZotp(_ on: Bool) async throws {
        let (m, sk) = try keys()
        try await execOk(ZKCmdBuilder.cmd19OpenZotp(m, sk, on))
    }

    // ---------- 密码 ----------
    // 0A 响应 KLV#04 = alias (LE 2B)
    private func aliasFrom(_ r: ExecResult) -> Int? {
        // JS: val.length >= 2, raw = len>=4 ? substr(0,4) : val → LE 解析
        guard let k = r.klvs.first(where: { $0.key == 0x04 }), k.val.count >= 2 else { return nil }
        let raw = k.val.count >= 4 ? String(k.val.prefix(4)) : k.val
        return Int(StatusParser.leHexToU32(raw))
    }
    @discardableResult
    func pwdAdd(pwd: String, validFrom: String, validTo: String) async throws -> Int {
        let (m, sk) = try keys()
        let r = try await execOk(try ZKCmdBuilder.cmd0ASyncPwd(m, sk, delAlias: 0, addPwd: pwd, validFrom: validFrom, validTo: validTo))
        guard let alias = aliasFrom(r) else {
            log("warn", "0A 响应无 KLV#04 alias (固件未返回)")
            return 0
        }
        // 第二步: 0B 设置有效期 (App 两步链)
        do {
            _ = try await execOk(ZKCmdBuilder.cmd0BSyncPwdExpire(m, sk, alias, validFrom, validTo))
        } catch {
            log("warn", "0B 设置有效期失败(不影响添加): \(error.localizedDescription)")
        }
        // 543: 实体标记写成"凭证#N", 与 DiagKit.entities 的识别词表同一口径
        log("info", "凭证#\(alias) 已添加 (0A+0B)")
        return alias
    }
    @discardableResult
    func pwdModify(alias: Int, pwd: String, validFrom: String, validTo: String) async throws -> Int {
        let (m, sk) = try keys()
        let r = try await execOk(try ZKCmdBuilder.cmd0ASyncPwd(m, sk, delAlias: alias, addPwd: pwd, validFrom: validFrom, validTo: validTo))
        let got = aliasFrom(r) ?? alias
        log("info", "凭证#\(alias) 已改写" + (got == alias ? "" : ", 锁端新编号 凭证#\(got) (0A 删旧+加新)"))
        return got
    }
    func pwdDelete(_ alias: Int) async throws {
        let (m, sk) = try keys()
        try await execOk(try ZKCmdBuilder.cmd0ASyncPwd(m, sk, delAlias: alias))
        log("info", "凭证#\(alias) 已删除 (0A)")
    }
    func pwdClear() async throws {
        let (m, sk) = try keys()
        try await execOk(try ZKCmdBuilder.cmd0ASyncPwd(m, sk, delAlias: 0xFFFF))
    }
    func pwdExpire(_ alias: Int, _ from: String, _ to: String) async throws {
        let (m, sk) = try keys()
        try await execOk(ZKCmdBuilder.cmd0BSyncPwdExpire(m, sk, alias, from, to))
        log("info", "凭证#\(alias) 有效期已设置 (0B)")
    }

    // ---------- 指纹 ----------
    struct FpPress {
        var orderIdx: UInt32?
        var featureNumber: UInt32?
        var batchNumber: UInt32?
        var nextTimeout: UInt32?
        var rc: Int
    }
    // cmd 13: 一次请求多响应 — 锁逐次按压逐次回帧 (orderIdx 1..N, orderIdx==0 收尾), JS _execMulti 语义
    // onPress 是**纯 UI 出口**: 每收到一帧就在 MainActor 上调一次 (collector 由 handle() 起,
    // 而 handle 本身就是 Task { @MainActor in … })，让录入页的 8 点进度能实时填。
    // 返回值与不传 onPress 时逐字节一致 —— 不拿它当协议能力，只是把已有数据早一点交给界面。
    func fpStart(times: Int = 8, timeoutMs: Int = 30000,
                 onPress: ((FpPress) -> Void)? = nil) async throws -> [FpPress] {
        let (m, sk) = try keys()
        try await ensureToken()
        let hex = ZKProtocol.injectToken(ZKCmdBuilder.cmd13AddFp(m, sk, times, 15).hex,
                                         sessionTokenHex)
        var frames = [ZKProtocol.ParsedFrame]()
        // 与 JS lock.js:507-511 同一套取值口径 (0x04 序号 / 0x05 特征号 / 0x06 批次 / 0x07 下一次超时)
        func press(of f: ZKProtocol.ParsedFrame) -> FpPress {
            func u32(_ key: UInt8) -> UInt32? {
                f.klvs.first(where: { $0.key == key }).map { StatusParser.leHexToU32($0.val) }
            }
            return FpPress(orderIdx: u32(0x04), featureNumber: u32(0x05),
                           batchNumber: u32(0x06), nextTimeout: u32(0x07), rc: extractRc(0x13, f))
        }
        collectorCmd = 0x13
        collector = { f in
            guard f.cmd == self.collectorCmd else { return }
            frames.append(f)
            if let onPress { onPress(press(of: f)) }
        }
        defer { collector = nil; collectorCmd = 0 }
        log("info", "TX 13 录指纹 (多响应, \(times) 次按压)")
        var attemptsLeft = 2 // JS _execMulti retries=2: 无帧时重发一次
        while frames.isEmpty && attemptsLeft > 0 {
            attemptsLeft -= 1
            try await ble.writeFrameHex(hex)
            let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
            while Date() < deadline {
                // 断链/取消早退: 旧写法会一直转到 30s 到点才抛"未收到任何按压响应",
                // 期间锁已被人拿走/电量耗尽也不知情, collector 也一直被占 (新会话的 cmd13 帧会被吞)
                if Task.isCancelled || ble.connectedMAC.isEmpty || connectedDeviceId.isEmpty {
                    log("warn", "13 录指纹中链路断开或任务取消, 提前结束")
                    break
                }
                // 收尾: 任一帧 orderIdx == 0
                if frames.contains(where: { f in
                    f.klvs.first(where: { $0.key == 0x04 }).map { StatusParser.leHexToU32($0.val) } == 0
                }) { break }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        guard !frames.isEmpty else { throw BLEErrorX.msg("13 未收到任何按压响应") }
        return frames.map { press(of: $0) }
    }
    func fpConfirm(_ batchNumber: UInt32, validFrom: String, validTo: String) async throws {
        let (m, sk) = try keys()
        try await execOk(ZKCmdBuilder.cmd14FpConfirm(m, sk, batchNumber, validFrom, validTo))
        log("info", "指纹#\(batchNumber) 已确认并设置有效期")   // 14 指纹
    }
    func fpDelete(_ batchNumber: UInt32) async throws {
        let (m, sk) = try keys()
        try await execOk(ZKCmdBuilder.cmd15DeleteFp(m, sk, batchNumber))
        log("info", "指纹#\(batchNumber) 已删除")   // 15 指纹
    }

    // ---------- 日志 ----------
    struct LogPage { var surplus: Int?; var logs: [LogEntry] }
    func getLogs(orderType: Int = 0, startIdx: UInt32, pageSize: Int = 5) async throws -> LogPage {
        let (m, sk) = try keys()
        let r = try await exec(ZKCmdBuilder.cmd16GetLog(m, sk, orderType: orderType, startIdx: startIdx, pageSize: pageSize))
        if r.rc != 0 && r.rc != -1 { throw BLEErrorX.msg(StatusParser.rcMessage(r.rc)) }
        let surplus = r.klvs.first(where: { $0.key == 0x04 }).map { Int(StatusParser.leHexToU32($0.val)) }
        let logs = StatusParser.parseLogs(r.klvs)
        // 截断条数只在"锁回来的这一页"上有意义，所以记在拉日志的这里，不进 LogEntry 模型 (§10.46)：
        // 不记就等于"有一条记录的时间/类型看着怪"永远解释不清，而它其实是帧被截半条。
        let truncated = StatusParser.truncatedLogCount(r.klvs)
        if truncated > 0 {
            log("warn", "这一页日志有 \(truncated) 条声明长度与实际长度不符 (帧被截断或超长)，已按原样入缓存")   // 16 这一页日志有
        }
        return LogPage(surplus: surplus, logs: logs)
    }

    // ---------- DFU 进入 (cmd 22) ----------
    func enableDfu() async throws {
        let (m, sk) = try keys()
        do {
            _ = try await execOk(ZKCmdBuilder.cmd22EnableDfu(m, sk, 0), retries: 2)
        } catch {
            // 锁重启瞬间断链属预期 (App sendDFUCmd 同样只等 rc)
            let msg = error.localizedDescription
            if msg.contains("断开") || msg.contains("disconnect") {
                log("info", "cmd 22 后锁断链 (进入升级模式的预期行为)")
                return
            }
            throw error
        }
    }

    // ---------- 配网编排 (重置后全流程, App devicereset 页) ----------
    func pair(deviceId: String, mac: String, progress: @escaping (String) -> Void) async throws -> Keychain {
        let m = mac.replacingOccurrences(of: ":", with: "").lowercased()
        pairMac = m
        if let old = DB.keychain(m), !old.skey.isEmpty {
            throw BLEErrorX.msg("该锁已有钥匙串 (MAC=\(old.mac)), 拒绝覆盖配网; 如需重配请先删除该设备")
        }
        try await connect(deviceId: deviceId)
        curMac = m
        defer { pairMac = nil }

        progress("步骤 1/7: 探测交换方式 (cmd 23)")
        let w = try await request(ZKCmdBuilder.cmd23ExKeyWay(), cmd: 0x23, needToken: false, retries: 3)
        let way = w.klvs.first(where: { $0.key == 0x01 }).map { StatusParser.intHex($0.val) } ?? 0
        guard way & 2 != 0 else { throw BLEErrorX.msg("交换方式不支持 (exSKeyWay=\(way)), 固件要求 bit1=1") }

        progress("步骤 2/7: 生成本地密钥 (skey/bkey/64 PIN)")
        // genSkey/genBkey 并不抛错, 旧写法套了 `try` (Swift 里是 "no calls to throwing functions" 告警)
        let skey = KeyGen.genSkey()
        let bkey = KeyGen.genBkey()
        let pins = try KeyGen.genPins(64)
        // 全零是"随机源故障"的特征值: 旧 KeyGen 丢弃 SecRandomCopyBytes 的状态码, 失败时返回全零缓冲,
        // 于是锁与本机都用 "0000…" 通信 —— 抓一帧即可解密, 而 7 步流程一路绿灯。此处 fail-closed 中止。
        guard !KeyGen.isAllZeroHex(skey), !KeyGen.isAllZeroHex(bkey),
              !pins.contains(where: { KeyGen.isAllZeroHex($0) }) else {
            throw BLEErrorX.msg("随机源异常: 生成的密钥族含全零字段, 已在换钥前中止 (锁未被改动, 可稍后重试)")
        }

        progress("步骤 3/7: cmd 05 交换密钥")
        let r5 = try await request(ZKCmdBuilder.cmd05Exchange(skey), cmd: 0x05, needToken: false, retries: 3)
        let rc5 = extractRc(0x05, r5)
        if rc5 != 0 { throw BLEErrorX.msg("换钥失败 rc=\(rc5) (\(StatusParser.rcMessage(rc5))) — 锁可能未处于重置态") }
        var keyExchanged = false
        if let echo = r5.klvs.first(where: { $0.key == 0x02 }), echo.val.lowercased() != skey.lowercased() {
            // skey 明文绝不进错误文案: 该串会写入 lastError → DiagLogs → kf.diag_logs (随系统备份) 与 UI 展示
            throw BLEErrorX.msg("换钥回显不匹配 (本地/回显长度 \(skey.count)/\(echo.val.count)), 已中止")
        }

        keyExchanged = true        // 自此以后失败 = 锁内新密钥已生效, 必须按 pairWarning 告知
        progress("步骤 4/7: 获取会话令牌")
        try await ensureToken()

        progress("步骤 5/7: 同步 PIN 池 (4 批)")
        let batchSize = 16
        for i in 0..<4 {
            let batch = Array(pins[i * batchSize..<(i + 1) * batchSize])
            let del = (i == 0) ? [KeyGen.delPinSentinel] : []
            guard let c = ZKCmdBuilder.cmd08SyncPinsBatch(m, skey, batch, delPins: del) else {
                throw BLEErrorX.msg("PIN 批次构建失败")
            }
            let rb = try await exec(c)
            if rb.rc != 0 { throw BLEErrorX.msg(Self.pairWarning(keyExchanged, "PIN 批次 \(i + 1) 失败 rc=\(rb.rc) (\(StatusParser.rcMessage(rb.rc)))")) }
        }

        progress("步骤 6/7: 设置 bkey (cmd 21)")
        let r21 = try await exec(ZKCmdBuilder.cmd21SetBkey(m, skey, bkey))
        if r21.rc != 0 { throw BLEErrorX.msg(Self.pairWarning(keyExchanged, "bkey 失败 rc=\(r21.rc)")) }

        progress("步骤 7/7: 加密状态校验 (cmd 03)")
        let stR = try await exec(ZKCmdBuilder.cmd03StatusWrap(m, skey))
        let st = StatusParser.parseStatus(stR.klvs)
        if stR.rc != 0 { throw BLEErrorX.msg(Self.pairWarning(keyExchanged, "配对校验失败 rc=\(stR.rc)")) }

        let kc = Keychain(version: 1, mac: m, pid: st.pid, pidName: st.pidName,
                          skey: skey, bkey: bkey, pins: pins,
                          ekey: ZKCmdBuilder.buildEkeyOpen(skey, m, pins[0]),
                          trackid: String(KeyGen.genTrackId()),
                          bleId: deviceId, fw: st.firmware,
                          pairedAt: ISO8601DateFormatter().string(from: Date()))
        DB.saveKeychain(kc)
        connectedMAC = m
        progress("配网完成: \(st.pidName.isEmpty ? "pid=\(st.pid)" : st.pidName) @ \(m)")
        return kc
    }
}

/// 帧 hex 脱敏: 保留长度与前 4 位供排障对位, 密钥材料不落盘、不外传。
/// 放在文件作用域而非 LockService 内: 该类是 @MainActor, 嵌套类型会继承隔离域,
/// 导致非隔离上下文 (BackupKit.restoreAll / 日志工具) 无法复用同一份脱敏实现。
enum Redact {
    static func frameHex(_ s: String) -> String {
        guard let r = s.range(of: "hex=") else { return s }
        let tail = s[r.upperBound...]
        var taken = ""
        for c in tail { if c.isHexDigit { taken.append(c) } else { break } }
        guard taken.count >= 8 else { return s }
        let head = String(taken.prefix(4))
        return String(s[..<r.upperBound]) + head + "(\(taken.count) 位已隐去)" + String(tail.dropFirst(taken.count))
    }
}
