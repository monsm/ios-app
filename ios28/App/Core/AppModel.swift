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

    @ObservationIgnored private weak var router: Router?
    @ObservationIgnored private var autoLockTask: Task<Void, Never>?
    @ObservationIgnored private var activitySignature = ""
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
            return
        }

        if refreshStatus, LockService.shared.connectedMAC == mac {
            if let st = try? await LockService.shared.getStatus(mac: mac) {
                DB.writeStatus(mac, st)
            }
        }

        lock = makeLock(kc)
        lastStatus = DB.get(StatusSnapshot.self, "kf_snap_" + mac)
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
        guard on != decoyApplied else { return }
        decoyApplied = on
        DB.setDecoy(on)
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
        ledgerCorrupt = DB.isLedgerCorrupt(m)
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
                createdAt: p.at,
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
                createdAt: f.at,
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
                createdAt: k.at,
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
        events = RecordsSource.load(mac: m, lockName: name, memberNames: names)
    }

    /// 成员卡片。活跃度（最近一次开门）来自 `MemberHub.activityBundle`，
    /// 那是个 O(锁 × 日志) 的重活，所以按签名缓存。
    ///
    /// 缓存的**结果**必须留着：原实现只在签名变化时重算，却把结果丢在局部变量里，
    /// 于是同一轮刷新里第二次调用拿到的是空 bundle ——
    /// 名册每一行的「最近 \(When.ago(...))」永远是「还没开过门」。
    private func reloadMemberCards() -> [MemberCard] {
        let ext = MemberHub.allExt()
        let raw = DB.members()
        let signature = raw.map(\.id).joined(separator: "|") + "#" + String(events.count)
        if signature != activitySignature {
            activitySignature = signature
            activityCache = MemberHub.activityBundle(raw.map(\.id))
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

    private func makeLock(_ kc: Keychain) -> LockSummary {
        let snap = DB.readStatus(kc.mac)
        let name = kc.name.isEmpty ? (kc.pidName.isEmpty ? "我的门锁" : kc.pidName) : kc.name
        let ledger = DB.ledger(kc.mac)
        let meta = LockArchive.meta(kc.mac)
        return LockSummary(
            id: kc.mac,
            name: name,
            model: kc.pidName.isEmpty ? "未知型号" : kc.pidName,
            pid: kc.pid,
            battery: snap?.powerLevel ?? -1,
            signal: LinkSenseModel.level(LinkSenseModel.savedRSSI(kc.mac)),
            firmware: snap?.firmware ?? kc.fw,
            keyCount: ledger.pwds.count + ledger.fps.count + MobileKeyService.list(kc.mac).count,
            isConnected: LockService.shared.connectedMAC == kc.mac,
            safeMode: (snap?.verifyMode ?? 0) != 0,
            muted: DB.store.getBool("kf_muted_" + kc.mac),
            hidden: LockArchive.isHidden(kc.mac),
            group: meta.grp
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
        let mac = currentMac
        guard !mac.isEmpty else { phase = .failed("还没有添加门锁"); return }

        lastError = nil
        // 触感只在**结果**上给：按下一下，成功或失败各一下。
        // （早先挂在相位的 `.sensoryFeedback` 上，连上／下发／等回执会连着震四五下。）
        Haptics.impact()
        // 自动重试只覆盖**连不上**这一段：命令没发出去，重发是安全的。
        // 命令已经发出、只是没等到回执时**不重试** ——
        // 引擎层对开锁命令刻意不重试（锁可能已经执行了），这一层不能把它绕过去。
        let attempts = SettingsStore.shared.autoRetry ? 2 : 1
        for attempt in 1 ... attempts {
            phase = .reaching
            do {
                try await LockService.shared.ensureConnected(mac: mac)
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                guard attempt < attempts else {
                    phase = .failed("连不上门锁：\(msg)")
                    lastError = msg
                    Haptics.notify(.error)
                    return
                }
                // 刚失败就立刻重连多半还是失败：让链路缓一下再试。
                try? await Task.sleep(for: .milliseconds(700))
                continue
            }
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
                    Haptics.notify(.success)
                    let now = Int64(Date().timeIntervalSince1970 * 1000)
                    lastUnlockAt = now
                    lastActionAt = now
                    Milestones.recordUnlockSuccess()
                    startAutoLockCountdown()
                    try? await Task.sleep(for: .milliseconds(900))
                    if phase == .opened { phase = .idle }
                    await reload(refreshStatus: false)
                } else if rc == 22 {
                    phase = .failed("门锁要求第二种验证方式")
                    Haptics.notify(.error)
                } else {
                    phase = .failed(StatusParser.rcFriendly(rc))
                    Haptics.notify(.error)
                }
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                phase = .failed(msg)
                lastError = msg
                Haptics.notify(.error)
            }
            return
        }
    }

    func resetUnlock() {
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
        lastError = nil
        do {
            let st = try await LockService.shared.getStatus(mac: mac)
            DB.writeStatus(mac, st)
            sampleRSSI()
            await reload(refreshStatus: false)
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    @discardableResult
    func readLogs() async -> (read: Int, remaining: Int?)? {
        let mac = currentMac
        guard busy == nil else { return nil }
        // 没有锁时要说清楚：这里原先直接 return nil，界面上一点动静都没有 ——
        // 用户点了「从门锁读一次」，卡片回到原样，像是什么都没发生。
        guard !mac.isEmpty else {
            lastError = "还没有绑定门锁 —— 先配一把锁，再回来读记录。"
            return nil
        }
        busy = "正在读门锁记录…"
        defer { busy = nil }
        lastError = nil
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            sampleRSSI()
            var startIdx: UInt32 = 0xFFFF_FFFF
            var collected: [LogEntry] = []
            var surplus: Int?
            var pages = 0
            for _ in 0 ..< 20 {
                let page = try await LockService.shared.getLogs(startIdx: startIdx, pageSize: 5)
                pages += 1
                if let s = page.surplus { surplus = s }
                if page.logs.isEmpty { break }
                collected.append(contentsOf: page.logs)
                if let s = page.surplus, s <= 0 { break }
                if page.logs.count < 5 { break }
                guard let low = page.logs.map(\.idxRaw).min(), low > 0 else { break }
                startIdx = low - 1
            }
            let remaining = pages >= 20 ? surplus : nil
            DB.writeLogs(mac, collected)
            RecordsSource.markSynced(mac: mac, at: Int64(Date().timeIntervalSince1970 * 1000))
            readLogsAt = RecordsSource.lastSync(mac: mac)
            await reload(refreshStatus: false)
            return (read: collected.count, remaining: remaining)
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    // MARK: - 凭证写入

    private func memberID(for owner: String?) -> String? {
        guard let owner, !owner.isEmpty else { return nil }
        if DB.member(owner) != nil { return owner }
        return DB.members().first { $0.name == owner }?.id
    }

    func addPassword(_ pwd: String, from: String, to: String,
                     owner: String?, note: String?,
                     replacing alias: Int? = nil) async -> Result<Int, Error> {
        let mac = currentMac
        guard !mac.isEmpty else { return .failure(BLEErrorX.msg("还没有添加门锁")) }
        guard !DB.isDecoy else { return .failure(BLEErrorX.msg("当前无法保存，请稍后再试")) }
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
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            try await LockService.shared.fpDelete(UInt32(batch))
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

    func syncTime() async -> Result<(Int, Int), Error> {
        let mac = currentMac
        guard !mac.isEmpty else { return .failure(BLEErrorX.msg("还没有添加门锁")) }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            let r = try await LockService.shared.syncTime()
            Haptics.notify(.success)
            await reload(refreshStatus: true)
            return .success((r.before, r.after))
        } catch {
            return .failure(error)
        }
    }

    func setMuted(_ on: Bool) async -> Result<Void, Error> {
        let mac = currentMac
        guard !mac.isEmpty else { return .failure(BLEErrorX.msg("还没有添加门锁")) }
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
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            try await LockService.shared.setValidationMode(on)
            await reload(refreshStatus: false)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func setAutoLock(_ interval: Int) async -> Result<Void, Error> {
        let mac = currentMac
        guard !mac.isEmpty else { return .failure(BLEErrorX.msg("还没有添加门锁")) }
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
            await reload(refreshStatus: false)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func applyDefence(_ mode: DefendMode, startSec: Int, endSec: Int) async -> Result<Void, Error> {
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
