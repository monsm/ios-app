// AppModel.swift —— 应用级状态（真实引擎驱动，不是种子数据）。
//
// 纪律：@Observable（iOS 17+ 现代写法），不用 ObservableObject。
// 这里只放"跨页面共享"的状态；页面临时状态留在页面里。
//
// 这一版把上一版占位的 sample 种子全换成了 Engine 的真读数：
//   · 锁  ← DB.keychains() / DB.keychain(mac) / DB.readStatus(mac)
//   · 凭证 ← DB.ledger(mac).pwds / .fps + MobileKeyService.list(mac)
//   · 成员 ← DB.members() + MemberHub.ext(id)
//   · 台账 ← DB.readLogs(mac)（cmd16 写入的缓存）
// 开锁、读状态、读日志、增删密码、配网，全部走 LockService / BLEService 的真链路。
import SwiftUI
import Foundation

@MainActor
@Observable
final class AppModel {
    // MARK: - 真实数据（由 reload() 从 Engine 构建）

    /// 当前门锁（nil = 还没添加）。
    var lock: LockSummary?
    /// 台账（DB.readLogs 的投影）。
    var entries: [LedgerEntry] = []
    /// 凭证（DB.ledger 的投影）。
    var keys: [KeyItem] = []
    /// 成员（DB.members + MemberHub 的投影）。
    var members: [MemberCard] = []

    // MARK: - 界面态

    /// 本机数据保护是否已解锁（冷启动才要求）。
    var unlocked: Bool = !DB.hasPasscode()
    /// 胁迫码进入的空壳模式：数据区显示为空（开锁能力保留）。
    var decoyMode: Bool = false
    /// 只读试验模式（顶部常驻红条，必须常驻 —— 用户第二天会忘了自己开过它）。
    /// 初值从 kf_trial_guard 读；开关写回由 trialGuardBinding 负责。
    var trialGuard: Bool = DB.store.getBool("kf_trial_guard", false)
    /// 开锁链相位（门页刻度盘读它）。
    var dialPhase: DialPhase = .idle
    /// 最近一次动作的时刻（毫秒 epoch）。
    var lastActionAt: Int64?
    /// 最近一次读到的锁状态快照。
    var lastStatus: StatusSnapshot?
    /// 正在跑的长任务的一句话（配网 / 读日志）。
    var busyMessage: String?
    /// 最近一次失败的原因（页面就地展示）。
    var lastError: String?

    // MARK: - 开锁链的可见状态（原版 UnlockDial 的进度 / 失败链 / 自动上锁倒计时）

    /// 开锁链三段进度：0 待机 / 1 握手 / 2 鉴权下发 / 3 等回执。
    var unlockPhase: Int = 0
    /// 连续失败次数（失败终态显示三项自查清单）。
    var failStreak: Int = 0
    /// 退避重试的倒计时文案（2s / 5s）。
    var retryHint: String?
    /// 自动上锁倒计时（秒）。nil = 不显示。
    var autoLockLeft: Int?
    /// 最近一次开锁成功的时刻（毫秒）。30 秒内再次开锁要过本机密码闸。
    var lastUnlockSuccessAt: Int64?
    /// 通过「30 秒内二次开锁」密码闸的时刻（ms）。
    ///
    /// 2026-11-01 修复：闸门页的说明写着「输对一次后 30 秒内不再重复询问」，
    /// 但 `needsGate` 只看 `lastUnlockSuccessAt` —— 而每次开锁都会刷新它，
    /// 于是**连续开门会一直弹密码**（每开一次就重置 30 秒窗口），说明文案是假的。
    /// 这里记「刚通过闸门」的时刻，供 `needsGate` 给一个真正的宽限窗。
    var gatePassedAt: Int64?
    @ObservationIgnored private var autoLockTask: Task<Void, Never>?
    /// 用户在等待中轻点圆盘撤销：命令已发就等回执，未发就立刻停（不发下一帧）。
    @ObservationIgnored private var unlockCancelled = false

    /// 弱引用路由：EngineHost 的唯一跳转出口。由 RootView 在装配时注入。
    @ObservationIgnored weak var router: Router?

    /// 用户在「全部锁 / 换锁」里显式选中的锁。它优先于启动默认锁，直到进程重启。
    /// 没有它，冷启动的默认锁会把「刚刚手动切到的另一把」一直盖回去。
    var overrideMac: String?

    /// 当前锁的 MAC（没锁时回落本机偏好锁；DB.preferredMac 内部会做归一化）。
    /// 「锁档案 · 设为启动默认锁」的真实消费点：冷启动 app.lock 还是 nil 时先落默认锁，
    /// 默认锁不存在（已解绑）才回退上次停留的那把。
    var currentMac: String {
        if let overrideMac, DB.keychain(overrideMac) != nil { return overrideMac }
        if let lock { return lock.id }
        let def = LockArchive.defaultMac
        if !def.isEmpty, DB.keychain(def) != nil { return def }
        return DB.preferredMac()
    }

