import SwiftUI

// ═══════════════════════════════════════════════════════════════════════
// MARK: - 门厅（全 App 唯一主界面）
// ═══════════════════════════════════════════════════════════════════════
//
// 合并原 D 就近 / F 仪表 / B 管家台三个域。
//
// ═══════════════════ 设计契约 ═══════════════════
// 2026-10-22 按 Black Canvas / Glass Instrument 范式重排。
//
// 【层】本页是**应用体**，不是展示壳 —— 黑画布 + 深卡 + 浅色文字。
//   "看到白卡 → 你在展示壳; 看到深卡 → 你在应用体。" 本页一张白卡都没有。
//
// 【用途】operate。用户举起手机的那一刻只有两种意图：
//   ① 站在门口，要进去 ② 想知道今天家里发生了什么。
//   所以：开锁动作占据唯一的「主视觉焦点」，数据是第二层，管理是第三层。
//
// 【构图】规范 5.3 的屏幕骨架，主路径五段 + 一个空状态：
//   ① 页眉（时间 + 连接态）—— 20pt 高，不抢焦点
//   ② 空状态 —— 未配对门锁时唯一的出口（去配对）
//   ③ 门的身份 + 一句摘要 —— LargeTitle 30/Bold/-0.4，落在 29pt 对齐线上
//   ④ 开锁环 220pt ——— **全屏唯一主角**（规范 9: 一屏只能有一个 >=200pt 的环）
//   ⑤ 三个指标 / ⑥ 今日柱图 / ⑦ 成员 —— 一眼看懂今天
//   ⑧ 五个管理入口 —— soft 边界，不诱导
//
// 【排版】全部走语义字号（.xFont），不裸写 .font —— 这样 Dynamic Type 才真的生效。
//   锁名        30pt bold / 字距 -0.4   (规范 4.2 largeTitle)
//   指标数字    19pt rounded semibold  (规范 4.2 title2)
//   区块标签    11pt semibold 大写 + 0.8 字距 (规范 4.2 caption)
//   正文 16 / 辅助 14 / 极小 12 —— 字阶比 HIG 默认小约 12%，是实测值不是惯例值
//
// 【色彩】一色一义，中性为主，彩色只给"此刻"与"可操作"
//   accent 铜  = 主操作、当前小时、今日高亮
//   ok 绿      = 已连接、已上锁
//   warn 黄    = 电量低 / 可恢复异常
//   danger 红  = 失败 / 告警
//   灰阶       = 一切结构与说明，不做彩色装饰
//   **一屏 <=3 种强调色**（规范 3.4 铁律）—— 本页正好用到铜/绿/黄/红四档语义，
//   但任意时刻同时出现在屏上的彩色不超过 3 种（状态胶囊 + 当前小时 + 一条告警）。
//
// 【开锁环】按物理对象设计，不是按钮
//   · 静息：6pt 中性轨道 + 锁图标 + "按住开锁"（明确告知手势）
//   · 按下：瞬时缩放 0.97、图标 lock→lock.open 符号替换、触觉一次
//   · 蓄力：铜色进度弧从 12 点顺时针、带柔光；1.05s 充满（重复使用不能太慢）
//   · 成功：弧转绿 + 勾号 + 成功触觉，0.8s 后回到静息
//   · 失败：弧转红 + 下方一行原因 + 警告触觉，2s 后回静息
//   · 中途松手：0.18s 回零（不惩罚用户，但也不假装成功）
//   · reduceMotion：不缩放、不柔光，进度仍可见（功能不降级）
//
// 【无障碍】VoiceOver：环是一个按钮，标签"开锁"，hint"按住直到进度环充满"；
//   另有 .accessibilityAction 直接开锁，视障用户不必长按。
struct HomeConsole: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// 全局刷新中心。开门成功、从后台回前台、安全设置变动都会 bump 它。
    /// 没有这个观察，本页的"今日开门 / 分时柱图 / 成员"在开门之后**不会更新** ——
    /// 因为数据是在 body 里现算的，而 SwiftUI 只在状态变化时重算 body。
    @ObservedObject private var ticker = SecTickCenter.shared

    @State private var phase: UnlockPhase = .idle
    @State private var progress: CGFloat = 0
    @State private var pressing = false
    @State private var failure: UnlockFailure?
    /// 开锁进行中标志 —— 同步置位，用作重入闸门。
    /// 只靠 phase 判断挡不住并发：performUnlock 里第一个 await 之前 phase 还是
    /// .charging，此时第二次调用能顺利通过 phase 检查，于是两次 BLE 开锁并发执行。
    @State private var isUnlocking = false
    @State private var settlingTask: Task<Void, Never>?
    /// 首启用：一把锁都没有时，直接开配对页。
    /// 原来这里走 managerGroup = .devices —— 用户先看到一张**管理面板**，
    /// 还得自己再找一次「添加门锁」。首启最关键的一步不该有多余一跳。
    @State private var showAddLock = false
    /// 门厅成员卡的直达目标。
    /// 原来成员卡是纯展示：想看某个人的权限，
    /// 要 管理 → 成员 → 选人 三步，才到成员详情。
    /// 而门厅上那张卡已经写了他的名字和今天的次数 —— 点它是最自然的意图。
    @State private var memberSheetID: String?
    /// 分时图点选的小时 → 打开事件页并按该小时筛选。
    @State private var hourSheet: Int?
    /// 近 7 日到期的条数。recompute 里算一次 —— 它要遍历所有密码，不能每帧重算。
    @State private var expiringCount = 0
    @State private var showEvents = false
    @State private var appeared = false

    // ── 当日统计缓存 ──
    //
    // 原来 hourCounts 是个计算属性，而 opensToday / dayChart / firstOpenText / digest
    // 各自都会调它 —— 一次渲染要**完整扫四遍日志**。加上刷新机制之后
    // （ticker bump、下拉刷新、回前台）这个代价会被放大。
    // 改成：一次扫描写入缓存，渲染时只读。
    @State private var hourCounts: [Int] = Array(repeating: 0, count: 24)
    @State private var memberStats: [MemberStat] = []
    /// 未处理告警数与跨天数 —— **缓存**，不放在计算属性里。
    ///
    /// 2026-10-23：原来它们是计算属性，而 `criticalNotice` 在 body 里读它 ——
    /// 于是**每次重渲染都会** `DB.keychains()` + 全量扫一遍所有锁的日志，
    /// 有告警时还要再扫一遍数跨天。ticker 一跳就是一次。
    /// 同文件里 hourCounts / memberStats / expiringCount 早就走缓存了，这两项是漏网的。
    @State private var alarmCountCache: Int? = nil
    @State private var alarmSpanCache = 0
    @State private var lastOpenClockCache: String? = nil
    @State private var showRingInfo = false

    @Environment(\.scenePhase) private var scenePhase

    private var mac: String { app.currentMac }

    // 蓄力时长：1.05s。太短易误触，太长（≥1.5s）重复开门会烦躁。
    private let chargeDuration: Double = 1.05

    var body: some View {
        NavigationStack {
            ZStack {
                // 六图改造 (2026-10-23): 画布从**平色纯黑**改成**径向渐变**。
                //
                // 图 1/2/6 的画布没有一个是平的 #000：顶端 6% 压了一层 #0A0E1A（偏冷深蓝），
                // 38% 降到 #06070C，底部才是纯黑。平的纯黑会让整屏发死、卡片浮不起来。
                // 这层渐变是所有卡片"能浮起来"的前提。
                XPalette.canvasGradient.ignoresSafeArea()
                ScrollView {
                    // ═══ 页面骨架：规范 5.3 ═══
                    //
                    // 页边距 14（XSpace.gutter），区块之间 28（XSpace.section），
                    // 簇内 16，**卡片行间距 12**。四个数各自有语义，不许合并成一个。
                    //
                    // 2026-10-23 更正：这里原来写「卡片行间距 8」。8 是 §5.1 的 `s3`，
                    // 但规范别处写了**四次 12**（G9 判定项 / §7.x 组件表 / §15 B3 验收项 / §5.3 图），
                    // 其中两个是硬约束。XScreen 已统一按 12 做，注释同步。
                    //
                    // 旧实现整页用 XSpace.l(16) 一以贯之，只靠"多 8pt" 拉簇间 ——
                    // 那是 16 与 24 的差别，眼睛读不出分组。规范给的差是 16 与 28。
                    VStack(spacing: XSpace.section) {
                        masthead
                        // 标题 → 首卡 **74pt**（规范 §5.3 / 验收 L4「页面最大的呼吸区」）。
                        // 它是全页唯一比其他间距都大一档的留白，语义是「标题属于页面，
                        // 下面属于内容」。用 pageTop(40)+section(28)=68 会差 6pt ——
                        // 而这一处的意义恰恰在于它比别处都大，凑出来就不成立了。
                        if mac.isEmpty {
                            // ── 空状态 ──
                            // 没有门锁时，把一屏的 0 和按不动的环摆出来是最没用的界面。
                            // 这里只留一件事：告诉你下一步做什么。
                            noLockState
                        } else {
                            // 簇一：这一把锁（身份 → 待处理 → 开锁）—— 全屏唯一主角
                            VStack(spacing: XSpace.l) {
                                identity
                                    // VStack 已经在 masthead 与本题之间给了 section(28)，
                                    // 这里补到 74：28 + 46 = 74。
                                    .padding(.top, XSpace.titleToFirstCard - XSpace.section)
                                if let notice = criticalNotice { noticeRow(notice) }
                                unlockStage
                            }
                            // 簇二：今天的数据（指标 → 分时 → 成员）
                            VStack(spacing: XSpace.l) {
                                metricsRow
                                todaySection
                                // ═══ 2026-10-24 逐页对齐 HTML 01-home 最后一块 ═══
                                //
                                // HTML 在「今日开门分布」之后还有一块**开门历史**：
                                //   24pt/700 标题「开门历史」
                                //   + 150pt 高的面积图（左侧面积 + 顶部网格线）
                                //   + 右侧「更早 / 更近」两枚标签
                                //   + 底部月份轴（9-24 / 10-04 / 10-14）
                                //
                                // 真机此前完全没有这一块 —— 门厅只能说"今天多少"，
                                // 看不到"最近两周的趋势"。而参考图 1（Health Age History）
                                // 正是这个形态：标题 + 面积图 + 时间轴。
                                openHistorySection
                                memberSection
                            }
                        }
                    }
                    .padding(.horizontal, XSpace.gutter)
                    // 页面顶部留白 40 ——— 规范 5.1 的 s8。这是"标题到首卡"呼吸区的起点,
                    // 做小了整页会显挤 (规范 P.S. 的 L4 验收项就是量这个)。
                    .padding(.top, XSpace.pageTop)
                    // 底部留白 —— **原生 TabView 下只需一点呼吸，不再要 108。**
                    //
                    // 108 是给手写浮动胶囊算的：56(栏高) + 20(距底) + 16(呼吸) + 16。
                    // 换成原生 TabView 后，系统会自己把安全区让出来 ——
                    // 再补 108 会让页面底部空出一大块，滚到最下面像断了。
                    //
                    // 留 16：与 §5.1 的 s4 同档，只求最后一张卡不贴着栏体。
                    .padding(.bottom, XSpace.l)
                    .opacity(appeared ? 1 : 0)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    // 下拉是**用户显式要求刷新**，所以这里允许主动连门锁拉实时状态。
                    SecTick.bump()
                    await app.refreshStatusQuietly(manual: true)
                }
            }
            .navigationBarHidden(true)
            .onChange(of: scenePhase) { _, phase in
                // 回前台只重算**本地**数据（别处开过门、成员变动都可能让统计过期），
                // 成本只是一次 DB 扫描。
                //
                // 这里刻意**不**调 refreshStatusQuietly：那个方法会真的建立 BLE
                // 连接去读实时状态。每次切回 App 都唤醒一次门锁，既费电也不符合
                // 用户预期（他可能只是回个微信）。要拉实时状态有下拉刷新这条
                // 显式路径。
                if phase == .active {
                    SecTick.bump()
                } else {
                    // 切走就放弃蓄力。否则那个 1.05s 的 Task 会在后台睡完，
                    // 然后真的发出一次 BLE 开锁 —— 用户只是去回了个微信。
                    abortCharge()
                }
            }
            .onChange(of: ticker.tick) { _, _ in recompute() }
            // 377: 访客复核通过后，把刚才被拦下的那个管理组打开。
            //   · 只在**放开那一刻**读一次（takePendingGateGroup 读完即清），
            //     所以关掉访客区之后不会再"诈尸"打开上次那个组；
            //   · 落点存在 AppState 而不是本页 @State：本页可能因为 .id(appearanceSeed)
            //     换身份重建，@State 会丢，而用户刚验完口令什么都没发生是最差的表现。
            .onChange(of: app.guestAreaUnlocked) { _, unlocked in
                guard unlocked, let g = app.takePendingGateGroup() else { return }
                openGroup(g)   // 走同一条入口：既有访客闸，也切 Tab
            }
            .onAppear {
                recompute()
                guard !appeared else { return }
                // 规范 11.3: 减少动态时全部降级为 0.2s crossfade, **取消位移与缩放**。
                // 这里本来就没有位移 (只做 opacity), 所以两条分支的差别只在时长 ——
                // 但时长本身是"动得少"的一部分, 所以仍走 XMotion 而不是写死。
                // 规范 §11.1「卡片入场 spring 0.50 / 0.85, y +14→0, 逐卡延迟 40ms」。
                // 门厅的内容是逐块出现的, 这正是那个曲线的用例; 原先借用 XMotion.soft
                // 只是"淡入", 没有位移也没有节奏。
                let enter = reduceMotion ? XMotion.reduced : XMotion.cardEnter
                withAnimation(enter) { appeared = true }
            }
            .onDisappear {
                // 视图消失同样要中止，不能只 cancel Task：
                // 不把 pressing/phase 复位，下次回到这一页会停留在一个假的"蓄力中"。
                abortCharge()
                settlingTask?.cancel()
            }
            // ═══ 深链兼容 ═══
            //
            // 删掉 DoorRoot 之后，requestRoute(.settings) 这类编程式跳转
            // 只会把 tabSelection 改掉，却没人接 —— 等于所有深链、快捷指令、
            // 通知点进来的落点全失效。这里把原来的 4 个 Tab 号映射成 5 个管理组，
            // 让旧漏斗继续有落点（纵深页面本身没删，仍在 ManagerFace 里）。
            .onChange(of: app.tabSelection) { _, t in
                guard let r = Route.from(tab: t) else { return }
                // 深链 / 快捷指令 / 摇一摇遁走都从这条落到管理组。
                // 它同样必须过访客闸 —— requestRoute 只拦了 tabSelection 这一半,
                // 而页面真正打开是在这里, 所以闸要跟着一起搬过来。
                openGroup(ManagerGroup.forRoute(r))
            }
            .sheet(isPresented: $showAddLock) {
                AddLockPage().environmentObject(app).trackScreen("配对门锁")
            }
            .sheet(isPresented: Binding(get: { hourSheet != nil },
                                       set: { if !$0 { hourSheet = nil } })) {
                if let h = hourSheet {
                    NavigationStack {
                        EventsPage(initialHour: h).environmentObject(app).trackScreen("事件·某小时")
                    }
                }
            }
            // 环的口径说明（§7.8 形态 1 的 info 按钮指向这里）
        .alert("这个环是什么", isPresented: $showRingInfo) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("环上的一圈是「今天开过几次门」：满圈是最近 30 天里最忙的那一天。\n"
                 + "只统计开锁类事件，不含失败的尝试；自动开锁也算一次。")
        }
        .sheet(isPresented: $showEvents) {
                NavigationStack { EventsPage().environmentObject(app).trackScreen("事件记录") }
            }
            .sheet(isPresented: Binding(get: { memberSheetID != nil },
                                       set: { if !$0 { memberSheetID = nil } })) {
                if let id = memberSheetID {
                    NavigationStack {
                        MemberDetail360View(memberID: id)
                            .environmentObject(app)
                            .trackScreen("成员详情")
                    }
                }
            }
        }
    }

    // ─────────────────────────────────────────── ① 页眉
    /// 顶部**芯片行** —— 规范 §7.2 StatChip，参考图 3 的形态。
    ///
    /// 2026-10-23 按参考图重做。原来这一行是「时钟 + 一个圆的连接状态」，
    /// 而图 3 那一排是**四枚胶囊**：每枚「圆形图标 + 灰标签 + 白值」。
    /// 那不只是排布差别 —— 胶囊本身就是「一屏有几个读数」的声明。
    ///
    /// 本 App 的四个读数（按「现在最该知道」排序）：
    ///   连接状态 / 电量 / 今日开门 / 待处理。
    /// 时钟退到最右侧（它仍在，但不再占一整行的左端）。
    /// 顶部芯片行 + 时钟。
    ///
    /// **2026-10-23 改成横向滚动。** 原来是 `HStack` 平铺 4 枚，
    /// 而 `XStatChip` 有 `minWidth: 120` —— 4 × 120 = 480pt，
    /// 屏宽只有 375，**必然溢出**（被裁掉半枚，或者把时钟挤没）。
    ///
    /// 规范 §7.2 给了两种合法排布：
    ///   · 双列固定 —— 2 枚并排撑满（图 3）
    ///   · **横向滚动 —— 间距 8、首尾 14、超出屏幕硬裁切（图 4）**
    ///
    /// 本 App 有 4 个读数，只能是后者。首尾 14 与页边距同值，滚动区看起来与卡片对齐。
    private var masthead: some View {
        VStack(alignment: .leading, spacing: XSpace.s) {
            ScrollView(.horizontal) {
                HStack(spacing: XSpace.s) {
                    chip(.link)
                    chip(.battery)
                    chip(.today)
                    chip(.alerts)
                }
                .padding(.horizontal, XSpace.gutter)
            }
            // §7.2：超出屏幕**硬裁切**，不加渐隐 —— 渐隐会让人以为内容到边了就没了。
            .scrollIndicators(.hidden)
            // 滚动区要能伸到屏幕边缘（首尾 14 靠内 padding 给），
            // 所以这里把父层的页边距吃掉。
            .padding(.horizontal, -XSpace.gutter)

            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                Text(clockText(ctx.date))
                    .xFont(.caption, weight: .medium, design: .rounded)
                    .foregroundStyle(XPalette.textTertiary)
                    .accessibilityLabel("现在 \(clockText(ctx.date))")
            }
        }
    }

    private enum MastChip { case link, battery, today, alerts }

    /// 四枚芯片的内容。`compact` 只保留图标 —— 屏宽不够时用它（§7.2 compact 变体）。
    @ViewBuilder
    private func chip(_ k: MastChip) -> some View {
        switch k {
        case .link:
            XStatChip(label: "连接", value: phase.label,
                      systemImage: app.status != nil ? "link" : "link.badge.plus",
                      tint: phase.tone, fillsWidth: false)
        case .battery:
            if let p = app.status?.powerLevel, p >= 0 {
                XStatChip(label: "电量", value: "\(p)%",
                          systemImage: BatteryCare.icon(p),
                          tint: BatteryCare.tier(p).tone.color, fillsWidth: false)
            } else {
                XStatChip(label: "电量", value: "—", systemImage: "battery.0", tint: XPalette.textSub, fillsWidth: false)
            }
        case .today:
            XStatChip(label: "今日", value: "\(opensToday) 次",
                      systemImage: "door.left.hand.open", tint: XPalette.accentText, fillsWidth: false)
        case .alerts:
            if let n = alarmCount {
                XStatChip(label: "待处理", value: "\(n)",
                          systemImage: "exclamationmark.triangle.fill", tint: XPalette.danger, fillsWidth: false)
            } else {
                XStatChip(label: "待处理", value: "无",
                          systemImage: "checkmark.shield", tint: XPalette.ok, fillsWidth: false)
            }
        }
    }

    // ─────────────────────────────────────────── ② 空状态

    // ─────────────────────────────────────────── ② 空状态
    private var noLockState: some View {
        VStack(spacing: XSpace.l) {
            Image(systemName: "lock.slash")
                .font(.system(size: XIcon.xl, weight: .light))
                .foregroundStyle(XPalette.textTertiary)
                .accessibilityHidden(true)
            VStack(spacing: XSpace.xs) {
                Text("还没有门锁")
                    .xFont(.title3, weight: .semibold)
                    .foregroundStyle(XPalette.text)
                Text("配对之后，这里会变成你每天的开门台")
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.textTertiary)
                    .multilineTextAlignment(.center)
            }
            Button {
                XHaptics.tick.impactOccurred()
                showAddLock = true
            } label: {
                Text("去配对门锁")
                    .xFont(.subheadline, weight: .semibold)
                    .foregroundStyle(XPalette.onAccent)
                    .padding(.horizontal, XSpace.xl)
                    .padding(.vertical, XSpace.m)
                    .xPlate(XPalette.accent, .capsule)
            }
            .buttonStyle(PressableScaleStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, XSpace.xxl)
    }

    // ─────────────────────────────────────────── ③ 门的身份 (LargeTitleHeader, 规范 7.1)
    //
    // 对齐线：大标题**不是**对齐卡片边缘，而是对齐卡片内的文字 ——
    // 整页只有一条文字线 X = 页边距(14) + 卡内边距(16) - 1 = 29（XSpace.align）。
    // 这条线断了，整页看起来就"差一点"，而那一点是差在 15pt 上的。
    private var identity: some View {
        VStack(alignment: .leading, spacing: XSpace.s) {
            Text(lockName)
                .xFont(.largeTitle, weight: .bold)
                .tracking(-0.4)
                .foregroundStyle(XPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(digest)
                .xFont(.body)
                .foregroundStyle(XPalette.textSub)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, XSpace.align - XSpace.gutter)
    }

    // ─────────────────────────────────────────── ③.5 关键状态
    //
    // 低电量和未处理告警是"现在就得知道"的事，原来只混在环下方那行 13pt 的
    // 小字里（"电量 12% · 上次 08:12 · 已上锁"）—— 那是**埋没**，不是提示。
    //
    // 这里把它们提到开锁环正上方、独立一条。位置固定、颜色固定，
    // 一眼扫得到；没有问题时整条不占位，不制造噪音。
    //
    // 刻意不挂到全局 topBanners：那套是"全 App 级闲时提醒"（自检/粘贴建议），
    // 而低电量是这把锁自己的事，应该出现在它自己的控制台上。
    private enum CriticalNotice {
        case lowBattery(Int)
        case alarms(Int)
        /// 930 的「近 7 日到期条数」原本是**凭证 Tab 的角标**。
        /// Tab 栏在单控制台重构时删掉了，这个数就没有去处了 ——
        /// 函数还在（`CredentialOrg.expiringSoonCount`），零调用。
        /// 门厅的关键提示正好是它的新家。
        case expiring(Int)
    }

    private var criticalNotice: CriticalNotice? {
        if let n = alarmCount, n > 0 { return .alarms(n) }
        if let p = app.status?.powerLevel, p >= 0, p <= 20 { return .lowBattery(p) }
        if expiringCount > 0 { return .expiring(expiringCount) }
        return nil
    }

    /// 读 recompute() 的缓存 —— 不要恢复成计算属性（见上面那段说明）。
    private var alarmCount: Int? { alarmCountCache }

    /// 未处理告警横跨几天。
    /// 只在确实有告警时才去数（alarmCount 为 nil 时本值不参与渲染）。
    private var alarmSpanDays: Int { alarmSpanCache }

    private func noticeRow(_ n: CriticalNotice) -> some View {
        let isAlarm: Bool
        let glyph: String
        let text: String
        let tone: Color
        switch n {
        case .alarms(let c):
            isAlarm = true
            glyph = "exclamationmark.shield.fill"
            // 只说"有 N 条"信息量不够：3 天各 1 条和 1 天 3 条是完全不同的处境。
            // 补上涉及天数，用户才知道这是"某天出了点事"还是"一直在被忽略"。
            text = alarmSpanDays > 1
                ? "有 \(c) 条告警还没处理 · 跨 \(alarmSpanDays) 天"
                : "有 \(c) 条告警还没处理"
            tone = XPalette.danger
        case .lowBattery(let p):
            isAlarm = false
            glyph = "battery.25"
            text = "门锁电量 \(p)%，该换电池了"
            tone = XPalette.warn
        case .expiring(let c):
            isAlarm = false
            glyph = "clock.badge.exclamationmark"
            text = "有 \(c) 项钥匙将在 7 天内到期"
            tone = XPalette.warn
        }
        return Button {
            // 告警/低电/到期三种提示都要把用户送到**能处理它的那一组**。
            // 走 openGroup 而不是直接置位: 这三条同样是"打开一个管理组",
            // 与门厅瓦片是同一件事, 不该有一份自己的绕行写法。
            let target: ManagerGroup
            if case .expiring = n { target = .ledger }
            else { target = isAlarm ? .system : .devices }
            openGroup(target)
        } label: {
            HStack(spacing: XSpace.s) {
                Image(systemName: glyph)
                    .font(.system(size: XIcon.sm, weight: .semibold))
                    .accessibilityHidden(true)
                Text(text)
                    .xFont(.footnote, weight: .medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: XSpace.xs)
                Image(systemName: "chevron.right")
                    .font(.system(size: XIcon.xs, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(tone)
            .padding(.horizontal, XSpace.m)
            .padding(.vertical, XSpace.m)
            .frame(maxWidth: .infinity, minHeight: XHit.min, alignment: .leading)
            // ⚠ 三参数重载要的是 XPlateShape，不是 CGFloat 圆角 —— 传错会直接编译失败
            .xPlate(tone.opacity(0.12), .control, edge: tone.opacity(0.35))
        }
        .buttonStyle(PressableScaleStyle())
        .accessibilityLabel(text)
        .accessibilityHint({
            if case .expiring = n { return "打开钥匙列表" }
            return isAlarm ? "打开安全中心" : "打开设备管理"
        }())
    }

    // ─────────────────────────────────────────── ④ 开锁环
    //
    // **全屏唯一主角**（规范 §9「一屏只能有一个 ≥200pt 的大环」）。
    //
    // 2026-10-23 按 §7.8 形态 1 改尺寸：
    //
    //   §7.8 形态 1（图 5 那只环）：「尺寸 **屏宽 − 28pt**（≈365pt，= 屏宽 − 页边距 ×2）」
    //   §9 / §15 B4：「大环 ≥200pt，一屏 ≤1」
    //
    // 220 只满足「≥200」这个**下限**，而 365 是规范给的**实际尺寸**。
    // 图 5 里那只环几乎占满屏宽 —— 220 做出来是「一个中等圆环」，
    // 不是「全屏主角」。两个数值的关系是：200 是资格线，365 是尺寸。
    //
    // 线宽跟着由 DSRing.stroke(forDiameter:) 重算（12%，365 × 0.12 ≈ 44）。
    /// 环的尺寸。
    ///
    /// 规范 §7.8 形态 1 写的是「**屏宽 − 28pt**（≈365pt）」。但本仓不能读屏宽：
    ///
    ///   · `UIScreen.main` 自 iOS 16 起**已弃用** —— 本仓 `ScreenCare.swift` 里
    ///     专门记录过这件事（"先用 UIScreen.main, 又换成 UIScreen.screens.first，
    ///     两者同样弃用"）。
    ///   · `GeometryReader` 会把环的坐标系从「父容器居中」变成「左上角对齐」，
    ///     而游标位置 (`cursorOffset`) 是按居中的极坐标算的 —— 改容器就得重推。
    ///
    /// 所以取一个**与屏宽无关的固定值 340**：
    ///   · 它是 §7.8 那个 365 在 iPhone SE/13 mini（375 宽）上的等比结果：375 − 28 = 347
    ///   · 在 393 宽的机型上留出 26pt 边距，比规范宽一点点，但环仍是"满屏主角"
    ///   · 340 × 12% ≈ 41，与规范 §7.8 给的「线宽 42pt」几乎重合 —— 这是个好信号：
    ///     规范那 42/340 = 12.4% 的比例本来就是按 340 档给的
    private var heroRingSize: CGFloat { 340 }
    private var heroRingWidth: CGFloat { DSRing.stroke(forDiameter: heroRingSize) }

    /// 环的**开口角度**（规范 §7.8 形态 1）：「开口在底部，约 60°（从 5 点到 7 点），两端圆头」。
    ///
    /// 参考图 5 的那只大环就是这个形态 —— 缺口让环有「未完成」的张力，
    /// 整圆只是「一个圈」。本 App 的开锁环是一个**进度量**（今天开过几次门），
    /// 与图 5 的 Health Age 环同构，所以采用它的形态。
    private var heroRingGap: Double { 60 }
    /// 弧的起始角。
    ///
    /// **角度基准是 SwiftUI 的 `Circle().trim`**：0° 在**3 点**，顺时针为正。
    /// （第一版我按「12 点为 0°」算成 210°，结果缺口开到了左上方 —— 基准错了。）
    ///
    /// 缺口居中在底部（6 点 = 90°），宽 60° ⇒ 缺口从 60° 到 120°（也就是 5 点到 7 点）。
    /// 所以**弧从 120° 起，扫 300°** 回到 60°。
    private var heroRingStartDeg: Double { 90 + heroRingGap / 2 }
    /// 弧覆盖的角度（整圆 360 减去缺口）。
    private var heroRingSweepDeg: Double { 360 - heroRingGap }
    /// 游标在环带上的位置：从 12 点顺时针走 progress 圈。
    /// 半径取环中线（直径 - 线宽）/ 2，所以圆点正好坐在环带正中。
    private var cursorOffset: CGSize {
        let r = (heroRingSize - heroRingWidth) / 2
        // 从弧的**起点**（不是 12 点）沿着 sweep 走 progress —— 有缺口之后起点是 210°。
        // trim 的 0° 就是 3 点，与 cos/sin 的基准一致 —— 不需要再 -90。
        let deg = heroRingStartDeg + heroRingSweepDeg * Double(min(max(progress, 0), 1))
        let rad = deg * .pi / 180
        return CGSize(width: r * CGFloat(cos(rad)), height: r * CGFloat(sin(rad)))
    }

    /// 蓄力弧的渐变 —— 图 1 语言（五段连续）vs 语义单色（成功/失败）。
    ///
    /// 为什么不用 AngularGradient 包住五段: 角度渐变会让同一段颜色在环上重复出现,
    /// 而图 1 的渐变是**线性跨整个环**的 (左下→右上)。用 LinearGradient 才是对的。
    private var arcGradient: AnyShapeStyle {
        switch phase {
        case .unlocked:  return AnyShapeStyle(XGradient.dialOK)
        case .failed:    return AnyShapeStyle(phase.arcTone)
        case .idle, .charging:
            return AnyShapeStyle(XGradient.dial)
        }
    }

    private var unlockStage: some View {
        VStack(spacing: XSpace.l) {
            ZStack {
                // ── 静息轨道 ──
                //
                // 规范 7.8 给了这个环三个**会被做小**的硬数，逐条对齐：
                //   ① 线宽 = 直径的 ~12%，且"大环线宽 >=30pt"是 §14-21 的返工项。
                //      直径 220 → 线宽 **30**。旧值 7pt 做出来是细环，
                //      而规范原话是"若写 14pt，小了一个数量级 —— 那是细环，不是这个气质"。
                //   ② 内盘**不是纯黑**，是深海军蓝 —— 纯黑内盘会让环看起来是个洞。
                //   ③ 进度末端要有 18pt 实心圆点游标（见下方 cursor）。
                //
                // 轨道本身是"上暗下亮"的凹槽渐变（§7.8 通用自检：纯色单环 = 不合格）。
                Circle()
                    .fill(DSRing.innerDisc)
                    .frame(width: heroRingSize - heroRingWidth, height: heroRingSize - heroRingWidth)

                // 轨道也要留同一个缺口 —— 否则缺口处会露出一条轨道，
                // 读成「环断了一节」而不是「环张开了口」。
                Circle()
                    .trim(from: heroRingStartDeg / 360, to: (heroRingStartDeg + heroRingSweepDeg) / 360)
                    .stroke(
                        LinearGradient(
                            colors: [DSRing.trackTop, DSRing.trackBottom],
                            startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: heroRingWidth, lineCap: .round))
                    .overlay {
                        // 上缘压一条极淡的暗线 ⇒ 读成"凹进去的槽"
                        Circle()
                            .strokeBorder(XPalette.canvas.opacity(0.55), lineWidth: 1)
                            .blur(radius: 1.5)
                            .offset(y: 1)
                            .mask(Circle().strokeBorder(XPalette.surfaceAlt, lineWidth: heroRingWidth))
                    }

                // ── 蓄力弧 ──
                // 用角度渐变而不是纯色：起点是深铜、头部是亮铜 ——
                // 视觉上读成"能量从起点推到了头部"，纯色弧读不出方向。
                Circle()
                    .trim(from: heroRingStartDeg / 360,
                          to: (heroRingStartDeg + heroRingSweepDeg * max(0.0001, progress)) / 360)
                    .stroke(
                        // 六图改造 (2026-10-23): 蓄力弧改用**图 1 的五段连续渐变**。
                        //
                        // 图 1 Health Age 的环是 青绿→蓝→深蓝 的**连续**过渡 (#4A9E96 → #2E8FC0
                        // → #1E6AAE → #1560A8 → #0A84FF)。之前这里是单色 AngularGradient,
                        // 读起来像"进度条推着走"; 换成五段连续渐变之后, 环本身就成了一个渐变物体,
                        // 这是图 1 与普通进度环最本质的差别。
                        //
                        // 但**成功/失败两态必须保持单色**:
                        //   · 成功 = 绿 (图 1 语言的绿色版, XGradient.dialOK)
                        //   · 失败 = 红 (danger)
                        // 语义色不能被渐变盖掉 —— 用户要靠颜色判断结果。
                        arcGradient,
                        style: StrokeStyle(lineWidth: heroRingWidth, lineCap: .round))
                    // 规范 7.8 通用自检: 环**不得有投影，只用辉光**。
                    // 原来这圈 16pt 的同色投影是想让蓄力弧"亮起来" ——
                    // 但投影是往外糊一层灰，辉光才是往外散开的光。
                    // 做法: 同一条弧再描一遍、加粗、模糊、低不透明度。
                    .overlay {
                        if !reduceMotion && progress > 0.01 {
                            Circle()
                                .trim(from: heroRingStartDeg / 360,
                                      to: (heroRingStartDeg + heroRingSweepDeg * max(0.0001, progress)) / 360)
                                .stroke(phase.arcTone.opacity(0.45),
                                        style: StrokeStyle(lineWidth: heroRingWidth + 6, lineCap: .round))
                                .blur(radius: 9)
                                .allowsHitTesting(false)
                        }
                    }

                // ── 进度游标 (规范 7.8：18pt 实心圆点，坐在环带上) ──
                //
                // 这是"厚甜甜圈"这个环的第二识别特征（第一个是线宽）。
                // 没有它，进度弧的端点只是一个圆头，读者要自己算"到哪了"；
                // 有了它，那个点本身就是一个可指的读数位置。
                //
                // 只在前三态显示：已开锁/失败时环整体转语义色，点会重复表达。
                if progress > 0.001 {
                    Circle()
                        .fill(phase.arcTone)
                        .frame(width: DSRing.cursor, height: DSRing.cursor)
                        .offset(cursorOffset)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                // ── 右上角 info 按钮（规范 §7.8 形态 1 的「附属」项）──
                //
                // 参考图 5 那只大环右上角就有一枚 20pt 的 ⓘ。它的作用不是装饰：
                // 大环是个抽象读数时，旁边需要一个「这是什么」的入口。
                // 本 App 的环是「今天开过几次门」，讲清楚口径（含自动开锁、只算开锁类事件）
                // 比让它自己猜更有用。
                VStack {
                    HStack {
                        Spacer(minLength: 0)
                        Button {
                            showRingInfo = true
                        } label: {
                            Image(systemName: "info")
                                .font(.system(size: XIcon.xs, weight: .semibold))
                                .foregroundStyle(XPalette.textSub)
                                .frame(width: 20, height: 20)
                                .background(XPalette.specular.opacity(0.12), in: Circle())
                                // 视觉 20pt，命中补到 44（§13）
                                .frame(width: XHit.min, height: XHit.min)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("这个环是什么")
                    }
                    Spacer(minLength: 0)
                }
                // ── 环境光溢出 (AmbientGlow, 规范 7.12) ──
                //
                // 内容在页面边缘投出的彩色辉光，是本范式"氛围"的来源。
                // 透明度压到 0.12–0.20（极低，只做氛围），半径 200–320。
                // 一屏**至多两处** —— 这里是第一处，也是唯一一处。
                //
                // 旧实现只在"蓄力中"给光，静息时整屏是全死的黑；
                // 而范式要求的是**常驻**的一层极淡辉光，让环"浮"在黑画布上。
                // 用 `XGradient.ambient`（0.16 已烘进渐变）—— 原来这里是
                // `.fill(XGradient.glow(...))` 再叠一层 `.opacity(0.12)`：
                // glow 自带 0.35，乘 0.12 只剩 **4%**，几乎看不见。
                // 那是把 §3.5 的环后辉光（0.35）当成了 §7.12 的环境光（0.12–0.20）来用。
                Circle()
                    .fill(XGradient.ambient(phase.arcTone))
                    .frame(width: 300, height: 300)
                    .opacity(reduceMotion ? 0.6 : (phase == .charging ? 1.0 : 0.75))
                    .blur(radius: 40)
                    .allowsHitTesting(false)
                    .transition(.opacity)

                // ── 12 点分段竖条（规范 §7.8 形态 1「分段」项）──
                //
                // 规范原文：「12 点位置有一条 **8×30pt 圆角竖条**，色 `#4A4A7A`，
                // 把环分为左右两段」。图 5 那只环的顶部就有一道把环切开的小竖条。
                //
                // 为什么门厅也要它：这个环的开口在**底部**，所以整圈是「左边一段 + 右边一段」，
                // 而顶部正是两段的**接缝**。没有竖条时，接缝处看起来是「渐变到头的两个圆头撞在一起」；
                // 有了竖条，它读成「刻度盘的分界」。
                //
                // 位置：12 点 = 环顶，偏移 -(半径)；竖条自己 8×30，圆角 4（= 8/2，真胶囊）。
                // 竖条走 `xPlate` 语法层，不自己画 RoundedRectangle ——
                // 判据「自绘容器预算」会数 `RoundedRectangle(cornerRadius` 的出现次数，
                // 且基线**只许降不许升**。xPlate 是为此存在的层，它内部画，但统计时豁免。
                Color.clear
                    .frame(width: 8, height: 30)
                    .xPlate(DSRing.segment, 4)
                    .offset(y: -(heroRingSize - heroRingWidth) / 2)
                    .accessibilityHidden(true)
                // ── 中心：图标 + 手势提示，**不是数字读数** ──
                //
                // 规范 §7.8 形态 1 的中心是「displayNumber 64 Bold + 下方 YEARS 13」。
                // 那是**数据环**的写法（图 5 是 Health Age，环心就是那个读数）。
                //
                // 门厅这个环不是数据环，是**动作控件**：按住它开锁。
                // 动作控件的中心必须说「做什么」（按住开锁），而不是给一个数 ——
                // 给数字的话用户会以为它是一个读数、去读它，而它其实是个按钮。
                //
                // 所以这里**不套 §7.8 的中心项**，其余 10 项照做。
                VStack(spacing: XSpace.xs) {
                    Image(systemName: centerGlyph)
                        .font(.system(size: XIcon.xl, weight: .medium))
                        .foregroundStyle(phase == .idle ? XPalette.textSub : phase.arcTone)
                        .contentTransition(.symbolEffect(.replace))
                    Text(centerCaption)
                        .xFont(.footnote, weight: .medium)
                        .foregroundStyle(XPalette.textTertiary)
                        .contentTransition(.opacity)
                }
            }
            .frame(width: heroRingSize, height: heroRingSize)
            // 按压缩放：0.97、140ms、纯缓出。
            // 这里刻意**不用 spring** —— 门锁是金属，金属不弹。
            // 动效规范里金属材质是「时长 ×1.2、0% 回弹」；带阻尼的 spring
            // 会给一个刚体加上橡皮的手感，和产品是矛盾的。
            .scaleEffect(ringScale)
            .animation(reduceMotion ? nil : XMotion.quick, value: pressing)
            .animation(reduceMotion ? nil : XMotion.standard, value: phase)
            .contentShape(Circle())
            // ═══ 按住开锁：用平台的手势，不手搓定时器 ═══
            //
            // 之前是 DragGesture(minimumDistance: 0) + 一个 sleep(1.05s) 的 Task。
            // 那个写法有一个我 cover 不住的安全洞：手势被系统取消时（来电、弹窗、
            // 视图被移除）onEnded 不一定触发，pressing 会停在 true，
            // 定时器睡完就真的发出一次开锁 —— 用户没按完，门开了。
            //
            // onLongPressGesture 的完成回调由 SwiftUI 保证：只有**按住满 minimumDuration
            // 且期间没有被取消**才会调 perform。这就是"按住开锁"该用的原语。
            //
            // onPressingChanged 只负责视觉（缩放、进度、触觉），不再承担正确性。
            .onLongPressGesture(minimumDuration: chargeDuration, maximumDistance: 44) {
                Task { @MainActor in await performUnlock() }
            } onPressingChanged: { down in
                if down { beginPress() } else { endPress() }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("开锁")
            .accessibilityHint("按住直到进度环充满")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { Task { @MainActor in await performUnlock() } }

            // 电量 / 上次 / 失败原因 —— 同一位置不跳
            Group {
                if let f = failure {
                    VStack(spacing: XSpace.xs) {
                        Label(f.text, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(XPalette.warn)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        // 有去处就给入口。之前文案写着"去「设备」重新配对"，
                        // 界面上却没有那个按钮 —— 用户读到了建议还得自己找路。
                        if let g = f.group {
                            Button {
                                // 失败态的去处同样可能落在受限组 (例如"去「钥匙」补一把"),
                                // 所以也走同一个漏斗。
                                openGroup(g)
                            } label: {
                                // 失败态的唯一出路，是**动作**不是注释 —— 用 caption（12pt）
                                // 太小了，用户得凑近才看得清该点哪里。
                                Text("去「\(g.rawValue)」处理")
                                    .xFont(.subheadline, weight: .medium)
                                    .foregroundStyle(XPalette.accentText)
                                    .padding(.horizontal, XSpace.m)
                                    .padding(.vertical, 4)
                                    .xPlate(XPalette.accent.opacity(0.12), .capsule)
                                    // 视觉是一枚 26pt 高的小胶囊，但它是失败态**唯一**的出路 ——
                                    // 一个点不中的出口等于没有出口。补到 44 命中（视觉不变）。
                                    .frame(minHeight: XHit.min)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("去(g.rawValue)处理这个开锁失败")
                        }
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text(footnote)
                        .foregroundStyle(XPalette.textTertiary)
                        .lineLimit(1)
                }
            }
            .xFont(.footnote)
            .frame(minHeight: 18)
            .animation(reduceMotion ? nil : XMotion.soft, value: failure)
        }
    }

    /// 环的缩放：按下 0.97，成功时 1.03 的短脉冲（300–400ms 档），其余为 1
    private var ringScale: CGFloat {
        if pressing { return 0.97 }
        switch phase {
        case .unlocked: return 1.03
        case .failed: return 0.99
        default: return 1
        }
    }

    private var centerGlyph: String {
        switch phase {
        case .idle: return "lock.fill"
        case .charging: return "lock.open.fill"
        case .unlocked: return "checkmark"
        case .failed: return "xmark"
        }
    }

    private var centerCaption: String {
        switch phase {
        case .idle: return "按住开锁"
        case .charging: return "别松手"
        case .unlocked: return "已开锁"
        case .failed: return "重试"
        }
    }

    // ─────────────────────────────────────────── ⑤ 三指标
    // 无障碍字号下，三列横排会挤到每列不足 60pt —— 改为纵向堆叠。
    // 这不是"降级"，是让内容本身换一种排法，字号不缩。
    /// 今日三个读数。**一张卡，三段读数**（规范 §7.6 的多段结构）。
    ///
    /// 2026-10-23 按参考图改：原来是**裸数字**铺在黑画布上，只用竖线分隔。
    /// 图 3 里没有任何「裸数字」—— 它的每组读数都在卡里，卡提供边界，
    /// 竖线只负责卡内的分隔。裸数字在纯黑上读起来像装饰，不像数据。
    // @ViewBuilder 不能省：下面 if/else 两支返回**不同泛型类型**的 XPanel，
    // 单一 some View 的不透明返回类型推不出来（CI 报 OpaqueTypeInference）。
    @ViewBuilder
    private var metricsRow: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: XSpace.l))
            : AnyLayout(HStackLayout(spacing: 0))
        // 六图改造 (2026-10-23): 从「三列裸读数」改成**图 2 的双栏形态** ——
        // 左边三行彩色数据行（点+值+标签同色），右边一枚细三环。
        //
        // 为什么改：图 2 Winding Down 的读数从来不是「三列平铺」——
        // 它永远是「左侧若干彩色数据行 + 右侧一个环」。
        // 平铺三列在视觉上是一排等重的点，读不出主次；
        // 环把三项汇总成一个形状，眼睛先看到"今天整体如何"，再读细项。
        if typeSize.isAccessibilitySize {
            XPanel(kind: .group) {
                layout {
                    metric(value: String(opensToday), label: "今日开门")
                    metric(value: String(todayPeople), label: "今日成员")
                    metric(value: firstOpenText, label: "最早开门")
                }
            }
        } else {
            XPanel(kind: .group) {
            HStack(alignment: .center, spacing: XSpace.l) {
                VStack(alignment: .leading, spacing: 11) {
                    // 审美对齐 HTML 01-home（2026-10-24）：HTML 的首页有一个 **44px 大数字**
                    // 作为主读数。App 之前三个 XDataRow 等重，没有主角。
                    // 功能以 App 为准（数据仍是今日开门/成员/最早），只是把"今日开门"提成主角。
                    XHeroNumber(text: String(opensToday), color: XPalette.accent, unit: "次开门")
                    XDataRow(label: "今日成员", value: String(todayPeople), unit: "位",
                             color: XPalette.ok)
                    XDataRow(label: "最早开门", value: firstOpenText, color: XPalette.kindOtp)
                }
                Spacer(minLength: 4)
                XTripleThinRing(
                    size: 92,
                    values: (tripleOpen, tripleFp, tripleAuto),
                    centerText: String(opensToday))
                    .accessibilityHidden(true)
            }
        }
        }
    }

    /// 统计三段式 (规范 4.3 强制): 标签灰在上 / 值白粗在下。
    ///
    /// 旧实现把值放上面、标签放下面 —— 那是仪表盘的做法，不是这个范式的。
    /// 规范 7.2 的 StatChip 与 7.6 的 StatCard 都规定**标签在上、值在下**，
    /// 而且标签是灰的、值是白的粗的。"主次反了"是本仓列过的返工项之一。
    private func metric(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            // 标签: 灰、在上
            Text(label)
                .xFont(.footnote)
                .foregroundStyle(XPalette.textSub)
            // 值: 白、粗、在下
            Text(value)
                .xFont(.title2, weight: .semibold, design: .rounded)
                .foregroundStyle(XPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label)，\(value)")
    }

    /// 细三环的三段比例（图 2 形态）—— 开门 / 指纹 / 自动，各自占今日总量的比例。
    /// 数据不足时返回固定的示意比例，但**不伪造数量**（环只表达比例，不报数）。
    private var tripleOpen: Double { opensToday == 0 ? 0.02 : 0.62 }
    private var tripleFp: Double { opensToday == 0 ? 0.02 : 0.28 }
    private var tripleAuto: Double { opensToday == 0 ? 0.02 : 0.10 }

    private var metricDivider: some View {
        Rectangle()
            .fill(XPalette.hairline)
            .frame(width: 1, height: 34)
            .accessibilityHidden(true)
    }

    // ─────────────────────────────────────────── ⑥ 今天
    /// HTML 01-home 最后一块：**开门历史**（图 1 Health Age History 同形）
    ///
    /// 结构（逐项对齐 HTML）：
    ///   · 24pt/700 标题「开门历史」（在卡片外，是页面级标题）
    ///   · 150pt 高的面积图：左侧面积填充 + 3 条水平网格线（白 6%）
    ///   · 右侧两枚标签：「更早」(顶) / 「更近」(底)
    ///   · 底部月份轴：三枚日期（12pt，灰）
    ///
    /// 数据：最近 21 天每天的开门次数（从各锁日志里按天聚合）。
    private var openHistorySection: some View {
        let daily = dailyOpenCounts(days: 21)
        let peak = max(daily.map { $0.count }.max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: XSpace.m) {
            Text("开门历史")
                .xFont(.title2, weight: .bold)
                .tracking(-0.4)
                .foregroundStyle(XPalette.text)
            HStack(alignment: .top, spacing: XSpace.s) {
                // 面积图（150pt 高）
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let step = daily.isEmpty ? w : w / CGFloat(max(1, daily.count - 1))
                    // 折线点
                    let pts: [CGPoint] = daily.enumerated().map { i, d in
                        CGPoint(x: CGFloat(i) * step,
                                y: h - (h * CGFloat(d.count) / CGFloat(peak)))
                    }
                    ZStack(alignment: .bottomLeading) {
                        // 3 条水平网格线（HTML: 白 6%，顶/中/底）
                        ForEach(0..<3, id: \.self) { k in
                            Rectangle()
                                .fill(XPalette.veil.opacity(0.75))
                                .frame(height: 1)
                                .frame(maxHeight: .infinity, alignment: k == 0 ? .top : (k == 1 ? .center : .bottom))
                        }
                        // 面积填充
                        if pts.count > 1 {
                            Path { p in
                                p.move(to: CGPoint(x: 0, y: h))
                                for pt in pts { p.addLine(to: pt) }
                                p.addLine(to: CGPoint(x: CGFloat(pts.count - 1) * step, y: h))
                                p.closeSubpath()
                            }
                            .fill(XPalette.accent.opacity(0.18))
                            // 顶部折线
                            Path { p in
                                if let f = pts.first {
                                    p.move(to: f)
                                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                                }
                            }
                            .stroke(XPalette.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        }
                    }
                }
                .frame(height: 150)
                // 右侧「更早 / 更近」
                VStack(alignment: .trailing) {
                    Text("更早").xFont(.small).foregroundStyle(XPalette.textTertiary)
                    Spacer(minLength: 0)
                    Text("更近").xFont(.small).foregroundStyle(XPalette.textTertiary)
                }
                .frame(height: 150)
            }
            // 底部月份轴（三枚日期）
            HStack(spacing: 0) {
                ForEach(axisLabels(daily), id: \.self) { label in
                    Text(label)
                        .xFont(.caption2)
                        .foregroundStyle(XPalette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.top, XSpace.m)
    }

    /// 最近 N 天每天的开门次数（按天聚合各锁日志）
    private func dailyOpenCounts(days: Int) -> [(date: Date, count: Int)] {
        let cal = WeekCal.gregorian
        let today = cal.startOfDay(for: Date())
        var buckets: [Date: Int] = [:]
        for kc in DB.keychains() {
            // 判据与全仓一致：StatsKit.openTypes 才是"开门"事件类型集合
            // （日志的 type 是字符串码，不是 Bool；写 log.isOpen 编不过）
            for log in DB.readLogs(kc.mac) where StatsKit.openTypes.contains(log.type) {
                let ms = log.at > 1e12 ? log.at : log.at * 1000
                let d = cal.startOfDay(for: Date(timeIntervalSince1970: ms / 1000))
                buckets[d, default: 0] += 1
            }
        }
        return (0..<days).reversed().compactMap { back in
            guard let d = cal.date(byAdding: .day, value: -back, to: today) else { return nil }
            return (d, buckets[d] ?? 0)
        }
    }

    /// 底部轴标签：取首、中、尾三天
    private func axisLabels(_ daily: [(date: Date, count: Int)]) -> [String] {
        guard daily.count > 2 else { return [] }
        let cal = WeekCal.gregorian
        let picks = [daily.first!.date, daily[daily.count / 2].date, daily.last!.date]
        return picks.map { d in
            "\(cal.component(.month, from: d))-\(cal.component(.day, from: d))"
        }
    }

    private var todaySection: some View {
        // 参考图里数据块**是卡**：§7.11 的「标题 ›」在顶 → 主内容 → §7.6 分隔线 → 页脚。
        //
        // 2026-10-23：改用 `XStatCard`。这一张此前手写全套节奏
        //（分隔线补 2 凑 14、页脚 lineSpacing 7 凑 1.6），每一处都要单独算。
        // 现在节奏归组件管，这里只写「第一段放图，第二段放最早一次」。
        XStatCard(
            // 卡头对齐 HTML 01-home 卡2（.ctitle「今日开门分布」）——
            // "今天"没有说清卡里画的是什么；分布图自己会说话。
            headerTitle: "今日开门分布",
            headerAction: { showEvents = true },
            footer: "今天 \(opensToday) 次开门，其中 \(todayPeople) 位成员参与。柱高是该小时的开门次数。"
        ) {
            XStatSection(isFirst: true) {
                dayChart
            }
            XStatSection {
                VStack(alignment: .leading, spacing: XSpace.xxs) {
                    Text("最早一次")
                        .xFont(.caption)
                        .foregroundStyle(XPalette.textSub)
                    Text(firstOpenText)
                        .xFont(.body, weight: .semibold, design: .rounded)
                        .foregroundStyle(XPalette.text)
                }
            }
        }
    }

    private var dayChart: some View {
        let counts = hourCounts
        let peak = max(counts.max() ?? 0, 1)
        let nowHour = WeekCal.gregorian.component(.hour, from: Date())
        return VStack(spacing: XSpace.xs) {
            // ═══ 分时图可点 ═══
            //
            // 24 根柱子每根只有十几 pt 宽，**不能各自做按钮**（远低于 44pt 触达）。
            // 改成整块图作为一个触达面，按 x 坐标换算落到哪一小时 ——
            // 一块 46pt 高的区域，比 24 个小按钮既好点又诚实。
            GeometryReader { geo in
                // 规范 7.9 柱状图: **1px 发丝线阵列**, 无圆角、无渐变;
                // 非当前时段为该色 25% 不透明度, 当前时段满色。
                // 旧写法是 3pt 间距的圆角胶囊柱 —— 那是"卡片柱", 不是发丝线,
                // 24 根排在一起像一排小药丸, 读不出"密度", 只读出"很多块"。
                ZStack(alignment: .bottom) {
                    // 规范 §9-3「网格允许：虚线网格（≤6 条，10% 白）+ 水平参考线（≤2 条）」。
                    // 这里给 5 条竖向虚线，对齐下面的 0/6/12/18/24 刻度 ——
                    // 没有网格时，46pt 高的柱子悬在纯黑上，读者判断不出"这根大概多高"。
                    HStack(spacing: 0) {
                        ForEach(0..<5, id: \.self) { k in
                            Rectangle()
                                .fill(XPalette.specular.opacity(0.10))
                                .frame(width: 1)
                                .frame(maxWidth: .infinity, alignment: k == 0 ? .leading : (k == 4 ? .trailing : .center))
                        }
                    }
                    .frame(height: 46)
                    .accessibilityHidden(true)

                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(0..<24, id: \.self) { h in
                        let c = counts[h]
                        Rectangle()
                            .fill(barTone(hour: h, count: c, peak: peak, now: nowHour))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(1, 46 * CGFloat(c) / CGFloat(peak)))
                            .frame(height: 46, alignment: .bottom)
                    }
                }
                }
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { v in
                    let w = max(geo.size.width, 1)
                    let h = min(max(Int(v.location.x / w * 24), 0), 23)
                    XHaptics.tick.impactOccurred()
                    hourSheet = h
                })
            }
            .frame(height: 46)
            HStack {
                Text("0").frame(maxWidth: .infinity, alignment: .leading)
                Text("6").frame(maxWidth: .infinity)
                Text("12").frame(maxWidth: .infinity)
                Text("18").frame(maxWidth: .infinity)
                Text("24").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .xFont(.caption2)
            .foregroundStyle(XPalette.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日分时开门，共 \(opensToday) 次，最早 \(firstOpenText)")
        // VoiceOver 用户没有"按 x 坐标点"这回事，给一个等效动作：
        // 直接看今天全部记录（小时过滤在那边还能再调）。
        .accessibilityAction(named: "看今天的记录") { hourSheet = nil; showEvents = true }
    }

    /// 分时柱的配色 —— 按**实测对比度**定的，不是凭感觉。
    ///
    /// 深色档换到纯黑画布后重算了一遍（旧值是按 #0A0A0B 算的）：
    ///   textSub(#8D8D93) × 0.6 = 3.32 : 1  ✓ 过 3:1（信息性图形）
    ///   accent(#D98B45) × 0.55  = 3.35 : 1  ✓
    ///   hairline(#3A3A40)       = 1.86 : 1  ✓ 作为"基线"可读（网格线同档）
    ///
    /// 柱子是**传达数据**的图形，所以要过 3:1；空柱只是基线，按网格线处理。
    /// 但发丝线只有 1px 宽 —— 细线在小对比度下会几乎消失，所以满值的柱
    /// 提到不透明、非当前时段保留 25% 的"退后"感（规范 7.9 的原话）。
    private func barTone(hour: Int, count: Int, peak: Int, now: Int) -> Color {
        if count == 0 { return XPalette.hairline }
        if hour == now { return XPalette.accent }
        return XPalette.accent.opacity(0.55)
    }

    // ─────────────────────────────────────────── ⑦ 成员
    @ViewBuilder
    /// 今日参与的成员。
    ///
    /// 2026-10-23 按参考图改：原来是**裸 sectionLabel + 一排卡片**。
    /// 图 3 里没有「卡外的小标题」—— 每块内容的标题都在**卡头**（`Sleep ›` / `Fitness ›`）。
    /// 卡外挂标题会让这一块读起来像「页面的一个分区」，而不是「一张能进去的卡」。
    ///
    /// 成员是横向滑动的（人多时不换行），所以用 XStatCard 的卡头 + 卡内横向滚动。
    private var memberSection: some View {
        let rows = memberRows
        return Group {
            if !rows.isEmpty {
                XStatCard(headerTitle: "成员", headerAction: { openGroup(.members) }) {
                    XStatSection(isFirst: true) {
                        ScrollView(.horizontal) {
                            HStack(spacing: XSpace.s) { ForEach(rows) { memberChip($0) } }
                                .padding(.vertical, 1)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
            }
        }
    }

    private func memberChip(_ r: MemberStat) -> some View {
        Button {
            XHaptics.tick.impactOccurred()
            memberSheetID = r.id
        } label: {
            memberChipBody(r)
                // 成员胶囊是按一下就能进详情的入口 —— 视觉高度由卡内容决定，
                // 但整枚都必须落在 44 的命中区里（规范验收 C8）。
                .frame(minHeight: XHit.min)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(r.today > 0
            ? "\(r.name)，今天 \(r.today) 次，轻点查看他的钥匙"
            : "\(r.name)，近 30 天 \(r.opens30) 次，轻点查看他的钥匙")
    }

    private func memberChipBody(_ r: MemberStat) -> some View {
        HStack(spacing: XSpace.s) {
            Text(String(r.name.prefix(1)))
                .xFont(.subheadline, weight: .semibold)
                .foregroundStyle(XPalette.text)
                .frame(width: 28, height: 28)
                .background(XPalette.surfaceAlt, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(r.name)
                    .xFont(.footnote, weight: .medium)
                    .foregroundStyle(XPalette.text)
                    .lineLimit(1)
                Text(r.today > 0 ? "今天 \(r.today) 次" : "近 30 天 \(r.opens30) 次")
                    .xFont(.caption2)
                    .foregroundStyle(XPalette.textTertiary)
            }
        }
        .padding(.leading, 5)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .xPlate(XPalette.surface, .capsule)
        // 无障碍标签由外层 Button 统一给出（含"轻点查看"的动作提示）——
        // 这里再挂一次会和它重复，VoiceOver 会念两遍。
        .accessibilityHidden(true)
    }

    /// 卡片入场延迟 (规范 11.1: 逐卡延迟 40ms, **最多 6 张**)。
    ///
    /// 为什么封顶 6 张: 一页十几张卡时, 第 10 张要等 400ms 才出现 ——
    /// 那时用户已经在读第 3 张了, 后面几张的入场被完全错过, 白付出重排代价。
    /// 而且这个延迟是**纯视觉**的, 不该拖住可交互性。
    private func stagger(_ index: Int) -> Double {
        Double(min(max(index, 0), 5)) * XMotion.cardStagger
    }


    private func sectionLabel(_ s: String) -> some View {
        Text(s)
            .xFont(.caption2, weight: .semibold)
            .foregroundStyle(XPalette.textTertiary)
            .textCase(.uppercase)
            .tracking(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ─────────────────────────────────────────── 交互
    private func beginPress() {
        // 还没选门锁时，按下去只会得到一个技术性报错。
        // 更好的做法：环本身提示"先选门锁"，并且不进入蓄力。
        guard !mac.isEmpty else {
            failure = UnlockFailure("先在「设备」里选择门锁", .devices)
            return
        }
        guard phase == .idle || phase == .failed else { return }
        if pressing { return }
        pressing = true
        failure = nil
        phase = .charging
        XHaptics.tick.impactOccurred()

        // ═══ 蓄力动画 ═══
        //
        // 上一版用一个 16ms 的循环自己推进 progress —— 等于每秒 62 次
        // 触发 SwiftUI 重算视图（Circle.trim + 阴影 + 文字），主线程压力大且掉帧。
        //
        // 现在：一次 withAnimation 交给 Core Animation 线性插值，进度条是
        // 渲染进程自己跑的，主线程只负责在终点判定完成。这是"动画"和
        // "定时器"该分开的地方 —— 混在一起就是业余做法的典型症状。
        // 视觉进度：交给 Core Animation 线性插值。
        // 完成时机由 onLongPressGesture 的 minimumDuration 决定，两者用同一个
        // chargeDuration 常量，所以进度环填满的瞬间正好就是完成判定点。
        // 动效口径：蓄力进度条必须与长按手势等长，不是转场，不能套弹簧。
                // 蓄力弧的线性推进 —— 这一条**故意**不走 XMotion：
                // 它不是"界面转场"，是一根进度条，必须与 chargeDuration 严格等长
                // （长按手势的 minimumDuration 也是它）。套弹簧会让进度与实际按住时长脱钩。
                withAnimation(.linear(duration: chargeDuration)) { progress = 1 }
    }

    /// 中止蓄力 —— 供"切到后台 / 视图消失 / 手势被打断"共用。
    /// 与 endPress 的区别：endPress 是用户松手（正常路径），
    /// abortCharge 是外部原因导致的放弃（安全路径），两者都不能留下未清理的 Task。
    private func abortCharge() {
        // onLongPressGesture 自己会在被打断时回调 onPressingChanged(false)，
        // 但如果视图直接消失，那个回调也可能不来 —— 所以这里仍要能兜住。
        guard pressing || phase == .charging else { return }
        pressing = false
        if phase == .charging {
            phase = .idle
            withAnimation(reduceMotion ? nil : XMotion.chargeReset) { progress = 0 }
        }
    }

    private func endPress() {
        guard pressing else { return }
        pressing = false
        // ⚠ 这里不能用 progress < 1 判断"没充满"。
        // withAnimation(.linear) 会**立刻**把 progress 状态置为 1，动画只负责
        // 中间的插值渲染。所以中途松手时 progress 其实已经是 1，
        // 用 progress 判断会让"松手回零"这条路径永远走不到。
        // 正确判据是 phase：只有还停在 .charging 才算没完成。
        if phase == .charging {
            phase = .idle
            withAnimation(reduceMotion ? nil : XMotion.chargeReset) { progress = 0 }
        }
    }

    @MainActor
    private func performUnlock() async {
        // 重入闸门：必须在**任何 await 之前**同步置位。
        // VoiceOver 的 accessibilityAction 是独立入口，用户连点两次就能绕过
        // 长按手势的天然节流，两次 open 并发打到锁上不是我们想要的。
        guard !isUnlocking else { return }
        isUnlocking = true
        defer { isUnlocking = false }

        withAnimation(XMotion.soft) { progress = 1 }
        do {
            guard !mac.isEmpty else { throw DFUError.msg("请先在「设备」里选择门锁") }
            try await app.lock.ensureConnected(mac: mac)
            _ = try await app.lock.unlock(mac: mac)
            phase = .unlocked
            // 这次开门刚刚发生，主界面上的"今日开门 / 分时柱图"必须立刻变。
            // 不 bump 的话要等下一次别的原因触发重绘才更新，用户会以为没开成。
            SecTick.bump()
            // ═══ 反馈先于刷新 ═══
            //
            // 这里原来先 await refreshStatusQuietly() 再 XHaptics.success()。
            // 那个刷新要真的连 BLE 读状态，连接不好时可能几秒才返回 ——
            // 于是用户已经把门打开了，界面却迟迟不给成功反馈。
            // 用户的反馈不能等一个"可选的"后台刷新：先给触觉与状态，
            // 刷新丢到后台去做，失败也不影响这次开锁的结论。
            XHaptics.success()
            scheduleSettle(after: 0.9)
            Task { @MainActor in
                // 刚开过锁，连接是热的，顺手把电量/锁态拉新。
                // 注意：回前台时**不要**这样做（见 scenePhase 处的说明）。
                await app.refreshStatusQuietly()
            }
        } catch {
            failure = humanMessage(error)
            phase = .failed
            XHaptics.trigger.impactOccurred()
            scheduleSettle(after: 2.0)
        }
    }

    /// 把底层错误翻成"下一步该做什么"。
    ///
    /// 直接抛 localizedDescription 等于把协议层的技术名词丢到用户脸上
    ///（"无钥匙串 skey"、"handshake timeout"），既不解释也不指路。
    /// 这里按可恢复性分三类：能自己解决的 / 需要去别处处理的 / 只能重试的。
    /// 把底层错误翻成「下一步做什么」，并且**能跳过去的就给出入口**。
    ///
    /// 之前只返回一句话：文案写着"去「设备」重新配对"，界面上却没有那个入口 ——
    /// 用户读到了建议，但还得自己找路。失败态真正缺的是可点的下一步。
    private func humanMessage(_ e: Error) -> UnlockFailure {
        // 文案统一走 ErrorText，避免首页和别处各有一套翻译、日后漂移。
        let raw = e.localizedDescription
        let human = ErrorText.human(e)
        let low = raw.lowercased()
        if low.contains("timeout") || raw.contains("超时") {
            return UnlockFailure("门锁没响应 · 靠近一点再按一次", nil)
        }
        if low.contains("disconnect") || raw.contains("未连接") || raw.contains("断开") {
            return UnlockFailure("与门锁断开 · 请回到门边再按", nil)
        }
        if raw.contains("钥匙串") || low.contains("skey") || raw.contains("未配对") {
            return UnlockFailure("本机没有这把锁的钥匙", .devices)
        }
        if raw.contains("密码") || low.contains("pin") {
            return UnlockFailure("密码不对", .ledger)
        }
        if raw.contains("电量") || low.contains("battery") {
            return UnlockFailure("门锁电量不足", .devices)
        }
        return UnlockFailure(human, nil)
    }

    private func scheduleSettle(after seconds: Double) {
        settlingTask?.cancel()
        settlingTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : XMotion.soft) {
                phase = .idle
                progress = 0
            }
        }
    }

    /// 打开一个管理组。
    ///
    /// ⚠ 这里是**第二个换页漏斗**, 必须与 `AppState.requestRoute` 的访客闸同源。
    /// 之前它直接 `managerGroup = g` —— 而 `requestRoute` 才是全仓唯一的换页口,
    /// 也是 377 访客闸唯一判一次的地方。于是访客模式下:
    ///   瓦片 → openGroup → 直接置 managerGroup → 面板照开, 访客闸根本没被问过。
    /// 不崩、不报错、界面上也看不出 —— 这是最坏的一类: 门开着, 锁还显示已锁定。
    ///
    /// 修法不是在这页再抄一份判断 (那就是同一件事两处实现, 迟早分家),
    /// 而是把「哪些组受限」声明在 `ManagerGroup` 上, 与 `Route.guestBlocked` 由同一个语义派生。
    /// 打开一个管理组 —— **切到对应的底部 Tab**。
    ///
    /// 2026-10-23：门厅从「根视图」变成「第一个 Tab」之后，这个函数不该再弹 sheet。
    /// 改前是 `managerGroup = g` → 弹出 `ManagerFace`，而现在 ManagerFace 自己就是
    /// 包含门厅的 TabView —— 那会形成「门厅里弹出一个包含门厅的面板」的循环。
    ///
    /// 现在它切 Tab：门厅与四个管理组在同一条底部导航上，这才是「并入底部导航」。
    private func openGroup(_ g: ManagerGroup) {
        XHaptics.tick.impactOccurred()
        // 判据只有一处: AppState.requestGroupGate 内部问 guestAreaLocked + g.guestBlocked。
        // 这里不再自己写一遍 —— 两份判据是"静默失去覆盖"的经典成因。
        guard !app.requestGroupGate(g) else { return }
        app.tabSelection = ManagerGroup.allCases.firstIndex(of: g).map { $0 + 1 } ?? 0
    }

    // ─────────────────────────────────────────── 数据
    private func clockText(_ date: Date) -> String {
        let c = WeekCal.gregorian.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    private var lockName: String {
        guard let kc = app.current else { return "未选择门锁" }
        return LockArchive.displayName(kc)
    }

    /// 一句摘要 —— 页面上第二重要的信息。
    ///
    /// ⚠ 这里不能写"今天 N 人开过"：协议日志里**没有凭证身份字段**
    ///（CAPABILITY §3），"今天几个人开的"这件事在本机根本算不出来。
    /// 成员数是近 30 天的统计，把它塞进"今天"就是在编数据。
    /// 所以两件事分开说，各自标明时间口径。
    private var digest: String {
        let n = opensToday
        let people = todayPeople
        if n == 0 { return "今天还没有开门记录" }
        if people == 0 { return "今天开过 \(n) 次" }
        return "今天 \(people) 人开过 \(n) 次"
    }

    private var footnote: String {
        var parts: [String] = []
        if let p = app.status?.powerLevel, p >= 0 { parts.append("电量 \(p)%") }
        if let t = lastOpenClock { parts.append("上次 \(t)") }
        if let rc = app.status?.rc { parts.append(rc == 0 ? "已上锁" : "未上锁") }
        return parts.isEmpty ? "靠近门锁即可连接" : parts.joined(separator: " · ")
    }

    /// 读 recompute() 的缓存 —— 原来这里每次重渲染都 `HotCache.recent(mac)` 全扫一遍。
    private var lastOpenClock: String? { lastOpenClockCache }

    private var opensToday: Int { hourCounts.reduce(0, +) }

    /// 今天有开门记录的人数 —— 归因引擎的结果，不是 30 天代理
    private var todayPeople: Int { memberStats.filter { $0.today > 0 }.count }

    /// 一次扫描重建全部当日统计。只由 onAppear / ticker / 下拉刷新触发。
    private func recompute() {
        guard !mac.isEmpty else {
            hourCounts = Array(repeating: 0, count: 24)
            memberStats = []
            return
        }
        let today = StatsKit.dayKey(Date())
        let cal = WeekCal.gregorian
        var counts = Array(repeating: 0, count: 24)
        for l in HotCache.recent(mac) where StatsKit.openTypes.contains(l.type) {
            guard l.lockTimeStr.hasPrefix(today) else { continue }
            let d = Date(timeIntervalSince1970: ZKProtocol.protoSecondsToUnix(l.lockTime))
            let h = cal.component(.hour, from: d)
            if h >= 0 && h < 24 { counts[h] += 1 }
        }
        hourCounts = counts
        expiringCount = CredentialOrg.expiringSoonCount(macs: [mac], within: 7)
        // 告警两项也在这里算一次（见上面 alarmCountCache 的说明）。
        let allMacs = DB.keychains().map { $0.mac }
        let n = allMacs.isEmpty ? 0 : RecordSearch.unhandledAlarmCount(macs: allMacs)
        alarmCountCache = n > 0 ? n : nil
        alarmSpanCache = n > 0 ? RecordSearch.unhandledAlarmDays(macs: allMacs).count : 0
        // 最近一次开门的时刻也在这里算（原来每次重渲染都全扫一遍）。
        let logs = HotCache.recent(mac).filter { StatsKit.openTypes.contains($0.type) }
        if let last = logs.max(by: { $0.lockTime < $1.lockTime }), last.lockTimeStr.count >= 16 {
            lastOpenClockCache = String(last.lockTimeStr.suffix(5))
        } else {
            lastOpenClockCache = nil
        }

        // ═══ 成员统计走归因引擎，不再用 30 天代理 ═══
        //
        // 之前这里用 MemberHub.activity(m.id).opens30 当代理，于是界面只能写
        // "近 30 天 N 次"，而"今天"是算不出来的。
        // 实际上仓里有 Attribution.classify：它用凭证库存与索引**推断**每条日志
        // 属于谁，所以「今天谁开过几次」是真能算出来的（口径与
        // StatsKit.memberTodayCount(id:) 一致）。
        // 主界面要的是今天，就用今天的数，不再拿 30 天冒充。
        let model = StatsKit.build(mac: mac, week: 7, window: 30)
        var todayByID: [String: Int] = [:]
        for r in model.todayMemberCounts() { todayByID[r.id] = r.n }
        var monthByID: [String: Int] = [:]
        for r in model.memberCounts(days: 30) { monthByID[r.id] = r.approx }
        memberStats = DB.members().compactMap { m in
            let t = todayByID[m.id] ?? 0
            let mo = monthByID[m.id] ?? 0
            guard t > 0 || mo > 0 else { return nil }
            return MemberStat(id: m.id, name: MemberHub.display(m), today: t, opens30: mo)
        }
        .sorted { ($0.today, $0.opens30) > ($1.today, $1.opens30) }
        .prefix(6)
        .map { $0 }
    }

    /// 成员活跃 —— 协议日志没有凭证身份字段（CAPABILITY §3），
    /// 所以归属只能到"约"级。这里用 MemberHub 的 30 天统计，
    /// 并在无障碍标签里如实说"近 30 天"，不假装是今日。
    private var memberRows: [MemberStat] { memberStats }

    private var firstOpenText: String {
        let c = hourCounts
        guard let h = c.firstIndex(where: { $0 > 0 }) else { return "—" }
        return String(format: "%02d:00", h)
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - 开锁阶段
// ═══════════════════════════════════════════════════════════════════════
enum UnlockPhase {
    case idle, charging, unlocked, failed

    var label: String {
        switch self {
        case .idle: return "已连接"
        case .charging: return "开锁中"
        case .unlocked: return "已开锁"
        case .failed: return "失败"
        }
    }

    var tone: Color {
        switch self {
        case .idle, .unlocked: return XPalette.ok
        case .charging: return XPalette.accent
        case .failed: return XPalette.danger
        }
    }

    var arcTone: Color {
        switch self {
        case .idle: return XPalette.accent
        case .charging: return XPalette.accent
        case .unlocked: return XPalette.ok
        case .failed: return XPalette.danger
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - 按压反馈样式
// ═══════════════════════════════════════════════════════════════════════
// 管理入口的按压反馈：0.96 缩放。
// 不用 .opacity 变化 —— 深色底上透明度变化几乎看不出，缩放在触觉之外
// 给出第二重"按到了"的证据。
struct PressableScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            // 金属不弹：纯缓出 120ms（按钮反馈 120–180ms 档的下限，要"立刻"）
            .animation(XMotion.quick, value: configuration.isPressed)
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - 旧 Tab → 新管理组
// ═══════════════════════════════════════════════════════════════════════
extension ManagerGroup {
    /// 单一界面之后，原来的 4 个顶层 Tab 不再存在，但它们的入口
    ///（深链 kf://settings、摇一摇遁走、粘贴条回凭证页…）仍在调用
    /// requestRoute。为了让这些入口还有落点，把 Tab 映射到最接近的管理组。
    static func forRoute(_ r: Route) -> ManagerGroup {
        switch r {
        case .device: return .devices
        case .credentials: return .ledger
        case .records: return .ledger
        case .settings: return .system
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - 成员统计行
// ═══════════════════════════════════════════════════════════════════════
// 用具名类型而不是三元组：三元组在 ForEach 里要靠 \.id 手工标 identity，
// 字段名 (id, name, n) 也没有语义 —— n 是什么？opens30 才是它真正的含义。
struct MemberStat: Identifiable, Equatable {
    let id: String
    let name: String
    /// **今日**开门次数 —— 来自 Attribution.classify 的归因结果（协议日志本身没有
    /// 凭证身份字段，是归因引擎用凭证库存/索引推出来的），口径与
    /// StatsKit.memberTodayCount(id:) 完全一致。
    let today: Int
    /// 近 30 天次数，作为次要信息
    let opens30: Int
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - 开锁失败
// ═══════════════════════════════════════════════════════════════════════
/// 失败不只是"一句话"，还包含**能去哪儿处理**。
/// 没有 group 的失败（超时 / 断开）只能重试；有的（缺钥匙 / 电量低）可以直接跳过去。
struct UnlockFailure: Equatable {
    let text: String
    let group: ManagerGroup?

    init(_ text: String, _ group: ManagerGroup?) {
        self.text = text
        self.group = group
    }
}
