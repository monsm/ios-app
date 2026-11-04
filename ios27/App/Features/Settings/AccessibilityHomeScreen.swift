// AccessibilityHomeScreen.swift —— 无障碍与操作辅助（V8 设计语言）
//
// 与 AccessibilityScreen 的能力对齐：看得清（全局大字 / 放大临时码 / 大格模式）、
// 点得准（圆盘尺寸三档）、动效与对比（系统态只读 3 行）、样例。
import SwiftUI

struct AccessibilityHomeScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var bigText = SettingsStore.shared.axBigText
    @State private var bigOTP = DB.store.getBool("kf_ax_bigotp")
    @State private var bigTile = DB.store.getBool("kf_bigtile")
    @State private var dialSize = DB.store.getString("kf_dial_size", "standard")

    private var store: SettingsStore { SettingsStore.shared }

    var body: some View {
        VPage(title: "无障碍", lead: "这些开关只改本机的显示与操作手感，不写门锁。") {
            EmptyView()
        } content: {
            textCard
            touchCard
            motionCard
            sampleCard
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { sync() }
    }

    private func sync() {
        bigText = store.axBigText
        bigOTP = DB.store.getBool("kf_ax_bigotp")
        bigTile = DB.store.getBool("kf_bigtile")
        dialSize = DB.store.getString("kf_dial_size", "standard")
    }

    private var textCard: some View {
        VCard2 {
            VCardHead(eyebrow: "看得清", statement: "三档显示")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                rowToggle(title: "全局大字", detail: "动态字重放大到辅助功能档（Accessibility 2），所有页面跟着放大。", isOn: $bigText) {
                    store.axBigText = bigText
                }
                VDotRule()
                rowToggle(title: "放大临时码", detail: "生成动态码时用大字号显示六位码，并允许双击切换。", isOn: $bigOTP) {
                    DB.store.set("kf_ax_bigotp", bigOTP)
                }
                VDotRule()
                rowToggle(title: "大格模式", detail: "首页快捷操作与凭证行加高，减少误触。", isOn: $bigTile) {
                    DB.store.set("kf_bigtile", bigTile)
                }
            }
            .padding(.top, V8.S.gapS)
        }
    }

    private func rowToggle(title: String, detail: String, isOn: Binding<Bool>, onChange: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: V8.S.gapXS) {
            Toggle(isOn: isOn) {
                Text(title)
                    .font(V8.T.value)
                    .foregroundStyle(V8.C.ink1)
            }
            .onChange(of: isOn.wrappedValue) { _, _ in onChange() }
            Text(detail)
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: V8.H.min)
        .padding(.vertical, V8.S.gapXS)
    }

    private var touchCard: some View {
        VCard2 {
            VCardHead(eyebrow: "点得准", statement: "圆盘尺寸")
            VDivider2()
                .padding(.top, V8.S.gapM)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: V8.S.gapChip) {
                    dialChip("小", key: "small")
                    dialChip("标准", key: "standard")
                    dialChip("大", key: "large")
                }
            }
            .padding(.top, V8.S.gapM)
        }
    }

    private func dialChip(_ title: String, key: String) -> some View {
        let selected = dialSize == key
        return Button {
            dialSize = key
            DB.store.set("kf_dial_size", key)
        } label: {
            Text(title)
                .font(V8.T.tab)
                .foregroundStyle(selected ? V8.C.chipOn : V8.C.ink1)
                .padding(.horizontal, V8.S.gapM)
                .frame(minHeight: V8.H.min)
                .background(Capsule(style: .continuous).fill(selected ? V8.C.accent : V8.C.chipOff))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("圆盘尺寸 " + title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var motionCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "动效与对比", statement: "跟随系统")
            Text("系统「减弱动态效果 / 增加对比度 / 减少透明度」与本页是并联关系：任一开启都生效。这里不重复开关，只如实告诉你当前系统状态。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                VDataRow(tag: "减弱动态效果", tagTint: V8.C.ink4, title: reduceMotion ? "系统已开" : "系统未开", value: "")
                VDotRule()
                VDataRow(tag: "减少透明度", tagTint: V8.C.ink4, title: reduceTransparency ? "系统已开" : "系统未开", value: "")
                VDotRule()
                VDataRow(tag: "增加对比度", tagTint: V8.C.ink4, title: contrast == .increased ? "系统已开" : "系统未开", value: "")
            }
            .padding(.top, V8.S.gapS)
        }
    }

    private var sampleCard: some View {
        VCard2 {
            VCardHead(eyebrow: "样例", statement: "会跟着变")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("开门成功")
                .font(bigText ? V8.T.title2 : V8.T.headline)
                .foregroundStyle(V8.C.ink1)
                .padding(.top, V8.S.gapM)
            Text("这一行会跟随全局大字档变化。")
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapS)
        }
    }
}
