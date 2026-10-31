// AppearanceScreen.swift —— 外观 + 时间显示（两件事同属"这一屏看起来是什么样"）。
//
// 这屏干什么：主题 / 高对比 / 减少透明 + 密度 / 动效强度 + 时间制式 / 显示秒 / 两行日期。
// 每档即时生效、只存本机、不上传；「恢复默认外观」只重置外观偏好，不动门锁数据。
// 数据从哪来：SettingsStore.shared（本机偏好）+ TimeFormat（时间口径的唯一出口）。
// 主动作：这一屏没有主动作按钮 —— 全是档位；唯一"重"动作是底部「恢复默认外观」，描边不着色。
import SwiftUI

struct AppearanceScreen: View {
    private var store: SettingsStore { SettingsStore.shared }
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    @State private var showResetConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: T.S.l) {
                SettingsHeader(title: "外观", tone: tone, status: status)
                themePanel
                rhythmPanel
                timePanel
                quickPanel
                resetPanel
            }
            .padding(.vertical, T.S.l)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("恢复默认外观？", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("恢复默认外观", role: .destructive) { store.resetAppearance() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只重置主题、密度、动效、高对比与时间显示。不动本机密码、备份、钥匙串与任何门锁数据。")
        }
    }

    // MARK: 页头
    /// 这一屏没有「异常/正常」可言 —— 页头那颗点保持中性，状态由右边那行字说。
    private var tone: Tone { .neutral }

    private var status: String {
        var parts: [String] = [store.theme.title, store.density.title, store.motion.title]
        if store.highContrast { parts.append("高对比 开") }
        if systemReduceMotion { parts.append("系统减弱动效") }
        return parts.joined(separator: " · ")
    }

    // MARK: 主题
    private var themePanel: some View {
        VStack(spacing: T.S.s) {
            SectionLabel(text: "主题")
            Panel {
                VStack(alignment: .leading, spacing: T.S.m) {
                    SettingChips(items: AppearanceTheme.allCases,
                                 title: { $0.title },
                                 selection: settingsBinding(\.theme))
                    SettingRule()
                    SettingToggle(
                        label: "高对比",
                        note: "与系统「辅助功能 · 增加对比度」是并联关系，任一开着都加强描边与文字对比。",
                        isOn: settingsBinding(\.highContrast)
                    )
                    SettingRule()
                    SettingToggle(
                        label: "减少透明（玻璃退化为不透明面板）",
                        note: "系统「减少透明度」开启时自动生效；这里再开一道，让玻璃在楼道强光下也能读。",
                        isOn: settingsBinding(\.reduceTransparency)
                    )
                    SettingRule()
                    SettingsNote(text: "深色不是浅色的反相 —— 两套独立取值。深色底不是纯黑，留一点抬升空间给面板。")
                }
            }
            .padding(.horizontal, T.S.gutter)
        }
    }

    // MARK: 密度与动效
    private var rhythmPanel: some View {
        VStack(spacing: T.S.s) {
            SectionLabel(text: "节奏")
            Panel {
                VStack(alignment: .leading, spacing: T.S.m) {
                    Text("布局密度")
                        .font(T.F.unit)
                        .foregroundStyle(Ink.inkFaint)
                        .tracking(0.6)
                    SettingChips(items: LayoutDensity.allCases,
                                 title: { $0.title },
                                 selection: settingsBinding(\.density))
                    SettingsNote(text: "只改间距节奏，字号与 44pt 触达不动 —— 压小按钮不是「紧凑」，是点不准。")
                    SettingRule()
                    Text("动效强度")
                        .font(T.F.unit)
                        .foregroundStyle(Ink.inkFaint)
                        .tracking(0.6)
                    SettingChips(items: MotionTier.allCases,
                                 title: { $0.title },
                                 selection: settingsBinding(\.motion))
                    SettingsNote(text: systemReduceMotion
                                 ? "系统已开启「减弱动态效果」：进度弧保留（它是信息），数字滚动与逐格点亮已取消。"
                                 : "克制档取消数字滚动与逐格点亮；开锁进度弧在任何档位都保留 —— 它量的是真命令链。")
                }
            }
            .padding(.horizontal, T.S.gutter)
        }
    }

    // MARK: 时间显示（全 App 唯一出口）
    private var timePanel: some View {
        VStack(spacing: T.S.s) {
            SectionLabel(text: "时间显示", trailing: "全局")
            Panel {
                VStack(alignment: .leading, spacing: T.S.m) {
                    SettingChips(items: TimeDisplayStyle.allCases,
                                 title: { $0.title },
                                 selection: settingsBinding(\.timeStyle))
                    SettingsNote(text: "选「跟随系统」以外的档位后，本 App 不再听系统的 12/24 小时偏好 —— 一个开关管一件事。制式不做时区换算：锁端键盘上是几点，这里就显示几点。")
                    SettingRule()
                    SettingToggle(
                        label: "显示秒",
                        note: "只在日志原文真的带秒时出现；缺位的行不补「:00」—— 那等于假装这条记录精确到秒。",
                        isOn: settingsBinding(\.showSeconds)
                    )
                    SettingRule()
                    SettingToggle(
                        label: "记录行加第二行完整日期",
                        note: "台账行在时刻下面补一行 MM-DD。跨年的记录才显示年。",
                        isOn: settingsBinding(\.twoLineDate)
                    )
                    SettingRule()
                    timePreview
                }
            }
            .padding(.horizontal, T.S.gutter)
        }
    }

    // MARK: 时间样例：档位真的改了读数（不是摆设）
    private var timePreview: some View {
        VStack(alignment: .leading, spacing: T.S.xs) {
            Text("样例读数")
                .font(T.F.unit)
                .foregroundStyle(Ink.inkFaint)
                .tracking(0.6)
            HStack(alignment: .firstTextBaseline, spacing: T.S.s) {
                Text(previewClock)
                    .font(T.F.stamp)
                    .foregroundStyle(Ink.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    // 这里用 systemReduceMotion（本文件的环境值名）：
                    // 与 store 里的"App 内动效档"是两个独立开关 —— 系统的是硬约束，App 内的是偏好。
                    .animation(systemReduceMotion ? nil : T.M.snap, value: previewClock)
                Spacer(minLength: 0)
                if let dayLine = TimeDisplay.dayLine(now) {
                    Text(dayLine)
                        .font(T.F.unit)
                        .foregroundStyle(Ink.inkFaint)
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("时间显示样例 \(previewClock)")
    }

    private var now: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    /// 制式由 TimeDisplay 统一算（12/24 + 秒），这一屏只负责展示与改档。
    private var previewClock: String { TimeDisplay.clock(now) }

    // MARK: 快捷格（首页快捷操作 10 选 N + 智能排序）
    private var quickPanel: some View {
        VStack(spacing: T.S.s) {
            SectionLabel(text: "快捷操作")
            Panel {
                VStack(alignment: .leading, spacing: T.S.m) {
                    Text("首页显示几枚")
                        .font(T.F.unit)
                        .foregroundStyle(Ink.inkFaint)
                        .tracking(0.6)
                    HStack(spacing: T.S.s) {
                        ForEach([4, 6, 8], id: \.self) { n in
                            Button {
                                store.quickGridCount = n
                            } label: {
                                Text("\(n) 枚")
                                    .font(T.F.bodyStrong)
                                    .foregroundStyle(store.quickGridCount == n ? Signal.on : Ink.ink)
                                    .padding(.horizontal, T.S.m)
                                    .frame(minHeight: T.Hit.min)
                                    .background(store.quickGridCount == n ? Signal.base : Ink.plateAlt, in: .rect(cornerRadius: T.R.control))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(store.quickGridCount == n ? [.isButton, .isSelected] : .isButton)
                        }
                        Spacer(minLength: 0)
                    }
                    SettingRule()
                    SettingToggle(
                        label: "常用操作自动排前",
                        note: "按你实际点过的次数排序（存本机，不上传）。关掉后按下面勾选的顺序。",
                        isOn: Binding(get: { QuickPool.smartFirst }, set: { QuickPool.setSmartFirst($0) })
                    )
                    SettingRule()
                    Text("快捷池（10 选 6，至少留 1 项）")
                        .font(T.F.unit)
                        .foregroundStyle(Ink.inkFaint)
                        .tracking(0.6)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: T.S.s), count: 2), spacing: T.S.s) {
                        ForEach(QuickPool.all) { action in
                            quickToggle(action)
                        }
                    }
                    SettingsNote(text: "勾选结果即时生效到「门」页的快捷操作卡；这里只管显示与排序，不发任何锁端命令。")
                }
            }
            .padding(.horizontal, T.S.gutter)
        }
    }

    private func quickToggle(_ action: QuickAction) -> some View {
        let selected = QuickPool.selected.contains { $0.id == action.id }
        return Button {
            var ids = QuickPool.selected.map(\.id)
            if selected {
                guard ids.count > 1 else { return }
                ids.removeAll { $0 == action.id }
            } else {
                ids.append(action.id)
            }
            QuickPool.setSelected(ids)
        } label: {
            HStack(spacing: T.S.s) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .accessibilityHidden(true)
                    .font(T.F.icon(T.Icon.s, weight: .medium))
                    .foregroundStyle(selected ? Signal.base : Ink.inkFaint)
                Text(action.label)
                    .font(T.F.caption)
                    .foregroundStyle(Ink.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, T.S.s)
            .frame(minHeight: T.Hit.min)
            .background(Ink.plateAlt, in: .rect(cornerRadius: T.R.control))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: 恢复默认
    private var resetPanel: some View {
        VStack(spacing: T.S.s) {
            SectionLabel(text: "恢复")
            Panel {
                VStack(alignment: .leading, spacing: T.S.m) {
                    SecondaryAction(title: "恢复默认外观", systemImage: "arrow.uturn.backward") {
                        showResetConfirm = true
                    }
                    SettingsNote(text: "只重置这一屏的偏好。本机密码、备份、钥匙串与门锁数据一项都不动。")
                }
            }
            .padding(.horizontal, T.S.gutter)
        }
    }
}