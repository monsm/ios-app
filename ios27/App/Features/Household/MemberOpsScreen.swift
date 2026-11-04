// MemberOpsScreen.swift —— 成员流转与家庭场景（移交 / 借用 / 家政窗 / 轮值 / 关怀 / 访客 / 长辈 / 级联删除）。
//
// 来源：原 App/Core/MemberHub.swift 的 467 移交、472 借用、483 家政窗、481 轮值、480 关怀便签、
//   484 欢迎语、793 访客虚拟分组、479 长辈模式、501 删除成员级联凭证入回收站。
// 这屏干什么：把成员中心里「只有引擎没有入口」的那一整套流转动作接成可用页面。
// 数据从哪来：DB.members / MemberHub.ext / MemberHub.activityBundle / MemberOpsStore / CredBinStore。
// 主动作：「移交名下凭证」。
import SwiftUI

struct MemberOpsScreen: View {
    @Environment(AppModel.self) private var app

    @State private var memberID = ""
    @State private var transferTo = ""
    @State private var borrowBy = ""
    // 2026-11-03：借用到期是**日期**，按日历加 7 天（86_400×7 在有夏令时的地方会差一小时）。
    @State private var borrowDue = WeekCal.shifted(Date(), days: 7)
    @State private var windowWeekday = 6
    @State private var windowStart = 9
    @State private var windowEnd = 12
    @State private var careText = ""
    @State private var welcome = ""
    @State private var note = ""
    @State private var deleteTyped = ""
    @State private var showDelete = false
    @State private var outcome: String?
    @State private var tick = 0

