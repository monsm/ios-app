// 离线锁管家 for iOS — App 入口与全局状态 (SwiftUI 全原生)
import SwiftUI
import UIKit
import AudioToolbox
import UserNotifications
import CoreSpotlight   // 293/951 接住 Spotlight 结果回传的 NSUserActivity (索引写入见 App/Core/SpotlightKit.swift)

@main
struct LockKeeperApp: App {
    @StateObject private var app = AppState()
    // 943 主屏长按快速操作: 只借 UIApplicationDelegate 的 performActionFor 一个回调，
    // 其余方法一律不接 (本 App 没有后台任务需求)。取舍与"为什么不配闭包"写在 App/Core/QuickActions.swift。
    @UIApplicationDelegateAdaptor(QuickActionDelegate.self) private var quickActions
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .tint(DS.Palette.accent)
                .task {
                    QuickActions.install()   // 装三项; 从未启动过时长按看不到它们, 是系统限制不是漏做
                    SpotlightKit.reindexNow()   // 293/951 启动即整刷一次索引 (改名/增删另有即时钩子, 见 Store)
                }
                .onAppear {
                    // 落地走 handleDeepLink: 与手点深链**同一个**门禁 (应用锁未解开时只挂起 pendingRoute)，
                    // 快速操作因此不可能绕过应用锁 —— 这条性质由既有代码保证，不在新文件里重做一遍。
                    if let url = QuickActions.consume() { app.handleDeepLink(url) }
                }
                // 293/951 Spotlight 结果落地: 仍走 handleDeepLink 那一套门禁 —— 应用锁没开时只记 pending，
                // 解锁后由 applyPendingRoute 补走。索引能给的是"跳到哪"，不是"绕过锁"。
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    app.handleSpotlight(activity)
                }
        }
    }
}

// ---------- 主题 (JS utils/theme.js: kf_theme) ----------
// 颜色统一取自设计系统 DesignSystem.swift, 页面不再各自定义颜色
enum Theme {
    static var accent: Color { DS.Palette.accentText }
    static var warn: Color { DS.Palette.warn }
    static var ok: Color { DS.Palette.ok }
    static var isLight: Bool {
        DB.store.getString("kf_theme") == "light"
    }
    // 跟随系统: 未设置时 nil; 设置过则固定。纯黑 (idea 30) 走深色语义, 表面由 Palette 覆盖为纯黑
    static func scheme(for key: String) -> ColorScheme? {
        switch key {
        case "light": return .light
        case "dark", "black": return .dark
        default: return nil
        }
    }
    static var scheme: ColorScheme? {
        scheme(for: DB.store.getString("kf_theme"))
    }
}

// ---------- 全局状态 ----------
@MainActor
final class AppState: ObservableObject {
    @Published var devices: [Keychain] = []
    @Published var currentMac: String = ""
    @Published var status: LockStatus?
    @Published var snapshot: StatusSnapshotData?
    @Published var unlockState: UnlockState = .idle
    @Published var appUnlocked: Bool
    // 390: 伪装码进入后停在空壳界面 (不加载任何门锁/凭证视图与数据)
    @Published var decoyMode = false
    // 2026-10-13 对抗式排查: 启动块只跑一次的会话令牌。
    // 起因: `mainTabsChrome` 里那段 `.task { CrashGuard.checkAbnormalExit() … coldStartScan() }`
    // 被 `.id(app.appearanceSeed)` 包着 —— 改任何外观档 (主题/品牌色/密度/圆角/行高/动效/快捷格次序)
    // 都会给整树换身份, 子树被销毁重建 ⇒ `.task` **整段重放**:
    //   · onLaunch() 再跑一遍 (自检 / 月备排程 / 成就结算 / CrashGuard 重复打点);
    //   · coldStartScan() 再起一个扫描, 而它是裸 `Task {}` 不随 `.task` 取消 ⇒ 两个扫描轮询并发读同一 discovered。
    // 加这一位让启动块幂等 (AppState 是引用类型, 不受视图换身份影响)。
    var launchBootstrapped = false
    // ---------- 236/377 访客通道 / 383 毁灭复核: 两枚会话级授权位 ----------
    /// 377: 访客通道开着时主 TabView 只挂 设备/记录; 这一位记"本会话是否已重输口令放开 凭证/设置"。
    /// 刻意是内存态而不是存储键 —— 落盘就等于"退出不用再输密码", 与开关原话相反。
    @Published var guestAreaUnlocked = false
    /// 377: 复核完成后要落到的 Tab (nil = 只放开受限区, 不指定落点)
    @Published var guestGateTarget: Int?
    /// 377: 受限区的复核页开关 (承载体就是既有 AppLockView, 不新造第二个解锁面)
    @Published var showGuestGate = false
    /// 383: 当场验过应用锁口令才发得出的券; 真正的拦点在 DestroyKit.destroyAll (AuditChain.swift)
    @Published var sudoTicket: SudoTicket?
    /// 377 被收起来的那两个 Tab 号 (与下面 TabView 里的 value 一一对应: 1 凭证 / 3 设置)。
    /// 236 与本条同行为一 (DEFERRED 舍弃表: 访客模式并入 377): 原句「只看设备 Tab / 进凭证要密码 /
    /// 退出需密码 / 落点应用锁」全部落在本通道; 只拦 凭证/设置 两页, 记录页不含凭证本体照常可看,
    /// 界面文字也只写"凭证与设置", 不夸口拦记录。
    ///
    /// 2026-10-16 C1: 值改为**从 Route.guestBlocked 派生**，不再手写 `[1, 3]`。
    /// 原来这张字面量集合是"同一个量的第二次计算"（判据的另一半在视图里按序号摘除层级），
    /// 而新变体没有 Tab 序号 —— 两处同时失去指称对象，访客门禁会**静默**不再覆盖
    /// 应用锁/访客/伪装/销毁那一块，不崩不报错。判据收到 Route.guestBlocked 一处。
    static let guestBlockedTabs: Set<Int> = Route.guestBlockedTabs
    /// 377: 已进 App、但受限区还没放开
    var guestAreaLocked: Bool {
        appUnlocked && !decoyMode && SecurityPolicy.guestActive && !guestAreaUnlocked
    }
    @Published var toast: String?
    // 主题键的镜像: 变更时驱动 RootView 重建, 让配色立即生效
    @Published var themeSeed: String = DB.store.getString("kf_theme")
    /// 外观种子 (包16): 主题/品牌色/密度任一变更 +1, RootView 以 .id 重建全树实现即时换肤
    @Published var appearanceSeed = 0
    /// 2026-10-14: 行为类偏好 (开锁怎么开/什么动静) 的轻量变更信号 —— 见 setUnlockOption 注释。
    /// 与 appearanceSeed 的关键区别: 只让视图体重算，**不换身份**，所以滚动位置/焦点/动画全部保留。
    @Published var prefSeed = 0
    @Published var tabSelection = 0 { // 设备/凭证/记录/设置
        didSet {
            // 54/372 摇一摇的过程态跟着换页走: 回位票只在"留在设置页"期间有效,
            // 迷你开锁面板只属于设备页 —— 换页不收拾就是两条残影。
            if tabSelection != 3 { shakeReturnTab = nil }
            if tabSelection != 0 { shakePanel = false }
        }
    }
    // 294 本地深链 (kf://): 白名单路由; 应用锁未解开时**先挂起**, 解锁后才落地 (深链不得绕过门禁)
    @Published var pendingRoute: Route?
    @Published var pendingMac: String?   // 294 深链带的锁 ID (kf://device?mac=), 解锁后落地
    /// 294 深链 host 白名单。2026-10-16 C1: **由 Route.deepLinkHosts 派生**，不再手写序号表。
    /// 顺序只有一个声明处 (Route.byHost)，深链、Tab 号、访客受限集三样都从它推。
    static let deepLinkHosts: [String: Int] = Route.deepLinkHosts
    func handleDeepLink(_ url: URL) {
        guard url.scheme == "kf", let host = url.host?.lowercased(),
              let tab = AppState.deepLinkHosts[host] else { return }   // 未知 host = 忽略, 不跳不崩
        // 585 行内定位键: 只有 `?k=` 这一个参数被认，其余一律丢 (不拿任意 query 当指令)。
        // 值本身只是"到那页以后找哪条"的字符串，找不到的由消费方如实说"不在本机台账里"。
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let k = items.first(where: { $0.name == "k" })?.value, !k.isEmpty {
            pendingRecordKey = k
        }
        // 294 带锁 ID 直达: kf://device?mac=<hex> 落点为该锁详情 (开锁入口), 锁着先挂起。
        // 未知 MAC 直接忽略 (与 host 白名单同款, 不跳不崩)。
        if host == "device",
           let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let m = items.first(where: { $0.name == "mac" })?.value, !m.isEmpty,
           DB.keychain(DB.normalizeMac(m)) != nil {
            let mac = DB.normalizeMac(m)
            if appUnlocked && !decoyMode { select(mac) } else { pendingMac = mac }
        }
        if appUnlocked && !decoyMode { requestTab(tab) } else { pendingRoute = Route.from(tab: tab) }
    }
    func applyPendingRoute() {
        if let m = pendingMac, appUnlocked && !decoyMode { pendingMac = nil; select(m) }
        guard let r = pendingRoute else { return }
        pendingRoute = nil
        if appUnlocked && !decoyMode { requestRoute(r) }
    }
    /// 293/951 Spotlight 结果 → 既有落点。两条路都是**别人用过的**口:
    /// 锁走 `kf://device?mac=` (与深链/小组件同一个 handleDeepLink)，
    /// 凭证走 `pendingCredNav` 那对状态 (与通知落地同一个词表，解析端 CredentialsView.consumeCredJump
    /// 会自己切锁并打开 pwd:/fp: 详情)。认不出的 identifier 什么都不做 —— 索引可能比台账慢半拍，
    /// 条目点不开就不跳，不拿"跳到一个空页"冒充直达。
    func handleSpotlight(_ activity: NSUserActivity) {
        guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
        if let url = SpotlightKit.deviceURL(for: id) { handleDeepLink(url); return }
        guard let t = SpotlightKit.credentialTarget(for: id) else { return }
        pendingCredNav = t.nav
        pendingCredNavMac = t.mac
        if appUnlocked && !decoyMode { requestRoute(.credentials) } else { pendingRoute = .credentials }
    }
    // ---------- 377 访客通道: 受限 Tab 的唯一走位口 ----------
    /// 受控跳转都汇到这里: 目标是被收起来的 Tab 且本会话没重输过口令, 就把既有应用锁页拉起来而不是切过去。
    /// 深链、粘贴条的"回凭证页"、自检黄条的"去诊断"这些编程式跳转原本直接写 tabSelection,
    /// 不并到这条口上就会留成绕过访客限制的侧门。
    /// 换页的**唯一漏斗**。377 访客闸也只在这里判一次。
    func requestRoute(_ r: Route) {
        // 现行行为逐字不变：受限区先过闸，不受限直接切 Tab。
        guard guestAreaLocked, Self.guestBlockedTabs.contains(r.tabIndex) else {
            tabSelection = r.tabIndex; return
        }
        guestGateTarget = r.tabIndex
        showGuestGate = true
    }
    /// 兼容适配器：2026-10-16 起全仓**代码里**已无 `requestTab(<字面量>)`（只剩注释引述），
    /// 仍在用的只有从深链序号 / List 选中集派生的动态形式；两者都汇到同一个漏斗。
    /// 越界序号 (历史脏值 / 以后加 Tab 忘了改) 直接丢弃而不是崩溃，也不静默切到别的页。
    func requestTab(_ t: Int) {
        guard let r = Route.from(tab: t) else { return }
        requestRoute(r)
    }
    /// 377: 底部那颗"凭证与设置"胶囊 —— 只放开受限区, 不指定落点
    func openGuestGate() {
        guestGateTarget = nil
        showGuestGate = true
    }
    // ---------- 54/372 摇一摇: 一个传感器, 一条路由口 ----------
    /// 54: 设备页摇动 → 迷你开锁面板 (浮层).
    @Published var shakePanel = false
    /// 372: 记录/凭证页摇动 → 遁到设置页; 这一位是"回位票", 再摇一次回到原页.
    /// 刻意是内存态: 回位票只在"正躲在设置页"期间有意义, 落了盘反而会跨启动诈尸.
    @Published var shakeReturnTab: Int?
    /// 54 与 372 同抢一个传感器 —— 按当前 Tab 定死优先级, 不做"两个都试试":
    /// 记录(2)/凭证(1) → 372 遁走 (走的还是 requestTab, 377 访客门禁照常);
    /// 设备(0) → 54 面板开合; 设置(3) → 不响应 (已经是遁走目的地, 再摇没有可去的地方);
    /// 未解锁 / 伪装态 → 不响应 (摇动不得绕过门禁). Tab 换了由 tabSelection.didSet 收拾过程态.
    func handleShake() {
        guard appUnlocked, !decoyMode else { return }
        if let back = shakeReturnTab {
            shakeReturnTab = nil
            tabSelection = back
            return
        }
        switch tabSelection {
        case 1, 2:
            shakePanel = false
            let before = tabSelection
            requestRoute(.settings)
            // 门禁拦下时没真到设置页, 不发回位票 (否则再摇一次会跳到没人去过的地方)
            shakeReturnTab = tabSelection == 3 ? before : nil
        case 0:
            if current != nil { shakePanel.toggle() }
        default:
            break
        }
    }
    /// 377/383 会话授权收回: 应用锁重新落下时调用 (含 393/394 到点自动锁, 也含安全中心里就地生效的访客开关)。
    /// 访客区与 sudo 说的都是"这一次会话内验过", 锁都重新落了还认旧账就等于没拦。
    /// 顺带把落在受限 Tab 的选中位收回设备页 —— 那两个 Tab 此刻已不在层级树里,
    /// 不收回就是一个选不中也看不见的空档。
    func revokeSessionGrants() {
        guestAreaUnlocked = false
        sudoTicket = nil
        showGuestGate = false
        guestGateTarget = nil
        if Self.guestBlockedTabs.contains(tabSelection) { tabSelection = 0 }
    }
    /// 377: 应用锁通道验过之后的落地。常规门禁置 appUnlocked; 受限区复核只放开 Tab 并跳到用户要的那页。
    /// 两条都从这一个出口走, 398 会话痕迹与 391 胁迫打标才是同一套口径, 而不是"另一套解锁的边角料"。
    func commitUnlock(reauth: Bool) {
        showGuestGate = false
        if reauth {
            guestAreaUnlocked = true
            if let t = guestGateTarget { tabSelection = t }
            guestGateTarget = nil
            return
        }
        withAnimation(DS.Motion.standard) { appUnlocked = true }
    }
    // ---------- 161 应用锁秒进: 验证通过后回到上次停留的 Tab ----------
    static let lastTabKey = "kf_last_tab"
    func rememberTab(_ t: Int) {
        guard appUnlocked, !decoyMode else { return }   // 锁着或空壳会话不记, 免得把伪装态当"上次停留"
        DB.store.set(AppState.lastTabKey, t)
    }
    /// 挂起的深链优先 (那是用户明确要去的地方), 否则回到上次停留的 Tab; 越界档位夹回四页内。
    func restoreLastTab() {
        guard appUnlocked, !decoyMode, pendingRoute == nil else { return }
        let t = min(max(DB.store.getInt(AppState.lastTabKey, 0), 0), 3)
        // 377: 上次停在 凭证/设置 而访客通道开着 ⇒ 既不拉门禁也不越界, 落在设备页
        // (恢复"上次停留"不是用户明示的跳转, 拿它去弹口令页就是每次解锁都可能被打断)
        tabSelection = guestAreaLocked && Self.guestBlockedTabs.contains(t) ? 0 : t
    }
    // 包14: 首启引导完成/跳过的会话内标记 (OnboardingView 触发, 驱动 RootView 切主界面)
    @Published var onboardingFinished = false
    // 包18: Hero 一句话 (1000 晚归) / 连续失败 (1003) / 一次性时刻卡队列 (24/992/1010/1021/1050)
    @Published var homeMoment: String?
    @Published var failStreak = 0
    @Published var moment: Moment?
    @Published var writeReceipt: String?   // 包8/508 写入回执: 凭证保存成功后"已写入本机"对勾浮出
    /// 344 粘贴建议条: 回前台瞬间从 ClipboardCare 取一次快照。状态源本身是内存态 (不落盘),
    /// 这里只是把它喂给 View 树; 每次刷新都重跑 changeCount 比对, 所以"还在剪贴板"是可被证伪的说法。
    // 517 粘贴来源条: 检测到剪贴板里有本 App 相关的敏感值时给出的提示条 (RootView 挂在非凭证页的顶部)。
    // 为什么是全局一条而不是每个输入框一条: 清除动作要作用于**剪贴板**而不是某个字段,
    // 每个字段一条会同时出现好几个"清除"按钮，指向的却是同一份剪贴板内容。
    @Published var pasteSuggestion: ClipboardCare.Suggestion?
    func refreshPasteSuggestion() { pasteSuggestion = ClipboardCare.suggestion }
    // ---------- 同屏"闲时提醒"预算 (乱源治理第 2 批) ----------
    /// 827: 本会话里已点过的快捷格。原先挂在 DeviceHomeView 的 @State 上，而"谁上台"要看全局排位 ——
    /// 视图层的 @State 预算读不到，所以这一位搬到状态源 (判据一条没改，只是换了存放处)。
    @Published var ambientTipUsed: Set<String> = []
    /// 827 「不再提示」的即时状态。写盘那份是 HintOnce(偏好)，而 UserDefaults 不是可观察源 ——
    /// 只改盘不改状态，这行提示会留到下次进页才消失，看起来像按钮没反应。
    @Published var ambientTipOff = HintOnce.shown("827off")
    /// 42/268 首用气泡的同一条坑: HintOnce 写的是偏好盘，而盘不是可观察源 —— 只 mark 不改这一位，
    /// 气泡会留到下一次状态变化才消失，看起来就是"点掉它没反应"。与 ambientTipOff 同一手法成对出现。
    @Published var firstUseCapsuleDone = HintOnce.shown("capsule268")
    /// 汇总胶囊的承载页
    @Published var showAmbientList = false
    /// 827: 显示顺序里"还没被点过"的第一格; 全部点过或用户关了提示 ⇒ nil (整行不占位)。
    /// 判据三选一即算用过: 本次会话点掉过、以前点掉过、或 QuickPool 频次表里已有点击 ——
    /// 1047 静默学习只在没被手动关过时开着 (SettingsView 那条"关掉就清空计数"的承诺由 QuickPool.recordingOn 兑现)。
    var quickTipTile: QuickAction? {
        guard !ambientTipOff, !HintOnce.shown("827off") else { return nil }
        let c = QuickPool.counts
        return QuickPool.ordered().first { a in
            if ambientTipUsed.contains(a.id) || HintOnce.shown("827seen_" + a.id) { return false }
            return (c[a.id] ?? 0) == 0
        }
    }
    /// 当前成立的全部闲时提醒，按优先级排好。第 0 条上台，其余进汇总胶囊。
    /// 刻意在这里一次算完 (而不是每条横幅自己 `if`)：六条各自独立判断时，"这屏已经有别的在说话"这件事没人知道。
    var ambientRanked: [Ambient] {
        var out: [Ambient] = []
        if BackupStudio.selfCheckWarning != nil { out.append(.selfCheck) }
        if pasteSuggestion != nil, tabSelection != 1 { out.append(.pasteCare) }   // 站凭证页时不挂 (人就在那, 不用指路)
        // 42/268 首用气泡承诺的热点是「主控卡上的连接耗时标记」= ConnectMsBadge (67, hero 上的胶囊),
        // 单锁也画 ⇒ 不看 devices.count。我上一版照旧注释里"这排胶囊"的说法加了 >1 的闸, 那会把
        // 单锁用户的首用提示整个吞掉 —— 已收回 (文案说的是哪一块, 得以代码里那块真画不画为准)。
        if !firstUseCapsuleDone { out.append(.firstUseCapsule) }
        if quickTipTile != nil { out.append(.quickTileTip) }
        return NoticeBudget.ranked(out)
    }
    var ambientTop: Ambient? { ambientRanked.first }
    var ambientRest: [Ambient] { Array(ambientRanked.dropFirst()) }

