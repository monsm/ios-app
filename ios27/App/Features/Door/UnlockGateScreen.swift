// UnlockGateScreen.swift —— 30 秒内二次开锁的本机密码闸（原 DeviceHomeSupport.swift:122-219）。
//
// 这屏干什么：刚开过一次门，30 秒内再点圆盘要先输本机密码 —— 防止手机被人捡到后连续开门。
// 数据从哪来：DB.hasPasscode / DB.verifyPasscode（与冷启动闸同一套摘要）。
// 主动作：解锁并开门。失败三次进 30 秒冷却（与原版一致），冷却期内按钮禁用并显示剩余秒数。
import SwiftUI


/// List 里的「整块卡片」行（与其它 List 化页面同用途）。独立命名，避免同名扩展重声明。
private extension View {
    func gateCardRow() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading).plainRow()
    }
}
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
        // 2026-11-02（R5 全换系统）：ScrollView + VStack → 系统 List + Section。
        // ⚠ 第 2 轮加的**延时聚焦**（.task { sleep 350ms; focused = true }）与 `.scrollDismissesKeyboard` 保留在下方，
        // 它们是 L1（sheet 还没落位就弹键盘把内容顶出屏幕）的修复，不能丢。
        // 业务逻辑（verify 的四种结果）、冷却倒计时、禁用态、无障碍标签一字未改。
        List {
            header.gateCardRow()
            Section {
                VCard {
                    VStack(alignment: .leading, spacing: V.S.gapMS) {
                        // 段头已由 Section header 承担（「本机密码」）；这一行只保留原来 VSectionLabel 的
                        // trailing 信息（冷却秒数 / 位数要求）—— 它是有用的状态读数，不跟着标题一起删。
                        Text(cooling > 0 ? "冷却 \(cooling) 秒" : "4 位以上")
                            .font(V.F.unit)
                            .foregroundStyle(cooling > 0 ? V.C.critical : V.C.text3)
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
                .gateCardRow()
            } header: {
                sectionHeader("本机密码")
            }

            Section {
                SettingsNote(text: "为什么再要一次密码：手机刚开过门，30 秒内被人拿走时，这一道闸让 TA 不能直接再开。输对一次后 30 秒内不再重复询问。")
                    .gateCardRow()
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(V.S.gap16)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, V.S.gap16, for: .scrollContent)
        .contentMargins(.bottom, V.S.gapL, for: .scrollContent)
        .background(CanvasBackground())
        .navigationTitle("再次确认")
        .navigationBarTitleDisplayMode(.inline)
        // 键盘避让：往下拖就能收起数字键盘（否则 4 位数字键盘会盖住「解锁并开门」）。
        .scrollDismissesKeyboard(.interactively)
        // 打开 sheet 的瞬间就弹键盘，sheet 还没落位、安全区还没算好 —— 内容会被顶出屏幕。
        // 延时 350ms 再聚焦，等呈现动画结束（这是 sheet 里自动聚焦的标准做法）。
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            focused = true
        }
        .task(id: cooldownUntil) {
            guard cooldownUntil != nil else { return }
            while !Task.isCancelled {
                now = Date()
                if cooling == 0 { cooldownUntil = nil; error = nil; return }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// List 段头：中文必须显式 textCase(nil)，否则系统会把段头拉成大写形态。
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(V.F.small)
            .foregroundStyle(V.C.text3)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
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
                error = "密码不对 · 还可试 \(max(0, 3 - failures)) 次"
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
