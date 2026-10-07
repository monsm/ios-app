// 凭证 Tab (credentials 页) — 密码/指纹台账 + OTP + 包6 列表组织·批量·流转
// 交互约定: 与门锁通信期间整页置为忙碌 (busyKey), 杜绝 swipe/菜单并发下发指令;
// 所有破坏性动作统一走 confirmDestructive, 不在本文件重复实现弹窗。
// 包6 落地: 分段计数 (524/525 首字索引条随成员视图) / 双视图分组 (355) / 三态分组头 (528) /
// 置顶星标 (526/921) / 智能列表 (527) / 四维排序 (914) / 命名模板 (918) / 别名显示 (919) /
// 编辑模式 (347/356/357) / 统一延期 (348) / 批量移交 (349) / 智能选取 (350) /
// 合包导出 (351) / 停用摘要确认页 (353) / 整理建议中心 (358/505) / 月度清理任务 (366 在 onLaunch) /
// 三档预警 (359) / 过期即归档 (360/180/364) / 下发状态步条 (365 本地容错) / 月历 (363) /
// 删除后果说明 (670) / 版本历史入口 (487-496 在 CredentialCenterView) / 回收站 (497-506) /
// 误删撤销条 (506) / 最近搜索词 (531) / 搜索兜底动作 (532) / 组尾统计 (529 标"约")。
import SwiftUI
import UIKit

// ================= 凭证 Tab =================
struct CredentialsView: View {
    @EnvironmentObject var app: AppState
    // 包2 连接感知: 510 待下发横条 / 535 回执 依赖 LinkSense 补发回执计时 (只读观察)
    @ObservedObject private var sense = LinkSense.shared
    @State private var refreshTick = 0
    @State private var showAdd = false
    /// 正在与门锁通信的条目 ("pwd:3" / "fp:12" / "otp") / nil = 空闲
    @State private var busyKey: String?
    @State private var otpPwd = "******"
    @State private var otpWin = ""
    @State private var otpBig = false   // 885 凭证大字模式: 双击或开关切大字号对照抄写""

    // ---------- 包6 列表组织 ----------
    @State private var seg: Int = 0          // 524 类型分段: 0 全部 / 1 密码 / 2 指纹 / 3 临时码
    @State private var memberView = CredentialOrg.groupMode == 1   // 355 按成员视图
    @State private var smartSel: String = "" // 527 智能列表选中 id ("" = 默认)
    @State private var sortKey: CredSortKey = CredentialOrg.sortKey   // 914
    @State private var showCalendar = false  // 363 月历
    @State private var showOrganize = false  // 358 整理建议中心
    @State private var search = ""
    @State private var undoEntry: CredBinEntry?
    @State private var undoTimer: DispatchSourceTimer?
    // 347 编辑模式
    @State private var editMode = false
    @State private var selPwds: [Int] = []
    @State private var selFps: [Int] = []
    @State private var showExtend = false
    @State private var extendAliases: [Int] = []
    @State private var showTransfer = false
    @State private var showDisable = false
    @State private var showQueue = false
    @State private var showBin = false
    @State private var showDemo = false   // 包14/834 30 秒演示链接
    @State private var pwdDetailItem: LedgerPwd?   // 包5 PwdDetailStudio
    @State private var fpDetailItem: LedgerFp?     // 包5 FpDetailStudio
    @State private var histItem: HistItem?

    private var isBusy: Bool { busyKey != nil }

    var body: some View {
        NavigationStack {
            Group {
                if app.current == nil {
                    EmptyState(systemImage: "lock.badge.plus",
                               title: "还没有添加门锁",
                               message: "凭证台账要绑定到具体门锁。请先在门锁键盘上长按重置键恢复出厂，再回来添加设备（需要开启蓝牙）。",
                               actionTitle: "去添加门锁") { showAdd = true }
                } else {
                    VStack(spacing: 0) {
                        borrowBanner
                        pendingQueueBar   // 510 待下发横条 (跨页提示, 复用 kf_cqueue_)
                        credJumpBar       // 包9/577 记录详情"来源凭证"→ 定位本条 (消费后清)
                        headerToolbar
                        if showCalendar {
                            CredCalendarView(mac: mac, onPick: pickDay)
                        } else if editMode {
                            editList
                        } else {
                            mainList
                        }
                    }
                    .safeAreaInset(edge: .bottom) {
                        if editMode { batchBar }
                    }
                }
            }
            .navigationTitle("凭证")
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .id(app.currentMac)
            .onAppear {
                refreshTick += 1
                consumeCredJump()   // 包9/577: 记录/告警详情"来源凭证"深链
            }
            .onChange(of: app.pendingCredNav) { _, _ in consumeCredJump() }
            .overlay { undoBar }
            .sheet(isPresented: $showOrganize) {
                CredOrganizeView(mac: mac) {
                    reload()
                }
            }
            .sheet(isPresented: $showExtend) {
                if !extendAliases.isEmpty {
                    CredExtendView(mac: mac, aliases: extendAliases) { reload() }
                }
            }
            .sheet(isPresented: $showTransfer) {
                if selCount > 0 {
                    CredTransferView(mac: mac, pwdAliases: selPwds, fpBatches: selFps) { reload() }
                }
            }
            .sheet(isPresented: $showDisable) {
                if selCount > 0 {
                    CredDisableSheet(mac: mac, pwdAliases: selPwds, fpBatches: selFps) { finishDisable() }
                }
            }
            .sheet(isPresented: $showQueue) {
                CredQueueView(mac: mac)
            }
            .sheet(isPresented: $showBin) {
                NavigationStack {
                    CredBinView(mac: mac)
                        .toolbar { ToolbarItem(placement: .navigationBarLeading) {
                            Button("关闭") { showBin = false }
                        } }
                }
            }
            .sheet(item: $histItem) { item in
                NavigationStack {
                    CredHistoryView(mac: mac, kind: item.kind, key: item.key)
                        .toolbar { ToolbarItem(placement: .navigationBarLeading) {
                            Button("关闭") { histItem = nil }
                        } }
                }
            }
            .sheet(item: $pwdDetailItem) { item in
                PwdDetailStudio(alias: item.alias)
            }
            .sheet(item: $fpDetailItem) { item in
                FpDetailStudio(batch: item.batch)
            }
        }
        .sheet(isPresented: $showAdd) { AddDeviceView() }
    }

    private func reload() { refreshTick += 1 }

    private var mac: String { app.current?.mac ?? "" }

