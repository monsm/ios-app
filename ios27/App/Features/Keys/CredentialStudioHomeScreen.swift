// CredentialStudioHomeScreen.swift —— 凭证工作室（批量 / 回收站 / 版本 / 预警 / 导出 / 检测 / 排序）（V8 设计语言）
//
// 与 CredentialStudioScreen + CredentialStudioParts 的能力对齐：台账读数、排序与分组、
// 单选/全选、批量延期（真下发）、批量移除（移入回收站）、前缀备注、移交归属、
// 凭证包导出/导入、弱口令与重复检测、回收站、版本历史、到期预警。
// 只改渲染层：落盘仍走 CredentialOrg.batchExtend / batchDisable / batchPrefixNote /
// exportPackage / importPackage / CredBinStore / CredHistoryStore / CredStarStore。
//
// 与旧页的刻意差异：
//   ① 空壳模式（DB.isDecoy）整页只读：不列任何凭证、不显示回收站与快照，也拒绝全部写入。
//   ② 只读试验模式（app.trialGuard）：本机台账可编辑；批量延期里的锁端下发会被护栏拦下，
//      结果按「本机已改 / 锁端失败」分开报（旧页已经有这条口径，这里补一句前置说明）。
//   ③ 批量移除与清空回收站都走 .v8Confirm，并写明可不可以撤销。
//
// 02 §3.2 归并：keyCalendar 降为「到期月历」段（calendarSection）。月历读 app.keys 的有限期投影，
// 与主表（DB.listPwds/listFps）数据源分开，是两个不同的口径 —— 卡头上写清楚。
import SwiftUI
import Foundation
import UIKit