    /// 397 本机库体自检 (三项都是本地只读, 不碰 BLE)。结果存这里给诊断页显示, 返回异常项数给调用方决定要不要出声。
    /// 拆成"跑/存"与"提示"两步是因为: 解锁路径只在异常时提示 (每次解锁都弹"一切正常"会被关掉),
    /// 而手动按钮必须无论结果都给反馈。
    @Published var selfCheck397: [SelfCheckLine] = []
    @discardableResult
    func runSelfCheck397() -> Int {
        let ls = SelfCheck.run()
        selfCheck397 = ls
        let bad = ls.filter { !$0.ok }
        if let first = bad.first {
            lock.log("warn", "本机自检 \(bad.count) 项异常: \(first.name) — \(first.detail)")   // 397 本机自检
        }
        return bad.count
    }
    // 包1: 开锁过程态 — 80 三段进度 / 85 重试节奏 / 250 二次开锁应用锁闸
    @Published var phase = 0            // 0 空闲 · 1 握手 · 2 鉴权 · 3 执行
    @Published var retryWait: Int?      // 85 自动重试倒计时 (秒)
    @Published var retryAttempt = 0     // 85 即将执行第几次尝试
    @Published var showGate = false     // 250 二次开锁需过应用锁
    // 包3/779: 多锁矩阵点格 → 记录 Tab 带入成员过滤 (RecordsView 消费后清空)
    @Published var pendingRecordsFilter: String?
    // 包2/136 补充: 跨页跳回 — 记录/告警入口点"跳回设备页定位该锁"时, 落点即选中并提示
    @Published var pendingJumpLock: String?
    // 包9/577 详情跳凭证: 记录/告警详情"来源凭证"→ 凭证 Tab 定位该条并高亮 (值 = "pwd:<alias>" / "fp:<batch>", mac 另存)
    @Published var pendingCredNav: String?
    @Published var pendingCredNavMac: String?
    /// 366/1013 通知点按 → 凭证 Tab 的对应面板。与 pendingCredNav (577 定位到单条凭证) 是两回事。
    /// 应用锁未解开时凭证 Tab 根本不在层级树里, 值就一直挂着 → 解锁后 onAppear 才落地 (通知不得绕过门禁)
    @Published var pendingCredPanel: String?
    /// 358 整理建议 → 凭证页多选预勾选: 建议行点按带过来要勾的密码 alias 表。
    /// 与 pendingCredPanel (到了开哪个面板) 是两回事 —— 这个负责"进了多选先勾好哪些", 同 pendingRecordKey 族只存会话态。
    @Published var pendingCredSelect: [Int]?
    // 包9/582 图表下钻: 统计页成员条 → 记录 Tab 按该成员过滤
    @Published var pendingRecordsMember: String?
    /// 817 成员示例格直达建档: 记录页空态/过滤条的「添加成员」→ 成员中心到达即弹建档向导。
    /// 与 pendingRecordsMember 同类: 只负责"到了那页之后做什么", 落地仍走同一个 Tab 门禁。
    @Published var pendingMemberAdd = false
    /// 317 指纹工坊无成员直达: "request"=已请人建档; 建完改写为新成员 id, FpStudio 取走预选
    @Published var pendingFpOwner: String?
    /// 585 记录引用深链: `kf://records?k=<行键>` 带回来的**行内定位键**。
    /// 与 pendingCredNav (577) 同类: 只负责"到了那页之后定位哪条"，落地仍走同一个 Tab 门禁 ——
    /// 查询参数不是第二条入口，锁着的时候和 pendingRoute 一起挂起。
    @Published var pendingRecordKey: String?
    /// 586 当天全景: 详情卡"查看当天全部"带过去的**日键** (yyyy-MM-dd)。记录页收到后只保留那一天的组
    /// (是收窄显示范围，不是改筛选条件 —— 与 580 翻页用的是同一套"别悄悄改用户的过滤"的口径)。
    @Published var pendingRecordsDay: String?
    /// 583 结果定位高亮: 深链/当天全景落地后要闪一下的那一行。与 pendingRecordKey 成对使用。
    @Published var pendingFlashKey: String?
    /// 563 搜索词快照回填: 从告警详情"搜这类记录"带过去的**词** (到达后可再编辑再执行)。
    /// 只带一个字符串而不是带着一整套筛选: 回填的意义是"接着人话往下查"，把面板整个改掉会让人找不到自己刚才在哪。
    @Published var pendingSearch: String?
    /// 587 低电告警 → 这台锁的诊断: 记录详情带过去的**mac**。设置 Tab 收到后先把 current 切到该锁
    /// 再推诊断页 —— 原写法只置 tabSelection=3, 全仓无消费方, 按钮等于没落点。
    @Published var pendingDiag: String?
    /// 1013 保养到期通知 → 这台锁的维护与保养页: 通知层只带 mac 进来 (m4.care.<mac>),
    /// 设置 Tab 收到后切 current 再推页 —— 与 587 同一条路由形态, 不新造第二套。
    @Published var pendingCare: String?
    /// 801 引导末卡"去连接真锁": 置真后设备页挂载即拉起添加设备弹层
    /// (旧写法只切 tab, 落点靠用户自己在设备页再找入口, 不等于"直达 BLE 扫描页")
    @Published var pendingAddDevice = false
    /// 2026-10-15 走查: 设置 Tab **栈内**子页的"去设置…"落点。
    /// 起因: 安全中心里的两枚按钮 (`SecurityLockConfigView` 的"去「设置」把本机密码重设为纯数字"、
    /// `SecurityDestroyView` 销毁前备份闸的"先去备份") 动作都写着 `app.tabSelection = 3` ——
    /// 而它们本来就是**设置 Tab 下 push 进去的页**, 切 Tab 是一次空转: 点了什么都不发生,
    /// 前者还配着"跳转设置 Tab 的密码区"的无障碍提示, 后者配着"已切到设置"的 toast。
    /// 与 pendingDiag / pendingCare 同一条路由形态: 把"到了之后开什么"带过去, 设置页收到即开并清空。
    @Published var pendingSettingsFocus: String?
    private var unlockTask: Task<Void, Never>? = nil
    private var lastDispatch = Date.distantPast   // 244 指令去重
    private var dispatchAt = Date.distantPast     // 56 撤销窗口计时基准
    private var lastUnlockSuccessAt: Date?        // 250 30 秒内二次开锁判定
    private var momentQueue: [Moment] = []
    let lock = LockService.shared
    let hw = HardwareService.shared

