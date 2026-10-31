// MemberArchiveScreen.swift —— 归档成员（460/795：归档只收起，不删历史）。
//
// 这屏干什么：读被归档的成员，逐个恢复；并写清归档期间的影响面（记录页仍能筛到、凭证页仍列名下凭证）。
// 数据从哪来：AppModel.members（archived 位）+ HouseholdRoster（档案扩展与主责）。
// 主动作：逐行「恢复」（刻意不做「全部恢复」，也不给单一 signal 填充 —— 恢复必须一位一位点）。
// 归档动作本身无确认：它不删任何东西，随时能恢复。
import SwiftUI

struct MemberArchiveScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    private var roster: HouseholdRoster { HouseholdRoster.shared }
    private var archived: [MemberCard] { HHStats.archived(app.members) }
    private var active: [MemberCard] { HHStats.active(app.members) }

    var body: some View {
        ScrollView {
            VStack(spacing: V.S.gap16) {
                header
                if archived.isEmpty { emptyBlock } else { listPanel }
                impactPanel
                backPanel
            }
            .padding(.vertical, V.S.gap16)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("归档")
        .navigationBarTitleDisplayMode(.inline)
        .animation(reduceMotion ? nil : V.M.move, value: archived.count)
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
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "归档名单", trailing: "\(archived.count) 位")
                VStack(spacing: 0) {
                    ForEach(archived.indices, id: \.self) { index in
                        if index > 0 { HHRule().padding(.vertical, V.S.gapS) }
                        archivedRow(archived[index])
                    }
                }
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    private func archivedRow(_ member: MemberCard) -> some View {
        VStack(alignment: .leading, spacing: V.S.gapS) {
            HHMemberRow(
                member: member,
                extras: roster.extras(for: member.id),
                subline: "归档中 · 历史仍在",
                status: .archived
            )
            HStack(spacing: V.S.gapS) {
                Text("归档后记录页仍能筛到 TA，凭证页也仍列 TA 名下凭证 —— 归档不许挡撤权入口。")
                    .font(V.F.unit)
                    .foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: V.S.gapS)
                Button {
                    restore(member)
                } label: {
                    Text("恢复")
                        .font(V.F.bodyStrong)
                        .foregroundStyle(V.C.text1)
                        .padding(.horizontal, V.S.gapMS)
                        .frame(minHeight: V.Hit.min)
                        .overlay {
                            RoundedRectangle(cornerRadius: V.R.control, style: .continuous)
                                .strokeBorder(V.C.hairline, lineWidth: V.S.hair)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("恢复 \(member.name)")
            }
            .frame(minHeight: V.Hit.min)
        }
        .accessibilityElement(children: .contain)
    }

    private var emptyBlock: some View {
        VCard {
            VEmptyState(
                title: "没有归档的成员",
                message: "归档只是从名册与统计里收起，历史一条不删。想收起谁：在「家」的成员行上长按，选「归档」。",
                actionTitle: "回到名册",
                systemImage: "archivebox"
            ) {
                router.request(.tab(.household))
            }
            .padding(.vertical, V.S.gapXXL)
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    /// 影响面必须明写 —— 归档最容易被误读成「删掉了」。
    private var impactPanel: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "归档影响面", trailing: "逐位可恢复")
                VFieldRow(label: "仍在名册", value: "\(active.count)", unit: "位")
                VFieldRow(label: "已归档", value: "\(archived.count)", unit: "位")
                HHRule()
                impactRow("记录页仍能按 TA 筛", symbol: "list.bullet.rectangle.portrait")
                HHRule()
                impactRow("凭证页仍列 TA 名下凭证", symbol: "key.horizontal")
                HHRule()
                impactRow("成员统计与名册里不再出现", symbol: "person.2.slash")
                Text("恢复是逐位的，没有「全部恢复」—— 那会让人一次把不想回到名册的人也放回来。")
                    .font(V.F.unit)
                    .foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    private func impactRow(_ text: String, symbol: String) -> some View {
        HStack(spacing: V.S.gapMS) {
            Image(systemName: symbol)
                .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                .font(V.F.icon18)
                .foregroundStyle(V.C.text2)
                .frame(width: V.Icon.xl, alignment: .leading)
            Text(text)
                .font(V.F.body)
                .foregroundStyle(V.C.text1)
            Spacer(minLength: 0)
        }
        .frame(minHeight: V.Hit.min)
        .accessibilityElement(children: .combine)
    }

    private var backPanel: some View {
        VStack(spacing: V.S.gapS) {
            VOutlineButton(title: "回到成员名册", systemImage: "person.2") {
                router.request(.tab(.household))
            }
            Text("归档动作本身不做确认：它不删任何东西，随时能恢复。")
                .font(V.F.unit)
                .foregroundStyle(V.C.text3)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    private func restore(_ member: MemberCard) {
        guard let i = app.members.firstIndex(where: { $0.id == member.id }) else { return }
        app.members[i] = member.hh(archived: false)
        roster.mirrorArchived(member.id, false)
    }
}
