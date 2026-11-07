// AppModel.swift —— 应用级状态与真实引擎动作。
//
// 纪律：
//   · 页面只读 AppModel 的投影；写动作一律是 AppModel 上的 async 方法。
//   · 所有长任务都先把 `busy` 置上、结束时清掉；失败写 `lastError`（页面就地展示）。
//   · 钥匙串、台账、日志缓存三张表都来自 Engine，不在这里二次存储。
import SwiftUI

@MainActor
@Observable
final class AppModel {
    // MARK: - 数据投影

    var locks: [LockSummary] = []
    var lock: LockSummary?
    var credentials: [Credential] = []
    var members: [MemberCard] = []
    var events: [EventItem] = []
    var lastStatus: StatusSnapshot?
    var ledgerCorrupt = false

    // MARK: - 门禁

    var unlocked: Bool = !DB.hasPasscode()
    var decoy = false
    var trial = TrialGuard.isOn

    // MARK: - 开锁

    var phase: UnlockPhase = .idle
    var lastUnlockAt: Int64?
    var autoLockLeft: Int?
    var lastActionAt: Int64?
    var gatePassedAt: Int64?

    // MARK: - 通用

    var busy: String?
    var lastError: String?
    var overrideMac: String?
    var readLogsAt: Int64?
    /// 读日志的实时进度（F42/F45）。nil = 没在读。
    var logProgress: TaskProgress?
    /// 首屏还在读（骨架屏用，F32）。
    var isLoading: Bool = false
    /// 当前读日志的任务句柄 —— 取消长任务用（F42）。
    @ObservationIgnored private var logTask: Task<Void, Never>?
    /// 上一次开锁失败的**结构化**描述（F15 诊断卡用）。nil = 没失败过。
    var lastUnlockFailure: ScreenFailure?
    /// 上一次开锁用的是哪一类凭证（F16 回执卡用）。
    var lastUnlockCredential: String = ""
    /// 上一次动作**部分成功**时的说明（F43）。nil = 没有部分成功。
    /// 「新码写进去了、旧码没删掉」这种事不能混进「成功」里 ——
    /// 用户会以为整件事都成了，于是旧的那枚密码继续有效。
    var lastPartial: ScreenFailure?

    /// 最近一次「从门锁读日志」的分页读数 —— **只读展示**，不参与任何逻辑（诊断页用）。
    /// 真机审计（2026-11-07）：锁端日志约 2000 条滚存，单次读取的 20 页上限
    /// 一次只取最近 ~200 条；这些读数就是让用户自己看清"取了多少、还剩多少"。
    struct LogReadStats {
        var pages = 0          // 实际翻了几页
        var read = 0           // 实际写入缓存的条数
        var remaining: Int?    // 锁端剩余的条数（未触上限且锁有上报时）
        var capped = false     // 是否撞上 20 页上限（= 下次点击会继续往更早读）
        var lowest: UInt32?     // 本轮后已覆盖的最低序号（nil = 还没读过）
        var done = false       // 是否已把锁端历史读完（锚点已收）
        var at: Int64 = 0      // 读取时刻（epoch 毫秒）
    }
    /// 只读读数：最近一次 readLogs 的分页统计。
    private(set) var lastLogRead: LogReadStats?

    @ObservationIgnored private weak var router: Router?
    @ObservationIgnored private var autoLockTask: Task<Void, Never>?
    /// 自动上锁倒计时的代次，防止被取消的旧任务覆写新任务的状态。
    @ObservationIgnored private var autoLockGen = 0
    @ObservationIgnored private var activitySignature = ""
    /// 上一次载入的是哪把锁 —— 换锁时据此清缓存（B46）。
    @ObservationIgnored private var loadedMac = ""
    /// 活跃度缓存的**结果**。只留签名不留结果，缓存等于没做 ——
    /// 同一次刷新里第二次取成员卡片时拿到的是空 bundle，名册永远显示「还没开过门」。
    @ObservationIgnored private var activityCache: MemberHub.ActivityBundle?
    /// 上一次落到数据层的空壳态。用来判断「刚刚进/出空壳」——
    /// 只有**真的变了**的那一次才做进/出的副作用（重载会被频繁调用）。
    @ObservationIgnored private var decoyApplied = false

    let link = LinkSenseModel.shared

    // MARK: - 当前锁

    var currentMac: String {
        if let overrideMac, DB.keychainForUnlock(overrideMac) != nil { return overrideMac }
        if let lock { return lock.id }
        let def = LockArchive.defaultMac
        if !def.isEmpty, DB.keychainForUnlock(def) != nil { return def }
        return DB.preferredMac()
    }

    func attach(router: Router) { self.router = router }

    // MARK: - 载入

    func reload(refreshStatus: Bool = false) async {
        // 骨架屏只在**首屏**出现（F32）：之后的刷新不该把整页换成骨架。
        if !isLoading { isLoading = true }
        let mac = currentMac
        // 空壳标志必须**先**立起来，再去读任何数据 ——
        // 引擎层的 keychains()/ledger()/readLogs() 都靠这个标志返回空集；
        // 晚一步设置，锁名就已经先漏出去了。
        applyDecoyState()
        locks = DB.keychains().map(makeLock)

        guard !mac.isEmpty, let kc = DB.keychainForUnlock(mac) else {
            lock = nil
            credentials = []
            events = []
            members = reloadMemberCards()
            lastStatus = nil
            isLoading = false
            return
        }

        if refreshStatus, LockService.shared.connectedMAC == mac {
            if let st = try? await LockService.shared.getStatus(mac: mac) {
                DB.writeStatus(mac, st)
            }
            // await 期间用户可能已经在「我的锁」里换了一把锁 ——
            // 这时再把旧 mac 的投影装回去，今日页会显示上一把锁的读数，
            // 而 `currentMac` 已经指向新锁，直到下一次刷新才自愈。
            guard mac == currentMac else { return }
        }

        lock = makeLock(kc)
        isLoading = false
        // B46：换了一把锁 ⇒ 上一把锁的读数/活跃度/信号历史全部作废。
        if loadedMac != mac {
            loadedMac = mac
            CachePolicy.apply(.lockSwitched, mac: mac)
        }
        // 空壳里 `locks` 只留当前这一把：设置页的「N 把锁」要与今日页看得见的那把一致。
        // 真实锁清单（哪怕只有一把）属于被隐藏的信息；`lock` 本身按设计保留，门照样能开。
        if DB.isDecoy {
            locks = lock.map { [$0] } ?? []
        }
        // 空壳里不把真实快照装进界面投影：门锁信息页的「锁钟」就是从这里读的，
        // 而其余读数都被抹平，只剩它照实显示，等于告诉对方「这台手机真的连过锁」。
        lastStatus = DB.isDecoy ? nil : DB.get(StatusSnapshot.self, "kf_snap_" + mac)
        link.update(mac: mac)

        // 顺序有讲究：
        //   · 记录先刷 —— 成员活跃度的缓存签名取的是 `events.count`，
        //     记录没更新就重算成员，签名是旧的，缓存会一直复用旧结果；
        //   · 凭证再刷 —— 它内部会用刚算好的成员名做归属，并把成员卡片一起重算。
        reloadEvents(mac)
        reloadCredentials(mac)
        readLogsAt = RecordsSource.lastSync(mac: mac)
    }