struct CredentialStudioHomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    enum Sort: String, CaseIterable, Identifiable {
        case starred = "星标优先"
        case recent = "最近添加"
        case expiry = "最早到期"
        case alias = "编号"
        var id: String { rawValue }
    }

    @State private var selectedPwds: Set<Int> = []
    @State private var selectedFps: Set<Int> = []
    // 2026-11-05（对抗审查 · 持久化不一致）：同一张「整理方式」卡里，
    // **分组方式**（CredentialOrg.groupMode）是落盘的，**排序**却是纯 @State ——
    // 用户选了「最早到期」，退出再进来又回到「星标优先」。
    // 排序是用户刻意设的偏好，按同一条口径落盘。
    @State private var sort: Sort = Sort(rawValue: DB.store.getString("kf_studio_sort")) ?? .starred
    @State private var extendDays = 30
    @State private var prefixText = ""
    @State private var transferOwner: String?
    @State private var packagePassword = ""
    @State private var showPackageImport = false
    @State private var packageText = ""
    @State private var studioOutcome: String?
    @State private var studioOutcomeBad = false
    @State private var alertTarget: LedgerPwd?
    @State private var binOpen = false
    @State private var historyOpen = false
    @State private var confirmPurgeAll = false
    @State private var confirmRemove = false
    @State private var tick = 0
    // —— keyCalendar 并入段的状态（到期月历）
    @State private var monthAnchor = Date()
    @State private var pickedDay: String?

    private var decoyed: Bool { DB.isDecoy }
    private var studioMac: String { app.currentMac }

    private var pwdRows: [LedgerPwd] {
        let _ = tick
        let list = DB.listPwds(studioMac)
        let stars = CredStarStore.all(studioMac)
        let ordered: [LedgerPwd]
        switch sort {
        case .starred:
            ordered = list.sorted { lhs, rhs in
                let l = stars.contains("pwd:" + String(lhs.alias))
                let r = stars.contains("pwd:" + String(rhs.alias))
                if l != r { return l }
                return lhs.at > rhs.at
            }
        case .recent: ordered = list
        case .expiry: ordered = list.sorted { $0.to < $1.to }
        case .alias: ordered = list.sorted { $0.alias < $1.alias }
        }
        guard CredentialOrg.groupMode == .owner else { return ordered }
        return ordered.sorted { CredentialOrg.ownerName($0.owner) < CredentialOrg.ownerName($1.owner) }
    }

    private var fpRows: [LedgerFp] {
        let _ = tick
        return DB.listFps(studioMac)
    }

    private var totalSelected: Int { selectedPwds.count + selectedFps.count }

    private var judgement: String {
        if decoyed { return "空壳模式下不显示凭证台账" }
        if app.lock == nil { return "还没有门锁" }
        // 2026-11-05（截图审查 · 标题与芯片同义）：
        // 原来选中态写「已选 N 项」，而**紧贴标题上方**的芯片行里就有一枚
        // 「已选 · N 项」—— 同一屏同一个数，还是上下紧邻。
        // 按参考图的分工（标题叙述、卡片/芯片承载数字）改成指令，且不再重复数量。
        // 「台账 N 项」保留：删掉「台账读数」卡之后，总数只有这一处在说。
        if totalSelected > 0 { return "挑好了，接下来选动作" }
        return "台账 " + String(pwdRows.count + fpRows.count) + " 项"
    }

    private var lead: String? {
        if decoyed {
            return "空壳模式只隐藏数据，不改动数据。退出空壳后才能整理凭证台账。"
        }
        if app.lock == nil {
            return nil
        }
        // 2026-11-05（截图审查 · 设计冗余）：这段原来尾巴上还写着
        // 「排序：星标优先 · 分组：按类型」—— 而紧接其下的「整理方式」卡里，
        // 排序芯片的选中态就是「星标优先」，旁边按钮就写着「分组：按类型」。
        // 同一屏同一状态三处重复，且 lead 因此被撑到四行（HIG layout › Visual hierarchy：
        // 最重要的内容要靠近顶部）。lead 只留**别处看不到**的那条规则：批量动作先记本机。
        return "批量动作先在本机记账；锁端删除与延期按现有链路真下发，失败会如实回报。"
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            if !decoyed && app.lock != nil {
                chipRow
            }
        } content: {
            if decoyed {
                decoyCard
            } else if app.lock == nil {
                VEmpty(
                    title: "添加一把门锁",
                    reason: "凭证工作室整理的是某一把锁的凭证台账。先添加门锁，再回来。",
                    actionTitle: "添加门锁"
                ) { router.request(.dest(.addLock)) }
            } else {
                // 2026-11-05（对抗审查 · 设计冗余）：这里原来还有一张「台账读数」卡，
                // 四个数字（密码 / 指纹 / 已选 / 回收站）**每一个都在别处已经显示**：
                //   · 密码、指纹 —— 各自的列表卡标题就是「N 枚」；
                //   · 回收站 —— 「回收站」卡标题「N 项」；
                //   · 已选 —— 顶部芯片行有「已选 N 项」，判断句也写「已选 N 项」。
                // 一张卡把四件事各说第二遍，整张删掉。
                toolsCard
                selectionCard
                batchCard
                deliveryCard
                auditCard
                calendarSection
                binCard
                historyCard
                if let studioOutcome {
                    VCard2(style: .well) {
                        Text(studioOutcome)
                            .font(V8.T.footnote)
                            .foregroundStyle(studioOutcomeBad ? V8.C.danger : V8.C.ok)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if app.trialGuard {
                    trialCard
                }
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { tick += 1 }
        .sheet(item: $alertTarget) { pwd in
            CredAlertSheet2(mac: studioMac, pwd: pwd)
        }
        .sheet(isPresented: $showPackageImport) {
            CredentialImportSheet(mac: studioMac) {
                tick += 1
                studioOutcomeBad = false
                studioOutcome = "凭证包已导入（冲突项已跳过）"
            }
        }
        .sheet(isPresented: $binOpen) {
            CredBinSheet2(mac: studioMac) { tick += 1 }
        }
        .sheet(isPresented: $historyOpen) {
            CredHistorySheet2(mac: studioMac) { tick += 1 }
        }
        .v8Confirm(
            isPresented: $confirmPurgeAll,
            title: "清空回收站？",
            consequence: purgeAllConsequence,
            confirmTitle: "彻底删除"
        ) {
            CredBinStore.clear(studioMac)
            tick += 1
        }
        .v8Confirm(
            isPresented: $confirmRemove,
            title: "把所选凭证移出台账？",
            consequence: "所选条目会移入回收站，可整组还原；锁端凭证不会自动删除，仍能开门。要真正作废请用回收站里的「彻底删除」。",
            confirmTitle: "移入回收站"
        ) {
            batchDisable()
        }
    }

    private var purgeAllConsequence: String {
        "回收站里的 " + String(CredBinStore.all(studioMac).count) + " 条会被永久删除：连同它们在钥匙串里的口令副本、以及星标/停用位/预警提前量等派生设置一并清掉，不能恢复。锁端凭证不受影响。"
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: V8.S.gapChip) {
                VChip2(icon: .ring(Double(pwdRows.count) / Double(max(1, pwdRows.count + fpRows.count)), V8.D.password), label: "密码", value: String(pwdRows.count) + " 枚")
                VChip2(icon: .ring(Double(fpRows.count) / Double(max(1, pwdRows.count + fpRows.count)), V8.D.fingerprint), label: "指纹", value: String(fpRows.count) + " 枚")
                VChip2(icon: .glyph("checkmark.circle.fill"), label: "已选", value: String(totalSelected) + " 项")
                VChip2(icon: .glyph("trash"), label: "回收站", value: String(binCount) + " 项")
            }
            .padding(.leading, V8.S.gutterCard)
            .padding(.trailing, V8.S.gutterCard)
        }
        .scrollClipDisabled()
    }

    // MARK: - 到期月历（原 keyCalendar 页并入）

    /// 02 §3.2：keyCalendar 降为凭证库的「到期月历」段。月历只画有限期的凭证（app.keys）——
    /// 与工作室主表（DB.listPwds/listFps）的数据源刻意分开：主表按锁的台账，月历按全锁投影。
    private var calendar: Calendar { TimeFormat.calendar }

    private var calendarYear: Int { calendar.component(.year, from: monthAnchor) }
    private var calendarMonth: Int { calendar.component(.month, from: monthAnchor) }
    private var calendarDayCount: Int { calendar.range(of: .day, in: .month, for: monthAnchor)?.count ?? 30 }

    private var calendarLeadingBlanks: Int {
        guard let first = calendar.date(from: DateComponents(year: calendarYear, month: calendarMonth, day: 1)) else { return 0 }
        return calendar.component(.weekday, from: first) - 1
    }

    private var calendarMonthPrefix: String { String(format: "%04d-%02d", calendarYear, calendarMonth) }

    private var deadlines: [String: [KeyItem]] {
        var buckets: [String: [KeyItem]] = [:]
        for key in app.keys {
            guard let expiresAt = key.expiresAt else { continue }
            let dayKey = TimeFormat.dayKey(expiresAt)
            guard dayKey.hasPrefix(calendarMonthPrefix) else { continue }
            buckets[dayKey, default: []].append(key)
        }
        return buckets
    }

    private var monthTotal: Int { deadlines.values.reduce(0) { $0 + $1.count } }
    private var pickedItems: [KeyItem] { deadlines[pickedDay ?? ""] ?? [] }

    private var hasAnyExpiry: Bool { app.keys.contains { $0.expiresAt != nil } }

    @ViewBuilder
    private var calendarSection: some View {
        if !hasAnyExpiry {
            VEmpty(
                title: "还没有有限期的凭证",
                reason: "月历只画有限期的东西。给保洁发一张 7 天临时码，或把某枚密码设成有到期日，这里就会有格子亮起来。",
                actionTitle: "新增凭证"
            ) { router.request(.dest(.keyCreate)) }
        } else {
            calendarCard
            if pickedDay != nil {
                calendarDayCard
            }
        }
    }

    private var calendarCard: some View {
        VCard2 {
            VCardHead(eyebrow: "到期月历", statement: monthTotal > 0 ? "\(calendarYear) 年 \(calendarMonth) 月 · \(monthTotal) 条到期" : "\(calendarYear) 年 \(calendarMonth) 月 · 这个月没有凭证到期", trailing: "点格子看当天")
            VDivider2()
                .padding(.top, V8.S.gapM)
            HStack(spacing: V8.S.gapS) {
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(V8.T.chipValue)
                        .foregroundStyle(V8.C.ink1)
                        .frame(width: V8.H.min, height: V8.H.min)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("上一个月")
                Spacer(minLength: 0)
                Text(String(format: "%04d-%02d", calendarYear, calendarMonth))
                    .font(V8.T.value)
                    .foregroundStyle(V8.C.ink1)
                    .monospacedDigit()
                Spacer(minLength: 0)
                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(V8.T.chipValue)
                        .foregroundStyle(V8.C.ink1)
                        .frame(width: V8.H.min, height: V8.H.min)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("下一个月")
            }
            .padding(.top, V8.S.gapM)
            HStack(spacing: V8.S.gapXS) {
                ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { word in
                    Text(word)
                        .font(V8.T.micro)
                        .foregroundStyle(V8.C.ink4)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, V8.S.gapM)
            .accessibilityHidden(true)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: V8.S.gapXS), count: 7),
                      spacing: V8.S.gapXS) {
                ForEach(0 ..< calendarLeadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: V8.H.min)
                }
                ForEach(1 ... calendarDayCount, id: \.self) { day in
                    calendarDayCell(day)
                }
            }
            .padding(.top, V8.S.gapS)
        }
    }

    private func calendarDayCell(_ day: Int) -> some View {
        let dayKey = calendarMonthPrefix + "-" + String(format: "%02d", day)
        let count = deadlines[dayKey]?.count ?? 0
        let selected = pickedDay == dayKey
        return Button {
            pickedDay = selected ? nil : dayKey
        } label: {
            VStack(spacing: V8.S.gapXS / 2) {
                Text("\(day)")
                    .font(V8.T.caption)
                    .foregroundStyle(selected ? V8.C.ink1 : V8.C.ink3)
                    .monospacedDigit()
                if count > 0 {
                    Text("\(count)")
                        .font(V8.T.micro)
                        .foregroundStyle(selected ? V8.C.ink1 : V8.C.warn)
                        .monospacedDigit()
                } else {
                    Color.clear.frame(height: V8.S.gapM)
                }
            }
            .frame(maxWidth: .infinity, minHeight: V8.H.min)
            .background(
                RoundedRectangle(cornerRadius: V8.R.inset, style: .continuous)
                    .fill(selected ? V8.C.chipOff : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(calendarMonth) 月 \(day) 日" + (count > 0 ? "，\(count) 条到期" : ""))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var calendarDayCard: some View {
        VCard2 {
            VCardHead(eyebrow: "当天清单", statement: "\(pickedItems.count) 条到期",
                      trailing: pickedDay)
            VDivider2()
                .padding(.top, V8.S.gapM)
            if pickedItems.isEmpty {
                Text("这一天没有到期的凭证。点别的有数字的格子看看。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(pickedItems) { key in
                        Button {
                            KeysRoute.openDetail(key.id, router: router)
                        } label: {
                            VDataRow(tag: key.kind.rawValue, tagTint: calendarKindTint(key.kind), title: key.name,
                                     detail: CredentialOrg.ownerName(key.owner),
                                     value: KeysState.word(key, now: KeysState.now()))
                        }
                        .buttonStyle(.plain)
                        if key.id != pickedItems.last?.id { VDotRule() }
                    }
                }
                .padding(.top, V8.S.gapS)
            }
        }
    }

    private func calendarKindTint(_ kind: KeyItem.Kind) -> Color {
        switch kind {
        case .password: return V8.D.password
        case .fingerprint: return V8.D.fingerprint
        case .temp: return V8.D.temp
        case .mobile: return V8.D.mobile
        }
    }

    private func shiftMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: monthAnchor) {
            monthAnchor = next
            pickedDay = nil
        }
    }

    private var binCount: Int {
        let _ = tick
        return CredBinStore.all(studioMac).count
    }

    private var historyCount: Int {
        let _ = tick
        return CredHistoryStore.all(studioMac).count
    }

    // MARK: - 卡 2 整理方式

    private var toolsCard: some View {
        VCard2 {
            VCardHead(eyebrow: "整理方式", statement: "排序 / 分组 / 快照")
            VDivider2()
                .padding(.top, V8.S.gapM)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: V8.S.gapChip) {
                    ForEach(Sort.allCases) { option in
                        sortChip(option)
                    }
                }
            }
            .padding(.top, V8.S.gapM)
            HStack(spacing: V8.S.gapChip) {
                Button {
                    CredentialOrg.setGroupMode(CredentialOrg.groupMode == .owner ? .type : .owner)
                    tick += 1
                } label: {
                    Text(CredentialOrg.groupMode == .owner ? "分组：按成员" : "分组：按类型")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.ink1)
                        .padding(.horizontal, V8.S.gapM)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.chipOff))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("切换分组方式")
                Button {
                    saveSnapshot()
                } label: {
                    Text("保存版本快照")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.ink1)
                        .padding(.horizontal, V8.S.gapM)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.chipOff))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("保存版本快照")
                Spacer(minLength: 0)
            }
            .padding(.top, V8.S.gapS)
        }
    }

    private func sortChip(_ option: Sort) -> some View {
        let on = sort == option
        return Button {
            sort = option
            DB.store.set("kf_studio_sort", option.rawValue)
        } label: {
            Text(option.rawValue)
                .font(V8.T.tab)
                .foregroundStyle(on ? V8.C.chipOn : V8.C.ink1)
                .padding(.horizontal, V8.S.gapM)
                .frame(minHeight: V8.H.min)
                .background(Capsule(style: .continuous).fill(on ? V8.C.accent : V8.C.chipOff))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.rawValue)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func saveSnapshot() {
        guard !DB.isDecoy else {
            studioOutcomeBad = true
            studioOutcome = DecoyCopy.blocked("写版本快照")
            return
        }
        CredHistoryStore.capture(studioMac, note: "手动快照")
        studioOutcomeBad = false
        studioOutcome = "已保存当前台账快照"
        tick += 1
    }

    // MARK: - 卡 3 选择列表

    private var selectionCard: some View {
        VCard2 {
            HStack(spacing: V8.S.gapS) {
                VCardHead(eyebrow: "密码", statement: String(pwdRows.count) + " 枚")
                Spacer(minLength: 0)
                Button(selectedPwds.count == pwdRows.count && !pwdRows.isEmpty ? "取消全选" : "全选") {
                    selectedPwds = (selectedPwds.count == pwdRows.count && !pwdRows.isEmpty) ? [] : Set(pwdRows.map(\.alias))
                }
                .font(V8.T.caption)
                .foregroundStyle(V8.C.accent)
                .frame(minHeight: V8.H.min)
                .accessibilityLabel("全选密码")
            }
            VDivider2()
                .padding(.top, V8.S.gapM)
            if pwdRows.isEmpty {
                Text("还没有密码凭证。去「新增凭证」加一枚。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(pwdRows) { pwd in
                        pwdRow(pwd)
                        if pwd.id != pwdRows.last?.id { VDotRule() }
                    }
                }
                .padding(.top, V8.S.gapS)
            }
            VDivider2()
                .padding(.top, V8.S.gapL)
            HStack(spacing: V8.S.gapS) {
                VCardHead(eyebrow: "指纹", statement: String(fpRows.count) + " 枚")
                Spacer(minLength: 0)
                Button(selectedFps.count == fpRows.count && !fpRows.isEmpty ? "取消全选" : "全选") {
                    selectedFps = (selectedFps.count == fpRows.count && !fpRows.isEmpty) ? [] : Set(fpRows.map(\.batch))
                }
                .font(V8.T.caption)
                .foregroundStyle(V8.C.accent)
                .frame(minHeight: V8.H.min)
                .accessibilityLabel("全选指纹")
            }
            .padding(.top, V8.S.gapL)
            if fpRows.isEmpty {
                Text("还没有指纹。指纹要在门锁上按 8 次录入。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(fpRows) { fp in
                        fpRow(fp)
                        if fp.id != fpRows.last?.id { VDotRule() }
                    }
                }
                .padding(.top, V8.S.gapS)
            }
        }
    }

    private func pwdRow(_ pwd: LedgerPwd) -> some View {
        let id = "pwd:" + String(pwd.alias)
        let selected = selectedPwds.contains(pwd.alias)
        let starred = CredStarStore.isStarred(studioMac, id)
        return HStack(spacing: V8.S.gapS) {
            Button {
                if selected { selectedPwds.remove(pwd.alias) } else { selectedPwds.insert(pwd.alias) }
            } label: {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(V8.T.chipValue)
                    .foregroundStyle(selected ? V8.C.accent : V8.C.ink4)
                    .frame(minWidth: V8.H.min, minHeight: V8.H.min)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(selected ? "取消选择" : "选择")
            VStack(alignment: .leading, spacing: V8.S.gapXS) {
                HStack(spacing: V8.S.gapXS) {
                    Text(CredentialOrg.displayPwd(pwd))
                        .font(V8.T.value)
                        .foregroundStyle(V8.C.ink1)
                        .lineLimit(1)
                    if starred {
                        Image(systemName: "star.fill")
                            .font(V8.T.micro)
                            .foregroundStyle(V8.C.warn)
                            .accessibilityLabel("已星标")
                    }
                }
                Text("#" + String(pwd.alias) + " · " + CredentialOrg.expiryLabel(pwd.to) + " · " + CredentialOrg.stateLabel(CredentialOrg.pwdState(pwd)))
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
                    .lineLimit(1)
            }
            Spacer(minLength: V8.S.gapS)
            Button {
                toggleStar(id)
            } label: {
                Image(systemName: starred ? "star.fill" : "star")
                    .font(V8.T.chipValue)
                    .foregroundStyle(starred ? V8.C.warn : V8.C.ink4)
                    .frame(minWidth: V8.H.min, minHeight: V8.H.min)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(starred ? "取消星标" : "设为星标")
            Button("提醒") { alertTarget = pwd }
                .font(V8.T.caption)
                .foregroundStyle(V8.C.accent)
                .frame(minHeight: V8.H.min)
                .accessibilityLabel("设置到期预警")
        }
        .frame(minHeight: V8.H.min)
    }

    private func toggleStar(_ id: String) {
        guard !DB.isDecoy else {
            studioOutcomeBad = true
            studioOutcome = DecoyCopy.blocked("改星标")
            return
        }
        CredStarStore.toggle(studioMac, id)
        tick += 1
    }

    private func fpRow(_ fp: LedgerFp) -> some View {
        let selected = selectedFps.contains(fp.batch)
        return HStack(spacing: V8.S.gapS) {
            Button {
                if selected { selectedFps.remove(fp.batch) } else { selectedFps.insert(fp.batch) }
            } label: {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(V8.T.chipValue)
                    .foregroundStyle(selected ? V8.C.accent : V8.C.ink4)
                    .frame(minWidth: V8.H.min, minHeight: V8.H.min)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(selected ? "取消选择" : "选择")
            VStack(alignment: .leading, spacing: V8.S.gapXS) {
                Text(fp.name.isEmpty ? "指纹 " + String(fp.batch) : fp.name)
                    .font(V8.T.value)
                    .foregroundStyle(V8.C.ink1)
                    .lineLimit(1)
                Text(fpMeta(fp))
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
                    .lineLimit(1)
            }
            Spacer(minLength: V8.S.gapS)
            if fp.isAlarm == true {
                Text("防拆")
                    .font(V8.T.micro)
                    .foregroundStyle(V8.C.danger)
                    .padding(.horizontal, V8.S.gapS)
                    .frame(minHeight: V8.H.min)
            }
        }
        .frame(minHeight: V8.H.min)
    }

    private func fpMeta(_ fp: LedgerFp) -> String {
        let who = CredentialOrg.ownerName(fp.owner)
        return who.isEmpty ? "指纹 #" + String(fp.batch) : "#" + String(fp.batch) + " · " + who
    }

    // MARK: - 卡 4 批量动作

    private var batchCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "批量动作", statement: "先选条目再应用")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("批量延期（" + String(selectedPwds.count) + " 条密码）")
                .font(V8.T.label)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
            HStack(spacing: V8.S.gapChip) {
                ForEach([7, 30, 90, 180], id: \.self) { days in
                    Button {
                        extendDays = days
                    } label: {
                        Text(String(days) + " 天")
                            .font(V8.T.tab)
                            .foregroundStyle(extendDays == days ? V8.C.chipOn : V8.C.ink1)
                            .padding(.horizontal, V8.S.gapM)
                            .frame(minHeight: V8.H.min)
                            .background(Capsule(style: .continuous).fill(extendDays == days ? V8.C.accent : V8.C.chipOff))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("延期 " + String(days) + " 天")
                    .accessibilityAddTraits(extendDays == days ? [.isButton, .isSelected] : .isButton)
                }
                Spacer(minLength: 0)
            }
            Button {
                batchExtend()
            } label: {
                Text("应用批量延期")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.chipOn)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.accent))
            }
            .buttonStyle(.plain)
            .disabled(selectedPwds.isEmpty)
            .opacity(selectedPwds.isEmpty ? 0.45 : 1)
            .padding(.top, V8.S.gapS)
            VDivider2()
                .padding(.top, V8.S.gapL)
            Text("批量移除：所选条目会从台账移入回收站（可整组还原）；锁端凭证不会自动删除，仍能开门。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapFootnote)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                confirmRemove = true
            } label: {
                Text("移除所选（" + String(totalSelected) + " 项）")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.danger)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.dangerTrack))
            }
            .buttonStyle(.plain)
            .disabled(totalSelected == 0)
            .opacity(totalSelected == 0 ? 0.45 : 1)
            .padding(.top, V8.S.gapS)
            VDivider2()
                .padding(.top, V8.S.gapL)
            Text("前缀备注（加到所选凭证备注前）")
                .font(V8.T.label)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
            TextField("如「2026 春节 · 」", text: $prefixText)
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink1)
                .frame(minHeight: V8.H.min)
                .padding(.horizontal, V8.S.gapM)
                .background(V8.C.card, in: .rect(cornerRadius: V8.R.inset))
                .padding(.top, V8.S.gapS)
            Button {
                applyPrefix()
            } label: {
                Text("应用前缀备注")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.ink1)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.chipOff))
            }
            .buttonStyle(.plain)
            .disabled(prefixText.isEmpty || totalSelected == 0)
            .opacity((prefixText.isEmpty || totalSelected == 0) ? 0.45 : 1)
            .padding(.top, V8.S.gapS)
        }
    }

    // MARK: - 卡 5 移交与凭证包

    private var deliveryCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "移交与凭证包", statement: transferOwnerName)
            VDivider2()
                .padding(.top, V8.S.gapM)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: V8.S.gapChip) {
                    ForEach(MemberHub.sortedForPicker(app.members.filter { !$0.archived }, keys: app.keys)) { member in
                        transferChip(member)
                    }
                    Button {
                        transferOwner = nil
                    } label: {
                        Text("解除归属")
                            .font(V8.T.tab)
                            .foregroundStyle(V8.C.ink1)
                            .padding(.horizontal, V8.S.gapM)
                            .frame(minHeight: V8.H.min)
                            .background(Capsule(style: .continuous).fill(V8.C.chipOff))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("解除归属")
                }
            }
            .padding(.top, V8.S.gapM)
            Button {
                applyTransfer()
            } label: {
                Text("应用移交")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.ink1)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.chipOff))
            }
            .buttonStyle(.plain)
            .disabled(totalSelected == 0)
            .opacity(totalSelected == 0 ? 0.45 : 1)
            .padding(.top, V8.S.gapS)
            VDivider2()
                .padding(.top, V8.S.gapL)
            Text("凭证包导出（加密）")
                .font(V8.T.label)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
            TextField("包口令（至少 8 位）", text: $packagePassword)
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink1)
                .frame(minHeight: V8.H.min)
                .padding(.horizontal, V8.S.gapM)
                .background(V8.C.card, in: .rect(cornerRadius: V8.R.inset))
                .autocorrectionDisabled()
                .padding(.top, V8.S.gapS)
            Button {
                exportPackage()
            } label: {
                Text("导出所选凭证包")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.ink1)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.chipOff))
            }
            .buttonStyle(.plain)
            .disabled(packagePassword.count < 8 || totalSelected == 0)
            .opacity((packagePassword.count < 8 || totalSelected == 0) ? 0.45 : 1)
            .padding(.top, V8.S.gapS)
            if !packageText.isEmpty {
                VDataRow(tag: "凭证包", tagTint: V8.C.ink4, title: String(packageText.count) + " 字符", value: "")
                    .padding(.top, V8.S.gapS)
                Button {
                    Clip.set(packageText)
                } label: {
                    Text("复制凭证包")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.ink1)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.chipOff))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("复制凭证包")
                .padding(.top, V8.S.gapS)
            }
            VDivider2()
                .padding(.top, V8.S.gapL)
            Button {
                showPackageImport = true
            } label: {
                Text("从凭证包导入…")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.ink1)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.chipOff))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("从凭证包导入")
            .padding(.top, V8.S.gapM)
        }
    }

    private var transferOwnerName: String {
        guard let transferOwner else { return "移交给：未选择" }
        return "移交给：" + (DB.member(transferOwner)?.name ?? "已删除的成员")
    }

    private func transferChip(_ member: MemberCard) -> some View {
        let on = transferOwner == member.id
        return Button {
            transferOwner = member.id
        } label: {
            Text(member.name)
                .font(V8.T.tab)
                .foregroundStyle(on ? V8.C.chipOn : V8.C.ink1)
                .padding(.horizontal, V8.S.gapM)
                .frame(minHeight: V8.H.min)
                .background(Capsule(style: .continuous).fill(on ? V8.C.accent : V8.C.chipOff))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("移交给 " + member.name)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - 卡 6 弱口令 / 重复检测

    private var auditCard: some View {
        let weak = pwdRows.filter { CredentialOrg.weakReason($0.pwd ?? "") != nil }
        let duplicates = duplicateGroups
        return VCard2 {
            VCardHead(eyebrow: "弱口令 / 重复检测", statement: weak.isEmpty && duplicates.isEmpty ? "没有发现问题" : "有需要处理的项")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStatPair2(items: [
                .init(label: "弱口令", value: String(weak.count), unit: "条"),
                .init(label: "重复组", value: String(duplicates.count), unit: "组")
            ])
            .padding(.top, V8.S.gapM)
            if !weak.isEmpty {
                Text("弱口令：" + weak.map { "#" + String($0.alias) }.joined(separator: "、"))
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.danger)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !duplicates.isEmpty {
                Text("重复串：" + duplicates.map { $0.joined(separator: "/") }.joined(separator: " · "))
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.danger)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if weak.isEmpty && duplicates.isEmpty {
                Text("没有发现弱口令或重复密码。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("判据：少于 6 位 / 全部同一位 / 连续递增递减算弱；同一串数字在同锁或其它锁重复出现会列出。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapFootnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var duplicateGroups: [[String]] {
        var byValue: [String: [Int]] = [:]
        for p in pwdRows {
            guard let v = p.pwd, !v.isEmpty else { continue }
            byValue[v, default: []].append(p.alias)
        }
        return byValue.values.filter { $0.count > 1 }.map { $0.map { "#" + String($0) } }
    }

    // MARK: - 卡 7 回收站

    private var binCard: some View {
        VCard2 {
            VCardHead(eyebrow: "回收站", statement: String(binCount) + " 项", trailing: "可整组还原")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("停用或批量删除的凭证在这里，可整组还原或彻底删除。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapFootnote)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: V8.S.gapChip) {
                Button {
                    binOpen = true
                } label: {
                    Text("打开回收站")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.ink1)
                        .padding(.horizontal, V8.S.gapM)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.chipOff))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开回收站")
                Button {
                    confirmPurgeAll = true
                } label: {
                    Text("清空")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.danger)
                        .padding(.horizontal, V8.S.gapM)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.dangerTrack))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空回收站")
                Spacer(minLength: 0)
            }
            .padding(.top, V8.S.gapS)
        }
    }

    // MARK: - 卡 8 版本历史

    private var historyCard: some View {
        VCard2 {
            VCardHead(eyebrow: "版本历史", statement: String(historyCount) + " 份", trailing: "最多保留 10 份")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("每次「保存版本快照」留一档。恢复会先自动备份当前状态。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapFootnote)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                historyOpen = true
            } label: {
                Text("打开版本历史")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.ink1)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.chipOff))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开版本历史")
            .padding(.top, V8.S.gapS)
        }
    }

    // MARK: - 空壳 / 只读试验

    private var decoyCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "凭证工作室", statement: "空壳模式只读")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("空壳模式（胁迫码进入）下，凭证台账、回收站与版本快照都不显示，也不允许任何写入或导出。")
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Text("退出空壳请在本机密码界面输入正常密码。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var trialCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "只读试验模式", statement: "写入类命令已停用")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("只读试验模式只拦「往门锁写」的命令：批量延期的本机台账会改，但下发到锁会被护栏拦下，结果会按「锁端失败」如实报出。批量移除、前缀备注、移交、导出、快照都只改本机，仍可用。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapFootnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 动作

    private func batchExtend() {
        guard !DB.isDecoy else {
            studioOutcomeBad = true
            studioOutcome = DecoyCopy.blocked("改台账")
            return
        }
        guard !selectedPwds.isEmpty else { return }
        let df = DF.cached("yyyy-MM-dd HH:mm")
        let from = df.string(from: Date())
        let to = df.string(from: Date().addingTimeInterval(Double(extendDays) * 86400))
        let r = CredentialOrg.batchExtend(studioMac, Array(selectedPwds), from, to)
        Task {
            var ok = 0
            var remoteFailed = 0
            for alias in r.done {
                if case .success = await app.setPasswordExpiry(alias: alias, from: from, to: to) { ok += 1 }
                else { remoteFailed += 1 }
            }
            var msg = "已延期 " + String(ok) + " 条"
            if r.failed.count > 0 {
                msg += "；本机找不到 " + String(r.failed.count) + " 条（编号 " + r.failed.map { String($0) }.joined(separator: "/") + "）"
            }
            if remoteFailed > 0 {
                msg += "；下发到锁失败 " + String(remoteFailed) + " 条（本机已改，锁端仍是旧有效期，请重试）"
            }
            studioOutcomeBad = r.failed.count > 0 || remoteFailed > 0
            studioOutcome = msg
            tick += 1
        }
    }

    private func batchDisable() {
        guard !DB.isDecoy else {
            studioOutcomeBad = true
            studioOutcome = DecoyCopy.blocked("改台账")
            return
        }
        let pwdList = pwdRows.filter { selectedPwds.contains($0.alias) }
        let fpList = fpRows.filter { selectedFps.contains($0.batch) }
        let batchId = UUID().uuidString
        CredBinStore.addPwds(studioMac, pwdList, batchId: batchId, source: "批量停用")
        CredBinStore.addFps(studioMac, fpList, batchId: batchId, source: "批量停用")
        let r = CredentialOrg.batchDisable(studioMac, pwdAliases: Array(selectedPwds), fpBatches: Array(selectedFps))
        selectedPwds = []
        selectedFps = []
        studioOutcomeBad = r.failedPwds.count + r.failedFps.count > 0
        studioOutcome = "已停用 " + String(r.done) + " 项并移入回收站（失败 " + String(r.failedPwds.count + r.failedFps.count) + " 项）"
        tick += 1
    }

    private func applyPrefix() {
        guard !DB.isDecoy else {
            studioOutcomeBad = true
            studioOutcome = DecoyCopy.blocked("改台账")
            return
        }
        let p = prefixText.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else {
            studioOutcomeBad = true
            studioOutcome = "先填一个前缀再应用（例如「备用·」）"
            return
        }
        guard !selectedPwds.isEmpty || !selectedFps.isEmpty else {
            studioOutcomeBad = true
            studioOutcome = "先勾选要加备注的凭证"
            return
        }
        let r = CredentialOrg.batchPrefixNote(studioMac, pwdAliases: Array(selectedPwds), fpBatches: Array(selectedFps), prefix: p)
        studioOutcomeBad = r == 0
        studioOutcome = r == 0 ? "所选凭证本来就是这个前缀，没有改动" : "已给 " + String(r) + " 条凭证加前缀备注"
        tick += 1
    }

    private func applyTransfer() {
        guard !DB.isDecoy else {
            studioOutcomeBad = true
            studioOutcome = DecoyCopy.blocked("改台账")
            return
        }
        var ok = 0
        var missing: [String] = []
        for alias in selectedPwds {
            if DB.setPwdOwner(studioMac, alias, transferOwner) { ok += 1 }
            else { missing.append("密码#" + String(alias)) }
        }
        for batch in selectedFps {
            if DB.setFpOwner(studioMac, batch, transferOwner) { ok += 1 }
            else { missing.append("指纹#" + String(batch)) }
        }
        studioOutcomeBad = !missing.isEmpty
        studioOutcome = "已移交 " + String(ok) + " 项" + (missing.isEmpty ? "" : "；本机找不到 " + String(missing.count) + " 项（" + missing.joined(separator: "/") + "）")
        selectedPwds = []
        selectedFps = []
        tick += 1
    }

    private func exportPackage() {
        guard !DB.isDecoy else {
            studioOutcomeBad = true
            studioOutcome = DecoyCopy.blocked("导出凭证")
            return
        }
        guard let result = CredentialOrg.exportPackage(studioMac,
                                                       pwdAliases: Array(selectedPwds),
                                                       fpBatches: Array(selectedFps),
                                                       password: packagePassword) else {
            studioOutcomeBad = true
            studioOutcome = "导出失败：没有可导出的凭证"
            return
        }
        packageText = String(data: result.data, encoding: .utf8) ?? ""
        studioOutcomeBad = false
        studioOutcome = "已生成凭证包（" + String(result.size) + " 条）"
    }
}

