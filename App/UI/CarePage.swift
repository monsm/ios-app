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
            careHistoryGallery.xScrollLift()
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

    /// 审美对齐 HTML (2026-10-24): 「还剩多少」卡按 HTML 标准重写。
    ///
    /// HTML 60-care 卡1 = 卡头「还剩多少」+ **44px 大数字（天数）** + 右侧三色环
    ///   + 三列（上次保养 / 下次保养 / 周期）+ 页脚整句。
    /// 之前是 XStatCard 内的 19pt 标题 + 16pt 值 —— 数字不够大，三列也不在。
    private var periodCard: some View {
        let days = daysUntilCare
        let period = periodDays
        let elapsed = care.lastCareAt > 0 ? (period - days) : 0
        let pct = period > 0 ? min(1, max(0, Double(elapsed) / Double(period))) : 0
        return XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("还剩多少")
                        .xFont(.subheadline)
                        .foregroundStyle(XPalette.textTertiary)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .center, spacing: XSpace.l) {
                    VStack(alignment: .leading, spacing: 8) {
                        if days > 0 {
                            XHeroNumber(text: String(days), color: XPalette.warn, unit: "天")
                            Text("距离下次保养 —— 走到 0 就该动手了")
                                .xFont(.footnote)
                                .foregroundStyle(XPalette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if care.lastCareAt > 0 {
                            XHeroNumber(text: "该做", size: 34, color: XPalette.danger)
                            Text("已经过了保养周期")
                                .xFont(.footnote)
                                .foregroundStyle(XPalette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            XHeroNumber(text: "—", color: XPalette.textTertiary, unit: "天")
                            Text("保养周期尚未记录 —— 记一次就会开始倒计时")
                                .xFont(.footnote)
                                .foregroundStyle(XPalette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 4)
                    XTripleThinRing(
                        size: 92,
                        values: (pct, max(0, 1 - pct) * 0.6, 0.06),
                        colors: (XPalette.ok, XPalette.warn, XPalette.danger),
                        centerText: care.lastCareAt > 0 ? "\(Int(pct * 100))%" : "—")
                        .accessibilityHidden(true)
                }
                .padding(.top, 8)
                XHairline().padding(.vertical, 12)
                // HTML 卡1 的三列
                HStack(alignment: .top, spacing: XSpace.s) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("上次保养").xFont(.caption2).foregroundStyle(XPalette.textTertiary)
                        Text(lastCareText).xFont(.footnote, weight: .semibold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("下次保养").xFont(.caption2).foregroundStyle(XPalette.textTertiary)
                        Text(nextCareText).xFont(.footnote, weight: .semibold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("周期").xFont(.caption2).foregroundStyle(XPalette.textTertiary)
                        Text("\(period > 0 ? period : 90) 天").xFont(.footnote, weight: .semibold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if days <= 0 {
                    Button("记录本次保养") { markCare() }
                        .buttonStyle(XPrimaryButtonStyle())
                        .padding(.top, 12)
                }
                Text(periodDetail(days))
                    .xFont(.caption2)
                    .foregroundStyle(XPalette.textTertiary)
                    .padding(.top, 12)
                    .fixedSize(horizontal: false, vertical: true)
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
                Text("该做的")
                    .xFont(.subheadline)
                    .foregroundStyle(XPalette.textTertiary)
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

    /// 审美对齐 HTML (2026-10-24): 保养历史横向画廊（HTML 60-care 是横滑卡）
    private var careHistoryGallery: some View {
        let events = BatteryCare.events(mac).filter { $0.kind == "care" }.prefix(8)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: XSpace.s) {
                if events.isEmpty {
                    Text("还没有保养记录 —— 做完一次就会出现在这里")
                        .xFont(.footnote)
                        .foregroundStyle(XPalette.textTertiary)
                        .frame(width: 240, alignment: .leading)
                        .padding(XSpace.m)
                        .xPlate(XPalette.surfaceAlt.opacity(0.5), XRadius.tile)
                } else {
                    ForEach(Array(events), id: \.ts) { e in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("保养").xFont(.caption2).foregroundStyle(XPalette.textTertiary)
                            // 真实 API：TimeFormat.shortClock（TimeFormat.day / BatteryCare.daysAgoText 都不存在）
                            Text(TimeFormat.shortClock(e.ts)).xFont(.footnote, weight: .semibold)
                                .foregroundStyle(XPalette.text)
                            Text("\(TimeFormat.daysSince(ms: e.ts)) 天前").xFont(.caption2)
                                .foregroundStyle(XPalette.textTertiary)
                        }
                        .xScaledWidth(104, alignment: .leading)
                        .padding(XSpace.m)
                        .xPlate(XPalette.surfaceAlt.opacity(0.55), XRadius.tile)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

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

