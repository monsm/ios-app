// MemberDetailHomeScreen.swift —— 成员（V8 设计语言）· 02 §3.4 #29+#32 归并后的宿主页
//
// 与 MemberDetailScreen 的能力对齐：角色与权限矩阵 / 档案扩展 / 名下凭证 / 最近开门摘录 /
// 家庭场景（本周主责）/ 归档与删除 / 同名合并。
// 数据仍来自 AppModel.members + HouseholdRoster + app.entries；真值落 kf_member_ext、
// kf_duty_week 与 kf_members（电话）。
//
// 与旧页的刻意差异：
//   ① 空壳模式（胁迫码）整页不显示成员档案 —— 成员是本机真值，不是「锁端读不到就为空」那一类。
//   ② 旧页「只移除档案」与「连本机凭证一起移除」两个删除选项，实际都走 DB.removeMember（都会解除全部归属），
//      差别只在内存里的一份投影；这里统一成一个删除入口，并在确认里把三种真实后果一次写清。
//   ③ memberOps 整段并入（02 §3.4 #32）：移交 / 借用 / 家政窗 / 访客临时码归属 / 长辈模式 / 活跃度摘录，
//      全部挂在「这位成员」身上（不再单独一张「处理谁」芯片选人）。删除只保留本页这一套 ——
//      MemberOps 的删除卡（cascadeDelete 进回收站口径）与收尾卡的删除是同一件事的两套文案，按 02 §6.3 只留一套：
//      收尾卡的 .v8Confirm 已经写清「当前锁进回收站 + 其它锁只解除归属 + 锁端仍需线下删」，删除动作也升级为 cascadeDelete。
import SwiftUI
import UIKit

