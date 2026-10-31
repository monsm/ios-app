// KeyCreateScreen.swift —— 凭证工坊（新增 / 改造）。四步：类型归属 → 码值 → 有效期 → 确认。
//
// 数据从哪来：AppModel.keys / members；写回也是 AppModel.keys（值语义，改就是换一条）。
// 主动作：「下一步」逐级推进（步间硬拦，不静默补值），最后一步「写入台账」落库并退回钥匙列表。
// 诚实边界：锁端下发（cmd0A/0B、cmd13/14）没有链路，写入的只是本机台账，页面上说清楚。
import SwiftUI
import UIKit

struct KeyCreateScreen: View {
    // internal（不是 private）：四步视图在 KeyCreateParts.swift 的 extension 里，跨文件要可见。
    @Environment(AppModel.self) var app
    @Environment(Router.self) var router

    @State var step = 0
    @State var kindIndex = 0
    @State var owner: String?
    @State var code = ""
    @State var fromClipboard = false
    @State var name = ""
    @State var note = ""
    @State var durationDays = 7
    @State var confirmCode = ""
    @State var errorText: String?
    @State var editingID: String?

    let stepLabels = ["类型归属", "码值", "有效期", "确认"]

    var kinds: [KeyItem.Kind] { [.password, .temp, .fingerprint] }

    var kind: KeyItem.Kind { kinds[min(kindIndex, kinds.count - 1)] }

    var isEdit: Bool { editingID != nil }

    var codeValid: Bool {
        code.count >= 6 && code.count <= 8 && code.allSatisfy { $0.isNumber }
    }

    var strength: (score: Int, hint: String) { KeysCode.strength(code) }

    var body: some View {
        ScrollView {
            VStack(spacing: T.S.l) {
                header
                KeysStepDots(total: 4, index: step, labels: stepLabels)
                switch step {
                case 0: typeStep
                case 1: codeStep
                case 2: periodStep
                default: confirmStep
                }
                navRow
            }
            .padding(.vertical, T.S.l)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(isEdit ? "改造凭证" : "新增凭证")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            consumeRoute()
            readClipboardOnce()
        }
    }

    // MARK: 页头

    private var header: some View {
        VStack(alignment: .leading, spacing: T.S.xs) {
            Text(isEdit ? "改造凭证" : "新增凭证")
                .font(T.F.display())
                .foregroundStyle(Ink.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: T.S.s) {
                StateDot(tone: app.lock == nil ? .neutral : .ok,
                         word: app.lock == nil ? "未添加门锁" : "门锁在场")
                Text(app.lock == nil
                     ? "还没有门锁 —— 凭证要挂在具体一把锁上"
                     : "\(app.lock?.name ?? "") · \(app.lock?.model ?? "")")
                    .font(T.F.caption)
                    .foregroundStyle(Ink.inkSub)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, T.S.gutter)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func consumeRoute() {
        let context = router.consume()
        guard case .key(let id) = context else { return }
        guard let existing = app.keys.first(where: { $0.id == id }) else { return }
        editingID = id
        kindIndex = kinds.firstIndex(of: existing.kind) ?? 0
        owner = existing.owner
        code = existing.code ?? ""
        name = existing.name
        note = existing.name
        step = 0
    }

    /// 剪贴板里正好是一串 6~8 位数字时直接填上（301），并标明来源。
    private func readClipboardOnce() {
        guard !isEdit, code.isEmpty else { return }
        guard let text = UIPasteboard.general.string else { return }
        let digits = text.filter { $0.isNumber }
        guard digits.count >= 6, digits.count <= 8 else { return }
        code = digits
        fromClipboard = true
    }

    // MARK: 步间导航（真拦：坏值出不了这一步）

    private var navRow: some View {
        HStack(spacing: T.S.s) {
            if step > 0 {
                Button {
                    withAnimation(T.M.move) { step -= 1 }
                } label: {
                    Text("上一步")
                        .font(T.F.body)
                        .foregroundStyle(Ink.inkSub)
                        .frame(minHeight: T.Hit.min)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("上一步")
            }
            Spacer(minLength: 0)
            if step < 3 {
                Button {
                    advance()
                } label: {
                    HStack(spacing: T.S.xs) {
                        Text(nextTitle)
                            .font(T.F.bodyStrong)
                        Image(systemName: "chevron.right")
                            .font(.system(size: T.Icon.s, weight: .medium))
                    }
                    .foregroundStyle(Signal.on)
                    .padding(.horizontal, T.S.l)
                    .frame(minHeight: T.Hit.min)
                    .background(Signal.base, in: .rect(cornerRadius: T.R.control))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(nextTitle)
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    private var nextTitle: String {
        switch step {
        case 0: return "下一步：码值"
        case 1: return "下一步：有效期"
        default: return "下一步：确认"
        }
    }

    private func advance() {
        switch step {
        case 0:
            if owner == nil && !app.members.filter({ !$0.archived }).isEmpty {
                errorText = "先选归属成员 —— 凭证必须知道归谁。"
                return
            }
            if kind == .fingerprint && name.isEmpty {
                name = "指纹 \(app.keys.filter { $0.kind == .fingerprint }.count + 1)"
            }
        case 1:
            if kind != .fingerprint && !codeValid {
                errorText = "码值要 6~8 位纯数字 —— 就在上面那格改，改好再往下。"
                return
            }
        default:
            break
        }
        errorText = nil
        withAnimation(T.M.move) { step += 1 }
    }

    // MARK: 提交（写本机台账）

    func submit() {
        if kind != .fingerprint {
            guard codeValid else {
                step = 1
                errorText = "码值要 6~8 位纯数字。"
                return
            }
            guard confirmCode == code else {
                errorText = "两次输入不一致，请重输一遍。"
                return
            }
        }
        let finalName: String
        if !name.isEmpty {
            finalName = name
        } else if kind == .fingerprint {
            finalName = "指纹 \(app.keys.filter { $0.kind == .fingerprint }.count + 1)"
        } else if kind == .temp {
            finalName = note.isEmpty ? "临时码 \(TimeFormat.dayShort(expiryMillis))" : note
        } else {
            finalName = note.isEmpty ? "密码 \(app.keys.filter { $0.kind == .password }.count + 1)" : note
        }
        // TODO(engine): 下发 cmd0A/0B（密码体）与 cmd13/cmd14（指纹录入）。链路未接 ——
        // 这里只写本机台账；页面不假装已下发，回执文案只说「已记入本机」。
        let item = KeyItem(
            id: editingID ?? "local-\(Int(Date().timeIntervalSince1970 * 1000))",
            kind: kind,
            name: finalName,
            owner: owner,
            code: kind == .fingerprint ? nil : code,
            expiresAt: kind == .temp ? expiryMillis : nil,
            disabled: false
        )
        if editingID != nil {
            app.keys = KeysState.replace(item, in: app.keys)
        } else {
            app.keys.append(item)
        }
        router.keysPath = []
    }
}