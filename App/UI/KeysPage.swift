//
//  KeysPage.swift
//  凭证页 · 全新重写 (2026-10-21)
//
//  门里「钥匙」域的落地页。
//
//  ═══════════════════════════════════════════════════════════
//  与旧 CredentialsView (2478 行) 的根本区别
//  ═══════════════════════════════════════════════════════════
//
//  旧版: 4 类凭证 (密码/指纹/临时码/OTP) + 排序 + 筛选 chip +
//        智能列表 + 归档区 + 回收站 + 批量操作 + 月历 + 队列…
//        —— 一个"管理器", 打开它要先学会管理。
//
//  新版: 「谁能进」—— 一行一权
//    · 顶部: 生效中的授权 (按到期紧迫度排序)
//    · 中部: 类型分段 (全部/密码/指纹/临时码)
//    · 底部: 待处理 (到期预警/待下发)
//    · 搜索与批量收进 toolbar, 不占主版面
//
//  设计原则:
//    · 一行表达一件事: 谁 / 什么 / 何时到期
//    · 紧急的在前, 用色不用图标堆叠
//    · 危险操作 (删除/停用) 收进滑动菜单
//    · 不用 2×2 网格 (AX 5 倍字体)
//

import SwiftUI

/// 凭证页 —— 门里「钥匙」
struct KeysPage: View {
    @EnvironmentObject private var app: AppState

    @State private var seg: Int = 0          // 0 全部 / 1 密码 / 2 指纹 / 3 临时码
    @State private var search = ""
    @State private var searchActive = false
    @State private var refreshTick = 0
    @State private var showAdd = false

    private var mac: String { app.currentMac }

    var body: some View {
        List {
            if !expiringItems.isEmpty {
                expiringSection
            }
            segmentPicker
            credentialRows
            if rows.isEmpty {
                emptySection
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(XPalette.canvas)
        .navigationTitle("钥匙")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $search, isPresented: $searchActive, prompt: "搜索名称 / 备注 / 归属")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { MembersPage().environmentObject(app) } label: {
                    Image(systemName: "person.2")
                }
                .accessibilityLabel("成员")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                    XHaptics.tick.impactOccurred()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加凭证")
            }
        }
        .sheet(isPresented: $showAdd) {
            AddPwdView(embedded: true)
                .environmentObject(app)
        }
        .id(refreshTick)
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 数据
    // ═══════════════════════════════════════════════════════

    private var pwds: [LedgerPwd] {
        let all = DB.listPwds(mac)
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter { p in
            p.note.localizedCaseInsensitiveContains(q)
                || CredentialOrg.displayPwd(p).localizedCaseInsensitiveContains(q)
                || CredentialOrg.ownerName(p.owner).localizedCaseInsensitiveContains(q)
        }
    }

    private var fps: [LedgerFp] {
        let all = DB.listFps(mac)
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter { f in
            f.name.localizedCaseInsensitiveContains(q)
                || f.note.localizedCaseInsensitiveContains(q)
                || CredentialOrg.ownerName(f.owner).localizedCaseInsensitiveContains(q)
        }
    }

    /// 即将到期 (7 天内) —— 与 Tab 角标同源
    private var expiringItems: [LedgerPwd] {
        CredentialOrg.dueSoonPwds(mac)
    }

    private struct KeyRow: Identifiable {
        let id: String
        let title: String
        let subtitle: String?
        let stateLabel: String
        let stateTone: XToneColor
        let kind: Int      // 0 pwd / 1 fp / 2 temp
        let owner: String?
    }

    private var rows: [KeyRow] {
        var out: [KeyRow] = []
        if seg == 0 || seg == 1 {
            out += pwds.filter { !$0.temp }.map { p in
                let state = CredentialOrg.pwdState(p)
                return KeyRow(
                    id: "p\(p.alias)",
                    title: p.note.isEmpty ? "密码 #\(p.alias)" : p.note,
                    subtitle: subtitleFor(p),
                    stateLabel: CredentialOrg.stateLabel(state),
                    stateTone: toneFor(state),
                    kind: 0,
                    owner: p.owner)
            }
        }
        if seg == 0 || seg == 3 {
            out += pwds.filter { $0.temp }.map { p in
                let state = CredentialOrg.pwdState(p)
                return KeyRow(
                    id: "t\(p.alias)",
                    title: p.note.isEmpty ? "临时码 #\(p.alias)" : p.note,
                    subtitle: subtitleFor(p),
                    stateLabel: CredentialOrg.stateLabel(state),
                    stateTone: toneFor(state),
                    kind: 2,
                    owner: p.owner)
            }
        }
        if seg == 0 || seg == 2 {
            out += fps.map { f in
                KeyRow(
                    id: "f\(f.batch)",
                    title: f.name.isEmpty ? "指纹 #\(f.batch)" : f.name,
                    subtitle: f.note.isEmpty ? nil : f.note,
                    stateLabel: "有效",
                    stateTone: .ok,
                    kind: 1,
                    owner: f.owner)
            }
        }
        return out
    }

