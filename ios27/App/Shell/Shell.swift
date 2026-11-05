// Shell.swift —— App 外壳。
//
// **2026-11-01 重做：改用官方 `TabView` + `Tab`（iOS 18+ API）。**
//
// 为什么换（这是本轮 objective 的核心）：
//   之前是"自己画一条 HStack 胶囊，再在它背后铺一层 `.glassEffect`" ——
//   那只是**给自定义控件painted 了一层玻璃**，不是"用官方控件呈现液态玻璃"。
//   官方 `TabView` 的标签栏由系统渲染：它自带 Liquid Glass 材质、
//   选中态的形变、滚动时的收起、iPhone Duo 展开后的侧边位置、
//   以及 VoiceOver 的「第 N 个标签，共 M 个」语义 —— 这些都不是自己画得出来的。
//
// 代价（如实记录）：v7 参考图是「268pt 居中浮动胶囊」，官方标签栏是**全宽**的。
// 这是"用官方控件"必然带来的视觉变化 —— 但换来的是真正的系统材质与系统适配。
// 导航仍是 Router 的唯一漏斗：标签栏只改 router.tab；每个 Tab 的 NavigationStack 路径各自保留。
import SwiftUI

struct Shell: View {
    @Environment(Router.self) private var router
    @Environment(AppModel.self) private var app
    /// E-16：角标数缓存在 @State 里，不在 `body` 里算。
    /// 旧实现把 `CredentialOrg.expiringSoonCount(macs: DB.keychains()…)` 写在 `tabItems`，
    /// 而 `tabItems` 每次 body 重算都会求值 —— 等于**每次界面刷新都读一遍 UserDefaults
    /// 并遍历全部锁的台账**（切 Tab、开 sheet、任何 @Observable 变化都会触发）。
    @State private var keysBadge: Int = 0

    /// 标签栏形态开关。
    ///
    /// 2026-11-05（用户拍板：「保持原生液态玻璃控件优先」）：**默认改为官方 TabView**。
    /// 理由（都可核对）：
    ///   · 系统栏自带真 Liquid Glass 与选中态形变，并跟随「减少透明度 / 增强对比度」；
    ///   · 只有系统栏才吃下面的 .tabBarMinimizeBehavior(.onScrollDown)（自绘时那行是空转）；
    ///   · 只有系统栏才有 iPhone Duo 侧栏与滚动收起语义（自绘版本自己注明丢了这些）。
    /// 想回到参考图的浮岛形态：把 kf_native_tabbar 显式置 false（GlassTabBar 仍在，未删）。
    private var useNativeTabBar: Bool { TabBarMode.native }

    private var tabSelection: Binding<Int> {
        Binding(
            get: { router.tab.rawValue },
            set: { newValue in
                if let slot = TabSlot(rawValue: newValue) { router.tab = slot }
            }
        )
    }

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab(TabSlot.door.title, systemImage: TabSlot.door.symbol, value: TabSlot.door) {
                NavigationStack(path: router.path(for: .door)) {
                    // 2026-11-04（V8 重构 S4）：门页切到 V8 设计语言。
                    DoorHomeScreen().withDestinations()
                }
            }
            Tab(TabSlot.keys.title, systemImage: TabSlot.keys.symbol, value: TabSlot.keys) {
                NavigationStack(path: router.path(for: .keys)) {
                    // 2026-11-04（V8 重构 S4）：凭证根页切到 V8 设计语言。
                    // 旧 KeysScreen 先保留（可供回退与对照），确认无回归后删除。
                    KeysHomeScreen().withDestinations()
                }
            }
            // 原生角标：由系统标签栏渲染，位置/字号/颜色都由系统决定（不再自己画红点）。
            .badge(keysBadge)
            Tab(TabSlot.records.title, systemImage: TabSlot.records.symbol, value: TabSlot.records) {
                NavigationStack(path: router.path(for: .records)) {
                    // 2026-11-04（V8 重构 S4）：记录页切到 V8 设计语言。
                    RecordsHomeScreen().withDestinations()
                }
            }
            Tab(TabSlot.household.title, systemImage: TabSlot.household.symbol, value: TabSlot.household) {
                NavigationStack(path: router.path(for: .household)) {
                    // 2026-11-04（V8 重构 S4）：家页切到 V8 设计语言。
                    HouseHomeScreen().withDestinations()
                }
            }
            Tab(TabSlot.settings.title, systemImage: TabSlot.settings.symbol, value: TabSlot.settings) {
                NavigationStack(path: router.path(for: .settings)) {
                    // 2026-11-04（V8 重构 S4）：设置页切到 V8 索引语法。
                    SettingsHomeScreen().withDestinations()
                }
            }
        }
        // 2026-11-04（V8 重构 S3）：标签栏改成参考图的**浮动胶囊**。
        // 做法：保留官方 TabView（保住 5 条 NavigationStack 与状态），只把系统栏隐藏，
        // 再用 safeAreaInset 叠一条 GlassTabBar —— 这样既拿到浮岛形态，又不重写导航。
        // 回退：`kf_native_tabbar` = true 时用官方全宽栏（系统材质与 Duo 适配）。
        .toolbar(useNativeTabBar ? .visible : .hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            if !useNativeTabBar {
                GlassTabBar(
                    titles: TabSlot.allCases.map(\.title),
                    symbols: TabSlot.allCases.map(\.symbol),
                    selection: tabSelection
                )
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .background(V8.C.bg.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: router.tab)
        // E-16：只在真正可能变化时重算角标，不在每次 body 求值时读库。
        .task { refreshBadge() }
        .onChange(of: router.tab) { _, _ in refreshBadge() }
        .onChange(of: app.currentMac) { _, _ in refreshBadge() }
    }

    /// 凭证 Tab 的近 7 日到期角标：读 Engine 的 expiringSoonCount（跨全部锁）。
    /// 数值由 `refreshBadge()` 在出现/切 Tab/台账变更时写入 @State —— 见 E-16 说明。
    private func refreshBadge() {
        keysBadge = CredentialOrg.expiringSoonCount(macs: DB.keychains().map(\.mac))
    }
}

extension View {
    /// 每个 Tab 根挂同一套目的地解析。新增 Dest 时只改 Destinations.swift 一处。
    func withDestinations() -> some View {
        navigationDestination(for: Dest.self) { dest in
            Destinations.view(for: dest)
        }
    }
}

#Preview("Shell") {
    Shell()
        .environment(AppModel())
        .environment(Router())
}