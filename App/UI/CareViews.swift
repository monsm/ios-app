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
    private var meta: LockMeta { LockArchive.meta(mac) }
    /// 1022 频次自适应: 高频使用锁 (近 30 天开门 ≥60 次) 保养周期自适应缩短到 60 天
    private var opens30d: Int {
        guard let u = LockStats.usage().first(where: { $0.mac == mac }) else { return 0 }
        return u.opens30d
    }
    /// 1022 频次自适应: 高频使用锁 (近 30 天开门 ≥60 次) 保养周期自适应缩短到 60 天。
    /// 判据本体在 `BatteryCare.carePeriodDays(opens30d:)` —— 通知侧与"保养已记录"那句 toast 都取同一处。
    private var periodDays: Int { BatteryCare.carePeriodDays(opens30d: opens30d) }
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
                VStack(spacing: XSpace.l) {
                    carePeriodSection
                    historySection
                    swapSection
                    ekeySection
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
                    .xFont(.caption2)
                    .foregroundStyle(XPalette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }


    // ---------- 1028 保养历史过滤 (1014 事件) ----------
    private var historySection: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                secLabel("保养历史")
                if all.isEmpty {
                // 包14 空态族消费点 (815 双按钮 / 841 小管家默认开 / 1044 便签):
                // 旧版只有一句"还没有保养或换电记录" —— 现在空态直接给出那件能做的事:
                // 主动作打开五项清单 (与下方 1015 按钮同一个 sheet, 不另起流程)。
                XGuidedEmptyView(systemImage: "checkmark.seal",
                title: "还没有保养记录",
                message: "五项清单走一遍就会在这里落下第一条; 换电完成后走「换电关怀」里的图文指引。",
                actionTitle: "开始五项保养",
                action: { showChecklist = true })
                .listRowInsets(EdgeInsets())
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
                // 先落点再收摊：sheet 不收，切过去的 Tab 就在它底下 (见本页上方那条注释)
                dismiss()
                } label: {
                Label("到记录页查看全部 (保养过滤)", systemImage: "line.3.horizontal.decrease.circle")
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: XHit.min)
                .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
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
                    .xFont(.caption2)
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
                app.showToast("已打卡 — 下次半年检会重新起算")
                } label: {
                Label("确认应急钥匙还在 · 打卡", systemImage: "key.fill")
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: XHit.min)
                .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                Text("像消防演练一样每半年确认一次应急钥匙的位置与可用性。")
                    .xFont(.caption2)
                    .foregroundStyle(XPalette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
            ("clock.arrow.circlepath", "换电后校准门锁时间", "临时密码与时间窗凭证依赖锁钟"),
            ("checkmark.seal", "点下方「已换新」复位", "基线与低电提醒一并重置"),
        ]
    }
}

struct BatterySwapGuideView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    private var mac: String { app.current?.mac ?? "" }
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
                VStack(spacing: XSpace.l) {
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
                                .xFont(.caption2)
                                .foregroundStyle(XPalette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

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
                                .xFont(.caption2)
                                .foregroundStyle(XPalette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
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
                VStack(spacing: XSpace.l) {
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
                                .xFont(.caption2)
                                .foregroundStyle(XPalette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

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
