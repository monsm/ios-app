// UnlockGateScreen.swift —— 30 秒内二次开锁的本机密码闸（原 DeviceHomeSupport.swift:122-219）。
//
// 这屏干什么：刚开过一次门，30 秒内再点圆盘要先输本机密码 —— 防止手机被人捡到后连续开门。
// 数据从哪来：DB.hasPasscode / DB.verifyPasscode（与冷启动闸同一套摘要）。
// 主动作：解锁并开门。失败三次进 30 秒冷却（与原版一致），冷却期内按钮禁用并显示剩余秒数。
import SwiftUI

struct UnlockGateScreen: View {
    /// 验证通过后要执行的动作（门页传 runUnlockChain）。
    /// E-15：作为 `Dest` 打开时（例如从门页的「再次确认」入口进来）以前是 nil ⇒
    /// 用户输对了密码、页面直接关掉，**门根本没开**，而且没有任何提示 ——
    /// 这正是"看着成功、其实没做"的一类。现在缺省值就是真开锁。
    var onPass: (() -> Void)? = nil

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var error: String?
    @State private var failures = 0
    @State private var cooldownUntil: Date?
    @State private var now = Date()
    @FocusState private var focused: Bool

    private var cooling: Int {
        guard let until = cooldownUntil else { return 0 }
        return max(0, Int(until.timeIntervalSince(now).rounded(.up)))
    }

    private var canSubmit: Bool {
        code.count >= 4 && cooling == 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: V.S.gap16) {
                header
                VCard {
                    VStack(alignment: .leading, spacing: V.S.gapMS) {
                        VSectionLabel(text: "本机密码", trailing: cooling > 0 ? "冷却 \(cooling) 秒" : "4 位以上")
                        SecureField("本机密码", text: $code)
                            .font(V.F.number20)
                            .keyboardType(.numberPad)
                            .textContentType(.password)
                            .textFieldStyle(.plain)
                            .focused($focused)
                            .frame(minHeight: V.H.action)
                            .padding(.horizontal, V.S.gapMS)
                            .background(V.C.cardAlt, in: .rect(cornerRadius: V.R.control))
                            .overlay {
                                RoundedRectangle(cornerRadius: V.R.control, style: .continuous)
                                    .strokeBorder(error == nil ? V.C.hairline : V.C.critical, lineWidth: V.S.hair)
                            }
                            .accessibilityLabel("本机密码")
                        if let error {
                            VStatusLine(tone: .critical, text: error)
                        }
                        VActionButton(title: cooling > 0 ? "冷却中…" : "解锁并开门", systemImage: "lock.open") {
                            verify()
                        }
                        .disabled(!canSubmit)
                        .opacity(canSubmit ? 1 : 0.45)
                        VOutlineButton(title: "取消", systemImage: "xmark") { dismiss() }
                    }
                }
                .padding(.horizontal, V.S.pageGutter)
                SettingsNote(text: "为什么再要一次密码：手机刚开过门，30 秒内被人拿走时，这一道闸让 TA 不能直接再开。输对一次后 30 秒内不再重复询问。")
                    .padding(.horizontal, V.S.pageGutter)
            }
            .padding(.vertical, V.S.gap16)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("再次确认")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
        .task(id: cooldownUntil) {
            guard cooldownUntil != nil else { return }
            while !Task.isCancelled {
                now = Date()
                if cooling == 0 { cooldownUntil = nil; error = nil; return }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: V.S.gapXS) {
            Text("30 秒内再次开锁")
                .font(V.F.displayHome)
                .foregroundStyle(V.C.text1)
            Text("刚开过一次门。再开一次要先确认是本人操作。")
                .font(V.F.footnote)
                .foregroundStyle(V.C.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, V.S.pageGutter)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func verify() {
        guard canSubmit else { return }
        // SEC-28：走 AppLock 的**持久**失败计数与冷却。旧实现的 `failures` 是 @State ——
        // 关掉 sheet 就清零，拿到已解锁手机的人可以无限次重试 4 位数字密码。
        switch AppLock.shared.verify(code) {
        case .success:
            error = nil
            // 记「刚通过闸门」：承诺「输对一次后 30 秒内不再重复询问」的落地处（见 `DoorScreen.needsGate`）。
            app.gatePassedAt = Int64(Date().timeIntervalSince1970 * 1000)
            // E-15：没有显式回调时执行真正的开锁链 —— 而不是静默关页。
            if let onPass { onPass() } else { Task { await app.runUnlockChain() } }
            dismiss()
        case .decoy:
            // 胁迫码不该在这里放行：这道闸的目的正是「手机被拿走后再开一次要确认是本人」。
            error = "这个输入不能用于本操作"
            code = ""
        case .wrong(let remaining):
            failures = AppLock.shared.failStreak
            code = ""
            if remaining > 0 {
                cooldownUntil = Date().addingTimeInterval(Double(remaining))
                now = Date()
                error = "密码不对 · 冷却 \(remaining) 秒"
            } else {
                // 2026-11-04（错误归因 · 数字与引擎梯度不符）：这里写死「3 次」，而
                // `AppLock.cooldownSeconds` 的梯度是 **3→30s、5→5min、7→30min** ——
                // 前 2 次失败（streak 1、2）不冷却，第 3 次才开始。所以剩余次数应当是
                // 「到下一档还差几次」，不是固定的 3。而且失败 3 次以上就会进 remaining>0 分支，
                // 这句永远只在 streak ≤ 2 时出现 —— 说「还可试 3 次」与事实不符（最多 2 次）。
                let untilCooldown = max(1, 3 - failures)
                error = "密码不对 · 再错 \(untilCooldown) 次开始冷却"
            }
        case .cooling(let remaining):
            cooldownUntil = Date().addingTimeInterval(Double(remaining))
            now = Date()
            code = ""
            error = "冷却中 · \(remaining) 秒后再试"
        }
    }
}

#Preview("UnlockGateScreen") {
    // 这个屏现在需要 AppModel（缺省动作要真开锁），预览也得注入环境，
    // 否则 Preview 直接崩在 "No Observable object of type AppModel found"。
    // 与 Shell.swift 的预览同一写法（直接构造，不引入 @Previewable 这个全仓唯一用法）。
    NavigationStack { UnlockGateScreen() }
        .environment(AppModel())
        .environment(Router())
}
