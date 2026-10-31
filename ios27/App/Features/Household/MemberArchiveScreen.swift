// MemberArchiveScreen.swift —— 归档成员（460/795：归档只收起，不删历史）。
//
// 这屏干什么：读被归档的成员，逐个恢复；并写清归档期间的影响面（记录页仍能筛到、凭证页仍列名下凭证）。
// 数据从哪来：AppModel.members（archived 位）+ HouseholdRoster（档案扩展与主责）。
// 主动作：逐行「恢复」（刻意不做「全部恢复」，也不给单一 signal 填充 —— 恢复必须一位一位点）。
// 归档动作本身无确认：它不删任何东西，随时能恢复。
import SwiftUI

struct MemberArchiveScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    private var roster: HouseholdRoster { HouseholdRoster.shared }
    private var archived: [MemberCard] { HHStats.archived(app.members) }
    private var active: [MemberCard] { HHStats.active(app.members) }

    var body: some View {
        ScrollView {
            VStack(spacing: T.S.l) {
                header
                if archived.isEmpty { emptyBlock } else { listPanel }
                impactPanel
                backPanel
            }
            .padding(.vertical, T.S.l)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("归档")
        .navigationBarTitleDisplayMode(.inline)
        .animation(T.M.move, value: archived.count)
    }

    private var header: some View {
        HHPageHeader(
            title: "归档",
            overline: "保留历史 · 可随时恢复",
            tone: archived.isEmpty ? .neutral : .ok,
            status: archived.isEmpty
                ? "没有归档的成员 · 全员都在名册里"
                : "有成员在归档里 · 逐位可恢复"
        )
    }

    private var listPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "归档名单", trailing: "\(archived.count) 位")
                VStack(spacing: 0) {
                    ForEach(archived.indices, id: \.self) { index in
                        if index > 0 { HHRule().padding(.vertical, T.S.s) }
                        archivedRow(archived[index])
                    }
                }
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    private func archivedRow(_ member: MemberCard) -> some View {
        VStack(alignment: .leading, spacing: T.S.s) {
            HHMemberRow(
                member: member,
                extras: roster.extras(for: member.id),
                subline: "归档中 · 历史仍在",
                status: .archived
            )
            HStack(spacing: T.S.s) {
                Text("归档后记录页仍能筛到 TA，凭证页也仍列 TA 名下凭证 —— 归档不许挡撤权入口。")
                    .font(T.F.unit)
                    .foregroundStyle(Ink.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: T.S.s)
                Button {
                    restore(member)
                } label: {
                    Text("恢复")
                        .font(T.F.bodyStrong)
                        .foregroundStyle(Ink.ink)
                        .padding(.horizontal, T.S.m)
                        .frame(minHeight: T.Hit.min)
                        .overlay {
                            RoundedRectangle(cornerRadius: T.R.control, style: .continuous)
                                .strokeBorder(Ink.hairline, lineWidth: T.Stroke.hair)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("恢复 \(member.name)")
            }
            .frame(minHeight: T.Hit.min)
        }
        .accessibilityElement(children: .contain)
    }

    private var emptyBlock: some View {
        Panel {
            EmptyPanel(
                title: "没有归档的成员",
                message: "归档只是从名册与统计里收起，历史一条不删。想收起谁：在「家」的成员行上长按，选「归档」。",
                actionTitle: "回到名册",
                systemImage: "archivebox"
            ) {
                router.request(.tab(.household))
            }
            .padding(.vertical, T.S.xxl)
        }
        .padding(.horizontal, T.S.gutter)
    }

    /// 影响面必须明写 —— 归档最容易被误读成「删掉了」。
    private var impactPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "归档影响面", trailing: "逐位可恢复")
                FieldRow(label: "仍在名册", value: "\(active.count)", unit: "位")
                FieldRow(label: "已归档", value: "\(archived.count)", unit: "位")
                HHRule()
                impactRow("记录页仍能按 TA 筛", symbol: "list.bullet.rectangle.portrait")
                HHRule()
                impactRow("凭证页仍列 TA 名下凭证", symbol: "key.horizontal")
                HHRule()
                impactRow("成员统计与名册里不再出现", symbol: "person.2.slash")
                Text("恢复是逐位的，没有「全部恢复」—— 那会让人一次把不想回到名册的人也放回来。")
                    .font(T.F.unit)
                    .foregroundStyle(Ink.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    private func impactRow(_ text: String, symbol: String) -> some View {
        HStack(spacing: T.S.m) {
            Image(systemName: symbol)
                .font(.system(size: T.Icon.m, weight: .regular))
                .foregroundStyle(Ink.inkSub)
                .frame(width: T.Icon.xl, alignment: .leading)
            Text(text)
                .font(T.F.body)
                .foregroundStyle(Ink.ink)
            Spacer(minLength: 0)
        }
        .frame(minHeight: T.Hit.min)
        .accessibilityElement(children: .combine)
    }

    private var backPanel: some View {
        VStack(spacing: T.S.s) {
            SecondaryAction(title: "回到成员名册", systemImage: "person.2") {
                router.request(.tab(.household))
            }
            Text("归档动作本身不做确认：它不删任何东西，随时能恢复。")
                .font(T.F.unit)
                .foregroundStyle(Ink.inkFaint)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, T.S.gutter)
    }

    private func restore(_ member: MemberCard) {
        guard let i = app.members.firstIndex(where: { $0.id == member.id }) else { return }
        app.members[i] = member.hh(archived: false)
        roster.mirrorArchived(member.id, false)
    }
}
