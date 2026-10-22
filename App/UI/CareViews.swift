// 包4 维护关怀页面 — 维护中心 / 五项保养清单 / 换电图文指引 / 维护提醒设置
// 落地: 1012 年度换电日 · 1013 90 天周期 · 1014 事件入记录 · 1015 五项清单 · 1025 应急钥匙半年检 ·
//       1024 潮湿位 · 1026 低温关怀 · 1028 保养历史过滤 · 1030 清洁月历 · 1031/1038 免扰与白天送达 ·
//       116 换电图文引导 · 118 换电复位基线 · 1033 换电向导 (与 116 同一页: 分步图文 + 「已换新」完成写记录, 不重复造页) ·
//       287 低电阈值 · 146 升级提醒开关 · 1039/爱洁之家徽章联动
import SwiftUI

// ================= 维护中心 (锁详情页/设置入口, per-lock) =================
struct MaintenanceView: View {
    @EnvironmentObject var app: AppState
    // 2026-10-15 走查: 这一页有两条呈现路 —— 设置页那张 sheet (`SettingsView` 的 `showCare`) 与快捷格/设置栈里的 push。
    // sheet 是盖在整个 TabView 上的，页里那枚「到记录页查看全部」原先只写 `app.tabSelection = 2` 就完事
    // ⇒ 切的是**被盖住的那层**，用户点了看着没反应，甩掉 sheet 才发现自己站在记录页 (§7.3 那一族，`StatsView` 六枚格子是同类先例)。
    @Environment(\.dismiss) private var dismiss
    @State private var care = CareState()
    @State private var yearlyOn = false
    @State private var yearlyDate = Date()
    /// yearlyDate 是否真从库里解出来过。没解出来就不许回写, 否则 reload→onChange→saveYearly
    /// 会把用户的"年度换电日"静默改成今天 (yearlyDate 的初值)。
    @State private var yearlyLoaded = false
    @State private var ekeyOn = false
    @State private var loaded = false
    @State private var showChecklist = false

    private var mac: String { app.current?.mac ?? "" }
    /// 1022 频次自适应: 高频使用锁 (近 30 天开门 ≥60 次) 周期缩到 60 天。
    ///
    /// 判据只有一处（`BatteryCare.carePeriodDays`），读法也只有一处（这里用带 `mac:` 的重载）。
    /// 2026-10-23：此处原来自己先算 `opens30d` 再传给另一重载 —— 值对，但两种调用形式会让人不确定哪条是正门。
    private var periodDays: Int { BatteryCare.carePeriodDays(mac: mac) }
    /// 1013 周期已过天数 / 是否到期
    private var elapsedDays: Double {
        guard care.lastCareAt > 0 else { return 0 }
        return (Date().timeIntervalSince1970 * 1000 - care.lastCareAt) / 86400_000
    }
    private var careDue: Bool { care.lastCareAt > 0 && elapsedDays >= Double(periodDays) }

