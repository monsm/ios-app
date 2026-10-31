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
            VStack(spacing: V.S.gap16) {
                SettingsHeader(title: "外观", tone: tone, status: status)
                themePanel
                accentPanel
                rhythmPanel
                geometryPanel
                readoutPanel
                recordPanel
                carePanel
                timePanel
                quickPanel
                resetPanel
            }
            .padding(.vertical, V.S.gap16)
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
        VStack(spacing: V.S.gapS) {
            VSectionLabel(text: "主题")
            VCard {
                VStack(alignment: .leading, spacing: V.S.gapMS) {
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
            .padding(.horizontal, V.S.pageGutter)
        }
    }

    // MARK: 品牌色六套 + 自定义强调色（#28）

    private var accentPanel: some View {
        VStack(spacing: V.S.gapS) {
            VSectionLabel(text: "品牌色", trailing: store.customAccent == 0 ? "六套预设" : "自定义")
            VCard {
                VStack(alignment: .leading, spacing: V.S.gapMS) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: V.S.gapS), count: 3), spacing: V.S.gapS) {
                        ForEach(Array(Self.accents.enumerated()), id: \.offset) { pair in
                            let item = pair.element
                            let on = store.customAccent == 0 && store.accent == item.key
                            Button {
                                store.accent = item.key
                                store.customAccent = 0
                            } label: {
                                HStack(spacing: V.S.gapS) {
                                    Circle()
                                        .fill(SettingsStore.color(hex: item.hex))
                                        .frame(width: V.Icon.s, height: V.Icon.s)
                                    Text(item.title)
                                        .font(V.F.footnote)
                                        .foregroundStyle(V.C.text1)
                                    Spacer(minLength: 0)
                                    if on {
                                        Image(systemName: "checkmark")
                                            .font(V.F.icon15)
                                            .foregroundStyle(V.C.text1)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .padding(.horizontal, V.S.gapS)
                                .frame(minHeight: V.Hit.min)
                                .background(on ? V.C.cardAlt : Color.clear, in: .rect(cornerRadius: V.R.control))
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("品牌色 \(item.title)")
                            .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                    SettingRule()
                    ColorPicker("自定义强调色（会盖过六套预设）",
                                selection: Binding(
                                    get: { store.accentColor },
                                    set: { store.setCustomAccent($0) }
                                ),
                                supportsOpacity: false)
                        .font(V.F.body)
                        .foregroundStyle(V.C.text1)
                        .frame(minHeight: V.Hit.min)
                    if store.customAccent != 0 {
                        VOutlineButton(title: "取消自定义，回到六套预设", systemImage: "arrow.uturn.backward") {
                            store.clearCustomAccent()
                        }
                    }
                    SettingsNote(text: "强调色只影响系统 tint 与主控卡读数；文字与语义色仍走令牌。选到很亮的颜色时会压到能看清白字的亮度带。")
                }
            }
            .padding(.horizontal, V.S.pageGutter)
        }
    }

    private static let accents: [(key: String, title: String, hex: Int)] = [
        ("indigo", "靛蓝", 0x4F46E5),
        ("forest", "森林", 0x1D6F5F),
        ("amber", "琥珀", 0xB45309),
        ("graphite", "石墨", 0x5B6169),
        ("rose", "玫红", 0xBE123C),
        ("aurora", "极光", 0x0E7490)
    ]

    // MARK: 圆角 / 行高 / 时间线行距（#29 #30）

    private var geometryPanel: some View {
        VStack(spacing: V.S.gapS) {
            VSectionLabel(text: "几何")
            VCard {
                VStack(alignment: .leading, spacing: V.S.gapMS) {
                    Text("圆角")
                        .font(V.F.unit)
                        .foregroundStyle(V.C.text3)
                        .tracking(0.6)
                    SettingChips(items: ["", "soft", "plump"],
                                 title: { $0.isEmpty ? "标准" : ($0 == "soft" ? "偏硬朗" : "偏柔和") },
                                 selection: settingsBinding(\.radius))
                    SettingRule()
                    Text("凭证行高")
                        .font(V.F.unit)
                        .foregroundStyle(V.C.text3)
                        .tracking(0.6)
                    SettingChips(items: ["", "tall"],
                                 title: { $0.isEmpty ? "紧凑" : "舒适" },
                                 selection: settingsBinding(\.rowHeight))
                    SettingRule()
                    Text("时间线行距")
                        .font(V.F.unit)
                        .foregroundStyle(V.C.text3)
                        .tracking(0.6)
                    SettingChips(items: ["tight", "", "loose"],
                                 title: { $0 == "tight" ? "紧凑" : ($0 == "loose" ? "宽松" : "标准") },
                                 selection: settingsBinding(\.timelineGap))
                    SettingsNote(text: "圆角只动卡片 / 控件 / 面板三档，胶囊不参与；行高与行距不改字号与 44pt 触达。")
                }
            }
            .padding(.horizontal, V.S.pageGutter)
        }
    }

    // MARK: 主控读数 / 指标位 / 最近开门条数（#30 #31）

    private var readoutPanel: some View {
        VStack(spacing: V.S.gapS) {
            VSectionLabel(text: "主控读数")
            VCard {
                VStack(alignment: .leading, spacing: V.S.gapMS) {
                    Text("数字字体")
                        .font(V.F.unit)
                        .foregroundStyle(V.C.text3)
                        .tracking(0.6)
                    SettingChips(items: ["", "plain"],
                                 title: { $0 == "plain" ? "系统默认体" : "圆体" },
                                 selection: settingsBinding(\.digitFont))
                    SettingRule()
                    VToggleRow(title: "主控卡显示固件位", detail: "电量不参与隐藏 —— 它决定还能不能开锁。", isOn: Binding(
                        get: { HeroStats.shows("firmware") },
                        set: { on in
                            var ids = Array(HeroStats.visible)
                            if on { if !ids.contains("firmware") { ids.append("firmware") } }
                            else { ids.removeAll { $0 == "firmware" } }
                            HeroStats.setVisible(ids)
                        }
                    ))
                    SettingRule()
                    VToggleRow(title: "主控卡显示锁钟位", detail: "锁钟是临时码有效性的判据，可以收起。", isOn: Binding(
                        get: { HeroStats.shows("lockclock") },
                        set: { on in
                            var ids = Array(HeroStats.visible)
                            if on { if !ids.contains("lockclock") { ids.append("lockclock") } }
                            else { ids.removeAll { $0 == "lockclock" } }
                            HeroStats.setVisible(ids)
                        }
                    ))
                    SettingRule()
                    Text("最近开门条数")
                        .font(V.F.unit)
                        .foregroundStyle(V.C.text3)
                        .tracking(0.6)
                    HStack(spacing: V.S.gapS) {
                        ForEach([3, 5, 10], id: \.self) { n in
                            Button {
                                store.recentCount = n
                            } label: {
                                VTag(text: "\(n) 条", tint: store.recentCount == n ? V.C.blue : V.C.text3,
                                     filled: store.recentCount == n)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("最近开门显示 \(n) 条")
                            .accessibilityAddTraits(store.recentCount == n ? [.isButton, .isSelected] : .isButton)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: V.Hit.min)
                }
            }
            .padding(.horizontal, V.S.pageGutter)
        }
    }

    // MARK: 记录页开场策略（#31）

    private var recordPanel: some View {
        VStack(spacing: V.S.gapS) {
            VSectionLabel(text: "记录页")
            VCard {
                VStack(alignment: .leading, spacing: V.S.gapMS) {
                    SettingChips(items: ["", "fresh", "alarm"],
                                 title: { $0 == "fresh" ? "每次全部" : ($0 == "alarm" ? "每次只看告警" : "记住上次") },
                                 selection: settingsBinding(\.recordPolicy))
                    SettingsNote(text: "只改进入记录页时的起点；手动改过的过滤仍按锁保留，不会删任何记录。")
                }
            }
            .padding(.horizontal, V.S.pageGutter)
        }
    }

    // MARK: 长按时长 / 双击防抖 / 夜间免扰（#32）

    private var carePanel: some View {
        VStack(spacing: V.S.gapS) {
            VSectionLabel(text: "开锁与关怀")
            VCard {
                VStack(alignment: .leading, spacing: V.S.gapMS) {
                    Text("长按确认时长")
                        .font(V.F.unit)
                        .foregroundStyle(V.C.text3)
                        .tracking(0.6)
                    HStack(spacing: V.S.gapS) {
                        ForEach([0.4, 0.6, 0.9, 1.2, 1.6], id: \.self) { seconds in
                            Button {
                                store.holdDuration = seconds
                            } label: {
                                VTag(text: String(format: "%.1f", seconds),
                                     tint: abs(store.holdDuration - seconds) < 0.01 ? V.C.blue : V.C.text3,
                                     filled: abs(store.holdDuration - seconds) < 0.01)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(format: "长按 %.1f 秒", seconds))
                            .accessibilityAddTraits(abs(store.holdDuration - seconds) < 0.01 ? [.isButton, .isSelected] : .isButton)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: V.Hit.min)
                    SettingRule()
                    SettingToggle(
                        label: "双击防抖（0.3 秒内忽略重复触发）",
                        note: "门口手抖连点两下只算一次，避免重复下发开锁。",
                        isOn: settingsBinding(\.dbltapGuard)
                    )
                    SettingRule()
                    SettingToggle(
                        label: "夜间免扰（22:00–08:00 静音提示音）",
                        note: "夜间低电等提醒只留横幅，不响提示音。",
                        isOn: settingsBinding(\.quietNight)
                    )
                }
            }
            .padding(.horizontal, V.S.pageGutter)
        }
    }

    // MARK: 密度与动效
    private var rhythmPanel: some View {
        VStack(spacing: V.S.gapS) {
            VSectionLabel(text: "节奏")
            VCard {
                VStack(alignment: .leading, spacing: V.S.gapMS) {
                    Text("布局密度")
                        .font(V.F.unit)
                        .foregroundStyle(V.C.text3)
                        .tracking(0.6)
                    SettingChips(items: LayoutDensity.allCases,
                                 title: { $0.title },
                                 selection: settingsBinding(\.density))
                    SettingsNote(text: "只改间距节奏，字号与 44pt 触达不动 —— 压小按钮不是「紧凑」，是点不准。")
                    SettingRule()
                    Text("动效强度")
                        .font(V.F.unit)
                        .foregroundStyle(V.C.text3)
                        .tracking(0.6)
                    SettingChips(items: MotionTier.allCases,
                                 title: { $0.title },
                                 selection: settingsBinding(\.motion))
                    SettingsNote(text: systemReduceMotion
                                 ? "系统已开启「减弱动态效果」：进度弧保留（它是信息），数字滚动与逐格点亮已取消。"
                                 : "克制档取消数字滚动与逐格点亮；开锁进度弧在任何档位都保留 —— 它量的是真命令链。")
                }
            }
            .padding(.horizontal, V.S.pageGutter)
        }
    }

    // MARK: 时间显示（全 App 唯一出口）
    private var timePanel: some View {
        VStack(spacing: V.S.gapS) {
            VSectionLabel(text: "时间显示", trailing: "全局")
            VCard {
                VStack(alignment: .leading, spacing: V.S.gapMS) {
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
            .padding(.horizontal, V.S.pageGutter)
        }
    }

    // MARK: 时间样例：档位真的改了读数（不是摆设）
    private var timePreview: some View {
        VStack(alignment: .leading, spacing: V.S.gapXS) {
            Text("样例读数")
                .font(V.F.unit)
                .foregroundStyle(V.C.text3)
                .tracking(0.6)
            HStack(alignment: .firstTextBaseline, spacing: V.S.gapS) {
                Text(previewClock)
                    .font(V.F.stamp)
                    .foregroundStyle(V.C.text1)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    // 这里用 systemReduceMotion（本文件的环境值名）：
                    // 与 store 里的"App 内动效档"是两个独立开关 —— 系统的是硬约束，App 内的是偏好。
                    .animation(systemReduceMotion ? nil : V.M.snap, value: previewClock)
                Spacer(minLength: 0)
                if let dayLine = TimeDisplay.dayLine(now) {
                    Text(dayLine)
                        .font(V.F.unit)
                        .foregroundStyle(V.C.text3)
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
        VStack(spacing: V.S.gapS) {
            VSectionLabel(text: "快捷操作")
            VCard {
                VStack(alignment: .leading, spacing: V.S.gapMS) {
                    Text("首页显示几枚")
                        .font(V.F.unit)
                        .foregroundStyle(V.C.text3)
                        .tracking(0.6)
                    HStack(spacing: V.S.gapS) {
                        ForEach([4, 6, 8], id: \.self) { n in
                            Button {
                                store.quickGridCount = n
                            } label: {
                                Text("\(n) 枚")
                                    .font(V.F.bodyStrong)
                                    .foregroundStyle(store.quickGridCount == n ? V.C.text1 : V.C.text1)
                                    .padding(.horizontal, V.S.gapMS)
                                    .frame(minHeight: V.Hit.min)
                                    .background(store.quickGridCount == n ? V.C.blue : V.C.cardAlt, in: .rect(cornerRadius: V.R.control))
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
                        .font(V.F.unit)
                        .foregroundStyle(V.C.text3)
                        .tracking(0.6)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: V.S.gapS), count: 2), spacing: V.S.gapS) {
                        ForEach(QuickPool.all) { action in
                            quickToggle(action)
                        }
                    }
                    SettingsNote(text: "勾选结果即时生效到「门」页的快捷操作卡；这里只管显示与排序，不发任何锁端命令。")
                }
            }
            .padding(.horizontal, V.S.pageGutter)
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
            HStack(spacing: V.S.gapS) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .accessibilityHidden(true)
                    .font(V.F.icon15Medium)
                    .foregroundStyle(selected ? V.C.blue : V.C.text3)
                Text(action.label)
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text1)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, V.S.gapS)
            .frame(minHeight: V.Hit.min)
            .background(V.C.cardAlt, in: .rect(cornerRadius: V.R.control))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: 恢复默认
    private var resetPanel: some View {
        VStack(spacing: V.S.gapS) {
            VSectionLabel(text: "恢复")
            VCard {
                VStack(alignment: .leading, spacing: V.S.gapMS) {
                    VOutlineButton(title: "恢复默认外观", systemImage: "arrow.uturn.backward") {
                        showResetConfirm = true
                    }
                    SettingsNote(text: "只重置这一屏的偏好。本机密码、备份、钥匙串与门锁数据一项都不动。")
                }
            }
            .padding(.horizontal, V.S.pageGutter)
        }
    }
}