// AccessibilityScreen.swift —— 无障碍与操作辅助（AXPrefs）。
//
// 来源：原 App/Core/AccessibilityKit.swift（AXPrefs：大字、放大临时码、按住确认、大格、圆盘尺寸、
//   手势模式、高对比、减弱动效）+ App/Core/ToastCenter 的无障碍播报口径。
// 这屏干什么：把「看不看得清 / 点不点得准 / 手势怎么算确认」收成一页，所有档位即时生效并落盘。
// 数据从哪来：本页 AXSettings（kf_ax_* 键）；大字真正作用到全 App 的是 LockKeeperApp 的
//   `content.dynamicTypeSize(.accessibility2)`，读 `settings.axBigText`（不经过 AXSettings）。
// 主动作：无 —— 全是档位开关，不写门锁。
import SwiftUI

@MainActor
enum AXSettings {
    static var bigText: Bool { SettingsStore.shared.axBigText }
    static var bigOTP: Bool { DB.store.getBool("kf_ax_bigotp") }
    static var holdConfirm: Bool { DB.store.getBool("kf_hold_confirm", true) }
    static var bigTile: Bool { DB.store.getBool("kf_bigtile") }
    static var dialSize: String { DB.store.getString("kf_dial_size", "standard") }
    static var gestureMode: String { DB.store.getString("kf_gesture_mode", "hold") }

    // D5（ui-ia §4.3）：原 `AXSettings.dynamicTypeSize` 已删 —— 全仓 0 调用。
    // 大字真正生效的点是 `LockKeeperApp.swift:146` 的 `content.dynamicTypeSize(.accessibility2)`，
    // 它读的是 `settings.axBigText`（`SettingsStore`），不经过本枚举。留着这个属性会让人
    // 以为"改这里就能改全局字号"，而实际改不动。
}

struct AccessibilityScreen: View {
    // E-13：这六个 @State 是「持久层的镜像」。@State 的初值只在视图**首次创建**时取一次，
    // 所以别的页面改了同一个键（外观页的 ColorPicker、设置页开关、以及「恢复默认外观」
    // 会整体重置 axBigText / holdConfirm 等）时，这一页会继续显示旧值 —— 两份真相。
    // 保留 @State 是为了点一下就有反馈；每次出现时从持久层重新同步一次。
    @State private var bigText = SettingsStore.shared.axBigText
    @State private var bigOTP = AXSettings.bigOTP
    @State private var holdConfirm = AXSettings.holdConfirm
    @State private var bigTile = AXSettings.bigTile
    @State private var dialSize = AXSettings.dialSize
    @State private var gestureMode = AXSettings.gestureMode

    private func syncFromStore() {
        bigText = SettingsStore.shared.axBigText
        bigOTP = AXSettings.bigOTP
        holdConfirm = AXSettings.holdConfirm
        bigTile = AXSettings.bigTile
        dialSize = AXSettings.dialSize
        gestureMode = AXSettings.gestureMode
    }

