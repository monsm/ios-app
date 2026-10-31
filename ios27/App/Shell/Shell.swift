// Shell.swift —— App 外壳：5 个 Tab。
//
// 纪律：Tab 只导航不执行（开锁只在「门」页的刻度盘上）。
// Tab 数固定 5（不含 More）：HIG《Tab bars》要求避免溢出，375pt 宽机型上 6 项就溢出。
// iOS 26+ 的 `Tab` 声明式 API + `.tabBarMinimizeBehavior`，让内容顶到玻璃下面。
import SwiftUI

struct Shell: View {
    @Environment(Router.self) private var router
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.tab) {
            Tab(TabSlot.door.title, systemImage: TabSlot.door.symbol, value: TabSlot.door) {
                NavigationStack(path: router.path(for: .door)) {
                    DoorScreen().withDestinations()
                }
            }
            Tab(TabSlot.keys.title, systemImage: TabSlot.keys.symbol, value: TabSlot.keys) {
                NavigationStack(path: router.path(for: .keys)) {
                    KeysScreen().withDestinations()
                }
            }
            Tab(TabSlot.records.title, systemImage: TabSlot.records.symbol, value: TabSlot.records) {
                NavigationStack(path: router.path(for: .records)) {
                    RecordsScreen().withDestinations()
                }
            }
            Tab(TabSlot.household.title, systemImage: TabSlot.household.symbol, value: TabSlot.household) {
                NavigationStack(path: router.path(for: .household)) {
                    HouseholdScreen().withDestinations()
                }
            }
            Tab(TabSlot.settings.title, systemImage: TabSlot.settings.symbol, value: TabSlot.settings) {
                NavigationStack(path: router.path(for: .settings)) {
                    SettingsScreen().withDestinations()
                }
            }
            // 为什么没有独立的 Search Tab（iOS 26 的 Tab(role: .search)）：
            // 本 App 已经有 5 个 Tab（门/钥匙/台账/家/设置），再加一个就是 6 个。
            // HIG《Tab bars》明确说要避免溢出 More —— 375pt 宽的机型上 6 个项会溢出，
            // 而被塞进 More 的内容既难被看见也难被找到。
            // 检索按域放在各自页面里（台账搜事件、钥匙搜凭证），这才是它真正的作用范围。
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Signal.base)
        .sensoryFeedback(.selection, trigger: router.tab)
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
