//
//  SecurityPage.swift
//  安全中心 · 全新重写 (2026-10-21)
//
//  门里「这台手机」→ 本机保护的落地页。
//
//  ═══════════════════════════════════════════════════════════
//  与旧 SecurityCenterView (1570 行) 的区别
//  ═══════════════════════════════════════════════════════════
//
//  旧版: 防窥 / 凭证风险 / 审计 / 销毁 四个 Section 平铺,
//        每个入口下面跟一段说明文字。
//
//  新版: 先回答"现在安全吗", 再给动作
//    · 顶部: 安全状态卡 (一句话结论 + 三盏灯)
//    · 中部: 需要处理的风险 (只在有时出现)
//    · 底部: 四个动作入口 (防窥/审计/销毁/隐私)
//
//  设计原则:
//    · 结论先行: 用户打开安全页想知道"有没有事", 不是"有哪些功能"
//    · 风险前置: 有风险才出现, 没风险不占版面
//    · 危险动作 (销毁) 视觉上明显不同, 且需要长按
//

import SwiftUI

/// 安全中心 —— 门里「这台手机」→ 本机保护
struct SecurityPage: View {
    @EnvironmentObject private var app: AppState

    private var risks: [CredentialOrg.PwdRisk] { CredentialOrg.passwordRisks() }
    private var auditBroken: Bool {
        AuditLog().verifyChain().brokenAt >= 0
    }
    private var selfCheckIssues: [String] {
        DataHealth.integrity().filter { !$0.hasPrefix("数据解析正常") }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: XSpace.l) {
                statusCard
                if !risks.isEmpty || auditBroken || !selfCheckIssues.isEmpty {
                    riskCard
                }
                actionsCard
            }
            .padding(.horizontal, XSpace.gutter)
            .padding(.vertical, XSpace.l)
        }
        .background(XPalette.canvas)
        .navigationTitle("本机保护")
        .navigationBarTitleDisplayMode(.large)
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 状态卡
    // ═══════════════════════════════════════════════════════

    private var statusCard: some View {
        XPanel(kind: .hero) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                HStack(spacing: XSpace.s) {
                    Image(systemName: overallTone == .ok ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .font(.system(size: XIcon.lg, weight: .medium))
                        .foregroundStyle(overallTone.color)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(overallTitle)
                            .xFont(.title3, weight: .semibold)
                            .foregroundStyle(XPalette.text)
                        Text(overallDetail)
                            .xFont(.footnote)
                            .foregroundStyle(XPalette.textSub)
                    }
                }

                Divider().overlay(XPalette.hairline)

                // 三盏灯
                HStack(spacing: XSpace.l) {
                    lamp("凭证", ok: risks.isEmpty, detail: risks.isEmpty ? "无风险" : "\(risks.count) 项")
                    lamp("审计链", ok: !auditBroken, detail: auditBroken ? "断裂" : "完整")
                    lamp("数据", ok: selfCheckIssues.isEmpty, detail: selfCheckIssues.isEmpty ? "正常" : "\(selfCheckIssues.count) 项")
                }
            }
        }
    }

    private var overallTone: XToneColor {
        if !risks.isEmpty || auditBroken || !selfCheckIssues.isEmpty { return .warn }
        return .ok
    }

    private var overallTitle: String {
        overallTone == .ok ? "本机数据正常" : "有需要处理的项目"
    }

    private var overallDetail: String {
        if overallTone == .ok { return "凭证 / 审计链 / 数据完整性 全部通过" }
        var parts: [String] = []
        if !risks.isEmpty { parts.append("\(risks.count) 项凭证风险") }
        if auditBroken { parts.append("审计链断裂") }
        if !selfCheckIssues.isEmpty { parts.append("\(selfCheckIssues.count) 项数据异常") }
        return parts.joined(separator: " · ")
    }

    private func lamp(_ label: String, ok: Bool, detail: String) -> some View {
        VStack(spacing: XSpace.xxs) {
            Circle()
                .fill(ok ? XPalette.ok : XPalette.warn)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(label)
                .xFont(.caption2)
                .foregroundStyle(XPalette.textSub)
            Text(detail)
                .xFont(.caption2, weight: .medium)
                .foregroundStyle(ok ? XPalette.ok : XPalette.warn)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(detail)")
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 风险卡
    // ═══════════════════════════════════════════════════════

    private var riskCard: some View {
        XPanel(kind: .group, tone: .warn) {
            VStack(alignment: .leading, spacing: XSpace.s) {
                Text("需要处理")
                    .xFont(.subheadline, weight: .medium)
                    .foregroundStyle(XPalette.text)

                if !risks.isEmpty {
                    ForEach(risks.prefix(5)) { r in
                        HStack(alignment: .top, spacing: XSpace.s) {
                            Image(systemName: riskIcon(r.kind))
                                .font(.system(size: XIcon.sm, weight: .medium))
                                .foregroundStyle(r.kind == "弱口令" ? XPalette.danger : XPalette.warn)
                                .frame(width: 20)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(r.kind) · \(r.lockName) #\(r.alias)")
                                    .xFont(.footnote, weight: .medium)
                                    .foregroundStyle(XPalette.text)
                                Text(r.detail)
                                    .xFont(.caption)
                                    .foregroundStyle(XPalette.textSub)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }

                if auditBroken {
                    riskLine(icon: "link.badge.plus", title: "审计链断裂",
                             detail: "有条目被截断或换序重放")
                }
                ForEach(selfCheckIssues.prefix(3), id: \.self) { issue in
                    riskLine(icon: "doc.badge.exclamationmark", title: "数据异常", detail: issue)
                }
            }
        }
    }

    private func riskLine(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: XSpace.s) {
            Image(systemName: icon)
                .font(.system(size: XIcon.sm, weight: .medium))
                .foregroundStyle(XPalette.warn)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .xFont(.footnote, weight: .medium)
                    .foregroundStyle(XPalette.text)
                Text(detail)
                    .xFont(.caption)
                    .foregroundStyle(XPalette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func riskIcon(_ kind: String) -> String {
        switch kind {
        case "同值": return "doc.on.doc"
        case "超期": return "clock.badge.exclamationmark"
        default: return "lock.trianglebadge.exclamationmark"
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 动作
    // ═══════════════════════════════════════════════════════

    private var actionsCard: some View {
        XPanel(kind: .group, padding: 0) {
            VStack(spacing: 0) {
                actionRow(icon: "eye.slash", title: "防窥与遮蔽",
                          detail: "后台即糊 / 限时可见 / 水印") {
                    SecurityPeekView().environmentObject(app)
                }
                XHairline(inset: XSpace.card)
                actionRow(icon: "list.bullet.rectangle", title: "审计日志",
                          detail: "谁在什么时候做了什么") {
                    SecurityAuditView().environmentObject(app)
                }
                XHairline(inset: XSpace.card)
                actionRow(icon: "trash", title: "彻底销毁", detail: "不可恢复", danger: true) {
                    SecurityDestroyView().environmentObject(app)
                }
            }
        }
    }

    private func actionRow<Destination: View>(
        icon: String, title: String, detail: String, danger: Bool = false,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink { destination() } label: {
            HStack(spacing: XSpace.m) {
                Image(systemName: icon)
                    .font(.system(size: XIcon.sm, weight: .medium))
                    .foregroundStyle(danger ? XPalette.danger : XPalette.accentText)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .xFont(.body)
                        .foregroundStyle(danger ? XPalette.danger : XPalette.text)
                    Text(detail)
                        .xFont(.caption)
                        .foregroundStyle(XPalette.textSub)
                }
                Spacer(minLength: XSpace.s)
                Image(systemName: "chevron.right")
                    .font(.system(size: XIcon.xs, weight: .semibold))
                    .foregroundStyle(XPalette.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(XSpace.card)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(detail)")
    }
}