    private func subtitleFor(_ p: LedgerPwd) -> String? {
        var parts: [String] = []
        if let o = p.owner, !o.isEmpty {
            let n = CredentialOrg.ownerName(o)
            if !n.isEmpty { parts.append(n) }
        }
        let exp = CredentialOrg.expiryLabel(p.to)
        if !exp.isEmpty { parts.append(exp) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// pwdState 返回 Int —— 0 进行中 / 1 已排期 / 2 已过期
    /// (见 CredentialOrg.pwdState 注释: 按时间窗推断)
    private func toneFor(_ state: Int) -> XToneColor {
        switch state {
        case 0: return .ok
        case 1: return .neutral
        case 2: return .danger
        default: return .neutral
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 视图
    // ═══════════════════════════════════════════════════════

    private var expiringSection: some View {
        Section {
            ForEach(expiringItems.prefix(3), id: \.alias) { p in
                HStack(spacing: XSpace.s) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.system(size: XIcon.sm, weight: .medium))
                        .foregroundStyle(XPalette.warn)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.note.isEmpty ? "密码 #\(p.alias)" : p.note)
                            .vkFont(.subheadline, weight: .medium)
                            .foregroundStyle(XPalette.text)
                        Text(CredentialOrg.expiryLabel(p.to))
                            .vkFont(.caption)
                            .foregroundStyle(XPalette.warn)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(p.note) 即将到期, \(CredentialOrg.expiryLabel(p.to))")
            }
        } header: {
            Text("\(expiringItems.count) 份即将到期")
        }
    }

    private var segmentPicker: some View {
        Section {
            Picker("类型", selection: $seg) {
                Text("全部").tag(0)
                Text("密码").tag(1)
                Text("指纹").tag(2)
                Text("临时码").tag(3)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: XSpace.s, trailing: 0))
        }
    }

    @ViewBuilder
    private var credentialRows: some View {
        if !rows.isEmpty {
            Section {
                ForEach(rows) { row in
                    keyRow(row)
                }
            } header: {
                Text("\(rows.count) 份生效")
            }
        }
    }

    private func keyRow(_ row: KeyRow) -> some View {
        HStack(spacing: XSpace.m) {
            // 类型图标
            Image(systemName: iconFor(row.kind))
                .font(.system(size: XIcon.sm, weight: .medium))
                .foregroundStyle(XPalette.accentText)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .vkFont(.body)
                    .foregroundStyle(XPalette.text)
                    .lineLimit(1)
                if let s = row.subtitle {
                    Text(s)
                        .vkFont(.caption)
                        .foregroundStyle(XPalette.textSub)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: XSpace.s)

            XStatusPill(text: row.stateLabel, tone: row.stateTone)
        }
        .padding(.vertical, XSpace.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title), \(row.stateLabel)")
    }

    private func iconFor(_ kind: Int) -> String {
        switch kind {
        case 1: return "hand.raised.fill"
        case 2: return "clock.fill"
        default: return "key.fill"
        }
    }

    private var emptySection: some View {
        Section {
            VStack(spacing: XSpace.m) {
                Image(systemName: "key.slash")
                    .font(.system(size: XIcon.xl, weight: .light))
                    .foregroundStyle(XPalette.textTertiary)
                    .accessibilityHidden(true)
                Text(search.isEmpty ? "还没有凭证" : "没有匹配的凭证")
                    .vkFont(.headline)
                    .foregroundStyle(XPalette.text)
                Text(search.isEmpty ? "点右上角 + 添加第一份授权" : "换个关键词试试")
                    .vkFont(.subheadline)
                    .foregroundStyle(XPalette.textSub)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, XSpace.xxl)
            .listRowBackground(Color.clear)
        }
    }
}
