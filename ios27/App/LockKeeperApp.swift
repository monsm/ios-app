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
    @State private var settings = SettingsStore.shared
    @UIApplicationDelegateAdaptor(QuickActionDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(router)
                .tint(settings.accentColor)
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
    /// SEC-24：深链要求切换的锁（等用户确认后才真的写 currentMac）。nil = 无待确认。
    @State private var pendingSwitchMac: String?

    /// 弹窗文案用的锁名（未命名时由 displayName 兜底成"门锁 · MAC 后 4 位"，不会是空串）。
    private var lockNameForSwitch: String {
        guard let mac = pendingSwitchMac else { return "—" }
        return LockArchive.displayName(DB.keychain(mac) ?? Keychain(mac: mac, skey: ""))
    }

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
        // 关键：不开 App 内「全局大字」时**不要**写死 .large —— 那会把系统设置里的
        // 更大字号整体压回 Large，等于无视 Dynamic Type。只有 App 档开启时才强制 accessibility2。
        .modifier(AXTextSizeModifier(enabled: settings.axBigText))
        // 减弱动态：解锁闸门 → 主界面的切换改成直接出现，而不是淡入
        .animation(reduceMotion ? nil : settings.motion.resultAnimation, value: app.unlocked)
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
                    if DB.keychain(mac) != nil { pendingSwitchMac = mac }   // SEC-24：见下方确认弹窗
                }
                router.select(.door)
            case "credentials":
                router.select(.keys)
            case "records":
                if let k = items.first(where: { $0.name == "k" })?.value, !k.isEmpty {
                    // SEC-24：行 id 的格式是 `<mac>#<序号>`，而本页所有查询都以「当前锁」为作用域 ——
                    // 一个指向**别的锁**的 id 只会解析成"这条记录没找到"，没有任何越权读，
                    // 但也没必要把脏输入往查询里塞。校验形状，不对就当没带参数。
                    if k.contains("#"), k.split(separator: "#", omittingEmptySubsequences: false).count == 2 {
                        router.request(.record(id: k))
                    } else {
                        router.select(.records)
                    }
                } else {
                    router.select(.records)
                }
            case "settings":
                router.select(.settings)
            default:
                break
            }
        }
        // SEC-24：切换当前锁**要确认**。旧实现点一下外部来源的链接（备忘录、聊天记录、
        // 别人递过来的二维码）就把 A 锁的界面切成 B 锁，用户可能拿着 B 的电量/台账
        // 去按 A 的门 —— 这正是本 App 最怕的"看着对、其实错"。
        .alert("切换到这把锁？", isPresented: Binding(
            get: { pendingSwitchMac != nil },
            set: { if !$0 { pendingSwitchMac = nil } }
        )) {
            Button("切换") {
                if let mac = pendingSwitchMac { DB.currentMac = mac }
                pendingSwitchMac = nil
                Task { await app.reload(refreshStatus: false) }
            }
            Button("保留当前锁", role: .cancel) { pendingSwitchMac = nil }
        } message: {
            Text("链接指定了一把锁：\(lockNameForSwitch)。确认后才切换，避免误看另一把锁的读数。")
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // SEC-21：退后台超过 30 秒就重新要求本机密码（lock() 内部会清内存母钥缓存）。
                AppLock.shared.willEnterForeground()
                app.unlocked = AppLock.shared.unlocked
                if app.unlocked, let mac = app.currentKeychain?.mac { AutoOpenController.shared.onForeground(mac: mac) }
            case .background:
                AppLock.shared.didEnterBackground()
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

    private var colorScheme: ColorScheme? { settings.theme.colorScheme }

}

/// App 内「全局大字」档：关闭时完全交还系统 Dynamic Type（不覆写大小），
/// 开启时把整棵视图树压到 Accessibility 2。
private struct AXTextSizeModifier: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        Group {
            if enabled {
                content.dynamicTypeSize(.accessibility2)
            } else {
                content
            }
        }
    }
}

