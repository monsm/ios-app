// UnlockGateScreen.swift —— 30 秒内二次开锁的本机密码闸（V8 设计语言）
//
// 这屏干什么：刚开过一次门，30 秒内再点圆盘要先输本机密码 —— 防止手机被人捡到后连续开门。
// 数据从哪来：DB.hasPasscode / DB.verifyPasscode（与冷启动闸同一套摘要）。
// 主动作：解锁并开门。失败三次进 30 秒冷却（与原版一致），冷却期内按钮禁用并显示剩余秒数。
//
// 2026-11-04（Round 16b · S4 复核）：这一页**不是 Dest**，所以迁移清单里从来没有它 ——
// 但它是「30 秒二次开锁」的密码闸，是安全关键路径，而且从 V8 门页弹出来时是 V7 外观。
// 只换渲染层：AppLock.shared.verify 的梯度、gatePassedAt 的写入、E-15 的缺省真开锁全部原样。
import SwiftUI

struct UnlockGateScreen: View {
    /// 验证通过后要执行的动作（门页传 runUnlockChain）。
    /// E-15：作为 `Dest` 打开时以前是 nil ⇒ 用户输对了密码、页面直接关掉，**门根本没开**，
    /// 而且没有任何提示 —— 这正是"看着成功、其实没做"的一类。现在缺省值就是真开锁。
    var onPass: (() -> Void)? = nil

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var error: String?
    @State private var failures = 0
    @State private var cooldownUntil: Date?
    @State private var now = Date()

    private var cooling: Int {
        guard let until = cooldownUntil else { return 0 }
        return max(0, Int(until.timeIntervalSince(now).rounded(.up)))
    }

    private var canSubmit: Bool {
        code.count >= 4 && cooling == 0
    }

    private var judgement: String {
        if cooling > 0 { return "冷却中 · 还剩 \(cooling) 秒" }
        if let error { return error }
        return "30 秒内再次开锁"
    }

    var body: some View {
        VPage(title: judgement, lead: "刚开过一次门。再开一次要先确认是本人操作。") {
            EmptyView()
        } content: {
            codeCard
            Text("为什么再要一次密码：手机刚开过门，30 秒内被人拿走时，这一道闸让 TA 不能直接再开。输对一次后 30 秒内不再重复询问。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationTitle("再次确认")
        .task(id: cooldownUntil) {
            guard cooldownUntil != nil else { return }
            while !Task.isCancelled {
                now = Date()
                if cooling == 0 { cooldownUntil = nil; error = nil; return }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var codeCard: some View {
        VCard2 {
            VCardHead(
                eyebrow: "本机密码",
                statement: cooling > 0 ? "冷却中" : "4 位以上",
                trailing: cooling > 0 ? "还剩 \(cooling) 秒" : nil
            )
            VDivider2()
                .padding(.top, V8.S.gapM)
            // 共享输入框：聚焦时描边变实，出错时描边变红。
            VTextField(placeholder: "本机密码",
                        text: $code,
                        secure: true,
                        keyboard: .numberPad,
                        contentType: .password,
                        hasError: error != nil,
                        autofocus: true)
                .padding(.top, V8.S.gapM)
            if let error {
                Text(error)
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.danger)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
            V8ActionButton(title: cooling > 0 ? "冷却中…" : "解锁并开门", style: .primary) {
                verify()
            }
            .accessibilityLabel(cooling > 0 ? "冷却中" : "解锁并开门")
            .disabled(!canSubmit)
            .padding(.top, V8.S.gapM)
            V8ActionButton(title: "取消", style: .secondary) {
                dismiss()
            }
            .accessibilityLabel("取消")
            .padding(.top, V8.S.gapS)
        }
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
                // 「到下一档还差几次」，不是固定的 3。
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
    NavigationStack { UnlockGateScreen() }
        .environment(AppModel())
        .environment(Router())
}
