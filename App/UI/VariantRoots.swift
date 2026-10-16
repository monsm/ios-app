import SwiftUI

// ============================================================
// 两套新界面的首屏 + 共用的"诚实读数"层 (2026-10-16)
// ------------------------------------------------------------
// 为什么读数层必须先于两套界面存在：
//   docs/CAPABILITY.md §5 明确写了这台锁 **没有上锁状态位、没有门磁、没有在线状态**
//   (纯 BLE 近场, 厂商云已停服)。所以任何"已上锁 / 已开启"式的大字都是**无源断言**。
//   两套界面共用下面这一个 `LockReadout`，就只可能有一处撒谎；
//   各算一遍则必然漂移 —— 这是本仓反复踩过的"同一个量算两次"。
//
// 开锁一律走 app.requestUnlock()，**不走 startUnlock()**：
//   requestUnlock 是 296 只读模式 / 244 指令去重 / 250 三十秒二次验证 / 836 演示包装
//   四道闸的唯一漏斗 (LockKeeperApp.swift:467)。绕过它 = 新界面开了一条没闸的侧门。
// ============================================================

// MARK: - 变体专属色板 (已搬进 DS.Palette)
//
// 2026-10-16: 这十档颜色原先定义在本文件，而 `tools/contrast.js` **只解析 DesignSystem.swift**，
// 于是两套新界面从一开始就建在「没被任何断言覆盖过」的颜色上。
// 现在它们住在 `App/Core/DesignSystem.swift` 的 `enum Palette` 里，与其余令牌同一把尺子一起量（法则见 contrast.js 的 F 节）。
// 调用点仍写 `DS.Palette.gaugeCanvas` —— 名字没变，只是换了家。

// MARK: - 共用的诚实读数层

/// 一次锁端读数。**读不到**和**读到 0**是两件事，必须能区分。
/// 本 App 最容易撒谎的一处就在这里：不在场时把"防撬告警"显示成"无"，
/// 等于给用户一份假平安；显示成破折号才是真话。
enum ReadoutState: Equatable {
    case live                 // 本次在场从 03 状态帧读到
    case snapshot(Date)       // 只有本地快照，带取样时刻
    case unread               // 从没读到过
}

struct Readout: Equatable {
    var text: String          // 已经格式化好的显示串；unread 时是 "—"
    var state: ReadoutState
    var field: String         // 出处，如 "cmd03 #11"；无源的东西不许进这个类型

    var isLive: Bool { state == .live }

    /// 破折号而不是 0 / "无"。
    static let dash = "—"

    static func value(_ text: String, field: String, state: ReadoutState) -> Readout {
        Readout(text: text, state: state, field: field)
    }

    static func unread(field: String) -> Readout {
        Readout(text: dash, state: .unread, field: field)
    }
}

/// 从 `AppState.status`（StatusParser 的唯一出口）派生两套界面要用的全部读数。
/// 只做"字段 → 带出处的读数"这一件事，不重新解析、不二次计算任何协议量。
enum LockReadout {

    /// `LockStatus` 的哨兵约定（StatusParser.swift:8-30）：
    /// rc / powerLevel / sKeyStatus 用 -1 表示"没读到"，三组 Capacity 用 0 表示"没读到"。
    static func power(_ s: LockStatus?) -> Readout {
        guard let s else { return .unread(field: "cmd03 #11") }
        guard s.powerLevel >= 0 else { return .unread(field: "cmd03 #11") }
        return .value("\(s.powerLevel)", field: "cmd03 #11", state: .live)
    }

    /// 电量 0–1 的比例，供刻度弧/条用。**unread 时返回 nil 而不是 0** ——
    /// 返回 0 会让空盘画成"电量耗尽"，那是把没读到画成了最坏的值。
    static func powerFraction(_ s: LockStatus?) -> Double? {
        guard let s, s.powerLevel >= 0 else { return nil }
        return min(1, max(0, Double(s.powerLevel) / 100))
    }

    static func capacity(used: Int, total: Int, field: String) -> Readout {
        guard total > 0 else { return .unread(field: field) }
        return .value("\(used)", field: field, state: .live)
    }

    static func pin(_ s: LockStatus?) -> Readout {
        guard let s else { return .unread(field: "cmd03 #22/#21") }
        return capacity(used: s.pinStock, total: s.pinInfoCapacity, field: "cmd03 #22/#21")
    }
    static func pwd(_ s: LockStatus?) -> Readout {
        guard let s else { return .unread(field: "cmd03 #25/#24") }
        return capacity(used: s.pwdStock, total: s.pwdInfoCapacity, field: "cmd03 #25/#24")
    }
    static func fp(_ s: LockStatus?) -> Readout {
        guard let s else { return .unread(field: "cmd03 #28/#27") }
        return capacity(used: s.fpStock, total: s.fpInfoCapacity, field: "cmd03 #28/#27")
    }

    /// 键盘冻结。**没读到一律 unread**，不要写"未冻结"。
    static func freeze(_ s: LockStatus?) -> Readout {
        guard let s else { return .unread(field: "cmd03 #06") }
        guard s.keyboardFreeze != 0 else { return .value("无", field: "cmd03 #06", state: .live) }
        return .value("已冻结", field: "cmd03 #06", state: .live)
    }

