// HouseHomeScreen.swift —— 家（Tab 4）· V8 设计语言
//
// 与 HouseholdScreen 的功能对齐：成员概览 / 名单 / 排序入口 / 归档 / 成员流转 / 新建成员。
// 一屏一个英雄数：在册人数只出现在「成员」芯片里，标题不重复。
import SwiftUI

struct HouseHomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    private var activeMembers: [MemberCard] { HHStats.active(app.members) }
    private var archivedCount: Int { HHStats.archived(app.members).count }
    private var ownedKeys: Int { HHStats.ownedKeys(activeMembers) }

    private var weekOpens: Int {
        HHStats.weekOpens(app.entries, names: Set(activeMembers.map(\.name)))
    }

    private var visitorOpens: Int {
        MemberHub.activityBundle(activeMembers.map(\.id)).visitorOpens
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
        var bits: [String] = []
        bits.append("本周开了 \(weekOpens) 次门")
        bits.append("归档不影响历史记录")
        return bits.joined(separator: "，") + "。"
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            chipRow
        } content: {
            if activeMembers.isEmpty {
                VEmpty(
                    title: "还没有成员",
                    reason: "成员是手机钥匙与权限的归属。先建一位，再给他签发钥匙。",
                    actionTitle: "新建成员"
                ) { router.request(.dest(.memberCreate)) }
            } else {
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
                ForEach(HouseChip.allCases, id: \.self) { chip in
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
            Text("归档的成员仍保留历史记录，记录页还能筛到。")
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
                VNavRow(title: "归档", detail: "已归档 \(archivedCount) 位", value: nil) {
                    router.request(.dest(.memberArchive))
                }
                VDotRule()
                VNavRow(title: "成员流转", detail: "借用 / 家政窗 / 访客 / 长辈") {
                    router.request(.dest(.memberOps))
                }
            }
            .padding(.top, V8.S.gapS)
        }
    }
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