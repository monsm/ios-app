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
// 基础设施其实都齐了：XPalette.accent 已读 kf_accent 支持 6 套品牌色，
// lockKeeperApp.scheme(for:) 已读 kf_theme 支持 4 档。缺的只是这一页。
struct AppearancePage: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var theme = DB.store.getString("kf_theme")
    @State private var accent = DB.store.getString("kf_accent")
    @State private var hc = DB.store.getBool("kf_hc")
    @State private var weekStart = DB.store.getString("kf_week_start")

    private let themes: [(id: String, label: String, note: String)] = [
        ("", "跟随系统", "手机切到深色时一起变"),
        ("light", "浅色", "始终浅色"),
        ("dark", "深色", "始终深色"),
        ("black", "纯黑", "AMOLED 省电，画布变成真正的黑"),
    ]
    private let accents: [(id: String, label: String, light: UInt32, dark: UInt32)] = [
        ("", "铜", 0x9C5A22, 0xD98B45),
        ("indigo", "靛蓝", 0x4F46E5, 0x818CF8),
        ("forest", "森林", 0x15803D, 0x4ADE80),
        ("amber", "琥珀", 0xB45309, 0xFBBF24),
        ("graphite", "石墨", 0x3F3F46, 0xA1A1AA),
        ("rose", "玫瑰", 0xBE123C, 0xFB7185),
        ("aurora", "极光", 0x0E7490, 0x22D3EE),
    ]
    private let weekStarts: [(id: String, label: String)] = [
        ("", "跟随系统"), ("mon", "周一"), ("sun", "周日"), ("sat", "周六"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: XSpace.l) {
                themeCard
                accentCard
                miscCard
            }
            .padding(.horizontal, XSpace.gutter)
            .padding(.vertical, XSpace.l)
        }
        .background(XPalette.canvas)
        .navigationTitle("外观工作室")
        .navigationBarTitleDisplayMode(.inline)
    }

    // ── 外观模式 ───────────────────────────────────────────
    private var themeCard: some View {
        XPanel(kind: .group, padding: 0) {
            VStack(spacing: 0) {
                header("外观模式")
                ForEach(Array(themes.enumerated()), id: \.element.id) { idx, t in
                    pickRow(title: t.label, note: t.note, selected: theme == t.id) {
                        theme = t.id
                        app.setTheme(t.id)
                        XHaptics.tick.impactOccurred()
                    }
                    if idx < themes.count - 1 { XHairline(inset: XSpace.card) }
                }
            }
        }
    }

    // ── 品牌色 ─────────────────────────────────────────────
    private var accentCard: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                Text("品牌色")
                    .xFont(.system(.caption, weight: .semibold))
                    .foregroundStyle(XPalette.textTertiary)
                    .textCase(.uppercase)
                    .frame(maxWidth: .infinity, alignment: .leading)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: XSpace.m)],
                          spacing: XSpace.m) {
                    ForEach(accents, id: \.id) { a in
                        Button {
                            accent = a.id
                            app.setAccent(a.id)
                            XHaptics.tick.impactOccurred()
                        } label: {
                            VStack(spacing: 6) {
                                Circle()
                                    .fill(Color.adaptive(a.light, a.dark))
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        if accent == a.id {
                                            Circle()
                                                .strokeBorder(XPalette.text, lineWidth: 2)
                                                .frame(width: 44, height: 44)
                                        }
                                    }
                                    .frame(width: 44, height: 44)
                                Text(a.label)
                                    .xFont(.system(.caption2, weight: accent == a.id ? .semibold : .regular))
                                    .foregroundStyle(accent == a.id ? XPalette.text : XPalette.textSub)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(a.label + (accent == a.id ? "，当前" : ""))
                    }
                }
                Text("品牌色只影响强调元素（开锁环、当前小时、可点的字），不改正文与背景的对比度。")
                    .xFont(.system(.caption2))
                    .foregroundStyle(XPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // ── 高对比 / 周起始日 ──────────────────────────────────
    private var miscCard: some View {
        XPanel(kind: .group, padding: 0) {
            VStack(spacing: 0) {
                header("可读性与周界")
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("高对比").xFont(.system(.body)).foregroundStyle(XPalette.text)
                        Text("与系统的「增加对比度」并联，任一开着就加强")
                            .xFont(.system(.caption)).foregroundStyle(XPalette.textSub)
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
            .xFont(.system(.caption, weight: .semibold))
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
                        .xFont(.system(.body))
                        .foregroundStyle(XPalette.text)
                    if let note {
                        Text(note)
                            .xFont(.system(.caption))
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
