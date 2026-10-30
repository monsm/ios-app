// LockService · 连接与收发（连接 / 令牌 / 请求 / 执行 / 帧等待）
// 2026-10-29 从 LockService.swift 拆出。
import Foundation

extension LockService {
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
        tokenExpiryMs = 0; tokenFetchedAtMs = 0
    }

    // 幂等按需连接: 已连同一把 → 直接; 缓存 bleId → 直连; 失败 → MAC 扫描解析 (回写缓存)
    /// 2026-10-27 审核说明 (AUDIT-A F-26)：连接后读状态对 pid 这道闸门是 **iOS 新增的**，vendor 没有。
    /// 加它的理由：广播里的 MAC 谁都能伪造，而状态帧的响应难伪造得多（见下方注释）。
    /// 代价：老配对（未登记 pid）只能记警告不拦 —— 宁可放过老用户，也不能把正常人挡在门外。
    /// 这是**有意的偏离**，不是"iOS 比 vendor 多做了点什么"的偶然。
    func ensureConnected(mac: String) async throws {
        let m = mac.lowercased()
        guard !m.isEmpty else { throw BLEErrorX.msg("未选择门锁 (缺少 MAC)") }
        if connectedMAC == m, ble.connectedPeripheralId == connectedDeviceId, !connectedDeviceId.isEmpty {
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
                log("warn", "连接后身份不符： 锁端 pid=\(st.pid) 与登记的 pid=\(knownPid) 不一致 → 已断开， 不写缓存")
                throw BLEErrorX.msg("连到的设备与「\(kc.name)」不是同一把锁 (pid 不符)，已断开。附近可能有同名或伪造广播。")
            }
            if knownPid <= 0 { log("warn", "钥匙串未登记 pid, 跳过连接后身份复核 (老配对)") }
        } catch let e as BLEErrorX {
            throw e
        } catch {
            log("warn", "连接后读状态失败 (\(error.localizedDescription)) → 断开， 不写缓存")
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

    func handle(_ frame: ZKProtocol.ParsedFrame) {
        guard frame.ok else { return }
        if let cb = collector, frame.cmd == collectorCmd { cb(frame); return }
        guard let w = waiter, frame.cmd == w.cmd else { return }
        w.timer?.cancel()
        waiter = nil
        w.cont.resume(returning: frame)
    }

    // 断链/清理时即刻拒绝挂起等待 (JS G1 语义 — 调用方不空等 8s)
    func rejectWaiter(_ msg: String) {
        if let w = waiter {
            w.timer?.cancel()
            waiter = nil
            w.cont.resume(throwing: BLEErrorX.msg(msg))
        }
    }

    // ---------- 令牌 ----------
    func ensureToken() async throws {
        // 2026-10-18 性能: **令牌复用**。原来每次 needToken 都无条件重发 cmd01,
        // 而 cmd01 是一次完整往返（写 20B + 等回包）。开锁链上它是纯开销:
        //   unlock -> exec -> request(needToken) -> ensureToken(cmd01) -> 再发 cmd04
        // 也就是**两次往返**。令牌本身有 ttl（KLV#03，通常 45s），在有效期内直接复用即可。
        //
        // 判据: tokenExpiryMs 已扣了 2s 余量（见下方赋值处的注释），且令牌不是初始占位 "0000"。
        // 失效仍由既有兜底: rc=3（命令过期）时 exec 会刷令牌重试一次 —— 不会因为复用而卡死。
        // tokenExpiryMs == 0 表示"从没拿到过有效 ttl"（secs=0 时不记账，见下方原注释），
        // 那种情况**永不复用** —— 宁可多发一次 01，也不拿一枚来路不明的令牌去发写命令。
        // 2026-10-27 审核修复 (AUDIT-A F-23)：取消令牌复用，改成**每次刷新**。
        // 原实现缓存令牌 45s 复用，而 vendor `lock.js:247-250` 明确废除过这个口径（V81：无条件刷新）。
        // 加上 iOS 原先不重试 rc=13，就成了三端唯一「复用 + 不重试」的组合 —— 没有兜底。
        // 代价是多一次 cmd01 往返（约 100ms），换来的是不会拿过期令牌去发写命令。
        // 2026-10-30（提速，**省一次蓝牙往返 ≈100ms**）：有界复用。
        // 2026-10-27 曾把 45s 复用整个删掉，理由是「复用 + 不重试 rc=13」没有兜底。
        // 现在 `exec` 已有 rc=3 / rc=13 的「刷令牌重试一次」（见 exec 开头），兜底在了。
        // 恢复**短窗**复用：只认 20 秒内取到的令牌，且锁端 TTL 未到（留 2s 余量）。
        // 20s 远小于锁端常见 45s TTL —— 不存在"拿快过期的令牌去发写命令"。
        // 复用命中 = 开锁链从「cmd01 + cmd04 两次往返」变成「cmd04 一次往返」。
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let tokenFresh = tokenExpiryMs > nowMs + 2000
        let tokenYoung = tokenFetchedAtMs > 0 && nowMs - tokenFetchedAtMs < 20_000
        let tokenReal = sessionTokenHex != "0000" && !sessionTokenHex.isEmpty
        if tokenFresh, tokenYoung, tokenReal {
            log("info", "复用会话令牌 (年龄 \(nowMs - tokenFetchedAtMs)ms) — 省一次 cmd01 往返")
            return
        }
        log("info", "刷新会话令牌 (cmd 01)")
        let f = try await request(ZKCmdBuilder.cmd01Session(), cmd: 0x01, needToken: false, retries: 3)
        guard let k = f.klvs.first(where: { $0.key == 0x02 }) else {
            // 配网期这条基本只有一个含义: 锁已退回不可配网态 (01 拿不到令牌 ⇒ 之后每一步令牌面命令都发不出去)。
            // 与 05 被拒时同一取证口径: 留"回包形状"(只键与长度, 无值) + 该做什么, 免得现场只看到一句"无令牌"。
            log("error", "01 会话令牌响应缺 KLV#02 · 回包 " + Self.klvShape(f))
            throw BLEErrorX.msg("01 响应无令牌 (回包 \(Self.klvShape(f))): 配网期出现说明锁已不在重置/可配网状态， 请在门锁键盘上重置后立即重试")
        }
        // 2026-10-28 修：上面只判了 KLV#02 **存在**，没判**非空** —— 锁若返回 `vlen=0` 的空令牌，
        // `sessionTokenHex = ""` 之后 `injectToken` 会 `guard !tokenHex.isEmpty else { return hex }`
        // **原样返回不注入**，于是所有 needToken 命令都缺 KLV#EE，持续 rc=13（通讯过期），
        // 而调用方只看到「通讯过期」，完全不知道真实原因是拿到了空令牌。
        // Java `LockCommBase.getBytes` 在这里是抛 `LockException`（"未给命令提供ssToken"），口径更严。
        guard !k.val.isEmpty else {
            log("error", "01 会话令牌 KLV#02 为空 · 回包 " + Self.klvShape(f))
            throw BLEErrorX.msg("01 响应里的令牌是空值 (回包 \(Self.klvShape(f)))：锁没有给出有效会话令牌，请重置门锁后立即重试")
        }
        // 安全类型 gate 已删: JS lock.js _ensureToken 从不检查 (V81 注释 — Java 发送路径也从不检查),
        // 只要 KLV#02 令牌在就继续。Swift 之前的整串 intHex&3 硬抛会让
        // 安全类型编为 2 字节 (如 "0200"→512&3=0) 或缺 KLV#01 的固件配网必败, 而小程序正常。
        // 旧实现 readU16LE 把令牌截成 2 字节: 锁若上报 4B 令牌, 注入值就是错的 → 所有需令牌写命令必失败
        sessionTokenHex = k.val.lowercased()
        tokenFetchedAtMs = Int64(Date().timeIntervalSince1970 * 1000)   // 提速: 记下取到时刻供有界复用
        let secs = f.klvs.first(where: { $0.key == 0x03 }).map { UInt16(truncatingIfNeeded: HexKit.readU16LE($0.val, byteOffset: 0)) } ?? 0
        // JS session.js: ttl=0 保留默认 45s — now+0+2s 会立即过期
        // ⚠️ 2026-10-18: 这一行**必须**保持原样（`Int64(secs) * 1000 + 2000`）。
        // 我曾为配合"令牌复用"改成 `let ttl = secs > 0 ? secs : 45` 再乘，
        // 被 tools/logicparity.js 的 L09 判据当场拦下：那是与 APK 的**逻辑面差分**
        // （Java isExpire: now+2s > expire），不是排版问题。
        // 真要兜 ttl=0，正确做法是在**复用判据**里处理（见 ensureToken 开头），而不是改记账口径。
        if secs > 0 {
            tokenExpiryMs = Int64(Date().timeIntervalSince1970 * 1000) + Int64(secs) * 1000 + 2000
        }
        // 2026-10-27 审核 (AUDIT-D D-13)：**不再打印令牌前 4 位**。
        // 原先打 `token.prefix(4)` —— 4 个 hex 字符只占 16 bit，看着"很短"，
        // 但配合内存 `recentFrames` 里的完整帧，等于给攻击者一个校验位：
        // 他可以拿已知帧去猜令牌、用这 4 位验证猜想对不对。
        // 排查时真正需要的是"有没有拿到令牌、多长"，不是前几位是什么。
        log("info", "会话令牌就绪 (长度 \(sessionTokenHex.count) hex 字符)")
    }

    func request(_ cmdObj: ZKCmd, cmd: UInt8, needToken: Bool, retries: Int, timeoutMs: Int = 8000) async throws -> ZKProtocol.ParsedFrame {
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
                        log("warn", "\(cmdObj.name) 写命令失败(响应超时或写失败， 指令可能已生效) → 不重发 (避免重复执行), 交上层判定")
                        break
                    }
                }
                // 只清自己 cmd 的 waiter (JS lock.js 按 ww.cmd === cmd 清理), 不误杀并发中的其他请求
                if let w = waiter, w.cmd == cmd { w.timer?.cancel(); waiter = nil }
                // 断链自愈: 写失败 OR 连接已断 (断链后 writeChar/device 被清 → writeFrameHex 抛 parseFail)
                var brokenLink = ble.connectedPeripheralId.isEmpty || connectedDeviceId.isEmpty
                if case BLEErrorX.code(.writeFailed) = error { brokenLink = true }
                if brokenLink {
                    // 2026-10-14: disconnect() 会把 curMac 清空, 旧写法 `if !curMac.isEmpty` 紧随其后 =>
                    // 恒为 false, 自愈重连是死代码 (首个 hiccup 后连接不再恢复)。先存下再断。
                    let macToHeal = curMac
                    disconnect()
                    if !macToHeal.isEmpty { try? await ensureConnected(mac: macToHeal) }
                }
                log("warn", "cmd \(String(format: "%02x", cmd)) 第 \(attempt + 1) 次失败： \(error.localizedDescription)")
            }
        }
        throw lastErr
    }

    /// 从回包里取 rc。
    ///
    /// 2026-10-27 审核说明 (AUDIT-C A7)：本仓与 Android 在**两个边界**上口径不同 ——
    ///   · rc 的 KLV 位置：本仓按命令查表（`rcKLV`，0x05 的 rc 在 KLV#01，其余在 #03）；
    ///     Android 无条件读 KLV#03（因为它只发 03/04/08，不涉及 0x05）。
    ///   · 未登记的命令：本仓返回 **0（乐观）**；Android 返回 **-1（悲观）**。
    /// 乐观的理由：本仓会发 20+ 条命令，将来新增命令若忘了登记，返回 0 会让调用方
    /// 当成"成功"继续走 —— 那可能是错的。所以**新增命令时必须同步登记到 `rcKLV`**，
    /// 否则它的 rc 判定会静默失效。这条注释是给那一步的提醒。
    func extractRc(_ cmd: UInt8, _ resp: ZKProtocol.ParsedFrame) -> Int {
        guard let key = LockService.rcKLV[cmd] else { return 0 }
        guard let k = resp.klvs.first(where: { $0.key == key }) else { return -1 }
        return StatusParser.intHex(k.val)
    }

    func exec(_ cmdObj: ZKCmd, needToken: Bool = true, retries: Int = 3) async throws -> ExecResult {
        let cmd = cmdObj.cmd
        let resp = try await request(cmdObj, cmd: cmd, needToken: needToken, retries: retries)
        let rc = extractRc(cmd, resp)
        // rc=3 (命令过期/令牌失效) → 刷令牌重试一次
        // 2026-10-27 审核修复 (AUDIT-A F-13)：rc=13（会话已过期）也要自愈。
        // 原先只认 rc=3（命令过期），而 Android 认 rc=3 与 rc=13 两种。
        // 后果：iOS 遇到 rc=13 直接报错，用户得手动重试；Android 会自动重取令牌再发一次。
        if (rc == 3 || rc == 13), needToken {
            log("warn", "\(cmdObj.name) rc=\(rc) → 刷新令牌重试一次")
            sessionTokenHex = "0000"
            let resp2 = try? await request(cmdObj, cmd: cmd, needToken: true, retries: 1)
            if let r2 = resp2 {
                let rc2 = extractRc(cmd, r2)
                if rc2 != 3 && rc2 != 13 { return ExecResult(frame: r2, rc: rc2, klvs: r2.klvs) }
            }
        }
        // rc=12「mac地址不正确」的**顺序自愈** (2026-10-17 真机): 0x88 包络里那 6 字节 MAC 有两种取法,
        // 本机默认按原版 APK 语义 (见 ZKProtocol.MacOrder)。老钥匙串是在没有这一层之前配的, 若它是
        // 另一种取法, 之后每条命令都会回 rc=12 —— 而 rc≠0 的语义正是"锁没执行", 所以换一种取法重发
        // 一帧是安全的 (与 rc=3 刷令牌那一支同一条纪律)。只做一次, 成功即落盘: 下一帧起不必再试。
        // 配网期 (pairMac != nil) 不走这一支: 那里由 08 批次 1 的换序重发裁定 (见 finishPairing) ——
        // 免得把"任意写命令自愈"混进配网链: 配网期每条命令都改锁, 判据必须是本机知道语义的那一条。
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
            log("warn", "\(cmdObj.name) rc=12: 两种 MAC 字节序都被拒 (回退 \(used.rawValue)) — 不是字节序问题， 是锁内密钥与本机不一致")
        }
        log("info", "\(cmdObj.name) -> rc=\(rc)")
        return ExecResult(frame: resp, rc: rc, klvs: resp.klvs)
    }

    func execOk(_ cmdObj: ZKCmd, needToken: Bool = true, retries: Int = 3) async throws -> ExecResult {
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

}
