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
                            Text(CredentialOrg.displayPwd(pwd) + " · #\(pwd.alias)")
                                .font(V.F.body).foregroundStyle(V.C.text1)
                            if pwd.to.hasPrefix("2118") {
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
                                            Text("\(TimeFormat.dayShort(Int64(snap.at))) \(TimeFormat.clock(Int64(snap.at))) · \(snap.pwds.count) 密码 / \(snap.fps.count) 指纹")
                                                .font(V.F.rowDetail).foregroundStyle(V.C.text3)
                                        }
                                        Spacer(minLength: V.S.gapS)
                                        Button("恢复") {
                                            CredHistoryStore.restore(mac, snap)
                                            outcome = "已恢复这一版"
                                            onChange()
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
        }
    }

    private func capture() {
        CredHistoryStore.capture(mac, note: "手动快照")
        items = CredHistoryStore.all(mac)
        outcome = "已保存快照"
    }
}
