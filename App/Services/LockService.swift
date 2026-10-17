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
            // 配网期这条基本只有一个含义: 锁已退回不可配网态 (01 拿不到令牌 ⇒ 之后每一步令牌面命令都发不出去)。
            // 与 05 被拒时同一取证口径: 留"回包形状"(只键与长度, 无值) + 该做什么, 免得现场只看到一句"无令牌"。
            log("error", "01 会话令牌响应缺 KLV#02 · 回包 " + Self.klvShape(f))
            throw BLEErrorX.msg("01 响应无令牌 (回包 \(Self.klvShape(f))): 配网期出现说明锁已不在重置/可配网状态, 请在门锁键盘上重置后立即重试")
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
                // 忙判必须在**写之前** (2026-10-14 对抗式排查): 旧实现把判据放进挂 waiter 的 Task,
                // 而 writeFrameHex 在 Task 外无条件执行 => 判为"忙"时帧**照样发出去**, 第二条命令的响应
                // 被第一条的 waiter 收下 = 错帧 (cmd08 批量 13 分片最危险)。这里同步判, 忙即不发。
                if waiter != nil { throw BLEErrorX.msg("已有命令在等待响应") }
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
                    // 2026-10-14: disconnect() 会把 curMac 清空, 旧写法 `if !curMac.isEmpty` 紧随其后 =>
                    // 恒为 false, 自愈重连是死代码 (首个 hiccup 后连接不再恢复)。先存下再断。
                    let macToHeal = curMac
                    disconnect()
                    if !macToHeal.isEmpty { try? await ensureConnected(mac: macToHeal) }
                }
                log("warn", "cmd \(String(format: "%02x", cmd)) 第 \(attempt + 1) 次失败: \(error.localizedDescription)")
            }
        }
        throw lastErr
    }

    // rc 所在 KLV key (JS lock.js RC_KLV, 勘误后权威表)
    /// 0x88 包络里带 MAC 的命令 (rc=12 的顺序自愈只对它们有意义; 网关/明面命令的 MAC 在别处)。
    private static let macBearingCmds: Set<UInt8> = [0x03, 0x04, 0x08, 0x0a, 0x0b, 0x0e, 0x13, 0x14,
                                                    0x15, 0x16, 0x18, 0x19, 0x20, 0x21, 0x22, 0x24,
                                                    0x25, 0x41, 0x43, 0x44]
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
        // rc=12「mac地址不正确」的**顺序自愈** (2026-10-17 真机): 0x88 包络里那 6 字节 MAC 有两种取法,
        // 本机默认按原版 APK 语义 (见 ZKProtocol.MacOrder)。老钥匙串是在没有这一层之前配的, 若它是
        // 另一种取法, 之后每条命令都会回 rc=12 —— 而 rc≠0 的语义正是"锁没执行", 所以换一种取法重发
        // 一帧是安全的 (与 rc=3 刷令牌那一支同一条纪律)。只做一次, 成功即落盘: 下一帧起不必再试。
        // 配网期 (pairMac != nil) 刻意不走这一支: 那里由只读探针 calibrateMacOrder 裁定, 免得把
        // "写命令自愈"混进配网链 (配网期每条命令都是改锁的)。
        if rc == 12, pairMac == nil, LockService.macBearingCmds.contains(cmd), DB.keychain(curMac) != nil {
            let used = ZKProtocol.macOrder(curMac)
            let other = ZKProtocol.flipped(used)
            ZKProtocol.setMacOrder(curMac, other)
            let resp2 = try? await request(cmdObj, cmd: cmd, needToken: needToken, retries: 1)
            let rc2 = resp2.map { extractRc(cmd, $0) } ?? -1
            if let r2 = resp2, rc2 == 0 {
                DB.setMacOrder(curMac, other)
                log("warn", "\(cmdObj.name) rc=12 (mac地址不正确) → 换一种 MAC 字节序 (\(other.rawValue)) 重发即通过; 已记住这把锁的顺序")
                return ExecResult(frame: r2, rc: rc2, klvs: r2.klvs)
            }
            // 不是顺序问题 → 复原注册表 (方向错了会比默认更难查), 让上层按 mac 不符去报错
            ZKProtocol.setMacOrder(curMac, used)
            log("warn", "\(cmdObj.name) rc=12: 两种 MAC 字节序都被拒 (回退 \(used.rawValue)) — 不是字节序问题, 是锁内密钥与本机不一致")
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
    /// 配网尾链中断的提示。参数是"**本机有没有留存这一份密钥**", 而不是"换钥有没有发生":
    /// 留存过就不必去门锁键盘做重置 (再点一次配网会跳过换钥接着配完) —— 这是软砖后路的分水岭。
    static func pairWarning(_ resumable: Bool, _ msg: String) -> String {
        resumable
            ? "\(msg) — 本机已留存这一步的密钥 (skey/PIN/bkey), 再点一次配网会接着配完, 不必做键盘重置"
            : msg
    }
    /// 配网期的 rc → 该怎么办。刻意**不**复用 rcHint: 那一条是"已配对"语境 (rc=3 让你去快捷操作校时),
    /// 而配网期本机还没有钥匙串, 0E 校时根本发不出去 (校时链路要 skey) —— 同一句话在配网语境里是空头支票。
    private static func pairHint(_ rc: Int) -> String {
        switch rc {
        case 3, 9: return "锁内时钟不准, 而配网期无法校时 (校时要密钥); 请在门锁键盘上重置后马上重试"
        case 7, 27: return "锁当前不在可配网状态, 请在门锁键盘上做一次重置再试"
        case 13: return "通讯过期: 锁不认这份通讯会话 (会话令牌无效/已过期), 不是距离或信号问题 — 请在门锁键盘上做一次重置, 3 声提示后尽快点配对 (重置后的可配网窗口有限, 一旦超时锁会退回不可配网)"
        default: return "锁可能不在重置态, 请在门锁键盘上重置后重试"
        }
    }
    /// 回包的 KLV 形状 —— **只报键与长度, 一个值都不带**: 真机排障时 "#02=0B" 这种事实
    /// (锁压根没回密钥) 比任何猜测都有用, 而值里可能含 skey/ekey/PIN 明文 (不得进日志)。
    nonisolated static func klvShape(_ f: ZKProtocol.ParsedFrame) -> String {
        f.klvs.isEmpty ? "(无 KLV)" : f.klvs.map { String(format: "#%02x=%dB", $0.key, $0.vlen) }.joined(separator: " ")
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

    // ---------- 连通探测 (cmd12 回声) ----------
    /// 一次回声往返的结果。`matched` = 锁回显的 KLV#01 与本机发出去的值**逐字节相同**。
    struct EchoProbe { var ok: Bool; var rc: Int; var echoHex: String; var ms: Int; var matched: Bool }

    /// 对一台**已经扫到、但可能还没配对**的蓝牙设备发一条免令牌明文回声 (cmd12)。
    /// APK 侧的同一个动作在 RomlistPage: 扫描列表里对每台 ZK* 设备先 echo, rc=0 才进那把锁的页面
    /// (apk_raw/assets/www/build/main.js RomlistPage.echo)。
    /// 为什么本机需要它、而不是直接读 03 状态:
    ///   · 回声**不改锁内任何东西**, 也不写本机台账 —— 读 03 会落状态快照 + 电量采样 + 固件观测三处;
    ///   · 它不需要 skey (免令牌明文族: vendor/app/utils/kernel/cmds.js:50 的 cmd12Echo 不注入 KLV#0xEE),
    ///     所以**对还没配对的设备**也发得出去 —— 这正是它存在的理由。
    func probeEcho(deviceId: String, valueHex: String = "123456") async throws -> EchoProbe {
        // 临时链路: 不走 connect(deviceId:) —— 那条路会把 deviceId 写进 DB.lastDevice 与 connectedMAC,
        // 等于让本机记住一台没有钥匙的设备 (下次冷启动会去连它)。
        let hadLink = !ble.connectedMAC.isEmpty
        try await ble.connect(deviceId: deviceId)
        defer {
            // 拆掉临时链路, 并把探测期间假装出来的连接态清干净 —— 留着会骗过 ensureConnected
            // (它会以为本机还连着, 于是下一次操作发向一条已经不存在的链路)。
            rejectWaiter("探测用临时链路已断开")
            ble.disconnect()
            connectedDeviceId = ""
            connectedMAC = ""
            sessionTokenHex = "0000"
            tokenExpiryMs = 0
            if hadLink { log("warn", "探测用临时链路已撤下 — 原有链路需按需重连") }
        }
        return try await sendEcho(valueHex)
    }

    private func sendEcho(_ valueHex: String) async throws -> EchoProbe {
        let t0 = Date()
        // retries: 1 —— 这是"这一下通不通"的一次探测, 不是重试到通为止的操作
        let r = try await exec(ZKCmdBuilder.cmd12Echo(valueHex), needToken: false, retries: 1)
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        let echo = (r.klvs.first { $0.key == 0x01 }?.val ?? "").lowercased()
        return EchoProbe(ok: r.rc == 0, rc: r.rc, echoHex: echo, ms: ms,
                         matched: !echo.isEmpty && echo == valueHex.lowercased())
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
    /// 校时 (cmd 0E): 发**手机当前时间** —— 与原版 APK synctime 页完全一致
    /// (那边就是 `new St(En.getNowTimeString(), mac)`, 载荷为手机此刻的协议秒)。
    /// 旧实现算的是 `target = now + (lockSec - now)`, 数学上等于**把锁自己的钟原样写回去**:
    /// 屏上报"同步成功"而锁钟一秒没动 —— 而锁的命令有效期判据 (rc=3 命令过期 / rc=13 通讯过期)
    /// 全看这个钟, 所以这个空操作会把后面每一类命令都拖进时间问题里。
    /// 先读锁钟现在只用来**报告偏差** (读了不写回去), 再回读一次作为"真的写进去了"的证据 ——
    /// rc=0 只证明命令被接收, 不证明锁钟变了。
    @discardableResult
    func syncTime() async throws -> (before: Int, after: Int) {
        let (m, sk) = try keys()
        let now = ZKProtocol.nowProtoSeconds()
        var before = 0
        if let lockSec = try? await readLockTime() {
            before = Int(lockSec - now)
            if before != 0 { log("info", "校时前锁钟比手机\(before > 0 ? "快" : "慢") \(abs(before))s") }
        } else {
            log("warn", "读锁钟失败 (不影响下发: 0E 用手机当前时间)")
        }
        try await execOk(ZKCmdBuilder.cmd0ESyncTime(m, sk, now))
        DB.saveSyncTime(m, Date().timeIntervalSince1970 * 1000)
        var after = 0
        if let lockSec = try? await readLockTime() {
            after = Int(lockSec - ZKProtocol.nowProtoSeconds())
            log("info", "校时回读: 锁钟偏差 \(after)s")
            // >60s 不可能是秒级回读误差 (即使固件把锁钟取整到分钟也只有几十秒) ⇒ 当成"压根没写进去"报错,
            // 而不是拿一句"同步成功"把用户送走。
            if abs(after) > 60 {
                throw BLEErrorX.msg("校时命令已被接受, 但回读锁钟仍偏差 \(after)s — 门锁可能忽略了 0E (rc=0 不等于写成功)")
            }
        } else {
            log("warn", "校时回读失败 — 无法确认锁钟已更新")
        }
        return (before, after)
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
            // 2026-10-15 走查: 这里原先 `return 0`。0 不是"某个编号"，它是协议里 **delAlias: 0 = 本次不删任何密码**
            // 那个保留值 (上面那条 cmd0ASyncPwd 自己就是这么调的) —— 于是一口气错三处：界面报
            // "添加成功 (别名 #0)"、台账把这条密码记成 0 号、往后 `pwdDelete(0)` 发出去的就是"不删任何东西"
            // 那一帧而照样过 execOk ⇒ **屏上说已删除，密码在锁里还活着**。
            // 拿不到编号就是没确认到编号。本文件对"响应缺关键字段"的既有口径是抛错而不是给默认值
            // (见上面 01 无令牌那条)，这里同一条。
            throw BLEErrorX.msg("锁已接受写入，但没有回凭证编号 (0A 响应缺 KLV#04) — 这条密码本机不登记，请到锁内记录核对或重加")
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
        // 2026-10-15 走查: 与 pwdDelete 同一个洞，而后果更脏 —— 这条帧是"删 alias + 加新密码"两步合一，
        // alias = 0 时删的那一步是空操作 (0 = 不指定)，于是锁里**多出一条密码**、台账那边却按"改写"记账，
        // 报的还是"已改写"。0 号只可能来自这条密码当初没拿到锁端编号 (本文件上方 pwdAdd 那条)，
        // 那种情况要做的是删除+重加，不是改写。
        guard alias > 0 else {
            log("warn", "pwdModify 收到保留编号 0，已中止 (这条台账没有锁端编号)")
            throw BLEErrorX.msg("这条密码在本机台账里没有有效的锁端编号 (0 = 协议里的「不指定」)，改写会只在锁里多加一条而删不掉旧的 — 请先删除再重新添加")
        }
        let (m, sk) = try keys()
        let r = try await execOk(try ZKCmdBuilder.cmd0ASyncPwd(m, sk, delAlias: alias, addPwd: pwd, validFrom: validFrom, validTo: validTo))
        let got = aliasFrom(r) ?? alias
        log("info", "凭证#\(alias) 已改写" + (got == alias ? "" : ", 锁端新编号 凭证#\(got) (0A 删旧+加新)"))
        return got
    }
    func pwdDelete(_ alias: Int) async throws {
        // 2026-10-15 走查: 0 是协议里"本次不删任何密码"那一族的保留值 (见上面 cmd0ASyncPwd 的 delAlias 口径)。
        // 把 0 当编号发出去照样会拿到成功码 ⇒ `execOk` 过、日志写"已删除"、锁里那条密码一动不动。
        // 台账里真出现 0 号，只可能是这条密码当初就没从锁端拿到编号 —— 那种情况要如实报失败，
        // 而不是给一个假的"已删除"。
        guard alias > 0 else {
            log("warn", "pwdDelete 收到保留编号 0，已中止 (这条台账没有锁端编号)")
            throw BLEErrorX.msg("这条密码在本机台账里没有有效的锁端编号 (0 = 协议里的「不指定」)，无法按编号删除 — 请用「清空密码」或在门锁上处理")
        }
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
        // 把落盘的字节序先灌进协议层: 上次裁定的结果直接作为探针的第一个候选 (少一个来回),
        // 也让"续配"这条路径在重启后的第一帧就按已知顺序成帧。
        ZKProtocol.setMacOrder(m, DB.macOrder(m))
        if let old = DB.keychain(m), !old.skey.isEmpty {
            throw BLEErrorX.msg("该锁已有钥匙串 (MAC=\(old.mac)), 拒绝覆盖配网; 如需重配请先删除该设备")
        }
        try await connect(deviceId: deviceId)
        curMac = m
        defer { pairMac = nil }

        // 0. 续配: 上一次配网在换钥之后中断 (App 被杀 / 08·21·03 任一步失败 / 断链) 时, 锁内 skey
        //    就是本机留存的那一份 —— 先拿它把尾链走完。走不通 (锁被重新重置过, 密钥域已擦) 再回退整链。
        //    这是本 App 最接近"变砖"的那条后路: 没有它, 用户手上没锁 (或锁在门上) 就只能干等下次到锁跟前。
        if let pend = DB.pendingPair(m), !pend.skey.isEmpty, !pend.pins.isEmpty {
            progress("发现上次中断的配网记录 → 先试续配 (不重新换钥)")
            log("info", "续配尝试: 用留存密钥直接走尾链 (留存于 \(pend.pairedAt))")
            do {
                // 续配也要先裁定字节序: 03 是只读的, 顺带把"这份留存密钥还认不认"也一起验了 ——
                // 探针两种都被 rc=12 拒 ⇒ 留存密钥已过期 (锁被再次重置过), 落到 catch 走完整链。
                try await calibrateMacOrder(m, skey: pend.skey.lowercased(), resumable: true)
                let kc = try await finishPairing(m: m, deviceId: deviceId, skey: pend.skey.lowercased(),
                                                bkey: pend.bkey, pins: pend.pins,
                                                trackid: pend.trackid.isEmpty ? String(KeyGen.genTrackId()) : pend.trackid,
                                                resumable: true, progress: progress)
                DB.clearPendingPair(m)
                connectedMAC = m
                progress("续配完成: \(kc.pidName.isEmpty ? "pid=\(kc.pid)" : kc.pidName) @ \(m)")
                return kc
            } catch {
                log("warn", "续配不通 (\(error.localizedDescription)) → 回退完整配网链 (锁可能已被再次重置)")
                progress("续配不通 (锁可能已再次重置) → 走完整配网")
            }
        }

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

        progress("步骤 3/7: cmd 05 交换密钥 (先建通讯会话)")
        // 2026-10-17 真机现象 + APK 逐字对照勘误: **05 必须带会话令牌**。
        //   APK 原文 (apk_raw/assets/www/build/main.js, 05 构造器 `Et`):
        //     l.call(this, Jn.ZKCCOMM_EXSECURITYKEY, !0, "0000")   ← 第二个实参 = needSSToken = **true**
        //   Java 侧据此执行 (cn.zelkova.ZKurlcsPlugin.lockprotocol.BleLockConnector.doExecute):
        //     if (data.needSessionToken()) { doRefreshSsToken(); token = ssToken.getToken(); }
        //     → LockCommBase.getBytes(token) 把令牌作为 KLV#0xEE **追加在帧尾**
        //   ⇒ 真机真序是: 23(免令牌) → 01(取令牌) → 05(带 KLV#0xEE) → ...
        //   本机 (与 vendor/app/utils/kernel/cmds.js:cmd05Exchange 的"免令牌明文"模型) 一直把 05 裸发,
        //   锁于是回 rc=13「通讯过期」—— 报的是**通讯会话**无效 (没有有效令牌), 而不是命令时间 (那是 rc=3)。
        //   真机复现: 锁重置后点配对 → rc13 → 锁随之退出可配网态, 反复都是 rc13。
        var r5 = try await request(ZKCmdBuilder.cmd05Exchange(skey), cmd: 0x05, needToken: true, retries: 3)
        var rc5 = extractRc(0x05, r5)
        if rc5 == 13 {
            // 13 = 通讯过期 = 会话令牌被判无效/已过期。rc≠0 ⇒ 锁**没有执行**换钥 (锁内 skey 未动),
            // 所以重开一次会话再发一帧是安全的 — 这是 rc13 唯一可安全重试的时机 (rc=0 之后再发就会
            // 二次擦写锁内密钥域)。request(needToken:true) 每轮都会重新走 01, 令牌必然是新的。
            log("warn", "05 rc=13 (通讯过期): 重开会话令牌后重试一次 · 回包 " + Self.klvShape(r5))
            r5 = try await request(ZKCmdBuilder.cmd05Exchange(skey), cmd: 0x05, needToken: true, retries: 1)
            rc5 = extractRc(0x05, r5)
        }
        if rc5 != 0 {
            // 真机报告 (2026-10-17): 用户报"锁重置后一直添加不成功", 而运行日志里只有 TX/RX 两行 ——
            // 05 被锁拒收的原因既没进日志、也没进任何台账, 于是现场只能靠回包长度反推。
            // 这里把判决 (rc + 人话 + 该做什么) 与证据 (回包 KLV 的键与长度, 值一概不写) 一起留下。
            log("error", "05 换钥被锁拒收: rc=\(rc5) (\(StatusParser.rcMessage(rc5))) · \(Self.pairHint(rc5))"
                + " · 回包 " + Self.klvShape(r5))
            throw BLEErrorX.msg("换钥失败 rc=\(rc5) (\(StatusParser.rcMessage(rc5))) — \(Self.pairHint(rc5))")
        }
        // rc=0 = 锁**已经执行**了交换 (vendor lock.js: 执行即擦旧钥域) ⇒ 从这一刻起锁内密钥就是新的。
        // (旧实现在这里还有一个 `keyExchanged = true` 旗子, 写在回显比对**之后** —— 于是回显异常那一支
        //  只报"已中止", 读起来像"锁没被动过"; 那个旗子现已全部换成"本机有没有留存密钥"，
        //  因为对用户真正要紧的不是换钥发没发生, 而是他还能不能不再跑一趟锁跟前。)
        if let echo = r5.klvs.first(where: { $0.key == 0x02 }), echo.val.lowercased() != skey.lowercased() {
            // skey 明文绝不进错误文案: 该串会写入 lastError → DiagLogs → kf.diag_logs (随系统备份) 与 UI 展示
            log("error", "05 换钥回包密钥不一致: 回显 \(echo.val.count) 位 / 本地 \(skey.count) 位 · 回包 " + Self.klvShape(r5))
            // 回显不匹配时**不能**说"再点一次就能续配": 锁端那一份是本机读不懂的, 续配也白搭。
            // 这类必须去键盘重置 —— 文案与可续配那一族明确分开 (pairWarning(false, ...) 不追加续配承诺)。
            throw BLEErrorX.msg(Self.pairWarning(false,
                "换钥回显不匹配 (本地/回显长度 \(skey.count)/\(echo.val.count)) — 锁内密钥已是本机读不懂的一份, 无法续配; 请在门锁键盘上重置后重新配网"))
        }

        progress("步骤 4/7: 留存本次密钥 (配网中断可续配)")
        // 从 05 rc=0 这一刻起, 锁内 skey 已经是新的一份。旧实现要等到尾链全部成功才落盘 ⇒ 尾链任一步
        // 失败就只剩"去门锁键盘重置"一条路 (锁内部密钥对本机不可知 = 软砖)。现在换钥后立即留存,
        // 尾链走完再提升为正式钥匙串 (saveKeychain + clearPendingPair)。
        let pending = Keychain(version: 1, mac: m, skey: skey, bkey: bkey, pins: pins,
                               ekey: ZKCmdBuilder.buildEkeyOpen(skey, m, pins[0]),
                               trackid: String(KeyGen.genTrackId()), bleId: deviceId, fw: "",
                               pairedAt: ISO8601DateFormatter().string(from: Date()))
        let resumable = DB.savePendingPair(pending)
        if resumable {
            log("info", "已留存换钥后的密钥 (尾链若中断, 再点一次配网即续配, 无需键盘重置)")
        } else {
            log("error", "配网中断保护未能落盘 (系统 Keychain 写失败) — 尾链若中断只能靠门锁键盘重置恢复")
        }

        // 步骤 4.5/7: **MAC 字节序只读探针** (2026-10-17 真机 rc=12 的根治)
        //   锁重置后 05 回 rc=0 说明"换钥发生了", 但锁**没有**回显 skey (回包只有 KLV#01=rc),
        //   所以下一步 08 回 rc=12 时现场有两种解释: ① 包络里那 6 字节 MAC 取反了 ② 锁内 skey 与本机
        //   这份对不上。两者都会让锁回同一句「mac地址不正确」, 而 08 是写 PIN 池 —— 在错的前提下继续
        //   写, 现场只会更难判。03 密文面命令同样带 MAC, 却**什么都不改**: 拿它当探针, 一次配对里就把
        //   ①/② 分开, 并且把正确的取法记在 `kf_macorder_<mac>` 上供此后每一帧使用。
        progress("步骤 4.5/7: 裁定包络 MAC 字节序 (只读 03 探针)")
        try await calibrateMacOrder(m, skey: skey, resumable: resumable)

        let kc = try await finishPairing(m: m, deviceId: deviceId, skey: skey, bkey: bkey, pins: pins,
                                        trackid: pending.trackid, resumable: resumable, progress: progress)
        DB.clearPendingPair(m)   // 尾链成功才摘掉中断记录 (先删再落库会造出"无保护"窗口)
        cleanWrongOrderTwin(m)
        connectedMAC = m
        return kc
    }

    /// 0x88 包络 MAC 字节序的裁定 (只读, 不改锁上任何东西)。
    /// 两种取法各试一次 03 (密文面, 带 MAC, 无副作用); 谁 rc=0 谁对, 立即落盘。
    /// 两种都被 rc=12 拒 ⇒ 不是字节序问题, 是**锁内 skey 与本机这份对不上** (换钥没落进锁里):
    /// 这时**必须停手** —— 继续发 08 会在"配不上的前提"下往 PIN 池写, 而现场唯一的证据就是这条 rc。
    /// 返回前一定把注册表恢复成"已裁定/默认"的那个值, 免得留一个临时值害到别的锁。
    private func calibrateMacOrder(_ m: String, skey: String, resumable: Bool) async throws {
        var lastRc = -1
        for order in [ZKProtocol.MacOrder.display, ZKProtocol.flipped(.display)] {
            ZKProtocol.setMacOrder(m, order)
            let r = try await exec(ZKCmdBuilder.cmd03StatusWrap(m, skey, order: order))
            lastRc = r.rc
            if r.rc == 0 {
                DB.setMacOrder(m, order)
                log("info", "MAC 字节序裁定: \(order.rawValue) — 只读 03 探针 rc=0 (此后本机对这把锁一律按它成帧)")
                return
            }
            log("warn", "MAC 字节序候选 \(order.rawValue) 被拒: 03 探针 rc=\(r.rc) (\(StatusParser.rcMessage(r.rc))) · 回包 " + Self.klvShape(r.frame))
            if r.rc != 12 {
                ZKProtocol.setMacOrder(m, .display)
                throw BLEErrorX.msg("MAC 字节序探针失败 rc=\(r.rc) (\(StatusParser.rcMessage(r.rc))) — \(Self.pairHint(r.rc))")
            }
        }
        ZKProtocol.setMacOrder(m, .display)
        throw BLEErrorX.msg(Self.pairWarning(resumable,
            "两种 MAC 字节序都被锁拒 (rc=\(lastRc) mac地址不正确): 锁内密钥与本机这份对不上 (换钥没落进锁里)。本机已留存这套密钥, 再点一次配网会先试续配; 仍不通才需要去门锁键盘重置"))
    }

    /// 清掉一份"MAC 正好反过来"的幽灵台账。2026-10-17 的 rc=12 (mac地址不正确) 就是这么来的:
    /// 旧版把广播里的**线上序** macRaw 当 MAC 落库, 那份记录从未与锁对上过一次话, 却会一直挂在
    /// 设备页里 (同一把锁两条记录, 删了一条另一条还在)。配网成功后顺手清掉 ——
    /// 只在**配对确实成功**时做, 所以不会误删一份正在用的台账。
    private func cleanWrongOrderTwin(_ mac: String) {
        let twin = HexKit.reversePairs(mac).lowercased()
        guard twin != mac, DB.keychain(twin) != nil else { return }
        DB.removeKeychain(twin)
        log("warn", "清掉一份 MAC 顺序相反的幽灵台账 (\(twin)) — 旧版把广播线上序当锁 MAC 留下的")
    }

    /// 配网尾链 (步骤 5~7 + 落库)。**完整配网与续配共用同一条尾链** ——
    /// 分开写迟早只改一条, 而"续配"漏一步的后果正好是软砖。
    private func finishPairing(m: String, deviceId: String, skey: String, bkey: String, pins: [String],
                               trackid: String, resumable: Bool,
                               progress: @escaping (String) -> Void) async throws -> Keychain {
        log("info", "配网尾链 MAC 字节序 = \(ZKProtocol.macOrder(m).rawValue) (只读探针裁定结果)")
        let batchSize = 16   // APK 用 20 (o>20?20:o) —— 同样 4 批; 16 让单帧更小, 保留
        let batches = (pins.count + batchSize - 1) / batchSize
        progress("步骤 5/7: 同步 PIN 池 (\(pins.count) 个 / \(batches) 批)")
        var i = 0
        var n = 0
        while i < pins.count {
            n += 1
            let batch = Array(pins[i..<min(i + batchSize, pins.count)])
            let del = (i == 0) ? [KeyGen.delPinSentinel] : []
            guard let c = ZKCmdBuilder.cmd08SyncPinsBatch(m, skey, batch, delPins: del) else {
                throw BLEErrorX.msg("PIN 批次构建失败")
            }
            let rb = try await exec(c)
            if rb.rc != 0 {
                log("error", "PIN 批次 \(n) 被锁拒收: rc=\(rb.rc) (\(StatusParser.rcMessage(rb.rc))) · 回包 " + Self.klvShape(rb.frame))
                throw BLEErrorX.msg(Self.pairWarning(resumable, "PIN 批次 \(n) 失败 rc=\(rb.rc) (\(StatusParser.rcMessage(rb.rc)))"))
            }
            i += batchSize
        }

        progress("步骤 6/7: 设置 bkey (cmd 21)")
        let r21 = try await exec(ZKCmdBuilder.cmd21SetBkey(m, skey, bkey))
        if r21.rc != 0 {
            log("error", "21 bkey 被锁拒收: rc=\(r21.rc) (\(StatusParser.rcMessage(r21.rc))) · 回包 " + Self.klvShape(r21.frame))
            throw BLEErrorX.msg(Self.pairWarning(resumable, "bkey 失败 rc=\(r21.rc) (\(StatusParser.rcMessage(r21.rc)))"))
        }

        progress("步骤 7/7: 加密状态校验 (cmd 03)")
        let stR = try await exec(ZKCmdBuilder.cmd03StatusWrap(m, skey))
        let st = StatusParser.parseStatus(stR.klvs)
        if stR.rc != 0 {
            log("error", "03 加密回读校验被锁拒收: rc=\(stR.rc) (\(StatusParser.rcMessage(stR.rc))) · 回包 " + Self.klvShape(stR.frame))
            throw BLEErrorX.msg(Self.pairWarning(resumable, "配对校验失败 rc=\(stR.rc) (\(StatusParser.rcMessage(stR.rc)))"))
        }

        let kc = Keychain(version: 1, mac: m, pid: st.pid, pidName: st.pidName,
                          skey: skey, bkey: bkey, pins: pins,
                          ekey: ZKCmdBuilder.buildEkeyOpen(skey, m, pins[0]),
                          trackid: trackid, bleId: deviceId, fw: st.firmware,
                          pairedAt: ISO8601DateFormatter().string(from: Date()))
        DB.saveKeychain(kc)
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
