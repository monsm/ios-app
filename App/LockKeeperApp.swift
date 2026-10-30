// 离线锁管家 for iOS — App 入口与全局状态 (SwiftUI 全原生)
import SwiftUI
import UIKit
import UserNotifications

@main
struct LockKeeperApp: App {
    @StateObject private var app = AppState()
// 启动期系统职责走 UIApplicationDelegate 适配器（**密钥迁移** 一项）。
// 2026-10-27 审核修复 (AUDIT-B 2.8 #9)：原注释列了三项「BGTask 注册 / 密钥迁移 / MAC 字节序回灌」，
// 而 `BGTask` 已在 704a4c5 删除（全仓 0 命中）、MAC 回灌也随 `QuickAction` 一并移除。
// 现在适配器里只剩密钥迁移一件事。
    // 为什么不能放进 App 的 onLaunch(): 那函数挂在 .task 上可能多次调用, 而 BGTask 注册必须早于启动完成。
    @UIApplicationDelegateAdaptor(QuickActionDelegate.self) private var quickActions
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .tint(DS.Palette.accent)
        }
    }
}

// ---------- 主题 (JS utils/theme.js: kf_theme) ----------
// 颜色统一取自设计系统 DesignSystem.swift, 页面不再各自定义颜色
enum Theme {
    static var accent: Color { DS.Palette.accentText }
    static var warn: Color { DS.Palette.warn }
    static var ok: Color { DS.Palette.ok }
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


@MainActor
final class AppState: ObservableObject {
    let lock = LockService.shared
    let hw = HardwareService.shared