/// 只读试验模式常驻条。
struct TrialGuardBanner: View {
    var body: some View {
        HStack(spacing: V.S.gapS) {
            Image(systemName: "exclamationmark.triangle.fill")
                .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                .font(V.F.icon15Medium)
            Text("只读试验模式 · 所有写入都不会下发到门锁")
                .font(V.F.unit)
            Spacer(minLength: 0)
        }
        .foregroundStyle(V.C.critical)
        .padding(.horizontal, V.S.pageGutter)
        .padding(.vertical, V.S.gapXS)
        .background(V.C.critical.opacity(0.12))
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
            VStack(spacing: V.S.gap24) {
                Spacer()
                Image(systemName: "lock.shield")
                    .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                    .font(V.F.icon22Light)
                    .foregroundStyle(V.C.text2)
                Text("输入本机密码")
                    .font(V.F.display24)
                    .foregroundStyle(V.C.text1)
                Text("本机数据保护开着。密码只存在这台手机上。")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text2)
                    .multilineTextAlignment(.center)

                SecureField("本机密码", text: $code)
                    .textFieldStyle(.plain)
                    .font(V.F.number20)
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .frame(minHeight: V.H.action)
                    .background(V.C.card, in: .rect(cornerRadius: V.R.control))
                    .overlay {
                        RoundedRectangle(cornerRadius: V.R.control, style: .continuous)
                            .strokeBorder(failed ? V.C.critical : V.C.hairline, lineWidth: V.S.hair)
                    }
                    .padding(.horizontal, V.S.gapXXL)

                if failed {
                    Text(gateMessage)
                        .font(V.F.footnote)
                        .foregroundStyle(V.C.critical)
                }

                VActionButton(title: "解锁", busy: false) {
                    switch AppLock.shared.verify(code) {
                    case .success:
                        app.decoyMode = false
                        app.unlocked = true
                        failed = false
                    case .decoy:
                        // 胁迫码：门照样能开，数据区显示为空 —— 不报警、不暴露。
                        app.decoyMode = true
                        // 2026-11-01（Round 313）：**立刻**把空壳落到数据层并清空内存投影。
                        // 原实现只置 `app.decoyMode`，真正生效要等 `Shell()` 重建后首个页面
                        // 的 `.task` 跑完 `reload()`（里面有 `DB.setDecoy(decoyMode)` 与清空三张表）。
                        // 这中间存在一个窗口：`app.keys / members / entries` 仍是**真实数据**，
                        // 而被胁迫者正盯着这一屏 —— 恰好是空壳模式最不该发生的暴露。
                        // 三步都幂等：`DB.setDecoy(true)` 再设一次无害；三张表在 reload 里还会被再清一次。
                        DB.setDecoy(true)
                        app.keys = []
                        app.members = []
                        app.entries = []
                        app.unlocked = true
                        failed = false
                    case .wrong(let remaining):
                        failed = true
                        gateMessage = remaining > 0 ? "密码不对 · 冷却 \(remaining) 秒后再试" : "密码不对"
                    case .cooling(let remaining):
                        failed = true
                        gateMessage = "冷却中 · \(remaining) 秒后再试"
                    }
                }
                .padding(.horizontal, V.S.gapXXL)

                if bioAvailable {
                    Button {
                        Task { await unlockByBiometric() }
                    } label: {
                        HStack(spacing: V.S.gapS) {
                            Image(systemName: "faceid")
                                .accessibilityHidden(true)
                            Text(bioBusy ? "正在验证…" : "用面容 / 指纹解锁")
                                .font(V.F.bodyStrong)
                        }
                        .foregroundStyle(V.C.text1)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V.H.action)
                        .overlay {
                            RoundedRectangle(cornerRadius: V.R.control, style: .continuous)
                                .strokeBorder(V.C.hairline, lineWidth: V.S.hair)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(bioBusy)
                    .padding(.horizontal, V.S.gapXXL)
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
                // 只有模型层真的解锁了才放行。有胁迫码时 `unlockByBiometric()` 会返回 false，
                // 这里必须跟着拒绝 —— 否则"模型拒绝、界面照开"就是假门（本仓历史上翻过车）。
                guard AppLock.shared.unlockByBiometric() else {
                    failed = true
                    gateMessage = "当前设置下不能用生物识别 · 请用本机密码"
                    return
                }
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
