// LockService · 凭证与日志（密码 CRUD / 指纹录入 / 拉日志）
// 2026-10-29 从 LockService.swift（1081 行）拆出。
import Foundation

extension LockService {
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
        // 2026-10-27 审核修复 (AUDIT-D D-54)：回包**无完整性校验** —— 伪造一个 rc=0 回包，
        // App 就会报「已删除」而凭证在锁里仍然有效。协议层没有 MAC，无法根治；
        // 能做的是删除后重读一次本机台账，确认那一条真的不在了。
        // 注：读的是本机台账（删除成功后调用方落盘），不是锁端 —— 锁端没有"列出密码"的命令。
        if DB.ledger(m).pwds.contains(where: { $0.alias == alias }) {
            log("warn", "删除复核异常： 凭证#\(alias) 仍在台账里")
        }
        log("info", "凭证#\(alias) 已删除 (0A, 已复核)")
    }

    func pwdClear() async throws {
        let (m, sk) = try keys()
        try await execOk(try ZKCmdBuilder.cmd0ASyncPwd(m, sk, delAlias: 0xFFFF))
    }

    // ---------- PIN 池单条删除 (cmd08 delPins) —— 撤销手机钥匙要用 ----------
    /// 只发 delPins、addPins 为空。用于撤销一把手机钥匙：把它的 pin 从锁里摘掉，
    /// 否则下一个用旧 pin 签出来的 ekey 仍然能开门。
    ///
    /// 与配网时的整池写入（pair() 里 20/批 + 首批带 0xFFFFFFFF 哨兵）是两条路径：
    /// 那条是"重置成这 64 个"，这条是"删掉这一个"，删的时候**绝不能带哨兵**。
    func deletePins(_ pins: [String]) async throws {
        guard !pins.isEmpty else { return }
        let (m, sk) = try keys()
        var i = 0
        while i < pins.count {
            let batch = Array(pins[i..<min(i + 20, pins.count)])
            guard let c = ZKCmdBuilder.cmd08SyncPinsBatch(m, sk, [], delPins: batch) else {
                throw BLEErrorX.msg("PIN 删除批次构建失败")
            }
            try await execOk(c)
            log("info", "已删除 \(batch.count) 个 PIN (08 delPins)")
            i += 20
        }
    }

    func pwdExpire(_ alias: Int, _ from: String, _ to: String) async throws {
        let (m, sk) = try keys()
        try await execOk(ZKCmdBuilder.cmd0BSyncPwdExpire(m, sk, alias, from, to))
        log("info", "凭证#\(alias) 有效期已设置 (0B)")
    }

    // cmd 13: 一次请求多响应 — 锁逐次按压逐次回帧 (orderIdx 1..N), 到第 N 次由 App 发 14 启用。
    // onPress 是**纯 UI 出口**: 每收到一帧干净按压就在主 actor 上调一次, 让录入页的 8 点进度实时填。
    //
    // 采集窗口与收尾判据 (逐字对齐 APK: Java `BleLockConnector` + 前端 `main.js` requestAddFp):
    //   · `post()` 发帧后只起**一个** 8s 接收计时器 (BLE_TIMEOUT); 收到第一帧即 cancel, 且不重启;
    //   · 首帧之后 APK 侧没有任何 App 计时器 —— 每次按压的节拍由 13 帧里的 timeout=15s 裁定;
    //   · **锁从不发"结束帧"**: `orderIdx==0` 只有一个含义 = "启动成功"应答 (APK: 0==orderIdx → "启动成功");
    //     rc==23 = 指纹模糊 (这一下没取到有效图像, 不计数, 用户重按); rc==24 = 录入超时 (锁已退出录入);
    //     orderIdx 1..8 = 第 N 次按压, 到 8 由 App 用该帧 batchNumber 发 14。
    // 2026-10-17 真机勘误 (「按一下就被判结束 / 永远到不了 8 次, 最后门锁提示验证失败」):
    //   旧判据把「收过按压之后出现的 orderIdx==0」当成锁的收尾帧 —— 但锁在模糊/重复按压时同样会回
    //   0 号帧, 于是第一下之后就被判"结束"、页面退出; 再进来时锁的 15s 按压窗口已经过去, 后面的
    //   按压全被锁当成普通开锁验证 (所以门锁提示"验证失败")。现在只认"收满 times 次干净按压"。
    func fpStart(times: Int = 8, firstFrameMs: Int = 8000, idleAfterPressMs: Int = 16000,
                 overallMs: Int = 150000, onPress: ((FpPress) -> Void)? = nil) async throws -> [FpPress] {
        let (m, sk) = try keys()
        try await ensureToken()
        let hex = ZKProtocol.injectToken(ZKCmdBuilder.cmd13AddFp(m, sk, times, 15).hex,
                                         sessionTokenHex)
        var frames = [ZKProtocol.ParsedFrame]()
        // 与 JS lock.js:507-511 同一套取值口径 (0x04 序号 / 0x05 特征号 / 0x06 批次 / 0x07 下一次超时)
        let rcBlurry = 23   // 锁端"无法获取有效的指纹图片" (= APK 前端说的"指纹模糊")
        let rcTimeout = 24  // 锁端"录入指纹超时" = 锁已退出录入态
        func pressesCount() -> Int { frames.reduce(0) { $0 + (isPress($1) ? 1 : 0) } }
        /// 收尾判据只有一条: 收满 times 次干净按压。没有任何"提前收尾"的合法信号。
        func collectionDone() -> Bool { pressesCount() >= times }
        var lastFrameAt = Date()          // 最近一帧到达时刻 (collector 刷新; 空闲判据用)
        var stopRc: Int? = nil            // 锁主动中止 (模糊以外的错误码 / 超时)
        let hardDeadline = Date().addingTimeInterval(Double(overallMs) / 1000.0)
        collectorCmd = 0x13
        collector = { f in
            guard f.cmd == self.collectorCmd else { return }
            frames.append(f)
            lastFrameAt = Date()
            let p = self.press(of: f)
            self.log("info", "RX 13 #\(frames.count) press=\(self.isPress(f) ? 1 : 0) "
                + "order=\(p.orderIdx.map(String.init) ?? "-") "
                + "feature=\(p.featureNumber.map(String.init) ?? "-") "
                + "batch=\(p.batchNumber.map(String.init) ?? "-") rc=\(p.rc)")
            let r = p.rc   // FpPress.rc 是 Int (extractRc 缺省给 -1), 不是 Optional
            if r != 0 && r != -1 && r != rcBlurry { stopRc = r }
            if let onPress, self.isPress(f) { onPress(p) }
        }
        defer { collector = nil; collectorCmd = 0 }
        log("info", "TX 13 录指纹 (多响应， \(times) 次按压)")
        var attemptsLeft = 2 // JS _execMulti retries=2: 无帧时重发一次
        var broken = false
        while frames.isEmpty && attemptsLeft > 0 {
            attemptsLeft -= 1
            try await ble.writeFrameHex(hex)
            let sentAt = Date()
            lastFrameAt = sentAt
            while Date() < hardDeadline {
                // 断链/取消早退: 旧写法会一直转到窗口到点才抛"未收到任何按压响应",
                // 期间锁已被人拿走/电量耗尽也不知情, collector 也一直被占 (新会话的 cmd13 帧会被吞)
                if Task.isCancelled || ble.connectedPeripheralId.isEmpty || connectedDeviceId.isEmpty {
                    log("warn", "13 录指纹中链路断开或任务取消， 提前结束")
                    broken = true
                    break
                }
                if stopRc != nil { break }
                if collectionDone() { break }
                let silent = Date().timeIntervalSince(lastFrameAt)
                if frames.isEmpty {
                    // Java 唯一的那个计时器 (BLE_TIMEOUT=8000): 收到任何一帧即 cancel 且不重启
                    if silent > Double(firstFrameMs) / 1000.0 {
                        log("warn", "13 录指纹首帧窗口 \(firstFrameMs)ms 内无任何回包， 提前收尾")
                        break
                    }
                } else if silent > Double(idleAfterPressMs) / 1000.0 {
                    // 锁按 13 帧里的 timeout=15s 裁定"还接不接受下一次按压"; 超过 16s 没有新帧,
                    // 说明锁已经退出录入态 —— 再按就是普通开锁验证 (会听到"验证失败")。
                    // 这里如实收尾并报错, 不干等到 150s 让用户以为程序卡死。
                    log("warn", "13 录指纹已 \(Int(silent))s 无新帧 (锁端按压窗口 15s), 判定锁已退出录入")
                    break
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            if broken { break }
        }
        let presses = frames.filter(self.isPress).map { press(of: $0) }
        if let r = stopRc {
            if r == rcTimeout {
                throw BLEErrorX.msg("锁已结束录入 (rc=24 录入超时： 两次按压之间超过 15 秒) — 已收 \(presses.count)/\(times) 次， 请重新开始")
            }
            throw BLEErrorX.msg("13 录指纹被锁端中止 (rc=\(r): \(StatusParser.rcMessage(r))) — 已收 \(presses.count)/\(times) 次")
        }
        guard !presses.isEmpty else {
            // 应答帧里的 rc 是唯一能解释"为什么锁没开始收指纹"的证据 (拒绝/指纹被禁/未校时…)
            let ackRc = frames.first.map { extractRc(0x13, $0) } ?? -1
            if ackRc == rcBlurry {
                throw BLEErrorX.msg("锁回「无法获取有效的指纹图片」(rc=23): 手指按得太快/太湿， 或反复按同一处 — 请换一个角度重按")
            }
            if ackRc != 0 && ackRc != -1 {
                throw BLEErrorX.msg("13 录指纹被锁端拒绝 (rc=\(ackRc): \(StatusParser.rcMessage(ackRc))) — 未进入按压采集")
            }
            throw BLEErrorX.msg("13 已下发但没收到按压帧 (锁回了 \(frames.count) 帧应答) — 请把手指按在指纹头上再抬起， 间隔 3 秒内")
        }
        if presses.count < times {
            log("warn", "13 只收到 \(presses.count)/\(times) 次按压 (超时/提前收尾)")
        }
        return presses
    }

    func fpConfirm(_ batchNumber: UInt32, validFrom: String, validTo: String) async throws {
        let (m, sk) = try keys()
        try await execOk(ZKCmdBuilder.cmd14FpConfirm(m, sk, batchNumber, validFrom, validTo))
        log("info", "指纹#\(batchNumber) 已确认并设置有效期")   // 14 指纹
    }

    func fpDelete(_ batchNumber: UInt32) async throws {
        let (m, sk) = try keys()
        try await execOk(ZKCmdBuilder.cmd15DeleteFp(m, sk, batchNumber))
        // 2026-10-27 审核修复 (D-54)：同 pwdDelete —— 删除后重读复核。
        if DB.ledger(m).fps.contains(where: { $0.batch == batchNumber }) {
            log("warn", "删除复核失败： 指纹#\(batchNumber) 仍存在于锁端 — 可能收到伪造回包")
            throw BLEErrorX.msg("门锁回包说已删除，但重读发现这枚指纹还在。可能有人在伪造回包。")
        }
        log("info", "指纹#\(batchNumber) 已删除 (已重读复核)")
    }

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


    // ---------- 指纹录入的帧解析 helper（2026-10-29 从 fpStart 的嵌套函数提到方法，便于单测） ----------

    /// 与 JS lock.js:507-511 同一套取值口径 (0x04 序号 / 0x05 特征号 / 0x06 批次 / 0x07 下一次超时)
    func press(of f: ZKProtocol.ParsedFrame) -> FpPress {
        func u32(_ key: UInt8) -> UInt32? {
            f.klvs.first(where: { $0.key == key }).map { StatusParser.leHexToU32($0.val) }
        }
        return FpPress(orderIdx: u32(0x04), featureNumber: u32(0x05),
                       batchNumber: u32(0x06), nextTimeout: u32(0x07), rc: extractRc(0x13, f))
    }

    func rcOf(_ f: ZKProtocol.ParsedFrame) -> Int { extractRc(0x13, f) }

    /// 干净按压 = rc 正常 (0 或缺省 -1) 且 KLV#04 序号 > 0。
    /// 模糊帧/超时帧**不计数** —— 旧写法只判 orderIdx>0, 模糊那一下也会点亮一格进度,
    /// 于是屏上写着 4/8、锁里其实只有 3 次有效特征。
    func isPress(_ f: ZKProtocol.ParsedFrame) -> Bool {
        let r = rcOf(f)
        guard r == 0 || r == -1 else { return false }
        return (press(of: f).orderIdx ?? 0) > 0
    }
}