// MARK: - 到期预警（五档 + 到期时）

struct CredAlertSheet2: View {
    let mac: String
    let pwd: LedgerPwd
    @Environment(\.dismiss) private var dismiss
    @State private var alert = CredAlert()

    private let tiers: [(key: String, label: String, get: (CredAlert) -> Bool, set: (inout CredAlert) -> Void)] = [
        ("day", "到期前 7 天", { $0.day }, { $0.day.toggle() }),
        ("d3", "到期前 3 天", { $0.d3 }, { $0.d3.toggle() }),
        ("d1", "到期前 1 天", { $0.d1 }, { $0.d1.toggle() }),
        ("h24", "到期前 24 小时", { $0.h24 }, { $0.h24.toggle() }),
        ("h2", "到期前 2 小时", { $0.h2 }, { $0.h2.toggle() })
    ]

    var body: some View {
        NavigationStack {
            VPage(title: "到期预警", lead: alertLead) {
                EmptyView()
            } content: {
                VCard2 {
                    VCardHead(eyebrow: "这条凭证", statement: CredentialOrg.displayPwd(pwd))
                    VDivider2()
                        .padding(.top, V8.S.gapM)
                    Text(CredentialOrg.expiryDate(pwd) == nil
                         ? "长期有效密码没有到期点，不适用预警。"
                         : "到期：" + CredentialOrg.expiryLabel(pwd.to, verb: false))
                        .font(V8.T.footnote)
                        .foregroundStyle(V8.C.ink3)
                        .padding(.top, V8.S.gapM)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VCard2 {
                    VCardHead(eyebrow: "提醒档位", statement: "开任意档即在意到期")
                    VDivider2()
                        .padding(.top, V8.S.gapM)
                    VStack(spacing: 0) {
                        ForEach(Array(tiers.enumerated()), id: \.offset) { pair in
                            let tier = pair.element
                            tierToggle(tier)
                            if pair.offset < tiers.count - 1 { VDotRule() }
                        }
                    }
                    .padding(.top, V8.S.gapS)
                    Text("到期时那一条总会跟着走：开了任意档就代表你在意这条凭证的到期。")
                        .font(V8.T.footnote)
                        .foregroundStyle(V8.C.ink4)
                        .padding(.top, V8.S.gapFootnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    dismiss()
                } label: {
                    Text("完成")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.chipOn)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.accent))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("完成")
            }
            .background(V8.C.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { alert = CredentialOrg.alert(mac, pwd) }
    }

    private var alertLead: String {
        CredentialOrg.expiryDate(pwd) == nil ? "长期有效，不适用提醒。" : "到期前按档位提醒。"
    }

    private func tierToggle(_ tier: (key: String, label: String, get: (CredAlert) -> Bool, set: (inout CredAlert) -> Void)) -> some View {
        Toggle(isOn: Binding(
            get: { tier.get(alert) },
            set: { _ in
                var next = alert
                tier.set(&next)
                alert = next
                CredentialOrg.saveAlert(mac, pwd, next)
                CredentialOrg.scheduleAlerts(mac, pwd, next)
            }
        )) {
            Text(tier.label)
                .font(V8.T.value)
                .foregroundStyle(V8.C.ink1)
        }
        .frame(minHeight: V8.H.min)
    }
}

// MARK: - 回收站

struct CredBinSheet2: View {
    let mac: String
    var onChange: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var items: [CredBinItem] = []
    @State private var outcome: String?
    @State private var outcomeBad = false
    @State private var purgeTarget: CredBinItem?

    var body: some View {
        NavigationStack {
            VPage(title: "回收站", lead: "可整组还原；彻底删除不能撤销。") {
                EmptyView()
            } content: {
                if items.isEmpty {
                    VCard2(style: .well) {
                        Text("回收站是空的。停用或批量删除的凭证会先来到这里。")
                            .font(V8.T.body)
                            .foregroundStyle(V8.C.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    VCard2 {
                        VCardHead(eyebrow: "已收", statement: String(items.count) + " 项")
                        VDivider2()
                            .padding(.top, V8.S.gapM)
                        VStack(spacing: 0) {
                            ForEach(items) { item in
                                binRow(item)
                                if item.id != items.last?.id { VDotRule() }
                            }
                        }
                        .padding(.top, V8.S.gapS)
                    }
                    // 2026-11-05（对抗审查）：文案四处承诺「可整组还原」，此前只有逐条还原。
                    // 按 batchId 分组，每批给一个入口 —— 同一次误操作进来的条目可以一把捞回。
                    let batches = Dictionary(grouping: items, by: { $0.batchId })
                    ForEach(batches.keys.sorted(by: { ($0) < ($1) }), id: \.self) { b in
                        if let group = batches[b], group.count > 1 {
                            VDivider2()
                                .padding(.vertical, V8.S.gapS)
                            Button { restoreBatch(b) } label: {
                                Text("还原这一批（" + String(group.count) + " 条 · " + (group.first?.source ?? "") + "）")
                                    .font(V8.T.tab)
                                    .foregroundStyle(V8.C.accent)
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: V8.H.min)
                                    .background(Capsule(style: .continuous).fill(V8.C.chipOff))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("还原这一批" + String(group.count) + "条")
                        }
                    }
                }
                if let outcome {
                    Text(outcome)
                        .font(V8.T.footnote)
                        .foregroundStyle(outcomeBad ? V8.C.danger : V8.C.ok)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    dismiss()
                } label: {
                    Text("关闭")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.ink1)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.chipOff))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭回收站")
            }
            .background(V8.C.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { reload() }
            .v8Confirm(
                isPresented: Binding(
                    get: { purgeTarget != nil },
                    set: { if !$0 { purgeTarget = nil } }
                ),
                title: "彻底删除这一条？",
                consequence: "这一条会从回收站永久删除：连同它在钥匙串里的口令副本、以及星标/停用位/预警提前量等派生设置一并清掉，不能恢复。锁端凭证不受影响。",
                confirmTitle: "彻底删除"
            ) {
                if let item = purgeTarget { purge(item) }
            }
        }
    }

    private func binRow(_ item: CredBinItem) -> some View {
        HStack(spacing: V8.S.gapS) {
            VStack(alignment: .leading, spacing: V8.S.gapXS) {
                Text(itemTitle(item))
                    .font(V8.T.value)
                    .foregroundStyle(V8.C.ink1)
                    .lineLimit(1)
                Text(item.source + " · " + TimeFormat.dayShort(Int64(item.at)))
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
                    .lineLimit(1)
            }
            Spacer(minLength: V8.S.gapS)
            Button("还原") { restore(item) }
                .font(V8.T.caption)
                .foregroundStyle(V8.C.accent)
                .frame(minHeight: V8.H.min)
                .accessibilityLabel("还原这一条")
            Button("彻底删除") { purgeTarget = item }
                .font(V8.T.caption)
                .foregroundStyle(V8.C.danger)
                .frame(minHeight: V8.H.min)
                .accessibilityLabel("彻底删除这一条")
        }
        .frame(minHeight: V8.H.min)
    }

    private func itemTitle(_ item: CredBinItem) -> String {
        if let pwd = item.pwd { return CredentialOrg.displayPwd(pwd) }
        if let fp = item.fp { return fp.name.isEmpty ? "指纹 " + String(fp.batch) : fp.name }
        return "凭证"
    }

    private func reload() {
        items = CredBinStore.all(mac)
        onChange()
    }

    private func restoreBatch(_ batchId: String) {
        let r = CredBinStore.restoreBatch(mac, batchId: batchId)
        reload()
        if r.blocked == 0 {
            outcomeBad = false
            outcome = "已整组还原 " + String(r.ok) + " 条"
        } else {
            outcomeBad = true
            // 静默跳过会让人以为整组都回来了 —— 逐项说清哪一半没回来、为什么。
            outcome = "整组还原：成功 " + String(r.ok) + " 条，" + String(r.blocked) + " 条因编号已被其它凭证占用未还原（锁端会复用删除后的槽位），请先在锁上处理那些编号"
        }
    }

    private func restore(_ item: CredBinItem) {
        if CredBinStore.restore(mac, item) {
            outcomeBad = false
            outcome = "已还原"
            reload()
        } else if let a = item.pwd?.alias {
            outcomeBad = true
            outcome = "还原失败：编号 #" + String(a) + " 已被其它凭证占用（锁端会复用删除后的槽位），请先在锁上处理那一条"
        } else {
            outcomeBad = true
            outcome = "还原失败：回收站里找不到这一条"
        }
    }

    private func purge(_ item: CredBinItem) {
        CredBinStore.purge(mac, item)
        purgeTarget = nil
        outcomeBad = false
        outcome = "已彻底删除"
        reload()
    }
}

// MARK: - 版本历史

struct CredHistorySheet2: View {
    let mac: String
    var onChange: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var items: [CredSnapshot] = []
    @State private var outcome: String?
    @State private var outcomeBad = false
    @State private var restoreTarget: CredSnapshot?

    var body: some View {
        NavigationStack {
            VPage(title: "版本历史", lead: "恢复前会自动备份当前状态，随时可以再切回来。") {
                EmptyView()
            } content: {
                if items.isEmpty {
                    VCard2(style: .well) {
                        VCardHead(eyebrow: "还没有版本快照", statement: "先存一档")
                        Text("在工作室点「保存版本快照」，之后就能对比或恢复到任意一档。")
                            .font(V8.T.footnote)
                            .foregroundStyle(V8.C.ink3)
                            .padding(.top, V8.S.gapM)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            capture()
                        } label: {
                            Text("保存快照")
                                .font(V8.T.tab)
                                .foregroundStyle(V8.C.chipOn)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: V8.H.min)
                                .background(Capsule(style: .continuous).fill(V8.C.accent))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("保存快照")
                        .padding(.top, V8.S.gapM)
                    }
                } else {
                    VCard2 {
                        VCardHead(eyebrow: "快照", statement: String(items.count) + " 份")
                        VDivider2()
                            .padding(.top, V8.S.gapM)
                        VStack(spacing: 0) {
                            ForEach(items) { snap in
                                CredHistoryRow2(snap: snap) { restoreTarget = snap }
                                if snap.id != items.last?.id { VDotRule() }
                            }
                        }
                        .padding(.top, V8.S.gapS)
                    }
                    Button {
                        capture()
                    } label: {
                        Text("保存当前为快照")
                            .font(V8.T.tab)
                            .foregroundStyle(V8.C.ink1)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: V8.H.min)
                            .background(Capsule(style: .continuous).fill(V8.C.chipOff))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("保存当前为快照")
                }
                if let outcome {
                    Text(outcome)
                        .font(V8.T.footnote)
                        .foregroundStyle(outcomeBad ? V8.C.danger : V8.C.ok)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    dismiss()
                } label: {
                    Text("关闭")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.ink1)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.chipOff))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭版本历史")
            }
            .background(V8.C.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { items = CredHistoryStore.all(mac) }
            .v8Confirm(
                isPresented: Binding(
                    get: { restoreTarget != nil },
                    set: { if !$0 { restoreTarget = nil } }
                ),
                title: "用这一版覆盖当前凭证列表？",
                consequence: restoreWarningText,
                confirmTitle: "恢复",
                isDestructive: true
            ) {
                if let snap = restoreTarget { restore(snap) }
            }
        }
    }

    private var restoreWarningText: String {
        guard let snap = restoreTarget else { return "" }
        let name = snap.note.isEmpty ? "快照" : snap.note
        let counts = String(snap.pwds.count) + " 密码 / " + String(snap.fps.count) + " 指纹"
        return "「" + name + "」（" + counts + "）会替换当前台账：这份快照之后新增的凭证会从本机消失（锁端仍在，但 App 里看不到）。恢复前会自动把当前状态存成一份快照，随时可以再切回来。"
    }

    private func restore(_ snap: CredSnapshot) {
        CredHistoryStore.capture(mac, note: "恢复前自动快照")
        CredHistoryStore.restore(mac, snap)
        items = CredHistoryStore.all(mac)
        restoreTarget = nil
        outcomeBad = false
        outcome = "已恢复这一版（已自动备份替换前的状态）"
        onChange()
    }

    private func capture() {
        CredHistoryStore.capture(mac, note: "手动快照")
        items = CredHistoryStore.all(mac)
        outcomeBad = false
        outcome = "已保存快照"
    }
}

// MARK: - 版本历史的一行

struct CredHistoryRow2: View {
    let snap: CredSnapshot
    var askRestore: () -> Void

