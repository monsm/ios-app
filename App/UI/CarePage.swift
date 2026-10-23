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
        // 2026-10-23：改用 XScreen（规范 §5.3 / §5.4 的骨架组件）。
        //
        // 改前这里是手写的：ScrollView + VStack(section) + padding(.horizontal, gutter)
        // + padding(.vertical, .l)。四个页面各写各的版本 —— 顶部留白全仓有 12 种写法。
        // 现在骨架归组件管，本页只声明「有哪几张卡」。
        XScreen("维护与保养", subtitle: "机械件也该有保养记录") {
            periodCard.xScrollLift()
            todoCard.xScrollLift()
            historyRow.xScrollLift()
        }
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
        // 周期只从一个地方取（`BatteryCare.carePeriodDays(mac:)`）——
        // 这里原来自己算一份 opens30，与 daysUntilCare 的算法不同源，两处会给出不同的天数。
        let period = periodDays
        let elapsed = care.lastCareAt > 0 ? (period - days) : 0
        // 周期环: "还剩多少"是一个进程量, 环比文字更直观。
        // 弧走的是「已过去多少」而不是「还剩多少」—— 走得越满越该动手。
        // 规范 §7.6 StatCard 的卡内解剖（对照参考图里那张 Sleep 卡）：
        //   卡头（14 灰 + chevron）→ 标题（19 Bold）→ 标签（13 灰）→ 值 + **右侧环槽**
        //   → 分隔线 → 第二组 → 页脚注释。
        //
        // 旧实现是「环在左、文字在右」—— 那是图例的排法，不是数据卡。
        // 规范把环放在**右侧槽**：左列是读的字，右列是扫的形状，眼睛先读标题再看进度。
        // 2026-10-23：改用 `XStatCard`（规范 §7.6 的组件）。
        //
        // 这一张卡此前是**手写** §7.6 的节奏：卡头 → 负 padding 收 6 → 值 → 补 2 让线距成 14
        // → 页脚 12pt + lineSpacing 7。每一处都要单独算、单独注释，而且算错一次就「松一圈」。
        //
        // 现在节奏归组件管：XStatCard 给卡头/页脚/线的净距，XStatSection 给段间。
        // 页面只负责「这一段放什么内容」。
        return XStatCard(
            headerTitle: "保养",
            headerAction: { showHistory = true },
            footer: periodDetail(days)
        ) {
            XStatSection(isFirst: true) {
                VStack(alignment: .leading, spacing: XSpace.m) {
                    Text(periodTitle(days))
                        .xFont(.title2, weight: .bold)   // §7.6 标题 19 Bold
                        .foregroundStyle(XPalette.text)
                        .fixedSize(horizontal: false, vertical: true)
        
                    HStack(alignment: .center, spacing: XSpace.m) {
                        VStack(alignment: .leading, spacing: XSpace.xxs) {
                            Text(days > 0 ? "距离下次" : "状态")
                                .xFont(.footnote)
                                .foregroundStyle(XPalette.textSub)
                            XValueUnit(
                                value: days > 0 ? "\(days)" : (care.lastCareAt > 0 ? "该做" : "未记录"),
                                unit: days > 0 ? "天" : nil,
                                style: .headline,   // §7.6 值 16 Semibold
                                weight: .semibold)
                        }
                        Spacer(minLength: 0)
                        XCycleRing(
                            elapsed: elapsed,
                            period: max(period, 1),
                            headline: careRingPct(elapsed: elapsed, period: period),
                            caption: care.lastCareAt > 0 ? "已用" : "未记录",
                            a11yText: careRingA11y(days: days, elapsed: elapsed, period: period),
                            size: 104)
                    }
        
                    if days <= 0 {
                        Button("记录本次保养") {
                            markCare()
                        }
                        .buttonStyle(XPrimaryButtonStyle())
                    }
                }
            }
            // 第二段 —— 规范 §7.6 的卡内解剖是「线 → 第二组 → 线 → 页脚」。
            // 参考图 3 的 Sleep 卡第二段是 Bedtime / 10:30 PM / Avg: 2:19 AM，
            // 即「这一组读数背后的两个具体事实」。
            // 本卡对应的是：上次保养是哪天、当前按多少天算。
            XStatSection {
                HStack(alignment: .top, spacing: XSpace.xl) {
                    VStack(alignment: .leading, spacing: XSpace.xxs) {
                        Text("上次保养")
                            .xFont(.footnote)
                            .foregroundStyle(XPalette.textSub)
                        Text(lastCareText)
                            .xFont(.body, weight: .semibold, design: .rounded)
                            .foregroundStyle(XPalette.text)
                        Text("周期 \(periodDays > 0 ? periodDays : 90) 天")
                            .xFont(.footnote)
                            .foregroundStyle(XPalette.textTertiary)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: XSpace.xxs) {
                        Text("下次保养")
                            .xFont(.footnote)
                            .foregroundStyle(XPalette.textSub)
                        Text(nextCareText)
                            .xFont(.body, weight: .semibold, design: .rounded)
                            .foregroundStyle(XPalette.text)
                    }
                }
            }
        }
    }

    /// 上次保养距今几天（第二段左列）。
    ///
    /// 用「距上次 N 天」而不是日期字符串 —— 本页已有这个惯例
    /// （`cleanTodo` 的 detail 就是「距上次 \(days) 天」），两处必须同一个说法，
    /// 否则同一张卡会同时说「2026-10-18」和「距上次 5 天」两件事。
    private var lastCareText: String {
        guard care.lastCareAt > 0 else { return "未记录" }
        let d = TimeFormat.daysSince(ms: care.lastCareAt)
        return d <= 0 ? "今天" : "\(d) 天前"
    }
    /// 下次保养还剩几天（第二段右列）—— 与左列互补，不是复读：
    /// 左列回答「上次什么时候」，右列回答「下次什么时候该动手」。
    private var nextCareText: String {
        guard care.lastCareAt > 0 else { return "—" }
        let d = daysUntilCare
        return d > 0 ? "\(d) 天后" : "该做了"
    }

    /// 距离下次保养还有几天。
    ///
    /// **2026-10-23 修一个同页自相矛盾的 bug**：这里原来写死 `carePeriodDays(opens30d: 0)`，
    /// 也就是**永远按 90 天算**；而同一张卡片的 `periodCard` 用的是真实开门数（高频锁 60 天）。
    /// 于是高频锁会看到「环已转满 100%（60 天到了）」，标题却还写着「N 天后该保养」（按 90 天算）——
    /// 同一个数在一张卡上说两遍，而且两遍不一样。
    ///
    /// `BatteryCare.carePeriodDays(mac:)` 是那档口径的**唯一正确读法**（与通知侧同源）。
    private var periodDays: Int {
        care.lastCareAt > 0 ? BatteryCare.carePeriodDays(mac: mac) : 0
    }

    private var daysUntilCare: Int {
        guard care.lastCareAt > 0 else { return 0 }
        let elapsed = Int((Date().timeIntervalSince1970 * 1000 - care.lastCareAt) / 86_400_000)
        return periodDays - elapsed
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