    static func errCount(_ s: LockStatus?) -> Readout {
        guard let s else { return .unread(field: "cmd03 #07") }
        return .value("\(s.keyboardErrCount)", field: "cmd03 #07", state: .live)
    }

    static func firmware(_ s: LockStatus?) -> Readout {
        guard let s, !s.firmware.isEmpty else { return .unread(field: "cmd03 #31") }
        return .value(s.firmware, field: "cmd03 #31", state: .live)
    }

    static func model(_ s: LockStatus?) -> Readout {
        guard let s, s.pid != 0, !s.pidName.isEmpty else { return .unread(field: "cmd03 #34") }
        return .value(s.pidName, field: "cmd03 #34", state: .live)
    }

    /// 在场判据：读的是 LinkSense 的现成结论，不在这里另算一次"连没连上"。
    /// ⚠ 两个入参是**故意的**：`AppState` 是 `@MainActor`（LockKeeperApp.swift:60），而这个
    /// `enum` 不是 —— 直接收 `app` 就是 "main actor-isolated property 'currentMac' can not be
    /// referenced from a nonisolated context"（CI run 116 抓到）。取数动作留在调用点（那里是
    /// View 的成员，本身带主 actor 推断，`app.status` 那样的读法全仓都是），这里只留一个
    /// **纯函数**：给两个入参、返回一个 Bool —— 这样它也能被工具拿去做影子对拍。
    static func present(currentMac: String, status: LockStatus?) -> Bool {
        !currentMac.isEmpty && status != nil
    }
}

// MARK: - 派发入口

/// 两套新界面共用的根。**共用**是关键：可达性由这一处构造保证，
/// 而不是 core 维护一张清单、gauge 再维护一张 —— 两张清单必然漂移，
/// 结果就是"切到某版打不开某页"。S4 的 tools/variantparity.js 判的就是这件事。
struct VariantRootView: View {
    @EnvironmentObject var app: AppState
    @State private var showAll = false
    /// `matchedGeometryEffect` 的宿主。**显式命名空间，不靠声明顺序** ——
    /// CORE.md §2.1 那个 z 序事故（浮层整块盖住锁核，"缩小骑在标题上"这个形态在六张截图里
    /// 根本没交付）在 iOS 侧的对应物就是它。
    @Namespace private var lockNS
    /// 跟手位移（已过橡皮筋）。**只有一个写入处**：`dragGesture`。
    @State private var drag: CGVector = .zero

