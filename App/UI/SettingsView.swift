// 设置 Tab (settings 页) — 门锁管理/安全/家人与钥匙/网关/固件/备份/应用锁/外观/关于
// 分组原则: 同一心智模型的动作放同一 Section, 不再出现"一个 Section 只有一行"的碎片。
// 所有破坏性动作统一走 confirmDestructive (全局助手), 本文件不自带弹窗实现。
import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @State private var showMembers = false
    @State private var showKeychainHW = false
    @State private var showGateway = false
    @State private var showFirmware = false
    @State private var showDeviceInfo = false
    @State private var showBackup = false
    @State private var showMessages = false
    @State private var showAdd = false
    @State private var showOverview = false
    @State private var showManual = false
    // 包14: 27 设置内搜索 — 顶部搜索框过滤全部设置项
    @State private var query = ""
    // 与门锁通信中的忙碌态 — 防止连点重复下发指令
    @State private var settingMute = false
    @State private var clearingPwd = false
    // 包18: 版本彩蛋 (298) / VoiceOver 致意 (1049)
    @State private var eggShown = false
    @State private var versionTaps = 0
    @State private var voLine = ""

    /// 831 NEW 角标: 新功能首见, 进入一次即消 (状态存偏好表 kf_seen_)
    @ViewBuilder
    func newBadgeRow(_ title: String, _ feature: String, @ViewBuilder dest: () -> some View) -> some View {
        NavigationLink {
            if !DB.store.getBool("kf_seen_" + feature) {
                DB.store.set("kf_seen_" + feature, true)
            }
            dest()
        } label: {
            HStack(spacing: DS.Space.xs) {
                Label(title, systemImage: "sparkles")
                if !DB.store.getBool("kf_seen_" + feature) {
                    Text("NEW")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(DS.Palette.onAccent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(DS.Palette.accent, in: Capsule())
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                searchTextRow
                searchResults
                lockSection
                securitySection
                unlockSection
                autoOpenSection
                familySection
                toolsSection
                drillSection
                applockSection
                a11ySection
                appearanceSection
                memorySection
                reminderSection
                helpSection
                aboutSection
            }
            .navigationTitle("设置")
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .sheet(isPresented: $showMembers) { MembersView() }
            .sheet(isPresented: $showKeychainHW) { KeychainHWView() }
            .sheet(isPresented: $showGateway) { GatewayView() }
            .sheet(isPresented: $showFirmware) { FirmwareView() }
            .sheet(isPresented: $showDeviceInfo) { DeviceInfoView() }
            .sheet(isPresented: $showBackup) { BackupView() }
            .sheet(isPresented: $showMessages) { MessagesView() }
            .sheet(isPresented: $showAdd) { AddDeviceView() }
            .sheet(isPresented: $showOverview) { LockOverviewView() }
            .sheet(isPresented: $showManual) {
                NavigationStack { ManualPage() }
                    .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("完成") { showManual = false } } }
            }
        }
    }

    private var mac: String { app.current?.mac ?? "" }

    // ---------- 包14: 27 设置内搜索 + 831 NEW 角标 ----------
    private var searchTextRow: some View {
        Section {
            TextField("搜索设置 (如: 固件 / 备份 / 主题)", text: $query)
                .autocorrectionDisabled()
                .accessibilityLabel("搜索设置项")
        }
    }
    /// 搜索结果: 命中词映射到对应条目, 直达功能
    private struct SearchHit: Identifiable {
        let id: String
        let title: String
        let icon: String
        let go: () -> Void
    }
    private var searchHits: [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let all: [SearchHit] = [
            SearchHit(id: "s.lockprofile", title: "锁档案 (昵称/符号/色标)", icon: "lock") { app.tabSelection = 0 },
            SearchHit(id: "s.mute", title: "静音模式", icon: "speaker.slash") { app.tabSelection = 0 },
            SearchHit(id: "s.synctime", title: "校准门锁时间", icon: "clock.arrow.circlepath") { app.tabSelection = 0 },
            SearchHit(id: "s.maint", title: "维护与保养", icon: "wrench.and.screwdriver") { app.tabSelection = 0 },
            SearchHit(id: "s.safemode", title: "门锁安全模式", icon: "shield.lefthalf.filled") { app.tabSelection = 0 },
            SearchHit(id: "s.unlockopt", title: "开锁偏好 (按住确认/围栏/提示音)", icon: "hand.draw") { app.tabSelection = 0 },
            SearchHit(id: "s.autoopen", title: "靠近自动开锁 (走近自动开门/距离标定)", icon: "person.walk") { app.tabSelection = 3 },
            SearchHit(id: "s.members", title: "成员管理", icon: "person.2") { showMembers = true },
            SearchHit(id: "s.keychainhw", title: "蓝牙钥匙串", icon: "key.horizontal") { showKeychainHW = true },
            SearchHit(id: "s.gateway", title: "智能网关", icon: "antenna.radiowaves.left.and.right") { showGateway = true },
            SearchHit(id: "s.firmware", title: "检查固件更新", icon: "arrow.up.circle") { showFirmware = true },
            SearchHit(id: "s.backup", title: "备份与恢复", icon: "externaldrive") { showBackup = true },
            SearchHit(id: "s.backupstudio", title: "备份工作室 (导出向导/恢复/WebDAV策略/换机迁移)", icon: "wrench.and.scissors") { showBackup = true },
            SearchHit(id: "s.messages", title: "动态消息", icon: "bell") { showMessages = true },
            SearchHit(id: "s.logs", title: "运行日志", icon: "list.bullet.rectangle") { app.tabSelection = 3 },
            SearchHit(id: "s.applock", title: "本机数据保护 (应用锁)", icon: "lock.shield") { app.tabSelection = 3 },
            SearchHit(id: "s.appearance", title: "外观 (主题/品牌色/密度)", icon: "paintbrush") { app.tabSelection = 3 },
            SearchHit(id: "s.achievements", title: "我的成就", icon: "rosette") { app.tabSelection = 3 },
            SearchHit(id: "s.care", title: "关怀提醒与公告板", icon: "heart.text.square") { app.tabSelection = 3 },
            SearchHit(id: "s.maintremind", title: "维护提醒", icon: "bell.badge") { app.tabSelection = 3 },
            SearchHit(id: "s.demo", title: "演练与演示 (演示模式/样例备份/七天样例)", icon: "theatermasks") { app.tabSelection = 3 },
            SearchHit(id: "s.faq", title: "常见问题 (FAQ)", icon: "questionmark") { showManual = true },
            SearchHit(id: "s.manual", title: "使用手册", icon: "book") { showManual = true },
            SearchHit(id: "s.flow", title: "数据流向说明", icon: "arrow.right.circle") { app.tabSelection = 3 },
            SearchHit(id: "s.credits", title: "致谢与许可", icon: "hands.clap") { app.tabSelection = 3 },
            SearchHit(id: "s.copycheck", title: "文案体检 (664)", icon: "text.badge.checkmark") { app.tabSelection = 3 },
        ]
        return all.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.id.hasSuffix(q) }
    }
    @ViewBuilder
    private var searchResults: some View {
        if !searchHits.isEmpty {
            Section("搜索结果 (\(searchHits.count))") {
                ForEach(searchHits) { h in
                    Button { h.go() } label: {
                        Label(h.title, systemImage: h.icon)
                    }
                }
            }
        }
    }

    // ---------- 包14 演练区 (836/837/844/845): 演示模式总开关 + 样例备份 + 演练入口 ----------
    private var drillSection: some View {
        Section {
            Toggle("演示模式 (所有开锁走模拟, 不碰锁端)", isOn: Binding(
                get: { DemoKit.isOn },
                set: { on in
                    DemoKit.setOn(on)
                    app.loadDevices()
                    app.showToast(on ? "演示模式已开 · demo_ 数据已铺底" : "已清除全部演示数据")
                }))
            NavigationLink { DemoLabsView() } label: {
                Label("演练场: 样例备份/七天样例/锁死演练 (837/845/844)", systemImage: "testtube.2")
            }
            if DemoKit.drillBackupOn {
                Button("首备演练完成, 转正式备份 (842)", role: .destructive) {
                    DemoKit.finishDrillBackup()
                    app.showToast("备份已转正式")
                }
            }
        } header: {
            Text("演练与演示")
        } footer: {
            Text("演示数据全部带 demo_ 前缀 + 常驻横幅标识, 一键清除不影响真实台账; 演示模式不触碰 BLE 与协议。")
        }
    }

    // ---------- 包14 帮助区 (835/514/240/300/664/813): 手册/FAQ/数据流向/致谢/文案体检/证书 ----------
    private var helpSection: some View {
        Section {
            Button { showManual = true } label: { Label("使用手册与常见问题", systemImage: "book") }
            NavigationLink { DataFlowPage() } label: { Label("数据从哪来到哪去 (240)", systemImage: "arrow.right.circle") }
            NavigationLink { CreditsPage() } label: { Label("致谢与许可 (300)", systemImage: "hands.clap") }
            NavigationLink { CopyCheckPage() } label: { Label("文案体检 (664 彩蛋)", systemImage: "text.badge.checkmark") }
            if DB.store.getBool("kf_onb_ceremony") {
                NavigationLink { ButlerCertificateView() } label: {
                    Label("我的就任证书 (813)", systemImage: "rosette")
                }
            }
            Button("重看新手引导 (805)") {
                Onboarding.replayAll()
                app.onboardingFinished = false
                app.showToast("下次冷启动重新走引导, 或现在就看")
            }
        } header: {
            Text("帮助与关于")
        } footer: {
            Text("全部本地内容, 无在线客服; 手册章节随引导进度标记未读。")
        }
    }

    // ---------- 门锁 ----------
    private var lockSection: some View {
        Section("门锁") {
            if app.current == nil {
                Button { showAdd = true } label: { Label("添加设备", systemImage: "plus") }
            } else {
                NavigationLink("锁档案 (昵称/符号/色标/备注)") { LockProfileView() }
                // 包2 连接与预握手偏好 (70/97/100): 自动预握手开关 / 成功率积累占位 / 信号围栏记忆
                NavigationLink("连接与预握手 (自动预热/成功率)") { LinkPrefsView(mac: mac) }
                Button("锁信息名片") { showDeviceInfo = true }
                Toggle("静音模式", isOn: Binding(
                    get: { muteStored },
                    set: { silent in
                        guard !settingMute else { return }
                        settingMute = true
                        Task {
                            defer { settingMute = false }
                            do {
                                try await app.lock.ensureConnected(mac: mac)
                                try await app.lock.setSilent(silent)
                                DB.store.set("kf_mute_" + mac, silent)
                                app.showToast(silent ? "已静音" : "已恢复提示音")
                            } catch {
                                // DB 未写 → 开关回弹, 配 toast 说明原因
                                app.showToast("设置失败: \(error.localizedDescription)")
                            }
                        }
                    }))
                    .disabled(settingMute)
                NavigationLink("校准门锁时间") { SyncTimeView() }
                NavigationLink("维护与保养 (周期/换电)") { MaintenanceView() }
                if canDefend {
                    NavigationLink("一键布防") { DefendView() }
                }
                if canTailgate {
                    NavigationLink("防尾随入室") { TailgateView() }
                }
                if canClearPwd {
                    Button("清空密码", role: .destructive) { clearPwd() }
                        .disabled(clearingPwd)
                }
                Button("删除设备", role: .destructive) { deleteDevice() }
            }
        }
    }
    private var muteStored: Bool { DB.store.getBool("kf_mute_" + mac) }
    private var canDefend: Bool { PidMap.canDefend(app.current?.pid ?? 0) }
    private var canTailgate: Bool { PidMap.canTailgate(app.current?.pid ?? 0, fw: app.current?.fw) }
    private var canClearPwd: Bool { PidMap.canClearPwd(app.current?.pid ?? 0) }

    private func clearPwd() {
        guard !clearingPwd else { return }
        confirmDestructive("清空密码",
                          "执行清空密码操作，会作废所有成员的密码，门锁需重新逐个添加。确定要清空吗？",
                          confirmTitle: "清空") {
            Task { await self.doClearPwd() }
        }
    }
    private func doClearPwd() async {
        guard !clearingPwd else { return }
        clearingPwd = true
        defer { clearingPwd = false }
        do {
            try await app.lock.ensureConnected(mac: mac)
            try await app.lock.pwdClear()
            DB.saveLedger(mac, Ledger()) // 清空本地密码台账 (指纹保留)
            app.showToast("清空密码成功")
        } catch { app.showToast("清空失败: \(error.localizedDescription)") }
    }

    private func deleteDevice() {
        confirmDestructive("删除设备",
                          "将删除本机的钥匙串与该门锁全部本地数据 (锁端密钥不变)。删除后若未做过备份将无法找回，确定要删除吗？",
                          confirmTitle: "删除") {
            if let kc = app.current {
                DB.removeDevice(kc.mac)
                app.loadDevices()
                app.showToast("已删除")
            }
        }
    }

    // ---------- 安全 ----------
    private var securitySection: some View {
        Section("安全") {
            NavigationLink("门锁安全模式") { SafemodeIntroView(mode: "safe") }
            // 包7: 安全·隐私·审计中心 (应用锁增强/防窥/审计流水/数据销毁)
            NavigationLink { SecurityCenterView() } label: {
                Label("安全中心 (应用锁/防窥/审计/销毁)", systemImage: "lock.shield")
            }
        }
    }

    // ---------- 开锁 (包1: 按住确认/围栏/提示音/自动重试/圆盘尺寸) ----------
    private var unlockSection: some View {
        Section {
            Toggle("按住确认开锁", isOn: Binding(
                get: { DB.store.getBool("kf_hold_confirm", true) },
                set: { app.setUnlockOption("kf_hold_confirm", $0) }))
            Toggle("误触围栏", isOn: Binding(
                get: { DB.store.getBool("kf_fence") },
                set: { app.setUnlockOption("kf_fence", $0) }))
            Toggle("成功提示音", isOn: Binding(
                get: { DB.store.getBool("kf_unlock_sound") },
                set: { app.setUnlockOption("kf_unlock_sound", $0) }))
            Toggle("失败自动重试", isOn: Binding(
                get: { DB.store.getBool("kf_auto_retry", true) },
                set: { app.setUnlockOption("kf_auto_retry", $0) }))
            Picker("圆盘尺寸", selection: Binding(
                get: { DB.store.getInt("kf_dial_size", 176) },
                set: { app.setUnlockOption("kf_dial_size", $0) })) {
                Text("小 (160)").tag(160)
                Text("标准 (176)").tag(176)
                Text("大 (200)").tag(200)
            }
            .pickerStyle(.menu)
        } header: {
            Text("开锁")
        } footer: {
            Text("按住圆盘时长 (默认 0.9s, 可在 辅助功能 里 0.4–1.6s 自定, 875) 或上滑触发开锁；关闭「按住确认」后退回轻点直开 (适合单手与 VoiceOver)。误触围栏开启后需先从圆盘边缘拖到中心再执行开锁手势。")
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // ---------- 靠近自动开锁 (AUTOOPEN-PLAN §4): 全门绿才自动开门, 默认关, fail-closed ----------
    private var autoOpenSection: some View {
        if !mac.isEmpty {
            AutoOpenSection(mac: mac)
        }
    }

    // ---------- 家人与钥匙 (包13: 成员中心/791/798-792/483/479-794 入口) ----------
    private var familySection: some View {
        VStack(spacing: 0) {
            Section {
                memberFamilyRows
            } header: {
                Text("家人与钥匙")
            } footer: {
                Text("「访客」是本地虚拟分组, 不占锁端槽位; 活跃度与摘录均按台账推断 (约)。")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            credCareSection
        }
    }
    @ViewBuilder
    private var memberFamilyRows: some View {
        Button { showMembers = true } label: { Label("成员管理 (含成员中心)", systemImage: "person.2") }
        NavigationLink { UnclaimedClaimView() } label: { Label("未归属记录认领 (791)", systemImage: "questionmark.circle") }
        NavigationLink { MemberStackedView() } label: { Label("成员活跃结构 (798/792)", systemImage: "chart.bar.fill") }
        NavigationLink { HouseCleaningPresetView() } label: { Label("家政周期预设 (483)", systemImage: "broom.fill") }
        NavigationLink { MemberFamilySettingsView() } label: { Label("家庭设置: 长辈模式/隐私浏览 (479/794)", systemImage: "hand.raised.fill") }
        Button { showKeychainHW = true } label: { Label("蓝牙钥匙串", systemImage: "key.horizontal") }
        Button { showAdd = true } label: { Label("添加另一把锁", systemImage: "plus") }
    }

    // ---------- 包6 凭证整理 (491 版本配额 / 497 回收站保留期 / 919 别名显示) ----------
    private var credCareSection: some View {
        Section("凭证整理") {
            Stepper("历史版本配额 \(CredentialOrg.quota(mac)) 版/凭证 (491)", value: Binding(
                get: { CredentialOrg.quota(mac) },
                set: { DB.store.set("kf_ccred_quota", $0) }), in: 3...30, step: 1)
                .fixedSize(horizontal: false, vertical: true)
            Stepper("回收站保留 \(CredentialOrg.reclaimDays()) 天 (497)", value: Binding(
                get: { CredentialOrg.reclaimDays() },
                set: { DB.store.set("kf_cbin_reclaim_days", $0) }), in: 7...90, step: 7)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("成员别名显示 (919: 关系备注优先, 如「老妈」)", isOn: Binding(
                get: { CredentialOrg.aliasDisplay },
                set: { DB.store.set("kf_calias_display", $0) }))
                .fixedSize(horizontal: false, vertical: true)
        } footer: {
            Text("版本快照与回收站只在本机留存; 需锁端生效的操作保持「待下发」, 到场连接后在凭证页队列补发。")
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // ---------- 工具 (原网关/固件/备份/诊断 四个单行 Section 合并) ----------
    private var toolsSection: some View {
        Section("工具") {
            Button { showOverview = true } label: { Label("全部锁总览与对比", systemImage: "chart.bar.horizontal") }
            Button { showGateway = true } label: { Label("智能网关", systemImage: "antenna.radiowaves.left.and.right") }
            Button { showFirmware = true } label: { Label("检查固件更新", systemImage: "arrow.up.circle") }
            Button { showBackup = true } label: { Label("备份与恢复", systemImage: "externaldrive") }
            // 动态消息只走 sheet: MessagesView 自带 NavigationStack, 用 NavigationLink 会嵌套两层导航栏
            Button { showMessages = true } label: { Label("动态消息", systemImage: "bell") }
            NavigationLink("运行日志") { DiagnosticsView() }
            // 包17: 系统集成 (快捷指令/深链/NFC 登记/Watch 路线图)
            NavigationLink { IntegrationCenterView() } label: {
                Label("系统集成 (快捷指令/入口)", systemImage: "point.3.forward")
            }
        }
    }

    // ---------- 包15 无障碍与操作辅助 (设置-辅助功能入口) ----------
    private var a11ySection: some View {
        Section {
            NavigationLink { AccessibilityView() } label: {
                Label("辅助功能 (VoiceOver/视觉/运动/输入/听觉)", systemImage: "accessibility")
            }
        } header: {
            Text("无障碍")
        } footer: {
            Text("圆盘转子调节、字号五档、切换控制扫描、键盘快捷键、练习场与对比度计算器集中在辅助功能页。")
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // ---------- 本机数据保护 ----------
    private var applockSection: some View {
        Section {
            if DB.hasPasscode() {
                Button("更改本机密码") { setPasscode() }
                Button("关闭本机密码", role: .destructive) { disablePasscode() }
            } else {
                Button("设置本机密码") { setPasscode() }
            }
        } header: {
            Text("本机数据保护")
        } footer: {
            Text("查看密码内容与导出备份前建议设置本机密码。")
        }
    }

    /// 关闭本机密码 = 撤掉查看密码明文与导出备份的唯一屏障, 必须显式二次确认
    private func disablePasscode() {
        confirmDestructive("关闭本机密码",
                          "关闭后，查看密码内容与导出备份不再需要本机验证，任何拿到这台手机的人都能读取明文密码与钥匙串。确定要关闭吗？",
                          confirmTitle: "关闭保护") {
            DB.setPasscode(nil)
            app.appUnlocked = true
            app.showToast("已关闭")
        }
    }

    private func setPasscode() {
        let alert = UIAlertController(title: "设置本机密码", message: "4 位以上数字/字母", preferredStyle: .alert)
        alert.addTextField { $0.isSecureTextEntry = true }
        alert.addTextField { $0.isSecureTextEntry = true; $0.placeholder = "再次输入" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            let f1 = alert.textFields?[0].text ?? ""
            let f2 = alert.textFields?[1].text ?? ""
            guard !f1.isEmpty, f1 == f2 else { app.showToast("两次输入不一致"); return }
            guard f1.count >= 4 else { app.showToast("密码需 4 位以上"); return } // 与提示文案一致
            DB.setPasscode(f1)
            app.showToast("已设置")
        })
        UIApplication.topViewController()?.present(alert, animated: true)
    }

    // ---------- 外观 (包16: 主题四档 / 品牌色 / 密度 / 最近开门条数 / 备选图标 / 重置) ----------
    @State private var currentIcon: String? = UIApplication.shared.alternateIconName

    private var appearanceSection: some View {
        Section {
            // 外观模式 (idea 30): 跟随系统/浅色/深色/纯黑 — 纯黑为 OLED 省电与夜间的极暗档
            Picker("主题", selection: Binding(
                get: { DB.store.getString("kf_theme") },
                set: { app.setTheme($0) })) {
                Text("跟随系统").tag("")
                Text("浅色").tag("light")
                Text("深色").tag("dark")
                Text("纯黑 (AMOLED)").tag("black")
            }
            .pickerStyle(.menu)
            // 品牌色 (idea 31): 三套品牌色换肤, accent/accentText/渐变全 App 即时切换
            Picker("品牌色", selection: Binding(
                get: {
                    let v = DB.store.getString("kf_accent")
                    return v.isEmpty ? "indigo" : v
                },
                set: { app.setAccent($0) })) {
                ForEach(DS.accentThemes) { t in
                    HStack(spacing: DS.Space.s) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(t.preview)
                            .frame(width: 14, height: 14)
                            .accessibilityHidden(true)
                        Text(t.name)
                    }
                    .tag(t.key)
                }
            }
            .pickerStyle(.menu)
            // 布局密度 (包16): 只缩放间距令牌, 字号与触达不动
            Picker("布局密度", selection: Binding(
                get: { DB.store.getString("kf_density") },
                set: { app.setDensity($0) })) {
                Text("标准").tag("")
                Text("紧凑").tag("compact")
                Text("宽松").tag("relaxed")
            }
            .pickerStyle(.menu)
            // 素颜模式 (idea 1046): 一键关闭庆祝与徽章动效
            Toggle("素颜模式", isOn: Binding(
                get: { DB.store.getBool("kf_plain") },
                set: { DB.store.set("kf_plain", $0) }))
            // 最近开门条数 (idea 910): 设备页时间线长度
            Picker("最近开门条数", selection: Binding(
                get: { DB.store.getInt("kf_recent_count", 5) },
                set: { app.setRecentCount($0) })) {
                Text("3 条").tag(3)
                Text("5 条").tag(5)
                Text("10 条").tag(10)
            }
            .pickerStyle(.menu)
            iconPickerRow
            // 恢复默认外观 (idea 202): 带确认弹窗, 只重置外观偏好
            Button("恢复默认外观") { resetAppearance() }
        } header: {
            Text("外观")
        } footer: {
            Text("主题、品牌色、密度即时生效。素颜模式一键关闭庆祝与徽章动效；纯黑模式适合 OLED 屏幕夜间使用。")
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { currentIcon = UIApplication.shared.alternateIconName }
    }

    // ---------- 备选 App 图标 (idea 896) ----------
    // 缩略预览色块与真实 PNG 同底色同符号; 点按走系统 setAlternateIconName (系统自带确认弹窗)。
    private struct IconOption: Identifiable {
        let id: String?      // nil = 默认图标
        let name: String
        let glyph: String
        let bg: [Color]
    }
    private var iconOptions: [IconOption] {
        [
            IconOption(id: nil, name: "默认", glyph: "lock.fill",
                       bg: [Color(hex: 0x5A55EC), Color(hex: 0x4338CA)]),
            IconOption(id: "AppIcon-Ring", name: "锁环", glyph: "record.circle",
                       bg: [Color(hex: 0x178040), Color(hex: 0x0F5A2C)]),
            IconOption(id: "AppIcon-Key", name: "钥匙", glyph: "key.fill",
                       bg: [Color(hex: 0x9A5B10), Color(hex: 0x713F12)]),
            IconOption(id: "AppIcon-Shield", name: "盾牌", glyph: "shield.fill",
                       bg: [Color(hex: 0x334155), Color(hex: 0x1E293B)]),
        ]
    }
    private var iconPickerRow: some View {
        HStack(spacing: DS.Space.s) {
            Text("App 图标")
            Spacer(minLength: DS.Space.s)
            HStack(spacing: DS.Space.m) {
                ForEach(iconOptions) { opt in
                    Button { setIcon(opt.id) } label: {
                        ZStack(alignment: .bottomTrailing) {
                            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                                .fill(LinearGradient(colors: opt.bg, startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 48, height: 48)
                                .overlay(
                                    Image(systemName: opt.glyph)
                                        .font(.system(size: 24, weight: .medium))
                                        .foregroundStyle(.white)
                                )
                            if currentIcon == opt.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white, DS.Palette.ok)
                                    .offset(x: 4, y: 4)
                            }
                        }
                        .accessibilityLabel(currentIcon == opt.id ? "当前图标 \(opt.name)" : "切换为\(opt.name)图标")
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
        }
        .font(.body)
        .foregroundStyle(DS.Palette.text)
    }

    private func setIcon(_ name: String?) {
        guard UIApplication.shared.supportsAlternateIcons else {
            app.showToast("当前系统不支持更换图标")
            return
        }
        UIApplication.shared.setAlternateIconName(name) { error in
            if let error {
                app.showToast("更换失败: \(error.localizedDescription)")
            } else {
                currentIcon = name
            }
        }
    }

    private func resetAppearance() {
        confirmDestructive("恢复默认外观",
                          "将主题、品牌色与布局密度重置为默认值，不影响任何门锁数据。确定恢复吗？",
                          confirmTitle: "恢复默认") {
            app.resetAppearance()
            app.showToast("已恢复默认外观")
        }
    }

    // ---------- 纪念与成就 (包18) ----------
    private var memorySection: some View {
        Section {
            NavigationLink { AchievementsView() } label: { Label("我的成就", systemImage: "rosette") }
            NavigationLink { CareRemindersView() } label: { Label("关怀提醒与公告板", systemImage: "heart.text.square") }
        } header: {
            Text("纪念与成就")
        } footer: {
            Text("徽章、安心夜月历与纪念日提醒全部本地运行, 素颜模式可一键安静。")
        }
    }

    // ---------- 维护提醒 (包4: 287 阈值/1031 免扰/1038 白天送达/146 升级提醒 的入口) ----------
    private var reminderSection: some View {
        Section {
            NavigationLink { MaintSettingsView() } label: { Label("维护提醒", systemImage: "bell.badge") }
        } header: {
            Text("提醒")
        } footer: {
            Text("低电、保养、校时与固件提醒全部通过本地通知送达, 免扰时段可一键安静。")
        }
    }

    // ---------- 关于 ----------
    private var aboutSection: some View {
        Section {
            // 机械计数器 (idea 1006): 累计开锁次数
            HStack {
                Text("累计开锁").foregroundStyle(DS.Palette.text)
                Spacer(minLength: DS.Space.m)
                MechCounter(value: Milestones.unlockTotal)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("累计开锁 \(Milestones.unlockTotal) 次")
            // 版本彩蛋 (idea 298): 连点 10 次展示构建信息
            Button {
                versionTaps += 1
                if versionTaps >= 10, !eggShown {
                    eggShown = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } label: {
                HStack {
                    Text("当前版本").foregroundStyle(DS.Palette.text)
                    Spacer(minLength: DS.Space.m)
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                        .foregroundStyle(DS.Palette.textSub)
                        .monospacedDigit()
                }
            }
            if eggShown {
                LabeledRow("构建", Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")
                LabeledRow("遥测", "无 · 全程离线")
            }
        } footer: {
            Text(aboutFooterText)
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            // VoiceOver 致意 (idea 1049): 累计 30 天后一句静默致谢
            if UIAccessibility.isVoiceOverRunning { Milestones.markVoiceOver() }
            if let days = Milestones.voiceOverDays, days >= 30, !Milestones.onceDone("vo30") {
                Milestones.markOnce("vo30")
                voLine = " VoiceOver 已陪伴这个家 \(days) 天, 谢谢你听见每一扇门。"
            }
        }
    }

    private var aboutFooterText: String {
        var s = "厂商已停服的智能锁离线管理端。门锁数据、密码台账、家人档案全部保存在本机。换新手机用「备份与恢复」转移, 门锁无需重置。"
        if eggShown { s += " Build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?") · 本地构建。" }
        s += voLine
        return s
    }
}

/// 机械计数样式数字 (idea 1006): 每位一格, 等宽数字
struct MechCounter: View {
    let value: Int
    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(String(value).enumerated()), id: \.offset) { _, ch in
                Text(String(ch))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(DS.Palette.text)
                    .frame(width: 22)
                    .background(DS.Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(DS.Palette.hairline, lineWidth: 0.5)
                    )
            }
        }
        .accessibilityHidden(true)
    }
}

// ---------- 布防 (defend 页: 外出/在家/撤防) ----------
struct DefendView: View {
    @EnvironmentObject var app: AppState
    @State private var mode = 1
    @State private var fromTime = Date()
    @State private var toTime = Date()
    @State private var fromDate = Date()
    @State private var toDate = Date()
    @State private var busy = false

    var body: some View {
        Form {
            Picker("模式", selection: $mode) {
                Text("外出布防").tag(1)
                Text("在家布防").tag(2)
                Text("撤防").tag(0)
            }
            .pickerStyle(.segmented)
            if mode == 1 {
                Section("布防时间段") {
                    DatePicker("开始", selection: $fromDate).datePickerStyle(.compact)
                    DatePicker("结束", selection: $toDate).datePickerStyle(.compact)
                }
            } else if mode == 2 {
                Section("在家时段") {
                    DatePicker("开始", selection: $fromTime, displayedComponents: .hourAndMinute)
                    DatePicker("结束", selection: $toTime, displayedComponents: .hourAndMinute)
                }
            } else {
                Section {
                    Label {
                        Text("进行撤防操作之后，门锁将会退出布防模式")
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "info.circle").accessibilityHidden(true)
                    }
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                }
            }
            Section {
                // BusyButton 自带 minHeight 与忙碌态, 避免 Text↔ProgressView 互换导致行高抖动
                BusyButton(title: mode == 0 ? "确认撤防" : "确认布防",
                           systemImage: "shield.lefthalf.filled",
                           isBusy: busy) {
                    Task { await apply() }
                }
            } footer: {
                Text(mode == 1 ? "外出布防模式下，在该时间段内，使用指纹、密码、蓝牙无法开启该门锁" :
                     (mode == 2 ? "在家布防模式下，在该时间段内，使用指纹、密码、蓝牙无法开启该门锁" : "请打开手机蓝牙，靠近门锁进行操作"))
            }
        }
        .navigationTitle("一键布防")
        .scrollContentBackground(.hidden)
        .dsScreenBackground()
    }

    private func apply() async {
        guard let kc = app.current, !busy else { return }
        busy = true
        defer { busy = false }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        do {
            switch mode {
            case 1:
                let s = Int(ZKCmdBuilder.protoSec(f.string(from: fromDate)))
                let e = Int(ZKCmdBuilder.protoSec(f.string(from: toDate)))
                guard e > s else { app.showToast("结束时间必须大于开始时间"); return }
                try await app.lock.ensureConnected(mac: kc.mac)
                try await app.lock.setDefence(control: 1, startSec: s, endSec: e)
                DB.saveDefend(kc.mac, DefendCfg(control: 1, startSec: s, endSec: e, at: Date().timeIntervalSince1970 * 1000))
                app.showToast("布防成功")
            case 2:
                let cal = Calendar.current
                let sHMS = cal.dateComponents([.hour, .minute, .second], from: fromTime)
                let eHMS = cal.dateComponents([.hour, .minute, .second], from: toTime)
                let s = (sHMS.hour! * 3600 + sHMS.minute! * 60 + sHMS.second!) / 2
                let e = (eHMS.hour! * 3600 + eHMS.minute! * 60 + eHMS.second!) / 2
                guard e != s else { app.showToast("结束时间不能等于开始时间"); return }
                try await app.lock.ensureConnected(mac: kc.mac)
                try await app.lock.setDefence(control: 2, startSec: s, endSec: e)
                DB.saveDefend(kc.mac, DefendCfg(control: 2, startSec: s, endSec: e, at: Date().timeIntervalSince1970 * 1000))
                app.showToast("布防成功")
            default:
                try await app.lock.ensureConnected(mac: kc.mac)
                try await app.lock.setDefence(control: 0, startSec: 0, endSec: 0)
                DB.saveDefend(kc.mac, DefendCfg(control: 0, startSec: 0, endSec: 0, at: Date().timeIntervalSince1970 * 1000))
                app.showToast("撤防成功")
            }
        } catch {
            app.showToast("失败: \(error.localizedDescription)")
        }
    }
}

// ---------- 防尾随 (tailgate: cmd24 档位 1-6, 2~6 秒) ----------
struct TailgateView: View {
    @EnvironmentObject var app: AppState
    @State private var seconds = 6
    @State private var busy = false

    var body: some View {
        Form {
            Section {
                Picker("等待时长", selection: $seconds) {
                    ForEach(2...6, id: \.self) { Text("\($0) 秒").tag($0) }
                }
                .pickerStyle(.inline)
            } header: {
                Text("开锁后自动上锁等待时长")
            } footer: {
                Text("门锁默认使用蓝牙钥匙、密码、指纹等电控方式开锁，等待6秒后会自动上锁。您可以根据您的使用习惯设置等待时长，防止坏人利用等待时间尾随入室。")
            }
            Section {
                BusyButton(title: "设置", systemImage: "timer", isBusy: busy) {
                    Task { await run() }
                }
            }
        }
        .navigationTitle("防尾随入室")
        .scrollContentBackground(.hidden)
        .dsScreenBackground()
    }

    private func run() async {
        guard let kc = app.current, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await app.lock.ensureConnected(mac: kc.mac)
            try await app.lock.setAutoLock(seconds - 1) // cmd24 档位 = 秒数-1
            DB.saveTailgate(kc.mac, TailgateCfg(interval: seconds - 1, at: Date().timeIntervalSince1970 * 1000))
            app.showToast("设置成功")
        } catch { app.showToast("设置失败: \(error.localizedDescription)") }
    }
}

// ---------- 安全模式说明 (safemodeintroduce) ----------
struct SafemodeIntroView: View {
    var mode = "safe"
    private var isOtp: Bool { mode == "otp" }

    var body: some View {
        Form {
            if isOtp {
                Section("临时密码 (ZOTP) 介绍") {
                    Text("ZOTP 是临时开锁密码：6 位数字密码，每 30 分钟更换一次，同一窗口内最多 99 个。").font(.footnote)
                    Text("生成前请先校准门锁时间 (0E)，否则手机与锁时间窗不同步会导致密码不匹配。").font(.footnote)
                }
            } else {
                Section("门锁的安全模式介绍") {
                    Text("门锁的安全模式分为A模式和B模式").font(.subheadline)
                    Text("A模式：只需要单一方式（密码／指纹／手机）验证通过就可以开锁").font(.footnote)
                    Text("B模式：需要用两种不同方式（指纹+密码／指纹+手机／手机+密码）组合验证通过才可开锁").font(.footnote)
                }
                Section("怎么设置门锁的安全模式？") {
                    Text("进入到APP的\"设备信息\"页面，待读取到设备信息后即可查看当前门锁的安全模式并进行切换").font(.footnote)
                }
            }
        }
        .navigationTitle(isOtp ? "临时密码介绍" : "安全模式说明")
        .scrollContentBackground(.hidden)
        .dsScreenBackground()
    }
}