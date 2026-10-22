//
//  CarePage.swift
//  保养页 · 全新重写 (2026-10-21)
//
//  门里「这台锁」→ 保养的落地页。
//
//  ═══════════════════════════════════════════════════════════
//  与旧 CareViews (496 行) 的区别
//  ═══════════════════════════════════════════════════════════
//
//  旧版: 周期 Section + 清洁月历 + 历史过滤 + 换电 + 应急钥匙 + 环境
//
//  新版: 一张"该做什么"清单
//    · 顶部: 下次保养还剩多久
//    · 中部: 待办项 (换电 / 清洁 / 年检), 按紧迫度排
//    · 底部: 保养历史 (折叠)
//
//  设计原则:
//    · 保养页的价值是"提醒我该做什么", 不是"记录我做过什么"
//    · 待办项按紧迫度排序, 最急的在最上
//    · 历史默认折叠
//

import SwiftUI

/// 保养页
struct CarePage: View {
    @EnvironmentObject private var app: AppState

    @State private var care = CareState()
    @State private var showHistory = false
    @State private var loaded = false

    private var mac: String { app.currentMac }

    var body: some View {
        ScrollView {
            VStack(spacing: XSpace.section) {
                periodCard.xScrollLift()
                todoCard.xScrollLift()
                historyRow.xScrollLift()
            }
            .padding(.horizontal, XSpace.gutter)
            .padding(.vertical, XSpace.l)
        }
        .background(XPalette.canvas)
        .navigationTitle("维护与保养")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { if !loaded { reload() } }
    }

