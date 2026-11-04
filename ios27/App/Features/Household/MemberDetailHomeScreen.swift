// MemberDetailHomeScreen.swift —— 成员 360（V8 设计语言）
//
// 与 MemberDetailScreen 的能力对齐：角色与权限矩阵 / 档案扩展 / 名下凭证 / 最近开门摘录 /
// 家庭场景（本周主责）/ 归档与删除 / 同名合并。
// 数据仍来自 AppModel.members + HouseholdRoster + app.entries；真值落 kf_member_ext、
// kf_duty_week 与 kf_members（电话）。
//
// 与旧页的刻意差异：
//   ① 空壳模式（胁迫码）整页不显示成员档案 —— 成员是本机真值，不是「锁端读不到就为空」那一类。
//   ② 旧页「只移除档案」与「连本机凭证一起移除」两个删除选项，实际都走 DB.removeMember（都会解除全部归属），
//      差别只在内存里的一份投影；这里统一成一个删除入口，并在确认里把三种真实后果一次写清。
import SwiftUI
import UIKit

struct MemberDetailHomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    @State private var draft = HHMemberExtras()
    @State private var phone = ""
    @State private var loadedID: String?
    @State private var confirmDelete = false
    @State private var saved = false
    @State private var callNote: String?
    @State private var showMerge = false

    private var roster: HouseholdRoster { HouseholdRoster.shared }
    private var decoyed: Bool { DB.isDecoy }

    private var member: MemberCard? {
        guard let id = roster.focusMember else { return nil }
        return app.members.first { $0.id == id }
    }

    private var judgement: String {
        if decoyed { return "空壳模式下不显示成员档案" }
        guard let member else { return "还没选成员" }
        if member.archived { return "「" + HHDisplay.name(member, extras: draft) + "」已归档" }
        return "「" + HHDisplay.name(member, extras: draft) + "」"
    }

    private var lead: String {
        if decoyed {
            return "空壳模式只隐藏数据，不改动数据。成员档案与名下凭证都不显示，也不写入。"
        }
        guard let member else {
            return "从「家」的成员名册里点一位成员进来，这里会显示 TA 的档案、凭证与权限。"
        }
        if member.archived { return "归档只收起名册与统计，历史一条不删。逐位可恢复，没有「全部恢复」。" }
        return "档案扩展只存本机，不写入门锁；角色矩阵管的是本机界面，锁端没有角色字段。"
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            if decoyed || member == nil {
                EmptyView()
            } else {
                chipRow
            }
        } content: {
            if decoyed {
                decoyCard
            } else if let member {
                weekCard(member)
                roleCard(member)
                profileCard(member)
                if let callNote {
                    VFailure(
                        what: "这一通电话没有拨出去",
                        why: callNote,
                        next: "把号码改到系统能接受的形状（纯数字、至少 3 位），再点一次「呼叫」。"
                    )
                }
                keysCard(member)
                excerptsCard(member)
                sceneCard(member)
                closingCard(member)
                if !MemberMergeKit.candidates(primaryID: member.id).isEmpty {
                    mergeCard
                }
            } else {
                VEmpty(
                    title: "还没选成员",
                    reason: "从「家」的成员名册里点一位成员进来，这里会显示 TA 的档案、凭证与权限。",
                    actionTitle: "回到名册"
                ) { router.request(.tab(.household)) }
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let ctx = router.consume(if: { if case .member = $0 { return true }; return false }),
               case .member(let id) = ctx {
                roster.focusMember = id
            }
            load()
        }
        .sheet(isPresented: $showMerge) {
            if let member { MemberMergeSheet(primary: member) }
        }
    }

    // MARK: - 芯片行

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: V8.S.gapChip) {
                VChip2(icon: .glyph(roleSymbol(member?.role ?? .member)), label: "角色", value: member?.role.rawValue ?? "未选")
                VChip2(icon: .ring(1, V8.D.fingerprint), label: "凭证", value: "\(member?.keyCount ?? 0) 枚")
                VChip2(icon: .ring(0.5, V8.C.info), label: "最近", value: member.map { HHStats.lastOpen($0) } ?? "—")
                VChip2(icon: .ring(isDuty ? 1 : 0.02, V8.C.ok), label: "本周主责", value: isDuty ? "是" : "否")
            }
            .padding(.leading, V8.S.gutterCard)
            .padding(.trailing, V8.S.gutterCard)
        }
        .scrollClipDisabled()
    }

    private var isDuty: Bool {
        guard let member else { return false }
        return roster.dutyID() == member.id
    }

    private func roleSymbol(_ role: MemberCard.Role) -> String {
        switch role {
        case .owner: return "crown"
        case .guest: return "person.badge.clock"
        case .member: return "person"
        }
    }

    // MARK: - 卡 1 这一周

    private func weekCard(_ member: MemberCard) -> some View {
        VCard2 {
            VCardHead(eyebrow: "这一周", statement: HHStats.weekSentence(member, entries: app.entries) ?? "还没有可证明归属的开门", trailing: "约")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("锁端日志没有身份字段，只有归属明确的条目才会算进来。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Text("这一页只读本机数据，不连门锁 —— 离线或未连接时，档案与摘录完全一样。")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapXS)
                .fixedSize(horizontal: false, vertical: true)
            VNavRow(title: "去台账看全部记录", detail: "按 TA 筛一遍") {
                router.request(.dest(.records))
            }
            .padding(.top, V8.S.gapS)
        }
    }

    // MARK: - 卡 2 角色与权限

    private func roleCard(_ member: MemberCard) -> some View {
        VCard2 {
            VCardHead(eyebrow: "角色与权限", statement: "本机判据", trailing: "三档")
            VDivider2()
                .padding(.top, V8.S.gapM)
            HStack(spacing: V8.S.gapS) {
                ForEach(MemberCard.Role.allCases, id: \.self) { role in
                    roleChip(role, current: member.role)
                }
            }
            .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                ForEach(Array(HHPerm.rows.enumerated()), id: \.offset) { index, cap in
                    if index > 0 { VDotRule() }
                    permRow(cap, role: member.role)
                }
            }
            .padding(.top, V8.S.gapM)
            Text(HHPerm.scene(member.role))
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Text("矩阵管的是本机界面：锁端没有角色字段，这三档不改任何发往门锁的字节，备份包也不带角色。")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
            VDivider2()
                .padding(.top, V8.S.gapM)
            Toggle(isOn: Binding(
                get: { draft.emergencyAdmin },
                set: { v in
                    draft.emergencyAdmin = v
                    roster.update(member.id) { $0.emergencyAdmin = v }
                }
            )) {
                VStack(alignment: .leading, spacing: V8.S.gapXS) {
                    Text("紧急管理员")
                        .font(V8.T.value)
                        .foregroundStyle(V8.C.ink1)
                    Text(HHPerm.allows(member.role, "成员管理")
                         ? "把人点出来，免得只剩一个人管钥匙。"
                         : "角色是「" + member.role.rawValue + "」，矩阵里「成员管理」禁用 —— 先把角色改成管理员。")
                        .font(V8.T.caption)
                        .foregroundStyle(V8.C.ink4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minHeight: V8.H.min)
            .disabled(!HHPerm.allows(member.role, "成员管理"))
            .padding(.top, V8.S.gapS)
        }
    }

    private func roleChip(_ role: MemberCard.Role, current: MemberCard.Role) -> some View {
        let on = role == current
        return Button {
            setRole(role)
        } label: {
            HStack(spacing: V8.S.gapXS) {
                Image(systemName: roleSymbol(role))
                    .font(V8.T.caption)
                    .foregroundStyle(on ? V8.C.accent : V8.C.ink4)
                    .accessibilityHidden(true)
                Text(role.rawValue)
                    .font(V8.T.tab)
                    .foregroundStyle(on ? V8.C.ink1 : V8.C.ink3)
            }
            .padding(.horizontal, V8.S.gapM)
            .frame(minHeight: V8.H.min)
            .background(Capsule(style: .continuous).fill(on ? V8.C.accentTrack : V8.C.chipOff))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(on ? V8.C.accent : V8.C.line, lineWidth: V8.S.hair)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("角色 " + role.rawValue)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func permRow(_ cap: String, role: MemberCard.Role) -> some View {
        let allowed = HHPerm.allows(role, cap)
        return HStack(spacing: V8.S.gapM) {
            Text(cap)
                .font(V8.T.value)
                .foregroundStyle(V8.C.ink1)
            Spacer(minLength: V8.S.gapS)
            Image(systemName: allowed ? "checkmark.circle" : "xmark.circle")
                .font(V8.T.caption)
                .foregroundStyle(allowed ? V8.C.ok : V8.C.ink4)
                .accessibilityHidden(true)
            Text(allowed ? "允许" : "禁用")
                .font(V8.T.caption)
                .foregroundStyle(allowed ? V8.C.ok : V8.C.ink4)
        }
        .frame(minHeight: V8.S.rowHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cap + "，" + (allowed ? "允许" : "禁用"))
    }

    // MARK: - 卡 3 档案

    private func profileCard(_ member: MemberCard) -> some View {
        VCard2 {
            VCardHead(eyebrow: "档案", statement: saved ? "已保存" : "本机档案", trailing: "不上锁")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(alignment: .leading, spacing: V8.S.gapM) {
                fieldRow("与你的关系", text: $draft.relation, placeholder: "母亲 / 妹妹 / 钟点工")
                fieldRow("备注名", text: $draft.remark, placeholder: "记录条目显示「称呼（备注）」")
                fieldRow("分组标签", text: $draft.groupTag, placeholder: "家人 / 访客 / 服务人员")
                fieldRow("家庭便签", text: $draft.note, placeholder: "如：周六换锁芯")
                fieldRow("紧急联系", text: $draft.emergency, placeholder: "姓名 + 电话")
                fieldRow("电话（用于一键呼叫）", text: $phone, placeholder: "如 138 0000 0000")
            }
            .padding(.top, V8.S.gapM)
            if !phone.isEmpty {
                Button {
                    call()
                } label: {
                    HStack(spacing: V8.S.gapS) {
                        Image(systemName: "phone")
                            .font(V8.T.caption)
                            .foregroundStyle(V8.C.ink1)
                            .accessibilityHidden(true)
                        Text("呼叫 " + phone)
                            .font(V8.T.tab)
                            .foregroundStyle(V8.C.ink1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .overlay(
                        RoundedRectangle(cornerRadius: V8.R.capsule(V8.H.min), style: .continuous)
                            .strokeBorder(V8.C.line, lineWidth: V8.S.hair)
                    )
                }
                .buttonStyle(.plain)
                .disabled(phone.filter(\.isNumber).count < 3)
                .opacity(phone.filter(\.isNumber).count < 3 ? 0.45 : 1)
                .accessibilityLabel("一键呼叫 " + phone)
                .padding(.top, V8.S.gapM)
            }

            Text("emoji 代号")
                .font(V8.T.label)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapL)
            emojiRow(member)
                .padding(.top, V8.S.gapS)
            if app.trialGuard {
                Text("只读试验模式开着：本页只改本机档案，不下发到门锁，不受影响。")
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                save(member)
            } label: {
                Text(saved ? "档案已保存" : "保存档案")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.chipOn)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.accent))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("保存成员档案")
            .padding(.top, V8.S.gapL)
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

    private func emojiRow(_ member: MemberCard) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: V8.S.gapS) {
                ForEach(Self.emojiOptions.indices, id: \.self) { index in
                    let e = Self.emojiOptions[index]
                    emojiCell(e, member: member)
                }
            }
        }
    }

    private func emojiCell(_ e: String, member: MemberCard) -> some View {
        let on = draft.emoji == e
        return Button {
            draft.emoji = e
            roster.update(member.id) { $0.emoji = e }
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
        .buttonStyle(.plain)
        .accessibilityLabel(e.isEmpty ? "默认首字" : "代号 " + e)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private static let emojiOptions = ["", "🐻", "🐱", "🐸", "🐙", "🦊", "🐧", "🐯"]

    // MARK: - 卡 4 名下凭证

    private func keysCard(_ member: MemberCard) -> some View {
        let keys = memberKeys(member)
        return VCard2 {
            VCardHead(eyebrow: "名下凭证", statement: "归属可证明的 \(keys.count) 枚", trailing: "本机台账")
            VDivider2()
                .padding(.top, V8.S.gapM)
            if keys.isEmpty {
                Text("TA 名下还没有凭证。到「钥匙」页新建一枚，归属选 \(member.name)。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
                VNavRow(title: "去新建凭证", detail: "归属自动带这位成员") {
                    router.request(.dest(.keyCreate))
                }
                .padding(.top, V8.S.gapS)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(keys.enumerated()), id: \.element.id) { index, key in
                        if index > 0 { VDotRule() }
                        Button {
                            router.request(.key(id: key.id))
                        } label: {
                            VDataRow(
                                tag: key.kind.rawValue,
                                tagTint: key.disabled ? V8.C.ink4 : kindTint(key.kind),
                                title: key.name,
                                detail: key.disabled ? "已停用" : nil,
                                value: key.expiresAt.map { TimeFormat.dayShort($0) } ?? ""
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(key.kind.rawValue + " " + key.name)
                    }
                }
                .padding(.top, V8.S.gapS)
            }
        }
    }

    private func memberKeys(_ member: MemberCard) -> [KeyItem] {
        app.keys.filter { CredentialOrg.ownerMatches($0.owner, memberID: member.id, memberName: member.name) }
    }

    private func kindTint(_ kind: KeyItem.Kind) -> Color {
        switch kind {
        case .password: return V8.D.password
        case .fingerprint: return V8.D.fingerprint
        case .temp: return V8.D.temp
        case .mobile: return V8.D.mobile
        }
    }

    // MARK: - 卡 5 最近开门

    private func excerptsCard(_ member: MemberCard) -> some View {
        let entries = Array(app.entries.filter { $0.owner == member.name }.prefix(5))
        return VCard2 {
            VCardHead(eyebrow: "最近开门", statement: entries.isEmpty ? "没有可证明归属的开门" : "\(entries.count) 条", trailing: "约")
            VDivider2()
                .padding(.top, V8.S.gapM)
            if entries.isEmpty {
                Text("台账里还没有可证明归属到 TA 的开门。锁端日志没有身份字段，只有归属明确的条目才会出现在这里。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
                VNavRow(title: "去台账按 TA 筛", detail: "记录页的成员筛选") {
                    router.request(.dest(.records))
                }
                .padding(.top, V8.S.gapS)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { VDotRule() }
                        VDataRow(
                            tag: TimeFormat.dayShort(entry.at),
                            tagTint: entry.tone == .critical ? V8.C.danger : V8.C.ink4,
                            title: entry.event,
                            detail: entry.owner,
                            value: TimeDisplay.clock(entry.at)
                        )
                    }
                }
                .padding(.top, V8.S.gapS)
            }
        }
    }

    // MARK: - 卡 6 家庭场景

    private func sceneCard(_ member: MemberCard) -> some View {
        VCard2 {
            VCardHead(eyebrow: "家庭场景", statement: isDuty ? "本周的家里事归 TA" : "本周还没指派", trailing: "可改")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Toggle(isOn: Binding(
                get: { roster.dutyID() == member.id },
                set: { on in roster.setDuty(on ? member.id : nil) }
            )) {
                VStack(alignment: .leading, spacing: V8.S.gapXS) {
                    Text("本周主责")
                        .font(V8.T.value)
                        .foregroundStyle(V8.C.ink1)
                    Text(isDuty ? "本周的家里事归 TA。" : "把这一周的事指给 TA；下周可重新指。")
                        .font(V8.T.caption)
                        .foregroundStyle(V8.C.ink4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minHeight: V8.H.min)
            .padding(.top, V8.S.gapM)
            if !draft.note.isEmpty {
                VDivider2()
                    .padding(.top, V8.S.gapM)
                VDataRow(tag: "便签", tagTint: V8.C.ink4, title: draft.note, value: "")
                    .padding(.top, V8.S.gapS)
            }
        }
    }

    // MARK: - 卡 7 收尾（归档不删历史；删除的后果一次写清）

    private func closingCard(_ member: MemberCard) -> some View {
        VCard2 {
            VCardHead(eyebrow: "档案收尾", statement: member.archived ? "已归档 · 历史仍在" : "在册")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VNavRow(
                title: member.archived ? "恢复进名册" : "归档（保留历史）",
                detail: member.archived ? "回到成员名册" : "记录页仍能筛到 TA"
            ) {
                toggleArchive()
            }
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("归档只从名册与统计里收起，不删任何历史；删除会移走 TA 的档案并解除名下凭证的归属。")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                confirmDelete = true
            } label: {
                Text("删除成员")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.danger)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.dangerTrack))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("删除成员")
            .padding(.top, V8.S.gapM)
        }
        .v8Confirm(
            isPresented: $confirmDelete,
            title: "删除这位成员？",
            consequence: deleteConsequence(member),
            confirmTitle: "删除成员",
            isDestructive: true
        ) {
            remove(member)
        }
    }

    private func deleteConsequence(_ member: MemberCard) -> String {
        let owned = memberKeys(member)
        var parts: [String] = []
        if owned.isEmpty {
            parts.append("「" + member.name + "」名下没有台账凭证。")
        } else {
            let preview = owned.prefix(5).map { "· " + $0.kind.rawValue + " " + $0.name }.joined(separator: "\n")
            let more = owned.count > 5 ? "\n…" : ""
            parts.append("「" + member.name + "」名下 " + String(owned.count) + " 条台账凭证：\n" + preview + more)
        }
        parts.append("成员档案删除后不可恢复；名下凭证的归属会一并解除（凭证本身留在台账，变成未归属）。")
        parts.append("锁端的密码与指纹不会自动删除 —— 仍需本人到锁前手动删；指纹一旦在锁端删掉就无法远程补录。")
        return parts.joined(separator: "\n\n")
    }

    // MARK: - 同名合并

    private var mergeCard: some View {
        VCard2 {
            VCardHead(eyebrow: "重复档案", statement: "发现同名成员", trailing: "可合并")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("合并会保留这一位，把另一位名下的凭证归属迁过来后删除它。删除副档这一步没有撤销。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            VNavRow(title: "合并同名成员", detail: "执行前会再确认一次") {
                showMerge = true
            }
            .padding(.top, V8.S.gapS)
        }
    }

    // MARK: - 空壳

    private var decoyCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "成员档案", statement: "空壳模式只读")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("空壳模式（胁迫码进入）下，成员档案、名下凭证与开门摘录都不显示，也不写入 —— 否则一保存就会用空档案覆盖真实备注与关系。")
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

    // MARK: - 真动作（档案扩展写 kf_member_ext、本周主责写 kf_duty_week，都是真落盘）

    private func load() {
        guard !decoyed, let m = member else { return }
        if loadedID != m.id {
            draft = roster.extras(for: m.id)
            phone = DB.member(m.id)?.phone ?? ""
            loadedID = m.id
            saved = false
        }
    }

    private func setRole(_ role: MemberCard.Role) {
        guard !decoyed else { return }
        guard let m = member, let i = app.members.firstIndex(where: { $0.id == m.id }) else { return }
        app.members[i] = m.hh(role: role)
        roster.mirrorRole(m.id, role)
    }

    private func save(_ member: MemberCard) {
        guard !decoyed else { return }
        roster.update(member.id) { e in
            e.relation = draft.relation.trimmingCharacters(in: .whitespaces)
            e.remark = draft.remark.trimmingCharacters(in: .whitespaces)
            e.groupTag = draft.groupTag.trimmingCharacters(in: .whitespaces)
            e.note = draft.note.trimmingCharacters(in: .whitespaces)
            e.emergency = draft.emergency.trimmingCharacters(in: .whitespaces)
            e.emoji = draft.emoji
        }
        // 电话是 Engine Member 的独立字段（kf_members），不走 MemberExt。
        DB.setMemberInfo(member.id, ["phone": phone.trimmingCharacters(in: .whitespaces)])
        saved = true
    }

    /// 一键呼叫：清洗非数字，少于 3 位给出可修的原因。
    private func call() {
        let digits = phone.filter(\.isNumber)
        guard digits.count >= 3 else {
            callNote = "这个号码里没有足够数字（至少 3 位）—— 先在上面填完整，再点呼叫。"
            return
        }
        guard let url = URL(string: "tel://" + digits), UIApplication.shared.canOpenURL(url) else {
            callNote = "系统不接受这个号码（tel: 链接打不开）—— 检查一下是否含有非法字符。"
            return
        }
        callNote = nil
        UIApplication.shared.open(url)
    }

    private func toggleArchive() {
        guard !decoyed else { return }
        guard let m = member, let i = app.members.firstIndex(where: { $0.id == m.id }) else { return }
        let next = !m.archived
        app.members[i] = m.hh(archived: next)
        roster.mirrorArchived(m.id, next)
        AppToast.shared.show(next ? "已归档 · 历史仍在，记录页仍能筛到 TA" : "已恢复为在册成员", tone: .ok)
    }

    private func remove(_ member: MemberCard) {
        guard !decoyed else { return }
        app.members.removeAll { $0.id == member.id }
        // Engine 侧删除：DB.removeMember 会连带解除台账里这些凭证的归属（凭证本身保留）。
        DB.removeMember(member.id)
        for i in app.keys.indices where CredentialOrg.ownerMatches(app.keys[i].owner, memberID: member.id, memberName: member.name) {
            let k = app.keys[i]
            // createdAt 必须一起带过来：漏了它，解除归属会把「已使用 N 天」清零。
            app.keys[i] = KeyItem(id: k.id, kind: k.kind, name: k.name, owner: nil,
                                  code: k.code, expiresAt: k.expiresAt,
                                  createdAt: k.createdAt, disabled: k.disabled)
        }
        roster.forget(member.id)
        if roster.dutyID() == member.id { roster.setDuty(nil) }
        roster.focusMember = nil
        router.request(.tab(.household))
    }
}
