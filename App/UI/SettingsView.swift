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
    @State private var showManage = false
    @State private var showManual = false
    @State private var showDiag = false   // 587: 记录详情低电告警带 mac 过来 → 切锁并推诊断页
    @State private var showCare = false   // 1013: 保养到期通知带 mac 过来 → 切锁并推维护页 (与 587 同构)
    // 2026-10-15 走查: 两枚"目标页自带 NavigationStack"的入口改用 sheet 呈现 (见 memberFamilyRows 注释)
    @State private var showUnclaimed = false
    @State private var showFamilySettings = false
    // 2026-10-15 走查: 这两个目标页也自带 NavigationStack, 同样只能走 sheet
    @State private var showSecurity = false
    @State private var showHouseCleaning = false
    // 包14: 27 设置内搜索 — 顶部搜索框过滤全部设置项
    @State private var query = ""
    // 乱源治理第 4 批: 五组筛选的当前组。nil = 全部 (默认态与分组之前完全一样)。
    // 刻意是视图内 @State 而不是落盘键: 记住"上次只看外观与辅助"会让下次进来少看见一堆设置，
    // 那是把筛选变成隐藏 —— 页内搜索 (§27) 同样是会话态，两处口径一致。
    @State private var groupFilter: SettingsGroup?
    // 与门锁通信中的忙碌态 — 防止连点重复下发指令
    @State private var settingMute = false
    @State private var clearingPwd = false
    // 包18: 版本彩蛋 (298) / VoiceOver 致意 (1049)
    @State private var eggShown = false
    @State private var versionTaps = 0
    @State private var voLine = ""

    /// 831 NEW 角标: 新功能首见, 进入一次即消 (状态存偏好表 kf_seen_)
    /// "已看过"的落库放在 destination 的 .onAppear: 写在 ViewBuilder 里等于在构造视图时改数据,
    /// 视图被重建/预取时会反复触发, 而且 body 有副作用本来就是 SwiftUI 明确要避免的。
    @ViewBuilder
    func newBadgeRow(_ title: String, _ feature: String, @ViewBuilder dest: () -> some View) -> some View {
        NavigationLink {
            dest()
                .onAppear { DB.store.set("kf_seen_" + feature, true) }
        } label: {
            HStack(spacing: DS.Space.xs) {
                Label(title, systemImage: "sparkles")
                if !DB.store.getBool("kf_seen_" + feature) {
                    Text("NEW")
                        .vkFont(.caption2, weight: .medium)
                        .foregroundStyle(DS.Palette.onAccent)
                        .padding(.horizontal, DS.Space.xs)
                        .padding(.vertical, DS.Space.xxs)
                        .variantPlate(DS.Palette.accent, .capsule)
                        .accessibilityLabel("新功能")
                }
            }
        }
        // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 命中高仅约 16.6pt (< 44)。
        // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
        .frame(minHeight: DS.Hit.min)
        .contentShape(Rectangle())
    }

    var body: some View { vkBody.destined(.settings) }
    var vkBody: some View {
        NavigationStack {
            settingsReader
        }
    }

    /// 2026-10-15 走查: 设置页内搜索命中后要能**滚到那一节**。只切筛选片是不够的 ——
    /// 命中节常常排在所属分组的第二、第三节 (如「外观」在 .look 组里排第三), 用户还得自己翻。
    /// 滚动的唯一口子是 ScrollViewReader, 所以 List 外面套一层。
    /// 拆成两个属性而不是内联进 body: 本仓既有做法就是把巨型表达式拆出来
    /// (LockKeeperApp 里那几处 "unable to type-check this expression in reasonable time" 同因)。
    private var settingsReader: some View {
        ScrollViewReader { proxy in
            settingsList(proxy)
        }
    }

    private func settingsList(_ proxy: ScrollViewProxy) -> some View {
        List {
            searchTextRow
            searchResults(proxy)
            // 乱源治理第 4 批: 五组筛选片。默认 nil = 全部 ⇒ 这一屏与加这批之前逐字一致，
            // 谁不碰它就没有任何行为变化；碰了是把 17 节先筛成 3~6 节。
            SettingsGroupChips(selection: $groupFilter)
            // 每节挂一枚稳定锚 (`.id`), 供页内搜索 scrollTo 用。锚是字符串常量, 与筛选片无关。
            if settingsSectionShown(groupFilter, .daily) { lockSection.id(SettingsAnchor.lock) }
            if settingsSectionShown(groupFilter, .daily) { deviceManageSection.id(SettingsAnchor.deviceManage) }
            if settingsSectionShown(groupFilter, .data) { securitySection.id(SettingsAnchor.security) }
            if settingsSectionShown(groupFilter, .daily) { unlockSection.id(SettingsAnchor.unlock) }
            if settingsSectionShown(groupFilter, .look) { timeSection.id(SettingsAnchor.time) }
            if settingsSectionShown(groupFilter, .daily) { autoOpenSection.id(SettingsAnchor.autoOpen) }
            if settingsSectionShown(groupFilter, .keys) { familySection.id(SettingsAnchor.family) }
            if settingsSectionShown(groupFilter, .data) { toolsSection.id(SettingsAnchor.tools) }
            if settingsSectionShown(groupFilter, .data) { drillSection.id(SettingsAnchor.drill) }
            if settingsSectionShown(groupFilter, .data) { applockSection.id(SettingsAnchor.applock) }
            if settingsSectionShown(groupFilter, .look) { a11ySection.id(SettingsAnchor.a11y) }
            if settingsSectionShown(groupFilter, .look) { appearanceSection.id(SettingsAnchor.appearance) }
            if settingsSectionShown(groupFilter, .help) { memorySection.id(SettingsAnchor.memory) }
            if settingsSectionShown(groupFilter, .daily) { reminderSection.id(SettingsAnchor.reminder) }
            if settingsSectionShown(groupFilter, .daily) { alertToneSection.id(SettingsAnchor.alertTone) }
            if settingsSectionShown(groupFilter, .help) { helpSection.id(SettingsAnchor.help) }
            if settingsSectionShown(groupFilter, .help) { aboutSection.id(SettingsAnchor.about) }
        }
        .navigationTitle("设置")
        .variantList()
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
        .sheet(isPresented: $showManage) { DeviceManageView() }
        // 2026-10-15 走查: 与上面那批 sheet 同款 —— 目标页自带 NavigationStack, 只能走 sheet
        .sheet(isPresented: $showUnclaimed) { UnclaimedClaimView() }
        .sheet(isPresented: $showFamilySettings) { MemberFamilySettingsView() }
        .sheet(isPresented: $showSecurity, onDismiss: { landPendingFocus(app.pendingSettingsFocus) }) { SecurityCenterView() }
        .sheet(isPresented: $showHouseCleaning) { HouseCleaningPresetView() }
        .sheet(isPresented: $showManual) {
            NavigationStack { ManualPage() }
                .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("完成") { showManual = false } } }
        }
        // 587: 诊断页用 sheet 呈现 (设置栈里那行 NavigationLink 仍走 push, 两条入口同一个页面)。
        // 为什么不用 navigationDestination(isPresented:): 全仓无先例, 而 sheet+NavigationStack 与
        // showManual 那一段逐字同构 —— 无编译器的机器上, 复用已验证的写法是唯一稳的取向。
        .sheet(isPresented: $showDiag) {
            NavigationStack { DiagnosticsView() }
                .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("完成") { showDiag = false } } }
        }
        // 1013: 保养通知落点, 与 showDiag 逐字同构 (复用已验证的 sheet+NavigationStack 写法)
        .sheet(isPresented: $showCare) {
            NavigationStack { MaintenanceView() }
                .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("完成") { showCare = false } } }
        }
        .task { landPendingDiag(app.pendingDiag) }              // 冷启动/首次挂载: 值已挂着
        .onChange(of: app.pendingDiag) { _, m in landPendingDiag(m) }
        .task { landPendingCare(app.pendingCare) }              // 1013: 与上两行同构
        .onChange(of: app.pendingCare) { _, m in landPendingCare(m) }
        // 2026-10-15: 设置 Tab 栈内子页 (安全中心 → 本机密码 / 销毁) 的"去设置…"落点, 同一条形态
        .task { landPendingFocus(app.pendingSettingsFocus) }
        .onChange(of: app.pendingSettingsFocus) { _, f in landPendingFocus(f) }
    }

    /// 587 落点: 切到本条记录所属锁, 再推诊断页 —— "查看这台锁的诊断"里的"这台锁"要真生效。
    private func landPendingDiag(_ m: String?) {
        guard let m, !m.isEmpty else { return }
        app.pendingDiag = nil
        if m != app.currentMac { app.select(m) }
        showDiag = true
    }

    /// 1013 落点: 切到通知里那台锁, 再推维护与保养页
    private func landPendingCare(_ m: String?) {
        guard let m, !m.isEmpty else { return }
        app.pendingCare = nil
        if m != app.currentMac { app.select(m) }
        showCare = true
    }

    /// 2026-10-15 落点: 设置 Tab **栈内**子页带回来的"到了之后开什么"。
    /// 与上面两条同构 —— 那边带 mac、这里带一个落点名, 都是"值挂着 → 设置页收到 → 开面 → 清空"。
    /// 安全中心那两枚按钮原先只写 `app.tabSelection = 3`, 而它们就在设置 Tab 下, 等于空转。
    /// 2026-10-15 §4.2 补一条: **被安全中心 sheet 盖住时不许消费**。这一页的所有落点 (备份 sheet /
    /// 密码 alert) 都挂在被盖住的那层 List 上, 当场开等于开给一个看不见的界面看; 而值一清就再也
    /// 没人重试。改成"盖着就留着", 由 showSecurity 的 onDismiss 再叫一次 —— 两条路都以"消费即清空"
    /// 收尾, 所以真机上是开一次还是等人回来才开一次, 都会且只会开一次。
    private func landPendingFocus(_ f: String?) {
        guard let f, !f.isEmpty else { return }
        guard !showSecurity else { return }
        app.pendingSettingsFocus = nil
        switch f {
        case "backup":
            // 400 销毁前备份闸: 直接开「备份与恢复」(备份工作室在它里面)
            showBackup = true
        case "passcode":
            // 396 随机键位的前提: 直接拉起「设置本机密码」流程
            setPasscode()
        case "diag":
            // 自检黄条与 377 那条快捷条的按钮都写着"去诊断", 而光切 Tab 只把人放在设置页根上 ——
            // "诊断与运行日志"是这一页里的一行。切过去不等于送到。
            showDiag = true
        case "members":
            // 817/317: 两枚"示例头像/去新建成员"写的是**直达成员入口**, 原来只到设置页根,
            // 剩下"家人与钥匙 → 成员管理"两跳还得自己找。成员中心到达后仍由 pendingMemberAdd 弹向导。
            showMembers = true
        default:
            // 认不出的落点名**不做任何事**。这一条是本设计的软肋, 如实写下:
            // 新增落点时这里不会响, 只会退回"点了没反应"那一族。核对办法 = 拿
            // `grep -rn 'pendingSettingsFocus = "' App --include=*.swift | grep -v '^[^:]*:[0-9]*:[[:space:]]*//'`
            // 的取值逐个对本 switch 的 case。⚠ 过滤注释要用**整行注释**这一条：写成 `grep -v '//'` 会把
            // 三行带行尾注释的写入点一起滤掉（实测少算 9→6）。2026-10-15 实测：写入点 9 处 = backup 4 / diag 2 /
            // members 2 / passcode 1，四个 case 一一对应、无悬空值。
            // 九处**全部**与 `app.requestTab(3)` 成对：7 处靠它把人先带到设置 Tab（不然这一页没挂载，值没人消费）；
            // 另 2 处本来就在本 Tab 的「安全中心」sheet 里，那次 requestTab 是同值空转，真正退栈由 §4.2 那套
            // "安全中心自己收摊 + 设置页 onDismiss 补开"承担。
            break
        }
    }

    private var mac: String { app.current?.mac ?? "" }

    // ---------- 包14: 27 设置内搜索 + 831 NEW 角标 ----------
    private var searchTextRow: some View {
        Section {
            // 2026-10-14 走查: ① 补放大镜 —— 一个没有图标的输入框在设置页里看着像"又一行标签",
            // 放大镜是 iOS 搜索框唯一稳定的形状信号; ② 占位符原来是半角括号与半角冒号
            // ("搜索设置 (如: 固件 / 备份 / 主题)"), 与全页中文混排看着像没写完, 改全角。
            HStack(spacing: DS.Space.s) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: DS.Icon.sm))
                    .foregroundStyle(DS.Palette.textSub)
                    .accessibilityHidden(true)
                TextField("搜索设置（如：固件 / 备份 / 主题）", text: $query)
                    .autocorrectionDisabled()
                    .accessibilityLabel("搜索设置项")
                // 清空钮: 搜完想回到全部设置时, 不必一个字一个字退格 (删到空为止)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: DS.Icon.sm))
                            .foregroundStyle(DS.Palette.textSub)
                            .frame(minWidth: DS.Hit.min, minHeight: DS.Hit.min, alignment: .trailing)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空搜索")
                }
            }
        }
    }
    /// 设置页每一节的滚动锚 (2026-10-15): rawValue 直接当 `.id()` 用 —— 字符串, 稳定且读得懂。
    /// `group` = 这一节归哪个筛选分组。跳转前必须先切过去, 否则命中节可能压根没被渲染,
    /// `scrollTo` 会**静默落空** (这正是"点了搜索没反应"的另一种形态)。
    private enum SettingsAnchor: String {
        case lock, deviceManage, security, unlock, time, autoOpen, family
        case tools, drill, applock, a11y, appearance, memory, reminder, alertTone, help, about

        var group: SettingsGroup {
            switch self {
            case .lock, .deviceManage, .unlock, .autoOpen, .reminder, .alertTone: return .daily
            case .security, .tools, .drill, .applock: return .data
            case .family: return .keys
            case .time, .a11y, .appearance: return .look
            case .memory, .help, .about: return .help
            }
        }
    }

    /// 27 设置页内搜索 (原句落点"App Store 式设置内搜索"): 命中词映射到对应条目, 直达功能
    private struct SearchHit: Identifiable {
        let id: String
        let title: String
        let icon: String
        /// 命中落在设置页的哪一节 (nil = 这个功能不在本页, 由 `go` 去开 sheet)
        var anchor: SettingsAnchor? = nil
        var go: () -> Void = {}
    }
    private var searchHits: [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let all: [SearchHit] = [
            // 2026-10-14 走查修: 这一排原来有一半的落点是**空转**或**跳错页** ——
            //   · `app.tabSelection = 3` 的 10 条: 搜索框就在设置页里, 切到"设置" Tab 等于原地不动,
            //     点一下什么都不发生 (用户会以为搜索坏了);
            //   · `app.tabSelection = 0` 的 6 条: 把用户送去设备页, 而「静音模式 / 校准门锁时间 /
            //     维护与保养 / 门锁安全模式 / 开锁偏好 / 锁档案」这些入口全在设置页, 设备页没有它们。
            // 2026-10-15 补上第二半: 光切筛选片还不够 —— 命中节常常排在所属分组的第二、第三节
            // (如「外观」在 .look 组里排第三), 用户还得自己翻。现在每条命中带一个 `anchor`,
            // 由 searchResults 负责"切组 + scrollTo 滚到那一节"。
            // 不在本页的功能 (开 sheet 的那些) 仍是 `anchor: nil`, 交给 go 直接开。
            SearchHit(id: "s.lockprofile", title: "锁档案 (昵称/符号/色标)", icon: "lock", anchor: .lock),
            SearchHit(id: "s.devicemanage", title: "设备管理 (排序/分组/批量) — 置顶即启动默认锁", icon: "rectangle.3.group") { showManage = true },
            SearchHit(id: "s.mute", title: "静音模式", icon: "speaker.slash", anchor: .lock),
            SearchHit(id: "s.synctime", title: "校准门锁时间", icon: "clock.arrow.circlepath", anchor: .lock),
            SearchHit(id: "s.maint", title: "维护与保养", icon: "wrench.and.screwdriver", anchor: .lock),
            SearchHit(id: "s.safemode", title: "门锁安全模式", icon: "shield.lefthalf.filled", anchor: .security),
            SearchHit(id: "s.unlockopt", title: "开锁偏好 (按住确认/围栏/提示音)", icon: "hand.draw", anchor: .unlock),
            SearchHit(id: "s.autoopen", title: "靠近自动开锁 (走近自动开门/距离标定)", icon: "person.walk", anchor: .autoOpen),
            SearchHit(id: "s.members", title: "成员管理", icon: "person.2") { showMembers = true },
            SearchHit(id: "s.keychainhw", title: "蓝牙钥匙串", icon: "key.horizontal") { showKeychainHW = true },
            SearchHit(id: "s.gateway", title: "智能网关", icon: "antenna.radiowaves.left.and.right") { showGateway = true },
            SearchHit(id: "s.firmware", title: "检查固件更新", icon: "arrow.up.circle") { showFirmware = true },
            SearchHit(id: "s.backup", title: "备份与恢复", icon: "externaldrive") { showBackup = true },
            SearchHit(id: "s.backupstudio", title: "备份工作室 (导出向导/恢复/WebDAV策略/换机迁移)", icon: "wrench.and.scissors") { showBackup = true },
            SearchHit(id: "s.messages", title: "动态消息", icon: "bell") { showMessages = true },
            SearchHit(id: "s.logs", title: "诊断与运行日志", icon: "list.bullet.rectangle") { showDiag = true },
            SearchHit(id: "s.applock", title: "本机数据保护 (应用锁)", icon: "lock.shield", anchor: .applock),
            SearchHit(id: "s.appearance", title: "外观 (主题/品牌色/密度)", icon: "paintbrush", anchor: .appearance),
            SearchHit(id: "s.achievements", title: "我的成就", icon: "rosette", anchor: .memory),
            SearchHit(id: "s.care", title: "关怀提醒与公告板", icon: "heart.text.square", anchor: .memory),
            SearchHit(id: "s.maintremind", title: "维护提醒", icon: "bell.badge", anchor: .reminder),
            SearchHit(id: "s.demo", title: "演练与演示 (演示模式/样例备份/七天样例)", icon: "theatermasks", anchor: .drill),
            SearchHit(id: "s.faq", title: "常见问题 (FAQ)", icon: "questionmark") { showManual = true },
            SearchHit(id: "s.manual", title: "使用手册", icon: "book") { showManual = true },
            SearchHit(id: "s.flow", title: "数据流向说明", icon: "arrow.right.circle", anchor: .help),
            SearchHit(id: "s.credits", title: "致谢与许可", icon: "hands.clap", anchor: .help),
            SearchHit(id: "s.copycheck", title: "文案体检", icon: "text.badge.checkmark", anchor: .help),   // 664 文案体检
        ]
        return all.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.id.hasSuffix(q) }
    }
    @ViewBuilder
    private func searchResults(_ proxy: ScrollViewProxy) -> some View {
        if !searchHits.isEmpty {
            Section("搜索结果 (\(searchHits.count))") {
                ForEach(searchHits) { h in
                    Button {
                        if let a = h.anchor {
                            // ① 先把该节所属的分组切过去 —— 否则这一节可能压根没被渲染, scrollTo 会落空
                            groupFilter = a.group
                            // ② 再等一拍: 同一帧里新插入的 Section 还没进 List 的布局, 当场 scrollTo 找不到它
                            DispatchQueue.main.async {
                                withAnimation(DS.Motion.quick) { proxy.scrollTo(a, anchor: .top) }
                            }
                        }
                        h.go()
                    } label: {
                        Label(h.title, systemImage: h.icon)
                    }
                }
            }
        }
    }

    // ---------- 包14 演练区 (836/837/844/845): 演示模式总开关 + 样例备份 + 演练入口 ----------
    private var drillSection: some View {
        Section {
            VariantToggle("演示模式 (所有开锁走模拟, 不碰锁端)", isOn: Binding(
                get: { DemoKit.isOn },
                set: { on in
                    DemoKit.setOn(on)
                    app.loadDevices()
                    app.showToast(on ? "演示模式已开 · demo_ 数据已铺底" : "已清除全部演示数据")
                }))
            NavigationLink { DemoLabsView() } label: {
                Label("演练场: 样例备份/七天样例/锁死演练", systemImage: "testtube.2")   // 837/845/844 演练场
            }
            if DemoKit.drillBackupOn {
                Button("首备演练完成, 转正式备份", role: .destructive) {   // 842 首备演练完成
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
            // 上一行写着"与常见问题", 但 FAQPage 全仓没有入口 (零引用) → 承诺与实现不符, 这里补上真入口
            NavigationLink { FAQPage() } label: { Label("常见问题", systemImage: "questionmark.circle") }   // 514 常见问题
            // 831: 这一页是本轮新建的, 用 NEW 角标做首见提示 (进入一次即消)
            newBadgeRow("按症状排查", "guide282") { SymptomGuideView() }   // 282 按症状排查
            NavigationLink { DataFlowPage() } label: { Label("数据从哪来到哪去", systemImage: "arrow.right.circle") }   // 240 数据从哪来到哪去
            NavigationLink { CreditsPage() } label: { Label("致谢与许可", systemImage: "hands.clap") }   // 300 致谢与许可
            // 43/44 新变化与更新说明: 每条都带功能编号，构建时由 tools/changelogcheck.js 拿代码标注对拍，
            // 对不上就判失败 —— 所以这一页不可能出现"说了没做"的功能。
            NavigationLink { ChangelogView() } label: { Label("新变化", systemImage: "sparkles") }   // 43/44 新变化
            NavigationLink { CopyCheckPage() } label: { Label("文案体检", systemImage: "text.badge.checkmark") }   // 664 文案体检
            if DB.store.getBool("kf_onb_ceremony") {
                NavigationLink { ButlerCertificateView() } label: {
                    Label("我的就任证书", systemImage: "rosette")   // 813 我的就任证书
                }
            }
            Button {
                Onboarding.replayAll()
                app.onboardingFinished = false
                app.showToast("下次冷启动重新走引导, 或现在就看")
            } label: {
                HStack(spacing: DS.Space.s) {
                    Text("重看新手引导")   // 805 重看新手引导
                    Spacer(minLength: DS.Space.s)
                    // 805 已完成度: 与证书页同一份 finishedSteps, 不另记账
                    Text("已完成 \(Onboarding.finishedSteps.count)/\(Onboarding.Step.allCases.count) 步")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                }
            }
            // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 命中高仅约 16.5pt (< 44)。
            // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
        } header: {
            Text("帮助与关于")
        } footer: {
            Text("全部本地内容, 无在线客服; 手册章节随引导进度标记未读。")
        }
    }

    // ---------- 门锁 ----------
    // ---------- 设备管理 (104 分组 / 107 批量 / 766 排序置顶 / 767 分组场景) ----------
    // 单独成一段而不是塞进"门锁"段: 那一段讲的是**当前这把锁**的设置, 这一段讲的是锁与锁之间的关系,
    // 而且一把锁都没绑的时候也要进得去 (从备份恢复完的锁要先排序)。
    private var deviceManageSection: some View {
        Section {
            // 2026-10-15 走查: DeviceManageView 自带 NavigationStack, 而本页**已经**有一条 sheet 入口
            // (`showManage`, 页内搜索命中「设备管理」走它) —— 这里再 push 一次既是重复入口, 又是
            // "自带栈的页被 push" ⇒ 两层导航栏。两条入口并成一条, 统一走 sheet。
            Button { showManage = true } label: {
                Label("设备管理 (排序/分组/批量)", systemImage: "rectangle.3.group")
            }
            // 766 拖动排序与置顶同步设
            // 271 拖动排序与置顶同步设
            Text("拖动排序与置顶同步设备页的翻页顺序，第一行即启动默认锁。"
                 + "顺序、分组、分组折叠与隐藏随全量备份包走 (D-36)：换机恢复后不必重排；"
                 + "锁档案的场所副标题 / 备注 / 符号色标仍只存本机。")
                .vkFont(.caption2)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var lockSection: some View {
        Section("门锁") {
            if app.current == nil {
                // 包14 空态族第一次在设置页真接上 (814 顶部进度点 / 815 双按钮 / 834 演示链 / 841 小管家 / 1044 便签):
                // 814 的 1/3 = 三卡导览的次序 (连锁→录凭证→开门, 与 Onboarding 801 同口径), 这里停在"连锁"前一步;
                // 834 演示链 = 开演示锁并跳设备页 (组件的 accessibilityHint 承诺的就是这条路径, 不另编一套);
                // 此前这里只有一个裸「添加设备」按钮, 空态组件在设置页零消费。
                GuidedEmptyView(systemImage: "lock",
                                title: "还没有添加门锁",
                                message: "添加后这一段才会出现锁档案、静音、校时与删除等设置。三步走: 连锁 → 录凭证 → 开门。",
                                step: 1, stepTotal: 3,
                                primaryTitle: "添加设备",
                                primary: { showAdd = true },
                                secondaryTitle: "重看新手引导",
                                secondary: {
                                    Onboarding.replayAll()
                                    app.onboardingFinished = false
                                    app.showToast("下次冷启动重新走引导")
                                },
                                demoAction: {
                                    DemoKit.setOn(true)
                                    app.loadDevices()
                                    app.requestRoute(.device)
                                    // 收摊口径：SettingsView 有两种呈现 —— ① Tab 3 的根 (LockKeeperApp:1081)，
                                    // 这一句是真跳转，**不该**收摊；② 设备页 `.sheet { SettingsView() }`
                                    // (DeviceHomeView:197)，用户本来就在设备页 ⇒ 切 0 是空转、缺的正是 dismiss()。
                                    // 补一句 dismiss() 会同时作用在两种呈现上，而"dismiss() 在自带 NavigationStack 的
                                    // Tab 根上会不会 pop 栈/退到别处"本机判不了 ⇒ 不猜，挂真机卡 (交接书 §7.9 卡 10)。
                                    // 判它的尺子是常驻闸门 tools/sheetcover.js（行 LII 那条一次性尺子的落盘版）。
                                    app.showToast("演示锁已就位: 在设备页点圆盘走一遍, 顶部横幅可一键清除")
                                })
                    .listRowInsets(EdgeInsets())
            } else {
                NavigationLink("锁档案 (昵称/符号/色标/备注)") { LockProfileView() }
                // 包2 连接与预握手偏好 (70/97/100): 自动预握手开关 / 成功率积累占位 / 信号围栏记忆
                NavigationLink("连接与预握手 (自动预热/成功率)") { LinkPrefsView(mac: mac) }
                note("靠近时先连上，开锁少等一两秒；成功率只在本机统计。")
                Button("锁信息名片") { showDeviceInfo = true }
                note("型号、固件、电量与绑定时间的汇总卡。")
                VariantToggle("静音模式", isOn: Binding(
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
                note("关掉门锁键盘的提示音；不影响本 App 的通知。")
                NavigationLink("校准门锁时间") { SyncTimeView() }
                note("锁端时钟不准时，临时码和有效期会失效。")
                NavigationLink("维护与保养 (周期/换电)") { MaintenanceView() }
                if canDefend {
                    NavigationLink("一键布防") { DefendView() }
                    note("出门后锁端拒绝一切开锁，需再次连上解除。")
                }
                if canTailgate {
                    NavigationLink("防尾随入室") { TailgateView() }
                    note("开门后短时间内刷同一凭证才告警。")
                }
                if canClearPwd {
                    Button("清空密码", role: .destructive) { clearPwd() }
                        .disabled(clearingPwd)
                }
                // 2026-10-14 走查: 从「家人与钥匙」挪来 (它属于门锁本身, 不属于成员)。
                // 一加一删成对, 且本节空态那一支本来就带「添加设备」按钮 —— 有锁时才需要"另一把"。
                Button { showAdd = true } label: { Label("添加另一把锁", systemImage: "plus") }
                Button("删除设备", role: .destructive) { deleteDevice() }
            }
        }
    }
    private var muteStored: Bool { DB.store.getBool("kf_mute_" + mac) }

    /// 2026-10-14: 设置项小字注解。口径"简洁明了" —— 只说用户决策需要的那一句
    /// (这一项是干什么的 / 要不要连锁 / 有什么后果), 不铺陈实现细节 (那些留在注释里)。
    /// 与 deviceManageSection 既有的 caption2 小字同一族, 这里收成一个 helper 免得每处重抄三行修饰。
    private func note(_ s: String) -> some View {
        Text(s)
            .vkFont(.caption)
            .foregroundStyle(DS.Palette.textSub)
            .fixedSize(horizontal: false, vertical: true)
    }
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
        // 第八十七批: 这条最硬 —— 它要**清空整本密码台账**。原先 `mac` (活读 app.current) 在
        // ensureConnected 与 pwdClear 两次 await 之后才读最后一次；期间当前锁被改掉 (AppIntent /
        // kf:// 深链都会动 app.current) 就会清掉另一把锁的台账，而 nil 时 `?? ""` 还会静默写空台账。
        let m = mac
        guard !m.isEmpty else { app.showToast("未选择门锁"); return }
        clearingPwd = true
        defer { clearingPwd = false }
        do {
            try await app.lock.ensureConnected(mac: m)
            try await app.lock.pwdClear()
            DB.saveLedger(m, Ledger()) // 清空本地密码台账 (指纹保留)
            app.showToast("清空密码成功")
        } catch { app.showToast("清空失败: \(error.localizedDescription)") }
    }

    private func deleteDevice() {
        guard let kc = app.current else { return }
        // 109 删除冷静期: 后果要可核对 (逐类计数), 且必须键入锁名才放行 —— 旧写法只有一次"确定吗"
        let pws = DB.listPwds(kc.mac).count
        let fps = DB.listFps(kc.mac).count
        let pend = CredentialOrg.pendingCount(kc.mac)
        let bin = CredentialOrg.bin(kc.mac).count
        let recs = DB.readLogs(kc.mac).count   // 109: 记录缓存 (kf_logcache_) 也随设备删除, 计数一并预告
        let name = LockArchive.displayName(kc)
        var consequence = "将删除本机的钥匙串与该门锁全部本地数据 (锁端密钥不变)。"
        if pws + fps + pend + bin + recs > 0 {
            consequence += " 连带删除: 密码台账 \(pws) 条、指纹台账 \(fps) 条、待下发 \(pend) 项、回收站 \(bin) 条、本机缓存的开门记录 \(recs) 条。"
        }
        consequence += " 删除后若未做过备份将无法找回。"
        confirmDestructiveTyped("删除设备", consequence, requireWord: name, confirmTitle: "确认删除") {
            DB.removeDevice(kc.mac)
            app.loadDevices()
            app.showToast("已删除「\(name)」")
        }
    }

    // ---------- 安全 ----------
    private var securitySection: some View {
        Section("安全") {
            NavigationLink("门锁安全模式") { SafemodeIntroView(mode: "safe") }
            note("单次 / 双重验证：决定开一道锁还是两道。")
            // 包7: 安全·隐私·审计中心 (应用锁增强/防窥/审计流水/数据销毁)
            // 2026-10-15 走查: SecurityCenterView 自带 NavigationStack, push 进去会套两层导航栏
            // (判据见本文件「动态消息」那条注释)。改用 sheet —— 本页已有十余个设置子页走 sheet。
            Button { showSecurity = true } label: {
                Label("安全中心 (应用锁/防窥/审计/销毁)", systemImage: "lock.shield")
            }
            note("应用锁、防窥、审计流水与数据销毁都在这页。")
        }
    }

    // ---------- 开锁 (包1: 按住确认/围栏/提示音/自动重试/圆盘尺寸) ----------
    // ---------- 647 时间显示 (制式 + 是否到秒) ----------
    /// 单一出口: 时间线/详情卡/导出都读 `TimeFormat`，这里写的就是它们的结果。
    /// 分屏/多锁时"同一条记录显示成三个样子"是 647 的原罪，所以这节不提供任何页面级覆盖。
    /// 911 时间制式覆盖 (原句"独立于系统设置") 就是这同一个 Picker: 选"跟随系统"之外的一档时,
    /// 本 App 不再听系统的 12/24 小时偏好 —— 两件事共用一个键，而不是各存一份再吵谁赢。
    private var timeSection: some View {
        Section {
            Picker("时间制式", selection: Binding(
                get: { TimeFormat.style },
                set: { app.setUnlockOption(TimeFormat.styleKey, $0) })) {
                Text("跟随系统").tag("")
                Text("24 小时制").tag("24")
                Text("12 小时制").tag("12")
            }
            VariantToggle("显示秒", isOn: Binding(   // 651 显示秒
                get: { TimeFormat.showSeconds },
                set: { app.setUnlockOption(TimeFormat.secsKey, $0) }))
            VariantToggle("记录行加第二行完整日期", isOn: Binding(   // 648 记录行加第二行完整日
                get: { TimeFormat.twoLine },
                set: { app.setUnlockOption(TimeFormat.twoLineKey, $0) }))
        } footer: {
            Text("秒只在日志原文真的带秒时出现，缺位的行不补 “:00”——那等于假装这条记录精确到秒。\n"
                 + "制式不做时区换算：锁端键盘上写的是几点，这里就显示几点。")
                .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
        }
    }

    private var unlockSection: some View {
        Section {
            VariantToggle("按住确认开锁", isOn: Binding(
                get: { DB.store.getBool("kf_hold_confirm", true) },
                set: { app.setUnlockOption("kf_hold_confirm", $0) }))
            VariantToggle("误触围栏", isOn: Binding(
                get: { DB.store.getBool("kf_fence") },
                set: { app.setUnlockOption("kf_fence", $0) }))
            // 52/58 开锁手势三档 (第九十八批, 2026-10-10 拍板"手势族全做"后补回)。
            // 默认档 hold 与拍板前的行为**逐字一致**; 另两档是**替代**按住确认的确认方式，互斥而非叠加。
            Picker("开锁手势", selection: Binding(
                get: { UnlockPrefs.mode },
                set: { app.setUnlockOption("kf_gesture_mode", $0) })) {
                Text("按住确认 (默认)").tag("hold")
                Text("三连点防误开").tag("triple")   // 58 三连点防误开
                Text("旋转充能").tag("charge")   // 52 旋转充能
            }
            Text("三连点 = 连点圆盘三次才发指令，前两下只有渐强触感；旋转充能 = 沿圆盘外沿转满一圈"
                 + "(iPhone 无数码表冠，本档按原句「转一圈才发」的行为落地)。两种都不缩短防误触的判定，"
                 + "只是把「按住」换成另一种必须做完的动作。")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
            // 53 双击直开: 这是防误触的**减配** (绕过按住确认)，所以默认关、只在按住确认档可开、
            // 标签自己写明「绕过确认」 —— 一个把安全降级说得像便捷特性的开关，本仓不写。
            VariantToggle("双击直开 (绕过按住确认)", isOn: Binding(
                get: { DB.store.getBool("kf_tap_direct") },
                set: { app.setUnlockOption("kf_tap_direct", $0) }))
                .disabled(UnlockPrefs.mode != "hold")
            if UnlockPrefs.mode != "hold" {
                Text("三连点/旋转充能档已自带确认动作，双击直开只在「按住确认」档提供。")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
            }
            VariantToggle("成功提示音", isOn: Binding(
                get: { DB.store.getBool("kf_unlock_sound") },
                set: { app.setUnlockOption("kf_unlock_sound", $0) }))
            // 2026-10-13 对抗式排查: 实时活动的开关位 (`kf_live_unlock`) 原先全仓只有读没有写
            // ⇒ LiveUnlock.enabled 恒 true, 用户根本关不掉 (77/939/941 "可关" 是假能力)。
            // 这里补上唯一写入点。关掉只影响锁屏/灵动岛的展示, 开锁链本身一个字不变。
            VariantToggle("开锁实时活动 (锁屏/灵动岛)", isOn: Binding(
                get: { LiveUnlock.enabled },
                set: { LiveUnlock.setEnabled($0) }))
            // 848 成败两音各自一枚开关: 只开"失败"的人要的是"没开成就别吵我", 只开"成功"的人反过来 ——
            // 合成一枚开关就只能服务其中一半人, 而这一半永远察觉不到另一半的存在。
            VariantToggle("失败提示音", isOn: Binding(
                get: { DB.store.getBool("kf_unlock_fail_sound") },
                set: { app.setUnlockOption("kf_unlock_fail_sound", $0) }))
            // 音色 ID 未经真机核对 (AlertTone 里标着 ⚠), 所以文案不承诺"两声不同", 只说各响一次。
            Text("失败音只在**试完全部重试仍没开成**那一刻响一次, 中途静默重试不响。两枚开关都默认关, 走系统同一音量通道, 手机静音时一起安静。")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            // 884 公共场合音量提示: 把"这个声音走的是媒体音量"说出来 —— 用户调小本 App 却发现
            // 响的是整台手机的媒体音量，那才是吓人的地方。界面不假装自己有一个独立音量。
            Text("提示音跟随系统媒体音量：本 App 不单独放大，也不新开一路音量。"   // 884 提示音跟随系统媒体音
                 + "公共场合请先调系统的侧键音量，或直接关掉这一开关改用触感。")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            VariantToggle("失败自动重试", isOn: Binding(
                get: { DB.store.getBool("kf_auto_retry", true) },
                set: { app.setUnlockOption("kf_auto_retry", $0) }))
            Picker("圆盘尺寸", selection: Binding(
                get: { DB.store.getInt("kf_dial_size", 176) },
                set: { app.setUnlockOption("kf_dial_size", $0) })) {
                Text("小").tag(160)   // 160 界面文案
                Text("标准").tag(176)   // 176 标准
                Text("大").tag(200)   // 200 界面文案
            }
            .pickerStyle(.menu)
        } header: {
            Text("开锁")
        } footer: {
            Text("按住圆盘时长 (默认 0.9s, 可在 辅助功能 里 0.4–1.6s 自定) 或上滑触发开锁；关闭「按住确认」后退回轻点直开 (适合单手与 VoiceOver)。误触围栏开启后需先从圆盘边缘拖到中心再执行开锁手势。")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // ---------- 靠近自动开锁 (AUTOOPEN-PLAN §4): 全门绿才自动开门, 默认关, fail-closed ----------
    @ViewBuilder   // 编译级修正: 这块是"顶层 if 而没有 else/return", 不加 builder 就是一句 "function declares some View…" 的编译错误
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
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            credCareSection
        }
    }
    @ViewBuilder
    private var memberFamilyRows: some View {
        Button { showMembers = true } label: { Label("成员管理（含成员中心）", systemImage: "person.2") }
        // 2026-10-15 走查: 下面两行原为 NavigationLink, 而它们的目标页**自带 NavigationStack**
        // (UnclaimedClaimView / MemberFamilySettingsView 都是 leading「完成」「保存」+ dismiss 的
        // sheet 形态) —— push 进去就是内层栈套外层, 两层导航栏。这正是本文件 620 行那条判据
        // (「MessagesView 自带 NavigationStack, 用 NavigationLink 会嵌套两层导航栏」) 说的形状,
        // 作者当时的处理就是改用 sheet —— 这里照同一条做法。成员活跃结构 (MemberStackedView)
        // 没有自带栈, 仍走 push, 不动。
        Button { showUnclaimed = true } label: { Label("未归属记录认领", systemImage: "questionmark.circle") }   // 791 未归属记录认领
        NavigationLink { MemberStackedView() } label: { Label("成员活跃结构", systemImage: "chart.bar.fill") }   // 798/792 成员活跃结构
        Button { showHouseCleaning = true } label: { Label("家政周期预设", systemImage: "broom.fill") }   // 483 家政周期预设
        Button { showFamilySettings = true } label: { Label("家庭设置：长辈模式/隐私浏览", systemImage: "hand.raised.fill") }   // 479/794 家庭设置
        Button { showKeychainHW = true } label: { Label("蓝牙钥匙串", systemImage: "key.horizontal") }
        // 2026-10-14 走查: 「添加另一把锁」原先挂在本节末尾 —— 它讲的是"再加一把锁", 属于门锁本身,
        // 与"谁能开门"（家人与钥匙）不是同一件事; 而且本节的 footer 正在解释成员分组, 摆一个添加设备
        // 在下面读起来像"给这个成员再加一把锁"。已挪进 lockSection 的「门锁」节 (与「删除设备」同处,
        // 一加一删成对), 空态那一支本来就带「添加设备」按钮。
    }

    // ---------- 包6 凭证整理 (491 版本配额 / 497 回收站保留期 / 919 别名显示) ----------
    private var credCareSection: some View {
        Section {
            // 2026-10-14 走查: 原标签「历史版本配额 N 版/凭证」的量纲读不出来 —— "版/凭证" 是
            // "每凭证几版" 还是 "总共几版"? 同一节下面的「回收站保留 N 天」是单值, 两个 Stepper
            // 单位不同却并列, 更容易读岔。改成一句能直接念出来的话。
            Stepper("每个凭证保留 \(CredentialOrg.quota(mac)) 个历史版本", value: Binding(   // 491 历史版本配额
                get: { CredentialOrg.quota(mac) },
                set: { DB.store.set("kf_ccred_quota", $0) }), in: 3...30, step: 1)
                .fixedSize(horizontal: false, vertical: true)
            Stepper("回收站保留 \(CredentialOrg.reclaimDays()) 天", value: Binding(   // 497 回收站保留
                get: { CredentialOrg.reclaimDays() },
                set: { DB.store.set("kf_cbin_reclaim_days", $0) }), in: 7...90, step: 7)
                .fixedSize(horizontal: false, vertical: true)
            // 2026-10-14: 去掉标签里的内部规格编号 "(919: …)"。它把一行标签撑成两行、把右侧开关挤到
            // 第二行居中，而用户看到的是一串跟自己无关的编号 —— 本仓"乱源治理"清过 1037 处同类，这一处漏了。
            // 语义说明挪进本节 footer，标签回归一行 (截图里折行撑歪开关就是这条)。
            VariantToggle("成员别名显示", isOn: Binding(
                get: { CredentialOrg.aliasDisplay },
                set: { DB.store.set("kf_calias_display", $0) }))
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("凭证整理")
        } footer: {
            Text("「成员别名显示」开着时, 有备注名的成员优先显示备注 (如「老妈」), 否则显示称呼。\n版本快照与回收站只在本机留存; 需锁端生效的操作保持「待下发」, 到场连接后在凭证页队列补发。")
                .vkFont(.caption)
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
            NavigationLink("诊断与运行日志") { DiagnosticsView() }
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
                .vkFont(.caption)
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
                note("4 位以上数字。查看密码与导出备份前会要求输入。")
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
        let alert = UIAlertController(title: "设置本机密码", message: "4 位以上纯数字 (随机键位需要数字键盘, 含字母会失去该保护)", preferredStyle: .alert)
        alert.addTextField { $0.isSecureTextEntry = true; $0.keyboardType = .numberPad }
        alert.addTextField { $0.isSecureTextEntry = true; $0.placeholder = "再次输入"; $0.keyboardType = .numberPad }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            let f1 = alert.textFields?[0].text ?? ""
            let f2 = alert.textFields?[1].text ?? ""
            guard !f1.isEmpty, f1 == f2 else { app.showToast("两次输入不一致"); return }
            guard f1.count >= 4 else { app.showToast("密码需 4 位以上"); return } // 与提示文案一致
            guard f1.allSatisfy({ $0.isNumber }) else { app.showToast("只能使用数字"); return }
            DB.setPasscode(f1)
            DB.store.set(SecKey.randKeyDigits, true)   // 396 前提标记: 本机密码确为纯数字
            app.showToast("已设置")
        })
        UIApplication.topViewController()?.present(alert, animated: true)
    }

    // ---------- 外观 (包16: 主题四档 / 品牌色 / 密度 / 最近开门条数 / 备选图标 / 重置) ----------
    @State private var currentIcon: String? = UIApplication.shared.alternateIconName

    private var appearanceSection: some View {
        Section {
            // 2026-10-16 界面变体切换。放在"外观"节是因为它是显示层选择，
            // 但**它不参与 resetAppearance() 那张清单** —— 理由见 UIVariant.canResetWithAppearance：
            // 换的是整个导航模型，"将外观重置为默认值"这句弹窗没承诺过这件事。
            Picker("界面样式", selection: Binding(
                get: { app.uiVariant },
                set: { app.setUIVariant($0) })) {
                ForEach(UIVariant.allCases) { v in
                    Text(v.title).tag(v)
                }
            }
            .pickerStyle(.menu)
            // 实验性变体必须自报边界：不写这句，用户切过去发现某页没了，
            // 会以为功能被删 —— 这正是"两套 UI 必有一套少功能"的投诉形状。
            if app.uiVariant.isExperimental {
                Text(app.uiVariant.note + "。" + app.uiVariant.unfinished)
                    .vkFont(.footnote)
                    .foregroundStyle(.secondary)
            }
            // 完整性读数：静态闸门只能说"每个目的地都挂了缝"，
            // 说不了"你在真机上真的走到过没有"。这一行把后者变成可见数字 ——
            // 没点到的那几站列得出来，"两套都完整"才不是一句自我声明。
            VariantCoverageRow()
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
            // 31 三套品牌色换肤 (原句"三套"): accent/accentText/渐变全 App 即时切换, 已由 886 扩到六套
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
            // 圆角档位 (900): 只动卡片/控件/格子三档，胶囊不参与
            Picker("圆角", selection: Binding(
                get: { DB.store.getString("kf_radius") },
                set: { app.setRadius($0) })) {
                Text("标准").tag("")
                Text("偏硬朗 (小)").tag("soft")
                Text("偏柔和 (大)").tag("plump")
            }
            .pickerStyle(.menu)
            // Hero 卡纹理 (889): 纯矢量三层之一，默认"无纹理"= 与旧版一致
            Picker("主控卡纹理", selection: Binding(
                get: { DS.Metric.heroTexture },
                set: { app.setHeroTexture($0) })) {
                Text("无").tag("")
                Text("细网格").tag("grid")
                Text("微噪点").tag("grain")
            }
            .pickerStyle(.menu)
            note("只换主控卡的底纹，不影响内容与读数。")
            // 动效档位 (899): 管的是全 App 动效令牌，不是"只换 Tab 那一下" —— 文案照实写
            Picker("动效强度", selection: Binding(
                get: { DB.store.getString("kf_motion").isEmpty ? "standard" : DB.store.getString("kf_motion") },
                set: { app.setMotionTier($0) })) {
                Text("克制").tag("calm")
                Text("标准").tag("standard")
                Text("活泼").tag("lively")
            }
            .pickerStyle(.menu)
            if AXFlags.reduceMotion {
                Text("系统「减弱动态效果」已开启，当前强制走克制档，上面的选择暂不生效。")
                    .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 节日限定色 (890): 默认关。给用户的既有界面换色属于"打扰"，必须显式开。
            // 只在 671 表里的法定假日当天生效；补班日不染色 (那是要上班的日子)；表外节日一律不猜色。
            VariantToggle("法定节假日染主控卡", isOn: Binding(
                get: { DB.store.getBool("kf_festive") },
                set: { app.setFestive($0) }))
            // 启动一句话 (898): 按当天定值的一句本地短语，晚归语与节气排在它前面
            VariantToggle("主控卡每日一句话", isOn: Binding(
                get: { DB.store.getBool("kf_launch_line", true) },
                set: { app.setLaunchLine($0) }))
            // 高对比皮肤 (893): App 内这一档，不必为一只 App 去改整机设置。
            // getter 只读**本机偏好** kf_hc —— 读 DS.Appearance.highContrast (系统∪本机) 的话，
            // 系统那边开着而本机没开时这个开关会"关不下去"，看着像坏了。
            VariantToggle("高对比皮肤", isOn: Binding(
                get: { DB.store.getBool("kf_hc") },
                set: { app.setHighContrast($0) }))
            note("文字与分隔线加深一档，不必去改整机设置。")
            // 周起始日 (912): 一处读点管住"本周"时间词 / 月历表头与格子 / 本周整理数 / 本周轮值键
            Picker("周起始日", selection: Binding(
                get: { WeekCal.key },
                set: { app.setWeekStart($0) })) {
                Text("跟随系统（当前为 \(WeekCal.effectiveName)）").tag("")
                Text("周一").tag("mon")
                Text("周日").tag("sun")
                Text("周六").tag("sat")
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
            note("只改间距，字号与按钮大小不变。")
            // 凭证行高 (901): 两档 = 紧凑(隐藏副行, 只留名称与状态) / 舒适(加高, 带副行)。
            // 只加行最小高度，不动字号 —— 压矮会裁多行备注，那不是紧凑
            Picker("凭证行高", selection: Binding(
                get: { DB.store.getString("kf_row_h") },
                set: { app.setRowHeight($0) })) {
                Text("紧凑 (只留名称与状态)").tag("")
                Text("舒适 (加高)")   .tag("tall")
            }
            .pickerStyle(.menu)
            // 时间线行距 (907): 叠在上面的布局密度之上，两档体系是相乘不是各写一套
            Picker("时间线行距", selection: Binding(
                get: { DB.store.getString("kf_tl_gap") },
                set: { app.setTimelineGap($0) })) {
                Text("紧凑").tag("tight")
                Text("标准").tag("")
                Text("宽松").tag("loose")
            }
            .pickerStyle(.menu)
            // 902 数字字体两档: 单一令牌 DS.Metric.digitDesign, 落点只有主控卡读数与指标块两处。
            // 标签写明射程 —— 全仓 58 处散点读数不跟着换 (§84 撤掉的就是那种"总闸"假象),
            // 这里切的正是 902 原句"Hero 卡电量数字圆体/默认体可选"的那两处。
            Picker("主控读数数字字体", selection: Binding(   // 902 主控读数数字字体
                get: { DB.store.getString("kf_digit_font") },
                set: { app.setUnlockOption("kf_digit_font", $0) })) {
                Text("圆体 (默认)").tag("")
                Text("系统默认体").tag("plain")
            }
            .pickerStyle(.menu)
            note("只换主控卡上电量那几个数字的字体。")
            // Hero 参考指标位 (909): 电量刻意不给开关 (它决定还能不能开锁)
            VariantToggle("主控卡显示固件位", isOn: Binding(
                get: { DS.HeroStats.shows("firmware") },
                set: { v in app.setHeroStats(DS.HeroStats.all.filter { $0 != "firmware" || v }) }))
            VariantToggle("主控卡显示锁钟位", isOn: Binding(
                get: { DS.HeroStats.shows("lockclock") },
                set: { v in app.setHeroStats(DS.HeroStats.all.filter { $0 != "lockclock" || v }) }))
            note("主控卡上那几个小位要显示哪几个；电量不给关。")
            // 素颜模式 (idea 1046): 一键关闭庆祝与徽章动效
            VariantToggle("素颜模式", isOn: Binding(
                get: { DB.store.getBool("kf_plain") },
                set: { DB.store.set("kf_plain", $0) }))
            note("关掉彩带、徽章动效一类的庆祝效果。")
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
            // 897 四季图标自动对齐: 默认关。桌面图标是用户首屏上看得见的东西，悄悄换属于越界。
            VariantToggle("回前台时按当季对齐图标", isOn: Binding(
                get: { SeasonIcon.autoOn },
                set: { v in
                    SeasonIcon.setAuto(v)
                    if v { SeasonIcon.syncIfNeeded() } else { DB.store.remove(SeasonIcon.lastKey) }
                    app.showToast(v ? "只在季节真的换了时对齐一次；不想用就关掉"
                                      : "已关掉自动对齐，手动选的图标不受影响")
                }))
            Text("春夏秋冬分别用现有的四款图标（春绿环 / 夏主图标 / 秋琥珀钥匙 / 冬石墨盾）。只在你选过这四款之一时对齐；手动选别的图标不会被覆盖。")
                .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            // 892 自定义强调色 (ColorPicker 管线)。存的是"色相来源"，上屏的每一档都要过亮度带，
            // 所以选到近白/近黄这类压不住白字的颜色时，主卡不会变白糊一片 —— 是被压暗后的同色系。
            ColorPicker("自定义强调色 (会盖过上面六套)",
                        selection: Binding(
                            get: { Color(hex: DS.CustomAccent.rgb == 0 ? 0x4F46E5 : DS.CustomAccent.rgb) },
                            set: { c in
                                let hex = DS.CustomAccent.rgb(from: c)
                                app.setCustomAccent(hex)
                            }),
                        supportsOpacity: false)
            if DS.CustomAccent.isActive {
                Button("取消自定义，回到六套预设") { app.setCustomAccent(0) }
                    .vkFont(.footnote).foregroundStyle(DS.Palette.accentText)
                Text("自定义色只影响强调色、主控卡与按钮渐变；文字与语义色仍走系统令牌。选到很亮的颜色时会被压暗到能看清白字的范围，观感接近同色系的深色版。")
                    .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 895 "儿童友好"预设：不叫"儿童模式"——本 App 没有内容分级，名字暗示过滤就是虚假承诺
            Button("套用儿童友好外观预设") { app.applyFriendlyPreset() }   // 895 套用儿童友好外观预设
                .vkFont(.callout)
                .foregroundStyle(DS.Palette.accentText)
            Text("一次把品牌色、圆角、密度、凭证行高、动效与纹理推到「看得清、点得准、不闹」的组合；"
                 + "只改外观，不过滤内容，任何一档之后都能单独改回。")
                .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            // 记录页开场过滤策略 (908): 盖在 192"按锁记住上次过滤"之上的一层开场规则。
            // 措辞刻意避开"清除/删除"—— 三种策略都**不删**已存的会话过滤，只是决定进页面时从哪开始。
            Picker("记录页开场过滤", selection: Binding(
                get: { QueryFilters.policy },
                set: { QueryFilters.setPolicy($0) })) {
                Text("记住每把锁上次的过滤").tag("")
                Text("每次都从全部开始").tag("fresh")
                Text("每次默认只看告警").tag("alarm")
            }
            .pickerStyle(.menu)
            Text("这只改变进入记录页时的**起点**；你手动改过的过滤仍会按锁留着，切回上一项就还在。不会删任何记录。")
                .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            // 905 快捷格"十一选六" (921 加了"再开一次") + 1047 常用动作排前。
            // 放在"外观"这一节里是有意的：它改的是设备页那一圈格子的组成与次序，属于布局个性化；
            // 但要注意它改完是**立即生效**的 (走 bumpAppearanceForLayout 重建一次树)，
            // 不需要重进 App。
            ForEach(QuickPool.all) { a in
                VariantToggle(a.label, isOn: Binding(
                    get: { QuickPool.selected.contains(a) },
                    set: { on in
                        var ids = QuickPool.selected.map { $0.id }
                        if on { if !ids.contains(a.id) { ids.append(a.id) } }
                        else { ids.removeAll { $0 == a.id } }
                        // 一格都不留 = 快捷区整体消失，那是把"自定义"变成"自残"：兜回默认六格
                        QuickPool.setSelected(ids.isEmpty ? QuickPool.defaultIds : ids)
                        app.bumpAppearanceForLayout()
                    }))
            }
            Text("也可以直接在设备页长按任一快捷格打开这份编辑。")   // 905 也可以直接在设备页长
                .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
            VariantToggle("常用动作排到前面", isOn: Binding(   // 1047 常用动作排到前面
                get: { QuickPool.smartFirst },
                set: { v in
                    QuickPool.setSmartFirst(v)
                    if !v { QuickPool.clearCounts() }   // 关掉就把计数清空: 不留"统计还在偷偷跑"
                    app.showToast(v ? "开始按点击次数排序（只存本机）" : "已停止记录并清空计数")
                    app.bumpAppearanceForLayout()
                }))
            Text("没动过这个开关时: 本机静默记点击次数, 满 30 天后首格自动推荐最常用的一格; 关掉 = 停止记录并清空计数, 排序回到你手选的次序。")
                .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            if QuickPool.smartFirst {
                let c = QuickPool.counts
                Text(c.isEmpty ? "还没攒到点击记录：去设备页点几次快捷格。"
                               : "已记录: " + QuickPool.all.filter { c[$0.id] != nil }
                                   .map { "\($0.label) \(c[$0.id]!) 次" }.joined(separator: " · "))
                    .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 恢复默认外观 (idea 202): 带确认弹窗, 只重置外观偏好
            Button("恢复默认外观") { resetAppearance() }
        } header: {
            Text("外观")
        } footer: {
            Text("主题、品牌色（六套）、密度、圆角、高对比、周起始日、行高与行距、指标位、纹理、动效强度、节日色、每日一句话都在本机生效，即时可见，不上传。高对比与系统「辅助功能-增加对比度」是并联关系，任一开着都加强；系统「减弱动态效果」会把动效强度压到克制档。素颜模式一键关闭庆祝与徽章动效；纯黑适合 OLED 夜间。")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { currentIcon = UIApplication.shared.alternateIconName }
    }

    // ---------- 备选 App 图标 (idea 896) ----------
    // 缩略预览色块与真实 PNG 同底色同符号; 点按走 UIApplication.setAlternateIconName。
    // 更正一条旧断言：原注释写"系统自带确认弹窗"——Apple 文档只说结果经 completionHandler 回报，
    // 没有承诺过任何弹窗。真机上会不会弹属于**待实测**，已进验收单；不把它当既有事实写。
    // 先判 supportsAlternateIcons (文档: 只有它为 true 才允许换), 不支持就如实说明而不是静默失败。
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
            // ---- 896 新增五款: 底色与 _audit1012/mkicon.js 画位图用的那五个值逐字相同 (两处改一处就要改两处),
            //      glyph 一律用**本仓已经在别处用过**的 SF Symbol 名 —— 新造符号名在真机上可能整个画不出来,
            //      而预览画不出白色图形只剩一块纯色方片的图标, 用户会以为 App 坏了。
            IconOption(id: "AppIcon-Home", name: "家门", glyph: "house.fill",
                       bg: [Color(hex: 0x2C5AA0), Color(hex: 0x2C5AA0)]),
            IconOption(id: "AppIcon-Bell", name: "警报", glyph: "bell.fill",
                       bg: [Color(hex: 0x9F1239), Color(hex: 0x9F1239)]),
            IconOption(id: "AppIcon-Pin", name: "定位", glyph: "location.fill",
                       bg: [Color(hex: 0x0E7490), Color(hex: 0x0E7490)]),
            IconOption(id: "AppIcon-Guard", name: "门盾", glyph: "lock.shield.fill",
                       bg: [Color(hex: 0x4B2E83), Color(hex: 0x4B2E83)]),
            IconOption(id: "AppIcon-Heart", name: "心记", glyph: "heart.fill",
                       bg: [Color(hex: 0x7C3AED), Color(hex: 0x7C3AED)]),
        ]
    }
    private var iconPickerRow: some View {
        // 896: 四款→九款之后这一排装不下了 (9×48 + 间距 ≈ 560pt, 远超 iPhone 宽度), 所以从
        // "标题在左、图排在右的一行"改成"标题在上、图排自适应换行"的两段式。
        // 用 LazyVGrid(adaptive) 而不是横向 ScrollView: 后者会把后几款藏在滚动区外,
        // 用户不知道自己有九款可选 —— 换肤这种"看一眼才想换"的界面不该先藏起来。
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("App 图标")
                .vkFont(.body)
                .foregroundStyle(DS.Palette.text)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: DS.Space.m)],
                      alignment: .leading, spacing: DS.Space.m) {
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
                                    // onSem 而非 .white: 角标底是 DS.Palette.ok, 它在深色档是浅绿 4ADE80,
                                    // 纯白压上去只有 1.74:1 (机检断言在 tools/contrast.js)。
                                    // 两层符号 (勾/圆盘) 谁吃第一色未实测, 已进验收单 — 两种顺序这里都可读。
                                    .foregroundStyle(DS.Palette.onSem, DS.Palette.ok)
                                    .offset(x: 4, y: 4)
                            }
                        }
                        .accessibilityLabel(currentIcon == opt.id ? "当前图标 \(opt.name)" : "切换为\(opt.name)图标")
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
        }
        .vkFont(.body)
        .foregroundStyle(DS.Palette.text)
    }

    /// 887 备选图标: 八套备选集 (Ring/Key/Shield + 896 新增的 Home/Bell/Pin/Guard/Heart) 均已含
    /// dark/tinted 变体 (App/Assets.xcassets/*.appiconset)，系统深浅与染色两种渲染模式下各取对应变体。
    /// ⚠ 新增五款的 tinted 档是"底板去色提亮 + 白色图形"这种**单色剪影**画法 (与既有四款同一制式)，
    ///    系统在该档下会不会再自行套一层染色只有真机能定论 —— 未证实, 已进验收单。
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
                          "将主题、品牌色、布局密度、圆角、高对比皮肤、周起始日、凭证行高、时间线行距、指标位、纹理与每日一句话重置为默认值（素颜模式与 App 图标不动），不影响任何门锁数据。确定恢复吗？",
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

    // ---------- 733 告警音分级 + 963 每晚状态确认 ----------
    // 三枚开关全部默认关: 一条每天定时响的通知和一个会在告警时出声的 App,
    // 必须由用户明确点过才成立 —— 关着的开关也要看得出"它现在不响"。
    private var alertToneSection: some View {
        Section {
            VariantToggle("告警提示音 (低电单音)", isOn: Binding(
                get: { DB.store.getBool("kf_alert_tone") },
                set: { app.setUnlockOption("kf_alert_tone", $0) }))
            Text("只在低电告警**到达**那一刻响一声 (两档滞回各一次, 与那条本地通知同一时机)。总开关关掉, 下面这一档也不会响。")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            // 733 胁迫档: 与 390/391 的既有不变量直接相冲 —— 那两档靠"反馈与真解锁一致"才不被看出来,
            // 而三声急促音恰恰是胁迫放行当场的一个可听破绽。所以它不从属于总开关, 单独一刀 + 默认关 + 写明风险。
            VariantToggle("胁迫告警三音 (有风险, 默认关)", isOn: Binding(
                get: { DB.store.getBool("kf_duress_tone") },
                set: { app.setUnlockOption("kf_duress_tone", $0) }))
                .disabled(!DB.store.getBool("kf_alert_tone"))
            if DB.store.getBool("kf_alert_tone") {
                // 2026-10-14 走查: 这条是 `"…" + "…"` 拼的 ⇒ Text 不解析 Markdown, 屏上会出现
                // `**不一样**`。改走 mdText。
                mdText("⚠ 打开后, 用胁迫口令放行的那一刻会响三声, 和正常开锁**不一样** —— 站在旁边的人听得出来。"
                     + "本 App 的胁迫通道原本刻意做得与真解锁一模一样, 这一开关是主动放弃那层掩护去换\"我能听见告警\"。只想留痕不要声音, 就让它关着。")   // 390/391 的胁迫通道原本刻意做
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 963 每晚状态确认: 与 1031 免扰 (22–08) 的冲突是结构性的, 界面直接说谁赢。
            VariantToggle("每晚状态确认提醒", isOn: Binding(
                get: { StatusCheckNotice.on },
                set: { v in
                    app.setUnlockOption("kf_status_checkin", v)
                    // 回执说的是"排上了没有", 不是"开关动了没有" —— 免扰挡下的那一支必须当场看得见
                    if !v {
                        app.showToast("已撤销每晚确认")
                    } else if StatusCheckNotice.sync() {
                        app.showToast("已排上: 每天 \(StatusCheckNotice.hour):00 一条本地通知")
                    } else {
                        app.showToast("开关已打开, 但这条没排上 —— 免扰时段挡下, 或台账里还没有锁")
                    }
                }))
            Picker("确认时点", selection: Binding(
                get: { StatusCheckNotice.hour },
                set: { v in
                    app.setUnlockOption("kf_status_checkin_hour", v)
                    StatusCheckNotice.sync()
                })) {
                Text("20:00").tag(20)
                Text("21:00").tag(21)
                Text("22:00").tag(22)
            }
            .pickerStyle(.menu)
            .disabled(!StatusCheckNotice.on)
            // 2026-10-14 走查: 三元表达式的结果是 String ⇒ Text 不解析 Markdown, 命中免扰时
            // 屏上会出现 `**没有排上**`。改走 mdText。
            mdText(StatusCheckNotice.on && CareSchedule.quietOn && StatusCheckNotice.insideQuiet(StatusCheckNotice.hour)
                 ? "现在这条**没有排上**: 免扰时段覆盖 22–08, 你选的 \(StatusCheckNotice.hour):00 正落在里面, 按\"免扰优先\"不排。把免扰关掉, 或把时点挪到 20:00/21:00 才会响。"   // 1031 现在这条
                 : "到点给一条本地通知, 写的是台账里数得出的数 (几把锁、今天连上过几把)。通知不联网不连锁, 锁的真实状态要到场连上才知道。")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("告警声音与定时确认")
        }
    }

    // ---------- 关于 ----------
    private var aboutSection: some View {
        Section {
            // 机械计数器 (idea 1006): 累计开锁次数
            HStack(spacing: DS.Space.s) {
                Text("累计开锁").foregroundStyle(DS.Palette.text)
                Spacer(minLength: DS.Space.m)
                MechCounter(value: Milestones.unlockTotal)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("累计开锁 \(Milestones.unlockTotal) 次")
            // 279 版本信息行: 原句列的"SQLite 版本"在本工程不存在 (库体是 UserDefaults + Keychain,
            // 见 §217 那条 ⛔ 不适用)，所以这里给的是**真实存在**的四项而不是照抄原句。
            HStack(spacing: DS.Space.s) {
                Text("构建与主题").foregroundStyle(DS.Palette.text)
                Spacer(minLength: DS.Space.m)
                // 2026-10-13 run 63: 原来把 infoDictionary 取值 + 三段拼接全内联进 Text, 报 type-check 超时。
                let buildVer = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?"
                let themeCount = DS.Palette.themeTable.count
                Text("build " + buildVer + " · " + String(themeCount) + " 套主题")   // 279 套主题
                    .vkFont(.footnote.monospacedDigit())
                    .foregroundStyle(DS.Palette.textSub)
            }
            .accessibilityElement(children: .combine)
            // 版本彩蛋 (idea 298): 连点 10 次展示构建信息
            Button {
                versionTaps += 1
                if versionTaps >= 10, !eggShown {
                    eggShown = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } label: {
                HStack(spacing: DS.Space.s) {
                    Text("当前版本").foregroundStyle(DS.Palette.text)
                    Spacer(minLength: DS.Space.m)
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                        .foregroundStyle(DS.Palette.textSub)
                        .monospacedDigit()
                }
            }
            // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 命中高仅约 16.5pt (< 44)。
            // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
            if eggShown {
                LabeledRow("构建", Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")
                LabeledRow("遥测", "无 · 全程离线")
            }
        } footer: {
            Text(aboutFooterText)
                .vkFont(.caption)
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
        HStack(spacing: DS.Space.xs) {
            ForEach(Array(String(value).enumerated()), id: \.offset) { _, ch in
                Text(String(ch))
                    .vkFont(.subheadline, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(DS.Palette.text)
                    .frame(width: 22)
                    // @layout-allow VK豁免 刻度点: 22pt 宽的控制零件，不是容器
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

    var body: some View { vkBody.destined(.defend) }
    var vkBody: some View {
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
                    .vkFont(.footnote)
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
        .variantList()
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
                let cal = WeekCal.gregorian
                let sHMS = cal.dateComponents([.hour, .minute, .second], from: fromTime)
                let eHMS = cal.dateComponents([.hour, .minute, .second], from: toTime)
                let s = ((sHMS.hour ?? 0) * 3600 + (sHMS.minute ?? 0) * 60 + (sHMS.second ?? 0)) / 2
                let e = ((eHMS.hour ?? 0) * 3600 + (eHMS.minute ?? 0) * 60 + (eHMS.second ?? 0)) / 2
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

    var body: some View { vkBody.destined(.tailgate) }
    var vkBody: some View {
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
        .variantList()
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
    @EnvironmentObject var app: AppState
    @State private var switching = false      // 拍板 #2: cmd20 下发中, 防止连点重复改锁端策略
    private var isOtp: Bool { mode == "otp" }

    var body: some View { vkBody.destined(.safemodeIntro) }
    var vkBody: some View {
        Form {
            if isOtp {
                Section("临时密码 (ZOTP) 介绍") {
                    Text("ZOTP 是临时开锁密码：6 位数字密码，每 30 分钟更换一次，同一窗口内最多 99 个。").vkFont(.footnote)
                    Text("生成前请先校准门锁时间 (0E)，否则手机与锁时间窗不同步会导致密码不匹配。").vkFont(.footnote)
                }
            } else {
                Section("门锁的安全模式介绍") {
                    Text("门锁的安全模式分为A模式和B模式").vkFont(.subheadline)
                    Text("A模式：只需要单一方式（密码／指纹／手机）验证通过就可以开锁").vkFont(.footnote)
                    Text("B模式：需要用两种不同方式（指纹+密码／指纹+手机／手机+密码）组合验证通过才可开锁").vkFont(.footnote)
                }
                Section("怎么设置门锁的安全模式？") {
                    Text("当前模式在「锁信息名片」(设备页) 读取后显示。本 App 只给变严的方向 (A→B)；"
                         + "要放宽回 A 模式请在门锁键盘上操作或联系管理员。").vkFont(.footnote)
                    // 拍板 #2 (第六十六批): 给切换入口, 但只允许更严方向。
                    // 不给 B→A 的理由写在这: 放宽验证会让"两种组合验证"这条既有保护一指之间消失,
                    // 而锁端不记录是谁改的 —— 本机审计只会留下一条无法解释的降级。
                    if app.status == nil {
                        Text("还没读到锁状态 —— 先在设备页读一次锁信息，这里才会出现切换按钮。")
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                    } else if app.status?.verifyMode == 1 {
                        Text("当前已是 B 模式（双验）。本 App 不提供改回 A 模式的入口。")
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.ok)
                    } else {
                        Button(switching ? "切换中…" : "切换到 B 模式（双验，更严）(cmd 20)") {
                            confirmDestructive("切换到 B 模式（双验）",
                                "锁端将要求两种不同方式组合验证才能开锁 (cmd 20)。这一步会改变锁的验证策略："
                                + "切换后请先实测一次组合方式能开锁，再让其他人使用。本 App 不提供改回 A 模式的入口。",
                                confirmTitle: "切到 B 模式") {
                                switching = true
                                Task { await switchToDoubleVerify() }
                            }
                        }
                        .vkFont(.subheadline, weight: .medium)
                        .foregroundStyle(DS.Palette.accentText)
                        .disabled(switching)
                        .frame(minHeight: DS.Hit.min)
                    }
                }
            }
        }
        .navigationTitle(isOtp ? "临时密码介绍" : "安全模式说明")
        .variantList()
        .dsScreenBackground()
    }

    /// 拍板 #2: 下发 cmd20 后**必须回读校验** —— rc=0 只说明锁收了命令, 不代表验证策略真的改了。
    /// 没回读就报"已切换"是拿猜测给用户信心; 回读到不是 B 模式就如实说"未生效", 让人重读再试。
    private func switchToDoubleVerify() async {
        defer { switching = false }
        do {
            try await app.lock.setValidationMode(true)
            // 留存口径：这个开关**以锁端为准**，本机不另存一份"我以为的状态"——
            // 下面立刻回读校验，读到不是 B 模式就如实报"未生效"。存一份本地副本只会造出第二个真相。
            // 这条是"下发后的回读校验" (拍板 #2), 属于用户刚做的手动动作; 不传 manual:true 的话
            // 静默排查档会把回读一起吞掉, 于是界面永远报"未生效" —— 那是把闸接错地方。
            await app.refreshStatusQuietly(manual: true)
            if app.status?.verifyMode == 1 {
                app.lock.log("warn", "安全模式已切换 A→B 双验 (cmd20, 回读确认 verifyMode=1)")
                app.showToast("已切到 B 模式（双验），锁状态已回读确认")
            } else {
                app.lock.log("warn", "cmd20 已下发但回读 verifyMode 仍不是 B —— 视为未生效 (不报成功)")
                app.showToast("命令已下发，但回读显示未生效 —— 请重读锁信息再试一次")
            }
        } catch {
            app.lock.log("warn", "切换安全模式失败 (cmd20): \(error.localizedDescription)")
            app.showToast("切换失败：命令没有成功下发，锁仍按原模式验证")
        }
    }
}