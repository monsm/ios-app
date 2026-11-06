// LockService · 锁操作（读状态 / 校时 / 静音 / 安全模式 / 布防 / 临时码 / 开锁 / 固件升级）
// 2026-10-29 从 LockService.swift 拆出。
import Foundation

extension LockService {
    // ---------- 状态 ----------
    func getStatus(mac: String? = nil) async throws -> LockStatus {
        if let mac { curMac = mac.lowercased() }
        let kc = DB.keychainForUnlock(curMac)
        var r: ExecResult
        if let kc, !kc.skey.isEmpty {
            let (m, sk) = try keys()
            r = try await exec(ZKCmdBuilder.cmd03StatusWrap(m, sk))
        } else {
            r = try await exec(ZKCmdBuilder.cmd03StatusPlain(), needToken: false)
        }
        let st = StatusParser.parseStatus(r.klvs)
        // 2026-10-31（第 51 轮，**F6 锁态门的设计缺陷**）：原来是 `if st.rc == 0 { DB.writeStatus(...) }` ——
        // 即**只在成功时写快照**。而 F6 的判据是 `snap?.rc != 25 && snap?.rc != 26`：
        // 锁报 rc=25（忙）/ rc=26（被撬）时**根本不写快照**，快照保持旧值（多半是 rc=0）
        // ⇒ F6 判据通过 ⇒ 照样下发 04。**这道门在最该拦的时候永远不拦。**
        //
        // 现在：**无论 rc 是什么都写快照**（rc 本身就是锁态的一部分）。
        // 电量采样仍只在 rc==0 时做：rc≠0 的回包里 powerLevel 不可信（锁可能没真读状态）。
        // 空壳里可以发这条命令（开锁链要用回包），但**不落盘**：
        // 真实电量、rc、锁钟写进快照与电量历史，都是“主人在某时读过锁”的
        // 持久痕迹，退出空壳后仍然在。快照与采样只在正常态写。
        if !DB.isDecoy {
            DB.writeStatus(curMac, st) // 离线快照 (随时可读) —— 含 rc，供 F6 判据
            if st.rc == 0 {
                BatteryCare.sample(curMac, pct: st.powerLevel)   // 包4/45: 电量本地采样埋点 (90 天截断)
            }
        }
        return st
    }

