// 设置 Tab (settings 页) — 门锁管理/安全/家人与钥匙/网关/固件/备份/应用锁/外观/关于
// 分组原则: 同一心智模型的动作放同一 Section, 不再出现"一个 Section 只有一行"的碎片。
// 所有破坏性动作统一走 confirmDestructive (全局助手), 本文件不自带弹窗实现。
import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @State private var showMembers = false
    @State private var showGateway = false
    @State private var showDeviceInfo = false
    @State private var showBackup = false
    @State private var showAdd = false
    /// 2026-10-17 安卓版: 把当前锁的开锁凭证渲染成二维码 (扫码导入, 之后不再需要)
    @State private var shareLock: Keychain?
    // 2026-10-15 走查: 这两个目标页也自带 NavigationStack, 同样只能走 sheet
    // 包14: 27 设置内搜索 — 顶部搜索框过滤全部设置项
    @State private var query = ""
    // 乱源治理第 4 批: 五组筛选的当前组。nil = 全部 (默认态与分组之前完全一样)。
    // 刻意是视图内 @State 而不是落盘键: 记住"上次只看外观与辅助"会让下次进来少看见一堆设置，
    // 那是把筛选变成隐藏 —— 页内搜索 (§27) 同样是会话态，两处口径一致。
    @State private var groupFilter: SettingsGroup?
    // 与门锁通信中的忙碌态 — 防止连点重复下发指令
    @State private var settingMute = false
    /// 2026-10-28：通知权限只在进页时读一次（`NotifyAuth.status` 是同步阻塞读，
    /// 不能放在 body 里每次重算都调，否则设置页每次刷新都卡最多 2 秒）。
    @State private var notifyLabel = ""
    @State private var notifyOff = false
    @State private var clearingPwd = false
    // 包18: 版本彩蛋 (298) / VoiceOver 致意 (1049)
    @State private var eggShown = false
    @State private var versionTaps = 0

    /// 831 NEW 角标: 新功能首见, 进入一次即消 (状态存偏好表 kf_seen_)
    /// "已看过"的落库放在 destination 的 .onAppear: 写在 ViewBuilder 里等于在构造视图时改数据,
    /// 视图被重建/预取时会反复触发, 而且 body 有副作用本来就是 SwiftUI 明确要避免的。
    @ViewBuilder
    var body: some View { vkBody.destined(.settings) }
    var vkBody: some View {
        NavigationStack {
            settingsReader
        }
        .onAppear {
            let s = NotifyAuth.status
            notifyLabel = NotifyAuth.labelFor(s)
            notifyOff = NotifyAuth.isOffFor(s)
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
            // 2026-10-27：`securitySection` 已删（纯说明无入口），见上方注释。
            if settingsSectionShown(groupFilter, .daily) { unlockSection.id(SettingsAnchor.unlock) }
            if settingsSectionShown(groupFilter, .look) { timeSection.id(SettingsAnchor.time) }
            if settingsSectionShown(groupFilter, .daily) { autoOpenSection.id(SettingsAnchor.autoOpen) }
            if settingsSectionShown(groupFilter, .keys) { familySection.id(SettingsAnchor.family) }
            if settingsSectionShown(groupFilter, .data) { toolsSection.id(SettingsAnchor.tools) }
            if settingsSectionShown(groupFilter, .data) { applockSection.id(SettingsAnchor.applock) }
            if settingsSectionShown(groupFilter, .look) { appearanceSection.id(SettingsAnchor.appearance) }
            if settingsSectionShown(groupFilter, .help) { aboutSection.id(SettingsAnchor.about) }
        }
        .navigationTitle("设置")
        .variantList()
        .dsScreenBackground()
        .sheet(isPresented: $showMembers) { MembersView() }
        .sheet(isPresented: $showGateway) { GatewayView() }
        .sheet(isPresented: $showDeviceInfo) { DeviceInfoView() }
        .sheet(isPresented: $showBackup) { BackupView() }
        .sheet(item: $shareLock) { ShareToAndroidView(kc: $0) }
        .sheet(isPresented: $showAdd) { AddDeviceView() }
        // 为什么不用 navigationDestination(isPresented:): 全仓无先例, 而 sheet+NavigationStack 与
        // 与 showDiag 那一段逐字同构 —— 无编译器的机器上, 复用已验证的写法是唯一稳的取向。
        .task { landPendingCare(app.pendingCare) }              // 1013: 与上两行同构
        .onChange(of: app.pendingCare) { _, m in landPendingCare(m) }
        // 2026-10-27 审核修复 (AUDIT-B 2.4)：`pendingDiag` 原先 1 处写、0 处读 ——
        // 长按菜单的「这台锁的诊断」点了没反应。与上面 pendingCare 同一条路由形态。
        .task { landPendingDiag(app.pendingDiag) }
        .onChange(of: app.pendingDiag) { _, m in landPendingDiag(m) }
        // 2026-10-15: 设置 Tab 栈内子页 (安全中心 → 本机密码 / 销毁) 的"去设置…"落点, 同一条形态
        .task { landPendingFocus(app.pendingSettingsFocus) }
        .onChange(of: app.pendingSettingsFocus) { _, f in landPendingFocus(f) }
    }

    /// 587 落点: 切到本条记录所属锁。
    ///
    /// 2026-10-27 审核修复 (AUDIT-B 2.4)：这里原有一行注释「再推诊断页」，
    /// 而**诊断页已随十三轮精简整族删除**，那个落点函数也一起没了 ——
    /// 于是 `pendingDiag` 只剩写入、没有消费者，长按菜单那颗按钮点了没反应。
    /// 现在如实落到**设备页该锁**（电量、状态、快捷操作都在那里），
    /// 与 `landPendingCare` 同构；不再假装能跳到已不存在的页面。
    private func landPendingDiag(_ m: String?) {
        guard let m, !m.isEmpty else { return }
        app.pendingDiag = nil
        if m != app.currentMac { app.select(m) }
        app.requestRoute(.device)
    }


    /// 1013 落点: 切到通知里那台锁。
    /// 维护与保养页已随大删波4移除, 所以落到**设备页该锁** —— 电量、低电横幅、换电指引都在那里,
    /// 通知说的事 (该换电池了) 在设备页能就地看到, 不再指一个不存在的页面。
    private func landPendingCare(_ m: String?) {
        guard let m, !m.isEmpty else { return }
        app.pendingCare = nil
        if m != app.currentMac { app.select(m) }
        app.requestRoute(.device)
    }

    /// 2026-10-15 落点: 设置 Tab **栈内**子页带回来的"到了之后开什么"。
    /// 与上面两条同构 —— 那边带 mac、这里带一个落点名, 都是"值挂着 → 设置页收到 → 开面 → 清空"。
    /// 安全中心那两枚按钮原先只写 `app.tabSelection = 3`, 而它们就在设置 Tab 下, 等于空转。
    /// 2026-10-15 §4.2 补一条: **被安全中心 sheet 盖住时不许消费**。这一页的所有落点 (备份 sheet /
    /// 密码 alert) 都挂在被盖住的那层 List 上, 当场开等于开给一个看不见的界面看; 而值一清就再也
    /// 没人重试。改成"盖着就留着" —— 两条路都以"消费即清空"收尾, 所以真机上是开一次还是等人回来才开一次, 都会且只会开一次。
    private func landPendingFocus(_ f: String?) {
        guard let f, !f.isEmpty else { return }
        app.pendingSettingsFocus = nil
        switch f {
        case "backup":
            // 400 销毁前备份闸: 直接开「备份与恢复」(备份工作室在它里面)
            showBackup = true
        case "passcode":
            // 396 随机键位的前提: 直接拉起「设置本机密码」流程
            setPasscode()
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
        case lock, security, unlock, time, autoOpen, family
        case tools, drill, applock, appearance, memory, alertTone, about

        var group: SettingsGroup {
            switch self {
            case .lock, .unlock, .autoOpen, .alertTone: return .daily
            case .security, .tools, .drill, .applock: return .data
            case .family: return .keys
            case .time, .appearance: return .look
            case .memory, .about: return .help
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
            SearchHit(id: "s.mute", title: "静音模式", icon: "speaker.slash", anchor: .lock),
            SearchHit(id: "s.synctime", title: "校准门锁时间", icon: "clock.arrow.circlepath", anchor: .lock),
            // 2026-10-26: 今日新增的四项补进搜索索引 —— 入口在门锁段/工具段里，但索引此前没登记，
            // 于是搜「布防」「手机钥匙」「固件升级」「只读」都是零结果。
            //
            // ⚠ 这四个页面是 NavigationLink push 进去的，SearchHit 只能"滚动定位"到某一节，
            //    没有程序化 push 的入口（设置页用的是 NavigationLink 声明式，不是 path 栈）。
            //    所以这里只给 anchor（保证滚到对应段，用户看到那一行再点），
            //    **不给 go** —— 给一个空的 go 会让人以为点搜索就直接进页面，实际只滚动。
            SearchHit(id: "s.defend", title: "布防 (时段内否决自动开锁)", icon: "shield.lefthalf.filled", anchor: .lock),
            SearchHit(id: "s.mobilekey", title: "手机钥匙 (给成员发数字钥匙)", icon: "iphone.gen3.badge.key", anchor: .family),
            SearchHit(id: "s.dfu", title: "固件升级 (Nordic DFU, 在「家人与钥匙」段)", icon: "arrow.up.circle", anchor: .family),
            SearchHit(id: "s.trialguard", title: "只读试验模式 (真机排障只看不改)", icon: "eye.slash", anchor: .tools),
            // 2026-10-28 删除：`s.safemode`「门锁安全模式」—— 那个 Section 已于 81c1432 删除
            // （纯说明无入口），搜索项却留着，点进去滚到 unlock 段也没有任何「安全模式」内容。
            SearchHit(id: "s.unlockopt", title: "开锁偏好 (按住确认/围栏/圆盘尺寸)", icon: "hand.draw", anchor: .unlock),
            SearchHit(id: "s.autoopen", title: "靠近自动开锁 (走近自动开门)", icon: "person.walk", anchor: .autoOpen),
            SearchHit(id: "s.members", title: "成员管理", icon: "person.2") { showMembers = true },
            SearchHit(id: "s.gateway", title: "智能网关", icon: "antenna.radiowaves.left.and.right") { showGateway = true },
            SearchHit(id: "s.backup", title: "备份与恢复", icon: "externaldrive") { showBackup = true },
            // 2026-10-28 界面审核修复：删掉重复的 `s.backupstudio` 搜索项 ——
            // 它和上一行 `s.backup` **标题相同、动作相同**（都只是 `showBackup = true`），
            // 用户搜「备份」会看到两条一模一样的结果，点了做同一件事。
            // 当初大概是给「备份工作室」单独留个入口，但那一页从未独立存在过。
            SearchHit(id: "s.applock", title: "本机数据保护 (应用锁)", icon: "lock.shield", anchor: .applock),
            SearchHit(id: "s.appearance", title: "外观 (主题/品牌色/密度)", icon: "paintbrush", anchor: .appearance),
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
    private var lockSection: some View {
        Section("门锁") {
            // 分享给安卓: 只在有当前锁时出现。入口放在门锁段而不是设备管理页 ——
            // 这张码是"这一把锁"的凭证, 而设备管理讲的是锁与锁之间的关系。
            if let kc = app.current {
                Button { shareLock = kc } label: {
                    Label("分享给安卓 (扫码开锁)", systemImage: "qrcode")
                }
            }
            if app.current == nil {
                // 814 的 1/3 = 引导次序 (连锁→录凭证→开门), 这里停在"连锁"前一步;
                // 此前这里只有一个裸「添加设备」按钮, 空态组件在设置页零消费。
                GuidedEmptyView(systemImage: "lock",
                                title: "还没有添加门锁",
                                message: "添加后这一段才会出现锁档案、静音、校时与删除等设置。三步走: 连锁 → 录凭证 → 开门。",
                                step: 1, stepTotal: 3,
                                primaryTitle: "添加设备",
                                primary: { showAdd = true },
                                )
                    .listRowInsets(EdgeInsets())
            } else {
                NavigationLink("锁档案 (昵称/符号/色标/备注)") { LockProfileView() }
                note("靠近时先连上，开锁少等一两秒；成功率只在本机统计。")
                Button("锁信息名片") { showDeviceInfo = true }
                note("型号、固件、电量与绑定时间的汇总卡。")
                // 2026-10-28 补入口（**真缺口**）：`SafemodeIntroView` 只在 QuickPool 里以
                // `mode: "otp"` 构造过一次 —— `mode: "safe"` 那半边（A/B 说明 + 「切换到 B 模式」按钮）
                // **永远不可达**。而 `setValidationMode(true)` 全仓只有它内部一处调用。
                // 于是 APK 的 `page-setsafemode`（设置安全模式 A/B）在 iOS 上虽然有实现、却没入口。
                NavigationLink("安全模式 (A/B 双验)") { SafemodeIntroView() }
                note("单次验证还是两种方式组合验证；本 App 只提供 A→B 变严的方向。")
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
                if canTailgate {
                    NavigationLink("防尾随入室") { TailgateView() }
                    note("开门后短时间内刷同一凭证才告警。")
                }
                // 包9 布防 (cmd25): 原版 APK 有、iOS 此前只有构造器没有入口。
                // 门禁用 canDefend (KX / V1_Pro 家族)，与 APK 的 canDefend 白名单同源。
                if canDefend {
                    NavigationLink {
                        DefendView()
                    } label: {
                        HStack(spacing: DS.Space.s) {
                            Text("布防")
                            Spacer(minLength: 0)
                            Text(DefendKit.summary(DB.defend(mac)))
                                .vkFont(.caption)
                                .foregroundStyle(DefendKit.isActive(DB.defend(mac))
                                                 ? DS.Palette.ok : DS.Palette.textSub)
                        }
                    }
                    note("时段内一票否决自动开锁；布防期间靠近门锁不会自动开门。")
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
    // 2026-10-28 修复：原来只读本地 kf_mute_ —— **换手机 / 别人在锁上改过之后，
    // 这个开关显示的状态就和锁端不一致（开关会撒谎）**。
    // APK 的做法是用 03 回包的 getSoundVolumn() > 0 反推开关（main.js 三处）。
    // iOS 的 StatusParser.swift:82 早就解析了 KLV#14 soundVolumn，只是零消费。
    // 现在：读得到锁端状态就用锁端（1 = 静音，0 = 有声，与 cmd18 载荷语义一致），
    // 读不到才回落本地记录。
    private var muteStored: Bool {
        if let s = app.status { return s.soundVolumn > 0 }
        return DB.store.getBool("kf_mute_" + mac)
    }

    /// 2026-10-14: 设置项小字注解。口径"简洁明了" —— 只说用户决策需要的那一句
    /// (这一项是干什么的 / 要不要连锁 / 有什么后果), 不铺陈实现细节 (那些留在注释里)。
    /// 与 deviceManageSection 既有的 caption2 小字同一族, 这里收成一个 helper 免得每处重抄三行修饰。
    private func note(_ s: String) -> some View {
        Text(s)
            .vkFont(.caption)
            .foregroundStyle(DS.Palette.textSub)
            .fixedSize(horizontal: false, vertical: true)
    }
    private var canTailgate: Bool { PidMap.canTailgate(app.current?.pid ?? 0, fw: app.current?.fw) }
    private var canDefend: Bool { PidMap.canDefend(app.current?.pid ?? 0) }
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
            // 2026-10-28 修复（**数据丢失级**）：原来写 `DB.saveLedger(m, Ledger())` ——
            // `Ledger()` 的两个字段都是空数组，`fps` 也一起被清空，而同行注释还写着「指纹保留」。
            // 用户点「清空密码」，指纹台账**连带消失**（锁端指纹仍能开锁，本机档案没了）。
            // 文案只说「会作废所有成员的密码」，没有任何一句预告指纹会没。
            var keepLedger = DB.ledger(m)
            keepLedger.pwds = []              // 只清密码
            DB.saveLedger(m, keepLedger)      // 指纹（fps）原样保留
            app.showToast("清空密码成功")
        } catch { app.showToast("清空失败: \(error.localizedDescription)") }
    }

    private func deleteDevice() {
        guard let kc = app.current else { return }
        // 109 删除冷静期: 后果要可核对 (逐类计数), 且必须键入锁名才放行 —— 旧写法只有一次"确定吗"
        let pws = DB.listPwds(kc.mac).count
        let fps = DB.listFps(kc.mac).count
        let recs = DB.readLogs(kc.mac).count   // 109: 记录缓存 (kf_logcache_) 也随设备删除, 计数一并预告
        let name = LockArchive.displayName(kc)
        var consequence = "将删除本机的钥匙串与该门锁全部本地数据 (锁端密钥不变)。"
        if pws + fps + recs > 0 {
        // 2026-10-28：删掉「待下发 N 项 / 回收站 N 条」—— 这两套功能都不存在
        // （全仓无队列类型、无回收站存储），原来只是硬编码 0 凑文案。
            consequence += " 连带删除: 密码台账 \(pws) 条、指纹台账 \(fps) 条、本机缓存的开门记录 \(recs) 条。"
        }
        consequence += " 删除后若未做过备份将无法找回。"
        confirmDestructiveTyped("删除设备", consequence, requireWord: name, confirmTitle: "确认删除") {
            DB.removeDevice(kc.mac)
            app.loadDevices()
            app.showToast("已删除「\(name)」")
        }
    }

    // 2026-10-27 界面审核修复：**删掉 `Section("安全")`** ——
    // 它只有一句悬空说明「单次 / 双重验证：决定开一道锁还是两道」，
    // 而这一节里**没有任何可操作项**（真正的切换入口在「安全模式说明」那一页）。
    // 用户读到这句话却在这一节里找不到能点的东西 —— 说明与控件被拆到两处，是结构错位。
    // 这句话已挪进 unlockSection 的 footer（验证模式与开锁动作本来就是一回事）。

    // ---------- 开锁 (包1: 按住确认/围栏/自动重试/圆盘尺寸) ----------
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
                        // 2026-10-28 删除：这两档**从未实现** —— `UnlockPrefs.modes = ["hold"]`，
                        // 而 `mode` 的实现是 `modes.contains(v) ? v : "hold"` ⇒ 选什么都回弹到 hold；
                        // `triple` / `charge` 在后台零出现（UnlockDial 没有任何对应手势处理）。
                        // 留着等于给用户两个永远选不上、选了也不生效的假选项。
            }
                        // 2026-10-28：原说明文字讲的是两个不存在的档位，随档位一起删。
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
            // 2026-10-27：把原「安全」节的悬空说明并进来 —— 验证模式与开锁动作是一回事，
            // 拆成两节只会让人在「安全」里找不到能点的东西。
            Text("单次 / 双重验证（A / B 模式）：决定开一道锁还是两道。这是**锁端策略**，当前模式在「锁信息名片」读取后显示；本 App 只提供变严的入口（A→B），要放宽请到门锁键盘操作。")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
            Text("按住圆盘时长 (默认 0.9s，可在上方「外观」里 0.4–1.6s 自定) 或上滑触发开锁；关闭「按住确认」后退回轻点直开 (适合单手与 VoiceOver)。误触围栏开启后需先从圆盘边缘拖到中心再执行开锁手势。")
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
    /// 家人与钥匙 + 凭证整理 —— **两个独立的 Section**。
    ///
    /// 2026-10-27 截图核对修复：原先把这两个 Section 包在 `VStack(spacing: 0)` 里。
    /// `Section` 只在 `List`/`Form` 的**直接子级**才有分组语义 —— 被 VStack 包住后，
    /// 整个 VStack 变成 List 的一行，里面的 Section 退化成普通容器，于是：
    ///   · header/footer 不再吸附在组头组尾，而是居中夹在行之间（截图里「家人与钥匙」居中）
    ///   · 行与 footer 正文垂直重叠（「手机钥匙」压住「访客是本地虚拟分组…」）
    ///   · 两节内容混成一坨（「凭证整理」跑到列表行中间）
    /// 现在拆成两个并列的 Section（@ViewBuilder 允许一个属性返回多个 Section）。
    @ViewBuilder
    private var familySection: some View {
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
    @ViewBuilder
    private var memberFamilyRows: some View {
        Button { showMembers = true } label: { Label("成员管理（含成员中心）", systemImage: "person.2") }
        // 包9 固件升级 (cmd22 + Nordic DFU): 原版 APK 有完整 OTA, iOS 此前把 DFU 逻辑整体删掉只剩包解析。
        // 门禁用 canDeviceUpgrade (与 APK 同源), 防网关/钥匙串误入。
        if PidMap.canDeviceUpgrade(app.current?.pid ?? 0) {
            NavigationLink {
                DFUView()
            } label: {
                Label("固件升级", systemImage: "arrow.up.circle")
            }
        }
        // 包9 手机钥匙 (41/43/44 的成员侧): 与「蓝牙钥匙串」并列 ——
        // 前者是把钥匙写进随身硬件, 后者是把 ekey 发给成员的手机, 归属对象不同, 不能合并成一条。
        NavigationLink {
            MobileKeyView()
        } label: {
            Label("手机钥匙", systemImage: "iphone.gen3.badge.key")
        }
        // 2026-10-28 补：`HardwareService` 的蓝牙钥匙串（ZKBBV1）整套能力早就写好了 ——
        // 5 个服务方法 + 4 个 CRUD + 备份集成都齐，但**零 UI 入口**。
        // 而上面「手机钥匙」的 footer 还在对用户说「与「蓝牙钥匙串」不同：钥匙串是随身硬件」，
        // 用户会去找那个入口 —— 找不到。现在补上（与手机钥匙并列，两者归属对象不同：
        // 一个写进实体硬件，一个发给成员手机，不能合并）。
        NavigationLink {
            DongleView()
        } label: {
            Label("蓝牙钥匙串", systemImage: "key.horizontal")
        }
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
            // 2026-10-26 精简：回收站保留天数设置已删（回收站整套移除）。
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
            Text("「成员别名显示」开着时, 有备注名的成员优先显示备注 (如「老妈」), 否则显示称呼。\n版本快照只在本机留存; 需锁端生效的操作必须到场连接后另行执行，本 App 不排队。")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // ---------- 工具 (原网关/固件/备份/诊断 四个单行 Section 合并) ----------
    private var toolsSection: some View {
        Section("工具") {
            Button { showBackup = true } label: { Label("备份与恢复", systemImage: "externaldrive") }
            // 2026-10-28 补：`GatewayView` 此前**只有搜索索引能到达** ——
            // `showGateway` 的唯一写点是 `s.gateway` 那条 SearchHit（SettingsView:251），
            // 设置列表里没有可见行。用户不搜「智能网关」就永远看不到配网/状态/重启三个能力。
            Button { showGateway = true } label: { Label("智能网关", systemImage: "antenna.radiowaves.left.and.right") }
            // 2026-10-28 补：通知权限状态此前**无处可看**（`NotifyAuthBox` 零调用）。
            // 到期提醒是这个 App 唯一的主动提醒出口，权限关了却没人告诉用户，等于静默失效。
            if notifyOff {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: DS.Space.s) {
                        Label("通知权限", systemImage: "bell.slash")
                        Spacer(minLength: 0)
                        Text(notifyLabel + " · 到期提醒不会送达")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.danger)
                    }
                }
            }
            // 2026-10-28 补入口：`TrialGuard.set(true)` 全仓零调用 —— 这道只读护栏
            // 永远打不开（`LockService` 里的 assertReadOnly 判据一直在，但没人能开）。
            // 而设置页搜索索引 :236 还写着「只读试验模式 (真机排障只看不改)」—— 搜得到、开不了。
            // 按 TrialGuardKit 的设计取舍放在「工具」这一段（低频/实验室入口）。
            Button {
                if TrialGuard.isOn {
                    TrialGuard.set(false)
                    app.showToast("只读试验模式已关闭")
                } else {
                    confirmDestructive("开启只读试验模式", TrialGuard.warning, confirmTitle: "开启") {
                        TrialGuard.set(true)
                        app.showToast("只读试验模式已开启：写入类操作全部停用")
                    }
                }
            } label: {
                HStack(spacing: DS.Space.s) {
                    Label("只读试验模式", systemImage: "eye.slash")
                    Spacer(minLength: 0)
                    Text(TrialGuard.isOn ? "已开启" : "关闭")
                        .vkFont(.caption)
                        .foregroundStyle(TrialGuard.isOn ? DS.Palette.danger : DS.Palette.textSub)
                }
            }
        }
    }
    // ---------- 本机数据保护 ----------
    private var applockSection: some View {
        Section {
            if DB.hasPasscode() {
                Button("更改本机密码") { setPasscode() }
                Button(DB.hasDuressCode() ? "更改胁迫码" : "设置胁迫码") { setDuressCode() }
                Button("关闭本机密码", role: .destructive) { disablePasscode() }
            } else {
                Button("设置本机密码") { setPasscode() }
                note("4 位以上数字。设置后，**冷启动** App 需要输入它才能进入。")
            }
        } header: {
            Text("应用锁")
        } footer: {
            Text(DB.hasDuressCode()
                 ? "冷启动需输密码。胁迫码已设置：被胁迫时输入它会进入空壳模式 —— 门能开，但凭证与记录显示为空。"
                 : "冷启动需输密码。可另设一个胁迫码：被胁迫时输入它，App 进入空壳模式（门能开、数据看不见），不报警不暴露。")
        }
    }

    /// 设置胁迫码。已有密码时先验证原密码（与改密码同一纪律）。
    private func setDuressCode() {
        promptOldPasscode { ok in
            guard ok else { return }
            let alert = UIAlertController(
                title: DB.hasDuressCode() ? "更改胁迫码" : "设置胁迫码",
                message: "被胁迫时输入这个码，App 进入空壳模式：门能开，但凭证与记录显示为空。\n\n⚠ 必须与正常密码不同 —— 相同就等于把正常密码当胁迫码用。",
                preferredStyle: .alert)
            alert.addTextField { $0.isSecureTextEntry = true; $0.keyboardType = .numberPad; $0.placeholder = "4 位以上数字" }
            alert.addTextField { $0.isSecureTextEntry = true; $0.keyboardType = .numberPad; $0.placeholder = "再次输入" }
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            if DB.hasDuressCode() {
                alert.addAction(UIAlertAction(title: "清除胁迫码", style: .destructive) { _ in
                    DB.clearDuressCode()
                    app.showToast("胁迫码已清除")
                })
            }
            alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
                let f1 = alert.textFields?[0].text ?? ""
                let f2 = alert.textFields?[1].text ?? ""
                guard !f1.isEmpty, f1 == f2 else { app.showToast("两次输入不一致"); return }
                guard f1.count >= 4 else { app.showToast("需 4 位以上"); return }
                guard f1.allSatisfy({ $0.isNumber }) else { app.showToast("只能使用数字"); return }
                if DB.setDuressCode(f1) {
                    app.showToast("胁迫码已设置")
                } else {
                    app.showToast("设置失败：胁迫码不能与正常密码相同")
                }
            })
            UIApplication.topViewController()?.present(alert, animated: true)
        }
    }

    /// 关闭本机密码 = 撤掉「设置」页的入口屏障（它不拦查看明文/导出，见上方说明）
    /// 关闭本机密码 —— **必须先验证原密码**。
    /// 2026-10-27 审核修复 (AUDIT-D D-08)：原先只要点两下（确认框 + 确定）就能永久移除应用锁，
    /// 不需要知道原密码 —— 拿到解锁手机的人可以直接把保护关掉。
    private func disablePasscode() {
        promptOldPasscode { ok in
            guard ok else { return }
            confirmDestructive("关闭本机密码",
                              "关闭后，设置页不再有入口屏障。注意：查看密码明文与导出备份本来就不受本机密码约束 —— 任何拿到这台手机的人都能直接读取。确定要关闭吗？",
                              confirmTitle: "关闭保护") {
                DB.setPasscode(nil)
                app.showToast("已关闭")
            }
        }
    }

    /// 验证原密码。取消/输错都不执行后续动作。
    private func promptOldPasscode(_ then: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: "验证原密码",
                                      message: "修改或关闭本机密码前需要先验证。",
                                      preferredStyle: .alert)
        alert.addTextField { $0.isSecureTextEntry = true; $0.keyboardType = .numberPad }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in then(false) })
        alert.addAction(UIAlertAction(title: "验证", style: .default) { _ in
            let pw = alert.textFields?[0].text ?? ""
            if DB.verifyPasscode(pw) { then(true) }
            else { app.showToast("原密码不正确"); then(false) }
        })
        UIApplication.topViewController()?.present(alert, animated: true)
    }

    private func setPasscode() {
        // 2026-10-27 审核修复 (AUDIT-D D-09)：**已有密码时改密码必须先验原密码**。
        // 否则拿到解锁手机的人可以直接改成一个自己知道的密码，等于接管保护。
        if DB.hasPasscode() {
            promptOldPasscode { ok in
                guard ok else { return }
                presentSetPasscodeAlert()
            }
            return
        }
        presentSetPasscodeAlert()
    }

    private func presentSetPasscodeAlert() {
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
            app.showToast("已设置")
        })
        UIApplication.topViewController()?.present(alert, animated: true)
    }


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
            // 2026-10-27 四轮精简：素颜模式已删。
            // 最近开门条数 (idea 910): 设备页时间线长度
            Picker("最近开门条数", selection: Binding(
                get: { DB.store.getInt("kf_recent_count", 5) },
                set: { app.setRecentCount($0) })) {
                Text("3 条").tag(3)
                Text("5 条").tag(5)
                Text("10 条").tag(10)
            }
            .pickerStyle(.menu)
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
            // 2026-10-27 四轮精简：儿童友好外观预设入口已删。
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
            // ---------- 2026-10-26 补的 4 枚开关 ----------
            // 这四枚的读取与消费代码本来就都在（长按进度条 / 快捷格列数 / 双击防抖 / 低电阈值），
            // 但**全仓没有写点** —— 键永远等于默认值，等于开关不存在。补在这里让它们真能用。
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Picker("长按确认时长", selection: Binding(
                    get: { AXPrefs.holdDuration },
                    set: { app.setUnlockOption("kf_ax_hold", String(format: "%.1f", $0)) })) {
                    ForEach([0.4, 0.6, 0.9, 1.2, 1.6], id: \.self) { s in
                        Text(String(format: "%.1f 秒", s)).tag(s)
                    }
                }
                .pickerStyle(.menu)
                // 520 行那句"可在辅助功能里 0.4–1.6s 自定"长期是空承诺（没有那个页），现在成真。
                Text("按住圆盘多久算确认。关掉「按住确认」后此项不生效。")
                    .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
            }
            // 2026-10-28 补：`MemberHub.setElderMode` 全仓零调用 —— 而 `MemberHub.elderMode` 有 6 处 UI 消费
            // （凭证页分段从 4 段降到 3 段、完成页切「口述卡」、隐藏部分次要入口）。
            // 于是「长辈模式」永远开不了，那 6 处分支是**永远走不到的死路**。
            VariantToggle("长辈模式 (分段更少 / 大字 / 口述卡)", isOn: Binding(
                get: { MemberHub.elderMode },
                set: { on in
                    MemberHub.setElderMode(on)
                    app.bumpAppearanceForLayout()
                    app.showToast(on ? "长辈模式已开启：凭证页分段精简为 3 档" : "长辈模式已关闭")
                }))
            VariantToggle("大格模式 (快捷格 2 列)", isOn: Binding(
                get: { AXPrefs.bigTile },
                set: { app.setUnlockOption("kf_bigtile", $0) }))
            VariantToggle("双击防抖 (0.3 秒内忽略重复触发)", isOn: Binding(
                get: { AXPrefs.dbltapGuard },
                set: { app.setUnlockOption("kf_dbltap_guard", $0) }))
            Picker("低电提醒阈值", selection: Binding(
                get: { CareSchedule.battThreshold },
                set: { app.setUnlockOption("kf_batt_threshold", $0) })) {
                // 只给 10/15/20：CareSchedule.battThreshold 的白名单就是这三个（其它值会被夹回 15）。
                // 多给档位等于给一个"选了不生效"的选项。
                ForEach([10, 15, 20], id: \.self) { v in
                    Text("\(v)%").tag(v)
                }
            }
            .pickerStyle(.menu)
            Button("恢复默认外观") { resetAppearance() }
        } header: {
            Text("外观")
        } footer: {
            Text("主题、品牌色（六套）、密度、圆角、高对比、周起始日、行高与行距、指标位、纹理、动效强度、节日色、每日一句话都在本机生效，即时可见，不上传。高对比与系统「辅助功能-增加对比度」是并联关系，任一开着都加强；系统「减弱动态效果」会把动效强度压到克制档。素颜模式一键关闭庆祝与徽章动效；纯黑适合 OLED 夜间。")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }



    private func resetAppearance() {
        confirmDestructive("恢复默认外观",
                          "将主题、品牌色、布局密度、圆角、高对比皮肤、周起始日、凭证行高、时间线行距、指标位、纹理与每日一句话重置为默认值）。，不影响任何门锁数据。确定恢复吗？",
                          confirmTitle: "恢复默认") {
            app.resetAppearance()
            app.showToast("已恢复默认外观")
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
        }
    }

    private var aboutFooterText: String {
        var s = "厂商已停服的智能锁离线管理端。门锁数据、密码台账、家人档案全部保存在本机。换新手机用「备份与恢复」转移, 门锁无需重置。"
        if eggShown { s += " Build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?") · 本地构建。" }
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


// ---------- 防尾随 (tailgate: cmd24 档位 = 秒数，2~6 秒（APK 索引即秒数）) ----------
struct TailgateView: View {
    @EnvironmentObject var app: AppState
    @State private var seconds = 6
    @State private var busy = false

    var body: some View { vkBody.destined(.tailgate) }
    var vkBody: some View {
        Form {
            Section {
                Picker("等待时长", selection: $seconds) {
                    // 2026-10-28 修（**安全相关 off-by-one**）：APK `TailgatePage.chooseBtnImgStrs`
                    // 是 `["","","off","off","off","off","checkmark"]`（长度 7，索引 0..6），
                    // `getCurrentChooseSecond()` 从索引 2 遍历到 6、**返回索引本身**，
                    // `execSetTailgate` 又把这个索引值直接 `new Hi(索引, mac)` 送 cmd24 ——
                    // 所以档位就是 **2/3/4/5/6 秒，默认 6 秒**（不是 1..6、也没有 7 秒）。
                    // 原实现 `2...7` + `seconds-1` 让「选 6 秒」实际下发 5 秒 —— 防尾随时间
                    // 比用户设定短 1 秒，正好是尾随者挤进门的那 1 秒。
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
            try await app.lock.setAutoLock(seconds) // cmd24 档位 = 秒数本身（见 Picker 上方注释）
            DB.saveTailgate(kc.mac, TailgateCfg(interval: seconds, at: Date().timeIntervalSince1970 * 1000))
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
                Section("怎么设置门锁的安全模式？") {
                    // 2026-10-28 补：APK 的 page-safemodeintroduce 有 A/B 两档的完整定义，
                    // iOS 这边只写「当前已是 B 模式」，用户不知道 A 和 B 到底差在哪。
                    Text("A 模式：只需要单一方式（密码 / 指纹 / 手机）验证通过就可以开锁。")
                        .vkFont(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("B 模式：需要两种不同方式组合验证（指纹+密码 / 指纹+手机 / 手机+密码）才能开锁。")
                        .vkFont(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("只有 A 模式下临时开锁密码（ZOTP）才有效。")
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.warn)
                        .fixedSize(horizontal: false, vertical: true)
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