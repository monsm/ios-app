// RootView · Tab 容器与场景生命周期（mainTabView / mainTabs / mainTabsChrome / handleScenePhase）
// 2026-10-29 从 LockKeeperApp.swift（1018 行）拆出。
import SwiftUI

extension RootView {
    private var mainTabView: some View {
        TabView(selection: $app.tabSelection) {
            // 280 页面打开耗时: 起点在下面的 onChange(tabSelection)，终点就是各 Tab 内容的 onAppear。
            Tab("设备", systemImage: "lock.fill", value: 0) { deviceTabContent }
                // 162 握手可离开: 握手在别的 Tab 完成时这里亮一枚 "✓" (nil = 无角标); 回设备页即清
                .badge(handshakeDoneAway ? Text("✓") : nil)
            // 930 替代: 原句要的中尺寸"到期凭证 Widget"在免费账号读不到台账 (App Groups 禁),
            // 替代栏给的是"到期前 7/3/1 天三级本地通知 + 凭证页顶部红点" —— 通知在
            // CredentialOrg.scheduleAlerts, 红点落在系统 Tab 角标上 (与记录 Tab 的 735 角标同一手法,
            // 0 时系统自动隐藏)。口径与 363 月历格同源, 不另算一套。
            Tab("凭证", systemImage: "key.horizontal.fill", value: 1) { credentialsTabContent }
                .badge(CredentialOrg.expiringSoonCount(macs: DB.keychains().map { $0.mac }))
            Tab("记录", systemImage: "list.bullet.rectangle.fill", value: 2) { recordsTabContent }
            Tab("设置", systemImage: "gearshape.fill", value: 3) { settingsTabContent }
        }
    }