    func readLockTime() async throws -> Int64 {
        let st = try await getStatus()
        // 2026-10-30（界面全维度 · 错误文案）：`KLV#04` 是协议字段号，用户读不懂。
        guard let t = st.lockTime else { throw BLEErrorX.msg("门锁这次没有回报时间 — 请重新读取状态；若反复如此，可能是固件版本较老不支持校时") }
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
        // 空壳模式下开锁能力必须保留（设计：「门照样能开，这是保命的前提」）。
        guard let kc = DB.keychainForUnlock(curMac), !kc.skey.isEmpty else { throw BLEErrorX.msg("无钥匙串，无法开锁") }

        func signed(_ pin: String) -> String {
            ZKCmdBuilder.buildEkeyOpen(kc.skey.lowercased(), kc.mac.lowercased(), pin)
        }

        // 2026-11-01 修复：**「锁档案 · 开锁 PIN」这个设置在开锁时是完全无效的。**
        // 旧实现是「只要 kc.ekey 非空就用它，pinDec 一律忽略」，而配网后 kc.ekey 基本都非空，
        // 于是两件事同时发生：
        //   ① 用户选了第 N 枚 PIN，实际用的仍是配网那枚；
        //   ② 配网那枚 ekey 一旦失效（换 PIN / 换管理员 / 锁被重刷 / 绑定到了别的设备），
        //      **每一次开锁都会失败，而且本机没有任何路径能现签一枚新的** —— 即"手动开锁总是失败"。
        // 现在：显式选了 PIN 就**现签**（"选它"的意义就在于此）；没选才回落到配网 ekey。
        let chosen = (pinDec ?? "").trimmingCharacters(in: .whitespaces)
        var cred = ""
        // 2026-11-01：把**凭证来源**写进交互流水。
        // 排查「总是 rc=2」时，第一件要知道的就是"这帧用的是配网存的那枚 ekey，还是现签的"。
        // 前者失效是本仓已知的软肋（换 PIN / 换管理员 / 锁被重刷后它就永久不可用）。
        var credSource = "无"
        if !chosen.isEmpty {
            cred = signed(chosen)
            credSource = "用户选定的 PIN 现签"
        } else if !kc.ekey.isEmpty {
            cred = kc.ekey                                     // 配网时已签发
            credSource = "配网时存的 ekey"
        } else if let first = kc.pins.first(where: { !$0.isEmpty }) {
            cred = signed(first)
            credSource = "PIN 池第 1 枚现签"
        }
        log("info", "开锁凭证来源 = \(credSource)（本机 PIN 池 \(kc.pins.count) 枚）")
        if kc.ekey.isEmpty, kc.pins.isEmpty, chosen.isEmpty {
            throw BLEErrorX.msg("这把锁还没有可用的开锁凭证 — 请先在「凭证」页添加一条密码，或重新配对这把锁")
        }
        // 2026-10-30（同上）：不暴露 ekey/PIN 术语。
        guard !cred.isEmpty else { throw BLEErrorX.msg("没能生成开锁凭证 — 请重新配对这把锁，或改用「凭证」页里的密码开锁") }

        // 2026-11-02（**真机日志驱动，修我第 203 轮自己引入的 P0**）：
        //
        // 第 203 轮我加了这条守卫，把 cmd03 KLV#06 当「冻结剩余秒数」：
        //     if freeze > 0 { throw "锁端键盘已冻结，约 N 秒后再试" }
        //
        // 真机日志（21:21-21:27 那份 307 行）证明这是**误判**，而且后果是致命的：
        //   · 4 次开锁尝试，**0 次发出 cmd04** —— 全在发命令前被这条守卫拦下；
        //   · cmd03 回包解出来是 KLV#06 = 0x1e(30)、KLV#07 = 0x05(5)，
        //     而这两个值在 20 次读取、跨 5 分钟内**一动不动**；
        //   · 真正的「冻结倒计时」不可能不变。它们更像**阈值/配置**
        //     （"连续错 5 次则冻结 30 秒"），不是"当前还剩 30 秒"。
        //   · 原版 vendor `main.js` 里 KLV#06 的 getter 叫 `getKeyboardFreeze()`，
        //     **全仓零处用它做判断** —— 原版 App 从来不用这个字段拦开锁。
        //
        // 结论：**不能拿 KLV#06/#07 当「现在被冻结」的判据**。锁真的冻结时，
        // cmd04 会回 rc=2 或专门的错误码，那才是可判的事实；而"先读一个语义不明的
        // 字段，非零就不发命令"只会把每一次开锁都变成"点了没反应"。
        //
        // 现在的处置：
        //   · 不再抛错、不再拦开锁 —— 命令照发，让锁自己回答（rc 会如实告诉我们对错）；
        //   · 但仍读一次 cmd03：errCount 非零时**收窄逐枚试错额度**（避免刷整池加深计数），
        //     这是原版没有的保护，保留它是有价值的，且不会阻止第一次开锁；
        //   · 冻结/试错计数**只作为诊断读数**写进交互流水，供排查时看。
        var maxPinRetries = kc.pins.count
        if let st = try? await getStatus() {
            if st.keyboardErrCount > 0 {
                // 锁端已记过试错：收窄额度，别把整池刷完（那只会加深计数）。
                maxPinRetries = min(maxPinRetries, 3)
            }
            // 只记读数，不据此拦截。字段语义未定（见上），所以措辞不带"已冻结"这种断言。
            if st.keyboardFreeze > 0 || st.keyboardErrCount > 0 {
                log("info", "锁端键盘计数读数 freeze=\(st.keyboardFreeze) errCount=\(st.keyboardErrCount)（仅诊断，不拦截开锁）")
            }
        }

        var r = try await exec(ZKCmdBuilder.cmd04Open(cred, klv01Hex: "0000"), retries: 2)
        // 2026-11-01：把 rc **明文**写进交互流水（`DiagLogs` → 设置页「交互流水」可复制）。
        // 为什么：TX/RX 帧里的载荷会被 `FrameRedact` 脱敏，而 **rc 在载荷里** ——
        // 用户复制出来的流水若只有帧头，就看不出"锁到底为什么拒绝"。rc 是协议码，不是凭据。
        log(r.rc == 0 || r.rc == 22 ? "info" : "warn",
            "开锁回执 rc=\(r.rc) · \(StatusParser.rcMessage(r.rc))")
        // 0 = 成功。22 = 「不能重复验证」（vendor status.js 原文）—— **不再当成功**，交上层如实提示。
        if r.rc == 0 { return r.rc }

        // 2026-11-01：**凭证被拒时的自愈回落。**
        // 1/11 解密失败、2 PIN 无效、6 已绑定其他设备 —— 这四个码都指向"这枚 ekey 不可用"，
        // 而不是"锁忙(25)/布防(27)/反锁(21)/时间偏差(3,9,13)"这类环境问题。
        // 旧实现在这里直接返回 rc，用户看到"无效的PIN码"却没有任何自救办法；
        // 现在若手上还有 PIN，就现签一枚再试一次，把"每次都失败"变成"有机会成功"。
        let credentialRejected = [1, 2, 6, 11].contains(r.rc)
        if credentialRejected {
            // 2026-11-01（**真机日志驱动**）：原来只试 `kc.pins.first` ——
            // 而那枚往往正是当初签"存储 ekey"用的同一枚 PIN，
            // AES-ECB 没有随机数 ⇒ 现签出来的密文与刚才那帧**逐字节相同**
            // （真机日志里两次 TX hex 一模一样），于是"自愈重试"完全是空转。
            // 现在把本机 PIN 池**逐个**试：密文与已发过的相同就跳过，
            // 一旦出现非凭证类错误（锁忙/布防/时间偏差）立刻停下 —— 那种情况再换 PIN 也没用。
            var tried: Set<String> = [cred]
            for (idx, pin) in kc.pins.enumerated() where !pin.isEmpty && idx < maxPinRetries {   // 冻结保护：不把整池刷完
                let fresh = signed(pin)
                if fresh.isEmpty || tried.contains(fresh) { continue }
                tried.insert(fresh)
                log("info", "开锁回执是凭证类失败 → 改用本机 PIN 池第 \(idx + 1) 枚现签重试")
                r = try await exec(ZKCmdBuilder.cmd04Open(fresh, klv01Hex: "0000"), retries: 1)
                log(r.rc == 0 || r.rc == 22 ? "info" : "warn",
                    "开锁回执(PIN #\(idx + 1)) rc=\(r.rc) · \(StatusParser.rcMessage(r.rc))")
                if r.rc == 0 || r.rc == 22 { break }
                if ![1, 2, 6, 11].contains(r.rc) { break }
            }
        }
        // 2026-11-02（真机根因修复的另一半）：整池试完仍被拒 ⇒ 存的那枚 ekey 已**永久中毒**
        // （它嵌的 PIN 已被 deletePins 摘掉，重试同一枚毫无意义）。重签一枚指向 pool[1] 的
        // ekey 写回钥匙串 —— 本次开锁仍然失败，但**下一次**就有活凭证。这是"不重置锁"的唯一自救路径。
        if credentialRejected, !kc.ekey.isEmpty {
            if MobileKeyService.repairPairingEkey(kc: kc) {
                log("warn", "存储的开锁凭证已失效（锁端已无这枚 PIN）— 已自动重签，请再按一次开锁")
            }
        }
        return r.rc
    }