    private var stampText: String {
        TimeFormat.dayShort(Int64(snap.at))
    }
    private var clockText: String {
        TimeDisplay.clock(Int64(snap.at))
    }
    private var countsText: String {
        String(snap.pwds.count) + " 密码 / " + String(snap.fps.count) + " 指纹"
    }
    private var titleText: String {
        snap.note.isEmpty ? "快照" : snap.note
    }
    private var detailText: String {
        stampText + " " + clockText + " · " + countsText
    }

    var body: some View {
        HStack(spacing: V8.S.gapS) {
            VStack(alignment: .leading, spacing: V8.S.gapXS) {
                Text(titleText)
                    .font(V8.T.value)
                    .foregroundStyle(V8.C.ink1)
                Text(detailText)
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
            }
            Spacer(minLength: V8.S.gapS)
            Button("恢复", action: askRestore)
                .font(V8.T.caption)
                .foregroundStyle(V8.C.accent)
                .frame(minHeight: V8.H.min)
                .accessibilityLabel("恢复这一版快照")
        }
        .frame(minHeight: V8.H.min)
    }
}

// MARK: - 凭证包导入

/// 粘贴一段工作室导出的加密文本 + 口令，合并进当前台账。
/// 冲突项（同 alias / 同 batch）跳过不覆盖 —— 包里的编号是导出那台锁分配的。
struct CredentialImportSheet: View {
    let mac: String
    var onImported: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var password = ""
    @State private var error: String?
    @State private var result: String?

