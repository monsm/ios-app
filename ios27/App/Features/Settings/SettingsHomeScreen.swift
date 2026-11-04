// SettingsHomeScreen.swift —— 设置（Tab 5）· V8 设计语言（索引页）
//
// 参考图没有设置页样本（三屏全是数据仪表），所以这里**有意偏离**：
// 不套英雄图形，而是"索引卡 + 每组行"——设置的本质是索引，不是读数。
// 偏离补偿：卡内一律用参考图的分类行语法（VNavRow），卡间距/内边距按参考图实测（11.1 / 16.5pt）。
import SwiftUI

struct SettingsHomeScreen: View {
    @Environment(Router.self) private var router

    var body: some View {
        VPage(title: "设置", lead: "所有偏好只存在这台手机上。门锁数据不联网。") {
            EmptyView()
        } content: {
            lockCard
            safetyCard
            lookCard
            dataCard
            toolCard
            dangerCard
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private var lockCard: some View {
        card("门锁", statement: "这台锁") {
            VNavRow(title: "锁实况", detail: "电量 / 信号 / 固件 / 锁钟") { router.request(.dest(.lockStatus)) }
            VDotRule()
            VNavRow(title: "锁设置", detail: "静音 / 防尾随 / 安全模式 / 布防") { router.request(.dest(.lockSettings)) }
            VDotRule()
            VNavRow(title: "锁信息名片", detail: "固件与容量") { router.request(.dest(.deviceInfo)) }
            VDotRule()
            VNavRow(title: "我的锁", detail: "全部锁 / 锁档案 / 版面") { router.request(.dest(.lockPortfolio)) }
        }
    }

    private var safetyCard: some View {
        card("安全", statement: "本机与锁端") {
            VNavRow(title: "安全", detail: "本机密码 / 生物识别 / 只读试验 / 诱饵") { router.request(.dest(.security)) }
            VDotRule()
            VNavRow(title: "靠近自动开锁", detail: "默认关；开启前先标定距离") { router.request(.dest(.autoOpen)) }

        }
    }

    private var lookCard: some View {
        card("外观", statement: "看与读") {
            VNavRow(title: "外观", detail: "主题 / 强调色 / 密度 / 快捷格 / 无障碍") { router.request(.dest(.appearance)) }
        }
    }

    private var dataCard: some View {
        card("数据", statement: "只在本机") {
            VNavRow(title: "备份与恢复", detail: "本机备份 / 恢复 / WebDAV / 多份 / 迁移 / 自检") { router.request(.dest(.backup)) }

        }
    }

    private var toolCard: some View {
        card("工具", statement: "硬件与诊断") {
            VNavRow(title: "硬件", detail: "钥匙串 / 写钥 / God 模式入口") { router.request(.dest(.hardware)) }
            VDotRule()
            VNavRow(title: "诊断", detail: "协议测试 / God 模式（开发者项都在这一页）") { router.request(.dest(.protocolTest)) }
            VDotRule()
            VNavRow(title: "关于", detail: "版本 / 累计开锁 / 声明") { router.request(.dest(.about)) }
        }
    }

    private var dangerCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "不可逆", statement: "删除本机数据")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("会清空本机台账、成员与凭证记录；门锁里的凭证不受影响，仍能用原密码开门。没有云端副本可恢复。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapFootnote)
                .fixedSize(horizontal: false, vertical: true)
            VNavRow(title: "删除本机数据", detail: "需要二次确认") { router.request(.dest(.security)) }
                .padding(.top, V8.S.gapS)
        }
    }

    private func card<Content: View>(_ eyebrow: String, statement: String, @ViewBuilder content: () -> Content) -> some View {
        VCard2 {
            VCardHead(eyebrow: eyebrow, statement: statement)
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                content()
            }
            .padding(.top, V8.S.gapS)
        }
    }
}