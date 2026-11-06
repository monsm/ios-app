// PasscodeSheets.swift —— 本机密码 / 胁迫码的输入与验证（V8 设计语言）
//
// 从 SettingsParts.swift 拆出（2026-11-04 · S4 前置）：
//   ① SettingsParts.swift 是 V7 渲染层，而安全页已迁到 V8 —— 从 V8 页面弹出两张 V7 sheet，
//      同一个交互里两套设计语言。
//   ② 这两个 sheet 是本仓**唯一的密码校验链**（DB.verifyPasscode / DB.setPasscode /
//      DB.setDuressCode / AppLock.shared.verify）。复制一份就会漂 —— 所以只换渲染层，
//      校验逻辑逐字保留。
//
// 纪律：`commit()` 与 `verify()` 里的判据顺序、错误文案、AppLock 梯度全部**原样**，
// 它们每一条都对应一个曾经踩过的坑（见各自注释）。
import SwiftUI

// MARK: - 设置 / 更改本机密码或胁迫码

struct PasscodeSheet: View {
    var kind: PasscodeKind = .passcode

    @Environment(\.dismiss) private var dismiss
    private var store: SettingsStore { SettingsStore.shared }

    @State private var oldCode = ""
    @State private var first = ""
    @State private var second = ""
    @State private var error: String?

    private var isChange: Bool {
        switch kind {
        case .passcode: return store.hasPasscode
        case .duress: return store.hasDuressCode
        }
    }

    private var judgement: String {
        (isChange ? "更改" : "设置") + kind.title
    }

    private var lead: String {
        if let error { return error }
        return "4 位以上纯数字 · 两次输入必须一致"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(judgement)
                        .font(V8.T.title2)
                        .foregroundStyle(V8.C.ink1)
                        .tracking(V8.G.heroNumberTracking / 3)
                        .padding(.horizontal, V8.S.padCard)
                        .padding(.top, V8.S.gapSection)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(lead)
                        .font(V8.T.bodyL)
                        .foregroundStyle(error == nil ? V8.C.ink3 : V8.C.danger)
                        .lineSpacing(V8.L.bodyL - V8.T.bodyL.size)
                        .padding(.horizontal, V8.S.padCard)
                        .padding(.top, V8.S.gapTitleBody)
                        .fixedSize(horizontal: false, vertical: true)
                    VCard2 {
                        VStack(alignment: .leading, spacing: V8.S.gapM) {
                            if isChange {
                                secureField("原本机密码", text: $oldCode, contentType: .password)
                                Text("先验证当前本机密码 —— 只验本机摘要，不联网。")
                                    .font(V8.T.caption)
                                    .foregroundStyle(V8.C.ink4)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            secureField(kind.fieldPlaceholder, text: $first, contentType: .newPassword)
                            secureField("再次输入", text: $second, contentType: nil)
                            V8ActionButton(title: "确定", style: .primary) {
                                commit()
                            }
                            .accessibilityLabel("确定")
                            .padding(.top, V8.S.gapXS)
                            V8ActionButton(title: "取消", style: .secondary) {
                                dismiss()
                            }
                            .accessibilityLabel("取消")
                        }
                    }
                    .padding(.top, V8.S.gapBodyCard)
                    Text(kind.note)
                        .font(V8.T.footnote)
                        .foregroundStyle(V8.C.ink3)
                        .padding(.top, V8.S.gapM)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, V8.S.gutterCard)
                .padding(.bottom, V8.S.gapXXL)
            }
            .scrollIndicators(.hidden)
            .background(V8.C.bg.ignoresSafeArea())
            // 键盘避让：三个密码框在页面中部，数字键盘弹起会盖住「确定」。
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
        }
        // 半屏 sheet 会被数字键盘整个盖住 —— 必须 .large，并给一个可见的拖拽指示。
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func secureField(_ label: String, text: Binding<String>, contentType: UITextContentType?) -> some View {
        // 共享输入框：聚焦描边、错误描边、禁用态全部由组件给。
        VTextField(placeholder: label, text: text, secure: true, keyboard: .numberPad, contentType: contentType)
    }

    private func commit() {
        // 2026-11-04（校验顺序 · 用户体验）：旧实现**先验旧密码、再校新密码格式**。
        // 于是"旧密码对、但新密码只输了 3 位"的人会看到「原本机密码不对」——
        // 一句指向错方向的诊断，他会去重输旧密码，而问题在新密码。
        // 新密码的格式与两次一致是**本地可判**的，先判它；旧密码验证放最后。
        guard first.count >= 4 else { error = "需 4 位以上"; return }
        // 2026-11-04（会把自己锁死的输入）：`Character.isNumber` 对**全角数字**（１２３４）也返回 true。
        // 粘贴一串全角数字能通过校验、设成密码，而数字键盘**只能打出半角** —— 之后再也输不进去。
        guard first.allSatisfy({ $0.isASCII && $0.isNumber }) else { error = "只能输入半角数字（0-9）"; return }
        guard first == second else { error = "两次输入不一致"; return }
        if isChange {
            guard DB.verifyPasscode(oldCode) else { error = "原本机密码不对"; return }
        }
        switch kind {
        case .passcode:
            // 真摘要：PBKDF2-HMAC-SHA256 落 kf_passcode（DB 内部实现，旧摘要验过即静默升级）。
            // 与胁迫码相同的新密码会被拒（否则胁迫码永远不触发，见 Store.setPasscode）。
            guard DB.setPasscode(first) else {
                error = "新密码不能与已设的胁迫码相同 —— 否则胁迫码将永远不触发；请换一个"
                return
            }
        case .duress:
            // 胁迫码独立键 kf_duress。`setDuressCode` 返回 Bool，其中一条失败条件是
            // **胁迫码与本机密码相同**。原来用 `_ =` 丢掉结果、直接 `dismiss()` ——
            // 用户以为设好了，实际根本没设，要到"真需要用胁迫码"那一刻才会发现。
            guard DB.setDuressCode(first) else {
                error = "胁迫码不能与本机密码相同；请换一个 4 位以上数字"
                return
            }
        }
        dismiss()
    }
}

