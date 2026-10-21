import SwiftUI

// ═══════════════════════════════════════════════════════════════════════
// MARK: - 诊断与自检
// ═══════════════════════════════════════════════════════════════════════
//
// 这一屏补的是一个**计划内、但丢了**的界面：
// `App/Core/DiagKit.swift` 有 642 行、十来组采集器（自检 / 数据健康 / 异常退出 /
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

    private var selfChecks: [DiagKit.SelfCheckLine] { DiagKit.SelfCheck.run() }
    private var health: [String] { DiagKit.DataHealth.integrity() }
    private var orphans: [String] { DiagKit.DataHealth.scanOrphans() }

    var body: some View {
        ScrollView {
            VStack(spacing: XSpace.l) {
                selfCheckCard
                healthCard
                stabilityCard
                opsCard
                bleCard
                retentionCard
            }
            .padding(.horizontal, XSpace.gutter)
            .padding(.vertical, XSpace.l)
        }
        .background(XPalette.canvas)
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
                    Text(DiagKit.SelfCheck.summary(lines))
                        .xFont(.system(.subheadline, weight: .medium))
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
                            Text(l.name).xFont(.system(.footnote, weight: .medium))
                                .foregroundStyle(XPalette.text)
                            Text(l.detail).xFont(.system(.caption))
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
                header("数据健康", tone: health.isEmpty && orphans.isEmpty ? XPalette.ok : XPalette.warn)
                if health.isEmpty && orphans.isEmpty {
                    itemRow(icon: "checkmark.circle.fill", tone: XPalette.ok,
                            title: "没有发现数据问题",
                            detail: "数据键都能解析，也没有孤立文件")
                } else {
                    ForEach(Array(health.enumerated()), id: \.offset) { _, s in
                        itemRow(icon: "exclamationmark.triangle.fill", tone: XPalette.warn,
                                title: s, detail: nil)
                    }
                    ForEach(Array(orphans.prefix(6).enumerated()), id: \.offset) { _, s in
                        itemRow(icon: "shippingbox", tone: XPalette.textSub, title: s, detail: nil)
                    }
                    if orphans.count > 6 {
                        itemRow(icon: "ellipsis", tone: XPalette.textTertiary,
                                title: "另有 \(orphans.count - 6) 项孤立数据", detail: nil)
                    }
                }
            }
        }
    }

    // ── 稳定性 ────────────────────────────────────────────
    private var stabilityCard: some View {
        let startup = DiagKit.StartupTrace.totalMs
        let crashed = DiagKit.CrashGuard.pendingAbnormal
        return XPanel(kind: .group, padding: 0) {
            VStack(spacing: 0) {
                header("稳定性", tone: crashed ? XPalette.warn : XPalette.ok)
                itemRow(icon: crashed ? "bolt.trianglebadge.exclamationmark.fill" : "checkmark.circle.fill",
                        tone: crashed ? XPalette.warn : XPalette.ok,
                        title: crashed ? "上次是异常退出" : "上次正常退出",
                        detail: crashed ? "不是崩溃上报，只是本机记录到会话没有正常结束" : nil)
                XHairline(inset: XSpace.card)
                itemRow(icon: startup > 800 ? "clock.badge.exclamationmark" : "clock",
                        tone: startup > 800 ? XPalette.warn : XPalette.textSub,
                        title: String(format: "本次启动 %.0f ms", startup),
                        detail: startup > 800 ? "超过 800ms 预算，冷启动可能偏慢" : "在 800ms 预算内")
                let arch = DiagKit.CrashGuard.archList()
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
        let ops = DiagKit.DiagOps.list()
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
                                .xFont(.system(.caption2, design: .monospaced))
                                .foregroundStyle(XPalette.textTertiary)
                                .frame(width: 76, alignment: .leading)
                            Text(o.label)
                                .xFont(.system(.caption))
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
        let ev = DiagKit.BleTelemetry.events
        let bad = DiagKit.BleTelemetry.attempts.filter { !$0.ok }
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
        let days = DiagKit.DiagLogs.retentionDays
        let n = DiagKit.DiagLogs.all().count
        return XPanel(kind: .group, padding: 0) {
            VStack(spacing: 0) {
                header("日志", tone: XPalette.textTertiary)
                itemRow(icon: "doc.text", tone: XPalette.textSub,
                        title: "本机保留 \(n) 条",
                        detail: days == nil ? "永久保留（不自动清理）" : "只保留最近 \(days!) 天")
            }
        }
    }

    // ── 构件 ──────────────────────────────────────────────
    private func header(_ s: String, tone: Color) -> some View {
        Text(s)
            .xFont(.system(.caption, weight: .semibold))
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
                    .xFont(.system(.footnote))
                    .foregroundStyle(XPalette.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .xFont(.system(.caption))
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
        out.append(DiagKit.SelfCheck.summary(selfChecks))
        for l in selfChecks { out.append("· \(l.name)：\(l.ok ? "通过" : "异常") — \(l.detail)") }
        if !health.isEmpty { out.append("数据健康："); health.forEach { out.append("· " + $0) } }
        if !orphans.isEmpty { out.append("孤立数据 \(orphans.count) 项") }
        out.append("启动 \(String(format: "%.0f", DiagKit.StartupTrace.totalMs)) ms")
        out.append(DiagKit.CrashGuard.pendingAbnormal ? "上次异常退出" : "上次正常退出")
        out.append("日志 \(DiagKit.DiagLogs.all().count) 条")
        return out.joined(separator: "\n")
    }
}
