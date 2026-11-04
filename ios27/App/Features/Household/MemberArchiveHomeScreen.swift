// MemberArchiveHomeScreen.swift —— 归档成员（V8 设计语言）
//
// 与 MemberArchiveScreen 的能力对齐：列出被归档的成员逐个恢复；写清归档影响面；
// 空态给出去处。刻意没有「全部恢复」—— 恢复必须一位一位点。
import SwiftUI

struct MemberArchiveHomeScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    private var roster: HouseholdRoster { HouseholdRoster.shared }
    private var archived: [MemberCard] { HHStats.archived(app.members) }
    private var active: [MemberCard] { HHStats.active(app.members) }

    private var judgement: String {
        archived.isEmpty ? "没有归档的成员" : "有 \(archived.count) 位在归档里"
    }

    private var lead: String {
        archived.isEmpty
            ? "归档只是从名册与统计里收起，历史一条不删。"
            : "归档只收起，不删历史。逐位可恢复，没有「全部恢复」。"
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            EmptyView()
        } content: {
            if archived.isEmpty {
                VEmpty(
                    title: "没有归档的成员",
                    reason: "归档只是从名册与统计里收起，历史一条不删。想收起谁：在「家」的成员行上长按，选「归档」。",
                    actionTitle: "回到名册"
                ) { router.request(.tab(.household)) }
            } else {
                listCard
            }
            impactCard
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .animation(reduceMotion ? nil : V8.M.move, value: archived.count)
    }

    private var listCard: some View {
        VCard2 {
            VCardHead(eyebrow: "归档名单", statement: "\(archived.count) 位")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                ForEach(archived, id: \.id) { member in
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
                            restore(member)
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
                    if member.id != archived.last?.id { VDotRule() }
                }
            }
            .padding(.top, V8.S.gapS)
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("归档后记录页仍能筛到 TA，凭证页也仍列 TA 名下凭证 —— 归档不许挡撤权入口。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapFootnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var impactCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "归档影响面", statement: "逐位可恢复")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                VDataRow(tag: "仍在名册", tagTint: V8.C.ink4, title: "\(active.count)", value: "位")
                VDotRule()
                VDataRow(tag: "已归档", tagTint: V8.C.ink4, title: "\(archived.count)", value: "位")
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

    private func restore(_ member: MemberCard) {
        guard let i = app.members.firstIndex(where: { $0.id == member.id }) else { return }
        app.members[i] = member.hh(archived: false)
        roster.mirrorArchived(member.id, false)
        AppToast.shared.show("已恢复为在册成员", tone: .ok)
    }
}