    // MARK: - 载入

    /// 从 Engine 重建全部界面数据。页面 .task / onAppear 调它。
    /// - Parameter refreshStatus: true 时顺带联网读一次 cmd03（会耗时，只在需要时开）。
    func reload(refreshStatus: Bool = false) async {
        let mac = currentMac
        if mac.isEmpty {
            lock = nil
            keys = []
            members = []
            entries = []
            lastStatus = nil
            return
        }
        guard let kc = DB.keychain(mac) else {
            lock = nil
            keys = []
            members = []
            entries = []
            return
        }

        if refreshStatus, LockService.shared.connectedMAC == mac {
            if let st = try? await LockService.shared.getStatus(mac: mac) {
                DB.writeStatus(mac, st)
            }
        }

        let snap = DB.readStatus(mac)
        lock = LockSummary(
            id: kc.mac,
            name: kc.name.isEmpty ? (kc.pidName.isEmpty ? "我的门锁" : kc.pidName) : kc.name,
            model: kc.pidName.isEmpty ? "未知型号" : kc.pidName,
            battery: snap?.powerLevel ?? -1,
            // 2026-11-01 修复：原来硬编码 `signal: 0`，而 `LockSummary.signal` 的注释写着「0 = 未知」。
            // `LockStatusScreen:91` 把它显示成「信号 0 / 4」并涂成警告色（`<= 1` ⇒ 永远警告），
            // 用户看到的是"信号极差"，而实际上**从未测过**。
            // `LinkSenseModel.level` 早就有同一个 0–4 映射（0 = 不可测），直接复用。
            signal: LinkSenseModel.level(LinkSenseModel.savedRSSI(mac)),
            firmware: snap?.firmware ?? kc.fw,
            // 2026-11-01（Round 240）：原来只数 `pwds + fps`，**不含手机钥匙** ——
            // 而凭证页的「全部 N」芯片数的是 `keys`（含手机钥匙），成员行也是。
            // 于是门页说「5 枚凭证在册」、点进去列表却有 7 条。这里与 `keys` 对齐。
            keyCount: DB.ledger(mac).pwds.count + DB.ledger(mac).fps.count + MobileKeyService.list(mac).count,
            isConnected: LockService.shared.connectedMAC == mac,
            // 安全模式 / 静音：按 cmd03 的 securityLevel / soundVolumn 映射。
            // TODO(真机核对)：这两条的语义需要在真锁上对一次（A/B 双验 与 提示音开关）。
            // 安全模式 = 双验（cmd20 SETVALIDATIONMODE 对应快照的 verifyMode）。
            safeMode: (snap?.verifyMode ?? 0) != 0,
            // 静音：cmd03 快照里没有这一项，读本机镜像键（只在 cmd18 写成功后落）。
            muted: DB.store.getBool("kf_muted_" + mac)
        )
        lastStatus = DB.get(StatusSnapshot.self, "kf_snap_" + mac)

        reloadKeys(mac)
        reloadMembers()
        reloadEntries(mac)
        // 胁迫码进入的空壳模式：门照样能开，但数据区（凭证 / 成员 / 台账）显示为空。
        // 只清界面投影，不动任何真实存储 —— 退出空壳模式（杀进程后正常密码解锁）即恢复。
        if decoyMode {
            keys = []
            members = []
            entries = []
        }
        // SEC-03：把"当前是不是空壳"广播到数据层。凭证工作室 / 备份工作室 / 记录工作室
        // 这些直接读 DB 的页面必须据此返回空集，否则胁迫者能在空壳里看到并导出真实凭证。
        let wasDecoy = DB.isDecoy
        DB.setDecoy(decoyMode)
        if decoyMode { CredentialOrg.cancelAllForDecoy() }
        else if wasDecoy {
            // 只在**真的从空壳退出来**时重建一次（reload 会被频繁调用）。
            CredentialOrg.resetDecoyNotificationGuard()
            CredentialOrg.rescheduleAllAlerts()
            // 自动开锁的轮询在空壳里是停的（`pollOnce` 达标即 `stop()`），退出后要恢复 ——
            // 否则用户会以为"自动开门坏了"，而且没有任何提示。
            if let mac = currentKeychain?.mac { AutoOpenController.shared.onForeground(mac: mac) }
        }
        // ↑ SEC-03 同一族的**通知面**：数据层清空了，但已排/已送达的到期提醒还带着
        //   真实凭证名（「密码临期 · 前门密码」）—— 胁迫者一看通知中心就知道了。
        //   进空壳整族清掉；退出空壳必须**重建**，否则提醒永久消失而界面仍显示已排程。
    }