    /// 主 TabView + 长按菜单 + 底栏/访客复核 —— 从 appUnlocked 分支抽出: 该表达式报 type-check 超时
    private var mainTabs: some View {
        // iOS 18+ 的 Tab 声明式写法: 类型安全, 系统按平台自动选择底栏/侧栏形态
        // 包15 键盘: Cmd 1-4 切 Tab 真接线 (164/530); Tab/Esc 遍历由系统「全键盘控制」提供 (854)
        mainTabView
            // 只读试验模式：全 App 顶部常驻红条。**必须常驻** ——
            // 用户第二天忘了自己开过它，会以为"App 坏了、什么都改不了"。
            .safeAreaInset(edge: .top, spacing: 0) { TrialGuardBanner() }
        // 26 Tab 长按快捷菜单 (iOS 18)。这一条只在"真按得动"的项上开口:
        // 每一项都汇进本仓**已有的落点口** (requestTab / pendingCredPanel 词表 /
        // pendingRecordsDay / pendingDiag), 没有一项指向还不存在的页面 ——
        // 长按菜单最容易变成"写了三行其实一行做不到"的地方, 所以宁可每页只给两三项。
        // ⚠ API-VERIFY: `contextMenu(forSelectionType:tabBar:primaryAction:)` 全仓无先例,
        //    形状按 iOS 18 TabView 文档; 未编译、未证实。若系统不认这一形, 退路是
        //    把同样的动作挂到各 Tab 内容的 .contextMenu (长按页内元素), 语义会差一档。
        // 2026-10-13 run 69: 这两个闭包的形参是**选中集 `Set<Int>`** (不是单个 Int) ——
        // 原写 `{ t in switch t { case 0: … } }` 报 "expression pattern of type 'Int' cannot
        // match values of type 'Set<Int>'" / "cannot convert 'Set<Int>' to 'Int'"。取首个元素。
        .contextMenu(forSelectionType: Int.self) { selected in
            switch selected.first ?? -1 {
            case 0:
                Button("只看今天的记录") {
                    app.pendingRecordsDay = StatsKit.dayKey(Date())
                    app.requestRoute(.records)
                }
            case 1:
                // 2026-10-28 删除：这三枚（凭证回收站 / 到期与整理建议 / 待补拉队列）**全是死入口** ——
                // 它们只写 `app.pendingCredPanel`，而那个字段全仓**零读取方**（注释提到的
                // `consumeCredPanel` 从未存在）。回收站与待下发队列两套功能也早已整族移除。
                // 点了只会跳到凭证页，什么都不会展开。
                Button("打开凭证页") { app.requestRoute(.credentials) }
            case 2:
                Button("只看今天") {
                    app.pendingRecordsDay = StatsKit.dayKey(Date())
                    app.requestRoute(.records)
                }
                Button("回设备页开锁") { app.requestRoute(.device) }
            default:
                // 设置 (3) 与任何没预料到的值: 只给真存在的两条
                if app.currentMac.isEmpty {
                    Button("打开这一页") { app.requestTab(selected.first ?? 0) }
                } else {
                    // 2026-10-28 修复：诊断页已随十三轮精简整族删除（SettingsView:95-97 自述），
                    // 这一枚只做 `pendingDiag = mac` + 切到设置页，落地只 select 锁、**不显示任何诊断信息**。
                    // 改成真存在的落点：这台锁的档案页（能看到固件/电量/型号等读数）。
                    // 2026-10-28 修正：Route 只有 device/credentials/records/settings 四个成员，
                    // 没有 lockProfile —— 锁档案页是 Destination 里的一站（Sheets.LockProfileView），
                    // 从设备页的「更多」区进。这里落点改为设备页（那页上就能看到档案入口）。
                    Button("这台锁的读数") { app.requestRoute(.device) }
                    Button("打开这一页") { app.requestTab(selected.first ?? 0) }
                }
            }
        } primaryAction: { selected in
            // 长按后直接点一下 (竖屏主操作) = 进那一页, 走的仍是 requestTab 那道访客门禁
            if let t = selected.first { app.requestTab(t) }
        }
        // 2026-10-27 删除：**Tab 栏上方的悬浮「开锁」按钮是冗余入口**。
        //
        // 它标着「开锁」，而实际只做 `requestRoute(.device)` —— 纯切页，不开锁。
        // 而底栏第一个 Tab 就是「设备」，点 Tab 到的是同一个地方。
        // 代码注释自己早就写着「**只导航、不开锁**: 主操作仍然只有那一个 176pt 圆盘」，
        // 也写着「第二个开锁入口 = 第二套误开面」。
        //
        // 代价却是实打实的：占掉底部空间、压住 Tab 栏标签（截图里「凭证」「记录」被盖），
        // 还让用户以为它能一键开锁 —— 点了只是跳页，困惑大于便利。
        // 真正的主操作在设备页那个 176pt 圆盘上，不在这里。
        .animation(DS.Motion.quick, value: app.tabSelection)
        // 用 safeAreaInset 而不是 overlay — 覆盖式会压住导航栏标题
    }

    /// 主界面的顶部横幅/时刻卡/启动 task/前后台钩子 —— 同上, 继续拆
    @ViewBuilder
    private var mainTabsChrome: some View {
        mainTabs
        .safeAreaInset(edge: .top, spacing: 0) {
            topBanners
        }
        .task { bootstrapOnce() }
        // 2026-10-13 run 60: 原来把整段前后台收尾逻辑内联在这个闭包里, 与上下十几个
        // .onChange / .overlay 同处一个巨型 body 表达式 ⇒ 编译器报
        //   "unable to type-check this expression in reasonable time"。
        // 抽成独立方法后 body 只剩一行调用, 类型检查负担从整个 body 缩到一个函数。
        .onChange(of: scenePhase) { _, phase in handleScenePhase(phase) }   // 135 回前台即刷新
    }

