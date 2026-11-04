// MemberOpsHomeScreen.swift —— 成员流转与家庭场景（V8 设计语言）
//
// 与 MemberOpsScreen 的能力对齐：移交 / 借用登记 / 家政窗 / 轮值 / 关怀便签 / 访客临时码归属 /
// 长辈模式 / 删除成员（级联本机凭证进回收站）。
// 数据仍来自 DB.members / MemberHub / MemberOpsStore / CredBinStore / CredentialOrg。
//
// 与旧页的刻意差异（删除成员的「两套后果」统一成一套）：
//   旧页的确认框只写「名下密码与指纹会先移入本机回收站（可整组还原）」，但同一段代码还会做两件
//   它没说的话：① 只有**当前这把锁**的凭证进回收站；② 其它锁上的归属被清空，凭证不进回收站、
//   锁端仍然有效。这里把三件事写在同一个确认里，并在删除回执里再说一遍 —— 用户按确认框就能判断
//   「我会丢什么」，不用等删完才知道。
import SwiftUI

struct MemberOpsHomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    @State private var memberID = ""
    @State private var transferTo = ""
    @State private var borrowBy = ""
    // 借用到期是**日期**，按日历加 7 天（86_400×7 在有夏令时的地方会差一小时）。
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
    /// 回执是成功还是「什么都没做成」——颜色必须来自这个标志，不来自文案里有没有某个字。
    @State private var outcomeOK = true
    @State private var tick = 0

    private var mac: String { app.currentMac }
    private var decoyed: Bool { DB.isDecoy }
    private var readOnly: Bool { app.trialGuard }
    private var members: [MemberCard] { app.members.filter { !$0.archived } }
    private var member: MemberCard? { members.first { $0.id == memberID } }
    private var roster: HouseholdRoster { HouseholdRoster.shared }

    private var judgement: String {
        if decoyed { return "空壳模式下不显示成员" }
        if members.isEmpty { return "家里还没有成员" }
        guard let member else { return "先选一位成员" }
        return "处理「" + HHDisplay.name(member, extras: roster.extras(for: member.id)) + "」"
    }

    private var lead: String {
        if decoyed {
            return "空壳模式只隐藏数据，不改动数据。成员与凭证归属都不显示，也不写入。"
        }
        if members.isEmpty { return "成员流转要挂在具体某个人身上。先到「家」新建一位成员，再回来。" }
        return "移交、借用、家政窗与便签都只改本机台账，不下发到门锁；锁端的密码与指纹仍需线下操作。离线时这些动作照常可用。"
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            if decoyed || members.isEmpty {
                EmptyView()
            } else {
                chipRow
            }
        } content: {
            if decoyed {
                decoyCard
            } else if members.isEmpty {
                VEmpty(
                    title: "还没有成员",
                    reason: "成员流转要挂在具体某个人身上。先到「家」新建一位成员，再回来处理。",
                    actionTitle: "去新建成员"
                ) { router.request(.dest(.memberCreate)) }
            } else {
                pickerCard
                if let member {
                    summaryCard(member)
                    transferCard(member)
                    borrowCard(member)
                    windowCard
                    sceneCard(member)
                    activityCard(member)
                    visitorCard
                    elderCard
                    deleteCard(member)
                }
                if outcome != nil {
                    outcomeCard
                }
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if memberID.isEmpty { memberID = members.first?.id ?? "" }
            loadFields()
        }
        .onChange(of: memberID) { _, _ in loadFields() }
        .v8Confirm(
            isPresented: $showDelete,
            title: "删除成员并收回本机凭证？",
            consequence: deleteConsequence,
            confirmTitle: "删除成员",
            isDestructive: true
        ) {
            performDelete()
        }
    }

    // MARK: - 芯片行

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: V8.S.gapChip) {
                VChip2(icon: .ring(1, V8.C.accent), label: "成员", value: "\(members.count) 位")
                VChip2(icon: .ring(0.5, V8.C.info), label: "借用", value: "\(borrowCount) 条")
                VChip2(icon: .ring(0.3, V8.D.fingerprint), label: "家政窗", value: "\(windowList.count) 条")
                VChip2(icon: .ring(isDuty ? 1 : 0.02, V8.C.ok), label: "本周主责", value: isDuty ? "是" : "否")
            }
            .padding(.leading, V8.S.gutterCard)
            .padding(.trailing, V8.S.gutterCard)
        }
        .scrollClipDisabled()
    }

    /// 借与家政窗都落在 UserDefaults，视图没有别的观察点 —— 每次写入后 tick 变一次，
    /// 这两个读点把它读出来，页面才会跟着重建（否则刚登记完的借用行不会出现）。
    private var borrowCount: Int { borrowMap.count }

    private var borrowMap: [String: MemberBorrow] {
        _ = tick
        return MemberOpsStore.borrows(mac)
    }

    private var windowList: [HouseWindow] {
        _ = tick
        return MemberOpsStore.windows(mac)
    }

    private var isDuty: Bool {
        guard let member else { return false }
        return MemberHub.dutyThisWeek == member.id
    }

    // MARK: - 处理谁

    private var pickerCard: some View {
        VCard2 {
            VCardHead(eyebrow: "处理谁", statement: member.map { HHDisplay.name($0, extras: roster.extras(for: $0.id)) } ?? "未选", trailing: "\(members.count) 位在册")
            VDivider2()
                .padding(.top, V8.S.gapM)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: V8.S.gapChip) {
                    ForEach(members) { m in
                        pickerChip(m)
                    }
                }
            }
            .padding(.top, V8.S.gapM)
        }
    }

    private func pickerChip(_ m: MemberCard) -> some View {
        let on = memberID == m.id
        return Button {
            memberID = m.id
        } label: {
            Text(HHDisplay.name(m, extras: roster.extras(for: m.id)))
                .font(V8.T.tab)
                .foregroundStyle(on ? V8.C.chipOn : V8.C.ink1)
                .padding(.horizontal, V8.S.gapM)
                .frame(minHeight: V8.H.min)
                .background(Capsule(style: .continuous).fill(on ? V8.C.accent : V8.C.chipOff))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(m.name)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - 概览

    private func summaryCard(_ m: MemberCard) -> some View {
        let ext = roster.extras(for: m.id)
        return VCard2(style: .well) {
            VCardHead(eyebrow: "概览", statement: m.role.rawValue, trailing: "\(m.keyCount) 枚凭证")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStatPair2(items: [
                .init(label: "关系", value: ext.relation.isEmpty ? "未填" : ext.relation),
                .init(label: "分组", value: ext.groupTag.isEmpty ? "未分组" : ext.groupTag)
            ])
            .padding(.top, V8.S.gapM)
        }
    }

    // MARK: - 移交

    private func transferCard(_ m: MemberCard) -> some View {
        VCard2 {
            VCardHead(eyebrow: "移交名下凭证", statement: transferToMember.map { "给「" + $0.name + "」" } ?? "先选接收人")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("把「" + m.name + "」名下的密码与指纹改归属到另一位成员；台账条目本身不动。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: V8.S.gapS) {
                    ForEach(members.filter { $0.id != m.id }) { target in
                        transferChip(target)
                    }
                }
            }
            .padding(.top, V8.S.gapM)
            Button {
                let n = MemberOpsStore.transfer(mac: mac, from: m.id, to: transferTo)
                // 0 枚不是成功：台账里可能一条都没有归属到 TA，也可能是归属存的是旧口径的名字。
                // 旧页一律报「已移交 N 枚凭证」并把 0 也涂成成功色 —— 用户会以为已经处理完。
                if n > 0 {
                    outcome = "已移交 " + String(n) + " 枚凭证"
                    outcomeOK = true
                } else {
                    outcome = "没有可移交的凭证 —— TA 名下这台锁上没有密码或指纹，或它们的归属还是旧口径的名字。"
                    outcomeOK = false
                }
                tick += 1
                Task { await app.reload(refreshStatus: false) }
            } label: {
                Text("移交名下凭证")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.chipOn)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.accent))
            }
            .buttonStyle(.plain)
            .disabled(transferTo.isEmpty)
            .opacity(transferTo.isEmpty ? 0.45 : 1)
            .accessibilityLabel("移交名下凭证")
            .padding(.top, V8.S.gapM)
            Text("移交只改本机台账的归属，不下发到门锁 —— 锁端凭证仍然有效。")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var transferToMember: MemberCard? { members.first { $0.id == transferTo } }

    private func transferChip(_ target: MemberCard) -> some View {
        let on = transferTo == target.id
        return Button {
            transferTo = target.id
        } label: {
            Text(target.name)
                .font(V8.T.tab)
                .foregroundStyle(on ? V8.C.chipOn : V8.C.ink1)
                .padding(.horizontal, V8.S.gapM)
                .frame(minHeight: V8.H.min)
                .background(Capsule(style: .continuous).fill(on ? V8.C.accent : V8.C.chipOff))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("移交给 " + target.name)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - 借用

    private func borrowCard(_ m: MemberCard) -> some View {
        let map = borrowMap
        return VCard2 {
            VCardHead(eyebrow: "借用登记", statement: map[m.id].map { "借给 " + $0.by } ?? "未登记", trailing: map[m.id]?.due)
            VDivider2()
                .padding(.top, V8.S.gapM)
            if let b = map[m.id] {
                VDataRow(tag: "借给", tagTint: V8.C.ink4, title: b.by, value: "")
                    .padding(.top, V8.S.gapS)
                VDataRow(tag: "归还日", tagTint: V8.C.ink4, title: b.due, value: "")
                Button {
                    MemberOpsStore.removeBorrow(mac, memberID: m.id)
                    outcome = "已结束借用"
                    outcomeOK = true
                    tick += 1
                } label: {
                    Text("结束借用")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.ink1)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .overlay(
                            RoundedRectangle(cornerRadius: V8.R.capsule(V8.H.min), style: .continuous)
                                .strokeBorder(V8.C.line, lineWidth: V8.S.hair)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("结束借用")
                .padding(.top, V8.S.gapM)
            } else {
                VStack(alignment: .leading, spacing: V8.S.gapXS) {
                    Text("借用人")
                        .font(V8.T.label)
                        .foregroundStyle(V8.C.ink4)
                    TextField("如 楼上邻居", text: $borrowBy)
                        .font(V8.T.body)
                        .foregroundStyle(V8.C.ink1)
                        .frame(minHeight: V8.H.min)
                        .padding(.horizontal, V8.S.gapM)
                        .background(V8.C.well, in: .rect(cornerRadius: V8.R.inset))
                }
                .padding(.top, V8.S.gapM)
                DatePicker("归还日", selection: $borrowDue, displayedComponents: .date)
                    .font(V8.T.body)
                    .foregroundStyle(V8.C.ink1)
                    .frame(minHeight: V8.H.min)
                    .padding(.top, V8.S.gapS)
                Button {
                    let df = DF.cached("yyyy-MM-dd")
                    MemberOpsStore.setBorrow(mac, memberID: m.id, by: borrowBy.isEmpty ? m.name : borrowBy, due: df.string(from: borrowDue))
                    outcome = "已登记借用"
                    outcomeOK = true
                    tick += 1
                } label: {
                    Text("登记借用")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.ink1)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .overlay(
                            RoundedRectangle(cornerRadius: V8.R.capsule(V8.H.min), style: .continuous)
                                .strokeBorder(V8.C.line, lineWidth: V8.S.hair)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("登记借用")
                .padding(.top, V8.S.gapM)
            }
            Text("借用只记本机，不写门锁；到期提醒在成员详情里显示。")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 家政窗

    private var windowCard: some View {
        let list = windowList
        return VCard2 {
            VCardHead(eyebrow: "家政窗", statement: list.isEmpty ? "没有固定时段" : "\(list.count) 个时段", trailing: "本机排期")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("给钟点工 / 服务人员的固定进出时段。只做本机排期提示，不写锁端。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: V8.S.gapS) {
                Picker("星期", selection: $windowWeekday) {
                    ForEach(1 ... 7, id: \.self) { d in
                        Text(Self.weekdayNames[d]).tag(d)
                    }
                }
                .pickerStyle(.menu)
                Spacer(minLength: 0)
            }
            .padding(.top, V8.S.gapS)
            Stepper("开始 \(windowStart):00", value: $windowStart, in: 0 ... 23)
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink1)
            Stepper("结束 \(windowEnd):00", value: $windowEnd, in: 1 ... 24)
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink1)
            Button {
                // 起 == 止 是空集：加进去也筛不出任何时段，先如实拒绝而不是让用户对着空窗猜。
                if windowStart >= windowEnd {
                    outcome = "开始时间要早于结束时间 —— 现在是 " + String(windowStart) + ":00 到 " + String(windowEnd) + ":00，这个时段是空的。"
                    outcomeOK = false
                } else {
                    MemberOpsStore.addWindow(mac, HouseWindow(id: UUID().uuidString, weekday: windowWeekday,
                                                              startHour: windowStart, endHour: windowEnd, note: ""))
                    outcome = "已添加家政窗"
                    outcomeOK = true
                    tick += 1
                }
            } label: {
                Text("添加家政窗")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.ink1)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .overlay(
                        RoundedRectangle(cornerRadius: V8.R.capsule(V8.H.min), style: .continuous)
                            .strokeBorder(V8.C.line, lineWidth: V8.S.hair)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("添加家政窗")
            .padding(.top, V8.S.gapS)
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, window in
                    if index > 0 { VDotRule() }
                    HStack(spacing: V8.S.gapS) {
                        Text(window.weekdayText + " " + String(window.startHour) + ":00–" + String(window.endHour) + ":00")
                            .font(V8.T.value)
                            .foregroundStyle(V8.C.ink1)
                        Spacer(minLength: 0)
                        Button {
                            MemberOpsStore.removeWindow(mac, id: window.id)
                            tick += 1
                        } label: {
                            Text("删除")
                                .font(V8.T.caption)
                                .foregroundStyle(V8.C.danger)
                                .frame(minHeight: V8.H.min)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("删除 " + window.weekdayText + " 的时段")
                    }
                    .frame(minHeight: V8.H.min)
                }
            }
            .padding(.top, V8.S.gapS)
        }
    }

    private static let weekdayNames = ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    // MARK: - 家庭场景

    private func sceneCard(_ m: MemberCard) -> some View {
        let isDutyNow = MemberHub.dutyThisWeek == m.id
        return VCard2(style: .well) {
            VCardHead(eyebrow: "家庭场景", statement: isDutyNow ? "本周主责 · 是" : "本周主责 · 否", trailing: "本机")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(alignment: .leading, spacing: V8.S.gapM) {
                Button {
                    roster.setDuty(isDutyNow ? nil : m.id)
                    outcome = isDutyNow ? "已取消本周主责" : "已设为本周主责"
                    outcomeOK = true
                } label: {
                    Text(isDutyNow ? "取消本周主责" : "设为本周主责")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.ink1)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .overlay(
                            RoundedRectangle(cornerRadius: V8.R.capsule(V8.H.min), style: .continuous)
                                .strokeBorder(V8.C.line, lineWidth: V8.S.hair)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isDutyNow ? "取消本周主责" : "设为本周主责")
                fieldBlock("关怀便签（孩子 / 长辈看到的提示）", text: $careText, placeholder: "如 记得带伞")
                fieldBlock("访客欢迎语", text: $welcome, placeholder: "如 欢迎来家里做客")
                fieldBlock("家庭便签", text: $note, placeholder: "如 周六换锁芯")
                Button {
                    roster.update(m.id) { e in
                        e.careText = careText
                        e.welcome = welcome
                        e.note = note
                    }
                    outcome = "已保存家庭场景"
                    outcomeOK = true
                } label: {
                    Text("保存家庭场景")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.ink1)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .overlay(
                            RoundedRectangle(cornerRadius: V8.R.capsule(V8.H.min), style: .continuous)
                                .strokeBorder(V8.C.line, lineWidth: V8.S.hair)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("保存家庭场景")
            }
            .padding(.top, V8.S.gapM)
        }
    }

    private func fieldBlock(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: V8.S.gapXS) {
            Text(label)
                .font(V8.T.label)
                .foregroundStyle(V8.C.ink4)
            TextField(placeholder, text: text)
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink1)
                .frame(minHeight: V8.H.min)
                .padding(.horizontal, V8.S.gapM)
                .background(V8.C.well, in: .rect(cornerRadius: V8.R.inset))
        }
    }

    // MARK: - 活跃度

    private func activityCard(_ m: MemberCard) -> some View {
        let bundle = MemberHub.activityBundle(members.map(\.id))
        let a = bundle.table[m.id] ?? MemberHub.Activity()
        let excerpts = MemberHub.recentExcerpts(m.id, 5)
        return VCard2 {
            VCardHead(eyebrow: "活跃度", statement: "近 30 天 " + String(a.opens30) + " 次", trailing: "约")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStatPair2(items: [
                .init(label: "近 30 天", value: String(a.opens30), unit: "次"),
                .init(label: "本月", value: String(a.month), unit: "次"),
                .init(label: "名下", value: String(a.owns), unit: "枚")
            ])
            .padding(.top, V8.S.gapM)
            Text(MemberHub.weekSentence(m.id) ?? "近 7 天没有可证明归属的开门。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            if excerpts.isEmpty {
                Text("还没有可归属的开门记录。锁端日志没有身份字段，只能按时间窗推断。")
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(excerpts.enumerated()), id: \.offset) { index, item in
                        if index > 0 { VDotRule() }
                        VDataRow(tag: item.time, tagTint: V8.C.ink4, title: item.text, value: "")
                    }
                }
                .padding(.top, V8.S.gapS)
            }
        }
    }

    // MARK: - 访客虚拟分组

    private var visitorCard: some View {
        let bundle = MemberHub.activityBundle(members.map(\.id))
        let temps = DB.listPwds(mac).filter { $0.temp && ($0.owner ?? "").isEmpty }
        return VCard2 {
            VCardHead(eyebrow: "访客 · 临时码未归属", statement: "开门 " + String(bundle.visitorOpens) + " 次", trailing: "本机展示层")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStatPair2(items: [
                .init(label: "访客开门", value: String(bundle.visitorOpens), unit: "次"),
                .init(label: "名下临时码", value: String(bundle.visitorTemps), unit: "枚")
            ])
            .padding(.top, V8.S.gapM)
            if temps.isEmpty {
                Text("没有未归属的临时码。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(temps.prefix(6).enumerated()), id: \.element.alias) { index, p in
                        if index > 0 { VDotRule() }
                        HStack(spacing: V8.S.gapS) {
                            Text(CredentialOrg.displayPwd(p))
                                .font(V8.T.value)
                                .foregroundStyle(V8.C.ink1)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Menu {
                                ForEach(members) { m in
                                    Button(m.name) {
                                        DB.setPwdOwner(mac, p.alias, m.id)
                                        outcome = "已归属给 " + m.name
                                        outcomeOK = true
                                        tick += 1
                                    }
                                }
                            } label: {
                                Text("归属")
                                    .font(V8.T.caption)
                                    .foregroundStyle(V8.C.info)
                                    .frame(minHeight: V8.H.min)
                            }
                            .accessibilityLabel("给临时码选归属")
                        }
                        .frame(minHeight: V8.H.min)
                    }
                }
                .padding(.top, V8.S.gapS)
            }
            Text("访客组只存在于展示层：临时码且无可证明归属才算访客，不写入锁端凭证表。")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 长辈模式

    private var elderCard: some View {
        VCard2 {
            VCardHead(eyebrow: "长辈模式", statement: MemberHub.elderMode ? "已开启" : "未开启", trailing: "只影响凭证页")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Toggle(isOn: Binding(
                get: { MemberHub.elderMode },
                set: { on in
                    MemberHub.setElderMode(on)
                    tick += 1
                }
            )) {
                VStack(alignment: .leading, spacing: V8.S.gapXS) {
                    Text("开启长辈模式")
                        .font(V8.T.value)
                        .foregroundStyle(V8.C.ink1)
                    Text("凭证页只留全部 / 密码 / 指纹分段，隐藏批量与导出入口。只影响凭证页这一档；想让字更大，请到「无障碍」开大字档。")
                        .font(V8.T.caption)
                        .foregroundStyle(V8.C.ink4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minHeight: V8.H.min)
            .padding(.top, V8.S.gapM)
        }
    }

    // MARK: - 删除成员（级联本机凭证入回收站）

    private func deleteCard(_ m: MemberCard) -> some View {
        let preview = CredentialOrg.memberCredentialPreview(m.id)
        let otherHint = otherLocksHint(m)
        return VCard2 {
            VCardHead(eyebrow: "删除成员", statement: "本机档案 + 归属一并清", trailing: "不可撤销")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("当前这把锁名下 " + String(currentLockCredentialCount(m)) + " 枚凭证会先进入回收站（可整组还原），然后删除成员档案。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            if let otherHint {
                Text(otherHint)
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.warn)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !preview.isEmpty {
                Text(preview.prefix(4).joined(separator: " · "))
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
                    .lineLimit(2)
                    .padding(.top, V8.S.gapS)
            }
            if readOnly {
                Text("只读试验模式开着：它只拦下发到门锁的写命令。本页删除只改本机台账与回收站，锁端凭证本来就要线下删。")
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: V8.S.gapXS) {
                Text("键入「删除」确认")
                    .font(V8.T.label)
                    .foregroundStyle(V8.C.ink4)
                TextField("删除", text: $deleteTyped)
                    .font(V8.T.body)
                    .foregroundStyle(V8.C.ink1)
                    .frame(minHeight: V8.H.min)
                    .padding(.horizontal, V8.S.gapM)
                    .background(V8.C.well, in: .rect(cornerRadius: V8.R.inset))
            }
            .padding(.top, V8.S.gapM)
            Button {
                showDelete = true
            } label: {
                Text("删除成员")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.danger)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.dangerTrack))
            }
            .buttonStyle(.plain)
            .disabled(deleteTyped != "删除")
            .opacity(deleteTyped == "删除" ? 1 : 0.45)
            .accessibilityLabel("删除成员")
            .padding(.top, V8.S.gapM)
        }
    }

    private var outcomeCard: some View {
        VCard2(style: .well) {
            Text(outcome ?? "")
                .font(V8.T.footnote)
                .foregroundStyle(outcomeOK ? V8.C.ok : V8.C.warn)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 空壳

    private var decoyCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "成员流转", statement: "空壳模式只读")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("空壳模式（胁迫码进入）下，成员名单、凭证归属与家庭便签都不显示，也不写入。")
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink3)
                .lineSpacing(V8.L.body - V8.T.body.size)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Text("退出空壳请在本机密码界面输入正常密码。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 删除的后果（统一成一套）

    private var deleteConsequence: String {
        guard let m = member else { return "" }
        let current = currentLockCredentialCount(m)
        let other = otherLocksCredentialCount(m)
        var parts: [String] = []
        if current > 0 {
            parts.append("当前这把锁名下 " + String(current) + " 枚凭证会先进入本机回收站（可整组还原），然后删除成员档案。")
        } else {
            parts.append("当前这把锁名下没有这位成员的凭证。")
        }
        if other > 0 {
            parts.append("另有 " + String(other) + " 条在其它锁上：只解除归属，不进回收站，锁端仍然有效 —— 需要时请分别到那几把锁上单独删。")
        }
        parts.append("成员档案删除后不可恢复；锁端凭证不会自动删除，指纹一旦在锁端删掉就无法远程补录。")
        return parts.joined(separator: "\n\n")
    }

    /// 其它锁上属于这位成员的凭证条数。删除只处理当前锁，这些条目会变成无归属。
    private func otherLocksHint(_ m: MemberCard) -> String? {
        let n = otherLocksCredentialCount(m)
        guard n > 0 else { return nil }
        return "另有 " + String(n) + " 条属于 TA 的凭证在其它锁上 —— 那些锁端仍然有效，删除后只会变成「未归属」，不会进回收站。需要的话请分别到那几把锁上单独删除。"
    }

    private func otherLocksCredentialCount(_ m: MemberCard) -> Int {
        var n = 0
        for kc in DB.keychains() where DB.normalizeMac(kc.mac) != DB.normalizeMac(mac) {
            n += DB.listPwds(kc.mac).filter { CredentialOrg.ownerMatches($0.owner, memberID: m.id, memberName: m.name) }.count
            n += DB.listFps(kc.mac).filter { CredentialOrg.ownerMatches($0.owner, memberID: m.id, memberName: m.name) }.count
        }
        return n
    }

    private func currentLockCredentialCount(_ m: MemberCard) -> Int {
        DB.listPwds(mac).filter { CredentialOrg.ownerMatches($0.owner, memberID: m.id, memberName: m.name) }.count
            + DB.listFps(mac).filter { CredentialOrg.ownerMatches($0.owner, memberID: m.id, memberName: m.name) }.count
    }

    // MARK: - 动作

    private func loadFields() {
        guard !decoyed else { return }
        guard let m = member else { return }
        let ext = roster.extras(for: m.id)
        careText = ext.careText
        welcome = ext.welcome
        note = ext.note
        transferTo = members.first(where: { $0.id != m.id })?.id ?? ""
    }

    private func performDelete() {
        guard !decoyed, deleteTyped == "删除", let m = member else { return }
        let other = otherLocksCredentialCount(m)
        let n = MemberOpsStore.cascadeDelete(mac: mac, memberID: m.id)
        DB.removeMember(m.id)
        roster.forget(m.id)
        memberID = members.first(where: { $0.id != m.id })?.id ?? ""
        deleteTyped = ""
        outcome = "已删除成员，" + String(n) + " 枚凭证进入回收站"
            + (other > 0 ? "；另有 " + String(other) + " 条在其它锁上，已转为无归属（锁端仍然有效，需要时请到那把锁上单独删除）" : "")
        Task { await app.reload(refreshStatus: false) }
    }
}
