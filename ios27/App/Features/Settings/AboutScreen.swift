// AboutScreen.swift —— 关于：这台 App 是谁、装了多少次开门、版本号在哪。
//
// 这屏干什么：累计开锁机械计数器 / 构建与主题 / 版本号；版本号连点 10 次才展开构建号与
// 「遥测：无 · 全程离线」的声明 —— 这个彩蛋是有意藏起来的，因为它说的是"厂商已停服"这件事。
// 数据从哪来：SettingsStore.shared（累计开锁）+ Bundle（版本 / 构建号）。
// 主动作：本屏没有主动作按钮 —— 它是一屏读数。唯一的交互是版本行的连点彩蛋。
import SwiftUI

struct AboutScreen: View {
    private var store: SettingsStore { SettingsStore.shared }

    @State private var versionTaps = 0
    @State private var eggShown = false

    var body: some View {
        ScrollView {
            VStack(spacing: T.S.l) {
                SettingsHeader(title: "关于", tone: .neutral, status: status)
                counterPanel
                buildPanel
                versionPanel
                declarationPanel
            }
            .padding(.vertical, T.S.l)
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
        VStack(spacing: T.S.s) {
            SectionLabel(text: "累计开锁", trailing: "本机")
            Panel {
                VStack(alignment: .leading, spacing: T.S.m) {
                    HStack(spacing: T.S.xs) {
                        ForEach(Array(String(store.unlockTotal).enumerated()), id: \.offset) { _, ch in
                            Text(String(ch))
                                .font(T.F.reading(22))
                                .foregroundStyle(Ink.ink)
                                .monospacedDigit()
                                .frame(width: T.Icon.xl + T.S.xs, height: T.Icon.xl + T.S.m)
                                .background(Ink.plateAlt, in: .rect(cornerRadius: T.R.control))
                        }
                        Spacer(minLength: T.S.s)
                        Text("次")
                            .font(T.F.unit)
                            .foregroundStyle(Ink.inkFaint)
                            .tracking(0.6)
                    }
                    SettingRule()
                    SettingsNote(text: "每位一格，换位不跳宽。这个数只统计本机成功开锁回执 —— 失败与被否决的尝试不计数。")
                }
            }
            .padding(.horizontal, T.S.gutter)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("累计开锁 \(store.unlockTotal) 次")
        }
    }

    // MARK: 构建
    private var buildPanel: some View {
        VStack(spacing: T.S.s) {
            SectionLabel(text: "构建")
            Panel {
                VStack(spacing: 0) {
                    FieldRow(label: "构建号", value: SettingsFacts.build)
                    SettingRule()
                    // TODO(engine) 主题套数应由外观令牌表给出（现在只有浅色 / 深色两套取值）。
                    FieldRow(label: "主题套数", value: "2", unit: "套")
                    SettingRule()
                    FieldRow(label: "遥测", value: "无", tint: Ink.inkSub, mono: false)
                }
            }
            .padding(.horizontal, T.S.gutter)
        }
    }

    // MARK: 版本行（连点 10 次才展开彩蛋）
    private var versionPanel: some View {
        VStack(spacing: T.S.s) {
            SectionLabel(text: "版本")
            Panel {
                VStack(alignment: .leading, spacing: T.S.m) {
                    Button {
                        versionTaps += 1
                        if versionTaps >= 10, !eggShown { eggShown = true }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: T.S.s) {
                            Text("当前版本")
                                .font(T.F.body)
                                .foregroundStyle(Ink.inkSub)
                            Spacer(minLength: T.S.s)
                            Reading(value: SettingsFacts.version, size: 15, tint: Ink.ink, animated: false)
                        }
                        .frame(minHeight: T.Hit.min)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("当前版本 \(SettingsFacts.version)")
                    .accessibilityHint("连点 10 次展开构建信息")

                    if eggShown {
                        SettingRule()
                        StatusLine(tone: .ok, text: "已展开：构建信息与离线声明")
                        SettingRule()
                        FieldRow(label: "构建", value: "release · \(SettingsFacts.build)")
                        SettingRule()
                        FieldRow(label: "遥测", value: "无 · 全程离线", tint: Ink.ink, mono: false)
                        SettingRule()
                        SettingsNote(text: "这不是一句宣传：App 里没有任何上报地址、没有账号、没有云同步。锁的协议帧只走蓝牙，数据只落这台手机。")
                            .transition(.opacity)
                    } else {
                        SettingsNote(text: "版本号连点 10 次会展开构建信息与一条离线声明。")
                    }
                }
            }
            .padding(.horizontal, T.S.gutter)
            .animation(T.M.move, value: eggShown)
        }
    }

    // MARK: 离线声明
    private var declarationPanel: some View {
        VStack(spacing: T.S.s) {
            SectionLabel(text: "说明")
            Panel {
                VStack(alignment: .leading, spacing: T.S.m) {
                    SettingsNote(text: "厂商已停服的智能锁离线管理端。门锁数据、密码台账、家人档案全部保存在这台手机上，换新手机用「备份与恢复」转移 —— 门锁本身不需要重置。")
                    SettingRule()
                    SettingsNote(text: "协议层与密码学沿用已验证实现；界面是本版重写的。App 不联网、不注册账号、不做任何上传。")
                }
            }
            .padding(.horizontal, T.S.gutter)
        }
    }
}