    /// 只重建凭证（增删改之后调，比重载全部便宜）。
    func reloadKeys(_ mac: String? = nil) {
        let m = mac ?? currentMac
        guard !m.isEmpty else { keys = []; return }
        let l = DB.ledger(m)
        var out: [KeyItem] = []
        for p in l.pwds {
            out.append(KeyItem(
                id: "pwd:\(p.alias)",
                kind: p.temp ? .temp : .password,
                name: p.note.isEmpty ? (p.temp ? "临时码 \(p.alias)" : "密码 \(p.alias)") : p.note,
                owner: p.owner,
                code: p.pwd.map { String(repeating: "•", count: max(4, $0.count)) },
                expiresAt: Self.epochMillis(p.to),
                createdAt: p.at,   // LedgerPwd.at 是毫秒 epoch
                disabled: CredentialLocalState.isDisabled(mac: m, id: "pwd:\(p.alias)")
            ))
        }
        for f in l.fps {
            out.append(KeyItem(
                id: "fp:\(f.batch)",
                kind: .fingerprint,
                name: f.name.isEmpty ? "指纹 \(f.batch)" : f.name,
                owner: f.owner,
                code: nil,
                expiresAt: nil,   // 指纹台账没有到期字段（LedgerFp 只有 batch/name/at/note/src/owner/isAlarm）
                createdAt: f.at,  // 但 `at`（录入时刻）有 —— 填上，详情页才有「已使用 N 天」
                disabled: CredentialLocalState.isDisabled(mac: m, id: "fp:\(f.batch)")
            ))
        }
        for k in MobileKeyService.list(m) {
            out.append(KeyItem(
                id: "mkey:\(k.id)",
                kind: .mobile,
                name: k.memberName.isEmpty ? "手机钥匙" : k.memberName + " 的手机钥匙",
                // 2026-11-01（Round 238）：密码/指纹的 `owner` 是**成员 id**，而这里原来存的是**名字** ——
                // 同一个 `KeyItem.owner` 字段两种口径（Round 237 修了写入侧与计数，这里补齐投影侧）。
                // 旧手机钥匙记录可能没有 memberID，那时回落名字（读侧 `ownerName` 已有名字回退）。
                owner: k.memberID.isEmpty ? k.memberName : k.memberID,
                code: k.ekey,
                expiresAt: k.forever ? nil : Self.epochMillis(k.validTo),
                disabled: CredentialLocalState.isDisabled(mac: m, id: "mkey:\(k.id)")
            ))
        }
        keys = out
    }

    /// 只重建成员。
    func reloadMembers() {
        let table = MemberHub.allExt()
        members = DB.members().map { m in
            let ext = table[m.id] ?? MemberExt()
            let role: MemberCard.Role = ext.role == "main" ? .owner : (ext.role == "guest" ? .guest : .member)
            return MemberCard(
                id: m.id,
                name: m.name.isEmpty ? "未命名" : m.name,
                role: role,
                // `owner` 历史上有 id 与名字两种口径（见 `addPassword`），计数两种都认。
            keyCount: keys.filter { $0.owner == m.id || $0.owner == m.name }.count,
                lastActiveAt: nil,
                archived: ext.archived
            )
        }
    }

    /// 只重建台账。
    /// 唯一映射口径 → RecordsSource.load：归属人、detail、告警色、未回时刻过滤都在那一处，
    /// 这里不能再写第二份（旧实现 owner 恒为 nil，门页「最近开门」永远显示「未归属」，
    /// 且与记录页对同一条日志给出不同的 tint/detail）。
    func reloadEntries(_ mac: String? = nil) {
        let m = mac ?? currentMac
        guard !m.isEmpty else { entries = []; return }
        let load = RecordsSource.load(mac: m, lockName: lock?.name ?? "门锁", members: members)
        entries = load.entries
    }

    // MARK: - 开锁（真链路 + 失败重试链 + 自动上锁倒计时）