    enum UnlockState: Equatable {
        case idle, connecting, opening, success, doubleVerify, failed(String)
        var isFailed: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    init() {
        // 2026-10-17 拍板 A: 删掉启动门禁 —— 打开 App 不再需要本机密码/FaceID。
        // 旧值 `!DB.hasPasscode()`: 设过密码的机器每次冷启动都停在 AppLockView。
        // 其余安全动作 (毁灭操作复核 383 / 访客受限区复核 377) 改成**只走面容/指纹**。
        appUnlocked = true
        loadDevices(preferDefault: true)   // 包3/271: 冷启动落到上滑固定的默认锁
        // 366/1013: delegate 此前只在"排月度备份提醒"那条路径里顺手装 (BackupStudioKit:108)
        // → 没开月备的用户点任何本地通知都没反应。分派器必须在启动就装好, 与是否开月备无关。
        UNUserNotificationCenter.current().delegate = UNDelegate.shared
        // 374: 录屏采集监听在启动就装好 —— 遮罩只有在"进详情页之前"就知道状态才有意义
        ScreenCaptureWatch.shared.start()
        // 54/372: 摇一摇信号在启动就装好, 与当前页无关 —— 落点由 handleShake 按 Tab 分流.
        // 不移除观察者: 单例的存活期就是进程期.
        //
        // 怎么接的 (2026-10-13 改): 原先写 `UIAccessibility.shakeNotification` —— Apple **从未**公开过
        // 这个符号 (UIKit 的无障碍通知名清单里没有它), 所以编译不过。改从 `UIWindow.motionEnded`
        // 改成一层零尺寸 UIViewController 接住 motionEnded, 转成 App 内 .kfDeviceShake 通知 ——
        // 这是唯一真正会到达的做法: WindowGroup 的 window 由框架自建, 换不成自建子类。
        NotificationCenter.default.addObserver(forName: .kfDeviceShake,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleShake() }
        }
    }

