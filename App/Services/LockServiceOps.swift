// LockService · 锁操作（读状态 / 校时 / 静音 / 安全模式 / 布防 / 临时码 / 开锁 / 固件升级）
// 2026-10-29 从 LockService.swift 拆出。
import Foundation

extension LockService {
    // ---------- 状态 ----------
    func getStatus(mac: String? = nil) async throws -> LockStatus {
        if let mac { curMac = mac.lowercased() }
        let kc = DB.keychain(curMac)
        var r: ExecResult
        if let kc, !kc.skey.isEmpty {
            let (m, sk) = try keys()
            r = try await exec(ZKCmdBuilder.cmd03StatusWrap(m, sk))
        } else {
            r = try await exec(ZKCmdBuilder.cmd03StatusPlain(), needToken: false)
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
        let hadLink = !ble.connectedPeripheralId.isEmpty
        try await ble.connect(deviceId: deviceId)
        defer {
            // 拆掉临时链路, 并把探测期间假装出来的连接态清干净 —— 留着会骗过 ensureConnected
            // (它会以为本机还连着, 于是下一次操作发向一条已经不存在的链路)。
            rejectWaiter("探测用临时链路已断开")
            ble.disconnect()
            connectedDeviceId = ""
            connectedMAC = ""
            sessionTokenHex = "0000"
            tokenExpiryMs = 0; tokenFetchedAtMs = 0
            if hadLink { log("warn", "探测用临时链路已撤下 — 原有链路需按需重连") }
        }
        return try await sendEcho(valueHex)
    }

    func sendEcho(_ valueHex: String) async throws -> EchoProbe {
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
        guard let kc = DB.keychain(curMac), !kc.skey.isEmpty else { throw BLEErrorX.msg("无钥匙串， 无法开锁") }
        let cred: String
        if !kc.ekey.isEmpty {
            cred = kc.ekey                                     // 配网时已签发
        } else {
            let pin = pinDec ?? kc.pins.first
            guard let pin, !pin.isEmpty else { throw BLEErrorX.msg("无 PIN 可用： 需要 ekey 或 PIN 才能签发开锁凭证") }
            cred = ZKCmdBuilder.buildEkeyOpen(kc.skey.lowercased(), kc.mac.lowercased(), pin)
        }
        guard !cred.isEmpty else { throw BLEErrorX.msg("开锁凭证为空 (ekey/PIN 签发失败), 已中止下发") }
        let r = try await exec(ZKCmdBuilder.cmd04Open(cred, klv01Hex: "0000"), retries: 2)
        return r.rc  // 0 成功; 22 双验继续
    }

    func syncTime() async throws -> (before: Int, after: Int) {
        let (m, sk) = try keys()
        let now = ZKProtocol.nowProtoSeconds()
        var before = 0
        if let lockSec = try? await readLockTime() {
            before = Int(lockSec - now)
            if before != 0 { log("info", "校时前锁钟比手机\(before > 0 ? "快" : "慢") \(abs(before))s") }
        } else {
            log("warn", "读锁钟失败 (不影响下发： 0E 用手机当前时间)")
        }
        try await execOk(ZKCmdBuilder.cmd0ESyncTime(m, sk, now))
        DB.saveSyncTime(m, Date().timeIntervalSince1970 * 1000)
        var after = 0
        if let lockSec = try? await readLockTime() {
            after = Int(lockSec - ZKProtocol.nowProtoSeconds())
            log("info", "校时回读： 锁钟偏差 \(after)s")
            // >60s 不可能是秒级回读误差 (即使固件把锁钟取整到分钟也只有几十秒) ⇒ 当成"压根没写进去"报错,
            // 而不是拿一句"同步成功"把用户送走。
            if abs(after) > 60 {
                throw BLEErrorX.msg("校时命令已被接受， 但回读锁钟仍偏差 \(after)s — 门锁可能忽略了 0E (rc=0 不等于写成功)")
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

    // ---------- 布防 (cmd25 SETDEFENCE) —— 补齐 iOS 侧缺失的入口 ----------
    /// 布防/撤防。control: 0 撤防 / 1 不定期 / 2 时段；startSec/endSec 是**协议半秒**的日内值，
    /// 由 DefendKit.protoSec 换算；撤防与不定期一律传 0（与 APK 的 time 字段全 0 一致）。
    ///
    /// 这条命令显式带会话令牌：它改动锁的安全策略，与 04/05 同族；漏令牌会拿到 rc=13「通讯过期」，
    /// 且重试也不会自愈，所以把 needToken 写出来而不是靠默认值。
    func setDefence(control: Int, startSec: Int, endSec: Int) async throws {
        let (m, sk) = try keys()
        try await execOk(ZKCmdBuilder.cmd25Defence(m, sk, control, startSec, endSec), needToken: true)
        log("info", "布防已下发 (25): control=\(control) start=\(startSec) end=\(endSec)")
    }

    // ---------- 进 DFU (cmd22) —— 补齐 OTA 链路的第一步 ----------
    /// 让锁重启进 bootloader。**这是预期断链**：锁收到 22 后会以 `ZkDFU` + MAC 后 8 位重新广播，
    /// 所以本方法成功后不要等回包以外的任何东西，也不要把随后的 disconnect 当失败。
    ///
    /// 与 APK 的 sendDFUCmd 同口径：param 传 0 表示"重启进 bootloader"。
    func enableDfu(param: Int = 0) async throws {
        let (m, sk) = try keys()
        // 超时给短一点：锁可能在回 rc 后立刻开始重启，等太久只会拿到断链错误。
        try await execOk(ZKCmdBuilder.cmd22EnableDfu(m, sk, param), needToken: true, retries: 1)
        log("info", "已下发 22 进 DFU: param=\(param)（随后断链属预期）")
    }

}
