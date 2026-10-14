// 包13 成员·家庭协作 — 成员中心 (入口在 设置-成员管理 右上「成员中心」)
// 五块: 档案 (260/457/458/916/265/461/463/266/666) · 关联 (261/459/473/476/791/464/465) ·
//       流转 (467/468/474/472/460-795/462/263/469/470) · 家庭场景 (479-486/475) ·
//       聚合视图 (788/789/793/794/630/264-466/792/798)。
// 纪律: 颜色只走 DS 令牌; 触达 ≥44pt; "访客" 虚拟分组只在本地展示层 (MemberHub.visitorId),
// 绝不写入锁端凭证表; 推断类数据 (活跃度/摘录) 一律带"约"。
import SwiftUI
import UIKit
import Charts

// ================= 成员中心 (788 总表入口 · 264 排序 · 630 分组 · 793 访客 · 794 隐私) =================
struct MemberCenterView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var tick = 0
    @State private var sortKey: Int = 0        // 264/466: 0 添加时间 / 1 姓名 / 2 最近开门时间 / 3 近 30 天开门次数
    @State private var groupFilter: String = "" // 630 分组过滤
    @State private var showWizard = false
    @State private var showArchived = false
    @State private var showGroups = false
    @State private var showMeeting = false
    // 415 名册导出: ShareLink 要在渲染期就有 URL, 所以点菜单时先按需生成再开面板 (不在 body 里写盘)
    @State private var rosterURL: URL?
    @State private var showRoster = false

    private var members: [Member] {
        // archivedIDs() 此前零调用: 它一次解出整张 ext 表; 旧写法每个成员调两次 ext() = 每成员整体重解一遍字典。
        // groupTag 那步仍按成员取 ext (要的是值不是集合), 至少砍掉一半重复解码。
        let archived = MemberHub.archivedIDs()
        return DB.members()
            .filter { !archived.contains($0.id) }
            .filter { m in groupFilter.isEmpty || MemberHub.ext(m.id).groupTag == groupFilter }
    }

    var body: some View {
        NavigationStack {
            List {
                headerStat
                groupChipSection
                activeSection(sortKey)
                visitorSection
                archivedSection
                sceneSection
                guideSection      // 973 给家人开门禁的四步
                navSection
            }
            .navigationTitle("成员中心")
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("排序", selection: $sortKey) {   // 264/466 排序
                            Text("添加时间").tag(0)
                            Text("姓名").tag(1)
                            Text("最近开门时间 (约)").tag(2)
                            Text("近 30 天开门次数 (约)").tag(3)
                        }
                        .pickerStyle(.inline)
                        Button("分组标签") { showGroups = true }   // 630 分组标签
                        Button("家庭会议摘要") { showMeeting = true }   // 482 家庭会议摘要
                        Button("成员家庭设置") { app.tabSelection = 3 }   // 479/794 成员家庭设置
                        Button("导出成员名册") {   // 415 导出成员名册
                            rosterURL = ExportKit.writeRoster()
                            showRoster = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").accessibilityLabel("成员中心菜单")
                    }
                    // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 命中高仅约 16.5pt (< 44)。
                    // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
            }
            .sheet(isPresented: $showWizard) { MemberWizardView(onDone: { tick += 1 }) }
            .sheet(isPresented: $showArchived) { MemberArchivedView(onRestored: { tick += 1 }) }
            .sheet(isPresented: $showGroups) { MemberGroupSheet(onSaved: { tick += 1 }) }
            .sheet(isPresented: $showMeeting) { MemberMeetingSheet() }
            // 817c 记录页"添加成员"示例位跳过来时直接弹向导; 标记一次性消费。
            // 下一轮 runloop 再置 sheet: onAppear 同步段里开 sheet 在首帧可能因视图未入窗被吞掉。
            .onAppear {
                if app.pendingMemberAdd {
                    app.pendingMemberAdd = false
                    DispatchQueue.main.async { showWizard = true }
                }
            }
            // 415 名册分享面板: 用 ShareLink(item: URL) 而不是 UIActivityViewController ——
            // 后者要么设 popover 锚点 (iPad), 要么就是本仓 SecurityCenterView:1238 那种裸用法;
            // 本 App 现在是 iPhone-only (project.yml TARGETED_DEVICE_FAMILY=1), 今天不会崩, 但改设备族时那就是个雷,
            // 新代码一律走免锚点的 ShareLink。
            .sheet(isPresented: $showRoster) {
                NavigationStack {
                    List {
                        Section("成员名册") {   // 415 成员名册
                            Text("共 \(DB.members().count) 位成员 · 文件 "
                                 + (rosterURL?.lastPathComponent ?? "生成失败"))
                                .font(.subheadline)
                                .foregroundStyle(DS.Palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("名册里只有人与称呼: 不含锁 MAC、凭证编号、口令, 也不含常用锁清单。\n"
                                 + "要搬整套数据请走备份 —— 名册不承担那个用途, 也正因为它少, 才适合发给家人线下核对。")
                                .font(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                            if let u = rosterURL {
                                ShareLink(item: u) {
                                    Label("分享这个 .vcf 文件", systemImage: "square.and.arrow.up")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(DS.Palette.accentText)
                                        .frame(minHeight: DS.Hit.min)
                                }
                            } else {
                                Text("本机还没有成员档案，名册是空的")   // 415 本机还没有成员档案
                                    .font(.caption)
                                    .foregroundStyle(DS.Palette.warn)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .navigationTitle("导出成员名册")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) { Button("完成") { showRoster = false } }
                    }
                }
            }
            .id(tick)   // 写库后重建, List 直接重查 DB
        }
    }

    // 266 概览头: N 位成员 / M 条持凭证 (排除归档)
    private var headerStat: some View {
        let list = members
        let n = list.count
        let m = list.reduce(0) { $0 + MemberHub.activity($1.id).owns }
        return Section {
            HStack(spacing: DS.Space.m) {
                if let first = list.first {
                    MemberAvatar(member: first)
                } else {
                    MemberAvatar(member: Member(id: "g", name: "家", at: 0))
                }
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("共 \(n) 位成员 · \(m) 条凭证")   // 266 位成员
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Palette.text)
                    Text("活跃度按台账推断 (约), 点成员看 360 详情")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // 630 分组过滤 chips (家人/访客/服务人员 — 与包10 图例同组字段)
    @ViewBuilder
    private var groupChipSection: some View {
        let tags = Array(Set(DB.members().map { MemberHub.ext($0.id).groupTag })).filter { !$0.isEmpty }.sorted()
        if !tags.isEmpty {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.xs) {
                        groupChip("", "全部")
                        ForEach(tags, id: \.self) { t in groupChip(t, t) }
                    }
                    .padding(.vertical, DS.Space.xxs)
                }
            }
        }
    }
    private func groupChip(_ tag: String, _ label: String) -> some View {
        let on = groupFilter == tag
        return Button {
            withAnimation(DS.Motion.quick) { groupFilter = tag }
        } label: {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, DS.Space.s)
                .padding(.vertical, DS.Space.xs + 2)
                .background(on ? DS.Palette.accentText.opacity(0.14) : DS.Palette.surfaceAlt, in: Capsule())
                .overlay(Capsule().strokeBorder(DS.Palette.hairline, lineWidth: 0.5))
                .foregroundStyle(on ? DS.Palette.accentText : DS.Palette.text)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("分组 " + label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// 264/466 排序四档。
    /// 466 原句要的是"按近 30 天开门次数"那一档 —— 以前这一页只有"按最近一次开门时间" (tag 2),
    /// 名字却叫"最近活跃", 次数那一档根本没接。现在两档各排各的, 口径都带"约" (台账归属推断)。
    /// 活跃度表一次算完再排: 原先在比较式里现算 MemberHub.activity(), 每比一次就全锁重读一遍日志。
    private func activeSection(_ sort: Int) -> some View {
        let acts: [String: MemberHub.Activity] = (sort == 2 || sort == 3) ? activityTable : [:]
        let list: [Member]
        switch sort {
        case 1: list = members.sorted { MemberHub.display($0) < MemberHub.display($1) }
        case 2: list = members.sorted { (acts[$0.id]?.last ?? "") > (acts[$1.id]?.last ?? "") }
        case 3: list = members.sorted { (acts[$0.id]?.opens30 ?? -1) > (acts[$1.id]?.opens30 ?? -1) }
        default: list = members.sorted { $0.at < $1.at }
        }
        return Section {
            if list.isEmpty {
                EmptyState(systemImage: "person.2.slash",
                           title: "还没有成员",
                           message: "建档向导分三步: 称呼 → 角色 → 初始凭证。",
                           actionTitle: "建档向导") { showWizard = true }   // 463 建档向导
            }
            ForEach(list) { m in
                NavigationLink { MemberDetail360View(memberID: m.id, onChanged: { tick += 1 }) } label: {
                    MemberRow(member: m)
                }
                .swipeActions {
                    // 460/795 归档不蒸发: 左滑归档保留历史不删除 (再次左滑恢复在归档列表)
                    Button {
                        var e = MemberHub.ext(m.id)
                        e.archived = true
                        MemberHub.saveExt(m.id, e)
                        tick += 1
                    } label: { Label("归档", systemImage: "archivebox") }
                    .tint(DS.Palette.ok)
                }
            }
        } header: {
            Text("成员 (\(list.count))")
        } footer: {
            Text("活跃度与摘录为台账推断 (约): 锁端日志无身份字段, 归属只算可证明的。"
                 + "「久未用」判的是近 30 天没有可证明归属的开门, 标在每行行尾; "   // 262/466 久未用
                 + "要看谁这段时间开得多, 上方选「近 30 天开门次数」那一档。")
        }
    }
    /// 264/466 排序用的活跃度表: 一次算完全员, 不在比较式里逐次重扫全锁日志。
    private var activityTable: [String: MemberHub.Activity] {
        var t: [String: MemberHub.Activity] = [:]
        for m in members { t[m.id] = MemberHub.activity(m.id) }
        return t
    }

    // 793 访客虚拟分组: 本地展示层虚拟成员, 不占锁端槽位
    private var visitorSection: some View {
        let opens = visitorOpenCount
        let temps = visitorOwns
        return Section {
            Button {
                app.pendingRecordsFilter = MemberHub.visitorId
                app.tabSelection = 2
                dismiss()
            } label: {
                HStack(spacing: DS.Space.s) {
                    MemberAvatar(member: Member(id: MemberHub.visitorId, name: "访客", at: 0))
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text("访客 · 虚拟成员")   // 793 访客
                            .font(.subheadline)
                            .foregroundStyle(DS.Palette.text)
                        Text("临时码未归属记录约 \(opens) 条 · 名下临时码 \(temps) 条")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .frame(minHeight: DS.Hit.min)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("访客虚拟分组, 约 \(opens) 条未归属临时码记录")
        } header: {
            Text("访客 (虚拟分组)")
        } footer: {
            Text("「访客」只出现在本地展示层, 不写入锁端凭证表。")
        }
    }
    private var visitorOpenCount: Int {
        var n = 0
        for kc in DB.keychains() {
            let logs = DB.readLogs(kc.mac).filter { StatsKit.openTypes.contains($0.type) }
            let status = DB.readStatus(kc.mac)
            let rows = Attribution.classify(
                logs: logs.map { LogEntry(type: $0.type, typeName: $0.typeName, idx: $0.idxRaw, idxRaw: $0.idxRaw,
                                          lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr, body: "") },
                pwds: DB.listPwds(kc.mac), fps: DB.listFps(kc.mac),
                status: status.map { ($0.fpStock, $0.pwdStock, $0.lockTime) })
            for r in rows where MemberHub.isVisitorRow(kind: r.kind, whoId: r.who) { n += 1 }
        }
        return n
    }
    private var visitorOwns: Int {
        DB.keychains().reduce(0) { $0 + DB.listPwds($1.mac).filter { $0.temp }.count }
    }

    @ViewBuilder
    private var archivedSection: some View {
        let arch = DB.members().filter { MemberHub.ext($0.id).archived }
        if !arch.isEmpty {
            Section {
                Button { showArchived = true } label: {
                    Label("归档成员 (\(arch.count)) · 460/795 保留历史", systemImage: "archivebox")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    // 家庭场景快捷 (481/475)
    private var sceneSection: some View {
        Section {
            if let dutyID = MemberHub.dutyThisWeek, let dm = DB.member(dutyID) {
                LabeledContent("本周主责") {   // 481 本周主责
                    Text(MemberHub.display(dm))
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.accentText)
                }
            } else {
                Text("本周主责: 未安排 — 在成员 360 页设置")   // 481 本周主责
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.textSub)
            }
            ForEach(members.prefix(4)) { m in
                if !MemberHub.ext(m.id).note.isEmpty {
                    LabeledContent("便签 · " + MemberHub.display(m)) {
                        Text(MemberHub.ext(m.id).note)
                            .font(.subheadline)
                            .foregroundStyle(DS.Palette.textSub)
                            .lineLimit(2)
                    }
                }
            }
        } header: {
            Text("家庭场景")
        }
    }

    // 聚合视图入口
    // ---------- 973 四步图文 (原句「给家人配手表」四步) ----------
    // 文字**取自说明书同一章** (ManualKit "ch.family")：这一页不另抄一份步骤，
    // 否则改了说明书而这里没改，就会出现"两处教程说法不一致"。
    // 手表那半步做不到 (本 App 无 watch target，协议也不能让手表替锁开门)，
    // 章里第一段就把这句写在明面上 —— 做不到就说不做，不拿四步里的某一步含糊带过。
    @ViewBuilder
    private var guideSection: some View {
        if let ch = ManualKit.chapters.first(where: { $0.id == "ch.family" }) {
            DisclosureGroup {
                ForEach(ch.lines, id: \.self) { line in
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 2)
                }
            } label: {
                Text(ch.title)   // 973 界面文案
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Palette.text)
            }
        }
    }

    private var navSection: some View {
        Section {
            NavigationLink("成员活跃总表") { MemberActiveTable(onChanged: { tick += 1 }) }   // 788/789 成员活跃总表
            NavigationLink("家庭设置") { MemberFamilySettingsView() }   // 479/794 家庭设置
            NavigationLink("家庭会议摘要") { MemberMeetingSheet() }   // 482 家庭会议摘要
        } header: {
            Text("聚合视图")
        }
    }
}

// ---------- 成员行 (457 首字头像 + 458 角色 + 462 同名提示 + 262/466 活跃度) ----------
struct MemberRow: View {
    let member: Member
    @State private var tick = 0

    private var dup: Member? {
        DB.members().first { $0.id != member.id && $0.name == member.name && !MemberHub.ext($0.id).archived }
    }

    var body: some View {
        HStack(spacing: DS.Space.s) {
            MemberAvatar(member: member)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                HStack(spacing: DS.Space.xs) {
                    Text(MemberHub.doubleLine(member))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DS.Palette.text)
                    rolePill
                    if dup != nil {
                        StatusPill(text: "同名待合并", systemImage: "arrow.triangle.merge", tone: .warn)   // 462 同名待合并
                    }
                }
                subLine
            }
            Spacer(minLength: 0)
            staleTag
        }
        .padding(.vertical, DS.Space.xs)
        .frame(minHeight: DS.Hit.min)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .contextMenu {
            Button("归档") {   // 460/795 归档
                var e = MemberHub.ext(member.id)
                e.archived = true
                MemberHub.saveExt(member.id, e)
                tick += 1
            }
            if let d = dup {
                Button("并入「\(d.name)」") {   // 462 并入
                    mergeInto(d)
                }
            }
        }
    }

    private func mergeInto(_ target: Member) {
        for kc in DB.keychains() {
            for p in DB.listPwds(kc.mac) where p.owner == member.id {
                DB.setPwdOwner(kc.mac, p.alias, target.id)
            }
            for f in DB.listFps(kc.mac) where f.owner == member.id {
                DB.setFpOwner(kc.mac, f.batch, target.id)
            }
        }
        MemberHub.reassignClaims(from: member.id, to: target.id)   // 462
        DB.removeMember(member.id)
        tick += 1
    }

    private var rolePill: some View {
        let r = MemberHub.ext(member.id).role
        return StatusPill(text: MemberHub.roleLabel(r),
                          systemImage: r == "main" ? "crown.fill" : (r == "guest" ? "person.badge.clock" : "person.fill"),
                          tone: r == "main" ? .warn : .neutral)
    }
    private var subLine: some View {
        let e = MemberHub.ext(member.id)
        let a = MemberHub.activity(member.id)
        let bits = [member.relation,
                    e.remark.isEmpty ? "" : "备注 " + e.remark,
                    a.last.isEmpty ? "" : "最近开门约 " + String(a.last.prefix(10)),
                    a.owns > 0 ? "名下 " + String(a.owns) + " 条" : ""]
            .filter { !$0.isEmpty }
        return Text(bits.isEmpty ? "暂无台账凭证" : bits.joined(separator: " · "))
            .font(.caption)
            .foregroundStyle(DS.Palette.textSub)
            .fixedSize(horizontal: false, vertical: true)
            // 262 久未用的行整体压暗一档: 只靠右侧"久未用"小字, 扫描名单时视线抓不到
            .opacity(a.stale ? 0.55 : 1)
    }
    // 262/466 久未用置灰 (台账推断口径)
    private var staleTag: some View {
        let stale = MemberHub.activity(member.id).stale
        return Text(stale ? "久未用" : "活跃 (约)")
            .font(.caption2)
            .foregroundStyle(stale ? DS.Palette.textSub : DS.Palette.ok)
            .lineLimit(1)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// 457 首字符号头像 + 916 emoji 代号: 零图片资源 (本地绘制)
// 994 右下角叠加"该成员已选的徽章"角标 (SF Symbol, 取徽章总表的 icon 字段, 守 219 零图片资源纪律)。
// 影响面 (grep "MemberAvatar(" 全仓 12 处构造点): 本文件 8 处 + DeviceHomeView 4 处 (hero 那三枚叠放
// 头像 / 临时码到期卡 / 生日卡 / 便签行), 全站头像因此都会长角标 —— 但只长在 kf_member_badge 里
// 真存了那枚徽章的成员身上; 虚拟成员"访客"(__visitor)与概览头那个 id "g" 的占位档永远查不到角标 ——
// 「授予徽章」那份菜单只遍历 DB.members() 的真实成员 (Sheets.swift 的 reload 就是这条数据源),
// 这两个虚拟 id 进不了表, 所以它们的头像观感维持原样。
struct MemberAvatar: View {
    let member: Member
    var size: CGFloat = 34
    var tint: Color? = nil   // 480: 传成员建档色时整个头像随该色; 不传维持原 accentText 口径

    // ---------- 994 角标取数与档位 ----------
    /// 994 已选徽章 id → 徽章总表里查到的那一枚; 两道都查到才算有一枚角标。
    /// 查不到时头像走"只画头像本体"那条分支, 交回与加这段代码之前逐字同一条修饰符链 ——
    /// 没选角标的成员观感零变化, 角标位始终由真实选定的那一枚徽章独占。
    /// 降级口径 (依据 Milestones.heroFlairActive 那段 999 的判法): 素颜模式 (kf_plain) 关的是
    /// **动效与装饰层** —— 999 关的是史诗徽章那圈流光边, 徽章本体照留; 设置页对素颜模式的承诺也是
    /// "关闭庆祝与徽章动效"; DS.Metric.emptyMascot 关的是纯装饰的空态图形。
    /// 这一枚角标是业主在「授予徽章」里亲手选定、进 kf_member_badge 且随备份走的**内容**,
    /// 画法又是纯静态 (零粒子零流光), 所以素颜模式照显示 —— 否则详情页写着"已选角标 X"而头像上
    /// 什么都没有, 就成了文案与画面对不上。高对比档同样照常显示: 底板与细边都是实色 (半透明叠字在
    /// 高对比档属禁用), 走的正是 AccessibilityKit 里"高对比降为实底"那一条口径。
    private var cornerBadge: Badge? {
        guard let bid = Milestones.memberBadges()[member.id] else { return nil }
        return Milestones.badge(bid)   // 双保险与 RecordsView 门神榜同一条判据: 总表里查得到的那一枚才落到角标位
    }
    /// 994 角标字号随头像档位, 只取 DS.Icon 现成档位 (xs 13 / sm 16 / md 20), 不自造字号:
    /// 22–26 小头像走 xs, 28–39 标准行头像走 sm, 40 以上 (详情页 44) 走 md。
    private var cornerGlyph: CGFloat {
        if size >= 40 { return DS.Icon.md }
        if size >= 28 { return DS.Icon.sm }
        return DS.Icon.xs
    }
    /// 994 角标图: 徽章自己的 SF Symbol + 与头像同源的 tint 前景。
    /// 底板与细边同色 (DS.Palette.surface) —— 细边那 1.5pt 的作用是把角标从头像那圈 base@0.5 外环上
    /// "切"出来, 两者各留边界; 与 DeviceHomeView 锁位角标、AccessibilityKit 圆片是同一条抠边口径。
    /// 对 VoiceOver 隐藏: 徽章名已由头像的 accessibilityLabel 一并合读, 屏幕上因此多出来的是图形而非第二个朗读元素。
    private func badgeCornerMark(_ b: Badge, base: Color) -> some View {
        Image(systemName: b.icon)
            .font(.system(size: cornerGlyph, weight: .semibold))
            .foregroundStyle(base)
            .padding(DS.Space.xxs)
            // 2026-10-14 材质统一批次: 这一处**故意留实底**。它是角标与头像外环之间的抠边片
            // (下一行那圈同色 1.5pt 描边也是抠边用的, 两者必须同色才切得开), 玻璃的折射底会把
            // 头像那圈环再映一遍 —— 换材质反而把"切出来"这件事糊掉。
            // @layout-allow 面板实底
            .background(DS.Palette.surface, in: Circle())
            .overlay(Circle().strokeBorder(DS.Palette.surface, lineWidth: 1.5))
            .accessibilityHidden(true)
    }

    /// 457: 未显式传 tint 时读成员建档色 (480 建档色此前只有 480 自己消费, 头像一直恒为 accentText)。
    /// 994: 这段原先写在 body 里的 `var base = …; if … { base = … }` 提到独立计算属性 ——
    /// 头像现在是 @ViewBuilder 的 body, 结果构建器里只允许产出视图的 `if`, 给局部变量赋值的那种裸 `if` 得搬出去。
    private var baseColor: Color {
        if let t = tint { return t }
        if member.color.hasPrefix("#"), let v = UInt32(member.color.dropFirst(), radix: 16) {
            return Color(hex: v)
        }
        return DS.Palette.accentText
    }

    // 994: body 改成 @ViewBuilder, 是为了让"只画头像本体"那条分支交回原样的头像链, 有角标时才在外面
    // 多挂一层 overlay。头像本体的 frame/ZStack/字号/命中区保持原样: `.overlay` 只叠在已算好的尺寸上
    // (主视图的 frame 与它占的 spacing 都由头像自己那 `.frame(width:height:)` 说了算),
    // 而角标又落在头像自己那 size×size 方块的右下角之内 (只用 alignment 定位, 因此越不出 frame、压不到相邻行文字)。
    @ViewBuilder
    var body: some View {
        let base = baseColor
        if let b = cornerBadge {
            // 994 有角标: overlay 挂在头像链的外面
            avatarCircle(base: base, badge: b)
                .overlay(alignment: .bottomTrailing) { badgeCornerMark(b, base: base) }
        } else {
            // 994 只画头像本体这一支: 与改动前逐字相同的那条链, overlay 整层缺席
            avatarCircle(base: base, badge: nil)
        }
    }

    /// 457/916 头像本体 (994 抽出成函数只为给上面两条分支复用同一条链, 渲染内容与抽出前一致)
    private func avatarCircle(base: Color, badge b: Badge?) -> some View {
        let e = MemberHub.ext(member.id)
        let ch = String(member.name.prefix(1))
        // 994 a11y: 有角标时在头像标签尾部并读"角标 <徽章名>", 无角标时标签与改动前逐字相同。
        return ZStack {
            Circle()
                .fill(base.opacity(0.14))
            Circle()
                .strokeBorder(base.opacity(0.5), lineWidth: 1)
            if !e.emoji.isEmpty {
                Text(e.emoji)
                    .font(.title3)
            } else if member.id == MemberHub.visitorId {
                Image(systemName: "person.badge.clock")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(base)
            } else {
                Text(ch.isEmpty ? "员" : ch)
                    .font(.headline)
                    .foregroundStyle(base)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("头像 " + (member.name.isEmpty ? "成员" : member.name)
                            + (b.map { ", 角标 \($0.title)" } ?? ""))
    }
}

// ================= 成员 360 详情 (459 上档案 / 下凭证+摘录 ⚠约 · 473 来源 · 476 图谱 · 464/465 · 470 矩阵 · 469) =================
struct MemberDetail360View: View {
    let memberID: String
    var onChanged: () -> Void = {}
    @EnvironmentObject var app: AppState
    @State private var tick = 0
    @State private var showMerge = false
    @State private var showExitWizard = false
    @State private var showBorrow = false

    private var member: Member? { DB.member(memberID) }

    var body: some View {
        if let m = member {
            List {
                if let line = MemberHub.weekSentence(m.id) {
                    Section { Label(line, systemImage: "calendar.badge.clock")
                        .font(.footnote).foregroundStyle(DS.Palette.text)
                        .fixedSize(horizontal: false, vertical: true) }
                }
                archiveSection(m)
                // 467「待确认移交」区已撤 (2026-10-09 拍板): 移交实际由凭证页 `CredentialOrg.batchTransfer`
                // 直接改本机台账, 队列没有发起方 → 这个区永远只显示"暂无"。留着就是假开关那一族。
                credsSection(m)
                excerptSection(m)
                feedSection(m)
                sourceSection(m)
                graphSection(m)
                sceneSection(m)
                permSection(m)
            }
            .navigationTitle(MemberHub.display(m))
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("补全档案 (关系/电话/生日/代号/分组/便签)") { editProfile(m); onChanged() }
                    Button("重复合并") { showMerge = true }   // 462 重复合并
                    Button("退出处置向导") { showExitWizard = true }   // 474 退出处置向导
                    Button(role: .destructive) { confirmDelete(m) } label: {
                        Label("删除并级联提示", systemImage: "trash")   // 263 删除并级联提示
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").accessibilityLabel("成员操作菜单")
                }
            } }
            .sheet(isPresented: $showMerge) { MergeMembersView(primary: m) { tick += 1; onChanged() } }
            .sheet(isPresented: $showExitWizard) { MemberExitWizard(memberID: m.id, onDone: { onChanged() }) }
            .sheet(isPresented: $showBorrow) { BorrowSheetView(memberID: m.id, onDone: { tick += 1 }) }
            .id(tick)
        } else {
            EmptyState(systemImage: "person.slash",
                       title: "成员不存在",
                       message: "档案可能已被删除或合并。")
                .frame(maxWidth: .infinity)
        }
    }

    // ---------- 档案区 (457/458/916/265/461/464/465/485/1017/653/480 · 994 角标) ----------
    private func archiveSection(_ m: Member) -> some View {
        let e = MemberHub.ext(m.id)
        let a = MemberHub.activity(m.id)
        // 994 这一位已选的角标: 与头像右下角同一道取数 (存了 id 但徽章总表查不到 = 当没选, 两处口径一致)
        let corner = Milestones.memberBadges()[m.id].flatMap { Milestones.badge($0) }
        // 994 指路文案: 两种状态各说各的实话 —— 没选的时候不许写"角标已画在右下角"那种指着空气的话。
        // 整句一行写完 (单行字面量不许跨行), 入口措辞照 Sheets.swift 成员管理列表的真实菜单项写。
        let hintNone = "选法: 「设置 → 成员管理」里长按这一位成员的行 →「授予徽章」(那份菜单列的是本机已点亮的徽章), 选中的那枚就画在本成员头像的右下角。"
        let hintSome = "角标已画在本成员头像的右下角, 图形就是这枚徽章自己的那枚符号。改选或撤下: 「设置 → 成员管理」里长按这一位成员的行 →「授予徽章」, 同一菜单里有「移除角标」。"
        let cornerHint = corner == nil ? hintNone : hintSome
        return Section {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                HStack(spacing: DS.Space.s) {
                    MemberAvatar(member: m, size: 44)
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(MemberHub.display(m))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(DS.Palette.text)
                        Text(MemberHub.roleLabel(e.role) + (m.relation.isEmpty ? "" : " · " + m.relation))
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    Spacer(minLength: 0)
                    StatusPill(text: "名下 \(a.owns) 条", systemImage: "key.fill", tone: .accent)
                }
                // 465 紧急联系行 (纯本地)
                LabeledContent("紧急联系") {   // 465 紧急联系
                    Text(e.emergency.isEmpty ? "未填" : e.emergency)
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.textSub)
                }
                // 464 常用锁
                if !e.commonLocks.isEmpty {
                    LabeledContent("常用锁") {   // 464 常用锁
                        let names = e.commonLocks.map { LockArchive.displayName(DB.keychain($0) ?? Keychain(mac: $0, skey: "")) }
                        Text(names.joined(separator: "、"))
                            .font(.subheadline)
                            .foregroundStyle(DS.Palette.textSub)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                // 485/1017/653 生日行 (Milestones 已有数据与提前一天通知, 只接线不重做)
                if let bd = Milestones.memberBirthdays()[m.id] {
                    LabeledContent("生日") {   // 485 生日
                        Text(bd + " · 提前一天提醒")
                            .font(.subheadline)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                }
                // 994 角标行: 只报 kf_member_badge 里真实存下的那一枚 —— 已选就报徽章名,
                // 那一位还没挑的照实读作"未选角标", 两种状态都是本机台账的原话。
                LabeledContent("角标") {   // 994 角标
                    Text(corner.map { "已选「\($0.title)」" } ?? "未选角标")
                        .font(.subheadline)
                        .foregroundStyle(corner == nil ? DS.Palette.textSub : DS.Palette.text)
                }
                // 994 指路行: 选与撤的真实入口在「设置 → 成员管理」那张列表的长按菜单里
                // (「授予徽章」子菜单 +「移除角标」), 这一页只报状态并把人指到那个真实入口 ——
                // 徽章选择器全 App 保持一处实现, 两处写迟早一处改了另一处走偏。
                // 文案随状态分两路: 已选的说"改选/撤下", 未选的说"怎么挑", 各自只说自己那一份。
                Text(cornerHint)
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                // 480 孩子码关怀文案 (家长视角)
                if !e.careText.isEmpty {
                    LabeledContent("关怀语") {   // 480 关怀语
                        Text(e.careText)
                            .font(.subheadline)
                            .foregroundStyle(DS.Palette.accentText)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        } header: {
            Text("档案")
        }
    }

    // ---------- 261/472 名下凭证 (含借用横条) ----------
    private func credsSection(_ m: Member) -> some View {
        var pwdCount = 0, fpCount = 0
        var borrowLines: [String] = []
        var credLines: [String] = []   // 261 清单: 借用中的走 borrowLines, 同一凭证不在本段出现两次
        for kc in DB.keychains() where !kc.mac.isEmpty {
            for p in DB.listPwds(kc.mac) where p.owner == m.id {
                pwdCount += 1
                if let b = MemberHub.borrows(kc.mac)["p" + String(p.alias)] {
                    borrowLines.append(CredentialOrg.displayPwd(p) + " · 借给 " + b.by + " (还 " + b.due + ")")
                } else {
                    credLines.append(CredentialOrg.displayPwd(p))
                }
            }
            for f in DB.listFps(kc.mac) where f.owner == m.id {
                fpCount += 1
                if let b = MemberHub.borrows(kc.mac)["f" + String(f.batch)] {
                    borrowLines.append("「" + f.name + "」 · 借给 " + b.by + " (还 " + b.due + ")")
                } else {
                    credLines.append("「" + f.name + "」")
                }
            }
        }
        return Section {
            Text("密码 \(pwdCount) 条 · 指纹 \(fpCount) 条 · 未归属转未分配不在此列")   // 261 密码
                .font(.subheadline)
                .foregroundStyle(DS.Palette.text)
            // 261 清单本体: 只有计数没有名目时, 用户没法核对"名下到底有哪几把"
            ForEach(Array(credLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            ForEach(borrowLines, id: \.self) { line in
                HStack(spacing: DS.Space.s) {
                    StatusPill(text: "借用中", systemImage: "person.2.badge.gearshape", tone: .warn)   // 472 借用中
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.textSub)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
            }
            Button {
                showBorrow = true
            } label: {
                Label("借用登记", systemImage: "person.2.badge.plus")   // 472 借用登记
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundStyle(DS.Palette.accentText)
        } header: {
            Text("名下凭证")   // 261 名下凭证
        }
    }

    // ---------- 459 最近开门摘录 (⚠台账推断, 带"约") ----------
    private func excerptSection(_ m: Member) -> some View {
        let rows = MemberHub.recentExcerpts(m.id, 10)
        return Section {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                HStack(spacing: DS.Space.s) {
                    Text(String(r.time.prefix(10)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(DS.Palette.textSub)
                    Text(r.text)
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.text)
                    Spacer(minLength: 0)
                    Text("约")
                        .font(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                }
                .accessibilityElement(children: .combine)
            }
            if rows.isEmpty {
                Text("还没有可证明归属的开门记录 (台账积累中, 属正常)。")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("最近开门 (约 · 459)")
        }
    }

    // ---------- 367 停用动态 (读敏感流水里归属本成员的那几条; 不新建存储、不新建键) ----------
    private func feedSection(_ m: Member) -> some View {
        let rows = SensitiveLedger().memberItems(m.id)
        return Section {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                HStack(spacing: DS.Space.s) {
                    Text(SensitiveLedger.stamp(r))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(DS.Palette.textSub)
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(r.kind).font(.subheadline)
                        Text(r.target).font(.caption).foregroundStyle(DS.Palette.textSub)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
            if rows.isEmpty {
                Text("还没有停用记录。停用凭证时勾「写入该成员动态」才会写进这里；不勾只在敏感操作流水里留一条汇总，不落到个人档案。")   // 367 还没有停用记录
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("凭证停用动态")   // 367 凭证停用动态
        }
    }

    // ---------- 473 授权来源统计 ----------
    private func sourceSection(_ m: Member) -> some View {
        let s = MemberHub.sourceCounts(m.id)
        return Section {
            HStack(spacing: DS.Space.m) {
                sourceCell("创建", s.created)
                sourceCell("移交", s.moved)
                sourceCell("恢复", s.restored)
            }
            .accessibilityElement(children: .combine)
        } header: {
            Text("授权来源")   // 473 授权来源
        }
    }
    private func sourceCell(_ label: String, _ n: Int) -> some View {
        VStack(spacing: DS.Space.xs) {
            Text(String(n))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(DS.Palette.accentText)
            Text(label)
                .font(.caption2)
                .foregroundStyle(DS.Palette.textSub)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.s)
        .background(DS.Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
    }

    // ---------- 476 归属图谱 (SwiftUI 自绘两列: 创建人→使用人) ----------
    private func graphSection(_ m: Member) -> some View {
        let edges = MemberHub.graph(m.id)
        return Section {
            if edges.isEmpty {
                Text("暂无「谁创建给谁」的凭证关系 — 这一张图只画得出本机版本历史里留得下那一手移交的凭证。"   // 476 暂无
                     + "在凭证页批量移交之后, 这里就画出 创建人→使用人。")   // 349 在凭证页批量移交
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(edges.enumerated()), id: \.offset) { _, e in
                HStack(spacing: DS.Space.s) {
                    MemberAvatar(member: m, size: 26)
                    Image(systemName: e.direction == "out" ? "arrow.right.circle.fill" : "arrow.left.circle.fill")
                        .font(.system(size: DS.Icon.xs))
                        .foregroundStyle(DS.Palette.accentText)
                        .accessibilityHidden(true)
                    Text(e.peer)
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(e.label)
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel((e.direction == "out" ? "TA 移交给 " : "移交给 TA 的, 上一手 ") + e.peer + ", " + e.label)
            }
        } header: {
            Text("归属图谱")   // 476 归属图谱
        } footer: {
            // 判据与落盘注记同源 (MemberHub.transferNotePrefix 对 CredentialOrg.batchTransfer),
            // 所以这里说的"移交之后会画出来"是真的会画出来 —— 原先判的是另一个字符串, 这一栏恒为占位句。
            Text("箭头方向: 右 = TA 移交出去 (对端是现在的持有人), 左 = 别人移交给 TA (对端是上一手)。"
                 + "两端都取版本历史里那条「移交 → 使用人」注记与它前一版的归属; 查不到上一手就不画, 不编一个名字顶上。")
                .font(.caption2)
                .foregroundStyle(DS.Palette.textSub)
        }
    }

    // ---------- 家庭场景 (481/468/469/480/484/475) ----------
    private func sceneSection(_ m: Member) -> some View {
        let role = MemberHub.ext(m.id).role
        return Section {
            // 470 这一档真收 UI 的地方之一: 「管凭证」为禁用的角色 (访客) 不出现这枚代管开关,
            // 并且把"为什么这里少了一枚"写在原地 —— 收起来却不说明, 就是本仓反复犯的无声忽略。
            if MemberHub.permAllows(role, "管凭证") {
                Toggle("由我代管 (468: TA 名下凭证被单条停用时, 361 便签补一句 管理员代操作)", isOn: Binding(
                    get: { MemberHub.ext(m.id).proxy },
                    set: { v in
                        var ext = MemberHub.ext(m.id); ext.proxy = v
                        MemberHub.saveExt(m.id, ext)
                        onChanged()
                    }))
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("角色是「" + MemberHub.roleLabel(role) + "」: 矩阵里「管凭证」为禁用, 所以这一档不给代管开关。")   // 468/470 矩阵里
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if MemberHub.dutyThisWeek == m.id {
                StatusPill(text: "本周主责", systemImage: "calendar.badge.clock", tone: .accent)
            }
            Toggle("设为本周主责", isOn: Binding(   // 481 设为本周主责
                get: { MemberHub.dutyThisWeek == m.id },
                set: { v in
                    MemberHub.setDuty(v ? m.id : nil)
                    onChanged()
                }))
            .fixedSize(horizontal: false, vertical: true)
            if MemberHub.proxyNames.contains(m.id) {
                Text("代管中: 在凭证页对 TA 名下凭证做单条停用时, 那一行的 361 停用便签会写上 管理员代操作; "   // 468 代管中
                     + "家庭会议摘要也点名代管中的成员。锁端没有代操作这一位, 这句标注只落本机。")   // 482 家庭会议摘要
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("家庭场景")
        }
    }

    // ---------- 470 权限矩阵 + 469 紧急管理员 + 843 角色与示例内嵌 ----------
    private func permSection(_ m: Member) -> some View {
        let role = MemberHub.ext(m.id).role
        let matrix = MemberHub.permRows(role)          // 470 的表定义在 MemberHub (全仓唯一一份)
        let admins = MemberHub.emergencyAdmins()       // 469 读点: 一次解表, 下面那行点名与会议摘要共用
        return Section {
            // 843 (家庭共享设置那一形态): 角色选择器就放在它驱动的那台矩阵**正上方** ——
            // 选一下当场看得见哪几行亮/灭，不用翻去另一页对照一份会漂移的说明表。
            // 创意原句写的是"查看者/管理员"，本仓那三档是 458 的主理人/成员/访客，
            // 示例文字与矩阵行都由 MemberHub.permRows(role) 现算，不另写一份权限说明 (两处各写一遍迟早互相打脸)。
            Picker("角色", selection: Binding(   // 458/843 角色
                get: { role },
                set: { v in
                    var e = MemberHub.ext(m.id)
                    e.role = v
                    MemberHub.saveExt(m.id, e)
                    onChanged()
                })) {
                Text("主理人").tag("main")
                Text("成员").tag("member")
                Text("访客").tag("guest")
            }
            ForEach(["main", "member", "guest"], id: \.self) { r in
                roleExample(r, current: role)
            }
            ForEach(matrix, id: \.name) { row in
                LabeledContent(row.name) {
                    StatusPill(text: row.allowed ? "允许" : "禁用",
                               systemImage: row.allowed ? "checkmark.circle" : "xmark.circle",
                               tone: row.allowed ? .ok : .neutral)
                }
            }
            Text("矩阵管的是本机 UI: 「管凭证」这一行决定这一档给不给 468 的代管开关 (上方「家庭场景」那一节), "   // 470 矩阵管的是本机
                 + "「成员管理」这一行决定能不能被指成 469 紧急管理员 (就在下面)。不给的那一枚会就地写明为什么少。"
                 + "边界: 锁端没有角色字段, 备份包也不带角色 —— 这三档不改任何发往门锁的字节; "
                 + "角色与代管会被写进成员名册那张 vcf 的备注行。")   // 415 角色与代管会被写进成
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            // 469 的真读点之一: 这一页把"谁被指成了紧急管理员"写在明面上。
            // 原先这个位只有 Toggle 的 set、全仓零读取方, 界面却承诺"救援码说明与其绑定" —— 那句已按实情收窄。
            LabeledContent("紧急管理员") {   // 469 紧急管理员
                Text(admins.isEmpty ? "未指定" : admins.map { MemberHub.display($0) }.joined(separator: "、"))
                    .font(.subheadline)
                    .foregroundStyle(admins.isEmpty ? DS.Palette.textSub : DS.Palette.accentText)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if MemberHub.permAllows(role, "成员管理") {
                Toggle("把 Ta 设为紧急管理员 (469: 本机点名档)", isOn: Binding(
                    get: { MemberHub.ext(m.id).emergencyAdmin },
                    set: { v in
                        var ext = MemberHub.ext(m.id); ext.emergencyAdmin = v
                        MemberHub.saveExt(m.id, ext)
                        onChanged()
                    }))
                .fixedSize(horizontal: false, vertical: true)
                Text("这一档的作用是把人点出来: 上面那一行与 482 家庭会议摘要都会写上 Ta 的名字, 免得只剩一个人管钥匙。"
                     + "救援码本身仍在 设置-安全 里生成, 那段说明目前不读这份名单 —— 两者今天没有绑定关系。")
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("角色是「" + MemberHub.roleLabel(role) + "」: 矩阵里「成员管理」这一行是禁用, 所以这一档不给指成紧急管理员 (470 收的就是本机 UI)。要给它, 先把角色改成主理人。")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("权限与应急")   // 470/469 权限与应急
        }
    }
    /// 843 角色示例行：能/不能两串**由 MemberHub.permRows 现算**，只有场景句是写死的文案
    /// (场景讲的是"这种人通常是谁"，不是权限位 —— 权限位改了这里会跟着变，不会两边各说一套)。
    /// "访客名下仍可以有临时码"这句刻意保留：那是**锁端**的事，470 只管本机 UI，两者最容易被读混。
    private func roleExample(_ r: String, current: String) -> some View {
        let can = MemberHub.permCan(r)
        let cant = MemberHub.permCannot(r)
        let scene: String
        switch r {
        case "main": scene = "通常是房子主人：这台机器上的所有事都归 Ta"
        case "guest": scene = "通常是访客/钟点工：名下仍可以有临时码 (那是锁端的事)，本机这边不给代管、也不给指成紧急管理员"   // 470 通常是访客
        default: scene = "通常是家人：日常开门与补凭证够用，导出与备份不给"
        }
        // 2026-10-13 run 60: 原来把两个 `isEmpty ? … : joined(…)` 三元直接拼进 Text 的字符串里,
        // 整个 roleExample 体报 "unable to type-check this expression in reasonable time"。
        // 先把两串各自算好 (显式 String), 再拼 —— 编译器不再面对一个巨表达式。
        let canText: String = can.isEmpty ? "没有" : can.joined(separator: "、")
        let cantText: String = cant.isEmpty ? "没有" : cant.joined(separator: "、")
        return VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text(MemberHub.roleLabel(r) + (r == current ? " · 当前所选" : ""))
                .font(.caption.weight(.semibold))
                .foregroundStyle(r == current ? DS.Palette.accentText : DS.Palette.text)
            Text("能：" + canText + "　不能：" + cantText)
                .font(.caption2)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            Text(scene)
                .font(.caption2)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // ---------- 补全档案 (265/461/458/457-916/464/465/475/480/484/630) ----------
    private func editProfile(_ m: Member) {
        let e = MemberHub.ext(m.id)
        // 843: 角色不再在这里填英文代码 —— 它有了正上方的单选 (主理人/成员/访客)，两处能改一个值就是两个真相源。
        // 旧写法还留着一个真隐患: 手打 "Main"/"管理员" 这类值不报错，只会被 MemberHub.permRows 静默当成"成员"。
        let alert = UIAlertController(title: "补全档案", message: "角色改到下方「权限与应急」里单选，这里不再填英文代码。", preferredStyle: .alert)   // 470/843 角色改到下方
        func field(_ ph: String, _ initial: String, _ kb: UIKeyboardType = .default) -> UITextField {
            // 2026-10-13 run 60: 参数原名 `init` —— 它是 Swift 的关键字 (初始化器), 于是 `$0.text = init`
            // 里的 `init` 被解析成"类型的初始化器"而不是这个参数 ⇒ 报
            //   "'init' is a member of the type; use 'type(of: ...)' to initialize a new object…"
            //   "cannot reference 'mutating' method as function value" 等 4 条。
            // 改名 `initial`; 调用点全是位置传参 (`field("关系", m.relation)`), 不受影响。
            alert.addTextField { $0.placeholder = ph; $0.text = initial; $0.keyboardType = kb; $0.clearButtonMode = .whileEditing }
            return alert.textFields!.last!
        }
        let fRelation = field("与你的关系", m.relation)
        let fRemark = field("备注名", e.remark)   // 461 备注名
        let fEmoji = field("emoji 代号", e.emoji)   // 916 代号
        let fEmergency = field("紧急联系 姓名+电话", e.emergency)   // 465 紧急联系
        let fNote = field("家庭便签 (475, 如 周六换锁芯)", e.note)
        let fCare = field("孩子码关怀文案", e.careText)   // 480 孩子码关怀文案
        let fWelcome = field("访客欢迎语", e.welcome)   // 484 访客欢迎语
        let fGroup = field("分组标签 家人/访客/服务人员", e.groupTag)   // 630 分组标签
        let fCommon = field("常用锁 (mac 或名称, 逗号分隔; 多锁时排前 464)",
                            e.commonLocks.joined(separator: ", "))
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in
            var next = e
            // role 不在这里改 (见上) —— 保存时保持 e.role 原值, 只改其余字段
            next.emoji = fEmoji.text ?? ""
            next.remark = fRemark.text ?? ""
            next.emergency = fEmergency.text ?? ""
            next.note = fNote.text ?? ""
            next.careText = fCare.text ?? ""
            next.welcome = fWelcome.text ?? ""
            next.groupTag = fGroup.text ?? ""
            next.commonLocks = fCommon.text!
                .split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            MemberHub.saveExt(m.id, next)
            DB.setMemberInfo(m.id, ["relation": fRelation.text ?? ""])
            onChanged()
            app.showToast("档案已保存")
        })
        UIApplication.topViewController()?.present(alert, animated: true)
    }

    // ---------- 263 删除级联提示 (走既有 501 回收站机制) ----------
    // D-152a (2026-10-11 拍板 方案③): 弹窗当场选「只移除档案 / 连锁端一起收回」, 默认第一项。
    // 撤权那一支走的还是 629/353 那条现成队列 (CredentialOrg.enqueue del_pwd/del_fp), 没有新数据面;
    // 指纹不可远程补录 (670) 这句话与选项写在同一屏 —— 它是这个选择唯一的真代价。
    private func confirmDelete(_ m: Member) {
        let preview = CredentialOrg.memberCredentialPreview(m.id)
        let msg = preview.isEmpty
            ? "确定要删除「" + m.name + "」吗? TA 名下没有台账凭证。"
            : "删除「" + m.name + "」后, 名下 " + String(preview.count) + " 条凭证将转为未分配并入回收站 (可整组还原 501):\n"
              + preview.prefix(5).joined(separator: "\n") + (preview.count > 5 ? "\n…" : "")
              + "\n\n· 只移除档案: 只动本机台账, 锁里那些指纹与密码不会被收回, TA 仍能开门。\n"
              + "· 连锁端一起收回: 这些凭证会排上锁端删除, 到场连接后真正失效。"
              + "指纹一旦在锁端删掉就无法远程补录, 只能本人到锁前重录 —— 还原时对指纹只剩本机记录。"
        let alert = UIAlertController(title: "删除成员", message: msg, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "只移除档案", style: .default) { _ in
            for kc in DB.keychains() { CredentialOrg.cascadeBinMember(kc.mac, m.id) }
            DB.removeMember(m.id)
            onChanged()
            app.showToast("已删除并入回收站")
        })
        alert.addAction(UIAlertAction(title: "连锁端一起收回", style: .destructive) { _ in
            // 排上队列的条数在闭包内取 (不改捕获的局部变量: handler 是 escaping 闭包)
            let queued = DB.keychains().reduce(0) { sum, kc in
                sum + CredentialOrg.cascadeBinMember(kc.mac, m.id, revokeLocks: true)
            }
            DB.removeMember(m.id)
            onChanged()
            app.showToast(queued > 0 ? "已删除并入回收站 · 已排 \(queued) 条锁端删除 (连接门锁后生效)"
                                      : "已删除并入回收站 (名下没有可收回的凭证)")
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        UIApplication.topViewController()?.present(alert, animated: true)
    }
}

// ================= 463 建档向导 (称呼 → 角色 → 初始凭证 三小步, 末步顺路建临时码) =================
struct MemberWizardView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    var onDone: () -> Void = {}
    @State private var step = 0
    @State private var name = ""
    @State private var role = "member"
    @State private var emoji = ""
    @State private var remark = ""
    @State private var pwd = ""
    @State private var makePwd = false
    @State private var busy = false
    @State private var newID: String?

    private var steps: [String] { ["称呼与代号", "角色与备注", "初始凭证"] }
    private var canNext: Bool {
        switch step {
        case 0: return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case 1: return true
        default: return !makePwd || (pwd.count >= 6 && pwd.count <= 8)
        }
    }
    private func pwdOK() -> Bool { pwd.count >= 6 && pwd.count <= 8 && pwd.allSatisfy { $0.isNumber } }
    /// 458 向导里的角色副标题: 这一档相对"成员"档多/少哪几项, 全部由 MemberHub.permRows 现算
    /// (470 那张表只有一处定义; 原先这里手写三份"备份/成员管理"式说明, 改了表就说明就漂了)。
    /// 只列差集: iPhone 的选择器行里全列五项会被截断, 而差集才是选角色时真正要看的那一句。
    private func rolePickHint(_ r: String) -> String {
        let mine = MemberHub.permRows(r).filter { $0.allowed }.map { $0.name }
        let base = MemberHub.permRows("member").filter { $0.allowed }.map { $0.name }
        if r == "member" { return mine.joined(separator: "/") }
        let mineSet = Set(mine)
        let baseSet = Set(base)
        let more = mine.filter { !baseSet.contains($0) }
        let less = base.filter { !mineSet.contains($0) }
        if !more.isEmpty { return "比成员多 " + more.joined(separator: "/") }
        if !less.isEmpty { return "比成员少 " + less.joined(separator: "/") }
        return "与成员同"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("步骤 \(step + 1)/3 · " + steps[step]) {
                    switch step {
                    case 0:
                        TextField("称呼 (汉字/英文/数字, 上限 20)", text: $name)
                            .autocorrectionDisabled()
                        Picker("emoji 代号", selection: $emoji) {   // 916 代号
                            ForEach(["", "🐻", "🐱", "🐸", "🐙", "🦊", "🐧", "🐯"], id: \.self) { e in
                                Text(e.isEmpty ? "默认首字" : e).tag(e)
                            }
                        }
                        .pickerStyle(.menu)
                    case 1:
                        Picker("角色", selection: $role) {   // 458/470 角色
                            // 副标题现算, 不手写第二份"这档能干什么" —— 那张表只有 MemberHub.permRows 一处定义
                            ForEach(MemberHub.roles, id: \.self) { r in
                                Text(MemberHub.roleLabel(r) + " (" + rolePickHint(r) + ")").tag(r)
                            }
                        }
                        .pickerStyle(.inline)
                        TextField("备注名 (461, 记录条目显示 称呼（备注）)", text: $remark)
                            .autocorrectionDisabled()
                    default:
                        Toggle("顺路建 10 分钟临时码 (末步)", isOn: $makePwd)
                            .fixedSize(horizontal: false, vertical: true)
                        if makePwd {
                            TextField("6~8 位数字 (下发到当前锁)", text: $pwd)
                                .keyboardType(.numberPad)
                            Text("归属自动记为 TA; 不建也行, 稍后在凭证页添加。")
                                .font(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        // 463: 建档流程内直达指纹录入 (与临时码同格), 录完回凭证页可指归属
                        NavigationLink("录指纹后到凭证页指归属") { StartAddFpView(embedded: true) }   // 463 录指纹后到凭证页指归
                            .font(.footnote)
                    }
                }
                if step < 2 {
                    Section {
                        Button {
                            guard canNext else { return }
                            if step == 0, newID == nil {
                                newID = createMember()
                            }
                            step += 1
                            DS.Haptics.tick.impactOccurred()
                        } label: {
                            Text("下一步")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(DS.Palette.accentText)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .frame(minHeight: DS.Hit.min)
                        }
                        .buttonStyle(PlainButtonStyle())
                        // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 命中高仅约 14.5pt (< 44)。
                        // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Rectangle())
                    }
                } else {
                    Section {
                        BusyButton(title: busy ? "处理中…" : "完成建档",
                                    systemImage: "checkmark.seal", isBusy: busy) {
                            submit()
                        }
                        .disabled(!canNext || busy)
                    }
                }
            }
            .navigationTitle("建档向导")   // 463 建档向导
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("取消") { dismiss() } } }
            .axBottomAnchor()   // 870
        }
    }

    private func createMember() -> String? {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard let m = DB.addMember(n) else {
            app.showToast("姓名为空或已存在 (可走 462 合并)")
            return nil
        }
        var e = MemberHub.ext(m.id)
        e.emoji = emoji
        e.role = role
        e.remark = remark
        MemberHub.saveExt(m.id, e)
        if app.pendingFpOwner == "request" { app.pendingFpOwner = m.id }   // 317: 建完交回
        return m.id
    }

    private func submit() {
        guard let id = newID ?? createMember() else { dismiss(); return }
        guard makePwd, pwdOK() else {
            onDone()
            dismiss()
            app.showToast("已添加「" + name + "」")
            return
        }
        busy = true
        Task {
            defer {
                busy = false
                onDone()
                dismiss()
            }
            guard let kc = app.current else {
                app.showToast("已建档; 建码需先选一把锁")
                return
            }
            do {
                try await app.lock.ensureConnected(mac: kc.mac)
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = "yyyy-MM-dd HH:mm:ss"
                let from = f.string(from: Date())
                let to = f.string(from: Date().addingTimeInterval(600))
                let alias = try await app.lock.pwdAdd(pwd: pwd, validFrom: from, validTo: to)
                let rec = LedgerPwd(alias: alias, from: from, to: to, temp: true,
                                     at: Date().timeIntervalSince1970 * 1000, pwd: pwd, owner: id,
                                     note: "向导建码 · " + name)
                DB.addPwd(kc.mac, rec)
                CredentialOrg.snapshot(kc.mac, kind: "pwd", key: alias, pwd: rec, fp: nil, note: "新增临时码")
                app.showToast("已建档并给 TA 建了 10 分钟临时码")
            } catch {
                app.showToast("建档成功, 建码失败: " + error.localizedDescription)
            }
        }
    }
}

// ================= 462 重复合并 (同名检测 + 手动迁移凭证归属) =================
struct MergeMembersView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let primary: Member
    var onDone: () -> Void = {}
    @State private var secondaryID: String?

    private var secondaryCandidates: [Member] {
        DB.members().filter { $0.id != primary.id && $0.name == primary.name }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("主档 (保留)") {
                    HStack(spacing: DS.Space.s) {
                        MemberAvatar(member: primary, size: 28)
                        Text(MemberHub.display(primary))
                            .font(.subheadline)
                            .foregroundStyle(DS.Palette.text)
                        Spacer(minLength: 0)
                    }
                }
                Section("副档 (凭证将迁移至主档, 档案删除)") {
                    Picker("选择副档", selection: $secondaryID) {
                        Text("请选择").tag(nil as String?)
                        ForEach(secondaryCandidates) { m in
                            Text(m.name + " · 名下 " + String(MemberHub.activity(m.id).owns) + " 条").tag(m.id as String?)
                        }
                    }
                    .pickerStyle(.inline)
                    if secondaryID == nil {
                        Text("没有同名成员。若只是称呼重复, 请在成员页重命名其一。")
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Section {
                    Button { doMerge() } label: {
                        Text("执行合并")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: DS.Hit.min)
                    }
                    .buttonStyle(PrimaryActionStyle())
                    .disabled(secondaryID == nil)
                    // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 命中高仅约 16.5pt (< 44)。
                    // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
            }
            .navigationTitle("重复合并")   // 462 重复合并
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("取消") { dismiss() } } }
        }
    }

    private func doMerge() {
        guard let sid = secondaryID else { return }
        var moved = 0
        for kc in DB.keychains() {
            for p in DB.listPwds(kc.mac) where p.owner == sid {
                DB.setPwdOwner(kc.mac, p.alias, primary.id); moved += 1
            }
            for f in DB.listFps(kc.mac) where f.owner == sid {
                DB.setFpOwner(kc.mac, f.batch, primary.id); moved += 1
            }
        }
        MemberHub.reassignClaims(from: sid, to: primary.id)   // 462
        DB.removeMember(sid)
        onDone()
        app.showToast("已合并, 迁移 \(moved) 条凭证至「" + primary.name + "」")
        dismiss()
    }
}

// ================= 474 退出处置向导 (归档成员时名下凭证逐条: 移交/停用/保留) =================
struct MemberExitWizard: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let memberID: String
    var onDone: () -> Void = {}
    @State private var decisions: [String: String] = [:]
    @State private var moveItem: Item?   // 474 候选移接人多于一个时挂起, 由确认框选目标

    private struct Item: Identifiable {
        var id: String
        var label: String
        var mac: String
        var kind: String
        var key: Int
    }
    private var items: [Item] {
        var out = [Item]()
        for kc in DB.keychains() {
            for p in DB.listPwds(kc.mac).filter({ $0.owner == memberID }) {
                out.append(Item(id: "p" + String(p.alias),
                                 label: CredentialOrg.displayPwd(p),
                                 mac: kc.mac, kind: "pwd", key: p.alias))
            }
            for f in DB.listFps(kc.mac).filter({ $0.owner == memberID }) {
                out.append(Item(id: "f" + String(f.batch),
                                 label: "「" + f.name + "」",
                                 mac: kc.mac, kind: "fp", key: f.batch))
            }
        }
        return out
    }
    private var allDecided: Bool { items.allSatisfy { decisions[$0.id] != nil } }

    var body: some View {
        NavigationStack {
            Form {
                if items.isEmpty {
                    Section {
                        Text("该成员名下没有台账凭证, 直接归档即可。")   // 460/795 该成员名下没有台账凭
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                } else {
                    Section {
                        ForEach(items) { it in
                            HStack(spacing: DS.Space.s) {
                                Text(it.label)
                                    .font(.subheadline)
                                    .foregroundStyle(DS.Palette.text)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Spacer(minLength: 0)
                                Menu {
                                    Button("移交他人") { decide(it, "move") }
                                    Button("停用 (入回收站)") { decide(it, "delete") }
                                    Button("保留原样") { decide(it, "keep") }
                                } label: {
                                    StatusPill(text: optionLabel(decisions[it.id]),
                                                systemImage: "ellipsis.circle",
                                                tone: decisions[it.id] == nil ? .neutral : .accent)
                                }
                            }
                            .frame(minHeight: DS.Hit.min)
                        }
                    } header: {
                        Text("逐条处置 (474 · 保留/移交/停用)")
                    }
                }
                Section {
                    Button {
                        if !items.isEmpty && !allDecided {
                            app.showToast("先把每条凭证选一种处置")
                            return
                        }
                        var e = MemberHub.ext(memberID)
                        e.archived = true
                        MemberHub.saveExt(memberID, e)
                        onDone()
                        app.showToast("已归档, 历史记录保留")   // 460/795 已归档
                        dismiss()
                    } label: {
                        Text("归档并执行")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: DS.Hit.min)
                    }
                    .buttonStyle(DestructiveActionStyle())
                    // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 命中高仅约 16.5pt (< 44)。
                    // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
            }
            .navigationTitle("退出处置向导")   // 474 退出处置向导
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("取消") { dismiss() } } }
            // 474 候选移接人多于一个时不许替用户抓第一个: 弹确认框让用户自己选目标
            .confirmationDialog("移交给谁", isPresented: Binding(   // 474 移交给谁
                get: { moveItem != nil },
                set: { if !$0 { moveItem = nil } }
            ), titleVisibility: .visible) {
                ForEach(moveTargets) { t in
                    Button(MemberHub.display(t)) {
                        if let it = moveItem { performMove(it, to: t) }
                        moveItem = nil
                    }
                }
                Button("取消", role: .cancel) { moveItem = nil }
            }
        }
    }

    private var moveTargets: [Member] { DB.members().filter { $0.id != memberID && !MemberHub.ext($0.id).archived } }

    private func performMove(_ it: Item, to t: Member) {
        decisions[it.id] = "move"
        if it.kind == "pwd" { DB.setPwdOwner(it.mac, it.key, t.id) }
        else { DB.setFpOwner(it.mac, it.key, t.id) }
        app.showToast("已移交至「" + MemberHub.display(t) + "」")
    }

    private func decide(_ it: Item, _ d: String) {
        switch d {
        case "move":
            let targets = moveTargets
            if targets.isEmpty {
                decisions[it.id] = "keep"
                app.showToast("没有可移交的成员, 已保留")
            } else if targets.count == 1 {
                performMove(it, to: targets[0])
            } else {
                // 多候选: 等确认框里选定目标再落 decided, 取消则维持未决
                moveItem = it
            }
        case "delete":
            decisions[it.id] = "delete"
            if it.kind == "pwd" {
                guard let p = DB.listPwds(it.mac).first(where: { $0.alias == it.key }) else { return }
                // 确认口径：这一支是归档向导里**逐项决策**的 result —— 用户已在每一条上亲手选了「删除」
                //   (787/788 的三选一：保留 / 移交 / 删除)，此处是执行选择，不是发起动作；删的行与相邻 addToBin 同一条。
                DB.delPwd(it.mac, it.key)
                CredentialOrg.addToBin(it.mac, pwd: p, source: .manual)
                CredentialOrg.enqueue(it.mac, kind: "del_pwd", title: "删除密码 #" + String(it.key), pwd: p)
            } else {
                guard let f = DB.listFps(it.mac).first(where: { $0.batch == it.key }) else { return }
                // 确认口径：同上面密码那一支 —— 逐项决策里已选「删除」，这里是执行。
                DB.delFp(it.mac, it.key)
                CredentialOrg.addToBin(it.mac, fp: f, source: .manual)
                CredentialOrg.enqueue(it.mac, kind: "del_fp", title: "删除指纹批次 " + String(it.key), fp: f)
            }
            app.showToast("已停用并入回收站")
        default:
            decisions[it.id] = "keep"
        }
    }
    private func optionLabel(_ d: String?) -> String {
        switch d {
        case "move": return "移交"
        case "delete": return "停用"
        case "keep": return "保留"
        default: return "未决"
        }
    }
}

// ================= 472 借用登记 (凭证页顶横条的销记) =================
struct BorrowSheetView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let memberID: String
    var onDone: () -> Void = {}
    @State private var mac: String
    @State private var by = ""
    @State private var due = ""
    @State private var tick = 0

    init(memberID: String, onDone: @escaping () -> Void) {
        self.memberID = memberID
        self.onDone = onDone
        _mac = State(initialValue: DB.preferredMac())
    }

    private var borrowMap: [String: MemberBorrow] { MemberHub.borrows(mac) }

    var body: some View {
        NavigationStack {
            List {
                Section("新建借用 (472 · 归属 " + (DB.member(memberID)?.name ?? "成员") + ")") {
                    TextField("借用人", text: $by)
                        .autocorrectionDisabled()
                    TextField("归还日期 yyyy-MM-dd", text: $due)
                        .autocorrectionDisabled()
                    Button { register() } label: {
                        Label("登记", systemImage: "person.2.badge.plus")
                            .font(.subheadline)
                            .foregroundStyle(DS.Palette.accentText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(by.isEmpty || due.isEmpty)
                }
                Section("进行中 (\(borrowMap.count)) · 点 已归还 销记") {
                    ForEach(Array(borrowMap.keys.sorted()), id: \.self) { k in
                        // 2026-10-13 对抗式点击审计: 原写 `let b = borrowMap[k]!` —— borrowMap 是
                        // **计算属性** (每次重新查 DB), ForEach 的 key 集合与闭包求值来自两次独立调用,
                        // 中间任何一次删除/销记都会让 k 在新 map 里消失 ⇒ 强解包 trap。
                        // 同一帧同线程数据不变所以当前不可达, 但这是"计算属性 + 下标强解包"的教科书款。
                        // 2026-10-13 修 CI: 上面那版写成了 `guard let b = borrowMap[k] else { continue }` ——
                        // ViewBuilder 闭包里 `continue` 找不到所属循环 (这不是 for 循环, 是逐元素的 builder 闭包),
                        // 编译错被级联到 ForEach 的初始化器上 ("no exact matches in call to initializer")。
                        // builder 语境的等价写法就是 if let: 键不在新 map 里就安静跳过, 语义一致。
                        if let b = borrowMap[k] {
                        HStack(spacing: DS.Space.s) {
                            Text(k.hasPrefix("b") ? "凭证明细见凭证页" : k)
                                .font(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                            Text("借给 " + b.by + " · 还 " + b.due)
                                .font(.subheadline)
                                .foregroundStyle(DS.Palette.text)
                            Spacer(minLength: 0)
                            Button("已归还") {
                                MemberHub.saveBorrow(mac, itemKey: k, nil)
                                tick += 1
                                onDone()
                                app.showToast("已销记归还")
                            }
                            .buttonStyle(SecondaryActionStyle(fullWidth: false))
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Rectangle())
                        }
                        }
                    }
                    if borrowMap.isEmpty {
                        Text("没有进行中的借用。")
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                }
            }
            .navigationTitle("借用登记")   // 472 借用登记
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("完成") { dismiss() } } }
            .id(tick)
        }
    }

    private func register() {
        // 登记在当前锁该成员名下第一条凭证上; 无凭证时用时间戳键占位
        var key = "b" + String(Int(Date().timeIntervalSince1970))
        if let p = DB.listPwds(mac).first(where: { $0.owner == memberID }) {
            key = "p" + String(p.alias)
        } else if let f = DB.listFps(mac).first(where: { $0.owner == memberID }) {
            key = "f" + String(f.batch)
        }
        MemberHub.saveBorrow(mac, itemKey: key, MemberBorrow(by: by, due: due, at: Date().timeIntervalSince1970))
        tick += 1
        onDone()
        app.showToast("已登记: " + by + " · 还 " + due)
    }
}

// ================= 460/795 归档成员列表 (恢复入口) =================
struct MemberArchivedView: View {
    @Environment(\.dismiss) private var dismiss
    var onRestored: () -> Void = {}
    @State private var tick = 0

    private var archived: [Member] {
        DB.members().filter { MemberHub.ext($0.id).archived }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(archived) { m in
                    LabeledContent {
                        Button("恢复") {
                            var e = MemberHub.ext(m.id)
                            e.archived = false
                            MemberHub.saveExt(m.id, e)
                            tick += 1
                            onRestored()
                        }
                        .buttonStyle(SecondaryActionStyle(fullWidth: false))
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Rectangle())
                    } label: {
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text(MemberHub.display(m))
                                .font(.subheadline)
                                .foregroundStyle(DS.Palette.text)
                            Text("归档中 · 只从成员列表与成员统计里收起; 记录页仍能筛到 TA, "
                                 + "凭证页也仍列 TA 名下凭证 —— 归档不许挡撤权入口。")   // 460/795 凭证页也仍列
                                .font(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if archived.isEmpty {
                    Text("归档列表为空 — 成员归档后历史不蒸发。")   // 795 归档列表为空
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                }
            }
            .navigationTitle("归档成员")   // 460/795 归档成员
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("完成") { dismiss() } } }
            .id(tick)
        }
    }
}

// ================= 630 分组标签编辑 =================
struct MemberGroupSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    var onSaved: () -> Void = {}
    @State private var tags: [String: String] = [:]

    private let options = ["", "家人", "访客", "服务人员"]

    var body: some View {
        NavigationStack {
            Form {
                Section("成员分组标签") {   // 630 成员分组标签
                    ForEach(DB.members(), id: \.id) { m in
                        Picker(MemberHub.display(m), selection: Binding(
                            get: { tags[m.id] ?? MemberHub.ext(m.id).groupTag },
                            set: { tags[m.id] = $0 })
                        ) {
                            ForEach(options, id: \.self) { o in
                                Text(o.isEmpty ? "无分组" : o).tag(o)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                Section {
                    Button {
                        for (mid, t) in tags {
                            var e = MemberHub.ext(mid)
                            e.groupTag = t
                            MemberHub.saveExt(mid, e)
                        }
                        onSaved()
                        app.showToast("分组已保存")
                        dismiss()
                    } label: {
                        Text("保存分组")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: DS.Hit.min)
                    }
                    .buttonStyle(PrimaryActionStyle())
                    // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 命中高仅约 16.5pt (< 44)。
                    // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
            }
            .navigationTitle("分组标签")   // 630 分组标签
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("取消") { dismiss() } } }
        }
    }
}

// ================= 479/794 家庭设置 (长辈模式 · 隐私浏览) =================
// 486 (长辈模式下临时码完成页默认进口述卡) 已接: 落地点在 CredentialStudio 的 TempCodeStudio.doneCard,
// 那边读 MemberHub.elderMode —— 完成页收成 口述卡 + 一枚大「完成」, 常规那几段 (329/333/再发一张) 就地说明后收起。
// 这一页只负责把话说明白 (见下面 elder 那一节), 不做第二份实现。
struct MemberFamilySettingsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var elder = MemberHub.elderMode
    @State private var privacy = MemberHub.privacyActive
    @State private var privacyLeft = 0

    var body: some View {
        NavigationStack {
            Form {
                // 479/486 长辈模式的两个落点都写在下面那段话里: 479 = 凭证页大字高对比 (凭证页行上),
                // 486 = 临时码完成页收成口述卡 (CredentialStudio.doneCard)。开关本身只写 MemberHub.elderMode。
                Section("长辈模式") {   // 479/486 长辈模式
                    Toggle("长辈模式 (凭证页大字高对比、只留密码/指纹两组 · 临时码完成页收成口述卡)", isOn: $elder)
                        .fixedSize(horizontal: false, vertical: true)
                    if elder {
                        Text("凭证页: 分段只留 全部/密码/指纹, 批量与导出入口收起, 组尾那条过期清理也不出现; "
                             + "凭证行标题升到标题级、副行升到正文档, 副行文字改用主文本色 —— 大字与高对比就落在这两处。"   // 479 凭证行标题升到标题级
                             + "这一档只动凭证页与临时码完成页, 其它页面不跟着变。")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("临时码完成页: 开这一档后完成页只留大字号口述卡 + 一枚大「完成」, "   // 486 临时码完成页
                             // 329 一句话口令
                             // 333 一句话口令
                             + "一句话口令 / 首用回执 / 再发一张 那几段收起并在原地说明; 页标题也切到「口述卡」。")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Section("隐私浏览") {   // 794 隐私浏览
                    Toggle("隐私浏览 (限时 10 分钟: 写隐私时段标记, 本页回显剩余时间)", isOn: $privacy)
                        .fixedSize(horizontal: false, vertical: true)
                    if privacy {
                        Text(privacyLeft > 0
                             ? "剩余 \(privacyLeft) 秒后自动关闭"
                             : "开启后 10 分钟自动关闭; 当前只写隐私时段标记并在本页回显, 不改统计口径")   // 794 开启后
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .navigationTitle("家庭设置")
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) {
                Button("保存") {
                    MemberHub.setElderMode(elder)
                    MemberHub.setPrivacy(privacy)
                    dismiss()
                }
            } }
            .onAppear {
                privacyLeft = max(0, Int(MemberHub.privacyUntilSec - Date().timeIntervalSince1970))
            }
        }
    }
}

// ================= 791 未归属记录认领 (记录页跳来, 本机覆盖层不改锁端) =================
struct UnclaimedClaimView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var mac: String
    @State private var selMember: [String: String] = [:]

    init() {
        _mac = State(initialValue: DB.preferredMac())
    }

    private struct Row: Identifiable {
        var key: String
        var time: String
        var kindWord: String
        var id: String { key }
    }
    /// 未归属行 = 归属推不出 (who 为空); 793 判定里 temp 类进访客分组, 其余进认领
    private var unclaimed: [Row] {
        var out = [Row]()
        for kc in DB.keychains() where kc.mac == mac {
            let logs = DB.readLogs(kc.mac).filter { StatsKit.openTypes.contains($0.type) }
            let status = DB.readStatus(kc.mac)
            let rows = Attribution.classify(
                logs: logs.map { LogEntry(type: $0.type, typeName: $0.typeName, idx: $0.idxRaw, idxRaw: $0.idxRaw,
                                          lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr, body: "") },
                pwds: DB.listPwds(kc.mac), fps: DB.listFps(kc.mac),
                status: status.map { ($0.fpStock, $0.pwdStock, $0.lockTime) })
            for (i, r) in rows.enumerated() where r.who == nil {
                let word = r.kind.map { Attribution.words[$0] ?? "记录" } ?? "记录"
                // 认领键与记录页 RowVM.key 对齐 (String(idxRaw)), 覆盖层才能生效
                out.append(Row(key: String(logs[i].idxRaw),
                                time: logs[i].lockTimeStr, kindWord: word))
            }
        }
        return out.sorted { $0.time > $1.time }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(unclaimed.prefix(20)) { r in
                        VStack(alignment: .leading, spacing: DS.Space.xs) {
                            HStack(spacing: DS.Space.s) {
                                Text(String(r.time.prefix(16)))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(DS.Palette.textSub)
                                Text(r.kindWord + " (未归属, 台账推断)")
                                    .font(.subheadline)
                                    .foregroundStyle(DS.Palette.textSub)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                StatusPill(text: "待认领", systemImage: "questionmark.circle", tone: .neutral)
                            }
                            Picker("认领给", selection: Binding(
                                get: { selMember[r.key] ?? "" },
                                set: { selMember[r.key] = $0 })
                            ) {
                                ForEach(DB.members().filter { !MemberHub.ext($0.id).archived }) { m in
                                    Text(MemberHub.display(m)).tag(m.id)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                    if unclaimed.isEmpty {
                        Text("没有未归属的开门记录 (归属只算可证明的, 推不出就进这里认领)。")
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                } header: {
                    Text("未归属记录认领")   // 791 未归属记录认领
                }
                Section {
                    Button {
                        var n = 0
                        for (k, mid) in selMember {
                            MemberHub.claim(mac, logKey: k, memberId: mid)
                            n += 1
                        }
                        app.showToast("已认领 \(n) 条 (本机覆盖层, 不改锁端数据)")
                        selMember = [:]
                        dismiss()
                    } label: {
                        Label("认领所选 (\(selMember.count))", systemImage: "checkmark.seal")
                            .font(.subheadline)
                            .foregroundStyle(DS.Palette.accentText)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(selMember.isEmpty)
                }
            }
            .navigationTitle("认领未归属")   // 791 认领未归属
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("完成") { dismiss() } } }
        }
    }
}

// ================= 788 成员活跃总表 (每人一行, 点击进 789 聚合详情) =================
struct MemberActiveTable: View {
    @EnvironmentObject var app: AppState
    var onChanged: () -> Void = {}

    private struct Row: Identifiable {
        var m: Member
        var a: MemberHub.Activity
        var id: String { m.id }
    }
    private var rows: [Row] {
        DB.members()
            .filter { !MemberHub.ext($0.id).archived }
            .map { m in Row(m: m, a: MemberHub.activity(m.id)) }
            .sorted { $0.a.owns > $1.a.owns }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("成员活跃总表 (788 · 本月次数/最近使用/凭证数)") {
                    ForEach(rows) { r in
                        NavigationLink {
                            MemberDetail360View(memberID: r.m.id, onChanged: { onChanged() })
                        } label: {
                            HStack(spacing: DS.Space.s) {
                                MemberAvatar(member: r.m)
                                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                                    Text(MemberHub.display(r.m))
                                        .font(.subheadline)
                                        .foregroundStyle(DS.Palette.text)
                                    Text("本月约 \(r.a.month) 次 · 名下 \(r.a.owns) 条 · 最近 "
                                         + (r.a.last.isEmpty ? "—" : String(r.a.last.prefix(10))))
                                        .font(.caption)
                                        .foregroundStyle(DS.Palette.textSub)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                            .frame(minHeight: DS.Hit.min)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if rows.isEmpty {
                        // 这一屏的 rows 排除**已归档**成员，所以"空"有两种完全不同的原因：
                        // 一台都没建过档 vs 全都归档了。后者说"去建档"是在催用户重复建一遍档案。
                        // 计数按"档案还在名册里的归档者"算 —— ext 表可能留着已删成员的残档。
                        let archIds = MemberHub.archivedIDs()
                        let arch = DB.members().filter { archIds.contains($0.id) }.count
                        Text(arch > 0
                            ? "在册成员是空的 — 本机有 \(arch) 位归档成员，回成员中心点「归档成员」那一栏找回。"   // 788 在册成员是空的
                            : "还没有成员 — 在 成员中心 走建档向导。")
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .navigationTitle("成员活跃总表")   // 788 成员活跃总表
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) {
                Button("完成") { app.tabSelection = 3 }
            } }
        }
    }
}

// ================= 798 成员堆叠面积图 + 792 成员轮换小节 (全锁台账推断, 带"约") =================
struct MemberStackedView: View {
    struct StackPt: Identifiable {
        var day: Date
        var who: String
        var n: Int
        var id: String { "\(who)|\(day.timeIntervalSince1970)" }
    }
    struct RotationPoint {
        var label: String
        var detail: String
    }

    /// 798 成员堆叠面积图: 真序列 = 每个 (日 × 成员) 一个点，AreaMark 按成员分层累加。
    /// 旧写法把所有点的 day 都填 now、y 恒为 1、x 是跨成员的累计数 ——
    /// 那画出来是一条与时间无关的水平带，轴标却写"成员分层累计 (30 天)"，是纯装饰。
    private var stack: [StackPt] {
        var per: [String: [String: Int]] = [:]          // who -> 日 key -> 次数
        let now = Date()
        for kc in DB.keychains() {
            let logs = DB.readLogs(kc.mac).filter { StatsKit.openTypes.contains($0.type) }
            let status = DB.readStatus(kc.mac)
            let rows = Attribution.classify(
                logs: logs.map { LogEntry(type: $0.type, typeName: $0.typeName, idx: $0.idxRaw, idxRaw: $0.idxRaw,
                                          lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr, body: "") },
                pwds: DB.listPwds(kc.mac), fps: DB.listFps(kc.mac),
                status: status.map { ($0.fpStock, $0.pwdStock, $0.lockTime) })
            let cutoff = now.addingTimeInterval(-30 * 86400)
            for (i, r) in rows.enumerated() {
                guard let who = r.who else { continue }
                let unix = ZKProtocol.protoSecondsToUnix(Int64(logs[i].lockTime))
                guard unix >= cutoff.timeIntervalSince1970 else { continue }
                let day = Date(timeIntervalSince1970: Double(unix))
                // 日 key 走 StatsKit.dayKey 那一份 (与 616/780/642 同一套周序与假日口径)
                per[who, default: [:]][StatsKit.dayKey(day), default: 0] += 1
            }
        }
        var out: [StackPt] = []
        for (who, days) in per {
            for (key, n) in days {
                guard let d = RecordSearch.dateFromKey(key) else { continue }
                out.append(StackPt(day: d, who: who, n: n))
            }
        }
        return out.sorted { $0.day < $1.day }
    }

    private var rotations: [RotationPoint] {
        var out: [RotationPoint] = []
        let cal = WeekCal.gregorian
        for kc in DB.keychains() {
            let logs = DB.readLogs(kc.mac).filter { StatsKit.openTypes.contains($0.type) }
            let rows = Attribution.classify(
                logs: logs.map { LogEntry(type: $0.type, typeName: $0.typeName, idx: $0.idxRaw, idxRaw: $0.idxRaw,
                                          lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr, body: "") },
                pwds: DB.listPwds(kc.mac), fps: DB.listFps(kc.mac), status: nil)
            var prevFirst: String? = nil
            var byDay: [String: [String]] = [:]
            var order: [String] = []
            for (i, r) in rows.enumerated() where r.who != nil {
                let dk = String(logs[i].lockTimeStr.prefix(10))
                if byDay[dk] == nil { order.append(dk) }
                byDay[dk, default: []].append(r.who!)
            }
            for dk in order.suffix(7) {
                // 792: 保序去重 — 原先 Set(...) 打乱"在家顺序", 同一天顺序每次刷新都在变
                var seen = Set<String>()
                let names = byDay[dk]!.filter { seen.insert($0).inserted }.map { DB.member($0)?.name ?? "成员" }
                let first = names.joined(separator: " / ")
                if let p = prevFirst, p != first, !names.isEmpty {
                    out.append(RotationPoint(label: "「" + (DB.keychain(kc.mac).map { LockArchive.displayName($0) } ?? kc.mac) + "」"
                                             + String(dk.dropFirst(5)),
                                             detail: "在家顺序变化: " + first))
                }
                if !names.isEmpty { prevFirst = first }
            }
            _ = cal
        }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            if stack.isEmpty {
                Text("近 30 天还没有可证明归属的开门数据, 积累后这里会出 798 堆叠图 (约级口径)。")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .padding(DS.Space.l)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Chart(stack) { p in
                    AreaMark(x: .value("日期", p.day),
                             y: .value("开门次数", p.n))
                        // 798: 图例显示成员名而不是归属 id (unknown 归 id 显示兜底)
                        .foregroundStyle(by: .value("成员", DB.member(p.who).map(MemberHub.display) ?? p.who))
                        .interpolationMethod(.monotone)
                }
                .chartXAxisLabel("近 30 天逐日 (台账推断, 约)", alignment: .leading)
                .frame(height: 140)
                .padding(.horizontal, DS.Space.gutter)
            }
            // 789: 图例成员可点进 360 (与活跃总表行同一落点)
            if !stack.isEmpty {
                ForEach(Set(stack.map(\.who)).sorted(), id: \.self) { w in
                    NavigationLink { MemberDetail360View(memberID: w) } label: {
                        Label(DB.member(w).map(MemberHub.display) ?? w, systemImage: "person.circle")
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.accentText)
                    }
                    .frame(minHeight: DS.Hit.min)
                }
            }
            if !rotations.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    SectionTitle(text: "成员轮换", count: rotations.count)   // 792 成员轮换
                    ForEach(rotations.prefix(5), id: \.label) { r in
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text(r.label)
                                .font(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                            Text(r.detail)
                                .font(.subheadline)
                                .foregroundStyle(DS.Palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, DS.Space.gutter)
            }
        }
        .padding(.vertical, DS.Space.s)
    }
}

// ================= 482 家庭会议摘要 (30 天数据合成一页"家庭会议材料") =================
struct MemberMeetingSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var text: String {
        var lines: [String] = []
        lines.append("家庭会议摘要 · 近 30 天")
        let lockUsages = LockStats.usage()
        lines.append("成员 " + String(DB.members().count) + " 位 · 门锁 " + String(DB.keychains().count) + " 把 · 凭证 "
                     + String(DB.keychains().reduce(0) { $0 + DB.listPwds($1.mac).count + DB.listFps($1.mac).count }) + " 条")
        for m in DB.members() where !MemberHub.ext(m.id).archived {
            let a = MemberHub.activity(m.id)
            lines.append("· " + MemberHub.display(m) + " (约): 近 30 天开门 " + String(a.opens30)
                         + " 次 · 名下凭证 " + String(a.owns) + " 条")
        }
        for u in lockUsages {
            lines.append("· 锁「" + u.name + "」: 近 30 天开门约 " + String(u.opens30d)
                         + " 次 · 告警 " + String(u.alarms30d) + " 条")
        }
        let expiring = DB.keychains().compactMap { kc -> String? in
            let soon = DB.listPwds(kc.mac).filter { p in
                guard let d = CredentialOrg.expiryDate(p) else { return false }
                return d.timeIntervalSinceNow < 7 * 86400
            }
            return soon.isEmpty ? nil : "· 7 天内到期 " + String(soon.count) + " 条 (" + LockArchive.displayName(kc) + ")"
        }
        lines.append(contentsOf: expiring)
        if let duty = MemberHub.dutyThisWeek, let dm = DB.member(duty) {
            lines.append("· 本周主责: " + MemberHub.display(dm))
        }
        // 469 的第二个真读点: 会议材料里点名紧急管理员 (原先这个位全仓零读取方)
        let ea = MemberHub.emergencyAdmins()
        lines.append("· 紧急管理员: " + (ea.isEmpty ? "未指定" : ea.map { MemberHub.display($0) }.joined(separator: "、")))   // 469 紧急管理员
        // 468 的读点之一: 代管中的成员在这里点名; 逐条标注落在凭证页那一条 361 停用便签上
        let prox = MemberHub.proxyNames
        let pm = DB.members().filter { prox.contains($0.id) }
        lines.append("· 代管中: " + (pm.isEmpty ? "没有" : pm.map { MemberHub.display($0) }.joined(separator: "、")))   // 468 代管中
        return lines.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                ScrollView {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DS.Space.l)
                        // 2026-10-14 材质统一: 代管清单面板从实底改玻璃 (它是这页唯一的面板)
                        .axGlass(DS.Radius.card)
                }
                .padding(.horizontal, DS.Space.gutter)
                HStack(spacing: DS.Space.s) {
                    Button {
                        UIPasteboard.general.string = text
                        copied = true
                        app.showToast("会议材料已复制")
                    } label: {
                        Label(copied ? "已复制" : "复制会议材料",
                              systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(DS.Palette.accentText)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(SecondaryActionStyle(fullWidth: false))
                }
                .padding(.horizontal, DS.Space.gutter)
            }
            .padding(.vertical, DS.Space.m)
            .navigationTitle("家庭会议摘要")   // 482 家庭会议摘要
            .navigationBarTitleDisplayMode(.inline)
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("完成") { dismiss() } } }
        }
    }
}

// ================= 475 家庭便签 (一行本地文本, 与成员绑定, 设备页 Hero 下浮动显示) =================
struct FamilyNoteView: View {
    @EnvironmentObject var app: AppState
    @State private var selMember: String
    @State private var text: String = ""
    @State private var tick = 0

    init() {
        _selMember = State(initialValue: DB.members().first?.id ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            if !selMember.isEmpty {
                LabeledContent("挂在谁名下") {
                    // @layout-allow 触达托管 Picker: 控件本体高度由系统渲染, 我们撑 frame 只会多出一片点不动的死区。
                    // 上机复测: 用拇指点这一行的上下边缘, 看打不打得开 (打得开=系统已给够 44, 这条可以销)
                    Picker("成员", selection: $selMember) {
                        ForEach(DB.members().filter { !MemberHub.ext($0.id).archived }) { m in
                            Text(MemberHub.display(m)).tag(m.id)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            TextField("一行便签 (如 周六换锁芯)", text: $text)
                .autocorrectionDisabled()
                .lineLimit(2)
            Text("便签存在本机, 绑在成员身上, 设备页 Hero 卡下方浮动显示。")   // 475 便签存在本机
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.Space.s) {
                Button { save() } label: {
                    Text("保存便签")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: DS.Hit.min)
                }
                .buttonStyle(PrimaryActionStyle())
                .disabled(selMember.isEmpty || text.isEmpty)
                // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 命中高仅约 16.5pt (< 44)。
                // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
            }
        }
        .padding(DS.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsScreenBackground()
        .onAppear {
            text = MemberHub.ext(selMember).note
        }
        .onChange(of: selMember) { _, _ in
            text = MemberHub.ext(selMember).note
            tick += 1
        }
        .id(tick)
    }

    private func save() {
        var e = MemberHub.ext(selMember)
        e.note = text
        MemberHub.saveExt(selMember, e)
        app.showToast("便签已挂到「" + (DB.member(selMember)?.name ?? "成员") + "」名下")
    }
}

// ================= 483 家政周期预设 (⚠降级: 协议无循环时段, 只做整段起止窗) =================
struct HouseCleaningPresetView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var mac: String
    @State private var from: Date
    @State private var to: Date
    @State private var label = "家政"
    @State private var busy = false

    init() {
        _mac = State(initialValue: DB.preferredMac())
        _from = State(initialValue: Date())
        _to = State(initialValue: Date().addingTimeInterval(8 * 3600))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("家政周期预设") {   // 483 家政周期预设
                    DatePicker("开始", selection: $from, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("结束", selection: $to, displayedComponents: [.date, .hourAndMinute])
                    TextField("标签", text: $label)
                        .autocorrectionDisabled()
                    Text("协议未定义循环时段, 预设只生成一段整窗; 工作日 8:00-18:00 每日循环需锁端支持, 暂不做。")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section {
                    BusyButton(title: busy ? "生成中…" : "生成家政整窗",
                                systemImage: "calendar.badge.clock", isBusy: busy) {
                        submit()
                    }
                    .disabled(mac.isEmpty || from >= to)
                }
                // houseWin(mac) 此前零调用: 只能写入、读不回来, 用户提交后页面一片空白, 看着像没存上
                if let cur = MemberHub.houseWin(mac) {
                    Section("当前已登记") {   // 483 当前已登记
                        LabeledRow("标签", cur.label.isEmpty ? "(无)" : cur.label)
                        LabeledRow("整窗", cur.from + " → " + cur.to)
                        Text("每把锁只留最近一段 (再次生成会覆盖)。这条登记不产生锁端命令, 家政人员用自带钥匙进出。")
                            .font(.caption2).foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .navigationTitle("家政周期预设")   // 483 家政周期预设
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) {
                Button("完成") {
                    app.tabSelection = 1
                    dismiss()
                }
            } }
        }
    }

    private func submit() {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await app.lock.ensureConnected(mac: mac)
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = "yyyy-MM-dd HH:mm:ss"
                let fromS = f.string(from: from)
                let toS = f.string(from: to)
                MemberHub.saveHouseWin(mac, HouseWin(from: fromS, to: toS, label: label))
                // 只登记到本机 (kf_house_win_)。**不写进凭证台账, 所以 359 三档预警不会盯它** ——
                // 359 只按凭证的 from/to 排本地通知; 家政窗是另一族数据 (上面的"当前已登记"区回显)。
                // 不下发 0 码, 家政自带钥匙。
                app.showToast("家政窗口 " + label + " 已登记 (整段起止, 无循环; 不参与凭证到期预警)")
                app.tabSelection = 1
                dismiss()
            } catch {
                app.showToast("登记失败: " + error.localizedDescription)
            }
        }
    }
}