    var current: Keychain? {
        devices.first { $0.mac == currentMac } ?? devices.first
    }
    /// 当前锁的显示名。**口径在 `LockArchive.displayName` 一份** ——
    /// 这里曾经把那四行 (pidName 优先、含 "pid="/"未知" 时退回 PidMap、再退 mac) 逐字抄了一遍，
    /// 两处今天恰好同值，但改一处就会让"标题里的锁名"和"锁选择器/统计页里的锁名"不一样 (§10.30)。
    var displayName: String {
        guard let kc = current else { return "离线锁管家" }
        return LockArchive.displayName(kc)
    }
    // 包3/idea 271: 上滑固定的启动默认锁 — 冷启动落在默认锁; 无默认时维持原有"上次选中"行为
    func loadDevices(preferDefault: Bool = false) {
        devices = DB.keychains()
        let def = LockArchive.defaultMac
        let saved = DB.currentMac
        var next: String
        if preferDefault, devices.contains(where: { $0.mac == def }) {
            next = def
        } else if devices.contains(where: { $0.mac == saved }) {
            next = saved
        } else {
            next = devices.last?.mac ?? ""
        }
        if next != currentMac { status = nil }   // 设备身份变了 → 清实时状态 (原会沿用上一把锁的电量/固件)
        currentMac = next
        snapshot = DB.readStatus(currentMac)
    }
    func select(_ mac: String) {
        DB.currentMac = mac
        currentMac = mac
        status = nil
        snapshot = DB.readStatus(mac)
        Task { await refreshStatusQuietly() }
    }
    /// 127 静默排查的口径是"只停自动的那部分，手动照常" (DiagnosticsView 底部 footer 也是这么承诺的)。
    /// 第九十一批补上这条闸: 此前 `refreshStatusQuietly` 完全没有看 `DiagFlags.silent`，
    /// 而它被两处**自动**路径调用 —— 切锁 (:181 select) 与开锁后的复位定时器 (:356)，
    /// 于是"开了静默还在自动连锁读状态"，干净复现问题的口径是假的 (AUDIT-A §127 那条 gap 至今成立)。
    /// 用户主动的刷新与"下发后回读校验"传 `manual: true` 照连 (不传就把 cmd20 的回读也一起吞掉)。
    func refreshStatusQuietly(manual: Bool = false) async {
        guard manual || !DiagFlags.silent else { return }
        guard let kc = current else { return }
        do {
            try await lock.ensureConnected(mac: kc.mac)
            status = try await lock.getStatus()
            LockArchive.touchConnected(kc.mac)   // 包3/292: 连接成功刷新沉睡判定基准
        } catch {
            status = nil
        }
    }
    /// 包8/508 写入回执: 2 秒内浮出对勾, 替代云同步反馈 (纯本地, 不碰网络)
    func flashReceipt(_ msg: String) {
        writeReceipt = msg
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if writeReceipt == msg { writeReceipt = nil }
        }
    }
    func showToast(_ msg: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { toast = msg }
        // 长文案多停留一会儿, 保证读得完
        let stay: UInt64 = msg.count > 20 ? 3_400_000_000 : 1_800_000_000
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: stay)
            if toast == msg {
                withAnimation(.easeIn(duration: DS.Duration.quick)) { toast = nil } // idea 211 时长令牌
            }
        }
    }

    // 开锁 (App opendevice 语义: rc=0 成功 / rc=22 双验继续 / 其余报错)
    // 包1 手势族统一入口: 按住确认/上滑/VO 直开都汇到 requestUnlock。
    // 防误触三保险: 244 去重队列 → 250 二次开锁应用锁 → 56 撤销窗口 (执行期轻点)。
    func requestUnlock() {
        // 296 只读安全模式: 圆盘、快捷操作、AppIntents、深链这几条侧门全汇到这一个入口,
        // 拦在这里就等于拦住了"开锁"这一族动作本身, 而不是拦住某一个按钮。
        guard SecurityPolicy.allows(.unlock) else {
            showToast(SecurityPolicy.denialMessage(.unlock))
            return
        }
        guard current != nil else { return }
        if unlockState == .connecting || unlockState == .opening {
            // 56: 指令发出后 0.8s 内轻点圆盘 = 撤销 — 拦截回执等待与自动重试链
            // (BLE 字节一旦发出无法撤回, 与 244/250 共同构成防误触保险, 不虚构"已撤回指令");
            // 自动重试等待期轻点 = 取消重试, 转手动
            if unlockState == .opening,
               Date().timeIntervalSince(dispatchAt) < 0.8 || retryWait != nil {
                cancelUnlock(notify: true)
            }
            return
        }
        let now = Date()
        // 244 指令去重: 1.2s 内的重复触发只提示, 不重复入队
        guard now.timeIntervalSince(lastDispatch) > 1.2 else {
            showToast("指令已收到, 正在执行")
            return
        }
        lastDispatch = now
        // 250: 同一锁 30 秒内再次开锁, 先过应用锁验证 (未设本机密码则无此闸)
        if DB.hasPasscode(), let t = lastUnlockSuccessAt, now.timeIntervalSince(t) < 30 {
            showGate = true
            return
        }
        startUnlock()
    }

    func startUnlock() {
        // 296: 这一层还有两个不走 requestUnlock 的来源 —— 靠近自动开锁 (AutoOpen.swift:291)
        // 与 250 二次开锁闸放行后的重发。闸落在这里, 自动档就开不了"只读模式还能自己开门"这个口子。
        guard SecurityPolicy.allows(.unlock) else {
            showToast(SecurityPolicy.denialMessage(.unlock))
            return
        }
        unlockTask?.cancel()
        // 836 演练包装层: 演示模式下开锁全走本地模拟 (不碰 BLE/协议/失败日志), 三阶段节奏同真实路径
        if DemoKit.isOn {
            demoUnlock()
            return
        }
        unlockTask = Task { await runUnlock() }
    }

    private func demoUnlock() {
        DemoKit.simulateDemoUnlock(phase: { p in
            self.phase = p
            self.unlockState = p == 1 ? .connecting : .opening
        }, onDone: {
            self.unlockState = .success
            self.phase = 0
            self.finishDemoDwell()
            self.showToast("演示开锁成功 (demo_ 不碰真实门锁)")
        })
    }
    private func finishDemoDwell() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if unlockState == .success {
                unlockState = .idle
                phase = 0
            }
        }
    }

    /// 56/89: 提前取消 (撤销窗口 / 握手超时取消按钮)
    func cancelUnlock(notify: Bool = false) {
        unlockTask?.cancel()
        unlockTask = nil
        phase = 0
        retryWait = nil
        if unlockState == .connecting || unlockState == .opening {
            unlockState = .idle
            if notify { showToast("已取消") }
        }
        // 2026-10-14: 取消也要收起实时活动 —— 否则 current 未清, 下一次 begin() 被 `current == nil` 挡掉,
        // 新开锁没有锁屏活动, 旧的"连接中"还挂在锁屏 (30s staleDate 只是标脏, 不会自动 end)。
        LiveUnlock.failed()
    }

    // ---------- 246 本次用哪条 PIN ----------
    /// 存的是**下标**而不是 PIN 本身 —— 口令留在钥匙串 (kc.pins) 里, 不落 UserDefaults。
    /// -1 / 越界 = 未选, 交给 LockService 走既有的 `kc.pins.first` 兜底 (老行为不变)。
    func chosenPinIndex(_ mac: String) -> Int { DB.store.getInt("kf_pinpick_" + mac, -1) }
    func setChosenPinIndex(_ mac: String, _ i: Int) { DB.store.set("kf_pinpick_" + mac, i) }
    /// 解析成本次开锁要用的 PIN; nil = 不指定 (与从前逐字节相同)
    func chosenPin(_ kc: Keychain) -> String? {
        let i = chosenPinIndex(kc.mac)
        return (i >= 0 && i < kc.pins.count) ? kc.pins[i] : nil
    }

    private func runUnlock() async {
        guard let kc = current else { return }
        let attempts = DB.store.getBool("kf_auto_retry", true) ? 3 : 1
        var lastMsg = ""
        var lastRc: Int? = nil   // 86: 服务层回的错误码 (异常路径没有码, 保持 nil)
        let liveToken = LiveUnlock.begin(lockName: displayName)   // 77/939/941: 锁屏/灵动岛起一场"连接中" 
        for attempt in 1...attempts {
            phase = 1
            unlockState = .connecting
            do {
                try await lock.ensureConnected(mac: kc.mac)
                LinkSense.shared.noteUserConnect()   // 98 冷热标识: 用户触发的连接标"即连"
                phase = 2
                dispatchAt = Date()   // 56 撤销窗口从指令真正发出起算
                unlockState = .opening
                let rc = try await lock.unlock(mac: kc.mac, pinDec: chosenPin(kc))   // 246: 带上下拉胶囊选的那条
                phase = 3
                if rc == 0 {
                    settleUnlockSuccess()
                    return
                }
                if rc == 22 {
                    unlockState = .doubleVerify
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    finishDwell(.doubleVerify)
                    LiveUnlock.fail(liveToken)   // 2026-10-14: 双验档本次流程结束, 收起活动 (代次校验)
                    return
                }
                lastRc = rc                             // 86: 错误码进失败快照
                lastMsg = StatusParser.rcFriendly(rc)   // 84 人话直读
            } catch is CancellationError {
                LiveUnlock.fail(liveToken)   // 2026-10-14: 取消路径也收活动 (代次校验: 不误收新开锁的活动)
                return   // cancelUnlock 已复位, 不计入失败
            } catch {
                lastMsg = error.localizedDescription
            }
            // 超时不自动重试: 指令可能已生效 (门已开只是没回执), 再发一次就是第二次开锁动作
            if lastMsg.contains("超时") { break }
            failStreak += 1   // 87 三连败排查清单按尝试次数累计
            // 83/85: 前两次自动静默重试, 退避 2s/5s 并显示节奏文案; 之后转手动
            if attempt < attempts, !Task.isCancelled {
                retryAttempt = attempt + 1
                for w in stride(from: attempt == 1 ? 2 : 5, through: 1, by: -1) {
                    retryWait = w
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
                retryWait = nil
                continue
            }
            break
        }
        // 终态失败: 直读原因 (84) + 写入时间线标记 (92)
        unlockState = .failed(lastMsg)
        phase = 0
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        AlertTone.unlockFailure()   // 848 失败短音: 只在走完重试链的终态响, 独立开关默认关
        // 86 失败快照: 失败当时的 RSSI / 电量 / 错误码一起留痕 (电量取本机缓存读数, 与 125 同一份口径)
        DB.recordFailEvent(kc.mac, lastMsg,
                           rssi: LinkSense.shared.lastRssi,
                           pct: DB.readStatus(kc.mac)?.powerLevel,
                           rc: lastRc)
        LiveUnlock.fail(liveToken)   // 77/939/941: 失败立刻收起 (代次校验: 不误收新开锁的活动)
        finishDwell(.failed(lastMsg))
    }

    /// 收尾复位: 只复位"本次操作的结果态", 用户中途已重试则不得覆盖。
    /// 成功档 2s 回待机并轻提示可查记录 (idea 247, 每天只提示一次)。
    private func finishDwell(_ finished: UnlockState) {
        let dwell: UInt64
        switch finished {
        case .success: dwell = 2_000_000_000
        case .doubleVerify: dwell = 4_200_000_000
        default: dwell = finished.isFailed ? 3_000_000_000 : 4_200_000_000
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: dwell)
            if unlockState == finished {
                unlockState = .idle
                phase = 0
                if case .success = finished { unlockReturnedHint() }
            }
            await refreshStatusQuietly()
        }
    }
    private func unlockReturnedHint() {
        let day = Milestones.dayKey()
        if DB.store.getString("kf_unlock_hint_day") != day {
            DB.store.set("kf_unlock_hint_day", day)
            showToast("本次开门已记录, 可到「记录」回看")
        }
    }
    // ---------- 外观变更 (包16: idea 21/30/31/202/910) ----------
    // 21 主题切换 crossfade: 统一入口 = 写存储键 → withAnimation 播 crossfade → 种子驱动 RootView .id 重建
    private func applyAppearance(_ mutate: () -> Void) {
        mutate()
        withAnimation(DS.Motion.soft) { appearanceSeed &+= 1 }
    }
    /// 外观模式: ""/light/dark/black
    func setTheme(_ key: String) {
        applyAppearance {
            DB.store.set("kf_theme", key)
            themeSeed = key
        }
    }
    /// 品牌主题: indigo/forest/amber
    func setAccent(_ key: String) {
        applyAppearance { DB.store.set("kf_accent", key) }
    }
    /// 布局密度: ""(标准)/compact/relaxed
    func setDensity(_ key: String) {
        applyAppearance { DB.store.set("kf_density", key) }
    }
    /// 893 App 内高对比皮肤: 与系统"增加对比度"并联，任一开着就加强
    func setHighContrast(_ v: Bool) {
        applyAppearance { DB.store.set("kf_hc", v) }
    }
    /// 900 全局圆角档位: ""(标准)/soft/plump
    func setRadius(_ key: String) {
        applyAppearance { DB.store.set("kf_radius", key) }
    }
    /// 912 周起始日: ""(跟随系统)/mon/sun/sat。走外观通道 ——
    /// 周界变了的话"本周"区、月历表头与轮值键都要重算，留着旧值就是三处各说一套。
    func setWeekStart(_ key: String) {
        applyAppearance { DB.store.set("kf_week_start", key) }
    }
    /// 901 凭证行高: ""(标准)/tall
    func setRowHeight(_ key: String) {
        applyAppearance { DB.store.set("kf_row_h", key) }
    }
    /// 907 时间线行距: ""(标准)/tight/loose
    func setTimelineGap(_ key: String) {
        applyAppearance { DB.store.set("kf_tl_gap", key) }
    }
    /// 909 Hero 参考指标位 (电量不参与)
    func setHeroStats(_ ids: [String]) {
        applyAppearance { DS.HeroStats.setVisible(ids) }
    }
    /// 889 主控卡纹理: ""(无)/grid/grain，白名单在 DS.Metric.heroTexture 里守
    func setHeroTexture(_ key: String) {
        applyAppearance { DB.store.set("kf_hero_tex", key) }
    }
    /// 898 主控卡每日一句话 (按当天定值，不是每次刷新随机)
    func setLaunchLine(_ v: Bool) {
        applyAppearance { DB.store.set("kf_launch_line", v) }
    }
    /// 890 节日限定色 (默认关)：走外观通道，切换当天 hero 立刻重新取值
    func setFestive(_ v: Bool) {
        applyAppearance { DB.store.set("kf_festive", v) }
    }
    /// 899 动效强度: calm/standard/lively (系统"减弱动态"会在令牌层把任何档压到 calm)
    func setMotionTier(_ key: String) {
        applyAppearance { DB.store.set("kf_motion", key) }
    }
    /// 最近开门条数 (idea 910): 3/5/10
    func setRecentCount(_ n: Int) {
        applyAppearance { DB.store.set("kf_recent_count", n) }
    }
    /// 包1 开锁偏好 (76 提示音 / 62 围栏 / 249 圆盘尺寸 / 按住确认 / 自动重试):
    /// 区分两类 —— 参与布局/外观求值的走整树重建 (让圆盘/密度即时生效)，纯行为类只发轻量信号。
    ///
    /// 2026-10-14 修"设置页拨开关就跳回顶部": 旧实现**一律**走 applyAppearance ⇒ 每次拨开关都给
    /// `.id(app.appearanceSeed)` 换身份，整棵子树被销毁重建 (该语义见 rootCore 与 390 那条注释)：
    ///   · 设置页 List 的滚动位置直接回到顶部 (UITableView 的 contentOffset 随视图树一起销毁);
    ///   · `.task` 整段重放、coldStartScan 再起一轮、onLaunch 再跑一遍 (390 那条已用 launchBootstrapped 兜住)。
    /// 而这批键没有一处参与配色/密度/圆角/行高/动效求值 (逐个 grep 过读取点: 全在"用时求值" ——
    /// 开锁流程 / 提示音播放 / 通知排程 / 语音播报)，根本不需要整树重建。
    /// 改为只 bump `prefSeed`：视图体照常重算 ⇒ Toggle 的 get 重读 ⇒ 视觉翻转，
    /// 而**视图身份不变** ⇒ 滚动位置、键盘焦点、动画上下文全部保留。
    static let behaviorKeys: Set<String> = [
        "kf_hold_confirm", "kf_fence", "kf_tap_direct",
        "kf_unlock_sound", "kf_unlock_fail_sound", "kf_auto_retry",
        "kf_alert_tone", "kf_duress_tone",
        "kf_status_checkin", "kf_status_checkin_hour", "kf_vo_announce",
        // 2026-10-15 走查 §7.4-10: 无障碍那批键此前全部走 applyAppearance ⇒ 换身份 ⇒ 整树重建
        // = **拨一次开关被弹回设置页顶部**（同一条病灶作者已用上面这批治过）。这十枚并入的准入条件是逐键查出来的：
        // 它的**全部**读取点都落在"会因 AppState 的 @Published 变化而重算 body"的位置 ——
        //   · 根上那两枚修饰符 `.dynamicTypeSize(...)` / `.saturation(...)` 挂在 `.id(app.appearanceSeed)`
        //     **之外**、RootView.body 之内，而 RootView 观察 app ⇒ prefSeed 一样让它们重算，
        //     "根层修饰符"不构成否决（这条最反直觉，是 kf_ax_gray / kf_ax_bigpreview 能并的依据）；
        //   · UnlockDial 自己不观察 app，但 `kf_hold_confirm` / `kf_fence` 早就在里面以同一形状
        //     （计算属性喂 body）被读、且已在名单里跑了很久 ⇒ `kf_dial_size` / `kf_gesture_mode` /
        //     `kf_ax_hold` 走的是同一条级联，不是新机制；
        //   · `kf_onehand` 的读取是 `axOnehand(_ on: Bool = AXPrefs.onehand, …)` 的**默认实参**，
        //     每次调用点展开求值，不是"构造时读一次"；
        //   · `kf_ax_doublehaptic` / `kf_ax_bigotp` / `kf_ax_captions` / `kf_bigtile` 的读点都在 obs 宿主体内。
        // **刻意没并的四枚**（判据不齐，宁可留着"跳顶"这个已知 annoyance，也不把开关改成"拨了没作用"）：
        //   `kf_ax_dwell`（除滑杆与演示文字外**没有任何行为消费者**）、
        //   `kf_font_scale`（档位变 = 全树布局尺寸变，UIKit-backed 的 List 行不换身份能否重取档位，本机无证据）、
        //   `kf_form_bottom`（`defaultScrollAnchor` 的语义是"首次布局时的锚点"，偏好变了而不换布局身份能否把已存在的 List 重新锚底，未知）、
        //   `kf_lefty`（`HeroCard` 不观察 app，且值不从父层传入、没有传参链可追，只能指望级联 —— 无证据可证死也无证据可证活）。
        // 这一条要真收口，得等一次真机：把四枚逐一试"拨完不退出页面，值是否即时生效"。
        "kf_ax_bigotp", "kf_ax_bigpreview", "kf_ax_captions", "kf_ax_doublehaptic",
        "kf_ax_gray", "kf_ax_hold", "kf_bigtile", "kf_dial_size",
        "kf_gesture_mode", "kf_onehand"
    ]
    func setUnlockOption(_ key: String, _ v: Any) {
        DB.store.set(key, v)
        if Self.behaviorKeys.contains(key) { prefSeed &+= 1 }
        else { applyAppearance {} }
    }
    /// 894 恢复带外观段的备份后重取外观。
    /// 为什么必须由 UI 层显式调：themeSeed / appearanceSeed 是 AppState 的内存镜像，
    /// 备份导入走的是 Store 落盘，不会自动改这两个值 —— 不刷就会"包里是深色、屏幕还是浅色"，
    /// 要等冷启动才生效 (那就是"恢复了但看着没恢复"的那类投诉)。
    func reloadAppearance() {
        themeSeed = DB.store.getString("kf_theme")
        applyAppearance {}
    }
    /// 905/1047 快捷格池子或"常用排前"变了：只需要重建一次树让新次序生效，
    /// 不涉及配色，所以走同一条外观通道 (它本来就是"重建全树"的通道，名字里的 appearance 是历史包袱)。
    func bumpAppearanceForLayout() { applyAppearance {} }
    /// 892 自定义强调色 (0 = 取消, 回到六套预设)。走外观通道：Palette.themed 是在 UIColor provider 里读的，
    /// 不重建树的话"选了色但界面不动"，要等下一次冷启动才生效。
    func setCustomAccent(_ hex: UInt32) {
        applyAppearance { DS.CustomAccent.set(hex) }
    }
    /// 895 "儿童友好"预设：一次推五档外观。**必须走外观通道** ——
    /// DS.FriendlyPreset.apply() 只写 Store，不重建树就会"按了没反应、重进 App 才变"（本仓最常见的那类缺陷）。
    func applyFriendlyPreset() {
        applyAppearance { DS.FriendlyPreset.apply() }
        showToast("已套用友好预设：只改了外观档位（品牌色/圆角/密度/行高/动效/纹理），"
                  + "本 App 没有内容分级，任何一档都能单独改回")
    }
    /// 恢复默认外观 (idea 202): 只重置外观偏好, 不触碰任何门锁数据。
    /// 清单必须与"外观"节里出现的键一一对应 —— 包16 加圆角/高对比时这里同步补上。
    /// (902 数字字体在役: kf_digit_font 只圈定 MetricTile/HeroStat 两处落点 (DesignSystem.digitDesign),
    ///  不是全 App 总闸 —— 原版 §84 那种总闸才要动 58 处散点, 撤的是它; 这一档是后来按实圈定重做的。
    ///  键在役, 就必须进这张重置清单, 否则"恢复默认"会漏掉它, 而确认弹窗写的是"将外观重置为默认值"。)
    func resetAppearance() {
        applyAppearance {
            DB.store.set("kf_theme", "")
            DB.store.remove("kf_accent")
            DB.store.remove("kf_density")
            DB.store.remove("kf_radius")
            DB.store.remove("kf_hc")
            DB.store.remove("kf_week_start")
            DB.store.remove("kf_row_h")
            DB.store.remove("kf_tl_gap")
            DB.store.remove("kf_hero_stats")
            DB.store.remove("kf_accent_custom")   // 892
            DB.store.remove("kf_hero_tex")
            // kf_launch_line 默认开：remove 就是回到默认，不是"关掉"
            DB.store.remove("kf_launch_line")
            DB.store.remove("kf_festive")
            // kf_motion 的默认档是 "standard"，remove 就等于回到默认 (不是关掉动效)
            DB.store.remove("kf_motion")
            DB.store.remove("kf_icon_season")
            DB.store.remove("kf_icon_season_last")
            DB.store.remove("kf_digit_font")   // 902
            themeSeed = ""
        }
    }

    // ---------- 包18: 庆祝与成就 ----------
    /// 一次性时刻队列: 去重入队, 逐张呈现 (MomentCardView 见 Celebration.swift)
    func enqueueMoment(_ m: Moment) {
        guard !momentQueue.contains(where: { $0.id == m.id }), moment?.id != m.id else { return }
        momentQueue.append(m)
        if moment == nil { advanceMoment() }
    }
    func advanceMoment() {
        withAnimation(DS.Motion.soft) { moment = momentQueue.isEmpty ? nil : momentQueue.removeFirst() }
    }
    /// 成就结算 (开锁/备份/整理/打卡后调用): 音效(996)/本地通知(986)/时刻卡或 toast
    func evaluateAchievements() {
        for b in Milestones.evaluate() {
            if Milestones.collectSound && !Milestones.plainMode { Milestones.playCollectSound() }
            if Milestones.achNotify { Task { await Milestones.notifyAchievement(b) } }
            if Milestones.plainMode {
                showToast("徽章点亮: \(b.title)")
            } else if b.rarity == .epic {
                enqueueMoment(Moment(id: "m18." + b.id, icon: b.icon, title: "徽章点亮",
                                     subtitle: "\(b.title) · \(b.rarity.title)", celebrate: true))
            } else {
                showToast("成就达成: \(b.title)")
            }
        }
    }
    /// 启动结算: 跨年烟花(1021) / 安装周年卡(1050) / VoiceOver 记录(1049) / 成就补结算
    func onLaunch() {
        Milestones.bootstrap()
        // 963 每晚状态确认通知: 启动这一趟负责把排期对齐当前开关 (开关/免扰/台账任一变化都要重排)。
        // 授权沿用 CareSchedule 那一份请求口, 不弹第二个系统授权框。
        Task { await StatusCheckNotice.requestAuthAndSync() }
        // 758 启动提示: 上次异常退出时先给一张时刻卡 —— 此前只有走进诊断页才看得到那条标签,
        // "启动时提示"这一半不存在。防重键带档案首行 (含检测时刻), 同一次异常只弹一次。
        if CrashGuard.pendingAbnormal, let top = CrashGuard.archList().first,
           !Milestones.onceDone("crash758_" + top) {
            Milestones.markOnce("crash758_" + top)
            enqueueMoment(Moment(id: "crash758", icon: "exclamationmark.triangle",
                                 title: "上次是异常退出",
                                 subtitle: "时长与最后操作存在诊断页「异常退出档案」里, 进去可以核对。"))   // 758 时长与最后操作存在诊
        }
        // 385 保留期到期: 启动时自动物理删除 + 重封链 + 留清理记录 (此前只靠安全中心手动按钮才会碰它);
        // months=0 (永久) 时 purgeExpired 内部直接返回, 无须另判。
        // 752 清理前导出提醒: 自动这一支现在也过诊断页/销毁共用的**同一道备份闸** (DestroyKit.backupGatePass,
        // 口径 = 7 天内有本机备份)。闸没放开就**不删**, 只弹一张卡指去「设置-备份与恢复」;
        // 导过一次之后下次启动自然会把这批清掉。手动按钮那边仍是当场二次确认 (那边有人在场, 这里没有)。
        let retention = DB.store.getInt(SecKey.auditRetention, 0)
        if retention > 0 {
            if DestroyKit.backupGatePass {
                AuditLog().purgeExpired(months: retention)
            } else if !Milestones.onceDone("purge752_\(retention)") {
                Milestones.markOnce("purge752_\(retention)")
                enqueueMoment(Moment(id: "purge752", icon: "externaldrive.fill",
                                     title: "保留期到了, 但先不删",
                                     subtitle: "审计流水已过 \(retention) 个月保留档, 最近 7 天却没有本机备份 —— 这一次清理已跳过。导出一次备份 (设置-备份与恢复), 下次启动就会把这批清掉。"))
            }
        }
        // 223 启动自动归档: 诊断页那枚开关开着才动手 (默认关), 走与手动按钮同一引擎; 条数进维护回执 (387)
        if DB.store.getBool("kf_diag_autoarchive") {
            let archived = DataHealth.archiveOldLogs()
            if archived > 0 { MaintenanceLog.record("归档旧日志 \(archived) 条") }
        }
        let cal = WeekCal.gregorian
        let now = Date()
        let year = cal.component(.year, from: now)
        if cal.component(.month, from: now) == 1, cal.component(.day, from: now) == 1,
           !Milestones.onceDone("ny\(year)") {
            Milestones.markOnce("ny\(year)")
            enqueueMoment(Moment(id: "ny\(year)", icon: "sparkles", title: "陪你跨入新一年",
                                 subtitle: "日历翻过一页, 这扇门继续交给你。", celebrate: true))
        }
        if let first = Milestones.firstDate, Milestones.daysSinceFirst >= 365,
           Milestones.isSameMonthDay(first, now), !Milestones.onceDone("appann\(year)") {
            Milestones.markOnce("appann\(year)")
            enqueueMoment(Moment(id: "appann\(year)", icon: "rosette",
                                 title: "一起管了 \(Milestones.daysSinceFirst) 天",
                                 subtitle: "从第一天到现在, 谢谢你一直在。", celebrate: true))
        }
        if UIAccessibility.isVoiceOverRunning { Milestones.markVoiceOver() }
        // 998 徽章周年回忆: 某枚徽章恰好满一年 (同一月日, 且去年或更早达成) → 一年只弹一次的时刻卡。
        // badgeAnniversaryToday 此前零调用 = 引擎写好了没人走。onceDone 键带年份, 与 appann 同一防重口径。
        if let b = Milestones.badgeAnniversaryToday(), !Milestones.onceDone("badgeann_\(b.id)_\(year)") {
            Milestones.markOnce("badgeann_\(b.id)_\(year)")
            enqueueMoment(Moment(id: "badgeann_\(b.id)_\(year)", icon: b.icon,
                                 title: "「\(b.title)」满一年了",
                                 subtitle: "去年这天拿到的徽章, 现在还在你手上。", celebrate: true))
        }
        // 1043 时光胶囊到期: 到日启动弹一次时刻卡 (onceDone 键带 openOn 防重, 与 badgeann 同口径)
        if let c = Milestones.capsule(), Milestones.capsuleIsOpen(c),
           !Milestones.onceDone("capsule_\(c.openOn)") {
            Milestones.markOnce("capsule_\(c.openOn)")
            enqueueMoment(Moment(id: "capsule." + c.openOn, icon: "hourglass",
                                 title: "时光胶囊到时间了",
                                 subtitle: "打开成就页看看那时写下的话。", celebrate: true))
        }
        evaluateAchievements()
        // 包4: 关怀提醒巡检 (1013 保养到期/1023 指纹头/校时 30 天/1024 防潮/146 固件, 全部本地通知)
        Task { await CareSchedule.refreshOnLaunch() }
        // 包6: 凭证流转巡检 — 回收站 30 天自动清 (497) + 月度清理任务排程 (366, 幂等)
        Task { _ = CredentialOrg.launchTick() }
        // 包8: 448 启动自检 (库体哈希 vs 上次快照, 异常挂黄条) + 1018 月度备份日排程
        //       + 428 充电备份 BGTask 注册 (系统择机执行, 不承诺接电即备) + 445 中断迁移检测
        Task { @MainActor in
            _ = BackupStudio.runStartupSelfCheck()
            await BackupStudio.scheduleMonthlyBackup()
            // 428: BGTask 注册已移到 QuickActionDelegate.didFinishLaunchingWithOptions ——
            // 必须早于启动完成 (Apple 契约), 且每进程只注册一次 (onLaunch 可能被多次调用)。
            if let s = BackupStudio.pendingMigration() {
                self.showToast("检测到未完成的换机迁移 (\(s.channel) \(s.step)%) — 可回滚或继续")
            }
        }
    }
    /// 开锁成功后的里程碑结算 (24/992/1005/1010/1000); 凌晨静默态(1002)只计数不播时刻
    private func settleUnlockSuccess() {
        unlockState = .success
        phase = 0
        failStreak = 0
        lastUnlockSuccessAt = Date()   // 250
        // 247 成功档收尾: 2s 后圆盘回待机 + 当天首次轻提示"可到记录回看"。
        // 此前 `finishDwell(.success)` 零调用 (死码): 开完门圆盘一直停在 .success, 回待机与那句提示都不发生。
        // 顺带接上它尾部的 refreshStatusQuietly() —— 即"开锁后静默重读电量"那一半 (135)。
        finishDwell(.success)
        LiveUnlock.succeeded(lockName: displayName)   // 77/939/941: 更新成"已开锁", 10 秒后自动收起
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // 包3: 258 首连验证标记 (开锁成功=全链路跑通) + 292 连接基准刷新
        LockArchive.markVerified(currentMac)
        LockArchive.touchConnected(currentMac)
        // 2026-10-15 走查 (对照 H5 权威 main.js @577111): 双验模式 (verifyMode==1) 下 rc==0
        // 只是第一道通过, H5 原版此刻会提示「门锁已开启双重验证，请继续使用指纹/密码开锁」。
        // 此前直接报「门已打开」= 对 B 模式用户说谎; 用状态帧镜像判, 快照未读到时宁可不提示 (与
        // LockOverviewView「未读到≠无告警」同一口径)。
        if status?.verifyMode == 1 {
            showToast("双验模式: 第一道已通过, 请再用指纹或密码完成第二道验证")
        }
        // 76 成功短音效: 默认只震动, 开关在设置-开锁 (系统铃声开关静音时自动无声)
        AlertTone.unlockSuccess()
        let crossing = Milestones.recordUnlockSuccess()
        let hour = WeekCal.gregorian.component(.hour, from: Date())
        defer { evaluateAchievements() }
        guard hour >= 6 else { return }   // 1002: 0-6 点只留触感, 不播全屏时刻
        if crossing.first {
            enqueueMoment(Moment(id: "m18.first", icon: "key.horizontal.fill",
                                 title: "第一扇门, 由你打开",
                                 subtitle: "这是你和这个家故事的开始。", celebrate: !Milestones.plainMode))
        } else if crossing.at100 {
            // 里程碑开锁触发一次庆祝: 与包18 礼花打通 (素颜模式只亮卡不撒花)
            enqueueMoment(Moment(id: "m18.100", icon: "flag.fill",
                                 title: "你已守护这个家 100 次",
                                 subtitle: "寻常的日子, 不寻常的守护。",
                                 celebrate: !Milestones.plainMode))
        }
        if crossing.at1000 { Milestones.heartbeatHaptic() }
        let year = WeekCal.gregorian.component(.year, from: Date())
        if Milestones.isBondAnniversaryToday, !Milestones.onceDone("bondann\(year)") {
            Milestones.markOnce("bondann\(year)")
            DB.store.set("kf_bond_anniv_done", true)
            enqueueMoment(Moment(id: "m18.bondann", icon: "sparkles", title: "结缘纪念日快乐",
                                 subtitle: "这一年的每一次开关, 都有你。", celebrate: !Milestones.plainMode))
        }
        if hour >= 22 { publishHomeMoment("欢迎回家, 辛苦了") }
    }
    /// Hero 卡一句话 (1000 晚归欢迎语), 8 秒后自行淡出
    private func publishHomeMoment(_ text: String) {
        withAnimation(DS.Motion.soft) { homeMoment = text }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if homeMoment == text { withAnimation(DS.Motion.exit) { homeMoment = nil } }
        }
    }

    // 最近开门 (attribution R1/R2); 条数偏好见 idea 910 (kf_recent_count, 默认 5)
    // 170: 多带一个 key —— 直接走 RecordOverlay.oid, 不在这里手拼 "mac#idx"。
    // 手拼就是第二个规则点: 哪天格式改了, 这行的深链会静默认不出 (585 的 toast 兜住, 但没人去点)。
    func recentRecords(count: Int? = nil) -> [(text: String, time: String, warn: Bool, key: String, whoId: String?)] {
        guard let kc = current else { return [] }
        let n = count ?? DB.store.getInt("kf_recent_count", 5)
        let logs = DB.readLogs(kc.mac).prefix(n)
        let rows = Attribution.classify(
            logs: logs.map { LogEntry(type: $0.type, typeName: $0.typeName, idx: $0.idxRaw, idxRaw: $0.idxRaw, lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr, body: "") },
            pwds: DB.listPwds(kc.mac), fps: DB.listFps(kc.mac),
            status: status.map { ($0.fpStock, $0.pwdStock, $0.lockTime ?? 0) })
        var out = [(String, String, Bool, String, String?)]()
        for (i, e) in logs.enumerated() {
            guard i < rows.count else { continue }
            let c = rows[i]
            var text = e.lockTimeStr.isEmpty ? e.typeName : String(e.lockTimeStr.dropFirst(5).prefix(11)) + " · " + e.typeName
            // 559: 带出可证明的成员 id 供"查这位成员的记录"; 判据与下面显示成员名**同一条** ——
            // 行上真写着成员名才带出, 成员已从档案删掉的行走 landMember 的 guard 也只会落个失败 toast。
            var whoId: String? = nil
            if let who = c.who, let m = DB.member(who) {
                // 919: 别名开关开且 relation 非空时, 首页这行也走关系称呼
                let shown = MemberHub.aliasName(who) ?? m.name
                text = (e.lockTimeStr.isEmpty ? "" : String(e.lockTimeStr.dropFirst(5).prefix(11)) + " · ") + shown + " 用" + (Attribution.words[c.kind ?? ""] ?? "") + "开了门"
                whoId = who
            }
            // 第一百五十七批：这里原本自己写着 `type == 7 || 13 || 224` —— 5 类告警只圈了 3 类，
            // 于是设备页这行**低电量(6) 与 试错锁定(10) 的告警不标红**，
            // 而同一条记录在告警中心、统计、导出里都算告警 ⇒ 同一件事两个颜色。口径只认 StatsKit.alarmTypes 那一份。
            let warn = StatsKit.alarmTypes.contains(e.type)
            out.append((text, e.lockTimeStr, warn, RecordOverlay.oid(mac: kc.mac, rowKey: String(e.idxRaw)), whoId))
        }
        return out
    }
}

