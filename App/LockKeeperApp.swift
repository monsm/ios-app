// 离线锁管家 for iOS — App 入口与全局状态 (SwiftUI 全原生)
import SwiftUI
import UIKit
import UserNotifications

@main
struct LockKeeperApp: App {
    @StateObject private var app = AppState()
    // 启动期系统职责走 UIApplicationDelegate 适配器 (BGTask 注册 / 密钥迁移 / MAC 字节序回灌)。
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
    // 2026-10-26: 原 `guestAreaLocked`（377 访客通道闸）已删 —— 它依赖 `SecurityPolicy.guestActive`，
    // 而 `kf_speek_guest` **从来没有写点**（设置页无此开关）⇒ 恒 false ⇒ 本属性恒 false。
    // 于是下游四处判据全部恒等于「访客未开启」：凭证/设置 Tab 永远显示、访客入口按钮永不出现、
    // 换页闸永不拦截。按"删功能"处置：连同下面四处判据一起展开成无条件。
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

    /// 应用锁验证通过后的落地。
    /// 2026-10-26: 原 `reauth` 参数已删 —— 它只服务 377 访客通道的「只放开 Tab 不动 appUnlocked」，
    /// 而那条通道已整套删除（guestAreaLocked 恒 false）。现在只有一种落地：置 appUnlocked。
    func commitUnlock() {
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
    @Published var pendingCredPanel: String?
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
        appUnlocked = true
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
        // 86 失败快照: 失败当时的 RSSI / 电量 / 错误码一起留痕 (电量取本机缓存读数, 与 125 同一份口径)
        DB.recordFailEvent(kc.mac, lastMsg,
                           rssi: LinkSense.shared.lastRssi,
                           pct: DB.readStatus(kc.mac)?.powerLevel,
                           rc: lastRc)
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
    /// 900 全局圆角档位: ""(标准)/soft/plump
    func setRadius(_ key: String) {
        applyAppearance { DB.store.set("kf_radius", key) }
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
        "kf_auto_retry",
        // 2026-10-15 走查 §7.4-10: 无障碍那批键此前全部走 applyAppearance ⇒ 换身份 ⇒ 整树重建
        // = **拨一次开关被弹回设置页顶部**。并入条件是逐键查出来的：**全部**读取点都必须落在
        // "会因 AppState 的 @Published 变化而重算 body"的位置。
        //   · 根上 `.dynamicTypeSize(...)` 挂在 `.id(app.appearanceSeed)` **之外**、RootView.body 之内，
        //     而 RootView 观察 app ⇒ prefSeed 一样让它们重算，"根层修饰符"不构成否决；
        //   · UnlockDial 自己不观察 app，但 `kf_hold_confirm` / `kf_fence` 早就在里面以同一形状
        //     （计算属性喂 body）被读 ⇒ `kf_dial_size` / `kf_gesture_mode` / `kf_ax_hold` 同一条级联。
        //
        // 2026-10-26 精简：原名单里 8 枚键连同它们的读取属性与消费代码一起删除（无写点 ⇒ 恒默认值），
        // 因此从本名单移除：kf_ax_captions / kf_ax_doublehaptic / kf_ax_gray / kf_onehand /
        // kf_font_scale / kf_form_bottom / kf_lefty / kf_vo_announce。
        "kf_ax_bigotp", "kf_ax_bigpreview", "kf_ax_hold", "kf_bigtile",
        "kf_dial_size", "kf_gesture_mode"
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
            // kf_motion 的默认档是 "standard"，remove 就等于回到默认 (不是关掉动效)
            DB.store.remove("kf_motion")
            DB.store.remove("kf_digit_font")   // 902
            themeSeed = ""
        }
    }