    /// 2026-10-27 三轮恢复：`UnlockState` 在删 Moment 队列时被连带删掉 ——
    /// 它是开锁状态机（AutoOpen / Mascot / UnlockDial 都在用），不在删除清单里。
    enum UnlockState: Equatable {
        case idle, connecting, opening, success, doubleVerify, failed(String)
        var isFailed: Bool {
            if case .failed = self { return true }
            return false
        }
    }
    @Published var devices: [Keychain] = []
    @Published var currentMac: String = ""
    @Published var status: LockStatus?
    @Published var snapshot: StatusSnapshotData?
    @Published var unlockState: UnlockState = .idle
    /// 2026-10-27 审核：本字段**不再承担任何门禁**。全仓没有路径能把它置回 false，
    /// 原先四处深链门禁 / 明文密码门禁 / F0 门里的判断恒为真，已按「承认没有应用锁」全部删除。
    /// 保留此字段只为 `SettingsView` 的旧引用与动画绑定，实际恒 true。
    @Published var appUnlocked: Bool = true
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
    // 2026-10-26: 原 `guestAreaLocked`（377 访客通道闸）已删 —— 它依赖 `SecurityPolicy.guestActive`，
    // 而 `kf_speek_guest` **从来没有写点**（设置页无此开关）⇒ 恒 false ⇒ 本属性恒 false。
    // 于是下游四处判据全部恒等于「访客未开启」：凭证/设置 Tab 永远显示、访客入口按钮永不出现、
    // 换页闸永不拦截。按"删功能"处置：连同下面四处判据一起展开成无条件。
    // 2026-10-29 性能：`toast` 已迁到独立的 ToastCenter（见 Core/ToastCenter.swift）。
    // 它原来挂在这里，而 RootView + 43 个视图都观察 AppState ⇒ 每条提示都重算整棵树。
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
        }
    }
    // 294 本地深链 (kf://): 白名单路由; 应用锁未解开时**先挂起**, 解锁后才落地 (深链不得绕过门禁)
    @Published var pendingRoute: Route?
    /// 2026-10-29 性能：只在 AppState 内部落地（294 深链锁 ID），没有任何视图读它 —— 不需要发布。
    var pendingMac: String?
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
            if !decoyMode { select(mac) } else { pendingMac = mac }
        }
        if !decoyMode { requestTab(tab) } else { pendingRoute = Route.from(tab: tab) }
    }
    func applyPendingRoute() {
        if let m = pendingMac, !decoyMode { pendingMac = nil; select(m) }
        guard let r = pendingRoute else { return }
        pendingRoute = nil
        if !decoyMode { requestRoute(r) }
    }
    // ---------- 377 访客通道: 受限 Tab 的唯一走位口 ----------
    /// 受控跳转都汇到这里: 目标是被收起来的 Tab 且本会话没重输过口令, 就把既有应用锁页拉起来而不是切过去。
    /// 深链、粘贴条的"回凭证页"、自检黄条的"去诊断"这些编程式跳转原本直接写 tabSelection,
    /// 不并到这条口上就会留成绕过访客限制的侧门。
    /// 换页的**唯一漏斗**。377 访客闸也只在这里判一次。
    func requestRoute(_ r: Route) {
        // 2026-10-26: 原「受限区先过闸」已删（guestAreaLocked 恒 false）⇒ 换页直接切。
        tabSelection = r.tabIndex
    }

    /// 会话授权收回：真进后台时调用（见 handleScenePhase 的 .background 分支）。
    /// 2026-10-26: 原实现含访客三行（guestAreaUnlocked / showGuestGate / guestGateTarget），
    /// 已随 377 访客通道整套删除。**本函数本身必须保留** —— 它是「用户离开 App = 本次会话结束」
    /// 的落点；启动门禁删掉后 appUnlocked 再也不会变 false，若连它也不调，就等于一次放开永久敞开。
    /// 现在它只做一件事：检查 7 天未备份的提醒标记（原访客逻辑之外的那部分职责）。
    func revokeSessionGrants() {
        // 377 访客通道已删；当前无可收回的会话级授权。
        // 保留空实现的理由见上方注释：调用点还在，且未来若再加会话级授权，这里是唯一落点。
    }
    /// 兼容适配器：2026-10-16 起全仓**代码里**已无 `requestTab(<字面量>)`（只剩注释引述），
    /// 仍在用的只有从深链序号 / List 选中集派生的动态形式；两者都汇到同一个漏斗。
    /// 越界序号 (历史脏值 / 以后加 Tab 忘了改) 直接丢弃而不是崩溃，也不静默切到别的页。
    func requestTab(_ t: Int) {
        guard let r = Route.from(tab: t) else { return }
        requestRoute(r)
    }
    /// 377: 应用锁通道验过之后的落地。常规门禁置 appUnlocked; 受限区复核只放开 Tab 并跳到用户要的那页。
    /// 两条都从这一个出口走, 398 会话痕迹与 391 胁迫打标才是同一套口径, 而不是"另一套解锁的边角料"。

    // 2026-10-30 删除（第 86 轮）：`runSelfCheck397()` 恒返回 0 —— SelfCheck 三项检查
    // （库体哈希/审计链/JSON 回环）已随诊断族移除，函数体只剩 `return 0`。
    // 它唯一的调用点（冷启动自检提示）已一并删除，本函数遂成死代码。
    // 真需要自检时重建 `SelfCheck` 与调用点，别只留一个恒 0 的壳让人误以为"有自检"。

    /// 应用锁验证通过后的落地。
    /// 2026-10-26: 原 `reauth` 参数已删 —— 它只服务 377 访客通道的「只放开 Tab 不动 appUnlocked」，
    /// 而那条通道已整套删除（guestAreaLocked 恒 false）。现在只有一种落地：置 appUnlocked。
    // ---------- 161 应用锁秒进: 验证通过后回到上次停留的 Tab ----------
    static let lastTabKey = "kf_last_tab"
    func rememberTab(_ t: Int) {
        guard !decoyMode else { return }   // 锁着或空壳会话不记, 免得把伪装态当"上次停留"
        DB.store.set(AppState.lastTabKey, t)
    }
    /// 挂起的深链优先 (那是用户明确要去的地方), 否则回到上次停留的 Tab; 越界档位夹回四页内。
    func restoreLastTab() {
        guard !decoyMode, pendingRoute == nil else { return }
        let t = min(max(DB.store.getInt(AppState.lastTabKey, 0), 0), 3)
        // 2026-10-26: 原「上次停在受限区就不恢复」已删（guestAreaLocked 恒 false）⇒ 直接恢复。
        tabSelection = t
    }
    @Published var failStreak = 0
    @Published var writeReceipt: String?   // 包8/508 写入回执: 凭证保存成功后"已写入本机"对勾浮出
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
    /// 2026-10-29 性能：全仓零读取方（见 RootTabs 里那条注释），只被写入 —— 不需要发布。
    var pendingCredPanel: String?
    /// 358 整理建议 → 凭证页多选预勾选: 建议行点按带过来要勾的密码 alias 表。
    /// 与 pendingCredPanel (到了开哪个面板) 是两回事 —— 这个负责"进了多选先勾好哪些", 同 pendingRecordKey 族只存会话态。
    @Published var pendingCredSelect: [Int]?
    // 包9/582 图表下钻: 统计页成员条 → 记录 Tab 按该成员过滤
    @Published var pendingRecordsMember: String?
    /// 817 建档向导直达: 记录页/其它入口置 pendingMemberAdd → 成员中心到达即弹建档向导。
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
    /// 子页里那些"去设置…"动作) 写着 `app.tabSelection = 3` ——
    /// 而它们本来就是**设置 Tab 下 push 进去的页**, 切 Tab 是一次空转: 点了什么都不发生,
    /// 前者还配着"跳转设置 Tab 的密码区"的无障碍提示, 后者配着"已切到设置"的 toast。
    /// 与 pendingDiag / pendingCare 同一条路由形态: 把"到了之后开什么"带过去, 设置页收到即开并清空。
    @Published var pendingSettingsFocus: String?
    private var unlockTask: Task<Void, Never>? = nil
    private var lastDispatch = Date.distantPast   // 244 指令去重
    private var dispatchAt = Date.distantPast     // 56 撤销窗口计时基准
    private var lastUnlockSuccessAt: Date?        // 250 30 秒内二次开锁判定

    init() {
        // 2026-10-17 拍板 A: 删掉启动门禁 —— 打开 App 不再需要本机密码/FaceID。
        // 旧值 `!DB.hasPasscode()`: 设过密码的机器每次冷启动都停在 AppLockView。
        // 其余安全动作 (毁灭操作复核 383 / 访客受限区复核 377) 改成**只走面容/指纹**。
        loadDevices(preferDefault: true)   // 包3/271: 冷启动落到上滑固定的默认锁
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
    /// 2026-10-29 性能：`status` 是 @Published，而它被 RootView 与设备页观察 ——
    /// 每次轮询无条件赋值都会让整棵树重算 body，哪怕读数一模一样（绝大多数轮询都是这样）。
    /// 这里只在真的变化时赋值。
    func applyStatus(_ st: LockStatus) {
        if status != st { status = st }
    }

    /// 2026-10-29 修复：`refreshStatusQuietly` 的调用点里 `select()` 与开锁复位定时器是**并发**的 ——
    /// 而函数体在 await 之后才写 `status`。场景：用户切到 B 锁 → select 起了一次读 → 还没回来时
    /// 开锁复位定时器那次（读的是 A 锁）先返回 ⇒ `status` 被写成 A 锁的读数，而界面标题是 B。
    /// 用世代号 + 返回前复核当前锁，过期的那次直接丢弃。
    private var statusTicket = 0

    func refreshStatusQuietly(manual: Bool = false) async {
        guard manual || !DiagFlags.silent else { return }
        guard let kc = current else { return }
        statusTicket += 1
        let ticket = statusTicket
        do {
            try await lock.ensureConnected(mac: kc.mac)
            let st = try await lock.getStatus()
            // await 之后世界可能已经变了：世代号变了，或当前锁已经不是发起时那把。
            guard ticket == statusTicket, currentMac == kc.mac else { return }
            applyStatus(st)
            LockArchive.touchConnected(kc.mac)   // 包3/292: 连接成功刷新沉睡判定基准
        } catch {
            guard ticket == statusTicket, currentMac == kc.mac else { return }
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
        // 2026-10-29 性能：具体展示逻辑在 ToastCenter 里（带自己的自动清除计时），
        // 这样一次提示只重算一条提示条，不再把整棵树带着算一遍。
        ToastCenter.shared.show(msg)
    }

    // 开锁 (App opendevice 语义: rc=0 成功 / rc=22 双验继续 / 其余报错)
    // 包1 手势族统一入口: 按住确认/上滑/VO 直开都汇到 requestUnlock。
    // 防误触三保险: 244 去重队列 → 250 二次开锁应用锁 → 56 撤销窗口 (执行期轻点)。
    func requestUnlock() {
        // 2026-10-26: 这里原有 guard SecurityPolicy.allows(.unlock) 拦截（296 只读安全模式）。
        // readOnly 读的 SecKey.safeModeOn 从来没有写点（设置页无此开关）⇒ 恒 false ⇒ guard 永远放行，已删。
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
            showToast("指令已收到， 正在执行")
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
        // 同上：startUnlock 那层 guard 也已删（同一个恒 false 的只读模式判据）。
        unlockTask?.cancel()
        unlockTask = Task { await runUnlock() }
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
    }

    // ---------- 246 本次用哪条 PIN ----------
    /// 存的是**下标**而不是 PIN 本身 —— 口令留在钥匙串 (kc.pins) 里, 不落 UserDefaults。
    /// -1 / 越界 = 未选, 交给 LockService 走既有的 `kc.pins.first` 兜底 (老行为不变)。
    func chosenPinIndex(_ mac: String) -> Int { DB.store.getInt("kf_pinpick_" + mac, -1) }
    // 【保留未接 2026-10-29】多 PIN 时记住「用哪一枚」—— 多锁/多 PIN 场景
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
        for attempt in 1...attempts {
            // 2026-10-29 修复：取消后底层可能把 CancellationError 包成 BLE 超时再抛上来，
            // 那样会落进下面的 catch 继续跑下一轮 —— 已取消的操作会「复活」并把状态改成失败。
            if Task.isCancelled { return }
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
                    return
                }
                lastRc = rc                             // 86: 错误码进失败快照
                lastMsg = StatusParser.rcFriendly(rc)   // 84 人话直读
            } catch is CancellationError {
                return   // cancelUnlock 已复位, 不计入失败
            } catch {
                lastMsg = error.localizedDescription
            }
            // 2026-10-29：catch 之后再看一次 —— 取消不算失败，也不该进 failStreak / 重试。
            if Task.isCancelled { return }
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
        // 2026-10-29：取消时不写失败终态（cancelUnlock 已把状态复位成 idle）。
        if Task.isCancelled { return }
        // 终态失败: 直读原因 (84) + 写入时间线标记 (92)
        unlockState = .failed(lastMsg)
        phase = 0
        UINotificationFeedbackGenerator().notificationOccurred(.error)
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
            showToast("本次开门已记录， 可到「记录」回看")
        }
    }
    func onLaunch() {
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
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // 包3: 258 首连验证标记 (开锁成功=全链路跑通) + 292 连接基准刷新
        LockArchive.markVerified(currentMac)
        LockArchive.touchConnected(currentMac)
        // 2026-10-15 走查 (对照 H5 权威 main.js @577111): 双验模式 (verifyMode==1) 下 rc==0
        // 只是第一道通过, H5 原版此刻会提示「门锁已开启双重验证，请继续使用指纹/密码开锁」。
        // 此前直接报「门已打开」= 对 B 模式用户说谎; 用状态帧镜像判, 快照未读到时宁可不提示 (与
        // 与本 App「未读到≠无告警」同一口径)。
        if status?.verifyMode == 1 {
            showToast("双验模式： 第一道已通过， 请再用指纹或密码完成第二道验证")
        } else {
            // 来源标注 (用户 2026-10-17): 与自动档那句成对 —— 开完要能说清是自己点的还是走近自动开的。
            // 只在非双验时报"成功", 双验那条上面已经给了实话。
            showToast("手动开锁成功 — \(displayName)")
        }
        // 成功反馈: 触感 + 圆盘回待机 (提示音已随波 1 移除)
        Milestones.recordUnlockSuccess()
        let hour = WeekCal.gregorian.component(.hour, from: Date())
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
        // 2026-10-29 性能：循环里每行调一次 DB.member（各自解析一份成员字典）。一次建表。
        let memberByID = Dictionary(DB.members().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for (i, e) in logs.enumerated() {
            guard i < rows.count else { continue }
            let c = rows[i]
            var text = e.lockTimeStr.isEmpty ? e.typeName : String(e.lockTimeStr.dropFirst(5).prefix(11)) + " · " + e.typeName
            // 559: 带出可证明的成员 id 供"查这位成员的记录"; 判据与下面显示成员名**同一条** ——
            // 行上真写着成员名才带出, 成员已从档案删掉的行走 landMember 的 guard 也只会落个失败 toast。
            var whoId: String? = nil
            if let who = c.who, let m = memberByID[who] {
                // 919: 别名开关开且 relation 非空时, 首页这行也走关系称呼
                let shown = MemberHub.aliasName(who) ?? m.name
                text = (e.lockTimeStr.isEmpty ? "" : String(e.lockTimeStr.dropFirst(5).prefix(11)) + " · ") + shown + " 用" + (Attribution.words[c.kind ?? ""] ?? "") + "开了门"
                whoId = who
            }
            // 第一百五十七批：这里原本自己写着 `type == 7 || 13 || 224` —— 5 类告警只圈了 3 类，
            // 于是设备页这行**低电量(4) 与 密码失败锁定(10) 的告警不标红**，
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
    @ObservedObject var sense = LinkSense.shared
    /// 2026-10-27：应用锁（冷启动门禁 + 伪装码）
    @ObservedObject var lock = AppLock.shared
    // 162 握手可离开: 圆盘握手在别的 Tab 完成 → 设备 Tab 亮角标; 回到设备页清零
    @State var handshakeDoneAway = false
    @Environment(\.scenePhase) var scenePhase
    // 读取 themeSeed: 设置页切换主题时立即重建配色
    var colorScheme: ColorScheme? { Theme.scheme(for: app.themeSeed) }

    /// 顶部横幅栈 (演示/BLE/自检/粘贴建议/toast/写入回执) —— 从 body 内联的 safeAreaInset
    /// 里抽出: 该表达式报 type-check 超时。
    @ViewBuilder
    var topBanners: some View {
        VStack(spacing: 0) {
            // 包2/69 蓝牙直通条: 系统蓝牙关闭时全 App 顶部提示 (深链系统设置不可用 → 指引文案)
            if !LinkSense.shared.btOn {
                BLEOffBanner(denied: LinkSense.shared.btDenied) {
                    LinkSense.shared.openBluetoothSettings()
                }
            }
            // 包8/448 启动自检黄条: 库体哈希与上次快照不一致 → 设备 Tab 顶部黄条 "去诊断"
            // 2026-10-29 性能：提示条改由独立宿主观察 ToastCenter —— 见 ToastBannerHost 注释。
            ToastBannerHost()
            // 包8/508 写入回执: 凭证保存/停用成功后对勾浮出 (替代云同步反馈)
            if let r = app.writeReceipt {
                writeReceiptView(r)
            }
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

// 2026-10-26: 原 `GuestReauthGate`（377 访客受限区复核页）已删 —— 它的唯一入口
// （fullScreenCover on showGuestGate）已随访客通道一起移除，视图本身零引用。


/// 872 防连点: 300ms 内重复点击忽略 (开关 AXPrefs.dbltapGuard, 默认开)。
/// 做法是 **PrimitiveButtonStyle 外包一层闸 + 内层仍是真 Button** ——
/// ButtonStyle 拿不到 action (拦不住点击), 而直接在外层用 onTapGesture 会把 List 行点击、
/// 滚动手势、VoiceOver 激活这些系统语义弄丢 (全仓 40 处调用点都在吃这些语义)。
/// 内层 Button 保留全部系统行为, 只有 trigger() 走闸; 闸状态是每个按钮各自的 @State, 不跨按钮误伤。

/// 卡片表面: 靠 surface 与渐变画布的明度差分层, 不加描边。
/// 每张卡都套 0.5pt 描边会让所有卡片看起来出自同一个模板 —— 描边是 1px Web 做法,
/// iOS 上 surface/canvas 的明度差已经足够表达层级, 描边反而是重复劳动。
/// 阴影在深色模式下纯黑不可见, 故改用极淡的提亮。
/// `tint` 给"需要处理"的卡混入语义色底 (8%), 让异常自带色温而不靠描边。
// 2026-10-16: 从 `private` 放开成 internal —— 第二个消费点在 App/Core/VariantGrammar.swift 的
// `card()`（新语法层的主表面，同一句 `.shadow(color: .cardElevation, radius: 12, y: 4)`）。
// **只此一处定义**是刻意的：另抄一份阴影色，两套变体迟早会在这一步上分家。
