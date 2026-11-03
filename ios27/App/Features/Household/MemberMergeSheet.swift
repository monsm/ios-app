// MemberMergeSheet.swift —— 同名成员合并（462）。
//
// 主档保留；副档的凭证归属与认领覆盖迁到主档，然后删除副档。只动本机台账，不碰锁端。
import SwiftUI

struct MemberMergeSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    let primary: MemberCard
    @State private var candidates: [Member] = []
    @State private var secondaryID: String?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: V.S.gap16) {
                    VCard {
                        VStack(alignment: .leading, spacing: V.S.gapMS) {
                            VSectionLabel(text: "主档（保留）")
                            Text(primary.name)
                                .font(V.F.bodyStrong)
                                .foregroundStyle(V.C.text1)
                            SettingsNote(text: "副档名下的密码/指纹归属会迁到这位成员；认领覆盖层一起改判，然后删除副档。")
                        }
                    }
                    .padding(.horizontal, V.S.pageGutter)

                    VCard {
                        VStack(alignment: .leading, spacing: V.S.gapMS) {
                            VSectionLabel(text: "副档（将被删除）", trailing: candidates.isEmpty ? "无" : "\(candidates.count) 位")
                            if candidates.isEmpty {
                                Text("没有同名成员。若只是称呼重复，请先改名再合并。")
                                    .font(V.F.body)
                                    .foregroundStyle(V.C.text2)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                ForEach(candidates) { m in
                                    Button {
                                        secondaryID = m.id
                                    } label: {
                                        HStack(spacing: V.S.gapS) {
                                            Text(m.name)
                                                .font(V.F.body)
                                                .foregroundStyle(V.C.text1)
                                            Spacer(minLength: 0)
                                            if secondaryID == m.id {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(V.C.blue)
                                                    .accessibilityHidden(true)
                                            }
                                        }
                                        .frame(minHeight: V.Hit.min)
                                        .contentShape(.rect)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(m.name)
                                }
                            }
                            if let error {
                                VStatusLine(tone: .critical, text: error)
                            }
                            VActionButton(title: "执行合并", systemImage: "arrow.triangle.merge") {
                                merge()
                            }
                            .disabled(secondaryID == nil)
                            .opacity(secondaryID == nil ? 0.4 : 1)
                        }
                    }
                    .padding(.horizontal, V.S.pageGutter)
                }
                .padding(.vertical, V.S.gap16)
            }
            .background(CanvasBackground())
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

    private func merge() {
        guard let secondaryID else { return }
        // 2026-11-04（错误归因 · 三种情况混成一句）：`merge` 返回 0 有两种原因 ——
        //   ① 前置校验失败（副档不存在 / 与主档不同名）；
        //   ② 校验通过但**没有任何凭证需要迁移**（副档名下本来就空）—— 这种情况下
        //      副档**已经被删掉了**，是成功，不是失败。
        // 旧判据 `moved > 0 || DB.member(secondaryID) == nil` 恰好靠"副档是否还在"
        // 区分这两种，所以行为是对的；但失败分支的文案只列了①的前半段（"副档不存在或
        // 与主档不是同名"），漏了"不同名"以外的可能。现在按真实前置条件说清。
        let moved = MemberMergeKit.merge(primaryID: primary.id, secondaryID: secondaryID)
        if moved > 0 || DB.member(secondaryID) == nil {
            // 2026-11-01（Round 274）：合并会把**凭证的 owner 改判给主档**，而原来只 `reloadMembers()` ——
            // `app.keys` 没重建 ⇒ 凭证页那几条仍显示旧成员名，直到别的原因触发 `reloadKeys`。
            // `reloadKeys()` 内部已顺带 `reloadMembers()`（Round 244），所以只调它一个就够。
            app.reloadKeys()
            dismiss()
        } else {
            // 走到这里 = merge 的前置校验没过（副档已被别处删掉，或两档名字不同）。
            error = "合并没有执行：副档可能已被删除，或与主档的称呼不再相同。刷新这一页后重试。"
        }
    }
}
