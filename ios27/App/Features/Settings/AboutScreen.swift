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
        // 全换系统（2026-11-02）：整页容器是系统 List，四段各成一个 Section(header:)。
        // 卡片式内容用 plainRow() 保持原样；行式内容（主题套数 / 构建 / 遥测）走 VFieldRow。
        List {
            SettingsHeader(title: "关于", tone: .neutral, status: status).plainRow()
            counterSection
            buildSection
            versionSection
            declarationSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, V.S.gap16, for: .scrollContent)
        .contentMargins(.bottom, V.S.gap16, for: .scrollContent)
        .background(CanvasBackground())
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: eggShown) { _, new in new }
    }

    private var status: String {
        eggShown ? "离线锁管家 \(SettingsFacts.version) · 构建 \(SettingsFacts.build)" : "离线锁管家 · 全程离线，数据只在这台手机"
    }

    // MARK: 主角：累计开锁机械计数器（每位一格，等宽）
    private var counterSection: some View {
        Section {
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
            .accessibilityElement(children: .combine)
            .accessibilityLabel("累计开锁 \(store.unlockTotal) 次")
        } header: {
            Text("累计开锁 · 本机")
        }
    }

    // MARK: 外观事实（构建号与遥测只在版本彩蛋里出现一次，这里不再重复一遍）
    private var buildSection: some View {
        Section {
            // 主题套数是真值：AppearanceTheme 新增一档，这里自动跟着变。
            VFieldRow(label: "主题套数", value: "\(AppearanceTheme.allCases.count)", unit: "套")
        } header: {
            Text("外观")
        }
    }

    // MARK: 版本行（连点 10 次才展开彩蛋）
    private var versionSection: some View {
        Section {
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
            .animation(reduceMotion ? nil : V.M.move, value: eggShown)
        } header: {
            Text("版本")
        }
    }

    // MARK: 离线声明
    private var declarationSection: some View {
        Section {
            VCard {
                VStack(alignment: .leading, spacing: V.S.gapMS) {
                    SettingsNote(text: "厂商已停服的智能锁离线管理端。门锁数据、密码台账、家人档案全部保存在这台手机上，换新手机用「备份与恢复」转移 —— 门锁本身不需要重置。")
                    SettingRule()
                    // 2026-11-02（R7 收尾）：原句「App 不联网、不做任何上传」与实现不符 ——
                    // 备份工作室有用户自配的 WebDAV 上传出口。如实说清「不注册、默认不联网、唯一出口是你自配的」。
                    SettingsNote(text: "协议层与密码学沿用已验证实现；界面是本版重写的。不注册账号、默认不连任何服务器；唯一可能离开本机的是你自己在「备份工作室」里配置的 WebDAV。")
                }
            }
        } header: {
            Text("说明")
        }
    }
}
