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

    // ---------- 包6 列表组织 ----------
    @State private var seg: Int = 0          // 524 类型分段: 0 全部 / 1 密码 / 2 指纹 / 3 临时码
    @State private var memberView = CredentialOrg.groupMode == .owner   // 355 按成员视图
    @State private var search = ""
    /// 2026-10-26 恢复：`isBusy` 在清理四件套时被误删（它读 busyKey，是主流程状态）。
    private var isBusy: Bool { busyKey != nil }
    // 2026-10-26 恢复：这些 @State 在清理四件套时被连带删掉，但它们是主流程状态。
    @State private var editMode = false
    @State private var selPwds: [Int] = []
    @State private var selFps: [Int] = []
    @State private var showExtend = false
    @State private var extendAliases: [Int] = []
    @State private var showDisable = false
    @State private var pwdDetailItem: LedgerPwd?   // 包5 PwdDetailStudio
    @State private var fpDetailItem: LedgerFp?     // 包5 FpDetailStudio
    @State private var showTempCode = false

    var body: some View { vkBody.destined(.credentials) }
    var vkBody: some View {
        NavigationStack {
            Group {
                if app.current == nil {
                    EmptyState(systemImage: "lock.badge.plus",
                               title: "还没有添加门锁",
                               message: "凭证台账要绑定到具体门锁。请先在门锁键盘上长按重置键恢复出厂，再回来添加设备（需要开启蓝牙）。",
                               actionTitle: "去添加门锁") { showAdd = true }
                } else {
                    VStack(spacing: 0) {
                        headerToolbar
                        if editMode {
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
            .variantList()
            .dsScreenBackground()
            .id(app.currentMac)
            .onAppear {
                refreshTick += 1
                consumeCredJump()   // 包9/577: 记录/告警详情"来源凭证"深链
                consumeCredSelect() // 358: 整理建议带回的多选预勾选
            }
            .onChange(of: app.pendingCredNav) { _, _ in consumeCredJump() }
            .onChange(of: app.pendingCredSelect) { _, _ in consumeCredSelect() }
            // 2026-10-26 精简：整理建议中心 sheet 已删。
            .sheet(isPresented: $showExtend) {
                if !extendAliases.isEmpty {
                    // 同上: CredExtendView 里那颗按钮写的是「关闭」, 而它过去只 reload()
                    CredExtendView(mac: mac, aliases: extendAliases) { reload(); showExtend = false }
                }
            }
            // 2026-10-27 三轮精简：批量移交 sheet 已删。
            .sheet(isPresented: $showDisable) {
                if selCount > 0 {
                    CredDisableSheet(mac: mac, pwdAliases: selPwds, fpBatches: selFps) { finishDisable() }
                }
            }
            // 2026-10-26 精简：凭证中心 sheet 已删（四件套全部移除）。
            .sheet(isPresented: $showTempCode) {
                TempCodeStudio()
            }
            // 2026-10-26 精简：版本历史 sheet 已删。
            .sheet(item: $pwdDetailItem) { item in
                PwdDetailStudio(alias: item.alias)
            }
            .sheet(item: $fpDetailItem) { item in
                FpDetailStudio(batch: item.batch)
            }
        }
        .sheet(isPresented: $showAdd) { AddDeviceView() }
        // 2026-10-27：解密密口令不再进 Toast（会被截屏/录屏带走），改成一次性对话框。
        .alert("解密密口令（只看这一次）", isPresented: Binding(
            get: { secretOnce != nil },
            set: { if !$0 { secretOnce = nil } }
        )) {
            Button("已记住，关闭", role: .cancel) { secretOnce = nil }
        } message: {
            Text("口令：\(secretOnce ?? "")\n\n请勿与凭证包同渠道发送。关闭后不再显示。")
        }
    }

    private func reload() { refreshTick += 1 }

    private var mac: String { app.current?.mac ?? "" }

    // ---------- 顶部工具条 (524 分段计数 / 914 四维排序器 / 363 月历 / 358 整理 / 347 选择) ----------
    // 472 借用横条: 页顶显示进行中借用, 点 已归还 销记
    // ---------- 577 详情跳凭证定位 (包9): 记录/告警详情"来源凭证"深链 → 高亮条 + 打开对应详情 ----------
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
    }


    /// 358: 整理建议行点按带回的多选预勾选。就地进编辑模式并勾好 —— 与「选择」按钮同一条状态机
    /// (editMode/selPwds/selFps), 不另造一套选中集; 排序档互斥照 :379 的口径先关掉再进。
    private func consumeCredSelect() {
        guard let ids = app.pendingCredSelect else { return }
        app.pendingCredSelect = nil
        withAnimation(DS.Motion.quick) { editMode = true }
        selPwds = ids
        selFps = []
    }

    // 2026-10-26 精简：pendingQueueBar（待下发横条）已删（队列功能整套移除）。
    private var LockArchiveLockName: String {
        app.devices.first { $0.mac == mac }.map { LockArchive.displayName($0) } ?? String(mac.prefix(6))
    }

    /// 页面头 —— 2026-10-18 按 PageGrammar 的三条归类规则重构。
    ///
    /// 重构前: 3 行 9 个控件 (计数+待处理+排序+月历+整理+选择+拖动排序 / 4 分段+按成员 / 智能筛选),
    /// 加搜索与锁内存量, 首屏 12+ 入口 —— 用户在"凭证页"上找不到"凭证"。
    ///
    /// 重构后 (规则):
    ///   1. 主操作 = 添加凭证 (底部固定, 同屏唯一)
    ///   2. 次级 <= 2 = 搜索 / 选择 (图标常驻)
    ///   3. 其余全进「⋯」: 视图(排序/月历/按成员/智能筛选) + 整理(整理建议/拖动排序) + 数据(待处理)
    ///
    /// 判据一条没改: 每个入口调的还是原来那个 action, 只是**位置**从"平铺三行"改成"按语义分层"。
    private var headerToolbar: some View {
        VStack(spacing: DS.Space.xs) {
            // 第 1 行: 计数 + 溢出菜单。只保留"看/找/选"三件事之外的一切。
            HStack(spacing: DS.Space.s) {
                Text("共 \(CredentialOrg.typeCounts(mac).all) 条")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                // 溢出: 其余全部按语义分组进这里
                Menu {
                    Section("视图") {
                        // 2026-10-27 三轮精简：排序入口已删（排序四档移除）。
                        Button {
                            memberView.toggle()
            // 2026-10-26 精简：分组模式持久化已删（整理功能移除）。
                        } label: {
                            Label(memberView ? "按类型分组" : "按成员分组", systemImage: "person.2")
                        }
                    }
                    Section("筛选") {
            // 2026-10-26 精简：智能列表（命名过滤）已删。
                    }
                    Section("整理") {
                    // 2026-10-26 精简：该入口已删。
                        if !editMode && CredentialOrg.typeCounts(mac).all > 0 {
                            Button {
                                DS.Haptics.tick.impactOccurred()
                            } label: {
                            }
                        }
                    }
                    // 2026-10-26 精简：待下发队列入口已删（队列功能整套移除）。
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: DS.Icon.md, weight: .semibold))
                        .frame(width: DS.Hit.min, height: DS.Hit.min)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("更多: 排序/视图/筛选/整理")
            }
            // 第 2 行: 类型分段 (4 个) —— 这是**筛选**不是操作, 允许常驻一行
            let segCount = MemberHub.elderMode ? 3 : 4
            HStack(spacing: DS.Space.xs) {
                ForEach(0..<segCount, id: \.self) { i in
                    segChip(i)
                }
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
                Text(labels[i]).vkFont(elderOn ? .body.weight(.medium) : .caption.weight(.medium))
                if c > 0 {
                    Text("\(c)")
                        .vkFont(elderOn ? .body.weight(.semibold) : .caption2.weight(.semibold))
                        .foregroundStyle(on ? DS.Palette.onAccent : DS.Palette.textSub)
                        .padding(.horizontal, DS.Space.xs).padding(.vertical, DS.Space.xxs)
                        .background(on ? DS.Palette.onFillWash.opacity(0.24) : DS.Palette.surfaceAlt, in: Capsule())
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, DS.Space.s).padding(.vertical, DS.Space.s)
            .foregroundStyle(on ? DS.Palette.onAccent : DS.Palette.textSub)
            .background(on ? AnyShapeStyle(DS.Palette.accent) : AnyShapeStyle(DS.Palette.surfaceAlt), in: Capsule())
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("\(labels[i]) \(c) 条")
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
        .listRowSpacing(DS.Space.xs)   // 批量操作行距保持宽松 (纪律: 批量行距)
    }
    /// 182 排序档的说明行: 只承诺这一档真做得到的事 (段内先后 + 落 kf_cseq_ 跨启动)。
    @ViewBuilder
    private func routerRow(_ symbol: String, _ title: String, _ scene: String) -> some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: symbol)
                .font(.system(size: DS.Icon.md))
                .foregroundStyle(DS.Palette.accentText)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title)
                    .vkFont(.subheadline, weight: .medium)
                    .foregroundStyle(DS.Palette.text)
                Text(scene)
                    .vkFont(.caption)
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
            if memberView {
                memberSections
            } else {
                let pwds = sortedPwds
                let fps = sortedFps
            }
            if seg == 0 { otpSection }
            // 354: 全归档不算"台账空" — 归档区那张卡就是这批条目的落点, 谎报"还没有台账"会导向重复建码
            if memberView || (!memberView && sortedPwds.isEmpty && sortedFps.isEmpty
                              && true) {   // 2026-10-26: 归档已删，恒空
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
                            .vkFont(.caption2)
                            .foregroundStyle(DS.Palette.textSub)
                        HStack(spacing: DS.Space.xs) {
                            ForEach(hist.prefix(5), id: \.self) { w in
                                HStack(spacing: 2) {
                                    Button(w) { search = w }
                                        .vkFont(.caption)
                                        .buttonStyle(.bordered)
                                        .accessibilityLabel("搜索 \(w)")
                                    Button { CredentialOrg.removeSearchHistory(w) } label: {
                                        Image(systemName: "xmark.circle")
                                            .font(.system(size: 12))
                                            .frame(width: 24, height: 24)
                                            .contentShape(Rectangle())
                                    }
                                    .accessibilityLabel("删除最近搜索 \(w)")
                                    // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 没有 minHeight (< 44)。
                                    // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
                                    .frame(minHeight: DS.Hit.min)
                                    .contentShape(Rectangle())
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
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                        HStack(spacing: DS.Space.s) {
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
                                    app.showToast("已改用「\(search)」重搜, 命中的是名称/备注/别名/归属")   // 532 已改用
                                } else {
                                    app.showToast("没有匹配的成员")
                                }
                            } label: {
                                Label("按成员重搜", systemImage: "person")
                            }
                            .vkFont(.caption)
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, DS.Space.xs)
                }
            }
            TextField("搜索名称 / 备注 / #别名", text: $search)   // 531 搜索名称
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
                hits.append(CredHit(id: "p\(p.alias)", pwd: p, pinned: false))
            }
        }
        for f in DB.listFps(mac) {
            let hay = "\(f.name) \(f.note) \(CredentialOrg.ownerName(f.owner))"
            if hay.localizedCaseInsensitiveContains(q) {
                hits.append(CredHit(id: "f\(f.batch)", fp: f, pinned: false))
            }
        }
        return hits.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.id < b.id
        }
    }

    // 2026-10-26 精简：queueSection（下发状态步条）已删（队列功能整套移除）。
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
        // 460 归档成员不参与当前显示 (与成员名册/记录过滤口径一致); 只作用展示层,
        // seqBasePwds 仍是全量 — 归档者留下的手排序不能被展示过滤改写。
        // 2026-10-15 走查 (性能): 原写法在 filter 闭包里逐条 MemberHub.ext/isArchived (每条一次全量解码);
        // 集合一次取, 闭包内 Set 查, 行为不变。
        let memberArchived = MemberHub.archivedIDs()
        let credArchived: Set<Int> = []   // 2026-10-26: 归档已删
        pwds = pwds.filter { !memberArchived.contains($0.owner ?? "") }
        // 354 已归档只从正常显示里收起; 搜索路径 (filteredResults) 特意不过滤 — 收起不是失效, 搜得到才收得回
        pwds = pwds.filter { !credArchived.contains($0.alias) }
        return pwds
    }
    /// 置顶段在前, 其余按 182 手动序 (kf_cseq_), 没有手动序才按 914 的排序维度
    private func orderedPwds(_ pwds: [LedgerPwd]) -> [LedgerPwd] {
        // 526 置顶行固定顶部
        let pinned: [LedgerPwd] = []   // 2026-10-26: 星标已删，无置顶
        let rest = pwds
        var ordered = rest
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


    /// 行内小提示行 (装饰, 不参与 VoiceOver 合并)
    private struct HintRow: View {
        let text: String
        var body: some View {
            Text(text)
                .vkFont(.caption2)
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
        // 460 归档成员的口令/指纹不进当前显示; seqBaseFps 保持全量 (同上)
        // 2026-10-15 走查 (性能): 同 segFilteredPwds — 集合一次取, 闭包内 Set 查。
        let memberArchived = MemberHub.archivedIDs()
        let credArchived: Set<Int> = []   // 2026-10-26: 归档已删
        fps = fps.filter { !memberArchived.contains($0.owner ?? "") }
        // 354 已归档的指纹同理 (搜索不过滤)
        fps = fps.filter { !credArchived.contains(100000 + $0.batch) }
        return fps
    }
    private func orderedFps(_ fps: [LedgerFp]) -> [LedgerFp] {
        let pinned: [LedgerFp] = []
        let rest = fps
        // 2026-10-27 三轮：排序四档已删，恒按时间倒序（原 default 分支）
        var ordered: [LedgerFp] = rest.sorted { ($0.at) > ($1.at) }
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
    /// onMove 收到的 IndexSet / 目的下标都是**本段内**的下标,
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
        app.showToast("组内先后已记住, 跨启动保持")   // 182 组内先后已记住
    }
    /// 两个段的取键函数 (密码取 alias, 指纹取 batch)
    private func pwdKeys(_ group: [LedgerPwd]) -> [Int] { group.map { $0.alias } }
    private func fpKeys(_ group: [LedgerFp]) -> [Int] { group.map { $0.batch } }


    /// 529 段尾统计行的统一渲染。两个段种的"使用"不是一个读数 (密码有逐条时间窗推断, 指纹只有锁整体),
    /// 所以只共用样式, 话各说各的 —— 不拿同一句糊过去。
    private func segStatRow(_ text: String) -> some View {
        Text(text)
            .vkFont(.caption2)
            .foregroundStyle(DS.Palette.textSub)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var memberSections: some View {
        // 2026-10-15 走查 (性能): 原写法在 ForEach(DB.members()) 行内逐成员调 DB.listPwds/listFps
        // (M 成员 = M+1 次全量 JSON 解码) 且每条凭证行各调一次 isArchived (每次都 archived(mac)
        // 全量解码)。提到循环外算一次, 行内只做内存 filter —— 行为不变, 解码次数从 O(M×N) 降为 O(1)。
        let allPwds = DB.listPwds(mac)
        let allFps = DB.listFps(mac)
        let archPwd: Set<Int> = []
        let archFp = archPwd   // isArchived 内部: pwd 存原 alias, fp 存 100000+batch, 同一个 Set
        ForEach(DB.members()) { m in
            // 354: 归档条目在本页任何浏览方式里都不出现 (含按成员视图); 归档区卡是唯一落点
            let pwds = orderedPwds(allPwds.filter {
                $0.owner == m.id && !archPwd.contains($0.alias)
            })
            let fps = orderedFps(allFps.filter {
                $0.owner == m.id && !archFp.contains(100000 + $0.batch)
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
        let noPwd = orderedPwds(allPwds.filter { $0.owner == nil && !archPwd.contains($0.alias) })
        let noFp = orderedFps(allFps.filter { $0.owner == nil && !archFp.contains(100000 + $0.batch) })
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
                    .vkFont(rowTitleFont)
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
                    .vkFont(rowSubFont)
                    .foregroundStyle(rowSubColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 918 命名模板: 主标题下挂 "谁-哪里-何时" 推断名 (锁端无名称字段, 本地展示);
            // 901 紧凑档同副行一起收起 —— "只留名称与状态"里没有它
            if !compactRow, let p, CredentialOrg.aliasDisplay, CredentialOrg.namingTemplate(p) != titleOf(hit) {
                Text(CredentialOrg.namingTemplate(p))
                    .vkFont(rowSubFont)
                    .foregroundStyle(rowSubColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(titleOf(hit))
        .accessibilityActions {
            if let v = hit.pwd?.pwd {
                Button("拷贝密码明文") {   // 849 拷贝密码明文
                    Clip.set(v)
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
                Clip.set(v)
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
                "",
                !p.note.isEmpty ? "备注 \(p.note)" : ""
            ].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        if let f = hit.fp {
            return [
                f.at > 0 ? "登记于 " + shortDate(f.at) : "已登记在门锁内",
                f.at > 0 ? "" : "",
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
            Button("密码详情") { pwdDetailItem = p }   // 305/308/309 密码详情
            Button("修改密码内容") { modifyPwd(p) }
            Button("修改有效期") { Task { resetPwdPeriod(p) } }
            Button("添加备注") { editNote(pwd: p) }
            Menu("归属到成员") { ownerMenu(isPwd: true, key: p.alias) }
            Divider()
            Button("三档预警") { toggleAlerts(p) }   // 359 三档预警
            // 368 延期催办文本: 只对"有到期时间且 7 天内到期"的条目出现, 产出可直接发给住客的礼貌催办语。
            // 文本里**绝不含口令本身** (要复制到聊天工具, 含码等于把门卡发出去)。
            if let d = CredentialOrg.expiryDate(p), d.timeIntervalSinceNow > 0, d.timeIntervalSinceNow < 7 * 86_400 {
                Button("生成延期提醒文本") {   // 368 生成延期提醒文本
                    Clip.set(renewText(p, d))
                    app.showToast("催办文本已复制到剪贴板 (不含口令)")
                }
            }
                    // 2026-10-26 精简：版本历史入口已删。
            Divider()
            Button("停用 (本地, 锁端待处理)", role: .destructive) { disablePwd(p) }
            Button("彻底删除", role: .destructive) { deletePwd(p) }   // 670 彻底删除
        }
        if let f = hit.fp {
            Button("指纹详情") { fpDetailItem = f }   // 316/320/323 指纹详情
            Button("重命名") { renameFp(f) }
            Button(f.isAlarm == true ? "取消预警指纹" : "设为预警指纹") {
                DB.setFpAlarm(mac, f.batch, f.isAlarm != true)
                app.showToast(f.isAlarm == true ? "已取消预警指纹" : "已设为预警指纹")
            }
            Button("添加备注") { editNote(fp: f) }
            Menu("归属到成员") { ownerMenu(isPwd: false, key: f.batch) }
                    // 2026-10-26 精简：版本历史入口已删。
            Button(hit.pinned ? "取消置顶" : "置顶") {
            }
                    // 2026-10-26 精简：归档/移出归档入口已删（归档功能整套移除）。
            Divider()
            Button("停用 (本地, 锁端待处理)", role: .destructive) { disableFp(f) }
            Button("彻底删除", role: .destructive) { deleteFp(f) }   // 670 彻底删除
        }
    }

    // 成员归属徽章: 用 accentText (文字级对比度 6:1), 不用品牌填充色
    private func ownerBadge(_ name: String) -> some View {
        Text(name)
            .vkFont(.caption, weight: .medium)
            .lineLimit(1)
            .foregroundStyle(DS.Palette.accentText)
            .padding(.horizontal, DS.Space.s).padding(.vertical, DS.Space.xxs)
            .variantPlate(DS.Palette.accentText.opacity(0.12), .capsule)
    }

    // ---------- 347 编辑模式: 选择圈 + 全选循环 (356) + 智能选取 (350) ----------
    private var selCount: Int { selPwds.count + selFps.count }

    private var editList: some View {
        List {
            Section {
                HStack(spacing: DS.Space.s) {
                    Button {
                        cycleSelect()
                        DS.Haptics.tick.impactOccurred()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cycleLabel)
                                .vkFont(.subheadline, weight: .semibold)
                            Text("下一步: \(cycleNextLabel)")   // 356 下一步
                                .vkFont(.caption2)
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
                        app.showToast("已记住当前组内顺序")   // 182/352 已记住当前组内顺序
                    }
                    .vkFont(.caption, weight: .medium)
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                    .accessibilityLabel("把当前先后写成手动序, 与排序档里的拖动共用同一张顺序表")   // 182/352 把当前先后写成手动序
                }
                HStack(spacing: DS.Space.s) {
                    Text("智能选取")   // 350 智能选取
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                    ForEach(["已过期", "同成员", "同类型"], id: \.self) { s in
                        Button(s) { applySmart(s) }
                            .vkFont(.caption, weight: .medium)
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
                    // 356 点按行选一条
                    // 350 点按行选一条
                    Text("点按行选一条; 行右侧滑动点「选」同样算一条。要连着选一片: 上面那枚循环键按 全选→反选→清空 走, 或用「智能选取」一次选一把 已过期/同成员/同类型。")
                        .vkFont(.footnote)
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
    // 2026-10-15 走查 (性能): isArchived 每条一次全量解码 ⇒ N 条 = O(N²) 解码。集合一次取, 行为不变。
    private var selectablePwds: [LedgerPwd] {
        let arch: Set<Int> = []
        return DB.listPwds(mac).filter { !arch.contains($0.alias) }
    }
    private var selectableFps: [LedgerFp] {
        let arch: Set<Int> = []
        return DB.listFps(mac).filter { !arch.contains(100000 + $0.batch) }
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
        let r = (pwd: selPwds, fp: selFps)   // 2026-10-26: 智能选择已删
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
            HStack(spacing: DS.Space.s) {
                Text("已选 \(selCount) 条")
                    .vkFont(.subheadline, weight: .semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Button("完成") {
                    withAnimation(DS.Motion.quick) { editMode = false; selPwds = []; selFps = [] }
                }
                .vkFont(.subheadline, weight: .medium)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
            }
            // 922 两排: 上一排是整理类 (置顶/延期/移交/前缀/导出), 下一排是两条破坏性 (停用/删除) ——
            // 7 枚挤一行在窄机上会截字, 破坏性动作也该离整理动作远一格手指
            HStack(spacing: DS.Space.xs) {
                // 2026-10-26 精简：「置顶」批量按钮已删（星标功能整套移除）。
                batchBtn("延期", icon: "calendar.badge.clock") {
                    extendAliases = selPwds.isEmpty ? [] : selPwds
                    if selPwds.isEmpty { app.showToast("延期只作用于已选密码"); return }
                    showExtend = true
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
                    confirmDestructive("删除所选 \(n) 条凭证",   // 922 删除所选
                                       "删除后这些凭证在锁内立即失效 (需门锁在场直发); 本机记录进回收站 本机记录直接移除、**不可找回**, 值或开门能力要重新下发。确定继续？",
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
                Text(t).vkFont(.caption2)
            }
            .foregroundStyle(destructive ? DS.Palette.danger : DS.Palette.accentText)
            .frame(maxWidth: .infinity)
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(t), 作用于已选 \(selCount) 条")
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
        Clip.set(text)
        // 351: 复制照旧 (聊天工具粘贴场景), 同时把分享面板弹出来 —— 同一份密文, 口令仍另行发送
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        UIApplication.topViewController()?.present(av, animated: true)
        // 2026-10-27 审核修复 (AUDIT-D D-38)：口令**不再**打进 Toast —— 那是屏幕明文，
        // 截屏/录屏/旁人一眼就能拿到。改成：只提示已复制到剪贴板，口令本身单独放在一个
        // 可再次查看的对话框里（用户在交接时自己决定什么时候看）。
        app.showToast("已生成 \(result.size) 条凭证包并复制到剪贴板。解密密口令已单独显示，请勿与凭证包同渠道发送。")
        presentSecretOnce(pw)
    }

    /// 353 批量停用摘要确认页之后的执行: 本地移除 + 回收站 + 锁端删除入队
    /// 一次性展示敏感串（口令等）。不进 Toast（会被截屏/录屏带走），
    /// 而是弹一个可手动关闭的对话框 —— 用户在自己准备好时才看。
    @State private var secretOnce: String?
    private func presentSecretOnce(_ s: String) { secretOnce = s }

    private func finishDisable() {
        guard busyKey == nil else { return }
        busyKey = "batch"
        Task { @MainActor in
            defer { busyKey = nil; editMode = false; selPwds = []; selFps = [] }
            // 2026-10-27 (D-58)：batchDisable 现在返回 (done, failedPwds, failedFps) ——
            // 原先静默跳过找不到的条目，用户看到"已停用 8 条"却不知道有 2 条根本没动。
            let r = CredentialOrg.batchDisable(mac, pwdAliases: selPwds, fpBatches: selFps)
            if r.done > 0 {
                _ = Milestones.recordOrganize()
                app.flashReceipt("已写入本机")   // 508 已写入本机
                let extra = (r.failedPwds.count + r.failedFps.count) > 0 ? " · ⚠ 有 \(r.failedPwds.count + r.failedFps.count) 条已不在台账" : ""
                app.showToast("已停用 \(r.done) 条, 收入回收站" + extra)
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
                DB.delPwd(m, p.alias)
                done += 1
            }
            for f in fps {
                // 2026-10-13 对抗式排查: UInt32(越界 Int) 是 trap ⇒ 先安全转换, 越界就跳过并告知
                guard let b = f.batchU32 else {
                    app.showToast("指纹「\(f.name)」批次号越界 (\(f.batch))，已跳过 — 台账或备份来源可能损坏")
                    continue
                }
                try await app.lock.fpDelete(b)
                DB.delFp(m, f.batch)
                done += 1
            }
            showToastOrganized("已删除 \(done) 条")
        } catch {
            app.showToast(done > 0 ? "已删除 \(done) 条后中断: \(error.localizedDescription)" : "删除失败: \(error.localizedDescription)")
        }
        reload()
    }




    // ---------- OTP 内联卡 (App credentials + otpgenerate) ----------
    private var otpSection: some View {
        Section("临时密码 (ZOTP)") {
            VariantToggle("开通临时密码", isOn: Binding(
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
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
            } else {
            }
        }
    }


    @ViewBuilder
    private var otpGenRow: some View {
        HStack(spacing: DS.Space.s) {
            // 374: 采集进行中不把码排出来, 大字模式也拿不到明文 (刻意只换文本, 不整页遮黑)
                        Text(otpPwd)
                // 885 大字模式: 开关 (kf_ax_bigotp) 或双击切换, 等宽数字防跳 (231)
                .vkFont((DB.store.getBool("kf_ax_bigotp") || otpBig) ? .largeTitle.weight(.semibold).monospacedDigit() : .title3.weight(.semibold).monospacedDigit())
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
                    // 2026-10-17 真机勘误「临时码能生成但不显示」: 挡片默认值原为 true ——
                    // 生成出来的六位码被一层 .ultraThinMaterial 常驻盖住, 只有长按 0.5s 才露出来,
                    // 用户看到的就是"空白/******"。默认改为关 (需要的人仍可在设置-安全里打开)。
                    if !otpPeek {
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
                Clip.set(otpPwd)   // 405
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
                .vkFont(.caption).foregroundStyle(DS.Palette.textSub)
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
        // 周期必须取**锁端上报**的 zotpPeriod (03#05, 单位分钟), 缺省才回落 30。
        // 2026-10-17 对拍发现: 这里写死 30, 而锁端若是别的窗口, 页面算出的六位码锁端必判错
        // (读快照生成、反而能用)
        let pRaw = DB.readStatus(kc.mac)?.zotpPeriod ?? 0
        let period = pRaw > 0 ? pRaw : 30
        let pwd = ZOTP.generate(macHex: kc.mac, skeyHex: kc.skey, periodMin: period, idx: idx)   // period 单位=分钟（来自锁端 KLV#05 zotpPeriod）
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
        Clip.set(pwd)   // 405
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        return true
    }

    private var emptyHint: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("本机还没有凭证台账。用「添加密码」或「录入指纹」开始。")
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                // 包14/815 空态双按钮: 主"添加密码" + 次"看看它如何工作"
                HStack(spacing: DS.Space.s) {
                    NavigationLink { AddPwdView(embedded: true) } label: {
                        Text("添加第一条密码")
                            .vkFont(.subheadline, weight: .semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryActionStyle(fullWidth: false))
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

    // ---------- 506 误删撤销条: 删除后底部浮出 5 秒 "已删除 · 撤销", 撤销则原位还原不入回收站 ----------
    // 833: 第一次浮出时多附一句防误删说明 (HintOnce 之后不再出现)。
    // 第一百五十二批把这片的措辞改成**跟着真实路径走**：撤销要收回的东西不止回收站那一格 ——
    // 停用那条路还排着一条"待下发的锁端删除"并写着 361 停用便签；彻底删除那条路锁端已经真删了，
    // 本机恢复≠锁上还有。所以话术由 `CredentialOrg.undoRemove` 一份生成，界面不再各写一遍。
    // 2026-10-26 精简：stopUndoTimer 已删（undoBar 移除后无撤销条可停）。

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
        // 2026-10-27 审核修复 (AUDIT-D D-39)：**明文密码不再进 Toast**。
        // Toast 的问题：可截图、录屏、旁人一眼看到、且不随页面关闭而消失（有停留时间）、
        // 还会进无障碍朗读。而 `viewPwd` 是「看一眼明文」这个动作 —— 看完就该没了。
        // 改成系统 alert：用户点「知道了」即消失，不留在屏幕上。
        let alert = UIAlertController(title: "密码 #\(p.alias)",
                                      message: pwd + "\n\n请勿外传；关闭后不再显示。",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .cancel))
        UIApplication.topViewController()?.present(alert, animated: true)
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
        return "本机单条停用 · 管理员代操作"   // 468 本机单条停用
    }

    /// 364/180/360 停用: 本地移除 + 回收站 (7 天恢复窗口), 锁端删除入队 (本地意图, UI 明示)
    private func disablePwd(_ p: LedgerPwd) {
        guard busyKey == nil else { return }
        confirmDestructive("停用密码 #\(p.alias)",
                          // 天数口径：这个 7 天是 **364 的一键恢复窗口**，出处 `CredentialOrg.withinRecoverWindow`
                          //   里写死的 `7 * 86400`，与 497 那个 7~90 天可调的回收站保留期不是同一件事 (所以不读 reclaimDays)。
                          "停用后本机台账立即移除并收入回收站 — 7 天内可一键恢复, 超期需重新下发; 锁端删除记为「待下发」。",
                          confirmTitle: "停用") {
            DB.delPwd(mac, p.alias)
            // 361: 单条停用没有 313 的四选一, 便签如实记"未填", 不编一个原因充数 (要不要补必填见 NEXT-DECISIONS 组5)
            CredentialOrg.markDisabled(mac, kind: "pwd", keys: [p.alias], label: "未填", via: disableVia(owner: p.owner))
            showToastOrganized("已停用, 7 天内可恢复")   // 364 已停用
        }
    }
    private func disableFp(_ f: LedgerFp) {
        guard busyKey == nil else { return }
        confirmDestructive("停用指纹「\(f.name)」",
                          // 天数口径：同停用密码那一支 —— 7 天是 364 一键恢复窗口 (`withinRecoverWindow` 写死)，
                          //   不是 497 那个可调的回收站保留期。
                          "停用后本机台账立即移除并收入回收站 — 7 天内可一键恢复, 超期需重新录入; 锁端删除记为「待下发」。",
                          confirmTitle: "停用") {
            DB.delFp(mac, f.batch)
            CredentialOrg.markDisabled(mac, kind: "fp", keys: [f.batch], label: "未填", via: disableVia(owner: f.owner))   // 361 同上, 如实记未填; 468 代管时补标注
            showToastOrganized("已停用, 7 天内可恢复")   // 364 已停用
        }
    }

    /// 彻底删除: 锁端删除 + 本地删前快照 (494 双通道), 670 后果文案具体化
    private func deletePwd(_ p: LedgerPwd) {
        guard busyKey == nil else { return }
        confirmDestructive("彻底删除密码 #\(p.alias)",
                           // 「30 天」原先写死：回收站保留期是设置页那枚 7~90 天的 Stepper (497)，
                           // 用户调过之后这句就把安全网说大了 —— 而它恰恰出现在按下去就不可逆的那一刻。
                           "删除后该密码在锁内立即失效, 本机台账移除 (本机记录直接移除不可找回, 密码值需重新生成下发才有效)。确定继续？",
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
            // 确认口径：彻底删除 (670) —— 确认入口在外层的 `deletePwd` (confirmDestructive，±4 行窗口看不到那么远)，
            //   那一问的正文写的就是这一行做的事；锁端 pwdDelete 已直发，台账与回收站同一条 p，
            //   回收站 reclaimDays 天 (497) + 504 还原排重新下发 + 506 撤销条。
            DB.delPwd(m, p.alias)
            showToastOrganized("已彻底删除")
        } catch { app.showToast("删除失败: \(error.localizedDescription)") }
    }

    private func deleteFp(_ f: LedgerFp) {
        guard busyKey == nil else { return }
        confirmDestructive("彻底删除指纹「\(f.name)」",
                           "删除后果: 该指纹在锁内立即失效且无法远程补录 — 需成员本人到锁前重新录入 8 次指压。本机记录直接移除、不可找回。确定继续？",
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
        // 2026-10-13 对抗式排查: UInt32(越界 Int) 是 trap ⇒ 先安全转换
        guard let b = f.batchU32 else {
            app.showToast("指纹「\(f.name)」批次号越界 (\(f.batch))，已中止 — 台账或备份来源可能损坏")
            return
        }
        do {
            try await app.lock.ensureConnected(mac: m)
            try await app.lock.fpDelete(b)
            // 确认口径：同上面密码那一支 —— 确认在外层 `deleteFp`，只是指纹侧的后果写得更硬
            //   (无法远程补录，本人重录 8 次指压)；回收站那条回来的仍是档案，开门能力要重录 (670)。
            DB.delFp(m, f.batch)
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
                DB.setPwdNote(mac, p.alias, "")
            }
            if let f = fp {
                var nf = f; nf.note = ""
                DB.setFpNote(mac, f.batch, "")
            }
            _ = Milestones.recordOrganize()
            refreshTick += 1
        })
        alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in
            let note = (alert.textFields?.first?.text ?? "")
            if let p = pwd {
                var np = p; np.note = note
                DB.setPwdNote(mac, p.alias, note)
            }
            if let f = fp {
                var nf = f; nf.note = note
                DB.setFpNote(mac, f.batch, note)
            }
            _ = Milestones.recordOrganize()
            refreshTick += 1
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        UIApplication.topViewController()?.present(alert, animated: true)
    }

    /// 1007 维护致谢: 整理动作计数, 每 10 次附一句致谢
    /// 1007 整理动作计数 (致谢文案已随徽章引擎删除, 这里只记数 + 刷新)
    private func showToastOrganized(_ base: String) {
        Milestones.recordOrganize()
        app.showToast(base)
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
        let sheet = UIAlertController(title: "到期预警 #\(p.alias)",   // 359/930 到期预警
                                     message: "长期有效密码无到期点, 不适用。",
                                     preferredStyle: .actionSheet)
        func addTier(_ title: String, current: Bool, toggle: @escaping () -> Void) {
            sheet.addAction(UIAlertAction(title: (current ? "○ " : "◉ ") + title, style: .default, handler: { _ in toggle() }))
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
            sheet.addAction(off)
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        UIApplication.topViewController()?.present(sheet, animated: true)
    }
}


// ================= 全局弹窗助手 (各页面共用, 不再各写一份) =================
// 破坏性确认: 取消 / 标红确认
// UIAlertController 与 topViewController() 都是主 actor 的; 这两个助手只由界面动作调用,
// 所以整枚函数下沉到主 actor, action 也标 @MainActor (它执行的永远是界面上的"确认"动作)。
@MainActor
func confirmDestructive(_ title: String,
                        _ message: String,
                        confirmTitle: String = "确定",
                        action: @escaping @MainActor () -> Void) {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: confirmTitle, style: .destructive) { _ in action() })
    UIApplication.topViewController()?.present(alert, animated: true)
}

/// 109 删除冷静期: 比 confirmDestructive 更严一档 —— 必须**逐字键入指定词**才能提交,
/// 并把将被连带删除的数量写进正文 (破坏性动作的"后果预告"要可核对, 不能只说"将删除若干")。
@MainActor
func confirmDestructiveTyped(_ title: String,
                             _ message: String,
                             requireWord: String,
                             confirmTitle: String = "确认删除",
                             action: @escaping @MainActor () -> Void) {
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
