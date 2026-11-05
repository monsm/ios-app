// DoorHomeScreen.swift —— 门（Tab 1）· V8 设计语言
//
// 与 DoorScreen 的功能对齐（数据绑定一致：AppModel.lock / dialPhase / entries、LinkSenseModel、QuickPool）。
// 结构（对应参考图 P2 型）：芯片行 → 电量环（英雄）→ 判断句 → 因果段 → 卡 1 今天的门 → 卡 2 快捷操作 → 卡 3 连接
// 底部常驻：GlassSlideToUnlock（唯一主动作）。
import SwiftUI

struct DoorHomeScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    @State private var link = LinkSenseModel()
    @State private var showQuickEdit = false
    @State private var showUnlockGate = false
    /// 防抖：上次触发开锁的时刻（dbltapGuard 用）。
    @State private var lastFireAt: Date?

    private var lock: LockSummary? { app.lock }

    private var batteryPct: Int {
        lock.map { BatteryCare.displayPct($0.id, snapshot: $0.battery) } ?? -1
    }

    private var batteryFraction: Double {
        batteryPct < 0 ? 0 : Double(batteryPct) / 100.0
    }

    private var judgement: String {
        guard let lock else { return "还没有添加门锁" }
        if !lock.isConnected { return "门未连接" }
        if batteryPct >= 0 && batteryPct < 15 { return "电量偏低" }
        if lock.safeMode { return "安全模式已开" }
        return "门已就绪"
    }

    private var lead: String {
        guard let lock else {
            return "把锁的后面板打开，长按 RESET 直到三声嘀，然后在这里添加。换过手机的话，也可以先从备份恢复。"
        }
        var bits: [String] = []
        bits.append(lock.model)
        if let first = todayOpenEntries.first {
            bits.append("最近一次 " + TimeDisplay.clock(first.at))
        } else {
            bits.append("今天还没有开门")
        }
        bits.append(lock.muted ? "静音开" : "静音关")
        return bits.joined(separator: "，") + "。"
    }

    private var todayOpenEntries: [LedgerEntry] {
        let start = Int64(TimeFormat.calendar.startOfDay(for: Date()).timeIntervalSince1970 * 1000)
        return app.entries.filter { $0.at >= start && ($0.tone == .ok || $0.tone == .live) }
    }

    private var kindRows: [(String, Color, Int)] {
        let today = todayOpenEntries
        return [
            ("密码", V8.D.password, today.filter { $0.event.contains("密码") }.count),
            ("指纹", V8.D.fingerprint, today.filter { $0.event.contains("指纹") }.count),
            ("临时码", V8.D.temp, today.filter { $0.event.contains("临时") }.count),
            ("手机钥匙", V8.D.mobile, today.filter { $0.event.contains("手机") }.count)
        ]
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            VStack(spacing: V8.S.gapS) {
                if !DevModuleStore.hidden.contains(DevModule.statusIcons.rawValue) { lockSwitchRow }
                if !DevModuleStore.hidden.contains(DevModule.groupChips.rawValue) { groupSwitchRow }
                chipRow
            }
        } content: {
            if lock == nil {
                VEmpty(
                    title: "还没有添加门锁",
                    reason: "把锁的后面板打开，长按 RESET 直到三声嘀，然后在这里添加。换过手机的话，也可以先从备份恢复。",
                    actionTitle: "添加门锁"
                ) { router.request(.dest(.addLock)) }
            } else {
                // 2026-11-05（对抗审查）：三个可排序槽按 `DevLayout.order` 渲染 ——
                // 在此之前门页写死了 hero/today/quick 的顺序，于是「我的锁 → 版面」里的
                // 上移/下移只是改了一个没人读的键（kf_dev_order）。
                ForEach(DevLayout.order) { slot in doorCard(slot) }
                attentionCard
                // 「连接感知区」开关的真实消费点（V7 同一判据）。
                if !DevModuleStore.hidden.contains(DevModule.linkSense.rawValue) { linkCard }
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await app.reload(refreshStatus: true)
            link.update(mac: app.currentMac)
            if app.lock != nil { await link.preheat() }
        }
        .onChange(of: app.lock?.id) { _, _ in
            link.update(mac: app.currentMac)
        }
        .sensoryFeedback(.success, trigger: app.dialPhase == .opened) { _, new in new }
        .sensoryFeedback(.error, trigger: app.dialPhase.isFailed) { _, new in new }
        .sheet(isPresented: $showQuickEdit) { QuickPoolEditSheet() }
        .sheet(isPresented: $showUnlockGate) {
            NavigationStack {
                UnlockGateScreen {
                    Task { await app.runUnlockChain() }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if app.lock != nil {
                GlassSlideToUnlock(onUnlock: { requestUnlock() }, busy: app.dialPhase.isBusy)
                    .padding(.horizontal, V8.S.gutterCard)
                    .padding(.bottom, V8.S.gapS)
            }
        }
    }

    // MARK: - 芯片行


    /// 三个可排序槽到门页卡片的映射（与 V7 的 DevSlot.note 逐条对应）：
    ///   status = 电量主环 / 读数 / 今日面积图 → heroCard
    ///   quick  = 10 选 N 的快捷操作格 → quickCard
    ///   recent = 最近开门 → todayCard（今天的门）
    @ViewBuilder
    private func doorCard(_ slot: DevSlot) -> some View {
        switch slot {
        case .status: heroCard
        case .quick: quickCard
        case .recent: todayCard
        }
    }

    // MARK: - 多锁切换（02 §3.1 #1 点名的「多锁切换」；V8 迁移时整段丢失）

    /// 2026-11-05（对抗审查）：V7 门页有两条芯片行 ——
    ///   · `statusIconsRow`：每把锁一颗芯片（名称 + 电量词 + 连接色），点按切换当前锁；
    ///   · `groupChipsRow`：按分组切换（点组切到该组第一把锁）。
    /// 二者同时是 `DevModuleStore` 里 `statusIcons` / `groupChips` 两个开关的**唯一消费点**。
    /// 迁 V8 时两条行都没了 ⇒ 门页没有多锁切换（02 明确要求保留），
    /// 而「版面 → 模块显隐」那两个开关写进 `kf_dev_hidden` 之后没有任何页面读它 ——
    /// 连同「在翻页里隐藏这把锁」(`LockArchive.isHidden`) 一起成了死设置。
    ///
    /// 现在按 V7 原判据恢复，并让隐藏的锁不出现（当前锁永远显示 —— 否则用户会把自己藏到没入口）。
    private var lockSwitchRow: some View {
        let locks = DB.keychains()
        let current = DB.normalizeMac(app.currentMac)
        let shown = locks.filter { DB.normalizeMac($0.mac) == current || !LockArchive.isHidden($0.mac) }
        return Group {
            if shown.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: V8.S.gapChip) {
                        ForEach(shown, id: \.mac) { kc in
                            let on = DB.normalizeMac(kc.mac) == current
                            Button { switchLock(kc) } label: {
                                // 2026-11-05（对抗审查）：用锁身份里选的**符号**做芯片图标。
                                // 在此之前 LockArchive.symbolName 全仓零调用 —— 「符号」那个
                                // 九宫格选了只写进 LockMeta，没有任何界面显示它。
                                VChip2(icon: .glyph(LockArchive.symbolName(LockArchive.meta(kc.mac))),
                                       label: LockArchive.displayName(kc),
                                       value: batteryWord(kc.mac))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("切换到 " + LockArchive.displayName(kc))
                            .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                    .padding(.horizontal, V8.S.gutterCard)
                }
                .scrollClipDisabled()
            }
        }
    }

    private var groupSwitchRow: some View {
        let groups = LockArchive.grouped(DB.keychains()).filter { !$0.name.isEmpty }
        let current = DB.normalizeMac(app.currentMac)
        return Group {
            if groups.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: V8.S.gapChip) {
                        ForEach(groups) { group in
                            let active = group.locks.contains { DB.normalizeMac($0.mac) == current }
                            Button {
                                if let first = group.locks.first { switchLock(first) }
                            } label: {
                                VChip2(icon: .ring(active ? 1 : 0.02, active ? V8.C.accent : V8.C.ink4),
                                       label: group.name,
                                       value: "\(group.locks.count) 把")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("按组切换到 " + group.name)
                            .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                    .padding(.horizontal, V8.S.gutterCard)
                }
                .scrollClipDisabled()
            }
        }
    }

    /// 门页电量读数：与其它四处同一口径（`BatteryCare.displayPct` + `faceText`）。
    /// V7 的教训：门页曾直接读原始 powerLevel 自己拼百分比，同一块电量在两页显示两个数字。
    private func batteryWord(_ mac: String) -> String {
        BatteryCare.faceText(BatteryCare.displayPct(mac, snapshot: DB.readStatus(mac)?.powerLevel ?? -1))
    }

    /// 切锁：与 V7 门页同一口径 —— 先置 overrideMac 再让 AppModel 重建投影。
    private func switchLock(_ kc: Keychain) {
        guard DB.normalizeMac(kc.mac) != DB.normalizeMac(app.currentMac) else { return }
        DB.currentMac = kc.mac
        app.overrideMac = kc.mac
        app.lock = nil
        Task { @MainActor in await app.reload(refreshStatus: false) }
    }
    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: V8.S.gapChip) {
                VChip2(icon: .ring(lock?.isConnected == true ? 1 : 0.02, lock?.isConnected == true ? V8.C.ok : V8.C.danger),
                       label: "连接", value: lock?.isConnected == true ? "已连接" : "未连接")
                VChip2(icon: .ring(1, V8.D.fingerprint), label: "凭证", value: "\(app.keys.count) 枚")
                VChip2(icon: .ring(lock?.safeMode == true ? 1 : 0.02, V8.C.warn),
                       label: "安全模式", value: lock?.safeMode == true ? "已开" : "关")
                VChip2(icon: .ring(1, V8.C.accent), label: "今天", value: "\(todayOpenEntries.count) 次")
            }
            .padding(.leading, V8.S.gutterCard)
            .padding(.trailing, V8.S.gutterCard)
        }
        .scrollClipDisabled()
    }

    // MARK: - 英雄：电量环

    private var heroCard: some View {
        VCard2 {
            VStack(spacing: V8.S.gapM) {
                ZStack {
                    VHeroRing(
                        fraction: batteryFraction,
                        center: batteryPct < 0 ? "—" : "\(batteryPct)",
                        label: "%",
                        size: V8.G.heroOuter * 0.62,
                        tint: batteryPct >= 0 && batteryPct < 15 ? V8.C.danger : V8.C.accent
                    )
                    if app.dialPhase == .opened {
                        Image(systemName: "checkmark")
                            .font(V8.T.heroL)
                            .foregroundStyle(V8.C.ok)
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                            .accessibilityHidden(true)
                    }
                }
                .animation(reduceMotion ? nil : V8.M.settle, value: app.dialPhase == .opened)
                if let left = app.autoLockLeft {
                    Text("约 \(left) 秒后自动上锁 · 请确认门已关好")
                        .font(V8.T.footnote)
                        .foregroundStyle(V8.C.ink3)
                }
                if let hint = app.retryHint {
                    VBusy(text: hint)
                }
                if case .failed(let msg) = app.dialPhase {
                    VFailure(what: "开锁失败", why: msg, next: "走近门锁再试一次；连续失败请检查钥匙串是否插好。")
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 卡 1 今天的门

    private var todayCard: some View {
        VCard2 {
            VCardHead(eyebrow: "今天的门", statement: "\(todayOpenEntries.count) 次开锁",
                      trailing: todayOpenEntries.first.map { TimeDisplay.clock($0.at) })
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                ForEach(Array(kindRows.enumerated()), id: \.offset) { pair in
                    VDataRow(tag: pair.element.0, tagTint: pair.element.1,
                             title: pair.element.0, detail: nil,
                             value: "\(pair.element.2)", unit: "次")
                    if pair.offset != kindRows.count - 1 { VDotRule() }
                }
            }
            .padding(.top, V8.S.gapS)
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("只统计本机收到的开锁回执；失败的尝试不计数。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapFootnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 卡 2 快捷操作

    /// 门页真正显示的快捷操作（2026-11-05 对抗审查：这段逻辑在迁 V8 时丢了）。
    ///
    /// 旧 DoorScreen 的 quickShown 是 Array(QuickPool.ordered().prefix(cap)) —— 它同时做两件事：
    ///   · 按 quickGridCount 截断（设置里「快捷格 10 选 N」）；
    ///   · 按 QuickPool.ordered() 排序（智能开 = 按点过的次数降序；关但满 30 天 = 最常用提首）。
    /// V8 门页直接用了 QuickPool.selected —— 上限与排序双双失效：设置里选 3 枚，门页照样列出全部；
    /// 而「常用操作自动排前」这个开关读得到、写得到，却永远不影响任何顺序。
    private var quickShown: [QuickAction] {
        let cap = max(1, SettingsStore.shared.quickGridCount)
        return Array(QuickPool.ordered().prefix(cap))
    }

    // MARK: - 卡 2 异常提醒（02 §3.1 #1 点名的「异常提醒」；迁 V8 时整段丢失）

    /// 2026-11-05（地毯式对抗审查）：旧 DoorScreen 有一张「需要留意」卡，四条判据：
    /// 密钥未绑定 / 超过 30 天未校时 / 电量低于阈值 / 凭证 2 小时内到期或已过期。
    /// 43 个 Dest 迁 V8 时这张卡没有承接 —— `CredentialOrg.dueSoonPwds` 因此变成零调用；
    /// 用户再也看不到「这把锁快没电」或「临时码马上失效」的首页提醒。这里逐条恢复，
    /// 文案与判据原样保留（含「已过期」与「将到期」两句话分开说的那份诚实）。
    @ViewBuilder
    private var attentionCard: some View {
        let items = attentionItems
        if !items.isEmpty {
            VCard2 {
                VCardHead(eyebrow: "需要留意", statement: "\(items.count) 项", trailing: nil)
                VDivider2()
                    .padding(.top, V8.S.gapM)
                VStack(alignment: .leading, spacing: V8.S.gapS) {
                    ForEach(Array(items.enumerated()), id: \.offset) { pair in
                        HStack(alignment: .top, spacing: V8.S.gapS) {
                            Image(systemName: pair.element.icon)
                                .font(V8.T.footnote)
                                .foregroundStyle(V8.C.warn)
                                .accessibilityHidden(true)
                            Text(pair.element.text)
                                .font(V8.T.footnote)
                                .foregroundStyle(V8.C.ink1)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.top, V8.S.gapM)
            }
        }
    }

    private var attentionItems: [(text: String, icon: String)] {
        var out: [(String, String)] = []
        let mac = app.currentMac
        if (app.lastStatus?.status.sKeyStatus ?? 0) != 0 {
            out.append(("密钥尚未绑定，这把锁可能还没完成配网", "exclamationmark.triangle.fill"))
        }
        let lastSync = DB.syncTime(mac)
        let nowMs = Date().timeIntervalSince1970 * 1000
        if lastSync <= 0 || nowMs - lastSync > 30 * 86_400_000 {
            out.append(("超过 30 天未校时，动态密码可能失效 — 到快捷操作同步时间", "clock.badge.exclamationmark.fill"))
        }
        if let lock = app.lock, lock.battery >= 0, lock.battery <= CareSchedule.battThreshold {
            out.append(("当前电量 \(lock.battery)%，已低于提醒阈值 (\(CareSchedule.battThreshold)%) — 建议备好电池", "battery.25percent"))
        }
        let due = CredentialOrg.dueSoonPwds(mac)
        if !due.isEmpty {
            // 窗口是 [now-1h, now+2h] —— 包含已过期 1 小时内的条目。
            // 一律写「将在 2 小时内到期」对已过期的那几条是假的：它们早就不放行了。
            let nearest = CredentialOrg.expiryDate(due[0])?.timeIntervalSince1970 ?? 0
            let expired = nearest < Date().timeIntervalSince1970
            let text = expired
                ? "有 \(due.count) 条凭证已过期（最近一条 #\(due[0].alias)）— 锁端已不再放行，请到凭证页处理"
                : "有 \(due.count) 条凭证将在 2 小时内到期（最近一条 #\(due[0].alias)）— 需要续期请到凭证页"
            out.append((text, "clock.badge.exclamationmark.fill"))
        }
        return out
    }
    private var quickCard: some View {
        VCard2 {
            HStack(alignment: .firstTextBaseline) {
                VCardHead(eyebrow: "一按即开", statement: "\(QuickPool.selected.count) 个快捷位")
                Spacer(minLength: 0)
                Button { showQuickEdit = true } label: {
                    Text("编辑")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.accent)
                        .frame(minHeight: V8.H.min)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("编辑快捷操作")
            }
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                ForEach(Array(quickShown.enumerated()), id: \.element.id) { pair in
                    VNavRow(title: pair.element.label, detail: nil) {
                        runQuick(pair.element.id)
                    }
                    if pair.offset != quickShown.count - 1 { VDotRule() }
                }
            }
            .padding(.top, V8.S.gapS)
        }
    }

    // MARK: - 卡 3 连接

    private var linkCard: some View {
        VCard2 {
            VCardHead(eyebrow: "连接", statement: link.phase.rawValue,
                      trailing: link.lastRSSI.map { "\($0) dBm" })
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                VNavRow(title: "预热连接", detail: link.busy ? "进行中…" : "提前连上，开门更快") {
                    Task { await link.preheat() }
                }
                VDotRule()
                VNavRow(title: "重连", detail: "阶梯 \(Int(link.nextLadder))s") {
                    Task { await link.reconnect() }
                }
                VDotRule()
                VNavRow(title: "读信号强度", detail: "RSSI") {
                    link.readRSSI()
                }
                VDotRule()
                VNavRow(title: "门锁设置", detail: "静音 / 防尾随 / 安全模式 / 布防") {
                    router.request(.dest(.lockSettings))
                }
                VDotRule()
                // 2026-11-05（S5 归并复核）：锁维护页（网关 / 固件 / 电池 / 名片）归并后
                // 三个来源 Dest（gateway / batteryProfile / deviceInfo）全仓零调用点 ——
                // 1440 行的能力在 UI 上不可达。按 02 §2 的树恢复入口。
                VNavRow(title: "锁维护", detail: "固件 / 电池 / 网关 / 锁信息名片") {
                    router.request(.dest(.gateway))
                }
                VDotRule()
                VNavRow(title: "我的锁", detail: "全部锁 / 锁档案 / 版面") {
                    router.request(.dest(.lockPortfolio))
                }
                VDotRule()
                // 2026-11-04（Round 16b · 能力守恒复核）：旧门页芯片行有一枚「版面」，
                // 点开是 ModuleOrderSheet（三槽排序 + 模块显隐 + 快捷格勾选）。
                // 门页迁 V8 时这一枚丢了 —— .moduleOrder 变成零入口的孤儿 Dest。
                // 这里恢复入口，指向已迁的 ModuleOrderHomeScreen。
                VNavRow(title: "版面", detail: "模块排序与显隐") {
                    router.request(.dest(.moduleOrder))
                }
            }
            .padding(.top, V8.S.gapS)
        }
    }

    // MARK: - 动作

    /// 唯一开锁入口：本机密码闸（30 秒内二次开锁）+ 双击防抖 + 真命令链（与 DoorScreen 同口径）。
    private func requestUnlock() {
        guard app.dialPhase == .idle || app.dialPhase.isFailed else { return }
        if SettingsStore.shared.dbltapGuard,
           let last = lastFireAt, Date().timeIntervalSince(last) < 0.3 {
            return
        }
        lastFireAt = Date()
        if needsGate {
            showUnlockGate = true
        } else {
            Task { await app.runUnlockChain() }
        }
    }

    private var needsGate: Bool {
        guard DB.hasPasscode(), let last = app.lastUnlockSuccessAt else { return false }
        let now = Date().timeIntervalSince1970 * 1000
        // 刚通过闸门的 30 秒内直接放行 —— 否则连续开门会一直弹密码（与 DoorScreen 同一修复）。
        if let passed = app.gatePassedAt, now - Double(passed) < 30_000 { return false }
        return now - Double(last) > 30_000
    }

    private func runQuick(_ id: String) {
        // 2026-11-05（对抗审查）：旧 DoorScreen 在这里先记一次点击（QuickPool.recordTap），
        // 迁 V8 时漏了 —— 于是「常用操作自动排前」的计数器永远是空的。
        QuickPool.recordTap(id)
        switch id {
        case "addPwd", "addFp": router.request(.dest(.keyCreate))
        case "otp": router.request(.dest(.zotp))
        case "syncTime": router.request(.dest(.syncTime))
        case "studio": router.request(.dest(.credentialStudio))
        case "backup": router.request(.dest(.backup))
        case "tailgate": router.request(.dest(.tailgate))
        case "safemode": router.request(.dest(.safeMode))
        case "dfu": router.request(.dest(.dfu))
        default: Task { await app.runUnlockChain() }
        }
    }
}