// ---------- 根视图 (AppLock 门禁 + TabView) ----------
struct RootView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var sense = LinkSense.shared
    // 378: 安全中心那页的开关拨动后 SecTick.bump, 这里重算水印层 (跨页即时生效)
    @ObservedObject private var secTick = SecTickCenter.shared
    // 162 握手可离开: 圆盘握手在别的 Tab 完成 → 设备 Tab 亮角标; 回到设备页清零
    @State private var handshakeDoneAway = false
    @Environment(\.scenePhase) private var scenePhase
    // 读取 themeSeed: 设置页切换主题时立即重建配色
    private var colorScheme: ColorScheme? { Theme.scheme(for: app.themeSeed) }
    /// 四个 Tab 的内容视图 (从 body 内联的 TabView 里抽出: 该表达式报 type-check 超时)。
    /// ⚠ Tab 是 TabContent **不是** View: `.keyboardShortcut` 挂不上去 (报 "Tab … has no member
    ///   'keyboardShortcut'"), 要挂在 Tab 的**内容视图**上; 只有 `.badge` 才是 Tab 自己的成员。
    @ViewBuilder private var deviceTabContent: some View {
        DeviceHomeView()
            .onAppear { PageTrace.shown("设备") }
            .keyboardShortcut("1", modifiers: .command)
    }
    @ViewBuilder private var credentialsTabContent: some View {
        // 身份挂在这里 (父层) 才有效: CredentialsView 的 @State 由 TabView 持有,
        // 在其 body 内部写 .id(app.currentMac) 不会重建该 struct → 切锁后
        // selPwds/selFps/otpPwd 仍是上一把锁的值, 批量停用会打到错锁。
        CredentialsView().id(app.currentMac)
            .safeAreaInset(edge: .top, spacing: 0) { bleStatusStrip(app: app, sense: sense) }
            .onAppear { PageTrace.shown("凭证") }
            .keyboardShortcut("2", modifiers: .command)
    }
    @ViewBuilder private var recordsTabContent: some View {
        // 同凭证 Tab: 记录是纯 per-lock 数据, 在父层挂身份才能整体重建。
        // RecordsView 只有 :178 onAppear→loadFromCache, 编程式切锁 (跳回/意图改 currentMac)
        // 不触发 → groups/allRows 仍是旧锁行, :1187 的认领会把旧锁 idxRaw 记到新锁键下。
        RecordsView().id(app.currentMac)
            .safeAreaInset(edge: .top, spacing: 0) { bleStatusStrip(app: app, sense: sense) }
            .onAppear { PageTrace.shown("记录") }
            .keyboardShortcut("3", modifiers: .command)
    }
    @ViewBuilder private var settingsTabContent: some View {
        SettingsView()
            .safeAreaInset(edge: .top, spacing: 0) { bleStatusStrip(app: app, sense: sense) }
            .onAppear { PageTrace.shown("设置") }
            .keyboardShortcut("4", modifiers: .command)
    }

    /// 顶部横幅栈 (演示/BLE/自检/粘贴建议/toast/写入回执) —— 从 body 内联的 safeAreaInset
    /// 里抽出: 该表达式报 type-check 超时。
    @ViewBuilder
    private var topBanners: some View {
        VStack(spacing: 0) {
            // 包14/836 演示模式常驻横幅: 四 Tab 共用, 演示数据全路径可辨识
            DemoBanner()
            // 包2/69 蓝牙直通条: 系统蓝牙关闭时全 App 顶部提示 (深链系统设置不可用 → 指引文案)
            if !LinkSense.shared.btOn {
                BLEOffBanner { LinkSense.shared.openBluetoothSettings() }
            }
            // 包8/448 启动自检黄条: 库体哈希与上次快照不一致 → 设备 Tab 顶部黄条 "去诊断"
            // 乱源治理第 2 批: 它不再无条件挂 —— 闲时提醒同屏只留一条, 由 app.ambientTop 说了算
            if app.ambientTop == .selfCheck, let w = BackupStudio.selfCheckWarning {
                selfCheckBanner(w)
            }
            // 344 粘贴建议条: 回前台时本会话刚复制的凭证还在不在, 一条快捷条解决。
            // 站凭证页时不挂 (人就在那, 不用指路); 文案里的秒数取自回前台那一刻的快照。
            if app.ambientTop == .pasteCare, let s = app.pasteSuggestion {
                pasteSuggestionBar(s)
            }
            // 被预算压掉的提醒不静默消失: 给一枚汇总入口, 点进去逐条仍是它原来的动作
            if !app.ambientRest.isEmpty {
                ambientOverflowChip(app.ambientRest.count)
            }
            if let t = app.toast {
                ToastView(text: t)
                    .allowsHitTesting(false)   // 顶部提示不吃点击
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            // 包8/508 写入回执: 凭证保存/停用成功后对勾浮出 (替代云同步反馈)
            if let r = app.writeReceipt {
                writeReceiptView(r)
            }
        }
    }

    /// 四个 Tab 的 TabView (从 mainTabs 抽出: 该表达式报 type-check 超时)
    @ViewBuilder
    private var mainTabView: some View {
        TabView(selection: $app.tabSelection) {
            // 280 页面打开耗时: 起点在下面的 onChange(tabSelection)，终点就是各 Tab 内容的 onAppear。
            Tab("设备", systemImage: "lock.fill", value: 0) { deviceTabContent }
                // 162 握手可离开: 握手在别的 Tab 完成时这里亮一枚 "✓" (nil = 无角标); 回设备页即清
                .badge(handshakeDoneAway ? Text("✓") : nil)
            // 377 访客通道: 受限区没放开时, 凭证与设置这两个 Tab 根本**不进层级树**
            // (不是禁点、不是加遮罩 —— 进不去的那两页连同里面的口令与成员名都不该挂在屏上)。
            if !app.guestAreaLocked {
                // 930 替代: 原句要的中尺寸"到期凭证 Widget"在免费账号读不到台账 (App Groups 禁),
                // 替代栏给的是"到期前 7/3/1 天三级本地通知 + 凭证页顶部红点" —— 通知在
                // CredentialOrg.scheduleAlerts, 红点落在系统 Tab 角标上 (与记录 Tab 的 735 角标同一手法,
                // 0 时系统自动隐藏)。口径与 363 月历格同源, 不另算一套。
                Tab("凭证", systemImage: "key.horizontal.fill", value: 1) { credentialsTabContent }
                    .badge(CredentialOrg.expiringSoonCount(macs: DB.keychains().map { $0.mac }))
            }
            Tab("记录", systemImage: "list.bullet.rectangle.fill", value: 2) { recordsTabContent }
                // 735 Tab 角标: 口径与记录页铃铛同源 (RecordSearch.unhandledAlarmCount); 0 时系统自动隐藏
                .badge(RecordSearch.unhandledAlarmCount(macs: DB.keychains().map { $0.mac }))
            // 377: 设置页同样收起 —— 里面是本机密码、备份与销毁这些不该给访客看的东西;
            // 代价如实写在这里: 想关掉访客通道本身也要先重输一次口令 (开关原话的"退出需密码")。
            if !app.guestAreaLocked {
                Tab("设置", systemImage: "gearshape.fill", value: 3) { settingsTabContent }
            }
        }
    }

    /// 主 TabView + 长按菜单 + 底栏/访客复核 —— 从 appUnlocked 分支抽出: 该表达式报 type-check 超时
    private var mainTabs: some View {
        // iOS 18+ 的 Tab 声明式写法: 类型安全, 系统按平台自动选择底栏/侧栏形态
        // 包15 键盘: Cmd 1-4 切 Tab 真接线 (164/530); Tab/Esc 遍历由系统「全键盘控制」提供 (854)
        // 包2/136 跨页状态细条: 非设备 Tab 顶部一条 BLE 状态细线, 点按跳回设备页定位当前锁;
        // 162 握手可离开: 切走 Tab 不取消进行中的握手 (回连循环/看门狗继续跑)
        mainTabView
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
                if app.current != nil {
                    Button("打开迷你开锁面板") { app.requestRoute(.device); app.shakePanel = true }
                }
                Button("只看今天的记录") {
                    app.pendingRecordsDay = StatsKit.dayKey(Date())
                    app.requestRoute(.records)
                }
            case 1:
                Button("凭证回收站") { app.pendingCredPanel = "bin"; app.requestRoute(.credentials) }
                Button("到期与整理建议") { app.pendingCredPanel = "expired"; app.requestRoute(.credentials) }
                Button("待补拉队列") { app.pendingCredPanel = "queue"; app.requestRoute(.credentials) }
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
                    Button("这台锁的诊断") { app.pendingDiag = app.currentMac; app.requestRoute(.settings) }
                    Button("打开这一页") { app.requestTab(selected.first ?? 0) }
                }
            }
        } primaryAction: { selected in
            // 长按后直接点一下 (竖屏主操作) = 进那一页, 走的仍是 requestTab 那道访客门禁
            if let t = selected.first { app.requestTab(t) }
        }
        // 25 Tab 栏中央主按钮 (Instagram 式)。iOS 的 TabView 没有"中间那个按钮"这种系统位,
        // 所以落点用 safeAreaInset(.bottom) —— 与上面那条 .top 同一手法, 不是 overlay:
        // 覆盖式会压住导航栏标题与页面内容 (本文件注释里已经记过一次这个坑)。
        // **只导航、不开锁**: 主操作仍然只有那一个 176pt 圆盘。第二个开锁入口 = 第二套误开面,
        // 也违背拍板"主屏/锁屏一键开锁是新的误开面"那条同向判断。
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: DS.Space.xs) {
                if app.tabSelection != 0, !app.decoyMode {
                    Button {
                        DS.Haptics.tick.impactOccurred()
                        app.requestRoute(.device)
                    } label: {
                        Label("开锁", systemImage: "lock.open.fill")
                            .accessibilityLabel("到设备页开锁")
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .transition(.opacity)
                }
                // 377 访客通道: 受限区唯一的入口。点它不切页 —— 把**既有**应用锁页拉起来复核,
                // 通过之后 TabView 才把 凭证/设置 挂回层级树 (不新造第二个解锁面)。
                if app.guestAreaLocked {
                    Button {
                        DS.Haptics.tick.impactOccurred()
                        app.openGuestGate()
                    } label: {
                        Label("凭证与设置 (需重输密码)", systemImage: "lock.badge.clock")
                            .accessibilityLabel("访客模式已开, 轻点后用应用锁密码放开凭证与设置")
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .transition(.opacity)
                }
            }
            .padding(.bottom, DS.Space.xs)
        }
        .animation(DS.Motion.quick, value: app.tabSelection)
        // 377: 受限区复核用的承载体就是 AppLockView 本身 (reauth 档: 验过只放开 Tab, 不动 appUnlocked)。
        // 用 fullScreenCover 而不是 sheet: 半屏会把底下那层凭证/记录的内容露一角出来。
        .fullScreenCover(isPresented: $app.showGuestGate) {
            GuestReauthGate()
                .environmentObject(app)
        }
        // 乱源治理第 2 批: 被预算压掉的提醒在这里逐条给回它原来的动作 (sheet 而不是 cover ——
        // 它是"看一眼再回去"的面，不该把底下的内容全遮掉)
        .sheet(isPresented: $app.showAmbientList) {
            AmbientOverflowSheet()
                .environmentObject(app)
        }
        // 用 safeAreaInset 而不是 overlay — 覆盖式会压住导航栏标题
    }

    /// 主界面的顶部横幅/时刻卡/启动 task/前后台钩子 —— 同上, 继续拆
    @ViewBuilder
    private var mainTabsChrome: some View {
        mainTabs
        .safeAreaInset(edge: .top, spacing: 0) {
            topBanners
        }
        // 包18: 一次性时刻卡 (里程碑/周年/史诗徽章) 覆盖层
        // 2026-10-16: 纪念卡层抽成 MomentLayer 修饰符 —— 和 bootstrapOnce 同一条理由：
        // 它原先长在 mainTabsChrome 上，两个新变体不挂 mainTabsChrome 就会**静默收不到纪念时刻**。
        // 一处实现、两处挂载，禁止复制第二份条件与 transition。
        .modifier(MomentLayer())
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
        CrashGuard.checkAbnormalExit()
        CrashGuard.markSessionStart()
        app.onLaunch()
        // 215 启动预算 / 224 启动预热: 两个引擎此前全库零调用。
        // Prewarm 只做本地键位与热点缓存读取, 不碰 BLE —— 不会在启动时偷偷发起连接。
        StartupTrace.mark("onLaunch 结束")
        Prewarm.run(mac: app.currentMac)
        if StartupTrace.overBudget {
            app.lock.log("warn", "启动耗时 \(Int(StartupTrace.totalMs))ms, 超 800ms 预算")   // 215 启动耗时
        }
        RootView.registerHost(app)   // 包2: LinkSense 宿主注册 + 回连/巡检循环
        LinkSense.shared.coldStartScan()   // 包2/134 冷启动先扫描 (定位可见锁, 不连接)
    }
    /// 实例便捷转发，供 `.task` 直接调用（保持 body 表达式小，见本文件多处 type-check 超时的教训）。
    private func bootstrapOnce() { RootView.bootstrapOnce(app) }

    var body: some View {
        rootChrome
    }

    /// RootView 的四种形态 (引导/伪装空壳/主界面/应用锁) —— 从巨型 body 拆出
    @ViewBuilder
    private var rootGroup: some View {
        Group {
            if !Onboarding.allDone && !app.onboardingFinished {
                // 包14 首启五步: 承诺/导览/角色/权限/演示/自检/证书, 进度逐键存档 (804);
                // 完成后切换进主界面, 其 .task 触发 onLaunch 结算
                OnboardingView(onExit: { app.onboardingFinished = true })
                    .environmentObject(app)
            } else {
                // 2026-10-17 拍板 A: 应用锁启动门禁已删 (伪装口令 390 随之不可达, 一并移除)。
                // 进 App 只分两种形态: 首启引导 / 主界面。
                mainTabsChrome
            }
        }
    }

    /// 摇一摇/外观种子/字号/灰度/加粗/动效/水印层 —— 继续拆 (原表达式报 type-check 超时)
    @ViewBuilder
    private var rootCore: some View {
        rootGroup
        // 54/372 摇一摇接收层: SwiftUI 无该手势, UIKit 入口 UIWindow.motionEnded 又换不了 WindowGroup
        // 的 window —— 用一层零尺寸 VC 接住再转 .kfDeviceShake (实现见文件尾部)。
        .onDeviceShake()
        // 包16: 外观种子变更时整树重建 — 配色/密度即时全局生效; withAnimation 提供淡入淡出 (idea 21)
        .id(app.appearanceSeed)
        // 包15: App 字号五档 × 系统 Dynamic Type 叠加 (858, 含 866 极限字号自检 200% 预览)
        .dynamicTypeSize(AXFlags.typeSize())
        // 包15: 灰度预览自检 (879) — 全 App 去饱和, 检查渐变主题无色可读性
        .saturation(AXFlags.grayPreview ? 0 : 1)
        // 861 系统加粗跟随: 读系统"加粗文本"开关, 在根上设 legibilityWeight ——
        // 显式字重的文本 (凭证名/开关标签) 才跟着加粗。关档时给 .regular 而不是留空:
        // 两档都显式, 不依赖系统默认推断 (LegibilityWeight.bold 的官方语义就是 "force Accessibility Bold")。
        .environment(\.legibilityWeight, AXFlags.boldText ? .bold : .regular)
        .animation(DS.Motion.soft, value: app.appUnlocked)
        // 378 常驻水印: 全局对角重复层 (安全中心页内那份保留不动, 那里是设置项自己的预览)。
        // 读一下 tick 使开关拨动后整层重算; hitTesting/朗读屏蔽在 SecurityWatermark 内部已带。
        .overlay {
            let _ = secTick.tick
            if DB.store.getBool(SecKey.watermarkOn, false) {
                SecurityWatermark(seed: DB.store.getString(SecKey.watermarkTxt))
                    .ignoresSafeArea()
            }
        }
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
            PageTrace.markNav(to: new)
        }
        .onChange(of: app.appUnlocked) { _, unlocked in
            // 161: 先回上次停留位, 再落地挂起深链 (restoreLastTab 内部见 pendingRoute 就避让)
            if unlocked {
                app.restoreLastTab(); app.applyPendingRoute()
                // 397 解锁后跑一次本机库体自检 (纯本地读, 不碰 BLE); 只在异常时出声
                let bad = app.runSelfCheck397()
                if bad > 0 { app.showToast("本机自检发现 \(bad) 项异常，详见「设置-诊断」") }   // 397 本机自检发现
            } else {
                // 377/383: 锁重新落下 (手动锁 / 393 到点自动锁) 就把会话级授权一起收回 ——
                // 访客区的放开与 sudo 券说的都是"这一次解锁验过", 锁都落了还认旧账就等于没拦。
                app.revokeSessionGrants()
            }
        }
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
            case .connecting, .down: break
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


    /// 包8/448 启动自检黄条 —— 2026-10-13 run 64 从 body 内联块抽出: 该表达式报 type-check 超时。
    @ViewBuilder
    /// 汇总胶囊: 屏上只留一条提醒，其余收在这儿。数字如实是被压掉的条数，不含屏上那条。
    private func ambientOverflowChip(_ n: Int) -> some View {
        Button {
            DS.Haptics.tick.impactOccurred()
            app.showAmbientList = true
        } label: {
            HStack(spacing: DS.Space.xs) {
                Image(systemName: "bell.badge")
                    .font(.system(size: DS.Icon.xs))
                    .accessibilityHidden(true)
                Text("还有 \(n) 条提醒")
                    .vkFont(.caption2)
                Image(systemName: "chevron.right")
                    .font(.system(size: DS.Icon.xs))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(DS.Palette.textSub)
            .padding(.horizontal, DS.Space.s)
            .padding(.vertical, DS.Space.xs)
            .variantPlate(DS.Palette.surfaceAlt, .capsule)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .frame(minHeight: DS.Hit.min)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("屏上只留了一条提醒，另有 \(n) 条被收起，轻点逐条查看")
    }

    private func selfCheckBanner(_ w: String) -> some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: DS.Icon.sm, weight: .semibold))
                .accessibilityHidden(true)
            Text(w).vkFont(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("去诊断") {
                // 2026-10-15 走查 §4.3: 与 NoticeBudget 那条同病 —— 按钮说"去诊断", 原来只把人放到
                // 设置页根上。带落点名, 由设置页直接开诊断面。
                app.pendingSettingsFocus = "diag"
                app.requestRoute(.settings)
            }   // 377: 访客通道开着时先复核, 不白切
                .vkFont(.caption, weight: .medium)
        }
        .foregroundStyle(DS.Palette.warn)
        .padding(.horizontal, DS.Space.l)
        .padding(.vertical, DS.Space.s)
        .background(DS.Palette.warn.opacity(0.14))
    }

    /// 344 粘贴建议条 —— 2026-10-13 run 63 从 body 内联块抽出: 该表达式报 type-check 超时。
    @ViewBuilder
    private func pasteSuggestionBar(_ s: ClipboardCare.Suggestion) -> some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: DS.Icon.sm))
                .accessibilityHidden(true)
            Group {
                switch s.stage {
                case .waiting(let n):
                    Text("刚复制的「\(s.label)」还在剪贴板 — \(n) 秒后自动清除")
                case .cleared:
                    Text("刚复制的「\(s.label)」到点已自动清除")
                }
            }
            .vkFont(.caption)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DS.Space.xs)
            if case .waiting = s.stage {
                // 517 立即清除: 走 ClipboardCare.clearNow() (唯一出口), 不在这里直接写 pasteboard
                Button("立即清除") {   // 517 立即清除
                    ClipboardCare.clearNow()
                    withAnimation(DS.Motion.standard) { app.pasteSuggestion = nil }
                }
                Button("再复制一次") {
                    ClipboardCare.recopy()
                    withAnimation(DS.Motion.standard) { app.refreshPasteSuggestion() }
                }
            } else {
                Button("回凭证页") {
                    ClipboardCare.dismissSuggestion()
                    app.requestRoute(.credentials)   // 377: 访客通道开着时这条快捷条同样不能白切进去
                    withAnimation(DS.Motion.standard) { app.pasteSuggestion = nil }
                }
            }
            Button("知道了") {
                ClipboardCare.dismissSuggestion()
                withAnimation(DS.Motion.standard) { app.pasteSuggestion = nil }
            }
        }
        .vkFont(.caption, weight: .medium)
        .foregroundStyle(DS.Palette.accentText)
        .padding(.horizontal, DS.Space.l)
        .padding(.vertical, DS.Space.s)
        .background(DS.Palette.accent.opacity(0.12))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// 包8/508 写入回执浮层 —— 2026-10-13 run 63 从 body 内联块抽出:
    /// 巨型 body 里这一段报 "unable to type-check this expression in reasonable time"。
    @ViewBuilder
    private func writeReceiptView(_ r: String) -> some View {
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
            // 动效令牌的非隔离读点: 系统"减弱动态效果"只能在设置里改, 改完回来必然经过这里。
            AXFlags.refreshSnapshots()
            // 2026-10-17 拍板 A: 「到点自动落锁」随启动门禁一起删 —— 现在没有锁屏页可回,
            // 留着它只会把 appUnlocked 置 false, 让深链/落点/回连那些 guard 静默失效。
            if app.appUnlocked {
                // 靠近自动开锁 (AUTOOPEN): F0 前台门 + F1 进前台按档位刷面容 (挂起期静默)
                AutoOpenController.shared.onForeground(mac: app.currentMac)
                // 344 回前台才出快捷条 (344 的原话就是"回前台显示"), 顺带重算剩余秒数
                app.refreshPasteSuggestion()
                // 671 自动档: 用户没开开关时这里一次请求都不发；开了也每进程只发一次 (HolidayFeed 内部判)
                Task { await HolidayFeed.autoRefreshIfNeeded() }
                // 897 四季图标: 默认关。开着也只在"季节真的换了"时对齐一次 (年-季记号)，不每次回前台打扰
                SeasonIcon.syncIfNeeded()
            }
        } else if phase == .background {
            // 2026-10-14: 只有**真进后台**才算退后台。旧实现把 .inactive (下拉通知中心/控制中心、
            // 来电、Face ID 系统弹窗) 也当退后台 —— 会误记锁定到期时刻 (反复下拉可无限顺延宽限),
            // 还会提前清掉崩溃标记 (随后真崩溃被判成"正常退出")。.inactive 只收起过期的快捷条。
            app.pasteSuggestion = nil
            // 393: 退后台按档位记锁定到期时刻 ("" = 立即, 最严)
            LockGuard.onBackground()
            // 221 退后台收尾: 记会话时长并清崩溃标记 (CrashGuard 的判定就依赖这一步)
            CrashGuard.markCleanExit()
            AutoOpenController.shared.onBackground()
        } else {
            // .inactive: 只收起过期的快捷条, **不**记锁定到期时刻 (否则反复下拉通知中心可无限顺延宽限)。
            // 但崩溃标记仍要清 —— 从任务切换器强退时进程多在 .inactive 被 SIGKILL,
            // 只在 .background 清会把正常强退误报成"异常退出"。
            app.pasteSuggestion = nil
            CrashGuard.markCleanExit()
            // 2026-10-14: .inactive 也要停自动开锁的武装态与加速度计 (下拉通知中心/来电/系统弹窗期间
            // AUTOOPEN 不该继续武装并喂传感器); 锁定计时与崩溃标记的取舍见上。
            AutoOpenController.shared.onBackground()
        }
    }
    // 包2/136 跨页状态细条: 非设备 Tab 顶部一条 BLE 状态细线 (2pt 语义色 + 状态行),
    // 点按跳回设备 Tab 并定位当前锁; 135 scenePhase .active 时静默刷新, 退后台暂停回连。
    @ViewBuilder
    private func bleStatusStrip(app: AppState, sense: LinkSense) -> some View {
        BLEStrip(title: "跳回设备页", state: sense.linkState,
                 detail: sense.lastRssi.map { "RSSI \($0)" }) {
            app.requestRoute(.device)
            app.pendingJumpLock = app.currentMac
        }
    }
}