    /// 2026-10-16 启动块从 `mainTabsChrome` 里抽出来成这一个函数，**不是重构好看**：
    /// 界面变体（core / gauge）不挂 `mainTabsChrome`，抽出来之前那些变体会**静默跳过整条启动链** ——
    /// 异常退出档案、onLaunch 的自检/月备排程/成就结算、启动预热、LinkSense 宿主注册与冷启动扫描
    /// 全都不跑，而且不报错。这就是本仓"删/改名留悬空引用"那一族的新成员：**换容器留孤儿副作用**。
    /// 现在 legacy 与两个新变体都调用这一个实现，`launchBootstrapped` 继续兜 `.id(appearanceSeed)` 的重放。
    static func bootstrapOnce(_ app: AppState) {
        guard !app.launchBootstrapped else { return }
        app.launchBootstrapped = true
        // 547/758 异常退出档案: 这四个函数此前全库零调用, 整条链路从未跑过。
        // 顺序要紧: 先按上次的标记判定异常退出, 再为本次会话打点。
        app.onLaunch()
        // 215 启动预算 / 224 启动预热: 两个引擎此前全库零调用。
        // Prewarm 只做本地键位与热点缓存读取, 不碰 BLE —— 不会在启动时偷偷发起连接。
        // 2026-10-26: 两件事从已失效的 .onChange(of: app.appUnlocked) 搬来这里。
        // 冷启动必跑（原入口的触发条件"appUnlocked 变为 true"在删掉启动门禁后永不成立）。
        app.restoreLastTab()          // 161: 回到上次停留的 Tab（内部见 pendingRoute 就避让）
        app.applyPendingRoute()       // 落地挂起的深链
        let selfCheckBad = app.runSelfCheck397()
        if selfCheckBad > 0 {
            app.showToast("本机自检发现 \(selfCheckBad) 项异常，详见「设置-诊断」")   // 397 本机自检发现
        }
        RootView.registerHost(app)   // 包2: LinkSense 宿主注册 + 回连/巡检循环
        LinkSense.shared.coldStartScan()   // 包2/134 冷启动先扫描 (定位可见锁, 不连接)
        // 2026-10-18 冷启动预连接（用户口径："打开 app 1 秒内做完一遍"）。
        //
        // 原来连接要等 DeviceHomeView 的 .task → sense.enterPage() → preconnect()，
        // 也就是**首页渲染完之后**才开始建链。而建链本身（扫描→connect→发现服务→setNotify）
        // 是这条链上最贵的一段。用户从点图标到"能开锁"之间，这段时间完全是白等的。
        //
        // 现在：启动链路里**立刻**发起预连接（与 coldStartScan 同一拍，不等 UI）。
        // 它是静默的（不弹权限、不弹面容、不 toast），失败也只是安静退出 ——
        // 真到用户按圆盘时 ensureConnected 仍然会兜底重试，不改变任何既有语义。
        //
        // 时序上它和首页渲染并行：用户看到界面的那一刻，链路往往已经建好了。
        LinkSense.shared.startupPreconnect(mac: app.currentMac)
    }
    /// 实例便捷转发，供 `.task` 直接调用（保持 body 表达式小，见本文件多处 type-check 超时的教训）。
    private func bootstrapOnce() { RootView.bootstrapOnce(app) }


    var body: some View {
        // 2026-10-28：冷启动时 scenePhase 的 onChange 不一定触发初始回调，
        // 这里补一次，保证首帧的动效令牌就能拿到正确的系统减弱动态值。
        rootChrome
            .onAppear { AXFlags.refreshSnapshots() }
    }

    /// 主界面。首启引导已随本轮删减移除, 启动不再分形态 —— 这里只返回主界面本体。
    @ViewBuilder
    private var rootGroup: some View {
        // 2026-10-27 新增（AUDIT-D D-01 + D-48）：应用锁门禁。
        // 用户决策：**只在冷启动**要求输密码（不打断日常切前台）。
        // 未解锁 → LockScreen；解锁后 → 主界面。
        // 伪装码在 LockScreen 里识别：输胁迫码同样进主界面，但 decoy = true（空壳模式）。
        ZStack {
            if lock.unlocked {
                mainTabsChrome
            } else {
                LockScreen()
            }
        }
        // 伪装态同步到 AppState：全仓 12 处 decoyMode 判据靠它生效
        .onChange(of: lock.decoy) { _, d in app.decoyMode = d }
        .onChange(of: lock.unlocked) { _, u in
            app.appUnlocked = u
            if u, !lock.decoy { app.restoreLastTab() }
        }
    }