    /// 空壳（胁迫码）开关的**唯一**入口。进/出空壳的副作用都收在这里。
    ///
    /// 进空壳：数据层整体返回空集、已排的到期提醒整族清掉、剪贴板清空。
    /// 出空壳：到期提醒**必须重建** —— 进空壳时清掉了，不重建的话提醒永久消失，
    /// 而界面仍显示「已排程」；自动开门的轮询也要恢复，否则用户以为它坏了。
    private func applyDecoyState() {
        let on = decoy
        // **先落数据层，再判断要不要做副作用。**
        //
        // 原先这里先 `guard on != decoyApplied else { return }` 才写 DB —— 而
        // `AppLock.lock()`（回前台超 30 秒）会直接把 DB 的空壳标志复位，AppModel
        // 却把 `decoyApplied` 留在 true。此时再次输入胁迫码：on 与缓存相等 ⇒ 直接
        // return ⇒ DB 从未重新置 true，随后的 reload 会把真实锁、凭证、成员全部读出来。
        // 空壳在最需要它的第二次进入时失效。标志写入必须无条件、幂等。
        DB.setDecoy(on)
        guard on != decoyApplied else { return }
        decoyApplied = on
        if on {
            CredentialOrg.cancelAllForDecoy()
        } else {
            CredentialOrg.resetDecoyNotificationGuard()
            CredentialOrg.rescheduleAllAlerts()
            AutoOpenController.shared.onForeground(mac: currentMac)
        }
    }

    func reloadCredentials(_ mac: String? = nil) {
        let m = mac ?? currentMac
        guard !m.isEmpty else { credentials = []; ledgerCorrupt = false; return }
        // 空壳里台账被过滤成空表，但 `isLedgerCorrupt` 读的是真实存储。
        // 照实显示会让「通行」页冒出「台账读取异常」—— 等于告诉对方这台手机
        // 的存储出过问题，与「空壳里什么都没有」的假象冲突。
        ledgerCorrupt = DB.isDecoy ? false : DB.isLedgerCorrupt(m)
        let ledger = DB.ledger(m)

        var out: [Credential] = []
        for p in ledger.pwds {
            let ownerName = name(forOwner: p.owner)
            out.append(Credential(
                id: "pwd:\(p.alias)",
                kind: p.temp ? .temp : .password,
                name: p.note.isEmpty ? (p.temp ? "临时码 \(p.alias)" : "密码 \(p.alias)") : p.note,
                ownerID: p.owner,
                ownerName: ownerName,
                masked: String(repeating: "•", count: max(4, p.pwd?.count ?? 4)),
                expiresAt: Self.expiry(p.to),
                validFrom: Self.millis(p.from),
                createdAt: Self.safeMillis(p.at),
                disabled: CredentialLocalState.isDisabled(mac: m, id: "pwd:\(p.alias)"),
                alias: p.alias,
                batch: nil,
                mobileID: nil,
                note: p.note
            ))
        }
        for f in ledger.fps {
            out.append(Credential(
                id: "fp:\(f.batch)",
                kind: .fingerprint,
                name: f.name.isEmpty ? "指纹 \(f.batch)" : f.name,
                ownerID: f.owner,
                ownerName: name(forOwner: f.owner),
                masked: nil,
                expiresAt: nil,
                validFrom: nil,
                createdAt: Self.safeMillis(f.at),
                disabled: CredentialLocalState.isDisabled(mac: m, id: "fp:\(f.batch)"),
                alias: nil,
                batch: f.batch,
                mobileID: nil,
                note: f.note
            ))
        }
        for k in MobileKeyService.list(m) {
            out.append(Credential(
                id: "mkey:\(k.id)",
                kind: .mobile,
                name: k.memberName.isEmpty ? "手机钥匙" : "\(k.memberName) 的手机钥匙",
                ownerID: k.memberID.isEmpty ? nil : k.memberID,
                ownerName: k.memberName,
                masked: "•••• \(String(k.pin.suffix(2)))",
                expiresAt: (k.forever || k.validTo.hasPrefix("2118")) ? nil : Self.millis(k.validTo),
                validFrom: nil,
                createdAt: Self.safeMillis(k.at),
                disabled: false,
                alias: nil,
                batch: nil,
                mobileID: k.id,
                note: ""
            ))
        }
        credentials = out
        members = reloadMemberCards()
    }

    func reloadEvents(_ mac: String? = nil) {
        let m = mac ?? currentMac
        guard !m.isEmpty, let kc = DB.keychainForUnlock(m) else { events = []; return }
        let name = kc.name.isEmpty ? (kc.pidName.isEmpty ? "我的门锁" : kc.pidName) : kc.name
        // 成员名直接从数据层取，不走成员卡片投影 ——
        // 成员卡片反过来要靠记录算活跃度，两边互相依赖会绕成环。
        var names: [String: String] = [:]
        for member in DB.members() { names[member.id] = member.name }
        // B43：内存里的事件投影有上限 —— 锁端能存两千条，全摆进内存会拖垮滚动。
        // 盘上仍是全量（搜索与洞察不受影响），这里只是**不进内存**。
        events = MemoryCap.trim(RecordsSource.load(mac: m, lockName: name, memberNames: names))
    }

