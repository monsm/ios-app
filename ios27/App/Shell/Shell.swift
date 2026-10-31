// Shell.swift —— App 外壳：v7 浮动玻璃标签栏（4 项：设备 / 凭证 / 记录 / 设置）。
//
// 参考 TOKENS.md「浮动标签栏（统一规格，4 项）」：268×57pt、居中、bottom 19.7pt、圆角 28.5pt；
// 材质 rgba(32,32,32,.72) + blur(20) saturate(180%) + inset 0 0 0 .5px rgba(120,150,160,.35)；
// 选中项 56×49 黑胶囊 + inset 亮边。
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

    var body: some View {
        @Bindable var router = router
        ZStack(alignment: .bottom) {
            tabContent(router)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: V.Tab.contentInset)
                }

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                VFloatingTabBar(selection: $router.tab, items: tabItems)
                    .padding(.bottom, V.Tab.bottom)
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .background(V.C.bg.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: router.tab)
        // E-16：只在真正可能变化时重算角标，不在每次 body 求值时读库。
        .task { refreshBadge() }
        .onChange(of: router.tab) { _, _ in refreshBadge() }
        .onChange(of: app.currentMac) { _, _ in refreshBadge() }
    }

    /// 凭证 Tab 的近 7 日到期角标：读 Engine 的 expiringSoonCount（跨全部锁）。
    /// 数值由 `refreshBadge()` 在出现/切 Tab/台账变更时写入 @State —— 见 E-16 说明。
    private var tabItems: [VTabItem] {
        var items = VTabItem.all
        if let i = items.firstIndex(where: { $0.slot == .keys }) { items[i].badge = keysBadge }
        return items
    }

    private func refreshBadge() {
        keysBadge = CredentialOrg.expiringSoonCount(macs: DB.keychains().map(\.mac))
    }

    @ViewBuilder
    private func tabContent(_ router: Router) -> some View {
        switch router.tab {
        case .door:
            NavigationStack(path: router.path(for: .door)) {
                DoorScreen().withDestinations()
            }
        case .keys:
            NavigationStack(path: router.path(for: .keys)) {
                KeysScreen().withDestinations()
            }
        case .records:
            NavigationStack(path: router.path(for: .records)) {
                RecordsScreen().withDestinations()
            }
        case .household:
            // 家庭页保留在 Router 里（门页「成员」入口与 .member(id:) 深链仍可达）；
            // v7 参考图只有 4 个标签，因此它不在浮动标签栏上常驻。
            NavigationStack(path: router.path(for: .household)) {
                HouseholdScreen().withDestinations()
            }
        case .settings:
            NavigationStack(path: router.path(for: .settings)) {
                SettingsScreen().withDestinations()
            }
        }
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
