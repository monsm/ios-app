// 设置 Tab (settings 页) — 门锁管理/安全/家人与钥匙/网关/固件/备份/应用锁/外观/关于
// 分组原则: 同一心智模型的动作放同一 Section, 不再出现"一个 Section 只有一行"的碎片。
// 所有破坏性动作统一走 confirmDestructive (全局助手), 本文件不自带弹窗实现。
import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @State var showMembers = false
    @State var showGateway = false
    // 2026-10-29：锁设置 sheet（B 档）
    @State var showBackup = false
    /// 2026-10-17 安卓版: 把当前锁的开锁凭证渲染成二维码 (扫码导入, 之后不再需要)
    @State var shareLock: Keychain?
    // 2026-10-15 走查: 这两个目标页也自带 NavigationStack, 同样只能走 sheet
    // 包14: 27 设置内搜索 — 顶部搜索框过滤全部设置项
    @State var query = ""
    // 乱源治理第 4 批: 五组筛选的当前组。nil = 全部 (默认态与分组之前完全一样)。
    // 刻意是视图内 @State 而不是落盘键: 记住"上次只看外观与辅助"会让下次进来少看见一堆设置，
    // 那是把筛选变成隐藏 —— 页内搜索 (§27) 同样是会话态，两处口径一致。
    @State var groupFilter: SettingsGroup?
    /// 2026-10-28：通知权限只在进页时读一次（`NotifyAuth.status` 是同步阻塞读，
    /// 不能放在 body 里每次重算都调，否则设置页每次刷新都卡最多 2 秒）。
    @State var notifyLabel = ""
    @State var notifyOff = false
    // 包18: 版本彩蛋 (298) —— ✅ 实现（`eggShown` / `versionTaps` 在本文件）。
    //       VoiceOver 致意 (1049) —— ❌ **未实现**（全仓只有注释，第 114 轮已把空壳删除）。
    @State var eggShown = false
    @State var versionTaps = 0

    /// 2026-10-30 修正：原注释说「831 NEW 角标…已看过落 kf_seen_」—— 全仓既无角标绘制、也无 kf_seen_ 读写点，**该功能从未实现**。
    /// 下面两个 @State 属于「版本彩蛋 (298)」，与 NEW 角标无关。
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
    var settingsReader: some View {
        ScrollViewReader { proxy in
            settingsList(proxy)
        }
    }

    func settingsList(_ proxy: ScrollViewProxy) -> some View {
        List {
            searchTextRow
            searchResults(proxy)
            // 乱源治理第 4 批: 五组筛选片。默认 nil = 全部 ⇒ 这一屏与加这批之前逐字一致，
            // 谁不碰它就没有任何行为变化；碰了是把 17 节先筛成 3~6 节。
            SettingsGroupChips(selection: $groupFilter)
            // 每节挂一枚稳定锚 (`.id`), 供页内搜索 scrollTo 用。锚是字符串常量, 与筛选片无关。
            // 2026-10-29 布局整理：9 节按**分组顺序**排列 ——
            // 开门日常(3) → 凭证与成员(1) → 数据与安全(2) → 外观与辅助(2) → 帮助与关于(1)。
            // 原先「时间显示」(外观组) 夹在两个「开门日常」节之间，切到「外观」筛选片后
            // 它排在最前面，与同组的「外观」节隔了三节，读起来像两个不相干的东西。
            if settingsSectionShown(groupFilter, .daily) { lockSection.id(SettingsAnchor.lock) }
            if settingsSectionShown(groupFilter, .daily) { unlockSection.id(SettingsAnchor.unlock) }
            if settingsSectionShown(groupFilter, .daily) { autoOpenSection.id(SettingsAnchor.autoOpen) }
            if settingsSectionShown(groupFilter, .keys) { familySection.id(SettingsAnchor.family) }
            if settingsSectionShown(groupFilter, .data) { toolsSection.id(SettingsAnchor.tools) }
            if settingsSectionShown(groupFilter, .data) { applockSection.id(SettingsAnchor.applock) }
            if settingsSectionShown(groupFilter, .look) { timeSection.id(SettingsAnchor.time) }
            if settingsSectionShown(groupFilter, .look) { appearanceSection.id(SettingsAnchor.appearance) }
            if settingsSectionShown(groupFilter, .help) { aboutSection.id(SettingsAnchor.about) }
        }
        .navigationTitle("设置")
        .variantList()
        .dsScreenBackground()
        .sheet(isPresented: $showMembers) { MembersView() }
        .sheet(isPresented: $showGateway) { GatewayView() }
        .sheet(isPresented: $showBackup) { BackupView() }
        .sheet(item: $shareLock) { ShareToAndroidView(kc: $0) }
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
    func landPendingDiag(_ m: String?) {
        guard let m, !m.isEmpty else { return }
        app.pendingDiag = nil
        if m != app.currentMac { app.select(m) }
        app.requestRoute(.device)
    }


    /// 1013 落点: 切到通知里那台锁。
    /// 维护与保养页已随大删波4移除, 所以落到**设备页该锁** —— 电量、低电横幅、换电指引都在那里,
    /// 通知说的事 (该换电池了) 在设备页能就地看到, 不再指一个不存在的页面。
    func landPendingCare(_ m: String?) {
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
    func landPendingFocus(_ f: String?) {
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

    var mac: String { app.current?.mac ?? "" }

    // ---------- 包14: 27 设置内搜索 + 831 NEW 角标 ----------
    var searchTextRow: some View {
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
    enum SettingsAnchor: String {
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
    struct SearchHit: Identifiable {
        let id: String
        let title: String
        let icon: String
        /// 命中落在设置页的哪一节 (nil = 这个功能不在本页, 由 `go` 去开 sheet)
        var anchor: SettingsAnchor? = nil
        var go: () -> Void = {}
    }
    var searchHits: [SearchHit] {
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
            SearchHit(id: "s.mute", title: "静音模式", icon: "speaker.slash") { openLockSettings() },
            SearchHit(id: "s.synctime", title: "校准门锁时间", icon: "clock.arrow.circlepath") { openLockSettings() },
            // 2026-10-26: 今日新增的四项补进搜索索引 —— 入口在门锁段/工具段里，但索引此前没登记，
            // 于是搜「布防」「手机钥匙」「固件升级」「只读」都是零结果。
            //
            // ⚠ 这四个页面是 NavigationLink push 进去的，SearchHit 只能"滚动定位"到某一节，
            //    没有程序化 push 的入口（设置页用的是 NavigationLink 声明式，不是 path 栈）。
            //    所以这里只给 anchor（保证滚到对应段，用户看到那一行再点），
            //    **不给 go** —— 给一个空的 go 会让人以为点搜索就直接进页面，实际只滚动。
            SearchHit(id: "s.defend", title: "布防 (时段内否决自动开锁)", icon: "shield.lefthalf.filled") { openLockSettings() },
            SearchHit(id: "s.mobilekey", title: "手机钥匙 (给成员发数字钥匙)", icon: "iphone.gen3", anchor: .family),
            SearchHit(id: "s.dfu", title: "固件升级 (Nordic DFU)", icon: "arrow.up.circle") { openLockSettings() },
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
    func searchResults(_ proxy: ScrollViewProxy) -> some View {
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
        // 2026-10-30 补（第 119 轮，**空态**）：搜索零结果时整块不渲染，用户无法区分
        // 「搜了没结果」和「搜索坏了」。
        if !query.trimmingCharacters(in: .whitespaces).isEmpty && searchHits.isEmpty {
            Section {
                Text("没有找到「\(query)」")
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
            }
        }
    }
    var lockSection: some View {
        Section("门锁") {
            // 2026-10-29 入口去重（用户反馈「同一个界面被很多次入口」）：
            // 本段原先有 6 个入口，其中 3 个是别处的重复：
            //   · 锁信息名片   → 已收进「锁设置 → 概览」底部一行（唯一入口）
            //   · 锁设置       → 设备页「管理这把锁」是唯一入口（本页不再重复）
            //   · 添加另一把锁 → 设备页右上角「+」是唯一入口
            // 留下的是**只有设置页才有**的三项：锁档案 / 分享给安卓 / 删除设备。
            if app.current == nil {
                GuidedEmptyView(systemImage: "lock",
                                title: "还没有添加门锁",
                                message: "添加后这一段才会出现锁档案与删除。三步走： 连上锁 → 录凭证 → 开门。",
                                step: 1, stepTotal: 3,
                                primaryTitle: "去设备页添加",
                                primary: { goAddDevice() },
                                )
                    .listRowInsets(EdgeInsets())
            } else {
                NavigationLink { LockProfileView() } label: {
                    Label("锁档案 (昵称/符号/色标/备注)", systemImage: "person.text.rectangle")
                }
                note("型号、固件、电量与完整名片都在设备页 →「管理这把锁」→「概览」里。")
                Button("删除设备", role: .destructive) { deleteDevice() }
            }
        }
    }

    /// 2026-10-29 入口去重：添加设备只在设备页右上角「+」。
    func goAddDevice() {
        app.requestRoute(.device)
        app.showToast("在设备页右上角点「+」添加门锁")
    }

    /// 2026-10-29：锁设置只有设备页「管理这把锁」一个入口。
    /// 设置页搜索命中这四项时，直接把用户送到那个入口（而不是本页再开一个重复的 sheet）。
    func openLockSettings() {
        app.requestRoute(.device)
        app.showToast("在设备页点「管理这把锁」进入锁设置")
    }

    /// 2026-10-14: 设置项小字注解。口径"简洁明了" —— 只说用户决策需要的那一句
    /// (这一项是干什么的 / 要不要连上锁 / 有什么后果), 不铺陈实现细节 (那些留在注释里)。
    func note(_ s: String) -> some View {
        Text(s)
            .vkFont(.caption)
            .foregroundStyle(DS.Palette.textSub)
            .fixedSize(horizontal: false, vertical: true)
    }

    func deleteDevice() {
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
            consequence += " 连带删除： 密码台账 \(pws) 条、指纹台账 \(fps) 条、本机缓存的开门记录 \(recs) 条。"
        }
        consequence += " 删除后若未做过备份将无法找回。"
        confirmDestructiveTyped("删除设备", consequence, requireWord: name, confirmTitle: "确认删除") {
            DB.removeDevice(kc.mac)
            app.loadDevices()
            app.showToast("已删除「\(name)」")
        }
    }

    func disablePasscode() {
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

    func setPasscode() {
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

    func promptOldPasscode(_ then: @escaping (Bool) -> Void) {
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

    var aboutFooterText: String {
        var s = "厂商已停服的智能锁离线管理端。门锁数据、密码台账、家人档案全部保存在本机。换新手机用「备份与恢复」转移， 门锁无需重置。"
        if eggShown { s += " Build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?") · 本地构建。" }
        return s
    }

/// 机械计数样式数字 (idea 1006): 每位一格, 等宽数字
    func presentSetPasscodeAlert() {
        let alert = UIAlertController(title: "设置本机密码", message: "4 位以上纯数字（本机密码用于解锁 App 与确认高危操作）", preferredStyle: .alert)   // 2026-10-30：原句「随机键位需要数字键盘」—— 随机键位功能全仓不存在
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

    func setDuressCode() {
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

}