    /// 成员卡片。活跃度（最近一次开门）来自 `StatsWorker`（B41）。
    ///
    /// 活跃度是 O(锁 × 日志) 的重活 —— 现在它跑在 **actor** 里，主线程只拿结果。
    /// 刚进页面时结果还没回来，这一版会先给「还没有记录」的空卡片，
    /// 结果回来后再刷一次 —— 宁可晚一拍，不要卡住首屏。
    private func reloadMemberCards() -> [MemberCard] {
        let ext = MemberHub.allExt()
        let raw = DB.members()
        // 只按 `events.count` 做签名会漏掉「条数不变、内容/时间变了」的刷新
        // （校时改写锁钟时间、刷新替换了同一批记录）：成员卡片会一直复用
        // 旧的「最近 N 天前」。把首尾时间也纳入签名。
        let signature = raw.map(\.id).joined(separator: "|")
            + "#\(events.count)#\(events.first?.time ?? 0)#\(events.last?.time ?? 0)"
            + "#\(MemberActivityCache.generation)"
        if signature != activitySignature {
            activitySignature = signature
            activityCache = nil
            // B41：重算挪进 actor，主线程不阻塞。
            refreshActivity(ids: raw.map(\.id), signature: signature)
        }
        let activity = activityCache ?? MemberHub.ActivityBundle()
        return raw.map { m in
            let e = ext[m.id] ?? MemberExt()
            let role = MemberRole.parse(e.role)
            let count = credentials.reduce(0) { partial, c in
                partial + (CredentialOrg.ownerMatches(c.ownerID, memberID: m.id, memberName: m.name) ? 1 : 0)
            }
            let last = activity.table[m.id]?.lastUnix ?? 0
            return MemberCard(
                id: m.id,
                name: m.name.isEmpty ? "未命名" : m.name,
                role: role,
                colorHex: m.color,
                groupTag: e.groupTag,
                keyCount: count,
                lastActiveAt: last > 0 ? last * 1000 : nil,
                archived: e.archived,
                note: e.note
            )
        }
    }

    /// 在 actor 里重算活跃度，回来后刷新成员卡片（B41）。
    private func refreshActivity(ids: [String], signature: String) {
        let generation = MemberActivityCache.generation
        Task { @MainActor in
            let bundle = await StatsWorker.shared.activity(ids: ids, signature: signature)
            // 期间缓存被作废（换锁 / 恢复备份）⇒ 这一份结果已经过期，丢掉。
            guard MemberActivityCache.generation == generation else { return }
            activityCache = bundle
            members = reloadMemberCards()
        }
    }

    private func makeLock(_ kc: Keychain) -> LockSummary {
        let snap = DB.readStatus(kc.mac)
        let name = kc.name.isEmpty ? (kc.pidName.isEmpty ? "我的门锁" : kc.pidName) : kc.name
        let ledger = DB.ledger(kc.mac)
        // 空壳里不读锁的档案备注：分组/隐藏/上次信号都是这台手机攒下来的使用痕迹。
        // 锁名留着（胁迫码的前提是「门照样能开」，总得有个称呼），
        // 型号/电量/固件/连接态在下面全部抹平 —— 那些是真实硬件读数。
        let meta = DB.isDecoy ? LockMeta() : LockArchive.meta(kc.mac)
        return LockSummary(
            id: kc.mac,
            name: name,
            // 型号 / 电量 / 固件都是"这台锁现在是什么样"的真实读数。空壳里全部抹平：
            // 门仍然能开，但胁迫者看不到任何可以拿去做判断的硬件信息。
            model: DB.isDecoy ? "未知型号" : (kc.pidName.isEmpty ? "未知型号" : kc.pidName),
            pid: DB.isDecoy ? 0 : kc.pid,
            battery: DB.isDecoy ? -1 : (snap?.powerLevel ?? -1),
            signal: DB.isDecoy ? 0 : LinkSenseModel.level(LinkSenseModel.savedRSSI(kc.mac)),
            firmware: DB.isDecoy ? "" : (snap?.firmware ?? kc.fw),
            keyCount: ledger.pwds.count + ledger.fps.count + MobileKeyService.list(kc.mac).count,
            isConnected: !DB.isDecoy && LockService.shared.connectedMAC == kc.mac,
            safeMode: !DB.isDecoy && (snap?.verifyMode ?? 0) != 0,
            muted: !DB.isDecoy && DB.store.getBool("kf_muted_" + kc.mac),
            hidden: !DB.isDecoy && LockArchive.isHidden(kc.mac),
            group: DB.isDecoy ? "" : meta.grp
        )
    }

    func name(forOwner owner: String?) -> String? {
        guard let owner, !owner.isEmpty else { return nil }
        if let m = DB.member(owner) { return m.name }
        if let hit = members.first(where: { $0.name == owner }) { return hit.name }
        return owner
    }

    // MARK: - 门禁

    func noteGate(outcome: AppLock.Outcome) {
        switch outcome {
        case .success:
            unlocked = true
            decoy = false
        case .decoy:
            unlocked = true
            decoy = true
            // 空壳必须**立刻**生效。等 reload() 跑完的那一拍里，界面上还是真实凭证 ——
            // 胁迫者正盯着这一屏，恰好是空壳模式最不该发生的暴露。
            clearProjectionsForDecoy()
            // 锁屏前停在哪个详情页，解锁后就还在哪一页；那些页面的 `@State` 里留着
            // 上一会话的真实数据。回根是唯一不依赖每个页面自觉清场的做法。
            router?.resetForDecoy()
        default:
            return
        }
        applyDecoyState()
        gatePassedAt = Int64(Date().timeIntervalSince1970 * 1000)
        Task { await reload(refreshStatus: false) }
    }

    /// 进空壳那一刻先把界面投影里的**用户数据**全部清空。
    ///
    /// 数据层由 `applyDecoyState()` 一并关上；这里先清界面投影，
    /// 是因为两者之间隔着一次 `Task` —— 那一拍里胁迫者正盯着这一屏。
    ///
    /// `lock`（当前这把锁）**留着**：胁迫码的前提就是「门照样能开」，
    /// 清掉它就等于把唯一的目标（开锁）也藏起来了。
    /// 锁名不算敏感数据 —— 引擎层藏的是「有几把锁」这个清单，不是你正站在哪扇门前。
    /// `keyCount` 在空壳里本来就是 0（台账与手机钥匙都被过滤成空）。
    private func clearProjectionsForDecoy() {
        locks = []
        credentials = []
        members = []
        events = []
        ledgerCorrupt = false
        // `lock` 本身留着（门照样能开），但**不能留上一会话的真实投影**：
        // 它的电量 / 固件 / 连接态来自真实锁，而把这三个字段遮平的 `makeLock`
        // 要等异步 reload 才跑。胁迫码解锁后的第一帧足以把它们印在今日页上。
        // 这里按同一口径先做一份空壳投影，reload 落地后再由 makeLock 覆盖。
        lock = lock.map {
            LockSummary(id: $0.id, name: $0.name, model: "未知型号", pid: 0,
                        battery: -1, signal: 0, firmware: "", keyCount: 0,
                        isConnected: false, safeMode: false, muted: false,
                        hidden: false, group: "")
        }
        // 上一会话的残留也要清：失败文案里可能带着锁名/MAC，`phase` 可能停在
        // 「门开了」，`lastStatus` 是上一次真实读数。这些都会在今日页立刻显示。
        lastError = nil
        busy = nil
        phase = .idle
        lastStatus = nil
        readLogsAt = nil
        resetUnlock()
        lastUnlockAt = nil
        link.clearForDecoy()
        // 剪贴板也要清：进空壳前可能刚复制过一枚动态码（`Clip.set` 有 90 秒有效期），
        // 而空壳里没有任何界面会去动剪贴板 —— 胁迫者长按粘贴就能拿到。
        Clip.clear()
    }