    var body: some View {
        NavigationStack {
            VPage(title: "导入凭证包", lead: "导入是合并，不是覆盖。") {
                EmptyView()
            } content: {
                VCard2 {
                    VCardHead(eyebrow: "凭证包文本", statement: error == nil ? "粘贴整段文本" : "有错误")
                    VDivider2()
                        .padding(.top, V8.S.gapM)
                    TextEditor(text: $text)
                        .font(V8.T.footnote)
                        .frame(minHeight: V8.H.comfortable * 3)
                        .scrollContentBackground(.hidden)
                        .padding(V8.S.gapS)
                        .background(V8.C.well, in: .rect(cornerRadius: V8.R.inset))
                        .accessibilityLabel("凭证包文本")
                        .padding(.top, V8.S.gapM)
                    // 2026-11-05（对抗审查 · 安全）：导出包口令是加密凭证包的密钥，
                    // 明文输入 + 无遮挡等于把它摊在屏幕上。改 SecureField（打码），
                    // 与其它口令输入同口径。
                    SecureField("包口令", text: $password)
                        .font(V8.T.body)
                        .foregroundStyle(V8.C.ink1)
                        .frame(minHeight: V8.H.min)
                        .padding(.horizontal, V8.S.gapM)
                        .background(V8.C.well, in: .rect(cornerRadius: V8.R.inset))
                        .autocorrectionDisabled()
                        .padding(.top, V8.S.gapS)
                    if let error {
                        Text(error)
                            .font(V8.T.footnote)
                            .foregroundStyle(V8.C.danger)
                            .padding(.top, V8.S.gapS)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let result {
                        Text(result)
                            .font(V8.T.footnote)
                            .foregroundStyle(V8.C.ok)
                            .padding(.top, V8.S.gapS)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        run()
                    } label: {
                        Text("导入")
                            .font(V8.T.tab)
                            .foregroundStyle(V8.C.chipOn)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: V8.H.min)
                            .background(Capsule(style: .continuous).fill(V8.C.accent))
                    }
                    .buttonStyle(.plain)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                    .opacity((text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty) ? 0.45 : 1)
                    .padding(.top, V8.S.gapM)
                    Button {
                        dismiss()
                    } label: {
                        Text("关闭")
                            .font(V8.T.tab)
                            .foregroundStyle(V8.C.ink1)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: V8.H.min)
                            .background(Capsule(style: .continuous).fill(V8.C.chipOff))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭导入")
                    .padding(.top, V8.S.gapS)
                }
                VCard2(style: .well) {
                    Text("导入是合并，不是覆盖：同编号的凭证会被跳过（不覆盖本机已有的），导入结果会如实报出写入与跳过的条数。")
                        .font(V8.T.footnote)
                        .foregroundStyle(V8.C.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .background(V8.C.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func run() {
        error = nil
        result = nil
        do {
            let r = try CredentialOrg.importPackage(text, password: password, into: mac)
            if r.imported == 0 {
                error = "没有可导入的凭证：" + String(r.skipped) + " 项与现有凭证编号冲突（已全部跳过）"
                return
            }
            result = "已导入 " + String(r.imported) + " 项" + (r.skipped > 0 ? "，跳过 " + String(r.skipped) + " 项（编号冲突）" : "")
            onImported()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