// LinkSense 宿主注册 (RootView 首次挂载时): 包装层只读协作, 不建循环依赖
extension RootView {
    @MainActor
    static func registerHost(_ app: AppState) {
        AppState.hostRef = app
        LinkSense.shared.startReconnectLoop()
        LinkSense.shared.startDeadWatch()
    }
}

// ---------- 全局 Toast (悬浮在内容之上, 用 iOS 26 的液态玻璃) ----------
struct ToastView: View {
    var text: String
    var body: some View {
        Text(text)
            .vkFont(.footnote, weight: .medium)
            .foregroundStyle(DS.Palette.text)
            .lineLimit(3)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.s + 2)
            .frame(maxWidth: 420)
            // 玻璃层自带深浅色适配与背景折射, 不需要再叠一层描边
            .axGlass(DS.Radius.control)
            .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
            .padding(.horizontal, DS.Space.xl)
            .padding(.top, DS.Space.xs)
            .accessibilityAddTraits(.isStaticText)
    }
}

// ---------- 377 访客受限区复核 (2026-10-17 拍板 A: 只走面容/指纹, 不再有本机密码) ----------
/// 原承载体是 AppLockView 的口令键盘。启动门禁删掉后, 口令这个凭据在本机已不存在,
/// 复核只剩生物识别一条路 —— 所以这里是一个**只做一件事**的小页, 不重建第二个解锁面。
struct GuestReauthGate: View {
    @EnvironmentObject var app: AppState
    @State private var busy = false
    @State private var note = "用面容/指纹确认是你本人后, 放开凭证与设置两页"
    var body: some View {
        VStack(spacing: DS.Space.m) {
            Image(systemName: "faceid")
                .font(.system(size: 44))
                .foregroundStyle(DS.Palette.accentText)
                .accessibilityHidden(true)
            Text("凭证与设置已收起")
                .vkFont(.headline)
            Text(note)
                .vkFont(.footnote)
                .foregroundStyle(DS.Palette.textSub)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await verify() }
            } label: {
                Text(busy ? "验证中…" : "验证")
                    .frame(maxWidth: .infinity, minHeight: DS.Hit.min)
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy)
            Button("取消") { app.showGuestGate = false }
                .frame(minHeight: DS.Hit.min)
        }
        .padding(DS.Space.l)
        .task { await verify() }
    }
    private func verify() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        if await AuthKit.verifyBiometricAsync(reason: "放开凭证与设置") {
            app.commitUnlock(reauth: true)
        } else {
            note = "未通过面容/指纹确认, 这两页仍收着"
        }
    }
}