    func lockApp() {
        AppLock.shared.lock()
        unlocked = false
        decoy = false
        applyDecoyState()
        DB.dropKeychainCache()
        LockService.shared.disconnect()
    }

    // MARK: - 开锁

    func unlock() async {
        guard !phase.isBusy else { return }
        // 上锁/进空壳之后，进行中的任务不能再把门打开 —— 这是门禁最重要的一条。
        guard AppLock.shared.unlocked else { phase = .idle; return }
        let mac = currentMac
        guard !mac.isEmpty else { phase = .failed("还没有添加门锁"); return }

        lastError = nil
        // 触感只在**结果**上给：按下一下，成功或失败各一下。
        // （早先挂在相位的 `.sensoryFeedback` 上，连上／下发／等回执会连着震四五下。）
        Haptics.impact()
        phase = .reaching
        // 自动开门可能正为同一把锁下发 04：告诉它「用户自己按了」，并等它收尾。
        // 两条开锁命令同时走一条 BLE 链路时，只有一条能挂上 waiter —— 后到的
        // 必然报「已有命令在等待响应」，而用户只是按了一下开锁。
        AutoOpenController.shared.noteManualUnlock()
        var waitedTicks = 0
        while AutoOpenController.shared.isDispatching, waitedTicks < 40 {
            try? await Task.sleep(for: .milliseconds(100))
            waitedTicks += 1
        }
        // 读门锁日志（最多 20 页）也走同一条 BLE 链路：它可能正占着 waiter。
        // 此时直接下发 04，只会在 120ms 后撞上「已有命令在等待响应」——
        // 用户看到的是「门没打开」，而其实锁好好的，只是 App 自己把两条命令叠在了一起。
        // 等它读完（最多 6 秒；期间镜头停在「连接中」），再把开锁交给链路。
        if busy != nil {
            var busyTicks = 0
            while busy != nil, busyTicks < 60 {
                try? await Task.sleep(for: .milliseconds(100))
                busyTicks += 1
            }
            if busy != nil {
                phase = .failed("门锁正在读取记录，请稍后再开锁。")
                Haptics.notify(.error)
                return
            }
        }
        guard AppLock.shared.unlocked else { phase = .idle; return }
        // 自动重试只覆盖**连不上**这一段：命令没发出去，重发是安全的。
        // 命令已经发出、只是没等到回执时**不重试** ——
        // 引擎层对开锁命令刻意不重试（锁可能已经执行了），这一层不能把它绕过去。
        let attempts = SettingsStore.shared.autoRetry ? 2 : 1
        for attempt in 1 ... attempts {
            phase = .reaching
            do {
                try await LockService.shared.ensureConnected(mac: mac)
            } catch {
                let raw = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                // 空壳里不显示带锁名/MAC 的真实链路错误：这些字段刚被
                // `clearProjectionsForDecoy` 刻意清掉，失败文案不能又把它们带回来。
                let msg = DB.isDecoy ? "没能打开门锁，请再试一次。" : raw
                guard attempt < attempts else {
                    phase = .failed("连不上门锁：\(msg)")
                    lastError = msg
                    lastUnlockFailure = ErrorCopy.failure(error)
                    LinkQuality.noteFailure(mac, msg)
                    Haptics.notify(.error)
                    return
                }
                // 刚失败就立刻重连多半还是失败：让链路缓一下再试。
                try? await Task.sleep(for: .milliseconds(700))
                continue
            }
            // 连接期间可能已经退后台超时上锁；此时绝不能再把命令发出去。
            guard AppLock.shared.unlocked else { phase = .idle; return }
            phase = .sending
            // Engine 的 `unlock` 是「写帧 + 等回执」一次调用，界面看不到中间那一步。
            // 所以把 `.waiting` 放在 await **之前**：环停在 0.86 等待的，是真的在等锁回执；
            // 若放在之后，「等回执」只会闪一帧，而「已下发」会陪着用户等满整个超时。
            phase = .waiting
            sampleRSSI()
            do {
                let rc = try await LockService.shared.unlock(mac: mac, pinDec: chosenPin(mac))
                if rc == 0 {
                    phase = .opened
                    lastUnlockFailure = nil
                    LinkQuality.noteConnect(mac)
                    lastUnlockCredential = chosenPin(mac) == nil ? "本机钥匙里的一枚" : "你选的那枚凭证"
                    Haptics.notify(.success)
                    let now = Int64(Date().timeIntervalSince1970 * 1000)
                    lastUnlockAt = now
                    lastActionAt = now
                    // 空壳里的开锁**只开门，不记账**：终身开锁次数与自动开门的
                    // 上次开门时间戳都会保留到退出空壳之后，成为「这次被胁迫」
                    // 的持久痕迹。胁迫者看不到，但数据库里多了一条真实记录。
                    if !DB.isDecoy {
                        Milestones.recordUnlockSuccess()
                        // 自动开门的冷却承诺是「距离上次**开门**超过 6 秒」——
                        // 手动开的锁也算一次开门，否则手动开完立刻走开再靠近，
                        // 2 秒后就能被自动开门，与设置页写的 6 秒不符。
                        AutoOpen.setPersistedLastDispatch(mac, Date().timeIntervalSince1970)
                    }
                    startAutoLockCountdown()
                    try? await Task.sleep(for: .milliseconds(900))
                    if phase == .opened { phase = .idle }
                    await reload(refreshStatus: false)
                } else if rc == 22 {
                    phase = .failed("门锁要求第二种验证方式")
                    lastUnlockFailure = ErrorCopy.failure(rc: rc)
                    Haptics.notify(.error)
                } else {
                    phase = .failed(StatusParser.rcFriendly(rc))
                    lastUnlockFailure = ErrorCopy.failure(rc: rc)
                    Haptics.notify(.error)
                }
            } catch {
                let raw = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                let msg = DB.isDecoy ? "没能打开门锁，请再试一次。" : raw
                phase = .failed(msg)
                lastError = msg
                // 结构化失败（F15）：诊断卡要靠它分清「连不上」与「凭证被拒」。
                lastUnlockFailure = ErrorCopy.failure(error, cmd: 0x04)
                Haptics.notify(.error)
            }
            return
        }
    }

