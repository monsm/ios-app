//
//  MembersPage.swift
//  成员中心 · 全新重写 (2026-10-21)
//
//  门里「钥匙」→ 成员的落地页。
//
//  ═══════════════════════════════════════════════════════════
//  与旧 MemberCenterView (1881 行) 的区别
//  ═══════════════════════════════════════════════════════════
//
//  旧版: 成员名册 + 分组 chip + 归档 + 场景 + 导航 + 权限矩阵 +
//        归属图谱 + 活跃总表 + 匿名认领 + 家庭设置 + 长辈模式…
//        —— 12 个子视图堆在一个入口页。
//
//  新版: 一份"谁在这个家"的名册
//    · 每人一行: 头像色点 + 名字 + 角色 + 名下凭证数
//    · 点行 → 详情 (保留 MemberDetail360View)
//    · 右上 + → 新增向导 (保留 MemberWizardView)
//    · 底部: 归档 / 匿名认领 / 分组 三个次要入口
//
//  设计原则:
//    · 名册优先: 成员页就该是"名单", 不是"管理中心"
//    · 每行带当下值: 几份凭证 / 最近活跃
//    · 次要功能收进底部, 不抢主版面
//

import SwiftUI

/// 成员中心 —— 门里「钥匙」→ 成员
struct MembersPage: View {
    @EnvironmentObject private var app: AppState

    @State private var members: [Member] = []
    @State private var showWizard = false
    @State private var refreshTick = 0

    private var mac: String { app.currentMac }

