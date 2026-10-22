import SwiftUI

// ═══════════════════════════════════════════════════════════════════════
// MARK: - 诊断与自检
// ═══════════════════════════════════════════════════════════════════════
//
// 这一屏补的是一个**计划内、但丢了**的界面：
// `App/Core/swift` 有 642 行、十来组采集器（自检 / 数据健康 / 异常退出 /
// 启动耗时 / 最近操作 / 蓝牙遥测 / 日志保留 / 页面耗时），
// 而全仓 UI **零消费** —— 采了半天没有任何地方显示。
//
// 连环后果是两处假承诺（本轮一并修掉）：
//   · 自检横幅按钮写着「去诊断」，落点名 `diag` 指向一个不存在的页面
//   · 自检 toast 写着「详见「设置-诊断」」
//
// 这里只显示**能行动的信息**：通过/不通过、哪一项坏了、要不要清理。
// 不做仪表盘式的堆砌 —— 诊断页的价值是"看完知道下一步"，不是"数字很多"。
struct DiagnosticsPage: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var copied = false
    /// 处置动作之后要重新读一遍 DB —— 这些数据都是计算属性，靠它触发重算。
    @State private var revision = 0
    @State private var retention = DB.store.getString("kf_diag_log_retention")
    @State private var opsOn = DiagOps.isOn()

    /// ⚠ 这些原来都是**计算属性**：每次 body 求值都重算一遍。
    /// 而 `SelfCheck.run()` 会走全库指纹 + 审计链重算，`integrity()` 会遍历
    /// UserDefaults 的每个键，`gapDays` 会对每把锁读一遍日志。
    /// 这一页有 6 张卡，滚动一下就会触发多次全量体检 —— 真机上表现为卡顿甚至闪退。
    /// 改成"进入时算一次，动作后重算"（revision 变更时刷新）。
    @State private var selfChecks: [SelfCheckLine] = []
    @State private var health: [String] = []
    /// 451 空洞日期检测：日志覆盖区间内整天没有任何条目的日期。
    /// 这个函数一直零调用 —— 而"数据健康"这一块正好是它的位置。
    /// 它只报**两侧都有数据**的内部空洞（首尾没数据不算缺口），所以不会把"刚装上还没记录"报成问题。
    @State private var gapDays: [String] = []

    /// 体检一次，写进 @State（body 里只读）。
    private func refresh() {
        selfChecks = SelfCheck.run()
        health = DataHealth.integrity()
        gapDays = DB.keychains().flatMap { DataHealth.gapDays(mac: $0.mac) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: XSpace.section) {
                let _ = revision
                selfCheckCard
                healthCard
                stabilityCard
                opsCard
                bleCard
                retentionCard
                actionsCard
            }
            .padding(.horizontal, XSpace.gutter)
            .padding(.vertical, XSpace.l)
        }
        .background(XPalette.canvas)
        .task { refresh() }
        .onChange(of: revision) { _, _ in refresh() }
        .navigationTitle("诊断与自检")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(copied ? "已复制" : "复制") {
                    UIPasteboard.general.string = fullReport()
                    copied = true
                    XHaptics.success()
                }
                .xFont(.subheadline, weight: .medium)
                .accessibilityLabel("复制全部诊断信息")
            }
        }
    }

    // ── 自检 ──────────────────────────────────────────────
    private var selfCheckCard: some View {
        let lines = selfChecks
        let bad = lines.filter { !$0.ok }.count
        return XPanel(kind: .group, padding: 0) {
            VStack(spacing: 0) {
                header("本机自检", tone: bad == 0 ? XPalette.ok : XPalette.warn)
                HStack(spacing: XSpace.s) {
                    Image(systemName: bad == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: XIcon.md, weight: .semibold))
                        .foregroundStyle(bad == 0 ? XPalette.ok : XPalette.warn)
                        .accessibilityHidden(true)
                    Text(SelfCheck.summary(lines))
                        .xFont(.subheadline, weight: .medium)
                        .foregroundStyle(XPalette.text)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, XSpace.card)
                .padding(.bottom, XSpace.m)

                ForEach(Array(lines.enumerated()), id: \.offset) { idx, l in
                    HStack(alignment: .top, spacing: XSpace.s) {
                        Image(systemName: l.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: XIcon.sm, weight: .semibold))
                            .foregroundStyle(l.ok ? XPalette.ok : XPalette.danger)
                            .frame(width: 22)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l.name).xFont(.footnote, weight: .medium)
                                .foregroundStyle(XPalette.text)
                            Text(l.detail).xFont(.caption)
                                .foregroundStyle(XPalette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, XSpace.card)
                    .padding(.vertical, XSpace.s)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(l.name)：\(l.ok ? "通过" : "异常")，\(l.detail)")
                    if idx < lines.count - 1 { XHairline(inset: XSpace.card) }
                }
            }
        }
    }

    // ── 数据健康 ──────────────────────────────────────────
    private var healthCard: some View {
        XPanel(kind: .group, padding: 0) {
            VStack(spacing: 0) {
                header("数据健康", tone: health.isEmpty ? XPalette.ok : XPalette.warn)
                if health.isEmpty && gapDays.isEmpty {
                    itemRow(icon: "checkmark.circle.fill", tone: XPalette.ok,
                            title: "没有发现数据问题",
                            detail: "数据键都能解析，也没有孤立文件或日志断档")
                } else {
                    ForEach(Array(health.enumerated()), id: \.offset) { _, s in
                        itemRow(icon: "exclamationmark.triangle.fill", tone: XPalette.warn,
                                title: s, detail: nil)
                    }
                    if !gapDays.isEmpty {
                        itemRow(icon: "calendar.badge.exclamationmark", tone: XPalette.warn,
                                title: "日志有 \(gapDays.count) 天没有记录",
                                detail: gapDays.prefix(3).joined(separator: " · ")
                                        + (gapDays.count > 3 ? " 等" : ""))
                    }
                    // （孤儿数据已在上面 health 里以"孤儿数据: …"的形式列出）
                }
            }
        }
    }

    // ── 稳定性 ────────────────────────────────────────────
    private var stabilityCard: some View {
        let startup = StartupTrace.totalMs
        let crashed = CrashGuard.pendingAbnormal
        return XPanel(kind: .group, padding: 0) {
            VStack(spacing: 0) {
                header("稳定性", tone: crashed ? XPalette.warn : XPalette.ok)
                // 这里说"最近"，不说"上次"：pending 现在会在下一次正常启动时自动清掉，
                // 而档案里可能还留着多次历史 —— 说"上次"会让人以为是刚才那次。
                itemRow(icon: crashed ? "bolt.trianglebadge.exclamationmark.fill" : "checkmark.circle.fill",
                        tone: crashed ? XPalette.warn : XPalette.ok,
                        title: crashed ? "最近有一次异常退出" : "最近一次是正常退出",
                        detail: crashed ? "不是崩溃上报，只是本机记录到会话没有正常结束" : nil)
                XHairline(inset: XSpace.card)
                itemRow(icon: startup > 800 ? "clock.badge.exclamationmark" : "clock",
                        tone: startup > 800 ? XPalette.warn : XPalette.textSub,
                        title: String(format: "本次启动 %.0f ms", startup),
                        detail: startup > 800 ? "超过 800ms 预算，冷启动可能偏慢" : "在 800ms 预算内")
                let arch = CrashGuard.archList()
                if !arch.isEmpty {
                    XHairline(inset: XSpace.card)
                    itemRow(icon: "archivebox", tone: XPalette.textSub,
                            title: "保留 \(arch.count) 次异常会话记录",
                            detail: arch.prefix(3).joined(separator: " · "))
                }
            }
        }
    }

    // ── 最近操作 ──────────────────────────────────────────
    private var opsCard: some View {
        let ops = DiagOps.list()
        return XPanel(kind: .group, padding: 0) {
            VStack(spacing: 0) {
                header("最近操作", tone: XPalette.textTertiary)
                if ops.isEmpty {
                    itemRow(icon: "list.bullet", tone: XPalette.textTertiary,
                            title: "还没有记录", detail: "开关在设置里（默认开）")
                } else {
                    ForEach(Array(ops.prefix(10).enumerated()), id: \.offset) { idx, o in
                        HStack(spacing: XSpace.s) {
                            Text(o.t)
                                .xFont(.caption2, design: .monospaced)
                                .foregroundStyle(XPalette.textTertiary)
                                .frame(width: 76, alignment: .leading)
                            Text(o.label)
                                .xFont(.caption)
                                .foregroundStyle(XPalette.textSub)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, XSpace.card)
                        .padding(.vertical, 6)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(o.t) \(o.label)")
                        if idx < min(ops.count, 10) - 1 { XHairline(inset: XSpace.card) }
                    }
                }
            }
        }
    }

    // ── 蓝牙 ──────────────────────────────────────────────
    private var bleCard: some View {
        let ev = BleTelemetry.events
        let bad = BleTelemetry.attempts.filter { !$0.ok }
        return XPanel(kind: .group, padding: 0) {
            VStack(spacing: 0) {
                header("蓝牙", tone: bad.isEmpty ? XPalette.ok : XPalette.warn)
                if ev.isEmpty && bad.isEmpty {
                    itemRow(icon: "antenna.radiowaves.left.and.right", tone: XPalette.textTertiary,
                            title: "还没有连接记录", detail: "配过一次锁之后这里会有内容")
                } else {
                    if let last = ev.first {
                        itemRow(icon: last.ok ? "checkmark.circle.fill" : "xmark.circle.fill",
                                tone: last.ok ? XPalette.ok : XPalette.warn,
                                title: "最近：\(last.what)",
                                detail: "\(last.at)")
                    }
                    if !bad.isEmpty, let a = bad.first {
                        XHairline(inset: XSpace.card)
                        itemRow(icon: "exclamationmark.triangle.fill", tone: XPalette.warn,
                                title: "失败 \(bad.count) 次",
                                detail: "\(a.t) \(a.reason)")
                    }
                }
            }
        }
    }

    // ── 日志保留 ──────────────────────────────────────────
    private var retentionCard: some View {
        let days = DiagLogs.retentionDays
        let n = DiagLogs.all().count
        return XPanel(kind: .group, padding: 0) {
            VStack(spacing: 0) {
                header("日志", tone: XPalette.textTertiary)
                itemRow(icon: "doc.text", tone: XPalette.textSub,
                        title: "本机保留 \(n) 条",
                        detail: days == nil ? "永久保留（不自动清理）" : "只保留最近 \(days!) 天")
            }
        }
    }

    // ── 处置 ──────────────────────────────────────────────
    //
    // 诊断页原来只有"看"。但 DiagKit 里这几个动作本来就存在，
    // 只是没有任何入口 —— 尤其 archiveOldLogs：它只在启动时被调用，
    // 且要先打开 kf_diag_autoarchive（默认关）—— 等于这个功能默认不存在。
    private var actionsCard: some View {
        XPanel(kind: .group, padding: 0) {
            VStack(spacing: 0) {
                header("处置", tone: XPalette.textTertiary)

                actionRow(icon: "archivebox", title: "归档一年前的旧日志",
                          detail: "把超期记录移入归档区，缓存只留近期") {
                    let n = DataHealth.archiveOldLogs()
                    XHaptics.success()
                    app.showToast(n > 0 ? "已归档 \(n) 条旧日志" : "没有需要归档的旧日志")
                    revision &+= 1
                }

                XHairline(inset: XSpace.card)

                // 日志保留期：三档，按当前值打勾
                VStack(alignment: .leading, spacing: XSpace.s) {
                    Text("日志保留期")
                        .xFont(.footnote, weight: .medium)
                        .foregroundStyle(XPalette.text)
                    HStack(spacing: XSpace.s) {
                        retentionChip("全部", "")
                        retentionChip("365 天", "365")
                        retentionChip("90 天", "90")
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, XSpace.card)
                .padding(.vertical, XSpace.m)

                XHairline(inset: XSpace.card)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("记录最近操作").xFont(.footnote).foregroundStyle(XPalette.text)
                        Text("关闭后不再往本机写操作流水")
                            .xFont(.caption2).foregroundStyle(XPalette.textSub)
                    }
                    Spacer(minLength: XSpace.s)
                    XToggle(isOn: Binding(
                        get: { opsOn },
                        set: { v in
                            opsOn = v
                            DB.store.set("kf_diag_ops_on", v)
                            XHaptics.tick.impactOccurred()
                        })) { EmptyView() }
                }
                .padding(.horizontal, XSpace.card)
                .frame(minHeight: XHit.min)

                XHairline(inset: XSpace.card)

                actionRow(icon: "clock.arrow.circlepath", title: "清空页面耗时记录",
                          detail: "只清采样数据，不影响任何业务", danger: false) {
                    PageTrace.clear()
                    XHaptics.success()
                    app.showToast("页面耗时记录已清空")
                    revision &+= 1
                }
            }
        }
    }

    private func retentionChip(_ label: String, _ value: String) -> some View {
        Button {
            retention = value
            DB.store.set("kf_diag_log_retention", value)
            // 当场生效：否则用户切完看不到任何变化，要等下次写日志才裁剪。
            let removed = DiagLogs.applyRetentionNow()
            XHaptics.tick.impactOccurred()
            if removed > 0 { app.showToast("已按新保留期删除 (removed) 条", tone: .done) }
            revision &+= 1
        } label: {
            Text(label)
                .xFont(.caption, weight: retention == value ? .semibold : .regular)
                .foregroundStyle(retention == value ? XPalette.onAccent : XPalette.textSub)
                // 保留期选择器是一排小胶囊，视觉约 26pt。它是**真的会点**的（切了当场生效），
                // 所以命中补到 44（视觉不变）。
                .frame(minHeight: XHit.min)
                .contentShape(Rectangle())
                .padding(.horizontal, XSpace.m)
                .padding(.vertical, 6)
                .xPlate(retention == value ? XPalette.accent : XPalette.surfaceAlt, .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label + (retention == value ? "，当前" : ""))
    }

    private func actionRow(icon: String, title: String, detail: String, danger: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: XSpace.s) {
                Image(systemName: icon)
                    .font(.system(size: XIcon.sm, weight: .medium))
                    .foregroundStyle(danger ? XPalette.danger : XPalette.accentText)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).xFont(.footnote).foregroundStyle(XPalette.text)
                    Text(detail).xFont(.caption2).foregroundStyle(XPalette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: XIcon.xs, weight: .semibold))
                    .foregroundStyle(XPalette.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, XSpace.card)
            .padding(.vertical, XSpace.s)
            .frame(minHeight: XHit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title + "，" + detail)
    }

    // ── 构件 ──────────────────────────────────────────────
    private func header(_ s: String, tone: Color) -> some View {
        Text(s)
            .xFont(.caption, weight: .semibold)
            .foregroundStyle(tone)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, XSpace.card)
            .padding(.top, XSpace.m)
            .padding(.bottom, XSpace.s)
    }

    private func itemRow(icon: String, tone: Color, title: String, detail: String?) -> some View {
        HStack(alignment: .top, spacing: XSpace.s) {
            Image(systemName: icon)
                .font(.system(size: XIcon.sm, weight: .medium))
                .foregroundStyle(tone)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .xFont(.caption)
                        .foregroundStyle(XPalette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, XSpace.card)
        .padding(.vertical, XSpace.s)
        .frame(minHeight: XHit.min)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title + (detail.map { "，" + $0 } ?? ""))
    }

    /// 复制成一段可粘贴的纯文本 —— 用户要反馈问题时，这是最有用的东西。
    private func fullReport() -> String {
        var out: [String] = ["— 诊断 —"]
        out.append(SelfCheck.summary(selfChecks))
        for l in selfChecks { out.append("· \(l.name)：\(l.ok ? "通过" : "异常") — \(l.detail)") }
        if !health.isEmpty { out.append("数据健康："); health.forEach { out.append("· " + $0) } }
        out.append("启动 \(String(format: "%.0f", StartupTrace.totalMs)) ms")
        out.append(CrashGuard.pendingAbnormal ? "最近有一次异常退出" : "最近一次正常退出")
        out.append("日志 \(DiagLogs.all().count) 条")
        return out.joined(separator: "\n")
    }
}
