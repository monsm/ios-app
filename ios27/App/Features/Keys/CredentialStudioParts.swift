// CredentialStudioParts.swift —— 凭证工作室的三个弹层（预警档 / 回收站 / 版本历史）。
//
// 来源：原 App/UI/CredentialOtp.swift 的 toggleAlerts（359/930 五档预警）
//   与 App/Core/CredentialOrg.swift 的 kf_cbin_ / kf_chist_。
import SwiftUI

// MARK: - 到期预警（五档 + 到期时）

struct CredAlertSheet: View {
    let mac: String
    let pwd: LedgerPwd
    @Environment(\.dismiss) private var dismiss
    @State private var alert = CredAlert()

    private let tiers: [(key: String, label: String, get: (CredAlert) -> Bool, set: (inout CredAlert) -> Void)] = [
        ("day", "到期前 7 天", { $0.day }, { $0.day.toggle() }),
        ("d3", "到期前 3 天", { $0.d3 }, { $0.d3.toggle() }),
        ("d1", "到期前 1 天", { $0.d1 }, { $0.d1.toggle() }),
        ("h24", "到期前 24 小时", { $0.h24 }, { $0.h24.toggle() }),
        ("h2", "到期前 2 小时", { $0.h2 }, { $0.h2.toggle() })
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: V.S.gapM) {
                    VCard {
                        VStack(alignment: .leading, spacing: V.S.gapS) {
                            VCardHeader(title: "到期预警")
                            // displayPwd 已含「#alias」，再拼一次会显示成「… 的密码 #3 · #3」。
                            Text(CredentialOrg.displayPwd(pwd))
                                .font(V.F.body).foregroundStyle(V.C.text1)
                            // 与引擎同口径（`expiryDate == nil` 即永久），不自己写 `hasPrefix`。
                            if CredentialOrg.expiryDate(pwd) == nil {
                                Text("长期有效密码没有到期点，不适用预警。")
                                    .font(V.F.footnote).foregroundStyle(V.C.text3)
                            } else {
                                Text("到期：\(CredentialOrg.expiryLabel(pwd.to, verb: false))")
                                    .font(V.F.footnote).foregroundStyle(V.C.text3)
                            }
                        }
                    }
                    .padding(.horizontal, V.S.cardGutter)
                    VCard {
                        VStack(alignment: .leading, spacing: V.S.gapXS) {
                            ForEach(Array(tiers.enumerated()), id: \.offset) { pair in
                                let tier = pair.element
                                VToggleRow(title: tier.label, detail: nil, isOn: Binding(
                                    get: { tier.get(alert) },
                                    set: { _ in
                                        var next = alert
                                        tier.set(&next)
                                        alert = next
                                        CredentialOrg.saveAlert(mac, pwd, next)
                                        CredentialOrg.scheduleAlerts(mac, pwd, next)
                                    }
                                ))
                            }
                            Text("到期时那一条总会跟着走：开了任意档就代表你在意这条凭证的到期。")
                                .font(V.F.micro).foregroundStyle(V.C.text3)
                        }
                    }
                    .padding(.horizontal, V.S.cardGutter)
                    VActionButton(title: "完成") { dismiss() }
                        .padding(.horizontal, V.S.cardGutter)
                }
                .padding(.top, V.Page.topSpace)
                .padding(.bottom, V.S.gapL)
            }
            .background(V.C.bg.ignoresSafeArea())
            .navigationTitle("预警")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { alert = CredentialOrg.alert(mac, pwd) }
    }
}

// MARK: - 回收站

// 2026-11-03：版本历史恢复的待确认目标（放在文件级，供 CredHistorySheet 使用）。
private struct HistoryRestoreTarget: Identifiable {
    let id: String
    let snap: CredSnapshot
}

