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
        .tint(T.C.brass)
    }
}

extension View {
    @MainActor
    func withDestinations() -> some View {
        navigationDestination(for: Dest.self) { Destinations.view(for: $0) }
    }
}
