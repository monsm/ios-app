// LockKeeperApp.swift —— App 入口。
//
// 纪律：冷启动只做三件事 —— 装配环境、按需过本机密码闸、进 Shell。
// 不在这里做任何业务（上一版把整条启动链塞进 body，编译器报 type-check 超时）。
import SwiftUI
import LocalAuthentication

@main
struct LockKeeperApp: App {
    @State private var app = AppModel()
    @State private var router = Router()
    @UIApplicationDelegateAdaptor(QuickActionDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(router)
                .tint(Signal.base)
        }
    }
}

/// 根容器：本机密码闸 + Shell + 只读试验模式常驻条。
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var settings = SettingsStore.shared

    var body: some View {
        ZStack {
            if app.unlocked {
                Shell()
            } else {
                LockGateScreen()
            }
        }
        // 外观与无障碍档位：主题跟随系统/浅色/深色 + 全局大字档（原 AXPrefs 的真实生效点）。
        .preferredColorScheme(colorScheme)
        .dynamicTypeSize(settings.axBigText ? .accessibility2 : .large)
        // 减弱动态：解锁闸门 → 主界面的切换改成直接出现，而不是淡入
        .animation(reduceMotion ? nil : T.M.move, value: app.unlocked)
        // 装配：把路由注入 AppModel —— 这是 Engine 唯一能触达界面的出口（EngineHost）。
        // 同时注册到 EngineHostRegistry，供通知回调这类没有视图上下文的路径取用。
        .onAppear {
            app.router = router
            EngineHostRegistry.register(app)
            app.unlocked = AppLock.shared.unlocked
            if let mac = app.currentKeychain?.mac { AutoOpenController.shared.onForeground(mac: mac) }
        }
        .task { await MainActor.run { AutoOpenController.shared.start() } }
        .onOpenURL { url in
            guard app.unlocked else { return }   // 深链不得绕过本机密码闸
            guard url.scheme == "kf", let host = url.host?.lowercased() else { return }
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            switch host {
            case "device":
                if let m = items.first(where: { $0.name == "mac" })?.value, !m.isEmpty {
                    let mac = DB.normalizeMac(m)
                    if DB.keychain(mac) != nil { DB.currentMac = mac }
                }
                router.select(.door)
            case "credentials":
                router.select(.keys)
            case "records":
                if let k = items.first(where: { $0.name == "k" })?.value, !k.isEmpty {
                    router.request(.record(id: k))
                } else {
                    router.select(.records)
                }
            case "settings":
                router.select(.settings)
            default:
                break
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                app.unlocked = AppLock.shared.unlocked
                if let mac = app.currentKeychain?.mac { AutoOpenController.shared.onForeground(mac: mac) }
            case .background:
                AutoOpenController.shared.onBackground()
            default:
                break
            }
        }
        // 只读试验模式必须常驻：用户第二天会忘了自己开过它，然后以为 App 坏了。
        .safeAreaInset(edge: .top, spacing: 0) {
            if app.trialGuard { TrialGuardBanner() }
        }
        // 全局提示条（原 ToastCenter）：任何页面的动作回执都可以走 AppToast.shared.show。
        .overlay(alignment: .top) { ToastHost() }
    }

    private var colorScheme: ColorScheme? {
        switch settings.theme {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }
}

/// 只读试验模式常驻条。
struct TrialGuardBanner: View {
    var body: some View {
        HStack(spacing: T.S.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                .font(T.F.icon(T.Icon.s, weight: .medium))
            Text("只读试验模式 · 所有写入都不会下发到门锁")
                .font(T.F.unit)
            Spacer(minLength: 0)
        }
        .foregroundStyle(State.critical)
        .padding(.horizontal, T.S.gutter)
        .padding(.vertical, T.S.xs)
        .background(State.critical.opacity(0.12))
        .accessibilityElement(children: .combine)
    }
}