    func resetUnlock() {
        autoLockGen += 1
        autoLockTask?.cancel()
        autoLockTask = nil
        autoLockLeft = nil
        if !phase.isBusy { phase = .idle }
    }

    private func chosenPin(_ mac: String) -> String? {
        let idx = DB.store.getInt("kf_chosen_pin_" + mac, -1)
        guard idx >= 0, let kc = DB.keychain(mac), idx < kc.pins.count else { return nil }
        return kc.pins[idx]
    }

    private func startAutoLockCountdown() {
        // 代次守卫：`cancel()` 只是请求取消，旧任务可能已经睡到最后一拍，
        // 醒来后仍会把新任务的 `autoLockLeft` 覆写成 nil（倒计时闪一下消失）。
        autoLockGen += 1
        let generation = autoLockGen
        autoLockTask?.cancel()
        // 空壳里不读真实的自动上锁档位：设置页已按默认 6 秒伪造，
        // 今日页的「约 N 秒后自动上锁」不能把主人设过的 2/3/4/5 秒如实报出来。
        let interval = DB.isDecoy ? 6 : (DB.tailgate(currentMac)?.interval ?? 6)
        let total = max(2, interval + 1)
        autoLockLeft = total
        autoLockTask = Task { @MainActor in
            for left in stride(from: total, through: 1, by: -1) {
                if Task.isCancelled || generation != autoLockGen { return }
                autoLockLeft = left
                try? await Task.sleep(for: .seconds(1))
            }
            if generation == autoLockGen { autoLockLeft = nil }
        }
    }

    // MARK: - 状态 / 日志

    /// 连上之后读一次 RSSI。
    ///
    /// 「信号」那一栏此前永远显示「不可测」：`LinkSenseModel.readRSSI()` 全 App 零调用点，
    /// `kf_linkrssi_<mac>` 从来没被写过 —— 读数只可能停在「装这个 App 之前就有的值」。
    /// 系统 `readRSSI` 不占协议往返，代价可以忽略。
    private func sampleRSSI() {
        let mac = currentMac
        guard !mac.isEmpty else { return }
        link.update(mac: mac)
        link.readRSSI()
    }