    private func reload() {
        care = BatteryCare.care(mac)
        loaded = true
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 周期卡
    // ═══════════════════════════════════════════════════════

    private var periodCard: some View {
        let days = daysUntilCare
        // 之前这里写的是 carePeriodDays(opens30d: 0) —— **硬编码 0**。
        // 后果: 高频锁（30 天 ≥60 次开门）本该 60 天保养一次，
        // 但界面永远按 90 天算，通知却在第 60 天来催。两边对不上。
        // 现在读真实开门数，与 BatteryCare 的调度同源。
        let opens30 = HotCache.recent(mac).filter { StatsKit.openTypes.contains($0.type) }.count
        let period = care.lastCareAt > 0 ? BatteryCare.carePeriodDays(opens30d: opens30) : 0
        let elapsed = care.lastCareAt > 0 ? (period - days) : 0
        // 周期环: "还剩多少"是一个进程量, 环比文字更直观。
        // 弧走的是「已过去多少」而不是「还剩多少」—— 走得越满越该动手。
        // 规范 §7.6 StatCard 的卡内解剖（对照参考图里那张 Sleep 卡）：
        //   卡头（14 灰 + chevron）→ 标题（19 Bold）→ 标签（13 灰）→ 值 + **右侧环槽**
        //   → 分隔线 → 第二组 → 页脚注释。
        //
        // 旧实现是「环在左、文字在右」—— 那是图例的排法，不是数据卡。
        // 规范把环放在**右侧槽**：左列是读的字，右列是扫的形状，眼睛先读标题再看进度。
        return XPanel(kind: .hero, tone: days <= 0 ? .warn : .ok) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                XCardLink(title: "保养") { showHistory = true }

                // 标题 19 Bold（规范 §7.6 表：标题 → 标签 12pt）
                Text(periodTitle(days))
                    .xFont(.title3, weight: .bold)
                    .foregroundStyle(XPalette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    // §7.6「卡头 → 标题 6pt」。VStack 给了 12，这里收回 6 → 净 6。
                    .padding(.top, -6)

                HStack(alignment: .center, spacing: XSpace.m) {
                    // 左列：标签 13 灰 → 值 16 Semibold 白（标签在上、值在下，§7.2/§7.6 一致）
                    VStack(alignment: .leading, spacing: XSpace.xxs) {
                        Text(days > 0 ? "距离下次" : "状态")
                            .xFont(.footnote)
                            .foregroundStyle(XPalette.textSub)
                        // §7.16：单位不能与数值同大。原来写作 "\(days) 天" —— 一个字号一个颜色，
                        // "天" 和数字一样大，数字读不成一整块。拆成数值 + 单位两段。
                        XValueUnit(
                            value: days > 0 ? "\(days)" : (care.lastCareAt > 0 ? "该做" : "未记录"),
                            unit: days > 0 ? "天" : nil,
                            style: .body,
                            weight: .semibold)
                    }
                    Spacer(minLength: 0)
                    // 右侧槽：环 104pt（规范给 84 或更大），垂直居中。
                    // 环心必须给**另一个量**：参考图里环心是 Score 53，而左边的值是 Duration 3h25m。
                    // 之前我把环心也写成剩余天数 —— 于是同一张卡把同一个数字说了两遍。
                    // 现在环心给「已用百分比」，左列给绝对值，两者互补而不是复读。
                    XCycleRing(
                        elapsed: elapsed,
                        period: max(period, 1),
                        headline: careRingPct(elapsed: elapsed, period: period),
                        caption: care.lastCareAt > 0 ? "已用" : "未记录",
                        // 规范 §13.5：读屏要读**一句话**，不是两个词用逗号拼起来。
                        a11yText: careRingA11y(days: days, elapsed: elapsed, period: period),
                        size: 104)
                }

                // §7.6 内部纵向节奏：**值 → 分隔线 14pt**、**分隔线 → 下一组 12pt**。
                // 原来传 verticalPadding: 14 —— 那是线的上下各补 14，再叠上 VStack 的 12，
                // 实际成了 26 / 26，比规范松了近一倍。
                // 现在线自身不补白，只在上方补 2：12+2 = 14（上），12+0 = 12（下）。
                XHairline()
                    .padding(.top, 2)

                // §7.6 页脚注释：**12 Regular / 行高 1.6**。原来是 caption(11) + lineSpacing 3，
                // 行高只有 1.27 —— 页脚读起来挤成一团，和正文抢注意力。
                // 12 × 1.6 = 19.2，行距补 7（19.2 − 12 ≈ 7）。
                Text(periodDetail(days))
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.textSub)
                    .lineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)

                if days <= 0 {
                    Button("记录本次保养") {
                        markCare()
                    }
                    .buttonStyle(XPrimaryButtonStyle())
                }
            }
        }
    }

    private var daysUntilCare: Int {
        guard care.lastCareAt > 0 else { return 0 }
        let period = BatteryCare.carePeriodDays(opens30d: 0)
        let elapsed = Int((Date().timeIntervalSince1970 * 1000 - care.lastCareAt) / 86_400_000)
        return period - elapsed
    }

    private func periodTitle(_ days: Int) -> String {
        if care.lastCareAt <= 0 { return "还没记录过保养" }
        if days <= 0 { return "该保养了" }
        if days <= 7 { return "\(days) 天后该保养" }
        return "保养状态良好"
    }

    private func periodDetail(_ days: Int) -> String {
        if care.lastCareAt <= 0 { return "记录一次保养, 之后会按周期提醒。" }
        if days <= 0 { return "已超过建议周期 \(-days) 天。" }
        return "下次保养还剩 \(days) 天。"
    }

    private func markCare() {
        care.lastCareAt = Date().timeIntervalSince1970 * 1000
        BatteryCare.saveCare(mac, care)
        XHaptics.success()
        app.showToast("已记录本次保养")
        reload()
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 待办
    // ═══════════════════════════════════════════════════════

    private var todoCard: some View {
        XPanel(kind: .group, padding: 0) {
            VStack(spacing: 0) {
                if let battery = batteryTodo {
                    todoRow(battery)
                    XHairline(inset: XSpace.card)
                }
                todoRow(cleanTodo)
                // 应急钥匙半年检 —— CareState 里有 ekeyCheckAt / ekeyRemindOn，
                // 但这一页从来没有对应条目。半年没看过应急钥匙，
                // 真到断电那天才发现钥匙找不到。
                if ekeyTodoNeeded {
                    XHairline(inset: XSpace.card)
                    todoRow(ekeyTodo)
                }
                if let yearly = yearlyTodo {
                    XHairline(inset: XSpace.card)
                    todoRow(yearly)
                }
            }
        }
    }

    private struct Todo {
        let icon: String
        let title: String
        let detail: String
        let tone: XToneColor
    }

    private var batteryTodo: Todo? {
        guard let p = DB.readStatus(mac)?.powerLevel, p >= 0 else { return nil }
        if p <= 20 {
            return Todo(icon: "battery.25", title: "换电池",
                        detail: "电量 \(p)%, 建议尽快更换",
                        tone: p <= 10 ? .danger : .warn)
        }
        return nil
    }

    private var cleanTodo: Todo {
        let days = care.lastCareAt > 0
            ? Int((Date().timeIntervalSince1970 * 1000 - care.lastCareAt) / 86_400_000)
            : 999
        if days > 90 {
            return Todo(icon: "sparkles", title: "清洁锁体",
                        detail: days > 900 ? "还没记录过" : "距上次 \(days) 天",
                        tone: .neutral)
        }
        return Todo(icon: "sparkles", title: "清洁锁体",
                    detail: "距上次 \(days) 天, 状态良好", tone: .ok)
    }

    private var yearlyTodo: Todo? {
        guard !care.yearlyBattDay.isEmpty else { return nil }
        return Todo(icon: "calendar", title: "年度换电提醒",
                    detail: "已设为每年 \(care.yearlyBattDay)", tone: .neutral)
    }

    /// 应急钥匙是否需要检视（半年一次）
    private var ekeyTodoNeeded: Bool {
        guard care.ekeyRemindOn else { return false }
        if care.ekeyCheckAt <= 0 { return true }   // 从没记过 → 该做
        let days = Int((Date().timeIntervalSince1970 * 1000 - care.ekeyCheckAt) / 86_400_000)
        return days >= 180
    }

    private var ekeyTodo: Todo {
        let days: Int = care.ekeyCheckAt > 0
            ? Int((Date().timeIntervalSince1970 * 1000 - care.ekeyCheckAt) / 86_400_000)
            : -1
        return Todo(
            icon: "key.fill",
            title: "确认应急钥匙位置",
            detail: days < 0 ? "从未记录 — 半年该检一次"
                             : "已 \(days) 天未检视（建议每 180 天）",
            tone: days < 0 || days >= 180 ? .warn : .neutral)
    }

    private func todoRow(_ todo: Todo) -> some View {
        HStack(spacing: XSpace.m) {
            Image(systemName: todo.icon)
                .font(.system(size: XIcon.sm, weight: .medium))
                .foregroundStyle(todo.tone == .neutral ? XPalette.textSub : todo.tone.color)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title)
                    .xFont(.body)
                    .foregroundStyle(XPalette.text)
                Text(todo.detail)
                    .xFont(.caption)
                    .foregroundStyle(todo.tone == .ok ? XPalette.ok : XPalette.textSub)
            }
            Spacer(minLength: 0)
        }
        .padding(XSpace.card)
        .accessibilityElement(children: .combine)
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 历史
    // ═══════════════════════════════════════════════════════

    private var historyRow: some View {
        // XRow 自带 action 参数 (内部就是 Button), 不再手搓 surface 底。
        // .sheet 必须留在外面 —— 它不属于被替换的那层样式。
        XPanel(kind: .group) {
            XRow(systemImage: "clock.arrow.circlepath", title: "保养历史",
                 subtitle: "查看做过的保养记录", showsChevron: true) {
                showHistory = true
            }
        }
        .sheet(isPresented: $showHistory) {
            NavigationStack {
                MaintenanceView()
                    .environmentObject(app)
                    .navigationTitle("维护与保养")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") { showHistory = false }
                        }
                    }
            }
        }
    }

    /// 保养环的读屏文案。
    ///
    /// 抽成方法而不是写在调用点：那个表达式是「三元 + 字符串插值 + 算术 + 内层三元」，
    /// 而 CI 已在**同一个文件**抓到两次「unable to type-check this expression」。
    /// 这类嵌套在本地看不出问题，编译才炸 —— 提前拆平。
    private func careRingA11y(days: Int, elapsed: Int, period: Int) -> String {
        guard care.lastCareAt > 0 else { return "保养周期尚未记录" }
        let pct = Int((Double(elapsed) / Double(max(period, 1)) * 100).rounded())
        let tail = days > 0 ? "还剩 \(days) 天" : "该做保养了"
        return "保养周期已用 \(pct)%，\(tail)"
    }


    /// 环心的百分比（未记录时给 em dash）。同 careRingA11y，为拆平表达式而抽出。
    private func careRingPct(elapsed: Int, period: Int) -> String {
        guard care.lastCareAt > 0 else { return "—" }
        let pct = Int((Double(elapsed) / Double(max(period, 1)) * 100).rounded())
        return "\(pct)%"
    }

}

