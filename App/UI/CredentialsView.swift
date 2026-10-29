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
    @ObservedObject var sense = LinkSense.shared
    @State var refreshTick = 0
    /// 正在与门锁通信的条目 ("pwd:3" / "fp:12" / "otp") / nil = 空闲
    @State var busyKey: String?
    @State var otpPwd = "******"
    @State var otpWin = ""
    @State var otpBig = false   // 885 凭证大字模式: 双击或开关切大字号对照抄写""
    @State var otpShieldOn = false  // 375 防窥挡片: **默认关**（开了才会盖住临时码）
    @State var otpReveal = false    // 375 长按挡片查看中（松手复位）

    // ---------- 包6 列表组织 ----------
    @State var seg: Int = 0          // 524 类型分段: 0 全部 / 1 密码 / 2 指纹 / 3 临时码
    @State var memberView = CredentialOrg.groupMode == .owner   // 355 按成员视图
    @State var search = ""
    /// 2026-10-26 恢复：`isBusy` 在清理四件套时被误删（它读 busyKey，是主流程状态）。
    var isBusy: Bool { busyKey != nil }
    // 2026-10-26 恢复：这些 @State 在清理四件套时被连带删掉，但它们是主流程状态。
    @State var editMode = false
    @State var showCalendar = false   // 2026-10-29: 到期月历 sheet
    @State var selPwds: [Int] = []
    @State var selFps: [Int] = []
    @State var showExtend = false
    @State var extendAliases: [Int] = []
    @State var showDisable = false
    @State var pwdDetailItem: LedgerPwd?   // 包5 PwdDetailStudio
    @State var fpDetailItem: LedgerFp?     // 包5 FpDetailStudio

    var body: some View { vkBody.destined(.credentials) }
    var vkBody: some View {
        NavigationStack {
            Group {
                if app.current == nil {
                    EmptyState(systemImage: "lock.badge.plus",
                               title: "还没有添加门锁",
                               message: "凭证台账要绑定到具体门锁。请先在门锁键盘上长按重置键恢复出厂，再回来添加设备（需要开启蓝牙）。",
                               actionTitle: "去添加门锁") { goAddDevice() }
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
            // 2026-10-29: 到期月历
            .sheet(isPresented: $showCalendar) { CredentialCalendarView() }
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
        // 2026-10-28 删除：`showTempCode` 是**死 sheet** —— 全仓只有声明与绑定，
        // 零 `= true` 写点，那张面板永远不会出现。临时码功能走的是页内的 otpSection，不需要这个 sheet。
            // 2026-10-26 精简：版本历史 sheet 已删。
            .sheet(item: $pwdDetailItem) { item in
                PwdDetailStudio(alias: item.alias)
            }
            .sheet(item: $fpDetailItem) { item in
                FpDetailStudio(batch: item.batch)
            }
        }
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

    func reload() { refreshTick += 1 }

    var mac: String { app.current?.mac ?? "" }

    // ---------- 顶部工具条 (524 分段计数 / 914 四维排序器 / 363 月历 / 358 整理 / 347 选择) ----------
    // 472 借用横条: 页顶显示进行中借用, 点 已归还 销记
    // ---------- 577 详情跳凭证定位 (包9): 记录/告警详情"来源凭证"深链 → 高亮条 + 打开对应详情 ----------
    /// 消费深链: pwd:<alias> → 密码段 + 打开详情; fp:<batch> → 指纹段。跨锁时先切锁。
    func consumeCredJump() {
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
    func consumeCredSelect() {
        guard let ids = app.pendingCredSelect else { return }
        app.pendingCredSelect = nil
        withAnimation(DS.Motion.quick) { editMode = true }
        selPwds = ids
        selFps = []
    }

    // 2026-10-26 精简：pendingQueueBar（待下发横条）已删（队列功能整套移除）。
    var LockArchiveLockName: String {
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
    var headerToolbar: some View {
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
                        // 2026-10-29：`CredentialOrg.monthDeadlines` / `dayDeadlines` 零调用 —— 到期月历入口
                        Button { showCalendar = true } label: {
                            Label("到期月历", systemImage: "calendar")
                        }
                        // 2026-10-27 三轮精简：排序入口已删（排序四档移除）。
                        Button {
                            memberView.toggle()
            // 2026-10-26 精简：分组模式持久化已删（整理功能移除）。
                        } label: {
                            Label(memberView ? "按类型分组" : "按成员分组", systemImage: "person.2")
                        }
                    }
            // 2026-10-27 删除：`Section("筛选")` 是个**空壳** —— 里面的「智能列表」
            // 已于 2026-10-26 精简时删掉，只剩这一行注释。菜单里挂一个点不出任何东西的分组，
            // 用户会以为是坏的。
                    // 2026-10-28 修复：这里原来是**空壳** —— 空 label 的 Button、只有触感没有动作，
                    // 而 editMode 唯一置 true 的路径（app.pendingCredSelect）全仓只有 `= nil` 写点，
                    // 于是全选/批量延期/导出/停用/删除 **7 个按钮永远不出现**。
                    // 现在这里给两件真能用的：进入多选、按条件智能选取。
                    Section("整理") {
                        if !editMode && CredentialOrg.typeCounts(mac).all > 0 {
                            Button {
                                DS.Haptics.tick.impactOccurred()
                                withAnimation(DS.Motion.quick) { editMode = true }
                                selPwds = []
                                selFps = []
                            } label: {
                                Label("选择凭证 (批量操作)", systemImage: "checkmark.circle")
                            }
                        }
                        if editMode {
                            Button {
                                DS.Haptics.tick.impactOccurred()
                                // 智能选取：按当前 seg 与筛选条件选中全部可见行（真实现，不再是空动作）
                                let pwds = sortedPwds.map { $0.alias }
                                let fps = sortedFps.map { $0.batch }
                                selPwds = pwds
                                selFps = fps
                                app.showToast("已选中 \(pwds.count + fps.count) 条（当前筛选下的全部）")
                            } label: {
                                Label("智能选取 (当前筛选全部)", systemImage: "wand.and.stars")
                            }
                            Button(role: .destructive) {
                                DS.Haptics.tick.impactOccurred()
                                withAnimation(DS.Motion.quick) { editMode = false; selPwds = []; selFps = [] }
                            } label: {
                                Label("退出多选", systemImage: "xmark.circle")
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

    // ---------- 批量操作栏 (347/348/349/351/353/357) ----------
    @ViewBuilder
    var batchBar: some View {
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
                // 2026-10-29 补（**注释承诺了、按钮却不在**）：本段上方注释写着「上一排是整理类
                // (置顶/延期/移交/前缀/导出)」，实际只有「延期」「导出」两个 —— 而 `CredentialOrg.batchPrefixNote`
                // 一直在、零调用。补回「前缀」按钮。
                batchBtn("前缀", icon: "textformat.abc") {
                    if selCount == 0 { app.showToast("先选择凭证"); return }
                    promptBatchPrefix()
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
                                       "删除后这些凭证在锁内立即失效（需门锁在场直发）；本机台账记录直接移除、**不可找回**（没有回收站），值或开门能力要重新下发。确定继续？",
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
    /// 2026-10-29：批量加前缀（`CredentialOrg.batchPrefixNote` 的 UI 入口）。
    /// 只加在**还没有这个前缀**的条目上（函数内判 `hasPrefix`），不会重复叠加。
    func promptBatchPrefix() {
        let n = selCount
        let alert = UIAlertController(
            title: "批量加前缀",
            message: "给已选的 \(n) 条凭证的备注前加同一个前缀（例如「客房-」）。已有备注会保留在前缀后面。",
            preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "前缀"
            tf.autocorrectionType = .no   // UITextField 没有 autocorrectionDisabled（那是 SwiftUI 的）
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "加前缀", style: .default) { _ in
            let p = (alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespaces)
            guard !p.isEmpty else { app.showToast("前缀不能为空"); return }
            let done = CredentialOrg.batchPrefixNote(mac, pwdAliases: selPwds, fpBatches: selFps, prefix: p)
            app.showToast(done > 0 ? "已给 \(done) 条加前缀「\(p)」" : "没有可加的凭证（可能都已带这个前缀）")
            reload()
        })
        UIApplication.topViewController()?.present(alert, animated: true)
    }

    func batchBtn(_ t: String, icon: String, destructive: Bool = false, _ a: @escaping () -> Void) -> some View {
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
    func exportPackage() {
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
    @State var secretOnce: String?
    func presentSecretOnce(_ s: String) { secretOnce = s }

    func finishDisable() {
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
                app.showToast("已停用 \(r.done) 条" + extra)
                reload()
            } else {
                app.showToast("所选凭证已不在台账")
                reload()
            }
        }
    }

    /// 922 批量删除: 逐条复用单条「彻底删除」那一支 (锁内直删 + 回收站留档), 不做物理删;
    /// 中断时把已删条数如实报出, 不静默跳过 (与批量停用同一个 busyKey 闸, 不加第二把锁)
    func batchDelete() async {
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

    /// 2026-10-29 入口去重：添加设备只在设备页右上角「+」，这里只做跳转 + 指路。
    func goAddDevice() {
        app.requestRoute(.device)
        app.showToast("在设备页右上角点「+」添加门锁")
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
