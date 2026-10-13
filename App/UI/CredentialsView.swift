// 凭证 Tab (credentials 页) — 密码/指纹台账 + OTP + 包6 列表组织·批量·流转
// 交互约定: 与门锁通信期间整页置为忙碌 (busyKey), 杜绝 swipe/菜单并发下发指令;
// 所有破坏性动作统一走 confirmDestructive, 不在本文件重复实现弹窗。
// 906 分段计数徽标 = 下面这四处里的"分段计数"那一处 (与 524/525 首字索引条同源，不另建计数键)。
// 包6 落地: 分段计数 (524/525 首字索引条随成员视图) / 双视图分组 (355) / 三态分组头 (528) /
// 置顶星标 (526/921) / 智能列表 (527) / 四维排序 (914) / 命名模板 (918) / 别名显示 (919) /
// 编辑模式 (347/356/357) / 组内拖动排序 (182 排序档) / 统一延期 (348) / 批量移交 (349) / 智能选取 (350) /
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
    @State private var otpPeek = false  // 375 磨砂挡片长按移开中 (松手复位)
    @ObservedObject private var cap = ScreenCaptureWatch.shared   // 374 录屏遮罩

    // ---------- 包6 列表组织 ----------
    @State private var seg: Int = 0          // 524 类型分段: 0 全部 / 1 密码 / 2 指纹 / 3 临时码
    @State private var memberView = CredentialOrg.groupMode == .owner   // 355 按成员视图
    @State private var smartSel: String = "" // 527 智能列表选中 id ("" = 默认)
    @State private var sortKey: CredSortKey = CredentialOrg.sortKey   // 914
    @State private var showCalendar = false  // 363 月历
    @State private var showOrganize = false  // 358 整理建议中心
    @State private var search = ""
    @State private var undoEntry: CredBinEntry?
    @State private var undoHard = false                    // 506 撤销条属于哪条路: 停用(false) / 彻底删除(true)
    @State private var undoTeachOnce = false      // 833 只在第一次删除时附那一句防误删说明
    @State private var undoTimer: DispatchSourceTimer?
    // 347 编辑模式
    @State private var editMode = false
    // 182 排序档: 与编辑模式互斥的第二种"行内控件"形态。开启时 List 进系统编辑态,
    // 带 onMove 的那几个分组当场出现排序把手 (本仓第一处拖动排序在 DeviceManageView:125, 写法照它)。
    @State private var sorting = false
    @State private var selPwds: [Int] = []
    @State private var selFps: [Int] = []
    @State private var showExtend = false
    @State private var extendAliases: [Int] = []
    @State private var showTransfer = false
    @State private var showDisable = false
    @State private var showQueue = false
    @State private var showBin = false
    /// 532 搜索兜底: 「去回收站搜」要把当前搜索词递进回收站, 而不是只把门打开 (空搜索框等于把人丢回原地)
    @State private var binQuery = ""
    @State private var showDemo = false   // 包14/834 30 秒演示链接
    @State private var pwdDetailItem: LedgerPwd?   // 包5 PwdDetailStudio
    @State private var fpDetailItem: LedgerFp?     // 包5 FpDetailStudio
    @State private var histItem: HistItem?
    @State private var jumpBarOn = false           // 577: 条子要活过 consumeCredJump 清 nil 的那一步

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
                        // 29 上下文工具栏 (Photos 式): 选中态才出现的这条 batchBar 就是它——
                        // 与 922 批量整理共用同一个 editMode，不另做一套"选中后的浮动条"。
                        // 未选中时整条不占位: 常驻工具栏会让用户以为那些按钮现在也能点。
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
                consumeCredPanel()  // 366/1013: 本地通知点按要打开的面板
                consumeCredSelect() // 358: 整理建议带回的多选预勾选
            }
            .onChange(of: app.pendingCredNav) { _, _ in consumeCredJump() }
            .onChange(of: app.pendingCredPanel) { _, _ in consumeCredPanel() }
            .onChange(of: app.pendingCredSelect) { _, _ in consumeCredSelect() }
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
                    CredBinView(mac: mac, initialQuery: binQuery)
                        .toolbar { ToolbarItem(placement: .navigationBarLeading) {
                            Button("关闭") { showBin = false; binQuery = "" }
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
        if jumpBarOn {
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
                    jumpBarOn = false
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
        var opened = false
        if nav.hasPrefix("pwd:"), let a = Int(nav.dropFirst(4)), DB.getPwd(mac, a) != nil {
            pwdDetailItem = DB.getPwd(mac, a); opened = true
        } else if nav.hasPrefix("fp:"), let b = Int(nav.dropFirst(3)), DB.getFp(mac, b) != nil {
            fpDetailItem = DB.getFp(mac, b); opened = true
        }
        // 577: 真弹出详情才挂条; 找不到不挂, 别让条替没做到的事说话 (旧 toast 无差别弹, 已并进本判定)
        jumpBarOn = opened
    }

    /// 366/1013: 通知面板落地。面板名由 CredentialOrg.applyNotification 写入;
    /// 未知名字只切到本 Tab 不猜要开哪个面板 (与 handleNotificationAction 的 fail-closed 口径一致)。
    private func consumeCredPanel() {
        guard let p = app.pendingCredPanel else { return }
        app.pendingCredPanel = nil
        switch p {
        case "bin":
            binQuery = ""   // 532: 只有「去回收站搜」那个动作才带词, 通知落地那条路不带
            showBin = true
        case "queue": showQueue = true
        case "organize", "expired": showOrganize = true
        default: app.showToast("已跳到凭证页")
        }
    }

    /// 358: 整理建议行点按带回的多选预勾选。就地进编辑模式并勾好 —— 与「选择」按钮同一条状态机
    /// (editMode/selPwds/selFps), 不另造一套选中集; 排序档互斥照 :379 的口径先关掉再进。
    private func consumeCredSelect() {
        guard let ids = app.pendingCredSelect else { return }
        app.pendingCredSelect = nil
        sorting = false
        withAnimation(DS.Motion.quick) { editMode = true }
        selPwds = ids
        selFps = []
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
                Button { showCalendar.toggle(); sorting = false } label: {
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
                // 922 凭证批量整理 = 这个入口 (「选择」进多选，批量删除/停用与 313 四选一原因同源)。
                // 479 长辈模式刻意隐藏: 批量入口对老人是误删风险，不是漏适配。
                // 182 排序档开着时同样不出现: 一行不能同时挂两套行内控件 (选择圈 + 排序把手)。
                if !editMode && !sorting && !MemberHub.elderMode {   // 479 长辈模式隐藏批量与导出入口
                    Button("选择") {
                        withAnimation(DS.Motion.quick) { editMode = true }
                        DS.Haptics.tick.impactOccurred()
                    }
                    .frame(minHeight: DS.Hit.min)
                }
                // 182 组内拖动排序的入口。原先这句承诺写在密码段底部那一行提示上 (「长按行拖动可调整组内顺序」),
                // 而拖动一处都没实现, 长按只弹一条"用编辑模式里的顺序按钮"的提示 —— 那是假热区。这里给真开关:
                // 打开后 List 进系统编辑态, 带 onMove 的分组当场出现把手, 拖完写 kf_cseq_ 跨启动保持。
                // 台账一条凭证都没有时不出现这一枚: 空列表没有可拖的行, 摆一个把手就是哑按钮。
                if !editMode && !showCalendar && CredentialOrg.typeCounts(mac).all > 0 {
                    Button {
                        sorting.toggle()
                        if sorting { editMode = false; selPwds = []; selFps = [] }
                        DS.Haptics.tick.impactOccurred()
                    } label: {
                        Image(systemName: sorting ? "checkmark" : "line.3.horizontal")
                            .font(.system(size: DS.Icon.md, weight: .semibold))
                            .foregroundStyle(sorting ? DS.Palette.accentText : DS.Palette.text)
                            .frame(width: DS.Hit.min, height: DS.Hit.min)
                            .contentShape(Rectangle())
                    }
                    // 图标而不是文字: 这一条工具栏已有三枚图标 + 「选择」, 再塞一枚文字按钮在窄屏上会挤破版
                    .accessibilityLabel("组内拖动排序 \(sorting ? "已开, 点按结束" : "未开, 点按开始") (182)")
                    .accessibilityAddTraits(sorting ? .isSelected : [])
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
                    CredentialOrg.setGroupMode(memberView ? .owner : .type)
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
                        // 菜单行给全标签 (名称 · 属主 · 状态); 外面的胶囊仍只显示名称, 长标签会被 lineLimit(1) 截断
                        Button(CredentialOrg.smartListLabel(l)) { smartSel = l.id }
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
        // 479 长辈模式: 只留 全部/密码/指纹 三组, 隐藏临时码组与批量/导出入口; 字号同步行本体那一档 (大字)
        let labels = MemberHub.elderMode ? ["全部", "密码", "指纹", ""] : ["全部", "密码", "指纹", "临时码"]
        let c = countForSeg(i)
        let on = seg == i
        return Button {
            seg = i
            DS.Haptics.tick.impactOccurred()
        } label: {
            HStack(spacing: DS.Space.xxs) {
                Text(labels[i]).font(elderOn ? .body.weight(.medium) : .caption.weight(.medium))
                if c > 0 {
                    Text("\(c)")
                        .font(elderOn ? .body.weight(.semibold) : .caption2.weight(.semibold))
                        .foregroundStyle(on ? DS.Palette.onAccent : DS.Palette.textSub)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(on ? DS.Palette.onFillWash.opacity(0.24) : DS.Palette.surfaceAlt, in: Capsule())
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
            if sorting { sortHintRow }         // 182: 处在排序档就把规则写在同一屏, 不让人猜拖了会怎样
            if showFirstCredRouter { firstCredRouter }   // 806 首录分流
            listBody
        }
        .listRowSpacing(DS.Space.xs)   // 批量操作行距保持宽松 (纪律: 批量行距)
        // 182: 排序把手由系统编辑态提供 —— 这一句是本仓第二处 onMove, 第一处 (设备页 766) 就是这么进的。
        // 用 .constant 而不是让系统自己切: 这一页的 editMode (347 多选) 是另一套行内控件, 两者必须各管各的。
        .environment(\.editMode, .constant(sorting ? .active : .inactive))
    }
    /// 182 排序档的说明行: 只承诺这一档真做得到的事 (段内先后 + 落 kf_cseq_ 跨启动)。
    @ViewBuilder
    private var sortHintRow: some View {
        HintRow(text: "拖动行尾的排序把手调整本段先后 (182)。先后写进本机台账: 跨启动保持, 并随全量备份一起走。"
                + "类型视图里各状态段各排各的, 置顶段不参与; 按成员视图里排的是这个成员段内 密码 与 指纹 各自的先后。")
            .listRowBackground(DS.Palette.accentText.opacity(0.06))
    }

    // ---------- 806 凭证首录分流 (1Password 那一形态) ----------
    // 原句是"首次添加凭证**弹**三选一卡"。这里做成列表顶部的常驻分流卡而不是自动弹窗：
    // 引导 (Onboarding) 刚走完就叠第二层弹窗，是"关不掉的第二层"，而这张卡上的三个入口
    // 本来就是页面里已有的那三个 —— 收进 List 第一行既说清了区别，也不抢走焦点。
    // 只在**这把锁一条凭证都没有**时出现，录进第一条或用户自己关掉之后就不再挡路 (HintOnce)。
    private var showFirstCredRouter: Bool {
        !HintOnce.shown("806") && DB.listPwds(mac).isEmpty && DB.listFps(mac).isEmpty
    }
    @ViewBuilder
    private var firstCredRouter: some View {
        Section {
            NavigationLink { AddPwdView(embedded: true) } label: {
                routerRow("lock.open.rotation", "长期密码",
                          "自己与全家日常用 · 没有到期点，可随时改或删")
            }
            NavigationLink { StartAddFpView(embedded: true) } label: {
                routerRow("hand.raised.fill", "录指纹",
                          "给固定的人 (家人/钟点工) · 一次录入长期可用")
            }
            NavigationLink { TempCodeStudio() } label: {
                routerRow("person.2.arrow.trajectory.circle", "临时码",
                          "给访客/租客 · 定好生效与到期，到点自动作废")
            }
            Button("以后不再显示这张卡") {
                HintOnce.mark("806")
                app.showToast("这张分流卡不会再出现 (可在页里的入口随时添加)")
            }
            .font(.footnote)
            .foregroundStyle(DS.Palette.textSub)
            .frame(minHeight: DS.Hit.min)
        } header: {
            Text("先说清你要哪一种 (806)")
        } footer: {
            Text("三类都是本机台账 + 一次下发到锁，全程离线。选错了也不会锁死人：随时能改或删。")
                .font(.caption2)
        }
    }
    private func routerRow(_ symbol: String, _ title: String, _ scene: String) -> some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: symbol)
                .font(.system(size: DS.Icon.md))
                .foregroundStyle(DS.Palette.accentText)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DS.Palette.text)
                Text(scene)
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: DS.Hit.min)
        .accessibilityElement(children: .combine)
    }

    /// 列表内容抽成 ViewBuilder: 编辑模式与正常模式共用, 避免嵌套两个 List
    @ViewBuilder
    private var listBody: some View {
            searchSection
            queueSection
            stockSection
            dueSoonBanner
            otpStockHint
            archivedStrip
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
            // 354: 全归档不算"台账空" — 归档区那张卡就是这批条目的落点, 谎报"还没有台账"会导向重复建码
            if memberView || (!memberView && sortedPwds.isEmpty && sortedFps.isEmpty
                              && CredentialOrg.archived(mac).isEmpty) {
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
                    // 532 搜索兜底动作: 两个入口都要把"当前这次搜索的意图"真递过去, 不能只换个面。
                    // 原先「去回收站搜」只开弹窗不带词 (空搜索框 = 把人丢回原地), 「按成员重搜」只切分组视图
                    // 却弹「已按成员 X 过滤」那句回执 —— 承诺的结果没发生, 属于假回执。
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text("没有找到「\(search)」")
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                        HStack(spacing: DS.Space.s) {
                            Button {
                                binQuery = search.trimmingCharacters(in: .whitespaces)
                                showBin = true
                            } label: {
                                Label("去回收站搜 (503)", systemImage: "magnifyingglass.circle")
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .accessibilityLabel("带着 \(search) 去回收站搜 (503)")
                            Button {
                                let q = search.trimmingCharacters(in: .whitespaces)
                                let m = DB.members().first { $0.name.localizedCaseInsensitiveContains(q) || $0.relation.localizedCaseInsensitiveContains(q) }
                                if let m {
                                    // 真过滤: 把搜索词换成这位成员**在搜索命中范围里出现的那一串**。
                                    // filteredResults 的 hay 里归属字段走 CredentialOrg.ownerName —— 别名显示档 (919) 下
                                    // 那一格是称呼 (relation) 而不是姓名, 所以直接塞姓名会搜不到 TA 名下凭证 (假重搜)。
                                    let term = CredentialOrg.ownerName(m.id)
                                    search = term.isEmpty ? m.name : term
                                    CredentialOrg.pushSearchHistory(search)
                                    app.showToast("已改用「\(search)」重搜 (532), 命中的是名称/备注/别名/归属")
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
        for f in DB.listFps(mac) {
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
        // 同批: 入口钉住 (CredentialCenterView.retry 是同型形状的另一份)
        let m = mac
        guard !m.isEmpty else { app.showToast("未选择门锁"); return }
        busyKey = "queue:\(item.id)"
        Task {
            defer { busyKey = nil }
            do {
                try await app.lock.ensureConnected(mac: m)
                let extra = try await CredentialOrg.sendQueued(m, app.lock, item)
                CredentialOrg.markQueue(m, id: item.id, state: .done, note: item.title + " · 锁端确认" + extra)
                app.showToast("\(item.title) 已下发")
            } catch {
                CredentialOrg.markQueue(m, id: item.id, state: .failed, note: item.title + " · 第 \(item.attempt + 1) 次失败")
                app.showToast("重试失败: \(error.localizedDescription)")
            }
        }
    }

    // ---------- 359 到期提醒行 (2 小时档, Hero 卡下方等价物) ----------
    @ViewBuilder
    private var dueSoonBanner: some View {
        let due = CredentialOrg.dueSoonPwds(mac)
        if !due.isEmpty {
            Button {
                // 359: 点按落**最近一条**到期 (与行内名单同一个 filter 的结果, 不另算一份)
                if let next = due.min(by: { (CredentialOrg.expiryDate($0) ?? .distantFuture) < (CredentialOrg.expiryDate($1) ?? .distantFuture) }) {
                    pwdDetailItem = next
                }
            } label: {
                HStack(spacing: DS.Space.xs) {
                    Label {
                        Text("\(due.count) 条密码 2 小时内到期 (已开 2 小时档预警)")
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.circle.fill")
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: DS.Icon.xs, weight: .semibold))
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(DS.Palette.warn)
            .listRowBackground(DS.Palette.warn.opacity(0.06))
            .accessibilityLabel("\(due.count) 条密码 2 小时内到期, 点按查看最近到期的一条详情 (359)")
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
                // 口径修正: pStock/fStock 是锁内**剩余**容量, 旧写法拿"剩余 − 本机条数"当作
                // "锁内多出的未知凭证数", 数值与结论都是错的 (正例见 Sheets:959 的 cap − stock)。
                // 已用 = 容量上限 − 剩余; 上限未知 (旧快照无 KLV#24/#27) 时不做推断, 宁可不显示。
                let snap = DB.readStatus(mac)
                let dp: Int
                if let cap = snap?.pwdCap, cap > 0, pStock >= 0 {
                    dp = max(0, (cap - pStock) - DB.listPwds(mac).count)
                } else { dp = 0 }
                let df: Int
                if let cap = snap?.fpCap, cap > 0, fStock >= 0 {
                    df = max(0, (cap - fStock) - DB.listFps(mac).count)
                } else { df = 0 }
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
    private var sortedPwds: [LedgerPwd] { orderedPwds(segFilteredPwds()) }
    /// 182 拖动排序的回写基准 = **全量**显示序 (不扣分段、不套智能筛选)。
    /// 拿"屏幕上这一批"回写整表, 没显示的那批会被推到表尾 —— 分段是展示层的事, 顺序是台账层的事。
    private var seqBasePwds: [LedgerPwd] { orderedPwds(DB.listPwds(mac)) }

    private func segFilteredPwds() -> [LedgerPwd] {
        var pwds = DB.listPwds(mac)
        if seg == 1 || seg == 3 {
            pwds = pwds.filter { seg == 3 ? $0.temp : !$0.temp }
        }
        if let l = CredentialOrg.smartLists(mac).first(where: { $0.id == smartSel }), l.kind != "fp" {
            pwds = pwds.filter { p in
                if l.owner != "", p.owner != l.owner { return false }
                if !l.state.isEmpty, CredentialOrg.stateString(CredentialOrg.pwdState(p)) != l.state { return false }
                if l.tag == "stale" { return p.at > 0 && CredentialOrg.nowSec - p.at / 1000 > 365 * 86400 }
                if l.tag == "noowner" { return p.owner == nil }
                return true
            }
        }
        // 460 归档成员不参与当前显示 (与成员名册/记录过滤口径一致); 只作用展示层,
        // seqBasePwds 仍是全量 — 归档者留下的手排序不能被展示过滤改写。
        pwds = pwds.filter { !MemberHub.ext($0.owner ?? "").archived }
        // 354 已归档只从正常显示里收起; 搜索路径 (filteredResults) 特意不过滤 — 收起不是失效, 搜得到才收得回
        pwds = pwds.filter { !CredentialOrg.isArchived(mac, "pwd", $0.alias) }
        return pwds
    }
    /// 置顶段在前, 其余按 182 手动序 (kf_cseq_), 没有手动序才按 914 的排序维度
    private func orderedPwds(_ pwds: [LedgerPwd]) -> [LedgerPwd] {
        // 526 置顶行固定顶部
        let pinned = pwds.filter { CredentialOrg.isStarred(mac, "pwd", $0.alias) }
        let rest = pwds.filter { !CredentialOrg.isStarred(mac, "pwd", $0.alias) }
        var ordered = orderPwds(rest)
        // 182/352 拖拽排序: 用户手动序优先 (seq 存的 index 数组)
        let order = CredentialOrg.seq(mac)["p"] ?? []
        let byIdx = manualIndex(order)
        if !order.isEmpty {
            ordered = ordered.sorted { a, b in
                let ia = byIdx[a.alias, default: 9999]
                let ib = byIdx[b.alias, default: 9999]
                return ia < ib
            }
        }
        return pinned + ordered
    }
    /// 手动序数组 → "元素 → 位次" 查表。
    /// 这里刻意用 uniquingKeysWith 而不是 uniqueKeysWithValues: kf_cseq_ 是持久化数据,
    /// 旧包/半写坏的表里出现重复 alias 时, 后者会当场 trap (整个凭证页变崩溃), 前者只是取第一个位次。
    private func manualIndex(_ order: [Int]) -> [Int: Int] {
        Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
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
            // 标签写的是"最近使用", 旧写法按 p.at (录入时间) 排 —— 名不副实。
            // 改用 inferredLastUseMap: 一次读日志, 临时凭证按自己的时间窗归属;
            // 长期凭证锁端日志不记凭证身份, 只能给锁级参考 (同值 → 实际落到录入时间次序)。
            let lastUse = CredentialOrg.inferredLastUseMap(mac)
            return input.sorted { a, b in
                // -1 当"无使用证据"哨兵: 真实 epoch 不可能为负
                let ua = lastUse[a.alias] ?? -1
                let ub = lastUse[b.alias] ?? -1
                if ua != ub { return ua > ub }
                return a.at > b.at
            }
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
                // 212 首次进入各行错开入场: 复用 DesignSystem 的 staggered (会话内只播一次, reduceMotion 退化淡入)。
                // 步长沿用共享值 50ms —— 原句写 30ms, 但那份机制是全 App 一份, 不为一行注释差异动共享数。
                ForEach(Array(pinned.enumerated()), id: \.offset) { i, p in
                    credRow(CredHit(id: "p\(p.alias)", pwd: p, pinned: true))
                        .staggered(min(i, 8))
                }
            }
        }
        // 528 进行中/已排期/已过期三态分组头, 组头带计数
        for state in [0, 1, 2] {
            let group = pwds.filter { CredentialOrg.pwdState($0) == state }
            if !group.isEmpty {
                Section("\(CredentialOrg.stateLabel(state)) (\(group.count))") {
                    // 182 拖动只搬"本组这一串"; 置顶段不参与 (星标段有它自己的 526 规则)
                    let rows = group.filter { !CredentialOrg.isStarred(mac, "pwd", $0.alias) }
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, p in
                        credRow(CredHit(id: "p\(p.alias)", pwd: p, pinned: false))
                            .staggered(min(i, 8))   // 212 同置顶段交错入场
                    }
                    .onMove { src, dst in
                        commitGroupMove(keys: pwdKeys(rows), slot: "p", src: src, dst: dst)
                    }
                    // 529 组尾统计行: "本组 X 条 · 近 30 天使用约 Y 次" (台账推断, 带"约")
                    let uses = group.compactMap { CredentialOrg.recentUseCount(mac, pwdAlias: $0.alias) }.reduce(0, +)
                    if uses > 0 {
                        segStatRow("本组 \(group.count) 条 · 近 30 天使用约 \(uses) 次")
                    }
                    if state == 2 {
                        // 360 过期即归档 + 348 统一延期快捷
                        Button("这一组统一延期") {
                            extendAliases = group.map { $0.alias }
                            showExtend = true
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DS.Palette.accentText)
                        // 334 过期打包清理: 不新造"本机静默删除", 而是把这组选中后交给现有停用流
                        // (摘要 + 313 必填原因 + 回收站 364 + 锁端删除记待下发), 免得台账与锁端分叉
                        if !MemberHub.elderMode {
                            Button("清理本组已过期 (\(group.count) 条)") {
                                selPwds = group.map { $0.alias }
                                selFps = []
                                showDisable = true
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(DS.Palette.danger)
                            .frame(minHeight: DS.Hit.min - DS.Space.xs)
                            .accessibilityHint("先把本组全部过期凭证选入停用确认页, 在确认页还要再点一次并填原因")
                        }
                    }
                }
            }
        }
        // 182 组内排序的说明不再挂在这里: 原先这句 (「长按行拖动可调整组内顺序」) 底下没有任何拖动实现,
        // 是一处假热区。现在拖动真做了, 规则写在排序档自己那一行 (见 sortHintRow), 不开排序档就不出现。
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
    private var sortedFps: [LedgerFp] { orderedFps(segFilteredFps()) }
    /// 182 拖动排序的回写基准 (同密码段那一支: 全量, 不套智能筛选)
    private var seqBaseFps: [LedgerFp] { orderedFps(DB.listFps(mac)) }

    private func segFilteredFps() -> [LedgerFp] {
        var fps = DB.listFps(mac)
        if let l = CredentialOrg.smartLists(mac).first(where: { $0.id == smartSel }), l.kind == "fp" {
            fps = fps.filter {
                if l.owner != "", $0.owner != l.owner { return false }
                if l.tag == "noowner" { return $0.owner == nil }
                // 「添加超一年」这一档此前**只接在密码段**：指纹侧没有对应分支 ⇒ 芯片被无声忽略，
                // 选它等于没选 (显示全部指纹)。单位与密码侧同 (LedgerFp.at 是 epoch 毫秒)。
                if l.tag == "stale" { return $0.at > 0 && CredentialOrg.nowSec - $0.at / 1000 > 365 * 86400 }
                return true
            }
        }
        // 460 归档成员的口令/指纹不进当前显示; seqBaseFps 保持全量 (同上)
        fps = fps.filter { !MemberHub.ext($0.owner ?? "").archived }
        // 354 已归档的指纹同理 (搜索不过滤)
        fps = fps.filter { !CredentialOrg.isArchived(mac, "fp", $0.batch) }
        return fps
    }
    private func orderedFps(_ fps: [LedgerFp]) -> [LedgerFp] {
        let pinned = fps.filter { CredentialOrg.isStarred(mac, "fp", $0.batch) }
        let rest = fps.filter { !CredentialOrg.isStarred(mac, "fp", $0.batch) }
        var ordered: [LedgerFp]
        switch sortKey {
        case .name:
            ordered = rest.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .type:
            ordered = rest.sorted { ($0.isAlarm == true ? 0 : 1) < ($1.isAlarm == true ? 0 : 1) }
        default:
            ordered = rest.sorted { ($0.at) > ($1.at) }
        }
        let order = CredentialOrg.seq(mac)["f"] ?? []
        if !order.isEmpty {
            let byIdx = manualIndex(order)
            ordered = ordered.sorted { a, b in
                let ia = byIdx[a.batch, default: 9999]
                let ib = byIdx[b.batch, default: 9999]
                return ia < ib
            }
        }
        return pinned + ordered
    }

    // ---------- 182 组内拖动排序 ----------
    /// onMove 收到的 IndexSet / 目的下标都是**本段内**的下标 (与 DeviceManageView:125 同一口径),
    /// 所以先在本段里搬, 再把搬完的这一串依次回写到"整表里属于本段的那些位置"上 ——
    /// 别段的位次一格不动, 段内先后就落进了 kf_cseq_。
    /// 下标先过一道范围筛: 数组搬动用越界 IndexSet 是当场 trap, 而这一句的索引来自系统回调。
    private func commitGroupMove(keys: [Int], slot: String, src: IndexSet, dst: Int) {
        let within = IndexSet(src.filter { $0 >= 0 && $0 < keys.count })
        guard !within.isEmpty else { return }
        var moved = keys
        moved.move(fromOffsets: within, toOffset: min(max(dst, 0), keys.count))
        let mine = Set(keys)
        var base = slot == "f" ? seqBaseFps.map { $0.batch } : seqBasePwds.map { $0.alias }
        var q = moved
        for i in base.indices {
            if q.isEmpty { break }
            if mine.contains(base[i]) { base[i] = q.removeFirst() }
        }
        var seq = CredentialOrg.seq(mac)
        seq[slot] = base
        CredentialOrg.setSeq(mac, seq)
        reload()
        app.showToast("组内先后已记住 (182), 跨启动保持")
    }
    /// 两个段的取键函数 (密码取 alias, 指纹取 batch)
    private func pwdKeys(_ group: [LedgerPwd]) -> [Int] { group.map { $0.alias } }
    private func fpKeys(_ group: [LedgerFp]) -> [Int] { group.map { $0.batch } }

    /// 529 段尾统计行的统一渲染。两个段种的"使用"不是一个读数 (密码有逐条时间窗推断, 指纹只有锁整体),
    /// 所以只共用样式, 话各说各的 —— 不拿同一句糊过去。
    private func segStatRow(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(DS.Palette.textSub)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
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
                        StartAddFpView(embedded: true, prefillOwner: missing.count == 1 ? missing.first?.id : nil)
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
            ForEach(Array(fps.enumerated()), id: \.offset) { i, f in
                credRow(CredHit(id: "f\(f.batch)", fp: f, pinned: CredentialOrg.isStarred(mac, "fp", f.batch)))
                    .staggered(min(i, 8))   // 212 指纹段同样交错入场
            }
            .onMove { src, dst in
                commitGroupMove(keys: fpKeys(fps), slot: "f", src: src, dst: dst)   // 182 指纹段内拖动
            }
            // 529 指纹段尾统计: 指纹没有"逐枚使用次数"这个读数 (日志无指纹身份字段), 数的是该锁
            // 近 30 天指纹开门 (type3) 与指纹告警 (type13) 条数, 都标"约" —— 与密码段那句不是一个读数
            if !fps.isEmpty {
                let opens = CredentialOrg.fpUseCount30d(mac)
                let alarms = CredentialOrg.fpAlarmLogCount(mac)
                segStatRow(alarms > 0
                    ? "本段 \(fps.count) 枚 · 近 30 天指纹开门约 \(opens) 次 · 告警约 \(alarms) 条"
                    : "本段 \(fps.count) 枚 · 近 30 天指纹开门约 \(opens) 次")
            }
            NavigationLink { StartAddFpView(embedded: true) } label: { Label("录入指纹", systemImage: "plus") }
        }
    }

    // ---------- 355 成员视图 (未归属独立成段) ----------
    // 182: 这一视图里每个段都有 密码 / 指纹 两串, 拖动各自的段内先后 (一次 onMove 只管它挂的那个 ForEach)。
    // 段内先后同样走 orderedPwds/orderedFps —— 原先这里直接拿台账原始序, 手动序 (kf_cseq_) 与 526 置顶
    // 在按成员视图里一概不生效, 于是"切到按成员, 刚排好的顺序没了"。
    @ViewBuilder
    private var memberSections: some View {
        ForEach(DB.members()) { m in
            // 354: 归档条目在本页任何浏览方式里都不出现 (含按成员视图); 归档区卡是唯一落点
            let pwds = orderedPwds(DB.listPwds(mac).filter {
                $0.owner == m.id && !CredentialOrg.isArchived(mac, "pwd", $0.alias)
            })
            let fps = orderedFps(DB.listFps(mac).filter {
                $0.owner == m.id && !CredentialOrg.isArchived(mac, "fp", $0.batch)
            })
            if !pwds.isEmpty || !fps.isEmpty {
                Section("\(CredentialOrg.aliasDisplay && !m.relation.isEmpty ? m.relation + " · " : "")\(m.name) (\(pwds.count + fps.count))") {
                    ForEach(pwds) { p in credRow(CredHit(id: "p\(p.alias)", pwd: p)) }
                        .onMove { src, dst in
                            commitGroupMove(keys: pwdKeys(pwds), slot: "p", src: src, dst: dst)
                        }
                    ForEach(fps) { f in credRow(CredHit(id: "f\(f.batch)", fp: f)) }
                        .onMove { src, dst in
                            commitGroupMove(keys: fpKeys(fps), slot: "f", src: src, dst: dst)
                        }
                }
            }
        }
        let noPwd = orderedPwds(DB.listPwds(mac).filter { $0.owner == nil && !CredentialOrg.isArchived(mac, "pwd", $0.alias) })
        let noFp = orderedFps(DB.listFps(mac).filter { $0.owner == nil && !CredentialOrg.isArchived(mac, "fp", $0.batch) })
        if !noPwd.isEmpty || !noFp.isEmpty {
            Section("未归属 (\(noPwd.count + noFp.count))") {
                ForEach(noPwd) { p in credRow(CredHit(id: "p\(p.alias)", pwd: p)) }
                    .onMove { src, dst in
                        commitGroupMove(keys: pwdKeys(noPwd), slot: "p", src: src, dst: dst)
                    }
                ForEach(noFp) { f in credRow(CredHit(id: "f\(f.batch)", fp: f)) }
                    .onMove { src, dst in
                        commitGroupMove(keys: fpKeys(noFp), slot: "f", src: src, dst: dst)
                    }
            }
        }
        Section {
            NavigationLink { AddPwdView(embedded: true) } label: { Label("添加密码", systemImage: "plus") }
            NavigationLink { StartAddFpView(embedded: true) } label: { Label("录入指纹", systemImage: "plus") }
        }
    }

    // ---------- 统一行渲染 (普通/搜索/成员/编辑模式共用; VoiceOver 合并成一条) ----------
    // 479 长辈模式在这一族行上接了**真的大字与高对比**: 字号走语义档升一级 (标题行 subheadline→title3,
    // 副行 caption→body), 对比度走"次文本色升到主文本色"那一档 (两个色都是 DS.Palette 里被 contrast.js 检过的令牌)。
    // 刻意不写 .system(size:): 那一档不参与 Dynamic Type 缩放, 字号闸门 (tools/dynamictype.js 规则 1) 也不放行。
    private var elderOn: Bool { MemberHub.elderMode }
    private var rowTitleFont: Font { elderOn ? .title3.weight(.semibold) : .subheadline.weight(.semibold) }
    private var rowSubFont: Font { elderOn ? .body : .caption }
    private var rowSubColor: Color { elderOn ? DS.Palette.text : DS.Palette.textSub }

    @ViewBuilder
    private func credRow(_ hit: CredHit) -> some View {
        let p = hit.pwd
        let f = hit.fp
        // 331 同行一个时刻: 胶囊与副行倒计时同帧同判据, 不留两处各自取 Date()
        let now = Date()
        // 901 紧凑档 (kf_row_h 非 tall): 隐藏副标题只留名称与状态 (IDEA-BANK 901 的"RSS 紧凑行"),
        // 舒适档 tall 才带副行与推断名。判据只有行高这一个键, 不另造开关。
        let compactRow = DB.store.getString("kf_row_h") != "tall"
        // 901 行高二档挂在**行本体**上 (DS.Metric.rowMinH): 凭证行是"看+点"的高频行,
        // 手抖的人在长列表里靠的是行高而不是字号。加高只加空白，不动字号与触达下限。
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.s) {
                Text(titleOf(hit))
                    .font(rowTitleFont)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let p {
                    if CredentialOrg.pwdState(p) == 2 {
                        StatusPill(text: "已过期", systemImage: "clock.badge.xmark", tone: .danger)
                    } else if CredentialOrg.isEarlyExpired(mac, p, now) {
                        // 331 本机提前线已过、锁端未到期: 只提示, 锁到锁端到期照常开门
                        StatusPill(text: "提前失效", systemImage: "hourglass", tone: .warn)
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
                // 1011 满年小徽章: 副行 "已陪伴 N 天 · 满一年了" 只在满年时给一枚同判据胶囊
                if let at = p?.at ?? f?.at, Milestones.companionFullYear(at) {
                    StatusPill(text: "满一年", systemImage: "rosette", tone: .accent)
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
            let sub = subOf(hit, now)
            if !sub.isEmpty && !compactRow {
                Text(sub)
                    .font(rowSubFont)
                    .foregroundStyle(rowSubColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 918 命名模板: 主标题下挂 "谁-哪里-何时" 推断名 (锁端无名称字段, 本地展示);
            // 901 紧凑档同副行一起收起 —— "只留名称与状态"里没有它
            if !compactRow, let p, CredentialOrg.aliasDisplay, CredentialOrg.namingTemplate(p) != titleOf(hit) {
                Text(CredentialOrg.namingTemplate(p))
                    .font(rowSubFont)
                    .foregroundStyle(rowSubColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        // 849 凭证朗读顺序 "名称-类型-状态" (不堆叠字段), 856 盲文简写走 value
        .accessibilityLabel(credVoLabel(hit))
        .accessibilityValue(AXTerms.br(credVoState(hit, now)))
        // 849 拷贝对朗读侧走转子动作, 不对 VoiceOver 承诺"双击" (VO 的双击=激活, 不是我们的双击手势)
        .accessibilityActions {
            if let v = hit.pwd?.pwd {
                Button("拷贝密码明文 (849)") {
                    ClipboardCare.copySecret(v, via: "密码明文")
                    app.showToast("已复制")
                }
            }
        }
        .contextMenu { credMenu(hit) }
        .overlay(alignment: .topLeading) {
            if editMode { selectionCircle(hit) }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard editMode else { return }
            toggleSel(hit)
        }
        // 849 非编辑态双击整行 = 拷贝该条密码明文 (与详情页同一条 405 通路);
        // 编辑态整行单击已归勾选, 双击里再判一次 editMode, 两种模式不抢手势
        .onTapGesture(count: 2) {
            if !editMode, let v = hit.pwd?.pwd {
                ClipboardCare.copySecret(v, via: "密码明文")
                app.showToast("已复制")
            }
        }
        .swipeActions(edge: .trailing) {
            if editMode {
                Button { toggleSel(hit) } label: {
                    Label(isSelected(hit) ? "取消选" : "选", systemImage: isSelected(hit) ? "xmark.circle" : "checkmark.circle")
                }
                .tint(DS.Palette.accent)
            }
            // 182 排序档开着时把破坏性的两枚收掉: 这一档要拖的是行, 不该同时把「停用/彻底删除」摆在手边。
            // 确认门槛本身没变 (§10.39 不许同一动作分叉), 这里只是不出现那两枚按钮。
            if !sorting {
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
        }
        // 182 原先这里挂着一枚 onLongPressGesture, 弹的是「长按可停用/删除; 编辑模式里用顺序按钮调整组内先后」——
        // 既不是拖动 (假热区), 又会把拖动排序要用的那次长按抢走。排序真做到之后这一句整块撤掉:
        // 停用/删除走右侧滑动或长按菜单 (contextMenu 由系统提供), 组内先后走上方的排序档 (182)。
        // 901 行高二档 (kf_row_h): minHeight 而不是固定 height —— 固定高度会裁掉多行备注
        .frame(minHeight: DS.Metric.rowMinH, alignment: .topLeading)
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
    /// 331 播报里"提前失效"排在"已排期"之前但让位于锁端"已过期" —— 与行上胶囊同一优先级
    private func credVoState(_ hit: CredHit, _ now: Date) -> String {
        if let p = hit.pwd {
            if CredentialOrg.pwdState(p) == 2 { return "已过期" }
            if CredentialOrg.isEarlyExpired(mac, p, now) { return "提前失效" }
            switch CredentialOrg.pwdState(p) {
            case 1: return "已排期"
            default: return "可用"
            }
        }
        if let f = hit.fp {
            return f.isAlarm == true ? "预警指纹" : "可用"
        }
        return "可用"
    }

    private func subOf(_ hit: CredHit, _ now: Date) -> String {
        if let p = hit.pwd {
            return [
                p.temp ? "一次性" : "",
                p.at > 0 ? "添加于 " + shortDate(p.at) : "",
                Milestones.companionText(p.at) ?? "",
                // 331 设过本机提前量时按本机尺读数并标注, 没设与原来完全同值
                CredentialOrg.listCountdown(mac, p, now),
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

    /// 368 催办语: 称呼用备注或成员名, 到期日按本机时区读法; 没有称呼就说"您好", 不编造姓名。
    private func renewText(_ p: LedgerPwd, _ to: Date) -> String {
        let who = p.note.isEmpty ? (p.owner.flatMap { DB.member($0)?.name } ?? "") : p.note
        let greet = who.isEmpty ? "您好" : "您好，\(who)"
        let day = to.formatted(.dateTime.year().month().day())
        let hour = to.formatted(.dateTime.hour().minute())
        return "\(greet)，您那条进门凭证将在 \(day) \(hour) 到期。"
            + "如果还需要用，麻烦提前说一声，我给您延一下或重新发一张。"
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
            // 368 延期催办文本: 只对"有到期时间且 7 天内到期"的条目出现, 产出可直接发给住客的礼貌催办语。
            // 文本里**绝不含口令本身** (要复制到聊天工具, 含码等于把门卡发出去)。
            if let d = CredentialOrg.expiryDate(p), d.timeIntervalSinceNow > 0, d.timeIntervalSinceNow < 7 * 86_400 {
                Button("生成延期提醒文本 (368)") {
                    UIPasteboard.general.string = renewText(p, d)
                    app.showToast("催办文本已复制到剪贴板 (不含口令)")
                }
            }
            Button(hit.pinned ? "取消置顶" : "置顶") {
                CredentialOrg.toggleStar(mac, "pwd", p.alias)
                DS.Haptics.tick.impactOccurred()
            }
            if let sug = CredentialOrg.starSuggestion(mac), sug == "p\(p.alias)" {
                Button("标为常用 (近 30 天约最常用, 921)") {
                    CredentialOrg.toggleStar(mac, "pwd", p.alias)
                }
            }
            Button(CredentialOrg.isArchived(mac, "pwd", p.alias) ? "移出归档 (354)" : "归档 (354)") {
                let on = !CredentialOrg.isArchived(mac, "pwd", p.alias)
                CredentialOrg.setArchived(mac, "pwd", p.alias, on)
                app.showToast(on ? "已归档 — 列表顶部归档区可还原" : "已移出归档")
                reload()
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
            Button(CredentialOrg.isArchived(mac, "fp", f.batch) ? "移出归档 (354)" : "归档 (354)") {
                let on = !CredentialOrg.isArchived(mac, "fp", f.batch)
                CredentialOrg.setArchived(mac, "fp", f.batch, on)
                app.showToast(on ? "已归档 — 列表顶部归档区可还原" : "已移出归档")
                reload()
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
                        // 182/352: 记住当前组内顺序 (置顶段单独记, 避免拖动段误伤置顶)。
                        // 拖动排序 (上方排序档) 与这一枚写的是同一张 kf_cseq_, 不是两套顺序。
                        // 回写取 seqBase* (全量显示序) 而不是 sortedPwds/sortedFps: 后者已经被分段与智能筛选削过,
                        // 拿削过的这一批回写整表, 没显示的那一批 (例如临时码) 的位次就被抹平到表尾。
                        var seq = CredentialOrg.seq(mac)
                        seq["p"] = seqBasePwds.map { $0.alias }
                        seq["f"] = seqBaseFps.map { $0.batch }
                        CredentialOrg.setSeq(mac, seq)
                        app.showToast("已记住当前组内顺序 (182/352)")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                    .accessibilityLabel("把当前先后写成手动序 (182/352), 与排序档里的拖动共用同一张顺序表")
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
                    // 347 那句「双指下滑连续选 (双指区划由系统滚动提供)」在 iOS 上不存在: 系统没有多指选择手势,
                    // 也没有一个滚动容器替用户划出多选区。这里改成这一屏真做得到的三条路 (逐条点按 / 行右滑「选」/ 356 循环 + 350 智能选取)。
                    Text("点按行选一条; 行右侧滑动点「选」同样算一条。要连着选一片: 上面那枚循环键按 全选→反选→清空 走 (356), 或用「智能选取」一次选一把 已过期/同成员/同类型 (350)。")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                listBody
            }
        }
        .listRowSpacing(DS.Space.xs)
    }

    /// 354 选择位面 = 浏览位面: 归档条目既看不见, 也不许被"全选/反选/智能选取"选中 —
    /// 隐藏行一旦进破坏性批量 (353 停用 / 922 删除), 就是"看不到却被停掉"。台账级读数不走这里。
    private var selectablePwds: [LedgerPwd] {
        DB.listPwds(mac).filter { !CredentialOrg.isArchived(mac, "pwd", $0.alias) }
    }
    private var selectableFps: [LedgerFp] {
        DB.listFps(mac).filter { !CredentialOrg.isArchived(mac, "fp", $0.batch) }
    }
    private var selectableTotal: Int { selectablePwds.count + selectableFps.count }
    private var cycleLabel: String {
        let total = selectableTotal
        if selCount == 0 { return "全选 (\(total) 条)" }
        if selCount == total { return "已全选 (\(total))" }
        return "已选 \(selCount) / \(total) — 反选"
    }
    private var cycleNextLabel: String {
        let total = selectableTotal
        if selCount == 0 { return "反选" }
        if selCount == total { return "清空" }
        return "全选"
    }
    private func cycleSelect() {
        let allP = selectablePwds.map { $0.alias }
        let allF = selectableFps.map { $0.batch }
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
            // 922 两排: 上一排是整理类 (置顶/延期/移交/前缀/导出), 下一排是两条破坏性 (停用/删除) ——
            // 7 枚挤一行在窄机上会截字, 破坏性动作也该离整理动作远一格手指
            HStack(spacing: DS.Space.xs) {
                batchBtn("置顶", icon: "star") {
                    if selCount == 0 { app.showToast("先选择凭证"); return }
                    var n = 0
                    for a in selPwds where !CredentialOrg.isStarred(mac, "pwd", a) { CredentialOrg.setStar(mac, "pwd", a, true); n += 1 }
                    for b in selFps where !CredentialOrg.isStarred(mac, "fp", b) { CredentialOrg.setStar(mac, "fp", b, true); n += 1 }
                    app.showToast(n > 0 ? "已置顶 \(n) 条 (922)" : "所选都已置顶")
                    reload()
                }
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
            }
            HStack(spacing: DS.Space.xs) {
                batchBtn("停用", icon: "pause.circle", destructive: true) {
                    if selCount == 0 { app.showToast("先选择凭证"); return }
                    showDisable = true
                }
                // 922 批量删除: 语义与单条滑动里的「删除」一致 (锁内立即失效), 本机仍进回收站;
                // 门锁不在场就如实报已删条数后中断, 不静默跳过任何一条
                batchBtn("删除", icon: "trash", destructive: true) {
                    if selCount == 0 { app.showToast("先选择凭证"); return }
                    let n = selCount
                    confirmDestructive("删除所选 \(n) 条凭证 (922)",
                                       "删除后这些凭证在锁内立即失效 (需门锁在场直发); 本机记录进回收站 \(CredentialOrg.reclaimDays()) 天内可找回, 值或开门能力要重新下发。确定继续？",
                                       confirmTitle: "删除") {
                        Task { await batchDelete() }
                    }
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
        // 口令不进剪贴板: 明文凭证包与口令必须分开交付。
        // 也刻意不走 405 自清: 这是 AES 密文信封, 且要粘进聊天工具, 60 秒后清掉只会打断交接
        UIPasteboard.general.string = text
        // 351: 复制照旧 (聊天工具粘贴场景), 同时把分享面板弹出来 —— 同一份密文, 口令仍另行发送
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        UIApplication.topViewController()?.present(av, animated: true)
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

    /// 922 批量删除: 逐条复用单条「彻底删除」那一支 (锁内直删 + 回收站留档), 不做物理删;
    /// 中断时把已删条数如实报出, 不静默跳过 (与批量停用同一个 busyKey 闸, 不加第二把锁)
    private func batchDelete() async {
        guard busyKey == nil else { return }
        let m = mac
        guard !m.isEmpty else { app.showToast("未选择门锁"); return }
        let pwds = selPwds.compactMap { DB.getPwd(m, $0) }
        let fps = selFps.compactMap { DB.getFp(m, $0) }
        guard !pwds.isEmpty || !fps.isEmpty else { app.showToast("所选凭证已不在台账"); reload(); return }
        busyKey = "batch"
        defer { busyKey = nil; editMode = false; selPwds = []; selFps = [] }
        var done = 0
        do {
            try await app.lock.ensureConnected(mac: m)
            for p in pwds {
                try await app.lock.pwdDelete(p.alias)
                CredentialOrg.addToBin(m, pwd: p, source: .manual)
                DB.delPwd(m, p.alias)
                done += 1
            }
            for f in fps {
                try await app.lock.fpDelete(UInt32(f.batch))
                CredentialOrg.addToBin(m, fp: f, source: .manual)
                DB.delFp(m, f.batch)
                done += 1
            }
            showToastOrganized("已删除 \(done) 条")
        } catch {
            app.showToast(done > 0 ? "已删除 \(done) 条后中断: \(error.localizedDescription)" : "删除失败: \(error.localizedDescription)")
        }
        reload()
    }

    // ---------- 智能列表 (527) 管理 ----------
    /// 527 新建向导的条件勾选集: 向导是多层弹层 (名称 → 条件), 勾选态要跨层保留。
    /// 旧写法把 Pick 放函数体里、勾一次整条向导重启, 勾选和名称全丢; 提成引用类型后条件层只重建自己。
    final class SmartPick { var chosen: Set<String> = [] }

    private func newSmartList(pick: SmartPick = SmartPick(), named: String = "", owner: String = "") {
        let alert = UIAlertController(title: "新建智能列表 (527)", message: "把常用筛选组合存为命名快捷", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "名称 (如: 已过期访客)"; $0.text = named }
        // 527: 属主可选。筛选 (:890/:1054) 是**成员 id 精确匹配**, 手输姓名在这里解析成 id;
        // 空 = 全部属主。解析不到会退回这一步 (保留已勾条件, 免得存出一条永远 0 命中的列表)
        alert.addTextField { $0.placeholder = "属主 (可选: 成员 id 或姓名)"; $0.text = owner }
        alert.addAction(UIAlertAction(title: "下一步", style: .default) { _ in
            let name = (alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { app.showToast("起个名字"); return }
            let raw = (alert.textFields?.dropFirst().first?.text ?? "").trimmingCharacters(in: .whitespaces)
            var ownerID = ""
            if !raw.isEmpty {
                if DB.member(raw) != nil {
                    ownerID = raw
                } else if let m = DB.members().first(where: { $0.name == raw }) {
                    ownerID = m.id
                } else {
                    app.showToast("没找到成员「\(raw)」: 属主按成员 id 或姓名对上才行, 请重填")
                    newSmartList(pick: pick, named: name, owner: raw)
                    return
                }
            }
            UIApplication.topViewController()?.present(smartSheet(pick, name: name, owner: ownerID), animated: true)
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        UIApplication.topViewController()?.present(alert, animated: true)
    }

    /// 527 条件多选层: 勾选只重建这一层, 名称/属主不再重问
    private func smartSheet(_ pick: SmartPick, name: String, owner: String) -> UIAlertController {
        let sheet = UIAlertController(title: "筛选条件", message: "可多选, 全部满足才命中", preferredStyle: .actionSheet)
        // 「添加超一年」而非「一年未用」：台账里只有**添加时刻** (`LedgerFp.at` / `LedgerPwd.at`)，
        // 锁端没有"逐凭证最后使用"这一读数 (529 那套是从日志推断的、还会返回 nil)，
        // 所以这条筛的就是建档时间，措辞不能说成"未使用"。存盘的 tag 值仍是 "stale"，老列表不受影响。
        for opt in ["密码", "指纹", "已过期", "无归属", "添加超一年"] {
            let box = pick.chosen.contains(opt) ? "☑ " : "☐ "
            sheet.addAction(UIAlertAction(title: box + opt, style: .default) { _ in
                if pick.chosen.contains(opt) { pick.chosen.remove(opt) } else { pick.chosen.insert(opt) }
                // 等旧弹层收完再挂新弹层 (同步 present 会在收场动画里被系统丢掉)
                if let top = UIApplication.topViewController() {
                    top.dismiss(animated: true) { top.present(smartSheet(pick, name: name, owner: owner), animated: true) }
                }
            })
        }
        sheet.addAction(UIAlertAction(title: "保存", style: .default) { _ in
            let kind = pick.chosen.contains("指纹") ? "fp" : "pwd"
            var state = ""
            if pick.chosen.contains("已过期") { state = "expired" }
            let tag = pick.chosen.contains("无归属") ? "noowner" : (pick.chosen.contains("添加超一年") ? "stale" : "")
            var lists = CredentialOrg.smartLists(mac)
            let l = CredSmartList(id: UUID().uuidString, name: name, kind: kind, owner: owner, state: state, tag: tag)
            lists.append(l)
            CredentialOrg.saveSmartLists(mac, lists)
            smartSel = l.id
            app.showToast("已套用智能列表「\(name)」")
        })
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        return sheet
    }
    private func manageSmartLists() {
        let lists = CredentialOrg.smartLists(mac)
        guard !lists.isEmpty else { app.showToast("还没有智能列表"); return }
        let alert = UIAlertController(title: "管理智能列表 (527)", message: nil, preferredStyle: .actionSheet)
        for l in lists {
            // 删除是不可逆动作: 菜单里给全标签 (名称 · 属主 · 状态) 才认得出删的是哪一条
            alert.addAction(UIAlertAction(title: "删除「\(CredentialOrg.smartListLabel(l))」", style: .destructive) { _ in
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
                    // 同上: 开关按下的一刻钉住锁，Task 里用 m 而不是再活读一次
                    let m = mac
                    guard !m.isEmpty else { app.showToast("未选择门锁"); return }
                    busyKey = "otp"
                    Task {
                        defer { busyKey = nil }
                        do {
                            // 第八十八批: 这条命令面原先不先绑锁就直接发 (services 层按自己的 curMac 取钥,
                            // LockService.swift:285-288 / :93)，于是"用户点的是这把锁，19 命令发到上次连过的那把"。
                            // 补 ensureConnected 把目标钉成 m —— 与仓内其它命令面的写法同构。
                            try await app.lock.ensureConnected(mac: m)
                            try await app.lock.setZotp(on)
                            DB.saveOtpStatus(m, OtpStatus(on: on, at: Date().timeIntervalSince1970 * 1000))
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
            } else {
                otpExplainer   // 820 科普空态: 未开通时先把机制讲清, 而不是只丢一枚看不懂的开关
            }
        }
    }

    // ---------- 820 OTP 科普空态 (Authy) ----------
    // 原句写的是「图解 30 秒动态码原理 + 手动录入按钮」，两处都得按真实机制改口径：
    // ① 本锁 ZOTP 的窗口是 **30 分钟**，不是 30 秒 (ZOTP.generate: now/(60*period)，金标 case v30_*/v60_0
    //    就是这个换算)。照创意原文写「30 秒」等于让界面承诺一个算法里不存在的东西。
    // ② 没有「手动录入」那一步可录：种子就是这把锁的 skey (绑定时已在本地)，用户手上不存在一个要抄的 secret。
    //    所以这里给的两个动作都是真做得到的：开通 = 上面那枚开关；校准 = 进 SyncTimeView。
    // 三格"图解"用的是符号 + 短句，不是插图：本仓零位图资产 (219 / tools/assetscheck.js)，
    // 画不出来的东西就不该用一张不存在的图去承诺。
    private var otpExplainer: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("临时密码是怎么来的 (820)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DS.Palette.text)
            HStack(alignment: .top, spacing: DS.Space.s) {
                otpStepCell("key.horizontal", "这把锁的密钥", "绑定时已存在本机，从不外发")
                otpStepCell("clock", "当前 30 分钟窗口", "按门锁自己的钟切，不是手机时间")
                otpStepCell("number", "算出 6 位码", "过了窗口自动作废")
            }
            NavigationLink { SyncTimeView() } label: {
                Label("先校准门锁时间 (窗口按锁钟切)", systemImage: "clock.arrow.2.circlepath")
            }
            Text("再打开上面那枚「开通临时密码」就能生成。每个窗口最多 100 个码，用完等下一个窗口。")
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        .accessibilityElement(children: .contain)
    }
    private func otpStepCell(_ symbol: String, _ title: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Image(systemName: symbol)
                .font(.system(size: DS.Icon.sm))
                .foregroundStyle(DS.Palette.accentText)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(DS.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(note)
                .font(.caption2)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var otpGenRow: some View {
        HStack(spacing: DS.Space.s) {
            // 374: 采集进行中不把码排出来, 大字模式也拿不到明文 (刻意只换文本, 不整页遮黑)
            Text(cap.recording ? "录屏中已隐去 (374)" : otpPwd)
                // 885 大字模式: 开关 (kf_ax_bigotp) 或双击切换, 等宽数字防跳 (231)
                .font((DB.store.getBool("kf_ax_bigotp") || otpBig) ? .largeTitle.weight(.semibold).monospacedDigit() : .title3.weight(.semibold).monospacedDigit())
                // 342 换码微动效: 值换掉时逐位滚过去 (与 207 电量数字滚动同一个 contentTransition(.numericText()))。
                // 触感沿用 genOtp() 末尾那一次成功反馈，**不再叠第二次** —— 一次生成两下震动只会让人分不清是哪件事。
                // 动效节操仍由 DS.Motion 那一档决定：系统"减弱动态效果"下走 calm (0.10s easeOut)，不做无响应的滑动。
                .contentTransition(.numericText())
                .animation(DS.Motion.quick, value: otpPwd)
                .foregroundStyle(DS.Palette.text)
                .textSelection(.enabled)
                .onTapGesture(count: 2) { otpBig.toggle() }
                .accessibilityLabel("临时码, 双击切大字号")
                // 375 挡片: 开关开着才出现; 长按移开, 松手复位。
                // 挡片在顶层会吃掉触摸, 所以 885 的双击在挡片上也挂一份 —— 否则默认开挡片时双击等于失灵。
                .overlay(alignment: .leading) {
                    if DB.store.getBool(SecKey.frostedOn, true), !otpPeek {
                        RoundedRectangle(cornerRadius: DS.Radius.control)
                            .fill(.ultraThinMaterial)
                            .onLongPressGesture(minimumDuration: 0.5, maximumDistance: 50, pressing: { p in
                                if !p { withAnimation(DS.Motion.standard) { otpPeek = false } }
                            }, perform: {
                                withAnimation(DS.Motion.standard) { otpPeek = true }
                            })
                            .onTapGesture(count: 2) { otpBig.toggle() }
                    }
                }
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
                ClipboardCare.copySecret(otpPwd, via: "临时码卡片")   // 405
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
    /// 返回值 = 是否真生成 (首张按钮拿它决定回执; 各失败支自己弹原因, 不静默)。
    @discardableResult
    private func genOtp() -> Bool {
        guard busyKey == nil else { return false }
        guard let kc = app.current, kc.skey.count == 32 else { app.showToast("缺少该锁钥匙串"); return false }
        let win = ZOTP.nextWindow()
        let cur = DB.otpIdx(mac)
        let idx = (cur?.invalidTime == win) ? (cur?.idx ?? -1) + 1 : 0
        if idx > 99 {
            app.showToast("当前窗口已达 100 个上限, 请到下一个 30 分钟窗口再生成")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return false
        }
        let pwd = ZOTP.generate(macHex: kc.mac, skeyHex: kc.skey, periodSec: 30, idx: idx)
        // `generate` 只在算得出码时才返回值 (钥匙串长度、MAC 形状任一不过就返回空串，见 ZOTP.swift)。
        // 空串不许当「生成成功」：原先会一路把空值写进 otpPwd、复制进剪贴板、再震一下「成功」，
        // 屏幕上是一个看不见的码，而 idx 也已经被记进窗口 —— 用户只知道「没开门」。
        // 这道 guard 必须排在 saveOtpIdx 之前：失败的这一次不许占用窗口内的 100 个名额。
        guard !pwd.isEmpty else {
            app.showToast("这把锁的 MAC 不是整 6 字节十六进制, 已中止生成 (临时码要用它反序拼料)")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return false
        }
        DB.saveOtpIdx(mac, OtpIdx(idx: idx, invalidTime: win))
        otpPwd = pwd
        otpWin = win
        ClipboardCare.copySecret(pwd, via: "生成临时码")   // 405
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        return true
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
            }
            .padding(.vertical, 2)
        }
    }

    /// 821 临时码零库存: 已开通但一张没发 → "酒店前台发门卡"比喻 + 首张按钮。
    /// 这一块原先嵌在"整册空"的 emptyHint 里 ⇒ 台账里有密码但没发过临时码时它永远不出现;
    /// 提出来挂列表固定位 (listBody), 空台账时也只由这一块渲染一次。
    @ViewBuilder
    private var otpStockHint: some View {
        if DB.otpStatus(mac)?.on == true, DB.listPwds(mac).filter({ $0.temp }).isEmpty {
            Section {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("临时码还没有发过一张 — 像酒店前台的门卡, 客人走一张, 就发下一张。")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("发第一张临时码") { genFirstOtp() }
                        .buttonStyle(SecondaryActionStyle(fullWidth: false))
                        .disabled(isBusy)
                }
                .padding(.vertical, 2)
            }
        }
    }
    /// 821 空台账场景"发第一张临时码": 走现有 genOtp 通路, 需锁在场。
    /// busyKey 只占"连接中"这一段 —— genOtp 自带 busyKey==nil 门槛, 不先还回去第一张永远不生成
    /// (原先连完直接调 genOtp, 被自己的占用挡下, 回执却报成功)。
    private func genFirstOtp() {
        guard busyKey == nil else { return }
        busyKey = "otp"
        Task {
            defer { busyKey = nil }
            do {
                try await app.lock.ensureConnected(mac: mac)
                busyKey = nil   // 还回连接占用再生成; genOtp 同步完成, 生成段无需再占
                if genOtp() {
                    app.showToast("第一张临时码已生成, 可让客人直接在锁键盘输入")
                }
            } catch { app.showToast("需在场连接锁端: \(error.localizedDescription)") }
        }
    }

    /// 354 归档区: 归档 = 收起不删 — 与停用 (锁端待处理) / 彻底删除 (670) 是三个不同档, 这里只碰展示层。
    /// 单条与全部两种还原都在这里; 搜索路径里归档条目仍可见, 它的还原入口在条目长按菜单的「移出归档」。
    @ViewBuilder
    private var archivedStrip: some View {
        let ap = DB.listPwds(mac).filter { CredentialOrg.isArchived(mac, "pwd", $0.alias) }
        let af = DB.listFps(mac).filter { CredentialOrg.isArchived(mac, "fp", $0.batch) }
        if !ap.isEmpty || !af.isEmpty {
            Section {
                DisclosureGroup {
                    ForEach(ap, id: \.alias) { p in
                        archRow(title: p.temp ? "临时码 #\(p.alias)" : "密码 #\(p.alias)",
                                owner: p.owner) {
                            CredentialOrg.setArchived(mac, "pwd", p.alias, false)
                            app.showToast("已还原到列表")
                            reload()
                        }
                    }
                    ForEach(af, id: \.batch) { f in
                        archRow(title: "指纹 · \(f.name)", owner: f.owner) {
                            CredentialOrg.setArchived(mac, "fp", f.batch, false)
                            app.showToast("已还原到列表")
                            reload()
                        }
                    }
                    Button("全部还原 (354)") {
                        CredentialOrg.unarchiveAll(mac)
                        app.showToast("归档已全部还原")
                        reload()
                    }
                    .font(.footnote)
                    .buttonStyle(.borderless)
                } label: {
                    Text("归档区 (354) · \(ap.count + af.count) 条 — 收起不删, 随时可还原")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    @ViewBuilder
    private func archRow(title: String, owner: String?, restore: @escaping () -> Void) -> some View {
        HStack(spacing: DS.Space.s) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.text)
                if let o = owner, !o.isEmpty {
                    Text("归属 " + o)
                        .font(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                }
            }
            Spacer(minLength: DS.Space.s)
            Button("还原", action: restore)
                .font(.footnote.weight(.medium))
                .foregroundStyle(DS.Palette.accentText)
                .buttonStyle(.borderless)
        }
    }

    // ---------- 506 误删撤销条: 删除后底部浮出 5 秒 "已删除 · 撤销", 撤销则原位还原不入回收站 ----------
    // 833: 第一次浮出时多附一句防误删说明 (HintOnce 之后不再出现)。
    // 第一百五十二批把这片的措辞改成**跟着真实路径走**：撤销要收回的东西不止回收站那一格 ——
    // 停用那条路还排着一条"待下发的锁端删除"并写着 361 停用便签；彻底删除那条路锁端已经真删了，
    // 本机恢复≠锁上还有。所以话术由 `CredentialOrg.undoRemove` 一份生成，界面不再各写一遍。
    @ViewBuilder
    private var undoBar: some View {
        if let e = undoEntry {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DS.Space.s) {
                    Text("\(e.text) \(undoHard ? "已彻底删除" : "已停用")")
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Button("撤销") {
                        app.showToast(CredentialOrg.undoRemove(mac, entry: e, hard: undoHard))
                        undoEntry = nil
                        stopUndoTimer()
                        reload()
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
                if undoTeachOnce {
                    Text(undoHard
                         ? "第一次删: 这条浮出后的 5 秒里点「撤销」能取回本机记录 (833)。"
                             + "锁端那一步已经真做过 —— 没过期和密码会排入「重新下发」，指纹只能本人到锁前重录。"
                         : "第一次停用: 这 5 秒里点「撤销」，本机记录放回原位，"
                             + "那条还没发出去的「锁端删除」与停用便签一并收回 (833)。")
                        .font(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.s)
            .background(DS.Palette.surface)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .combine)
            .accessibilityHint("5 秒内点按撤销可取回本机记录；停用那条路还会收回待下发的锁端删除")
        }
    }
    private func armUndo(_ entry: CredBinEntry, hard: Bool) {
        undoHard = hard
        // 标记打在"这一条真的浮出来了"的时刻，而不是渲染期改状态 (本仓明令避免的形状)。
        undoTeachOnce = !HintOnce.shown("833")
        if undoTeachOnce { HintOnce.mark("833") }
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
        f.locale = Locale(identifier: "en_US_POSIX")
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
            // 在用户按下"作废旧密码"的那一刻就把目标锁钉住 (含非空校验)，Task 里一律用 m
            let m = mac
            guard !m.isEmpty else { app.showToast("未选择门锁"); return }
            busyKey = "pwd:\(p.alias)"
            Task {
                defer { busyKey = nil }
                do {
                    try await app.lock.ensureConnected(mac: m)
                    let aliasOut = try await app.lock.pwdModify(alias: p.alias, pwd: np, validFrom: p.from, validTo: p.to)
                    DB.rePwd(m, p.alias, np)
                    if aliasOut != p.alias {
                        DB.addPwd(m, LedgerPwd(alias: aliasOut, from: p.from, to: p.to, temp: p.temp, at: Date().timeIntervalSince1970 * 1000, pwd: np, owner: p.owner, note: p.note))
                        // 确认口径：换槽 (上面按钮的破坏性项「作废旧密码」已经问过并要 6~8 位新码)，
                        //   锁端返回新槽号后旧槽已不存在，addPwd 紧跟着把台账补到新槽 ⇒ 无删除后果可预告。
                        DB.delPwd(m, p.alias)
                    }
                    // 487 保存自动快照: 改值即留一档 (值/时段/备注)
                    let finalAlias = aliasOut == p.alias ? p.alias : aliasOut
                    if let p2 = DB.getPwd(m, finalAlias) {
                        CredentialOrg.snapshot(m, kind: "pwd", key: finalAlias, pwd: p2, fp: nil, note: "修改了密码值")
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
        // 第八十七批: 入口一次性钉住目标锁。原先 `mac` (活读 app.current) 在这条链上被读 3 次 ——
        // 两次 await 之间当前锁若被 AppIntent / kf:// 深链改掉，命令发向 A 锁而台账写进 B 锁；
        // 而 current 变 nil 时 `?? ""` 会静默写出一条"没有锁"的台账。同口径见 doDeletePwd/doDeleteFp/
        // modifyPwd/OTP 开关/SettingsView.doClearPwd 与 CredentialStudio.FpStudio.saveAndClose。
        let m = mac
        guard !m.isEmpty else { app.showToast("未选择门锁"); return }
        busyKey = "pwd:\(p.alias)"
        defer { busyKey = nil }
        do {
            try await app.lock.ensureConnected(mac: m)
            try await app.lock.pwdExpire(p.alias, p.from, p.to)
            CredentialOrg.snapshot(m, kind: "pwd", key: p.alias, pwd: p, fp: nil, note: "修改了有效期")
            DB.setPwdPeriod(m, p.alias, p.from, p.to)
            app.showToast("已更新有效期")
        } catch { app.showToast("更新失败: \(error.localizedDescription)") }
    }

    private func periodText(_ p: LedgerPwd) -> String {
        if p.to.hasPrefix("2118") { return "长期有效" }
        return "到 \(p.to.prefix(16).replacingOccurrences(of: "T", with: " ")) 失效"
    }

    /// 468 代管: 这条凭证的属主在成员档案上被标了「由我代管」时, 361 的停用便签补一句 管理员代操作。
    /// 判据读 MemberHub.proxyNames (与成员页同一张 kf_member_ext), 只在归属可证明时补, 无归属不猜。
    /// 便签的回显点在回收站那一行 (CredentialCenterView 的 disableMarkText), 所以这句标注是给人看得见的。
    private func disableVia(owner: String?) -> String {
        guard let o = owner, !o.isEmpty, MemberHub.proxyNames.contains(o) else { return "本机单条停用" }
        return "本机单条停用 · 管理员代操作 (468)"
    }

    /// 364/180/360 停用: 本地移除 + 回收站 (7 天恢复窗口), 锁端删除入队 (本地意图, UI 明示)
    private func disablePwd(_ p: LedgerPwd) {
        guard busyKey == nil else { return }
        confirmDestructive("停用密码 #\(p.alias)",
                          // 天数口径：这个 7 天是 **364 的一键恢复窗口**，出处 `CredentialOrg.withinRecoverWindow`
                          //   里写死的 `7 * 86400`，与 497 那个 7~90 天可调的回收站保留期不是同一件事 (所以不读 reclaimDays)。
                          "停用后本机台账立即移除并收入回收站 — 7 天内可一键恢复, 超期需重新下发; 锁端删除记为「待下发」。",
                          confirmTitle: "停用") {
            CredentialOrg.addToBin(mac, pwd: p, source: .manual)
            DB.delPwd(mac, p.alias)
            CredentialOrg.enqueue(mac, kind: "del_pwd", title: "删除密码 #\(p.alias)")
            // 361: 单条停用没有 313 的四选一, 便签如实记"未填", 不编一个原因充数 (要不要补必填见 NEXT-DECISIONS 组5)
            CredentialOrg.markDisabled(mac, kind: "pwd", keys: [p.alias], label: "未填", via: disableVia(owner: p.owner))
            if let e = CredentialOrg.bin(mac).first(where: { $0.pwd?.alias == p.alias }) {
                armUndo(e, hard: false)
            }
            showToastOrganized("已停用, 7 天内可恢复 (364)")
        }
    }
    private func disableFp(_ f: LedgerFp) {
        guard busyKey == nil else { return }
        confirmDestructive("停用指纹「\(f.name)」",
                          // 天数口径：同停用密码那一支 —— 7 天是 364 一键恢复窗口 (`withinRecoverWindow` 写死)，
                          //   不是 497 那个可调的回收站保留期。
                          "停用后本机台账立即移除并收入回收站 — 7 天内可一键恢复, 超期需重新录入; 锁端删除记为「待下发」。",
                          confirmTitle: "停用") {
            CredentialOrg.addToBin(mac, fp: f, source: .manual)
            DB.delFp(mac, f.batch)
            CredentialOrg.enqueue(mac, kind: "del_fp", title: "删除指纹「\(f.name)」")
            CredentialOrg.markDisabled(mac, kind: "fp", keys: [f.batch], label: "未填", via: disableVia(owner: f.owner))   // 361 同上, 如实记未填; 468 代管时补标注
            if let e = CredentialOrg.bin(mac).first(where: { $0.fp?.batch == f.batch }) {
                armUndo(e, hard: false)
            }
            showToastOrganized("已停用, 7 天内可恢复 (364)")
        }
    }

    /// 彻底删除: 锁端删除 + 本地删前快照 (494 双通道), 670 后果文案具体化
    private func deletePwd(_ p: LedgerPwd) {
        guard busyKey == nil else { return }
        confirmDestructive("彻底删除密码 #\(p.alias)",
                           // 「30 天」原先写死：回收站保留期是设置页那枚 7~90 天的 Stepper (497)，
                           // 用户调过之后这句就把安全网说大了 —— 而它恰恰出现在按下去就不可逆的那一刻。
                           "删除后该密码在锁内立即失效, 本机台账移除 (回收站 \(CredentialOrg.reclaimDays()) 天内可找回记录, 但密码值需重新生成下发才有效)。确定继续？",
                           confirmTitle: "彻底删除") {
            Task { await self.doDeletePwd(p) }
        }
    }
    private func doDeletePwd(_ p: LedgerPwd) async {
        guard busyKey == nil else { return }
        let m = mac
        guard !m.isEmpty else { app.showToast("未选择门锁"); return }
        busyKey = "pwd:\(p.alias)"
        defer { busyKey = nil }
        do {
            try await app.lock.ensureConnected(mac: m)
            try await app.lock.pwdDelete(p.alias)
            CredentialOrg.addToBin(m, pwd: p, source: .manual)   // 494 删前快照 + 回收站双通道
            // 确认口径：彻底删除 (670) —— 确认入口在外层的 `deletePwd` (confirmDestructive，±4 行窗口看不到那么远)，
            //   那一问的正文写的就是这一行做的事；锁端 pwdDelete 已直发，台账与回收站同一条 p，
            //   回收站 reclaimDays 天 (497) + 504 还原排重新下发 + 506 撤销条。
            DB.delPwd(m, p.alias)
            if let e = CredentialOrg.bin(m).first(where: { $0.pwd?.alias == p.alias }) {
                armUndo(e, hard: true)
            }
            showToastOrganized("已彻底删除")
        } catch { app.showToast("删除失败: \(error.localizedDescription)") }
    }

    private func deleteFp(_ f: LedgerFp) {
        guard busyKey == nil else { return }
        confirmDestructive("彻底删除指纹「\(f.name)」",
                           "删除后果: 该指纹在锁内立即失效且无法远程补录 — 需成员本人到锁前重新录入 8 次指压。本机记录进回收站 \(CredentialOrg.reclaimDays()) 天。确定继续？",
                           confirmTitle: "彻底删除") {
            Task { await self.doDeleteFp(f) }
        }
    }
    private func doDeleteFp(_ f: LedgerFp) async {
        guard busyKey == nil else { return }
        let m = mac
        guard !m.isEmpty else { app.showToast("未选择门锁"); return }
        busyKey = "fp:\(f.batch)"
        defer { busyKey = nil }
        do {
            try await app.lock.ensureConnected(mac: m)
            try await app.lock.fpDelete(UInt32(f.batch))
            CredentialOrg.addToBin(m, fp: f, source: .manual)
            // 确认口径：同上面密码那一支 —— 确认在外层 `deleteFp`，只是指纹侧的后果写得更硬
            //   (无法远程补录，本人重录 8 次指压)；回收站那条回来的仍是档案，开门能力要重录 (670)。
            DB.delFp(m, f.batch)
            if let e = CredentialOrg.bin(m).first(where: { $0.fp?.batch == f.batch }) {
                armUndo(e, hard: true)
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

    /// 359/930 到期预警五档: 7 / 3 / 1 天 + 24 / 2 小时**全部排本地通知** (930 替代落地后
    /// 2 小时档不再只是列表提醒行), 另有一条"到期时"通知自动跟着走, 不单设开关。
    private func toggleAlerts(_ p: LedgerPwd) {
        let a = CredentialOrg.alert(mac, p)
        let sheet = UIAlertController(title: "到期预警 #\(p.alias) (359/930)",
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
        addTier("到期前 3 天提醒", current: a.d3) {
            var n = a; n.d3.toggle()
            CredentialOrg.saveAlert(mac, p, n)
            CredentialOrg.scheduleAlerts(mac, p, n)
            app.showToast(n.d3 ? "已开 3 天档" : "已关 3 天档")
        }
        addTier("到期前 1 天提醒", current: a.d1) {
            var n = a; n.d1.toggle()
            CredentialOrg.saveAlert(mac, p, n)
            CredentialOrg.scheduleAlerts(mac, p, n)
            app.showToast(n.d1 ? "已开 1 天档" : "已关 1 天档")
        }
        addTier("到期前 24 小时提醒", current: a.h24) {
            var n = a; n.h24.toggle()
            CredentialOrg.saveAlert(mac, p, n)
            CredentialOrg.scheduleAlerts(mac, p, n)
            app.showToast(n.h24 ? "已开 24 小时档" : "已关 24 小时档")
        }
        addTier("到期前 2 小时提醒", current: a.h2) {
            var n = a; n.h2.toggle()
            CredentialOrg.saveAlert(mac, p, n)
            CredentialOrg.scheduleAlerts(mac, p, n)   // 930: 2 小时档现在也排通知 (列表提醒行照旧)
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

/// 109 删除冷静期: 比 confirmDestructive 更严一档 —— 必须**逐字键入指定词**才能提交,
/// 并把将被连带删除的数量写进正文 (破坏性动作的"后果预告"要可核对, 不能只说"将删除若干")。
func confirmDestructiveTyped(_ title: String,
                             _ message: String,
                             requireWord: String,
                             confirmTitle: String = "确认删除",
                             action: @escaping () -> Void) {
    let alert = UIAlertController(title: title,
                                  message: message + "\n\n请输入「\(requireWord)」以解锁删除按钮:",
                                  preferredStyle: .alert)
    alert.addTextField { $0.placeholder = requireWord; $0.autocorrectionType = .no; $0.autocapitalizationType = .none }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    let ok = UIAlertAction(title: confirmTitle, style: .destructive) { _ in action() }
    ok.isEnabled = false
    alert.addAction(ok)
    // 只在逐字相符时放行 (去首尾空白): 手滑连点不可能通过
    alert.textFields?[0].addAction(UIAction { _ in
        ok.isEnabled = (alert.textFields?[0].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == requireWord
    }, for: .editingChanged)
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
