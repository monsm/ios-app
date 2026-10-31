// HouseholdScreen.swift —— 家（Tab 4 根）。家庭名册的一台面板。
//
// 这屏干什么：读这个家的名册与读数（成员 / 名下凭证 / 本周开门 / 归档），按分组筛人，点行进成员 360。
// 数据从哪来：AppModel.members（锁端可证字段）+ HouseholdRoster（本机档案扩展与本周主责）+ AppModel.entries（台账）。
// 主动作：新建成员（走建档向导）。次入口：归档、访客虚拟分组、家庭场景。
import SwiftUI

/// 名册排序四档（264/466）。全部按本机可读字段排，不假装有服务端排序。
enum HHMemberSort: CaseIterable, Hashable {
    case recent, name, keys, opens30

    var title: String {
        switch self {
        case .recent: return "最近活跃"
        case .name: return "姓名"
        case .keys: return "凭证数"
        case .opens30: return "近 30 天次数"
        }
    }
}

struct HouseholdScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @State private var group: String = ""
    @State private var sort: HHMemberSort = .recent

    private var roster: HouseholdRoster { HouseholdRoster.shared }

    private var activeMembers: [MemberCard] { HHStats.active(app.members) }
    private var archivedCount: Int { HHStats.archived(app.members).count }

    private var shown: [MemberCard] {
        let filtered = group.isEmpty
            ? activeMembers
            : activeMembers.filter { roster.extras(for: $0.id).groupTag == group }
        return sorted(filtered)
    }

    /// 264/466 四档排序。全部按本机可读的字段排，不假装有服务端排序。
    private func sorted(_ list: [MemberCard]) -> [MemberCard] {
        switch sort {
        case .recent:
            return list.sorted { ($0.lastActiveAt ?? 0) > ($1.lastActiveAt ?? 0) }
        case .name:
            return list.sorted { lhs, rhs in
                let a = HHDisplay.name(lhs, extras: roster.extras(for: lhs.id))
                let b = HHDisplay.name(rhs, extras: roster.extras(for: rhs.id))
                return a < b
            }
        case .keys:
            return list.sorted { $0.keyCount > $1.keyCount }
        case .opens30:
            let counts = opens30Counts
            return list.sorted { (counts[$0.name] ?? 0) > (counts[$1.name] ?? 0) }
        }
    }

    /// 近 30 天可证明归属的开门次数（约）。归属按台账 owner 名匹配。
    /// TODO(engine)：接 MemberHub.activityBundle（Attribution.classify）；现在只认台账已归属的行。
    private var opens30Counts: [String: Int] {
        let cutoff = Int64(Date().timeIntervalSince1970 * 1000) - 30 * 86_400_000
        var out: [String: Int] = [:]
        for entry in app.entries where entry.at >= cutoff {
            guard let owner = entry.owner, !owner.isEmpty else { continue }
            out[owner, default: 0] += 1
        }
        return out
    }

    private var tags: [String] {
        Array(Set(activeMembers.map { roster.extras(for: $0.id).groupTag }).filter { !$0.isEmpty }).sorted()
    }

    /// 近 7 天可证明归属的开门（约）。锁端日志没有身份字段，只算台账已归属的行。
    private var weekOpens: Int {
        HHStats.weekOpens(app.entries, names: Set(activeMembers.map(\.name)))
    }

    private var dutyMember: MemberCard? {
        guard let id = roster.dutyID() else { return nil }
        return app.members.first { $0.id == id }
    }

    private var atLimit: Bool { app.members.count >= HHStats.memberLimit }

    var body: some View {
        ScrollView {
            VStack(spacing: T.S.l) {
                header
                overviewPanel
                if !tags.isEmpty {
                    ChipRow(items: [""] + tags, title: { $0.isEmpty ? "全部" : $0 }, selection: $group)
                        .animation(T.M.snap, value: group)
                }
                rosterPanel
                if archivedCount > 0 { archivePanel }
                scenePanel
                if !activeMembers.isEmpty { createPanel }
            }
            .padding(.vertical, T.S.l)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .onAppear(perform: consume)
        .onChange(of: router.pending) { _, _ in consume() }
        .navigationTitle("家")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(HHMemberSort.allCases, id: \.self) { option in
                        Button(option.title) { sort = option }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("排序方式，当前 \(sort.title)")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.request(.dest(.memberCreate))
                } label: {
                    Image(systemName: "person.badge.plus")
                }
                .accessibilityLabel("新建成员")
                .disabled(atLimit)
            }
        }
    }

    // MARK: 页头（大标题 + 一行状态）
    private var header: some View {
        HHPageHeader(
            title: "家",
            overline: "成员与家庭",
            tone: archivedCount == 0 ? .ok : .neutral,
            status: archivedCount == 0
                ? "全员都在名册里 · 归属与本周主责在下方面板"
                : "有成员在归档里 · 归档不删历史，随时可恢复"
        )
    }

    // MARK: 主角：这一台面板就是家的读数
    private var overviewPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "家庭概览", trailing: "本周")
                ReadingGrid(items: [
                    .init(label: "成员", value: "\(activeMembers.count)", unit: "位"),
                    .init(label: "名下凭证", value: "\(HHStats.ownedKeys(activeMembers))", unit: "枚"),
                    .init(label: "本周开门（约）", value: "\(weekOpens)", unit: "次"),
                    .init(label: "归档", value: "\(archivedCount)", unit: "位",
                          tint: archivedCount == 0 ? Ink.ink : Ink.inkSub),
                ])
                .padding(.top, T.S.xs)

                HHRule()

                Menu {
                    Button("不安排") { roster.setDuty(nil) }
                    ForEach(activeMembers) { m in
                        Button(HHDisplay.name(m, extras: roster.extras(for: m.id))) {
                            roster.setDuty(m.id)
                        }
                    }
                } label: {
                    HStack(spacing: T.S.m) {
                        Text("本周主责")
                            .font(T.F.body)
                            .foregroundStyle(Ink.inkSub)
                        Spacer(minLength: T.S.s)
                        if let dutyMember {
                            Text(HHDisplay.name(dutyMember, extras: roster.extras(for: dutyMember.id)))
                                .font(T.F.bodyStrong)
                                .foregroundStyle(Ink.ink)
                        } else {
                            Text("未安排 · 点这里指人")
                                .font(T.F.caption)
                                .foregroundStyle(Ink.inkSub)
                        }
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: T.Icon.s, weight: .medium))
                            .foregroundStyle(Ink.inkFaint)
                    }
                    .frame(minHeight: T.Hit.min)
                    .contentShape(.rect)
                }
                .accessibilityLabel(dutyMember.map { "本周主责 \($0.name)" } ?? "本周主责未安排，点这里指人")

                HHRule()

                HHRowButton(
                    title: "访客 · 临时码未归属",
                    symbol: "person.badge.clock",
                    readingValue: "\(visitorOpens)",
                    readingUnit: "条",
                    action: { router.request(.dest(.records)) }
                )
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    /// 临时码且无归属的开门条数（793 访客虚拟分组：只在展示层，不写入锁端凭证表）。
    /// TODO(engine)：接 Attribution.classify 的 isVisitorRow 判定；现在只按台账 event 文案 + owner 为空近似。
    private var visitorOpens: Int {
        app.entries.filter { entry in
            entry.owner == nil && entry.event.contains("临时码")
        }.count
    }

    // MARK: 名册
    private var rosterPanel: some View {
        let list = shown
        return Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: group.isEmpty ? "成员名册" : "成员名册 · \(group)", trailing: "\(list.count) 位 · " + sort.title)
                if shown.isEmpty {
                    if activeMembers.isEmpty {
                        EmptyPanel(
                            title: "还没有成员",
                            message: "建档向导四步：称呼 → 角色 → 档案 → 初始凭证。建完就能把密码和指纹归属到人。",
                            actionTitle: "新建成员",
                            systemImage: "person.2.slash",
                            action: { router.request(.dest(.memberCreate)) }
                        )
                        .padding(.vertical, T.S.xxl)
                    } else {
                        VStack(alignment: .leading, spacing: T.S.s) {
                            Text("这个分组下没有人")
                                .font(T.F.body)
                                .foregroundStyle(Ink.ink)
                            Text("当前按「\(group)」筛选。清除筛选可回到全部成员。")
                                .font(T.F.caption)
                                .foregroundStyle(Ink.inkSub)
                                .fixedSize(horizontal: false, vertical: true)
                            FieldRow(label: "全部成员", value: "\(activeMembers.count)", unit: "位")
                            SecondaryAction(title: "清除筛选", systemImage: "line.3.horizontal.decrease.circle") {
                                group = ""
                            }
                        }
                        .frame(minHeight: T.Hit.min)
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(list.indices, id: \.self) { index in
                            if index > 0 { HHRule() }
                            rosterRow(list[index])
                        }
                    }
                }
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    private func rosterRow(_ member: MemberCard) -> some View {
        Button { open(member) } label: {
            HHMemberRow(
                member: member,
                extras: roster.extras(for: member.id),
                subline: HHDisplay.subline(member, extras: roster.extras(for: member.id)),
                status: HHStats.status(member)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { open(member) } label: { Label("成员 360", systemImage: "person.text.rectangle") }
            Button { archive(member) } label: { Label("归档", systemImage: "archivebox") }
        }
    }

    // MARK: 归档入口
    private var archivePanel: some View {
        Panel {
            HHRowButton(
                title: "归档成员 · 保留历史",
                symbol: "archivebox",
                readingValue: "\(archivedCount)",
                readingUnit: "位",
                action: { router.request(.dest(.memberArchive)) }
            )
        }
        .padding(.horizontal, T.S.gutter)
    }

    // MARK: 家庭场景（本周主责 + 便签）
    private var scenePanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "家庭场景")
                if dutyMember == nil {
                    Text("本周主责还没安排 —— 打开任意成员的 360，在「家庭场景」里点「设为本周主责」。")
                        .font(T.F.caption)
                        .foregroundStyle(Ink.inkSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if noteMembers.isEmpty {
                    Text("还没有人写便签。便签写在成员 360 的档案里（如「周六换锁芯」）。")
                        .font(T.F.caption)
                        .foregroundStyle(Ink.inkSub)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(noteMembers.prefix(3), id: \.id) { m in
                        VStack(alignment: .leading, spacing: T.S.xxs) {
                            Text(HHDisplay.name(m, extras: roster.extras(for: m.id)))
                                .font(T.F.unit)
                                .foregroundStyle(Ink.inkFaint)
                                .tracking(0.6)
                            Text(roster.extras(for: m.id).note)
                                .font(T.F.caption)
                                .foregroundStyle(Ink.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    /// 写了便签的成员（家庭场景只读前 3 位，不做第二份名单）。
    private var noteMembers: [MemberCard] {
        activeMembers.filter { !roster.extras(for: $0.id).note.isEmpty }
    }

    // MARK: 主动作（同屏只此一处 signal 填充）
    private var createPanel: some View {
        VStack(spacing: T.S.s) {
            PrimaryAction(title: "新建成员", systemImage: "person.badge.plus") {
                router.request(.dest(.memberCreate))
            }
            .disabled(atLimit)
            .opacity(atLimit ? 0.5 : 1)
            Text(atLimit
                 ? "已到本机成员上限 15 位 —— 先归档一位再建新人（归档不删历史）。"
                 : "成员表存在本机，不占锁端槽位；建完在成员 360 里给 TA 配凭证。")
                .font(T.F.unit)
                .foregroundStyle(Ink.inkFaint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, T.S.m)
        }
        .padding(.horizontal, T.S.gutter)
        .padding(.top, T.S.s)
    }

    /// 消费 Router 带来的 .member(id:) 上下文：落到那位成员的 360。
    /// 用完即清（consume() 会把 pending 置回 none）。
    private func consume() {
        guard case .member(let id) = router.consume() else { return }
        guard app.members.contains(where: { $0.id == id }) else { return }
        roster.focusMember = id
        router.request(.dest(.memberDetail))
    }

    // MARK: 真动作
    private func open(_ member: MemberCard) {
        roster.focusMember = member.id
        router.request(.dest(.memberDetail))
    }

    private func archive(_ member: MemberCard) {
        guard let i = app.members.firstIndex(where: { $0.id == member.id }) else { return }
        app.members[i] = member.hh(archived: true)
        roster.mirrorArchived(member.id, true)
    }
}
