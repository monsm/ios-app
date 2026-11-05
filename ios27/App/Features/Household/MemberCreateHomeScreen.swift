// MemberCreateHomeScreen.swift —— 建档向导（V8 设计语言）
//
// 与 MemberCreateScreen 的能力对齐：四步真序列（01 称呼 → 02 角色 → 03 档案 → 04 初始凭证）。
// 数据仍走 Engine：DB.addMember 落 kf_members；档案扩展走 MemberHub.saveExt（kf_member_ext）；
// 第四步的临时码走 AppModel.addTempCode（cmd0A 真下发 → 成功才写台账）。
//
// 与旧页的刻意差异：
//   ① 空壳模式（胁迫码）下整页停用 —— DB.addMember 会返回 nil，旧页会把它误报成「已有同名成员」。
//   ② 只读试验模式（app.trialGuard）下关掉「顺路建临时码」：下发会被 ZKProtocol.assertReadOnly 拦下，
//      与其让用户走一遍必然失败的链路，不如在入口说清。
import SwiftUI
import UIKit

struct MemberCreateHomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    @State private var step = 0
    @State private var name = ""
    @State private var emoji = ""
    @State private var role: MemberCard.Role = .member
    @State private var remark = ""
    @State private var relation = ""
    @State private var groupTag = ""
    @State private var emergency = ""
    @State private var makeCode = false
    @State private var code = ""
    @State private var newID: String?
    @State private var errorLine: String?
    @State private var creating = false
    @State private var confirmCancel = false

    private var roster: HouseholdRoster { HouseholdRoster.shared }
    private var decoyed: Bool { DB.isDecoy }
    private var readOnly: Bool { app.trialGuard }

    private static let steps: [(no: String, title: String, hint: String)] = [
        ("01", "称呼与代号", "名字会出现在每一条台账上，所以先定称呼。"),
        ("02", "角色与备注", "角色决定这台手机上 TA 能做什么；备注只影响记录怎么显示。"),
        ("03", "档案", "关系、分组、紧急联系 —— 这一档纯本机，不上锁。"),
        ("04", "初始凭证", "顺路建一张 10 分钟临时码，或稍后到「钥匙」页再配。")
    ]

    private var current: (no: String, title: String, hint: String) { Self.steps[step] }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private var nameOK: Bool {
        let n = trimmedName
        guard !n.isEmpty, n.count <= 20 else { return false }
        return n.allSatisfy { $0.isLetter || $0.isNumber }
    }

    private var nameTaken: Bool {
        app.members.contains { $0.name == trimmedName && $0.id != newID }
    }

    private var codeOK: Bool {
        code.count >= 6 && code.count <= 8 && code.allSatisfy { $0.isNumber }
    }

    /// 同 HouseholdScreen.atLimit：只数**在册**成员 —— 归档不占名额。
    private var atLimit: Bool { HHStats.active(app.members).count >= HHStats.memberLimit }

    private var canAdvance: Bool {
        if decoyed { return false }
        switch step {
        case 0: return nameOK && !nameTaken && !atLimit
        case 3: return !makeCode || codeOK
        default: return true
        }
    }

    private var judgement: String {
        if decoyed { return "空壳模式下不建档" }
        if atLimit { return "已到本机成员上限" }
        return "第 \(step + 1) 步 · " + current.title
    }

    private var lead: String {
        if decoyed {
            return DecoyCopy.notProvided("建档会写真实的 kf_members")
        }
        return current.hint + "这一页不连门锁；只有第 4 步的临时码要下发。"
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            if decoyed {
                EmptyView()
            } else {
                stepChips
            }
        } content: {
            if decoyed {
                decoyCard
            } else {
                if atLimit {
                    VFailure(
                        what: "已到本机成员上限",
                        why: "本机最多 \(HHStats.memberLimit) 位在册成员，归档的不占名额。",
                        next: "先到「家」的归档页把不用的成员归档，再回来建新人。"
                    )
                } else {
                    stepCard
                    if step == 3 { codeCard }
                    if let errorLine {
                        VFailure(
                            what: "这一步没有完成",
                            why: errorLine,
                            next: "按上面的提示处理后重试；已经写下的档案不会丢。"
                        )
                    }
                    actionCard
                    cancelNote
                }
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("取消") { askCancel() }
                    .disabled(creating)
                    .opacity(creating ? 0.45 : 1)
                    .accessibilityLabel("取消建档")
            }
        }
        .v8Confirm(
            isPresented: $confirmCancel,
            title: "取消建档？",
            consequence: cancelConsequence,
            confirmTitle: "取消并撤回",
            isDestructive: true
        ) {
            cancel()
        }
    }

    // MARK: - 四步芯片

    private var stepChips: some View {
        VHScroll {
            HStack(spacing: V8.S.gapChip) {
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, item in
                    VChip2(
                        icon: .ring(stepFraction(index), stepTint(index)),
                        label: "第 \(index + 1) 步",
                        value: item.no + " · " + item.title
                    )
                }
            }
            .padding(.leading, V8.S.gutterCard)
            .padding(.trailing, V8.S.gutterCard)
        }
        .scrollClipDisabled()
    }

    private func stepFraction(_ index: Int) -> Double {
        if index < step { return 1 }
        if index == step { return 0.5 }
        return 0.02
    }

    private func stepTint(_ index: Int) -> Color {
        if index < step { return V8.C.ok }
        if index == step { return V8.C.accent }
        return V8.C.ink4
    }

    // MARK: - 当前步的输入

    private var stepCard: some View {
        VCard2 {
            // 2026-11-05（截图审查 · 设计冗余）：卡头写「01 · 称呼与代号」，而页首芯片写着
            // 「第 1 步 / 01 · 称呼与代号」、页面大标题写着「第 1 步 · 称呼与代号」——
            // 同一个步骤名一屏内三次。卡内输入框自带标签（称呼 / emoji 代号），卡头不再重复；
            // 「必填 / 可选」移到字段标签上，信息不丢。
            VStack(alignment: .leading, spacing: V8.S.gapM) {
                stepBody
            }
        }
    }

    @ViewBuilder
    private var stepBody: some View {
        if step == 0 {
            fieldRow("称呼 · 必填", text: $name, placeholder: "汉字 / 英文 / 数字，上限 20 字")
            if !name.isEmpty && !nameOK {
                Text("称呼只接受汉字、英文、数字，且不超过 20 字。")
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.warn)
                    .fixedSize(horizontal: false, vertical: true)
            } else if nameTaken {
                Text("已经有同名成员了 —— 换个称呼，或到那位成员的 360 里用「合并」把两个名字并成一个。")
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            emojiPicker
                .padding(.top, V8.S.gapS)
        } else if step == 1 {
            VStack(spacing: 0) {
                ForEach(Array(MemberCard.Role.allCases.enumerated()), id: \.offset) { index, item in
                    if index > 0 { VDotRule() }
                    roleRow(item)
                }
            }
            fieldRow("备注名", text: $remark, placeholder: "记录条目显示「称呼（备注）」")
        } else if step == 2 {
            fieldRow("与你的关系", text: $relation, placeholder: "母亲 / 妹妹 / 钟点工")
            fieldRow("分组标签", text: $groupTag, placeholder: "家人 / 访客 / 服务人员")
            fieldRow("紧急联系", text: $emergency, placeholder: "姓名 + 电话")
        } else {
            Toggle(isOn: Binding(
                get: { makeCode && !readOnly },
                set: { on in makeCode = on && !readOnly }
            )) {
                VStack(alignment: .leading, spacing: V8.S.gapXS) {
                    Text("顺路建 10 分钟临时码")
                        .font(V8.T.value)
                        .foregroundStyle(readOnly ? V8.C.ink4 : V8.C.ink1)
                    Text(readOnly
                         ? "只读试验模式开着 —— 临时码会被锁端护栏拦下，这一步先不建。"
                         : "下发到当前门锁，归属自动记为 TA。不建也行。")
                        .font(V8.T.caption)
                        .foregroundStyle(V8.C.ink4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minHeight: V8.H.min)
            .disabled(readOnly)
        }
    }

    private func fieldRow(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: V8.S.gapXS) {
            Text(label)
                .font(V8.T.label)
                .foregroundStyle(V8.C.ink4)
            TextField(placeholder, text: text)
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink1)
                .frame(minHeight: V8.H.min)
                .padding(.horizontal, V8.S.gapM)
                .background(V8.C.well, in: .rect(cornerRadius: V8.R.inset))
        }
    }

    private var emojiPicker: some View {
        VStack(alignment: .leading, spacing: V8.S.gapXS) {
            Text("emoji 代号")
                .font(V8.T.label)
                .foregroundStyle(V8.C.ink4)
            VHScroll {
                HStack(spacing: V8.S.gapS) {
                    ForEach(Self.emojiOptions.indices, id: \.self) { index in
                        emojiCell(Self.emojiOptions[index])
                    }
                }
            }
        }
    }

    private static let emojiOptions = ["", "🐻", "🐱", "🐸", "🐙", "🦊", "🐧", "🐯"]

    private func emojiCell(_ e: String) -> some View {
        let on = emoji == e
        return Button {
            emoji = e
        } label: {
            Text(e.isEmpty ? "首字" : e)
                .font(e.isEmpty ? V8.T.caption : V8.T.body)
                .foregroundStyle(on ? V8.C.ink1 : V8.C.ink3)
                .frame(width: V8.S.gapXXL, height: V8.S.gapXXL)
                .background(on ? V8.C.accentTrack : V8.C.chipOff, in: Circle())
                .overlay(
                    Circle().strokeBorder(on ? V8.C.accent : V8.C.line, lineWidth: V8.S.hair)
                )
                .frame(minWidth: V8.H.min, minHeight: V8.H.min)
                .contentShape(Rectangle())
        }
        .buttonStyle(V8PressStyle())
        .accessibilityLabel(e.isEmpty ? "默认首字" : "代号 " + e)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func roleRow(_ item: MemberCard.Role) -> some View {
        let on = role == item
        return Button {
            role = item
        } label: {
            HStack(spacing: V8.S.gapM) {
                Image(systemName: roleSymbol(item))
                    .font(V8.T.caption)
                    .foregroundStyle(on ? V8.C.accent : V8.C.ink4)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: V8.S.gapXS) {
                    Text(item.rawValue)
                        .font(V8.T.value)
                        .foregroundStyle(V8.C.ink1)
                    Text(HHPerm.hint(item) + " · " + HHPerm.scene(item))
                        .font(V8.T.caption)
                        .foregroundStyle(V8.C.ink4)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: V8.S.gapS)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(V8.T.caption)
                    .foregroundStyle(on ? V8.C.accent : V8.C.ink4)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: V8.H.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(V8PressStyle())
        .accessibilityLabel("角色 " + item.rawValue + "，" + HHPerm.hint(item))
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func roleSymbol(_ role: MemberCard.Role) -> String {
        switch role {
        case .owner: return "crown"
        case .guest: return "person.badge.clock"
        case .member: return "person"
        }
    }

    // MARK: - 第四步：临时码

    private var codeCard: some View {
        VCard2 {
            VCardHead(eyebrow: "临时码", statement: makeCode ? "10 分钟" : "未启用", trailing: readOnly ? "只读试验模式" : "可选")
            VDivider2()
                .padding(.top, V8.S.gapM)
            if makeCode && !readOnly {
                fieldRow("6~8 位纯数字", text: $code, placeholder: "例如 482913")
                    .padding(.top, V8.S.gapM)
                if !code.isEmpty && !codeOK {
                    Text("临时码要 6~8 位纯数字；现在这串不会被下发。")
                        .font(V8.T.caption)
                        .foregroundStyle(V8.C.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VDataRow(tag: "有效期至", tagTint: V8.C.ink4, title: expiryText, value: "")
                    .padding(.top, V8.S.gapS)
                Text("到期后锁端自动失效，不需要再回来删。")
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(readOnly
                     ? "只读试验模式开着：临时码下发会被锁端护栏拦下。可以只完成建档，稍后关掉再补一枚。"
                     : "不建码也能完成建档 —— 之后到「钥匙」页新建一枚，归属选这个成员即可。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var expiryText: String {
        let at = Int64(Date().timeIntervalSince1970 * 1000) + 600_000
        return TimeDisplay.clock(at)
    }

    // MARK: - 步进

    private var actionCard: some View {
        VCard2(style: .well) {
            if step < 3 {
                Button {
                    advance()
                } label: {
                    Text("下一步")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.chipOn)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.accent))
                }
                .buttonStyle(V8PressStyle())
                .disabled(!canAdvance)
                .opacity(canAdvance ? 1 : 0.45)
                .accessibilityLabel("下一步")
            } else {
                Button {
                    finish()
                } label: {
                    Text(creating ? "正在建档…" : "完成建档")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.chipOn)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.accent))
                }
                .buttonStyle(V8PressStyle())
                .disabled(!canAdvance || creating)
                .opacity((canAdvance && !creating) ? 1 : 0.45)
                .accessibilityLabel("完成建档")
            }
            if step > 0 {
                Button {
                    step -= 1
                    errorLine = nil
                } label: {
                    Text("上一步")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.ink1)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .overlay(
                            RoundedRectangle(cornerRadius: V8.R.capsule(V8.H.min), style: .continuous)
                                .strokeBorder(V8.C.line, lineWidth: V8.S.hair)
                        )
                }
                .buttonStyle(V8PressStyle())
                .disabled(creating)
                .accessibilityLabel("上一步")
                .padding(.top, V8.S.gapS)
            }
            Text("第一步按「下一步」时才会真正建号；中途取消不会留下半个人（已建的号会在取消时一并撤回）。")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var cancelNote: some View {
        Text("称呼会出现在每一条台账上；角色与备注只影响本机界面。")
            .font(V8.T.caption)
            .foregroundStyle(V8.C.ink4)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 空壳

    private var decoyCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "新建成员", statement: "空壳模式不建档")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("空壳模式（胁迫码进入）下不建号、不写档案 —— 否则新成员会写进真实的 kf_members，成为真实数据的一部分。")
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink3)
                .lineSpacing(V8.L.body - V8.T.body.size)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Text("退出空壳请在本机密码界面输入正常密码。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 真动作

    private func advance() {
        guard canAdvance else { return }
        if step == 0 {
            guard create() else { return }
        }
        if step == 1 { writeProfile() }
        if step == 2 { writeProfile() }
        errorLine = nil
        step += 1
    }

    private func create() -> Bool {
        guard !decoyed else {
            errorLine = "空壳模式下不建档 —— 先退出空壳再回来。"
            return false
        }
        // 已经建过号（用户退回过第 1 步）就不再建第二个 —— 否则同一个人会在名册里出现两次。
        if newID != nil { return true }
        guard !atLimit else {
            errorLine = "已到本机成员上限 " + String(HHStats.memberLimit) + " 位。先归档一位，再回来建新人。"
            return false
        }
        guard nameOK else {
            errorLine = "称呼只接受汉字、英文、数字，且不超过 20 字。"
            return false
        }
        guard !nameTaken else {
            errorLine = "已经有同名成员了 —— 换个称呼，或到那位成员的 360 里合并。"
            return false
        }
        // 真建档走 Engine：DB.addMember 落 kf_members 并分配成员色。
        guard let created = DB.addMember(trimmedName) else {
            let trimmed = trimmedName.trimmingCharacters(in: .whitespacesAndNewlines)
            errorLine = trimmed.isEmpty
                ? "称呼不能为空 —— 回到第 1 步填一个再继续。"
                : "已经有同名成员了 —— 换个称呼，或到那位成员的 360 里合并。"
            return false
        }
        app.members.append(MemberCard(id: created.id, name: created.name, role: role, keyCount: 0,
                                      lastActiveAt: nil, archived: false))
        newID = created.id
        roster.focusMember = created.id
        roster.update(created.id) { $0.emoji = emoji }
        roster.mirrorRole(created.id, role)
        return true
    }

    /// 第二 / 三步的选择当场写进档案 —— 不在末步一次性补写（旧实现那里丢过用户选的档位）。
    private func writeProfile() {
        guard let id = newID, let i = app.members.firstIndex(where: { $0.id == id }) else { return }
        app.members[i] = app.members[i].hh(role: role)
        roster.update(id) { e in
            e.emoji = emoji
            e.remark = remark.trimmingCharacters(in: .whitespaces)
            e.relation = relation.trimmingCharacters(in: .whitespaces)
            e.groupTag = groupTag.trimmingCharacters(in: .whitespaces)
            e.emergency = emergency.trimmingCharacters(in: .whitespaces)
        }
    }

    private func finish() {
        guard canAdvance, let id = newID, !creating else { return }
        writeProfile()
        let memberName = trimmedName
        // 不建码：直接进成员 360。
        guard makeCode && codeOK && !readOnly else {
            roster.focusMember = id
            router.request(.dest(.memberDetail))
            return
        }
        // 建码要先有锁：没有门锁时如实说明「已建档、码未建」，不假装成功。
        guard app.lock != nil else {
            errorLine = "已建档，但临时码没建：本机还没有添加门锁。先到「门」页添加门锁，再回来补一枚。"
            return
        }
        creating = true
        errorLine = nil
        // 真链路：cmd0A 下发 10 分钟临时码 → 成功才写台账（temp=true + 归属）→ 刷新名册。
        Task { @MainActor in
            defer { creating = false }
            let df = DF.cached("yyyy-MM-dd HH:mm")
            let from = df.string(from: Date())
            let to = df.string(from: Date().addingTimeInterval(600))
            let r = await app.addTempCode(code, from: from, to: to,
                                          owner: memberName, note: "向导临时码 · " + memberName)
            switch r {
            case .success:
                app.reloadMembers()
                roster.focusMember = id
                // 建档已落库并下发成功：清掉 newID，避免用户返回本页再点「取消」时
                // cancel() 的「取消=回滚删除」分支把刚建好的成员删掉（凭证却留在台账里）。
                newID = nil
                router.request(.dest(.memberDetail))
            case .failure(let e):
                let msg = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
                errorLine = "已建档，但临时码没建成：" + msg + "（可到「钥匙」页重试）"
            }
        }
    }

    /// 取消不是「什么都不做」：第 1 步按过「下一步」就已经真的建了号，
    /// 取消会把刚建好的成员连同档案一起撤回 —— 这一步没有撤销入口，必须说清再动手。
    private var cancelConsequence: String {
        guard let id = newID else {
            return "还没有建号，取消只会回到「家」的名册，不留下任何东西。"
        }
        let name = app.members.first { $0.id == id }?.name ?? trimmedName
        return "「" + name + "」已经建好并写进本机成员表，取消会把它连同档案一起撤回（这一步没有撤销入口）。"
            + "如果已经下发过临时码，那条码也会失去归属。"
    }

    private func askCancel() {
        guard !creating else { return }
        confirmCancel = true
    }

    private func cancel() {
        guard !creating else { return }
        if let id = newID {
            app.members.removeAll { $0.id == id }
            DB.removeMember(id)
            roster.forget(id)
            if roster.dutyID() == id { roster.setDuty(nil) }
            roster.focusMember = nil
            // 向导第 4 步可能已生成过归这名成员的临时码，撤销建档后它就成了孤儿归属 ——
            // 只改 app.members 不动 app.keys 会一直显示旧归属。
            app.reloadKeys()
        }
        router.request(.tab(.household))
    }
}
