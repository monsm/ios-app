// LockKeeperApp.swift —— App 入口。
//
// 纪律：冷启动只做三件事 —— 装配环境、按需过本机密码闸、进 Shell。
// 不在这里做任何业务（上一版把整条启动链塞进 body，编译器报 type-check 超时）。
import SwiftUI

@main
struct LockKeeperApp: App {
    @State private var app = AppModel()
    @State private var router = Router()

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

    var body: some View {
        ZStack {
            if app.unlocked {
                Shell()
            } else {
                LockGateScreen()
            }
        }
        .animation(T.M.move, value: app.unlocked)
        // 装配：把路由注入 AppModel —— 这是 Engine 唯一能触达界面的出口（EngineHost）。
        .onAppear { app.router = router }
        // 只读试验模式必须常驻：用户第二天会忘了自己开过它，然后以为 App 坏了。
        .safeAreaInset(edge: .top, spacing: 0) {
            if app.trialGuard { TrialGuardBanner() }
        }
    }
}

/// 只读试验模式常驻条。
struct TrialGuardBanner: View {
    var body: some View {
        HStack(spacing: T.S.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: T.Icon.s, weight: .medium))
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
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            CanvasBackground()
            VStack(spacing: T.S.xl) {
                Spacer()
                Image(systemName: "lock.shield")
                    .font(.system(size: T.Icon.xl, weight: .light))
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
                    Text("密码不对")
                        .font(T.F.caption)
                        .foregroundStyle(State.critical)
                }

                PrimaryAction(title: "解锁", busy: false) {
                    // TODO(engine): 接 AppLock 的 PBKDF2 校验；伪装码进 decoy 空壳模式。
                    if code.isEmpty {
                        failed = true
                    } else {
                        app.unlocked = true
                    }
                }
                .padding(.horizontal, T.S.xxl)

                Spacer()
                Spacer()
            }
        }
        .onAppear { focused = true }
        .sensoryFeedback(.error, trigger: failed) { _, new in new }
    }
}