    /// 开锁链：ensureConnected → cmd04 → 回执。刻度盘的进度弧跟着真实阶段走。
    /// 失败处理链（原版 DeviceHomeBlocks.swift:403-519）：
    ///   · 自动重试 2 次（2s / 5s 退避）；超时不重试 —— 门口反复广播比失败更糟；
    ///   · 连续失败累计 failStreak，第三次起由门页显示三项自查清单与「再试一次」；
    ///   · 成功才记 lastUnlockSuccessAt / Milestones，并起自动上锁倒计时。
    func runUnlockChain() async {
        guard dialPhase == .idle || dialPhase.isFailed else { return }
        let mac = currentMac
        guard !mac.isEmpty else {
            dialPhase = .failed("还没有添加门锁")
            return
        }
        let maxAttempts = SettingsStore.shared.autoRetry ? 3 : 1
        unlockCancelled = false
        lastError = nil
        retryHint = nil
        for attempt in 0 ..< maxAttempts {
            if Task.isCancelled { break }
            // 2026-11-01（真机日志驱动）：凭证类 rc（1/2/6/11）是**确定性**失败 ——
            // 同一枚凭证再发一次必然同样结果。日志里能看到自动重试把同一条 cmd04 连发了 6 次，
            // 白耗电，还可能踩到锁端的防重放。这种情况**不再自动重试**，直接如实报错。
            var nonRetryable = false
            do {
                unlockPhase = 1
                dialPhase = .reaching
                try await LockService.shared.ensureConnected(mac: mac)
                if unlockCancelled { dialPhase = .idle; unlockPhase = 0; return }
                unlockPhase = 2
                dialPhase = .sending
                // 「锁档案 · 开锁 PIN」的真实消费点：选过第 N 枚就传第 N 枚，
                // 没选（-1）交给 LockService 用第一枚（与旧版自动档同义）。
                let rc = try await LockService.shared.unlock(mac: mac, pinDec: chosenPin(mac))
                unlockPhase = 3
                dialPhase = .waiting
                if rc == 0 {
                    dialPhase = .opened
                    unlockPhase = 3
                    let now = Int64(Date().timeIntervalSince1970 * 1000)
                    lastActionAt = now
                    lastUnlockSuccessAt = now
                    failStreak = 0
                    retryHint = nil
                    Milestones.recordUnlockSuccess()
                    await reload(refreshStatus: false)
                    startAutoLockCountdown()
                    try? await Task.sleep(for: .milliseconds(900))
                    if dialPhase == .opened { dialPhase = .idle; unlockPhase = 0 }
                    return
                }
                // 2026-11-01：`rc == 22` 此前**也被当成成功**（显示「已开锁」、记 lastUnlockSuccessAt、
                // 起自动上锁倒计时、记里程碑）。但 `StatusParser.rcMsg[22]` 的注释明确写着
                // 「这张表要与 vendor status.js 逐字一致」，而 22 = **「不能重复验证」**；
                // Android 侧也是把它当错误文案弹给用户的。**没有任何证据表明 22 等于"门开了"。**
                // 若 22 实际是"还需要第二种验证"，旧行为就是**把失败显示成成功**，还会开始自动上锁倒计时。
                // 现在改成如实提示，且不记成功、不起倒计时。（B 模式双验属可选档，需真机再确认一次文案。）
                if rc == 22 {
                    nonRetryable = true
                    throw BLEErrorX.msg("门锁要求第二种验证方式（B 模式双验）—— 请再用指纹或密码验证一次")
                }
                nonRetryable = [1, 2, 6, 11].contains(rc)
                throw BLEErrorX.msg(StatusParser.rcFriendly(rc))
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                let timeout = msg.contains("超时") || msg.lowercased().contains("timeout")
                failStreak += 1
                if attempt + 1 < maxAttempts, !timeout, !nonRetryable {
                    retryHint = "第 \(attempt + 1) 次没成 · \(attempt == 0 ? 2 : 5) 秒后自动重试"
                    dialPhase = .reaching
                    unlockPhase = 1
                    try? await Task.sleep(for: .seconds(attempt == 0 ? 2 : 5))
                    if Task.isCancelled || unlockCancelled { return }
                    continue
                }
                lastError = msg
                retryHint = nil
                unlockPhase = 0
                dialPhase = .failed(msg)
                return
            }
        }
    }

    /// 中途撤销等待（原版「轻点圆盘可撤销」）：只回到待机，不补发任何命令。
    func cancelUnlock() {
        unlockCancelled = true
        autoLockTask?.cancel()
        autoLockTask = nil
        retryHint = nil
        unlockPhase = 0
        if dialPhase.isBusy { dialPhase = .idle }
    }

    /// 锁档案里选的那枚 PIN；-1 / 越界 = 交给 LockService 的自动档。
    private func chosenPin(_ mac: String) -> String? {
        let idx = DB.store.getInt("kf_chosen_pin_" + mac, -1)
        guard idx >= 0, let kc = DB.keychain(mac), idx < kc.pins.count else { return nil }
        return kc.pins[idx]
    }

    /// 自动上锁倒计时：档位取 cmd24 的本机记忆（kf_tailgate_），没设过按厂商默认 6 秒。
    /// 这是本地回放，不是门磁读数 —— 文案写「约 N 秒后自动上锁 · 请确认门已关好」。
    func startAutoLockCountdown() {
        autoLockTask?.cancel()
        let interval = DB.tailgate(currentMac)?.interval ?? 6
        let total = max(2, interval + 1)
        autoLockLeft = total
        autoLockTask = Task { @MainActor in
            for left in stride(from: total, through: 1, by: -1) {
                if Task.isCancelled { return }
                autoLockLeft = left
                try? await Task.sleep(for: .seconds(1))
            }
            autoLockLeft = nil
        }
    }

