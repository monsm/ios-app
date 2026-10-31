// UnlockGateScreen.swift —— 30 秒内二次开锁的本机密码闸（原 DeviceHomeSupport.swift:122-219）。
//
// 这屏干什么：刚开过一次门，30 秒内再点圆盘要先输本机密码 —— 防止手机被人捡到后连续开门。
// 数据从哪来：DB.hasPasscode / DB.verifyPasscode（与冷启动闸同一套摘要）。
// 主动作：解锁并开门。失败三次进 30 秒冷却（与原版一致），冷却期内按钮禁用并显示剩余秒数。
import SwiftUI

struct UnlockGateScreen: View {
    /// 验证通过后要执行的动作（门页传 runUnlockChain；作为 Dest 打开时为空）。
    var onPass: (() -> Void)? = nil

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
        if DB.verifyPasscode(code) {
            error = nil
            onPass?()
            dismiss()
        } else {
            failures += 1
            code = ""
            if failures >= 3 {
                cooldownUntil = Date().addingTimeInterval(30)
                now = Date()
                error = "密码不对 · 已连续 3 次，冷却 30 秒"
            } else {
                error = "密码不对 · 还可试 \(3 - failures) 次"
            }
        }
    }
}

#Preview("UnlockGateScreen") {
    NavigationStack { UnlockGateScreen() }
}
