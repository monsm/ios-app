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

    var body: some View { vkBody.destined(.memberCenter) }
    var vkBody: some View {
        NavigationStack {
            List {
                groupChipSection
                activeSection(sortKey)
                visitorSection
                archivedSection
                sceneSection
                navSection
            }
            .navigationTitle("成员中心")
            .variantList()
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
            // 817c 记录页"添加成员"示例位跳过来时直接弹向导; 标记一次性消费。
            // 下一轮 runloop 再置 sheet: onAppear 同步段里开 sheet 在首帧可能因视图未入窗被吞掉。
            .onAppear {
                if app.pendingMemberAdd {
                    app.pendingMemberAdd = false
                    DispatchQueue.main.async { showWizard = true }
                }
            }
            // 415 名册分享面板: 用 ShareLink(item: URL) 而不是 UIActivityViewController ——
            // 后者要么设 popover 锚点 (iPad), 要么就是本仓别处（如原 SecurityCenterView）那种裸用法;
            // 本 App 现在是 iPhone-only (project.yml TARGETED_DEVICE_FAMILY=1), 今天不会崩, 但改设备族时那就是个雷,
            // 新代码一律走免锚点的 ShareLink。
            .sheet(isPresented: $showRoster) {
                NavigationStack {
                    List {
                        Section("成员名册") {   // 415 成员名册
                            Text("共 \(DB.members().count) 位成员 · 文件 "
                                 + (rosterURL?.lastPathComponent ?? "生成失败"))
                                .vkFont(.subheadline)
                                .foregroundStyle(DS.Palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("名册里只有人与称呼: 不含锁 MAC、凭证编号、口令, 也不含常用锁清单。\n"
                                 + "要搬整套数据请走备份 —— 名册不承担那个用途, 也正因为它少, 才适合发给家人线下核对。")
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                            if let u = rosterURL {
                                ShareLink(item: u) {
                                    Label("分享这个 .vcf 文件", systemImage: "square.and.arrow.up")
                                        .vkFont(.subheadline, weight: .semibold)
                                        .foregroundStyle(DS.Palette.accentText)
                                        .frame(minHeight: DS.Hit.min)
                                }
                            } else {
                                Text("本机还没有成员档案，名册是空的")   // 415 本机还没有成员档案
                                    .vkFont(.caption)
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

    // 2026-10-27 四轮精简：概览头已删。

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
                .vkFont(.caption, weight: .medium)
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
                app.requestRoute(.records)
                dismiss()
            } label: {
                HStack(spacing: DS.Space.s) {
                    MemberAvatar(member: Member(id: MemberHub.visitorId, name: "访客", at: 0))
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text("访客 · 虚拟成员")   // 793 访客
                            .vkFont(.subheadline)
                            .foregroundStyle(DS.Palette.text)
                        Text("临时码未归属记录约 \(opens) 条 · 名下临时码 \(temps) 条")
                            .vkFont(.caption)
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
                    Label("归档成员 (\(arch.count)) · 保留历史", systemImage: "archivebox")
                        .vkFont(.subheadline)
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
                        .vkFont(.subheadline)
                        .foregroundStyle(DS.Palette.accentText)
                }
            } else {
                Text("本周主责: 未安排 — 在成员的详情页里设置")   // 481 本周主责
                    .vkFont(.subheadline)
                    .foregroundStyle(DS.Palette.textSub)
            }
            ForEach(members.prefix(4)) { m in
                if !MemberHub.ext(m.id).note.isEmpty {
                    LabeledContent("便签 · " + MemberHub.display(m)) {
                        Text(MemberHub.ext(m.id).note)
                            .vkFont(.subheadline)
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

    private var navSection: some View {
        // 2026-10-27 删除：`Section { } header: { Text("聚合视图") }` —— body 是**空的**。
        // 屏幕上就是「聚合视图」标题下面一片空白，用户会以为加载失败。
        // 聚合视图本身已在早前精简里移除，这个空壳是残留。
    }
}

// ---------- 成员行 (457 首字头像 + 458 角色 + 462 同名提示 + 262/466 活跃度) ----------
struct MemberRow: View {
    let member: Member
    @State private var tick = 0


    var body: some View {
        HStack(spacing: DS.Space.s) {
            MemberAvatar(member: member)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                HStack(spacing: DS.Space.xs) {
                    Text(MemberHub.doubleLine(member))
                        .vkFont(.subheadline, weight: .medium)
                        .foregroundStyle(DS.Palette.text)
                    rolePill
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
        }
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
            .vkFont(.caption)
            .foregroundStyle(DS.Palette.textSub)
            .fixedSize(horizontal: false, vertical: true)
            // 262 久未用的行整体压暗一档: 只靠右侧"久未用"小字, 扫描名单时视线抓不到
            .opacity(a.stale ? 0.55 : 1)
    }
    // 262/466 久未用置灰 (台账推断口径)
    private var staleTag: some View {
        let stale = MemberHub.activity(member.id).stale
        return Text(stale ? "久未用" : "活跃 (约)")
            .vkFont(.caption2)
            .foregroundStyle(stale ? DS.Palette.textSub : DS.Palette.ok)
            .lineLimit(1)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// 457 首字符号头像 + 916 emoji 代号: 零图片资源 (本地绘制)
// 影响面 (grep "MemberAvatar(" 全仓 12 处构造点): 本文件 8 处 + DeviceHomeView 4 处 (hero 那三枚叠放
// 「授予徽章」那份菜单只遍历 DB.members() 的真实成员 (Sheets.swift 的 reload 就是这条数据源),
// 这两个虚拟 id 进不了表, 所以它们的头像观感维持原样。
struct MemberAvatar: View {
    let member: Member
    var size: CGFloat = 34
    var tint: Color? = nil   // 480: 传成员建档色时整个头像随该色; 不传维持原 accentText 口径

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

    var body: some View {
        avatarCircle(base: baseColor)
    }

    /// 457/916 头像本体 (994 抽出成函数只为给上面两条分支复用同一条链, 渲染内容与抽出前一致)
    private func avatarCircle(base: Color) -> some View {
        let e = MemberHub.ext(member.id)
        let ch = String(member.name.prefix(1))
        return ZStack {
            Circle()
                .fill(base.opacity(0.14))
            Circle()
                .strokeBorder(base.opacity(0.5), lineWidth: 1)
            if !e.emoji.isEmpty {
                Text(e.emoji)
                    .vkFont(.title3)
            } else if member.id == MemberHub.visitorId {
                Image(systemName: "person.badge.clock")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(base)
            } else {
                Text(ch.isEmpty ? "员" : ch)
                    .vkFont(.headline)
                    .foregroundStyle(base)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("头像 " + (member.name.isEmpty ? "成员" : member.name)
                            )
    }
}

// ================= 成员 360 详情 (459 上档案 / 下凭证+摘录 ⚠约 · 473 来源 · 476 图谱 · 464/465 · 470 矩阵 · 469) =================
struct MemberDetail360View: View {
    let memberID: String
    var onChanged: () -> Void = {}
    @EnvironmentObject var app: AppState
    @State private var tick = 0
    @State private var showMerge = false

    private var member: Member? { DB.member(memberID) }

    var body: some View { vkBody.destined(.memberDetail360) }
    /// ⚠ `@ViewBuilder` 这一句不能省：顶层是 `if let / else` 两个**不同类型**的分支
    /// （`List{…}` vs `EmptyState`）。它原先是 `body`，隐式带着协议给的 @ViewBuilder；
    /// 改名成 `vkBody` 之后那份隐式就没了 —— CI run 115 报的 "branches have mismatching types"
    /// 说的就是这件事。（其余 76 处 `vkBody` 是单表达式或两支同为 `AnyView` 的 if-表达式，不加也能编。）
    @ViewBuilder var vkBody: some View {
        if let m = member {
            List {
                if let line = MemberHub.weekSentence(m.id) {
                    Section { Label(line, systemImage: "calendar.badge.clock")
                        .vkFont(.footnote).foregroundStyle(DS.Palette.text)
                        .fixedSize(horizontal: false, vertical: true) }
                }
                // 467「待确认移交」区已撤 (2026-10-09 拍板): 移交实际由凭证页 `CredentialOrg.batchTransfer`
                // 直接改本机台账, 队列没有发起方 → 这个区永远只显示"暂无"。留着就是假开关那一族。
                credsSection(m)
                permSection(m)
            }
            .navigationTitle(MemberHub.display(m))
            .variantList()
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("补全档案 (关系/电话/生日/代号/分组/便签)") { editProfile(m); onChanged() }
                    Button("重复合并") { showMerge = true }   // 462 重复合并
                    Button(role: .destructive) { confirmDelete(m) } label: {
                        Label("删除并级联提示", systemImage: "trash")   // 263 删除并级联提示
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").accessibilityLabel("成员操作菜单")
                }
            } }
            .sheet(isPresented: $showMerge) { MergeMembersView(primary: m) { tick += 1; onChanged() } }
            .id(tick)
        } else {
            EmptyState(systemImage: "person.slash",
                       title: "成员不存在",
                       message: "档案可能已被删除或合并。")
                .frame(maxWidth: .infinity)
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
                .vkFont(.subheadline)
                .foregroundStyle(DS.Palette.text)
            // 261 清单本体: 只有计数没有名目时, 用户没法核对"名下到底有哪几把"
            ForEach(Array(credLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            ForEach(borrowLines, id: \.self) { line in
                HStack(spacing: DS.Space.s) {
                    StatusPill(text: "借用中", systemImage: "person.2.badge.gearshape", tone: .warn)   // 472 借用中
                    Text(line)
                        .vkFont(.subheadline)
                        .foregroundStyle(DS.Palette.textSub)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
            }
                    // 2026-10-26 精简：借用登记入口已删。
            .buttonStyle(PlainButtonStyle())
            .foregroundStyle(DS.Palette.accentText)
        } header: {
            Text("名下凭证")   // 261 名下凭证
        }
    }



    private func sourceCell(_ label: String, _ n: Int) -> some View {
        VStack(spacing: DS.Space.xs) {
            Text(String(n))
                .vkFont(.title3, weight: .semibold)
                .monospacedDigit()
                .foregroundStyle(DS.Palette.accentText)
            Text(label)
                .vkFont(.caption2)
                .foregroundStyle(DS.Palette.textSub)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.s)
        .variantPlate(DS.Palette.surfaceAlt, .control)
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
            Text("矩阵管的是本机 UI: 「管凭证」这一行决定这一档给不给代管开关 (上方「家庭场景」那一节), "   // 470 矩阵管的是本机
                 + "「成员管理」这一行决定能不能被指成紧急管理员 (就在下面)。不给的那一枚会就地写明为什么少。"
                 + "边界: 锁端没有角色字段, 备份包也不带角色 —— 这三档不改任何发往门锁的字节; "
                 + "角色与代管会被写进成员名册那张 vcf 的备注行。")   // 415 角色与代管会被写进成
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            // 469 的真读点之一: 这一页把"谁被指成了紧急管理员"写在明面上。
            // 原先这个位只有 Toggle 的 set、全仓零读取方, 界面却承诺"救援码说明与其绑定" —— 那句已按实情收窄。
            LabeledContent("紧急管理员") {   // 469 紧急管理员
                Text(admins.isEmpty ? "未指定" : admins.map { MemberHub.display($0) }.joined(separator: "、"))
                    .vkFont(.subheadline)
                    .foregroundStyle(admins.isEmpty ? DS.Palette.textSub : DS.Palette.accentText)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if MemberHub.permAllows(role, "成员管理") {
                VariantToggle("把 Ta 设为紧急管理员 (本机点名档)", isOn: Binding(
                    get: { MemberHub.ext(m.id).emergencyAdmin },
                    set: { v in
                        var ext = MemberHub.ext(m.id); ext.emergencyAdmin = v
                        MemberHub.saveExt(m.id, ext)
                        onChanged()
                    }))
                .fixedSize(horizontal: false, vertical: true)
                Text("这一档的作用是把人点出来: 上面那一行会写上 Ta 的名字, 免得只剩一个人管钥匙。"
                     + "救援码本身仍在 设置-安全 里生成, 那段说明目前不读这份名单 —— 两者今天没有绑定关系。")
                    .vkFont(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("角色是「" + MemberHub.roleLabel(role) + "」: 矩阵里「成员管理」这一行是禁用, 所以这一档不给指成紧急管理员 (收的就是本机 UI)。要给它, 先把角色改成主理人。")
                    .vkFont(.caption)
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
                .vkFont(.caption, weight: .semibold)
                .foregroundStyle(r == current ? DS.Palette.accentText : DS.Palette.text)
            Text("能：" + canText + "　不能：" + cantText)
                .vkFont(.caption2)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            Text(scene)
                .vkFont(.caption2)
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
            return alert.textFields?.last ?? UITextField()
        }
        let fRelation = field("与你的关系", m.relation)
        let fRemark = field("备注名", e.remark)   // 461 备注名
        let fEmoji = field("emoji 代号", e.emoji)   // 916 代号
        let fEmergency = field("紧急联系 姓名+电话", e.emergency)   // 465 紧急联系
        let fCare = field("孩子码关怀文案", e.careText)   // 480 孩子码关怀文案
        let fNote = field("家庭便签 (如 周六换锁芯)", e.note)
        let fWelcome = field("访客欢迎语", e.welcome)   // 484 访客欢迎语
        let fGroup = field("分组标签 家人/访客/服务人员", e.groupTag)   // 630 分组标签
        let fCommon = field("常用锁 (mac 或名称, 逗号分隔; 多锁时排前)",
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
            next.commonLocks = (fCommon.text ?? "")
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
            : "删除「" + m.name + "」后, 名下 " + String(preview.count) + " 条凭证将转为未分配并入回收站 (可整组还原):\n"
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
            // 2026-10-27 (D-57)：不再收集"排上队列的条数" —— 根本没有队列（见 cascadeBinMember 注释）
            for kc in DB.keychains() {
                CredentialOrg.cascadeBinMember(kc.mac, m.id, revokeLocks: true)
            }
            DB.removeMember(m.id)
            onChanged()
            // 2026-10-27 审核修复 (AUDIT-D D-57)：**不再承诺"已排 N 条锁端删除"**。
            // 那句话是假的 —— `cascadeBinMember` 原先只 `queued += 1`，根本没有队列，
            // 连接门锁后什么都不会发生。安全承诺级别的假话比不承诺更危险。
            // 现在如实说：本机已处理，锁端凭证仍在，需要时手动删。
            app.showToast("已删除并入回收站 · ⚠ 锁端凭证仍在，需要时请到设备页手动删除")
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
        default: return !makePwd || pwdOK()
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

    var body: some View { vkBody.destined(.memberWizard) }
    var vkBody: some View {
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
                        TextField("备注名 (记录条目显示 称呼（备注）)", text: $remark)
                            .autocorrectionDisabled()
                    default:
                        VariantToggle("顺路建 10 分钟临时码 (末步)", isOn: $makePwd)
                            .fixedSize(horizontal: false, vertical: true)
                        if makePwd {
                            TextField("6~8 位数字 (下发到当前锁)", text: $pwd)
                                .keyboardType(.numberPad)
                            Text("归属自动记为 TA; 不建也行, 稍后在凭证页添加。")
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        // 463: 建档流程内直达指纹录入 (与临时码同格), 录完回凭证页可指归属
                        NavigationLink("录指纹后到凭证页指归属") { StartAddFpView(embedded: true) }   // 463 录指纹后到凭证页指归
                            .vkFont(.footnote)
                    }
                }
                if step < 2 {
                    Section {
                        Button {
                            guard canNext else { return }
                            if step == 0, newID == nil {
                                newID = createMember()
                                // 2026-10-14: 建档失败 (重名/空名) 不能推进 —— 否则用户走到末步才被踢出, 输入全废。
                                guard newID != nil else { return }
                            }
                            step += 1
                            DS.Haptics.tick.impactOccurred()
                        } label: {
                            Text("下一步")
                                .vkFont(.subheadline, weight: .medium)
                                .foregroundStyle(DS.Palette.accentText)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .frame(minHeight: DS.Hit.min)
                        }
                        .buttonStyle(PlainButtonStyle())
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
            .variantList()
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("取消") { dismiss() } } }
            .axBottomAnchor()   // 870
        }
    }

    private func createMember() -> String? {
        let n = name.trimmingCharacters(in: .whitespaces)
        // 2026-10-14: 与重命名 (rename) 同口径 —— 否则能建出"之后改不动"的名字 (重命名强制字母数字)。
        guard !n.isEmpty, n.count <= 20, n.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            app.showToast("姓名需为汉字/英文/数字, 上限 20 字")
            return nil
        }
        guard let m = DB.addMember(n) else {
            app.showToast("姓名为空或已存在 (可用合并把两个名字并成一个)")
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
            // 2026-10-14: 勾了"建临时码"但码非法时, 旧实现只报"已添加", 用户以为码建好了。
            app.showToast(makePwd ? "已添加「\(name)」— 临时码未建 (需 6~8 位纯数字)"
                                  : "已添加「\(name)」")
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

    var body: some View { vkBody.destined(.mergeMembers) }
    var vkBody: some View {
        NavigationStack {
            Form {
                Section("主档 (保留)") {
                    HStack(spacing: DS.Space.s) {
                        MemberAvatar(member: primary, size: 28)
                        Text(MemberHub.display(primary))
                            .vkFont(.subheadline)
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
                            .vkFont(.footnote)
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
                }
            }
            .navigationTitle("重复合并")   // 462 重复合并
            .navigationBarTitleDisplayMode(.inline)
            .variantList()
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



// ================= 460/795 归档成员列表 (恢复入口) =================
struct MemberArchivedView: View {
    @Environment(\.dismiss) private var dismiss
    var onRestored: () -> Void = {}
    @State private var tick = 0

    private var archived: [Member] {
        DB.members().filter { MemberHub.ext($0.id).archived }
    }

    var body: some View { vkBody.destined(.memberArchived) }
    var vkBody: some View {
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
                                .vkFont(.subheadline)
                                .foregroundStyle(DS.Palette.text)
                            Text("归档中 · 只从成员列表与成员统计里收起; 记录页仍能筛到 TA, "
                                 + "凭证页也仍列 TA 名下凭证 —— 归档不许挡撤权入口。")   // 460/795 凭证页也仍列
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if archived.isEmpty {
                    Text("归档列表为空 — 成员归档后历史不蒸发。")   // 795 归档列表为空
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                }
            }
            .navigationTitle("归档成员")   // 460/795 归档成员
            .navigationBarTitleDisplayMode(.inline)
            .variantList()
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
                }
            }
            .navigationTitle("分组标签")   // 630 分组标签
            .navigationBarTitleDisplayMode(.inline)
            .variantList()
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("取消") { dismiss() } } }
        }
    }
}







