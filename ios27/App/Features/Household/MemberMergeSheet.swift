// MemberMergeSheet.swift —— 同名成员合并（V8 设计语言）
//
// 主档保留；副档的凭证归属与认领覆盖迁到主档，然后删除副档。只动本机台账，不碰锁端。
//
// 2026-11-04（Round 16 · S4 复核）：成员详情页已迁到 V8，而这个 sheet 仍是 V7 渲染层 ——
// 从 V8 页面弹出一张 V7 卡片，同一个交互里两套设计语言。只改渲染层：
// MemberMergeKit.candidates / merge 与 app.reloadKeys() 原样。
import SwiftUI

struct MemberMergeSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    let primary: MemberCard
    @State private var candidates: [Member] = []
    @State private var secondaryID: String?
    @State private var error: String?
    /// 2026-11-04（破坏性操作缺确认）：合并会**永久删除副档**，原来点「执行合并」直接执行。
    @State private var confirmMerge = false

    private var judgement: String {
        if candidates.isEmpty { return "没有可以合并的副档" }
        if secondaryID == nil { return "选一位要被合并的副档" }
        return "合并后只剩「\(primary.name)」"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(judgement)
                        .font(V8.T.title2)
                        .foregroundStyle(V8.C.ink1)
                        .tracking(V8.G.heroNumberTracking / 3)
                        .padding(.horizontal, V8.S.padCard)
                        .padding(.top, V8.S.gapSection)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("副档名下的密码与指纹归属会迁到这位成员；认领覆盖层一起改判，然后副档被删除。只动本机台账，不碰锁端。")
                        .font(V8.T.bodyL)
                        .foregroundStyle(V8.C.ink3)
                        .lineSpacing(V8.L.bodyL - V8.T.bodyL.size)
                        .padding(.horizontal, V8.S.padCard)
                        .padding(.top, V8.S.gapTitleBody)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: V8.S.gapCard) {
                        primaryCard
                        secondaryCard
                    }
                    .padding(.top, V8.S.gapBodyCard)
                }
                .padding(.horizontal, V8.S.gutterCard)
                .padding(.bottom, V8.S.gapXXL)
            }
            .scrollIndicators(.hidden)
            .background(V8.C.bg.ignoresSafeArea())
            .v8Confirm(
                isPresented: $confirmMerge,
                title: "确认合并并删除副档？",
                consequence: "副档名下的密码与指纹归属会迁到「\(primary.name)」，认领记录一起改判，然后副档被永久删除 —— 这一步没有撤销。只动本机台账，不碰锁端。",
                confirmTitle: "合并并删除",
                isDestructive: true
            ) {
                merge()
            }
            .navigationTitle("重复合并")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }.accessibilityLabel("取消")
                }
            }
        }
        .onAppear {
            candidates = MemberMergeKit.candidates(primaryID: primary.id)
        }
    }

    // MARK: - 卡 1 主档

    private var primaryCard: some View {
        VCard2 {
            VCardHead(eyebrow: "主档（保留）", statement: primary.name, trailing: "留")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("副档名下的密码与指纹归属会迁到这位成员；认领覆盖层一起改判，然后删除副档。")
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink3)
                .lineSpacing(V8.L.body - V8.T.body.size)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 卡 2 副档

    private var secondaryCard: some View {
        VCard2 {
            VCardHead(
                eyebrow: "副档（将被删除）",
                statement: candidates.isEmpty ? "没有同名成员" : "\(candidates.count) 位候选",
                trailing: candidates.isEmpty ? nil : "\(candidates.count) 位"
            )
            VDivider2()
                .padding(.top, V8.S.gapM)
            if candidates.isEmpty {
                Text("没有同名成员。若只是称呼重复，请先改名再合并。")
                    .font(V8.T.body)
                    .foregroundStyle(V8.C.ink3)
                    .lineSpacing(V8.L.body - V8.T.body.size)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(candidates.enumerated()), id: \.element.id) { pair in
                        candidateRow(pair.element)
                        if pair.offset != candidates.count - 1 { VDotRule() }
                    }
                }
                .padding(.top, V8.S.gapS)
                if let error {
                    // 2026-11-05（语义审计）：原来写「刷新这一页后重试」—— 但这是个弹层，没有刷新入口。
                // 真正的重试动作就是下面那颗「执行合并」。
                VFailure(what: "合并没有执行", why: error, next: "再点一次下面的「执行合并」；两边档案都还没改。")
                        .padding(.top, V8.S.gapM)
                }
                Button {
                    confirmMerge = true
                } label: {
                    Text("执行合并")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.chipOn)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.dangerFill))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("执行合并并删除副档")
                .disabled(secondaryID == nil)
                .opacity(secondaryID == nil ? 0.4 : 1)
                .padding(.top, V8.S.gapM)
                Text(secondaryID == nil
                     ? "先选一位副档，再执行合并。"
                     : "合并会永久删除副档，没有撤销入口。")
                    .font(V8.T.footnote)
                    .foregroundStyle(secondaryID == nil ? V8.C.ink4 : V8.C.danger)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func candidateRow(_ m: Member) -> some View {
        let on = secondaryID == m.id
        return Button {
            secondaryID = m.id
        } label: {
            HStack(spacing: V8.S.gapS) {
                Text(m.name)
                    .font(V8.T.value)
                    .foregroundStyle(V8.C.ink1)
                    .lineLimit(1)
                Spacer(minLength: V8.S.gapS)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(V8.T.chipValue)
                    .foregroundStyle(on ? V8.C.accent : V8.C.ink4)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: V8.H.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(m.name)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - 动作（原样）

    private func merge() {
        guard let secondaryID else { return }
        // 2026-11-04（错误归因 · 三种情况混成一句）：`merge` 返回 0 有两种原因 ——
        //   ① 前置校验失败（副档不存在 / 与主档不同名）；
        //   ② 校验通过但**没有任何凭证需要迁移**（副档名下本来就空）—— 这种情况下
        //      副档**已经被删掉了**，是成功，不是失败。
        // 旧判据 `moved > 0 || DB.member(secondaryID) == nil` 恰好靠"副档是否还在"
        // 区分这两种，所以行为是对的；但失败分支的文案只列了①的前半段。
        let moved = MemberMergeKit.merge(primaryID: primary.id, secondaryID: secondaryID)
        if moved > 0 || DB.member(secondaryID) == nil {
            // 2026-11-01（Round 274）：合并会把**凭证的 owner 改判给主档**，而原来只 `reloadMembers()` ——
            // `app.keys` 没重建 ⇒ 凭证页那几条仍显示旧成员名。
            // `reloadKeys()` 内部已顺带 `reloadMembers()`，所以只调它一个就够。
            app.reloadKeys()
            dismiss()
        } else {
            error = "合并没有执行：副档可能已被删除，或与主档的称呼不再相同。刷新这一页后重试。"
        }
    }
}
