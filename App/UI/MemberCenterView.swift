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
    @Environment(\.dismiss) var dismiss
    @State var tick = 0
    /// 2026-10-29 性能：全员活跃度一次算完，行内不再各自重扫全锁日志。
    @State var activity = MemberHub.ActivityBundle()
    @State var sortKey: Int = 0        // 264/466: 0 添加时间 / 1 姓名 / 2 最近开门时间 / 3 近 30 天开门次数
    @State var groupFilter: String = "" // 630 分组过滤
    @State var showWizard = false

    /// 2026-10-28：建档向导的统一入口（带 15 人上限检查）。
    /// APK `presentMemberAddPage` 判 `16 != memberList.length`，超出时明确拒绝
    /// 「已添加15个成员，无法再添加」（数组含一个"自己"占位，实际上限 15）。
    func openWizard() {
        if DB.members().count >= 15 {
            app.showToast("已添加 15 个成员，无法再添加（锁端槽位上限）")
            return
        }
        showWizard = true
    }
    @State var showArchived = false
    @State var showGroups = false
    // 415 名册导出: ShareLink 要在渲染期就有 URL, 所以点菜单时先按需生成再开面板 (不在 body 里写盘)
    @State var rosterURL: URL?
    @State var showRoster = false

    var members: [Member] {
        // archivedIDs() 此前零调用: 它一次解出整张 ext 表; 旧写法每个成员调两次 ext() = 每成员整体重解一遍字典。
        // groupTag 那步仍按成员取 ext (要的是值不是集合), 至少砍掉一半重复解码。
        // 2026-10-29 性能：archivedIDs() 与逐成员的 ext() 各自整表解码一遍；一次取表共用。
        let extTable = MemberHub.allExt()
        let archived = MemberHub.archivedIDs(extTable)
        return DB.members()
            .filter { !archived.contains($0.id) }
            .filter { m in groupFilter.isEmpty || MemberHub.ext(m.id, in: extTable).groupTag == groupFilter }
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
                        Button { showGroups = true }   label: {   // 630 分组标签
                            Label("分组标签", systemImage: "tag")
                        }
                        Button {   // 415 导出成员名册
                            rosterURL = ExportKit.writeRoster()
                            showRoster = true
                        } label: {
                            Label("导出成员名册", systemImage: "square.and.arrow.up")
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
            // 2026-10-29 性能：全员活跃度只在进页与写库后（tick 变化）算一次，不再每次 body 重算。
            .task { activity = MemberHub.activityBundle(members.map { $0.id }) }
            .onChange(of: tick) { _, _ in activity = MemberHub.activityBundle(members.map { $0.id }) }
        }
    }

    // 2026-10-27 四轮精简：概览头已删。

    // 630 分组过滤 chips (家人/访客/服务人员 — 与包10 图例同组字段)
    @ViewBuilder
    var groupChipSection: some View {
        // 2026-10-29 性能：逐成员 ext() = 逐成员整表解码；一次取表。
        let extTable = MemberHub.allExt()
        let tags = Array(Set(DB.members().map { MemberHub.ext($0.id, in: extTable).groupTag })).filter { !$0.isEmpty }.sorted()
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
    func groupChip(_ tag: String, _ label: String) -> some View {
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
    func activeSection(_ sort: Int) -> some View {
        let acts: [String: MemberHub.Activity] = (sort == 2 || sort == 3) ? activity.table : [:]
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
                           actionTitle: "建档向导") { openWizard() }   // 463 建档向导
            }
            ForEach(list) { m in
                NavigationLink { MemberDetail360View(memberID: m.id, onChanged: { tick += 1 }) } label: {
                    MemberRow(member: m, act: activity.table[m.id])
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

    // 793 访客虚拟分组: 本地展示层虚拟成员, 不占锁端槽位
    var visitorSection: some View {
        let opens = activity.visitorOpens
        let temps = activity.visitorTemps
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

    @ViewBuilder
    var archivedSection: some View {
        let extTable = MemberHub.allExt()
        let arch = DB.members().filter { MemberHub.ext($0.id, in: extTable).archived }
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
    var sceneSection: some View {
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

    var navSection: some View {
        // 2026-10-27 删除：`Section { } header: { Text("聚合视图") }` —— body 是**空的**。
        // 屏幕上就是「聚合视图」标题下面一片空白，用户会以为加载失败。
        // 聚合视图本身已在早前精简里移除，这个空壳是残留。
    }
}

// ---------- 成员行 (457 首字头像 + 458 角色 + 462 同名提示 + 262/466 活跃度) ----------
struct MemberRow: View {
    let member: Member
    /// 2026-10-29 性能：由父视图一次算好传入，行内不再调 MemberHub.activity（那会重扫全锁日志）。
    var act: MemberHub.Activity?
    @State var tick = 0


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
            Button {   // 460/795 归档
                var e = MemberHub.ext(member.id)
                e.archived = true
                MemberHub.saveExt(member.id, e)
                tick += 1
            } label: {
                Label("归档", systemImage: "archivebox")
            }
        }
    }


    var rolePill: some View {
        let r = MemberHub.ext(member.id).role
        return StatusPill(text: MemberHub.roleLabel(r),
                          systemImage: r == "main" ? "crown.fill" : (r == "guest" ? "person.badge.clock" : "person.fill"),
                          tone: r == "main" ? .warn : .neutral)
    }
    var subLine: some View {
        let e = MemberHub.ext(member.id)
        let a = act ?? MemberHub.Activity()
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
    var staleTag: some View {
        let stale = (act ?? MemberHub.Activity()).stale
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
    var baseColor: Color {
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
    func avatarCircle(base: Color) -> some View {
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