    private var mac: String { app.currentMac }
    private var members: [MemberCard] { app.members.filter { !$0.archived } }
    private var member: MemberCard? { members.first { $0.id == memberID } }
    private var roster: HouseholdRoster { HouseholdRoster.shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V.S.gapM) {
                header
                if members.isEmpty {
                    emptyCard
                } else {
                    pickerCard
                    if let m = member {
                        summaryCard(m)
                        transferCard(m)
                        borrowCard(m)
                        windowCard
                        sceneCard(m)
                        activityCard(m)
                        visitorCard
                        elderCard
                        deleteCard(m)
                    }
                }
            }
            .padding(.top, V.Page.topSpace)
        }
        .background(V.C.bg.ignoresSafeArea())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("成员流转")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if memberID.isEmpty { memberID = members.first?.id ?? "" }
            loadFields()
        }
        .onChange(of: memberID) { _, _ in loadFields() }
        .alert("删除成员并收回凭证？", isPresented: $showDelete) {
            Button("取消", role: .cancel) { deleteTyped = "" }
            Button("删除", role: .destructive) {
                if deleteTyped == "删除" { performDelete() }
            }
        } message: {
            Text("名下密码与指纹会先移入本机回收站（可整组还原），同时删除成员档案。锁端凭证不会自动删除。请键入「删除」确认。")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: V.S.gapXXS) {
                            // 2026-11-03（全维度整理）：标题交给系统导航栏（大标题），页内不再自绘。
            Text("移交 · 借用 · 家政窗 · 轮值 · 关怀 · 访客 · 长辈")
                .font(V.F.footnote).foregroundStyle(V.C.text3)
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    private var emptyCard: some View {
        VCard {
            Text("还没有成员。先到「家」新建一位成员，再回来处理流转。")
                .font(V.F.body).foregroundStyle(V.C.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private var pickerCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "处理谁", showsChevron: false)
                ScrollView(.horizontal) {
                    HStack(spacing: V.S.gapS) {
                        ForEach(members) { m in
                            Button { memberID = m.id } label: {
                                VTag(text: HHDisplay.name(m, extras: roster.extras(for: m.id)),
                                     tint: memberID == m.id ? V.C.blue : V.C.text3,
                                     filled: memberID == m.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private func summaryCard(_ m: MemberCard) -> some View {
        let ext = roster.extras(for: m.id)
        return VCard(style: .warm) {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: HHDisplay.name(m, extras: ext), showsChevron: false)
                VStatPair(items: [
                    ("角色", m.role.rawValue),
                    ("凭证", "\(m.keyCount) 枚"),
                    ("分组", ext.groupTag.isEmpty ? "未分组" : ext.groupTag)
                ])
                VValueRow(label: "关系", value: ext.relation.isEmpty ? "未填" : ext.relation, mono: false)
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    // MARK: - 移交

    private func transferCard(_ m: MemberCard) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "移交名下凭证")
                Text("把「\(m.name)」名下的密码与指纹改归属到另一位成员；台账条目本身不动。")
                    .font(V.F.footnote).foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView(.horizontal) {
                    HStack(spacing: V.S.gapS) {
                        ForEach(members.filter { $0.id != m.id }) { target in
                            Button { transferTo = target.id } label: {
                                VTag(text: target.name, tint: transferTo == target.id ? V.C.blue : V.C.text3, filled: transferTo == target.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                VActionButton(title: "移交名下凭证", systemImage: "arrow.left.arrow.right") {
                    let n = MemberOpsStore.transfer(mac: mac, from: m.id, to: transferTo)
                    outcome = "已移交 \(n) 枚凭证"
                    tick += 1
                    Task { await app.reload(refreshStatus: false) }
                }
                .disabled(transferTo.isEmpty)
                if let outcome {
                    Text(outcome).font(V.F.footnote).foregroundStyle(V.C.rewardGreen)
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    // MARK: - 借用

    private func borrowCard(_ m: MemberCard) -> some View {
        let map = MemberOpsStore.borrows(mac)
        return VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "借用登记")
                if let b = map[m.id] {
                    VValueRow(label: "借给", value: b.by, mono: false)
                    VValueRow(label: "归还日", value: b.due)
                    VOutlineButton(title: "结束借用", systemImage: "checkmark") {
                        MemberOpsStore.removeBorrow(mac, memberID: m.id)
                        tick += 1
                    }
                } else {
                    VTextFieldRow(label: "借用人", text: $borrowBy, placeholder: "如 楼上邻居")
                    DatePicker("归还日", selection: $borrowDue, displayedComponents: .date)
                        .font(V.F.body).foregroundStyle(V.C.text1)
                    VOutlineButton(title: "登记借用", systemImage: "person.badge.clock") {
                        let df = DF.cached("yyyy-MM-dd")
                        MemberOpsStore.setBorrow(mac, memberID: m.id, by: borrowBy.isEmpty ? m.name : borrowBy, due: df.string(from: borrowDue))
                        outcome = "已登记借用"
                        tick += 1
                    }
                }
                Text("借用只记本机，不写门锁；到期提醒在成员详情里显示。")
                    .font(V.F.micro).foregroundStyle(V.C.text3)
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    // MARK: - 家政窗

    private var windowCard: some View {
        let list = MemberOpsStore.windows(mac)
        return VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "家政窗")
                Text("给钟点工/服务人员的固定进出时段。只做本机排期提示，不写锁端。")
                    .font(V.F.footnote).foregroundStyle(V.C.text3)
                HStack(spacing: V.S.gapS) {
                    Picker("星期", selection: $windowWeekday) {
                        ForEach(1 ... 7, id: \.self) { d in
                            Text(["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"][d]).tag(d)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(V.C.text1)
                    Spacer(minLength: 0)
                }
                HStack(spacing: V.S.gapS) {
                    Stepper("开始 \(windowStart):00", value: $windowStart, in: 0 ... 23)
                        .font(V.F.footnote).foregroundStyle(V.C.text1)
                    Stepper("结束 \(windowEnd):00", value: $windowEnd, in: 1 ... 24)
                        .font(V.F.footnote).foregroundStyle(V.C.text1)
                }
                VOutlineButton(title: "添加家政窗", systemImage: "calendar.badge.plus") {
                    MemberOpsStore.addWindow(mac, HouseWindow(id: UUID().uuidString, weekday: windowWeekday,
                                                              startHour: windowStart, endHour: windowEnd,
                                                              note: ""))
                    outcome = "已添加家政窗"
                    tick += 1
                }
                ForEach(list) { window in
                    HStack {
                        Text("\(window.weekdayText) \(window.startHour):00–\(window.endHour):00")
                            .font(V.F.rowDetail).foregroundStyle(V.C.text1)
                        Spacer(minLength: 0)
                        Button("删除") {
                            MemberOpsStore.removeWindow(mac, id: window.id)
                            tick += 1
                        }
                        .font(V.F.footnote).foregroundStyle(V.C.pink)
                    }
                    .frame(minHeight: V.List.rowMinHeight)
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    // MARK: - 家庭场景

    private func sceneCard(_ m: MemberCard) -> some View {
        VCard(style: .warm) {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "家庭场景")
                VValueRow(label: "本周主责", value: MemberHub.dutyThisWeek == m.id ? "是" : "否")
                // 2026-11-04（同功能两页行为不一致）：成员 360（`MemberDetailScreen:59`）是**切换**
                // （已是主责再点就取消），这一页只有「设为」—— 已经是主责时点了什么都不会变，
                // 却回一句「已设为本周主责」，等于骗了一次点击。改成与 360 同一切换语义。
                let isDutyNow = MemberHub.dutyThisWeek == m.id
                VOutlineButton(title: isDutyNow ? "取消本周主责" : "设为本周主责",
                               systemImage: isDutyNow ? "calendar.badge.minus" : "calendar") {
                    roster.setDuty(isDutyNow ? nil : m.id)
                    outcome = isDutyNow ? "已取消本周主责" : "已设为本周主责"
                }
                VRowDivider()
                VTextFieldRow(label: "关怀便签（孩子/长辈看到的提示）", text: $careText, placeholder: "如 记得带伞", axisVertical: true)
                VTextFieldRow(label: "访客欢迎语", text: $welcome, placeholder: "如 欢迎来家里做客")
                VTextFieldRow(label: "家庭便签", text: $note, placeholder: "如 周六换锁芯", axisVertical: true)
                VOutlineButton(title: "保存家庭场景", systemImage: "checkmark") {
                    roster.update(m.id) { e in
                        e.careText = careText
                        e.welcome = welcome
                        e.note = note
                    }
                    outcome = "已保存"
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    // MARK: - 活跃度

    private func activityCard(_ m: MemberCard) -> some View {
        let bundle = MemberHub.activityBundle(members.map(\.id))
        let a = bundle.table[m.id] ?? MemberHub.Activity()
        let excerpts = MemberHub.recentExcerpts(m.id, 5)
        return VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "活跃度（约）")
                VStatPair(items: [
                    ("近 30 天", "\(a.opens30) 次"),
                    ("本月", "\(a.month) 次"),
                    ("名下", "\(a.owns) 枚")
                ])
                Text(MemberHub.weekSentence(m.id) ?? "近 7 天没有可证明归属的开门。")
                    .font(V.F.footnote).foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
                if excerpts.isEmpty {
                    Text("还没有可归属的开门记录。锁端日志没有身份字段，只能按时间窗推断。")
                        .font(V.F.micro).foregroundStyle(V.C.text3)
                } else {
                    ForEach(Array(excerpts.enumerated()), id: \.offset) { pair in
                        HStack {
                            Text(pair.element.time).font(V.F.micro).foregroundStyle(V.C.text3)
                            Text(pair.element.text).font(V.F.rowDetail).foregroundStyle(V.C.text1)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    // MARK: - 访客虚拟分组

    private var visitorCard: some View {
        let bundle = MemberHub.activityBundle(members.map(\.id))
        let temps = DB.listPwds(mac).filter { $0.temp && ($0.owner ?? "").isEmpty }
        return VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "访客 · 临时码未归属")
                VStatPair(items: [
                    ("访客开门", "\(bundle.visitorOpens) 次"),
                    ("名下临时码", "\(bundle.visitorTemps) 枚")
                ])
                if temps.isEmpty {
                    Text("没有未归属的临时码。")
                        .font(V.F.footnote).foregroundStyle(V.C.text3)
                } else {
                    ForEach(temps.prefix(6)) { p in
                        HStack {
                            Text(CredentialOrg.displayPwd(p)).font(V.F.rowDetail).foregroundStyle(V.C.text1)
                            Spacer(minLength: 0)
                            Menu("归属") {
                                ForEach(members) { m in
                                    Button(m.name) {
                                        DB.setPwdOwner(mac, p.alias, m.id)
                                        outcome = "已归属给 \(m.name)"
                                        tick += 1
                                    }
                                }
                            }
                            .font(V.F.footnote).foregroundStyle(V.C.blue)
                        }
                        .frame(minHeight: V.List.rowMinHeight)
                    }
                }
                Text("访客组只存在于展示层：临时码且无可证明归属才算访客，不写入锁端凭证表。")
                    .font(V.F.micro).foregroundStyle(V.C.text3)
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    // MARK: - 长辈模式

    private var elderCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "长辈模式", showsChevron: false)
                // 2026-11-01（Round 271）：原文案写「行内字号放大」，但**代码里没有任何字号缩放** ——
                // `elderMode` 全仓只用于「筛芯片只留全部/密码/指纹」与「隐藏凭证工作室/分享给安卓两行」。
                // 真正的大字是另一套：「无障碍 → 大字档」（`kf_ax_bigtext` → `dynamicTypeSize`），全 App 生效。
                // 承诺没做的事会让人开了长辈模式却觉得「字没变大、是不是坏了」，所以改准并指过去。
                VToggleRow(title: "开启长辈模式", detail: "凭证页只留全部/密码/指纹分段，隐藏批量与导出入口。只影响凭证页这一档；想让字更大，请到「无障碍」开大字档。", isOn: Binding(
                    get: { MemberHub.elderMode },
                    set: { on in MemberHub.setElderMode(on); tick += 1 }
                ))
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    /// 其它锁上属于这位成员的凭证条数。删除只处理当前锁，这些条目**会变成无归属**
    /// （锁端仍然有效）。确认前就要说出来，别等删完才告知。
    private func otherLocksCountHint(_ m: MemberCard) -> String? {
        let mac = app.currentMac
        var n = 0
        for kc in DB.keychains() where DB.normalizeMac(kc.mac) != DB.normalizeMac(mac) {
            func mine(_ owner: String?) -> Bool {
                guard let owner, !owner.isEmpty else { return false }
                return CredentialOrg.ownerMatches(owner, memberID: m.id, memberName: m.name)
            }
            n += DB.listPwds(kc.mac).filter { mine($0.owner) }.count
            n += DB.listFps(kc.mac).filter { mine($0.owner) }.count
        }
        guard n > 0 else { return nil }
        return "另有 \(n) 条属于 TA 的凭证在其它锁上 —— 那些锁端仍然有效，删除后只会变成「未归属」，不会进回收站。需要的话请分别到那几把锁上单独删除。"
    }

    // MARK: - 删除成员（级联凭证入回收站）

    private func deleteCard(_ m: MemberCard) -> some View {
        let preview = CredentialOrg.memberCredentialPreview(m.id)
        let otherLocksHint = otherLocksCountHint(m)
        return VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "删除成员", showsChevron: false)
                // 2026-11-04（读实现发现 · 跨锁与单锁口径不同）：`memberCredentialPreview` 是
                // **跨所有锁**合计，而 `cascadeDelete(mac:memberID:)` 只处理**当前这把锁**。
                // 多锁家庭里这个数字会大于实际进回收站的数量 —— 而这句话是删除确认，
                // 用户按它判断"会丢多少"。
                Text("当前这把锁名下 \(preview.count) 枚凭证会先进入回收站（可整组还原），然后删除成员档案。")
                    .font(V.F.footnote).foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
                // 2026-11-04（预告补全）：删除后的回执已经会说「另有 N 条在其它锁上，已转为无归属」——
                // 但那是**删完之后**才说的。同一件事应当在确认前就说，否则多锁家庭用户
                // 点下去才发现"另外两把锁上的凭证还在，只是没人归属了"。
                if let extra = otherLocksHint {
                    Text(extra)
                        .font(V.F.footnote).foregroundStyle(V.C.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !preview.isEmpty {
                    Text(preview.prefix(4).joined(separator: " · "))
                        .font(V.F.micro).foregroundStyle(V.C.text3)
                        .lineLimit(2)
                }
                VTextFieldRow(label: "键入「删除」确认", text: $deleteTyped, placeholder: "删除")
                VOutlineButton(title: "删除成员", systemImage: "person.crop.circle.badge.minus", tint: V.C.red) {
                    showDelete = true
                }
                .disabled(deleteTyped != "删除")
                .opacity(deleteTyped == "删除" ? 1 : 0.45)
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    // MARK: - 动作

    private func loadFields() {
        guard let m = member else { return }
        let ext = roster.extras(for: m.id)
        careText = ext.careText
        welcome = ext.welcome
        note = ext.note
        transferTo = members.first(where: { $0.id != m.id })?.id ?? ""
    }

    private func performDelete() {
        guard let m = member else { return }
        // 先数一下"其它锁"上这家伙名下的条目 —— 级联只处理当前这把锁，
        // 而 `DB.removeMember` 会把其它锁上的 owner 一并清空（凭证/指纹仍在、锁端照旧有效）。
        // 不提示的话，用户会以为"删除成员"已经把他所有权限都处理了。
        // 2026-11-03：同 cascadeDelete —— 旧数据按名字存 owner，只数 id 会漏。
        let otherLocks = DB.keychains().filter { $0.mac != mac }.reduce(0) { acc, kc in
            func mine(_ owner: String?) -> Bool {
                guard let owner, !owner.isEmpty else { return false }
                return CredentialOrg.ownerMatches(owner, memberID: m.id, memberName: m.name)
            }
            return acc + DB.listPwds(kc.mac).filter { mine($0.owner) }.count
                + DB.listFps(kc.mac).filter { mine($0.owner) }.count
        }
        let n = MemberOpsStore.cascadeDelete(mac: mac, memberID: m.id)
        DB.removeMember(m.id)
        roster.forget(m.id)
        memberID = members.first(where: { $0.id != m.id })?.id ?? ""
        deleteTyped = ""
        outcome = "已删除成员，\(n) 枚凭证进入回收站"
            + (otherLocks > 0 ? "；另有 \(otherLocks) 条在其它锁上，已转为无归属（锁端仍然有效，需要时请到那把锁上单独删除）" : "")
        Task { await app.reload(refreshStatus: false) }
    }
}

#Preview("MemberOpsScreen") {
    NavigationStack { MemberOpsScreen() }
        .environment(AppModel())
        .environment(Router())
}
