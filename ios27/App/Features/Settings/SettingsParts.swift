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
        VStack(alignment: .leading, spacing: T.S.xs) {
            Text(title)
                .font(T.F.display())
                .foregroundStyle(Ink.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: T.S.s) {
                StateDot(tone: tone, word: status)
                Text(status)
                    .font(T.F.caption)
                    .foregroundStyle(tone == .neutral ? Ink.inkSub : tone.color)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, T.S.gutter)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// 0.5pt 蚀刻分割线。面板内行与行之间用它，不用系统 Divider（那会画 1pt 的软线）。
struct SettingRule: View {
    var body: some View {
        Rectangle()
            .fill(Ink.hairline)
            .frame(height: T.Stroke.hair)
            .accessibilityHidden(true)
    }
}

/// 一行「符号 → 标签 / 读数 → 箭头」。读数走 FieldRow（等宽右对齐），整行 44pt 可点。
/// 这是设置页唯一的行语法：一屏里每节一行读数，点进去才是那一节。
struct SettingRow: View {
    let label: String
    let value: String
    var unit: String? = nil
    var tint: Color = Ink.ink
    /// 值是数字 / 时间时走等宽；值是词（「已设」「跟随系统」）时关掉，否则会读成读数。
    var mono: Bool = true
    var symbol: String? = nil
    var chevron: Bool = true
    /// 标签下面的一句后果说明。只写用户决策需要的那一句，不铺陈。
    var note: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: T.S.s) {
                if let symbol {
                    // 装饰性图标：语义由相邻文字承载（只标一次，重复标是噪音）
                    Image(systemName: symbol)
                        .accessibilityHidden(true)
                        .font(T.F.icon(T.Icon.m, weight: .regular))
                        .foregroundStyle(Ink.inkSub)
                        .frame(width: T.Icon.xl, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: T.S.xxs) {
                    FieldRow(label: label, value: value, unit: unit, tint: tint, mono: mono)
                    if let note {
                        Text(note)
                            .font(T.F.unit)
                            .foregroundStyle(Ink.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(T.F.icon(T.Icon.s, weight: .medium))
                        .foregroundStyle(Ink.inkFaint)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: T.Hit.min)
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
        VStack(alignment: .leading, spacing: T.S.xxs) {
            Toggle(isOn: $isOn) {
                Text(label)
                    .font(T.F.body)
                    .foregroundStyle(Ink.ink)
            }
            .tint(Ink.inkSub)
            .frame(minHeight: T.Hit.min)
            if let note {
                Text(note)
                    .font(T.F.unit)
                    .foregroundStyle(Ink.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// 破坏性动作行。语义红只随真实危险动作出现，不当装饰。
struct SettingDangerRow: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: T.S.s) {
                Text(title)
                    .font(T.F.body)
                    .foregroundStyle(State.critical)
                Spacer(minLength: 0)
            }
            .frame(minHeight: T.Hit.min)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// 破坏性主动作：填 critical，不是填 signal。
/// 用铜锈绿去按「删除」是把品牌色当装饰，也把危险动作画成了安全动作 —— 这里换成语义色。
/// 压填充的文字走 Ink.paper（浅色档是纸白、深色档是近黑），正好是两档 critical 上的可读色。
struct DangerAction: View {
    let title: String
    var busy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: T.S.s) {
                if busy {
                    ProgressView().controlSize(.small).tint(Ink.paper)
                }
                Text(title).font(T.F.bodyStrong)
            }
            .foregroundStyle(Ink.paper)
            .frame(maxWidth: .infinity)
            .frame(height: T.H.action)
            .background(State.critical, in: .rect(cornerRadius: T.R.control))
        }
        .buttonStyle(PressStyle())
        .disabled(busy)
        .accessibilityLabel(title)
    }
}

/// 页尾注解。只说明「这一项做什么 / 有什么后果」，不写实现细节。
struct SettingsNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(T.F.caption)
            .foregroundStyle(Ink.inkSub)
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
                VStack(spacing: T.S.l) {
                    SettingsHeader(
                        title: (isChange ? "更改" : "设置") + kind.title,
                        tone: error == nil ? .neutral : .attention,
                        status: error ?? "4 位以上纯数字 · 两次输入必须一致"
                    )

                    Panel {
                        VStack(alignment: .leading, spacing: T.S.m) {
                            Inset {
                                SecureField(kind.fieldPlaceholder, text: $first)
                                    .font(T.F.body)
                                    .keyboardType(.numberPad)
                                    .textContentType(.newPassword)
                                    .accessibilityLabel(kind.fieldPlaceholder)
                            }
                            Inset {
                                SecureField("再次输入", text: $second)
                                    .font(T.F.body)
                                    .keyboardType(.numberPad)
                                    .accessibilityLabel("再次输入")
                            }
                            PrimaryAction(title: "确定") { commit() }
                                .padding(.top, T.S.xs)
                        }
                    }
                    .padding(.horizontal, T.S.gutter)

                    SecondaryAction(title: "取消") { dismiss() }
                        .padding(.horizontal, T.S.gutter)

                    SettingsNote(text: kind.note)
                        .padding(.horizontal, T.S.gutter)
                }
                .padding(.vertical, T.S.l)
            }
            .background(CanvasBackground())
            .scrollEdgeEffectStyle(.soft, for: .top)
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func commit() {
        guard first.count >= 4 else { error = "需 4 位以上"; return }
        guard first.allSatisfy({ $0.isNumber }) else { error = "只能输入数字"; return }
        guard first == second else { error = "两次输入不一致"; return }
        switch kind {
        case .passcode:
            // TODO(engine) 真实现要把 PBKDF2-HMAC-SHA256 摘要落 SecretStore（旧摘要验过即静默升级）。
            store.hasPasscode = true
        case .duress:
            // TODO(engine) 胁迫码摘要与真密码分开落盘；空壳模式的读取判据在 LockGate。
            store.hasDuressCode = true
        }
        dismiss()
    }
}

// MARK: - 偏好绑定

/// 偏好 Binding。用 KeyPath 而不是 `$store.xxx`：`store` 在页面里是计算属性，
/// `@Bindable` 只对局部变量成立；KeyPath 写法让每个开关都指向同一个 SettingsStore 单例，
/// 页面之间不会出现"两页各存一份副本、显示两个值"。
func settingsBinding<Value>(_ keyPath: ReferenceWritableKeyPath<SettingsStore, Value>) -> Binding<Value> {
    Binding(
        get: { SettingsStore.shared[keyPath: keyPath] },
        set: { SettingsStore.shared[keyPath: keyPath] = $0 }
    )
}

/// 只读试验模式的 Binding。两个设置页都挂这个开关 —— 抽出来，免得一处改了另一处漂。
func trialGuardBinding(_ app: AppModel) -> Binding<Bool> {
    Binding(get: { app.trialGuard }, set: { app.trialGuard = $0 })
}

/// 面板内的档位 chip 行。ChipRow 自带页面级 gutter 内边距，嵌进面板时要把它收回来，
/// 否则面板内再吃一层 16pt，读数与档位对不齐。收回量走令牌，不写字面量。
struct SettingChips<Item: Hashable>: View {
    let items: [Item]
    let title: (Item) -> String
    @Binding var selection: Item

    var body: some View {
        ChipRow(items: items, title: title, selection: $selection)
            .padding(.horizontal, -T.S.gutter)
    }
}