    /// 摇一摇/外观种子/字号/灰度/加粗/动效/水印层 —— 继续拆 (原表达式报 type-check 超时)
    @ViewBuilder
    private var rootCore: some View {
        rootGroup
        // 包16: 外观种子变更时整树重建 — 配色/密度即时全局生效; withAnimation 提供淡入淡出 (idea 21)
        // 2026-10-18 门面改造: 启动/回前台按策略决定是否展示门面。
        // 冷启动展示; 回前台 < 300s 不重演; 深链进入时一律不展示。
        .id(app.appearanceSeed)
        .animation(DS.Motion.soft, value: app.appUnlocked)
        // 2026-10-27 审核修复 (AUDIT-B 2.6)：**接回两项系统无障碍支持**。
        // `AXTools.boldText` 与 `AXTools.typeSize()` 的实现一直都在（读系统开关），
        // 但它们唯一的消费点（根视图这两个修饰符）在早前精简里被删了 ——
        // 于是「设置→辅助功能→显示与文字大小」里的加粗文本与字号对 App 完全无效。
        //
        //   · `dynamicTypeSize`：把 App 档 × 系统相对倍率映射到最近的 DynamicTypeSize 预设
        //   · `legibilityWeight`：显式字重的文本（凭证名/开关标签）跟着系统加粗
        //
        // 为什么挂在 rootCore（而不是每个页面各挂一次）：这两项是**整树生效**的环境值，
        // 挂一处就够；分散挂会漏页面，且改口径要改几十处。
        .dynamicTypeSize(AXFlags.typeSize())
        // 2026-10-27 修正：`legibilityWeight` **不是可写的 EnvironmentValues 键** ——
        // `.environment(\.legibilityWeight, …)` 编译报「cannot infer key path type」。
        // 它只能读。正确的接入点在 `VKTypography`（所有文本的唯一入口）里，见那里的实现。
    }

    /// 后台隐私幕/深链/Tab 与解锁状态钩子/触感/配色 —— 同上
    @ViewBuilder
    private var rootChrome: some View {
        rootCore
        // 2026-10-17 拍板: 删除 233「内容已隐藏」后台隐私幕 (连同 PrivacyCurtain 结构体)。
        // 它是退后台时盖一层不透明幕, 回前台不要求任何验证 —— 与"需要面容才能看"的直觉不符,
        // 且启动门禁已删, 留着只会让用户回前台时以为 App 卡住。
        // 294 本地深链: 系统把 kf:// 路由送到这里; 解锁完成的瞬间才落地挂起的路由
        .onOpenURL { url in app.handleDeepLink(url) }
        .onChange(of: app.tabSelection) { _, new in
            // 280 起点: 只在采集开着时记时间戳 (关着就等于零成本)。深链/意图造成的切换同样会记一次,
            // 因为对用户而言那也是一次"页面打开"。
        }
        // 2026-10-26: 这里原本是 `.onChange(of: app.appUnlocked)`，承接三件事：
        //   · 解锁后 restoreLastTab() —— 回到上次停留的 Tab
        //   · 解锁后 runSelfCheck397() —— 本机库体自检（异常才出声）
        //   · 锁落下时 revokeSessionGrants() —— 这条**已改挂** scenePhase == .background（见 handleScenePhase）
        // 2026-10-17 拍板删掉启动门禁后 init() 里 `appUnlocked = true`，此后它**再也不会变**，
        // 于是这个 onChange 一次都不触发 —— 三件事全部静默失效（"回到上次停留"与自检一直没跑）。
        // 现在：前两件搬进 bootstrapOnce（冷启动必跑，语义等价且更早）；
        // 第三件随"手动锁/到点自动锁"一起去掉了（那条路径已不存在，没有"锁落下"这个事件）。
        .onChange(of: app.tabSelection) { _, t in
            app.rememberTab(t)   // 161 记"上次停留"
            if t == 0 { handshakeDoneAway = false }   // 162: 人回到设备页, 完成角标的使命结束
        }
        // 168 状态变化播报: 只报稳定态 (就绪/断开), "握手中"不打扰;
        // 断开只在确实从就绪掉线时报, 避免首次进页面 just to show 未连接 就朗读一句
        .onChange(of: sense.linkState) { old, new in
            switch new {
            case .ready: AXTools.announce("已连接门锁")
            case .down where old == .ready: AXTools.announce("门锁连接已断开")
            // 2026-10-27：新增 .notReady（连着但密钥未绑定）。它不是"稳定就绪态"，
            // 所以不播报 —— 用户能从屏幕上的黄条看到原因，语音再念一遍是噪音。
            case .notReady, .connecting, .down: break
            }
        }
        // 162 握手可离开: 圆盘握手 (connecting/opening) 在别的 Tab 上走到 success → 设备 Tab 挂角标。
        // 在设备页看着完成的人不打扰; 失败走 852 主动播报那条通道, 这里只报"完成"。
        .onChange(of: app.unlockState) { old, new in
            guard !app.decoyMode, app.tabSelection != 0 else { return }
            if (old == .connecting || old == .opening), new == .success { handshakeDoneAway = true }
        }
        .sensoryFeedback(.selection, trigger: app.tabSelection)   // Tab 切换的轻触感
        .preferredColorScheme(colorScheme)
    }



