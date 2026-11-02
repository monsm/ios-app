// SettingsParts.swift —— 设置域的内部语法：页头 / 行 / 开关 / 细线 / 注解 / 密码表。
//
// 这屏干什么：给 7 个设置页提供同一套行语法，避免每页各写一套 HStack ——
// 同一件事在 7 个页面若各画一遍，迟早出现 7 种观感（这是上一版的老毛病）。
// 数据从哪来：只吃调用方传进来的值，本文件不持有任何状态。
// 主动作：无。这里只画，不决定动作。
import SwiftUI

/// 页头：34pt semibold 大标题 + 一行状态（状态点 + 词 + 状态句）。
/// 中文标题最高 semibold —— 苹方无 Bold，.bold() 会静默回退。
struct SettingsHeader: View {
    let title: String
    let tone: Tone
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: V.S.gapXS) {
            Text(title)
                .font(V.F.displayHome)
                .foregroundStyle(V.C.text1)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: V.S.gapS) {
                VStateDot(tone: tone, word: status)
                Text(status)
                    .font(V.F.footnote)
                    .foregroundStyle(tone == .neutral ? V.C.text2 : tone.color)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, V.S.pageGutter)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// 0.5pt 蚀刻分割线。面板内行与行之间用它，不用系统 Divider（那会画 1pt 的软线）。
struct SettingRule: View {
    var body: some View {
        Rectangle()
            .fill(V.C.hairline)
            .frame(height: V.S.hair)
            .accessibilityHidden(true)
    }
}

/// 一行「符号 → 标签 / 读数 → 箭头」。读数走 FieldRow（等宽右对齐），整行 44pt 可点。
/// 这是设置页唯一的行语法：一屏里每节一行读数，点进去才是那一节。
struct SettingRow: View {
    let label: String
    let value: String
    var unit: String? = nil
    var tint: Color = V.C.text1
    /// 值是数字 / 时间时走等宽；值是词（「已设」「跟随系统」）时关掉，否则会读成读数。
    var mono: Bool = true
    var symbol: String? = nil
    var chevron: Bool = true
    /// 标签下面的一句后果说明。只写用户决策需要的那一句，不铺陈。
    var note: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: V.S.gapS) {
                if let symbol {
                    // 装饰性图标：语义由相邻文字承载（只标一次，重复标是噪音）
                    Image(systemName: symbol)
                        .accessibilityHidden(true)
                        .font(V.F.icon18)
                        .foregroundStyle(V.C.text2)
                        .frame(width: V.Icon.xl, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: V.S.gapXXS) {
                    VFieldRow(label: label, value: value, unit: unit, tint: tint, mono: mono)
                    if let note {
                        Text(note)
                            .font(V.F.unit)
                            .foregroundStyle(V.C.text3)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(V.F.icon15Medium)
                        .foregroundStyle(V.C.text3)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: V.Hit.min)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label)，\(value)\(unit.map { " \($0)" } ?? "")\(note.map { "。\($0)" } ?? "")")
        .accessibilityAddTraits(.isButton)
    }
}

/// 一行开关。开关走墨色（同屏 signal 只留给主动作）；说明写在该行下面。
struct SettingToggle: View {
    let label: String
    var note: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: V.S.gapXXS) {
            Toggle(isOn: $isOn) {
                Text(label)
                    .font(V.F.body)
                    .foregroundStyle(V.C.text1)
            }
            .tint(V.C.text2)
            .frame(minHeight: V.Hit.min)
            if let note {
                Text(note)
                    .font(V.F.unit)
                    .foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// 破坏性动作行。**全换系统（2026-11-02）**：改走 `Button(role: .destructive)` ——
/// 系统红 + 系统按压反馈 + VoiceOver 的破坏性语义，本仓不再自绘红字与 chevron。
/// 语义红只随真实危险动作出现，不当装饰；二次确认仍由调用方负责（本行只发起）。
struct SettingDangerRow: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            HStack(spacing: V.S.gapS) {
                Text(title)
                    .font(V.F.body)
                Spacer(minLength: 0)
            }
            .frame(minHeight: V.Hit.min)
            .contentShape(.rect)
        }
        .accessibilityLabel(title)
    }
}

