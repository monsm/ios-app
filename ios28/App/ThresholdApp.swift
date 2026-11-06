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
            if isOn { Task { await app.reload(refreshStatus: false) } }
        }
    }
}

@MainActor
struct ShellView: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

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

            TabBar(selection: Binding(
                get: { router.tab.rawValue },
                set: { router.tab = TabSlot(rawValue: $0) ?? .today }
            ))
        }
        .sheet(isPresented: $bindable.settingsOpen) {
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
