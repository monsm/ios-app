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
        List {
            if members.isEmpty {
                emptySection
            } else {
                rosterSection
            }
            secondarySection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
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

    // ═══════════════════════════════════════════════════════
    // MARK: - 名册
    // ═══════════════════════════════════════════════════════

    private var rosterSection: some View {
        Section {
            ForEach(members) { m in
                NavigationLink {
                    MemberDetail360View(memberID: m.id)
                        .environmentObject(app)
                } label: {
                    memberRow(m)
                }
            }
        } header: {
            Text("\(members.count) 位成员")
        } footer: {
            Text("点一位成员可看名下凭证、授权来源与最近活动。")
        }
    }

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
                        .vkFont(.subheadline, weight: .semibold)
                        .foregroundStyle(XPalette.onAccent)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(MemberHub.display(m))
                    .vkFont(.body)
                    .foregroundStyle(XPalette.text)
                    .lineLimit(1)
                Text(subtitle(m, role: role, total: total))
                    .vkFont(.caption)
                    .foregroundStyle(XPalette.textSub)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if total > 0 {
                Text("\(total)")
                    .vkFont(.subheadline.monospacedDigit())
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

    private var secondarySection: some View {
        Section {
            NavigationLink {
                MemberArchivedView().environmentObject(app)
            } label: {
                XRow(systemImage: "archivebox", title: "归档成员",
                     subtitle: "已归档的成员可恢复", showsChevron: true)
            }
            NavigationLink {
                UnclaimedClaimView().environmentObject(app)
            } label: {
                XRow(systemImage: "questionmark.circle", title: "匿名认领",
                     subtitle: "无归属的凭证可认领给成员", showsChevron: true)
            }
            NavigationLink {
                MemberFamilySettingsView().environmentObject(app)
            } label: {
                XRow(systemImage: "person.3", title: "家庭设置",
                     subtitle: "长辈模式 / 隐私浏览", showsChevron: true)
            }
        } header: {
            Text("更多")
        }
    }

    private var emptySection: some View {
        Section {
            VStack(spacing: XSpace.m) {
                Image(systemName: "person.2")
                    .font(.system(size: XIcon.xl, weight: .light))
                    .foregroundStyle(XPalette.textTertiary)
                    .accessibilityHidden(true)
                Text("还没有成员")
                    .vkFont(.headline)
                    .foregroundStyle(XPalette.text)
                Text("点右上角 + 添加第一位家人")
                    .vkFont(.subheadline)
                    .foregroundStyle(XPalette.textSub)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, XSpace.xxl)
            .listRowBackground(Color.clear)
        }
    }

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
