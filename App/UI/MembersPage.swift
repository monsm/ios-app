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

    private var mac: String { app.currentMac }

    var body: some View {
        // M5 重做: List → 卡片流
        //
        // 与 KeysPage 同一套语言: XPanel 分组 + 组内行 + 液态玻璃只在需要时用。
        // 数据逻辑（reload / members / mac）一行没动。
        // 2026-10-23：改用 XScreen（规范 §5.3 骨架 / §5.4 对齐线）。
        // 改前是手写 ScrollView + VStack(section) + 各自的 padding 与 background。
        XScreen("成员", subtitle: "谁能开门 · 各自的授权来源") {
            // 审美对齐 HTML 04-members：卡前 4 个胶囊 + 「成员分布」卡（环 + 两列）
            membersChipsRow
            // 审美对齐 HTML 30-members-list 卡1「钥匙分布」
            keysDistributionCard
            membersDistributionCard
            if members.isEmpty {
                emptyCard
            } else {
                // 先头像带（认人），再卡片（看细节）
                avatarStrip
                rosterCard
            }
            secondaryCard
        }
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
        // onDismiss 必须重载：members 是 @State 缓存，只靠 onAppear 的话
        // 新建成员后关闭 sheet 列表不会变 —— 用户会以为没建成。
        .sheet(isPresented: $showWizard, onDismiss: { reload() }) {
            MemberWizardView()
                .environmentObject(app)
        }
        .onAppear { reload() }
    }

    // ── 成员卡 ──
    // ── 横向大头像条 ──
    //
    // M5 形态: 成员页的识别锚点是**脸**，不是文字行。
    // 所以顶部先给一条横向头像带 —— 一眼认全家人，
    // 下面的卡片再给细节。
    /// HTML 04-members 卡前的 4 个胶囊
    private var membersChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: XSpace.s) {
                XStatChip(label: "成员", value: String(members.count))
                XStatChip(label: "活跃", value: String(members.filter { MemberHub.isActive($0.id) }.count))
                XStatChip(label: "归档", value: String(MemberHub.archivedIDs().count))
                XStatChip(label: "未归属记录", value: String(unclaimedCount))
            }
            .padding(.vertical, 2)
        }
    }

    /// HTML「成员分布」卡：三环 + 钥匙总数/指纹总数 两列 + 页脚
    /// HTML「钥匙分布」卡 —— 每类凭证横向占比条
    private var keysDistributionCard: some View {
        let macs = DB.keychains().map { $0.mac }
        let pwN = macs.reduce(0) { $0 + DB.listPwds($1).filter { !$0.temp }.count }
        let tempN = macs.reduce(0) { $0 + DB.listPwds($1).filter { $0.temp }.count }
        let fpN = macs.reduce(0) { $0 + DB.listFps($1).count }
        let total = max(1, pwN + tempN + fpN)
        return XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                Text("钥匙分布")
                    .xFont(.subheadline)
                    .foregroundStyle(XPalette.textTertiary)
                XDataRow(label: "密码", value: String(pwN), unit: "份", color: XPalette.kindTemp)
                XDataRow(label: "临时码", value: String(tempN), unit: "个", color: XPalette.kindOtp)
                XDataRow(label: "指纹", value: String(fpN), unit: "枚", color: XPalette.kindFp)
                // 横向占比条（不手绘形状：用 XStepBar 的三段语义）
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        Rectangle().fill(XPalette.kindTemp).frame(width: geo.size.width * CGFloat(pwN) / CGFloat(total))
                        Rectangle().fill(XPalette.kindOtp).frame(width: geo.size.width * CGFloat(tempN) / CGFloat(total))
                        Rectangle().fill(XPalette.kindFp).frame(width: geo.size.width * CGFloat(fpN) / CGFloat(total))
                    }
                }
                .frame(height: 6)
                .clipShape(Capsule())
                Text("条长按数量分 —— 一眼看出这个家主要靠哪种方式进人。")
                    .xFont(.caption2)
                    .foregroundStyle(XPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var membersDistributionCard: some View {
        let macs = DB.keychains().map { $0.mac }
        let pwN = macs.reduce(0) { $0 + DB.listPwds($1).count }
        let fpN = macs.reduce(0) { $0 + DB.listFps($1).count }
        let total = max(1, pwN + fpN)
        return XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: 0) {
                Text("成员分布")
                    .xFont(.subheadline)
                    .foregroundStyle(XPalette.textTertiary)
                HStack(alignment: .center, spacing: XSpace.l) {
                    VStack(alignment: .leading, spacing: 8) {
                        XHeroNumber(text: String(members.count), color: XPalette.accentText, unit: "位成员")
                        Text("活跃 \(members.filter { MemberHub.isActive($0.id) }.count) 位 · 归档 \(MemberHub.archivedIDs().count) 位")
                            .xFont(.footnote)
                            .foregroundStyle(XPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    XTripleThinRing(
                        size: 88,
                        values: (Double(pwN) / Double(total), Double(fpN) / Double(total), 0.06),
                        colors: (XPalette.kindTemp, XPalette.kindFp, XPalette.textSub),
                        centerText: String(pwN + fpN))
                        .accessibilityHidden(true)
                }
                .padding(.top, 8)
                XHairline().padding(.vertical, 12)
                HStack(alignment: .top, spacing: XSpace.s) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("钥匙总数").xFont(.caption2).foregroundStyle(XPalette.textTertiary)
                        Text("\(pwN) 份").xFont(.footnote, weight: .semibold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("指纹总数").xFont(.caption2).foregroundStyle(XPalette.textTertiary)
                        Text("\(fpN) 枚").xFont(.footnote, weight: .semibold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("环是按凭证类型分的 —— 人多了以后，看颜色比数名单快。")
                    .xFont(.caption2)
                    .foregroundStyle(XPalette.textTertiary)
                    .padding(.top, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 未归属记录数（成员页胶囊用）
    private var unclaimedCount: Int {
        let macs = DB.keychains().map { $0.mac }
        return macs.reduce(0) { n, m in
            n + DB.listPwds(m).filter { ($0.owner ?? "").isEmpty }.count
        }
    }

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
                                .foregroundStyle(XPalette.textSub)
                        }
                        .xScaledWidth(68)
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
                // 六图改造 (2026-10-23): 成员数从 caption 灰字改成**图 5 的 44px 主角数字**。
                //
                // 图 5 的第一张卡永远把「有多少」做成 44px 大数字 —— 它是这一屏的主读数。
                // 之前这里是 12pt 灰字，读起来像"表格标题"，用户要眯眼才知道家里几个人。
                HStack(alignment: .firstTextBaseline) {
                    XHeroNumber(text: String(members.count), unit: "位成员")
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
                        XHairline()
                            .padding(.leading, XSpace.card + 40 + XSpace.m)
                    }
                }

                Text("点一位成员可看名下钥匙、授权来源与最近活动。")
                    .xFont(.caption2)
                    .foregroundStyle(XPalette.textSub)
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
                XHairline().padding(.leading, XSpace.card + 40)
                NavigationLink {
                    UnclaimedClaimView().environmentObject(app)
                } label: {
                    XRow(systemImage: "questionmark.circle", title: "匿名认领",
                         subtitle: "还没分配给家人的钥匙可以认领", showsChevron: true)
                        .padding(.horizontal, XSpace.card)
                        .padding(.vertical, XSpace.s)
                }
                .buttonStyle(.plain)
                XHairline().padding(.leading, XSpace.card + 40)
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
                        message: "添加第一位家人, 之后可以把钥匙分给 TA，也能看到 TA 的开门记录。",
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
    /// 成员行 —— 内容适配版
    ///
    /// 上一轮我只换了外观（头像 + 开门数），**没做内容适配**:
    /// 审计发现本文件 0 个分支、只用了 5 个字段。而 MemberHub 还有:
    ///   · Activity.last     最近一次开门时间
    ///   · Activity.month    本月次数
    ///   · permRows(role)    5 项权限矩阵
    ///   · weekSentence(id)  近 7 天作息规律
    /// 这些数据早就算好了，只是没接到界面上。
    private func memberRow(_ m: Member) -> some View {
        let pwdCount = DB.listPwds(mac).filter { $0.owner == m.id }.count
        let fpCount = DB.listFps(mac).filter { $0.owner == m.id }.count
        let total = pwdCount + fpCount
        let role = MemberHub.ext(m.id).role
        let act = MemberHub.activity(m.id)
        let perms = MemberHub.permRows(role)
        let allowed = perms.filter { $0.allowed }.count
        return HStack(spacing: XSpace.m) {
            ZStack {
                Circle().fill(memberColor(m).opacity(0.14))
                Circle().strokeBorder(memberColor(m).opacity(0.5), lineWidth: 1.5)
                Text(String(MemberHub.display(m).prefix(1)))
                    .xFont(.headline, weight: .semibold)
                    .foregroundStyle(memberColor(m))
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: XSpace.xs) {
                    Text(MemberHub.display(m))
                        .xFont(.body, weight: .medium)
                        .foregroundStyle(act.stale ? XPalette.textSub : XPalette.text)
                        .lineLimit(1)
                    if act.stale {
                        Text("久未用")
                            .xFont(.caption2)
                            .foregroundStyle(XPalette.textSub)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(XPalette.surfaceAlt))
                    }
                }
                Text(subtitle(m, role: role, total: total))
                    .xFont(.caption)
                    .foregroundStyle(XPalette.textSub)
                    .lineLimit(1)
                if let last = lastOpenText(act.last) {
                    Text(last)
                        .xFont(.caption2)
                        .foregroundStyle(XPalette.textSub)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                if act.opens30 > 0 {
                    Text(String(act.opens30))
                        .xFontExact(.body.monospacedDigit(), weight: .semibold)
                        .foregroundStyle(XPalette.accent)
                    Text(act.month > 0 ? "本月 " + String(act.month) : "30 天")
                        .xFont(.caption2)
                        .foregroundStyle(XPalette.textTertiary)
                } else if total > 0 {
                    Text(String(total) + " 份")
                        .xFontExact(.caption.monospacedDigit())
                        .foregroundStyle(XPalette.textSub)
                }
                // 权限数（5 项里允许几项）
                Text(String(allowed) + "/" + String(perms.count))
                    .xFontExact(.caption2.monospacedDigit())
                    .foregroundStyle(allowed == perms.count ? XPalette.ok : XPalette.warn)
            }
        }
        .padding(.vertical, XSpace.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(m, role: role, total: total, act: act, allowed: allowed, permTotal: perms.count))
    }

    /// 最近一次开门的相对时间（"3 分钟前" / "昨天 18:20"）
    private func lastOpenText(_ last: String) -> String? {
        guard !last.isEmpty else { return nil }
        // lockTimeStr 形如 "2026-10-21 17:20:33"，取 月-日 时:分
        let short = String(last.suffix(14))
        return "最近 " + short
    }

    private func accessibilityText(_ m: Member, role: String, total: Int, act: MemberHub.Activity, allowed: Int, permTotal: Int) -> String {
        var parts = [MemberHub.display(m), MemberHub.roleLabel(role)]
        if total > 0 { parts.append(String(total) + " 项钥匙") }
        if act.opens30 > 0 { parts.append("近 30 天 " + String(act.opens30) + " 次") }
        parts.append("权限 " + String(allowed) + " / " + String(permTotal))
        return parts.joined(separator: "，")
    }

    private func subtitle(_ m: Member, role: String, total: Int) -> String {
        var parts: [String] = []
        let roleName = MemberHub.roleLabel(role)
        if !roleName.isEmpty { parts.append(roleName) }
        if !m.relation.isEmpty { parts.append(m.relation) }
        if total == 0 { parts.append("无钥匙") }
        return parts.joined(separator: " · ")
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 次要入口
    // ═══════════════════════════════════════════════════════



    // ═══════════════════════════════════════════════════════
    // MARK: - 数据
    // ═══════════════════════════════════════════════════════

    /// 成员建档色 —— 实现收在 `Color.memberSwatch` 一处。
    /// 这里回落 `accent` 而不是 `textSub`: 头像位是「有身份」的位置, 给个强调色比给灰色诚实。
    private func memberColor(_ m: Member) -> Color {
        Color.memberSwatch(m.color, fallback: XPalette.accent)
    }

    private func reload() {
        members = DB.members().filter { !MemberHub.archivedIDs().contains($0.id) }
    }
}