    // MARK: - 读锁状态

    func refreshStatus() async {
        let mac = currentMac
        guard !mac.isEmpty else { return }
        // 2026-11-01 修复：`lastError` 是**跨功能共用的单一错误槽**，而三个页面
        // （`DoorScreen:1102` / `LockStatusScreen:351` / `RecordsScreen:871`）都靠
        // 「`lastError` 非 nil」判断"本次操作失败"。此前本函数只在 catch 里写、成功时不清，
        // 于是上一次操作留下的旧错误（例如改密码时的"旧码没能删除"）会被下一个页面
        // 当成**它自己**的失败显示出来 —— 一次成功刷新却弹出别人的错误。
        // 与 `runUnlockChain` 同口径：开工先清槽，失败再写。
        lastError = nil
        do {
            let st = try await LockService.shared.getStatus(mac: mac)
            DB.writeStatus(mac, st)
            await reload(refreshStatus: false)
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - 读日志（cmd16 翻页）

    /// 读锁内日志：最多 20 页 × 5 条，逐页落缓存。
    ///
    /// 返回值 = **锁端还剩多少条更早的记录没读**（`nil` = 固件没报，不知道）。
    ///
    /// 2026-11-01：`LogPage.surplus` 早就从协议的 KLV#04 解析出来了，**但全仓没有任何消费者** ——
    /// 于是 20 页封顶（100 条）之后循环静默停止，用户看到「已读取 100 条」会以为读全了，
    /// 而锁里可能还有几百条更早的记录。这里把 surplus 带出去，让界面如实说明。
    /// 返回 **本次实际从锁内读到的条数** 与（若被 20 页上限截断）锁端剩余条数。
    ///
    /// 2026-11-01：原来只返回 `Int?`（剩余）。而界面用 `entries.count`（**合并后的缓存总数**，
    /// 在「全部锁」范围下还是多把锁之和）当"本次读取数" —— 于是这次一条都没读到也会显示
    /// 「已读取 300 条」。现在把"本次读到几条"如实带出来。
    @discardableResult
    func readLogs() async -> (read: Int, remaining: Int?)? {
        let mac = currentMac
        guard !mac.isEmpty, busyMessage == nil else { return nil }
        busyMessage = "正在读门锁记录…"
        defer { busyMessage = nil }
        // 同 `refreshStatus`：开工先清错误槽，否则记录页会把上一次别处留下的旧错误
        // 当成"读取失败 · …"显示。
        lastError = nil
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            // 2026-11-01 修复（第 203 轮三方对比）：**翻页方向原来是反的。**
            // vendor（`main.js` 的 getLog）是：`getLog(0, startIdx = 0xFFFFFFFF)`，
            // 收到一页后取**页内最后一条**的 idx，下一页 `startIdx = idx - 1` —— **从最新往回读**。
            // 本仓此前从 `0` 开始、`last.idxRaw + 1` **递增**（从最旧往前读）。
            // `orderType=0` 语义是"从 startIdx 往回"，所以从 0 开始只会读到 idx=0 那一条，
            // 然后每页都在原地打转 ⇒ 用户看到"读取成功"但几乎没有记录。
            // 本仓自己的金标 `GoldenDiffTests:87` 用的就是 0xFFFFFFFF，也只有这个方向对得上。
            var startIdx: UInt32 = 0xFFFF_FFFF
            var collected: [LogEntry] = []
            var lastSurplus: Int?
            var pagesRead = 0
            for _ in 0 ..< 20 {
                let page = try await LockService.shared.getLogs(startIdx: startIdx, pageSize: 5)
                pagesRead += 1
                // 每页都带 surplus（协议 KLV#04）；以最后一页的为准。
                if let s = page.surplus { lastSurplus = s }
                if page.logs.isEmpty { break }
                collected.append(contentsOf: page.logs)
                // vendor 同款：`surplus > 0 && logCount < 100` 才继续 —— surplus 为 0 表示已经到底。
                if let s = page.surplus, s <= 0 { break }
                if page.logs.count < 5 { break }
                // 往回退：取**页内最小 idx** 再 -1（idx 是 32 位，先判 0 防下溢）。
                // vendor 写的是"页内最后一条"，那隐含假设了固件按降序返回 —— 用 `min()` 等价，
                // 但即使某固件在页内升序也不会跑飞（`last` 会变成最大 idx，翻页直接原地打转）。
                guard let low = page.logs.map(\.idxRaw).min(), low > 0 else { break }
                startIdx = low - 1
            }
            // **只在读满 20 页（可能被截断）时才报剩余数。**
            // 原因：不同固件对 KLV#04 的语义可能是"剩余"也可能是"总数"，
            // 若提前读完（页数 < 20）还报一个数字，宁可不说也不要误报。
            let remaining: Int? = pagesRead >= 20 ? lastSurplus : nil
            DB.writeLogs(mac, collected)
            // 2026-11-01 修复：这一行原先写 `"kf_logsync_" + mac`（**未归一化**）且值是 **Int**，
            // 而读取方 `RecordsSource.lastSync` 用的是 `DB.normalizeMac(mac)` + `getString`。
            // 两处口径不一致 ⇒ 只要 mac 带冒号或大写，或者这条读取路径不是经由
            // `RecordsScreen.read()`（那里会补一次 `markSynced`），"上次读取时间"就永远读不到，
            // 界面恒显示「还没读取过锁内日志」—— 而其实刚刚读过。
            // 现在写/读/补记三处统一为：**归一化键 + 毫秒字符串**。
            DB.store.set("kf_logsync_" + DB.normalizeMac(mac), String(Int(Date().timeIntervalSince1970 * 1000)))
            await reload(refreshStatus: false)
            return (read: collected.count, remaining: remaining)
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    // MARK: - 凭证写入

    /// 新增一条密码/临时码。
    /// - Parameters:
    ///   - owner: 归属成员 —— **传 id 或成员名都可以**，内部统一换算成 id 再落库。
    ///     （E-03：旧实现写死 nil，工坊里选的归属被丢弃，导致新密码永远落「未归属」组；
    ///     Round 237：旧实现把调用方给的**名字**原样存进 `owner`，而读侧 `ownerName` 按 id 查 ⇒
    ///     工作室创建的凭证恒显示「未归属」。现在写侧统一成 id，读侧另留名字回退以兼容旧数据。）
    ///   - replacingAlias: 「改造密码值」（E-02）传旧 alias —— 先成功建新，再删旧，
    ///     顺序不能反（反了会在弱信号下把人关在门外）。旧实现忽略这个参数，
    ///     改造变成了「再多一把仍能开门的旧码」。
    func addPassword(_ pwd: String, from: String, to: String,
                     owner: String? = nil, note: String? = nil,
                     replacingAlias: Int? = nil) async -> Result<Int, Error> {
        let mac = currentMac
        guard !mac.isEmpty else { return .failure(BLEErrorX.msg("还没有添加门锁")) }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            let alias = try await LockService.shared.pwdAdd(pwd: pwd, validFrom: from, validTo: to)
            // 下发成功才写台账 —— 失败不写，避免"本机以为加了、锁里没有"。
            // 2026-11-01（Round 237）：调用方（凭证工作室的成员行）传的是**成员名**，
            // 而台账 `owner` 在全仓其它路径（成员管理指派 / 成员合并 / 备份恢复）里存的都是**成员 id**。
            // 两种口径混进同一字段 ⇒ 工作室创建的凭证在列表里恒显示「未归属」（`ownerName` 按 id 查）。
            // 这里统一成 id：已经是 id 就原样保留，是名字就换成对应成员的 id。
            let ownerID: String? = {
                guard let owner, !owner.isEmpty else { return nil }
                if DB.member(owner) != nil { return owner }
                return DB.members().first { $0.name == owner }?.id
            }()
            var l = DB.ledger(mac)
            l.pwds.append(LedgerPwd(
                alias: alias, from: from, to: to, temp: false,
                at: Date().timeIntervalSince1970 * 1000,
                pwd: pwd, owner: ownerID, note: note ?? "密码 \(alias)"
            ))
            if let old = replacingAlias, old != alias {
                // 新码已落库 → 再删旧码。删失败不改台账（锁端仍有旧码，界面如实显示两条）。
                do {
                    try await LockService.shared.pwdDelete(old)
                    l.pwds.removeAll { $0.alias == old }
                } catch {
                    lastError = "新码已写入，但旧码（#\(old)）没能删除 —— 请到凭证详情再删一次。"
                }
            }
            DB.saveLedger(mac, l)
            reloadKeys(mac)
            return .success(alias)
        } catch {
            return .failure(error)
        }
    }

    /// 向导 / 临时码：cmd0A 真下发（起止时间区分临时档），成功才写台账并标记 temp。
    /// 成员向导第 4 步用它把「10 分钟临时码」真正落库（旧实现只 append 内存，刷新即消失）。
    func addTempCode(_ pwd: String, from: String, to: String,
                     owner: String, note: String) async -> Result<Int, Error> {
        let mac = currentMac
        guard !mac.isEmpty else { return .failure(BLEErrorX.msg("还没有添加门锁")) }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            let alias = try await LockService.shared.pwdAdd(pwd: pwd, validFrom: from, validTo: to)
            var l = DB.ledger(mac)
            l.pwds.append(LedgerPwd(
                alias: alias, from: from, to: to, temp: true,
                at: Date().timeIntervalSince1970 * 1000,
                pwd: pwd, owner: owner, note: note
            ))
            DB.saveLedger(mac, l)
            reloadKeys(mac)
            return .success(alias)
        } catch {
            return .failure(error)
        }
    }

    func deletePassword(alias: Int) async -> Result<Void, Error> {
        let mac = currentMac
        guard !mac.isEmpty else { return .failure(BLEErrorX.msg("还没有添加门锁")) }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            try await LockService.shared.pwdDelete(alias)
            // 锁端删成功才摘台账（同口径：失败不写，免得两边不一致）。
            var l = DB.ledger(mac)
            l.pwds.removeAll { $0.alias == alias }
            DB.saveLedger(mac, l)
            reloadKeys(mac)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    // MARK: - 凭证改期 / 删除（真下发）

    /// 改一条密码的生效窗口：0B（pwdExpire）真下发，成功才改本机台账。
    func setPasswordExpiry(alias: Int, from: String, to: String) async -> Result<Void, Error> {
        let mac = currentMac
        guard !mac.isEmpty else { return .failure(BLEErrorX.msg("还没有添加门锁")) }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            try await LockService.shared.pwdExpire(alias, from, to)
            var l = DB.ledger(mac)
            if let i = l.pwds.firstIndex(where: { $0.alias == alias }) {
                l.pwds[i].from = from; l.pwds[i].to = to
                DB.saveLedger(mac, l)
            }
            reloadKeys(mac)
            return .success(())
        } catch { return .failure(error) }
    }

    /// 删除一枚指纹：15（fpDelete）真下发，成功才摘台账。
    func deleteFingerprint(batch: Int) async -> Result<Void, Error> {
        let mac = currentMac
        guard !mac.isEmpty else { return .failure(BLEErrorX.msg("还没有添加门锁")) }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            try await LockService.shared.fpDelete(UInt32(batch))
            var l = DB.ledger(mac)
            l.fps.removeAll { $0.batch == batch }
            DB.saveLedger(mac, l)
            reloadKeys(mac)
            return .success(())
        } catch { return .failure(error) }
    }

