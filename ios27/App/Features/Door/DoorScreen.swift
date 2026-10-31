// DoorScreen.swift —— 门（Tab 1）。v7 结构 + 原版设备页的全部交互（AUDIT-A §3-B）。
//
// 这一版把「只能轻点」的按钮换回真手势圆盘，并补回设备页的六个模块：
//   异常提醒卡 / 最近开门 / 下拉重扫 / 空态从备份恢复 / 自动上锁倒计时 / 失败排查链。
// 数据绑定保持原口径：AppModel.lock / entries / dialPhase / runUnlockChain；Router 跳转不变。
import SwiftUI

struct DoorScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    @State private var showQuickEdit = false
    @State private var showModuleOrder = false
    @State private var showUnlockGate = false
    @State private var refreshNote: String?
    @State private var checks: [Bool] = [false, false, false]
    /// 连接感知（原 LinkSenseKit 的预热/回连阶梯/RSSI 历史）。
    @State private var link = LinkSenseModel()

    // 圆盘手势态（原 UnlockDial.swift:311-455）
    @State private var pressing = false
    @State private var holdProgress: CGFloat = 0
    @State private var armed = false
    @State private var firedThisTouch = false
    @State private var lastFireAt: Date?
    @State private var lastTapAt: Date?
    @State private var holdTask: Task<Void, Never>?

    private var store: SettingsStore { SettingsStore.shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V.S.gapL) {
                if !DevModuleStore.hidden.contains(DevModule.linkSense.rawValue) {
                    LinkSenseBar(model: link)
                }
                chips
                if let note = refreshNote { refreshLine(note) }
                if let lock = app.lock {
                    attentionCard
                    ForEach(DevLayout.order) { slot in
                        switch slot {
                        case .status: statusSlot(lock)
                        case .quick: quickBlock
                        case .recent: recentBlock
                        }
                    }
                    shortcutsBlock
                } else {
                    noLockBlock
                }
            }
            .padding(.top, V.Page.topSpace)
            .padding(.bottom, V.S.gapL)
        }
        .background(V.C.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await app.reload(refreshStatus: true)
            link.update(mac: app.currentMac)
            if app.lock != nil { await link.preheat() }
        }
        .onChange(of: app.lock?.id) { _, _ in link.update(mac: app.currentMac) }
        .sensoryFeedback(.success, trigger: app.dialPhase == .opened) { _, new in new }
        .sensoryFeedback(.error, trigger: app.dialPhase.isFailed) { _, new in new }
        .sheet(isPresented: $showQuickEdit) { QuickPoolEditSheet() }
        .sheet(isPresented: $showModuleOrder) { ModuleOrderSheet() }
        .sheet(isPresented: $showUnlockGate) {
            NavigationStack {
                UnlockGateScreen {
                    Task { await app.runUnlockChain() }
                }
            }
        }
        .refreshable { await rescan() }
        .onDisappear { holdTask?.cancel() }
    }

    // MARK: - 芯片行

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: V.S.chipGap) {
                VChip(
                    title: "概览",
                    value: overviewWord,
                    tint: overviewTint,
                    style: .standard,
                    systemImage: "circle.hexagongrid.fill"
                )
                VChip(
                    title: "电量",
                    value: batteryChipValue,
                    tint: V.C.blue,
                    style: .standard,
                    systemImage: "battery.75percent"
                )
                Button { showModuleOrder = true } label: {
                    VChip(
                        title: "版面",
                        value: "模块",
                        tint: V.C.text2,
                        style: .compact,
                        systemImage: "square.grid.2x2"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("模块排序与显隐")
            }
            .padding(.horizontal, V.S.chipLeftA)
        }
        .scrollIndicators(.hidden)
    }

    private var overviewWord: String {
        guard let lock = app.lock else { return "未添加" }
        if !lock.isConnected { return "未连接" }
        if lock.battery >= 0, lock.battery < 20 { return "电量偏低" }
        return "全部正常"
    }

    private var overviewTint: Color {
        guard let lock = app.lock else { return V.C.text3 }
        if !lock.isConnected || (lock.battery >= 0 && lock.battery < 20) { return V.C.pink }
        return V.C.rewardGreen
    }

    private var batteryChipValue: String {
        guard let lock = app.lock, lock.battery >= 0 else { return "--" }
        return "\(lock.battery)%"
    }

    private func refreshLine(_ text: String) -> some View {
        HStack(spacing: V.S.gapS) {
            Image(systemName: "arrow.clockwise")
                .font(V.F.icon15)
                .foregroundStyle(V.C.text3)
                .accessibilityHidden(true)
            Text(text)
                .font(V.F.footnote)
                .foregroundStyle(V.C.text3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, V.S.pageGutterA)
    }

    // MARK: - 异常提醒卡（原 DeviceHomeBlocks.swift:196-247）

    @ViewBuilder
    private var attentionCard: some View {
        let items = attentionItems
        if !items.isEmpty {
            VCard {
                VStack(alignment: .leading, spacing: V.S.gapS) {
                    VSectionLabel(text: "需要留意", trailing: "\(items.count) 项")
                    ForEach(Array(items.enumerated()), id: \.offset) { pair in
                        HStack(alignment: .top, spacing: V.S.gapS) {
                            Image(systemName: pair.element.icon)
                                .font(V.F.icon15)
                                .foregroundStyle(pair.element.tone.color)
                                .accessibilityHidden(true)
                            Text(pair.element.text)
                                .font(V.F.footnote)
                                .foregroundStyle(V.C.text1)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .padding(.horizontal, V.S.cardGutter)
        }
    }

    private var attentionItems: [(text: String, icon: String, tone: Tone)] {
        var out: [(String, String, Tone)] = []
        let mac = app.currentMac
        if (app.lastStatus?.sKeyStatus ?? 0) != 0 {
            out.append(("密钥尚未绑定，这把锁可能还没完成配网", "exclamationmark.triangle.fill", .attention))
        }
        let lastSync = DB.syncTime(mac)
        let nowMs = Date().timeIntervalSince1970 * 1000
        if lastSync <= 0 || nowMs - lastSync > 30 * 86_400_000 {
            out.append(("超过 30 天未校时，临时密码可能失效 — 到快捷操作同步时间", "clock.badge.exclamationmark.fill", .attention))
        }
        if let lock = app.lock, lock.battery >= 0, lock.battery <= CareSchedule.battThreshold {
            out.append(("当前电量 \(lock.battery)%，已低于提醒阈值 (\(CareSchedule.battThreshold)%) — 建议备好电池", "battery.25percent", .attention))
        }
        let due = CredentialOrg.dueSoonPwds(mac)
        if !due.isEmpty {
            out.append(("有 \(due.count) 条凭证将在 2 小时内到期（最近一条 #\(due[0].alias)）— 需要续期请到凭证页", "clock.badge.exclamationmark.fill", .attention))
        }
        return out
    }

    // MARK: - 状态槽：圆盘 + 标题 + 读数 + 图表

    private func statusSlot(_ lock: LockSummary) -> some View {
        VStack(spacing: V.S.gapM) {
            gaugeBlock(lock)
            summaryBlock(lock)
            chartBlock
        }
    }

    private func gaugeBlock(_ lock: LockSummary) -> some View {
        VStack(spacing: V.S.gapM) {
            ZStack {
                VGauge(
                    center: batteryNumber(lock),
                    label: "电量",
                    fraction: batteryFraction(lock),
                    tint: V.C.blue,
                    numberFont: digitFont
                )
                .scaleEffect(dialScale)

                // 按住进度环（信息型动效：reduceMotion 下仍然显示，只是不弹）
                Circle()
                    .trim(from: 0, to: holdProgress)
                    .stroke(V.C.blue, style: StrokeStyle(lineWidth: V.S.gapXS, lineCap: .round))
                    .frame(width: V.Gauge.outer * dialScale - V.S.gapL,
                           height: V.Gauge.outer * dialScale - V.S.gapL)
                    .rotationEffect(.degrees(-90))
                    .opacity(holdProgress > 0.001 ? 0.95 : 0)
                    .accessibilityHidden(true)

                if armed {
                    Circle()
                        .strokeBorder(V.C.rewardGreen.opacity(0.75),
                                      style: StrokeStyle(lineWidth: V.S.hair, dash: [V.S.gapXS, V.S.gapXS]))
                        .frame(width: V.Gauge.outer * dialScale - V.S.gapL,
                               height: V.Gauge.outer * dialScale - V.S.gapL)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: V.Gauge.outer, height: V.Gauge.outer)
            .contentShape(.circle)
            .highPriorityGesture(dialGesture)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("开锁")
            .accessibilityValue(app.dialPhase.word)
            .accessibilityHint(dialHint)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { requestUnlock() }

            phaseBar
            autoLockLine
            retryLine
            failureChain
        }
        .frame(maxWidth: .infinity)
        .padding(.top, V.S.gapM)
        .animation(reduceMotion ? nil : V.M.move, value: app.dialPhase)
        .animation(reduceMotion ? nil : V.M.snap, value: armed)
    }

    private var dialScale: CGFloat {
        switch AXSettings.dialSize {
        case "small": return 0.86
        case "large": return 1.08
        default: return 1
        }
    }

    private var digitFont: VFont {
        store.digitFont == "plain" ? V.F.gaugeNumberPlain : V.F.gaugeNumber
    }

    private var dialHint: String {
        if app.dialPhase.isBusy { return "开锁中 · 轻点圆盘可撤销等待" }
        if fenceRequired && !armed { return "误触围栏开启：先从圆盘边缘拖到中心，再执行开锁手势" }
        switch effectiveGesture {
        case "tap": return "轻点开锁"
        case "double": return "双击开锁"
        default: return "按住 \(String(format: "%.1f", holdDuration)) 秒确认开锁，也可上滑"
        }
    }

    // MARK: 三段进度条（原版 80：握手 / 鉴权 / 执行）

    private var phaseBar: some View {
        HStack(spacing: V.S.gapXS) {
            ForEach(1 ... 3, id: \.self) { index in
                Capsule()
                    .fill(app.unlockPhase >= index
                          ? (app.dialPhase.isFailed ? V.C.critical : V.C.blue)
                          : V.C.hairline)
                    .frame(height: V.S.gapXS)
            }
        }
        .frame(maxWidth: V.Gauge.outer * 0.56)
        .opacity(app.unlockPhase > 0 ? 1 : 0.35)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var autoLockLine: some View {
        if let left = app.autoLockLeft {
            HStack(spacing: V.S.gapS) {
                Image(systemName: "timer")
                    .font(V.F.icon15)
                    .foregroundStyle(V.C.blue)
                    .accessibilityHidden(true)
                Text("约 \(left) 秒后自动上锁 · 请确认门已关好")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, V.S.pageGutterA)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var retryLine: some View {
        if let hint = app.retryHint {
            HStack(spacing: V.S.gapS) {
                ProgressView().controlSize(.small).tint(V.C.blue)
                Text(hint)
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, V.S.pageGutterA)
        }
    }

    // MARK: 失败处理链（进度 / 取消 / 退避 / 清单 / 再试一次）

    @ViewBuilder
    private var failureChain: some View {
        if app.failStreak > 0 {
            VStack(spacing: V.S.gapS) {
                Text(app.failStreak < 3 ? "再试一次，别着急" : "连着几次没成，逐项自查一遍：")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if app.failStreak >= 3 {
                    VCard {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(Self.checkTexts.enumerated()), id: \.offset) { pair in
                                Button {
                                    checks[pair.offset].toggle()
                                } label: {
                                    HStack(spacing: V.S.gapS) {
                                        Image(systemName: checks[pair.offset] ? "checkmark.circle.fill" : "circle")
                                            .font(V.F.icon15)
                                            .foregroundStyle(checks[pair.offset] ? V.C.rewardGreen : V.C.text3)
                                            .accessibilityHidden(true)
                                        Text(pair.element)
                                            .font(V.F.footnote)
                                            .foregroundStyle(V.C.text1)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 0)
                                    }
                                    .frame(minHeight: V.Hit.min)
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(pair.element)
                                .accessibilityAddTraits(checks[pair.offset] ? [.isButton, .isSelected] : .isButton)
                            }
                        }
                    }
                    .padding(.horizontal, V.S.pageGutterA)
                }
            }
            .padding(.horizontal, V.S.pageGutterA)
        }
        if case .failed = app.dialPhase {
            VOutlineButton(title: "再试一次", systemImage: "arrow.clockwise") {
                requestUnlock()
            }
            .padding(.horizontal, V.S.pageGutterA)
        }
    }

    private static let checkTexts = [
        "系统蓝牙已打开，手机没有开飞行模式",
        "走到门锁旁 1 米内，中间没有金属门/墙体",
        "门锁电量足够（低电时先换电池再试）"
    ]

    // MARK: - 手势（按住 / 上滑 / 围栏 / 双击 / 轻点）

    private var dialGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard !app.dialPhase.isBusy else { return }
                let center = CGPoint(x: V.Gauge.outer / 2, y: V.Gauge.outer / 2)
                let radius = V.Gauge.outer / 2
                func inside(_ point: CGPoint) -> Bool {
                    hypot(point.x - center.x, point.y - center.y) < radius * 0.75
                }
                if fenceRequired && !armed {
                    if !inside(value.startLocation), inside(value.location) {
                        armed = true
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(4))
                            armed = false
                        }
                    }
                    return
                }
                guard inside(value.startLocation) else { return }
                if !pressing {
                    pressing = true
                    firedThisTouch = false
                    holdProgress = 0
                    if effectiveGesture == "hold" { beginHold() }
                }
                if effectiveGesture == "hold", value.translation.height < -56 {
                    holdTask?.cancel()
                    holdTask = nil
                    holdProgress = 1
                }
            }
            .onEnded { value in
                let moved = abs(value.translation.width) + abs(value.translation.height)
                if app.dialPhase.isBusy {
                    if moved < V.S.gapMS { app.cancelUnlock() }
                    resetGesture()
                    return
                }
                guard !firedThisTouch else { resetGesture(); return }
                switch effectiveGesture {
                case "tap":
                    if moved < V.S.gapMS { requestUnlock() }
                case "double":
                    if moved < V.S.gapMS { handleDoubleTap() }
                default:
                    if holdProgress >= 1 {
                        requestUnlock()
                    } else if SettingsStore.shared.tapDirect, moved < V.S.gapMS {
                        handleDoubleTap()
                    }
                }
                resetGesture()
            }
    }

    private var fenceRequired: Bool { DB.store.getBool("kf_fence", false) }

    private var effectiveGesture: String {
        if !SettingsStore.shared.holdConfirm { return "tap" }
        let mode = AXSettings.gestureMode
        return ["hold", "tap", "double"].contains(mode) ? mode : "hold"
    }

    private var holdDuration: Double {
        min(1.6, max(0.4, DB.store.getDouble("kf_ax_hold", 0.9)))
    }

    private func beginHold() {
        holdTask?.cancel()
        let start = Date()
        let duration = holdDuration
        holdTask = Task { @MainActor in
            while !Task.isCancelled {
                let p = min(1, Date().timeIntervalSince(start) / duration)
                holdProgress = CGFloat(p)
                if p >= 1 {
                    requestUnlock()
                    return
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func resetGesture() {
        holdTask?.cancel()
        holdTask = nil
        pressing = false
        withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.55)) {
            holdProgress = 0
        }
    }

    private func handleDoubleTap() {
        let now = Date()
        if let last = lastTapAt, now.timeIntervalSince(last) < 0.45 {
            lastTapAt = nil
            requestUnlock()
        } else {
            lastTapAt = now
        }
    }

    /// 唯一开锁入口：本机密码闸（30 秒内二次开锁）+ 双击防抖 + 真命令链。
    private func requestUnlock() {
        guard app.dialPhase == .idle || app.dialPhase.isFailed else { return }
        guard !firedThisTouch else { return }
        if SettingsStore.shared.dbltapGuard,
           let last = lastFireAt, Date().timeIntervalSince(last) < 0.3 {
            return
        }
        firedThisTouch = true
        lastFireAt = Date()
        if needsGate {
            showUnlockGate = true
        } else {
            Task { await app.runUnlockChain() }
        }
    }

    private var needsGate: Bool {
        guard DB.hasPasscode(), let last = app.lastUnlockSuccessAt else { return false }
        return Date().timeIntervalSince1970 * 1000 - Double(last) < 30_000
    }

    // MARK: - 标题 / 读数

    private func summaryBlock(_ lock: LockSummary) -> some View {
        VStack(alignment: .leading, spacing: V.S.gapL) {
            VStack(alignment: .leading, spacing: V.Page.titleToBody) {
                Text(lock.name)
                    .font(V.F.displayA)
                    .foregroundStyle(V.C.text1)
                Text(statusWord(lock))
                    .font(V.F.displayA)
                    .foregroundStyle(V.C.text1)
                Text(bodyText(lock))
                    .font(V.F.body)
                    .foregroundStyle(V.C.text2)
                    .lineSpacing(V.Page.bodyLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, V.S.pageGutterA)

            VStatPair(items: [
                ("预计可用", estimateText(lock)),
                ("建议更换", replaceText(lock))
            ])
            .padding(.horizontal, V.S.pageGutterA)

            // 909 指标位显隐的真实消费点：电量恒显，固件 / 锁钟可按外观设置收起。
            if HeroStats.shows("firmware") || HeroStats.shows("lockclock") {
                VReadingGrid(items: heroItems(lock), columns: 2)
                    .padding(.horizontal, V.S.pageGutterA)
            }
        }
    }

    private func heroItems(_ lock: LockSummary) -> [VReadingGrid.Item] {
        var items: [VReadingGrid.Item] = []
        if HeroStats.shows("firmware") {
            items.append(.init(label: "固件", value: lock.firmware.isEmpty ? "未知" : lock.firmware))
        }
        if HeroStats.shows("lockclock") {
            let clock = app.lastStatus.map { ProtoTime.localStr($0.lockTime) } ?? "未读到"
            items.append(.init(label: "锁钟", value: clock))
        }
        items.append(.init(label: "钥匙", value: app.currentKeychain?.ekey.isEmpty == false ? "永久" : "未生成"))
        return items
    }

    private func statusWord(_ lock: LockSummary) -> String {
        if !lock.isConnected { return "未连接" }
        if lock.battery >= 0, lock.battery < 20 { return "电量偏低" }
        return "状态良好"
    }

    private func bodyText(_ lock: LockSummary) -> String {
        let opens = todayOpenCount
        let batteryPart = lock.battery >= 0 ? "电量 \(lock.battery)%" : "电量未知"
        let linkPart = lock.isConnected ? "蓝牙已连接" : "蓝牙未连接"
        return "\(batteryPart)，\(linkPart)，\(lock.keyCount) 枚凭证在册。今天已开锁 \(opens) 次。按日均 3 次估算，约可用 \(estimateMonths(lock))。"
    }

    private func estimateMonths(_ lock: LockSummary) -> String {
        guard lock.battery >= 0 else { return "未知" }
        let months = max(1, Int((Double(lock.battery) / 0.68 / 30).rounded()))
        return "\(months) 个月"
    }

    private func estimateText(_ lock: LockSummary) -> String {
        estimateMonths(lock)
    }

    private func replaceText(_ lock: LockSummary) -> String {
        guard lock.battery >= 0 else { return "未知" }
        let days = Double(lock.battery) / 0.68
        let date = Date().addingTimeInterval(days * 86_400)
        let parts = TimeFormat.calendar.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 1) 月 \(parts.day ?? 1) 日"
    }

    private func batteryNumber(_ lock: LockSummary) -> String {
        lock.battery >= 0 ? String(lock.battery) : "--"
    }

    private func batteryFraction(_ lock: LockSummary) -> Double {
        guard lock.battery >= 0 else { return 0 }
        return Double(max(0, min(100, lock.battery))) / 100
    }

    // MARK: - 图表

    private var chartBlock: some View {
        VStack(alignment: .leading, spacing: V.Page.chartTop) {
            Text("今天的开锁")
                .font(V.F.sectionTitle18)
                .foregroundStyle(V.C.text1)
            if todayOpenCount > 0 {
                HStack(alignment: .top, spacing: V.S.gapS) {
                    VAreaChart(values: chartValues)
                        .frame(width: V.Chart.plotWidth, height: V.Chart.height)
                    VStack(alignment: .leading) {
                        Text("高峰")
                        Spacer(minLength: 0)
                        Text("平时")
                    }
                    .font(V.F.chartTick)
                    .foregroundStyle(V.C.text4)
                    .frame(height: V.Chart.height)
                    .padding(.top, V.S.gapS)
                }
            } else {
                Text("今天还没有开锁记录。按住上方圆盘开一次门，曲线就会出现在这里。")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, V.S.pageGutterA)
    }

    private var todayOpenCount: Int {
        todayEntries.filter { $0.tone == .ok || $0.tone == .live }.count
    }

    private var todayEntries: [LedgerEntry] {
        let start = TimeFormat.calendar.startOfDay(for: Date())
        let startMillis = Int64(start.timeIntervalSince1970 * 1000)
        return app.entries.filter { $0.at >= startMillis }
    }

    private var chartValues: [Double] {
        var bins = Array(repeating: 0.0, count: 15)
        let calendar = TimeFormat.calendar
        for entry in todayEntries {
            let hour = calendar.component(.hour, from: TimeFormat.date(entry.at))
            let index = min(14, max(0, hour * 15 / 24))
            bins[index] += 1
        }
        return bins
    }

    // MARK: - 快捷操作（三列 / 大格两列 / 待添加指纹 / 长按编辑）

    private var quickBlock: some View {
        VStack(alignment: .leading, spacing: V.S.gapS) {
            HStack(alignment: .firstTextBaseline, spacing: V.S.gapS) {
                Text("快捷操作")
                    .font(V.F.section)
                    .foregroundStyle(V.C.text1)
                Spacer(minLength: 0)
                Button("编辑") { showQuickEdit = true }
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text3)
                    .frame(minHeight: V.Hit.min)
                    .accessibilityLabel("编辑快捷操作")
            }
            LazyVGrid(columns: quickColumns, spacing: V.S.gapS) {
                ForEach(Array(QuickPool.ordered().prefix(store.quickGridCount).enumerated()), id: \.element.id) { pair in
                    Button { runQuick(pair.element) } label: {
                        quickTile(pair.element)
                    }
                    .buttonStyle(.plain)
                    .onLongPressGesture(minimumDuration: 0.5) { showQuickEdit = true }
                    .accessibilityLabel(pair.element.label)
                    .accessibilityHint("轻点执行，长按编辑快捷操作")
                }
                if app.currentKeychain.map({ DB.listFps($0.mac).isEmpty }) == true {
                    Button { router.request(.dest(.keyCreate)) } label: {
                        pendingFingerTile
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("待添加指纹")
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
        .padding(.top, V.S.gapL)
    }

    private var quickColumns: [GridItem] {
        let count = AXSettings.bigTile ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: V.S.gapS), count: count)
    }

    private func quickTile(_ action: QuickAction) -> some View {
        VCard(style: .mini) {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                Image(systemName: action.icon)
                    .font(V.F.icon18)
                    .foregroundStyle(V.C.blue)
                    .accessibilityHidden(true)
                Text(action.label)
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text1)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: V.Metric.searchRow, alignment: .leading)
        }
    }

    private var pendingFingerTile: some View {
        VStack(alignment: .leading, spacing: V.S.gapS) {
            Image(systemName: "touchid")
                .font(V.F.icon18)
                .foregroundStyle(V.C.text3)
                .accessibilityHidden(true)
            Text("待添加指纹")
                .font(V.F.footnote)
                .foregroundStyle(V.C.text2)
                .lineLimit(2)
        }
        .padding(V.S.miniPad)
        .frame(maxWidth: .infinity, minHeight: V.Metric.searchRow, alignment: .leading)
        .background(V.C.cardAlt.opacity(0.4), in: .rect(cornerRadius: V.R.mini, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: V.R.mini, style: .continuous)
                .strokeBorder(V.C.hairline, style: StrokeStyle(lineWidth: V.S.hair, dash: [V.S.gapXS, V.S.gapXS]))
        }
    }

    private func runQuick(_ action: QuickAction) {
        QuickPool.recordTap(action.id)
        switch action.id {
        case "addPwd", "addFp", "studio":
            router.request(.dest(.keyCreate))
        case "otp":
            router.request(.dest(.zotp))
        case "syncTime":
            router.request(.dest(.syncTime))
        case "again":
            if let t = QuickPool.repeatTarget(app.lock?.id ?? "") {
                router.request(.key(id: t.keyID))
            } else {
                router.request(.dest(.keys))
            }
        case "backup":
            router.request(.dest(.backup))
        case "tailgate":
            router.request(.dest(.tailgate))
        case "safemode":
            router.request(.dest(.safeMode))
        case "dfu":
            router.request(.dest(.dfu))
        default:
            break
        }
    }

    // MARK: - 最近开门（原 DeviceHomeQuick.swift:231-292）

    private var recentBlock: some View {
        VStack(alignment: .leading, spacing: V.S.gapS) {
            HStack(alignment: .firstTextBaseline, spacing: V.S.gapS) {
                Text("最近开门")
                    .font(V.F.section)
                    .foregroundStyle(V.C.text1)
                Spacer(minLength: 0)
                Button("查看全部") { router.request(.tab(.records)) }
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text3)
                    .frame(minHeight: V.Hit.min)
                    .accessibilityLabel("查看全部开门记录")
            }
            if recentEntries.isEmpty {
                Text("还没有开门记录。开一次门，或到记录页读取锁内日志。")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, V.S.cardPad)
            } else {
                VCard {
                    VStack(spacing: 0) {
                        ForEach(Array(recentEntries.enumerated()), id: \.element.id) { pair in
                            if pair.offset > 0 { VDivider() }
                            Button { router.request(.record(id: pair.element.id)) } label: {
                                recentRow(pair.element)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("在记录页定位这一条")
                        }
                    }
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
        .padding(.top, V.S.gapL)
    }

    private var recentEntries: [LedgerEntry] {
        Array(app.entries.prefix(store.recentCount))
    }

    private func recentRow(_ entry: LedgerEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: V.S.gapM) {
            Text(TimeDisplay.clock(entry.at))
                .font(V.F.stamp)
                .foregroundStyle(V.C.text1)
                .monospacedDigit()
            VStack(alignment: .leading, spacing: V.S.gapXXS) {
                Text(entry.event)
                    .font(V.F.rowTitle)
                    .foregroundStyle(V.C.text1)
                    .lineLimit(1)
                Text(entry.owner ?? "未归属")
                    .font(V.F.rowDetail)
                    .foregroundStyle(V.C.text3)
                    .lineLimit(1)
            }
            Spacer(minLength: V.S.gapS)
            Image(systemName: "chevron.right")
                .font(V.F.chevron)
                .foregroundStyle(V.C.text4)
                .accessibilityHidden(true)
        }
        .frame(minHeight: V.List.rowMinHeight)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 快捷入口

    private var shortcutsBlock: some View {
        VStack(alignment: .leading, spacing: V.S.gapS) {
            Text("门锁与入口")
                .font(V.F.section)
                .foregroundStyle(V.C.text1)
            VCard {
                VStack(spacing: 0) {
                    VListRow(
                        title: "锁实况",
                        detail: "电量 / 信号 / 固件",
                        systemImage: "gauge.with.dots.needle.50percent",
                        tint: V.C.rewardBlue
                    ) { router.request(.dest(.lockStatus)) }
                    VDivider()
                    VListRow(
                        title: "锁信息名片",
                        detail: "固件 / 容量 / 电量采样 / 链路验证",
                        systemImage: "info.circle",
                        tint: V.C.miniBlue
                    ) { router.request(.dest(.deviceInfo)) }
                    VDivider()
                    VListRow(
                        title: "锁设置",
                        detail: "临时码开关 / 自动上锁 / 清空密码",
                        systemImage: "slider.horizontal.3",
                        tint: V.C.coral
                    ) { router.request(.dest(.lockSettings)) }
                    VDivider()
                    VListRow(
                        title: "添加门锁",
                        detail: "配网并绑定这把锁",
                        systemImage: "plus",
                        tint: V.C.rewardGreen
                    ) { router.request(.dest(.addLock)) }
                    VDivider()
                    VListRow(
                        title: "智能网关",
                        detail: "远程访问与转发",
                        systemImage: "antenna.radiowaves.left.and.right",
                        tint: V.C.purple
                    ) { router.request(.dest(.gateway)) }
                    VDivider()
                    VListRow(
                        title: "校准门锁时间",
                        detail: "让锁内时钟与手机一致",
                        systemImage: "clock.arrow.circlepath",
                        tint: V.C.miniBlue
                    ) { router.request(.dest(.syncTime)) }
                    VDivider()
                    VListRow(
                        title: "布防",
                        detail: "离家后监控门锁状态",
                        systemImage: "shield.lefthalf.filled",
                        tint: V.C.pink
                    ) { router.request(.dest(.defend)) }
                    VDivider()
                    VListRow(
                        title: "新增凭证",
                        detail: "密码 / 指纹 / 临时码",
                        systemImage: "key.horizontal.fill",
                        tint: V.C.coral
                    ) { router.request(.dest(.keyCreate)) }
                    VDivider()
                    VListRow(
                        title: "成员",
                        detail: "家人与访客",
                        systemImage: "person.2.fill",
                        tint: V.C.rewardGreen
                    ) { router.request(.dest(.household)) }
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
        .padding(.top, V.S.gapL)
    }

    // MARK: - 空态（必须给出路：添加 + 从备份恢复）

    private var noLockBlock: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapM) {
                Text("还没有添加门锁")
                    .font(V.F.displayB)
                    .foregroundStyle(V.C.text1)
                Text("把锁的后面板打开，长按 RESET 直到三声嘀，然后在这里添加。换过手机的话，也可以先从备份恢复。")
                    .font(V.F.body)
                    .foregroundStyle(V.C.text2)
                    .fixedSize(horizontal: false, vertical: true)
                VActionButton(title: "添加门锁", systemImage: "plus") {
                    router.request(.dest(.addLock))
                }
                VOutlineButton(title: "从备份恢复", systemImage: "arrow.down.doc") {
                    router.request(.dest(.backup))
                }
            }
        }
        .padding(.horizontal, V.S.pageGutterA)
        .padding(.top, V.S.gapL)
    }

    // MARK: - 下拉重扫

    private func rescan() async {
        await link.preheat()
        await app.refreshStatus()
        if let err = app.lastError {
            refreshNote = "重扫失败 · \(err)"
            app.lastError = nil
        } else {
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            refreshNote = "已重新扫描 · \(TimeFormat.clock(now))"
        }
    }
}

#Preview("DoorScreen") {
    NavigationStack {
        DoorScreen()
    }
    .environment(AppModel())
    .environment(Router())
}