    /// 启动结算: 异常退出卡(758) / 保留期到期卡(752) / 自动归档(223) / 关怀与凭证巡检 / 启动自检与月度备份排程
    func onLaunch() {
        // 758 启动提示: 上次异常退出时先给一张时刻卡 —— 此前只有走进诊断页才看得到那条标签,
        // "启动时提示"这一半不存在。防重键带档案首行 (含检测时刻), 同一次异常只弹一次。
        // 2026-10-26: 「保留期到了但先不删」这段已删 —— 它读 SecKey.auditRetention（385 保留期），
        // 而那个键**从来没有写点**（设置页没有保留期选项）⇒ retention 恒 0 ⇒ 整个 if 永不进入。
        // AuditLog().purgeExpired(months:) 因此从未被自动调用过；手动清理入口仍在诊断页，不受影响。
        // 223 启动自动归档: 诊断页那枚开关开着才动手 (默认关), 走与手动按钮同一引擎; 条数进维护回执 (387)
        if DB.store.getBool("kf_diag_autoarchive") {
            let archived = DataHealth.archiveOldLogs()
        }
        let cal = WeekCal.gregorian
        let now = Date()
        let year = cal.component(.year, from: now)
        // 包8: 448 启动自检 (库体哈希 vs 上次快照, 异常挂黄条) + 1018 月度备份日排程
        //       + 428 充电备份 BGTask 注册 (系统择机执行, 不承诺接电即备) + 445 中断迁移检测
        Task { @MainActor in
            // 428: BGTask 注册已移到 QuickActionDelegate.didFinishLaunchingWithOptions ——
            // 必须早于启动完成 (Apple 契约), 且每进程只注册一次 (onLaunch 可能被多次调用)。
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
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // 包3: 258 首连验证标记 (开锁成功=全链路跑通) + 292 连接基准刷新
        LockArchive.markVerified(currentMac)
        LockArchive.touchConnected(currentMac)
        // 2026-10-15 走查 (对照 H5 权威 main.js @577111): 双验模式 (verifyMode==1) 下 rc==0
        // 只是第一道通过, H5 原版此刻会提示「门锁已开启双重验证，请继续使用指纹/密码开锁」。
        // 此前直接报「门已打开」= 对 B 模式用户说谎; 用状态帧镜像判, 快照未读到时宁可不提示 (与
        // 与本 App「未读到≠无告警」同一口径)。
        if status?.verifyMode == 1 {
            showToast("双验模式: 第一道已通过, 请再用指纹或密码完成第二道验证")
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
            .keyboardShortcut("1", modifiers: .command)
    }
    @ViewBuilder private var credentialsTabContent: some View {
        // 身份挂在这里 (父层) 才有效: CredentialsView 的 @State 由 TabView 持有,
        // 在其 body 内部写 .id(app.currentMac) 不会重建该 struct → 切锁后
        // selPwds/selFps/otpPwd 仍是上一把锁的值, 批量停用会打到错锁。
        CredentialsView().id(app.currentMac)
            .safeAreaInset(edge: .top, spacing: 0) { bleStatusStrip(app: app, sense: sense) }
            .keyboardShortcut("2", modifiers: .command)
    }
    @ViewBuilder private var recordsTabContent: some View {
        // 同凭证 Tab: 记录是纯 per-lock 数据, 在父层挂身份才能整体重建。
        // RecordsView 只有 :178 onAppear→loadFromCache, 编程式切锁 (跳回/意图改 currentMac)
        // 不触发 → groups/allRows 仍是旧锁行, :1187 的认领会把旧锁 idxRaw 记到新锁键下。
        RecordsView().id(app.currentMac)
            .safeAreaInset(edge: .top, spacing: 0) { bleStatusStrip(app: app, sense: sense) }
            .keyboardShortcut("3", modifiers: .command)
    }
    @ViewBuilder private var settingsTabContent: some View {
        SettingsView()
            .safeAreaInset(edge: .top, spacing: 0) { bleStatusStrip(app: app, sense: sense) }
            .keyboardShortcut("4", modifiers: .command)
    }

    /// 顶部横幅栈 (演示/BLE/自检/粘贴建议/toast/写入回执) —— 从 body 内联的 safeAreaInset
    /// 里抽出: 该表达式报 type-check 超时。
    @ViewBuilder
    private var topBanners: some View {
        VStack(spacing: 0) {
            // 包2/69 蓝牙直通条: 系统蓝牙关闭时全 App 顶部提示 (深链系统设置不可用 → 指引文案)
            if !LinkSense.shared.btOn {
                BLEOffBanner(denied: LinkSense.shared.btDenied) {
                    LinkSense.shared.openBluetoothSettings()
                }
            }
            // 包8/448 启动自检黄条: 库体哈希与上次快照不一致 → 设备 Tab 顶部黄条 "去诊断"
            if let w = BackupStudio.selfCheckWarning {
                selfCheckBanner(w)
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
        // 包2/136 跨页状态细条: 非设备 Tab 顶部一条 BLE 状态细线, 点按跳回设备页定位当前锁;
        // 162 握手可离开: 切走 Tab 不取消进行中的握手 (回连循环/看门狗继续跑)
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
                    // 2026-10-26: 原「访客通道入口按钮」已删 —— guestAreaLocked 恒 false，
                    // 这个按钮从未显示过。
            }
            .padding(.bottom, DS.Space.xs)
        }
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
        rootChrome
    }

    /// 主界面。首启引导已随本轮删减移除, 启动不再分形态 —— 这里只返回主界面本体。
    @ViewBuilder
    private var rootGroup: some View {
        mainTabsChrome
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
    private func selfCheckBanner(_ w: String) -> some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: DS.Icon.sm, weight: .semibold))
                .accessibilityHidden(true)
            Text(w).vkFont(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("去诊断") {
                // 2026-10-15 走查 §4.3: 按钮说"去诊断", 原来只把人放到
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
            // 2026-10-17 拍板 A: 「到点自动落锁」随启动门禁一起删 —— 现在没有锁屏页可回,
            // 留着它只会把 appUnlocked 置 false, 让深链/落点/回连那些 guard 静默失效。
            if app.appUnlocked {
                // 靠近自动开锁 (AUTOOPEN): F0 前台门 + F1 进前台按档位刷面容 (挂起期静默)
                AutoOpenController.shared.onForeground(mac: app.currentMac)
                // 344 回前台才出快捷条 (344 的原话就是"回前台显示"), 顺带重算剩余秒数
                // 897 四季图标: 默认关。开着也只在"季节真的换了"时对齐一次 (年-季记号)，不每次回前台打扰
            }
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
        } else {
            // .inactive: 只收起过期的快捷条, **不**记锁定到期时刻 (否则反复下拉通知中心可无限顺延宽限)。
            // 但崩溃标记仍要清 —— 从任务切换器强退时进程多在 .inactive 被 SIGKILL,
            // 只在 .background 清会把正常强退误报成"异常退出"。
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

// 2026-10-26: 原 `GuestReauthGate`（377 访客受限区复核页）已删 —— 它的唯一入口
// （fullScreenCover on showGuestGate）已随访客通道一起移除，视图本身零引用。

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