struct CredBinSheet: View {
    let mac: String
    var onChange: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var items: [CredBinItem] = []
    @State private var outcome: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: V.S.gapM) {
                    if items.isEmpty {
                        VCard {
                            Text("回收站是空的。停用或批量删除的凭证会先来到这里。")
                                .font(V.F.body).foregroundStyle(V.C.text2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, V.S.cardGutter)
                    } else {
                        VCard {
                            VStack(spacing: 0) {
                                ForEach(items) { item in
                                    HStack(spacing: V.S.gapS) {
                                        VStack(alignment: .leading, spacing: V.S.gapXXS) {
                                            Text(item.pwd.map { CredentialOrg.displayPwd($0) } ?? item.fp?.name ?? "凭证")
                                                .font(V.F.rowTitle).foregroundStyle(V.C.text1).lineLimit(1)
                                            Text("\(item.source) · \(TimeFormat.dayShort(Int64(item.at)))")
                                                .font(V.F.rowDetail).foregroundStyle(V.C.text3)
                                        }
                                        Spacer(minLength: V.S.gapS)
                                        Button("还原") {
                                            if CredBinStore.restore(mac, item) {
                                                outcome = "已还原"
                                                reload()
                                            } else if let a = item.pwd?.alias {
                                                // 失败必须说原因：静默失败会让人以为"点了没反应"。
                                                outcome = "还原失败：编号 #\(a) 已被其它凭证占用（锁端会复用删除后的槽位），请先在锁上处理那一条"
                                            }
                                        }
                                        .font(V.F.footnote).foregroundStyle(V.C.blue)
                                        Button("彻底删除") {
                                            CredBinStore.purge(mac, item)
                                            outcome = "已彻底删除"
                                            reload()
                                        }
                                        .font(V.F.footnote).foregroundStyle(V.C.pink)
                                    }
                                    .frame(minHeight: V.List.rowMinHeight)
                                    VDivider()
                                }
                            }
                        }
                        .padding(.horizontal, V.S.cardGutter)
                    }
                    if let outcome {
                        Text(outcome).font(V.F.footnote).foregroundStyle(V.C.rewardGreen)
                            .padding(.horizontal, V.S.cardGutter)
                    }
                }
                .padding(.top, V.Page.topSpace)
            }
            .background(V.C.bg.ignoresSafeArea())
            .navigationTitle("回收站")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear { reload() }
        }
    }

    private func reload() {
        items = CredBinStore.all(mac)
        onChange()
    }
}

// MARK: - 版本历史

struct CredHistorySheet: View {
    let mac: String
    var onChange: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var items: [CredSnapshot] = []
    @State private var outcome: String?
    @State private var restoreTarget: HistoryRestoreTarget?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: V.S.gapM) {
                    if items.isEmpty {
                        VCard {
                            VStack(alignment: .leading, spacing: V.S.gapM) {
                                Text("还没有版本快照").font(V.F.bodyStrong).foregroundStyle(V.C.text1)
                                Text("在工作室点「保存版本快照」，之后就能对比/恢复到任意一档。")
                                    .font(V.F.footnote).foregroundStyle(V.C.text3)
                                VActionButton(title: "保存快照", systemImage: "camera") { capture() }
                            }
                        }
                        .padding(.horizontal, V.S.cardGutter)
                    } else {
                        VCard {
                            VStack(spacing: 0) {
                                ForEach(items) { snap in
                                    HStack(spacing: V.S.gapS) {
                                        VStack(alignment: .leading, spacing: V.S.gapXXS) {
                                            Text(snap.note.isEmpty ? "快照" : snap.note)
                                                .font(V.F.rowTitle).foregroundStyle(V.C.text1)
                                            Text("\(TimeFormat.dayShort(Int64(snap.at))) \(TimeDisplay.clock(Int64(snap.at))) · \(snap.pwds.count) 密码 / \(snap.fps.count) 指纹")
                                                .font(V.F.rowDetail).foregroundStyle(V.C.text3)
                                        }
                                        Spacer(minLength: V.S.gapS)
                                        Button("恢复") {
                                            // 2026-11-03（全功能点排查）：**这一下会整表替换台账** ——
                                            // 快照之后新增的凭证会从本机消失（锁端仍在，但 App 里看不到了）。
                                            // 原来是单击直达、只回一句「已恢复这一版」。现在先确认，并在替换前
                                            // 自动把**当前**状态存成一份快照 —— 恢复本身因此变成可撤销的。
                                            restoreTarget = snap
                                        }
                                        .font(V.F.footnote).foregroundStyle(V.C.blue)
                                    }
                                    .frame(minHeight: V.List.rowMinHeight)
                                    VDivider()
                                }
                            }
                        }
                        .padding(.horizontal, V.S.cardGutter)
                        VActionButton(title: "保存当前为快照", systemImage: "camera") { capture() }
                            .padding(.horizontal, V.S.cardGutter)
                    }
                    if let outcome {
                        Text(outcome).font(V.F.footnote).foregroundStyle(V.C.rewardGreen)
                            .padding(.horizontal, V.S.cardGutter)
                    }
                }
                .padding(.top, V.Page.topSpace)
            }
            .background(V.C.bg.ignoresSafeArea())
            .navigationTitle("版本历史")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } }
            }
            .onAppear { items = CredHistoryStore.all(mac) }
            .confirmationDialog("用这一版覆盖当前凭证列表？", isPresented: Binding(
                get: { restoreTarget != nil }, set: { if !$0 { restoreTarget = nil } }
            ), titleVisibility: .visible, presenting: restoreTarget) { target in
                Button("恢复", role: .destructive) { restore(target.snap) }
                Button("取消", role: .cancel) { restoreTarget = nil }
            } message: { target in
                Text("「\(target.snap.note.isEmpty ? "快照" : target.snap.note)」（\(target.snap.pwds.count) 密码 / \(target.snap.fps.count) 指纹）会**替换**当前台账：这份快照之后新增的凭证会从本机消失（锁端仍在，但 App 里看不到）。恢复前会自动把当前状态存成一份快照，随时可以再切回来。")
            }
        }
    }

    private func restore(_ snap: CredSnapshot) {
        // 先把「现在」存一份 —— 否则这次替换不可撤销。
        CredHistoryStore.capture(mac, note: "恢复前自动快照")
        CredHistoryStore.restore(mac, snap)
        items = CredHistoryStore.all(mac)
        restoreTarget = nil
        outcome = "已恢复这一版（已自动备份替换前的状态）"
        onChange()
    }

    private func capture() {
        CredHistoryStore.capture(mac, note: "手动快照")
        items = CredHistoryStore.all(mac)
        outcome = "已保存快照"
    }
}