// MARK: - 只验证旧密码（关闭本机密码 / 关闭胁迫码前必须过这一道）

/// 它不写任何状态 —— 验证通过才执行调用方给的 action（关闭动作本身）。
struct VerifyPasscodeSheet: View {
    let title: String
    let note: String
    let onVerified: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(V8.T.title2)
                        .foregroundStyle(V8.C.ink1)
                        .tracking(V8.G.heroNumberTracking / 3)
                        .padding(.horizontal, V8.S.padCard)
                        .padding(.top, V8.S.gapSection)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(error ?? note)
                        .font(V8.T.bodyL)
                        .foregroundStyle(error == nil ? V8.C.ink3 : V8.C.danger)
                        .lineSpacing(V8.L.bodyL - V8.T.bodyL.size)
                        .padding(.horizontal, V8.S.padCard)
                        .padding(.top, V8.S.gapTitleBody)
                        .fixedSize(horizontal: false, vertical: true)
                    VCard2 {
                        VStack(alignment: .leading, spacing: V8.S.gapM) {
                            VTextField(placeholder: "当前本机密码",
                                        text: $code,
                                        secure: true,
                                        keyboard: .numberPad,
                                        contentType: .password,
                                        hasError: error != nil)
                            V8ActionButton(title: "验证并继续", style: .primary) {
                                verify()
                            }
                            .accessibilityLabel("验证并继续")
                            .disabled(code.count < 4)
                            V8ActionButton(title: "取消", style: .secondary) {
                                dismiss()
                            }
                            .accessibilityLabel("取消")
                        }
                    }
                    .padding(.top, V8.S.gapBodyCard)
                    Text("验证的是这台手机上的摘要；不改锁端任何设置。")
                        .font(V8.T.footnote)
                        .foregroundStyle(V8.C.ink3)
                        .padding(.top, V8.S.gapM)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, V8.S.gutterCard)
                .padding(.bottom, V8.S.gapXXL)
            }
            .scrollIndicators(.hidden)
            .background(V8.C.bg.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func verify() {
        // SEC-28：失败计数必须走 AppLock（持久 + 冷却），不能只在本地 @State 里数。
        // 旧实现关掉 sheet 就清零 —— 拿到已解锁手机的人可以无限次试 4 位数字密码。
        switch AppLock.shared.verify(code) {
        case .success:
            onVerified()
            dismiss()
        case .decoy:
            // 胁迫码：本机密码类的确认动作一律**不放行**（否则被胁迫者能借它关掉数据保护）。
            error = "这个输入不能用于本操作"
            code = ""
        case .wrong(let remaining):
            // 2026-11-04（拷贝漂移）：这份 verify 是 UnlockGate 的同源拷贝 —— 那边把
            // 「还可试 N 次」改成「再错 N 次开始冷却」，这里漏了。两处用的是**同一个**
            // AppLock 梯度，文案应当同源。
            error = remaining > 0 ? "密码不对 · 冷却 \(remaining) 秒"
                                  : "密码不对 · 再错 \(max(1, 3 - AppLock.shared.failStreak)) 次开始冷却"
            code = ""
        case .cooling(let remaining):
            error = "冷却中 · \(remaining) 秒后再试"
            code = ""
        }
    }
}