struct PressFeedback: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .shadow(color: .black.opacity(configuration.isPressed ? 0.16 : 0), radius: 7, y: 3)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(DS.Motion.quick, value: configuration.isPressed)
    }
}

/// 872 防连点: 300ms 内重复点击忽略 (开关 AXPrefs.dbltapGuard, 默认开)。
/// 做法是 **PrimitiveButtonStyle 外包一层闸 + 内层仍是真 Button** ——
/// ButtonStyle 拿不到 action (拦不住点击), 而直接在外层用 onTapGesture 会把 List 行点击、
/// 滚动手势、VoiceOver 激活这些系统语义弄丢 (全仓 40 处调用点都在吃这些语义)。
/// 内层 Button 保留全部系统行为, 只有 trigger() 走闸; 闸状态是每个按钮各自的 @State, 不跨按钮误伤。
struct PressableButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Gate(configuration: configuration)
    }
    private struct Gate: View {
        let configuration: Configuration
        @State private var lastFire = Date.distantPast
        var body: some View {
            Button {
                let now = Date()
                guard !AXPrefs.dbltapGuard || now.timeIntervalSince(lastFire) >= 0.3 else { return }
                lastFire = now
                configuration.trigger()
            } label: { configuration.label }
            .buttonStyle(PressFeedback())
        }
    }
}

