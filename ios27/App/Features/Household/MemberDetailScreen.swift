// MemberDetailScreen.swift —— 成员 360（一位成员的完整档案）。
//
// 这屏干什么：读一个人 —— 角色与权限矩阵 / 档案扩展 / 名下凭证 / 最近开门摘录 / 家庭场景 / 归档与删除。
// 数据从哪来：AppModel.members 里那一位 + HouseholdRoster（档案扩展与本周主责）+ AppModel.entries（摘录）。
// 主动作：保存档案（同屏唯一 signal 填充）。角色是点一下即生效的真交互，矩阵当场跟着亮灭。
import SwiftUI

struct MemberDetailScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    @State private var draft: HHMemberExtras = HHMemberExtras()
    @State private var loadedID: String?
    @State private var confirmDelete = false
    @State private var saved = false
    @State private var showMerge = false

    private var roster: HouseholdRoster { HouseholdRoster.shared }

    internal var member: MemberCard? {
        guard let id = roster.focusMember else { return nil }
        return app.members.first { $0.id == id }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: V.S.gap16) {
                if let member {
                    header(member)
                    HHMemberWeekPanel(
                        member: member,
                        entries: app.entries,
                        openRecords: { router.request(.dest(.records)) }
                    )
                    rolePanel(member)
                    profilePanel(member)
                    HHMemberKeysPanel(
                        member: member,
                        keys: app.keys.filter { $0.owner == member.name },
                        openKey: { id in router.request(.key(id: id)) },
                        createKey: { router.request(.dest(.keyCreate)) }
                    )
                    HHMemberExcerptsPanel(
                        entries: Array(app.entries.filter { $0.owner == member.name }.prefix(5)),
                        openRecords: { router.request(.dest(.records)) }
                    )
                    HHMemberScenePanel(
                        member: member,
                        note: draft.note,
                        isDuty: roster.dutyID() == member.id,
                        toggleDuty: {
                            roster.setDuty(roster.dutyID() == member.id ? nil : member.id)
                        }
                    )
                    HHMemberClosingPanel(
                        member: member,
                        toggleArchive: { toggleArchive() },
                        askDelete: { confirmDelete = true }
                    )
                    if !MemberMergeKit.candidates(primaryID: member.id).isEmpty {
                        mergePanel(member)
                    }
                } else {
                    missingBlock
                }
            }
            .padding(.vertical, V.S.gap16)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("成员")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if member != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { toggleArchive() } label: {
                        Image(systemName: member?.archived == true ? "archivebox.circle.fill" : "archivebox")
                            .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字/按钮标签承载
                    }
                    .accessibilityLabel(member?.archived == true ? "恢复成员" : "归档成员")
                }
            }
        }
        .onAppear {
            if case .member(let id) = router.consume() {
                roster.focusMember = id
            }
            load()
        }
        .sheet(isPresented: $showMerge) {
            if let member { MemberMergeSheet(primary: member) }
        }
        .confirmationDialog("删除成员", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("只移除档案（锁端凭证仍有效）", role: .destructive) { remove(cascade: false) }
            Button("连本机凭证一起移除（锁端仍需线下删）", role: .destructive) { remove(cascade: true) }
            Button("取消", role: .cancel) {}
        } message: {
            Text(deleteMessage)
        }
    }

    // MARK: 重复合并（462）

    private func mergePanel(_ member: MemberCard) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "重复档案")
                Text("发现同名成员。合并会保留这一位，把另一位名下的凭证归属迁过来后删除它。")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text2)
                    .fixedSize(horizontal: false, vertical: true)
                VOutlineButton(title: "合并同名成员", systemImage: "arrow.triangle.merge") {
                    showMerge = true
                }
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    // MARK: 页头（大标题 + 一行状态）
    private func header(_ member: MemberCard) -> some View {
        VStack(alignment: .leading, spacing: V.S.gapMS) {
            HStack(spacing: V.S.gapMS) {
                HHAvatar(name: member.name, emoji: draft.emoji, size: HHMetric.avatarHero, glyph: V.F.display24)
                VStack(alignment: .leading, spacing: V.S.gapXXS) {
                    Text(HHDisplay.name(member, extras: draft))
                        .font(V.F.displayHome)
                        .foregroundStyle(V.C.text1)
                        // 标题最多两行；缩字只收到 0.85（0.6 会把 34pt 压成 20pt，中文长名字会糊）
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    HStack(spacing: V.S.gapS) {
                        VStateDot(tone: statusTone(member), word: statusWord(member))
                        Text(statusLine(member))
                            .font(V.F.footnote)
                            .foregroundStyle(V.C.text2)
                        Spacer(minLength: 0)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, V.S.pageGutter)
    }

    private func statusTone(_ member: MemberCard) -> Tone {
        switch HHStats.status(member) {
        case .archived, .never: return .neutral
        case .stale: return .attention
        case .active: return .ok
        }
    }

    private func statusWord(_ member: MemberCard) -> String {
        HHDisplay.statusWord(HHStats.status(member))
    }

    private func statusLine(_ member: MemberCard) -> String {
        if member.archived { return "已归档 · 历史仍在，记录页仍能筛到 TA" }
        return "\(member.role.rawValue) · \(HHStats.lastOpen(member))"
    }

    // MARK: 主角：角色三档 + 权限矩阵（点一下当场看得见哪几行亮/灭）
    private func rolePanel(_ member: MemberCard) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "角色与权限", trailing: "本机判据")
                HStack(spacing: V.S.gapS) {
                    ForEach(MemberCard.Role.allCases, id: \.self) { role in
                        roleChip(role, current: member.role)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, V.S.gapXXS)

                VStack(spacing: 0) {
                    ForEach(HHPerm.rows.indices, id: \.self) { index in
                        if index > 0 { HHRule() }
                        permRow(HHPerm.rows[index], role: member.role)
                    }
                }
                .animation(reduceMotion ? nil : V.M.snap, value: member.role)

                Text(HHPerm.scene(member.role))
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text2)
                    .fixedSize(horizontal: false, vertical: true)

                Text("矩阵管的是本机 UI：锁端没有角色字段，这三档不改任何发往门锁的字节，备份包也不带角色。")
                    .font(V.F.unit)
                    .foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)

                HHRule()

                HHToggleRow(
                    title: "紧急管理员",
                    detail: HHPerm.allows(member.role, "成员管理")
                        ? "把人点出来，免得只剩一个人管钥匙。"
                        : "角色是「\(member.role.rawValue)」，矩阵里「成员管理」禁用 —— 先把角色改成管理员。",
                    isOn: draft.emergencyAdmin,
                    enabled: HHPerm.allows(member.role, "成员管理")
                ) {
                    let v = !draft.emergencyAdmin
                    draft.emergencyAdmin = v
                    roster.update(member.id) { $0.emergencyAdmin = v }
                }
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    private func permRow(_ cap: String, role: MemberCard.Role) -> some View {
        HStack(spacing: V.S.gapMS) {
            Text(cap)
                .font(V.F.body)
                .foregroundStyle(V.C.text1)
            Spacer(minLength: V.S.gapS)
            HHPill(allowed: HHPerm.allows(role, cap))
        }
        .frame(minHeight: V.Hit.min - V.S.gapS)
        .accessibilityElement(children: .combine)
    }

    private func roleChip(_ role: MemberCard.Role, current: MemberCard.Role) -> some View {
        let on = role == current
        return Button {
            setRole(role)
        } label: {
            HStack(spacing: V.S.gapXS) {
                HHRoleMark(role: role, compact: true)
                if on {
                    Text("当前")
                        .font(V.F.unit)
                        .foregroundStyle(V.C.text2)
                }
            }
            .foregroundStyle(on ? V.C.text1 : V.C.text2)
            .padding(.horizontal, V.S.gapMS)
            .frame(minHeight: V.Hit.min)
            .background(on ? V.C.blue.opacity(0.16) : Color.clear, in: .capsule)
            .overlay {
                Capsule().strokeBorder(on ? V.C.blue.opacity(0.75) : V.C.hairline, lineWidth: V.S.hair)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("角色 \(role.rawValue)")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: 档案扩展（角色不在这里改 —— 上面单选是唯一真相源）
    private func profilePanel(_ member: MemberCard) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "档案", trailing: saved ? "已保存" : "本机")
                HHTextField(label: "与你的关系", text: $draft.relation, placeholder: "母亲 / 妹妹 / 钟点工")
                HHTextField(label: "备注名", text: $draft.remark, placeholder: "记录条目显示「称呼（备注）」")
                HHTextField(label: "分组标签", text: $draft.groupTag, placeholder: "家人 / 访客 / 服务人员")
                HHTextField(label: "家庭便签", text: $draft.note, placeholder: "如：周六换锁芯")
                HHTextField(label: "紧急联系", text: $draft.emergency, placeholder: "姓名 + 电话")

                Text("emoji 代号")
                    .font(V.F.unit)
                    .foregroundStyle(V.C.text3)
                    .tracking(0.6)
                emojiRow(member)

                VActionButton(title: saved ? "档案已保存" : "保存档案", systemImage: "checkmark") {
                    save(member)
                }
                .padding(.top, V.S.gapXS)
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    private func emojiRow(_ member: MemberCard) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: V.S.gapS) {
                ForEach(Self.emojiOptions.indices, id: \.self) { index in
                    let e = Self.emojiOptions[index]
                    let on = draft.emoji == e
                    Button {
                        draft.emoji = e
                        roster.update(member.id) { $0.emoji = e }
                    } label: {
                        Text(e.isEmpty ? "首字" : e)
                            .font(e.isEmpty ? V.F.unit : V.F.body)
                            .foregroundStyle(on ? V.C.text1 : V.C.text2)
                            .frame(width: V.Hit.min, height: V.Hit.min)
                            .background(on ? V.C.blue.opacity(0.16) : V.C.cardAlt, in: .circle)
                            .overlay {
                                Circle().strokeBorder(on ? V.C.blue.opacity(0.75) : V.C.hairline,
                                                      lineWidth: V.S.hair)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(e.isEmpty ? "默认首字" : "代号 \(e)")
                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private static let emojiOptions = ["", "🐻", "🐱", "🐸", "🐙", "🦊", "🐧", "🐯"]

    private var missingBlock: some View {
        VCard {
            VEmptyState(
                title: "还没选成员",
                message: "从「家」的成员名册里点一位成员进来，这里会显示 TA 的档案、凭证与权限。",
                actionTitle: "回到名册",
                systemImage: "person.crop.circle.badge.questionmark"
            ) {
                router.request(.tab(.household))
            }
            .padding(.vertical, V.S.gapXXL)
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    // MARK: 真动作（档案扩展写 kf_member_ext、本周主责写 kf_duty_week，都是真落盘）
    private func load() {
        guard let m = member else { return }
        if loadedID != m.id {
            draft = roster.extras(for: m.id)
            loadedID = m.id
            saved = false
        }
    }

    private func setRole(_ role: MemberCard.Role) {
        guard let m = member, let i = app.members.firstIndex(where: { $0.id == m.id }) else { return }
        app.members[i] = m.hh(role: role)
        roster.mirrorRole(m.id, role)
    }

    private func save(_ member: MemberCard) {
        roster.update(member.id) { e in
            e.relation = draft.relation.trimmingCharacters(in: .whitespaces)
            e.remark = draft.remark.trimmingCharacters(in: .whitespaces)
            e.groupTag = draft.groupTag.trimmingCharacters(in: .whitespaces)
            e.note = draft.note.trimmingCharacters(in: .whitespaces)
            e.emergency = draft.emergency.trimmingCharacters(in: .whitespaces)
            e.emoji = draft.emoji
        }
        saved = true
    }

    internal func toggleArchive() {
        guard let m = member, let i = app.members.firstIndex(where: { $0.id == m.id }) else { return }
        app.members[i] = m.hh(archived: !m.archived)
        roster.mirrorArchived(m.id, !m.archived)
    }

    /// 删除前的级联预告：先列名下凭证（最多 5 条），再写两种后果。
    /// TODO(engine)：锁端删除队列（cmd 删密码 / 删指纹）还没有链路 —— 现在只动本机台账，
    ///   文案里如实写「锁端仍需线下删」，不假装已经排了队列。
    private var deleteMessage: String {
        guard let m = member else { return "" }
        let owned = app.keys.filter { $0.owner == m.name }
        if owned.isEmpty {
            return "「\(m.name)」名下没有台账凭证。本机档案删除后不可恢复。"
        }
        let preview = owned.prefix(5).map { "· " + $0.kind.rawValue + " " + $0.name }.joined(separator: "\n")
        let more = owned.count > 5 ? "\n…" : ""
        return "「\(m.name)」名下 \(owned.count) 条台账凭证：\n\(preview)\(more)\n\n"
            + "只移除档案：本机归属一起移走，锁端密码/指纹仍然有效，TA 仍能开门。\n"
            + "连本机凭证一起移除：这些记录从本机台账消失，但锁端同样要本人到锁前手动删才会真正失效（指纹一旦在锁端删掉就无法远程补录）。"
    }

    private func remove(cascade: Bool) {
        guard let m = member else { return }
        app.members.removeAll { $0.id == m.id }
        // Engine 侧删除：DB.removeMember 会连带解除台账里这些凭证的归属（凭证本身保留）。
        DB.removeMember(m.id)
        if cascade {
            app.keys.removeAll { $0.owner == m.name }
        } else {
            for i in app.keys.indices where app.keys[i].owner == m.name {
                let k = app.keys[i]
                app.keys[i] = KeyItem(id: k.id, kind: k.kind, name: k.name, owner: nil,
                                      code: k.code, expiresAt: k.expiresAt, disabled: k.disabled)
            }
        }
        roster.forget(m.id)
        if roster.dutyID() == m.id { roster.setDuty(nil) }
        roster.focusMember = nil
        router.request(.tab(.household))
    }
}
