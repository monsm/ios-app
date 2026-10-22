import SwiftUI

// ═══════════════════════════════════════════════════════════════════════
// MARK: - 外观工作室
// ═══════════════════════════════════════════════════════════════════════
//
// 这一页补的是一个**整块缺失 + 菜单指错页**的问题：
//
//   · ManagerFace 的「外观工作室 · 主题 / 强调色 / 密度」点开后是 StudioPage，
//     而 StudioPage 是「钥匙工坊」（密码/临时/指纹/OTP 四张卡）—— 与外观无关。
//   · LockKeeperApp 里 theme / accent / hc / weekStart 四个 setter **零调用**，
//     所以主题、品牌色、高对比、周起始日用户全都改不了。
//   · 连带后果：XAppearance.isAMOLED（kf_theme == "black"）永远是 false，
//     "纯黑省电"这条分支在真机上从来到不了。
//
// 2026-10-23 用户裁定：**App 不提供配色选择**，只跟随系统的深色/浅色。
// 原「品牌色」七选一已整个删除，主题层也不再读 kf_accent。
// lockKeeperApp.scheme(for:) 已读 kf_theme 支持 4 档。缺的只是这一页。
struct AppearancePage: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var hc = DB.store.getBool("kf_hc")
    @State private var weekStart = DB.store.getString("kf_week_start")

    // 规范 §13.4：只做深色，不提供明暗切换。所以强调色只剩一栏（深色档值）。
    private let weekStarts: [(id: String, label: String)] = [
        ("", "跟随系统"), ("mon", "周一"), ("sun", "周日"), ("sat", "周六"),
    ]

    var body: some View {
        // 2026-10-23：改用 XScreen（规范 §5.3 骨架 / §5.4 对齐线）。
        // 改前是手写 ScrollView + VStack(section) + 各自的 padding 与 background。
        XScreen("外观工作室", style: .inline) {
            miscCard
        }
    }

    private var miscCard: some View {
        XPanel(kind: .group, padding: 0) {
            VStack(spacing: 0) {
                header("看得清 / 每周从哪天算")
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("高对比").xFont(.body).foregroundStyle(XPalette.text)
                        Text("系统里开了「增加对比度」时，这里也会跟着加强")
                            .xFont(.caption).foregroundStyle(XPalette.textSub)
                    }
                    Spacer(minLength: XSpace.s)
                    // XToggle 有自带的文字标签，这里标签在左侧自己排了，
                    // 所以用无标签重载（uicoverage 要求开关只能从 XToggle 一处来）。
                    XToggle(isOn: Binding(
                        get: { hc },
                        set: { v in hc = v; app.setHighContrast(v); XHaptics.tick.impactOccurred() })) {
                        EmptyView()
                    }
                }
                .padding(XSpace.card)
                XHairline(inset: XSpace.card)
                ForEach(Array(weekStarts.enumerated()), id: \.element.id) { idx, w in
                    pickRow(title: "一周从" + w.label + "开始", note: nil, selected: weekStart == w.id) {
                        weekStart = w.id
                        app.setWeekStart(w.id)
                        XHaptics.tick.impactOccurred()
                    }
                    if idx < weekStarts.count - 1 { XHairline(inset: XSpace.card) }
                }
            }
        }
    }

    // ── 构件 ───────────────────────────────────────────────
    private func header(_ s: String) -> some View {
        Text(s)
            .xFont(.caption, weight: .semibold)
            .foregroundStyle(XPalette.textTertiary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, XSpace.card)
            .padding(.top, XSpace.m)
            .padding(.bottom, XSpace.s)
    }

    private func pickRow(title: String, note: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: XSpace.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .xFont(.body)
                        .foregroundStyle(XPalette.text)
                    if let note {
                        Text(note)
                            .xFont(.caption)
                            .foregroundStyle(XPalette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: XSpace.s)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: XIcon.sm, weight: .semibold))
                    .foregroundStyle(selected ? XPalette.accentText : XPalette.hairlineStrong)
                    .accessibilityHidden(true)
            }
            .padding(XSpace.card)
            .frame(minHeight: XHit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title + (selected ? "，已选中" : ""))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
