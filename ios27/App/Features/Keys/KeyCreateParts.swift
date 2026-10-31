// KeyCreateParts.swift —— 工坊四步的四个视图（extension，与主文件同一份状态）。
//
// 拆开的理由：主文件只留导航与提交逻辑，每一步的形状在这里，读起来是一步一块。
import SwiftUI

extension KeyCreateScreen {

    // 减弱动态：四步视图住在扩展里，环境值由主文件（KeyCreateScreen.swift）声明，
    // 扩展直接读同一个属性 —— extension 不能声明存储属性，所以不在这一侧重复声明。

    // MARK: 第一步：类型与归属

    var typeStep: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "这一枚是什么")
                KeysChips(items: kinds, title: { $0.rawValue }, selection: Binding(
                    get: { kind },
                    set: { kindIndex = kinds.firstIndex(of: $0) ?? 0 }
                ))
                Text(kindHint)
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text2)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().overlay(V.C.hairline)

                // 来源：原 App/UI/CredentialOtp.swift「临时密码 (ZOTP)」独立入口。
                // 动态密码不是一条台账凭证，而是按窗口现算的六位码 —— 单独一页，工坊这里只放入口。
                VSectionLabel(text: "动态密码", trailing: "ZOTP")
                KeysInlineNote(tone: .neutral, text: "按锁端周期自动更换的 6 位临时码，不用提前添加凭证。适合给快递、访客当场报码。")
                Button {
                    router.request(.dest(.zotp))
                } label: {
                    HStack(spacing: V.S.gapS) {
                        Image(systemName: "clock.badge.questionmark")
                            .accessibilityHidden(true)
                            .font(V.F.icon15)
                        Text("打开动态密码")
                            .font(V.F.bodyStrong)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .accessibilityHidden(true)
                            .font(V.F.icon15Medium)
                    }
                    .foregroundStyle(V.C.text1)
                    .frame(minHeight: V.Hit.min)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开动态密码")

                Divider().overlay(V.C.hairline)

                VSectionLabel(text: "归谁", trailing: owner ?? "必选")
                let active = app.members.filter { !$0.archived }
                if active.isEmpty {
                    KeysInlineNote(tone: .attention, text: "还没有成员。先去「家」建一位成员；也可以先用未归属把凭证建起来。")
                    Button {
                        owner = nil
                        errorText = nil
                        withAnimation(reduceMotion ? nil : V.M.move) { step = 1 }
                    } label: {
                        Text("先用未归属继续")
                            .font(V.F.bodyStrong)
                            .foregroundStyle(V.C.text1)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: V.Hit.min)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("先用未归属继续")
                } else {
                    VStack(spacing: V.S.gapXXS) {
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
        .padding(.horizontal, V.S.pageGutter)
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
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                if kind == .fingerprint {
                    VSectionLabel(text: "指纹没有码值")
                    KeysInlineNote(tone: .neutral, text: "指纹录入要在门锁的指纹头上按 8 次（锁端命令 cmd13 启动、cmd14 确认）。本机这条链路还没接，下一步先把这条登记进台账。")
                    TextField("给这枚指纹起个名字", text: $name)
                        .font(V.F.body)
                        .frame(minHeight: V.Hit.min)
                        .autocorrectionDisabled()
                } else {
                    VSectionLabel(text: "码值", trailing: codeValid ? "位数合规" : "6~8 位数字")
                    if !code.isEmpty {
                        VReading(value: String(repeating: "•", count: code.count), font: V.F.number26)
                    }
                    TextField("输入 6~8 位数字", text: $code)
                        .font(V.F.number20)
                        .keyboardType(.numberPad)
                        .frame(minHeight: V.Hit.min)
                        .autocorrectionDisabled()
                        .onChange(of: code) { _, new in
                            if errorText != nil { errorText = nil }
                            let filtered = new.filter { $0.isNumber }
                            if filtered != new { code = String(filtered.prefix(8)) }
                        }
                    if fromClipboard {
                        KeysInlineNote(tone: .attention, text: "这串数字是从剪贴板识别来的。不对就重填，别让一段旧密码混进来。")
                    }
                    HStack(spacing: V.S.gapS) {
                        ForEach([6, 7, 8], id: \.self) { digits in
                            Button {
                                code = KeysCode.digits(digits)
                                fromClipboard = false
                            } label: {
                                Text("生成 \(digits) 位")
                                    .font(V.F.footnote)
                                    .foregroundStyle(V.C.text1)
                                    .padding(.horizontal, V.S.gapMS)
                                    .frame(minHeight: V.Hit.min)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: V.R.control, style: .continuous)
                                            .strokeBorder(V.C.hairline, lineWidth: V.S.hair)
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
        .padding(.horizontal, V.S.pageGutter)
    }

    var strengthRow: some View {
        HStack(spacing: V.S.gapS) {
            HStack(spacing: V.S.gapXXS) {
                ForEach(0 ..< 3, id: \.self) { index in
                    Capsule()
                        .fill(index < strength.score ? (strength.score <= 1 ? V.C.warning : V.C.blue) : V.C.cardAlt)
                        .frame(width: V.Icon.l, height: V.S.gapXS)
                }
            }
            .accessibilityHidden(true)
            Text(strength.hint)
                .font(V.F.unit)
                .foregroundStyle(strength.score <= 1 ? V.C.warning : V.C.text2)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("密码强度：\(strength.hint)")
    }

    /// 重复 / 前缀冲突 / 弱口令：全部走 Engine 的同一套判据（CredentialOrg），页面不再各写一份。
    @ViewBuilder
    var duplicateNote: some View {
        let mac = app.currentMac
        if let weak = CredentialOrg.weakReason(code), codeValid {
            KeysInlineNote(tone: .attention, text: "弱口令：\(weak) —— 建议换一串更难猜的数字。")
        }
        if !mac.isEmpty, codeValid {
            let excluding = Int(String(editingID?.split(separator: ":").last ?? "")) ?? 0
            let same = CredentialOrg.duplicatePwdValues(mac, code, excluding: excluding)
            let otherLocks = CredentialOrg.duplicatePwdLockNames(code, excludingMac: mac)
            let prefix = CredentialOrg.prefixConflict(mac, code, excluding: excluding)
            if !same.isEmpty {
                KeysInlineNote(tone: .attention, text: "本机台账里已经有 \(same.count) 枚密码用了同一串数字（#\(same[0].alias)）。同一把锁上重复，等于多留一条能被猜中的入口。")
            } else if !otherLocks.isEmpty {
                KeysInlineNote(tone: .attention, text: "另外 \(otherLocks.count) 把锁（\(otherLocks.joined(separator: "、"))）也用了同一串数字 —— 一处泄露会牵连多扇门。")
            } else if let clash = prefix.first {
                KeysInlineNote(tone: .attention, text: "前 4 位和密码 #\(clash.alias) 一样，口头转述时容易说混。")
            }
        }
    }

    // MARK: 第三步：有效期与备注

    var periodStep: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "有效期", trailing: kind == .temp ? "到期自动失效" : "长期有效")
                if kind == .temp {
                    HStack(spacing: V.S.gapS) {
                        ForEach([1, 3, 7, 30], id: \.self) { days in
                            Button {
                                durationDays = days
                            } label: {
                                Text("\(days) 天")
                                    .font(V.F.footnote)
                                    .foregroundStyle(V.C.text1)
                                    .padding(.horizontal, V.S.gapMS)
                                    .frame(minHeight: V.Hit.min)
                                    .background(durationDays == days ? V.C.blue.opacity(0.16) : V.C.cardAlt, in: .capsule)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("有效期 \(days) 天")
                            .accessibilityAddTraits(durationDays == days ? [.isSelected] : [])
                        }
                        Spacer(minLength: 0)
                    }
                    VReadingGrid(items: [
                        .init(label: "生效", value: TimeFormat.dayShort(KeysState.now())),
                        .init(label: "到期", value: TimeFormat.dayShort(expiryMillis)),
                    ])
                } else {
                    Text(kind == .fingerprint
                         ? "指纹一直有效，除非你在详情里停用它。"
                         : "长期密码没有到期点；要限期就回第一步改成临时码。")
                        .font(V.F.body)
                        .foregroundStyle(V.C.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().overlay(V.C.hairline)

                VSectionLabel(text: "备注")
                TextField("给谁 · 哪扇门 · 用多久", text: $note)
                    .font(V.F.body)
                    .frame(minHeight: V.Hit.min)
                    .autocorrectionDisabled()
                HStack(spacing: V.S.gapS) {
                    ForEach(["仅白天", "勿外传", "长期有效"], id: \.self) { phrase in
                        Button {
                            note = note.isEmpty ? phrase : note + " · " + phrase
                        } label: {
                            Text(phrase)
                                .font(V.F.footnote)
                                .foregroundStyle(V.C.text2)
                                .padding(.horizontal, V.S.gapMS)
                                .frame(minHeight: V.Hit.min)
                                .background(V.C.cardAlt, in: .capsule)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("追加短语 \(phrase)")
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, V.S.pageGutter)
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
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "即将写入")
                VFieldRow(label: "类型", value: kind.rawValue, mono: false)
                VFieldRow(label: "归属", value: owner ?? "未归属", mono: false)
                VFieldRow(label: "码值", value: kind == .fingerprint ? "无（按指纹）" : String(repeating: "•", count: code.count), mono: false)
                VFieldRow(label: "到期", value: kind == .temp ? TimeFormat.dayShort(expiryMillis) : "永久")
                if !note.isEmpty {
                    VFieldRow(label: "备注", value: note, mono: false)
                }
                Divider().overlay(V.C.hairline)
                if kind == .fingerprint {
                    KeysInlineNote(tone: .attention, text: "本机链路未接，这一步只把这条登记进台账（待录入）。连上锁后再去门锁上按 8 次。")
                    VActionButton(title: isEdit ? "保存改造" : "记入本机台账", systemImage: "key.fill") {
                        submit()
                    }
                } else {
                    VSectionLabel(text: "再输一遍码值")
                    TextField("重输一遍", text: $confirmCode)
                        .font(V.F.number18)
                        .keyboardType(.numberPad)
                        .frame(minHeight: V.Hit.min)
                        .autocorrectionDisabled()
                    if !confirmCode.isEmpty && confirmCode != code {
                        KeysInlineNote(tone: .critical, text: "两次输入不一致 —— 下发前会被拦下来，不会带着错值发出去。")
                    }
                    if let errorText {
                        KeysInlineNote(tone: .critical, text: errorText)
                    }
                    VActionButton(title: isEdit ? "保存改造" : "写入台账", systemImage: "key.fill") {
                        submit()
                    }
                    .disabled(confirmCode != code || !codeValid)
                    Text("写入会真下发到门锁（cmd0A 添加 + 0B 设有效期）；回执成功才记入本机台账，失败会留在这一页报原因。")
                        .font(V.F.unit)
                        .foregroundStyle(V.C.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }
}