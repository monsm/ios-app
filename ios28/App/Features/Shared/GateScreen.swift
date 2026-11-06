// GateScreen.swift —— 冷启动的本机密码闸。
//
// 设计：它不做成"锁屏"，而是做成门槛的第一步 —— 一扇窗、一行字、一组玻璃键。
// 安全：验证与冷却全部走 Engine/AppLock（墙钟 + 单调时钟双记），界面只负责输入。
import SwiftUI
import LocalAuthentication
import UIKit

@MainActor
struct GateScreen: View {
    @Environment(AppModel.self) private var app

    @State private var input = ""
    @State private var message: String?
    @State private var cooling = AppLock.shared.cooldownRemaining()

    private let keys: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["", "0", "⌫"],
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            VStack(spacing: 10) {
                Text("阈")
                    .type(T.F.wordmark)
                    .foregroundStyle(T.C.ink)
                Kicker(text: "THRESHOLD · 本机密码", dot: false, tint: T.C.ink3)
            }

            Spacer(minLength: 26)

            DisplayLine(text: message ?? "先确认是你。", size: 30)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            HStack(spacing: 14) {
                ForEach(0 ..< 6, id: \.self) { index in
                    Circle()
                        .fill(index < input.count ? T.C.brass : T.C.hairStrong)
                        .frame(width: 9, height: 9)
                        .scaleEffect(index < input.count ? 1 : 0.82)
                        .animation(T.M.snap, value: input.count)
                }
            }
            .padding(.top, 26)

            if cooling > 0 {
                Text("请等 \(cooling) 秒后再试")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.danger)
                    .padding(.top, 14)
            } else {
                Text(" ")
                    .type(T.F.caption)
                    .padding(.top, 14)
            }

            Spacer(minLength: 20)

            keypad

            if DB.hasPasscode() && !DB.hasDuressCode() {
                Button {
                    Task { await biometric() }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "faceid")
                        Text("用面容解锁")
                    }
                    .type(T.F.footnote)
                    .fontWeight(.medium)
                    .foregroundStyle(T.C.brass)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }

            Spacer(minLength: 24)
        }
        .padding(.horizontal, 30)
        .task {
            refreshCooldown()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                refreshCooldown()
            }
        }
    }

    private var keypad: some View {
        VStack(spacing: 12) {
            ForEach(keys.indices, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(keys[row], id: \.self) { key in
                        if key.isEmpty {
                            Color.clear.frame(width: 74, height: 60)
                        } else {
                            Button {
                                tap(key)
                            } label: {
                                Text(key)
                                    .type(T.F.keypad)
                                    .foregroundStyle(T.C.ink)
                                    .frame(width: 74, height: 60)
                                    .background {
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .fill(T.C.glass)
                                            .background {
                                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                                    .fill(.ultraThinMaterial)
                                            }
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .strokeBorder(T.C.glassEdge, lineWidth: 0.5)
                                    }
                            }
                            .buttonStyle(PressStyle())
                            .accessibilityLabel(key == "⌫" ? "删除" : key)
                        }
                    }
                }
            }
        }
    }

    private func tap(_ key: String) {
        guard cooling == 0 else { return }
        message = nil
        if key == "⌫" {
            if !input.isEmpty { input.removeLast() }
            return
        }
        guard input.count < 12 else { return }
        input.append(key)
        if input.count >= 6 { submit() }
    }

    private func submit() {
        let outcome = AppLock.shared.verify(input)
        switch outcome {
        case .success, .decoy:
            app.noteGate(outcome: outcome)
            input = ""
        case .wrong(let remaining):
            input = ""
            message = remaining > 0 ? "再试一次。" : "密码不对。"
            if remaining > 0 { cooling = remaining }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .cooling(let remaining):
            input = ""
            cooling = remaining
            message = "先等一会儿。"
        }
    }

    private func biometric() async {
        guard cooling == 0 else { return }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            message = "这台设备没有可用的面容或指纹。"
            return
        }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                                      localizedReason: "解锁你的家")
            if ok, AppLock.shared.unlockByBiometric() {
                app.noteGate(outcome: .success)
            }
        } catch {
            message = nil
        }
    }

    private func refreshCooldown() {
        let left = AppLock.shared.cooldownRemaining()
        if left != cooling { cooling = left }
    }
}
