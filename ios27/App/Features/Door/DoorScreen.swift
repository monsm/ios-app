// DoorScreen.swift —— 门（Tab 1）。v7 结构重写，参考 R1-device.html / TOKENS.md 参考 A。
//
// 布局全部取自实测：芯片行 left 19.3 / 芯片 178×53.3 r14；主环外径 279.3、描边 36.3、
// 缺口 163–201°、游标 289°、中心数字 73pt；标题 30pt/700 left 37.3；正文 17/23 #828282；
// 双列读数 12.5/17；图表区 282.4×125（6 条点线 + 3 条横线 + 蓝色区间带）。
// 数据绑定保持原口径：AppModel.lock / entries / dialPhase / runUnlockChain()；Router 跳转不变。
import SwiftUI

struct DoorScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @State private var showQuickEdit = false
    /// 连接感知（原 LinkSenseKit 的预热/回连阶梯/RSSI 历史）。
    @State private var link = LinkSenseModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V.S.gapL) {
                LinkSenseBar(model: link)
                chips
                if let lock = app.lock {
                    gaugeBlock(lock)
                    summaryBlock(lock)
                    chartBlock
                    quickBlock
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
    }

    // MARK: - 芯片行（R1：left 19.3 / gap 7.7）

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

    // MARK: - 主角：主环（点击 = 真实开锁链）

    private func gaugeBlock(_ lock: LockSummary) -> some View {
        VStack(spacing: V.S.gapM) {
            Button {
                Task { await app.runUnlockChain() }
            } label: {
                VGauge(
                    center: batteryNumber(lock),
                    label: "电量",
                    fraction: batteryFraction(lock),
                    tint: V.C.blue
                )
            }
            .buttonStyle(.plain)
            .disabled(app.dialPhase.isBusy)
            .accessibilityLabel("开锁")
            .accessibilityValue(app.dialPhase.word)

            if case .failed(let reason) = app.dialPhase {
                HStack(alignment: .top, spacing: V.S.gapS) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(V.F.sans(13))
                        .foregroundStyle(V.C.pink)
                        .accessibilityHidden(true)
                    Text(reason)
                        .font(V.F.footnote)
                        .foregroundStyle(V.C.text1)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(V.S.gapM)
                .background(V.C.pink.opacity(0.12), in: .rect(cornerRadius: V.R.action, style: .continuous))
                .padding(.horizontal, V.S.pageGutterA)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, V.S.gapM)
    }

    private func batteryNumber(_ lock: LockSummary) -> String {
        lock.battery >= 0 ? String(lock.battery) : "--"
    }

    private func batteryFraction(_ lock: LockSummary) -> Double {
        guard lock.battery >= 0 else { return 0 }
        return Double(max(0, min(100, lock.battery))) / 100
    }

    // MARK: - 标题 / 正文 / 双列读数（R1：left 37.3、30pt/700）

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
                    .lineSpacing(V.Page.bodySpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, V.S.pageGutterA)

            VStatPair(items: [
                ("预计可用", estimateText(lock)),
                ("建议更换", replaceText(lock))
            ])
            .padding(.horizontal, V.S.pageGutterA)
        }
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

    // MARK: - 图表（R1：282.4×125，6 条点线 + 3 条横线 + 区间带）

    private var chartBlock: some View {
        VStack(alignment: .leading, spacing: V.Page.chartTop) {
            Text("今天的开锁")
                .font(V.F.sans(18, weight: .bold))
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
                    .font(V.F.sans(8.6))
                    .foregroundStyle(V.C.text4)
                    .frame(height: V.Chart.height)
                    .padding(.top, V.S.gapS)
                }
            } else {
                Text("今天还没有开锁记录。轻点上方主环开一次门，曲线就会出现在这里。")
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

    /// 今天 24 小时 → 15 个桶，供面积图使用（没有记录就是 0，不编造形状）。
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

    // MARK: - 快捷操作（QuickPool：10 选 N / 常用排前 / 再开一次）

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
                    .frame(minHeight: V.List.rowMinHeight)
                    .accessibilityLabel("编辑快捷操作")
            }
            VCard {
                VStack(spacing: 0) {
                    ForEach(Array(QuickPool.ordered().prefix(SettingsStore.shared.quickGridCount).enumerated()), id: \.element.id) { index, action in
                        if index > 0 { VDivider() }
                        VListRow(
                            title: action.label,
                            systemImage: action.icon,
                            tint: V.C.rewardBlue
                        ) { runQuick(action) }
                    }
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
        .padding(.top, V.S.gapL)
    }

    private func runQuick(_ action: QuickAction) {
        QuickPool.recordTap(action.id)
        switch action.id {
        case "addPwd", "addFp", "studio":
            router.request(.dest(.keyCreate))
        case "otp":
            router.request(.dest(.keyCreate))
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
            router.request(.dest(.lockStatus))
        case "safemode":
            router.request(.dest(.lockStatus))
        case "dfu":
            router.request(.dest(.dfu))
        default:
            break
        }
    }

    // MARK: - 快捷入口（保留原有全部 Router 入口）

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
                    // 来源：原 App/UI/LockSettingsView.swift（锁设置）。
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

    // MARK: - 空态（必须给出路）

    private var noLockBlock: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapM) {
                Text("还没有添加门锁")
                    .font(V.F.displayB)
                    .foregroundStyle(V.C.text1)
                Text("把锁的后面板打开，长按 RESET 直到三声嘀，然后在这里添加。")
                    .font(V.F.body)
                    .foregroundStyle(V.C.text2)
                    .fixedSize(horizontal: false, vertical: true)
                VActionButton(title: "添加门锁", systemImage: "plus") {
                    router.request(.dest(.addLock))
                }
            }
        }
        .padding(.horizontal, V.S.pageGutterA)
        .padding(.top, V.S.gapL)
    }
}

#Preview("DoorScreen") {
    NavigationStack {
        DoorScreen()
    }
    .environment(AppModel())
    .environment(Router())
}