    /// 返回值里的 `after` 是**回读确认**：nil = 校时指令已下发，但回读失败，
    /// 无法确认锁钟真的更新了。原先用 0 表示「没偏差」，与回读失败不可区分，
    /// 界面于是把「没读回来」也报成「锁钟已对齐」。
    func syncTime() async throws -> (before: Int, after: Int?) {
        let (m, sk) = try keys()
        let now = ZKProtocol.nowProtoSeconds()
        var before = 0
        if let lockSec = try? await readLockTime() {
            before = Int(lockSec - now)
            if before != 0 { log("info", "校时前锁钟比手机\(before > 0 ? "快" : "慢") \(abs(before))s") }
        } else {
            log("warn", "读锁钟失败 （不影响下发：0E 用手机当前时间）")
        }
        _ = try await execOk(ZKCmdBuilder.cmd0ESyncTime(m, sk, now))
        DB.saveSyncTime(m, Date().timeIntervalSince1970 * 1000)
        var after: Int?
        if let lockSec = try? await readLockTime() {
            let delta = Int(lockSec - ZKProtocol.nowProtoSeconds())
            after = delta
            log("info", "校时回读：锁钟偏差 \(delta)s")
            // >60s 不可能是秒级回读误差 (即使固件把锁钟取整到分钟也只有几十秒) ⇒ 当成"压根没写进去"报错,
            // 而不是拿一句"同步成功"把用户送走。
            if abs(delta) > 60 {
                // 2026-10-30（界面全维度 · 错误文案）：这句会经 `SyncTimeView` 的
                // `result = "同步失败：\(error.localizedDescription)"` **原样显示给用户**，
                // 而 `0E` 是命令号、`rc=0` 是协议码 —— 用户读不懂。
                // 保留事实（偏差多少秒），换成"能做什么"的说法。
                throw BLEErrorX.msg("门锁收到了时间，但读回来还是差 \(delta) 秒 — 可能是固件忽略了校时指令；请重试一次，若仍如此请更新固件")
            }
        } else {
            log("warn", "校时回读失败 — 无法确认锁钟已更新")
        }
        return (before, after)
    }

