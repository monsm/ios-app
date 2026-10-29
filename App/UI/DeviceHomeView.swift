// 设备 Tab — 门锁总控页。
// 层级: 设备身份 → 连接与电量 → 需要处理的异常 → 开锁主控 → 快捷操作 → 最近开门。
// 开锁是全App最高频动作, 因此占据最大视觉权重并置于拇指可达区中部。
import SwiftUI
import UIKit

struct DeviceHomeView: View {
    @EnvironmentObject var app: AppState
    // 包1: 圆盘的连接语言 (241/242/245) 与回连触感 (243) 需要观察 BLE/锁会话实时状态 —
    // 两个服务单例不是 EnvironmentObject, 在此直接观察
    @ObservedObject var lockSvc = LockService.shared
    @ObservedObject var bleSvc = BLEService.shared
    // 包2 连接感知: 预握手/回连节律/回执 (只读观察, 不动协议)
    @ObservedObject var sense = LinkSense.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var showAdd = false
    // 2026-10-29：锁设置 sheet（B 档）—— 设备页工具栏齿轮打开
    @State var showLockSettings = false
    @State var refreshing = false
    @State var reconnectDot = false   // 91 回连静默小点
    @State var checks = [false, false, false]   // 87 排查清单勾选态
    // 包3 多锁导航: 101/763 横滑翻页 / 102 胶囊切换器 / 267 换锁二次确认 / 271 上滑默认 / 39 倒计时 / 112 换机向导
    @State var pageIndex = 0
    // 2026-10-29 修（**两处联动**）：pageOrder 原来是 @State 却**从未赋值**（只有 firstIndex 读点），
    // 恒空数组 ⇒ 换锁时永远走「不在翻页序列」分支。同时 groupFilter 只被 chip 写、**没人读**
    // （唯一读它的 inGroup 零调用）⇒ 组筛选点了没反应。改成从 app.devices 经 inGroup 派生，
    // 一次修好两处：组 chip 真生效，翻页序列也跟着过滤后的顺序走。
    var pageOrder: [String] {
        app.devices.filter { inGroup($0) }.map { $0.mac }
    }
    // 767 设备 Tab 按组切换: "" = 全部组。只影响"这一屏看得见哪些锁", 不动档案也不动数据。
    @State var groupFilter = ""
    @State var confirmMac: String?
    @State var confirmPulse = false
    @State var autoLockLeft: Int?
    // 同屏提醒要按预算排位，视图层的 @State 预算读不到。判据一字未改，只是换了存放处。
    @State var showRssi = false   // 63 点信号格弹出 dBm 数值 (格数看不出 1 格还是 2 格时看数字化)
    // 乱源治理第 3 批: 设备页模块显隐。默认空集 = 一块都不隐 (拍板口径), 面板只给能力不给默认。
    @State var devHidden = DevModuleStore.hidden
    /// 这一块现在该不该画 (必留的五块不走这里, 见 DevModules 文件头)
    func shown(_ m: DevModule) -> Bool { !devHidden.contains(m.rawValue) }

    var body: some View { vkBody.destined(.deviceHome) }
    var vkBody: some View {
        deviceShell
    }

