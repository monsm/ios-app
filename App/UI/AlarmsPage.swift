//
//  AlarmsPage.swift
//  告警中心 · 全新重写 (2026-10-21)
//
//  门里「事件」→ 告警的落地页。
//
//  ═══════════════════════════════════════════════════════════
//  与旧 AlarmCenterView (817 行) 的区别
//  ═══════════════════════════════════════════════════════════
//
//  旧版: 告警列表 + 分类筛选 + 处置动作 + 上下文 + 时间线。
//
//  新版: 一条按紧迫度排序的告警流
//    · 未处理在最上, 已处理折叠在底
//    · 每条: 级别色条 + 类型 + 时间 + 处置按钮
//    · 处置用滑动 (系统 swipeActions), 不弹菜单
//
//  设计原则:
//    · 告警三通道: 色 + 图标 + 文字 (不只靠颜色)
//    · 处置动作就地完成, 不跳页
//    · 已处理默认折叠, 减少噪音
//

import SwiftUI

/// 告警中心
struct AlarmsPage: View {
    @EnvironmentObject private var app: AppState

    @State private var recs: [Rec] = []
    @State private var loaded = false
    @State private var showHandled = false

    private var macs: [String] { DB.keychains().map { $0.mac } }

    var body: some View {
        VStack(spacing: 0) {
            alarmsHeader
            Group {
                if !loaded {
                    ScrollView {
                        XSkeleton(blocks: 3, blockHeight: 96)
                    }
                    .scrollDisabled(true)
                } else if alarms.isEmpty && handled.isEmpty {
                    emptyState
                } else {
                    alarmList
                }
            }
        }
        .background(XPalette.canvasGradient)
        // ═══ 2026-10-24 逐页对齐 HTML 53-alarms ═══
        //
        // 与 EventsPage 同一个遗漏：这一页也是手写骨架，第 1 轮统一修 XScreen 时漏了。
        // 原写法 .navigationTitle("告警") + .large = 导航栏大标题 + 页内无标题，
        // 而 HTML 的标题「告警中心」在页内（H1 + SUB「门锁主动报上来的异常」）。
        // 顺带：标题词也不一致，HTML 是「告警中心」不是「告警」。
        .navigationBarTitleDisplayMode(.inline)
        .task { if !loaded { load() } }
        .refreshable { load() }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 数据
    // ═══════════════════════════════════════════════════════

    /// HTML 53-alarms 的页内标题区：H1「告警中心」+ SUB
    private var alarmsHeader: some View {
        VStack(alignment: .leading, spacing: XSpace.xs) {
            Text("告警中心")
                .xFont(.largeTitle, weight: .bold)
                .tracking(-0.4)
                .foregroundStyle(XPalette.text)
            Text("门锁主动报上来的异常 · 处置后不再重复提醒")
                .xFont(.body)
                .foregroundStyle(XPalette.textSub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, XSpace.gutter)
        .padding(.top, XSpace.s)
        .padding(.bottom, XSpace.m)
    }

    private func load() {
        recs = RecordSearch.buildRecs(macs: macs)
        loaded = true
    }

    /// 未处理告警
    private var alarms: [Rec] {
        recs.filter { rec in
            guard rec.alarm else { return false }
            return !RecordOverlay.isFlagged(rec.mac, rec.key)
        }
    }

    /// 已处理告警
    private var handled: [Rec] {
        recs.filter { rec in
            guard rec.alarm else { return false }
            return RecordOverlay.isFlagged(rec.mac, rec.key)
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 视图
    // ═══════════════════════════════════════════════════════

    // ── 主告警卡（仅当有紧急级未处理告警）──
    //
    // M5 形态: 告警页的核心是**紧迫感**，不是清单。
    // 所以把最紧急的一条从列表里提出来，占整块，
    // 并显示"已持续多久"—— 时间压力是紧迫感的来源。
    @ViewBuilder
    private var primaryAlarm: some View {
        if let top = alarms.first(where: { AlarmMeta.level($0.type) == 3 }) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                HStack(spacing: XSpace.s) {
                    Text(AlarmMeta.levelName(top.type))
                        .xFont(.caption2, weight: .bold)
                        .foregroundStyle(XPalette.onAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(XPalette.danger))
                    if let dur = elapsedText(top) {
                        Text("已持续 \(dur)")
                            .xFont(.caption)
                            .foregroundStyle(XPalette.danger)
                    }
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(top.typeName.isEmpty ? "告警" : top.typeName)
                        .xFont(.title3, weight: .semibold)
                        .foregroundStyle(XPalette.text)
                    Text("\(shortTime(top.timeStr)) · \(top.lockName) · 未处理")
                        .xFont(.footnote)
                        .foregroundStyle(XPalette.textSub)
                }

                HStack(spacing: XSpace.s) {
                    Button {
                        markHandled(top)
                        XHaptics.trigger.impactOccurred()
                    } label: {
                        Text("知道了")
                            .xFont(.subheadline, weight: .semibold)
                            .foregroundStyle(XPalette.onAccent)
                            .frame(maxWidth: .infinity)
                            // HIG accessibility.md: iOS 控件默认尺寸 44×44，最小 28×28。
                            // 这里原来写死 42，差 2pt；改用令牌，日后调整只改一处。
                            .frame(height: XHit.min)
                            .background(RoundedRectangle(cornerRadius: XRadius.control, style: .continuous)
                                .fill(XPalette.danger))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("标记已知悉")
                }
            }
            .padding(XSpace.card)
            .background {
                RoundedRectangle(cornerRadius: XRadius.card, style: .continuous)
                    // @contrast-allow 告警卡的淡红**底衬**，不是信息图形；
                    //   告警本身由图标与文字承担（那两者都是满色）。
                    .fill(XPalette.danger.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: XRadius.card, style: .continuous)
                            .strokeBorder(XPalette.danger.opacity(0.35), lineWidth: 1)
                    )
            }
        }
    }

    /// 告警已持续多久
    ///
    /// 解析 timeStr 得到时刻，算到现在的差值。
    /// 解析失败返回 nil —— 不硬编造一个数字。
    /// 告警已持续多久
    ///
    /// 复用 RecordSearch.dateOf(Rec) —— 它已经把 timeStr 解析成 Date
    /// 并钉了公历 (WeekCal.gregorian)。
    /// 自己再写一遍 DateFormatter 会被 lint 拦下（我第一版就是这样）。
    /// 解析失败返回 nil —— 不硬编造一个数字。
    private func elapsedText(_ rec: Rec) -> String? {
        guard let d = RecordSearch.dateOf(rec) else { return nil }
        return humanize(Date().timeIntervalSince(d))
    }

    private func humanize(_ sec: TimeInterval) -> String? {
        guard sec > 60 else { return nil }
        let m = Int(sec / 60)
        if m < 60 { return "\(m) 分钟" }
        let h = m / 60
        if h < 24 { return "\(h) 小时 \(m % 60) 分" }
        return "\(h / 24) 天"
    }

    private var alarmList: some View {
        // M5 重做: List + Section → ScrollView + XPanel 卡片流
        //
        // 组头信息（"N 条待处理" / "已处理"）保留为卡内小标题 ——
        // 那是用户扫读时的锚点，不能丢。
        ScrollView {
            // 规范 5.3 骨架: 概览 / 主告警 / 列表 / 已处理 —— 四件事, 区块间距 28。
            // 旧实现一律 16, 于是"最高级告警占整块"这个紧迫感设计被周围的等距稀释掉了。
            VStack(spacing: XSpace.section) {
                if !alarms.isEmpty {
                    severityOverview
                }

                // 主告警：最高级未处理告警占整块 —— 紧迫感的核心。
                // 它是本页**唯一的主角**, 所以它不套在卡片列表里, 单独一块。
                primaryAlarm

                if !alarms.isEmpty {
                    XPanel(kind: .group, padding: 0) {
                        VStack(spacing: 0) {
                            groupHeader("\(alarms.count) 条待处理", tone: XPalette.warn)
                            ForEach(Array(alarms.enumerated()), id: \.element.id) { idx, rec in
                                alarmRow(rec, handled: false)
                                if idx < alarms.count - 1 {
                                    XHairline()
                                        .padding(.leading, XSpace.card + 28 + XSpace.s)
                                }
                            }
                        }
                    }
                }

                if !handled.isEmpty {
                    XPanel(kind: .group, padding: 0) {
                        VStack(spacing: 0) {
                            groupHeader("已处理 \(handled.count)", tone: XPalette.textSub)
                            if showHandled {
                                ForEach(Array(handled.enumerated()), id: \.element.id) { idx, rec in
                                    alarmRow(rec, handled: true)
                                    if idx < handled.count - 1 {
                                        XHairline()
                                            .padding(.leading, XSpace.card + 28 + XSpace.s)
                                    }
                                }
                            } else {
                                Button {
                                    withAnimation(XMotion.soft) { showHandled = true }
                                } label: {
                                    HStack {
                                        Text("显示 \(handled.count) 条已处理")
                                            .xFont(.footnote)
                                            .foregroundStyle(XPalette.textSub)
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: XIcon.xs, weight: .semibold))
                                            .foregroundStyle(XPalette.textTertiary)
                                    }
                                    .padding(.horizontal, XSpace.card)
                                    .frame(minHeight: XHit.min)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, XSpace.gutter)
            .padding(.top, XSpace.m)
            .padding(.bottom, XSpace.xxl)
        }
        .background(XPalette.canvasGradient)
    }

    /// 卡内组头 —— 取代原来 Section 的 header
    private func groupHeader(_ text: String, tone: Color) -> some View {
        HStack {
            Text(text)
                .xFont(.caption, weight: .medium)
                .foregroundStyle(tone)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, XSpace.card)
        .padding(.top, XSpace.m)
        .padding(.bottom, XSpace.s)
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 严重度概览
    // ═══════════════════════════════════════════════════════

    /// 待处理告警按三级严重度分布。
    ///
    /// 告警页最该先回答的是"有多严重", 而不是"有几条"。
    /// 原来只有每行左边一根 3pt 色条, 要一行行看才拼得出全貌;
    /// 这里用一条比例横条把三级一次说完, 数字跟在后面。
    /// 「待处理」读数卡 —— 对齐 tools/proto/53-alarms.html（本轮新建的原型）。
    ///
    /// 原型结构：卡头「待处理」→ 44px 待处理数 + 单位 → 右侧三色环（一/二/三级各一圈）
    ///          → sep → 三列（一级/二级/三级）→ footer 整句（三级各自是什么意思）。
    /// 改前是「一条比例条 + 一组读数」：没有主角数字，也没有把"三级各是什么"写出来。
    private var severityOverview: some View {
        let lv3 = alarms.filter { AlarmMeta.level($0.type) == 3 }.count
        let lv2 = alarms.filter { AlarmMeta.level($0.type) == 2 }.count
        let lv1 = alarms.count - lv3 - lv2
        let total = max(alarms.count, 1)
        return XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: 0) {
                Text("待处理")
                    .xFont(.subheadline)
                    .foregroundStyle(XPalette.textTertiary)
                HStack(alignment: .center, spacing: XSpace.l) {
                    VStack(alignment: .leading, spacing: 8) {
                        XHeroNumber(
                            text: String(alarms.count),
                            color: lv3 > 0 ? XPalette.danger : (lv2 > 0 ? XPalette.warn : XPalette.ok),
                            unit: "条")
                        Text(lv3 > 0 ? "最高一级 \(lv3) 条 —— 先处置它" : "没有一级告警")
                            .xFont(.footnote)
                            .foregroundStyle(XPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    XTripleThinRing(
                        size: 92,
                        values: (Double(lv3) / Double(total),
                                 Double(lv2) / Double(total),
                                 Double(lv1) / Double(total)),
                        colors: (XPalette.danger, XPalette.warn, XPalette.ok),
                        centerText: String(alarms.count))
                        .accessibilityHidden(true)
                }
                .padding(.top, 8)
                XHairline().padding(.vertical, 12)
                HStack(alignment: .top, spacing: XSpace.s) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("一级").xFont(.caption2).foregroundStyle(XPalette.textTertiary)
                        Text("\(lv3) 条").xFont(.footnote, weight: .semibold)
                            .foregroundStyle(XPalette.danger)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("二级").xFont(.caption2).foregroundStyle(XPalette.textTertiary)
                        Text("\(lv2) 条").xFont(.footnote, weight: .semibold)
                            .foregroundStyle(XPalette.warn)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("三级").xFont(.caption2).foregroundStyle(XPalette.textTertiary)
                        Text("\(lv1) 条").xFont(.footnote, weight: .semibold)
                            .foregroundStyle(XPalette.ok)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("一级是「可能被撬或电量见底」，二级是「能用但该处理」，三级只是记录。")
                    .xFont(.caption2)
                    .foregroundStyle(XPalette.textTertiary)
                    .padding(.top, 12)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func segment(width: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(color)
            .frame(width: max(width - 2, 3))
    }

    private func severityItem(_ label: String, _ n: Int, _ color: Color) -> some View {
        HStack(spacing: XSpace.xs) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text("\(label) \(n)")
                .xFont(.caption, weight: .medium)
                .foregroundStyle(n > 0 ? XPalette.text : XPalette.textSub)
                .monospacedDigit()
                .contentTransition(.numericText())   // 标记已处理后数字滚动
                .contentTransition(.numericText())   // 标记已处理后数字滚动
        }
    }

    private func alarmRow(_ rec: Rec, handled: Bool) -> some View {
        HStack(spacing: XSpace.m) {
            // 级别色条
            RoundedRectangle(cornerRadius: 2)
                .fill(levelColor(rec).opacity(handled ? 0.3 : 1))
                .frame(width: 3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: XSpace.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: XIcon.xs, weight: .semibold))
                        .foregroundStyle(levelColor(rec).opacity(handled ? 0.5 : 1))
                        .accessibilityHidden(true)
                    Text(rec.typeName.isEmpty ? "告警" : rec.typeName)
                        .xFont(.body, weight: handled ? .regular : .medium)
                        .foregroundStyle(handled ? XPalette.textSub : XPalette.text)
                        .lineLimit(1)
                }
                Text("\(shortTime(rec.timeStr)) · \(rec.lockName)")
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.textSub)
            }

            Spacer(minLength: 0)

            if !handled {
                Button {
                    markHandled(rec)
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: XIcon.md, weight: .medium))
                        .foregroundStyle(XPalette.accent)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("标记已处理")
            }
        }
        .padding(.vertical, XSpace.xxs)
        .opacity(handled ? 0.6 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rec.typeName), \(shortTime(rec.timeStr)), \(handled ? "已处理" : "待处理")")
    }

    private var emptyState: some View {
        XEmptyState(systemImage: "checkmark.shield",
                    title: "没有告警",
                    message: "所有记录都正常。")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 动作
    // ═══════════════════════════════════════════════════════

    private func markHandled(_ rec: Rec) {
        _ = RecordOverlay.toggleFlag(rec.mac, rec.key)
        XHaptics.trigger.impactOccurred()
        withAnimation(XMotion.soft) {
            // 触发重算
            recs = recs
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 辅助
    // ═══════════════════════════════════════════════════════

    private func levelColor(_ rec: Rec) -> Color {
        let lvl = AlarmMeta.level(rec.type)
        switch lvl {
        case 3: return XPalette.danger
        case 2: return XPalette.warn
        default: return XPalette.warn.opacity(0.7)
        }
    }

    /// 时刻截取的唯一实现在 TimeFormat.shortClock。
    private func shortTime(_ full: String) -> String { TimeFormat.shortClock(full) }
}