    func setSilent(_ on: Bool) async throws {
        let (m, sk) = try keys()
        _ = try await execOk(ZKCmdBuilder.cmd18Volume(m, sk, on))
    }

    /// cmd 20 验证模式 (A/B)。入口在设置-安全模式说明 (拍板 #2, 第六十六批)：**只允许 A→B 变严**,
    /// 且调用方必须回读 verifyMode 才能报成功 (rc=0 只证明命令被接收, 不证明策略变了)。不给 B→A。
    func setValidationMode(_ bMode: Bool) async throws {
        let (m, sk) = try keys()
        _ = try await execOk(ZKCmdBuilder.cmd20ValidationMode(m, sk, bMode))
    }

    func setAutoLock(_ interval: Int) async throws {
        let (m, sk) = try keys()
        _ = try await execOk(ZKCmdBuilder.cmd24AutoLock(m, sk, interval))
    }

    func setZotp(_ on: Bool) async throws {
        let (m, sk) = try keys()
        _ = try await execOk(ZKCmdBuilder.cmd19OpenZotp(m, sk, on))
    }

    // ---------- 布防 (cmd25 SETDEFENCE) —— 补齐 iOS 侧缺失的入口 ----------
    /// 布防/撤防。control: 0 撤防 / 1 不定期 / 2 时段；startSec/endSec 是**协议半秒**的日内值，
    /// 由 DefendKit.protoSec 换算；撤防与不定期一律传 0（与 APK 的 time 字段全 0 一致）。
    ///
    /// 这条命令显式带会话令牌：它改动锁的安全策略，与 04/05 同族；漏令牌会拿到 rc=13「通讯过期」，
    /// 且重试也不会自愈，所以把 needToken 写出来而不是靠默认值。
    func setDefence(control: Int, startSec: Int, endSec: Int) async throws {
        let (m, sk) = try keys()
        _ = try await execOk(ZKCmdBuilder.cmd25Defence(m, sk, control, startSec, endSec), needToken: true)
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
        _ = try await execOk(ZKCmdBuilder.cmd22EnableDfu(m, sk, param), needToken: true, retries: 1)
        log("info", "已下发 22 进 DFU: param=\(param)（随后断链属预期）")
    }

}