    /// 2026-10-29：NavigationStack 壳 —— 从 vkBody 抽出，压 Swift 类型推断预算。
    @ViewBuilder
    var deviceShell: some View {
        NavigationStack {
            ScrollView {
                deviceContent
            }
            // 537 下拉重扫: 只扫不连。127 静默模式关的是"自动"回连/预握手/自动开锁,
            // 用户主动下拉属于手动动作 (与"手动圆盘照常"同一条口径), 所以这里不看 DiagFlags.silent。
            .refreshable { await rescanPull() }
            .dsScreenBackground()
            .navigationTitle(app.displayName)
            .toolbar {
                ToolbarItem(placement: barSide) {
                    Button { Task { await refresh(manual: true) } } label: {
                        if refreshing { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(refreshing)
                    .accessibilityLabel("刷新门锁状态, 键盘 Cmd/Control+R")
                }
                ToolbarItem(placement: barSide) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("添加设备")
                }
                // 2026-10-29：锁设置入口（齿轮放工具栏，不放 Hero 卡 —— 卡内 .accessibilityElement(.combine) 会吞按钮）
                ToolbarItem(placement: barSide) {
                    Button { showLockSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("锁设置")
                }
            }
            .sheet(isPresented: $showAdd) { AddDeviceView() }
            .sheet(isPresented: $showLockSettings) { LockSettingsView() }
            .sheet(isPresented: $showModuleOrder) { moduleOrderSheet }
            // 2026-10-28 删除：`showSettings` 是**死 sheet** —— 零 `= true` 写点。
            // 设置页走 Tab 切换（app.requestRoute(.settings)），不需要这个 sheet。
            // 250 二次开锁应用锁闸
            .sheet(isPresented: $app.showGate) { UnlockGateView() }
            // 91 回连静默小点: 回连成功不打扰, 胶囊旁亮一枚小点 3 秒
            .onChange(of: lockSvc.connectedMAC) { _, new in
                guard new == app.currentMac, !new.isEmpty else { return }
                reconnectDot = true
                // 112 换机迁移验证：这台锁真的连上过一次 ⇒ 打上已验证标记。
                // 原先只有 BackupView 立旗标 + 这里清旗标的读侧，**没有任何地方把 kf_migok_ 置真**，
                // 于是 allSatisfy 恒 false、向导永远收不起来。现在以「连接成功」作为验证通过的判据。
                if !DB.store.getString("kf_migrate_pending").isEmpty {
                    DB.store.set("kf_migok_" + new, true)
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    reconnectDot = false
                }
            }
            // 包3: 换锁后同步翻页索引 + 清理与锁绑定的过程态
            .onChange(of: app.currentMac) { _, new in
                // 2026-10-28 修复：confirmMac 全仓只有 = nil 的写点，**从没有一处写非 nil** ——
                // 于是 dialAction 里那条「首点只亮胶囊、二点才发指令」的软闸永不触发，
                // 换锁之后第一次点圆盘**直接开锁**（正是误触风险最高的时刻）。
                // 现在换锁即设防：新锁需要点两次才发指令。
                if confirmMac != new {
                    confirmMac = new.isEmpty ? nil : new
                    confirmPulse = false   // 换锁同时清掉上一次的脉冲态
                }
                if let i = pageOrder.firstIndex(of: new) {
                    if i != pageIndex { pageIndex = i }
                } else {
                    // 当前锁不在翻页序列 (如沉睡锁从胶囊选中) → 重建序列并落位
                    if let i = pageOrder.firstIndex(of: new) { pageIndex = i }
                }
            }
            .onChange(of: app.devices.count) { _, _ in
            }
            // 268 状态变化历史: 三态切换记最近 5 笔 (长按胶囊可回看)
            .onChange(of: sense.linkState) { _, new in
                sense.noteStateHop(new.name)
            }
            // 136 补充 跨页跳回: 已在设备 Tab 时 (细条只在非设备 Tab 出现, 保险起见) 也响应
            .onChange(of: app.pendingJumpLock) { _, m in
                guard let m else { return }
                app.pendingJumpLock = nil
                if m != app.currentMac {
                    app.select(m)
                    app.showToast("已定位到「" + app.displayName + "」")
                }
            }
    // 243 断连触感: 已连接 → 断开瞬间一次中触感 (Hero 卡同步灰化见 statusCard)
    .sensoryFeedback(trigger: lockSvc.connectedMAC) { old, new in
        old == app.currentMac && new.isEmpty ? .impact(weight: .medium) : nil
    }
    // 39 自动上锁倒计时: 开锁成功即起秒 (本地回放 cmd24 档位, 不猜测门磁)
    .onChange(of: app.unlockState) { _, s in
        guard case .success = s else { return }
        startAutoLockCountdown()
    }
            .task {
                await refresh()
                sense.enterPage()   // 95 进页预热: 静默 ensureConnected + 93 信号围栏 + 96 只预热不执行
                // 包2/136 补充 跨页跳回: 记录/告警入口点"跳回设备页定位该锁"
                if let m = app.pendingJumpLock {
                    app.pendingJumpLock = nil
                    if m != app.currentMac {
                        app.select(m)
                    }
                    app.showToast("已定位到「" + app.displayName + "」")   // 136 界面文案
                }
                // 801 引导末卡"去连接真锁": 引导退场后本页才挂载, 由这里把添加设备拉起来
                if app.pendingAddDevice {
                    app.pendingAddDevice = false
                    showAdd = true
                }
            }
        }
    }

    /// 2026-10-29：从 vkBody 抽出 —— 加了齿轮/sheet 后整个表达式触发 Swift 类型推断超时，
    /// 拆一层是最小修复（`error: unable to type-check this expression in reasonable time`）。
    @ViewBuilder
    var deviceContent: some View {
                VStack(spacing: DS.Space.m) {
                    if app.devices.isEmpty {
                        Card {
                            EmptyState(systemImage: "lock.open.rotation",
                                       title: "还没有添加门锁",
                                       message: "请先在门锁键盘上长按重置键恢复出厂，再回到这里添加设备（需要开启蓝牙）",
                                       actionTitle: "添加设备") { showAdd = true }
                            // 824 第二出口: 只有"再扫一次"不够 —— 换机或误删之后用户手上拿的是
                            // 一份备份文件，不是一把门锁。指不到恢复入口的空态等于把数据判了死刑。
                            Button {
                                // 2026-10-14 走查: 原为直写 `app.tabSelection = 3` —— 设备页在访客通道
                                // 下照常可达, 而访客态里「设置」Tab 不进层级树, 直写会落到一个看不见的
                                // Tab (点一下像没反应)。走 requestTab, 访客态由它拉起复核页。
                                app.pendingSettingsFocus = "backup"   // §4.3: 这一按直达「备份与恢复」, 不再只放人在设置页根上
                                app.requestRoute(.settings)
                                app.showToast("到「备份与恢复」：可本地导入，或从坚果云恢复")   // 824 设置
                            } label: {
                                Label("从备份恢复", systemImage: "square.and.arrow.down")   // 824 从备份恢复
                                    .vkFont(.subheadline, weight: .medium)
                                    .foregroundStyle(DS.Palette.accentText)
                                    .frame(maxWidth: .infinity, minHeight: DS.Hit.min)
                            }
                            .buttonStyle(PressableButtonStyle())
                            // 1044 家庭公告板: 空态里的一张便签
                        }
                    } else {
                        // 767 按组切换 + 764 多锁状态图标行: 都放在 Hero 卡上方 ——
                        // 先一眼看清"哪把锁有事", 再落到当前锁的主控卡。
                        if app.devices.count > 1 {
                            if shown(.groupChips) { groupChips }
                        }
                        // 868 扫描组划分: 状态卡 / 圆盘 / 快捷格各自成组 (children: .contain),
                        // 外接开关与"切换控制"可以按组逐项聚焦, 不用在整页里一个个划过去。
                        moduleSlot(devOrder[0], delay: 1)   // 904: 槽位固定, 哪个模块占这个槽由用户定
                        // 2026-10-29 深重构：锁的唯一入口。Hero 卡内不能放按钮（`.accessibilityElement(.combine)`
                        // 会把按钮吞成整卡一个 VoiceOver 元素），所以用独立行 —— HIG 的 disclosure 惯例。
                        if app.current != nil {
                            NavigationLink {
                                LockSettingsView()
                            } label: {
                                HStack(spacing: DS.Space.s) {
                                    Label("管理这把锁", systemImage: "slider.horizontal.3")
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(DS.Palette.textSub)
                                }
                                .frame(maxWidth: .infinity, minHeight: DS.Hit.min)
                            }
                            .buttonStyle(PressableButtonStyle())
                            .padding(.horizontal, DS.Space.gutter)
                            .accessibilityHint("锁的概览、布防、防尾随、静音、固件与危险操作")
                        }
                        attentionCard
                        if shown(.linkSense) { linkSenseCard }
                        // 2026-10-27 审核：凭证选择胶囊已删（PIN 胶囊那一族），此处空壳一并移除。
                        unlockDial
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel("开锁圆盘组")   // 868 开锁圆盘组
                        // 2026-10-29：布防入口 —— 原来只在「设置 → 锁段」，用户找不到（本次审核的起点）。
                        // 只在锁支持布防时出现（canDefend）；与设置页那条**并存**（不删，避免打断老用户习惯）。
                        // 行内带当前布防状态（DefendKit.summary），不用点进去才知道现在是"撤防"还是"布防中"。
                        // 放圆盘下方：HIG 说重要控制宜在中部/下部，且与开锁动作同屏。
                        if let kc = app.current, PidMap.canDefend(kc.pid) {
                            NavigationLink {
                                DefendView()
                            } label: {
                                HStack(spacing: DS.Space.s) {
                                    Label("布防", systemImage: "shield.lefthalf.filled")
                                    Spacer(minLength: 0)
                                    Text(DefendKit.summary(DB.defend(kc.mac)))
                                        .vkFont(.caption)
                                        .foregroundStyle(DefendKit.isActive(DB.defend(kc.mac))
                                                         ? DS.Palette.ok : DS.Palette.textSub)
                                }
                                .frame(maxWidth: .infinity, minHeight: DS.Hit.min)
                            }
                            .buttonStyle(PressableButtonStyle())
                            .padding(.horizontal, DS.Space.gutter)
                            .accessibilityHint("时段内一票否决自动开锁；布防期间靠近门锁不会自动开门")
                        }
                        moduleSlot(devOrder[1], delay: 4)   // 904
                        moduleSlot(devOrder[2], delay: 5)   // 904
                        // 904 模块排序入口: 做成显式文字按钮 —— 原句点名的"长按设备页空白进编辑态"会与
                        // 60/873 那族手势链冲突 (设备页是 ScrollView, 空白长按同时是滚动/下拉刷新的一部分),
                        // 排序落成上/下移按钮, 不改整页手势。
                        Button { showModuleOrder = true } label: {
                            Label("模块排序与显隐", systemImage: "arrow.up.arrow.down")   // 904 模块排序
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                                .frame(maxWidth: .infinity, minHeight: DS.Hit.min)
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
                .padding(.vertical, DS.Space.m)
    }

    /// 537 下拉重扫: 三种结果说实话 —— 蓝牙没开 / 扫到了 (给信号数值) / 超时没扫到 (不假装刷新成功)。
    /// 走的是现有 `LinkSense.scan` (startScan/stopScan 成对, 不连接、不下发任何指令)。
    func rescanPull() async {
        guard sense.btOn else {
            app.showToast("系统蓝牙未开启 — 下拉重扫做不了")   // 537 系统蓝牙未开启
            return
        }
        do {
            if let dev = try await sense.scan(mac: app.currentMac, timeoutMs: 4000) {
                sense.noteScannedRssi(dev.rssi)
                app.showToast("已重扫: 信号 \(dev.rssi) dBm")   // 537 已重扫
            } else {
                app.showToast("4 秒内没扫到这把锁的广播 — 走近一点再下拉")   // 537 秒内没扫到这把锁的广
            }
        } catch {
            app.showToast("扫描没能启动: 蓝牙栈忙或权限未就绪")   // 537 扫描没能启动
        }
        await refresh(manual: true)
    }

    func refresh(manual: Bool = false) async {
        guard !refreshing else { return }
        refreshing = true
        // 127 静默档的边界按"谁起的这个动作"算: 按钮与下拉是用户主动 (manual: true),
        // 进页 `.task` 与切锁后的自动刷新不算 (口径见 AppState.refreshStatusQuietly 与 :71 那条既有注释)。
        await app.refreshStatusQuietly(manual: manual)
        refreshing = false
        // 764 图标行的红点 + 765 跨锁合并流: 同一批"要遍历各锁日志"的聚合放在一起算一次。
        // 都走本地缓存, 不主动连锁 —— 下拉刷新已经把 03 快照发出去了, 这里不再叠一轮 IO。
        let us = LockStats.usage()
        // 112: 迁移验证全部通过后清掉向导旗标 (下次恢复备份会重新立起)
        let flag = DB.store.getString("kf_migrate_pending")
        if !flag.isEmpty, !app.devices.isEmpty,
           app.devices.allSatisfy({ DB.store.getBool("kf_migok_" + $0.mac) }) {
            DB.store.remove("kf_migrate_pending")
        }
    }

    /// 767 组过滤: "" = 全部; "未分组" = 档案里组名为空的那些。
    /// 图标行与翻页共用这一条判据, 免得出现"chip 选了家用, 图标行还亮着仓库"的两套答案。
    // 【保留未接 2026-10-29】设备组筛选判据（"" = 全部 / "未分组" = 组名为空）—— 设备页组 chip 用
    func inGroup(_ kc: Keychain) -> Bool {
        if groupFilter.isEmpty { return true }
        let g = LockArchive.group(kc.mac)
        return groupFilter == LockArchive.ungroupedLabel ? g.isEmpty : g == groupFilter
    }
    /// 图标行的锁集: 组过滤后**全部**可见 (含沉睡/隐藏) — 它是"看一眼有没有事"的面,
    /// 把沉睡锁藏起来正好会让最该被看见的那把消失。
    /// 229 左手模式：工具条两侧对调、快捷格顺序镜像（常用那格落到拇指侧）。
    /// （左手模式已于 2026-10-26 删除，工具栏位置/次序现为恒定。）此前它被设置页读写、
    /// 全仓没有任何消费者 —— "镜像"是两个只改自己标签的按钮之一，这两行把它接上。
    var barSide: ToolbarItemPlacement {
        .navigationBarTrailing
    }
    var tiles: [QuickAction] {
        let o = QuickPool.ordered()
        return o
    }



    // ---------- 需要用户处理的异常: 只在真有问题时出现, 不占常驻版面 ----------
    @ViewBuilder
    static let lastStamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()


    // ---------- 开锁主控 ----------
    var checkTexts: [String] {
        ["手机蓝牙已开启", "已靠近门锁 (1–2 米内)", "门锁电量充足 (低于 20% 先换电池)"]
    }
    // 85 退避节奏文案
    var retryText: String? {
        guard let w = app.retryWait else { return nil }
        return "第 \(app.retryAttempt) 次 · 等 \(w) 秒"
    }

    // 2026-10-27 三轮精简：focusButton（专注开锁入口）已删。

    // ---------- 快捷操作 ----------
// 液态玻璃: 相邻玻璃元素必须放进同一个 GlassEffectContainer 才能融成一体,
    // 否则每块各自折射、边缘会出现难看的接缝。
    var moduleOrderSheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(devOrder.enumerated()), id: \.offset) { i, id in
                        HStack(spacing: DS.Space.s) {
                            Text(moduleName(id))
                                .vkFont(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityLabel("\(moduleName(id)), 第 \(i + 1) 位")
                            Button { moveModule(i, -1) } label: { Image(systemName: "arrow.up") }
                                .disabled(i == 0)
                                .frame(minHeight: DS.Hit.min)
                                .accessibilityLabel("上移 \(moduleName(id))")
                            Button { moveModule(i, 1) } label: { Image(systemName: "arrow.down") }
                                .disabled(i == devOrder.count - 1)
                                .frame(minHeight: DS.Hit.min)
                                .accessibilityLabel("下移 \(moduleName(id))")
                        }
                        .frame(minHeight: DS.Hit.min)
                        // 2026-10-14: .combine 会把两个纯图标按钮并成单一元素 => 读屏无法分别点上/下移。
                        // 改 .contain 保留子元素可操作性, 排序提示挪到模块名与按钮上。
                        .accessibilityElement(children: .contain)
                    }
                } header: {
                    Text("设备页模块顺序")   // 904 设备页模块顺序
                } footer: {
                    Text("槽位固定 (Hero 槽 / 快捷格槽 / 最近开门槽), 改的是哪个模块占哪个槽 —— 默认顺序就是现在的样子。")
                        .vkFont(.caption).foregroundStyle(DS.Palette.textSub)
                }
                // 乱源治理第 3 批: 显隐面板。默认全开 (一块都不隐), 这一节给的是"能不能关"，不是新默认值。
                Section {
                    ForEach(DevModule.allCases) { m in
                        VStack(alignment: .leading, spacing: DS.Space.xs) {
                            // 系统 Toggle: 标题写明用途, 开/关态由系统播报, 不另写重复值 (232 同口径)
                            VariantToggle(isOn: Binding(
                                get: { !devHidden.contains(m.rawValue) },
                                set: { on in
                                    DevModuleStore.setHidden(m, !on)
                                    devHidden = DevModuleStore.hidden   // 写盘之外还要即时生效 (UserDefaults 不是可观察源)
                                })) {
                                Text(m.title)
                            }
                            Text(m.cost)
                                .vkFont(.caption2)
                                .foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, DS.Space.xs)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(m.title)，关掉会少什么：\(m.cost)")
                    }
                } header: {
                    Text("显示与隐藏")
                } footer: {
                    Text("默认全部显示。关掉只是本页不再画这一块，功能、数据与排程都不受影响；设备切换器、开锁圆盘、三个可排序槽与异常卡不能关 —— 前两件是主操作与身份，后两件藏了就等于把警告和数据说明瞒掉。")
                        .vkFont(.caption).foregroundStyle(DS.Palette.textSub)
                }
                // 2026-10-28 补齐：这张面板原来只排 3 个模块槽 + 3 个显隐开关，
                // **改不了快捷格的组成与顺序** —— 而设置页 :869 的文案写着
                // 「也可以直接在设备页长按任一快捷格打开这份编辑」。
                // 那句话一直不成立（长按打开的就是这张面板，改不了快捷格）。
                // 现在把快捷格的十一选六搬进来，两处入口改的是同一份数据（QuickPool）。
                Section {
                    ForEach(QuickPool.all) { a in
                        VariantToggle(a.label, isOn: Binding(
                            get: { QuickPool.selected.contains(a) },
                            set: { on in
                                var ids = QuickPool.selected.map { $0.id }
                                if on { if !ids.contains(a.id) { ids.append(a.id) } }
                                else { ids.removeAll { $0 == a.id } }
                                // 一格都不留 = 快捷区整体消失，兜回默认格
                                QuickPool.setSelected(ids.isEmpty ? QuickPool.defaultIds : ids)
                                app.bumpAppearanceForLayout()
                            }))
                    }
                    VariantToggle("常用动作排到前面", isOn: Binding(
                        get: { QuickPool.smartFirst },
                        set: { v in
                            QuickPool.setSmartFirst(v)
                            if !v { QuickPool.clearCounts() }
                            app.showToast(v ? "开始按点击次数排序（只存本机）" : "已停止记录并清空计数")
                            app.bumpAppearanceForLayout()
                        }))
                } header: {
                    Text("快捷操作格")
                } footer: {
                    Text("勾选要在设备页显示的格子。一格都不留会兜回默认格 —— 「自定义」不该等于「自残」。")
                        .vkFont(.caption).foregroundStyle(DS.Palette.textSub)
                }
                Section {
                    Button("恢复默认") {
                        DB.store.remove("kf_dev_order")
                        DevModuleStore.reset()
                        devHidden = DevModuleStore.hidden
                        orderTick += 1
                    }
                }
            }
            .navigationTitle("模块排序与显隐")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") { showModuleOrder = false }
                }
            }
        }
    }


    var bleOn: Bool { app.lock.connectedMAC == app.currentMac }
    // 包2/69 系统蓝牙开关 (btReady): 关时全 App 顶部出引导条; 与 bleOn (该锁会话) 区分
    var btReady: Bool { bleSvc.isPoweredOn }
    /// 包2/64 三态: 当前锁链路 (非当前锁视为静态预览 → 未连接)
    /// 链路三态 + 「密钥未绑定」。
    ///
    /// 2026-10-27 截图核对修复：原实现只返回 `sense.linkState`（纯 BLE 连接态），
    /// 于是蓝牙连着就显示「门锁在线，随时可开」，而同一屏的黄条又说「密钥尚未绑定」。
    /// 密钥没绑定 ⇒ 签不出开锁凭据 ⇒ **开不了**。现在把 sKeyStatus 纳入判据：
    /// 连着但密钥未绑定 ⇒ `.notReady`，徽章文案随之改成「密钥未绑定」而不是「随时可开」。
    func linkState(for kc: Keychain) -> LinkState {
        guard kc.mac == app.currentMac else { return .down }
        let s = sense.linkState
        // 只有"已连接"这一态会被密钥状态否决；握手中/未连接本来就是"不能开"，不用改。
        if s == .ready {
            let sKey = app.status?.sKeyStatus ?? app.snapshot?.sKeyStatus ?? 0
            if sKey != 0 { return .notReady }
        }
        return s
    }
    // 1004/114 低电判定 (0~20, 判定逻辑收敛到 BatteryCare)
    func isLow(_ kc: Keychain) -> Bool { BatteryCare.isLow(batteryPct(for: kc)) }
    // 113 五档电量档位
    func battTier(for kc: Keychain) -> BatteryCare.Tier { BatteryCare.tier(batteryPct(for: kc)) }
    /// 120: 告急档 (≤10) 染红, 低电档 (11–20) 染橙, 其余保持常规白。
    /// 染红不跟 tier.severe 走 — severe 现在管 ≤20 的整套降级, 红色仍只到 ≤10 (与 1004 的二级升级同界)。
    func battTint(for kc: Keychain) -> Color? {
        if (0...10).contains(batteryPct(for: kc)) { return DS.Palette.danger }
        return isLow(kc) ? DS.Palette.warn : nil
    }
    func batteryPct(for kc: Keychain) -> Int {
        // 包4 + 2026-10-15 走查: 读数与写法都收进 BatteryCare.facePct/faceText, 这里只留"实时读数只属于当前这把"这一条判据
        // —— 专注模式那块的圆盘以前拿不到这个式子, 转子播电量时只会念"未知"。
        BatteryCare.facePct(kc.mac, live: kc.mac == app.currentMac ? (app.status?.powerLevel ?? -1) : -1)
    }
    func batteryText(for kc: Keychain) -> String {
        BatteryCare.faceText(batteryPct(for: kc))
    }
    func firmwareText(for kc: Keychain) -> String {
        if kc.mac == app.currentMac, let fw = app.status?.firmware, !fw.isEmpty { return fw }
        let fw = kc.fw.isEmpty ? (DB.readStatus(kc.mac)?.firmware ?? "") : kc.fw
        return fw.isEmpty ? "未知" : fw
    }
    func lockClockText(for kc: Keychain) -> String {
        if kc.mac == app.currentMac, let lt = app.status?.lockTime { return ProtoTime.localStr(lt) }
        let t = DB.readStatus(kc.mac)?.lockTime ?? 0
        return t > 0 ? ProtoTime.localStr(t) : "--"
    }
    var staleSync: Bool {
        let t = DB.syncTime(app.currentMac)
        guard t > 0 else { return false }
        return Date().timeIntervalSince1970 * 1000 - t > 30 * 86400 * 1000
    }
}

// ================= 校时页 (App synctime) =================
