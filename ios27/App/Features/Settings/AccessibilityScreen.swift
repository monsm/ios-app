// AccessibilityScreen.swift —— 无障碍与操作辅助（AXPrefs）。
//
// 来源：原 App/Core/AccessibilityKit.swift（AXPrefs：大字、放大临时码、按住确认、大格、圆盘尺寸、
//   手势模式、高对比、减弱动效）+ App/Core/ToastCenter 的无障碍播报口径。
// 这屏干什么：把「看不看得清 / 点不点得准 / 手势怎么算确认」收成一页，所有档位即时生效并落盘。
// 数据从哪来：本页 AXSettings（kf_ax_* 键）；RootView 读 dynamicTypeSize 让大字真正作用到全 App。
// 主动作：无 —— 全是档位开关，不写门锁。
import SwiftUI

enum AXSettings {
    static var bigText: Bool { SettingsStore.shared.axBigText }
    static var bigOTP: Bool { DB.store.getBool("kf_ax_bigotp") }
    static var holdConfirm: Bool { DB.store.getBool("kf_hold_confirm", true) }
    static var bigTile: Bool { DB.store.getBool("kf_bigtile") }
    static var dialSize: String { DB.store.getString("kf_dial_size", "standard") }
    static var gestureMode: String { DB.store.getString("kf_gesture_mode", "hold") }

    static var dynamicTypeSize: DynamicTypeSize {
        bigText ? .accessibility2 : .large
    }
}

struct AccessibilityScreen: View {
    @State private var bigText = SettingsStore.shared.axBigText
    @State private var bigOTP = AXSettings.bigOTP
    @State private var holdConfirm = AXSettings.holdConfirm
    @State private var bigTile = AXSettings.bigTile
    @State private var dialSize = AXSettings.dialSize
    @State private var gestureMode = AXSettings.gestureMode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V.S.gapM) {
                header
                textCard
                touchCard
                motionCard
                previewCard
            }
            .padding(.top, V.Page.topSpace)
            .padding(.bottom, V.Tab.contentInset)
        }
        .background(V.C.bg.ignoresSafeArea())
        .navigationTitle("无障碍")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: V.S.gapXXS) {
            Text("无障碍与操作辅助")
                .font(V.F.displayA).foregroundStyle(V.C.text1)
            Text("所有档位即时生效、只存本机。")
                .font(V.F.footnote).foregroundStyle(V.C.text3)
        }
        .padding(.horizontal, V.S.pageGutterA)
    }

    private var textCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "看得清")
                VToggleRow(title: "全局大字", detail: "动态字重放大到辅助功能档（Accessibility 2），所有页面跟着放大。", isOn: Binding(
                    get: { bigText },
                    set: { on in bigText = on; SettingsStore.shared.axBigText = on }
                ))
                VRowDivider()
                VToggleRow(title: "放大临时码", detail: "生成 ZOTP 时用大字号显示六位码，并允许双击切换。", isOn: Binding(
                    get: { bigOTP },
                    set: { on in bigOTP = on; DB.store.set("kf_ax_bigotp", on) }
                ))
                VRowDivider()
                VToggleRow(title: "大格模式", detail: "首页快捷操作与凭证行加高，减少误触。", isOn: Binding(
                    get: { bigTile },
                    set: { on in bigTile = on; DB.store.set("kf_bigtile", on) }
                ))
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private var touchCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "点得准")
                Text("圆盘尺寸")
                    .font(V.F.chipLabel).foregroundStyle(V.C.text4)
                HStack(spacing: V.S.gapS) {
                    ForEach(Array([(key: "small", label: "小"), (key: "standard", label: "标准"), (key: "large", label: "大")].enumerated()), id: \.offset) { pair in
                        let item = pair.element
                        Button { dialSize = item.key; DB.store.set("kf_dial_size", item.key) } label: {
                            VTag(text: item.label, tint: dialSize == item.key ? V.C.blue : V.C.text3, filled: dialSize == item.key)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                VRowDivider()
                Text("开锁手势")
                    .font(V.F.chipLabel).foregroundStyle(V.C.text4)
                HStack(spacing: V.S.gapS) {
                    ForEach(Array([(key: "hold", label: "按住开锁"), (key: "tap", label: "轻点开锁"), (key: "double", label: "双击开锁")].enumerated()), id: \.offset) { pair in
                        let item = pair.element
                        Button { gestureMode = item.key; DB.store.set("kf_gesture_mode", item.key) } label: {
                            VTag(text: item.label, tint: gestureMode == item.key ? V.C.blue : V.C.text3, filled: gestureMode == item.key)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                VRowDivider()
                VToggleRow(title: "按住确认开锁", detail: "关掉后退回轻点直开，单手更省力但误触也会开门。", isOn: Binding(
                    get: { holdConfirm },
                    set: { on in holdConfirm = on; DB.store.set("kf_hold_confirm", on) }
                ))
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private var motionCard: some View {
        VCard(style: .warm) {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "动效与对比")
                Text("系统「减弱动态效果 / 增加对比度 / 减少透明度」与本页是并联关系：任一开启都生效。这里不重复开关，只如实告诉你当前系统状态。")
                    .font(V.F.body).foregroundStyle(V.C.text9)
                    .fixedSize(horizontal: false, vertical: true)
                AccessibilityStatusRows()
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private var previewCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "样例")
                Text("开门成功")
                    .font((bigText ? V.F.axTitleBig : V.F.axTitle))
                    .foregroundStyle(V.C.text1)
                Text("这一行会跟随全局大字档变化。")
                    .font(V.F.body)
                    .foregroundStyle(V.C.text2)
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }
}

/// 系统无障碍三态只读展示（不伪造 App 内开关）。
private struct AccessibilityStatusRows: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: V.S.gapXS) {
            VValueRow(label: "减弱动态效果", value: reduceMotion ? "系统已开" : "系统未开")
            VValueRow(label: "减少透明度", value: reduceTransparency ? "系统已开" : "系统未开")
            VValueRow(label: "增加对比度", value: contrast == .increased ? "系统已开" : "系统未开")
        }
    }
}

#Preview("AccessibilityScreen") {
    NavigationStack { AccessibilityScreen() }
        .environment(AppModel())
        .environment(Router())
}