    var body: some View {
        // 2026-11-02（R4 全换系统）：页面容器从 ScrollView + VStack 换成系统 List。
        // 四段（看得清 / 点得准 / 动效与对比 / 样例）现在是四个 Section，
        // 开关与分段控件是**直接的行**（系统行内边距 + 系统分隔线 + 系统行点击），
        // 不再套一层 VCard 再自绘 VRowDivider —— 那等于在 List 里再造一张卡。
        // 业务逻辑、写盘键、禁用判据、无障碍标签一字未改。
        List {
            header.plainRow()

            Section {
                VToggleRow(title: "全局大字", detail: "动态字重放大到辅助功能档（Accessibility 2），所有页面跟着放大。", isOn: Binding(
                    get: { bigText },
                    set: { on in bigText = on; SettingsStore.shared.axBigText = on }
                ))
                VToggleRow(title: "放大临时码", detail: "生成 ZOTP 时用大字号显示六位码，并允许双击切换。", isOn: Binding(
                    get: { bigOTP },
                    set: { on in bigOTP = on; DB.store.set("kf_ax_bigotp", on) }
                ))
                VToggleRow(title: "大格模式", detail: "首页快捷操作与凭证行加高，减少误触。", isOn: Binding(
                    get: { bigTile },
                    set: { on in bigTile = on; DB.store.set("kf_bigtile", on) }
                ))
            } header: {
                sectionHeader("看得清")
            }

            Section {
                VStack(alignment: .leading, spacing: V.S.gapS) {
                    Text("圆盘尺寸")
                        .font(V.F.chipLabel).foregroundStyle(V.C.text4)
                    // 全换系统（2026-11-02）：三档单选交给系统分段控件（系统自带玻璃底座与按压反馈），
                    // 不再用三个自绘 VTag 冒充单选。
                    Picker("圆盘尺寸", selection: Binding(
                        get: { dialSize },
                        set: { dialSize = $0; DB.store.set("kf_dial_size", $0) }
                    )) {
                        Text("小").tag("small")
                        Text("标准").tag("standard")
                        Text("大").tag("large")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .frame(minHeight: V.Hit.min)

                VStack(alignment: .leading, spacing: V.S.gapS) {
                    Text("开锁手势")
                        .font(V.F.chipLabel).foregroundStyle(V.C.text4)
                    // 全换系统（2026-11-02）：三档单选交给系统分段控件。
                    // Round 254：写值必须走 SettingsStore（会 bump revision），不要只写 DB 键 ——
                    //   门页读的是可观察属性，直写拿不到这次变更，改档后手势不生效。
                    // Round 269：「按住确认」关闭时门页手势被强制成「轻点直开」
                    //   （DoorScreen.effectiveGesture 第一行 if !holdConfirm { return "tap" }）。
                    //   所以这一档必须禁用并给原因，否则界面在说谎。禁用判据取可观察的 SettingsStore。
                    Picker("开锁手势", selection: Binding(
                        get: { gestureMode },
                        set: { gestureMode = $0; SettingsStore.shared.gestureMode = $0 }
                    )) {
                        Text("按住开锁").tag("hold")
                        Text("轻点开锁").tag("tap")
                        Text("双击开锁").tag("double")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(!SettingsStore.shared.holdConfirm)
                    .opacity(SettingsStore.shared.holdConfirm ? 1 : 0.45)
                    if !SettingsStore.shared.holdConfirm {
                        Text("「按住确认开锁」关闭时，手势固定为轻点直开 —— 想用按住或双击，请先打开下面的开关。")
                            .font(V.F.micro)
                            .foregroundStyle(V.C.text3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(minHeight: V.Hit.min)

                VToggleRow(title: "按住确认开锁", detail: "关掉后退回轻点直开，单手更省力但误触也会开门。", isOn: Binding(
                    get: { holdConfirm },
                    set: { on in holdConfirm = on; SettingsStore.shared.holdConfirm = on }   // 同上：必须 bump revision
                ))
            } header: {
                sectionHeader("点得准")
            }

            Section {
                Text("系统「减弱动态效果 / 增加对比度 / 减少透明度」与本页是并联关系：任一开启都生效。这里不重复开关，只如实告诉你当前系统状态。")
                    .font(V.F.body).foregroundStyle(V.C.text9)
                    .fixedSize(horizontal: false, vertical: true)
                AccessibilityStatusRows()
            } header: {
                sectionHeader("动效与对比")
            }

            Section {
                Text("开门成功")
                    .font((bigText ? V.F.axTitleBig : V.F.axTitle))
                    .foregroundStyle(V.C.text1)
                Text("这一行会跟随全局大字档变化。")
                    .font(V.F.body)
                    .foregroundStyle(V.C.text2)
            } header: {
                sectionHeader("样例")
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(V.S.gap16)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, V.S.gap16, for: .scrollContent)
        .contentMargins(.bottom, V.S.gapL, for: .scrollContent)
        .background(CanvasBackground())
        .onAppear { syncFromStore() }   // E-13：从持久层重新同步，避免与外观页/重置动作不一致
        .navigationTitle("无障碍")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// List 段头：系统会给全大写/字距，中文要显式关掉 textCase，否则「看得清」会被拉成大写形态。
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(V.F.small)
            .foregroundStyle(V.C.text3)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: V.S.gapXXS) {
            Text("无障碍与操作辅助")
                .font(V.F.displayA).foregroundStyle(V.C.text1)
            Text("所有档位即时生效、只存本机。")
                .font(V.F.footnote).foregroundStyle(V.C.text3)
        }
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
