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
        let moved = MemberMergeKit.merge(primaryID: primary.id, secondaryID: secondaryID)
        if moved > 0 || DB.member(secondaryID) == nil {
            app.reloadMembers()
            dismiss()
        } else {
            error = "合并失败：副档不存在或与主档不是同名"
        }
    }
}