// MARK: - 凭证包导入

/// 粘贴一段工作室导出的加密文本 + 口令，合并进当前台账。
/// 冲突项（同 alias / 同 batch）**跳过不覆盖** —— 包里的编号是导出那台锁分配的。
struct PackageImportSheet: View {
    let mac: String
    var onImported: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var password = ""
    @State private var error: String?
    @State private var result: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: V.S.gap16) {
                    SettingsHeader(title: "导入凭证包", tone: error == nil ? .neutral : .attention,
                                   status: error ?? "粘贴导出时拿到的整段文本，再输入当时设的口令")
                    VCard {
                        VStack(alignment: .leading, spacing: V.S.gapMS) {
                            Text("凭证包文本")
                                .font(V.F.unit).foregroundStyle(V.C.text3)
                            TextEditor(text: $text)
                                .font(V.F.stamp)
                                .frame(minHeight: 140)
                                .scrollContentBackground(.hidden)
                                .padding(V.S.gapS)
                                .background(V.C.cardAlt, in: .rect(cornerRadius: V.R.control))
                                .accessibilityLabel("凭证包文本")
                            VTextFieldRow(label: "包口令", text: $password, placeholder: "导出时设的口令", secure: true)
                            if let error {
                                VStatusLine(tone: .critical, text: error)
                            }
                            if let result {
                                VStatusLine(tone: .ok, text: result)
                            }
                            VActionButton(title: "导入", systemImage: "square.and.arrow.down") {
                                run()
                            }
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                            VOutlineButton(title: "关闭") { dismiss() }
                        }
                    }
                    .padding(.horizontal, V.S.pageGutter)
                    SettingsNote(text: "导入是**合并**：同编号的凭证会被跳过（不覆盖本机已有的），导入结果会如实报出写入与跳过的条数。")
                        .padding(.horizontal, V.S.pageGutter)
                }
                .padding(.vertical, V.S.gap16)
            }
            .background(CanvasBackground())
            .scrollEdgeEffectStyle(.soft, for: .top)
            .navigationTitle("导入凭证包")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func run() {
        error = nil
        result = nil
        do {
            let r = try CredentialOrg.importPackage(text, password: password, into: mac)
            if r.imported == 0 {
                error = "没有可导入的凭证：\(r.skipped) 项与现有凭证编号冲突（已全部跳过）"
                return
            }
            result = "已导入 \(r.imported) 项" + (r.skipped > 0 ? "，跳过 \(r.skipped) 项（编号冲突）" : "")
            onImported()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