/// 页尾注解。只说明「这一项做什么 / 有什么后果」，不写实现细节。
struct SettingsNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(V.F.footnote)
            .foregroundStyle(V.C.text2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 密码表：本机密码与胁迫码共用同一条校验链（≥4 位、全数字、两次一致）。
/// 校验不通过就地报错，不假装成功；通过才写对应的状态位。
/// 两种表共用一套界面，是因为它们本来就是同一个输入框的两种含义 —— 分成两套只会漂成两种校验。
enum PasscodeKind {
    case passcode
    case duress

    var title: String {
        switch self {
        case .passcode: return "本机密码"
        case .duress: return "胁迫码"
        }
    }

    var fieldPlaceholder: String {
        switch self {
        case .passcode: return "本机密码"
        case .duress: return "胁迫码"
        }
    }

    var note: String {
        switch self {
        case .passcode:
            return "密码只存在这台手机里，不上传、不写进锁。忘记密码只能删 App 重装 —— 门锁与锁内凭证不受影响。"
        case .duress:
            return "胁迫码要与真密码不同。被胁迫时输入它：门照样能开，但凭证与记录显示为空 —— 不报警、不暴露。"
        }
    }
}

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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: V.S.gap16) {
                    SettingsHeader(
                        title: (isChange ? "更改" : "设置") + kind.title,
                        tone: error == nil ? .neutral : .attention,
                        status: error ?? "4 位以上纯数字 · 两次输入必须一致"
                    )

                    VCard {
                        VStack(alignment: .leading, spacing: V.S.gapMS) {
                            if isChange {
                                VInset {
                                    SecureField("原本机密码", text: $oldCode)
                                        .font(V.F.body)
                                        .keyboardType(.numberPad)
                                        .textContentType(.password)
                                        // 三个密码框统一 44pt 高：HIG 可点下限，也让它们与下面两颗按钮对齐。
                                        .frame(minHeight: V.Hit.min)
                                        .accessibilityLabel("原本机密码")
                                }
                                Text("先验证当前本机密码 —— 只验本机摘要，不联网。")
                                    .font(V.F.unit)
                                    .foregroundStyle(V.C.text3)
                            }
                            VInset {
                                SecureField(kind.fieldPlaceholder, text: $first)
                                    .font(V.F.body)
                                    .keyboardType(.numberPad)
                                    .textContentType(.newPassword)
                                    .frame(minHeight: V.Hit.min)
                                    .accessibilityLabel(kind.fieldPlaceholder)
                            }
                            VInset {
                                SecureField("再次输入", text: $second)
                                    .font(V.F.body)
                                    .keyboardType(.numberPad)
                                    .frame(minHeight: V.Hit.min)
                                    .accessibilityLabel("再次输入")
                            }
                            // 主动作与取消**同列同宽**：旧实现「确定」在卡内、「取消」在卡外，
                            // 两颗按钮左右边缘对不齐（换行后更明显）。
                            VActionButton(title: "确定") { commit() }
                                .padding(.top, V.S.gapXS)
                            VOutlineButton(title: "取消") { dismiss() }
                        }
                    }
                    .padding(.horizontal, V.S.pageGutter)

                    SettingsNote(text: kind.note)
                        .padding(.horizontal, V.S.pageGutter)
                }
                .padding(.vertical, V.S.gap16)
            }
            .background(CanvasBackground())
            .scrollEdgeEffectStyle(.soft, for: .top)
            // 键盘避让：三个密码框（原本机密码 / 新密码 / 再次输入）在页面中部，
            // 数字键盘弹起会盖住「确定」。往下拖即可收键盘。
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
        }
        // 半屏 sheet 会被数字键盘整个盖住 —— 这里必须 .large，并给一个可见的拖拽指示。
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func commit() {
        if isChange {
            guard DB.verifyPasscode(oldCode) else { error = "原本机密码不对"; return }
        }
        guard first.count >= 4 else { error = "需 4 位以上"; return }
        guard first.allSatisfy({ $0.isNumber }) else { error = "只能输入数字"; return }
        guard first == second else { error = "两次输入不一致"; return }
        switch kind {
        case .passcode:
            // 真摘要：PBKDF2-HMAC-SHA256 落 kf_passcode（DB 内部实现，旧摘要验过即静默升级）。
            DB.setPasscode(first)
        case .duress:
            // 胁迫码独立键 kf_duress；空壳模式的读取判据在 AppLock/LockGate。
            // 2026-11-01（Round 258）：`setDuressCode` 返回 Bool，其中一条失败条件是
            // **胁迫码与本机密码相同**（`verifyPasscode(code)` 命中就 return false，什么也不写）。
            // 原来用 `_ =` 丢掉结果、直接 `dismiss()` —— 用户以为设好了，实际根本没设，
            // 而且要到"真需要用胁迫码"那一刻才会发现。这一条是安全功能，不能静默失败。
            guard DB.setDuressCode(first) else {
                error = "胁迫码不能与本机密码相同；请换一个 4 位以上数字"
                return
            }
        }
        dismiss()
    }
}

