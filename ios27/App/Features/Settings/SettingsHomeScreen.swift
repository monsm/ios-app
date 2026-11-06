// SettingsHomeScreen.swift —— 设置（Tab 5）· V8 设计语言（索引页）
//
// 参考图没有设置页样本（三屏全是数据仪表），所以这里**有意偏离**：
// 不套英雄图形，而是"索引卡 + 每组行"——设置的本质是索引，不是读数。
// 偏离补偿：卡内一律用参考图的分类行语法（VNavRow），卡间距/内边距按参考图实测（11.1 / 16.5pt）。
import SwiftUI

struct SettingsHomeScreen: View {
    @Environment(Router.self) private var router
    // 2026-11-05（对抗审查）：删除锁本机数据的 V8 sheet 入口。旧 V7 页有此能力，迁 V8 时整张 sheet 丢失。
    @State private var showDeleteLock = false

    var body: some View {
        // 2026-11-05（Round 3）：标题已交给系统 navigationTitle（「设置」），
        // 这句话改成 status 行，不再与导航标题重复。
        VPage(title: "只在这台手机上", lead: "门锁数据不联网；外观与无障碍设置只影响本机。") {
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
        // 2026-11-05（对抗审查）：旧 V7 的 DeleteDeviceSheet 随 SettingsScreen 一起被删，
        // 删除一台锁的本机数据（含 20+ 数据族清理）在 V8 里整段丢失。这里接回。
        .sheet(isPresented: $showDeleteLock) { LockDataDeleteSheet().v8Sheet() }
    }

    private var lockCard: some View {
        card("门锁", statement: "这台锁") {
            VNavRow(title: "锁实况", detail: "电量 / 信号 / 固件 / 锁钟", systemImage: "gauge.with.dots.needle.33percent") { router.request(.dest(.lockStatus)) }
            VDotRule()
            VNavRow(title: "锁设置", detail: "静音 / 防尾随 / 安全模式 / 布防", systemImage: "slider.horizontal.3") { router.request(.dest(.lockSettings)) }
            VDotRule()
            VNavRow(title: "锁信息名片", detail: "固件与容量", systemImage: "info.circle") { router.request(.dest(.deviceInfo)) }
            VDotRule()
            VNavRow(title: "我的锁", detail: "全部锁 / 锁档案 / 版面", systemImage: "square.stack.3d.up") { router.request(.dest(.lockPortfolio)) }
        }
    }

    private var safetyCard: some View {
        card("安全", statement: "本机与锁端") {
            // 2026-11-05（看真机截图发现的冗余）：卡眉已经是「安全」，下面第一行又叫「安全」——
            // 一张索引卡里同一词上下两次。行标题改成说这一页里到底有什么。
            VNavRow(title: "本机密码与生物识别", detail: "解锁 / 只读试验 / 诱饵都在这一页", systemImage: "lock.shield", iconTint: V8.C.ok) { router.request(.dest(.security)) }
            VDotRule()
            VNavRow(title: "靠近自动开锁", detail: "默认关；开启前先标定距离", systemImage: "figure.walk", iconTint: V8.C.ok) { router.request(.dest(.autoOpen)) }
        }
    }

    private var lookCard: some View {
        card("外观", statement: "看与读") {
            // 同上：这张卡只有一行，行标题再叫「外观」就等于把卡眉抄了一遍。
            VNavRow(title: "主题、图标与阅读", detail: "强调色 / 密度 / 快捷格 / 无障碍", systemImage: "paintbrush.pointed", iconTint: V8.D.fingerprint) { router.request(.dest(.appearance)) }
        }
    }

    private var dataCard: some View {
        card("数据", statement: "只在本机") {
            VNavRow(title: "备份与恢复", detail: "本机备份 / 恢复 / WebDAV / 多份 / 迁移 / 自检", systemImage: "externaldrive", iconTint: V8.C.info) { router.request(.dest(.backup)) }

        }
    }

    private var toolCard: some View {
        card("工具", statement: "硬件与诊断") {
            VNavRow(title: "硬件", detail: "钥匙串 / 写钥 / God 模式入口", systemImage: "key.horizontal", iconTint: V8.C.ink3) { router.request(.dest(.hardware)) }
            VDotRule()
            VNavRow(title: "诊断", detail: "协议测试 / God 模式（开发者项都在这一页）", systemImage: "waveform.path.ecg", iconTint: V8.C.ink3) { router.request(.dest(.protocolTest)) }
            VDotRule()
            VNavRow(title: "关于", detail: "版本 / 累计开锁 / 声明", systemImage: "info.circle", iconTint: V8.C.ink3) { router.request(.dest(.about)) }
        }
    }

    private var dangerCard: some View {
        VCard2(style: .well) {
            // 2026-11-05：卡头写「删除本机数据」，下面那行写「删除这台锁的本机数据」——
            // 同一件事两遍。卡头改成限定范围，动作只留在按钮那一行。
            VCardHead(eyebrow: "不可逆", statement: "只删当前这把锁")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("只删当前这把锁在本机的数据：密码台账、记录缓存、回收站、版本快照、手机钥匙、锁档案与各类采样。成员与其它锁的数据不受影响；锁端密钥与锁内日志也不变，锁不需要重置，可以再次添加。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapFootnote)
                .fixedSize(horizontal: false, vertical: true)
            VNavRow(title: "删除这台锁的本机数据", detail: "需要键入锁名确认", systemImage: "trash", iconTint: V8.C.danger) { showDeleteLock = true }
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