    func refreshStatus() async {
        let mac = currentMac
        guard !mac.isEmpty else { return }
        // 空壳里不读锁的实时状态：这是一条真实 BLE 命令，读回来的真实读数还会
        // 经 `DB.writeStatus` 写进本机快照（设置页「维护与诊断」整页藏起来也是这个理由）。
        guard !DB.isDecoy else { return }
        lastError = nil
        do {
            // B20：同一把锁的并发状态读取**合并成一次** —— BLE 链路一次只挂得下一个
            // waiter，两次并发读必然有一个超时（用户连点两次「刷新」就是这种情况）。
            let stOpt: LockStatus? = await RequestCoalescer.shared.run("status:" + mac) {
                try? await LockService.shared.getStatus(mac: mac)
            }
            guard let st = stOpt else {
                // 合并器里读失败 = 真的读失败（错误在合并前就抛了）。
                throw BLEErrorX.msg("没读到门锁状态")
            }
            DB.writeStatus(mac, st)
            sampleRSSI()
            // B74：每次读到锁钟都记一次偏差 —— 漂移是趋势，要靠多次采样才看得出来。
            ClockDrift.note(mac: mac)
            await reload(refreshStatus: false)
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    @discardableResult
    func readLogs() async -> (read: Int, remaining: Int?)? {
        let mac = currentMac
        // `busy` 由 defer 在函数返回前清掉，调用方事后检查它永远拿到 nil。
        // 把「忙」写成一条明确的结果文案，两个入口才能区分失败与并发拒绝。
        guard busy == nil else {
            lastError = "门锁正忙，稍后再读。"
            return nil
        }
        // 开锁命令在飞（或自动开门正在下发）时同样不能读：BLE 链路只挂得下一个 waiter，
        // 读日志的 16 命令会撞上「已有命令在等待响应」。等门锁空下来再读，比读失败更诚实。
        guard !phase.isBusy, !AutoOpenController.shared.isDispatching else {
            lastError = "门锁正忙，稍后再读。"
            return nil
        }
        // 没有锁时要说清楚：这里原先直接 return nil，界面上一点动静都没有 ——
        // 用户点了「从门锁读一次」，卡片回到原样，像是什么都没发生。
        guard !mac.isEmpty else {
            lastError = "还没有绑定门锁 —— 先配一把锁，再回来读记录。"
            return nil
        }
        // 空壳里不读锁内日志：读回来也只会被过滤成空表，界面上是"读了个寂寞"，
        // 而锁端已经真的被翻了一遍。给一句与其它写入拒绝同一口径的中性话。
        guard !DB.isDecoy else {
            lastError = "当前无法读取，请稍后再试。"
            return nil
        }
        busy = "正在读门锁记录…"
        defer { busy = nil }
        lastError = nil
        // 进度（F42/F45）：显示「第 N/20 页、已读 M 条」——
        // 没有它，一次 20 页的读取在界面上就是「卡住了十几秒」。
        logProgress = TaskProgress(title: "正在读门锁记录",
                                   detail: "第 1 / \(LogSync.maxPages) 页",
                                   fraction: 0,
                                   total: LogSync.maxPages)
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            sampleRSSI()
            // 断点续读 + 自适应分页 + 后台补读都在 LogSync 里（B39/B42）。
            // 放进子 Task：这样「取消」能真的打断它，而不是只把进度条藏起来。
            let task = Task { await LogSync.sync(mac: mac) { p in
                Task { @MainActor in
                    self.logProgress?.update("第 \(p.page) / \(p.pages) 页 · 已读 \(p.read) 条",
                                            step: p.page,
                                            fraction: Double(p.page) / Double(max(p.pages, 1)))
                }
            } }
            logTask = task
            let result = await task.value
            logTask = nil
            logProgress = nil

            let capped = result.capped
            let remaining = result.remaining
            let lowest = result.lowest
            // 只读读数（诊断页展示用）：分页统计在这里落一笔，不参与上面的任何判停逻辑。
            lastLogRead = LogReadStats(
                pages: result.pages,
                read: result.read,
                remaining: remaining,
                capped: capped,
                lowest: lowest,
                done: result.done,
                at: Int64(Date().timeIntervalSince1970 * 1000))
            await reload(refreshStatus: false)

            if result.interrupted {
                // 部分成功（F43）：读到的已经落盘并留了锚点，下一轮从断点继续。
                let why = result.message ?? "连接中断"
                lastError = "\(why)（已保存本次读到的 \(result.read) 条；再读一次会从断点继续）"
                return (read: result.read, remaining: remaining)
            }
            // 撞上限 ⇒ 排一轮后台补读（B39）：连着的时候自动往更早翻，
            // 不必等用户再点一次。
            if capped { LogSync.scheduleBackground(mac) }
            return (read: result.read, remaining: remaining)
        } catch {
            logProgress = nil
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    /// 取消正在进行的读日志（F42）。已读到的部分仍然落盘 —— 下次从断点继续。
    func cancelLogRead() {
        logTask?.cancel()
        logTask = nil
        logProgress = nil
        busy = nil
        lastError = "已取消读取。已读到的部分保留，下次从断点继续。"
    }

    // MARK: - 凭证写入

    private func memberID(for owner: String?) -> String? {
        guard let owner, !owner.isEmpty else { return nil }
        if DB.member(owner) != nil { return owner }
        return DB.members().first { $0.name == owner }?.id
    }

    /// 台账不可解时，凭证写操作一律在**下发前**拒绝。
    ///
    /// `DB.saveLedger` 在台账损坏时会静默丢弃这次写入，而锁端那一帧已经真的执行了 ——
    /// 旧实现随后照样 `return .success`：界面说「已写入」，列表里却永远没有这一条；
    /// 用户再操作一次，锁里就多出第二条同样口令。宁可在动手前把话说清楚。
    private func ledgerCorruptRefusal(_ mac: String) -> Error? {
        guard DB.isLedgerCorrupt(mac) else { return nil }
        return BLEErrorX.msg("本机台账读取异常，为避免覆盖已有记录，这次没有写入门锁。")
    }

    func addPassword(_ pwd: String, from: String, to: String,
                     owner: String?, note: String?,
                     replacing alias: Int? = nil) async -> Result<Int, Error> {
        let mac = currentMac
        guard !mac.isEmpty else { return .failure(BLEErrorX.msg("还没有添加门锁")) }
        guard !DB.isDecoy else { return .failure(BLEErrorX.msg("当前无法保存，请稍后再试")) }
        if let refusal = ledgerCorruptRefusal(mac) { return .failure(refusal) }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            let newAlias = try await LockService.shared.pwdAdd(pwd: pwd, validFrom: from, validTo: to)
            var ledger = DB.ledger(mac)
            ledger.pwds.append(LedgerPwd(alias: newAlias, from: from, to: to, temp: false,
                                         at: Date().timeIntervalSince1970 * 1000,
                                         pwd: pwd, owner: memberID(for: owner),
                                         note: note ?? "密码 \(newAlias)"))
            if let alias, alias != newAlias {
                do {
                    try await LockService.shared.pwdDelete(alias)
                    ledger.pwds.removeAll { $0.alias == alias }
                } catch {
                    lastError = "新码已写入，但旧码（#\(alias)）没能删除。"
                    lastPartial = ScreenFailure(kind: .lockRejected,
                                               title: "旧码（#\(alias)）没能删除",
                                               detail: "新码已经写进门锁了，但旧的那一枚还在锁里。",
                                               next: "到凭证页把旧的那一枚删掉，否则它还能开门。",
                                               canRetry: true)
                }
            }
            DB.saveLedger(mac, ledger)
            scheduleReminder(mac, alias: newAlias)
            reloadCredentials(mac)
            return .success(newAlias)
        } catch {
            return .failure(error)
        }
    }

    func addTempCode(_ pwd: String, from: String, to: String,
                     owner: String?, note: String) async -> Result<Int, Error> {
        let mac = currentMac
        guard !mac.isEmpty else { return .failure(BLEErrorX.msg("还没有添加门锁")) }
        guard !DB.isDecoy else { return .failure(BLEErrorX.msg("当前无法保存，请稍后再试")) }
        if let refusal = ledgerCorruptRefusal(mac) { return .failure(refusal) }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            let alias = try await LockService.shared.pwdAdd(pwd: pwd, validFrom: from, validTo: to)
            var ledger = DB.ledger(mac)
            ledger.pwds.append(LedgerPwd(alias: alias, from: from, to: to, temp: true,
                                         at: Date().timeIntervalSince1970 * 1000,
                                         pwd: pwd, owner: memberID(for: owner), note: note))
            DB.saveLedger(mac, ledger)
            scheduleReminder(mac, alias: alias)
            reloadCredentials(mac)
            return .success(alias)
        } catch {
            return .failure(error)
        }
    }

    func deletePassword(alias: Int) async -> Result<Void, Error> {
        let mac = currentMac
        guard !mac.isEmpty else { return .failure(BLEErrorX.msg("还没有添加门锁")) }
        // 空壳里凭证列表是空的，正常路径到不了这里；仍然守一道 ——
        // 删密码是真删锁里的条目，不能靠"界面看不见"来保证不发生。
        guard !DB.isDecoy else { return .failure(BLEErrorX.msg("当前无法保存，请稍后再试")) }
        if let refusal = ledgerCorruptRefusal(mac) { return .failure(refusal) }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            try await LockService.shared.pwdDelete(alias)
            var ledger = DB.ledger(mac)
            ledger.pwds.removeAll { $0.alias == alias }
            DB.saveLedger(mac, ledger)
            CredentialOrg.cancelAlerts(mac: mac, alias: alias)
            reloadCredentials(mac)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func setPasswordExpiry(alias: Int, from: String, to: String) async -> Result<Void, Error> {
        let mac = currentMac
        guard !mac.isEmpty else { return .failure(BLEErrorX.msg("还没有添加门锁")) }
        guard !DB.isDecoy else { return .failure(BLEErrorX.msg("当前无法保存，请稍后再试")) }
        if let refusal = ledgerCorruptRefusal(mac) { return .failure(refusal) }
        // 0 是协议里的「不指定」：0B 带着它下发，界面像成功，锁里那条却什么都没变。
        guard alias > 0 else {
            return .failure(BLEErrorX.msg("这枚凭证在本机台账里没有有效的锁端编号，无法修改有效期 —— 请删除后重新添加。"))
        }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            try await LockService.shared.pwdExpire(alias, from, to)
            var ledger = DB.ledger(mac)
            if let i = ledger.pwds.firstIndex(where: { $0.alias == alias }) {
                ledger.pwds[i].from = from
                ledger.pwds[i].to = to
                DB.saveLedger(mac, ledger)
                scheduleReminder(mac, alias: alias)
            }
            reloadCredentials(mac)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func deleteFingerprint(batch: Int) async -> Result<Void, Error> {
        let mac = currentMac
        guard !mac.isEmpty else { return .failure(BLEErrorX.msg("还没有添加门锁")) }
        guard !DB.isDecoy else { return .failure(BLEErrorX.msg("当前无法保存，请稍后再试")) }
        if let refusal = ledgerCorruptRefusal(mac) { return .failure(refusal) }
        do {
            // `batch` 来自台账/恢复包，可能是负数或超过 UInt32。
            // `UInt32(batch)` 会直接 trap —— 删除确认就成了一个必崩的按钮。
            guard let entry = DB.ledger(mac).fps.first(where: { $0.batch == batch }),
                  let batchU32 = entry.batchU32 else {
                return .failure(BLEErrorX.msg("这枚指纹的批次号无效，无法删除 —— 请重新录入。"))
            }
            try await LockService.shared.ensureConnected(mac: mac)
            try await LockService.shared.fpDelete(batchU32)
            var ledger = DB.ledger(mac)
            ledger.fps.removeAll { $0.batch == batch }
            DB.saveLedger(mac, ledger)
            reloadCredentials(mac)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func enrollFingerprint(name: String, owner: String?, note: String,
                           onProgress: @escaping @MainActor (Int) -> Void) async -> Result<Int, Error> {
        let mac = currentMac
        guard !mac.isEmpty else { return .failure(BLEErrorX.msg("还没有添加门锁")) }
        guard !DB.isDecoy else { return .failure(BLEErrorX.msg("当前无法保存，请稍后再试")) }
        if let refusal = ledgerCorruptRefusal(mac) { return .failure(refusal) }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            var presses = 0
            let result = try await LockService.shared.fpStart { p in
                if p.orderIdx != nil {
                    presses += 1
                    let n = presses
                    Task { @MainActor in onProgress(n) }
                }
            }
            guard let last = result.last, let batch = last.batchNumber else {
                return .failure(BLEErrorX.msg("指纹录入没有拿到批次号，请重新录入"))
            }
            let formatter = DF.cached("yyyy-MM-dd HH:mm")
            let from = "2010-01-01 00:00"
            let to = formatter.string(from: TimeFormat.calendar.date(byAdding: .year, value: 100, to: Date()) ?? Date())
            try await LockService.shared.fpConfirm(batch, validFrom: from, validTo: to)
            var ledger = DB.ledger(mac)
            ledger.fps.append(LedgerFp(batch: Int(batch),
                                       name: name.isEmpty ? "指纹 \(batch)" : name,
                                       at: Date().timeIntervalSince1970 * 1000,
                                       note: note, src: nil,
                                       owner: memberID(for: owner), isAlarm: false))
            DB.saveLedger(mac, ledger)
            reloadCredentials(mac)
            return .success(Int(batch))
        } catch {
            return .failure(error)
        }
    }

    private func scheduleReminder(_ mac: String, alias: Int) {
        guard let pwd = DB.ledger(mac).pwds.first(where: { $0.alias == alias }) else { return }
        NotificationAuth.ensure()
        CredentialOrg.scheduleAlerts(mac, pwd, CredAlert(day: true, d3: true, d1: true, h24: true, h2: true))
    }

    // MARK: - 锁策略

    /// `after == nil` = 校时指令已下发，但没能回读确认（不是“偏差为 0”）。
    func syncTime() async -> Result<(Int, Int?), Error> {
        let mac = currentMac
        guard !mac.isEmpty else { return .failure(BLEErrorX.msg("还没有添加门锁")) }
        // 空壳里不改锁钟：这是对门锁的真实写入，而空壳的界面按「没有门锁」伪装。
        guard !DB.isDecoy else { return .failure(BLEErrorX.msg("当前无法校时，请稍后再试")) }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            let r = try await LockService.shared.syncTime()
            Haptics.notify(.success)
            await reload(refreshStatus: true)
            return .success((r.before, r.after))
        } catch {
            Haptics.notify(.error)
            return .failure(error)
        }
    }

    func setMuted(_ on: Bool) async -> Result<Void, Error> {
        let mac = currentMac
        guard !mac.isEmpty else { return .failure(BLEErrorX.msg("还没有添加门锁")) }
        // 空壳里不给锁下发任何设置（静音 / 双验 / 自动上锁 / 布防 / 校时同一道闸）。
        guard !DB.isDecoy else { return .failure(BLEErrorX.msg("当前无法保存，请稍后再试")) }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            try await LockService.shared.setSilent(on)
            DB.store.set("kf_muted_" + mac, on)
            await reload(refreshStatus: false)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func setSafeMode(_ on: Bool) async -> Result<Void, Error> {
        let mac = currentMac
        guard !mac.isEmpty else { return .failure(BLEErrorX.msg("还没有添加门锁")) }
        guard !DB.isDecoy else { return .failure(BLEErrorX.msg("当前无法保存，请稍后再试")) }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            try await LockService.shared.setValidationMode(on)
            // rc=0 只证明命令被接收，不证明策略变了（`LockServiceOps.setValidationMode` 的注释写明
            // 调用方必须回读 verifyMode 才能报成功）。不回读的话，固件不认这条命令时，
            // 界面上的开关会停在"已打开"，而锁其实还是单验 —— 一道安全开关的假成功。
            let st = try await LockService.shared.getStatus(mac: mac)
            DB.writeStatus(mac, st)
            let actual = st.verifyMode != 0
            guard actual == on else {
                return .failure(BLEErrorX.msg(on
                    ? "门锁回了成功，但验证模式没有变成双验。这把锁的固件可能不支持。"
                    : "门锁回了成功，但验证模式没有变回单验。"))
            }
            await reload(refreshStatus: false)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func setAutoLock(_ interval: Int) async -> Result<Void, Error> {
        let mac = currentMac
        guard !mac.isEmpty else { return .failure(BLEErrorX.msg("还没有添加门锁")) }
        guard !DB.isDecoy else { return .failure(BLEErrorX.msg("当前无法保存，请稍后再试")) }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            try await LockService.shared.setAutoLock(interval)
            DB.saveTailgate(mac, TailgateCfg(interval: interval, at: Date().timeIntervalSince1970 * 1000))
            await reload(refreshStatus: false)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func setZotp(_ on: Bool) async -> Result<Void, Error> {
        let mac = currentMac
        guard !mac.isEmpty else { return .failure(BLEErrorX.msg("还没有添加门锁")) }
        // 空壳里读到的永远是「没开通」，这时点「开启」会**真的**给锁下发 cmd19 ——
        // 一次胁迫会话就地改掉门锁的安全设置，而界面看起来只是"开了个开关"。
        // 与签发手机钥匙同一道闸：空壳不产生任何真实副作用。
        guard !DB.isDecoy else { return .failure(BLEErrorX.msg("当前无法保存，请稍后再试")) }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            try await LockService.shared.setZotp(on)
            // B14：写后回读。rc=0 只证明命令被接收 ——
            // 固件不认这条命令时，界面上的开关会停在「已打开」，而锁其实没开。
            // 状态帧里的 tempPwdMode 是动态密码的开关位，拿它对账。
            let st = try await LockService.shared.getStatus(mac: mac)
            DB.writeStatus(mac, st)
            let actual = st.tempPwdMode != 0
            guard actual == on else {
                return .failure(BLEErrorX.msg(on
                    ? "门锁回了成功，但动态密码没有开。这把锁的固件可能不支持。"
                    : "门锁回了成功，但动态密码还开着。"))
            }
            await reload(refreshStatus: false)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func applyDefence(_ mode: DefendMode, startSec: Int, endSec: Int) async -> Result<Void, Error> {
        // 空壳里不改布防：它会真的给锁下发 cmd25，还会写本地 F4 否决门读的配置。
        guard !DB.isDecoy else { return .failure(BLEErrorX.msg("当前无法保存，请稍后再试")) }
        do {
            try await DefendService.apply(host: self, mode: mode, startSec: startSec, endSec: endSec)
            await reload(refreshStatus: false)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    // MARK: - 手机钥匙

    func issueMobileKey(member: Member, forever: Bool,
                        from: String, to: String) async -> Result<MobileKey, Error> {
        // 空壳里必须拒绝签发。
        //
        // `MobileKeyService.issue` 的读写都走 `rawList` / `save`（刻意绕开空壳过滤，
        // 否则写路径会把整批钥匙覆盖成一条），所以它**真的会**从锁的 PIN 池里占一枚、
        // 签出一枚开锁 ekey 落进 Keychain；而界面用 `list()` 显示，空壳里永远是空表 ——
        // 用户点一下「签发」什么也看不到，锁端却少了一枚 PIN，退出空壳后还会凭空多一把钥匙。
        // 与 addPassword / addTempCode / enrollFingerprint 同一道闸。
        guard !DB.isDecoy else { return .failure(BLEErrorX.msg("当前无法保存，请稍后再试")) }
        guard let kc = DB.keychainForUnlock(currentMac) else {
            return .failure(BLEErrorX.msg("还没有添加门锁"))
        }
        do {
            let key = try await MobileKeyService.issue(kc: kc, member: member,
                                                       forever: forever, validFrom: from, validTo: to)
            reloadCredentials(kc.mac)
            return .success(key)
        } catch {
            return .failure(error)
        }
    }

    func revokeMobileKey(_ key: MobileKey) async -> Result<Void, Error> {
        // 与签发同一道闸：吊销会真删锁端 PIN，空壳里不该发生任何真实副作用的写。
        guard !DB.isDecoy else { return .failure(BLEErrorX.msg("当前无法保存，请稍后再试")) }
        guard let kc = DB.keychainForUnlock(currentMac) else {
            return .failure(BLEErrorX.msg("还没有添加门锁"))
        }
        do {
            try await MobileKeyService.revoke(host: self, kc: kc, key: key)
            reloadCredentials(kc.mac)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    // MARK: - 小工具

    /// 台账里的 `at` 是 `Double` 毫秒，来自备份时没有任何范围校验。
    /// `Int64(Double)` 在超出 Int64 或 NaN 时会**直接 trap**：一条 `"at": 1e300`
    /// 的恢复包就能让凭证详情页每次打开都崩。展示前统一夹到可表示的范围。
    static func safeMillis(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), Double(When.permanentCutoff))
    }

    static func millis(_ text: String) -> Int64? {
        guard !text.isEmpty else { return nil }
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let df = DF.cached(format)
            if let d = df.date(from: text) {
                return Int64(d.timeIntervalSince1970 * 1000)
            }
        }
        return nil
    }

    /// 引擎的「永久」是 `2118-01-01 00:00` 这个**哨兵值**（写库与到期判据都用它）。
    /// 界面层只认「有没有到期时间」这一种说法 —— 把哨兵归一成 nil，
    /// 免得它被当成真实日期印成「1 月 1 日到期」。
    static func expiry(_ text: String) -> Int64? {
        guard !text.hasPrefix("2118"), let ms = millis(text) else { return nil }
        return ms >= When.permanentCutoff ? nil : ms
    }

    static func stamp(_ date: Date) -> String {
        DF.cached("yyyy-MM-dd HH:mm").string(from: date)
    }

    static func stampSeconds(_ date: Date) -> String {
        DF.cached("yyyy-MM-dd HH:mm:ss").string(from: date)
    }

    var todayOpenCount: Int {
        let cal = Calendar.current
        return events.reduce(0) { partial, e in
            partial + ((e.isOpen && cal.isDateInToday(When.unix(e.time))) ? 1 : 0)
        }
    }

    var todayAlarmCount: Int {
        let cal = Calendar.current
        return events.reduce(0) { partial, e in
            partial + ((e.isAlarm && cal.isDateInToday(When.unix(e.time))) ? 1 : 0)
        }
    }
}

// MARK: - EngineHost

extension AppModel: EngineHost {
    var currentKeychain: Keychain? {
        let mac = currentMac
        return mac.isEmpty ? nil : DB.keychainForUnlock(mac)
    }

    var lockLink: LockService { LockService.shared }

    /// 自动开门在下发前用这一眼避开读日志 / 手动开锁 —— 三者共用一条 BLE waiter。
    var linkBusy: Bool { busy != nil || phase.isBusy }

    func requestCredentialRoute(alias: Int?) {
        router?.openCredential(alias.map { "pwd:\($0)" } ?? "")
    }
}

// MARK: - 本机停用位

enum CredentialLocalState {
    static func key(_ mac: String) -> String { "kf_disabled_" + DB.normalizeMac(mac) }

    static func isDisabled(mac: String, id: String) -> Bool {
        if DB.isDecoy { return false }
        let list = DB.store.get([String].self, key(mac)) ?? []
        return list.firstIndex(of: id) != nil
    }

    static func setDisabled(mac: String, id: String, _ off: Bool) {
        guard !mac.isEmpty, !id.isEmpty else { return }
        // 空壳里凭证列表为空 ⇒ 当前不可达。仍然守一道：写路径一律拒绝空壳，
        // 别给未来留一条「能改真实停用位」的入口（与 RecordOverlay 同族守卫）。
        if DB.isDecoy { return }
        var list = DB.store.get([String].self, key(mac)) ?? []
        if off {
            if list.firstIndex(of: id) == nil { list.append(id) }
        } else {
            list.removeAll { $0 == id }
        }
        if list.isEmpty {
            DB.store.remove(key(mac))
        } else {
            DB.store.set(key(mac), list)
        }
    }
}
