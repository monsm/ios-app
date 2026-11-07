// MemberDetailScreen.swift —— 一位成员的档案。
import SwiftUI

@MainActor
struct MemberDetailScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var role: MemberRole = .member
    @State private var note = ""
    @State private var groupTag = ""
    @State private var archived = false
    @State private var confirmingDelete = false
    @State private var loaded = false

    private var member: MemberCard? {
        app.members.first { $0.id == id }
    }

    private var id: String { router.pendingMemberID ?? "" }

    private var owned: [Credential] {
        app.credentials.filter {
            CredentialOrg.ownerMatches($0.ownerID, memberID: id, memberName: member?.name ?? "")
        }
    }

    private var activity: [EventItem] {
        app.events.filter { $0.whoID == id }.prefix(5).map { $0 }
    }

    var body: some View {
        ScreenScroll {
            if let member {
                content(member)
            } else {
                EmptyNote(line: "这位成员不在了。", detail: "可能已经被删除。", action: "返回") { dismiss() }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("删除这位成员？", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { remove() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("名下的凭证会变成「未归属」，锁端不会被删除。")
        }
        // 档案里的角色 / 分组 / 备注 / 归档状态要先灌进表单。
        // 不灌的话：管理员打开自己的档案，分段控件停在「成员」；
        // 在分组框里动一下，就会把 remark 和归档状态一起写成空。
        .task {
            guard !loaded else { return }
            let ext = MemberHub.ext(id)
            role = MemberRole.parse(ext.role)
            groupTag = ext.groupTag
            note = ext.note
            archived = ext.archived
            loaded = true
        }
    }

    @ViewBuilder
    private func content(_ member: MemberCard) -> some View {
        NavRow(kicker: "通行 / 成员", back: { dismiss() }) {
            AnyView(
                Button { confirmingDelete = true } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15))
                        .foregroundStyle(T.C.ink2)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除成员")
            )
        }

        HStack(spacing: 16) {
            MemberOrb(member: member, size: 64)
            VStack(alignment: .leading, spacing: 5) {
                Text(member.name)
                    .type(T.F.title2)
                    .foregroundStyle(T.C.ink)
                Text(member.role.title + (member.groupTag.isEmpty ? "" : " · \(member.groupTag)"))
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
            }
            Spacer()
        }
        .padding(.top, 18)

        DisplayLine(text: headline(member), size: 30)
            .padding(.top, 22)
        Text(detail(member))
            .type(T.F.footnote)
            .foregroundStyle(T.C.ink2)
            .lineSpacing(4)
            .padding(.top, 8)

        SectionHead(index: "01", title: "角色")
        SegmentedBar(items: MemberRole.allCases.map(\.title), selected: Binding(
            get: { MemberRole.allCases.firstIndex(of: role) ?? 1 },
            set: { role = MemberRole.allCases[$0] }
        ))
        .onChange(of: role) { _, newValue in save(role: newValue) }

        VStack(spacing: 0) {
            ForEach(MemberHub.permRows(role.fromEngine).indices, id: \.self) { index in
                let row = MemberHub.permRows(role.fromEngine)[index]
                HStack {
                    Text(row.name)
                        .type(T.F.callout)
                        .foregroundStyle(T.C.ink)
                    Spacer()
                    Image(systemName: row.allowed ? "checkmark" : "minus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(row.allowed ? T.C.brass : T.C.ink3)
                }
                .padding(.vertical, 11)
            }
        }
        .padding(.top, 6)

        // 这张表说明厂商角色模型里「本该有几项能力」，但本机没有任何按角色鉴权的路径：
        // 一台手机一个门禁，谁能解锁这台手机谁就能导出备份、改成员。
        // 不写这一句，勾选表就是在暗示一种不存在的限制。
        Text("角色只是名册上的归类：本机不会按角色拦下任何操作 —— 门锁只认钥匙，不认头衔。")
            .type(T.F.caption)
            .foregroundStyle(T.C.ink3)
            .padding(.top, 8)

        SectionHead(index: "02", title: "名下的钥匙", trailing: "\(owned.count)")
        if owned.isEmpty {
            Text("还没有分给 TA 任何钥匙。")
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
                .padding(.vertical, 8)
            // 原先这里只有一句空话：整页没有任何把钥匙归给 TA 的入口。
            Button {
                router.pendingCreateOwnerID = id
                router.push(.credentialCreate)
            } label: {
                Text("新建一枚归给 TA 的凭证")
                    .type(T.F.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(T.C.brass)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 6)
        } else {
            ForEach(owned) { item in
                Button { router.openCredential(item.id) } label: {
                    ContentRow(symbol: item.kind.symbol,
                               tone: item.isExpired ? .danger : .brass,
                               title: item.name,
                               subtitle: item.kind.title + (item.expiresAt == nil ? " · 长期有效" : " · " + When.expiryLabel(item.expiresAt)),
                               chevron: true)
                }
                .buttonStyle(.plain)
            }
        }

        SectionHead(index: "03", title: "最近")
        // D7：TA 这一周的开门柱状图 —— 名下钥匙再多，真正的活跃度看这里。
        WeekBars(days: WeekBars.build(events: app.events, memberID: id))
            .padding(.bottom, 6)
        if activity.isEmpty {
            Text("没有可证明是 TA 的开门记录。")
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
                .padding(.vertical, 8)
        } else {
            ForEach(activity) { event in
                Button { router.openEvent(event.id) } label: {
                    EventRow(event: event, showLock: true)
                }
                .buttonStyle(.plain)
            }
        }

        SectionHead(index: "04", title: "档案")
        FieldInput(placeholder: "分组，例如：家人 / 访客", text: $groupTag)
            .onChange(of: groupTag) { _, _ in save(role: role) }
        FieldInput(placeholder: "备注（只在本机）", text: $note)
            .padding(.top, 10)
            .onChange(of: note) { _, _ in save(role: role) }

        SwitchLine(title: "归档", detail: "保留历史，从常用名单收起；仍可在「已归档」里找到。", isOn: $archived)
            .onChange(of: archived) { _, _ in save(role: role) }
    }

    private func headline(_ member: MemberCard) -> String {
        if let last = member.lastActiveAt {
            return "\(When.ago(last))\n回来过。"
        }
        return "还在\n等第一次。"
    }

    private func detail(_ member: MemberCard) -> String {
        var parts = ["\(member.keyCount) 枚钥匙"]
        // 原先这里写「访客只能开门，看不到记录」—— 本机并不按角色拦任何操作，
        // 那句话是在承诺一条不存在的限制。角色只用于归类。
        if member.archived { parts.append("已归档") }
        return parts.joined(separator: " · ")
    }

    private func save(role newRole: MemberRole) {
        guard !id.isEmpty else { return }
        let old = MemberHub.ext(id)
        var ext = old
        ext.role = newRole.fromEngine
        ext.groupTag = groupTag
        ext.note = note
        ext.archived = archived
        // 灌入档案那一下也会触发 onChange；值没变就不写。
        guard ext != old else { return }
        MemberHub.saveExt(id, ext)
        app.reloadCredentials()
    }

    private func remove() {
        guard !id.isEmpty else { return }
        DB.removeMember(id)
        app.reloadCredentials()
        dismiss()
    }
}

// MARK: - 新成员

@MainActor
struct MemberCreateScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var role: MemberRole = .member
    @State private var groupTag = ""
    @State private var errorLine: String?

    var body: some View {
        ScreenScroll {
            NavRow(kicker: "通行 / 新成员", back: { dismiss() })

            DisplayLine(text: "先有一个\n名字。", size: 36)
                .padding(.top, 16)
            Text("成员只是本机的名册：它不改变锁里的任何字节，只决定钥匙归谁、记录算谁。")
                .type(T.F.footnote)
                .foregroundStyle(T.C.ink2)
                .lineSpacing(4)
                .padding(.top, 8)

            SectionHead(index: "01", title: "称呼")
            FieldInput(placeholder: "例如：妈妈", text: $name)
                .onChange(of: name) { _, newValue in
                    if newValue.count > 12 { name = String(newValue.prefix(12)) }
                }

            SectionHead(index: "02", title: "角色")
            SegmentedBar(items: MemberRole.allCases.map(\.title), selected: Binding(
                get: { MemberRole.allCases.firstIndex(of: role) ?? 1 },
                set: { role = MemberRole.allCases[$0] }
            ))
            Text(roleHint)
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
                .padding(.top, 8)

            SectionHead(index: "03", title: "分组")
            FieldInput(placeholder: "家人 / 访客 / 服务人员", text: $groupTag)

            if let errorLine {
                Text(errorLine)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.danger)
                    .padding(.top, 14)
            }

            PrimaryButton(title: "建档") { create() }
                .padding(.top, 24)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var roleHint: String {
        // 只描述归类，不承诺能力：本机没有按角色鉴权的路径（见 MemberDetailScreen 的说明）。
        switch role {
        case .owner: return "管理员：名册里管事的那个人。"
        case .member: return "成员：有钥匙的家人。"
        case .guest: return "访客：临时进门的人。"
        }
    }

    private func create() {
        // 空壳里 `DB.addMember` 会拒绝写入并返回 nil，若直接落到下面那句，
        // 用户看到的是「这个名字已经有人用了」—— 一句与真实原因无关的假话。
        guard !DB.isDecoy else {
            errorLine = "当前无法保存，请稍后再试。"
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorLine = "先给它一个称呼。"
            return
        }
        guard let member = DB.addMember(trimmed) else {
            errorLine = "这个名字已经有人用了。"
            return
        }
        var ext = MemberExt()
        ext.role = role.fromEngine
        ext.groupTag = groupTag
        MemberHub.saveExt(member.id, ext)
        app.reloadCredentials()
        dismiss()
    }
}
