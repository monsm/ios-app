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
    static func present(_ app: AppState) -> Bool {
        !app.currentMac.isEmpty && app.status != nil
    }
}

// MARK: - 派发入口

/// 两套新界面共用的根。**共用**是关键：可达性由这一处构造保证，
/// 而不是 core 维护一张清单、gauge 再维护一张 —— 两张清单必然漂移，
/// 结果就是"切到某版打不开某页"。S4 的 tools/variantparity.js 判的就是这件事。
struct VariantRootView: View {
    @EnvironmentObject var app: AppState
    @State private var showAll = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VariantHomeView()

            // 兜底通路。变体各自的域导航做好后，这一枚的角色是"全部页面"而不是"救命出口"，
            // 但**不许删** —— 删了就没有一条两版共用的可达性保证。
            // 走的是同一个 requestRoute 漏斗，所以它和光点切换是同一套语义（换内容，不叠层）。
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
        .sheet(item: Binding(
            get: { app.variantDomain },
            set: { app.variantDomain = $0 })) { d in
            // 域浮层挂在**这一层**而不是某个变体的首屏里，原因有两个，都是硬伤：
            //   1. 挂 CoreHomeView 的话，gauge 变体点"全部页面"会设上 variantDomain 却没有任何
            //      东西呈现 —— 切过去就少一条通路，正是"两套必有一套缺一块"的成因。
            //   2. 内容跟着 variantDomain 换：切域是**换人**不是**叠层**，
            //      所以"换页动作被 sheet 盖住"这一族缺陷在两套里都不成立。
            // ⚠ 这里不再需要 device/nil 兜底分支：sheet(item:) 只在非 nil 时呈现，
            //   而 device 由 Route 的四个 case 之一覆盖 —— 少一个 case 编译器就会拦。
            Group {
                switch d {
                // .device 走不到这里：requestRoute(.device) 在非 legacy 下是"收起域浮层"（见 AppState）。
                // 分支还得留着才能让 switch 穷尽，但里面**不许**放 DeviceHomeView()。
                case .device:      EmptyView()
                case .credentials: CredentialsView()
                case .records:     RecordsView()
                case .settings:    SettingsView()
                }
            }
            .environmentObject(app)
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

    var body: some View {
        switch app.uiVariant {
        case .legacy:
            DeviceHomeView()
        case .core:
            CoreHomeView()
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
    private var here: Bool { LockReadout.present(app) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                presenceBar
                    .padding(.top, 8)
                powerWindow
                    .padding(.top, 26)
                secondaryRow
                    .padding(.top, 12)
                alarmRow
                    .padding(.top, 22)
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
                    .font(.system(.footnote, design: .default).weight(.semibold))
                    .tracking(1.6)
                    .foregroundStyle(here ? DS.Palette.gaugeAmber : DS.Palette.textSub)
                Text(here ? "读数于本次连接" : "走近门锁即可读取")
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(DS.Palette.textSub)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(app.currentMac.isEmpty ? Readout.dash : "玄关")
                    .font(.system(.title3, design: .default).weight(.semibold))
                    .foregroundStyle(DS.Palette.text)
                Text([LockReadout.model(status).text, "FW " + LockReadout.firmware(status).text]
                        .joined(separator: " · "))
                    .font(.system(.caption2, design: .default).weight(.semibold))
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
                        .font(.system(.caption, design: .default).weight(.semibold)).tracking(1.7)
                        .foregroundStyle(DS.Palette.textSub)
                    Spacer()
                    Text(r.field)
                        .font(.system(.caption2, design: .default).weight(.semibold)).tracking(1.3)
                        .foregroundStyle(DS.Palette.textSub)
                }
                HStack(alignment: .center, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(r.text)
                            .font(.system(.largeTitle, design: .monospaced).weight(.light))
                            .tracking(-3.2)
                            .monospacedDigit()
                            .foregroundStyle(here ? DS.Palette.gaugeAmber : DS.Palette.textSub)
                        Text("%")
                            .font(.system(.title3, design: .monospaced).weight(.regular))
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    Spacer(minLength: 4)
                    gaugeArc(frac: frac)
                        .frame(width: 92, height: 92)
                }
                .padding(.top, 8)
                Text(here ? "近场一次性读取 · 本机无在线状态" : "该锁是纯近场协议，没有远程通道")
                    .font(.system(.caption, design: .monospaced))
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
                    .font(.system(.caption2, design: .default).weight(.semibold)).tracking(1.5)
                    .foregroundStyle(DS.Palette.textSub)
                Text(r.text)
                    .font(.system(.title, design: .monospaced).weight(.regular))
                    .tracking(-0.6)
                    .monospacedDigit()
                    .foregroundStyle(alarm ? DS.Palette.danger : DS.Palette.text)
                Text(note)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(DS.Palette.textSub)
            }
        }
    }

