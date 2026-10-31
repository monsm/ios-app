// AboutScreen.swift —— 关于：这台 App 是谁、装了多少次开门、版本号在哪。
//
// 这屏干什么：累计开锁机械计数器 / 构建与主题 / 版本号；版本号连点 10 次才展开构建号与
// 「遥测：无 · 全程离线」的声明 —— 这个彩蛋是有意藏起来的，因为它说的是"厂商已停服"这件事。
// 数据从哪来：SettingsStore.shared（累计开锁）+ Bundle（版本 / 构建号）。
// 主动作：本屏没有主动作按钮 —— 它是一屏读数。唯一的交互是版本行的连点彩蛋。
import SwiftUI

struct AboutScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var store: SettingsStore { SettingsStore.shared }

    @State private var versionTaps = 0
    @State private var eggShown = false

    var body: some View {
        ScrollView {
            VStack(spacing: V.S.gap16) {
                SettingsHeader(title: "关于", tone: .neutral, status: status)
                counterPanel
                buildPanel
                versionPanel
                declarationPanel
            }
            .padding(.vertical, V.S.gap16)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: eggShown) { _, new in new }
    }

    private var status: String {
        eggShown ? "离线锁管家 \(SettingsFacts.version) · 构建 \(SettingsFacts.build)" : "离线锁管家 · 全程离线，数据只在这台手机"
    }

    // MARK: 主角：累计开锁机械计数器（每位一格，等宽）
    private var counterPanel: some View {
        VStack(spacing: V.S.gapS) {
            VSectionLabel(text: "累计开锁", trailing: "本机")
            VCard {
                VStack(alignment: .leading, spacing: V.S.gapMS) {
                    HStack(spacing: V.S.gapXS) {
                        ForEach(Array(String(store.unlockTotal).enumerated()), id: \.offset) { _, ch in
                            Text(String(ch))
                                .font(V.F.number22)
                                .foregroundStyle(V.C.text1)
                                .monospacedDigit()
                                .frame(width: V.Icon.xl + V.S.gapXS, height: V.Icon.xl + V.S.gapMS)
                                .background(V.C.cardAlt, in: .rect(cornerRadius: V.R.control))
                        }
                        Spacer(minLength: V.S.gapS)
                        Text("次")
                            .font(V.F.unit)
                            .foregroundStyle(V.C.text3)
                            .tracking(0.6)
                    }
                    SettingRule()
                    SettingsNote(text: "每位一格，换位不跳宽。这个数只统计本机成功开锁回执 —— 失败与被否决的尝试不计数。")
                }
            }
            .padding(.horizontal, V.S.pageGutter)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("累计开锁 \(store.unlockTotal) 次")
        }
    }

    // MARK: 构建
    private var buildPanel: some View {
        VStack(spacing: V.S.gapS) {
            VSectionLabel(text: "构建")
            VCard {
                VStack(spacing: 0) {
                    VFieldRow(label: "构建号", value: SettingsFacts.build)
                    SettingRule()
                    // TODO(engine) 主题套数应由外观令牌表给出（现在只有浅色 / 深色两套取值）。
                    VFieldRow(label: "主题套数", value: "2", unit: "套")
                    SettingRule()
                    VFieldRow(label: "遥测", value: "无", tint: V.C.text2, mono: false)
                }
            }
            .padding(.horizontal, V.S.pageGutter)
        }
    }

    // MARK: 版本行（连点 10 次才展开彩蛋）
    private var versionPanel: some View {
        VStack(spacing: V.S.gapS) {
            VSectionLabel(text: "版本")
            VCard {
                VStack(alignment: .leading, spacing: V.S.gapMS) {
                    Button {
                        versionTaps += 1
                        if versionTaps >= 10, !eggShown { eggShown = true }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: V.S.gapS) {
                            Text("当前版本")
                                .font(V.F.body)
                                .foregroundStyle(V.C.text2)
                            Spacer(minLength: V.S.gapS)
                            VReading(value: SettingsFacts.version, font: V.F.number15, tint: V.C.text1, animated: false)
                        }
                        .frame(minHeight: V.Hit.min)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("当前版本 \(SettingsFacts.version)")
                    .accessibilityHint("连点 10 次展开构建信息")

                    if eggShown {
                        SettingRule()
                        VStatusLine(tone: .ok, text: "已展开：构建信息与离线声明")
                        SettingRule()
                        VFieldRow(label: "构建", value: "release · \(SettingsFacts.build)")
                        SettingRule()
                        VFieldRow(label: "遥测", value: "无 · 全程离线", tint: V.C.text1, mono: false)
                        SettingRule()
                        SettingsNote(text: "这不是一句宣传：App 里没有任何上报地址、没有账号、没有云同步。锁的协议帧只走蓝牙，数据只落这台手机。")
                            .transition(.opacity)
                    } else {
                        SettingsNote(text: "版本号连点 10 次会展开构建信息与一条离线声明。")
                    }
                }
            }
            .padding(.horizontal, V.S.pageGutter)
            .animation(reduceMotion ? nil : V.M.move, value: eggShown)
        }
    }

    // MARK: 离线声明
    private var declarationPanel: some View {
        VStack(spacing: V.S.gapS) {
            VSectionLabel(text: "说明")
            VCard {
                VStack(alignment: .leading, spacing: V.S.gapMS) {
                    SettingsNote(text: "厂商已停服的智能锁离线管理端。门锁数据、密码台账、家人档案全部保存在这台手机上，换新手机用「备份与恢复」转移 —— 门锁本身不需要重置。")
                    SettingRule()
                    SettingsNote(text: "协议层与密码学沿用已验证实现；界面是本版重写的。App 不联网、不注册账号、不做任何上传。")
                }
            }
            .padding(.horizontal, V.S.pageGutter)
        }
    }
}
