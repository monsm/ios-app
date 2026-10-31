// CredentialStudioScreen.swift —— 凭证工作室（批量 / 回收站 / 版本 / 预警 / 导出 / 检测 / 排序）。
//
// 来源：原 App/Core/CredentialOrg.swift + CredentialOrgBatch.swift + CredentialOrgState.swift
//   （347/348/353/357 批量、497-506 回收站、487/488 版本快照、526 星标、359/930 预警、351 凭证包、304/314 检测、355/914 分组排序）。
// 这屏干什么：把凭证页从「单条 CRUD」升级为可整理的一整套工具；批量动作先在本机记账，
//   锁端删除/延期按现有同一条链路（DB 台账 + 页内说明），不虚构待下发队列。
// 数据从哪来：DB.listPwds / DB.listFps / CredentialOrg* / CredBinStore / CredHistoryStore / CredStarStore。
// 主动作：「应用批量延期」—— 同屏唯一实心按钮。
import SwiftUI
import Foundation
import UIKit

struct CredentialStudioScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    enum Sort: String, CaseIterable, Identifiable {
        case starred = "星标优先"
        case recent = "最近添加"
        case expiry = "最早到期"
        case alias = "编号"
        var id: String { rawValue }
    }

    @State private var selectedPwds: Set<Int> = []
    @State private var selectedFps: Set<Int> = []
    @State private var sort: Sort = .starred
    @State private var extendDays = 30
    @State private var prefixText = ""
    @State private var transferOwner: String?
    @State private var packagePassword = ""
    @State private var packageText = ""
    @State private var studioOutcome: String?
    @State private var alertTarget: LedgerPwd?
    @State private var binOpen = false
    @State private var historyOpen = false
    @State private var showPurgeAll = false
    @State private var tick = 0

    private var studioMac: String { app.currentMac }

    private var pwdRows: [LedgerPwd] {
        let _ = tick
        let list = DB.listPwds(studioMac)
        let stars = CredStarStore.all(studioMac)
        let ordered: [LedgerPwd]
        switch sort {
        case .starred:
            ordered = list.sorted { lhs, rhs in
                let l = stars.contains("pwd:\(lhs.alias)"), r = stars.contains("pwd:\(rhs.alias)")
                if l != r { return l }
                return lhs.at > rhs.at
            }
        case .recent: ordered = list
        case .expiry: ordered = list.sorted { $0.to < $1.to }
        case .alias: ordered = list.sorted { $0.alias < $1.alias }
        }
        // 分组模式：按成员时把同一归属排在一起（组内仍保持上面选的排序）。
        guard CredentialOrg.groupMode == .owner else { return ordered }
        return ordered.sorted { CredentialOrg.ownerName($0.owner) < CredentialOrg.ownerName($1.owner) }
    }

    private var fpRows: [LedgerFp] {
        let _ = tick
        return DB.listFps(studioMac)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V.S.gapM) {
                header
                if app.lock == nil {
                    noLockCard
                } else {
                    summaryCard
                    toolsCard
                    selectionCard
                    batchCard
                    auditCard
                    binCard
                    historyCard
                }
            }
            .padding(.top, V.Page.topSpace)
            .padding(.bottom, V.Tab.contentInset)
        }
        .background(V.C.bg.ignoresSafeArea())
        .navigationTitle("凭证工作室")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { tick += 1 }
        .sheet(item: $alertTarget) { pwd in
            CredAlertSheet(mac: studioMac, pwd: pwd)
        }
        .sheet(isPresented: $binOpen) {
            CredBinSheet(mac: studioMac) { tick += 1 }
        }
        .sheet(isPresented: $historyOpen) {
            CredHistorySheet(mac: studioMac) { tick += 1 }
        }
        .alert("清空回收站？", isPresented: $showPurgeAll) {
            Button("取消", role: .cancel) {}
            Button("彻底删除", role: .destructive) { CredBinStore.clear(studioMac); tick += 1 }
        } message: {
            Text("回收站里的记录会被永久删除，不能恢复。锁端凭证不受影响。")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: V.S.gapXXS) {
            Text("凭证工作室")
                .font(V.F.displayA).foregroundStyle(V.C.text1)
            Text("批量整理 · 回收站 · 版本 · 预警 · 导出")
                .font(V.F.footnote).foregroundStyle(V.C.text3)
        }
        .padding(.horizontal, V.S.pageGutterA)
    }

    private var noLockCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapM) {
                Text("还没有门锁").font(V.F.displayB).foregroundStyle(V.C.text1)
                Text("凭证工作室整理的是某一把锁的凭证台账。先添加门锁，再回来。")
                    .font(V.F.body).foregroundStyle(V.C.text2)
                VActionButton(title: "添加门锁", systemImage: "plus") { router.request(.dest(.addLock)) }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private var summaryCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "台账读数")
                VStatPair(items: [
                    ("密码", "\(pwdRows.count) 枚"),
                    ("指纹", "\(fpRows.count) 枚"),
                    ("已选", "\(selectedPwds.count + selectedFps.count) 项"),
                    ("回收站", "\(CredBinStore.all(studioMac).count) 项")
                ])
                Text("排序：\(sort.rawValue) · 分组：\(CredentialOrg.groupMode == .owner ? "按成员" : "按类型")")
                    .font(V.F.micro).foregroundStyle(V.C.text3)
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    // MARK: - 工具条：排序 / 分组 / 版本

    private var toolsCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "整理方式")
                HStack(spacing: V.S.gapS) {
                    ForEach(Sort.allCases) { option in
                        Button { sort = option } label: {
                            VTag(text: option.rawValue, tint: sort == option ? V.C.blue : V.C.text3, filled: sort == option)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: V.S.gapS) {
                    Button {
                        CredentialOrg.setGroupMode(CredentialOrg.groupMode == .owner ? .type : .owner)
                        tick += 1
                    } label: {
                        VTag(text: CredentialOrg.groupMode == .owner ? "分组：按成员" : "分组：按类型", tint: V.C.text1)
                    }
                    .buttonStyle(.plain)
                    Button {
                        CredHistoryStore.capture(studioMac, note: "手动快照")
                        studioOutcome = "已保存当前台账快照"
                        tick += 1
                    } label: {
                        VTag(text: "保存版本快照", tint: V.C.text1)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    // MARK: - 选择列表

    private var selectionCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapXS) {
                HStack {
                    VCardHeader(title: "密码", showsChevron: false)
                    Spacer(minLength: 0)
                    Button(selectedPwds.count == pwdRows.count ? "取消全选" : "全选") {
                        selectedPwds = selectedPwds.count == pwdRows.count ? [] : Set(pwdRows.map(\.alias))
                    }
                    .font(V.F.footnote).foregroundStyle(V.C.blue)
                }
                if pwdRows.isEmpty {
                    Text("还没有密码凭证。去「新增凭证」加一枚。")
                        .font(V.F.footnote).foregroundStyle(V.C.text3)
                } else {
                    ForEach(pwdRows) { pwd in
                        pwdRow(pwd)
                        VDivider()
                    }
                }
                HStack {
                    VCardHeader(title: "指纹", showsChevron: false)
                    Spacer(minLength: 0)
                    Button(selectedFps.count == fpRows.count ? "取消全选" : "全选") {
                        selectedFps = selectedFps.count == fpRows.count ? [] : Set(fpRows.map(\.batch))
                    }
                    .font(V.F.footnote).foregroundStyle(V.C.blue)
                }
                if fpRows.isEmpty {
                    Text("还没有指纹。指纹要在门锁上按 8 次录入。")
                        .font(V.F.footnote).foregroundStyle(V.C.text3)
                } else {
                    ForEach(fpRows) { fp in
                        fpRow(fp)
                        VDivider()
                    }
                }
                if let studioOutcome {
                    Text(studioOutcome).font(V.F.footnote)
                        .foregroundStyle(studioOutcome.hasPrefix("已") ? V.C.rewardGreen : V.C.pink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private func pwdRow(_ pwd: LedgerPwd) -> some View {
        let id = "pwd:\(pwd.alias)"
        let selected = selectedPwds.contains(pwd.alias)
        return HStack(spacing: V.S.gapS) {
            Button {
                if selected { selectedPwds.remove(pwd.alias) } else { selectedPwds.insert(pwd.alias) }
            } label: {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(V.F.bodyLarge)
                    .foregroundStyle(selected ? V.C.blue : V.C.text3)
                    .frame(width: V.List.iconSize, height: V.List.iconSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(selected ? "取消选择" : "选择")
            VStack(alignment: .leading, spacing: V.S.gapXXS) {
                HStack(spacing: V.S.gapXS) {
                    Text(CredentialOrg.displayPwd(pwd)).font(V.F.rowTitle).foregroundStyle(V.C.text1).lineLimit(1)
                    if CredStarStore.isStarred(studioMac, id) {
                        Image(systemName: "star.fill").font(V.F.chipLabel).foregroundStyle(V.C.coral)
                    }
                }
                Text("#\(pwd.alias) · \(CredentialOrg.expiryLabel(pwd.to)) · \(CredentialOrg.stateLabel(CredentialOrg.pwdState(pwd)))")
                    .font(V.F.rowDetail).foregroundStyle(V.C.text3).lineLimit(1)
            }
            Spacer(minLength: V.S.gapS)
            Button {
                CredStarStore.toggle(studioMac, id)
                tick += 1
            } label: {
                Image(systemName: CredStarStore.isStarred(studioMac, id) ? "star.fill" : "star")
                    .font(V.F.cardBody)
                    .foregroundStyle(V.C.coral)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("星标")
            Button("提醒") { alertTarget = pwd }
                .font(V.F.footnote).foregroundStyle(V.C.blue)
        }
        .frame(minHeight: V.List.rowMinHeight)
    }

    private func fpRow(_ fp: LedgerFp) -> some View {
        let selected = selectedFps.contains(fp.batch)
        return HStack(spacing: V.S.gapS) {
            Button {
                if selected { selectedFps.remove(fp.batch) } else { selectedFps.insert(fp.batch) }
            } label: {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(V.F.bodyLarge)
                    .foregroundStyle(selected ? V.C.blue : V.C.text3)
                    .frame(width: V.List.iconSize, height: V.List.iconSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(selected ? "取消选择" : "选择")
            VStack(alignment: .leading, spacing: V.S.gapXXS) {
                Text(fp.name.isEmpty ? "指纹 \(fp.batch)" : fp.name)
                    .font(V.F.rowTitle).foregroundStyle(V.C.text1).lineLimit(1)
                Text("#\(fp.batch) · \(CredentialOrg.ownerName(fp.owner))")
                    .font(V.F.rowDetail).foregroundStyle(V.C.text3).lineLimit(1)
            }
            Spacer(minLength: 0)
            if fp.isAlarm == true {
                VTag(text: "防拆", tint: V.C.coral)
            }
        }
        .frame(minHeight: V.List.rowMinHeight)
    }

    // MARK: - 批量动作

    private var batchCard: some View {
        VCard(style: .warm) {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "批量动作", showsChevron: false)
                Text("批量延期（\(selectedPwds.count) 条密码）")
                    .font(V.F.chipLabel).foregroundStyle(V.C.text4)
                HStack(spacing: V.S.gapS) {
                    ForEach([7, 30, 90, 180], id: \.self) { days in
                        Button { extendDays = days } label: {
                            VTag(text: "\(days) 天", tint: extendDays == days ? V.C.blue : V.C.text3, filled: extendDays == days)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                VActionButton(title: "应用批量延期", systemImage: "calendar.badge.plus") { batchExtend() }
                    .disabled(selectedPwds.isEmpty)
                VRowDivider()
                Text("批量停用：移入本机回收站（可整组还原）；锁端凭证不会自动删除。")
                    .font(V.F.footnote).foregroundStyle(V.C.text3)
                VOutlineButton(title: "停用所选（\(selectedPwds.count + selectedFps.count) 项）", systemImage: "pause.circle") { batchDisable() }
                    .disabled(selectedPwds.isEmpty && selectedFps.isEmpty)
                VRowDivider()
                VTextFieldRow(label: "前缀备注（加到所选凭证备注前）", text: $prefixText, placeholder: "如「2026 春节 · 」")
                VOutlineButton(title: "应用前缀备注", systemImage: "text.badge.plus") { applyPrefix() }
                    .disabled(prefixText.isEmpty || (selectedPwds.isEmpty && selectedFps.isEmpty))
                VRowDivider()
                VValueRow(label: "移交给", value: transferOwner.flatMap { DB.member($0)?.name } ?? "未选择")
                ScrollView(.horizontal) {
                    HStack(spacing: V.S.gapS) {
                        ForEach(app.members.filter { !$0.archived }) { member in
                            Button { transferOwner = member.id } label: {
                                VTag(text: member.name, tint: transferOwner == member.id ? V.C.blue : V.C.text3, filled: transferOwner == member.id)
                            }
                            .buttonStyle(.plain)
                        }
                        Button { transferOwner = nil } label: {
                            VTag(text: "解除归属", tint: V.C.text3)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollIndicators(.hidden)
                VOutlineButton(title: "应用移交", systemImage: "person.crop.circle.badge.checkmark") { applyTransfer() }
                    .disabled(selectedPwds.isEmpty && selectedFps.isEmpty)
                VRowDivider()
                Text("凭证包导出（CredPackage 加密）")
                    .font(V.F.chipLabel).foregroundStyle(V.C.text4)
                VTextFieldRow(label: "包口令（至少 8 位）", text: $packagePassword, placeholder: "导出时设的口令", secure: true)
                VOutlineButton(title: "导出所选凭证包", systemImage: "shippingbox") { exportPackage() }
                    .disabled(packagePassword.count < 8 || (selectedPwds.isEmpty && selectedFps.isEmpty))
                if !packageText.isEmpty {
                    VValueRow(label: "凭证包", value: "\(packageText.count) 字符")
                    VOutlineButton(title: "复制凭证包", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = packageText
                    }
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    // MARK: - 检测

    private var auditCard: some View {
        let weak = pwdRows.filter { CredentialOrg.weakReason($0.pwd ?? "") != nil }
        let duplicates = duplicateGroups
        return VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "弱口令 / 重复检测")
                VStatPair(items: [
                    ("弱口令", "\(weak.count) 条"),
                    ("重复组", "\(duplicates.count) 组")
                ])
                if !weak.isEmpty {
                    Text("弱口令：" + weak.map { "#\($0.alias)" }.joined(separator: "、"))
                        .font(V.F.footnote).foregroundStyle(V.C.coral)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !duplicates.isEmpty {
                    Text("重复串：" + duplicates.map { $0.joined(separator: "/") }.joined(separator: " · "))
                        .font(V.F.footnote).foregroundStyle(V.C.coral)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if weak.isEmpty && duplicates.isEmpty {
                    Text("没有发现弱口令或重复密码。")
                        .font(V.F.footnote).foregroundStyle(V.C.text3)
                }
                Text("判据：少于 6 位 / 全部同一位 / 连续递增递减算弱；同一串数字在同锁或其它锁重复出现会列出。")
                    .font(V.F.micro).foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private var duplicateGroups: [[String]] {
        var byValue: [String: [Int]] = [:]
        for p in pwdRows {
            guard let v = p.pwd, !v.isEmpty else { continue }
            byValue[v, default: []].append(p.alias)
        }
        return byValue.values.filter { $0.count > 1 }.map { $0.map { "#\($0)" } }
    }

    // MARK: - 回收站 / 版本

    private var binCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "回收站")
                let items = CredBinStore.all(studioMac)
                VValueRow(label: "已收", value: "\(items.count) 项", note: "停用/批量删除的凭证在这里，可整组还原或彻底删除。")
                HStack(spacing: V.S.gapS) {
                    VOutlineButton(title: "打开回收站", systemImage: "trash") { binOpen = true }
                    VOutlineButton(title: "清空", systemImage: "trash.slash", tint: V.C.pink) { showPurgeAll = true }
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private var historyCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "版本历史")
                let list = CredHistoryStore.all(studioMac)
                VValueRow(label: "快照", value: "\(list.count) 份", note: "每次「保存版本快照」留一档，最多保留 10 份。")
                VOutlineButton(title: "打开版本历史", systemImage: "clock.arrow.circlepath") { historyOpen = true }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    // MARK: - 动作

    private func batchExtend() {
        guard !selectedPwds.isEmpty else { return }
        let df = DF.cached("yyyy-MM-dd HH:mm")
        let from = df.string(from: Date())
        let to = df.string(from: Date().addingTimeInterval(Double(extendDays) * 86400))
        let r = CredentialOrg.batchExtend(studioMac, Array(selectedPwds), from, to)
        // 引擎只改本机台账；对每条再真下发 0B，失败如实回报。
        Task {
            var ok = 0
            for alias in r.done {
                if case .success = await app.setPasswordExpiry(alias: alias, from: from, to: to) { ok += 1 }
            }
            studioOutcome = "已延期 \(ok) 条（本机 \(r.done.count) 条，失败 \(r.failed.count) 条）"
            tick += 1
        }
    }

    private func batchDisable() {
        let pwdList = pwdRows.filter { selectedPwds.contains($0.alias) }
        let fpList = fpRows.filter { selectedFps.contains($0.batch) }
        let batchId = UUID().uuidString
        CredBinStore.addPwds(studioMac, pwdList, batchId: batchId, source: "批量停用")
        CredBinStore.addFps(studioMac, fpList, batchId: batchId, source: "批量停用")
        let r = CredentialOrg.batchDisable(studioMac, pwdAliases: Array(selectedPwds), fpBatches: Array(selectedFps))
        selectedPwds = []
        selectedFps = []
        studioOutcome = "已停用 \(r.done) 项并移入回收站（失败 \(r.failedPwds.count + r.failedFps.count) 项）"
        tick += 1
    }

    private func applyPrefix() {
        let r = CredentialOrg.batchPrefixNote(studioMac, pwdAliases: Array(selectedPwds), fpBatches: Array(selectedFps), prefix: prefixText)
        studioOutcome = "已给 \(r) 条凭证加前缀备注"
        tick += 1
    }

    private func applyTransfer() {
        for alias in selectedPwds { DB.setPwdOwner(studioMac, alias, transferOwner) }
        for batch in selectedFps { DB.setFpOwner(studioMac, batch, transferOwner) }
        studioOutcome = "已移交 \(selectedPwds.count + selectedFps.count) 项"
        tick += 1
    }

    private func exportPackage() {
        guard let result = CredentialOrg.exportPackage(studioMac,
                                                       pwdAliases: Array(selectedPwds),
                                                       fpBatches: Array(selectedFps),
                                                       password: packagePassword) else {
            studioOutcome = "导出失败：没有可导出的凭证"
            return
        }
        packageText = String(data: result.data, encoding: .utf8) ?? ""
        studioOutcome = "已生成凭证包（\(result.size) 条）"
    }
}

#Preview("CredentialStudioScreen") {
    NavigationStack { CredentialStudioScreen() }
        .environment(AppModel())
        .environment(Router())
}