    var body: some View { vkBody.destined(.maintenance) }
    var vkBody: some View {
        ZStack {
            XPalette.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: XSpace.section) {
                    carePeriodSection.xScrollLift()
                    historySection.xScrollLift()
                    swapSection.xScrollLift()
                    ekeySection.xScrollLift()
                }
                .padding(.horizontal, XSpace.gutter)
                .padding(.vertical, XSpace.l)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("维护与保养")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if !loaded { loaded = true; reload() } }
        // 换锁重取: care 是 @State 快照, 而 mac/meta/opens30d/periodDays
        // 全是实时跟着 app.current 走的 —— 不重取就会出现"同屏两把锁"。
        .onChange(of: app.currentMac) { _, _ in reload() }
        .sheet(isPresented: $showChecklist) { CareChecklistView { reload() } }
        .onChange(of: yearlyOn) { _, _ in saveYearly() }
        .onChange(of: yearlyDate) { _, _ in saveYearly() }
    }

    private func reload() {
        care = BatteryCare.care(mac)
        ekeyOn = care.ekeyRemindOn
        yearlyOn = !care.yearlyBattDay.isEmpty
        let p = care.yearlyBattDay.split(separator: "-").compactMap { Int($0) }
        if p.count == 2,
           let d = WeekCal.gregorian.date(from: DateComponents(year: 2000, month: p[0], day: p[1])) {
            yearlyDate = d
            yearlyLoaded = true
        } else {
            // 关着 (无日期) 也算已加载; 开着却解不出日期 = 数据异常, 禁止回写
            yearlyLoaded = !yearlyOn
        }
    }
    private func saveYearly() {
        // 自激闸: reload() 里的赋值也会走 .onChange(yearlyOn)/.onChange(yearlyDate),
        // 日期没从库里解出来时直接返回, 不让"读"变成"写"。
        if yearlyOn, !yearlyLoaded { return }
        var s = BatteryCare.care(mac)
        let want: String
        if yearlyOn {
            let q = WeekCal.gregorian.dateComponents([.month, .day], from: yearlyDate)
            want = String(format: "%02d-%02d", q.month ?? 1, q.day ?? 1)
        } else { want = "" }
        // 与库中值一致即无变化: 打断 reload→onChange→save 的回写环 (也让重复 toggle 不再触发 reschedule)
        if want == s.yearlyBattDay { return }
        s.yearlyBattDay = want
        BatteryCare.saveCare(mac, s)
        care = s
        Task { await CareSchedule.rescheduleCalendar() }
    }
    /// 1034: 充电记录弹窗 (日期记今天, 时长可留空)
    private func markCharge() {
        let alert = UIAlertController(title: "充电记录", message: "将把上次充电记为今天", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "充电时长 (分钟, 可留空)"; $0.keyboardType = .numberPad }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "记录", style: .default) { _ in
            var s = BatteryCare.care(mac)
            s.chargeAt = Date().timeIntervalSince1970 * 1000
            s.chargeLenMin = Int(alert.textFields?.first?.text ?? "") ?? 0
            BatteryCare.saveCare(mac, s)
            care = s
        })
        UIApplication.topViewController()?.present(alert, animated: true)
    }
    private func saveEkey() {
        var s = BatteryCare.care(mac)
        s.ekeyRemindOn = ekeyOn
        BatteryCare.saveCare(mac, s)
        care = s
        Task { await CareSchedule.rescheduleCalendar() }
    }
    private func daysAgoText(_ tsMs: Double) -> String {
        let d = Int(Date().timeIntervalSince1970 * 1000 - tsMs) / 86_400_000
        return d <= 0 ? "今天" : "\(d) 天前"
    }

    // ---------- 1013 90 天周期 + 1015 五项入口 ----------
    private var carePeriodSection: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                secLabel("保养周期")
                LabeledRow("上次保养", care.lastCareAt > 0 ? daysAgoText(care.lastCareAt) : "还没记过")
                if care.lastCareAt > 0 {
                VStack(alignment: .leading, spacing: XSpace.xxs) {
                GeometryReader { geo in
                ZStack(alignment: .leading) {
                Capsule().fill(XPalette.surfaceAlt)
                Capsule().fill(careDue ? XPalette.warn : XPalette.accent)
                .frame(width: geo.size.width * CGFloat(min(elapsedDays / Double(periodDays), 1)))
                }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
                Text(careDue
                ? "已满 \(periodDays) 天, 建议安排一次保养"
                : "周期 \(periodDays) 天 · 已过 \(Int(elapsedDays)) 天" + (periodDays == 60 ? " · 高频使用自动缩短" : ""))
                .xFont(.caption2)
                .foregroundStyle(careDue ? XPalette.warn : XPalette.textSub)
                }
                .accessibilityElement(children: .combine)
                }
                Button { showChecklist = true } label: {
                Label(care.lastCareAt > 0 ? "再做一次五项保养" : "开始五项保养", systemImage: "checklist")
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: XHit.min)
                .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                Text("五项: 滑轨 / 锁舌 / 电池触点 / 指纹头 / 应急钥匙。完成即写入记录, 可在记录页按「保养」过滤。")
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }


    // ---------- 1028 保养历史过滤 (1014 事件) ----------
    private var historySection: some View {
        let all = BatteryCare.events(mac)
        return XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                secLabel("保养历史")
                if all.isEmpty {
                    // 包14 空态族消费点 (815 双按钮 / 841 小管家默认开 / 1044 便签):
                    // 空态直接给出那件能做的事 —— 主动作打开五项清单。
                    XEmptyState(systemImage: "checkmark.seal",
                                title: "还没有保养记录",
                                message: "五项清单走一遍就会在这里落下第一条; 换电完成后走「换电关怀」里的图文指引。",
                                actionTitle: "开始五项保养",
                                action: { showChecklist = true })
                }
                ForEach(Array(all.prefix(5).enumerated()), id: \.offset) { _, e in
                    HStack(spacing: XSpace.s) {
                        Image(systemName: e.kind == "battery" ? "battery.100" : "checkmark.seal")
                            .font(.system(size: XIcon.sm, weight: .medium))
                            .foregroundStyle(e.kind == "battery" ? XPalette.ok : XPalette.accentText)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: XSpace.xxs) {
                            Text(e.kind == "battery" ? "更换电池" : "保养完成")
                                .xFont(.subheadline)
                                .foregroundStyle(XPalette.text)
                            Text(e.note + " · " + daysAgoText(e.ts))
                                .xFont(.caption2)
                                .foregroundStyle(XPalette.textSub)
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
                if !all.isEmpty {
                    Button {
                        app.pendingRecordsFilter = "__care"
                        app.requestRoute(.records)
                        // 先落点再收摊：sheet 不收，切过去的 Tab 就在它底下
                        dismiss()
                    } label: {
                        Label("到记录页查看全部 (保养过滤)", systemImage: "line.3.horizontal.decrease.circle")
                            .xFont(.subheadline, weight: .medium)
                            .foregroundStyle(XPalette.accentText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: XHit.min)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // ---------- 116/118 换电 + 1012 年度提醒 ----------
    private var swapSection: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                secLabel("换电关怀")
                NavigationLink { BatterySwapGuideView() } label: {
                Label("换电池图文指引", systemImage: "battery.100")
                .frame(minHeight: XHit.min)
                }
                LabeledRow("上次换电",
                meta.batteryChangedAt > 0 ? daysAgoText(meta.batteryChangedAt * 1000) : "未记录 (见电池档案)")
                // 1034 充电记录: 可充电型号记充电日期与时长 (纯本机台账, 与协议无关)
                Button { markCharge() } label: {
                LabeledRow("上次充电 (可充电型号)",
                care.chargeAt > 0
                ? daysAgoText(care.chargeAt) + (care.chargeLenMin > 0 ? " · \(care.chargeLenMin) 分钟" : "")
                : "未记录")
                // 2026-10-18 设计审核: 可点行补 44pt 最小触达 (ui-ux-pro-max)
                .frame(maxWidth: .infinity, minHeight: XHit.min, alignment: .leading)
                .contentShape(Rectangle())
                }
                .foregroundStyle(XPalette.text)
                XToggle("每年换电池提醒", isOn: $yearlyOn)
                if yearlyOn {
                DatePicker("提醒日期", selection: $yearlyDate, displayedComponents: .date)
                }
                Text("年度提醒在选定日期上午 10 点送达 (本地通知, 白天送达)。")
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // ---------- 1025 应急钥匙半年检 ----------
    private var ekeySection: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                secLabel("应急钥匙")
                XToggle("应急钥匙半年检提醒", isOn: $ekeyOn)
                .onChange(of: ekeyOn) { _, _ in saveEkey() }
                LabeledRow("上次打卡", care.ekeyCheckAt > 0 ? daysAgoText(care.ekeyCheckAt) : "未打卡")
                Button {
                var s = BatteryCare.care(mac)
                s.ekeyCheckAt = Date().timeIntervalSince1970 * 1000
                BatteryCare.saveCare(mac, s)
                care = s
                XHaptics.tick.impactOccurred()
                app.showToast("已打卡 — 下次半年检会重新起算", tone: .done)
                } label: {
                Label("确认应急钥匙还在 · 打卡", systemImage: "key.fill")
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: XHit.min)
                .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                Text("像消防演练一样每半年确认一次应急钥匙的位置与可用性。")
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }


    private func secLabel(_ text: String) -> some View {
        Text(text)
            .xFont(.caption, weight: .semibold)
            .foregroundStyle(XPalette.textTertiary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}


// ================= 116/1033 换电图文引导 + 118 换电复位 =================
// 1033 换电池向导与 116 是同一落点: 分步图文 (开盖-换电池-校时), 完成写记录
// (BatteryCare.recordBatterySwap 已含 1014 事件 + 采样基线), 故不单列向导页, 仅此处备案。
/// 728 换电步骤的**唯一出处**: 维护页整页 (BatterySwapGuideView) 与低电告警详情的折叠段共用这一份,
/// 免得两处各写一遍早晚漂移。原句点名的"应急供电方式"本工程无出处 (厂商云已停服、没有手册可引), 不编。
enum BatterySwapGuide {
    static func steps(modelHint: String) -> [(icon: String, title: String, detail: String)] {
        [
            ("battery.100", "备好同型号新电池", modelHint),
            ("wrench.and.screwdriver", "拆下电池盖板", "一般在室内面板, 不需要拆卸整锁"),
            ("arrow.triangle.2.circlepath", "整组换新", "不要新旧电池混用, 触点对准弹簧"),
            ("clock.arrow.circlepath", "换电后校准门锁时间", "临时密码与时间窗钥匙依赖锁钟"),
            ("checkmark.seal", "点下方「已换新」复位", "基线与低电提醒一并重置"),
        ]
    }
}

struct BatterySwapGuideView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    private var mac: String { app.current?.mac ?? "" }
    /// 当前电量 + 上次换电 + 记录按钮
    @ViewBuilder
    private var batteryNowCard: some View {
        let snap = DB.readStatus(mac)
        let pct = BatteryCare.displayPct(mac, snapshot: snap?.powerLevel ?? -1)
        let low = BatteryCare.isLow(pct)
        let lastSwap = BatteryCare.events(mac).last(where: { $0.kind == "battery" })
        let days: Int = lastSwap.map {
            Int((Date().timeIntervalSince1970 * 1000 - $0.ts) / 86_400_000)
        } ?? -1
        XPanel(kind: .hero, tone: low ? .warn : .ok) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                HStack(alignment: .firstTextBaseline, spacing: XSpace.s) {
                    Text(pct >= 0 ? String(pct) + "%" : "—")
                        .xFont(.title2, weight: .semibold)
                        .foregroundStyle(low ? XPalette.warn : XPalette.ok)
                        .monospacedDigit()
                    Text(low ? "电量偏低，建议尽快更换" : "电量充足")
                        .xFont(.footnote)
                        .foregroundStyle(low ? XPalette.warn : XPalette.textSub)
                    Spacer(minLength: 0)
                }
                if days >= 0 {
                    Text("上次换电 " + String(days) + " 天前")
                        .xFont(.caption2)
                        .foregroundStyle(XPalette.textSub)
                } else {
                    Text("还没有换电记录 —— 换好后点下面记录一次")
                        .xFont(.caption2)
                        .foregroundStyle(XPalette.textSub)
                }
                Button {
                    BatteryCare.recordBatterySwap(mac)
                    XHaptics.success()
                    app.showToast("已记录换电")
                } label: {
                    Label("我换好了", systemImage: "checkmark.seal")
                }
                .buttonStyle(XSecondaryButtonStyle())
                .disabled(mac.isEmpty)
            }
        }
        .xScrollLift()
    }

    private var modelHint: String {
        let m = LockArchive.meta(mac).batteryModel
        return m.isEmpty ? "型号见锁信息名片-电池档案" : "已记型号: \(m)"
    }
    private var steps: [(icon: String, title: String, detail: String)] {
        BatterySwapGuide.steps(modelHint: modelHint)   // 728: 与低电告警详情共用一份步骤源
    }

    var body: some View { vkBody.destined(.batterySwapGuide) }
    var vkBody: some View {
        ZStack {
            XPalette.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: XSpace.section) {
                    // 当前电量卡 —— 换电指南却不显示电量，是最大的缺口。
                    // 用户点进来就是想知道"是不是真该换了"。
                    batteryNowCard
                    XPanel(kind: .group) {
                        VStack(alignment: .leading, spacing: XSpace.m) {
                            secLabel("换电步骤")
                            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                                HStack(alignment: .top, spacing: XSpace.s) {
                                    Text("\(i + 1)")
                                        .xFont(.caption, weight: .semibold)
                                        .monospacedDigit()
                                        .foregroundStyle(XPalette.onAccent)
                                        .frame(width: 22, height: 22)
                                        .background(XPalette.accent, in: Circle())
                                        .accessibilityHidden(true)
                                    Image(systemName: s.icon)
                                        .font(.system(size: XIcon.md, weight: .medium))
                                        .foregroundStyle(XPalette.accentText)
                                        .frame(width: 30)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: XSpace.xxs) {
                                        Text(s.title)
                                            .xFont(.subheadline, weight: .medium)
                                            .foregroundStyle(XPalette.text)
                                        Text(s.detail)
                                            .xFont(.caption)
                                            .foregroundStyle(XPalette.textSub)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .padding(.vertical, XSpace.xxs)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("第 \(i + 1) 步: \(s.title), \(s.detail)")
                            }
                            Text("全程只动电池 — 不需要重置门锁, 也不需要重新配网。")
                                .xFont(.footnote)
                                .foregroundStyle(XPalette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .xScrollLift()

                    XPanel(kind: .group) {
                        VStack(alignment: .leading, spacing: XSpace.m) {
                            XBusyButton(title: "已换新", systemImage: "checkmark", busy: false) { swap() }
                            NavigationLink { SyncTimeView() } label: {
                                Label("去校准门锁时间", systemImage: "clock.arrow.circlepath")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .frame(minHeight: XHit.min)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Text("「已换新」会写入换电记录、复位低电提醒武装位, 并在电池档案记下今天。")
                                .xFont(.footnote)
                                .foregroundStyle(XPalette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .xScrollLift()
                }
                .padding(.horizontal, XSpace.gutter)
                .padding(.vertical, XSpace.l)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("换电指引")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func secLabel(_ text: String) -> some View {
        Text(text)
            .xFont(.caption, weight: .semibold)
            .foregroundStyle(XPalette.textTertiary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 118 换电复位基线: 电池档案 + 采样基线 + 通知武装位 + 1014 事件, 一次到位
    private func swap() {
        var m = LockArchive.meta(mac)
        m.batteryChangedAt = Date().timeIntervalSince1970
        LockArchive.save(mac, m)
        BatteryCare.recordBatterySwap(mac)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        app.showToast("已换新 · 基线与提醒已复位")
        app.evaluateAchievements()   // 1039 续航管家徽章结算
        dismiss()
    }
}



struct CareChecklistView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    var onDone: () -> Void = {}
    @State private var checks = [false, false, false, false, false]
    private let items: [(icon: String, label: String)] = [
        ("gearshape.2", "滑轨与把手顺滑"),
        ("lock.rotation", "锁舌伸缩顺畅"),
        ("battery.100", "电池触点无锈蚀"),
        ("touchid", "指纹头清洁"),
        ("key.fill", "应急钥匙位置确认"),
    ]

    var body: some View {
        ZStack {
            XPalette.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: XSpace.section) {
                    // 保养台账 —— 这张卡原来不存在。
                    //
                    // 清单页只让用户打勾，但**不告诉他上次是什么时候保养的**。
                    // 而三件事早就算好了：lastCareAt / carePeriodDays / ekeyCheckAt，
                    // 全在 BatteryCare.CareState 里，只是一个都没接到界面。
                    careLedgerCard
                    XPanel(kind: .group) {
                        VStack(alignment: .leading, spacing: XSpace.m) {
                            secLabel("五项清单")
                            ForEach(Array(items.enumerated()), id: \.offset) { i, it in
                                Button { checks[i].toggle() } label: {
                                    HStack(spacing: XSpace.s) {
                                        Image(systemName: checks[i] ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: XIcon.sm, weight: .semibold))
                                            .foregroundStyle(checks[i] ? XPalette.ok : XPalette.textSub)
                                            .accessibilityHidden(true)
                                        Image(systemName: it.icon)
                                            .font(.system(size: XIcon.sm, weight: .medium))
                                            .foregroundStyle(XPalette.accentText)
                                            .frame(width: 24)
                                            .accessibilityHidden(true)
                                        Text(it.label)
                                            .xFont(.subheadline)
                                            .foregroundStyle(XPalette.text)
                                        Spacer(minLength: 0)
                                    }
                                    .frame(minHeight: XHit.min)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(it.label)
                                .accessibilityAddTraits(checks[i] ? [.isSelected] : [])
                            }
                            Text("逐项确认后才能完成保养 — 汽车保养手册的严谨, 用在门上一样合适。")
                                .xFont(.footnote)
                                .foregroundStyle(XPalette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .xScrollLift()

                    XBusyButton(title: "完成保养",
                                systemImage: "checkmark.seal",
                                busy: false) {
                        complete()
                    }
                    .disabled(!checks.allSatisfy({ $0 }))
                    .opacity(checks.allSatisfy({ $0 }) ? 1 : 0.5)
                }
                .padding(.horizontal, XSpace.gutter)
                .padding(.vertical, XSpace.l)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("锁体保养")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
    }

    /// 保养台账：上次 / 周期 / 到期 / 应急钥匙
    private var careLedgerCard: some View {
        let mac = app.current?.mac ?? ""
        let state = BatteryCare.care(mac)
        // 周期只从一个地方取。这里原来自己数 `HotCache.recent(mac)` 的开门数 ——
        // 那与 `LockStats.usage()` 是**两条读法**：后者还扣掉测试标记、按协议基准换算时间窗。
        // 两个数不同就会让同一把锁在「周期档」上给出 60 / 90 两种答案。
        let period = BatteryCare.carePeriodDays(mac: mac)
        let lastMs = state.lastCareAt
        let daysSince: Int = lastMs > 0
            ? Int((Date().timeIntervalSince1970 * 1000 - lastMs) / 86_400_000)
            : -1
        let daysLeft = daysSince < 0 ? -1 : max(0, period - daysSince)
        let dueTone: Color = daysLeft < 0 ? XPalette.textTertiary
            : (daysLeft == 0 ? XPalette.danger : (daysLeft <= 14 ? XPalette.warn : XPalette.ok))
        return XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                secLabel("保养周期")
                HStack(alignment: .firstTextBaseline, spacing: XSpace.s) {
                    Text(daysLeft < 0 ? "—" : String(daysLeft))
                        .xFont(.title2, weight: .semibold)
                        .foregroundStyle(dueTone)
                        .monospacedDigit()
                    Text(daysLeft < 0 ? "还没保养过" : "天后该保养")
                        .xFont(.caption)
                        .foregroundStyle(dueTone)
                    Spacer(minLength: 0)
                    Text("周期 " + String(period) + " 天")
                        .xFont(.caption2)
                        .foregroundStyle(XPalette.textSub)
                }
                if daysSince >= 0 {
                    ledgerRow("上次保养", String(daysSince) + " 天前")
                }
                // 应急钥匙半年检 —— CareState.ekeyCheckAt 一直没显示
                if state.ekeyCheckAt > 0 {
                    let ekDays = Int((Date().timeIntervalSince1970 * 1000 - state.ekeyCheckAt) / 86_400_000)
                    ledgerRow("应急钥匙检视", String(ekDays) + " 天前")
                } else {
                    ledgerRow("应急钥匙检视", "从未记录")
                }
                // 指纹头是否需要清洁 —— BatteryCare.fpCleanNeeded 一直没显示
                if BatteryCare.fpCleanNeeded(mac) {
                    HStack(spacing: XSpace.xs) {
                        Image(systemName: "touchid")
                            .font(.system(size: XIcon.xs, weight: .semibold))
                            .foregroundStyle(XPalette.warn)
                        Text("指纹头可能需清洁")
                            .xFont(.caption2)
                            .foregroundStyle(XPalette.warn)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .xScrollLift()
    }

    private func ledgerRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: XSpace.s) {
            Text(label)
                .xFont(.caption)
                .foregroundStyle(XPalette.textSub)
            Spacer(minLength: 0)
            Text(value)
                .xFontExact(.caption.monospacedDigit())
                .foregroundStyle(XPalette.textSub)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label + " " + value)
    }

    private func secLabel(_ text: String) -> some View {
        Text(text)
            .xFont(.caption, weight: .semibold)
            .foregroundStyle(XPalette.textTertiary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func complete() {
        let mac = app.current?.mac ?? ""
        var s = BatteryCare.care(mac)
        s.lastCareAt = Date().timeIntervalSince1970 * 1000
        BatteryCare.saveCare(mac, s)
        BatteryCare.markCareToday()                      // 1030 月历打点
        BatteryCare.addEvent(mac, kind: "care", note: "五项保养完成")   // 1014
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // 2026-10-15 走查: 这句原先把 90 写死在字面量里, 而保养页自己那个 periodDays 对高频锁给的是
        // 60 —— 用户按屏上说的等 90 天, 通知却在第 60 天就来催。天数与判据取同一处。
        app.showToast("保养已记录, \(BatteryCare.carePeriodDays(mac: mac)) 天周期重新起算")
        app.evaluateAchievements()                       // 1030 爱洁之家徽章结算
        onDone()
        dismiss()
    }
}