// MARK: - 偏好绑定

/// 偏好 Binding。用 KeyPath 而不是 `$store.xxx`：`store` 在页面里是计算属性，
/// `@Bindable` 只对局部变量成立；KeyPath 写法让每个开关都指向同一个 SettingsStore 单例，
/// 页面之间不会出现"两页各存一份副本、显示两个值"。
@MainActor
func settingsBinding<Value>(_ keyPath: ReferenceWritableKeyPath<SettingsStore, Value>) -> Binding<Value> {
    Binding(
        get: { SettingsStore.shared[keyPath: keyPath] },
        set: { SettingsStore.shared[keyPath: keyPath] = $0 }
    )
}

/// 只读试验模式的 Binding。两个设置页都挂这个开关 —— 抽出来，免得一处改了另一处漂。
/// @MainActor：Binding 的 get/set 在 Swift 6 下按 @Sendable 检查，捕获 AppModel / keyPath
/// 会直接报错（E-05）。标上隔离后捕获落在同一 actor 内，合法。
@MainActor
func trialGuardBinding(_ app: AppModel) -> Binding<Bool> {
    Binding(
        get: { app.trialGuard },
        set: { v in
            app.trialGuard = v
            TrialGuard.set(v)   // 写 kf_trial_guard：LockService.assertReadOnly 读的就是这个键
        }
    )
}

/// 只验证旧密码的 sheet：关闭本机密码 / 关闭胁迫码前必须过这一道。
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
                VStack(alignment: .leading, spacing: V.S.gap16) {
                    SettingsHeader(title: title, tone: error == nil ? .neutral : .attention,
                                   status: error ?? note)
                    VCard {
                        VStack(alignment: .leading, spacing: V.S.gapMS) {
                            VInset {
                                SecureField("当前本机密码", text: $code)
                                    .font(V.F.body)
                                    .keyboardType(.numberPad)
                                    .textContentType(.password)
                                    // 同 PasscodeSheet：44pt 可点下限，与下面两颗按钮同宽同高。
                                    .frame(minHeight: V.Hit.min)
                                    .accessibilityLabel("当前本机密码")
                            }
                            VActionButton(title: "验证并继续", systemImage: "lock.open") { verify() }
                                .disabled(code.count < 4)
                                .opacity(code.count < 4 ? 0.45 : 1)
                            VOutlineButton(title: "取消") { dismiss() }
                        }
                    }
                    .padding(.horizontal, V.S.pageGutter)
                    SettingsNote(text: "验证的是这台手机上的摘要；不改锁端任何设置。")
                        .padding(.horizontal, V.S.pageGutter)
                }
                .padding(.vertical, V.S.gap16)
            }
            .background(CanvasBackground())
            .scrollEdgeEffectStyle(.soft, for: .top)
            // 键盘避让：密码框 + 两个按钮在同一屏，数字键盘会盖住「验证并继续」。
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
        // 同 PasscodeSheet：验证框里有密码输入，必须全屏高度。
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
            error = remaining > 0 ? "密码不对 · 冷却 \(remaining) 秒" : "密码不对 · 再试一次"
            code = ""
        case .cooling(let remaining):
            error = "冷却中 · \(remaining) 秒后再试"
            code = ""
        }
    }
}

/// 面板内的档位选择。
///
/// 2026-11-01 改造：**改用原生 `Picker` + `.segmented`**，不再用自定义 chip 行。
/// 为什么（对应本轮 objective 的「尽可能有原生控件就用原生控件」）：
///   · 这里全部是 3–4 档的枚举（主题 4 / 密度 3 / 动效 3 / 时间 3 / 面容 3），
///     正是 `.segmented` 的标准场景；
///   · 原生分段控件自带：系统外观（iOS 26 起是液态玻璃材质）、VoiceOver 的
///     「adjustable / 第 N 项，共 M 项」语义、Switch Control 支持、Dynamic Type 适配 ——
///     这些自定义 chip 行都要自己写，且很难写全；
///   · 视觉上仍走系统控件，浅色/深色、强调色、无障碍「减少透明度」全部自动跟随。
///
/// 保留自定义 `VChipRow` 给**档位多到放不下**的场景（如家页的分组标签、凭证页的类型筛选）——
/// 那种情况分段控件会被压扁，反而是 `ScrollView` 里的 chip 行更合适。
struct SettingChips<Item: Hashable>: View {
    let items: [Item]
    let title: (Item) -> String
    @Binding var selection: Item

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(items, id: \.self) { item in
                Text(title(item)).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}