    // ---------- 凭证余量：只有站在锁旁边才准 ----------
    private var capacityBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("凭证余量")
                    .font(.system(.caption, design: .default).weight(.semibold)).tracking(1.7)
                    .foregroundStyle(DS.Palette.textSub)
                Spacer()
                Text("实时读 21 / 24 / 27")
                    .font(.system(.caption2, design: .default).weight(.semibold)).tracking(1.1)
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
                .font(.system(.callout, design: .default).weight(.semibold))
                .foregroundStyle(DS.Palette.text)
                .frame(width: 52, alignment: .leading)
            SegmentedBar(used: Int(r.text) ?? 0, total: total,
                         tint: DS.Palette.gaugeAmber,
                         groove: DS.Palette.hairline.opacity(0.5))
                .frame(height: 9)
            Text(total > 0 ? "\(r.text) / \(total)" : r.text)
                .font(.system(.footnote, design: .monospaced))
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
                    .font(.system(.body, design: .default).weight(.semibold))
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
                .font(.system(.footnote, design: .default))
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

/// 零标签：一枚锁核 + 三个光点。光点是域入口，点它即进入该域。
/// ⚠ 本文件里只做**可点**的通路；拖拽召唤（1:1 跟手 + 橡皮筋 + 动量投影）在下一批做，
///   因为它需要 matchedGeometryEffect 与自定义弹簧，全仓 0 使用先例，单独一批好定位编译错误。
struct CoreHomeView: View {
    @EnvironmentObject var app: AppState

    /// 三个光点走的就是那一条唯一漏斗 `app.requestRoute`。
    /// 域的内容由 `app.variantDomain` 决定（见 AppState 那条注释）——
    /// 所以点另一个光点是**换人**，不是**叠层**，"换页动作被 sheet 盖住"这一族缺陷在这里不成立。
    private static let dots: [Route] = [.records, .credentials, .settings]

    var body: some View {
        ZStack {
            DS.Palette.coreCanvas.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                dotsRow
                coreButton
                    .padding(.top, 26)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 26)
        }
        .onAppear { PageTrace.shown("锁核首页") }
        // 域浮层**不在这里**：挂在 VariantRootView 上由两套共用。
        // 这里再挂一张就是"同一个量算两次" —— 两套容器各自决定怎么呈现 variantDomain，迟早不一致。
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("FRONT DOOR")
                    .font(.system(.caption2, design: .default).weight(.semibold)).tracking(1.6)
                    .foregroundStyle(DS.Palette.textSub)
                Text(app.currentMac.isEmpty ? Readout.dash : "玄关")
                    .font(.system(.title2, design: .default).weight(.semibold))
                    .tracking(-0.7)
                    .foregroundStyle(DS.Palette.coreInk)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(LockReadout.power(app.status).text + "%")
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(DS.Palette.coreInk)
                Text("CELL")
                    .font(.system(.caption2, design: .default).weight(.semibold)).tracking(1.4)
                    .foregroundStyle(DS.Palette.textSub)
            }
        }
        .padding(.top, 8)
    }

    /// 三个光点。中间那颗在上，另两颗分列下侧 —— 与原型轨道位同一拓扑。
    private var dotsRow: some View {
        VStack(spacing: 18) {
            ForEach(CoreHomeView.dots.prefix(1)) { r in dot(r) }
            HStack(spacing: 96) {
                ForEach(CoreHomeView.dots.dropFirst()) { r in dot(r) }
            }
        }
    }

    private func dot(_ r: Route) -> some View {
        Button { app.requestRoute(r) } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(DS.Palette.hairline.opacity(0.55))
                        .frame(width: 54, height: 54)
                    Circle()
                        .strokeBorder(DS.Palette.coreA.opacity(0.55), lineWidth: 0.8)
                        .frame(width: 54, height: 54)
                    Text(String(r.title.prefix(1)))
                        .font(.system(.headline, design: .default).weight(.regular))
                        .foregroundStyle(DS.Palette.coreInk)
                }
                Text(r.title)
                    .font(.system(.caption2, design: .default).weight(.semibold)).tracking(1.4)
                    .foregroundStyle(DS.Palette.textSub)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("进入\(r.title)")
    }

    private var coreButton: some View {
        Button(action: { app.requestUnlock() }) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [DS.Palette.coreB.opacity(0.85),
                                                  DS.Palette.coreA.opacity(0.9)],
                                         center: .center, startRadius: 6, endRadius: 78))
                    .frame(width: 152, height: 152)
                Circle()
                    .strokeBorder(DS.Palette.text.opacity(0.55), lineWidth: 2.5)
                    .frame(width: 152, height: 152)
                Image(systemName: app.unlockState == .success ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(DS.Palette.coreInk)
            }
        }
        .buttonStyle(.plain)
        .disabled(!LockReadout.present(app))
        .opacity(LockReadout.present(app) ? 1 : 0.5)
        .accessibilityLabel("开门")
        .accessibilityHint(LockReadout.present(app) ? "走现行三道闸通道" : "需先走近门锁")
    }
}