    // ---------- 顶部工具条 (524 分段计数 / 914 四维排序器 / 363 月历 / 358 整理 / 347 选择) ----------
    // 472 借用横条: 页顶显示进行中借用, 点 已归还 销记
    @ViewBuilder
    private var borrowBanner: some View {
        let bs = MemberHub.borrows(mac)
        if !bs.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.xs) {
                    ForEach(Array(bs.keys.sorted()), id: \.self) { k in
                        let b = bs[k]!
                        HStack(spacing: DS.Space.xs) {
                            Text("借用 " + k + " · 借给 " + b.by + " (还 " + b.due + ")")
                                .font(.caption)
                                .foregroundStyle(DS.Palette.text)
                                .lineLimit(1)
                            Button("已归还") {
                                MemberHub.saveBorrow(mac, itemKey: k, nil)
                                refreshTick += 1
                                app.showToast("已销记归还 " + k)
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(DS.Palette.accentText)
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Capsule())
                        }
                        .padding(.horizontal, DS.Space.s)
                        .padding(.vertical, DS.Space.xs)
                        .background(DS.Palette.warn.opacity(0.12), in: Capsule())
                        .overlay(Capsule().strokeBorder(DS.Palette.hairline, lineWidth: 0.5))
                    }
                }
                .padding(.horizontal, DS.Space.gutter)
            }
        }
    }

    // ---------- 577 详情跳凭证定位 (包9): 记录/告警详情"来源凭证"深链 → 高亮条 + 打开对应详情 ----------
    @ViewBuilder
    private var credJumpBar: some View {
        if let nav = app.pendingCredNav {
            HStack(spacing: DS.Space.s) {
                Image(systemName: "location.fill")
                    .font(.system(size: DS.Icon.sm))
                    .foregroundStyle(DS.Palette.accentText)
                    .accessibilityHidden(true)
                Text("已从记录定位到该凭证 (577)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(DS.Palette.text)
                Spacer(minLength: 0)
                Button("关闭") {
                    app.pendingCredNav = nil
                    app.pendingCredNavMac = nil
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(DS.Palette.accentText)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
            }
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.xs + 2)
            .background(DS.Palette.accentText.opacity(0.09), in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.hairline, lineWidth: 0.5))
            .padding(.horizontal, DS.Space.gutter)
        }
    }
    /// 消费深链: pwd:<alias> → 密码段 + 打开详情; fp:<batch> → 指纹段。跨锁时先切锁。
    private func consumeCredJump() {
        guard let nav = app.pendingCredNav else { return }
        if let m = app.pendingCredNavMac, m != mac {
            app.select(m)
        }
        app.pendingCredNav = nil
        app.pendingCredNavMac = nil
        seg = 0
        memberView = false
        if nav.hasPrefix("pwd:"), let a = Int(nav.dropFirst(4)), DB.getPwd(mac, a) != nil {
            pwdDetailItem = DB.getPwd(mac, a)
        } else if nav.hasPrefix("fp:"), let b = Int(nav.dropFirst(3)), DB.getFp(mac, b) != nil {
            fpDetailItem = DB.getFp(mac, b)
        }
        app.showToast("已定位到来源凭证 (577)")
    }

    // ---------- 510 待下发横条: BLE 下发失败的变更聚合成凭证 Tab 顶部 "待下发 N 项" 横条 ----------
    // 538 按锁排队: 多锁各自队列不串台 — 横条按当前锁计, 清单页每行标目标锁;
    // 535 同步回执: 队列刚被补发清空时短条 "已同步 N 项" 2 分钟内可见。
    @ViewBuilder
    private var pendingQueueBar: some View {
        let q = CredentialOrg.pendingQueue(mac)
        if !q.isEmpty {
            Button { showQueue = true } label: {
                HStack(spacing: DS.Space.s) {
                    Image(systemName: "tray.full")
                        .font(.system(size: DS.Icon.sm, weight: .semibold))
                        .foregroundStyle(DS.Palette.warn)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("待下发 " + String(q.count) + " 项 · " + LockArchiveLockName)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(DS.Palette.text)
                        Text("到场连接后自动补发, 或进清单逐项重试 (510/533/538)")
                            .font(.caption2)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: DS.Icon.xs, weight: .semibold))
                        .foregroundStyle(DS.Palette.textSub)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, DS.Space.l)
                .padding(.vertical, DS.Space.s + 2)
                .background(DS.Palette.warn.opacity(0.10), in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.hairline, lineWidth: 0.5))
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DS.Space.gutter)
            .accessibilityLabel("待下发 " + String(q.count) + " 项, 点按查看清单")
        } else if sense.lastReceipt > 0, Date().timeIntervalSince(sense.receiptShownAt) < 120 {
            HStack(spacing: DS.Space.s) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: DS.Icon.sm, weight: .semibold))
                    .foregroundStyle(DS.Palette.ok)
                    .accessibilityHidden(true)
                Text("已同步 " + String(sense.lastReceipt) + " 项变更 — 队列已清空 (535)")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.s + 2)
            .background(DS.Palette.ok.opacity(0.10), in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            .padding(.horizontal, DS.Space.gutter)
            .accessibilityLabel("已同步 " + String(sense.lastReceipt) + " 项变更")
        }
    }
    private var LockArchiveLockName: String {
        app.devices.first { $0.mac == mac }.map { LockArchive.displayName($0) } ?? mac.prefix(6)
    }

    private var headerToolbar: some View {
        VStack(spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.s) {
                Text("共 \(CredentialOrg.typeCounts(mac).all) 条")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if !CredentialOrg.pendingQueue(mac).isEmpty {
                    Button { showQueue = true } label: {
                        Label("待处理 \(CredentialOrg.pendingQueue(mac).count) 项", systemImage: "arrow.down.circle")
                    }
                    .font(.caption)
                    .tint(DS.Palette.warn)
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                    .accessibilityLabel("待处理下发 \(CredentialOrg.pendingQueue(mac).count) 项, 点按查看")
                }
                Button {
                    sortKey = CredSortKey(rawValue: (sortKey.rawValue + 1) % CredSortKey.allCases.count)!
                    CredentialOrg.setSortKey(sortKey)
                    app.showToast("按「\(sortKey.label)」排序 (914)")
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: DS.Icon.md, weight: .semibold))
                        .frame(width: DS.Hit.min, height: DS.Hit.min)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("排序维度: \(sortKey.label), 点按在 名称/类型/最近使用/到期 间循环")
                Button { showCalendar.toggle() } label: {
                    Image(systemName: showCalendar ? "list.bullet" : "calendar")
                        .font(.system(size: DS.Icon.md, weight: .semibold))
                        .frame(width: DS.Hit.min, height: DS.Hit.min)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(showCalendar ? "退出月历" : "月历到期视图 (363)")
                Button { showOrganize = true } label: {
                    Image(systemName: "rectangle.3.offgrid")
                        .font(.system(size: DS.Icon.md, weight: .semibold))
                        .frame(width: DS.Hit.min, height: DS.Hit.min)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("整理建议中心 (358)")
                if !editMode && !MemberHub.elderMode {   // 479 长辈模式隐藏批量与导出入口
                    Button("选择") {
                        withAnimation(DS.Motion.quick) { editMode = true }
                        DS.Haptics.tick.impactOccurred()
                    }
                    .frame(minHeight: DS.Hit.min)
                }
            }
            // 524 类型分段计数 (479 长辈模式只出前三组)
            let segCount = MemberHub.elderMode ? 3 : 4
            HStack(spacing: DS.Space.xs) {
                ForEach(0..<segCount, id: \.self) { i in
                    segChip(i)
                }
                Spacer(minLength: 0)
                Button {
                    memberView.toggle()
                    CredentialOrg.setGroupMode(memberView ? 1 : 0)
                } label: {
                    HStack(spacing: DS.Space.xxs) {
                        Image(systemName: "person.2")
                            .font(.system(size: DS.Icon.sm, weight: .medium))
                        Text("按成员")
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, DS.Space.s).padding(.vertical, 6)
                    .foregroundStyle(memberView ? DS.Palette.accentText : DS.Palette.textSub)
                    .background((memberView ? DS.Palette.accentText.opacity(0.12) : DS.Palette.surfaceAlt), in: Capsule())
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("按成员分组 \(memberView ? "已开" : "未开") (355), 点按切换")
            }
            // 527 命名智能列表
            HStack(spacing: DS.Space.xs) {
                Menu {
                    Button("默认 (全部)") { smartSel = "" }
                    let lists = CredentialOrg.smartLists(mac)
                    if !lists.isEmpty { Divider() }
                    ForEach(lists) { l in
                        Button(l.name) { smartSel = l.id }
                    }
                    Divider()
                    Button("新建智能列表…") { newSmartList() }
                    Button("管理智能列表") { manageSmartLists() }
                } label: {
                    HStack(spacing: DS.Space.xxs) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: DS.Icon.sm, weight: .medium))
                        Text(smartSel.isEmpty ? "智能筛选" : CredentialOrg.smartLists(mac).first { $0.id == smartSel }?.name ?? "智能筛选")
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, DS.Space.s).padding(.vertical, 6)
                    .foregroundStyle(smartSel.isEmpty ? DS.Palette.textSub : DS.Palette.accentText)
                    .background((!smartSel.isEmpty ? DS.Palette.accentText.opacity(0.12) : DS.Palette.surfaceAlt), in: Capsule())
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("智能筛选 \(smartSel.isEmpty ? "默认" : "已套用"), 点按展开 (527)")
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, DS.Space.gutter)
        .padding(.vertical, DS.Space.xs)
        .accessibilityElement(children: .contain)
    }

    private func segChip(_ i: Int) -> some View {
        // 479 长辈模式: 只留 全部/密码/指纹 三组, 隐藏临时码组与批量/导出入口
        let labels = MemberHub.elderMode ? ["全部", "密码", "指纹", ""] : ["全部", "密码", "指纹", "临时码"]
        let c = countForSeg(i)
        let on = seg == i
        return Button {
            seg = i
            DS.Haptics.tick.impactOccurred()
        } label: {
            HStack(spacing: DS.Space.xxs) {
                Text(labels[i]).font(.caption.weight(.medium))
                if c > 0 {
                    Text("\(c)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(on ? DS.Palette.onAccent : DS.Palette.textSub)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(on ? Color.white.opacity(0.24) : DS.Palette.surfaceAlt, in: Capsule())
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, DS.Space.s).padding(.vertical, 6)
            .foregroundStyle(on ? DS.Palette.onAccent : DS.Palette.textSub)
            .background(on ? AnyShapeStyle(DS.Palette.accent) : AnyShapeStyle(DS.Palette.surfaceAlt), in: Capsule())
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("\(labels[i]) \(c) 条 (524 分段计数)")
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
    private func countForSeg(_ i: Int) -> Int {
        let t = CredentialOrg.typeCounts(mac)
        switch i {
        case 1: return t.pwd
        case 2: return t.fp
        case 3: return DB.listPwds(mac).filter { $0.temp }.count
        default: return t.all
        }
    }

    // ---------- 主列表 ----------
    private var mainList: some View {
        List {
            listBody
        }
        .listItemSpacing(DS.Space.xs)   // 批量操作行距保持宽松 (纪律: 批量行距)
    }

    /// 列表内容抽成 ViewBuilder: 编辑模式与正常模式共用, 避免嵌套两个 List
    @ViewBuilder
    private var listBody: some View {
            searchSection
            queueSection
            stockSection
            dueSoonBanner
            if memberView {
                memberSections
            } else {
                let pwds = sortedPwds
                if !pwds.isEmpty {
                    pwdSections(pwds)
                }
                let fps = sortedFps
                if seg == 0 || seg == 2, !fps.isEmpty {
                    fpSection(fps)
                }
            }
            if seg == 0 { otpSection }
            if memberView || (!memberView && sortedPwds.isEmpty && sortedFps.isEmpty) {
                emptyHint
            }
    }

    @ViewBuilder
    private var searchSection: some View {
        Section {
            if search.isEmpty {
                let hist = CredentialOrg.searchHistory()
                if !hist.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text("最近搜索")
                            .font(.caption2)
                            .foregroundStyle(DS.Palette.textSub)
                        HStack(spacing: DS.Space.xs) {
                            ForEach(hist.prefix(5), id: \.self) { w in
                                HStack(spacing: 2) {
                                    Button(w) { search = w }
                                        .font(.caption)
                                        .buttonStyle(.bordered)
                                        .accessibilityLabel("搜索 \(w)")
                                    Button { CredentialOrg.removeSearchHistory(w) } label: {
                                        Image(systemName: "xmark.circle")
                                            .font(.system(size: 12))
                                            .frame(width: 24, height: 24)
                                            .contentShape(Rectangle())
                                    }
                                    .accessibilityLabel("删除最近搜索 \(w)")
                                }
                            }
                        }
                    }
                }
            } else {
                let hits = filteredResults
                ForEach(hits) { hit in
                    credRow(hit)
                }
                if hits.isEmpty {
                    // 532 搜索兜底动作
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text("没有找到「\(search)」")
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                        HStack(spacing: DS.Space.s) {
                            Button {
                                showBin = true
                            } label: {
                                Label("去回收站搜 (503)", systemImage: "magnifyingglass.circle")
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .accessibilityLabel("去回收站搜索 \(search)")
                            Button {
                                let m = DB.members().first { $0.name.localizedCaseInsensitiveContains(search) || $0.relation.localizedCaseInsensitiveContains(search) }
                                if let m {
                                    memberView = true
                                    app.showToast("已按成员「\(m.name)」过滤")
                                } else {
                                    app.showToast("没有匹配的成员")
                                }
                            } label: {
                                Label("按成员重搜", systemImage: "person")
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, DS.Space.xs)
                }
            }
            TextField("搜索名称 / 备注 / #别名 (531)", text: $search)
                .keyboardShortcut("f", modifiers: .command)
                .accessibilityLabel("凭证搜索, 键盘 Cmd/Control+F")
                .autocorrectionDisabled()
                .onSubmit {
                    if !search.isEmpty { CredentialOrg.pushSearchHistory(search) }
                }
                .accessibilityLabel("凭证搜索")
        }
    }

    struct CredHit: Identifiable {
        var id: String
        var pwd: LedgerPwd?
        var fp: LedgerFp?
        var pinned: Bool = false
    }

    private var filteredResults: [CredHit] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var hits: [CredHit] = []
        for p in DB.listPwds(mac) {
            let hay = "\(p.alias) \(p.note) \(CredentialOrg.displayPwd(p)) \(CredentialOrg.namingTemplate(p)) \(CredentialOrg.ownerName(p.owner))"
            if hay.localizedCaseInsensitiveContains(q) {
                hits.append(CredHit(id: "p\(p.alias)", pwd: p, pinned: CredentialOrg.isStarred(mac, "pwd", p.alias)))
            }
        }
        for f in DB.listFp(mac) {
            let hay = "\(f.name) \(f.note) \(CredentialOrg.ownerName(f.owner))"
            if hay.localizedCaseInsensitiveContains(q) {
                hits.append(CredHit(id: "f\(f.batch)", fp: f, pinned: CredentialOrg.isStarred(mac, "fp", f.batch)))
            }
        }
        return hits.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.id < b.id
        }
    }

    // ---------- 365 下发状态步条 (本地容错态) ----------
    @ViewBuilder
    private var queueSection: some View {
        let q = CredentialOrg.pendingQueue(mac)
        if !q.isEmpty {
            Section("待下发 (\(q.count))") {
                ForEach(q.prefix(4)) { item in
                    HStack(spacing: DS.Space.s) {
                        StatusPill(text: queueStateText(item), systemImage: "arrow.down.circle", tone: queueTone(item))
                        Text(item.title)
                            .font(.subheadline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Spacer(minLength: 0)
                        Button("重试") { retryQueueItem(item) }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .disabled(isBusy)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(item.title), \(queueStateText(item))")
                }
                if q.count > 4 {
                    Button("其余 \(q.count - 4) 项 →") { showQueue = true }
                        .font(.caption)
                        .foregroundStyle(DS.Palette.accentText)
                }
                Text("锁端未连接时操作先记在这里, 到场连接后逐条重试; 失败项不会丢 (365, 本地容错态)。")
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func queueStateText(_ i: CredQueueItem) -> String {
        switch i.state {
        case 1: return "已下发"
        case 2: return "失败可重试"
        default: return "待下发"
        }
    }
    private func queueTone(_ i: CredQueueItem) -> ToneColor {
        switch i.state {
        case 1: return .ok
        case 2: return .danger
        default: return .warn
        }
    }
    private func retryQueueItem(_ item: CredQueueItem) {
        guard busyKey == nil else { return }
        busyKey = "queue:\(item.id)"
        Task {
            defer { busyKey = nil }
            do {
                try await app.lock.ensureConnected(mac: mac)
                try await applyQueueItem(item)
                CredentialOrg.markQueue(mac, id: item.id, state: .done, note: item.title + " · 锁端确认")
                app.showToast("\(item.title) 已下发")
            } catch {
                CredentialOrg.markQueue(mac, id: item.id, state: .failed, note: item.title + " · 第 \(item.attempt + 1) 次失败")
                app.showToast("重试失败: \(error.localizedDescription)")
            }
        }
    }
    /// 365 重试走既有协议命令 (不改命令集, 只复用): 步条 待下发→已下发→锁端确认(rc@#03)
    private func applyQueueItem(_ item: CredQueueItem) async throws {
        switch item.kind {
        case "del_pwd":
            try await app.lock.pwdDelete(item.pwd?.alias ?? 0)
        case "del_fp":
            try await app.lock.fpDelete(UInt32(item.fp?.batch ?? 0))
        case "period":
            if let p = item.pwd, !item.newFrom.isEmpty { try await app.lock.pwdExpire(p.alias, item.newFrom, item.newTo) }
        case "restore":
            if let p = item.pwd, let v = p.pwd { _ = try await app.lock.pwdAdd(pwd: v, validFrom: p.from, validTo: p.to) }
        default:
            break
        }
    }

    // ---------- 359 到期提醒行 (2 小时档, Hero 卡下方等价物) ----------
    @ViewBuilder
    private var dueSoonBanner: some View {
        let n = CredentialOrg.dueSoonCount(mac)
        if n > 0 {
            Label {
                Text("\(n) 条密码 2 小时内到期 (已开 2 小时档预警)")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.circle.fill")
                    .accessibilityHidden(true)
            }
            .font(.caption)
            .foregroundStyle(DS.Palette.warn)
            .listRowBackground(DS.Palette.warn.opacity(0.06))
        }
    }

    // ---------- 锁内存量行 + 台账对账 (无数据时整段隐藏, 不留空段) ----------
    @ViewBuilder
    private var stockSection: some View {
        let st = app.status
        let snap = app.snapshot
        let pStock = st?.pwdStock ?? snap?.pwdStock ?? -1
        let fStock = st?.fpStock ?? snap?.fpStock ?? -1
        if pStock >= 0 || fStock >= 0 {
            Section("锁内存量") {
                HStack(alignment: .top) {
                    Text("最近读到的锁内余量")
                        .foregroundStyle(DS.Palette.textSub)
                    Spacer(minLength: DS.Space.m)
                    Text([pStock >= 0 ? "密码 \(pStock)" : nil, fStock >= 0 ? "指纹 \(fStock)" : nil].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.text)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                let dp = pStock - DB.listPwds(mac).count
                let df = fStock - DB.listFps(mac).count
                if dp > 0 || df > 0 {
                    Label {
                        Text("锁内还有 \(dp > 0 ? "密码 \(dp) 条" : "")\(dp > 0 && df > 0 ? "、" : "")\(df > 0 ? "指纹 \(df) 条" : "") 不在本机台账 — 可能由键盘或其他管理员添加。")
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .accessibilityHidden(true)
                    }
                    .font(.caption)
                    .foregroundStyle(DS.Palette.warn)
                }
            }
        }
    }

    // ---------- 524/526/527/914/182 密码段 (三态分组头 528 + 置顶 + 组尾统计 529) ----------
    private var sortedPwds: [LedgerPwd] {
        var pwds = DB.listPwds(mac)
        if seg == 1 || seg == 3 {
            pwds = pwds.filter { seg == 3 ? $0.temp : !$0.temp }
        }
        if let l = CredentialOrg.smartLists(mac).first(where: { $0.id == smartSel }), l.kind != "fp" {
            pwds = pwds.filter { p in
                if l.owner != "", p.owner != l.owner { return false }
                if !l.state.isEmpty, CredentialOrg.stateString(CredentialOrg.pwdState(p)) != l.state { return false }
                if l.tag == "stale" { return p.at > 0 && CredentialOrg.nowSec - p.at > 365 * 86400 }
                if l.tag == "noowner" { return p.owner == nil }
                return true
            }
        }
        // 526 置顶行固定顶部
        let pinned = pwds.filter { CredentialOrg.isStarred(mac, "pwd", $0.alias) }
        let rest = pwds.filter { !CredentialOrg.isStarred(mac, "pwd", $0.alias) }
        var ordered = orderPwds(rest)
        // 182/352 拖拽排序: 用户手动序优先 (seq 存的 index 数组)
        let seq = CredentialOrg.seq(mac)
        let order = seq["p"] ?? []
        let byIdx = Dictionary(uniqueKeysAndValues: order.enumerated().map { ($1, $0) })
        if !order.isEmpty {
            ordered = ordered.sorted { a, b in
                let ia = byIdx[a.alias, default: 9999]
                let ib = byIdx[b.alias, default: 9999]
                return ia < ib
            }
        }
        return pinned + ordered
    }
    private func orderPwds(_ input: [LedgerPwd]) -> [LedgerPwd] {
        switch sortKey {
        case .name:
            return input.sorted { CredentialOrg.displayPwd($0).localizedStandardCompare(CredentialOrg.displayPwd($1)) == .orderedAscending }
        case .type:
            return input.sorted { a, b in
                if a.temp != b.temp { return a.temp }
                return a.alias < b.alias
            }
        case .recent:
            return input.sorted { ($0.at) > ($1.at) }
        case .expiry:
            return input.sorted { a, b in
                let ta = CredentialOrg.expiryDate(a) ?? Date.distantFuture
                let tb = CredentialOrg.expiryDate(b) ?? Date.distantFuture
                return ta < tb
            }
        }
    }

    @ViewBuilder
    private func pwdSections(_ pwds: [LedgerPwd]) {
        let pinned = pwds.filter { CredentialOrg.isStarred(mac, "pwd", $0.alias) }
        if !pinned.isEmpty {
            Section("置顶 (\(pinned.count))") {
                ForEach(pinned) { p in credRow(CredHit(id: "p\(p.alias)", pwd: p, pinned: true)) }
            }
        }
        // 528 进行中/已排期/已过期三态分组头, 组头带计数
        for state in [0, 1, 2] {
            let group = pwds.filter { CredentialOrg.pwdState($0) == state }
            if !group.isEmpty {
                Section("\(CredentialOrg.stateLabel(state)) (\(group.count))") {
                    ForEach(group.filter { !CredentialOrg.isStarred(mac, "pwd", $0.alias) }) { p in
                        credRow(CredHit(id: "p\(p.alias)", pwd: p, pinned: false))
                    }
                    // 529 组尾统计行: "本组 X 条 · 近 30 天使用约 Y 次" (台账推断, 带"约")
                    let uses = group.compactMap { CredentialOrg.recentUseCount(mac, pwdAlias: $0.alias) }.reduce(0, +)
                    if uses > 0 {
                        Text("本组 \(group.count) 条 · 近 30 天使用约 \(uses) 次")
                            .font(.caption2)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityHidden(true)
                    }
                    if state == 2 {
                        // 360 过期即归档 + 348 统一延期快捷
                        Button("这一组统一延期") {
                            extendAliases = group.map { $0.alias }
                            showExtend = true
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DS.Palette.accentText)
                    }
                }
            }
        }
        // 182 长按拖动: 组内排序
        if !pinned.isEmpty {
            Section {
                HintRow(text: "长按行拖动可调整组内顺序 (182), 顺序跨启动保持。")
            }
        }
        Section {
            CredStudioEntryView()   // 包5 凭证工坊 (177 扇出: 密码/临时码/指纹/OTP 四类)
            NavigationLink { AddPwdView(embedded: true) } label: { Label("添加密码", systemImage: "plus") }
            NavigationLink { CredBinView(mac: mac) } label: {
                Label("回收站 (\(CredentialOrg.bin(mac).count))", systemImage: "trash")
            }
            NavigationLink { CredHistoryListView(mac: mac) } label: {
                Label("版本历史与整理 (487/358)", systemImage: "clock.arrow.circlepath")
            }
            NavigationLink { CredCenterView(mac: mac, section: "organize") } label: {
                Label("凭证中心 (队列/整理)", systemImage: "tray.full")
            }
        }
    }

    /// 行内小提示行 (装饰, 不参与 VoiceOver 合并)
    private struct HintRow: View {
        let text: String
        var body: some View {
            Text(text)
                .font(.caption2)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // ---------- 指纹段 ----------
    private var sortedFps: [LedgerFp] {
        var fps = DB.listFp(mac)
        if let l = CredentialOrg.smartLists(mac).first(where: { $0.id == smartSel }), l.kind == "fp" {
            fps = fps.filter {
                if l.owner != "", $0.owner != l.owner { return false }
                if l.tag == "noowner" { return $0.owner == nil }
                return true
            }
        }
        let pinned = fps.filter { CredentialOrg.isStarred(mac, "fp", $0.batch) }
        let rest = fps.filter { !CredentialOrg.isStarred(mac, "fp", $0.batch) }
        let ordered: [LedgerFp]
        switch sortKey {
        case .name:
            ordered = rest.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .type:
            ordered = rest.sorted { ($0.isAlarm == true ? 0 : 1) < ($1.isAlarm == true ? 0 : 1) }
        default:
            ordered = rest.sorted { ($0.at) > ($1.at) }
        }
        let seq = CredentialOrg.seq(mac)
        let order = seq["f"] ?? []
        if !order.isEmpty {
            let byIdx = Dictionary(uniqueKeysAndValues: order.enumerated().map { ($1, $0) })
            ordered = ordered.sorted { a, b in
                let ia = byIdx[a.batch, default: 9999]
                let ib = byIdx[b.batch, default: 9999]
                return ia < ib
            }
        }
        return pinned + ordered
    }

    @ViewBuilder
    private func fpSection(_ fps: [LedgerFp]) {
        Section("指纹 (\(fps.count))") {
            // 322 缺失提醒行: 名下无指纹的成员 → 预填直达添加
            let missing = DB.members().filter { m in
                !MemberHub.ext(m.id).archived && !DB.listFps(mac).contains(where: { $0.owner == m.id })
            }
            if !missing.isEmpty {
                HStack(spacing: DS.Space.s) {
                    Label("有 \(missing.count) 位成员还没有指纹 (322)", systemImage: "person.badge.shield.slash")
                    Spacer(minLength: 0)
                    NavigationLink {
                        StartAddFpView(embedded: true)
                    } label: {
                        Text("去录入")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(DS.Palette.accentText)
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Rectangle())
                    }
                }
                .font(.caption)
                .foregroundStyle(DS.Palette.warn)
                .accessibilityElement(children: .combine)
            }
            // 324 冗余横条: 该锁仅剩 1 枚可用指纹 → 直达添加
            if fps.count == 1 {
                NavigationLink {
                    StartAddFpView(embedded: true)
                } label: {
                    HStack(spacing: DS.Space.s) {
                        Label("只剩 1 枚可用指纹, 建议添加备用 (324)", systemImage: "bell.badge")
                        Spacer(minLength: 0)
                    }
                    .font(.caption)
                    .foregroundStyle(DS.Palette.warn)
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
                .listRowBackground(DS.Palette.warn.opacity(0.06))
                .accessibilityLabel("冗余横条: 添加备用指纹 (324)")
            }
            if fps.isEmpty {
                Text("本机还没有指纹台账。录入后成员可用手指直接开锁。")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(fps) { f in
                credRow(CredHit(id: "f\(f.batch)", fp: f, pinned: CredentialOrg.isStarred(mac, "fp", f.batch)))
            }
            NavigationLink { StartAddFpView(embedded: true) } label: { Label("录入指纹", systemImage: "plus") }
        }
    }

    // ---------- 355 成员视图 (未归属独立成段) ----------
    @ViewBuilder
    private var memberSections: some View {
        ForEach(DB.members()) { m in
            let pwds = DB.listPwds(mac).filter { $0.owner == m.id }
            let fps = DB.listFp(mac).filter { $0.owner == m.id }
            if !pwds.isEmpty || !fps.isEmpty {
                Section("\(CredentialOrg.aliasDisplay && !m.relation.isEmpty ? m.relation + " · " : "")\(m.name) (\(pwds.count + fps.count))") {
                    ForEach(pwds) { p in credRow(CredHit(id: "p\(p.alias)", pwd: p)) }
                    ForEach(fps) { f in credRow(CredHit(id: "f\(f.batch)", fp: f)) }
                }
            }
        }
        let noPwd = DB.listPwds(mac).filter { $0.owner == nil }
        let noFp = DB.listFp(mac).filter { $0.owner == nil }
        if !noPwd.isEmpty || !noFp.isEmpty {
            Section("未归属 (\(noPwd.count + noFp.count))") {
                ForEach(noPwd) { p in credRow(CredHit(id: "p\(p.alias)", pwd: p)) }
                ForEach(noFp) { f in credRow(CredHit(id: "f\(f.batch)", fp: f)) }
            }
        }
        Section {
            NavigationLink { AddPwdView(embedded: true) } label: { Label("添加密码", systemImage: "plus") }
            NavigationLink { StartAddFpView(embedded: true) } label: { Label("录入指纹", systemImage: "plus") }
        }
    }

    // ---------- 统一行渲染 (普通/搜索/成员/编辑模式共用; VoiceOver 合并成一条) ----------
    @ViewBuilder
    private func credRow(_ hit: CredHit) -> some View {
        let p = hit.pwd
        let f = hit.fp
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.s) {
                Text(titleOf(hit))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let p {
                    if CredentialOrg.pwdState(p) == 2 {
                        StatusPill(text: "已过期", systemImage: "clock.badge.xmark", tone: .danger)
                    } else if CredentialOrg.pwdState(p) == 1 {
                        StatusPill(text: "已排期", systemImage: "calendar.badge.clock", tone: .accent)
                    }
                }
                if let f, f.isAlarm == true {
                    StatusPill(text: "预警指纹", systemImage: "bell.badge", tone: .warn)
                }
                if let o = p?.owner ?? f?.owner, !o.isEmpty {
                    ownerBadge(CredentialOrg.ownerName(o))
                }
                Spacer(minLength: 0)
                if hit.pinned {
                    Image(systemName: "star.fill")
                        .font(.system(size: DS.Icon.sm, weight: .medium))
                        .foregroundStyle(DS.Palette.accentText)
                        .accessibilityLabel("已置顶")
                }
                if busyKey == ("p" + String(hit.id.dropFirst())) {
                    ProgressView().controlSize(.mini)
                }
            }
            if !subOf(hit).isEmpty {
                Text(subOf(hit))
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 918 命名模板: 主标题下挂 "谁-哪里-何时" 推断名 (锁端无名称字段, 本地展示)
            if let p, CredentialOrg.aliasDisplay, CredentialOrg.namingTemplate(p) != titleOf(hit) {
                Text(CredentialOrg.namingTemplate(p))
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        // 849 凭证朗读顺序 "名称-类型-状态" (不堆叠字段), 856 盲文简写走 value
        .accessibilityLabel(credVoLabel(hit))
        .accessibilityValue(AXTerms.br(credVoState(hit)))
        .contextMenu { credMenu(hit) }
        .overlay(alignment: .topLeading) {
            if editMode { selectionCircle(hit) }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard editMode else { return }
            toggleSel(hit)
        }
        .swipeActions(edge: .trailing) {
            if editMode {
                Button { toggleSel(hit) } label: {
                    Label(isSelected(hit) ? "取消选" : "选", systemImage: isSelected(hit) ? "xmark.circle" : "checkmark.circle")
                }
                .tint(DS.Palette.accent)
            }
            if let p {
                Button(role: .destructive) { disablePwd(p) } label: { Label("停用", systemImage: "pause.circle") }
                Button(role: .destructive) { deletePwd(p) } label: { Label("删除", systemImage: "trash") }
                Button { Task { resetPwdPeriod(p) } } label: { Label("改期", systemImage: "calendar") }.tint(DS.Palette.accent)
            }
            if let f {
                Button(role: .destructive) { disableFp(f) } label: { Label("停用", systemImage: "pause.circle") }
                Button(role: .destructive) { deleteFp(f) } label: { Label("删除", systemImage: "trash") }
            }
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            // 182 长按进入拖动序: 简化为长按提示, 重排走编辑模式逐行上移
            guard !editMode else { return }
            app.showToast("长按可停用/删除; 编辑模式里用「顺序」按钮调整组内先后")
        }
        .disabled(isBusy)
    }

    private func titleOf(_ hit: CredHit) -> String {
        if let p = hit.pwd { return CredentialOrg.displayPwd(p) }
        if let f = hit.fp { return f.name }
        return ""
    }
    /// 849 凭证朗读顺序: 名称-类型-状态 (密码/指纹/临时码 走 AXTerms 词表, 不混"密钥")
    private func credVoLabel(_ hit: CredHit) -> String {
        let kind = hit.pwd != nil
            ? (hit.pwd?.temp == true ? AXTerms.otp : AXTerms.pwd) : AXTerms.fp
        return AXTerms.credential + ": " + titleOf(hit) + ", " + kind
    }
    /// 856 状态字段简写 (盲文友好), 走 AXTerms.br
    private func credVoState(_ hit: CredHit) -> String {
        if let p = hit.pwd {
            switch CredentialOrg.pwdState(p) {
            case 2: return "已过期"
            case 1: return "已排期"
            default: return "可用"
            }
        }
        if let f = hit.fp {
            return f.isAlarm == true ? "预警指纹" : "可用"
        }
        return "可用"
    }

    private func subOf(_ hit: CredHit) -> String {
        if let p = hit.pwd {
            return [
                p.temp ? "一次性" : "",
                p.at > 0 ? "添加于 " + shortDate(p.at) : "",
                Milestones.companionText(p.at) ?? "",
                CredentialOrg.countdown(p),
                !p.note.isEmpty ? "备注 \(p.note)" : ""
            ].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        if let f = hit.fp {
            return [
                f.at > 0 ? "登记于 " + shortDate(f.at) : "已登记在门锁内",
                f.at > 0 ? Milestones.companionText(f.at, prefix: "入家") ?? "" : "",
                f.src == "app" ? "本机录入" : "",
                !f.note.isEmpty ? "备注 \(f.note)" : ""
            ].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return ""
    }

    @ViewBuilder
    private func credMenu(_ hit: CredHit) -> some View {
        if let p = hit.pwd {
            Button("查看密码内容") { viewPwd(p) }
            Button("密码详情 (305/308/309)") { pwdDetailItem = p }
            Button("修改密码内容") { modifyPwd(p) }
            Button("修改有效期") { Task { resetPwdPeriod(p) } }
            Button("添加备注") { editNote(pwd: p) }
            Menu("归属到成员") { ownerMenu(isPwd: true, key: p.alias) }
            Divider()
            Button("三档预警 (359)") { toggleAlerts(p) }
            Button(hit.pinned ? "取消置顶" : "置顶") {
                CredentialOrg.toggleStar(mac, "pwd", p.alias)
                DS.Haptics.tick.impactOccurred()
            }
            if let sug = CredentialOrg.starSuggestion(mac), sug == "p\(p.alias)" {
                Button("标为常用 (近 30 天约最常用, 921)") {
                    CredentialOrg.toggleStar(mac, "pwd", p.alias)
                }
            }
            Button("历史 (\(CredentialOrg.history(mac, "pwd", p.alias).count), 487)") {
                histItem = HistItem(kind: "pwd", key: p.alias)
            }
            Divider()
            Button("停用 (本地, 锁端待处理)", role: .destructive) { disablePwd(p) }
            Button("彻底删除 (670)", role: .destructive) { deletePwd(p) }
        }
        if let f = hit.fp {
            Button("指纹详情 (316/320/323)") { fpDetailItem = f }
            Button("重命名") { renameFp(f) }
            Button(f.isAlarm == true ? "取消预警指纹" : "设为预警指纹") {
                DB.setFpAlarm(mac, f.batch, f.isAlarm != true)
                app.showToast(f.isAlarm == true ? "已取消预警指纹" : "已设为预警指纹")
            }
            Button("添加备注") { editNote(fp: f) }
            Menu("归属到成员") { ownerMenu(isPwd: false, key: f.batch) }
            Button("历史 (\(CredentialOrg.history(mac, "fp", f.batch).count), 487)") {
                histItem = HistItem(kind: "fp", key: f.batch)
            }
            Button(hit.pinned ? "取消置顶" : "置顶") {
                CredentialOrg.toggleStar(mac, "fp", f.batch)
            }
            Divider()
            Button("停用 (本地, 锁端待处理)", role: .destructive) { disableFp(f) }
            Button("彻底删除 (670)", role: .destructive) { deleteFp(f) }
        }
    }

    // 成员归属徽章: 用 accentText (文字级对比度 6:1), 不用品牌填充色
    private func ownerBadge(_ name: String) -> some View {
        Text(name)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .foregroundStyle(DS.Palette.accentText)
            .padding(.horizontal, 7).padding(.vertical, DS.Space.xxs)
            .background(DS.Palette.accentText.opacity(0.12), in: Capsule())
    }

    // ---------- 347 编辑模式: 选择圈 + 全选循环 (356) + 智能选取 (350) ----------
    private var selCount: Int { selPwds.count + selFps.count }

    private var editList: some View {
        List {
            Section {
                HStack {
                    Button {
                        cycleSelect()
                        DS.Haptics.tick.impactOccurred()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cycleLabel)
                                .font(.subheadline.weight(.semibold))
                            Text("下一步: \(cycleNextLabel) (356)")
                                .font(.caption2)
                                .foregroundStyle(DS.Palette.textSub)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: DS.Hit.min)
                    Spacer(minLength: 0)
                    Button("顺序") {
                        // 182/352: 记住当前组内顺序 (置顶段单独记, 避免拖动段误伤置顶)
                        var seq = CredentialOrg.seq(mac)
                        seq["p"] = sortedPwds.map { $0.alias }
                        seq["f"] = sortedFps.map { $0.batch }
                        CredentialOrg.setSeq(mac, seq)
                        app.showToast("已记住当前组内顺序 (182/352)")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                }
                HStack(spacing: DS.Space.s) {
                    Text("智能选取 (350)")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                    ForEach(["已过期", "同成员", "同类型"], id: \.self) { s in
                        Button(s) { applySmart(s) }
                            .font(.caption.weight(.medium))
                            .buttonStyle(.bordered)
                            .frame(minHeight: DS.Hit.min)
                    }
                    Spacer(minLength: 0)
                }
            }
            Section("已选 (\(selCount))") {
                if selCount == 0 {
                    Text("点按行选择, 双指下滑连续选 (双指区划由系统滚动提供)。")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                listBody
            }
        }
        .listItemSpacing(DS.Space.xs)
    }

    private var cycleLabel: String {
        let total = DB.listPwds(mac).count + DB.listFps(mac).count
        if selCount == 0 { return "全选 (\(total) 条)" }
        if selCount == total { return "已全选 (\(total))" }
        return "已选 \(selCount) / \(total) — 反选"
    }
    private var cycleNextLabel: String {
        let total = DB.listPwds(mac).count + DB.listFps(mac).count
        if selCount == 0 { return "反选" }
        if selCount == total { return "清空" }
        return "全选"
    }
    private func cycleSelect() {
        let allP = DB.listPwds(mac).map { $0.alias }
        let allF = DB.listFp(mac).map { $0.batch }
        let total = allP.count + allF.count
        if selCount == 0 {
            selPwds = allP; selFps = allF
        } else if selCount == total {
            selPwds = []; selFps = []
        } else {
            selPwds = allP.filter { !selPwds.contains($0) }
            selFps = allF.filter { !selFps.contains($0) }
        }
    }
    private func applySmart(_ s: String) {
        let key = s == "已过期" ? "expired" : (s == "同成员" ? "sameowner" : "samekind")
        let r = CredentialOrg.smartSet(mac, set: key, base: (pwd: selPwds, fp: selFps))
        selPwds = r.pwd
        selFps = r.fp
        app.showToast("已套用「\(s)」 \(selPwds.count + selFps.count) 条")
        DS.Haptics.tick.impactOccurred()
    }
    private func selectionCircle(_ hit: CredHit) -> some View {
        let on = isSelected(hit)
        return Image(systemName: on ? "checkmark.circle.fill" : "circle")
            .font(.system(size: DS.Icon.md, weight: .medium))
            .foregroundStyle(on ? DS.Palette.accent : DS.Palette.textSub)
            .padding(.leading, 6)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
            .accessibilityLabel(on ? "已选中" : "未选中")
    }
    private func isSelected(_ hit: CredHit) -> Bool {
        if let p = hit.pwd { return selPwds.contains(p.alias) }
        if let f = hit.fp { return selFps.contains(f.batch) }
        return false
    }
    private func toggleSel(_ hit: CredHit) {
        if let p = hit.pwd {
            if let i = selPwds.firstIndex(of: p.alias) { selPwds.remove(at: i) } else { selPwds.append(p.alias) }
        } else if let f = hit.fp {
            if let i = selFps.firstIndex(of: f.batch) { selFps.remove(at: i) } else { selFps.append(f.batch) }
        }
    }

    // ---------- 批量操作栏 (347/348/349/351/353/357) ----------
    @ViewBuilder
    private var batchBar: some View {
        VStack(spacing: DS.Space.xs) {
            HStack {
                Text("已选 \(selCount) 条")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Button("完成") {
                    withAnimation(DS.Motion.quick) { editMode = false; selPwds = []; selFps = [] }
                }
                .font(.subheadline.weight(.medium))
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
            }
            HStack(spacing: DS.Space.xs) {
                batchBtn("延期", icon: "calendar.badge.clock") {
                    extendAliases = selPwds.isEmpty ? [] : selPwds
                    if selPwds.isEmpty { app.showToast("延期只作用于已选密码"); return }
                    showExtend = true
                }
                batchBtn("移交", icon: "person.2") {
                    if selCount == 0 { app.showToast("先选择凭证"); return }
                    showTransfer = true
                }
                batchBtn("前缀", icon: "textformat") {
                    showPrefixNote()
                }
                batchBtn("导出", icon: "square.and.arrow.up") {
                    exportPackage()
                }
                batchBtn("停用", icon: "pause.circle", destructive: true) {
                    if selCount == 0 { app.showToast("先选择凭证"); return }
                    showDisable = true
                }
            }
        }
        .padding(.horizontal, DS.Space.gutter)
        .padding(.vertical, DS.Space.s)
        .background(.bar)
        .accessibilityElement(children: .contain)
    }
    private func batchBtn(_ t: String, icon: String, destructive: Bool = false, _ a: @escaping () -> Void) -> some View {
        Button { a() } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: DS.Icon.md, weight: .medium))
                Text(t).font(.caption2)
            }
            .foregroundStyle(destructive ? DS.Palette.danger : DS.Palette.accentText)
            .frame(maxWidth: .infinity)
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(t), 作用于已选 \(selCount) 条")
    }

    private func showPrefixNote() {
        guard selCount > 0 else { app.showToast("先选择凭证"); return }
        let alert = UIAlertController(title: "前缀批量备注 (357)", message: "统一插入各备注开头, 如「2026春节-」", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "前缀" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "应用", style: .default) { _ in
            let s = (alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty else { return }
            let n = CredentialOrg.batchPrefixNote(mac, pwdAliases: selPwds, fpBatches: selFps, prefix: s)
            app.showToast("已给 \(n) 条加前缀")
            _ = Milestones.recordOrganize()
            reload()
        })
        UIApplication.topViewController()?.present(alert, animated: true)
    }

    /// 351 合包导出: 仅凭证分区的 AES 信封, 8 位数字口令单列生成 (不与凭证混发), 走分享面板
    private func exportPackage() {
        guard selCount > 0 else { app.showToast("先选择要导出的凭证"); return }
        let pw = KeyGen.randomDigits(8)
        guard let result = CredentialOrg.exportPackage(mac, pwdAliases: selPwds, fpBatches: selFps, password: pw) else {
            app.showToast("导出失败"); return
        }
        guard let text = String(data: result.data, encoding: .utf8) else { return }
        // 口令不进剪贴板: 明文凭证包与口令必须分开交付
        UIPasteboard.general.string = text
        app.showToast("已生成 \(result.size) 条凭证包并复制到剪贴板。解密密口令「\(pw)」请另行发送, 勿与凭证包同渠道。")
    }

    /// 353 批量停用摘要确认页之后的执行: 本地移除 + 回收站 + 锁端删除入队
    private func finishDisable() {
        guard busyKey == nil else { return }
        busyKey = "batch"
        Task { @MainActor in
            defer { busyKey = nil; editMode = false; selPwds = []; selFps = [] }
            let n = CredentialOrg.batchDisable(mac, pwdAliases: selPwds, fpBatches: selFps)
            if n > 0 {
                _ = Milestones.recordOrganize()
                app.flashReceipt("已写入本机 (508)")
                app.showToast("已停用 \(n) 条, 收入回收站, 锁端删除待下发")
                reload()
            } else {
                app.showToast("所选凭证已不在台账")
                reload()
            }
        }
    }

    // ---------- 智能列表 (527) 管理 ----------
    private func newSmartList() {
        final class Pick { var chosen: Set<String> = [] }
        let pick = Pick()
        let alert = UIAlertController(title: "新建智能列表 (527)", message: "把常用筛选组合存为命名快捷", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "名称 (如: 已过期访客)" }
        let sheet = UIAlertController(title: "筛选条件", message: "可多选, 全部满足才命中", preferredStyle: .actionSheet)
        for opt in ["密码", "指纹", "已过期", "无归属", "一年未用"] {
            let box = pick.chosen.contains(opt) ? "☑ " : "☐ "
            sheet.addAction(UIAlertAction(title: box + opt, style: .default) { _ in
                if pick.chosen.contains(opt) { pick.chosen.remove(opt) } else { pick.chosen.insert(opt) }
                if let top = UIApplication.topViewController(), top.presentedViewController === sheet {
                    top.dismiss(animated: true)
                }
                newSmartList()   // 重建弹层显示勾选态
            })
        }
        alert.addAction(UIAlertAction(title: "下一步", style: .default) { _ in
            let name = (alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { app.showToast("起个名字"); return }
            UIApplication.topViewController()?.present(sheet, animated: true)
        })
        sheet.addAction(UIAlertAction(title: "保存", style: .default) { _ in
            let kind = pick.chosen.contains("指纹") ? "fp" : "pwd"
            var state = ""
            if pick.chosen.contains("已过期") { state = "expired" }
            let tag = pick.chosen.contains("无归属") ? "noowner" : (pick.chosen.contains("一年未用") ? "stale" : "")
            var lists = CredentialOrg.smartLists(mac)
            let l = CredSmartList(id: UUID().uuidString, name: name, kind: kind, owner: "", state: state, tag: tag)
            lists.append(l)
            CredentialOrg.saveSmartLists(mac, lists)
            smartSel = l.id
            app.showToast("已套用智能列表「\(name)」")
        })
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        UIApplication.topViewController()?.present(alert, animated: true)
    }
    private func manageSmartLists() {
        let lists = CredentialOrg.smartLists(mac)
        guard !lists.isEmpty else { app.showToast("还没有智能列表"); return }
        let alert = UIAlertController(title: "管理智能列表 (527)", message: nil, preferredStyle: .actionSheet)
        for l in lists {
            alert.addAction(UIAlertAction(title: "删除「\(l.name)」", style: .destructive) { _ in
                CredentialOrg.saveSmartLists(mac, lists.filter { $0.id != l.id })
                if smartSel == l.id { smartSel = "" }
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        UIApplication.topViewController()?.present(alert, animated: true)
    }

    /// 363 月历点日 → 落到当日到期清单 (App 内滚动到位)
    private func pickDay(_ date: Date) {
        let items = CredentialOrg.dayDeadlines(mac, date)
        app.showToast("当日到期 \(items.count) 条: " + items.map { "#\($0.alias)" }.prefix(6).joined(separator: " ") + (items.count > 6 ? " …" : ""))
    }

    // ---------- OTP 内联卡 (App credentials + otpgenerate) ----------
    private var otpSection: some View {
        Section("临时密码 (ZOTP)") {
            Toggle("开通临时密码", isOn: Binding(
                get: { DB.otpStatus(mac)?.on ?? false },
                set: { on in
                    guard busyKey == nil else { return }
                    busyKey = "otp"
                    Task {
                        defer { busyKey = nil }
                        do {
                            try await app.lock.setZotp(on)
                            DB.saveOtpStatus(mac, OtpStatus(on: on, at: Date().timeIntervalSince1970 * 1000))
                            app.showToast(on ? "临时密码已开启" : "已关闭")
                        } catch {
                            app.showToast("操作失败: \(error.localizedDescription)")
                        }
                    }
                }))
                .disabled(isBusy)
            if DB.otpStatus(mac)?.on == true {
                otpGenRow
                Label {
                    Text("每 30 分钟更换一次; 生成前请先校准门锁时间 (偏差 >180 秒会导致锁侧校验失败)。")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle").accessibilityHidden(true)
                }
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
            }
        }
    }

    @ViewBuilder
    private var otpGenRow: some View {
        HStack(spacing: DS.Space.s) {
            Text(otpPwd)
                // 885 大字模式: 开关 (kf_ax_bigotp) 或双击切换, 等宽数字防跳 (231)
                .font((DB.store.getBool("kf_ax_bigotp") || otpBig) ? .largeTitle.weight(.semibold).monospacedDigit() : .title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(DS.Palette.text)
                .textSelection(.enabled)
                .onTapGesture(count: 2) { otpBig.toggle() }
                .accessibilityLabel("临时码, 双击切大字号")
            Spacer(minLength: DS.Space.m)
            Button {
                genOtp()
            } label: {
                Text("生成")
                    .frame(minHeight: DS.Hit.min)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy)
            Button {
                UIPasteboard.general.string = otpPwd
                app.showToast("已复制")
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: DS.Icon.md))
                    .frame(width: DS.Hit.min, height: DS.Hit.min)
                    .contentShape(Rectangle())
            }
            .disabled(otpPwd == "******")
            .accessibilityLabel("复制临时密码")
            .accessibilityHint("把当前临时密码复制到剪贴板")
        }
        if !otpWin.isEmpty {
            Text("于 \(otpWin) 失效, 失效前仅可使用一次")
                .font(.caption).foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private func genOtp() {
        guard busyKey == nil else { return }
        guard let kc = app.current, kc.skey.count == 32 else { app.showToast("缺少该锁钥匙串"); return }
        let win = ZOTP.nextWindow()
        let cur = DB.otpIdx(mac)
        let idx = (cur?.invalidTime == win) ? (cur?.idx ?? -1) + 1 : 0
        if idx > 99 {
            app.showToast("当前窗口已达 100 个上限, 请到下一个 30 分钟窗口再生成")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        let pwd = ZOTP.generate(macHex: kc.mac, skeyHex: kc.skey, periodSec: 30, idx: idx)
        DB.saveOtpIdx(mac, OtpIdx(idx: idx, invalidTime: win))
        otpPwd = pwd
        otpWin = win
        UIPasteboard.general.string = pwd
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private var emptyHint: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("本机还没有凭证台账。用「添加密码」或「录入指纹」开始。")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                // 包14/815 空态双按钮: 主"添加密码" + 次"看看它如何工作"
                HStack(spacing: DS.Space.s) {
                    NavigationLink { AddPwdView(embedded: true) } label: {
                        Text("添加第一条密码")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryActionStyle(fullWidth: false))
                    Button { showDemo = true } label: {
                        Text("看看它如何工作")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryActionStyle(fullWidth: false))
                    .accessibilityHint("打开演示锁试玩, 不碰真实门锁")
                }
                .padding(.top, DS.Space.xs)
                // 821 临时码零库存: 已开通但一张没发 → "酒店前台发门卡"比喻 + 首张按钮
                if DB.otpStatus(mac)?.on == true, DB.listPwds(mac).filter({ $0.temp }).isEmpty {
                    Text("临时码还没有发过一张 — 像酒店前台的门卡, 客人走一张, 就发下一张。")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("发第一张临时码") { genFirstOtp() }
                        .buttonStyle(SecondaryActionStyle(fullWidth: false))
                        .disabled(isBusy)
                }
            }
            .padding(.vertical, 2)
        }
    }
    /// 821 空台账场景"发第一张临时码": 走现有 genOtp 通路, 需锁在场
    private func genFirstOtp() {
        guard busyKey == nil else { return }
        busyKey = "otp"
        Task {
            defer { busyKey = nil }
            do {
                try await app.lock.ensureConnected(mac: mac)
                genOtp()
                app.showToast("第一张临时码已生成, 可让客人直接在锁键盘输入")
            } catch { app.showToast("需在场连接锁端: \(error.localizedDescription)") }
        }
    }

    // ---------- 506 误删撤销条: 删除后底部浮出 5 秒 "已删除 · 撤销", 撤销则原位还原不入回收站 ----------
    @ViewBuilder
    private var undoBar: some View {
        if let e = undoEntry {
            HStack(spacing: DS.Space.s) {
                Text("\(e.text) 已删除")
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Button("撤销") {
                    _ = CredentialOrg.undoBin(mac, entry: e)
                    undoEntry = nil
                    stopUndoTimer()
                    app.showToast("已原位还原 (506, 未入回收站)")
                    reload()
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DS.Palette.accentText)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
            }
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.s)
            .background(DS.Palette.surface)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .combine)
            .accessibilityHint("5 秒内点按撤销可原位还原, 不入回收站")
        }
    }
    private func armUndo(_ entry: CredBinEntry) {
        undoEntry = entry
        withAnimation(DS.Motion.standard) { undoEntry = entry }
        startUndoTimer()
    }
    private func startUndoTimer() {
        stopUndoTimer()
        let t = DispatchSource.makeTimerSource()
        t.schedule(deadline: .now() + 5)
        t.setEventHandler {
            guard undoEntry != nil else { return }
            withAnimation(DS.Motion.exit) { undoEntry = nil }
        }
        undoTimer = t
        t.resume()
    }
    private func stopUndoTimer() {
        undoTimer?.cancel()
        undoTimer = nil
    }

    // ---------- 动作 ----------
    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd"
        return f
    }()
    private func shortDate(_ ts: Double) -> String {
        Self.shortDateFormatter.string(from: Date(timeIntervalSince1970: ts / 1000))
    }

    private func viewPwd(_ p: LedgerPwd) {
        guard let pwd = p.pwd else { app.showToast("当时未留存明文"); return }
        if DB.hasPasscode() && !app.appUnlocked { app.showToast("需先解锁应用锁"); return }
        app.showToast("密码 #\(p.alias): \(pwd) (请勿外传)")
    }

    private func modifyPwd(_ p: LedgerPwd) {
        guard busyKey == nil else { return }
        let alert = UIAlertController(title: "修改密码 (#\(p.alias))", message: "修改后旧密码立即作废, 需使用新密码开锁。", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "新密码 6~8 位数字"; $0.keyboardType = .numberPad }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        // 旧密码即刻作废 = 破坏性, 按钮必须显式标红, 不能伪装成普通确认
        alert.addAction(UIAlertAction(title: "作废旧密码", style: .destructive) { _ in
            let np = alert.textFields?.first?.text ?? ""
            guard np.count >= 6, np.count <= 8, np.allSatisfy({ $0.isNumber }) else { app.showToast("需 6~8 位数字"); return }
            busyKey = "pwd:\(p.alias)"
            Task {
                defer { busyKey = nil }
                do {
                    try await app.lock.ensureConnected(mac: mac)
                    let aliasOut = try await app.lock.pwdModify(alias: p.alias, pwd: np, validFrom: p.from, validTo: p.to)
                    DB.rePwd(mac, p.alias, np)
                    if aliasOut != p.alias {
                        DB.addPwd(mac, LedgerPwd(alias: aliasOut, from: p.from, to: p.to, temp: p.temp, at: Date().timeIntervalSince1970 * 1000, pwd: np, owner: p.owner, note: p.note))
                        DB.delPwd(mac, p.alias)
                    }
                    // 487 保存自动快照: 改值即留一档 (值/时段/备注)
                    let finalAlias = aliasOut == p.alias ? p.alias : aliasOut
                    if let p2 = DB.getPwd(mac, finalAlias) {
                        CredentialOrg.snapshot(mac, kind: "pwd", key: finalAlias, pwd: p2, fp: nil, note: "修改了密码值")
                    }
                    showToastOrganized("已修改, 旧密码已作废")
                } catch { app.showToast("修改失败: \(error.localizedDescription)") }
            }
        })
        UIApplication.topViewController()?.present(alert, animated: true)
    }

    private func resetPwdPeriod(_ p: LedgerPwd) {
        guard busyKey == nil else { return }
        // 重发 0B 会覆盖锁内有效期, 与「删除」同级别, 先知会再执行
        confirmDestructive("修改有效期", "将按原有效期重新下发到门锁 (\(periodText(p)))。确定继续吗？", confirmTitle: "重新下发") {
            Task { await self.doResetPwdPeriod(p) }
        }
    }
    private func doResetPwdPeriod(_ p: LedgerPwd) async {
        guard busyKey == nil else { return }
        busyKey = "pwd:\(p.alias)"
        defer { busyKey = nil }
        do {
            try await app.lock.ensureConnected(mac: mac)
            try await app.lock.pwdExpire(p.alias, p.from, p.to)
            CredentialOrg.snapshot(mac, kind: "pwd", key: p.alias, pwd: p, fp: nil, note: "修改了有效期")
            DB.setPwdPeriod(mac, p.alias, p.from, p.to)
            app.showToast("已更新有效期")
        } catch { app.showToast("更新失败: \(error.localizedDescription)") }
    }

    private func periodText(_ p: LedgerPwd) -> String {
        if p.to.hasPrefix("2118") { return "长期有效" }
        return "到 \(p.to.prefix(16).replacingOccurrences(of: "T", with: " ")) 失效"
    }

    /// 364/180/360 停用: 本地移除 + 回收站 (7 天恢复窗口), 锁端删除入队 (本地意图, UI 标注)
    private func disablePwd(_ p: LedgerPwd) {
        guard busyKey == nil else { return }
        confirmDestructive("停用密码 #\(p.alias)",
                          "停用后本机台账立即移除并收入回收站 — 7 天内可一键恢复, 超期需重新下发; 锁端删除记为「待下发」。",
                          confirmTitle: "停用") {
            CredentialOrg.addToBin(mac, pwd: p, source: .manual)
            DB.delPwd(mac, p.alias)
            CredentialOrg.enqueue(mac, kind: "del_pwd", title: "删除密码 #\(p.alias)")
            if let e = CredentialOrg.bin(mac).first(where: { $0.pwd?.alias == p.alias }) {
                armUndo(e)
            }
            showToastOrganized("已停用, 7 天内可恢复 (364)")
        }
    }
    private func disableFp(_ f: LedgerFp) {
        guard busyKey == nil else { return }
        confirmDestructive("停用指纹「\(f.name)」",
                          "停用后本机台账立即移除并收入回收站 — 7 天内可一键恢复, 超期需重新录入; 锁端删除记为「待下发」。",
                          confirmTitle: "停用") {
            CredentialOrg.addToBin(mac, fp: f, source: .manual)
            DB.delFp(mac, f.batch)
            CredentialOrg.enqueue(mac, kind: "del_fp", title: "删除指纹「\(f.name)」")
            if let e = CredentialOrg.bin(mac).first(where: { $0.fp?.batch == f.batch }) {
                armUndo(e)
            }
            showToastOrganized("已停用, 7 天内可恢复 (364)")
        }
    }

    /// 彻底删除: 锁端删除 + 本地删前快照 (494 双通道), 670 后果文案具体化
    private func deletePwd(_ p: LedgerPwd) {
        guard busyKey == nil else { return }
        confirmDestructive("彻底删除密码 #\(p.alias)",
                           "删除后该密码在锁内立即失效, 本机台账移除 (回收站 30 天内可找回记录, 但密码值需重新生成下发才有效)。确定继续？",
                           confirmTitle: "彻底删除") {
            Task { await self.doDeletePwd(p) }
        }
    }
    private func doDeletePwd(_ p: LedgerPwd) async {
        guard busyKey == nil else { return }
        busyKey = "pwd:\(p.alias)"
        defer { busyKey = nil }
        do {
            try await app.lock.ensureConnected(mac: mac)
            try await app.lock.pwdDelete(p.alias)
            CredentialOrg.addToBin(mac, pwd: p, source: .manual)   // 494 删前快照 + 回收站双通道
            DB.delPwd(mac, p.alias)
            if let e = CredentialOrg.bin(mac).first(where: { $0.pwd?.alias == p.alias }) {
                armUndo(e)
            }
            showToastOrganized("已彻底删除")
        } catch { app.showToast("删除失败: \(error.localizedDescription)") }
    }

    private func deleteFp(_ f: LedgerFp) {
        guard busyKey == nil else { return }
        confirmDestructive("彻底删除指纹「\(f.name)」",
                           "删除后果: 该指纹在锁内立即失效且无法远程补录 — 需成员本人到锁前重新录入 8 次指压。本机记录进回收站 30 天。确定继续？",
                           confirmTitle: "彻底删除") {
            Task { await self.doDeleteFp(f) }
        }
    }
    private func doDeleteFp(_ f: LedgerFp) async {
        guard busyKey == nil else { return }
        busyKey = "fp:\(f.batch)"
        defer { busyKey = nil }
        do {
            try await app.lock.ensureConnected(mac: mac)
            try await app.lock.fpDelete(UInt32(f.batch))
            CredentialOrg.addToBin(mac, fp: f, source: .manual)
            DB.delFp(mac, f.batch)
            if let e = CredentialOrg.bin(mac).first(where: { $0.fp?.batch == f.batch }) {
                armUndo(e)
            }
            showToastOrganized("已彻底删除")
        } catch { app.showToast("删除失败: \(error.localizedDescription)") }
    }

    private func renameFp(_ f: LedgerFp) {
        let alert = UIAlertController(title: "重命名指纹", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "如: 主人大拇指"; $0.text = f.name }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            let name = (alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            var np = f
            np.name = name
            CredentialOrg.snapshot(mac, kind: "fp", key: f.batch, pwd: nil, fp: np, note: "改了名称")
            DB.renameFp(mac, f.batch, name)
            refreshTick += 1
        })
        UIApplication.topViewController()?.present(alert, animated: true)
    }

    private func editNote(pwd: LedgerPwd? = nil, fp: LedgerFp? = nil) {
        let alert = UIAlertController(title: "凭证备注", message: "仅本机留存, 随全量备份换机", preferredStyle: .alert)
        alert.addTextField { $0.text = pwd?.note ?? fp?.note ?? "" }
        alert.addAction(UIAlertAction(title: "清除", style: .destructive) { _ in
            if let p = pwd {
                var np = p; np.note = ""
                CredentialOrg.snapshot(mac, kind: "pwd", key: p.alias, pwd: np, fp: nil, note: "改了备注")
                DB.setPwdNote(mac, p.alias, "")
            }
            if let f = fp {
                var nf = f; nf.note = ""
                CredentialOrg.snapshot(mac, kind: "fp", key: f.batch, pwd: nil, fp: nf, note: "改了备注")
                DB.setFpNote(mac, f.batch, "")
            }
            _ = Milestones.recordOrganize()
            refreshTick += 1
        })
        alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in
            let note = (alert.textFields?.first?.text ?? "")
            if let p = pwd {
                var np = p; np.note = note
                CredentialOrg.snapshot(mac, kind: "pwd", key: p.alias, pwd: np, fp: nil, note: "改了备注")
                DB.setPwdNote(mac, p.alias, note)
            }
            if let f = fp {
                var nf = f; nf.note = note
                CredentialOrg.snapshot(mac, kind: "fp", key: f.batch, pwd: nil, fp: nf, note: "改了备注")
                DB.setFpNote(mac, f.batch, note)
            }
            _ = Milestones.recordOrganize()
            refreshTick += 1
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        UIApplication.topViewController()?.present(alert, animated: true)
    }

    /// 1007 维护致谢: 整理动作计数, 每 10 次附一句致谢
    private func showToastOrganized(_ base: String) {
        let thanks = Milestones.recordOrganize()
        app.showToast(thanks ? base + " · 谢谢你把家管得井井有条" : base)
        refreshTick += 1
    }

    @ViewBuilder
    private func ownerMenu(isPwd: Bool, key: Int) -> some View {
        ForEach(DB.members()) { m in
            Button(m.name) {
                if isPwd { DB.setPwdOwner(mac, key, m.id) } else { DB.setFpOwner(mac, key, m.id) }
                _ = Milestones.recordOrganize()
                refreshTick += 1
            }
        }
        Button("解除归属", role: .destructive) {
            if isPwd { DB.setPwdOwner(mac, key, nil) } else { DB.setFpOwner(mac, key, nil) }
            refreshTick += 1
        }
    }

    /// 359 三档预警: 7 天 / 24 小时走本地通知日历排程, 2 小时档 App 内插提醒行
    private func toggleAlerts(_ p: LedgerPwd) {
        let a = CredentialOrg.alert(mac, p)
        let sheet = UIAlertController(title: "三档预警 #\(p.alias) (359)",
                                     message: "长期有效密码无到期点, 不适用。",
                                     preferredStyle: .actionSheet)
        func addTier(_ title: String, current: Bool, toggle: @escaping () -> Void) {
            sheet.addAction(UIAlertAction(title: (current ? "○ " : "◉ ") + title, style: .default, handler: toggle))
        }
        addTier("到期前 7 天提醒", current: a.day) {
            var n = a; n.day.toggle()
            CredentialOrg.saveAlert(mac, p, n)
            CredentialOrg.scheduleAlerts(mac, p, n)
            app.showToast(n.day ? "已开 7 天档" : "已关 7 天档")
        }
        addTier("到期前 24 小时提醒", current: a.h24) {
            var n = a; n.h24.toggle()
            CredentialOrg.saveAlert(mac, p, n)
            CredentialOrg.scheduleAlerts(mac, p, n)
            app.showToast(n.h24 ? "已开 24 小时档" : "已关 24 小时档")
        }
        addTier("到期前 2 小时提醒 (App 内提醒行)", current: a.h2) {
            var n = a; n.h2.toggle()
            CredentialOrg.saveAlert(mac, p, n)
            app.showToast(n.h2 ? "已开 2 小时档" : "已关 2 小时档")
        }
        if p.to.hasPrefix("2118") {
            let off = UIAlertAction(title: "了解", style: .cancel)
            sheet.actions = [off]
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        UIApplication.topViewController()?.present(sheet, animated: true)
    }
}

/// 487 历史页路由载荷 (contextMenu 里只能存值, 元组不满足 Identifiable)
struct HistItem: Identifiable, Hashable {
    var kind: String
    var key: Int
    var id: String { kind + ":" + String(key) }
}

// ================= 全局弹窗助手 (各页面共用, 不再各写一份) =================
// 破坏性确认: 取消 / 标红确认
func confirmDestructive(_ title: String,
                        _ message: String,
                        confirmTitle: String = "确定",
                        action: @escaping () -> Void) {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: confirmTitle, style: .destructive) { _ in action() })
    UIApplication.topViewController()?.present(alert, animated: true)
}

extension UIApplication {
    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var vc = scene?.keyWindow?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }
}