/// 卡片表面: 靠 surface 与渐变画布的明度差分层, 不加描边。
/// 每张卡都套 0.5pt 描边会让所有卡片看起来出自同一个模板 —— 描边是 1px Web 做法,
/// iOS 上 surface/canvas 的明度差已经足够表达层级, 描边反而是重复劳动。
/// 阴影在深色模式下纯黑不可见, 故改用极淡的提亮。
/// `tint` 给"需要处理"的卡混入语义色底 (8%), 让异常自带色温而不靠描边。
// 2026-10-16: 从 `private` 放开成 internal —— 第二个消费点在 App/Core/VariantGrammar.swift 的
// `card()`（新语法层的主表面，同一句 `.shadow(color: .cardElevation, radius: 12, y: 4)`）。
// **只此一处定义**是刻意的：另抄一份阴影色，两套变体迟早会在这一步上分家。
extension Color {
    static var cardElevation: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(Color.white).withAlphaComponent(0.04)
                : UIColor(Color.black).withAlphaComponent(0.05)
        })
    }
}

struct Card<Content: View>: View {
    var tint: ToneColor?
    var content: Content
    init(tint: ToneColor? = nil, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }
    /// 语义色叠底 (低电/告警的 ToneColor)。实底时代是 0.08；改玻璃后提到 0.14 ——
    /// 染色要同时压住自身与身后折射的底色，沿用 0.08 会让"这张卡是告警色"这件事失色。
    private var tintWash: Color {
        tint.map { $0.color.opacity(0.14) } ?? .clear
    }
    var body: some View {
        // 2026-10-16: 形状的决定权交给 VK.card —— 53 处 Card 调用一次跟着两套界面变，
        // 而不是去 53 个调用点各改一遍（那既是"同一个量算两次"，也必然漏改）。
        // `.legacy` 分支是原来这段 body 逐字搬过去的，见 VariantGrammar.swift 的 VK.card。
        // 传 tintWash 而不是 tint 本体：0.14 这个叠底浓度是"玻璃时代"定下来的，
        // 它的理由写在下面 tintWash 的注释里，两套新界面各自决定怎么用这个语义色。
        VK().card(tint: tint == nil ? nil : tintWash) { content }
    }
}
struct SectionTitle: View {
    var text: String
    var count: Int?
    var body: some View {
        // 2026-10-16: 形状交给当前变体决定 (VK.sectionTitle)，21 处调用一次跟着两套走。
        // legacy 分支是这里原来的实现逐字搬过去的，见 VariantGrammar.swift。
        VK().sectionTitle(text: text, count: count)
    }
}

// 摇一摇 (54/372) 的接收端 —— 一层零尺寸、不接触摸的 UIViewController。
// 为什么需要这一层: SwiftUI 没有"摇一摇"手势; UIKit 的入口是 UIWindow.motionEnded, 而 WindowGroup 的
// window 由框架自建、不能换成自建子类 (试过直接写 `class ShakeWindow: UIWindow` —— 编得过但一个实例
// 都不会被用上, 等于假热区)。所以走 UIResponder 事件链: 在这层 VC 上覆写 motionEnded,
// 把 .motionShake 转成 App 内 .kfDeviceShake 通知, 挂到 RootView 根部 (见 onDeviceShake)。
extension Notification.Name {
    static let kfDeviceShake = Notification.Name("kf.device.shake")
}

private struct ShakeReceiver: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ShakeReceiverVC { ShakeReceiverVC() }
    func updateUIViewController(_ uiViewController: ShakeReceiverVC, context: Context) {}
}

final class ShakeReceiverVC: UIViewController {
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .kfDeviceShake, object: event)
        }
    }
}

extension View {
    /// 挂上摇一摇接收层 (0 尺寸 / 不吃触摸 / 不进朗读, 只为接住 UIResponder 的 motion 事件)
    func onDeviceShake() -> some View {
        background(ShakeReceiver()
            .allowsHitTesting(false)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true))
    }
}
