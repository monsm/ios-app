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
    private var sessionToken: UInt32 = 0        // 2B
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
        let t = String(format: "%02d:%02d:%02d", Calendar.current.component(.hour, from: Date()),
                       Calendar.current.component(.minute, from: Date()),
                       Calendar.current.component(.second, from: Date()))
        logs.append("\(t) [\(level)] \(msg)")
        if logs.count > 200 { logs.removeFirst(logs.count - 200) }
        if level == "warn" || level == "error" { lastError = msg }
        // 包11: 分级日志台账 (153/283/542/543 的解析源), 按 751 保留策略留档
        DiagLogs.append(level, msg, date: String(Date().formatted(.iso8601).prefix(10)), time: t)
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
        ble.disconnect()
        connectedDeviceId = ""
        connectedMAC = ""
        curMac = ""
        sessionToken = 0
        tokenExpiryMs = 0
    }
    // 幂等按需连接: 已连同一把 → 直接; 缓存 bleId → 直连; 失败 → MAC 扫描解析 (回写缓存)
    func ensureConnected(mac: String) async throws {
        let m = mac.lowercased()
        guard !m.isEmpty else { throw BLEErrorX.msg("未选择门锁 (缺少 MAC)") }
        if connectedMAC == m, ble.connectedMAC == connectedDeviceId, !connectedDeviceId.isEmpty { return }
        if !connectedDeviceId.isEmpty { disconnect() }
        guard let kc = DB.keychain(m) else { throw BLEErrorX.msg("找不到 MAC=\(m) 的钥匙串 (请先配对或导入)") }
        if !kc.bleId.isEmpty {
            do {
                try await connect(deviceId: kc.bleId)
                return
            } catch {
                log("warn", "缓存 deviceId 直连失败 (\(error.localizedDescription)), 回退 MAC 扫描解析")
            }
        }
        log("info", "扫描解析 MAC=\(m) (请靠近门锁)")
        let deviceId = try await scanForMAC(m, timeoutMs: 8000)
        var kc2 = kc
        kc2.bleId = deviceId
        DB.saveKeychain(kc2)
        try await connect(deviceId: deviceId)
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
        sessionToken = UInt32(HexKit.readU16LE(k.val, byteOffset: 0))
        let secs = f.klvs.first(where: { $0.key == 0x03 }).map { UInt16(truncatingIfNeeded: HexKit.readU16LE($0.val, byteOffset: 0)) } ?? 0
        // JS session.js: ttl=0 保留默认 45s — now+0+2s 会立即过期
        if secs > 0 {
            tokenExpiryMs = Int64(Date().timeIntervalSince1970 * 1000) + Int64(secs) * 1000 + 2000
        }
        log("info", "会话令牌就绪 token=\(String(format: "%04x", sessionToken)) ttl=\(secs)s")
    }

    // ---------- 请求 (令牌注入 + 重试 + 写失败清 waiter) ----------
    @discardableResult
    private func request(_ cmdObj: ZKCmd, cmd: UInt8, needToken: Bool, retries: Int, timeoutMs: Int = 8000) async throws -> ZKProtocol.ParsedFrame {
        var hex = cmdObj.hex
        if needToken {
            try await ensureToken()
            hex = ZKProtocol.injectToken(hex, String(format: "%04x", sessionToken))
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
            sessionToken = 0
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
        // rc=-1 (无 rc KLV) 视为成功 (固件失败必带 rc)
        if r.rc != 0 && r.rc != -1 { throw BLEErrorX.msg(StatusParser.rcMessage(r.rc)) }
        return r
    }

    // ---------- 密钥面 ----------
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
        return alias
    }
    @discardableResult
    func pwdModify(alias: Int, pwd: String, validFrom: String, validTo: String) async throws -> Int {
        let (m, sk) = try keys()
        let r = try await execOk(try ZKCmdBuilder.cmd0ASyncPwd(m, sk, delAlias: alias, addPwd: pwd, validFrom: validFrom, validTo: validTo))
        return aliasFrom(r) ?? alias
    }
    func pwdDelete(_ alias: Int) async throws {
        let (m, sk) = try keys()
        try await execOk(try ZKCmdBuilder.cmd0ASyncPwd(m, sk, delAlias: alias))
    }
    func pwdClear() async throws {
        let (m, sk) = try keys()
        try await execOk(try ZKCmdBuilder.cmd0ASyncPwd(m, sk, delAlias: 0xFFFF))
    }
    func pwdExpire(_ alias: Int, _ from: String, _ to: String) async throws {
        let (m, sk) = try keys()
        try await execOk(ZKCmdBuilder.cmd0BSyncPwdExpire(m, sk, alias, from, to))
    }

    // ---------- 指纹 ----------
    struct FpPress { var orderIdx: UInt32?; var featureNumber: UInt32?; var batchNumber: UInt32?; var rc: Int }
    // cmd 13: 一次请求多响应 — 锁逐次按压逐次回帧 (orderIdx 1..N, orderIdx==0 收尾), JS _execMulti 语义
    func fpStart(times: Int = 8, timeoutMs: Int = 30000) async throws -> [FpPress] {
        let (m, sk) = try keys()
        try await ensureToken()
        let hex = ZKProtocol.injectToken(ZKCmdBuilder.cmd13AddFp(m, sk, times, 15).hex,
                                         String(format: "%04x", sessionToken))
        var frames = [ZKProtocol.ParsedFrame]()
        collectorCmd = 0x13
        collector = { f in if f.cmd == self.collectorCmd { frames.append(f) } }
        defer { collector = nil; collectorCmd = 0 }
        log("info", "TX 13 录指纹 (多响应, \(times) 次按压)")
        var attemptsLeft = 2 // JS _execMulti retries=2: 无帧时重发一次
        while frames.isEmpty && attemptsLeft > 0 {
            attemptsLeft -= 1
            try await ble.writeFrameHex(hex)
            let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
            while Date() < deadline {
                // 收尾: 任一帧 orderIdx == 0
                if frames.contains(where: { f in
                    f.klvs.first(where: { $0.key == 0x04 }).map { StatusParser.leHexToU32($0.val) } == 0
                }) { break }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        guard !frames.isEmpty else { throw BLEErrorX.msg("13 未收到任何按压响应") }
        return frames.map { f in
            FpPress(orderIdx: f.klvs.first(where: { $0.key == 0x04 }).map { StatusParser.leHexToU32($0.val) },
                    featureNumber: f.klvs.first(where: { $0.key == 0x05 }).map { StatusParser.leHexToU32($0.val) },
                    batchNumber: f.klvs.first(where: { $0.key == 0x06 }).map { StatusParser.leHexToU32($0.val) },
                    rc: extractRc(0x13, f))
        }
    }
    func fpConfirm(_ batchNumber: UInt32, validFrom: String, validTo: String) async throws {
        let (m, sk) = try keys()
        try await execOk(ZKCmdBuilder.cmd14FpConfirm(m, sk, batchNumber, validFrom, validTo))
    }
    func fpDelete(_ batchNumber: UInt32) async throws {
        let (m, sk) = try keys()
        try await execOk(ZKCmdBuilder.cmd15DeleteFp(m, sk, batchNumber))
    }

    // ---------- 日志 ----------
    struct LogPage { var surplus: Int?; var logs: [LogEntry] }
    func getLogs(orderType: Int = 0, startIdx: UInt32, pageSize: Int = 5) async throws -> LogPage {
        let (m, sk) = try keys()
        let r = try await exec(ZKCmdBuilder.cmd16GetLog(m, sk, orderType: orderType, startIdx: startIdx, pageSize: pageSize))
        if r.rc != 0 && r.rc != -1 { throw BLEErrorX.msg(StatusParser.rcMessage(r.rc)) }
        let surplus = r.klvs.first(where: { $0.key == 0x04 }).map { Int(StatusParser.leHexToU32($0.val)) }
        return LogPage(surplus: surplus, logs: StatusParser.parseLogs(r.klvs))
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
        let skey = KeyGen.genSkey()
        let bkey = KeyGen.genBkey()
        let pins = try KeyGen.genPins(64)

        progress("步骤 3/7: cmd 05 交换密钥")
        let r5 = try await request(ZKCmdBuilder.cmd05Exchange(skey), cmd: 0x05, needToken: false, retries: 3)
        let rc5 = extractRc(0x05, r5)
        if rc5 != 0 { throw BLEErrorX.msg("换钥失败 rc=\(rc5) (\(StatusParser.rcMessage(rc5))) — 锁可能未处于重置态") }
        if let echo = r5.klvs.first(where: { $0.key == 0x02 }), echo.val.lowercased() != skey.lowercased() {
            throw BLEErrorX.msg("换钥回显不匹配 (本地=\(skey) 回显=\(echo.val)), 已中止")
        }

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
            if rb.rc != 0 { throw BLEErrorX.msg("PIN 批次 \(i + 1) 失败 rc=\(rb.rc) (\(StatusParser.rcMessage(rb.rc)))") }
        }

        progress("步骤 6/7: 设置 bkey (cmd 21)")
        let r21 = try await exec(ZKCmdBuilder.cmd21SetBkey(m, skey, bkey))
        if r21.rc != 0 { throw BLEErrorX.msg("bkey 失败 rc=\(r21.rc)") }

        progress("步骤 7/7: 加密状态校验 (cmd 03)")
        let stR = try await exec(ZKCmdBuilder.cmd03StatusWrap(m, skey))
        let st = StatusParser.parseStatus(stR.klvs)
        if stR.rc != 0 { throw BLEErrorX.msg("配对校验失败 rc=\(stR.rc)") }

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