    /// 包8/508 写入回执浮层 —— 2026-10-13 run 63 从 body 内联块抽出:
    /// 巨型 body 里这一段报 "unable to type-check this expression in reasonable time"。
    @ViewBuilder
    func writeReceiptView(_ r: String) -> some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: DS.Icon.md))
                .foregroundStyle(DS.Palette.ok)
                .accessibilityHidden(true)
            Text(r)
                .vkFont(.caption, weight: .medium)
                .foregroundStyle(DS.Palette.text)
        }
        .padding(.horizontal, DS.Space.l)
        .padding(.vertical, DS.Space.s)
        // 2026-10-14 材质统一: 悬浮回执条从实底改液态玻璃 (与 ToastView 同一条 axGlass 通道)。
        // 它是浮在内容之上的一层, 正是折射底该起作用的位置; 描边不加 —— 玻璃自带边缘高光。
        .axGlassCapsule()
        .shadow(color: .cardElevation, radius: 8, y: 3)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .allowsHitTesting(false)
    }

    /// 135 前后台切换收尾 —— 2026-10-13 run 60 从 body 的内联 .onChange 闭包里抽出来:
    /// 内联时整个 body (十几个 .onChange/.overlay 串在一起) 是一个巨型表达式, 编译器报
    /// "unable to type-check this expression in reasonable time"。抽成方法后 body 只留一行调用。
    @MainActor
    private func handleScenePhase(_ phase: ScenePhase) {
        LinkSense.shared.setSceneActive(phase == .active)
        if phase == .active {
            // 2026-10-28 修复：`AXFlags.refreshSnapshots` 全仓零调用 —— 而它的注释写着
            // 「刷新点 = 启动 + 每次回前台」。缺了这一步，`reduceMotionSnapshot` 恒为初始值 false，
            // 于是 DS.Motion 的 systemReduceMotion 永远拿不到系统「减弱动态效果」的真值。
            // 改这个系统开关必须先离开 App 去设置，回来一定经过 .active —— 这里是唯一正确的刷新点。
            AXFlags.refreshSnapshots()
            // 2026-10-17 拍板 A: 「到点自动落锁」随启动门禁一起删 —— 现在没有锁屏页可回,
            // 留着它只会把 appUnlocked 置 false, 让深链/落点/回连那些 guard 静默失效。
                // 靠近自动开锁 (AUTOOPEN): F0 前台门 + F1 进前台按档位刷面容 (挂起期静默)
                AutoOpenController.shared.onForeground(mac: app.currentMac)
                // 344 回前台才出快捷条 (344 的原话就是"回前台显示"), 顺带重算剩余秒数
                // 897 四季图标: 默认关。开着也只在"季节真的换了"时对齐一次 (年-季记号)，不每次回前台打扰
        } else if phase == .background {
            // 2026-10-14: 只有**真进后台**才算退后台。旧实现把 .inactive (下拉通知中心/控制中心、
            // 来电、Face ID 系统弹窗) 也当退后台 —— 会误记锁定到期时刻 (反复下拉可无限顺延宽限),
            // 还会提前清掉崩溃标记 (随后真崩溃被判成"正常退出")。.inactive 只收起过期的快捷条。
            // 221 退后台收尾: 记会话时长并清崩溃标记 (CrashGuard 的判定就依赖这一步)
            AutoOpenController.shared.onBackground()
            // 2026-10-26: 访客区/临时授权在这里收回。
            // 原来由 .onChange(of: app.appUnlocked) 在"锁落下"时收 —— 但启动门禁删掉后
            // appUnlocked 再也不会变 false，那条路径永不触发，等于**一次放开就永久敞开**。
            // 改挂"真进后台"：用户离开 App 就是"这一次查验的会话结束了"，这与原意一致，
            // 且比"锁落下"更容易成立（后者那个事件已经不存在）。
            app.revokeSessionGrants()
            // 2026-10-29：诊断日志改成内存缓存 + 1s 防抖落盘（原来每条日志都读文件+写文件）。
            // 真进后台时冲一次，避免最后 1 秒的日志丢在内存里。
            DiagLogs.flush()
            // 2026-10-29：BLE 遥测同样改成内存缓存 + 1s 防抖，退后台一起冲。
            BleTelemetry.flush()
        } else {
            // .inactive: 只收起过期的快捷条, **不**记锁定到期时刻 (否则反复下拉通知中心可无限顺延宽限)。
            // 但崩溃标记仍要清 —— 从任务切换器强退时进程多在 .inactive 被 SIGKILL,
            // 只在 .background 清会把正常强退误报成"异常退出"。
            // 2026-10-14: .inactive 也要停自动开锁的武装态与加速度计 (下拉通知中心/来电/系统弹窗期间
            // AUTOOPEN 不该继续武装并喂传感器); 锁定计时与崩溃标记的取舍见上。
            AutoOpenController.shared.onBackground()
            // 任务切换器强退多停在 .inactive 就被 SIGKILL —— 这里也冲一次。
            DiagLogs.flush()
            // 2026-10-29：BLE 遥测同样改成内存缓存 + 1s 防抖，退后台一起冲。
            BleTelemetry.flush()
        }
    }

    // 2026-10-29：4 个 Tab 内容属性从 LockKeeperApp 搬到本文件 ——
    // destmap.js 的 propertyBody 只跟**同一文件**一跳，`Tab(...) { xxxTabContent }` 的
    // 内容属性必须与 Tab 同文件，否则四个根页不进台账（uicoverage 会掉 4 条）。
    @ViewBuilder private var deviceTabContent: some View {
        DeviceHomeView()
            .keyboardShortcut("1", modifiers: .command)
    }
    @ViewBuilder private var credentialsTabContent: some View {
        // 身份挂在这里 (父层) 才有效: CredentialsView 的 @State 由 TabView 持有,
        // 在其 body 内部写 .id(app.currentMac) 不会重建该 struct → 切锁后
        // selPwds/selFps/otpPwd 仍是上一把锁的值, 批量停用会打到错锁。
        CredentialsView().id(app.currentMac)
            .keyboardShortcut("2", modifiers: .command)
    }
    @ViewBuilder private var recordsTabContent: some View {
        // 同凭证 Tab: 记录是纯 per-lock 数据, 在父层挂身份才能整体重建。
        // RecordsView 只有 :178 onAppear→loadFromCache, 编程式切锁 (跳回/意图改 currentMac)
        // 不触发 → groups/allRows 仍是旧锁行, :1187 的认领会把旧锁 idxRaw 记到新锁键下。
        RecordsView().id(app.currentMac)
            .keyboardShortcut("3", modifiers: .command)
    }
    @ViewBuilder private var settingsTabContent: some View {
        SettingsView()
            .keyboardShortcut("4", modifiers: .command)
    }
}
