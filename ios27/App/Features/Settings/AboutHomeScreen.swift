// AboutHomeScreen.swift —— 关于（V8 设计语言）
//
// 与 AboutScreen 的能力对齐：累计开锁机械计数器 / 构建 / 版本（连点 10 次彩蛋）/ 离线声明。
// 结构：VPage + 四张卡；没有英雄图形（这是一屏读数，不是一个"指标"）。
import SwiftUI

struct AboutHomeScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var store: SettingsStore { SettingsStore.shared }

    @State private var versionTaps = 0
    @State private var eggShown = false

    private var status: String {
        eggShown
            ? "离线锁管家 \(SettingsFacts.version) · 构建 \(SettingsFacts.build)"
            : "离线锁管家 · 全程离线，数据只在这台手机"
    }

    var body: some View {
        VPage(title: "关于", lead: status) {
            EmptyView()
        } content: {
            counterCard
            buildCard
            versionCard
            declarationCard
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: eggShown) { _, new in new }
    }

    private var counterCard: some View {
        VCard2 {
            // 2026-11-05（原图裁切确认 · 设计冗余）：卡头 statement 写「0 次」，
            // 下面那排机械数字格又显示「0」+「次」—— 同一个数在一张卡里出现两次。
            // 卡头改成说这个数的**口径**（脚注讲的是「只算成功回执」，两者互补不重复）：
            VCardHead(eyebrow: "累计开锁", statement: "自本机安装以来", trailing: "本机")
            VDivider2()
                .padding(.top, V8.S.gapM)
            HStack(spacing: V8.S.gapXS) {
                ForEach(Array(String(store.unlockTotal).enumerated()), id: \.offset) { _, ch in
                    Text(String(ch))
                        .font(V8.T.headline)
                        .foregroundStyle(V8.C.ink1)
                        .monospacedDigit()
                        .frame(width: V8.S.gapXXL, height: V8.S.gapXXL)
                        .background(V8.C.well, in: .rect(cornerRadius: V8.R.inset))
                }
                Spacer(minLength: 0)
                Text("次")
                    .font(V8.T.micro)
                    .foregroundStyle(V8.C.ink4)
            }
            .padding(.top, V8.S.gapM)
            Text("每位一格，换位不跳宽。这个数只统计本机成功开锁回执 —— 失败与被否决的尝试不计数。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("累计开锁 \(store.unlockTotal) 次")
    }

    private var buildCard: some View {
        VCard2 {
            // 2026-11-05（对抗审查 · 设计冗余）：卡头 statement 已经是构建号，下面第一行
            // 又列了一次「构建号 = 同一个值」。构建号由卡头唯一承载。
            VCardHead(eyebrow: "构建", statement: SettingsFacts.build)
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                VDataRow(tag: "主题套数", tagTint: V8.C.ink4, title: "2", value: "", unit: "套")
                VDotRule()
                VDataRow(tag: "遥测", tagTint: V8.C.ink4, title: "无", value: "")
            }
            .padding(.top, V8.S.gapS)
        }
    }

    private var versionCard: some View {
        VCard2 {
            // 2026-11-05（对抗审查 · 设计冗余）：卡头写「当前 1.0.0」，下面那行又是
            // 「当前版本 1.0.0」—— 同一串值两遍。卡头只说这张卡是什么，版本由那行唯一显示。
            VCardHead(eyebrow: "版本", statement: "本机安装的这一份")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Button {
                versionTaps += 1
                if versionTaps >= 10, !eggShown { eggShown = true }
            } label: {
                HStack(spacing: V8.S.gapS) {
                    Text("当前版本")
                        .font(V8.T.body)
                        .foregroundStyle(V8.C.ink3)
                    Spacer(minLength: 0)
                    Text(SettingsFacts.version)
                        .font(V8.T.value)
                        .foregroundStyle(V8.C.ink1)
                        .monospacedDigit()
                }
                .frame(minHeight: V8.H.min)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("当前版本 \(SettingsFacts.version)")
            .accessibilityHint("连点 10 次展开构建信息")

            if eggShown {
                VDivider2()
                    .padding(.vertical, V8.S.gapS)
                VDataRow(tag: "构建", tagTint: V8.C.ok, title: "release · \(SettingsFacts.build)", value: "")
                VDotRule()
                VDataRow(tag: "遥测", tagTint: V8.C.ok, title: "无 · 全程离线", value: "")
                Text("这不是一句宣传：App 里没有任何上报地址、没有账号、没有云同步。锁的协议帧只走蓝牙，数据只落这台手机。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("版本号连点 10 次会展开构建信息与一条离线声明。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(reduceMotion ? nil : V8.M.move, value: eggShown)
    }

    private var declarationCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "说明", statement: "边界说清楚")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("厂商已停服的智能锁离线管理端。门锁数据、密码台账、家人档案全部保存在这台手机上，换新手机用「备份与恢复」转移 —— 门锁本身不需要重置。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .fixedSize(horizontal: false, vertical: true)
            Text("协议层与密码学沿用已验证实现；界面是本版重写的。App 不连厂商服务器、不注册账号、不自动上传任何数据 —— 只有你自己在「备份工作室」里配置的 WebDAV 会联网，而且每次上传都由你手动触发。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
