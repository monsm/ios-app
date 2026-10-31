// KeyCreateParts.swift —— 工坊四步的四个视图（extension，与主文件同一份状态）。
//
// 拆开的理由：主文件只留导航与提交逻辑，每一步的形状在这里，读起来是一步一块。
import SwiftUI

extension KeyCreateScreen {

    // 减弱动态：四步视图住在扩展里，环境值由主文件（KeyCreateScreen.swift）声明，
    // 扩展直接读同一个属性 —— extension 不能声明存储属性，所以不在这一侧重复声明。

    // MARK: 第一步：类型与归属

    var typeStep: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "这一枚是什么")
                KeysChips(items: kinds, title: { $0.rawValue }, selection: Binding(
                    get: { kind },
                    set: { kindIndex = kinds.firstIndex(of: $0) ?? 0 }
                ))
                Text(kindHint)
                    .font(T.F.caption)
                    .foregroundStyle(Ink.inkSub)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().overlay(Ink.hairline)

                SectionLabel(text: "归谁", trailing: owner ?? "必选")
                let active = app.members.filter { !$0.archived }
                if active.isEmpty {
                    KeysInlineNote(tone: .attention, text: "还没有成员。先去「家」建一位成员；也可以先用未归属把凭证建起来。")
                    Button {
                        owner = nil
                        errorText = nil
                        withAnimation(reduceMotion ? nil : T.M.move) { step = 1 }
                    } label: {
                        Text("先用未归属继续")
                            .font(T.F.bodyStrong)
                            .foregroundStyle(Ink.ink)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: T.Hit.min)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("先用未归属继续")
                } else {
                    VStack(spacing: T.S.xxs) {
                        ForEach(active) { member in
                            KeysOwnerRow(
                                name: member.name,
                                keyCount: app.keys.filter { $0.owner == member.name }.count,
                                selected: owner == member.name
                            ) {
                                owner = member.name
                                errorText = nil
                            }
                        }
                    }
                }
                if let errorText {
                    KeysInlineNote(tone: .critical, text: errorText)
                }
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    var kindHint: String {
        switch kind {
        case .password: return "6~8 位数字，长期有效。家人报一串数字就能开门。"
        case .temp: return "有起止时间的临时码。到期后门锁自己拒绝，不用回来手动停用。"
        case .fingerprint: return "指纹在门锁上按 8 次录入，没有码值。录入要门锁在场。"
        case .mobile: return "手机钥匙在「手机钥匙」页签发，这里不建。"
        }
    }

    // MARK: 第二步：码值

    var codeStep: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                if kind == .fingerprint {
                    SectionLabel(text: "指纹没有码值")
                    KeysInlineNote(tone: .neutral, text: "指纹录入要在门锁的指纹头上按 8 次（锁端命令 cmd13 启动、cmd14 确认）。本机这条链路还没接，下一步先把这条登记进台账。")
                    TextField("给这枚指纹起个名字", text: $name)
                        .font(T.F.body)
                        .frame(minHeight: T.Hit.min)
                        .autocorrectionDisabled()
                } else {
                    SectionLabel(text: "码值", trailing: codeValid ? "位数合规" : "6~8 位数字")
                    if !code.isEmpty {
                        Reading(value: String(repeating: "•", count: code.count), size: 26)
                    }
                    TextField("输入 6~8 位数字", text: $code)
                        .font(T.F.reading(20, weight: .medium))
                        .keyboardType(.numberPad)
                        .frame(minHeight: T.Hit.min)
                        .autocorrectionDisabled()
                        .onChange(of: code) { _, new in
                            if errorText != nil { errorText = nil }
                            let filtered = new.filter { $0.isNumber }
                            if filtered != new { code = String(filtered.prefix(8)) }
                        }
                    if fromClipboard {
                        KeysInlineNote(tone: .attention, text: "这串数字是从剪贴板识别来的。不对就重填，别让一段旧密码混进来。")
                    }
                    HStack(spacing: T.S.s) {
                        ForEach([6, 7, 8], id: \.self) { digits in
                            Button {
                                code = KeysCode.digits(digits)
                                fromClipboard = false
                            } label: {
                                Text("生成 \(digits) 位")
                                    .font(T.F.caption)
                                    .foregroundStyle(Ink.ink)
                                    .padding(.horizontal, T.S.m)
                                    .frame(minHeight: T.Hit.min)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: T.R.control, style: .continuous)
                                            .strokeBorder(Ink.hairline, lineWidth: T.Stroke.hair)
                                    }
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("本地生成 \(digits) 位数字码")
                        }
                        Spacer(minLength: 0)
                    }
                    if !code.isEmpty {
                        strengthRow
                    }
                    duplicateNote
                }
                if let errorText {
                    KeysInlineNote(tone: .critical, text: errorText)
                }
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    var strengthRow: some View {
        HStack(spacing: T.S.s) {
            HStack(spacing: T.S.xxs) {
                ForEach(0 ..< 3, id: \.self) { index in
                    Capsule()
                        .fill(index < strength.score ? (strength.score <= 1 ? State.attention : Signal.base) : Ink.plateAlt)
                        .frame(width: T.Icon.l, height: T.S.xs)
                }
            }
            .accessibilityHidden(true)
            Text(strength.hint)
                .font(T.F.unit)
                .foregroundStyle(strength.score <= 1 ? State.attention : Ink.inkSub)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("密码强度：\(strength.hint)")
    }

    /// 重复与前缀冲突：同值查本锁台账，前 4 位相同提示口头易混。
    @ViewBuilder
    var duplicateNote: some View {
        let same = codeValid ? app.keys.filter { $0.code == code && $0.id != editingID } : []
        if let first = same.first {
            KeysInlineNote(tone: .attention, text: "本机台账里已经有 \(same.count) 枚凭证用了同一串数字（\(first.name)）。同一把锁上重复，等于多留一条能被猜中的入口。")
        } else if codeValid {
            let prefixClash = app.keys.first { key in
                guard let other = key.code, other.count >= 4, code.count >= 4, key.id != editingID else { return false }
                return other.prefix(4) == code.prefix(4)
            }
            if let clash = prefixClash {
                KeysInlineNote(tone: .attention, text: "前 4 位和「\(clash.name)」一样，口头转述时容易说混。")
            }
        }
    }

    // MARK: 第三步：有效期与备注

    var periodStep: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "有效期", trailing: kind == .temp ? "到期自动失效" : "长期有效")
                if kind == .temp {
                    HStack(spacing: T.S.s) {
                        ForEach([1, 3, 7, 30], id: \.self) { days in
                            Button {
                                durationDays = days
                            } label: {
                                Text("\(days) 天")
                                    .font(T.F.caption)
                                    .foregroundStyle(Ink.ink)
                                    .padding(.horizontal, T.S.m)
                                    .frame(minHeight: T.Hit.min)
                                    .background(durationDays == days ? Signal.wash : Ink.plateAlt, in: .capsule)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("有效期 \(days) 天")
                            .accessibilityAddTraits(durationDays == days ? [.isSelected] : [])
                        }
                        Spacer(minLength: 0)
                    }
                    ReadingGrid(items: [
                        .init(label: "生效", value: TimeFormat.dayShort(KeysState.now())),
                        .init(label: "到期", value: TimeFormat.dayShort(expiryMillis)),
                    ])
                } else {
                    Text(kind == .fingerprint
                         ? "指纹一直有效，除非你在详情里停用它。"
                         : "长期密码没有到期点；要限期就回第一步改成临时码。")
                        .font(T.F.body)
                        .foregroundStyle(Ink.inkSub)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().overlay(Ink.hairline)

                SectionLabel(text: "备注")
                TextField("给谁 · 哪扇门 · 用多久", text: $note)
                    .font(T.F.body)
                    .frame(minHeight: T.Hit.min)
                    .autocorrectionDisabled()
                HStack(spacing: T.S.s) {
                    ForEach(["仅白天", "勿外传", "长期有效"], id: \.self) { phrase in
                        Button {
                            note = note.isEmpty ? phrase : note + " · " + phrase
                        } label: {
                            Text(phrase)
                                .font(T.F.caption)
                                .foregroundStyle(Ink.inkSub)
                                .padding(.horizontal, T.S.m)
                                .frame(minHeight: T.Hit.min)
                                .background(Ink.plateAlt, in: .capsule)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("追加短语 \(phrase)")
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    var expiryMillis: Int64 {
        let cal = TimeFormat.calendar
        let base = cal.startOfDay(for: Date())
        let shifted = cal.date(byAdding: .day, value: durationDays, to: base) ?? base
        let end = cal.date(byAdding: .second, value: 86399, to: shifted) ?? shifted
        return Int64(end.timeIntervalSince1970 * 1000)
    }

    // MARK: 第四步：确认与二次输入

    var confirmStep: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "即将写入")
                FieldRow(label: "类型", value: kind.rawValue, mono: false)
                FieldRow(label: "归属", value: owner ?? "未归属", mono: false)
                FieldRow(label: "码值", value: kind == .fingerprint ? "无（按指纹）" : String(repeating: "•", count: code.count), mono: false)
                FieldRow(label: "到期", value: kind == .temp ? TimeFormat.dayShort(expiryMillis) : "永久")
                if !note.isEmpty {
                    FieldRow(label: "备注", value: note, mono: false)
                }
                Divider().overlay(Ink.hairline)
                if kind == .fingerprint {
                    KeysInlineNote(tone: .attention, text: "本机链路未接，这一步只把这条登记进台账（待录入）。连上锁后再去门锁上按 8 次。")
                    PrimaryAction(title: isEdit ? "保存改造" : "记入本机台账", systemImage: "key.fill") {
                        submit()
                    }
                } else {
                    SectionLabel(text: "再输一遍码值")
                    TextField("重输一遍", text: $confirmCode)
                        .font(T.F.reading(18, weight: .medium))
                        .keyboardType(.numberPad)
                        .frame(minHeight: T.Hit.min)
                        .autocorrectionDisabled()
                    if !confirmCode.isEmpty && confirmCode != code {
                        KeysInlineNote(tone: .critical, text: "两次输入不一致 —— 下发前会被拦下来，不会带着错值发出去。")
                    }
                    if let errorText {
                        KeysInlineNote(tone: .critical, text: errorText)
                    }
                    PrimaryAction(title: isEdit ? "保存改造" : "写入台账", systemImage: "key.fill") {
                        submit()
                    }
                    .disabled(confirmCode != code || !codeValid)
                    Text("写入后这条会出现在钥匙台账里。锁端下发链路未接，页面上不会假装已经发到锁。")
                        .font(T.F.unit)
                        .foregroundStyle(Ink.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, T.S.gutter)
    }
}