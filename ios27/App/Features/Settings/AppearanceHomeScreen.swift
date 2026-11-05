// AppearanceHomeScreen.swift —— 外观与时间显示（V8 设计语言）
//
// 与 AppearanceScreen 的能力对齐：主题 / 高对比 / 减少透明、品牌色六套 + 自定义强调色、无障碍段（← accessibility 整页并入：全局大字 / 放大临时码 / 系统态三行 / 样例）；
// 应用图标九套、圆角 / 凭证行高 / 时间线行距、主控读数三件、记录页开场策略、
// 提示音与防抖、密度与动效、时间显示（含样例）、快捷操作 10 选 N、恢复默认外观。
// 只改渲染层：偏好仍写 SettingsStore.shared 的同一批 kf_* 键，重置仍走 resetAppearance()。
//
// 与旧页的一处刻意差异：空壳模式（DB.isDecoy）下这一屏只读 —— 外观偏好本身不是档案，
// 但「恢复默认外观」会一次改写二十多个真实偏好键；空壳的纪律是只隐藏、不破坏。
import SwiftUI
import UIKit

struct AppearanceHomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var axReduceTransparency
    @Environment(\.colorSchemeContrast) private var axContrast

    private var store: SettingsStore { SettingsStore.shared }

    @State private var showResetConfirm = false
    @State private var iconError: String?

    private var decoyed: Bool { DB.isDecoy }

    // MARK: - 判断句与副文

    private var judgement: String {
        if decoyed { return "空壳模式下外观只读" }
        return "外观只在这台手机上生效"
    }

    private var lead: String {
        if decoyed {
            return "空壳模式只隐藏数据，不改动数据。外观偏好可以看，但这一屏不写入 —— 退出空壳后再调。"
        }
        return "主题、密度、动效与时间制式只存在这台手机上，不上传、不写门锁。"
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            if decoyed {
                EmptyView()
            } else {
                chipRow
            }
        } content: {
            if decoyed {
                decoyCard
            } else {
                themeCard
                accentCard
                iconCard
                geometryCard
                careCard
                rhythmCard
                timeCard
                quickCard
                accessibilityCard
                resetCard
                }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .v8Confirm(
            isPresented: $showResetConfirm,
            title: "恢复默认外观？",
            consequence: "只重置这一屏的偏好（主题 / 密度 / 动效 / 高对比 / 时间显示 / 快捷格）。本机密码、备份、钥匙串与门锁数据一项都不动。恢复后要逐项重新调回 —— 这一步不能撤销。",
            confirmTitle: "恢复默认外观",
            isDestructive: true
        ) {
            store.resetAppearance()
        }
    }

    // MARK: - 芯片行（四枚状态，不重复卡内读数）

    private var chipRow: some View {
        VHScroll {
            HStack(spacing: V8.S.gapChip) {
                VChip2(icon: .ring(1, V8.C.accent), label: "主题", value: store.theme.title)
                VChip2(icon: .ring(densityFraction, V8.C.ink2), label: "密度", value: store.density.title)
                VChip2(icon: .ring(motionFraction, V8.C.ok), label: "动效", value: store.motion.title)
                VChip2(icon: .glyph("clock"), label: "时间", value: store.timeStyle.title)
            }
            .padding(.leading, V8.S.gutterCard)
            .padding(.trailing, V8.S.gutterCard)
        }
        .scrollClipDisabled()
    }

    private var densityFraction: Double {
        switch store.density {
        case .compact: return 0.34
        case .standard: return 0.67
        case .relaxed: return 1
        }
    }

    private var motionFraction: Double {
        switch store.motion {
        case .calm: return 0.34
        case .standard: return 0.67
        case .lively: return 1
        }
    }

    // MARK: - 空壳

    private var decoyCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "外观", statement: "空壳模式只读")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("空壳模式（胁迫码进入）下，这一屏既不显示也不写入任何偏好 —— 否则在胁迫场景里点一下「恢复默认外观」，就会用默认值覆盖你真实的外观设置。")
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink3)
                .lineSpacing(V8.L.body - V8.T.body.size)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Text("退出空壳请在本机密码界面输入正常密码。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 卡 1 主题

    private var themeStatement: String {
        switch store.theme {
        case .system: return "跟随系统深浅"
        case .light: return "固定浅色"
        case .dark, .black: return "固定深色"
        }
    }

    private var themeCard: some View {
        VCard2 {
            VCardHead(eyebrow: "主题", statement: themeStatement)
            VDivider2()
                .padding(.top, V8.S.gapM)
            VHScroll {
                HStack(spacing: V8.S.gapChip) {
                    ForEach(AppearanceTheme.selectable) { item in
                        selectChip(item.title, on: store.theme == item) { store.theme = item }
                    }
                }
            }
            .scrollClipDisabled()
            .padding(.top, V8.S.gapM)
            toggleRow("高对比", detail: "与系统「辅助功能 · 增加对比度」是并联关系：任一开着都会加强描边与文字对比。", isOn: settingsBinding(\.highContrast))
            toggleRow("减少透明（玻璃退化为不透明面板）", detail: "系统「减少透明度」开启时自动生效；这里再开一道，让玻璃在楼道强光下也能读。", isOn: settingsBinding(\.reduceTransparency))
            Text("深色不是浅色的反相 —— 两套独立取值。深色底不是纯黑，留一点抬升空间给面板。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 卡 2 品牌色

    private static let accents: [(key: String, title: String, hex: Int)] = [
        ("indigo", "靛蓝", 0x4F46E5),
        ("forest", "森林", 0x1D6F5F),
        ("amber", "琥珀", 0xB45309),
        ("graphite", "石墨", 0x5B6169),
        ("rose", "玫红", 0xBE123C),
        ("aurora", "极光", 0x0E7490)
    ]

    private var accentCard: some View {
        VCard2 {
            VCardHead(eyebrow: "品牌色", statement: store.customAccent == 0 ? "六套预设" : "自定义强调色")
            VDivider2()
                .padding(.top, V8.S.gapM)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: V8.S.gapS), count: 3), spacing: V8.S.gapS) {
                ForEach(Array(Self.accents.enumerated()), id: \.offset) { pair in
                    accentCell(pair.element)
                }
            }
            .padding(.top, V8.S.gapM)
            VDivider2()
                .padding(.top, V8.S.gapM)
            ColorPicker(
                "自定义强调色（会盖过六套预设）",
                selection: Binding(
                    get: { store.accentColor },
                    set: { store.setCustomAccent($0) }
                ),
                supportsOpacity: false
            )
            .font(V8.T.body)
            .foregroundStyle(V8.C.ink1)
            .frame(minHeight: V8.H.min)
            if store.customAccent != 0 {
                Button {
                    store.clearCustomAccent()
                } label: {
                    Text("取消自定义，回到六套预设")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.ink1)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .overlay(
                            RoundedRectangle(cornerRadius: V8.R.capsule(V8.H.min), style: .continuous)
                                .strokeBorder(V8.C.line, lineWidth: V8.E.hair)
                        )
                }
                .buttonStyle(V8PressStyle())
                .padding(.top, V8.S.gapS)
                .accessibilityLabel("取消自定义强调色")
            }
            Text("强调色只影响系统 tint 与主控卡读数；文字与语义色仍走令牌。选到很亮的颜色时会压到能看清白字的亮度带。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func accentCell(_ item: (key: String, title: String, hex: Int)) -> some View {
        let on = store.customAccent == 0 && store.accent == item.key
        return Button {
            store.accent = item.key
            store.customAccent = 0
        } label: {
            HStack(spacing: V8.S.gapS) {
                Circle()
                    .fill(SettingsStore.color(hex: item.hex))
                    .frame(width: V8.S.gapM, height: V8.S.gapM)
                    .accessibilityHidden(true)
                Text(item.title)
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink1)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if on {
                    Image(systemName: "checkmark")
                        .font(V8.T.micro)
                        .foregroundStyle(V8.C.ink1)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, V8.S.gapS)
            .frame(minHeight: V8.H.min)
            .background(on ? V8.C.chipOn : V8.C.chipOff, in: .rect(cornerRadius: V8.R.inset))
        }
        .buttonStyle(V8PressStyle())
        .accessibilityLabel("品牌色 " + item.title)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - 卡 3 应用图标

    private static let alternateIcons: [(key: String, title: String, symbol: String)] = [
        ("AppIcon", "默认", "app.badge"),
        ("AppIcon-Bell", "门铃", "bell.fill"),
        ("AppIcon-Guard", "守护", "shield.lefthalf.filled"),
        ("AppIcon-Heart", "家人", "heart.fill"),
        ("AppIcon-Home", "归家", "house.fill"),
        ("AppIcon-Key", "钥匙", "key.horizontal.fill"),
        ("AppIcon-Pin", "密码", "number.square.fill"),
        ("AppIcon-Ring", "刻度", "circle.dashed"),
        ("AppIcon-Shield", "盾牌", "shield.fill")
    ]

    private var alternateIconName: String? { UIApplication.shared.alternateIconName }

    private var iconCard: some View {
        VCard2 {
            VCardHead(eyebrow: "应用图标", statement: alternateIconName == nil ? "默认图标" : "已换图标", trailing: "九套")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("换图标只改桌面上的样子，不改 App 名与任何数据。系统会弹一次「已更换」提示。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: V8.S.gapS), count: 3), spacing: V8.S.gapS) {
                ForEach(Array(Self.alternateIcons.enumerated()), id: \.offset) { pair in
                    iconCell(pair.element)
                }
            }
            .padding(.top, V8.S.gapM)
            if let iconError {
                VFailure(what: "换图标没有完成", why: iconError, next: "图标仍是原来那套，不影响使用；可以重试或换一套再试。")
                    .padding(.top, V8.S.gapM)
            }
        }
    }

    private func iconCell(_ item: (key: String, title: String, symbol: String)) -> some View {
        let on = alternateIconName == item.key
        return Button {
            setAlternateIcon(item.key)
        } label: {
            HStack(spacing: V8.S.gapS) {
                Image(systemName: item.symbol)
                    .font(V8.T.chipValue)
                    .foregroundStyle(on ? V8.C.accent : V8.C.ink3)
                    .accessibilityHidden(true)
                Text(item.title)
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink1)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if on {
                    Image(systemName: "checkmark")
                        .font(V8.T.micro)
                        .foregroundStyle(V8.C.ink1)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, V8.S.gapS)
            .frame(minHeight: V8.H.min)
            .background(on ? V8.C.chipOn : V8.C.chipOff, in: .rect(cornerRadius: V8.R.inset))
        }
        .buttonStyle(V8PressStyle())
        .accessibilityLabel("应用图标 " + item.title)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func setAlternateIcon(_ key: String) {
        iconError = nil
        let target: String? = key == "AppIcon" ? nil : key
        guard UIApplication.shared.supportsAlternateIcons else {
            iconError = "这台设备不支持换图标。"
            return
        }
        UIApplication.shared.setAlternateIconName(target) { error in
            Task { @MainActor in
                if let error {
                    iconError = "换图标失败：" + error.localizedDescription
                } else {
                    AppToast.shared.show(target == nil ? "已恢复默认图标" : "图标已更换", tone: .ok)
                }
            }
        }
    }

    // MARK: - 卡 4 几何

    private var geometryCard: some View {
        VCard2 {
            VCardHead(eyebrow: "几何", statement: "圆角三档")
            VDivider2()
                .padding(.top, V8.S.gapM)
            optionGroup(
                "圆角",
                [("标准", ""), ("偏硬朗", "soft"), ("偏柔和", "plump")],
                current: store.radius,
                pick: { store.radius = $0 }
            )
            // 2026-11-05（全技能审核 · 幽灵文案）：卡片头原来写「圆角 / 行高 / 行距」，
            // 但行高、行距控制早已随「有开关无消费者」删除 —— 只剩圆角一个控制。
            Text("圆角只动卡片与内嵌块的圆角档位；胶囊不参与，44pt 触达不变。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 卡 5 主控读数（2026-11-05 全技能审核：整卡删除）
    //
    // 原卡的两个开关写 HeroStats（"门页显示固件位 / 锁钟位"），但 V8 门页 heroCard
    // 从来只读 app.dialPhase/battery，全仓没有任何 UI 读 HeroStats —— 两个开关是纯幽灵。
    // 删除 UI，保留 Engine/HeroStats 以兼容旧备份导入（BackupKit 仍读写 kf_hero_stats）。


    // MARK: - 卡 7 开锁与关怀

    private var careCard: some View {
        VCard2 {
            VCardHead(eyebrow: "开锁与关怀", statement: "提示音与防抖")
            VDivider2()
                .padding(.top, V8.S.gapM)
            toggleRow("双击防抖（0.3 秒内忽略重复触发）", detail: "门口手抖连点两下只算一次，避免重复下发开锁。", isOn: settingsBinding(\.dbltapGuard))
            toggleRow("夜间免扰（22:00–08:00 静音提示音）", detail: "夜间低电等提醒只留横幅，不响提示音。", isOn: settingsBinding(\.quietNight))
        }
    }

    // MARK: - 卡 8 节奏

    private var rhythmCard: some View {
        VCard2 {
            VCardHead(eyebrow: "节奏", statement: store.density.title + " · " + store.motion.title)
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("布局密度")
                .font(V8.T.label)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
            VHScroll {
                HStack(spacing: V8.S.gapChip) {
                    ForEach(LayoutDensity.allCases) { item in
                        selectChip(item.title, on: store.density == item) { store.density = item }
                    }
                }
            }
            .scrollClipDisabled()
            .padding(.top, V8.S.gapS)
            Text("只改间距节奏，字号与 44pt 触达不动 —— 压小按钮不是「紧凑」，是点不准。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
            Text("动效强度")
                .font(V8.T.label)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
            VHScroll {
                HStack(spacing: V8.S.gapChip) {
                    ForEach(MotionTier.allCases) { item in
                        selectChip(item.title, on: store.motion == item) { store.motion = item }
                    }
                }
            }
            .scrollClipDisabled()
            .padding(.top, V8.S.gapS)
            // 2026-11-05（全技能审核 · 幽灵文案）：原文承诺「取消数字滚动与逐格点亮」，
            // 但这两件事从未按 MotionTier 实现（数字 transition 只看 reduceMotion，逐格点亮根本不存在）。
            // 现在 V8.M 的四个动效令牌已按 kf_motion 分档，文案改成描述真实行为。
            Text(systemReduceMotion
                 ? "系统已开启「减弱动态效果」：所有位移动画取消，只保留必要的信息变化。"
                 : "克制档把所有弹跳压成短淡入；活泼档允许一次轻微回弹。系统「减弱动态效果」始终优先。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 卡 9 时间显示

    private var now: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    /// 制式由 TimeDisplay 统一算（12/24 + 秒），这一屏只负责展示与改档。
    private var previewClock: String { TimeDisplay.clock(now) }

    private var timeCard: some View {
        VCard2 {
            VCardHead(eyebrow: "时间显示", statement: "全 App 唯一出口", trailing: "全局")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VHScroll {
                HStack(spacing: V8.S.gapChip) {
                    ForEach(TimeDisplayStyle.allCases) { item in
                        selectChip(item.title, on: store.timeStyle == item) { store.timeStyle = item }
                    }
                }
            }
            .scrollClipDisabled()
            .padding(.top, V8.S.gapM)
            Text("选「跟随系统」以外的档位后，本 App 不再听系统的 12/24 小时偏好 —— 一个开关管一件事。制式不做时区换算：锁端键盘上是几点，这里就显示几点。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            toggleRow("显示秒", detail: "只在日志原文真的带秒时出现；缺位的行不补「:00」—— 那等于假装这条记录精确到秒。", isOn: settingsBinding(\.showSeconds))
            toggleRow("记录行加第二行完整日期", detail: "台账行在时刻下面补一行 MM-DD。跨年的记录才显示年。", isOn: settingsBinding(\.twoLineDate))
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("样例读数")
                .font(V8.T.label)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
            HStack(alignment: .firstTextBaseline, spacing: V8.S.gapS) {
                Text(previewClock)
                    .font(V8.T.title1)
                    .foregroundStyle(V8.C.ink1)
                    .monospacedDigit()
                    .contentTransition(systemReduceMotion ? .identity : .numericText())
                    .animation(systemReduceMotion ? nil : V8.M.snap, value: previewClock)
                Spacer(minLength: 0)
                if let dayLine = TimeDisplay.dayLine(now) {
                    Text(dayLine)
                        .font(V8.T.footnote)
                        .foregroundStyle(V8.C.ink3)
                        .monospacedDigit()
                }
            }
            .padding(.top, V8.S.gapS)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("时间显示样例 " + previewClock)
        }
    }

    // MARK: - 卡 10 快捷操作

    private var quickCard: some View {
        VCard2 {
            VCardHead(eyebrow: "快捷操作", statement: "首页显示几枚")
            VDivider2()
                .padding(.top, V8.S.gapM)
            HStack(spacing: V8.S.gapChip) {
                ForEach([4, 6, 8], id: \.self) { n in
                    selectChip("\(n) 枚", on: store.quickGridCount == n) { store.quickGridCount = n }
                }
            }
            .padding(.top, V8.S.gapM)
            toggleRow("常用操作自动排前", detail: "按你实际点过的次数排序（存本机，不上传）。关掉后按下面勾选的顺序。", isOn: Binding(
                get: { QuickPool.smartFirst },
                set: { QuickPool.setSmartFirst($0) }
            ))
            Text("快捷池（10 选 6，至少留 1 项）")
                .font(V8.T.label)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: V8.S.gapS), count: 2), spacing: V8.S.gapS) {
                ForEach(QuickPool.all) { action in
                    quickCell(action)
                }
            }
            .padding(.top, V8.S.gapS)
            Text("勾选结果即时生效到「门」页的快捷操作卡；这里只管显示与排序，不发任何锁端命令。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func quickCell(_ action: QuickAction) -> some View {
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
            HStack(spacing: V8.S.gapS) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .accessibilityHidden(true)
                    .font(V8.T.chipValue)
                    .foregroundStyle(selected ? V8.C.accent : V8.C.ink3)
                Text(action.label)
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink1)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, V8.S.gapS)
            .frame(minHeight: V8.H.min)
            .background(V8.C.chipOff, in: .rect(cornerRadius: V8.R.inset))
        }
        .buttonStyle(V8PressStyle())
        .accessibilityLabel(action.label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - 卡 11 无障碍（并入自 AccessibilityHomeScreen）

    /// 「无障碍」段（← accessibility / AccessibilityHomeScreen）：
    /// 看得清（全局大字 / 放大临时码）+ 系统态三行 + 样例。
    /// 真链路原样：全局大字仍写 SettingsStore.axBigText（kf_ax_bigtext，LockKeeperApp 的
    /// AXTextSizeModifier 是它的消费点）；放大临时码仍写 kf_ax_bigotp（ZotpHomeScreen 的码字号消费点）。
    /// 大格模式（kf_bigtile）已随「快捷格 10 选 N」并入上面的「快捷操作」卡，这里不再重复开关。
    @State private var axBigOTP = DB.store.getBool("kf_ax_bigotp")

    private var accessibilityCard: some View {
        VCard2 {
            VCardHead(eyebrow: "无障碍", statement: "看得清 · 点得准")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                toggleRow("全局大字", detail: "动态字重放大到辅助功能档（Accessibility 2），所有页面跟着放大。", isOn: settingsBinding(\.axBigText))
                VDotRule()
                toggleRow("放大临时码", detail: "生成动态码时用大字号显示六位码，并允许双击切换。", isOn: Binding(
                    get: { axBigOTP },
                    set: { on in
                        axBigOTP = on
                        DB.store.set("kf_ax_bigotp", on)
                    }
                ))
            }
            .padding(.top, V8.S.gapS)
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                VDataRow(tag: "系统", tagTint: V8.C.ink4, title: "减弱动态效果", value: systemReduceMotion ? "系统已开" : "系统未开")
                VDotRule()
                VDataRow(tag: "系统", tagTint: V8.C.ink4, title: "减少透明度", value: axReduceTransparency ? "系统已开" : "系统未开")
                VDotRule()
                VDataRow(tag: "系统", tagTint: V8.C.ink4, title: "增加对比度", value: axContrast == .increased ? "系统已开" : "系统未开")
            }
            .padding(.top, V8.S.gapS)
            Text("系统「减弱动态效果 / 增加对比度 / 减少透明度」与这里的开关是并联关系：任一开启都生效。系统态只如实显示，不重复开关。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Text("开门成功")
                .font(store.axBigText ? V8.T.title2 : V8.T.headline)
                .foregroundStyle(V8.C.ink1)
                .padding(.top, V8.S.gapM)
            Text("这一行会跟随全局大字档变化。")
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapS)
        }
    }

    // MARK: - 卡 12 恢复默认

    private var resetCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "恢复", statement: "只重置外观偏好")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Button {
                showResetConfirm = true
            } label: {
                Text("恢复默认外观")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.danger)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .overlay(
                        RoundedRectangle(cornerRadius: V8.R.capsule(V8.H.min), style: .continuous)
                            .strokeBorder(V8.C.line, lineWidth: V8.E.hair)
                    )
            }
            .buttonStyle(V8PressStyle())
            .accessibilityLabel("恢复默认外观")
            .padding(.top, V8.S.gapM)
            // 2026-11-05（对抗审查 · 设计冗余）：「只读试验模式 · 本页不受影响」原来是一整张卡，
            // 卡里只有一句「这里不受影响」—— 一张不承载任何操作的卡就是一个多余的边界。
            // 那句话并入本卡脚注：信息不丢，卡片少一张。
            Text("只重置这一屏的偏好。本机密码、备份、钥匙串与门锁数据一项都不动。"
                 + "只读试验模式拦的是下发到门锁的写命令与导入备份；外观偏好属于本机设置，仍可修改 —— 这里如实告诉你，不假装被拦。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 行构件

    private func selectChip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(V8.T.tab)
                .foregroundStyle(on ? V8.C.chipOn : V8.C.ink1)
                .padding(.horizontal, V8.S.gapM)
                .frame(minHeight: V8.H.min)
                .background(Capsule(style: .continuous).fill(on ? V8.C.accent : V8.C.chipOff))
        }
        .buttonStyle(V8PressStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func toggleRow(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: V8.S.gapXS) {
            Toggle(isOn: isOn) {
                Text(title)
                    .font(V8.T.value)
                    .foregroundStyle(V8.C.ink1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: V8.H.min)
            Text(detail)
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, V8.S.gapS)
    }

    private func optionGroup(
        _ title: String,
        _ options: [(String, String)],
        current: String,
        pick: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: V8.S.gapS) {
            Text(title)
                .font(V8.T.label)
                .foregroundStyle(V8.C.ink4)
            VHScroll {
                HStack(spacing: V8.S.gapChip) {
                    ForEach(Array(options.enumerated()), id: \.offset) { pair in
                        selectChip(pair.element.0, on: current == pair.element.1) {
                            pick(pair.element.1)
                        }
                    }
                }
            }
            .scrollClipDisabled()
        }
        .padding(.top, V8.S.gapM)
    }
}