    var body: some View {
        GeometryReader { geo in
            let L = SummonGeometry.layout(in: geo.size)
            ZStack(alignment: .topLeading) {
                Group {
                    VariantHomeView(layout: L)
                        .overlay(alignment: .bottomTrailing) { allPagesButton }
                }
                // 域浮层：**不再是系统 `.sheet`**，而是根层级里自绘的一层玻璃。
                // 为什么这一批必须换掉 sheet（本批唯一一处架构改动，理由写全）：
                //   `matchedGeometryEffect` **跨不过 sheet 边界** —— sheet 是另一个宿主层级，
                //   于是"同一枚锁核缩到 0.42 骑在浮层标题右侧"就只能画一枚长得一样的假核，
                //   而那正好违反 CORE.md 公理 2（一枚物体五种形态，不许出现"另一个组件接管"的接缝）。
                //   代价是实的：系统 sheet 白送的滚动/下拉关闭/模态语义要自己接 ——
                //   三条补偿写在 `DomainLayer` 的头注释上。
                // ⚠ 页面**必须写在这个尾随闭包里**（不能抽成辅助函数）：tools/destmap.js 把这条通道
                //   当成第 7 条呈现通道；搬进辅助函数 = 台账当场少三站，而它照样报"自检通过"。
                .domainLayer(domain: app.variantDomain,
                             onClose: { app.variantDomain = nil }) { d in
                    switch d {
                    // .device 走不到这里：requestRoute(.device) 在非 legacy 下是"收起域浮层"（见 AppState）。
                    // 分支还得留着才能让 switch 穷尽，但里面**不许**放 DeviceHomeView()。
                    case .device:      EmptyView()
                    case .credentials: CredentialsView()
                    case .records:     RecordsView()
                    case .settings:    SettingsView()
                    }
                }
                // 锁核层：**显式最上层**（z 序由层级决定，不由声明顺序）。骑乘态也在这里 ——
                // 于是"浮层盖住锁核"这个陷阱从结构上不成立。
                if app.uiVariant == .core { lockCoreLayer(L) }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .sheet(isPresented: $showAll) {
            NavigationStack {
                List {
                    // 四张现行根页。表由 Route.allCases 生成 —— 顺序只有一个声明处 (Route.byHost)。
                    ForEach(Route.allCases) { r in
                        Button(r.title) {
                            showAll = false
                            app.requestRoute(r)
                        }
                    }
                }
                .navigationTitle("全部页面")
            }
            .environmentObject(app)
        }
        // 启动链与纪念卡：这两件事原先只挂在 mainTabsChrome 上。
        // 新变体不挂它 ⇒ 自检/月备排程/成就结算/崩溃档案/LinkSense 回连**全都不跑且不报错**。
        // 换成调用同一个实现，见 RootView.bootstrapOnce 与 MomentLayer 的注释。
        .task { RootView.bootstrapOnce(app) }
        .modifier(MomentLayer())
    }

    /// 兜底通路。变体各自的域导航做好后，这一枚的角色是"全部页面"而不是"救命出口"，
    /// 但**不许删** —— 删了就没有一条两版共用的可达性保证。
    /// 走的是同一个 requestRoute 漏斗，所以它和光点切换是同一套语义（换内容，不叠层）。
    /// 挂在首屏那一层（而不是根的最上层）：浮层打开时它应当被玻璃盖住，而不是浮在上面可点。
    private var allPagesButton: some View {
        Button { showAll = true } label: {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(DS.Palette.text)
                .frame(width: 46, height: 46)
                .background(Circle().fill(DS.Palette.surfaceBase.opacity(0.86)))
                .overlay(Circle().strokeBorder(DS.Palette.hairline, lineWidth: 0.7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("全部页面")
        .padding(18)
    }

    // MARK: - 锁核层（拖拽召唤）

    /// 待机位与骑乘位是**同一枚**锁核的两个状态，`matchedGeometryEffect` 负责形变。
    /// 两态互斥（不会同时在场）—— 这是 matched geometry 的标准用法，也是它能跨层级失败的原因：
    /// 换 sheet 之前，两个状态分居两个宿主层级，插值无从谈起。
    @ViewBuilder
    private func lockCoreLayer(_ L: SummonGeometry.Layout) -> some View {
        ZStack(alignment: .topLeading) {
            if app.variantDomain == nil {
                lockCore(riding: false)
                    .position(x: L.home.x + drag.dx, y: L.home.y + drag.dy)
                    .matchedGeometryEffect(id: "lockCore", in: lockNS)
                    .gesture(dragGesture(L))
            } else {
                lockCore(riding: true)
                    .position(x: L.ride.x, y: L.ride.y)
                    .matchedGeometryEffect(id: "lockCore", in: lockNS)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(app.variantDomain == nil)
    }

    /// 锁核本体。`riding` 只改缩放 —— 位置由调用方 `.position` 给，
    /// 因为位置要在**两个状态之间**被 matched geometry 插值（写在里面就锁死了）。
    private func lockCore(riding: Bool) -> some View {
        let here = LockReadout.present(currentMac: app.currentMac, status: app.status)
        return ZStack {
            Circle()
                .fill(RadialGradient(colors: [DS.Palette.coreB.opacity(0.85),
                                              DS.Palette.coreA.opacity(0.9)],
                                     center: .center, startRadius: 6, endRadius: 78))
            Circle()
                .strokeBorder(DS.Palette.text.opacity(0.55), lineWidth: 2.5)
            Image(systemName: app.unlockState == .success ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(DS.Palette.coreInk)
        }
        .frame(width: 152, height: 152)
        .scaleEffect(riding ? SummonGeometry.rideScale : 1)
        .opacity(riding || here ? 1 : 0.5)
        .contentShape(Circle())
        .accessibilityElement()
        .accessibilityLabel("开门")
        .accessibilityHint(here ? "走现行三道闸通道；拖向周围三个光点可进入对应域"
                                 : "需先走近门锁；拖向光点仍可进入对应域")
        .accessibilityAddTraits(.isButton)
        // 无障碍激活与轻点都会走到这里；重复调用无害 —— 漏斗自带 1.2s 指令去重（244）。
        .accessibilityAction { app.requestUnlock() }
        .onTapGesture { if here { app.requestUnlock() } }
    }

    /// 拖拽：1:1 跟手 → 越界走橡皮筋 → 松手按**动量投影落点**判召唤。
    /// 三个量全部来自 `SummonGeometry`（纯函数，由 tools/summonshadow.js 用另一门语言对拍）。
    /// ⚠ 视图里**不许**自己写 `.spring(...)`：降档策略只有一个读点（`DS.Motion.summon` / `.fling`）。
    private func dragGesture(_ L: SummonGeometry.Layout) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { v in
                // 平铺档拖拽退场（CORE.md §1）：那一档三光点摊成三行，轨道位已经不存在了。
                guard !VK.flatTier else { return }
                drag = SummonGeometry.dragOffset(CGVector(dx: v.translation.width,
                                                          dy: v.translation.height),
                                                 limit: L.limit)
            }
            .onEnded { v in
                guard !VK.flatTier else { return }
                let velocity = CGVector(dx: v.velocity.width, dy: v.velocity.height)
                // 落点用**投影位移**判：拿抬手位置判，"朝光点甩一下"永远差一截。
                let projected = SummonGeometry.projectedOffset(drag, velocity: velocity, limit: L.limit)
                let landing = CGPoint(x: L.home.x + projected.dx, y: L.home.y + projected.dy)
                let target = SummonGeometry.summon(projected: landing, dots: L.dots, radius: L.hit)
                // 只有手势本身带动量才给 0.82 那一档（CORE.md §4）：
                // 慢慢拖到一半松手也弹过头，是"手感错了"最常见的一种。
                let momentum = SummonGeometry.hasMomentum(velocity, limit: L.limit)
                withAnimation(momentum ? DS.Motion.fling : DS.Motion.summon) {
                    drag = .zero
                    if let target { app.requestRoute(target) }
                }
            }
    }
}

/// 纪念时刻卡（里程碑/节日那类一次性浮现）。从 `mainTabsChrome` 里抽出来的唯一原因：
/// 三个界面变体都要有，而复制三份条件就会漂移。行为与原内联写法逐字一致。
struct MomentLayer: ViewModifier {
    @EnvironmentObject var app: AppState

    func body(content: Content) -> some View {
        content
            .overlay {
                if let m = app.moment {
                    MomentCardView(moment: m) { app.advanceMoment() }
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(DS.Motion.soft, value: app.moment)
    }
}

/// 首屏按变体分叉。读 `app.uiVariant`（AppState 的内存镜像）而不是 `UIVariant.current`（存储）——
/// 存储那份不观察变化，切了不会重算 body，就会"按了没反应、重进 App 才变"。
struct VariantHomeView: View {
    @EnvironmentObject var app: AppState
    /// 光点轨道位与拖拽半径**只有一个来源**（`SummonGeometry`）：画出来的光点
    /// 和判命中的光点必须是同一组坐标，否则会出现"看着撞上了却没反应"这种谁都查不出来的手感缺陷。
    let layout: SummonGeometry.Layout

    var body: some View {
        switch app.uiVariant {
        case .legacy:
            DeviceHomeView()
        case .core:
            CoreHomeView(layout: layout)
        case .gauge:
            GaugeHomeView()
        }
    }
}

// MARK: - 近场仪表首屏

/// 一块仪表盘。**熄屏是默认态**：99% 的时间用户不在锁旁边，那是正常状态不是错误页。
struct GaugeHomeView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    private var status: LockStatus? { app.status }
    private var here: Bool { LockReadout.present(currentMac: app.currentMac, status: app.status) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                presenceBar
                    .padding(.top, 8)
                powerWindow
                    .padding(.top, 26)
                secondaryRow
                    .padding(.top, 12)
                // 此处**没有告警行**：原稿引用了一个始终没写出来的 `alarmRow`，编译期把它抓住了。
                // 首屏不写"防撬告警"这类无源断言 —— 这台锁没有上锁状态位/门磁（CAPABILITY §5），
                // 不在场时那一行只能显示破折号；冻结/连错已由上一行的 `secondaryRow` 承担。
                capacityBlock
                    .padding(.top, 20)
                unlockButton
                    .padding(.top, 34)
                    .padding(.bottom, 30)
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DS.Palette.gaugeCanvas.ignoresSafeArea())
        .onAppear { PageTrace.shown("仪表首页") }
        .animation(DS.Motion.soft, value: here)
    }

    // ---------- 在场条：这个 App 真正的第一事实 ----------
    private var presenceBar: some View {
        HStack(alignment: .top, spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                Text(here ? "在场 · 已连接" : "不在场")
                    .vkFont(.system(.footnote, design: .default), weight: .semibold)
                    .tracking(1.6)
                    .foregroundStyle(here ? DS.Palette.gaugeAmber : DS.Palette.textSub)
                Text(here ? "读数于本次连接" : "走近门锁即可读取")
                    .vkFont(.system(.caption, design: .default))
                    .foregroundStyle(DS.Palette.textSub)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(app.currentMac.isEmpty ? Readout.dash : "玄关")
                    .vkFont(.system(.title3, design: .default), weight: .semibold)
                    .foregroundStyle(DS.Palette.text)
                Text([LockReadout.model(status).text, "FW " + LockReadout.firmware(status).text]
                        .joined(separator: " · "))
                    .vkFont(.system(.caption2, design: .default), weight: .semibold)
                    .tracking(1.3)
                    .foregroundStyle(DS.Palette.textSub)
            }
        }
    }

    // ---------- 主读数：电量刻度窗 ----------
    private var powerWindow: some View {
        let frac = LockReadout.powerFraction(status)
        let r = LockReadout.power(status)
        // P2: 面板底衬交给语法层。圆角 (14) / 描边透明度 / 凹槽色由 VK 一处定义 —— 首屏不再自己写
        // 16 / 0.7 / gaugeBezel 这些"语法层一改就得跟着改"的魔数。原来的 windowShape 整块删掉。
        // (本页只在 gauge 变体下渲染, 所以这里不出现 legacy 分支 —— 也不需要。)
        return VK(variant: .gauge).container(.hero) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("电量")
                        .vkFont(.system(.caption, design: .default), weight: .semibold).tracking(1.7)
                        .foregroundStyle(DS.Palette.textSub)
                    Spacer()
                    Text(r.field)
                        .vkFont(.system(.caption2, design: .default), weight: .semibold).tracking(1.3)
                        .foregroundStyle(DS.Palette.textSub)
                }
                HStack(alignment: .center, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(r.text)
                            .vkFont(.system(.largeTitle, design: .monospaced), weight: .light)
                            .tracking(-3.2)
                            .monospacedDigit()
                            .foregroundStyle(here ? DS.Palette.gaugeAmber : DS.Palette.textSub)
                        Text("%")
                            .vkFont(.system(.title3, design: .monospaced), weight: .regular)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    Spacer(minLength: 4)
                    gaugeArc(frac: frac)
                        .frame(width: 92, height: 92)
                }
                .padding(.top, 8)
                Text(here ? "近场一次性读取 · 本机无在线状态" : "该锁是纯近场协议，没有远程通道")
                    .vkFont(.system(.caption, design: .monospaced))
                    .foregroundStyle(DS.Palette.textSub)
                    .padding(.top, 10)
            }
        }
    }

    /// 270° 刻度弧。`frac == nil`（没读到）时**只画空轨，不画 0%** ——
    /// 空轨和零格是两种意思，画成 0% 就是把没读到说成电量耗尽。
    private func gaugeArc(frac: Double?) -> some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(DS.Palette.hairline, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(135))
            if let frac {
                Circle()
                    .trim(from: 0, to: 0.75 * frac)
                    .stroke(DS.Palette.gaugeAmber,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(135))
            }
        }
    }

    // ---------- 副读数两格 ----------
    private var secondaryRow: some View {
        HStack(spacing: 12) {
            cell("键盘冻结", LockReadout.freeze(status), "cmd03 #06",
                 alarm: LockReadout.freeze(status).text == "已冻结")
            cell("连错次数", LockReadout.errCount(status), "cmd03 #07",
                 alarm: Int(LockReadout.errCount(status).text) ?? 0 > 0)
        }
    }

    private func cell(_ title: String, _ r: Readout, _ note: String, alarm: Bool) -> some View {
        // P2: 内嵌小格交给语法层 (.inset) —— 底衬与倒角同样只由 VK 一处定义。
        VK(variant: .gauge).container(.inset) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .vkFont(.system(.caption2, design: .default), weight: .semibold).tracking(1.5)
                    .foregroundStyle(DS.Palette.textSub)
                Text(r.text)
                    .vkFont(.system(.title, design: .monospaced), weight: .regular)
                    .tracking(-0.6)
                    .monospacedDigit()
                    .foregroundStyle(alarm ? DS.Palette.danger : DS.Palette.text)
                Text(note)
                    .vkFont(.system(.caption2, design: .monospaced))
                    .foregroundStyle(DS.Palette.textSub)
            }
        }
    }

    // ---------- 凭证余量：只有站在锁旁边才准 ----------
    private var capacityBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("凭证余量")
                    .vkFont(.system(.caption, design: .default), weight: .semibold).tracking(1.7)
                    .foregroundStyle(DS.Palette.textSub)
                Spacer()
                Text("实时读 21 / 24 / 27")
                    .vkFont(.system(.caption2, design: .default), weight: .semibold).tracking(1.1)
                    .foregroundStyle(DS.Palette.textSub)
            }
            .padding(.bottom, 8)
            Divider().overlay(DS.Palette.hairline)
            capRow("PIN 池", LockReadout.pin(status), total: status?.pinInfoCapacity ?? 0)
            capRow("密码", LockReadout.pwd(status), total: status?.pwdInfoCapacity ?? 0)
            capRow("指纹", LockReadout.fp(status), total: status?.fpInfoCapacity ?? 0)
        }
    }

    private func capRow(_ name: String, _ r: Readout, total: Int) -> some View {
        HStack(spacing: 12) {
            Text(name)
                .vkFont(.system(.callout, design: .default), weight: .semibold)
                .foregroundStyle(DS.Palette.text)
                .frame(width: 52, alignment: .leading)
            SegmentedBar(used: Int(r.text) ?? 0, total: total,
                         tint: DS.Palette.gaugeAmber,
                         groove: DS.Palette.hairline.opacity(0.5))
                .frame(height: 9)
            Text(total > 0 ? "\(r.text) / \(total)" : r.text)
                .vkFont(.system(.footnote, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(DS.Palette.textSub)
                .frame(width: 62, alignment: .trailing)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Divider().overlay(DS.Palette.hairline.opacity(0.7)) }
    }

    // ---------- 主动作 ----------
    private var unlockButton: some View {
        VStack(spacing: 9) {
            Button(action: { app.requestUnlock() }) {
                Text(buttonLabel)
                    // 中文界面不用 .bold：PingFang SC 没有 700 这一档，.bold 会**静默**回退成
                    // Semibold，于是"我以为更重的那一级"其实从来没重过 (dynamictype 闸门规则 3)。
                    .vkFont(.system(.body, design: .default), weight: .semibold)
                    .tracking(1.2)
                    .foregroundStyle(DS.Palette.gaugeOnAmber)
                    .frame(maxWidth: .infinity).frame(height: 58)
                    .background(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(LinearGradient(colors: [DS.Palette.gaugeAmber,
                                                          DS.Palette.gaugeDeep],
                                                 startPoint: .top, endPoint: .bottom))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!here)
            .opacity(here ? 1 : 0.42)

            Text(buttonHint)
                .vkFont(.system(.footnote, design: .default))
                .multilineTextAlignment(.center)
                .foregroundStyle(DS.Palette.textSub)
        }
    }

    private var buttonLabel: String {
        if !here { return "贴近门锁" }
        if app.unlockState == .connecting || app.unlockState == .opening { return "开门中…" }
        return "开门"
    }
    private var buttonHint: String {
        if !here { return "未连接 · 该锁是纯近场协议，没有远程通道" }
        if app.unlockState == .success { return "已下发 · 锁端回执确认" }
        return "走现行 requestUnlock 通道：含只读模式、1.2s 去重、30s 二次验证三道闸"
    }
}

/// 一格一格的余量条。total<=0（没读到）时画空槽，不画"满"也不画"零"。
private struct SegmentedBar: View {
    let used: Int
    let total: Int
    let tint: Color
    let groove: Color

    var body: some View {
        GeometryReader { geo in
            let n = max(1, min(total, 64))
            let gap: CGFloat = total > 24 ? 1.5 : 3
            let w = max(1, (geo.size.width - gap * CGFloat(n - 1)) / CGFloat(n))
            HStack(spacing: gap) {
                ForEach(0..<n, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(i < used ? tint : groove)
                        .frame(width: w)
                }
            }
        }
    }
}

// MARK: - 一枚锁核首屏

/// 零标签：三个光点 + 一枚由上层画着的锁核。光点是域入口，点它即进入该域；
/// 拖向光点并松手是熟手的加速键（CORE.md §0："拖拽是给熟手的加速键，点击是给所有人的通路"）。
/// ⚠ 锁核本身**不在这里** —— 它由 `VariantRootView.lockCoreLayer` 画在根层级的最上层。
///   为什么必须搬家：待机位 ↔ 骑乘位是一次 `matchedGeometryEffect` 形变，它要求两个状态在
///   **同一层级**；锁核留在首屏里，浮层里的那枚就只能是另一个对象 —— 而那正是公交
///   CORE.md 公理 2 禁止的接缝。
/// ⚠ 光点位置由根层级算好传进来：首屏自己不量尺寸，量了就会和判命中的那份漂移。
struct CoreHomeView: View {
    @EnvironmentObject var app: AppState
    let layout: SummonGeometry.Layout

    var body: some View {
        ZStack(alignment: .topLeading) {
            DS.Palette.coreCanvas.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 0)
            }
            .padding(.horizontal, VK(variant: .core).gutter)

            // 平铺档（CORE.md §1）：三光点摊成三行带字条目，**拖拽退场**
            //（拖拽由上层按同一个开关关掉）。
            // 位置**不许写成内联坐标** —— 原型那次翻车就是坐标写在 markup 的 `style` 上，
            // 平铺档的重排规则一条都不生效（CORE.md §1 那条硬约束）。
            if VK.flatTier {
                flatDots
            } else {
                ForEach(SummonGeometry.dotRatios, id: \.route) { slot in
                    dot(slot.route)
                        .position(x: slot.point.x, y: slot.point.y)
                }
            }
        }
        .onAppear { PageTrace.shown("锁核首页") }
        // 域浮层**不在这里**：挂在 VariantRootView 上由两套共用。
        // 这里再挂一张就是"同一个量算两次" —— 两套容器各自决定怎么呈现 variantDomain，迟早不一致。
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("FRONT DOOR")
                    .vkFont(.system(.caption2, design: .default), weight: .semibold).tracking(1.6)
                    .foregroundStyle(DS.Palette.textSub)
                Text(app.currentMac.isEmpty ? Readout.dash : "玄关")
                    .vkFont(.system(.title2, design: .default), weight: .semibold)
                    .tracking(-0.7)
                    .foregroundStyle(DS.Palette.coreInk)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(LockReadout.power(app.status).text + "%")
                    .vkFont(.system(.body, design: .monospaced), weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(DS.Palette.coreInk)
                Text("CELL")
                    .vkFont(.system(.caption2, design: .default), weight: .semibold).tracking(1.4)
                    .foregroundStyle(DS.Palette.textSub)
            }
        }
        .padding(.top, 8)
    }

    /// 轨道档：三个光点按 `SummonGeometry` 的轨道位摆开（顶角在上，两颗下侧）。
    /// 它们走的就是那一条唯一漏斗 `app.requestRoute`；点另一个光点是**换人**不是**叠层**。
    private func dot(_ r: Route) -> some View {
        // 直径取 `layout.dotRadius` 而不是写死 54：光点与轨道半径都是由**同一份画布换算**出来的，
        // 写死就会在大屏上变成"轨道拉开了、光点没长大"，而命中的是一个看着很小的靶。
        let d = layout.dotRadius * 2
        return Button { app.requestRoute(r) } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(DS.Palette.hairline.opacity(0.55))
                        .frame(width: d, height: d)
                    Circle()
                        .strokeBorder(DS.Palette.coreA.opacity(0.55), lineWidth: 0.8)
                        .frame(width: d, height: d)
                    Text(String(r.title.prefix(1)))
                        .vkFont(.system(.headline, design: .default), weight: .regular)
                        .foregroundStyle(DS.Palette.coreInk)
                }
                Text(r.title)
                    .vkFont(.system(.caption2, design: .default), weight: .semibold).tracking(1.4)
                    .foregroundStyle(DS.Palette.textSub)
            }
        }
        .buttonStyle(.plain)
        // 命中区由 Button **自己**声明，不写在 label 里：光点是"圆里套一行字"，
        // 不声明 contentShape 的话，圆与字之间的缝隙是点不动的（看着是一整个目标，
        // 实际命中只有画出来那几个像素）。`tools/layout-audit` 的 R5 量的就是这件事，
        // 而它按 `frame(minHeight:)` 认 —— 所以这里必须是**字面令牌**：
        // 写成 `.frame(minHeight: d)` 这类变量，尺子解不出来就会退回"由行高反推"的估算（实测报 16.5pt）。
        // ⇒ 尺子能读的形状要写成它读得懂的样子，这是本仓"复算路径要能被机器走一遍"那条纪律的同一件事。
        .frame(minHeight: DS.Hit.min)
        .contentShape(Rectangle())
        .accessibilityLabel("进入\(r.title)")
        .accessibilityHint(r.domainNote)
    }

    // ---------- 平铺档：三行带字条目 ----------

    /// 顶角那颗在上、两颗在下 —— 与轨道档同一拓扑，只换了密度。
    /// **降档不许换容器语法**（CORE.md §6.3）：三行是发丝线分出来的条目，不是胶囊。
    private var flatDots: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ForEach(SummonGeometry.dotRatios, id: \.route) { slot in
                flatRow(slot.route)
                // 行与行之间一根**两端淡出**的发丝线 —— 零卡片定理里"承载层级"的三样之一。
                if slot.route != SummonGeometry.dotRatios.last?.route {
                    LinearGradient(colors: [DS.Palette.hairline.opacity(0),
                                            DS.Palette.hairline,
                                            DS.Palette.hairline.opacity(0)],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(height: 0.5)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, VK(variant: .core).gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func flatRow(_ r: Route) -> some View {
        Button { app.requestRoute(r) } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(DS.Palette.hairline.opacity(0.55))
                        .frame(width: 40, height: 40)
                    Circle()
                        .strokeBorder(DS.Palette.coreA.opacity(0.55), lineWidth: 0.8)
                        .frame(width: 40, height: 40)
                    Text(String(r.title.prefix(1)))
                        .vkFont(.system(.headline, design: .default), weight: .regular)
                        .foregroundStyle(DS.Palette.coreInk)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.title)
                        .vkFont(.system(.body, design: .default), weight: .medium)
                        .foregroundStyle(DS.Palette.coreInk)
                    Text(r.domainNote)
                        .vkFont(.system(.caption2, design: .default))
                        .foregroundStyle(DS.Palette.textSub)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("进入\(r.title)")
        .accessibilityHint(r.domainNote)
    }
}

// MARK: - 域浮层（两套新变体共用）

/// 域浮层的宿主。**自绘的一层玻璃，不再是系统 `.sheet`** —— 为什么必须换，见 `VariantRootView` 那段。
/// 代价是实的，系统 sheet 白送的三件东西这里都得自己接：
///   ① **模态语义** —— `.accessibilityAddTraits(.isModal)`。不补的话 VoiceOver 会继续读到底下首屏的
///      光点，而它们被玻璃盖着（本仓"看着在、其实摸不到"那道老毛病）；
///   ② **收起通路** —— 点空白 + 抓握条 + `.accessibilityAction(.escape)`（`CORE.md` §1 的退出方式）；
///   ③ **安全区** —— 遮罩自己 `ignoresSafeArea`，面板内容仍留在安全区里。
///
/// 浮层态的两条默认线（`CORE.md` §11 的 P-1 / P-2，本轮按默认线施工）：
///   · **P-1** 顶部保留**一行**小号状态读数（不新增元素，占的是本来空着的顶部空场）：
///     一个门锁 App 在"门锁"浮层里拨自动上锁，却不告诉你现在锁着还是开着 —— 这是第二轮评审实证报出来的；
///   · **P-2** 顶部一条**域切换带**：三域之间有横向通路。原先去程（点光点进来）成立、回程
///     （在这一页直接换域）没有画面 —— 实测两套的 act/key/lock 三帧逐像素相同，等于零横向通路。
///     平铺档同样给带字条目：降档只改密度，不改"有没有这个东西"（§6.3）。
struct DomainLayer<Page: View>: ViewModifier {
    let domain: Route?
    let onClose: () -> Void
    let page: (Route) -> Page

    @EnvironmentObject var app: AppState
    @Environment(\.uiVariant) private var variant

    init(domain: Route?, onClose: @escaping () -> Void, @ViewBuilder page: @escaping (Route) -> Page) {
        self.domain = domain
        self.onClose = onClose
        self.page = page
    }

    private var vk: VK { VK(variant: variant) }

    func body(content: Content) -> some View {
        content.overlay {
            if let d = domain { panel(d) }
        }
    }

    /// 面板高度：原型给的是 640pt 容量；小屏上留 72pt 露出首屏 —— 否则"浮层"就变成了"换页"。
    private func panelHeight(_ h: CGFloat) -> CGFloat { min(640, max(320, h - 72)) }

    @ViewBuilder
    private func panel(_ d: Route) -> some View {
        ZStack(alignment: .bottom) {
            // 遮罩：点空白收起。它也是"浮层与首屏谁是现在"的唯一视觉依据，不能省。
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { onClose() }
                .accessibilityHidden(true)

            GeometryReader { g in
                VStack(spacing: 0) {
                    grabber
                    band(current: d)
                    statusLine
                    Rectangle().fill(vk.hair).frame(height: 0.5)
                    page(d)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .frame(height: panelHeight(g.size.height))
                .background(panelBase)
                // 顶角圆、底角方（底边落在屏幕外）：clip 一个四角圆矩形会让浮层看着浮在屏幕中间。
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 22,
                                                 topTrailingRadius: 22,
                                                 style: .continuous))
                .overlay(alignment: .top) {
                    UnevenRoundedRectangle(topLeadingRadius: 22,
                                          topTrailingRadius: 22,
                                          style: .continuous)
                        .strokeBorder(vk.hair, lineWidth: 0.7)
                }
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isModal)
                .accessibilityAction(.escape) { onClose() }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            // 升起：从底边推上来。`calm` 档下这一层由 DS.Motion 统一压掉（不在视图里另写曲线）。
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(DS.Motion.soft, value: domain)
    }

    /// 抓握条：收起通路里最显眼的那一条（也是系统 sheet 白送给你的那一条）。
    private var grabber: some View {
        Capsule()
            .fill(vk.hair)
            .frame(width: 40, height: 4)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { onClose() }
            .accessibilityLabel("收起")
            .accessibilityAddTraits(.isButton)
    }

    /// **P-2** 域切换带：三域之间有横向通路。
    /// 再点一次当前域 = 收起（与 CORE.md §1 的退出方式一致："再点同一光点"）。
    /// 平铺档不做另一套：这一条本来就是**带字**的条目，降档只改密度（§6.3）。
    private func band(current: Route) -> some View {
        HStack(spacing: 0) {
            ForEach(Route.byHost.filter { $0 != .device }) { r in
                Button {
                    if r == current { onClose() } else { app.requestRoute(r) }
                } label: {
                    VStack(spacing: 3) {
                        Text(r.title)
                            .vkFont(.subheadline, weight: r == current ? .semibold : .regular)
                        Text(r.domainNote)
                            .vkFont(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(r == current ? vk.accent : vk.ink)
                .accessibilityLabel("\(r.title)，\(r.domainNote)")
                .accessibilityAddTraits(r == current ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 6)
    }

    /// **P-1** 状态读数。读数一律来自 `LockReadout`（那个"读不到就说读不到"的唯一出口）——
    /// 在这里另算一次 `app.status?.powerLevel` 就是本仓反复踩的"同一个量算两次"。
    private var statusLine: some View {
        let here = LockReadout.present(currentMac: app.currentMac, status: app.status)
        let power = LockReadout.power(app.status)
        let freeze = LockReadout.freeze(app.status)
        return HStack(spacing: 10) {
            Text(here ? "在场" : "不在场")
            Text("电量 " + power.text + (power.isLive ? "%" : ""))
            Text("键盘 " + freeze.text)
            Spacer(minLength: 0)
            Text(app.currentMac.isEmpty ? "未连接" : app.currentMac)
        }
        .vkFont(.caption2, weight: .medium)
        .foregroundStyle(here ? vk.sub : vk.faint)
        .padding(.horizontal, 16)
        .padding(.bottom, 7)
        .accessibilityElement(children: .combine)
    }

    /// 面板基底。三套各自不同 —— 这就是"两套界面切换后看着不一样"在浮层上的那一半。
    @ViewBuilder
    private var panelBase: some View {
        switch variant {
        case .core:
            // 锁核那套：玻璃（零卡片定理里承载层级的是玻璃本身与发丝线，不是盒子）
            Rectangle().fill(.ultraThinMaterial)
        case .gauge:
            // 仪表：凹槽基底。窗格在这里**不是装饰**，是面板的地（CORE.md §8.8 同一口径）。
            vk.bezel
        case .legacy:
            // 走不到：域浮层只在非 legacy 挂载（`VariantRootView` 只在非 legacy 分叉出来）。
            // 分支留着是为了让 switch 穷尽 —— 少一个 case 编译就不过，那是刻意的。
            vk.canvas
        }
    }
}

extension View {
    /// 挂上域浮层。**这是第 7 条呈现通道**（前六条：sheet / fullScreenCover / navigationDestination /
    /// popover / NavigationLink / Tab）。`tools/destmap.js` 必须认得它，否则台账会静默少三站 ——
    /// 那份工具自己记过这个失效模式："一条通道没被正控覆盖，就意味着走那条通道的目的地可能整批漏抽
    /// 而台账照样报自检通过"。
    /// ⚠ 目的地**必须写在尾随闭包里**：抽成辅助函数（`overlayPage(d)` 那种）台账就看不见了。
    func domainLayer<Page: View>(domain: Route?,
                                 onClose: @escaping () -> Void,
                                 @ViewBuilder page: @escaping (Route) -> Page) -> some View {
        modifier(DomainLayer(domain: domain, onClose: onClose, page: page))
    }
}
