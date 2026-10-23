// ================= 关怀提醒与公告板 =================
// 2026-10-20: 从被删除的 AchievementsView.swift 中独立出来 (Q11 只删成就页, 关怀提醒保留)。
import SwiftUI

// ================= 关怀提醒与公告板 (1010/991/1044) =================
struct CareRemindersView: View {
    @EnvironmentObject var app: AppState
    @State private var bulletin = Milestones.bulletin

    var body: some View { vkBody.destined(.careReminders) }
    var vkBody: some View {
        ZStack {
            XPalette.canvasGradient.ignoresSafeArea()

        // 2026-10-23：改用 XScreen（规范 §5.3 骨架 / §5.4 对齐线）。
        // 改前是手写 ScrollView + VStack(section) + 各自的 padding 与 background。
        XScreen("关怀提醒", style: .inline) {
                // 六图改造 (2026-10-23): 顶部加**图 5 读数卡**（44px 最近多少天 + 环）。
                //
                // 这一页存在的意义就是"提醒"，提醒的第一要义是**还剩多久**。
                // 之前最近的那个日子埋在三张卡里的一行 —— 用户要自己扫一遍才知道"最近是几天后"。
                countdownHeroCard.xScrollLift()
                bulletinCard.xScrollLift()
                annivCard.xScrollLift()
                bdayCard.xScrollLift()
        }
            .scrollIndicators(.hidden)
        }
        .onDisappear {
            Milestones.bulletin = bulletin.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// 图 5 读数卡：44px "最近还有几天" + 环（越近越满）
    private var countdownHeroCard: some View {
        // 汇总：纪念日 + 成员生日里最近的那个
        var candidates: [Int] = []
        let anniv = Milestones.bondDay   // 结缘日就是本页的"纪念日"（String 非可选，不要 ??）
        if !anniv.isEmpty {
            let d = daysUntil(anniv)
            if d >= 0 { candidates.append(d) }
        }
        for m in DB.members() {
            let md = Milestones.memberBirthdays()[m.id] ?? ""
            if !md.isEmpty {
                let d = daysUntil(md)
                if d >= 0 { candidates.append(d) }
            }
        }
        let nearest = candidates.min()
        return XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("最近的纪念")
                        .xFont(.subheadline)
                        .foregroundStyle(XPalette.textTertiary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(XPalette.textTertiary.opacity(0.6))
                }
                HStack(alignment: .center, spacing: XSpace.l) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let n = nearest {
                            XHeroNumber(
                                text: String(n),
                                unit: n == 0 ? "今天" : "天后",
                                color: n <= 7 ? XPalette.warn : XPalette.accentText)
                            Text(n == 0 ? "就是今天 —— 别忘了说一句" : "到那天早上 9 点会提醒一次")
                                .xFont(.footnote)
                                .foregroundStyle(XPalette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            XHeroNumber(text: "—", color: XPalette.textTertiary, unit: "还没填")
                            Text("在下面填了纪念日或生日，这里才会倒计时")
                                .xFont(.footnote)
                                .foregroundStyle(XPalette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 4)
                    XGradientDial(
                        size: 70,
                        progress: nearest == nil ? 0.02 : max(0.04, 1 - Double(min(nearest!, 60)) / 60),
                        widthRatio: 0.13,
                        showsCursor: false,
                        showsTick: false,
                        gradient: (nearest ?? 99) <= 7 ? XGradient.dial : XGradient.dialOK
                    ) { EmptyView() }
                    .accessibilityHidden(true)
                }
                .padding(.top, 8)
            }
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 家庭公告板
    // ═══════════════════════════════════════════════════════

    /// 距离某个 MM-dd 还有几天（0 = 今天，-1 = 日期无效）
    ///
    /// 原来只显示 "MM-dd"，用户得自己算。而这个页面存在的意义
    /// 就是"提醒"，提醒的第一要义是**还剩多久**。
    private func daysUntil(_ md: String) -> Int {
        let parts = md.split(separator: "-")
        guard parts.count == 2,
              let mo = Int(parts[0]), let dy = Int(parts[1]),
              (1...12).contains(mo), (1...31).contains(dy) else { return -1 }
        let cal = WeekCal.gregorian
        let now = Date()
        var comps = cal.dateComponents([.year], from: now)
        comps.month = mo
        comps.day = dy
        comps.hour = 0; comps.minute = 0; comps.second = 0
        guard var target = cal.date(from: comps) else { return -1 }
        // 今年的已过 → 算明年
        if target < cal.startOfDay(for: now) {
            comps.year = (comps.year ?? 0) + 1
            guard let next = cal.date(from: comps) else { return -1 }
            target = next
        }
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: target).day ?? -1
    }

    /// 倒计时文案
    private func countdownText(_ days: Int) -> String {
        if days < 0 { return "未填写" }
        if days == 0 { return "今天" }
        if days == 1 { return "明天" }
        if days <= 30 { return "\(days) 天后" }
        return "\(days) 天后"
    }

    /// 倒计时配色：今天/明天高亮，30 天内提醒，其余低调
    private func countdownTone(_ days: Int) -> Color {
        if days < 0 { return XPalette.textTertiary }
        if days <= 1 { return XPalette.accent }
        if days <= 30 { return XPalette.warn }
        return XPalette.textSub
    }

    private var bulletinCard: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                secLabel("家庭公告板")
                TextField("写一句常驻家里的话", text: $bulletin)
                    .xFont(.body)
                    .submitLabel(.done)
                    .onSubmit {
                        Milestones.bulletin = bulletin.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    .padding(XSpace.s)
                    .background(XPalette.surfaceSunken,
                                in: RoundedRectangle(cornerRadius: XRadius.min, style: .continuous))
                Text("这句便签已贴在这几处空态旁: 设备页、记录页, 以及走引导空态卡的页面 (设置门锁空态、成就陈列架、维护历史、诊断日志)。未接入的空态不会偷偷显示。")
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 纪念日
    // ═══════════════════════════════════════════════════════

    private var annivCard: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                secLabel("纪念日")
                LabeledRow("结缘日", Milestones.bondDay.isEmpty ? "添加门锁后自动记录" : Milestones.bondDay)
                XToggle("结缘纪念日提醒", isOn: Binding(
                    get: { CareReminders.annivOn },
                    set: { on in
                        DB.store.set("kf_care_anniv", on)
                        Task { await CareReminders.reschedule() }
                    }))
            }
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 成员生日
    // ═══════════════════════════════════════════════════════

    private var bdayCard: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                secLabel("成员生日")
                XToggle("成员生日提醒 (提前一天)", isOn: Binding(
                    get: { CareReminders.bdayOn },
                    set: { on in
                        DB.store.set("kf_care_bday", on)
                        Task { await CareReminders.reschedule() }
                    }))
                // 按"还有几天"排序 —— 最近要过生日的排最上面
                let rows = DB.members().map { m -> (Member, String, Int) in
                    let md = Milestones.memberBirthdays()[m.id] ?? ""
                    return (m, md, md.isEmpty ? 9999 : daysUntil(md))
                }.sorted { $0.2 < $1.2 }

                ForEach(rows, id: \.0.id) { (m, md, days) in
                    HStack(spacing: XSpace.s) {
                        Text(m.name)
                            .xFont(.subheadline)
                            .foregroundStyle(XPalette.text)
                        Spacer(minLength: XSpace.m)
                        if !md.isEmpty {
                            Text(md)
                                .xFontExact(.caption.monospacedDigit())
                                .foregroundStyle(XPalette.textSub)
                        }
                        Text(countdownText(days))
                            .xFontExact(.subheadline.monospacedDigit())
                            .foregroundStyle(countdownTone(days))
                            .frame(minWidth: 56, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(m.name + (md.isEmpty ? " 未填写生日" : " 生日 " + md + ", " + countdownText(days)))
                }
                Text("生日在 设置-成员管理-补全信息 里填写 (格式 MM-dd)。提醒通过本地通知送达, 全程离线, 不依赖任何服务器。")
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