/// 本机密码闸。冷启动才要求（不打断日常切前台）。
struct LockGateScreen: View {
    @Environment(AppModel.self) private var app
    @State private var code = ""
    @State private var failed = false
    @State private var gateMessage = "密码不对"
    @State private var bioAvailable = false
    @State private var bioBusy = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            CanvasBackground()
            VStack(spacing: T.S.xl) {
                Spacer()
                Image(systemName: "lock.shield")
                    .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                    .font(T.F.icon(T.Icon.xl, weight: .light))
                    .foregroundStyle(Ink.inkSub)
                Text("输入本机密码")
                    .font(T.F.display(24))
                    .foregroundStyle(Ink.ink)
                Text("本机数据保护开着。密码只存在这台手机上。")
                    .font(T.F.caption)
                    .foregroundStyle(Ink.inkSub)
                    .multilineTextAlignment(.center)

                SecureField("本机密码", text: $code)
                    .textFieldStyle(.plain)
                    .font(T.F.reading(20))
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .frame(height: T.H.action)
                    .background(Ink.plate, in: .rect(cornerRadius: T.R.control))
                    .overlay {
                        RoundedRectangle(cornerRadius: T.R.control, style: .continuous)
                            .strokeBorder(failed ? State.critical : Ink.hairline, lineWidth: T.Stroke.hair)
                    }
                    .padding(.horizontal, T.S.xxl)

                if failed {
                    Text(gateMessage)
                        .font(T.F.caption)
                        .foregroundStyle(State.critical)
                }

                PrimaryAction(title: "解锁", busy: false) {
                    switch AppLock.shared.verify(code) {
                    case .success:
                        app.decoyMode = false
                        app.unlocked = true
                        failed = false
                    case .decoy:
                        // 胁迫码：门照样能开，数据区显示为空 —— 不报警、不暴露。
                        app.decoyMode = true
                        app.unlocked = true
                        failed = false
                    case .wrong(let remaining):
                        failed = true
                        gateMessage = remaining > 0 ? "密码不对 · 冷却 (remaining) 秒后再试" : "密码不对"
                    case .cooling(let remaining):
                        failed = true
                        gateMessage = "冷却中 · (remaining) 秒后再试"
                    }
                }
                .padding(.horizontal, T.S.xxl)

                if bioAvailable {
                    Button {
                        Task { await unlockByBiometric() }
                    } label: {
                        HStack(spacing: T.S.s) {
                            Image(systemName: "faceid")
                                .accessibilityHidden(true)
                            Text(bioBusy ? "正在验证…" : "用面容 / 指纹解锁")
                                .font(T.F.bodyStrong)
                        }
                        .foregroundStyle(Ink.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: T.H.action)
                        .overlay {
                            RoundedRectangle(cornerRadius: T.R.control, style: .continuous)
                                .strokeBorder(Ink.hairline, lineWidth: T.Stroke.hair)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(bioBusy)
                    .padding(.horizontal, T.S.xxl)
                    .accessibilityLabel("用面容或指纹解锁")
                }

                Spacer()
                Spacer()
            }
        }
        .onAppear {
            focused = true
            bioAvailable = !DB.hasDuressCode() && DB.store.getBool("kf_bio_unlock", true) && canUseBiometrics()
        }
        .sensoryFeedback(.error, trigger: failed) { _, new in new }
    }

    /// 只在没有胁迫码时提供生物识别：有胁迫码时刷脸会直接暴露「这不是伪装模式」。
    private func canUseBiometrics() -> Bool {
        let ctx = LAContext()
        return ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    private func unlockByBiometric() async {
        guard !bioBusy else { return }
        bioBusy = true
        defer { bioBusy = false }
        let ctx = LAContext()
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                                 localizedReason: "解锁本机数据")
            if ok {
                AppLock.shared.unlockByBiometric()
                app.decoyMode = false
                app.unlocked = true
                failed = false
            }
        } catch {
            failed = true
            gateMessage = "生物识别未通过 · 可改用本机密码"
        }
    }
}