    /// 指纹录入：cmd13 多帧（用户按 8 次）→ cmd14 确认窗口 → 成功才写台账。
    func enrollFingerprint(name: String, owner: String?, note: String,
                           onProgress: @escaping @MainActor (Int) -> Void) async -> Result<Int, Error> {
        let mac = currentMac
        guard !mac.isEmpty else { return .failure(BLEErrorX.msg("还没有添加门锁")) }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            var pressCount = 0
            let presses = try await LockService.shared.fpStart { p in
                if p.orderIdx != nil {
                    pressCount += 1
                    let n = pressCount
                    Task { @MainActor in onProgress(n) }
                }
            }
            guard let last = presses.last, let batch = last.batchNumber else {
                return .failure(BLEErrorX.msg("指纹录入没有拿到批次号 — 请重新录入"))
            }
            let df = DF.cached("yyyy-MM-dd HH:mm")
            let from = "2010-01-01 00:00"
            // 2026-11-01 修复：原来写 `addingTimeInterval(100 * 365 * 86400)` —— 用**固定 365 天/年**，
            // 而 100 年里有 24–25 个闰日，实际会差近一个月（`WeekCal.shifted` 的注释里已经写过
            // "别用 `addingTimeInterval` 数日历日"这条纪律，这里是同一类）。
            // 指纹有效期是"近似永久"，差一个月不影响行为，但**用日历加法才是对的写法**。
            let to = df.string(from: TimeFormat.calendar.date(byAdding: .year, value: 100, to: Date()) ?? Date())
            try await LockService.shared.fpConfirm(batch, validFrom: from, validTo: to)
            var l = DB.ledger(mac)
            l.fps.append(LedgerFp(batch: Int(batch),
                                  name: name.isEmpty ? "指纹 \(batch)" : name,
                                  at: Date().timeIntervalSince1970 * 1000,
                                  note: note, src: nil, owner: owner, isAlarm: false))
            DB.saveLedger(mac, l)
            reloadKeys(mac)
            return .success(Int(batch))
        } catch { return .failure(error) }
    }

    // MARK: - 校时 / 静音 / 安全模式

    func syncTime() async -> Result<(Int, Int), Error> {
        // E-07：currentMac 是计算属性，await 期间换锁会校到另一把锁。
        let mac = currentMac
        guard !mac.isEmpty else { return .failure(BLEErrorX.msg("还没有添加门锁")) }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            let r = try await LockService.shared.syncTime()
            // 2026-11-01 修复：原来是 `refreshStatus: false` —— 校时的意义正是"把锁钟改对"，
            // 而门页的「锁钟」读数取 `app.lastStatus.status.lockTime`（见 `DoorScreen:700`）。
            // 不重读 cmd03 ⇒ 校时成功后**门页仍显示校时前的锁钟**。
            // 校时是本段唯一一处"改了锁钟却不重读"的地方（其余写入路径都已刷新）。
            await reload(refreshStatus: true)
            return .success((r.before, r.after))
        } catch { return .failure(error) }
    }

    func setMuted(_ on: Bool) async -> Result<Void, Error> {
        let mac = currentMac   // E-07：静音位必须落在下发时那把锁上
        guard !mac.isEmpty else { return .failure(BLEErrorX.msg("还没有添加门锁")) }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            try await LockService.shared.setSilent(on)
            DB.store.set("kf_muted_" + mac, on)
            await refreshStatus()
            return .success(())
        } catch { return .failure(error) }
    }

    func setSafeMode(_ on: Bool) async -> Result<Void, Error> {
        let mac = currentMac   // E-07
        guard !mac.isEmpty else { return .failure(BLEErrorX.msg("还没有添加门锁")) }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            try await LockService.shared.setValidationMode(on)
            await refreshStatus()
            return .success(())
        } catch { return .failure(error) }
    }

    // MARK: - 工具

    /// "yyyy-MM-dd HH:mm" / "yyyy-MM-dd" → 毫秒 epoch。解析不了就 nil（不猜）。
    static func epochMillis(_ s: String) -> Int64? {
        guard !s.isEmpty else { return nil }
        for f in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let df = DF.cached(f)
            if let d = df.date(from: s) { return Int64(d.timeIntervalSince1970 * 1000) }
        }
        return nil
    }
}

