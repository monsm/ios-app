// ThresholdApp.swift —— 入口。冷启动先过本机密码闸，然后进入三 Tab 的 Shell。
import SwiftUI

@main
struct ThresholdApp: App {
    @UIApplicationDelegateAdaptor(QuickActionDelegate.self) private var appDelegate
    @State private var app = AppModel()
    @State private var router = Router()
    @State private var settings = SettingsStore.shared
    @Environment(\.scenePhase) private var scenePhase

    private var scheme: ColorScheme? {
        _ = settings.revision
        return settings.preferredScheme
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(router)
                .preferredColorScheme(scheme)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                AppLock.shared.willEnterForeground()
                app.unlocked = AppLock.shared.unlocked
                app.decoy = AppLock.shared.decoy
                // 系统在进后台时会把「保持亮屏」复位，回前台补一次。
                ScreenAwake.reapply()
                AutoOpenController.shared.onForeground(mac: app.currentMac)
                if app.unlocked { Task { await app.reload(refreshStatus: false) } }
            case .background:
                AutoOpenController.shared.onBackground()
                AppLock.shared.didEnterBackground()
            default:
                break
            }
        }
    }
}

@MainActor
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    var body: some View {
        ZStack {
            DaylightField()
            if app.unlocked {
                ShellView()
                    .transition(.opacity)
            } else {
                GateScreen()
                    .transition(.opacity)
            }
        }
        .animation(T.M.settle, value: app.unlocked)
        // 只读试验模式必须常驻：用户第二天会忘了自己开过它，然后以为 App 坏了。
        .safeAreaInset(edge: .top, spacing: 0) {
            if app.trial { TrialBanner() }
        }
        // 全局提示条（AppToast）：任何页面的动作回执都走这一个浮层。
        .overlay(alignment: .bottom) { ToastHost() }
        .task {
            app.attach(router: router)
            EngineHostRegistry.register(app)
            if app.unlocked { await app.reload(refreshStatus: false) }
        }
        .onChange(of: app.unlocked) { _, isOn in
            if isOn {
                Task {
                    await app.reload(refreshStatus: false)
                    // 冷启动/超时上锁时，scenePhase 的 onForeground 发生在门禁之前，
                    // 轮询会立刻停掉；密码盘解锁又没有新的 scenePhase。不在这里恢复，
                    // 自动开门会一直“已开启”却整场会话都不工作。
                    AutoOpenController.shared.onForeground(mac: app.currentMac)
                }
            } else {
                // 上锁时把设置弹层收起；否则下次解锁会把上一会话的面板原样弹回来。
                router.settingsOpen = false
                router.settingsPath = []
            }
        }
    }
}

@MainActor
struct ShellView: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    /// I6：底栏形态。读的是 @Observable 单例的存储属性 —— 改了这里会重渲染。
    private var settings = SettingsStore.shared
    /// sheet 的呈现状态放在本地 `@State`，由 `onChange` 从 router 同步。
    ///
    /// 为什么不直接把 `$bindable.settingsOpen` 交给 `.sheet(isPresented:)`：
    /// `openSettings()` 会在同一拍里改 `settingsPath` 和 `settingsOpen`，
    /// 而绑定取值发生在 SwiftUI 的观察范围之外时，弹层可能“状态已经 true、
    /// 界面却没弹”。`onChange` 会显式读取这个属性、建立观察，再到本地状态，
    /// 路径与呈现分开两拍落地，底栏的设置按钮按下去一定有结果。
    @State private var settingsShown = false

    var body: some View {
        @Bindable var bindable = router
        Group {
            if settings.nativeTabBar {
                // I6：原生系统标签栏 —— 真 Liquid Glass 材质、滚动时自动收起
                //（.tabBarMinimizeBehavior 只对系统栏生效，自绘胶囊吃不到）、
                // VoiceOver 的「第 N 个标签」语义。设置在这里是真 Tab（第 4 个）。
                TabView(selection: $bindable.tab) {
                    Tab(TabSlot.today.title, systemImage: "sun.max", value: .today) {
                        NavigationStack(path: $bindable.todayPath) {
                            TodayScreen().withDestinations()
                        }
                    }
                    Tab(TabSlot.access.title, systemImage: "key", value: .access) {
                        NavigationStack(path: $bindable.accessPath) {
                            AccessScreen().withDestinations()
                        }
                    }
                    Tab(TabSlot.log.title, systemImage: "list.bullet", value: .log) {
                        NavigationStack(path: $bindable.logPath) {
                            LogScreen().withDestinations()
                        }
                    }
                    Tab(TabSlot.settings.title, systemImage: "gearshape", value: .settings) {
                        NavigationStack(path: $bindable.settingsPath) {
                            SettingsScreen().withDestinations()
                        }
                    }
                }
                .tabBarMinimizeBehavior(.onScrollDown)
                .tint(T.C.brass)
            } else {
                // 浮岛玻璃胶囊（默认）：内容滚到栏底下，第 4 个按钮拉起设置 sheet。
                ZStack(alignment: .bottom) {
                    Group {
                        switch router.tab {
                        case .today:
                            NavigationStack(path: $bindable.todayPath) {
                                TodayScreen().withDestinations()
                            }
                        case .access:
                            NavigationStack(path: $bindable.accessPath) {
                                AccessScreen().withDestinations()
                            }
                        case .log:
                            NavigationStack(path: $bindable.logPath) {
                                LogScreen().withDestinations()
                            }
                        case .settings:
                            // 形态切回来时正好停在设置 Tab：落回今日，别渲染空壳。
                            NavigationStack(path: $bindable.todayPath) {
                                TodayScreen().withDestinations()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    TabBar(
                        selection: Binding(
                            get: { router.tab.rawValue },
                            set: { router.tab = TabSlot(rawValue: $0) ?? .today }
                        ),
                        onSettings: { router.openSettings() }
                    )
                }
                .onChange(of: router.settingsOpen, initial: true) { _, open in
                    if settingsShown != open { settingsShown = open }
                }
                .sheet(isPresented: $settingsShown, onDismiss: { router.settingsOpen = false }) {
                    NavigationStack(path: $bindable.settingsPath) {
                        SettingsScreen().withDestinations()
                    }
                    .presentationDragIndicator(.hidden)
                }
            }
        }
        // 双形态共用：胶囊分支原先丢了这行（I6 重构时只在原生分支保留），默认形态下
        // Toggle/Stepper/confirmationDialog 等系统控件全部回退系统蓝 —— 现在提到外层。
        .tint(T.C.brass)
        // 形态切开关都要把「设置」落回合法位置：胶囊模式没有设置 Tab。
        .onChange(of: settings.nativeTabBar) { _, native in
            if !native && router.tab == .settings {
                router.tab = .today
                router.settingsPath = []
            }
            if native && router.settingsOpen {
                // 从胶囊切到原生时若设置 sheet 正开着，关掉 —— 内容已并入第 4 个 Tab。
                router.settingsOpen = false
                router.settingsPath = []
            }
        }
    }
}

extension View {
    @MainActor
    func withDestinations() -> some View {
        navigationDestination(for: Dest.self) { Destinations.view(for: $0) }
    }
}