struct MemberDetailHomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    @State private var draft = HHMemberExtras()
    @State private var phone = ""
    @State private var loadedID: String?
    @State private var confirmDelete = false
    @State private var saved = false
    @State private var callNote: String?
    @State private var showMerge = false
    // —— memberOps 并入段的状态（原 MemberOpsHomeScreen）
    @State private var transferTo = ""
    @State private var borrowBy = ""
    // 借用到期是**日期**，按日历加 7 天（86_400×7 在有夏令时的地方会差一小时）。
    @State private var borrowDue = WeekCal.shifted(Date(), days: 7)
    @State private var windowWeekday = 6
    @State private var windowStart = 9
    @State private var windowEnd = 12
    @State private var careText = ""
    @State private var welcome = ""
    @State private var opsNote = ""
    @State private var opsOutcome: String?
    /// 回执是成功还是「什么都没做成」——颜色必须来自这个标志，不来自文案里有没有某个字。
    @State private var opsOutcomeOK = true
    @State private var opsTick = 0

    private var roster: HouseholdRoster { HouseholdRoster.shared }
    private var decoyed: Bool { DB.isDecoy }

    private var member: MemberCard? {
        guard let id = roster.focusMember else { return nil }
        return app.members.first { $0.id == id }
    }

    private var judgement: String {
        if decoyed { return "空壳模式下不显示成员档案" }
        guard let member else { return "还没选成员" }
        if member.archived { return "「" + HHDisplay.name(member, extras: draft) + "」已归档" }
        return "「" + HHDisplay.name(member, extras: draft) + "」"
    }

    /// 2026-11-05（对抗审查 · 设计冗余）：没有选中成员时不再返回这段话 ——
    /// VEmpty 的 reason 就是同一句（逐字相同），空态里连说两遍。
    private var lead: String? {
        if decoyed {
            return "空壳模式只隐藏数据，不改动数据。成员档案与名下凭证都不显示，也不写入。"
        }
        guard let member else { return nil }
        if member.archived { return "归档只收起名册与统计，历史一条不删。逐位可恢复，没有「全部恢复」。" }
        return "档案扩展只存本机，不写入门锁；角色矩阵管的是本机界面，锁端没有角色字段。"
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            if decoyed || member == nil {
                EmptyView()
            } else {
                chipRow
            }
        } content: {
            if decoyed {
                decoyCard
            } else if let member {
                weekCard(member)
                roleCard(member)
                profileCard(member)
                if let callNote {
                    VFailure(
                        what: "这一通电话没有拨出去",
                        why: callNote,
                        next: "把号码改到系统能接受的形状（纯数字、至少 3 位），再点一次「呼叫」。"
                    )
                }
                keysCard(member)
                excerptsCard(member)
                sceneCard(member)
                opsSection(member)
                closingCard(member)
                if !MemberMergeKit.candidates(primaryID: member.id).isEmpty {
                    mergeCard
                }
            } else {
                VEmpty(
                    title: "从名册里选一位",
                    reason: "从「家」的成员名册里点一位成员进来，这里会显示 TA 的档案、凭证与权限。",
                    actionTitle: "回到名册"
                ) { router.request(.tab(.household)) }
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let ctx = router.consume(if: { if case .member = $0 { return true }; return false }),
               case .member(let id) = ctx {
                roster.focusMember = id
            }
            load()
            loadOpsFields()
        }
        .sheet(isPresented: $showMerge) {
            if let member { MemberMergeSheet(primary: member) }
        }
        .onChange(of: roster.focusMember) { _, _ in loadOpsFields() }
    }

    // MARK: - 芯片行

    private var chipRow: some View {
        VHScroll {
            HStack(spacing: V8.S.gapChip) {
                VChip2(icon: .glyph(roleSymbol(member?.role ?? .member)), label: "角色", value: member?.role.rawValue ?? "未选")
                VChip2(icon: .ring(1, V8.D.fingerprint), label: "凭证", value: "\(member?.keyCount ?? 0) 枚")
                VChip2(icon: .ring(0.5, V8.C.info), label: "最近", value: member.map { HHStats.lastOpen($0) } ?? "—")
                VChip2(icon: .ring(isDuty ? 1 : 0.02, V8.C.ok), label: "本周主责", value: isDuty ? "是" : "否")
            }
            .padding(.leading, V8.S.gutterCard)
            .padding(.trailing, V8.S.gutterCard)
        }
        .scrollClipDisabled()
    }

    private var isDuty: Bool {
        guard let member else { return false }
        return roster.dutyID() == member.id
    }

    private func roleSymbol(_ role: MemberCard.Role) -> String {
        switch role {
        case .owner: return "crown"
        case .guest: return "person.badge.clock"
        case .member: return "person"
        }
    }

    /// 这位成员近 7 天每天的可证明归属开门次数（用于「这一周」卡的柱图）。
    ///
    /// 2026-11-05（用户指令：减少文字、图形化变多）：本页 645 字 / 图形 0。
    /// 这 7 个数来自与 weekSentence 同一份归属判定（owner == member.name），是真实序列。
    private func weekBars(_ member: MemberCard) -> (values: [Double], labels: String) {
        let cal = TimeFormat.calendar
        let today = cal.startOfDay(for: Date())
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        var values: [Double] = []
        var labels: [String] = []
        for offset in stride(from: 6, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let start = Int64(day.timeIntervalSince1970 * 1000)
            let end = start + 86_400_000
            let n = app.entries.filter {
                $0.owner == member.name && $0.at >= start && $0.at < end
                    && ($0.tone == .ok || $0.tone == .live)
            }.count
            values.append(Double(n))
            labels.append(names[cal.component(.weekday, from: day) - 1])
        }
        return (values, labels.joined(separator: "   "))
    }

    // MARK: - 卡 1 这一周

    private func weekCard(_ member: MemberCard) -> some View {
        // 2026-11-05（性能）：weekBars 内部要按天过滤 7 次 app.entries；
        // 在 ViewBuilder 里调用两次（labels + values）等于每帧 14 次过滤。
        // 只算一次，交给下面两个视图共用（swiftui-expert：把计算提到视图外，视图只读结果）。
        let bars = weekBars(member)
        return VCard2 {
            VCardHead(eyebrow: "这一周", statement: HHStats.weekSentence(member, entries: app.entries) ?? "还没有可证明归属的开门", trailing: "约")
            VDivider2()
                .padding(.top, V8.S.gapM)
            // 2026-11-05（对抗审查 · 设计冗余）：「锁端日志没有身份字段，只有归属明确的条目
            // 才会算进来」这句在本页出现两次 —— 这里一次，「最近开门」的空态又一次（措辞几乎相同）。
            // 那句话在「最近开门」的空态里更有用（那里正是用户看不到数据的地方），这里只留
            // 本卡特有的一句：这一页读的是本机数据、不连门锁。
            // 2026-11-05（用户指令：图形化变多）：本周每天的开锁次数画成柱图 ——
            // 与卡头那句「本周 N 次」是同一份数据，但形状比句子更快。
            // 同上：只保留星期标签，关掉 VSpark 自带的「最早 / 最近」。
            VStack(alignment: .leading, spacing: V8.S.gapS) {
                VRangeCaption(text: bars.labels)
                VSpark(values: bars.values, tint: V8.C.accentFill, cursor: 6, axis: nil)
                    // 2026-11-05（无障碍）：VSpark 自带的是笼统的「波形」，这里换成真实序列。
                    // 不能给整张卡加 combine —— 卡里还有可点的「去台账看全部记录」，会被吞掉。
                    .accessibilityLabel("近 7 天每天开门次数：" + bars.values.map { String(Int($0)) }.joined(separator: "、"))
            }
            .padding(.top, V8.S.gapM)
            Text("这一页只读本机数据，不连门锁 —— 离线或未连接时，档案与摘录完全一样。")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapXS)
                .fixedSize(horizontal: false, vertical: true)
            VNavRow(title: "去台账看全部记录", detail: "按 TA 筛一遍") {
                router.request(.dest(.records))
            }
            .padding(.top, V8.S.gapS)
        }
    }

    // MARK: - 卡 2 角色与权限

    private func roleCard(_ member: MemberCard) -> some View {
        VCard2 {
            VCardHead(eyebrow: "角色与权限", statement: "本机判据", trailing: "三档")
            VDivider2()
                .padding(.top, V8.S.gapM)
            HStack(spacing: V8.S.gapS) {
                ForEach(MemberCard.Role.allCases, id: \.self) { role in
                    roleChip(role, current: member.role)
                }
            }
            .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                ForEach(Array(HHPerm.rows.enumerated()), id: \.offset) { index, cap in
                    if index > 0 { VDotRule() }
                    permRow(cap, role: member.role)
                }
            }
            .padding(.top, V8.S.gapM)
            Text(HHPerm.scene(member.role))
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Text("矩阵管的是本机界面：锁端没有角色字段，这三档不改任何发往门锁的字节，备份包也不带角色。")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
            VDivider2()
                .padding(.top, V8.S.gapM)
            Toggle(isOn: Binding(
                get: { draft.emergencyAdmin },
                set: { v in
                    draft.emergencyAdmin = v
                    roster.update(member.id) { $0.emergencyAdmin = v }
                }
            )) {
                VStack(alignment: .leading, spacing: V8.S.gapXS) {
                    Text("紧急管理员")
                        .font(V8.T.value)
                        .foregroundStyle(V8.C.ink1)
                    Text(HHPerm.allows(member.role, "成员管理")
                         ? "把人点出来，免得只剩一个人管钥匙。"
                         : "角色是「" + member.role.rawValue + "」，矩阵里「成员管理」禁用 —— 先把角色改成管理员。")
                        .font(V8.T.caption)
                        .foregroundStyle(V8.C.ink4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minHeight: V8.H.min)
            .disabled(!HHPerm.allows(member.role, "成员管理"))
            .padding(.top, V8.S.gapS)
        }
    }

    private func roleChip(_ role: MemberCard.Role, current: MemberCard.Role) -> some View {
        let on = role == current
        return Button {
            setRole(role)
        } label: {
            HStack(spacing: V8.S.gapXS) {
                Image(systemName: roleSymbol(role))
                    .font(V8.T.caption)
                    .foregroundStyle(on ? V8.C.accent : V8.C.ink4)
                    .accessibilityHidden(true)
                Text(role.rawValue)
                    .font(V8.T.tab)
                    .foregroundStyle(on ? V8.C.ink1 : V8.C.ink3)
            }
            .padding(.horizontal, V8.S.gapM)
            .frame(minHeight: V8.H.min)
            .background(Capsule(style: .continuous).fill(on ? V8.C.accentTrack : V8.C.chipOff))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(on ? V8.C.accent : V8.C.line, lineWidth: V8.S.hair)
            )
        }
        .buttonStyle(V8PressStyle())
        .accessibilityLabel("角色 " + role.rawValue)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func permRow(_ cap: String, role: MemberCard.Role) -> some View {
        let allowed = HHPerm.allows(role, cap)
        return HStack(spacing: V8.S.gapM) {
            Text(cap)
                .font(V8.T.value)
                .foregroundStyle(V8.C.ink1)
            Spacer(minLength: V8.S.gapS)
            Image(systemName: allowed ? "checkmark.circle" : "xmark.circle")
                .font(V8.T.caption)
                .foregroundStyle(allowed ? V8.C.ok : V8.C.ink4)
                .accessibilityHidden(true)
            Text(allowed ? "允许" : "禁用")
                .font(V8.T.caption)
                .foregroundStyle(allowed ? V8.C.ok : V8.C.ink4)
        }
        .frame(minHeight: V8.S.rowHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cap + "，" + (allowed ? "允许" : "禁用"))
    }

    // MARK: - 卡 3 档案

    private func profileCard(_ member: MemberCard) -> some View {
        VCard2 {
            VCardHead(eyebrow: "档案", statement: saved ? "已保存" : "本机档案", trailing: "不上锁")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(alignment: .leading, spacing: V8.S.gapM) {
                fieldRow("与你的关系", text: $draft.relation, placeholder: "母亲 / 妹妹 / 钟点工")
                fieldRow("备注名", text: $draft.remark, placeholder: "记录条目显示「称呼（备注）」")
                fieldRow("分组标签", text: $draft.groupTag, placeholder: "家人 / 访客 / 服务人员")
                fieldRow("家庭便签", text: $draft.note, placeholder: "如：周六换锁芯")
                fieldRow("紧急联系", text: $draft.emergency, placeholder: "姓名 + 电话")
                fieldRow("电话（用于一键呼叫）", text: $phone, placeholder: "如 138 0000 0000")
            }
            .padding(.top, V8.S.gapM)
            if !phone.isEmpty {
                Button {
                    call()
                } label: {
                    HStack(spacing: V8.S.gapS) {
                        Image(systemName: "phone")
                            .font(V8.T.caption)
                            .foregroundStyle(V8.C.ink1)
                            .accessibilityHidden(true)
                        Text("呼叫 " + phone)
                            .font(V8.T.tab)
                            .foregroundStyle(V8.C.ink1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .overlay(
                        RoundedRectangle(cornerRadius: V8.R.capsule(V8.H.min), style: .continuous)
                            .strokeBorder(V8.C.line, lineWidth: V8.S.hair)
                    )
                }
                .buttonStyle(V8PressStyle())
                .disabled(phone.filter(\.isNumber).count < 3)
                .opacity(phone.filter(\.isNumber).count < 3 ? 0.45 : 1)
                .accessibilityLabel("一键呼叫 " + phone)
                .padding(.top, V8.S.gapM)
            }

            Text("emoji 代号")
                .font(V8.T.label)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapL)
            emojiRow(member)
                .padding(.top, V8.S.gapS)
            if app.trialGuard {
                Text("只读试验模式开着：本页只改本机档案，不下发到门锁，不受影响。")
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                save(member)
            } label: {
                Text(saved ? "档案已保存" : "保存档案")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.chipOn)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.accent))
            }
            .buttonStyle(V8PressStyle())
            .accessibilityLabel("保存成员档案")
            .padding(.top, V8.S.gapL)
        }
    }

    private func fieldRow(_ label: String, text: Binding<String>, placeholder: String) -> some View {
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

    private func emojiRow(_ member: MemberCard) -> some View {
        VHScroll {
            HStack(spacing: V8.S.gapS) {
                ForEach(Self.emojiOptions.indices, id: \.self) { index in
                    let e = Self.emojiOptions[index]
                    emojiCell(e, member: member)
                }
            }
        }
    }

    private func emojiCell(_ e: String, member: MemberCard) -> some View {
        let on = draft.emoji == e
        return Button {
            draft.emoji = e
            roster.update(member.id) { $0.emoji = e }
        } label: {
            Text(e.isEmpty ? "首字" : e)
                .font(e.isEmpty ? V8.T.caption : V8.T.body)
                .foregroundStyle(on ? V8.C.ink1 : V8.C.ink3)
                .frame(width: V8.S.gapXXL, height: V8.S.gapXXL)
                .background(on ? V8.C.accentTrack : V8.C.chipOff, in: Circle())
                .overlay(
                    Circle().strokeBorder(on ? V8.C.accent : V8.C.line, lineWidth: V8.S.hair)
                )
                .frame(minWidth: V8.H.min, minHeight: V8.H.min)
                .contentShape(Rectangle())
        }
        .buttonStyle(V8PressStyle())
        .accessibilityLabel(e.isEmpty ? "默认首字" : "代号 " + e)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private static let emojiOptions = ["", "🐻", "🐱", "🐸", "🐙", "🦊", "🐧", "🐯"]

    // MARK: - 卡 4 名下凭证

    private func keysCard(_ member: MemberCard) -> some View {
        let keys = memberKeys(member)
        return VCard2 {
            VCardHead(eyebrow: "名下凭证", statement: "归属可证明的 \(keys.count) 枚", trailing: "本机台账")
            VDivider2()
                .padding(.top, V8.S.gapM)
            if keys.isEmpty {
                Text("TA 名下还没有凭证。到「钥匙」页新建一枚，归属选 \(member.name)。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
                VNavRow(title: "去新建凭证", detail: "归属自动带这位成员") {
                    router.request(.dest(.keyCreate))
                }
                .padding(.top, V8.S.gapS)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(keys.enumerated()), id: \.element.id) { index, key in
                        if index > 0 { VDotRule() }
                        Button {
                            router.request(.key(id: key.id))
                        } label: {
                            VDataRow(
                                tag: key.kind.rawValue,
                                tagTint: key.disabled ? V8.C.ink4 : kindTint(key.kind),
                                title: key.name,
                                detail: key.disabled ? "已停用" : nil,
                                value: key.expiresAt.map { TimeFormat.dayShort($0) } ?? "",
                                interactive: true
                            )
                        }
                        .buttonStyle(V8PressStyle())
                        .accessibilityLabel(key.kind.rawValue + " " + key.name)
                    }
                }
                .padding(.top, V8.S.gapS)
            }
        }
    }

    private func memberKeys(_ member: MemberCard) -> [KeyItem] {
        app.keys.filter { CredentialOrg.ownerMatches($0.owner, memberID: member.id, memberName: member.name) }
    }

    private func kindTint(_ kind: KeyItem.Kind) -> Color {
        switch kind {
        case .password: return V8.D.password
        case .fingerprint: return V8.D.fingerprint
        case .temp: return V8.D.temp
        case .mobile: return V8.D.mobile
        }
    }

    // MARK: - 卡 5 最近开门

    private func excerptsCard(_ member: MemberCard) -> some View {
        let entries = Array(app.entries.filter { $0.owner == member.name }.prefix(5))
        return VCard2 {
            VCardHead(eyebrow: "最近开门", statement: entries.isEmpty ? "没有可证明归属的开门" : "\(entries.count) 条", trailing: "约")
            VDivider2()
                .padding(.top, V8.S.gapM)
            if entries.isEmpty {
                Text("台账里还没有可证明归属到 TA 的开门。锁端日志没有身份字段，只有归属明确的条目才会出现在这里。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
                VNavRow(title: "去台账按 TA 筛", detail: "记录页的成员筛选") {
                    router.request(.dest(.records))
                }
                .padding(.top, V8.S.gapS)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { VDotRule() }
                        VDataRow(
                            tag: TimeFormat.dayShort(entry.at),
                            tagTint: entry.tone == .critical ? V8.C.danger : V8.C.ink4,
                            title: entry.event,
                            detail: entry.owner,
                            value: TimeDisplay.clock(entry.at)
                        )
                    }
                }
                .padding(.top, V8.S.gapS)
            }
        }
    }

    // MARK: - 卡 6 家庭场景

    private func sceneCard(_ member: MemberCard) -> some View {
        VCard2 {
            // 2026-11-05（对抗审查 · 设计冗余）：本页原来有**两张都叫「家庭场景」**的卡 ——
            // 一张是本周主责开关，一张是可编辑的关怀/欢迎/便签。而且「便签」这个字段在两处都出现：
            // 这里只读显示 draft.note，下面那张卡改的是同一个 note —— 在一处改了、另一处还是旧值。
            // 名字与字段都收拢：这张只讲「本周主责」。
            VCardHead(eyebrow: "本周主责", statement: isDuty ? "本周的家里事归 TA" : "本周还没指派", trailing: "可改")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Toggle(isOn: Binding(
                get: { roster.dutyID() == member.id },
                set: { on in roster.setDuty(on ? member.id : nil) }
            )) {
                VStack(alignment: .leading, spacing: V8.S.gapXS) {
                    Text("本周主责")
                        .font(V8.T.value)
                        .foregroundStyle(V8.C.ink1)
                    Text(isDuty ? "本周的家里事归 TA。" : "把这一周的事指给 TA；下周可重新指。")
                        .font(V8.T.caption)
                        .foregroundStyle(V8.C.ink4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minHeight: V8.H.min)
            .padding(.top, V8.S.gapM)
        }
    }

    // MARK: - 卡 7 收尾（归档不删历史；删除的后果一次写清）

    private func closingCard(_ member: MemberCard) -> some View {
        VCard2 {
            VCardHead(eyebrow: "档案收尾", statement: member.archived ? "已归档 · 历史仍在" : "在册")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VNavRow(
                title: member.archived ? "恢复进名册" : "归档（保留历史）",
                detail: member.archived ? "回到成员名册" : "记录页仍能筛到 TA"
            ) {
                toggleArchive()
            }
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("归档只从名册与统计里收起，不删任何历史；删除会移走 TA 的档案并解除名下凭证的归属。")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            // 2026-11-05（全技能审核 · APK 对位 P0）：原版 Android 在删成员前要求先清空
            // 该成员名下的手机钥匙/指纹/密码；V8 迁移后允许直接删，锁端凭证仍能开门。
            // 这里恢复「先撤销、再删人」的硬闸：只要名下还有凭证，删除按钮禁用并说明原因。
            let blocked = deleteBlockedReason(member)
            if let blocked {
                Text(blocked)
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.warn)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                confirmDelete = true
            } label: {
                Text("删除成员")
                    .font(V8.T.tab)
                    .foregroundStyle(blocked == nil ? V8.C.danger : V8.C.ink4)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(blocked == nil ? V8.C.dangerTrack : V8.C.well))
            }
            .buttonStyle(V8PressStyle())
            .disabled(blocked != nil)
            .opacity(blocked == nil ? 1 : 0.55)
            .accessibilityLabel("删除成员")
            .accessibilityHint(blocked ?? "")
            .padding(.top, V8.S.gapM)
        }
        .v8Confirm(
            isPresented: $confirmDelete,
            title: "删除这位成员？",
            consequence: deleteConsequence(member),
            confirmTitle: "删除成员",
            isDestructive: true
        ) {
            remove(member)
        }
    }

    /// 删除成员前的硬闸：名下还有任何凭证时不允许删人。
    private func deleteBlockedReason(_ member: MemberCard) -> String? {
        let owned = memberKeys(member)
        guard !owned.isEmpty else { return nil }
        let pw = owned.filter { $0.kind == .password }.count
        let fp = owned.filter { $0.kind == .fingerprint }.count
        let temp = owned.filter { $0.kind == .temp }.count
        let mobile = owned.filter { $0.kind == .mobile }.count
        return "先处理 TA 名下的 " + String(owned.count) + " 枚凭证（密码 " + String(pw)
            + " / 指纹 " + String(fp) + " / 临时码 " + String(temp) + " / 手机钥匙 " + String(mobile)
            + "）：到凭证页逐条删除或转给其他成员。锁端凭证不撤销就删成员，TA 仍能开门。"
    }

    private func deleteConsequence(_ member: MemberCard) -> String {
        let owned = memberKeys(member)
        var parts: [String] = []
        if owned.isEmpty {
            parts.append("「" + member.name + "」名下没有台账凭证。")
        } else {
            let preview = owned.prefix(5).map { "· " + $0.kind.rawValue + " " + $0.name }.joined(separator: "\n")
            let more = owned.count > 5 ? "\n…" : ""
            parts.append("「" + member.name + "」名下 " + String(owned.count) + " 条台账凭证：\n" + preview + more)
        }
        let currentLock = DB.listPwds(app.currentMac).filter { CredentialOrg.ownerMatches($0.owner, memberID: member.id, memberName: member.name) }.count
            + DB.listFps(app.currentMac).filter { CredentialOrg.ownerMatches($0.owner, memberID: member.id, memberName: member.name) }.count
        if currentLock > 0 {
            parts.append("当前这把锁名下 " + String(currentLock) + " 枚凭证会先进入本机回收站（可整组还原）。")
        }
        parts.append("成员档案删除后不可恢复；名下凭证的归属会一并解除（凭证本身留在台账，变成未归属）。")
        parts.append("锁端的密码与指纹不会自动删除 —— 仍需本人到锁前手动删；指纹一旦在锁端删掉就无法远程补录。")
        return parts.joined(separator: "\n\n")
    }

    // MARK: - 同名合并

    private var mergeCard: some View {
        VCard2 {
            VCardHead(eyebrow: "重复档案", statement: "发现同名成员", trailing: "可合并")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("合并会保留这一位，把另一位名下的凭证归属迁过来后删除它。删除副档这一步没有撤销。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            VNavRow(title: "合并同名成员", detail: "执行前会再确认一次") {
                showMerge = true
            }
            .padding(.top, V8.S.gapS)
        }
    }

    // MARK: - 空壳

    private var decoyCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "成员档案", statement: "空壳模式只读")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("空壳模式（胁迫码进入）下，成员档案、名下凭证与开门摘录都不显示，也不写入 —— 否则一保存就会用空档案覆盖真实备注与关系。")
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

    // MARK: - 真动作（档案扩展写 kf_member_ext、本周主责写 kf_duty_week，都是真落盘）

    private func load() {
        guard !decoyed, let m = member else { return }
        if loadedID != m.id {
            draft = roster.extras(for: m.id)
            phone = DB.member(m.id)?.phone ?? ""
            loadedID = m.id
            saved = false
        }
    }

    private func setRole(_ role: MemberCard.Role) {
        guard !decoyed else { return }
        guard let m = member, let i = app.members.firstIndex(where: { $0.id == m.id }) else { return }
        app.members[i] = m.hh(role: role)
        roster.mirrorRole(m.id, role)
    }

    private func save(_ member: MemberCard) {
        guard !decoyed else { return }
        roster.update(member.id) { e in
            e.relation = draft.relation.trimmingCharacters(in: .whitespaces)
            e.remark = draft.remark.trimmingCharacters(in: .whitespaces)
            e.groupTag = draft.groupTag.trimmingCharacters(in: .whitespaces)
            e.note = draft.note.trimmingCharacters(in: .whitespaces)
            e.emergency = draft.emergency.trimmingCharacters(in: .whitespaces)
            e.emoji = draft.emoji
        }
        // 电话是 Engine Member 的独立字段（kf_members），不走 MemberExt。
        DB.setMemberInfo(member.id, ["phone": phone.trimmingCharacters(in: .whitespaces)])
        saved = true
    }

    /// 一键呼叫：清洗非数字，少于 3 位给出可修的原因。
    private func call() {
        let digits = phone.filter(\.isNumber)
        guard digits.count >= 3 else {
            callNote = "这个号码里没有足够数字（至少 3 位）—— 先在上面填完整，再点呼叫。"
            return
        }
        guard let url = URL(string: "tel://" + digits), UIApplication.shared.canOpenURL(url) else {
            callNote = "系统不接受这个号码（tel: 链接打不开）—— 检查一下是否含有非法字符。"
            return
        }
        callNote = nil
        UIApplication.shared.open(url)
    }

    private func toggleArchive() {
        guard !decoyed else { return }
        guard let m = member, let i = app.members.firstIndex(where: { $0.id == m.id }) else { return }
        let next = !m.archived
        app.members[i] = m.hh(archived: next)
        roster.mirrorArchived(m.id, next)
        AppToast.shared.show(next ? "已归档 · 历史仍在，记录页仍能筛到 TA" : "已恢复为在册成员", tone: .ok)
    }

    private func remove(_ member: MemberCard) {
        guard !decoyed else { return }
        // 02 §6.3：两套删除后果统一成 cascadeDelete（先入回收站再删档案）——
        // 与「成员流转」旧页同一条链路，这里只保留一套。回执与确认文案已经把「当前锁进回收站、
        // 其它锁只解除归属、锁端仍需线下删」写清（见 deleteConsequence）。
        let n = MemberOpsStore.cascadeDelete(mac: app.currentMac, memberID: member.id)
        app.members.removeAll { $0.id == member.id }
        // Engine 侧删除：DB.removeMember 会连带解除台账里这些凭证的归属（凭证本身保留）。
        DB.removeMember(member.id)
        for i in app.keys.indices where CredentialOrg.ownerMatches(app.keys[i].owner, memberID: member.id, memberName: member.name) {
            let k = app.keys[i]
            // createdAt 必须一起带过来：漏了它，解除归属会把「已使用 N 天」清零。
            app.keys[i] = KeyItem(id: k.id, kind: k.kind, name: k.name, owner: nil,
                                  code: k.code, expiresAt: k.expiresAt,
                                  createdAt: k.createdAt, disabled: k.disabled)
        }
        roster.forget(member.id)
        if roster.dutyID() == member.id { roster.setDuty(nil) }
        roster.focusMember = nil
        if n > 0 {
            AppToast.shared.show("已删除成员，\(n) 枚本机凭证进入回收站（锁端仍需线下删）", tone: .ok)
        }
        router.request(.tab(.household))
    }

    // MARK: - 流转段（原 memberOps 页整段并入 · 02 §3.4 #32）

    /// 原页的「处理谁」选人卡不再需要：这一段本来就挂在当前成员身上。
    /// 保留的能力：移交名下凭证 / 借用登记 / 家政窗 / 家庭场景便签 / 活跃度摘录 / 访客临时码归属 / 长辈模式。
    /// 删除卡不并入 —— 删除在本页「档案收尾」里已经有一套（见上方 closingCard 与 remove）。
    private func opsSection(_ member: MemberCard) -> some View {
        VStack(spacing: V8.S.gapCard) {
            transferCard(member)
            borrowCard(member)
            windowCard
            careSceneCard(member)
            activityCard(member)
            visitorCard
            elderCard
            if let opsOutcome {
                opsOutcomeCard
            }
        }
    }

    private var opsBorrowMap: [String: MemberBorrow] {
        _ = opsTick
        return MemberOpsStore.borrows(app.currentMac)
    }

    private var opsWindowList: [HouseWindow] {
        _ = opsTick
        return MemberOpsStore.windows(app.currentMac)
    }

    // MARK: 流转 · 移交

    private func transferCard(_ m: MemberCard) -> some View {
        VCard2 {
            VCardHead(eyebrow: "流转 · 移交名下凭证", statement: transferToMember.map { "给「" + $0.name + "」" } ?? "先选接收人")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("把「" + m.name + "」名下的密码与指纹改归属到另一位成员；台账条目本身不动。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            VHScroll {
                HStack(spacing: V8.S.gapS) {
                    ForEach(otherMembers(m)) { target in
                        transferChip(target)
                    }
                }
            }
            .padding(.top, V8.S.gapM)
            Button {
                let n = MemberOpsStore.transfer(mac: app.currentMac, from: m.id, to: transferTo)
                // 0 枚不是成功：台账里可能一条都没有归属到 TA，也可能是归属存的是旧口径的名字。
                if n > 0 {
                    opsOutcome = "已移交 " + String(n) + " 枚凭证"
                    opsOutcomeOK = true
                } else {
                    opsOutcome = "没有可移交的凭证 —— TA 名下这台锁上没有密码或指纹，或它们的归属还是旧口径的名字。"
                    opsOutcomeOK = false
                }
                opsTick += 1
                Task { await app.reload(refreshStatus: false) }
            } label: {
                Text("移交名下凭证")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.chipOn)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.accent))
            }
            .buttonStyle(V8PressStyle())
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

    private func otherMembers(_ m: MemberCard) -> [MemberCard] {
        app.members.filter { !$0.archived && $0.id != m.id }
    }

    private var transferToMember: MemberCard? { app.members.first { $0.id == transferTo } }

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
        .buttonStyle(V8PressStyle())
        .accessibilityLabel("移交给 " + target.name)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: 流转 · 借用

    private func borrowCard(_ m: MemberCard) -> some View {
        let map = opsBorrowMap
        return VCard2 {
            VCardHead(eyebrow: "流转 · 借用登记", statement: map[m.id].map { "借给 " + $0.by } ?? "未登记", trailing: map[m.id]?.due)
            VDivider2()
                .padding(.top, V8.S.gapM)
            if let b = map[m.id] {
                VDataRow(tag: "借给", tagTint: V8.C.ink4, title: b.by, value: "")
                    .padding(.top, V8.S.gapS)
                VDataRow(tag: "归还日", tagTint: V8.C.ink4, title: b.due, value: "")
                Button {
                    MemberOpsStore.removeBorrow(app.currentMac, memberID: m.id)
                    opsOutcome = "已结束借用"
                    opsOutcomeOK = true
                    opsTick += 1
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
                .buttonStyle(V8PressStyle())
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
                    MemberOpsStore.setBorrow(app.currentMac, memberID: m.id, by: borrowBy.isEmpty ? m.name : borrowBy, due: df.string(from: borrowDue))
                    opsOutcome = "已登记借用"
                    opsOutcomeOK = true
                    opsTick += 1
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
                .buttonStyle(V8PressStyle())
                .accessibilityLabel("登记借用")
                .padding(.top, V8.S.gapM)
            }
            Text("借用只记本机，不写门锁；归还日就显示在上面。")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 流转 · 家政窗

    private var windowCard: some View {
        let list = opsWindowList
        return VCard2 {
            VCardHead(eyebrow: "流转 · 家政窗", statement: list.isEmpty ? "没有固定时段" : "\(list.count) 个时段", trailing: "本机排期")
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
                        Text(Self.opsWeekdayNames[d]).tag(d)
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
                // 起 == 止 是空集：加进去也筛不出任何时段，先如实拒绝。
                if windowStart >= windowEnd {
                    opsOutcome = "开始时间要早于结束时间 —— 现在是 " + String(windowStart) + ":00 到 " + String(windowEnd) + ":00，这个时段是空的。"
                    opsOutcomeOK = false
                } else {
                    MemberOpsStore.addWindow(app.currentMac, HouseWindow(id: UUID().uuidString, weekday: windowWeekday,
                                                                      startHour: windowStart, endHour: windowEnd, note: ""))
                    opsOutcome = "已添加家政窗"
                    opsOutcomeOK = true
                    opsTick += 1
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
            .buttonStyle(V8PressStyle())
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
                            MemberOpsStore.removeWindow(app.currentMac, id: window.id)
                            opsTick += 1
                        } label: {
                            Text("删除")
                                .font(V8.T.caption)
                                .foregroundStyle(V8.C.danger)
                                .frame(minHeight: V8.H.min)
                        }
                        .buttonStyle(V8PressStyle())
                        .accessibilityLabel("删除 " + window.weekdayText + " 的时段")
                    }
                    .frame(minHeight: V8.H.min)
                }
            }
            .padding(.top, V8.S.gapS)
        }
    }

    private static let opsWeekdayNames = ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    // MARK: 流转 · 关怀便签（孩子/长辈提示 / 访客欢迎语 / 家庭便签）

    private func careSceneCard(_ m: MemberCard) -> some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "家庭场景", statement: "关怀 / 欢迎语 / 便签", trailing: "本机")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(alignment: .leading, spacing: V8.S.gapM) {
                opsFieldBlock("关怀便签（孩子 / 长辈看到的提示）", text: $careText, placeholder: "如 记得带伞")
                opsFieldBlock("访客欢迎语", text: $welcome, placeholder: "如 欢迎来家里做客")
                opsFieldBlock("家庭便签", text: $opsNote, placeholder: "如 周六换锁芯")
                Button {
                    roster.update(m.id) { e in
                        e.careText = careText
                        e.welcome = welcome
                        e.note = opsNote
                    }
                    opsOutcome = "已保存家庭场景"
                    opsOutcomeOK = true
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
                .buttonStyle(V8PressStyle())
                .accessibilityLabel("保存家庭场景")
            }
            .padding(.top, V8.S.gapM)
        }
    }

    private func opsFieldBlock(_ label: String, text: Binding<String>, placeholder: String) -> some View {
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

    // MARK: 流转 · 活跃度

    private func activityCard(_ m: MemberCard) -> some View {
        let bundle = MemberHub.activityBundle(app.members.filter { !$0.archived }.map(\.id))
        let a = bundle.table[m.id] ?? MemberHub.Activity()
        let excerpts = MemberHub.recentExcerpts(m.id, 5)
        return VCard2 {
            VCardHead(eyebrow: "流转 · 活跃度", statement: "近 30 天 " + String(a.opens30) + " 次", trailing: "约")
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

    // MARK: 流转 · 访客临时码归属

    private var visitorCard: some View {
        let mac = app.currentMac
        let temps = DB.listPwds(mac).filter { $0.temp && ($0.owner ?? "").isEmpty }
        return VCard2 {
            VCardHead(eyebrow: "流转 · 访客临时码", statement: "未归属 \(temps.count) 枚", trailing: "本机展示层")
            VDivider2()
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
                                ForEach(app.members.filter { !$0.archived }) { target in
                                    Button(target.name) {
                                        DB.setPwdOwner(mac, p.alias, target.id)
                                        opsOutcome = "已归属给 " + target.name
                                        opsOutcomeOK = true
                                        opsTick += 1
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

    // MARK: 流转 · 长辈模式

    private var elderCard: some View {
        VCard2 {
            VCardHead(eyebrow: "流转 · 长辈模式", statement: MemberHub.elderMode ? "已开启" : "未开启", trailing: "只影响凭证页")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Toggle(isOn: Binding(
                get: { MemberHub.elderMode },
                set: { on in
                    MemberHub.setElderMode(on)
                    opsTick += 1
                }
            )) {
                VStack(alignment: .leading, spacing: V8.S.gapXS) {
                    Text("开启长辈模式")
                        .font(V8.T.value)
                        .foregroundStyle(V8.C.ink1)
                    Text("凭证页只留全部 / 密码 / 指纹分段，隐藏批量与导出入口。只影响凭证页这一档；想让字更大，请到「外观」开大字档。")
                        .font(V8.T.caption)
                        .foregroundStyle(V8.C.ink4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minHeight: V8.H.min)
            .padding(.top, V8.S.gapM)
        }
    }

    private var opsOutcomeCard: some View {
        VCard2(style: .well) {
            Text(opsOutcome ?? "")
                .font(V8.T.footnote)
                .foregroundStyle(opsOutcomeOK ? V8.C.ok : V8.C.warn)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 流转段的字段随成员切换而重读（原页 onChange(of: memberID) 的等价物：focusMember 变了就重读）。
    private func loadOpsFields() {
        guard !decoyed, let m = member else { return }
        let ext = roster.extras(for: m.id)
        careText = ext.careText
        welcome = ext.welcome
        opsNote = ext.note
        transferTo = app.members.first(where: { !$0.archived && $0.id != m.id })?.id ?? ""
    }
}