// MARK: - 凭证的本机停用位（不删锁端）
//
// 原版「停用/恢复使用」是**本机状态**：锁端凭证仍在，只是本机台账把它标成停用并可恢复。
// ios27 旧实现误调 deletePassword/deleteFingerprint（真删锁端），用户点一下「停用」，
// 那枚密码就从锁里消失且不可逆 —— 这是 AUDIT-A §7-B8 的数据事故。
// 这里把停用位落成本机键（按锁分族），KeyDetail 只改它，锁端一条命令都不发。
enum CredentialLocalState {
    static func key(_ mac: String) -> String { "kf_v7_disabled_" + DB.normalizeMac(mac) }

    static func isDisabled(mac: String, id: String) -> Bool {
        let list = DB.store.get([String].self, key(mac)) ?? []
        return list.contains(id)
    }

    static func setDisabled(mac: String, id: String, _ off: Bool) {
        guard !mac.isEmpty, !id.isEmpty else { return }
        var list = DB.store.get([String].self, key(mac)) ?? []
        if off {
            if !list.contains(id) { list.append(id) }
        } else {
            list.removeAll { $0 == id }
        }
        if list.isEmpty { DB.store.remove(key(mac)) } else { DB.store.set(key(mac), list) }
    }
}

// MARK: - 数据模型（界面投影；由 AppModel.reload 从 Engine 构建）

