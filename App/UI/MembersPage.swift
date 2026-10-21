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


    private func memberRow(_ m: Member) -> some View {
        let pwdCount = DB.listPwds(mac).filter { $0.owner == m.id }.count
        let fpCount = DB.listFps(mac).filter { $0.owner == m.id }.count
        let total = pwdCount + fpCount
        let role = MemberHub.ext(m.id).role
        return HStack(spacing: XSpace.m) {
            // 头像色点 (成员色)
            Circle()
                .fill(memberColor(m))
                .frame(width: 36, height: 36)
                .overlay(
                    Text(String(MemberHub.display(m).prefix(1)))
                        .xFont(.subheadline, weight: .semibold)
                        .foregroundStyle(XPalette.onAccent)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(MemberHub.display(m))
                    .xFont(.body)
                    .foregroundStyle(XPalette.text)
                    .lineLimit(1)
                Text(subtitle(m, role: role, total: total))
                    .xFont(.caption)
                    .foregroundStyle(XPalette.textSub)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if total > 0 {
                Text("\(total)")
                    .xFont(.subheadline.monospacedDigit())
                    .foregroundStyle(XPalette.textSub)
            }
        }
        .padding(.vertical, XSpace.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(MemberHub.display(m)), \(MemberHub.roleLabel(role)), \(total) 份凭证")
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
