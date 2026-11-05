// KeyCreateHomeScreen.swift —— 凭证工坊（新增 / 改造）（V8 设计语言）
//
// 与 KeyCreateScreen + KeyCreateParts 的能力对齐：四步（类型归属 → 码值 → 有效期 → 确认）、
// 类型选择、归属成员、码值强度与重复检测、本地生成数字码、剪贴板识别、备注短语、
// 指纹录入、写入台账。
// 只改渲染层：写台账仍走 app.addPassword / app.enrollFingerprint，落盘键与错误文案不变。
//
// 与旧页的刻意差异：
//   ① 空壳模式（DB.isDecoy）整页只读：不显示成员与凭证信息，也拒绝提交（旧页会一路填到第四步，
//      最后被数据层静默拒绝，用户以为建好了）。
//   ② 只读试验模式（app.trialGuard）在页内写明：提交会被护栏拦下，本机台账也不会写。
//   ③ 台账损坏时提前说明「现在写不进去」，而不是等用户填完四步。
import SwiftUI
import UIKit

struct KeyCreateHomeScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    @State private var step = 0
    @State private var kindIndex = 0
    @State private var owner: String?
    @State private var code = ""
    @State private var fromClipboard = false
    @State private var name = ""
    @State private var note = ""
    @State private var durationDays = 7
    @State private var confirmCode = ""
    @State private var errorText: String?
    @State private var editingID: String?
    @State private var busy = false
    @State private var fpCount = 0
    /// 数字键盘没有 Return 键 —— 用焦点状态给「完成」按钮一个落点（纯 SwiftUI，不引 UIKit）。
    @FocusState private var codeFocused: Bool

    private let stepLabels = ["类型归属", "码值", "有效期", "确认"]
    private let kinds: [KeyItem.Kind] = [.password, .temp, .fingerprint]

    private var kind: KeyItem.Kind { kinds[min(kindIndex, kinds.count - 1)] }
    private var isEdit: Bool { editingID != nil }
    private var decoyed: Bool { DB.isDecoy }
    private var codeValid: Bool {
        code.count >= 6 && code.count <= 8 && code.allSatisfy { $0.isNumber }
    }
    private var strength: (score: Int, hint: String) { KeysCode.strength(code) }

    // MARK: - 判断句与副文

    private var judgement: String {
        if decoyed { return "空壳模式下不新建凭证" }
        if app.ledgerCorrupt { return "本机台账读不出来" }
        if app.lock == nil { return "还没有门锁" }
        if step == 0 { return isEdit ? "改造一枚已有凭证" : "四步建一枚凭证" }
        return "第 " + String(step + 1) + " 步 · " + stepLabels[min(step, stepLabels.count - 1)]
    }

    private var lead: String {
        if decoyed {
            return "空壳模式只隐藏数据，不改动数据。退出空壳后才能新建或改造凭证。"
        }
        if app.ledgerCorrupt {
            return "当前会话里对凭证的改动不会保存（写入会被拒绝）。请先到「备份工作室」从一份备份恢复。"
        }
        if app.lock == nil {
            return "凭证要挂在具体一把锁上。先在「门」页添加一把锁，再回来创建。"
        }
        return "写入会真下发到门锁；回执成功才记入本机台账，失败会留在这一页报原因。"
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            if !decoyed && app.lock != nil {
                chipRow
            }
        } content: {
            if decoyed {
                decoyCard
            } else if app.ledgerCorrupt {
                // 2026-11-05（对抗审查 · 流程不合理）：这张卡原来**没有按钮** ——
                // 唯一的出路「去备份工作室恢复」只写在一句话里。
                // 把那条出路变成可点的动作（它与原因匹配；重试解决不了台账损坏）。
                VFailure(
                    what: "本机凭证台账读不出来",
                    why: "当前会话里对凭证的改动不会保存（写入会被拒绝）。",
                    next: "请先到「备份工作室」从一份备份恢复，再继续创建凭证。",
                    retry: { router.request(.dest(.backup)) },
                    actionTitle: "去备份工作室"
                )
            } else if app.lock == nil {
                VEmpty(
                    title: "添加一把门锁",
                    reason: "凭证是挂在某一把具体的锁上的。先把锁恢复出厂（长按 RESET 到三声嘀），再回来添加。",
                    actionTitle: "添加门锁"
                ) { router.request(.dest(.addLock)) }
            } else {
                stepCard
                navRow
                if let errorText {
                    VFailure(
                        what: "这一步没有通过",
                        why: errorText,
                        next: "按上面的提示改好后再继续；已经填好的内容还在。"
                    )
                }
                if app.trialGuard {
                    trialCard
                }
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        // 2026-11-05（对抗审查 · 安全）：本页用**明文 TextField**输入要写进锁的密码，
        // 却没有截图/录屏遮挡 —— 而同一串值在凭证详情页是打码 + captureShield 的。
        // 用户在新建流程里截图分享「我加了个什么密码」时，6~8 位开锁密码会整段进相册。
        // 这里与 KeyDetail / Zotp / MobileKey 同口径挂上遮挡。
        .captureShield("这里正在输入一枚开锁密码\n屏幕正在被录制或截图，已遮挡")
        .onAppear {
            consumeRoute()
            if let want = KeyCreateIntent.pending {
                KeyCreateIntent.pending = nil
                if let idx = kinds.firstIndex(of: want) { kindIndex = idx }
            }
            readClipboardOnce()
        }
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: V8.S.gapChip) {
                VChip2(icon: .glyph("square.stack.3d.up.fill"), label: "类型", value: kind.rawValue)
                VChip2(icon: .glyph("person.fill"), label: "归属", value: ownerLabel)
                VChip2(icon: .ring(codeFraction, codeTint), label: "码值", value: codeLabel)
                VChip2(icon: .ring(Double(step + 1) / 4.0, V8.C.accent), label: "进度", value: "第 " + String(step + 1) + "/4 步")
            }
            .padding(.leading, V8.S.gutterCard)
            .padding(.trailing, V8.S.gutterCard)
        }
        .scrollClipDisabled()
    }

    private var ownerLabel: String {
        guard let ownerName else { return "未归属" }
        return ownerName
    }

    private var codeFraction: Double {
        if kind == .fingerprint { return 1 }
        return min(1, Double(code.count) / 8.0)
    }

    private var codeTint: Color {
        if kind == .fingerprint { return V8.D.fingerprint }
        return codeValid ? V8.C.ok : V8.C.warn
    }

    private var codeLabel: String {
        if kind == .fingerprint { return "按指纹" }
        if code.isEmpty { return "待填" }
        return String(code.count) + " 位"
    }

    private var stepCard: some View {
        VCard2 {
            VCardHead(eyebrow: stepLabels[min(step, stepLabels.count - 1)], statement: stepStatement)
            VDivider2()
                .padding(.top, V8.S.gapM)
            switch step {
            case 0: typeStep
            case 1: codeStep
            case 2: periodStep
            default: confirmStep
            }
        }
    }

    private var stepStatement: String {
        switch step {
        case 0: return isEdit ? "改造：" + kind.rawValue : kind.rawValue
        case 1: return kindHint
        case 2: return kind == .temp ? "有效期 " + String(durationDays) + " 天" : "长期有效"
        default: return isEdit ? "确认后保存改造" : "确认后写入台账"
        }
    }

    // MARK: - 第一步：类型与归属

    @ViewBuilder
    private var typeStep: some View {
        VStack(alignment: .leading, spacing: V8.S.gapM) {
            Text("这一枚是什么")
                .font(V8.T.label)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
            HStack(spacing: V8.S.gapChip) {
                ForEach(kinds, id: \.self) { item in
                    kindChip(item)
                }
            }
            Text(kindHint)
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .fixedSize(horizontal: false, vertical: true)
            VDivider2()
                .padding(.top, V8.S.gapS)
            Text("动态密码")
                .font(V8.T.label)
                .foregroundStyle(V8.C.ink4)
            Text("按锁端周期自动更换的 6 位临时码，不用提前添加凭证。适合给快递、访客当场报码。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .fixedSize(horizontal: false, vertical: true)
            VNavRow(title: "打开动态密码", detail: "按锁端周期生成 6 位动态码") {
                router.request(.dest(.zotp))
            }
            VDivider2()
                .padding(.top, V8.S.gapS)
            Text("归谁")
                .font(V8.T.label)
                .foregroundStyle(V8.C.ink4)
            ownerPicker
        }
    }

    private func kindChip(_ item: KeyItem.Kind) -> some View {
        let on = kind == item
        return Button {
            kindIndex = kinds.firstIndex(of: item) ?? 0
            errorText = nil
        } label: {
            Text(item.rawValue)
                .font(V8.T.tab)
                .foregroundStyle(on ? V8.C.chipOn : V8.C.ink1)
                .padding(.horizontal, V8.S.gapM)
                .frame(minHeight: V8.H.min)
                .background(Capsule(style: .continuous).fill(on ? V8.C.accent : V8.C.chipOff))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.rawValue)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private var kindHint: String {
        switch kind {
        case .password: return "6~8 位数字，长期有效。家人报一串数字就能开门。"
        case .temp: return "有起止时间的临时码。到期后门锁自己拒绝，不用回来手动停用。"
        case .fingerprint: return "指纹在门锁上按 8 次录入，没有码值。录入要门锁在场。"
        case .mobile: return "手机钥匙在「手机钥匙」页签发，这里不建。"
        }
    }

    @ViewBuilder
    private var ownerPicker: some View {
        let active = MemberHub.sortedForPicker(app.members.filter { !$0.archived }, keys: app.keys)
        if active.isEmpty {
            Text("还没有成员。先去「家」建一位成员；也可以先用未归属把凭证建起来。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.warn)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                owner = nil
                errorText = nil
                withAnimation(reduceMotion ? nil : V8.M.move) { step = 1 }
            } label: {
                Text("先用未归属继续")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.ink1)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.chipOff))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("先用未归属继续")
        } else {
            VStack(spacing: 0) {
                ForEach(active) { member in
                    Button {
                        owner = member.id
                        errorText = nil
                    } label: {
                        VDataRow(
                            tag: member.role.rawValue,
                            tagTint: member.role == .owner ? V8.C.accent : V8.C.ink4,
                            title: member.name,
                            detail: (owner == member.id || owner == member.name) ? "已选" : nil,
                            value: String(app.keys.filter {
                                CredentialOrg.ownerMatches($0.owner, memberID: member.id, memberName: member.name)
                            }.count),
                            unit: "枚"
                        )
                    }
                    .buttonStyle(.plain)
                    if member.id != active.last?.id { VDotRule() }
                }
            }
        }
    }

    // MARK: - 第二步：码值

    @ViewBuilder
    private var codeStep: some View {
        VStack(alignment: .leading, spacing: V8.S.gapM) {
            if kind == .fingerprint {
                Text("指纹没有码值")
                    .font(V8.T.label)
                    .foregroundStyle(V8.C.ink4)
                    .padding(.top, V8.S.gapM)
                Text("指纹没有码值。下一步会真连锁录入：请把手指按在门锁的指纹头上再抬起，连续 8 次，成功后才记入本机台账。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("给这枚指纹起个名字", text: $name)
                    .font(V8.T.body)
                    .foregroundStyle(V8.C.ink1)
                    .frame(minHeight: V8.H.min)
                    .padding(.horizontal, V8.S.gapM)
                    .background(V8.C.well, in: .rect(cornerRadius: V8.R.inset))
                    .autocorrectionDisabled()
            } else {
                Text("码值 · " + (codeValid ? "位数合规" : "6~8 位数字"))
                    .font(V8.T.label)
                    .foregroundStyle(V8.C.ink4)
                    .padding(.top, V8.S.gapM)
                if !code.isEmpty {
                    Text(String(repeating: "•", count: code.count))
                        .font(V8.T.heroL)
                        .monospacedDigit()
                        .foregroundStyle(V8.C.ink1)
                        .tracking(V8.G.heroNumberTracking)
                }
                TextField("输入 6~8 位数字", text: $code)
                    .font(V8.T.body)
                    .foregroundStyle(V8.C.ink1)
                    .keyboardType(.numberPad)
                    // 2026-11-05（对抗审查 · UI/UX）：数字键盘**没有 Return 键**，
                    // 而本页主按钮在输入框下方 —— 键盘一弹就把「下一步」挡住，
                    // 用户只能杀 App。给一个明确的收起键。
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("完成") { codeFocused = false }
                        }
                    }
                    .focused($codeFocused)
                    .frame(minHeight: V8.H.min)
                    .padding(.horizontal, V8.S.gapM)
                    .background(V8.C.well, in: .rect(cornerRadius: V8.R.inset))
                    .autocorrectionDisabled()
                    .onChange(of: code) { _, new in
                        if errorText != nil { errorText = nil }
                        let filtered = new.filter { $0.isNumber }
                        if filtered != new { code = String(filtered.prefix(8)) }
                    }
                if fromClipboard {
                    Text("这串数字是从剪贴板识别来的。不对就重填，别让一段旧密码混进来。")
                        .font(V8.T.footnote)
                        .foregroundStyle(V8.C.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: V8.S.gapChip) {
                    ForEach([6, 7, 8], id: \.self) { digits in
                        Button {
                            code = KeysCode.digits(digits)
                            fromClipboard = false
                        } label: {
                            Text("生成 " + String(digits) + " 位")
                                .font(V8.T.tab)
                                .foregroundStyle(V8.C.ink1)
                                .padding(.horizontal, V8.S.gapM)
                                .frame(minHeight: V8.H.min)
                                .background(Capsule(style: .continuous).fill(V8.C.chipOff))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("本地生成 " + String(digits) + " 位数字码")
                    }
                    Spacer(minLength: 0)
                }
                if !code.isEmpty { strengthRow }
                duplicateNote
            }
        }
    }

    private var strengthRow: some View {
        HStack(spacing: V8.S.gapS) {
            HStack(spacing: V8.S.gapXS) {
                ForEach(0 ..< 3, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(index < strength.score ? (strength.score <= 1 ? V8.C.warnFill : V8.C.accent) : V8.C.chipOff)
                        .frame(width: V8.S.gapL, height: V8.S.gapXS)
                }
            }
            .accessibilityHidden(true)
            Text(strength.hint)
                .font(V8.T.caption)
                .foregroundStyle(strength.score <= 1 ? V8.C.warn : V8.C.ink3)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("密码强度：" + strength.hint)
    }

    /// 重复 / 前缀冲突 / 弱口令：全部走 Engine 的同一套判据（CredentialOrg），页面不再各写一份。
    @ViewBuilder
    private var duplicateNote: some View {
        let mac = app.currentMac
        if let weak = CredentialOrg.weakReason(code), codeValid {
            Text("弱口令：" + weak + " —— 建议换一串更难猜的数字。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.warn)
                .fixedSize(horizontal: false, vertical: true)
        }
        if !mac.isEmpty, codeValid {
            let excluding = Int(String(editingID?.split(separator: ":").last ?? "")) ?? 0
            let same = CredentialOrg.duplicatePwdValues(mac, code, excluding: excluding)
            let otherLocks = CredentialOrg.duplicatePwdLockNames(code, excludingMac: mac)
            let prefix = CredentialOrg.prefixConflict(mac, code, excluding: excluding)
            if !same.isEmpty {
                Text("本机台账里已经有 " + String(same.count) + " 枚密码用了同一串数字（#" + String(same[0].alias) + "）。同一把锁上重复，等于多留一条能被猜中的入口。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.warn)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !otherLocks.isEmpty {
                Text("另外 " + String(otherLocks.count) + " 把锁（" + otherLocks.joined(separator: "、") + "）也用了同一串数字 —— 一处泄露会牵连多扇门。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.warn)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let clash = prefix.first {
                Text("前 4 位和密码 #" + String(clash.alias) + " 一样，口头转述时容易说混。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 第三步：有效期与备注

    @ViewBuilder
    private var periodStep: some View {
        VStack(alignment: .leading, spacing: V8.S.gapM) {
            Text("有效期 · " + (kind == .temp ? "到期自动失效" : "长期有效"))
                .font(V8.T.label)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
            if kind == .temp {
                HStack(spacing: V8.S.gapChip) {
                    ForEach([1, 3, 7, 30], id: \.self) { days in
                        Button {
                            durationDays = days
                        } label: {
                            Text(String(days) + " 天")
                                .font(V8.T.tab)
                                .foregroundStyle(durationDays == days ? V8.C.chipOn : V8.C.ink1)
                                .padding(.horizontal, V8.S.gapM)
                                .frame(minHeight: V8.H.min)
                                .background(Capsule(style: .continuous).fill(durationDays == days ? V8.C.accent : V8.C.chipOff))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("有效期 " + String(days) + " 天")
                        .accessibilityAddTraits(durationDays == days ? [.isButton, .isSelected] : .isButton)
                    }
                    Spacer(minLength: 0)
                }
                VStatPair2(items: [
                    .init(label: "生效", value: TimeFormat.dayShort(KeysState.now())),
                    .init(label: "到期", value: TimeFormat.dayShort(expiryMillis))
                ])
            } else {
                Text(kind == .fingerprint
                     ? "指纹一直有效，除非你在详情里停用它。"
                     : "长期密码没有到期点；要限期就回第一步改成临时码。")
                    .font(V8.T.body)
                    .foregroundStyle(V8.C.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VDivider2()
                .padding(.top, V8.S.gapS)
            Text("备注")
                .font(V8.T.label)
                .foregroundStyle(V8.C.ink4)
            TextField("给谁 · 哪扇门 · 用多久", text: $note)
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink1)
                .frame(minHeight: V8.H.min)
                .padding(.horizontal, V8.S.gapM)
                .background(V8.C.well, in: .rect(cornerRadius: V8.R.inset))
                .autocorrectionDisabled()
            HStack(spacing: V8.S.gapChip) {
                ForEach(notePhrases, id: \.self) { phrase in
                    Button {
                        note = note.isEmpty ? phrase : note + " · " + phrase
                    } label: {
                        Text(phrase)
                            .font(V8.T.caption)
                            .foregroundStyle(V8.C.ink2)
                            .padding(.horizontal, V8.S.gapM)
                            .frame(minHeight: V8.H.min)
                            .background(Capsule(style: .continuous).fill(V8.C.chipOff))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("追加短语 " + phrase)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// 备注快捷短语。按类型裁剪：临时码不给「长期有效」—— 它跟上方选的到期日矛盾。
    private var notePhrases: [String] {
        kind == .temp ? ["仅白天", "勿外传"] : ["仅白天", "勿外传", "长期有效"]
    }

    private var expiryMillis: Int64 {
        let cal = TimeFormat.calendar
        let base = cal.startOfDay(for: Date())
        guard let nextDay = cal.date(byAdding: .day, value: durationDays + 1, to: base) else {
            return Int64(base.timeIntervalSince1970 * 1000)
        }
        let endOfDay = cal.date(byAdding: .second, value: -1, to: nextDay) ?? nextDay
        return Int64(endOfDay.timeIntervalSince1970 * 1000)
    }

    // MARK: - 第四步：确认与二次输入

    @ViewBuilder
    private var confirmStep: some View {
        VStack(alignment: .leading, spacing: V8.S.gapM) {
            Text("即将写入")
                .font(V8.T.label)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                VDataRow(tag: "类型", tagTint: V8.C.ink4, title: kind.rawValue, value: "")
                VDotRule()
                VDataRow(tag: "归属", tagTint: V8.C.ink4, title: ownerLabel, value: "")
                VDotRule()
                VDataRow(tag: "码值", tagTint: V8.C.ink4,
                         title: kind == .fingerprint ? "无（按指纹）" : String(repeating: "•", count: code.count),
                         value: "")
                VDotRule()
                VDataRow(tag: "到期", tagTint: V8.C.ink4,
                         title: kind == .temp ? TimeFormat.dayShort(expiryMillis) : "永久", value: "")
                if !note.isEmpty {
                    VDotRule()
                    VDataRow(tag: "备注", tagTint: V8.C.ink4, title: note, value: "")
                }
            }
            .padding(.top, V8.S.gapS)
            VDivider2()
                .padding(.top, V8.S.gapS)
            if kind == .fingerprint {
                Text("这一步会真连锁录入指纹：请把手指按在指纹头上再抬起，连续 8 次；成功后才记入本机台账。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.warn)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    submit()
                } label: {
                    Text(busy ? "录入中… 已按 " + String(fpCount) + "/8" : (isEdit ? "保存改造" : "开始录入指纹"))
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.chipOn)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.accent))
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .padding(.top, V8.S.gapS)
            } else {
                Text("再输一遍码值")
                    .font(V8.T.label)
                    .foregroundStyle(V8.C.ink4)
                TextField("重输一遍", text: $confirmCode)
                    .font(V8.T.body)
                    .foregroundStyle(V8.C.ink1)
                    .keyboardType(.numberPad)
                    .frame(minHeight: V8.H.min)
                    .padding(.horizontal, V8.S.gapM)
                    .background(V8.C.well, in: .rect(cornerRadius: V8.R.inset))
                    .autocorrectionDisabled()
                if !confirmCode.isEmpty && confirmCode != code {
                    Text("两次输入不一致 —— 下发前会被拦下来，不会带着错值发出去。")
                        .font(V8.T.footnote)
                        .foregroundStyle(V8.C.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    submit()
                } label: {
                    Text(isEdit ? "保存改造" : "写入台账")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.chipOn)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.accent))
                }
                .buttonStyle(.plain)
                .disabled(confirmCode != code || !codeValid || busy)
                .opacity((confirmCode != code || !codeValid || busy) ? 0.45 : 1)
                .padding(.top, V8.S.gapS)
                // 2026-11-05（减字 · 去重复）：这句与页面 lead **逐字相同**，
                // 而 lead 在同一屏顶部一直可见。同一句话在同一屏出现两次，删掉脚注这一份。
            }
        }
    }

    // MARK: - 步间导航（真拦：坏值出不了这一步）

    private var navRow: some View {
        HStack(spacing: V8.S.gapS) {
            if step > 0 {
                Button {
                    withAnimation(reduceMotion ? nil : V8.M.move) { step -= 1 }
                } label: {
                    Text("上一步")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.ink2)
                        .frame(minHeight: V8.H.min)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("上一步")
            }
            Spacer(minLength: 0)
            if step < 3 {
                Button {
                    advance()
                } label: {
                    Text(nextTitle)
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.chipOn)
                        .padding(.horizontal, V8.S.gapL)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.accent))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(nextTitle)
            }
        }
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
            if app.currentKeychain == nil {
                errorText = "还没有添加门锁 —— 先在「门」页添加一把锁，再回来创建凭证。"
                return
            }
            if owner == nil && !app.members.filter({ !$0.archived }).isEmpty {
                errorText = "先选归属成员 —— 凭证必须知道归谁。"
                return
            }
            if kind == .fingerprint && name.isEmpty {
                name = "指纹 " + String(app.keys.filter { $0.kind == .fingerprint }.count + 1)
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
        withAnimation(reduceMotion ? nil : V8.M.move) { step += 1 }
    }

    // MARK: - 提交（写本机台账）

    private func submit() {
        guard !DB.isDecoy else {
            errorText = "空壳模式下不写入凭证 —— 先退出空壳再来。"
            return
        }
        guard !app.trialGuard else {
            errorText = "只读试验模式已开启：写入要往门锁下发，已停用。先到「安全」页关闭它。"
            return
        }
        guard !busy else { return }
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
            finalName = "指纹 " + String(app.keys.filter { $0.kind == .fingerprint }.count + 1)
        } else if kind == .temp {
            finalName = note.isEmpty ? "临时码 " + TimeFormat.dayShort(expiryMillis) : note
        } else {
            finalName = note.isEmpty ? "密码 " + String(app.keys.filter { $0.kind == .password }.count + 1) : note
        }
        if kind == .fingerprint {
            guard let kc = app.currentKeychain else { errorText = "还没有添加门锁"; return }
            busy = true
            fpCount = 0
            errorText = nil
            Task { @MainActor in
                ScreenCare.keepingAwake(true)
                defer { ScreenCare.keepingAwake(false) }
                let r = await app.enrollFingerprint(name: finalName, owner: ownerName, note: note) { n in
                    fpCount = n
                }
                busy = false
                switch r {
                case .success:
                    _ = kc
                    router.keysPath = []
                case .failure(let e):
                    errorText = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
                }
            }
            return
        }
        let df = DF.cached("yyyy-MM-dd HH:mm")
        let fromStr = df.string(from: Date())
        let toStr: String = {
            if kind == .temp { return df.string(from: Date(timeIntervalSince1970: Double(expiryMillis) / 1000)) }
            return "2118-12-31 23:59"
        }()
        busy = true
        errorText = nil
        let oldAlias: Int? = {
            guard let editingID, editingID.hasPrefix("pwd:") else { return nil }
            return Int(editingID.dropFirst(4))
        }()
        Task {
            let result = await app.addPassword(code, from: fromStr, to: toStr,
                                               owner: ownerName, note: finalName,
                                               replacingAlias: oldAlias)
            busy = false
            switch result {
            case .success:
                if let warn = app.lastError {
                    AppToast.shared.show(warn, tone: .warn)
                    app.lastError = nil
                }
                router.keysPath = []
            case .failure(let e):
                errorText = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
            }
        }
    }

    /// 归属成员 → 成员名。三种历史口径（id / 名字 / 旧数据）都认。
    private var ownerName: String? {
        guard let owner, !owner.isEmpty else { return nil }
        if let m = app.members.first(where: { $0.id == owner }) { return m.name }
        if let m = app.members.first(where: { $0.name == owner }) { return m.name }
        if let m = DB.member(owner) { return m.name }
        return owner
    }

    private func consumeRoute() {
        guard let context = router.consume(if: { if case .key = $0 { return true }; return false }),
              case .key(let id) = context else { return }
        guard let existing = app.keys.first(where: { $0.id == id }) else { return }
        editingID = id
        kindIndex = kinds.firstIndex(of: existing.kind) ?? 0
        owner = existing.owner
        code = existing.code ?? ""
        name = existing.name
        note = existing.name
        step = 0
    }

    /// 剪贴板里正好是一串 6~8 位数字时直接填上，并标明来源。
    private func readClipboardOnce() {
        guard !isEdit, code.isEmpty else { return }
        guard let text = UIPasteboard.general.string else { return }
        let digits = text.filter { $0.isNumber }
        guard digits.count >= 6, digits.count <= 8 else { return }
        code = digits
        fromClipboard = true
    }

    // MARK: - 空壳 / 只读试验

    private var decoyCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "凭证工坊", statement: "空壳模式只读")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("空壳模式（胁迫码进入）下，成员与凭证信息都不显示，也不允许新建或改造凭证。")
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Text("退出空壳请在本机密码界面输入正常密码。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var trialCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "只读试验模式", statement: "写入类命令已停用")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("只读试验模式已开启：写入凭证要往门锁下发，会被护栏拦下。本机台账也不会写入。先到「安全」页关闭它再来。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapFootnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
