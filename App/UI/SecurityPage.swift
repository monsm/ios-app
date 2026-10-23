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
        // 2026-10-23：改用 XScreen（规范 §5.3 骨架 / §5.4 对齐线）。
        // 改前是手写 ScrollView + VStack(section) + 各自的 padding 与 background。
        XScreen("本机保护") {
            statusCard.xScrollLift()
            if !risks.isEmpty || auditBroken || !selfCheckIssues.isEmpty {
                riskCard.xScrollLift()
            }
            actionsCard.xScrollLift()
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 状态卡
    // ═══════════════════════════════════════════════════════

    /// 六图改造 (2026-10-23): 状态卡改**图 5 MetricCard**形态（44px 风险数 + 环）。
    ///
    /// 图 5 用一个大数字回答"现在什么情况"。本页的问题是"有没有事"，
    /// 答案就是一个数：**有几项风险**。之前是一行 title3 文字（"无风险"），
    /// 用户读到的只是形容词，读不到量。
    private var statusCard: some View {
        let riskTotal = risks.count + (auditBroken ? 1 : 0) + selfCheckIssues.count + (appLocked ? 0 : 1)
        let health: Double = riskTotal == 0 ? 1.0 : max(0.04, 1 - Double(riskTotal) / 6)
        return XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                HStack {
                    Text("现在安全吗")
                        .xFont(.subheadline)
                        .foregroundStyle(XPalette.textTertiary)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .center, spacing: XSpace.l) {
                    VStack(alignment: .leading, spacing: 8) {
                        XHeroNumber(
                            text: String(riskTotal),
                            color: overallTone.color,
                            unit: "项风险")
                        Text(overallDetail)
                            .xFont(.footnote)
                            .foregroundStyle(XPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    XGradientDial(
                        size: 76,
                        progress: health,
                        widthRatio: 0.13,
                        showsCursor: false,
                        showsTick: false,
                        gradient: riskTotal == 0 ? XGradient.dialOK : XGradient.dial
                    ) { EmptyView() }
                    .accessibilityHidden(true)
                }

                XHairline()

                // 三盏灯
                HStack(spacing: XSpace.l) {
                    lamp("钥匙", ok: risks.isEmpty, detail: risks.isEmpty ? "无风险" : "\(risks.count) 项")
                    lamp("审计链", ok: !auditBroken, detail: auditBroken ? "断裂" : "完整")
                    lamp("数据", ok: selfCheckIssues.isEmpty, detail: selfCheckIssues.isEmpty ? "正常" : "\(selfCheckIssues.count) 项")
                }
            }
        }
    }

    /// 应用锁是否开启（安全页最该显示的一件事，原来没有）
    private var appLocked: Bool { DB.store.getBool("kf_applock") }

    /// 上次备份距今是否够新（14 天内算新）
    private var backupDays: Int {
        let ms = DB.store.getInt("kf_bk_last_export", 0)
        guard ms > 0 else { return -1 }
        return Int((Date().timeIntervalSince1970 * 1000 - Double(ms)) / 86_400_000)
    }
    private var backupFresh: Bool { backupDays >= 0 && backupDays <= 14 }
    private var backupDetail: String {
        if backupDays < 0 { return "从未" }
        if backupDays == 0 { return "今天" }
        return String(backupDays) + " 天前"
    }

    /// 总状态 —— 必须与下面五盏灯一致
    ///
    /// 加了「应用锁 / 备份」两盏灯之后，这里也要把它们算进来，
    /// 否则会出现"顶部说全部通过、下面显示应用锁未开启"的自相矛盾。
    private var overallTone: XToneColor {
        if !risks.isEmpty || auditBroken || !selfCheckIssues.isEmpty
            || !appLocked || !backupFresh { return .warn }
        return .ok
    }

    private var overallTitle: String {
        overallTone == .ok ? "本机数据正常" : "有需要处理的项目"
    }

    private var overallDetail: String {
        if overallTone == .ok { return "钥匙 / 审计链 / 数据完整性 / 应用锁 / 备份 全部通过" }
        var parts: [String] = []
        if !risks.isEmpty { parts.append("\(risks.count) 项钥匙风险") }
        if auditBroken { parts.append("审计链断裂") }
        if !selfCheckIssues.isEmpty { parts.append("\(selfCheckIssues.count) 项数据异常") }
        if !appLocked { parts.append("应用锁未开启") }
        if !backupFresh { parts.append(backupDays < 0 ? "从未备份" : "备份 \(backupDays) 天前") }
        return parts.joined(separator: " · ")
    }

    /// 状态灯 —— 原来是 8pt 小圆点, 作为安全页的核心指示太弱。
    ///
    /// 现在: 22pt 灯体 + 外圈柔光 + 内圈高光, 状态一眼可辨;
    /// 异常时灯体带轻微脉冲 (reduceMotion 时不脉冲, 只保留静态色)。
    /// 颜色依然是**双通道**之一: 灯下还有 detail 文字, 不只靠颜色。
    private func lamp(_ label: String, ok: Bool, detail: String) -> some View {
        let tone = ok ? XPalette.ok : XPalette.warn
        return VStack(spacing: XSpace.xs) {
            ZStack {
                // 外圈柔光
                Circle()
                    .fill(tone.opacity(XOpacity.glow))
                    .frame(width: 30, height: 30)
                // 灯体
                Circle()
                    .fill(tone)
                    .frame(width: 12, height: 12)
                // 内圈高光 (让灯有体积)
                Circle()
                    .fill(XPalette.specular.opacity(XOpacity.track))
                    .frame(width: 4, height: 4)
                    .offset(x: -2, y: -2)
            }
            .accessibilityHidden(true)

            Text(label)
                .xFont(.caption2, weight: .medium)
                .foregroundStyle(XPalette.textSub)

            Text(detail)
                .xFont(.caption2, weight: .semibold)
                .foregroundStyle(tone)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(ok ? "正常" : "需处理"), \(detail)")
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 风险卡
    // ═══════════════════════════════════════════════════════

    private var riskCard: some View {
        XPanel(kind: .group, tone: .warn) {
            VStack(alignment: .leading, spacing: XSpace.s) {
                // HTML 卡2 卡头「有没有事」
                Text("有没有事")
                    .xFont(.subheadline)
                    .foregroundStyle(XPalette.textTertiary)

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
                // HTML 卡3 卡头「有哪些功能」
                Text("有哪些功能")
                    .xFont(.subheadline)
                    .foregroundStyle(XPalette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, XSpace.card)
                    .padding(.top, XSpace.m)
                    .padding(.bottom, XSpace.s)

                // 应用锁必须是这一页的第一条:
                // 后面三条(防窥/审计/销毁)全都建立在"本机已经被锁住"之上。
                // 之前这一条根本不存在 —— kf_applock 只被读、从未被写，
                // 于是整个安全页恒报「应用锁未开启」，毁灭动作也复核不了口令。
                actionRow(icon: DB.hasPasscode() ? "lock.shield.fill" : "lock.open",
                          title: "应用锁",
                          detail: DB.hasPasscode() ? "已开启 · 修改或关闭" : "未开启 · 现在设置") {
                    AppLockSetupView().environmentObject(app).trackScreen("应用锁")
                }
                XHairline(inset: XSpace.card)
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
                    Text("这几条都是本机能力 —— 门锁并不知道你开了应用锁或审计，它们防的是这台手机被翻。")
                    .xFont(.caption2)
                    .foregroundStyle(XPalette.textTertiary)
                    .padding(.horizontal, XSpace.card)
                    .padding(.vertical, 12)
                    .fixedSize(horizontal: false, vertical: true)
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