    var body: some View {
        // M5 重做: List → 卡片流
        //
        // 与 KeysPage 同一套语言: XPanel 分组 + 组内行 + 液态玻璃只在需要时用。
        // 数据逻辑（reload / members / mac）一行没动。
        ScrollView {
            VStack(spacing: XSpace.l) {
                if members.isEmpty {
                    emptyCard
                } else {
                    // 先头像带（认人），再卡片（看细节）
                    avatarStrip
                    rosterCard
                }
                secondaryCard
            }
            .padding(.horizontal, XSpace.gutter)
            .padding(.top, XSpace.s)
            .padding(.bottom, XSpace.xxl)
        }
        .background(XPalette.canvas)
        .navigationTitle("成员")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showWizard = true
                    XHaptics.tick.impactOccurred()
                } label: {
                    Image(systemName: "person.badge.plus")
                }
                .accessibilityLabel("新增成员")
            }
        }
        .sheet(isPresented: $showWizard) {
            MemberWizardView()
                .environmentObject(app)
        }
        .onAppear { reload() }
        .id(refreshTick)
    }

    // ── 成员卡 ──
    // ── 横向大头像条 ──
    //
    // M5 形态: 成员页的识别锚点是**脸**，不是文字行。
    // 所以顶部先给一条横向头像带 —— 一眼认全家人，
    // 下面的卡片再给细节。
    private var avatarStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: XSpace.l) {
                ForEach(members) { m in
                    NavigationLink {
                        MemberDetail360View(memberID: m.id)
                            .environmentObject(app)
                    } label: {
                        VStack(spacing: XSpace.xs) {
                            ZStack {
                                Circle()
                                    .fill(memberColor(m).opacity(0.14))
                                Circle()
                                    .strokeBorder(memberColor(m), lineWidth: 2)
                                Text(String(MemberHub.display(m).prefix(1)))
                                    .xFont(.title2, weight: .semibold)
                                    .foregroundStyle(memberColor(m))
                            }
                            .frame(width: 64, height: 64)

                            Text(MemberHub.display(m))
                                .xFont(.footnote, weight: .medium)
                                .foregroundStyle(XPalette.text)
                                .lineLimit(1)

                            Text(MemberHub.roleLabel(MemberHub.ext(m.id).role))
                                .xFont(.caption2)
                                .foregroundStyle(XPalette.textTertiary)
                        }
                        .frame(width: 68)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(MemberHub.display(m)), \(MemberHub.roleLabel(MemberHub.ext(m.id).role))")
                }
            }
            .padding(.horizontal, XSpace.gutter)
        }
    }

    private var rosterCard: some View {
        XPanel(kind: .group, padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("\(members.count) 位成员")
                        .xFont(.caption, weight: .medium)
                        .foregroundStyle(XPalette.textSub)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, XSpace.card)
                .padding(.top, XSpace.m)
                .padding(.bottom, XSpace.s)

                ForEach(Array(members.enumerated()), id: \.element.id) { idx, m in
                    NavigationLink {
                        MemberDetail360View(memberID: m.id)
                            .environmentObject(app)
                    } label: {
                        memberRow(m)
                    }
                    .buttonStyle(.plain)
                    if idx < members.count - 1 {
                        Divider().overlay(XPalette.hairline)
                            .padding(.leading, XSpace.card + 40 + XSpace.m)
                    }
                }

                Text("点一位成员可看名下凭证、授权来源与最近活动。")
                    .xFont(.caption2)
                    .foregroundStyle(XPalette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, XSpace.card)
                    .padding(.top, XSpace.s)
                    .padding(.bottom, XSpace.m)
            }
        }
    }

    // ── 其余入口卡 ──
    private var secondaryCard: some View {
        XPanel(kind: .group, padding: 0) {
            VStack(spacing: 0) {
                NavigationLink {
                    MemberArchivedView().environmentObject(app)
                } label: {
                    XRow(systemImage: "archivebox", title: "归档成员",
                         subtitle: "已归档的成员可恢复", showsChevron: true)
                        .padding(.horizontal, XSpace.card)
                        .padding(.vertical, XSpace.s)
                }
                .buttonStyle(.plain)
                Divider().overlay(XPalette.hairline).padding(.leading, XSpace.card + 40)
                NavigationLink {
                    UnclaimedClaimView().environmentObject(app)
                } label: {
                    XRow(systemImage: "questionmark.circle", title: "匿名认领",
                         subtitle: "无归属的凭证可认领给成员", showsChevron: true)
                        .padding(.horizontal, XSpace.card)
                        .padding(.vertical, XSpace.s)
                }
                .buttonStyle(.plain)
                Divider().overlay(XPalette.hairline).padding(.leading, XSpace.card + 40)
                NavigationLink {
                    MemberFamilySettingsView().environmentObject(app)
                } label: {
                    XRow(systemImage: "person.3", title: "家庭设置",
                         subtitle: "长辈模式 / 隐私浏览", showsChevron: true)
                        .padding(.horizontal, XSpace.card)
                        .padding(.vertical, XSpace.s)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // ── 空态卡 ──
    private var emptyCard: some View {
        XPanel(kind: .group, padding: 0) {
            XEmptyState(systemImage: "person.2",
                        title: "还没有成员",
                        message: "添加第一位家人, 之后可以为 TA 分配凭证与查看开门记录。",
                        actionTitle: "添加成员",
                        action: { showWizard = true })
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 名册
    // ═══════════════════════════════════════════════════════


    /// 成员行 —— 头像主导
    ///
    /// 与原来 36pt 圆点 + 纯文字相比:
    ///   · 头像 44pt，带成员色浅底 + 描边（视觉锚点）
    ///   · 右侧显示 30 天开门数（真实数据，来自 MemberHub.activity）
    ///   · 久未用的成员置灰（MemberHub.Activity.stale 已有判据）
    private func memberRow(_ m: Member) -> some View {
        let pwdCount = DB.listPwds(mac).filter { $0.owner == m.id }.count
        let fpCount = DB.listFps(mac).filter { $0.owner == m.id }.count
        let total = pwdCount + fpCount
        let role = MemberHub.ext(m.id).role
        let act = MemberHub.activity(m.id)
        return HStack(spacing: XSpace.m) {
            // 头像
            ZStack {
                Circle().fill(memberColor(m).opacity(0.14))
                Circle().strokeBorder(memberColor(m).opacity(0.5), lineWidth: 1.5)
                Text(String(MemberHub.display(m).prefix(1)))
                    .xFont(.headline, weight: .semibold)
                    .foregroundStyle(memberColor(m))
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(MemberHub.display(m))
                    .xFont(.body, weight: .medium)
                    .foregroundStyle(act.stale ? XPalette.textSub : XPalette.text)
                    .lineLimit(1)
                Text(subtitle(m, role: role, total: total))
                    .xFont(.caption)
                    .foregroundStyle(XPalette.textSub)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // 30 天开门数 —— 真实统计，不是装饰
            if act.opens30 > 0 {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(act.opens30)")
                        .xFont(.body.monospacedDigit(), weight: .semibold)
                        .foregroundStyle(XPalette.accent)
                    Text("30 天")
                        .xFont(.caption2)
                        .foregroundStyle(XPalette.textTertiary)
                }
            } else if total > 0 {
                Text("\(total) 份")
                    .xFont(.caption.monospacedDigit())
                    .foregroundStyle(XPalette.textTertiary)
            }
        }
        .padding(.vertical, XSpace.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(MemberHub.display(m)), \(MemberHub.roleLabel(role)), 近 30 天 \(act.opens30) 次开门, \(total) 份凭证")
    }

    private func subtitle(_ m: Member, role: String, total: Int) -> String {
        var parts: [String] = []
        let roleName = MemberHub.roleLabel(role)
        if !roleName.isEmpty { parts.append(roleName) }
        if !m.relation.isEmpty { parts.append(m.relation) }
        if total == 0 { parts.append("无凭证") }
        return parts.joined(separator: " · ")
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 次要入口
    // ═══════════════════════════════════════════════════════



    // ═══════════════════════════════════════════════════════
    // MARK: - 数据
    // ═══════════════════════════════════════════════════════

    /// 成员建档色 (Member.color 是 "#RRGGBB" 字符串)
    private func memberColor(_ m: Member) -> Color {
        if m.color.hasPrefix("#"), let v = UInt32(m.color.dropFirst(), radix: 16) {
            return Color(hex: v)
        }
        return XPalette.accent
    }

    private func reload() {
        members = DB.members().filter { !MemberHub.archivedIDs().contains($0.id) }
    }
}
