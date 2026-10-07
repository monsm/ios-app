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
    @State private var sortKey: Int = 0        // 264: 0 添加时间 / 1 姓名 / 2 最近活跃
    @State private var groupFilter: String = "" // 630 分组过滤
    @State private var showWizard = false
    @State private var showArchived = false
    @State private var showGroups = false
    @State private var showMeeting = false

    private var members: [Member] {
        DB.members()
            .filter { !MemberHub.ext($0.id).archived }
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
                navSection
            }
            .navigationTitle("成员中心")
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("排序 (264)", selection: $sortKey) {
                            Text("添加时间").tag(0)
                            Text("姓名").tag(1)
                            Text("最近活跃 (约)").tag(2)
                        }
                        .pickerStyle(.inline)
                        Button("分组标签 (630)") { showGroups = true }
                        Button("家庭会议摘要 (482)") { showMeeting = true }
                        Button("成员家庭设置 (479/794)") { app.tabSelection = 3 }
                    } label: {
                        Image(systemName: "ellipsis.circle").accessibilityLabel("成员中心菜单")
                    }
                }
            }
            .sheet(isPresented: $showWizard) { MemberWizardView(onDone: { tick += 1 }) }
            .sheet(isPresented: $showArchived) { MemberArchivedView(onRestored: { tick += 1 }) }
            .sheet(isPresented: $showGroups) { MemberGroupSheet(onSaved: { tick += 1 }) }
            .sheet(isPresented: $showMeeting) { MemberMeetingSheet() }
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
                    Text("共 \(n) 位成员 · \(m) 条凭证 (266)")
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

    private func activeSection(_ sort: Int) -> some View {
        let list: [Member]
        switch sort {
        case 1: list = members.sorted { MemberHub.display($0) < MemberHub.display($1) }
        case 2: list = members.sorted { MemberHub.activity($0.id).last > MemberHub.activity($1.id).last }
        default: list = members.sorted { $0.at < $1.at }
        }
        return Section {
            if list.isEmpty {
                EmptyState(systemImage: "person.2.slash",
                           title: "还没有成员",
                           message: "建档向导分三步: 称呼 → 角色 → 初始凭证。",
                           actionTitle: "建档向导 (463)") { showWizard = true }
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
            Text("活跃度与摘录为台账推断 (约): 锁端日志无身份字段, 归属只算可证明的。")
        }
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
                        Text("访客 · 虚拟成员 (793)")
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
                LabeledContent("本周主责 (481)") {
                    Text(MemberHub.display(dm))
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.accentText)
                }
            } else {
                Text("本周主责 (481): 未安排 — 在成员 360 页设置")
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
    private var navSection: some View {
        Section {
            NavigationLink("成员活跃总表 (788/789)") { MemberActiveTable(onChanged: { tick += 1 }) }
            NavigationLink("家庭设置 (479/486/794)") { MemberFamilySettingsView() }
            NavigationLink("家庭会议摘要 (482)") { MemberMeetingSheet() }
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
                        StatusPill(text: "同名待合并 (462)", systemImage: "arrow.triangle.merge", tone: .warn)
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
            Button("归档 (460/795)") {
                var e = MemberHub.ext(member.id)
                e.archived = true
                MemberHub.saveExt(member.id, e)
                tick += 1
            }
            if let d = dup {
                Button("并入「\(d.name)」 (462 重复合并)") {
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
struct MemberAvatar: View {
    let member: Member
    var size: CGFloat = 34

    var body: some View {
        let e = MemberHub.ext(member.id)
        let ch = String(member.name.prefix(1))
        ZStack {
            Circle()
                .fill(DS.Palette.accentText.opacity(0.14))
            Circle()
                .strokeBorder(DS.Palette.accentText.opacity(0.5), lineWidth: 1)
            if !e.emoji.isEmpty {
                Text(e.emoji)
                    .font(.title3)
            } else if member.id == MemberHub.visitorId {
                Image(systemName: "person.badge.clock")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(DS.Palette.accentText)
            } else {
                Text(ch.isEmpty ? "员" : ch)
                    .font(.headline)
                    .foregroundStyle(DS.Palette.accentText)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("头像 " + (member.name.isEmpty ? "成员" : member.name))
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
                archiveSection(m)
                pendingSection
                credsSection(m)
                excerptSection(m)
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
                    Button("重复合并 (462)") { showMerge = true }
                    Button("退出处置向导 (474)") { showExitWizard = true }
                    Button(role: .destructive) { confirmDelete(m) } label: {
                        Label("删除并级联提示 (263)", systemImage: "trash")
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

    // ---------- 档案区 (457/458/916/265/461/464/465/485/1017/653/480) ----------
    private func archiveSection(_ m: Member) -> some View {
        let e = MemberHub.ext(m.id)
        let a = MemberHub.activity(m.id)
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
                LabeledContent("紧急联系 (465)") {
                    Text(e.emergency.isEmpty ? "未填" : e.emergency)
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.textSub)
                }
                // 464 常用锁
                if !e.commonLocks.isEmpty {
                    LabeledContent("常用锁 (464)") {
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
                    LabeledContent("生日 (485)") {
                        Text(bd + " · 提前一天提醒")
                            .font(.subheadline)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                }
                // 480 孩子码关怀文案 (家长视角)
                if !e.careText.isEmpty {
                    LabeledContent("关怀语 (480)") {
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

    // ---------- 467 待确认移交 ----------
    private var pendingSection: some View {
        let pend = MemberHub.pendingTransfers(memberID)
        return Section {
            ForEach(pend) { t in
                let devName = DB.keychain(t.mac).map { LockArchive.displayName($0) } ?? "未知锁"
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text((t.kind == "pwd" ? "密码 #" : "指纹 ") + String(t.key) + " · " + devName)
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.text)
                    Text("来自 " + (DB.member(t.from)?.name ?? "未知") + " · 点接受才改归属 (467)")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: DS.Space.s) {
                        Button("接受") {
                            MemberHub.acceptTransfer(t)
                            onChanged()
                            app.showToast("已接受移交, 归属改到本人")
                        }
                        .buttonStyle(SecondaryActionStyle(fullWidth: false))
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Rectangle())
                        Button("拒绝") {
                            MemberHub.rejectTransfer(t.id)
                            onChanged()
                        }
                        .buttonStyle(DestructiveActionStyle())
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Rectangle())
                        Spacer(minLength: 0)
                    }
                }
            }
            if pend.isEmpty {
                Text("暂无待确认移交。")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
            }
        } header: {
            Text("待确认移交 (467)")
        }
    }

    // ---------- 261/472 名下凭证 (含借用横条) ----------
    private func credsSection(_ m: Member) -> some View {
        var pwdCount = 0, fpCount = 0
        var borrowLines: [String] = []
        for kc in DB.keychains() where !kc.mac.isEmpty {
            for p in DB.listPwds(kc.mac) where p.owner == m.id {
                pwdCount += 1
                if let b = MemberHub.borrows(kc.mac)["p" + String(p.alias)] {
                    borrowLines.append(CredentialOrg.displayPwd(p) + " · 借给 " + b.by + " (还 " + b.due + ")")
                }
            }
            for f in DB.listFps(kc.mac) where f.owner == m.id {
                fpCount += 1
                if let b = MemberHub.borrows(kc.mac)["f" + String(f.batch)] {
                    borrowLines.append("「" + f.name + "」 · 借给 " + b.by + " (还 " + b.due + ")")
                }
            }
        }
        return Section {
            Text("密码 \(pwdCount) 条 · 指纹 \(fpCount) 条 · 未归属转未分配不在此列 (261)")
                .font(.subheadline)
                .foregroundStyle(DS.Palette.text)
            ForEach(borrowLines, id: \.self) { line in
                HStack(spacing: DS.Space.s) {
                    StatusPill(text: "借用中 (472)", systemImage: "person.2.badge.gearshape", tone: .warn)
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
                Label("借用登记 (472)", systemImage: "person.2.badge.plus")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundStyle(DS.Palette.accentText)
        } header: {
            Text("名下凭证 (261)")
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
            Text("授权来源 (473)")
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
                Text("暂无「谁创建给谁」的凭证关系, 移交后这里会画出创建人→使用人 (476)。")
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
            }
        } header: {
            Text("归属图谱 (476)")
        }
    }

    // ---------- 家庭场景 (481/468/469/480/484/475) ----------
    private func sceneSection(_ m: Member) -> some View {
        return Section {
            Toggle("由我代管 (468: 期间操作记 管理员代操作)", isOn: Binding(
                get: { MemberHub.ext(m.id).proxy },
                set: { v in
                    var ext = MemberHub.ext(m.id); ext.proxy = v
                    MemberHub.saveExt(m.id, ext)
                    onChanged()
                }))
            .fixedSize(horizontal: false, vertical: true)
            if MemberHub.dutyThisWeek == m.id {
                StatusPill(text: "本周主责", systemImage: "calendar.badge.clock", tone: .accent)
            }
            Toggle("设为本周主责 (481)", isOn: Binding(
                get: { MemberHub.dutyThisWeek == m.id },
                set: { v in
                    MemberHub.setDuty(v ? m.id : nil)
                    onChanged()
                }))
            .fixedSize(horizontal: false, vertical: true)
            if MemberHub.proxyNames.contains(m.id) {
                Text("代管中: 该成员凭证操作在日志统一标注 管理员代操作 (468)。")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("家庭场景")
        }
    }

    // ---------- 470 权限矩阵 + 469 紧急管理员 ----------
    private func permSection(_ m: Member) -> some View {
        let role = MemberHub.ext(m.id).role
        let matrix = permRows(role: role)
        return Section {
            ForEach(matrix, id: \.0) { k, v in
                LabeledContent(k) {
                    StatusPill(text: v ? "允许" : "禁用",
                               systemImage: v ? "checkmark.circle" : "xmark.circle",
                               tone: v ? .ok : .neutral)
                }
            }
            Text("矩阵只约束本机 UI (470), 锁端无角色字段。")
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("紧急管理员 (469: 救援码说明与其绑定, 防单点失能)", isOn: Binding(
                get: { MemberHub.ext(m.id).emergencyAdmin },
                set: { v in
                    var ext = MemberHub.ext(m.id); ext.emergencyAdmin = v
                    MemberHub.saveExt(m.id, ext)
                    onChanged()
                }))
            .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("权限与应急 (470/469)")
        }
    }
    private func permRows(role: String) -> [(String, Bool)] {
        switch role {
        case "main": return [("看记录", true), ("管凭证", true), ("导出", true), ("备份", true), ("成员管理", true)]
        case "guest": return [("看记录", false), ("管凭证", false), ("导出", false), ("备份", false), ("成员管理", false)]
        default: return [("看记录", true), ("管凭证", true), ("导出", false), ("备份", false), ("成员管理", false)]
        }
    }

    // ---------- 补全档案 (265/461/458/457-916/464/465/475/480/484/630) ----------
    private func editProfile(_ m: Member) {
        let e = MemberHub.ext(m.id)
        let alert = UIAlertController(title: "补全档案", message: nil, preferredStyle: .alert)
        func field(_ ph: String, _ init: String, _ kb: UIKeyboardType = .default) -> UITextField {
            alert.addTextField { $0.placeholder = ph; $0.text = init; $0.keyboardType = kb; $0.clearButtonMode = .whileEditing }
            return alert.textFields!.last!
        }
        let fRelation = field("与你的关系", m.relation)
        let fRemark = field("备注名 (461)", e.remark)
        let fRole = field("角色 main/member/guest (458)", e.role)
        let fEmoji = field("emoji 代号 (916, 留空用首字)", e.emoji)
        let fEmergency = field("紧急联系 姓名+电话 (465)", e.emergency)
        let fNote = field("家庭便签 (475, 如 周六换锁芯)", e.note)
        let fCare = field("孩子码关怀文案 (480)", e.careText)
        let fWelcome = field("访客欢迎语 (484, 归属时间推断约)", e.welcome)
        let fGroup = field("分组标签 家人/访客/服务人员 (630)", e.groupTag)
        let fCommon = field("常用锁 (mac 或名称, 逗号分隔; 多锁时排前 464)",
                            e.commonLocks.joined(separator: ", "))
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in
            var next = e
            next.role = fRole.text ?? "member"
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
    private func confirmDelete(_ m: Member) {
        var preview: [String] = []
        for kc in DB.keychains() {
            for p in DB.listPwds(kc.mac).filter({ $0.owner == m.id }) {
                preview.append("密码 #" + String(p.alias) + " · " + LockArchive.displayName(kc))
            }
            for f in DB.listFps(kc.mac).filter({ $0.owner == m.id }) {
                preview.append("指纹「" + f.name + "」 · " + LockArchive.displayName(kc))
            }
        }
        let msg = preview.isEmpty
            ? "确定要删除「" + m.name + "」吗? TA 名下没有台账凭证, 仅移除成员档案。"
            : "删除「" + m.name + "」后, 名下 " + String(preview.count) + " 条凭证将转为未分配并入回收站 (可整组还原 501):\n"
              + preview.prefix(5).joined(separator: "\n") + (preview.count > 5 ? "\n…" : "")
        confirmDestructive("删除成员", msg, confirmTitle: "删除并入回收站") {
            for kc in DB.keychains() { CredentialOrg.cascadeBinMember(kc.mac, m.id) }
            DB.removeMember(m.id)
            onChanged()
            app.showToast("已删除并入回收站")
        }
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

    var body: some View {
        NavigationStack {
            Form {
                Section("步骤 \(step + 1)/3 · " + steps[step]) {
                    switch step {
                    case 0:
                        TextField("称呼 (汉字/英文/数字, 上限 20)", text: $name)
                            .autocorrectionDisabled()
                        Picker("emoji 代号 (916, 纯文字头像)", selection: $emoji) {
                            ForEach(["", "🐻", "🐱", "🐸", "🐙", "🦊", "🐧", "🐯"], id: \.self) { e in
                                Text(e.isEmpty ? "默认首字" : e).tag(e)
                            }
                        }
                        .pickerStyle(.menu)
                    case 1:
                        Picker("角色 (458 三档)", selection: $role) {
                            Text("主理人 (备份/成员管理)").tag("main")
                            Text("成员 (看记录/管凭证)").tag("member")
                            Text("访客 (本机只读)").tag("guest")
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
            .navigationTitle("建档向导 (463)")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("取消") { dismiss() } } }
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
                }
            }
            .navigationTitle("重复合并 (462)")
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
                        Text("该成员名下没有台账凭证, 直接归档即可 (460/795 历史保留)。")
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
                        app.showToast("已归档, 历史记录保留 (460/795)")
                        dismiss()
                    } label: {
                        Text("归档并执行")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: DS.Hit.min)
                    }
                    .buttonStyle(DestructiveActionStyle())
                }
            }
            .navigationTitle("退出处置向导 (474)")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("取消") { dismiss() } } }
        }
    }

    private func decide(_ it: Item, _ d: String) {
        decisions[it.id] = d
        switch d {
        case "move":
            let target = DB.members().first { $0.id != memberID && !MemberHub.ext($0.id).archived }
            if let t = target {
                if it.kind == "pwd" { DB.setPwdOwner(it.mac, it.key, t.id) }
                else { DB.setFpOwner(it.mac, it.key, t.id) }
                app.showToast("已移交至「" + MemberHub.display(t) + "」")
            } else {
                decisions[it.id] = "keep"
                app.showToast("没有可移交的成员, 已保留")
            }
        case "delete":
            if it.kind == "pwd" {
                guard let p = DB.listPwds(it.mac).first(where: { $0.alias == it.key }) else { return }
                DB.delPwd(it.mac, it.key)
                CredentialOrg.addToBin(it.mac, pwd: p, source: .manual)
                CredentialOrg.enqueue(it.mac, kind: "del_pwd", title: "删除密码 #" + String(it.key), pwd: p)
            } else {
                guard let f = DB.listFps(it.mac).first(where: { $0.batch == it.key }) else { return }
                DB.delFp(it.mac, it.key)
                CredentialOrg.addToBin(it.mac, fp: f, source: .manual)
                CredentialOrg.enqueue(it.mac, kind: "del_fp", title: "删除指纹批次 " + String(it.key), fp: f)
            }
            app.showToast("已停用并入回收站")
        default:
            break
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
        _mac = State(initialValue: DB.keychains().first?.mac ?? "")
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
                        let b = borrowMap[k]!
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
                    if borrowMap.isEmpty {
                        Text("没有进行中的借用。")
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                }
            }
            .navigationTitle("借用登记 (472)")
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
                            Text("归档中 · 记录仍可筛选, 凭证 Tab 不再展示")
                                .font(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                        }
                    }
                }
                if archived.isEmpty {
                    Text("归档列表为空 — 成员归档后历史不蒸发 (795)。")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                }
            }
            .navigationTitle("归档成员 (460/795)")
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
                Section("成员分组标签 (630 · 与记录页成员过滤联动)") {
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
            .navigationTitle("分组标签 (630)")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("取消") { dismiss() } } }
        }
    }
}

// ================= 479/486/794 家庭设置 (长辈模式 · 隐私浏览) =================
struct MemberFamilySettingsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var elder = MemberHub.elderMode
    @State private var privacy = MemberHub.privacyActive
    @State private var privacyLeft = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("长辈模式 (479/486)") {
                    Toggle("长辈模式 (大字高对比 · 凭证页只留密码/指纹两组)", isOn: $elder)
                        .fixedSize(horizontal: false, vertical: true)
                    if elder {
                        Text("凭证 Tab 隐藏批量与导出入口, 临时码完成页默认进口述卡 (486)。")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Section("隐私浏览 (794)") {
                    Toggle("隐私浏览 (限时 10 分钟: 成员统计只显示本人数据 + 水印)", isOn: $privacy)
                        .fixedSize(horizontal: false, vertical: true)
                    if privacy {
                        Text(privacyLeft > 0
                             ? "剩余 \(privacyLeft) 秒后自动关闭"
                             : "开启后 10 分钟自动关闭, 期间成员统计只显示本人数据")
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
        _mac = State(initialValue: DB.keychains().first?.mac ?? "")
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
                    Text("未归属记录认领 (791)")
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
            .navigationTitle("认领未归属 (791)")
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
                        Text("还没有成员 — 在 成员中心 走建档向导。")
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                }
            }
            .navigationTitle("成员活跃总表 (788)")
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
        var cum: Int
        var id: Date { day }
    }
    struct RotationPoint {
        var label: String
        var detail: String
    }

    private var stack: [StackPt] {
        var per: [String: Int] = [:]
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
                let unix = Double(ZKProtocol.protoSecondsToMs(Int64(logs[i].lockTime))) / 1000
                guard unix >= cutoff.timeIntervalSince1970 else { continue }
                per[who, default: 0] += 1
            }
        }
        var cum = 0
        return per.map { _, n in cum += n; return StackPt(day: now, cum: cum) }
    }

    private var rotations: [RotationPoint] {
        var out: [RotationPoint] = []
        let cal = Calendar.current
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
                let names = Set(byDay[dk]!).map { DB.member($0)?.name ?? "成员" }
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
                    AreaMark(x: .value("累计", p.cum),
                              y: .value("成员分层", 1))
                        .foregroundStyle(DS.Palette.accent.opacity(0.4))
                        .interpolationMethod(.monotone)
                }
                .chartXAxisLabel("成员分层累计 (30 天, 约)", alignment: .leading)
                .frame(height: 140)
                .padding(.horizontal, DS.Space.gutter)
            }
            if !rotations.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    SectionTitle(text: "成员轮换 (792)", count: rotations.count)
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
                        .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
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
            .navigationTitle("家庭会议摘要 (482)")
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
            Text("便签存在本机, 绑在成员身上, 设备页 Hero 卡下方浮动显示 (475)。")
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
        _mac = State(initialValue: DB.keychains().first?.mac ?? "")
        _from = State(initialValue: Date())
        _to = State(initialValue: Date().addingTimeInterval(8 * 3600))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("家政周期预设 (483 · 降级为整段起止窗)") {
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
            }
            .navigationTitle("家政周期预设 (483)")
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
                // 本地登记整窗 (凭证 Tab 359 三档预警会自动盯上); 不下发 0 码, 家政自带钥匙
                app.showToast("家政窗口 " + label + " 已登记 (整段起止, 无循环)")
                app.tabSelection = 1
                dismiss()
            } catch {
                app.showToast("登记失败: " + error.localizedDescription)
            }
        }
    }
}
