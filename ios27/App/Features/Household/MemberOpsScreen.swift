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
    @State private var borrowDue = Date().addingTimeInterval(7 * 86400)
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
            .padding(.bottom, V.Tab.contentInset)
        }
        .background(V.C.bg.ignoresSafeArea())
        .navigationTitle("成员流转")
        .navigationBarTitleDisplayMode(.inline)
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
            Text("成员流转")
                .font(V.F.displayA).foregroundStyle(V.C.text1)
            Text("移交 · 借用 · 家政窗 · 轮值 · 关怀 · 访客 · 长辈")
                .font(V.F.footnote).foregroundStyle(V.C.text3)
        }
        .padding(.horizontal, V.S.pageGutterA)
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
                VOutlineButton(title: "设为本周主责", systemImage: "calendar") {
                    roster.setDuty(m.id)
                    outcome = "已设为本周主责"
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
                VToggleRow(title: "开启长辈模式", detail: "凭证页只留全部/密码/指纹分段，隐藏批量与导出入口，行内字号放大。只影响凭证页这一档。", isOn: Binding(
                    get: { MemberHub.elderMode },
                    set: { on in MemberHub.setElderMode(on); tick += 1 }
                ))
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    // MARK: - 删除成员（级联凭证入回收站）

    private func deleteCard(_ m: MemberCard) -> some View {
        let preview = CredentialOrg.memberCredentialPreview(m.id)
        return VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "删除成员", showsChevron: false)
                Text("名下 \(preview.count) 枚凭证会先进入回收站（可整组还原），然后删除成员档案。")
                    .font(V.F.footnote).foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
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
        let n = MemberOpsStore.cascadeDelete(mac: mac, memberID: m.id)
        DB.removeMember(m.id)
        roster.forget(m.id)
        memberID = members.first(where: { $0.id != m.id })?.id ?? ""
        deleteTyped = ""
        outcome = "已删除成员，\(n) 枚凭证进入回收站"
        Task { await app.reload(refreshStatus: false) }
    }
}

#Preview("MemberOpsScreen") {
    NavigationStack { MemberOpsScreen() }
        .environment(AppModel())
        .environment(Router())
}