struct LockSummary: Identifiable, Hashable {
    let id: String
    let name: String
    let model: String
    let battery: Int          // -1 = 未知
    let signal: Int           // 0 = 未知
    let firmware: String
    let keyCount: Int
    let isConnected: Bool
    let safeMode: Bool
    let muted: Bool
}

struct KeyItem: Identifiable, Hashable {
    enum Kind: String, CaseIterable {
        case password = "密码"
        case fingerprint = "指纹"
        case temp = "临时码"
        case mobile = "手机钥匙"
    }
    let id: String            // "pwd:<alias>" / "fp:<batch>" / "mkey:<uuid>"
    let kind: Kind
    let name: String
    let owner: String?
    let code: String?
    /// 到期时刻（毫秒 epoch）。nil = 永久。
    let expiresAt: Int64?
    /// 创建时刻（毫秒 epoch）。0 = 未知（旧数据 / 手机钥匙等本身没有这个概念）。
    /// 供 `CredentialOrg.pwdAgeDays` 显示「已使用 N 天」（327 那一族里唯一低成本的接线点）。
    var createdAt: Double = 0
    let disabled: Bool
}

struct MemberCard: Identifiable, Hashable {
    enum Role: String, CaseIterable {
        case owner = "管理员"
        case member = "成员"
        case guest = "访客"
    }
    let id: String
    let name: String
    let role: Role
    let keyCount: Int
    let lastActiveAt: Int64?
    let archived: Bool
}

// MARK: - EngineHost 桥接
//
// 引擎只声明它需要什么（见 Engine/EngineHost.swift），这里把界面状态喂给它。
// 这是**唯一**允许 Engine 与界面接触的地方。
extension AppModel: EngineHost {
    var currentKeychain: Keychain? {
        let mac = currentMac
        return mac.isEmpty ? nil : DB.keychain(mac)
    }

    var lockLink: LockService { LockService.shared }

    /// 把「点通知」翻成一次界面跳转（CredentialOrg.applyNotification 的落地端）。
    func requestCredentialRoute(alias: Int?) {
        router?.request(.key(id: alias.map { "pwd:\($0)" } ?? ""))
    }
}