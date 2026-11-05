// HouseHomeScreen.swift —— 家（Tab 4）· V8 设计语言
//
// 02 §3.4 #31 归并：memberArchive 降为「归档」段（showArchived 筛选 + 归档名单 + 影响面卡）。
// 能力守恒：HHStats.archived / mirrorArchived 恢复链路、「逐位可恢复、没有全部恢复」的纪律、
// 归档影响面五行读数、空态与只读文案全部保留。
//
// 与 HouseholdScreen 的功能对齐：成员概览 / 名单 / 排序入口 / 归档 / 成员流转 / 新建成员。
// 一屏一个英雄数：在册人数只出现在「成员」芯片里，标题不重复。
import SwiftUI

struct HouseHomeScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    /// memberArchive 并入后的「归档」筛选：false = 只看在册，true = 看归档名单。
    @State private var showArchived = false

    private var activeMembers: [MemberCard] { HHStats.active(app.members) }
    private var archivedCount: Int { HHStats.archived(app.members).count }
    private var ownedKeys: Int { HHStats.ownedKeys(activeMembers) }

    private var weekOpens: Int {
        HHStats.weekOpens(app.entries, names: Set(activeMembers.map(\.name)))
    }

    private var visitorOpens: Int {
        MemberHub.activityBundle(activeMembers.map(\.id)).visitorOpens
    }

    /// 近 7 天（含今天）每天的成功开门次数 + 对应的星期标签。
    ///
    /// 2026-11-05（用户指令：图形化变多）：本页此前是全仓「文字多、图形 0」的典型。
    /// 这 7 个数是真数据（本机回执），不是装饰 —— 与「不假装知道」的口径一致。
    private var weekDaily: (values: [Double], labels: String) {
        let cal = TimeFormat.calendar
        let today = cal.startOfDay(for: Date())
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        var values: [Double] = []
        var labels: [String] = []
        for offset in stride(from: 6, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let start = Int64(day.timeIntervalSince1970 * 1000)
            let end = start + 86_400_000
            let n = app.entries.filter {
                $0.at >= start && $0.at < end && ($0.tone == .ok || $0.tone == .live)
            }.count
            values.append(Double(n))
            labels.append(names[cal.component(.weekday, from: day) - 1])
        }
        return (values, labels.joined(separator: "   "))
    }

    private var weekBarsCard: some View {
        // 同上：weekDaily 会按天过滤 7 次，别在 ViewBuilder 里调两回。
        let bars = weekDaily
        return VCard2 {
            VCardHead(eyebrow: "近 7 天开门", statement: "\(weekOpens) 次", trailing: "本机回执")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VRangeCaption(text: bars.labels)
                .padding(.top, V8.S.gapM)
            // cursor 指向今天（最后一格），与记录页 24 小时波形的处理一致。
            VSpark(values: bars.values, tint: V8.C.accentFill, cursor: max(0, bars.values.count - 1), axis: .samples)
                .padding(.top, V8.S.gapS)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("近 7 天开门 \(weekOpens) 次")
    }

    private var judgement: String {
        if activeMembers.isEmpty { return "家里还没有成员" }
        if archivedCount > 0 { return "有 \(archivedCount) 位成员已归档" }
        if weekOpens == 0 { return "这周还没有人开门" }
        return "这周的往来都正常"
    }

    private var lead: String {
        if activeMembers.isEmpty {
            return "手机钥匙要签给具体某个人。先建一位成员，回来就能给他签发。"
        }
        // 2026-11-05（用户指令：减少多余文字、图形化变多）：
        // 「本周开了 N 次门」这句改成由下面的柱图承载（图形说同一件事更省字）。
        // lead 只留别处没有的一条规则。
        return "开门次数只统计本机读到的回执；归档不影响历史记录。"
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            chipRow
        } content: {
            if activeMembers.isEmpty && archivedMembers.isEmpty {
                VEmpty(
                    title: "新建一位成员",
                    reason: "成员是手机钥匙与权限的归属。先建一位，再给他签发钥匙。",
                    actionTitle: "新建成员"
                ) { router.request(.dest(.memberCreate)) }
            } else if showArchived {
                archiveCard
                archiveImpactCard
            } else {
                // 2026-11-05（用户指令：图形化变多）：本页原来**没有任何图形**。
                // 7 日开锁次数是真实序列，画成柱图放在最上面（参考图也是洞察卡在上）。
                weekBarsCard
                memberCard
                entryCard
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.request(.dest(.memberCreate))
                } label: {
                    Image(systemName: "plus")
                        .font(V8.T.chipValue)
                }
                .accessibilityLabel("新建成员")
            }
        }
        .task { await app.reload() }
        .onChange(of: router.pending) { _, _ in
            if case .member(let id) = router.consume(if: { ctx in
                if case .member = ctx { return true }
                return false
            }) {
                router.request(.dest(.memberDetail))
                router.pending = .member(id: id)
            }
        }
    }

    // MARK: - 芯片行

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: V8.S.gapChip) {
                // 2026-11-05（对抗审查 · 设计冗余）：.members 这一格写「N 位」，
                // 而「成员」卡标题写「在册 N 位」—— 同一个数字在相邻两处重复。
                // 成员数由卡片承载。
                //
                // 2026-11-05（截图审查 · 同类）：.week 这一格写「本周 6 次」，
                // 而紧接着的 lead 就是「本周开了 6 次门」—— 芯片正下方一行就是同一个 6。
                // 规则：芯片只承载**别处看不到**的数字。这里 lead 已经说了，芯片删掉。
                ForEach(HouseChip.allCases.filter { $0 != .members && $0 != .week }, id: \.self) { chip in
                    VChip2(icon: chip.icon(app), label: chip.title, value: chip.value(app))
                }
            }
            .padding(.leading, V8.S.gutterCard)
            .padding(.trailing, V8.S.gutterCard)
        }
        .scrollClipDisabled()
    }

    // MARK: - 卡 1 成员

    private var memberCard: some View {
        VCard2 {
            VCardHead(eyebrow: "成员", statement: "在册 \(activeMembers.count) 位")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                ForEach(activeMembers) { member in
                    Button {
                        router.request(.dest(.memberDetail))
                        router.pending = .member(id: member.id)
                    } label: {
                        VDataRow(
                            tag: roleName(member.role),
                            tagTint: roleTint(member.role),
                            title: member.name,
                            detail: HHDisplay.statusWord(HHStats.status(member)),
                            value: "\(member.keyCount)",
                            unit: "枚"
                        )
                    }
                    .buttonStyle(.plain)
                    if member.id != activeMembers.last?.id { VDotRule() }
                }
            }
            .padding(.top, V8.S.gapS)
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("归档的成员仍保留历史记录，记录页还能筛到。" + (archivedCount > 0 ? " 点上面的「归档」看名单与恢复。" : ""))
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapFootnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func roleName(_ role: MemberCard.Role) -> String {
        switch role {
        case .owner: return "主人"
        case .member: return "家人"
        case .guest: return "访客"
        }
    }

    private func roleTint(_ role: MemberCard.Role) -> Color {
        switch role {
        case .owner: return V8.C.accent
        case .member: return V8.D.fingerprint
        case .guest: return V8.C.warn
        }
    }

    // MARK: - 卡 2 入口

    private var entryCard: some View {
        VCard2 {
            VCardHead(eyebrow: "家庭", statement: "三件事")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                VNavRow(title: "成员档案与权限", detail: "角色 / 联系方式 / 备注") {
                    router.request(.dest(.memberDetail))
                }
                VDotRule()
                VNavRow(title: "归档", detail: "已归档 \(archivedCount) 位 · 历史仍在", value: nil) {
                    showArchived = true
                }
                VDotRule()
                VNavRow(title: "成员流转", detail: "借用 / 家政窗 / 访客 / 长辈") {
                    router.request(.dest(.memberOps))
                }
            }
            .padding(.top, V8.S.gapS)
        }
    }

    // MARK: - 归档段（原 memberArchive 页整段并入）

    private var archivedMembers: [MemberCard] { HHStats.archived(app.members) }

    /// 归档名单 + 恢复。恢复链路原样：app.members 投影 + roster.mirrorArchived 落 kf_member_ext。
    /// 刻意没有「全部恢复」—— 恢复必须一位一位点（原页纪律，不许退化）。
    private var archiveCard: some View {
        VCard2 {
            VCardHead(eyebrow: "归档名单", statement: archivedMembers.isEmpty ? "没有归档的成员" : "\(archivedMembers.count) 位",
                      trailing: showArchived ? "返回名册" : nil)
            VDivider2()
                .padding(.top, V8.S.gapM)
            if archivedMembers.isEmpty {
                Text("归档只是从名册与统计里收起，历史一条不删。想收起谁：在成员行进入「成员」，用「档案收尾」里的归档。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(archivedMembers, id: \.id) { member in
                        HStack(spacing: V8.S.gapS) {
                            VDataRow(
                                tag: member.role.rawValue,
                                tagTint: V8.C.ink4,
                                title: member.name,
                                detail: "归档中 · 历史仍在",
                                value: "\(member.keyCount)",
                                unit: "枚"
                            )
                            Button {
                                restoreArchived(member)
                            } label: {
                                Text("恢复")
                                    .font(V8.T.tab)
                                    .foregroundStyle(V8.C.ink1)
                                    .padding(.horizontal, V8.S.gapM)
                                    .frame(minHeight: V8.H.min)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: V8.R.capsule(V8.H.min), style: .continuous)
                                            .strokeBorder(V8.C.line, lineWidth: V8.S.hair)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("恢复 " + member.name)
                        }
                        if member.id != archivedMembers.last?.id { VDotRule() }
                    }
                }
                .padding(.top, V8.S.gapS)
            }
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("归档后记录页仍能筛到 TA，凭证页也仍列 TA 名下凭证 —— 归档不许挡撤权入口。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapFootnote)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showArchived = false
            } label: {
                Text("回到名册")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.ink1)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .overlay(
                        RoundedRectangle(cornerRadius: V8.R.capsule(V8.H.min), style: .continuous)
                            .strokeBorder(V8.C.line, lineWidth: V8.S.hair)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("回到名册")
            .padding(.top, V8.S.gapM)
        }
    }

    /// 归档影响面（原页 impactCard 五行读数，原样保留）。
    private var archiveImpactCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "归档影响面", statement: "逐位可恢复")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                VDataRow(tag: "仍在名册", tagTint: V8.C.ink4, title: "\(activeMembers.count)", value: "位")
                VDotRule()
                VDataRow(tag: "已归档", tagTint: V8.C.ink4, title: "\(archivedMembers.count)", value: "位")
                VDotRule()
                VDataRow(tag: "记录页", tagTint: V8.C.ok, title: "仍能按 TA 筛", value: "")
                VDotRule()
                VDataRow(tag: "凭证页", tagTint: V8.C.ok, title: "仍列 TA 名下凭证", value: "")
                VDotRule()
                VDataRow(tag: "成员统计", tagTint: V8.C.warn, title: "名册里不再出现", value: "")
            }
            .padding(.top, V8.S.gapS)
            Text("恢复是逐位的，没有「全部恢复」—— 那会让人一次把不想回到名册的人也放回来。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func restoreArchived(_ member: MemberCard) {
        guard let i = app.members.firstIndex(where: { $0.id == member.id }) else { return }
        app.members[i] = member.hh(archived: false)
        roster.mirrorArchived(member.id, false)
        AppToast.shared.show("已恢复为在册成员", tone: .ok)
    }

    private var roster: HouseholdRoster { HouseholdRoster.shared }
}

// MARK: - 四个芯片（成员 / 凭证 / 访客 / 本周）

private enum HouseChip: String, CaseIterable, Hashable {
    case members, keys, visitors, week

    var title: String {
        switch self {
        case .members: return "成员"
        case .keys: return "凭证"
        case .visitors: return "访客"
        case .week: return "本周"
        }
    }

    @MainActor
    func value(_ app: AppModel) -> String {
        switch self {
        case .members: return "\(HHStats.active(app.members).count) 位"
        case .keys: return "\(HHStats.ownedKeys(HHStats.active(app.members))) 枚"
        case .visitors: return "\(MemberHub.activityBundle(HHStats.active(app.members).map(\.id)).visitorOpens) 次"
        case .week: return "\(HHStats.weekOpens(app.entries, names: Set(HHStats.active(app.members).map(\.name)))) 次"
        }
    }

    @MainActor
    func icon(_ app: AppModel) -> VChipIcon {
        switch self {
        case .members: return .ring(1, V8.C.accent)
        case .keys: return .ring(0.6, V8.D.fingerprint)
        case .visitors: return .ring(0.3, V8.C.warn)
        case .week: return .ring(0.8, V8.C.ok)
        }
    }
}