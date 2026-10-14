// 设备 Tab — 门锁总控页。
// 层级: 设备身份 → 连接与电量 → 需要处理的异常 → 开锁主控 → 快捷操作 → 最近开门。
// 开锁是全App最高频动作, 因此占据最大视觉权重并置于拇指可达区中部。
import SwiftUI
import UIKit

struct DeviceHomeView: View {
    @EnvironmentObject var app: AppState
    // 包1: 圆盘的连接语言 (241/242/245) 与回连触感 (243) 需要观察 BLE/锁会话实时状态 —
    // 两个服务单例不是 EnvironmentObject, 在此直接观察
    @ObservedObject private var lockSvc = LockService.shared
    @ObservedObject private var bleSvc = BLEService.shared
    // 包2 连接感知: 预握手/回连节律/回执 (只读观察, 不动协议)
    @ObservedObject private var sense = LinkSense.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showAdd = false
    /// 437 到期的备份复核钉。**不进 body 里算** —— duePins 要列一次目录 + 解两份偏好,
    /// 而本页 body 随 BLE 状态频繁重算 (与 432 的 buildCover 同一条理由), 所以进页/刷新时算一次。
    @State private var duePins: [BackupStudio.PinDue] = []
    @State private var refreshing = false
    @State private var showFocus = false      // 81 全屏专注开锁
    @State private var flipped = false        // 78 Hero 卡翻面
    @State private var reconnectDot = false   // 91 回连静默小点
    @State private var checks = [false, false, false]   // 87 排查清单勾选态
    // 包3 多锁导航: 101/763 横滑翻页 / 102 胶囊切换器 / 267 换锁二次确认 / 271 上滑默认 / 39 倒计时 / 112 换机向导
    @State private var pageIndex = 0
    @State private var pageOrder: [String] = []
    // 767 设备 Tab 按组切换: "" = 全部组。只影响"这一屏看得见哪些锁", 不动档案也不动数据。
    @State private var groupFilter = ""
    // 764 图标行的红点判据 + 765 跨锁合并流: 都在进页/刷新时算一次, 不在 body 里遍历各锁日志 (与 437 同一条理由)
    @State private var alarmMacs: Set<String> = []
    @State private var mergedRecent: [Rec] = []
    @State private var activeTops: [Member] = []   // 790 最近活跃头像圈 (与 mergedRecent 同一刷新时机)
    @State private var recentAllLocks = false   // 765 当前锁 / 全部锁 (持久化 kf_recent_all, 与 566 同一口径)
    @State private var confirmMac: String?
    @State private var confirmPulse = false
    @State private var autoLockLeft: Int?
    @State private var wizardBusy = ""
    @State private var wizardDismissed = false
    @State private var showOverview = false
    @State private var showManage = false     // 104/107/766 设备管理 (排序/分组/批量)
    @State private var showSettings = false   // 包8/507 备份角标跳转
    @State private var showTileEdit = false   // 905 长按快捷格 → 编辑面板
    // 827 的"本会话点过哪些格 / 是否关了提示"两态搬到 AppState (ambientTipUsed / ambientTipOff):
    // 同屏提醒要按预算排位，视图层的 @State 预算读不到。判据一字未改，只是换了存放处。
    @State private var showRssi = false   // 63 点信号格弹出 dBm 数值 (格数看不出 1 格还是 2 格时看数字化)
    // 乱源治理第 3 批: 设备页模块显隐。默认空集 = 一块都不隐 (拍板口径), 面板只给能力不给默认。
    @State private var devHidden = DevModuleStore.hidden
    /// 这一块现在该不该画 (必留的五块不走这里, 见 DevModules 文件头)
    private func shown(_ m: DevModule) -> Bool { !devHidden.contains(m.rawValue) }

    var body: some View {
        NavigationStack {
            ScrollView {
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
                                app.tabSelection = 3
                                app.showToast("设置 → 备份：可本地导入，或从坚果云恢复")   // 824 设置
                            } label: {
                                Label("从备份恢复", systemImage: "square.and.arrow.down")   // 824 从备份恢复
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(DS.Palette.accentText)
                                    .frame(maxWidth: .infinity, minHeight: DS.Hit.min)
                            }
                            .buttonStyle(PressableButtonStyle())
                            // 1044 家庭公告板: 空态里的一张便签
                            if !Milestones.bulletin.isEmpty {
                                Label(Milestones.bulletin, systemImage: "pin.fill")
                                    .font(.footnote)
                                    .foregroundStyle(DS.Palette.accentText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } else {
                        if !wizardDismissed { migrationWizard.staggered(0) }
                        if app.devices.count > 1 { capsuleSwitcher.staggered(0) }
                        // 42 首用气泡引导: 多锁用户最容易错过的动作是"长按这排胶囊看最近状态变化"
                        // (那件事本身是 268，已经实现)。只说一次、由用户自己点掉;
                        // 提示承诺的必须是**页面上真做得出**的动作 —— 832 那条就想承诺一个不存在的长按。
                        if app.ambientTop == .firstUseCapsule {
                            Button { app.firstUseCapsuleDone = true; HintOnce.mark("capsule268") } label: {
                                HStack(spacing: DS.Space.xs) {
                                    Image(systemName: "hand.point.up.left")
                                        .font(.system(size: DS.Icon.xs))
                                    Text("小提示：长按主控卡上的「连接耗时」标记可看最近状态变化")   // 42/268 小提示
                                        .font(.caption2)
                                        .multilineTextAlignment(.leading)
                                }
                                .foregroundStyle(DS.Palette.textSub)
                                .padding(.horizontal, DS.Space.s)
                                .padding(.vertical, DS.Space.xs)
                                .background(Capsule().fill(DS.Palette.surfaceAlt))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(minHeight: DS.Hit.min)
                            }
                            .buttonStyle(PressableButtonStyle())
                            .accessibilityLabel("首用提示：长按主控卡上的连接耗时标记可看最近状态变化，点按收起")
                        }
                        // 767 按组切换 + 764 多锁状态图标行: 都放在 Hero 卡上方 ——
                        // 先一眼看清"哪把锁有事", 再落到当前锁的主控卡。
                        if app.devices.count > 1 {
                            if shown(.groupChips) { groupChips.staggered(0) }
                            if shown(.statusIcons) { statusIconRow.staggered(0) }
                        }
                        // 868 扫描组划分: 状态卡 / 圆盘 / 快捷格各自成组 (children: .contain),
                        // 外接开关与"切换控制"可以按组逐项聚焦, 不用在整页里一个个划过去。
                        moduleSlot(devOrder[0], delay: 1)   // 904: 槽位固定, 哪个模块占这个槽由用户定
                        attentionCard.staggered(2)
                        if shown(.linkSense) { linkSenseCard.staggered(2) }
                        // 246 凭证选择胶囊: 该锁有多条可用 PIN 且还没签发 ekey 时才出现 (有 ekey 时开锁根本不用 PIN, 给了是假选择)
                        if let kc = app.current, kc.ekey.isEmpty, kc.pins.count > 1 {
                            pinPickCapsule(kc).staggered(2)
                        }
                        unlockDial.staggered(3)
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel("开锁圆盘组")   // 868 开锁圆盘组
                        moduleSlot(devOrder[1], delay: 4)   // 904
                        moduleSlot(devOrder[2], delay: 5)   // 904
                        if shown(.nightCheck) { nightCheckRow.staggered(6) }
                        if shown(.familyCare) { familyCareRows.staggered(6) }
                        if shown(.privacyNote) { privacyFootnote.staggered(6) }
                        // 904 模块排序入口: 做成显式文字按钮 —— 原句点名的"长按设备页空白进编辑态"会与
                        // 60/873 那族手势链冲突 (设备页是 ScrollView, 空白长按同时是滚动/下拉刷新的一部分),
                        // 排序落成上/下移按钮, 不改整页手势。
                        Button { showModuleOrder = true } label: {
                            Label("模块排序与显隐", systemImage: "arrow.up.arrow.down")   // 904 模块排序
                                .font(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                                .frame(maxWidth: .infinity, minHeight: DS.Hit.min)
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
                .padding(.vertical, DS.Space.m)
            }
            // 537 下拉重扫: 只扫不连。127 静默模式关的是"自动"回连/预握手/自动开锁,
            // 用户主动下拉属于手动动作 (与"手动圆盘照常"同一条口径), 所以这里不看 DiagFlags.silent。
            .refreshable { await rescanPull() }
            .dsScreenBackground()
            // 54 摇一摇唤出: 迷你开锁面板浮在设备页顶部。挂在 ScrollView 上而不是卡片里 ——
            // 浮层不随内容滚动, 摇出来就必须一直在眼前。面板态只属于设备页, 换页由 AppState 收掉。
            .overlay(alignment: .top) {
                if app.shakePanel, app.current != nil {
                    shakeMiniPanel
                        .padding(.horizontal, DS.Space.m)
                        .padding(.top, DS.Space.s)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
            // 826 聚光教练标: 首进设备 Tab 用半透明遮罩圈住一个焦点单点讲解, 点任意处推进下一焦点。
            // 只做一次 (kf_coach_done); 遮罩自己吃掉点击, 所以它同时也是"推进/结束"的手势面。
            .overlay {
                if let step = coachStep { coachOverlay(step) }
            }
            .task {
                if !DB.store.getBool("kf_coach_done"), app.current != nil { coachStep = 0 }
            }
            .animation(reduceMotion ? nil : DS.Motion.standard, value: app.shakePanel)
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
            }
            .sheet(isPresented: $showAdd) { AddDeviceView() }
            .sheet(isPresented: $showModuleOrder) { moduleOrderSheet }
            // 包3: 全部锁总览与对比 (768/776/778/779/784/787/773)
            .sheet(isPresented: $showOverview) { LockOverviewView() }
            // 104/107/766: 排序与分组改的是"这一屏看得见哪些锁、按什么次序", 关页时立刻重算,
            // 不能等下次进页 — 用户拖完就看, 拖不动的那种反馈最伤信任。
            .sheet(isPresented: $showManage, onDismiss: {
                syncPageOrder()
                alarmMacs = LockStats.recentAlarmMacs(LockStats.usage())
                recomputeMerged()
            }) { DeviceManageView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showTileEdit) { QuickTileEditorSheet() }   // 905 长按快捷格进编辑
            // 250 二次开锁应用锁闸
            .sheet(isPresented: $app.showGate) { UnlockGateView() }
            // 81 全屏专注开锁
            .fullScreenCover(isPresented: $showFocus) { FocusUnlockView() }
            // 91 回连静默小点: 回连成功不打扰, 胶囊旁亮一枚小点 3 秒
            .onChange(of: lockSvc.connectedMAC) { _, new in
                guard new == app.currentMac, !new.isEmpty else { return }
                reconnectDot = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    reconnectDot = false
                }
            }
            // 包3: 换锁后同步翻页索引 + 清理与锁绑定的过程态
            .onChange(of: app.currentMac) { _, new in
                flipped = false
                if confirmMac != new { confirmMac = nil }   // 菜单/联动切锁不设防, 只有横滑才设
                if let i = pageOrder.firstIndex(of: new) {
                    if i != pageIndex { pageIndex = i }
                } else {
                    // 当前锁不在翻页序列 (如沉睡锁从胶囊选中) → 重建序列并落位
                    syncPageOrder()
                    if let i = pageOrder.firstIndex(of: new) { pageIndex = i }
                }
            }
            .onChange(of: app.devices.count) { _ in
                syncPageOrder()
                // 绑定/删除之后合并流与告警点位都会留下上一批锁的行: 立刻按新台账重算,
                // 不等用户手动刷新 (否则解绑那把锁的"最近开门"会继续挂在列表里)。
                alarmMacs = LockStats.recentAlarmMacs(LockStats.usage())
                recomputeMerged()
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
                recentAllLocks = DB.store.getBool("kf_recent_all")   // 765 上次选的范围 (与 566 同一口径: 筛选跨会话保留)
                syncPageOrder()
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

    /// 537 下拉重扫: 三种结果说实话 —— 蓝牙没开 / 扫到了 (给信号数值) / 超时没扫到 (不假装刷新成功)。
    /// 走的是现有 `LinkSense.scan` (startScan/stopScan 成对, 不连接、不下发任何指令)。
    private func rescanPull() async {
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

    private func refresh(manual: Bool = false) async {
        guard !refreshing else { return }
        refreshing = true
        // 127 静默档的边界按"谁起的这个动作"算: 按钮与下拉是用户主动 (manual: true),
        // 进页 `.task` 与切锁后的自动刷新不算 (口径见 AppState.refreshStatusQuietly 与 :71 那条既有注释)。
        await app.refreshStatusQuietly(manual: manual)
        refreshing = false
        duePins = BackupStudio.duePins()   // 437: 进页与手动刷新各算一次, 不在 body 里列目录
        // 764 图标行的红点 + 765 跨锁合并流: 同一批"要遍历各锁日志"的聚合放在一起算一次。
        // 都走本地缓存, 不主动连锁 —— 下拉刷新已经把 03 快照发出去了, 这里不再叠一轮 IO。
        let us = LockStats.usage()
        alarmMacs = LockStats.recentAlarmMacs(us)
        recomputeMerged()
        // 112: 迁移验证全部通过后清掉向导旗标 (下次恢复备份会重新立起)
        let flag = DB.store.getString("kf_migrate_pending")
        if !flag.isEmpty, !app.devices.isEmpty,
           app.devices.allSatisfy({ DB.store.getBool("kf_migok_" + $0.mac) }) {
            DB.store.remove("kf_migrate_pending")
        }
    }

    // ---------- 设备切换 (包3: 102 胶囊 + 101/763 横滑翻页 + 114 低电置顶 + 292 沉睡跳过 + 766 手工顺序 + 767 按组) ----------
    /// 三档顺序, 互斥而不是叠加 (叠加就会出现"我明明排好了它又自己跑掉"):
    ///   1. 1041 电量升序 (胶囊菜单里的明确开关) → 低电置顶 + 电量升序;
    ///   2. 766 手工顺序 (设备管理里拖过/置顶过) → 完全照用户排的次序, 低电只标橙点不再挪位置 (764);
    ///   3. 都没设 → 271 默认锁首位 + 114 低电置顶 + 绑定先后。
    /// 沉睡锁 (292) 与隐藏锁 (108) 在三档里都退出横滑序列, 只从胶囊可达 — 判据与入口各自独立。
    private func syncPageOrder() {
        // 组名可能被改名或整个清空 (在设备管理里), 残留的过滤值会把翻页序列压成只剩当前锁一页。
        // 这一句的作用域只在"重算序列"时: 组没了就回到"全部", 而不是让用户面对一排空的胶囊。
        if !groupFilter.isEmpty, !groupNameList.contains(groupFilter) { groupFilter = "" }
        let byBatt = DB.store.getBool("kf_sort_batt")   // 1041 电量升序开关
        let manual = LockArchive.hasManualOrder         // 766
        let def = LockArchive.defaultMac
        let base = manual ? LockArchive.orderedDevices(app.devices) : app.devices
        let seq: [Keychain]
        if manual, !byBatt {
            // 手工顺序**不再比较**: orderedDevices 返回的就是用户排好的全序, 再排一次等于把它撤销。
            seq = base
        } else {
            seq = base.sorted { a, b in
                if byBatt {
                    let la = isLow(a), lb = isLow(b)
                    if la != lb { return la }
                    let pa = batteryPct(for: a), pb = batteryPct(for: b)
                    if pa != pb { return pa < pb }
                } else {
                    if a.mac == def { return true }
                    if b.mac == def { return false }
                    let la = isLow(a), lb = isLow(b)
                    if la != lb { return la }   // 114 低电置顶
                }
                return a.pairedAt < b.pairedAt
            }
        }
        pageOrder = seq.filter { inGroup($0) && !LockArchive.isSleeping($0.mac) && !LockArchive.isHidden($0.mac) }
            .map { $0.mac }
        // 当前锁若已沉睡/被隐藏/不在所选组, 保留一页让它可见 (从胶囊或图标行选中的落点)
        if let cur = app.current, !pageOrder.contains(cur.mac) {
            pageOrder.append(cur.mac)
        }
        if let cur = app.current, let i = pageOrder.firstIndex(of: cur.mac) { pageIndex = i }
    }
    /// 767 组过滤: "" = 全部; "未分组" = 档案里组名为空的那些。
    /// 图标行与翻页共用这一条判据, 免得出现"chip 选了家用, 图标行还亮着仓库"的两套答案。
    private func inGroup(_ kc: Keychain) -> Bool {
        if groupFilter.isEmpty { return true }
        let g = LockArchive.group(kc.mac)
        return groupFilter == LockArchive.ungroupedLabel ? g.isEmpty : g == groupFilter
    }
    /// 图标行的锁集: 组过滤后**全部**可见 (含沉睡/隐藏) — 它是"看一眼有没有事"的面,
    /// 把沉睡锁藏起来正好会让最该被看见的那把消失。
    /// 229 左手模式：工具条两侧对调、快捷格顺序镜像（常用那格落到拇指侧）。
    /// 开关只有 `AXPrefs.lefty` 一个出处 (AccessibilityKit.swift:214)，此前它被设置页读写、
    /// 全仓没有任何消费者 —— "镜像"是两个只改自己标签的按钮之一，这两行把它接上。
    private var barSide: ToolbarItemPlacement {
        AXPrefs.lefty ? .navigationBarLeading : .navigationBarTrailing
    }
    private var tiles: [QuickAction] {
        let o = QuickPool.ordered()
        return AXPrefs.lefty ? o.reversed() : o
    }

    private var rowLocks: [Keychain] {
        LockArchive.orderedDevices(app.devices).filter { inGroup($0) }
    }
    /// 765 合并流跟着组过滤走: 选了"仓库"却在流里看到家门口的记录, 那不是"跨锁", 那是串台。
    private func recomputeMerged() {
        mergedRecent = RecordSearch.mergedRecentOpens(macs: rowLocks.map { $0.mac }, count: 10)
        // 790 最近活跃头像圈借同一刷新时机重算 —— Hero 卡每帧现算 = 成员数 × 全量日志各解一遍,
        // 那是这个文件里最贵的操作; 跟着 onAppear/换锁/换组走足够 (活跃度本来就是"约"级信息)。
        activeTops = DB.members()
            .filter { !MemberHub.ext($0.id).archived }
            .map { ($0, MemberHub.activity($0.id).last) }
            .filter { !$0.1.isEmpty }
            .sorted { $0.1 > $1.1 }
            .prefix(3)
            .map(\.0)
    }
    private var groupNameList: [String] {
        LockArchive.grouped(LockArchive.orderedDevices(app.devices)).map { $0.name }
    }
    @ViewBuilder
    private var groupChips: some View {
        let names = groupNameList
        if names.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s) {
                    chip("", "全部")   // 767 全部
                    ForEach(names, id: \.self) { n in chip(n, n) }
                }
                .padding(.horizontal, DS.Space.gutter)
            }
            .accessibilityLabel("按组切换门锁, 当前\(groupFilter.isEmpty ? "全部" : groupFilter)")
        }
    }
    private func chip(_ name: String, _ label: String) -> some View {
        let on = groupFilter == name
        return Button {
            groupFilter = name
            syncPageOrder()
            recomputeMerged()
            DS.Haptics.tick.impactOccurred()
        } label: {
            Text(label)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, DS.Space.l)
                .padding(.vertical, 12)
                .background(on ? DS.Palette.accent : DS.Palette.surfaceAlt, in: Capsule())
                .overlay(Capsule().strokeBorder(DS.Palette.hairline, lineWidth: 0.5))
                .foregroundStyle(on ? DS.Palette.onAccent : DS.Palette.text)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    // ---------- 764 多锁状态图标行 (家庭 App 房间行) ----------
    // 点图标 = 切当前锁; 当前锁加一圈主题色描边 (原句"靛蓝描边"= 品牌主色, 六套主题下都跟着变)。
    private var statusIconRow: some View {
        let locks = rowLocks
        return VStack(alignment: .leading, spacing: DS.Space.xs) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s) {
                    ForEach(locks) { kc in statusTile(kc) }
                }
                .padding(.horizontal, DS.Space.gutter)
            }
            Text("红点=近 30 天日志里有告警 · 橙点=低电 · 绿点=本机已连接 · 空心圈=没读到读数 (不代表门锁正常)")
                .font(.caption2)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DS.Space.gutter)
        }
    }
    private func statusTile(_ kc: Keychain) -> some View {
        let isCur = kc.mac == app.currentMac
        let m = LockArchive.meta(kc.mac)
        let name = LockArchive.displayName(kc)
        let sleeping = LockArchive.isSleeping(kc.mac)
        let dot: Dot = alarmMacs.contains(kc.mac) ? .alarm
            : (isLow(kc) ? .low : (lockSvc.connectedMAC == kc.mac ? .linked : .none))
        return Button {
            if kc.mac != app.currentMac { app.select(kc.mac) }
        } label: {
            VStack(spacing: DS.Space.xxs) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: LockArchive.symbolName(m))
                        .font(.system(size: DS.Icon.md, weight: .medium))
                        .foregroundStyle(LockArchive.swatchColor(m.colorKey))
                        .frame(width: 46, height: 46)
                        .background(DS.Palette.surfaceAlt, in: Circle())
                    // `.none` 画空心圈: 实心灰点会被读成"查过了, 它没事", 而那正是没查过的样子
                    if dot == .none {
                        Circle()
                            .strokeBorder(DS.Palette.hairlineStrong, lineWidth: 1.5)
                            .frame(width: 11, height: 11)
                            .padding(2)
                    } else {
                        Circle().fill(dot.color)
                            .frame(width: 11, height: 11)
                            .overlay(Circle().strokeBorder(DS.Palette.surface, lineWidth: 1.5))
                            .padding(2)
                    }
                }
                .overlay {
                    if isCur { Circle().strokeBorder(DS.Palette.accent, lineWidth: 2.5) }
                }
                // 44pt 是命中区, 文字块另给宽度: 名字长就截断, 完整名走 a11y 标签
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(isCur ? DS.Palette.text : DS.Palette.textSub)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 56)
            }
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("\(name), \(dot.word)\(sleeping ? ", 沉睡" : "")\(isCur ? ", 当前锁" : ""), 点按切换")
        .accessibilityAddTraits(isCur ? [.isSelected] : [])
    }
    /// 764 的四种状态: 优先级 告警 > 低电 > 已连接 > 无读数。
    /// `.none` 在图标上是**空心圈**而不是灰点 —— 灰点会被读成"我查过了, 它没事", 而那正是没查过的样子。
    private enum Dot {
        case alarm, low, linked, none
        var color: Color {
            switch self {
            case .alarm: return DS.Palette.danger
            case .low: return DS.Palette.warn
            case .linked: return DS.Palette.ok
            case .none: return DS.Palette.hairlineStrong
            }
        }
        var word: String {
            switch self {
            case .alarm: return "近 30 天有告警"
            case .low: return "低电量"
            case .linked: return "已连接"
            case .none: return "没读到读数"
            }
        }
    }
    private var pagedLocks: [Keychain] {
        let byMac = Dictionary(app.devices.map { ($0.mac, $0) }, uniquingKeysWith: { a, _ in a })
        return pageOrder.compactMap { byMac[$0] }
    }
    private var capsuleSwitcher: some View {
        HStack(spacing: DS.Space.s) {
            capsuleMenu
            Spacer(minLength: 0)
            // 763 页点: 当前页高亮, 低电锁橙色描边 (114), 点击直达
            HStack(spacing: DS.Space.xs) {
                ForEach(Array(pagedLocks.enumerated()), id: \.offset) { i, kc in
                    Button { withAnimation(DS.Motion.soft) { pageIndex = i } } label: {
                        Capsule()
                            .fill(i == pageIndex ? DS.Palette.accent : DS.Palette.hairline)
                            .frame(width: i == pageIndex ? 18 : 7, height: 7)
                            .overlay {
                                if isLow(kc), i != pageIndex {
                                    Capsule().strokeBorder(DS.Palette.warn, lineWidth: 1.5)
                                }
                            }
                            // 视觉小点 + 44pt 命中区分离 (触达纪律)
                            .frame(width: DS.Hit.min, height: DS.Hit.min)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel("第 \(i + 1) 页 \(LockArchive.displayName(kc))\(isLow(kc) ? ", 低电量" : "")")
                }
            }
            .accessibilityElement(children: .contain)
        }
        .padding(.horizontal, DS.Space.gutter)
    }
    private var capsuleMenu: some View {
        Menu {
            // 767 胶囊里也按组分区: 十几把锁时"一长条"和"按空间分组"是两种找法, 这里跟着图标行的过滤走。
            // 只有真出现 ≥2 组才分区 —— 单组时套一层组名标题纯属噪音。
            let gs = LockArchive.grouped(pagedLocks)
            if gs.count > 1 {
                ForEach(gs) { g in
                    Section(g.name) {
                        ForEach(g.locks) { kc in lockMenuItem(kc) }
                    }
                }
            } else {
                Section("门锁") {
                    ForEach(pagedLocks) { kc in lockMenuItem(kc) }
                }
            }
            let sleepers = app.devices.filter { LockArchive.isSleeping($0.mac) }
            if !sleepers.isEmpty {
                Section("沉睡 (超 30 天未连接)") {
                    ForEach(sleepers) { kc in
                        Button {
                            app.select(kc.mac)
                        } label: {
                            HStack(spacing: DS.Space.s) {
                                Circle().fill(LockArchive.swatchColor(LockArchive.meta(kc.mac).colorKey))
                                    .frame(width: 8, height: 8)
                                Text(LockArchive.displayName(kc))
                                Image(systemName: "moon.zzz.fill").foregroundStyle(DS.Palette.textSub)
                            }
                        }
                    }
                }
            }
            let hiddenLocks = app.devices.filter { LockArchive.isHidden($0.mac) }
            if !hiddenLocks.isEmpty {
                // 108: 隐藏的锁**不会消失**，只是退出横滑序列。这里就是它的可达面与恢复入口
                // (恢复开关在"锁档案"里，与隐藏动作同一个地方，免得两个方向各找一个页面)。
                Section("已隐藏 (\(hiddenLocks.count))") {
                    ForEach(hiddenLocks) { kc in
                        Button {
                            app.select(kc.mac)
                        } label: {
                            HStack(spacing: DS.Space.s) {
                                Circle().fill(LockArchive.swatchColor(LockArchive.meta(kc.mac).colorKey))
                                    .frame(width: 8, height: 8)
                                Text(LockArchive.displayName(kc))
                                Image(systemName: "eye.slash").foregroundStyle(DS.Palette.textSub)
                            }
                        }
                    }
                }
            }
            Divider()
            Button {
                DB.store.set("kf_sort_batt", !DB.store.getBool("kf_sort_batt"))
                DS.Haptics.tick.impactOccurred()
                syncPageOrder()
            } label: {
                // 关掉电量档之后回到哪一档, 取决于有没有手工顺序 (766) —— 文案跟着实际结果走,
                // 不能一直写"恢复绑定先后": 排过序的用户按下去看到的是自己的顺序回来了, 那句就成了假话。
                Label(DB.store.getBool("kf_sort_batt")
                      ? (LockArchive.hasManualOrder ? "恢复手工排序" : "恢复绑定先后排序")   // 766 恢复手工排序
                      : "按电量升序 (先照顾最弱)",
                      systemImage: "arrow.up.arrow.down")
            }
            Divider()
            Button { showOverview = true } label: {
                Label("全部锁总览与对比", systemImage: "chart.bar.horizontal")
            }
            Button { showManage = true } label: {
                Label("设备管理 (排序/分组/批量)", systemImage: "rectangle.3.group")
            }
        } label: {
            HStack(spacing: DS.Space.xs) {
                Circle().fill(LockArchive.swatchColor(LockArchive.meta(app.currentMac).colorKey))
                    .frame(width: 8, height: 8)
                Text(app.displayName)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(DS.Palette.text)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: DS.Icon.xs, weight: .semibold))
                    .foregroundStyle(DS.Palette.textSub)
            }
            .padding(.horizontal, DS.Space.m)
            .padding(.vertical, DS.Space.xs + 2)
            // 2026-10-14 材质统一: 换锁 chip 上玻璃 (装饰性 hairline 描边随之去掉, 玻璃自带边缘高光)
            .axGlassCapsule()
            // 视觉紧凑胶囊 + 44pt 命中区分离: 胶囊本身不必撑高
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("切换门锁, 当前 \(app.displayName)")
    }
    private func lockMenuItem(_ kc: Keychain) -> some View {
        Button {
            if kc.mac != app.currentMac { app.select(kc.mac) }
        } label: {
            HStack(spacing: DS.Space.s) {
                Circle().fill(LockArchive.swatchColor(LockArchive.meta(kc.mac).colorKey))
                    .frame(width: 8, height: 8)
                Text(LockArchive.displayName(kc))
                if isLow(kc) { Image(systemName: "battery.25percent").foregroundStyle(DS.Palette.warn) }
                if LockArchive.isSleeping(kc.mac) { Image(systemName: "moon.zzz.fill").foregroundStyle(DS.Palette.textSub) }
            }
        }
        // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 没有 minHeight (< 44)。
        // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
        .frame(minHeight: DS.Hit.min)
        .contentShape(Rectangle())
    }
    // 101/763/771/786: Hero 卡横滑翻页 — 圆盘与状态文本随卡片平行滑动交接 (TabView 原生平移)。
    // 786 "只有 Hero 区响应翻锁": 手势就挂在这个 TabView 上, 页面别处 (圆盘纵向滑、下拉刷新、Tab 栏) 各管各的轴,
    // 所以不需要任何 gesture 仲裁 —— 两套手势抢同一条轴的写法才是这里要避免的。
    private var heroPager: some View {
        TabView(selection: $pageIndex) {
            ForEach(Array(pagedLocks.enumerated()), id: \.offset) { i, kc in
                statusCard(for: kc)
                    .padding(.horizontal, DS.Space.xs)
                    .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // 23 HeroCard 滚动视差 (Halide): 身份卡随页面上滚以约三分之一倍速跟手, 制造"卡片浮在内容上"的层次。
        // 只动位移; 翻面 (78)/低电触感 (113/120)/reduceMotion 退化全部不动。
        .scrollTransition(.interactive, axis: .vertical) { content, phase in
            content.offset(y: reduceMotion ? 0 : phase.value * 36)
        }
        .animation(DS.Motion.soft, value: pageIndex)
        // 267 换锁二次确认: 横滑落点换锁后, 首次点圆盘只弹锁名胶囊, 再点才执行
        .onChange(of: pageIndex) { _, i in
            guard pagedLocks.indices.contains(i) else { return }
            let kc = pagedLocks[i]
            if kc.mac != app.currentMac {
                confirmMac = kc.mac
                app.select(kc.mac)
            }
        }
        // 271 上滑设默认: 横滑翻页时带明显上挑分量 → 该锁固定为冷启动默认并置顶。
        // 门槛 |w|>60 ∧ h<-60: 纯横翻 (h≈0) 与纵向滚动 (|w| 小) 都不触发, 只认斜上挑。
        .simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { g in
                guard g.translation.height < -60, abs(g.translation.width) > 60,
                      let kc = app.current else { return }
                LockArchive.setDefaultMac(kc.mac)
                DS.Haptics.trigger.impactOccurred()
                syncPageOrder()
                app.showToast("「\(LockArchive.displayName(kc))」已设为启动默认锁")
            })
    }

    // ---------- 状态卡: 身份 + 连接 + 三个关键读数 ----------
    // 全页唯一的品牌渐变面 (HeroCard): 门锁的"身份卡"配得上最高视觉权重,
    // 也让页面其余部分可以安心保持安静。
    // 78 卡片翻面: 开锁成功翻到背面看本次开门摘要, 点按翻回 (reduceMotion 退化为淡入淡出)。
    private func statusCard(for kc: Keychain) -> some View {
        let isCurrent = kc.mac == app.currentMac
        return ZStack {
            heroCard(for: kc, isCurrent: isCurrent)
                .opacity(flipped ? 0 : 1)
                .accessibilityHidden(flipped)
            heroBack
                .opacity(flipped ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .accessibilityHidden(!flipped)
        }
        .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        // 包4: 低电分级触感 — 进入 ≤20% 一次 warning, 跌入 ≤10% (告急) 一次 error
        .sensoryFeedback(trigger: lowBucket(kc)) { old, new in
            guard isCurrent else { return nil }
            if new == "sev", old != "sev" { return .error }
            if new == "low", old != "low" { return .warning }
            return nil
        }
        .onTapGesture {
            guard isCurrent else { return }   // 非当前页是静态预览, 翻面只在当前锁生效
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : DS.Motion.standard) { flipped.toggle() }
        }
        .onChange(of: app.unlockState) { _, s in
            guard isCurrent else { return }
            guard case .success = s else { return }
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : DS.Motion.standard) { flipped = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(6))
                if flipped { withAnimation(DS.Motion.soft) { flipped = false } }
            }
        }
    }
    // 243 断连灰化: 连接断开时整卡去饱和, 恢复即回彩
    // 包3: 参数化到任意锁 — 当前页吃实时状态, 其余页读各锁快照 (101/763 横滑预览)
    private func heroCard(for kc: Keychain, isCurrent: Bool) -> some View {
        let connected = isCurrent && bleOn
        // 113 五档电量 / 120: 低电降级档 (≤20%) 关流光边并压亮度, 动效令牌同步降 calm
        let tier = BatteryCare.tier(batteryPct(for: kc))
        return HeroCard(flair: isCurrent && Milestones.heroFlairActive && !tier.severe) {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                HStack(alignment: .top, spacing: DS.Space.m) {
                    HStack(spacing: DS.Space.s) {
                        // 105 锁符号: 档案里选的 SF Symbol 同步到 Hero 卡
                        Image(systemName: LockArchive.symbolName(LockArchive.meta(kc.mac)))
                            .font(.system(size: DS.Icon.md, weight: .medium))
                            .foregroundStyle(LockArchive.swatchColor(LockArchive.meta(kc.mac).colorKey))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text(LockArchive.displayName(kc))
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(DS.heroFg)
                                .lineLimit(1)
                            // 774 场所副标题: 档案里填了场所就替代型号行
                            Text(LockArchive.subtitle(kc))
                                .font(.footnote)
                                .foregroundStyle(DS.heroFg.opacity(0.9))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            // 1000 晚归欢迎语 / 1001 节气问候 (只属于当前锁的活页面)
                            if isCurrent, let m = heroMomentText {
                                Text(m)
                                    .font(.footnote)
                                    .foregroundStyle(DS.heroFg.opacity(0.9))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: DS.Space.xs) {
                        if isCurrent {
                            // 包2: 三态语义胶囊 (64) + 拟人文案 (68) + 冷热标识 (98) + 63 信号格 + 67 耗时
                            LinkPill(state: linkState(for: kc), connectMs: sense.connectMs, rssi: sense.lastRssi,
                                     source: sense.connectSource == "即连" ? "即连" : "已预热")
                            RSSIBars(level: LinkSense.rssiLevel(sense.lastRssi))
                                .opacity(isCurrent ? 1 : 0)
                                .accessibilityHidden(!isCurrent)
                                // 63 点一格弹出 dBm 原始数值: 三格表看不出"1 格强"与"2 格弱"的界
                                .onTapGesture { if isCurrent { showRssi.toggle() } }
                                .overlay(alignment: .top) {
                                    if isCurrent && showRssi {
                                        Text("\(sense.lastRssi) dBm")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(DS.heroFg)
                                            .padding(.horizontal, DS.Space.xs)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(.black.opacity(0.55)))
                                            .offset(y: -18)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .accessibilityLabel(isCurrent ? "信号 \(sense.lastRssi) dBm, 轻点显示数值" : "信号")   // 63 信号
                            ConnectMsBadge(ms: sense.connectMs)
                            // 268 状态变化历史: 长按胶囊弹出最近 5 次三态切换时间列表
                            .contextMenu {
                                Menu("最近状态变化") {   // 268 最近状态变化
                                    ForEach(Array(LinkSense.history().enumerated()), id: \.offset) { _, h in
                                        Text(h.at + " " + h.to)
                                    }
                                }
                                // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 命中高仅约 16.5pt (< 44)。
                                // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
                                .frame(minHeight: DS.Hit.min)
                                .contentShape(Rectangle())
                            }
                            // 91 回连静默小点
                            if reconnectDot {
                                Circle()
                                    .frame(width: 8, height: 8)
                                    .foregroundStyle(DS.Palette.ok)
                                    .overlay(Circle().strokeBorder(DS.heroFg.opacity(0.7), lineWidth: 1))
                                    .transition(.opacity)
                                    .accessibilityHidden(true)
                            }
                            // 81 专注开锁入口 (原案"Hero 卡下拉"与纵向滚动手势冲突, 收敛为明确入口)
                            focusButton
                        } else {
                            HeroPill(text: "滑动到这页即连接", systemImage: "arrow.left.arrow.right",
                                     tint: DS.heroFg.opacity(0.75))
                        }
                    }
                }
                // 859 AX 档降级布局: 字号 >=1.5 (AXFlags.axStackLayout) 时三个指标改纵向堆叠 ——
                // 特大字号下横排会被压成三行小字/截断; 圆盘缩 128pt 那半在 UnlockDial:321。
                // 用 AnyLayout 而不是复制两份 HeroStat: 指标与显隐逻辑只有一个出处。
                let statsLayout = AXFlags.axStackLayout
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s))
                    : AnyLayout(HStackLayout(spacing: DS.Space.s))
                statsLayout {
                    // 电量是一级读数(它决定你还能不能开锁), 固件/锁钟是三级参考信息 —
                    // 三者同级会让人看不出重点
                    HeroStat(systemImage: battTier(for: kc).icon,
                             label: "电量",
                             value: batteryText(for: kc),
                             emphasized: true,
                             tint: battTint(for: kc))
                    // 909 指标位显隐: **电量不参与隐藏** —— 它决定"还能不能开锁"，
                    // 一个能把自己藏掉的读数就不是读数。固件/锁钟是参考信息，允许收起来腾位置。
                    if DS.HeroStats.shows("firmware") {
                        HeroStat(systemImage: "memorychip",
                                 label: "固件",
                                 value: firmwareText(for: kc),
                                 emphasized: false)
                    }
                    if DS.HeroStats.shows("lockclock") {
                        HeroStat(systemImage: "clock",
                                 label: "锁钟",
                                 value: lockClockText(for: kc),
                                 emphasized: false)
                    }
                }
                // 982 开门里程碑: Hero 卡角标小旗 (全局计数, 只在当前页展示)
                if isCurrent, Milestones.unlockTotal >= 100 {
                    HStack(spacing: DS.Space.s) {
                        HeroPill(text: "已守护 \(Milestones.unlockTotal) 次", systemImage: "flag.fill")
                        Spacer(minLength: 0)
                    }
                }
                // 包8/507 备份状态角标: 两态 (今日已备份 / 多日未备份), 点按跳设置-备份
                if isCurrent {
                    let bs = BackupStudio.badgeState
                    Button { showSettings = true } label: {
                        HStack(spacing: DS.Space.xs) {
                            Circle().fill(bs == .fresh ? DS.Palette.ok : DS.heroFg)
                                .frame(width: 6, height: 6)
                            Text(bs == .fresh ? "今日已备份" : "多日未备份")
                                .font(.caption2)
                                .foregroundStyle(DS.heroFg.opacity(0.92))
                        }
                        .padding(.horizontal, DS.Space.xs)
                        .padding(.vertical, DS.Space.xxs)
                        .background(DS.heroFg.opacity(0.14), in: Capsule())
                    }
                    .frame(minHeight: DS.Hit.min)
                    .accessibilityLabel("备份状态角标, 打开备份设置")   // 507 备份状态角标
                }
                // 258 首连验证标记: 添加后完成一次开锁前, Hero 卡上挂着待验证提示
                if !LockArchive.isVerified(kc.mac) {
                    HStack(spacing: DS.Space.xs) {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: DS.Icon.sm, weight: .semibold))
                            .foregroundStyle(DS.heroFg.opacity(0.9))
                            .accessibilityHidden(true)
                        Text("链路待验证 · 成功开一次锁即打标")
                            .font(.footnote)
                            .foregroundStyle(DS.heroFg.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                // 1004 喂电提醒: 电量 ≤20% 时图标呼吸 + 一句叮嘱
                if isLow(kc) {
                    HStack(spacing: DS.Space.xs) {
                        Image(systemName: "battery.25percent")
                            .font(.system(size: DS.Icon.sm, weight: .semibold))
                            .foregroundStyle(DS.Palette.warn)
                            .modifier(BreathingGlyph())
                            .accessibilityHidden(true)
                        Text("该喂电了, 别让它饿着")
                            .font(.footnote)
                            .foregroundStyle(DS.heroFg.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                // 116 换电图文引导: 低电降级档 (≤20%) 时 Hero 卡直接给出入口
                if isCurrent, tier.severe {
                    NavigationLink { BatterySwapGuideView() } label: {
                        HStack(spacing: DS.Space.xs) {
                            Image(systemName: "arrow.right.circle")
                                .font(.system(size: DS.Icon.sm, weight: .semibold))
                                .foregroundStyle(DS.heroFg.opacity(0.9))
                                .accessibilityHidden(true)
                            Text("打开换电图文指引")
                                .font(.footnote)
                                .foregroundStyle(DS.heroFg)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel("电量告急, 打开换电图文指引")
                }
                // 121 低温季静默提示 (11–3 月, 纯本地日期规则)
                if isCurrent, !isLow(kc), BatteryCare.isColdSeason {
                    HStack(spacing: DS.Space.xs) {
                        Image(systemName: "thermometer.snowflake")
                            .font(.system(size: DS.Icon.sm, weight: .semibold))
                            .foregroundStyle(DS.heroFg.opacity(0.9))
                            .accessibilityHidden(true)
                        Text("低温季: 电池续航会缩短, 多留意电量")
                            .font(.footnote)
                            .foregroundStyle(DS.heroFg.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                // 790 最近活跃成员头像圈: 卡角叠放最近活跃 3 位, 点开列成员名, 选谁直接查谁的记录。
                if isCurrent {
                    HStack(spacing: DS.Space.s) {
                        Spacer(minLength: 0)
                        activeMembersBadge
                    }
                }
            }
        }
        .saturation(connected ? 1 : 0.55)
        .brightness(tier.severe ? -0.06 : 0)   // 120 低电视觉降级
        // 847 Hero 卡合并播报: 单元素合读 连接态+电量 (盲文简写 856)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AXTerms.lock + ": " + AXTerms.br((connected ? AXTerms.connected : AXTerms.notConnected) + ", " + AXTerms.battery + " " + batteryText(for: kc)))
    }

    /// 790 头像圈: 叠放的 3 枚首字头像 (数据来自 activeTops, 刷新时机与合并流同一条);
    /// 点开列出成员名, 选择即落记录页按该成员过滤 —— 复用 559 的 openMemberRecords (同一落点两处入口)。
    @ViewBuilder
    private var activeMembersBadge: some View {
        if !activeTops.isEmpty {
            Menu {
                ForEach(activeTops) { m in
                    Button { openMemberRecords(m.id) } label: {
                        Label(MemberHub.display(m), systemImage: "person.crop.circle")
                    }
                }
            } label: {
                HStack(spacing: DS.Space.xxs) {
                    ForEach(activeTops) { m in
                        MemberAvatar(member: m, size: 26, tint: DS.heroFg)
                            .overlay(Circle().strokeBorder(DS.heroFg.opacity(0.6), lineWidth: 1.5))
                    }
                }
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("最近活跃成员: 点开按成员查记录")   // 790 最近活跃成员
        }
    }

    // 78 翻面 (背面): 82 对勾弹出 + 本次开门摘要
    private var heroBack: some View {
        HeroCard(flair: Milestones.heroFlairActive) {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: DS.Icon.sm, weight: .semibold))
                        .foregroundStyle(DS.heroFg)      // 863: 反转下 hero 会变浅, 写死白=白压白
                        // 82: 每次翻面弹性弹出一次
                        .symbolEffect(.bounce, value: flipped)
                    Text("已开锁")
                        .font(.headline)
                        .foregroundStyle(DS.heroFg)
                        .lineLimit(1)
                }
                Text(backSummary)
                    .font(.footnote)
                    .foregroundStyle(DS.heroFg.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                Text("轻点翻回正面")
                    .font(.caption2)
                    .foregroundStyle(DS.heroFg.opacity(0.7))
            }
        }
        .saturation(bleOn ? 1 : 0.55)
    }
    private var backSummary: String {
        let last = app.recentRecords(count: 1).first
        let when = (last?.time.count ?? 0) >= 16 ? String(last!.time.dropFirst(5).prefix(11)) : "本次"
        return "\(when) · 已守护 \(Milestones.unlockTotal) 次"
    }

    // ---------- 需要用户处理的异常: 只在真有问题时出现, 不占常驻版面 ----------
    @ViewBuilder
    private var attentionCard: some View {
        let notes: [(String, String, ToneColor)] = attentionItems
        if !notes.isEmpty {
            Card(tint: .warn) {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, n in
                        HStack(alignment: .top, spacing: DS.Space.s) {
                            Image(systemName: n.1)
                                .font(.system(size: DS.Icon.sm, weight: .semibold))
                                .foregroundStyle(n.2.color)
                                .accessibilityHidden(true)
                            Text(n.0)
                                .font(.footnote)
                                .foregroundStyle(DS.Palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }
    private var attentionItems: [(String, String, ToneColor)] {
        var out: [(String, String, ToneColor)] = []
        if (app.status?.sKeyStatus ?? app.snapshot?.sKeyStatus ?? 0) != 0 {
            out.append(("密钥尚未绑定，该门锁可能还没完成配网", "exclamationmark.triangle.fill", .warn))
        }
        if staleSync {
            out.append(("超过 30 天未校时，临时密码可能失效，请到快捷操作同步时间", "clock.badge.exclamationmark.fill", .warn))
        }
        // 287 低电阈值横幅 (阈值在 设置-维护提醒 可调, 默认 15%)
        if let kc = app.current {
            let p = batteryPct(for: kc)
            if p >= 0, p <= CareSchedule.battThreshold {
                out.append(("当前电量 \(p)%, 已低于提醒阈值 (\(CareSchedule.battThreshold)%) — 建议备好电池", "battery.25percent", .warn))
            }
        }
        // 1023 指纹头清洁: 连续 3 次指纹识别告警
        if let mac = app.current?.mac, BatteryCare.fpCleanNeeded(mac) {
            out.append(("连续 3 次指纹识别告警 — 指纹头可能脏了, 擦拭后再试", "drop.fill", .warn))
        }
        return out
    }

    // ---------- 包2 连接感知区: 69 蓝牙直通条 / 126 回连节律点阵 / 125 最后已知状态 / 535 同步回执 / 130 唤醒失败细分 ----------
    @ViewBuilder
    private var linkSenseCard: some View {
        let state = sense.linkState
        let rows = senseRows(state)
        if !rows.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                        HStack(alignment: .top, spacing: DS.Space.s) {
                            Image(systemName: r.1)
                                .font(.system(size: DS.Icon.sm, weight: .semibold))
                                .foregroundStyle(rowTone(r.2))
                                .accessibilityHidden(true)
                            Text(r.0)
                                .font(.footnote)
                                .foregroundStyle(r.3 ? DS.Palette.textSub : DS.Palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                            if r.3 {
                                Text("缓存")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(DS.Palette.textSub)
                                    .padding(.horizontal, 4).padding(.vertical, DS.Space.xxs)
                                    .background(DS.Palette.surfaceAlt, in: Capsule())
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    // 126 回连节律点阵 (仅在有回连轮次时出现)
                    if state == .down, sense.reconnectAttempt > 0 {
                        ReconnectDots(attempt: sense.reconnectAttempt, nextWait: nextLadderWait)
                    }
                }
            }
        }
    }
    /// 69/126/125/535/130/270/272/273 连接感知行 —— 纯函数, 不进 ViewBuilder。
    /// 原先把 `var rows` + `if { rows.append(...) }` 直接写在 @ViewBuilder 里, 分支体是 `()` 不是 View,
    /// 编译器报 "type '()' cannot conform to 'View'"。行表是数据, 组装与渲染本就该分开。
    private func senseRows(_ state: LinkState) -> [(String, String, String, Bool)] {
        var rows: [(String, String, String, Bool)] = []   // (text, icon, toneKey, cached)
        if !btReady {
            rows.append(("系统蓝牙已关闭 — 打开后会自动重连", "antenna.radiowaves.left.and.right.slash", "warn", false))   // 69 系统蓝牙已关闭
        }
        if state == .down, sense.reconnectAttempt > 0, CredentialOrg.pendingCount(app.currentMac) > 0 {
            rows.append(("回连节律: " + nextLadderText, "arrow.clockwise", "accent", false))
        }
        // 535 同步回执: 最近一次补发 N 项, 2 分钟内淡出
        if sense.lastReceipt > 0, Date().timeIntervalSince(sense.receiptShownAt) < 120 {
            rows.append(("已同步 \(sense.lastReceipt) 项变更", "checkmark.circle.fill", "ok", false))
        }
        // 131 会话重协商进行中: 假死巡检触发, 完成即消 (只读旗标, 无手动入口)
        if sense.revalidating {
            rows.append(("会话重协商中 — 假死巡检触发, 完成后自动消失", "arrow.triangle.2.circlepath", "accent", false))   // 131 会话重协商中
        }
        // 130 唤醒失败细分 (保守): 最近一次握手失败时给出三类归因 + 124 占用保守文案
        if state == .down, let last = lastWakeFail {
            rows.append(("唤醒失败 · \(last.name) — \(last.hint)", last.icon, "danger", false))
        }
        // 270/129 信号骤降预警: 最近 RSSI 走弱时建议靠近
        if let w = sense.weakSignalHint {
            rows.append((w, "antenna.radiowaves.left.and.right", "warn", false))
        }
        // 272 连接保持时长: 挂起过久提示重连
        if state == .ready, sense.holdMinutes >= 30 {
            rows.append(("连接已保持 \(sense.holdMinutes) 分钟 — 偏久, 可点刷新重连", "timer", "sub", false))   // 272 连接已保持
        }
        // 273 意图暂存: 断连且有排队变更时, 明示"已暂存, 回连续作"
        if state == .down, CredentialOrg.pendingCount(app.currentMac) > 0 {
            rows.append(("变更已暂存 — 回到锁旁会自动补发", "tray.full", "sub", false))   // 273 变更已暂存
        }
        // 125 最后已知状态: 断连时展示最后一次读到的电量/固件并标注"缓存"
        if state == .down, let snap = DB.readStatus(app.currentMac) {
            let at = DB.statusTime(app.currentMac)
            let when = at > 0 ? " · 数据截至 " + Self.lastStamp.string(from: Date(timeIntervalSince1970: at / 1000)) : ""
            let batt = snap.powerLevel >= 0 ? String(snap.powerLevel) + "%" : "--"
            let fw = snap.firmware.isEmpty ? "未知" : snap.firmware
            rows.append(("最后已知: 电量 " + batt + " / 固件 " + fw + " (缓存" + when + ")",
                         "clock.arrow.circlepath", "sub", true))
        }
        return rows
    }
    private var nextLadderText: String { "第 \(sense.reconnectAttempt) 轮 · 下一轮等 " + String(nextLadderWait) + " 秒" }
    private var nextLadderWait: Int { Int(sense.nextLadderInterval()) }
    private var lastWakeFail: LinkSense.FailKind? {
        // 130 细分: 取最近一条失败事件, 本地词表归三类; 124 占用细分协议未确证, 超时类走保守文案
        // 返回类型用已在用的 LinkSense.FailKind (name/hint 同形): `LinkSense.WakeReason` 早在删表那一轮就从
        // LinkSenseKit 移走了 (见 LinkSenseKit.swift:331 那句"已删"), 这三处引用是删类型时没扫调用点留下的。
        guard let ev = BleTelemetry.events.first(where: { !$0.ok }) else { return nil }
        // 124 死码改活: 旧判据 `ev.what.contains("超时")` 命中不了任何一条真实失败串 ——
        // 全仓 7 类 ok:false 事件是 预握手:未发现 / 预握手:信号弱跳过 / 预握手失败 X类 /
        // 握手失败 X类 / 回连失败第N轮 / 会话重协商失败 / 冷启动扫描失败, 一个"超时"都没有,
        // 那句占用文案从来不可达。占用归因改挂真实存在的"协议类/会话层失败"上。
        if ev.what.contains("蓝牙") {
            return LinkSense.FailKind(name: "蓝牙未开", hint: "打开系统蓝牙后会自动重连")
        }
        if ev.what.contains("协议类") || ev.what.contains("会话重协商失败") {
            return LinkSense.FailKind(name: "占用类", hint: LinkSense.occupationHint())
        }
        return LinkSense.FailKind(name: "不在广播范围", hint: "走到门锁旁 1 米内再试")
    }
    private func rowTone(_ key: String) -> Color {
        switch key {
        case "ok": return DS.Palette.ok
        case "warn": return DS.Palette.warn
        case "danger": return DS.Palette.danger
        case "accent": return DS.Palette.accentText
        default: return DS.Palette.textSub
        }
    }
    static let lastStamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    // ---------- 54 摇一摇迷你开锁面板 ----------
    /// 摇一摇唤出的迷你开锁面 (IDEA-BANK #54): 浮在设备页顶部, 再摇一次或点角上「收起」关掉。
    /// 开锁按钮走 app.requestUnlock() —— 与圆盘是**同一个入口**, 244 去重 / 250 二次应用锁 /
    /// 56 撤销窗口 / 296 只读模式逐道照常。轻点直发等于绕过按住确认, 与 53 双击直开同一减配口径,
    /// 所以卡面自己把这一点说出来, 不留"摇出来的是快车道"这种未言明的差别。
    private var shakeMiniPanel: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(spacing: DS.Space.xs) {
                Circle()
                    .fill(bleOn ? DS.Palette.ok : DS.Palette.warn)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(app.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(bleOn ? "已连接" : "未连接 · 开锁会自动唤醒")
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : DS.Motion.exit) { app.shakePanel = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: DS.Icon.xs, weight: .medium))
                        .foregroundStyle(DS.Palette.textSub)
                        .frame(width: DS.Hit.min, height: DS.Hit.min)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("收起迷你开锁面板")
            }
            Button {
                app.shakePanel = false
                app.requestUnlock()
            } label: {
                Label("开锁", systemImage: "lock.open")
            }
            .buttonStyle(PrimaryActionStyle(fullWidth: false))
            .accessibilityHint("轻点直发, 绕过按住确认")
            Text("轻点直发: 绕过按住确认 (同 53 口径); 二次应用锁与防抖去重照常")
                .font(.caption2)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Space.m)
        .axGlass(DS.Radius.card)
        .accessibilityElement(children: .contain)
    }

    // ---------- 开锁主控 ----------
    private var unlockDial: some View {
        // 868 切换控制扫描组: 圆盘为独立扫描组, 外接开关逐项聚焦 (停留时长按 869 自定滑杆)
        VStack(spacing: DS.Space.m) {
            UnlockDial(state: app.unlockState,
                       phase: app.phase,
                       connected: bleOn,
                       bleReady: btReady,
                       failStreak: app.failStreak,
                       retryText: retryText,
                       batteryText: app.current.map { batteryText(for: $0) } ?? "未知",
                       rssi: LinkSense.rssiFor(app.currentMac),
                       action: { dialAction() },
                       cancelAction: { app.cancelUnlock(notify: true) })
            // 包15 字幕式过程条 (881): 连接/开锁过程逐字文案条给听障用户 (设置-辅助可关)
            if AXPrefs.captions {
                CaptionStepBar(phase: app.phase, unlockState: app.unlockState)
                    .transition(.opacity)
            }
            // 39 自动上锁倒计时 (协议 cmd24 档位的本地回放, 不虚构门磁): 开锁成功后提醒关手
            if let left = autoLockLeft {
                Label("约 \(left) 秒后自动上锁 · 请确认门已关好", systemImage: "timer")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.accentText)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                    .accessibilityLabel("自动上锁倒计时 \(left) 秒, 请确认门已关好")
            }
            if !btReady {
                Text("打开系统蓝牙后即可开锁")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
            } else if !bleOn {
                Text("未连接时点击会自动唤醒门锁蓝牙")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
            }
            // 88 临时码备援: BLE 反复失败时, 已开通的临时码可在锁键盘直接输入 (纯提示, 不涉协议)
            if app.failStreak >= 2, DB.otpStatus(app.currentMac)?.on == true {
                Label("蓝牙连不稳? 已开通的临时码可直接在门锁键盘输入开门", systemImage: "keyboard")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.accentText)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            // 1003 安慰式报错: 一次失败轻声安慰, 三次后给可勾排查清单 (87)
            if app.failStreak > 0 {
                VStack(spacing: DS.Space.xs) {
                    Text(app.failStreak < 3 ? "再试一次, 别着急" : "连着几次没成, 逐项自查一遍:")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if app.failStreak >= 3 {
                        checklist
                        NavigationLink {
                            DiagnosticsView()
                        } label: {
                            Label("打开排查工具", systemImage: "wrench.and.screwdriver")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(DS.Palette.accentText)
                                .padding(.horizontal, DS.Space.l)
                                .frame(minHeight: DS.Hit.min)
                                .background(DS.Palette.accentText.opacity(0.09),
                                            in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
                .transition(.opacity)
            }
            // 83: 自动重试 (2s/5s) 用尽进入终态失败 → 圆盘下方主按钮手动再试
            // (超时失败不涨 failStreak, 所以钩在 .failed 上, 不能挂进上面 failStreak 块)
            if case .failed = app.unlockState {
                Button("再试一次") { dialAction() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Palette.accentText)
                    .padding(.horizontal, DS.Space.xl)
                    .frame(minHeight: DS.Hit.min)
                    .background(DS.Palette.accentText.opacity(0.12), in: Capsule())
                    .buttonStyle(PressableButtonStyle())
            }
        }
        .axOnehand()   // 873/60 单手下沉: 圆盘区整体下移入拇指区
                       // (挂在整个圆盘区 VStack 上 —— 原先误挂在 `if AXPrefs.captions` 分支后,
                       //  那是把修饰符接在 if 语句上, 编译器按隐式成员解析报 "cannot be used on type 'View'")
        .padding(.vertical, DS.Space.l)
        .animation(DS.Motion.soft, value: app.failStreak)
        .animation(DS.Motion.soft, value: autoLockLeft)
        // 267 换锁二次确认: 横滑换锁后第一次点圆盘 → 放大的锁名胶囊提示, 再点才执行
        .overlay {
            if confirmPulse {
                VStack(spacing: DS.Space.xs) {
                    Text("即将开锁")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                    Text(app.displayName)
                        .font(.headline)
                        .foregroundStyle(DS.Palette.accentText)
                        .padding(.horizontal, DS.Space.l)
                        .padding(.vertical, DS.Space.s)
                        // 2026-10-14 材质统一: 二次确认提示胶囊上玻璃。
                        // 下面那圈 accent 1.5pt 留着 —— 它是"还没执行, 再点才开锁"的告警边, 不是装饰边。
                        .axGlassCapsule()
                        .overlay(Capsule().strokeBorder(DS.Palette.accent, lineWidth: 1.5))
                        .scaleEffect(confirmPulse ? 1.06 : 1)
                    Text("再点一次圆盘开始开锁")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                }
                .padding(DS.Space.l)
                .axGlass(DS.Radius.card)
                .transition(.scale(scale: 1.12).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("换锁确认: 即将对 \(app.displayName) 开锁, 再点一次圆盘确认")
            }
        }
    }
    private func dialAction() {
        if confirmMac != nil {
            // 首点: 只亮胶囊, 不发指令 (244 去重窗口之外的软闸)
            DS.Haptics.tick.impactOccurred()
            confirmMac = nil
            withAnimation(DS.Motion.standard) { confirmPulse = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.4))
                withAnimation(DS.Motion.exit) { confirmPulse = false }
            }
            return
        }
        app.requestUnlock()
    }
    // 39 倒计时: 秒数来自本地布防记忆 (kf_tailgate_, 档位+1=秒), 没设过按厂商默认 6 秒
    private func startAutoLockCountdown() {
        let interval = DB.tailgate(app.currentMac)?.interval ?? 5
        let total = max(2, interval + 1)
        autoLockLeft = total
        Task { @MainActor in
            for left in stride(from: total, through: 1, by: -1) {
                autoLockLeft = left
                try? await Task.sleep(for: .seconds(1))
                if autoLockLeft != left { return }   // 期间重新开锁/切锁 → 让位新的倒计时
            }
            withAnimation(DS.Motion.exit) { autoLockLeft = nil }
        }
    }

    // ---------- 112 换机验证向导 (恢复备份后逐锁点按验证连接) ----------
    // kf_migrate_pending 由备份恢复写入; 每锁 kf_migok_<mac> 打勾, 全部通过后收起。
    @ViewBuilder
    private var migrationWizard: some View {
        if DB.store.getString("kf_migrate_pending").isEmpty == false {
            let pending = app.devices.filter { !DB.store.getBool("kf_migok_" + $0.mac) }
            // 112: 不设多锁门槛 —— 单锁用户换机恢复备份后同样要验证密钥与连接, 原句只讲"恢复备份后逐锁验证"。
            if !pending.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        HStack(spacing: DS.Space.s) {
                            SectionTitle(text: "换机迁移验证")
                            Spacer(minLength: 0)
                            Button("收起") { wizardDismissed = true }
                                .font(.footnote)
                                .foregroundStyle(DS.Palette.textSub)
                        }
                        Text("检测到刚恢复过备份。逐把靠近门锁点「验证」，确认密钥与连接都正常。")
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(pending) { kc in
                            HStack(spacing: DS.Space.s) {
                                Circle().fill(LockArchive.swatchColor(LockArchive.meta(kc.mac).colorKey))
                                    .frame(width: 8, height: 8)
                                Text(LockArchive.displayName(kc))
                                    .font(.subheadline)
                                    .foregroundStyle(DS.Palette.text)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                Spacer(minLength: DS.Space.s)
                                if wizardBusy == kc.mac {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Button("验证") { Task { await verifyMigrated(kc) } }
                                        .buttonStyle(SecondaryActionStyle(fullWidth: false))
                                }
                            }
                            .frame(minHeight: DS.Hit.min)
                        }
                    }
                }
            }
        }
    }
    private func verifyMigrated(_ kc: Keychain) async {
        guard wizardBusy.isEmpty else { return }
        wizardBusy = kc.mac
        defer { wizardBusy = "" }
        do {
            try await app.lock.ensureConnected(mac: kc.mac)
            _ = try await app.lock.getStatus(mac: kc.mac)
            DB.store.set("kf_migok_" + kc.mac, true)
            DS.Haptics.tick.impactOccurred()
            app.showToast("「\(LockArchive.displayName(kc))」验证通过")
        } catch {
            app.showToast("「\(LockArchive.displayName(kc))」验证失败: \(error.localizedDescription)")
        }
    }

    // 87 排查清单: 查蓝牙 / 走近 / 查电量, 逐项可勾
    private var checklist: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(checkTexts.enumerated()), id: \.offset) { i, txt in
                Button { checks[i].toggle() } label: {
                    HStack(spacing: DS.Space.s) {
                        Image(systemName: checks[i] ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: DS.Icon.sm, weight: .semibold))
                            .foregroundStyle(checks[i] ? DS.Palette.ok : DS.Palette.textSub)
                        Text(txt)
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(txt)
                .accessibilityAddTraits(checks[i] ? [.isSelected] : [])
            }
        }
    }
    private var checkTexts: [String] {
        ["手机蓝牙已开启", "已靠近门锁 (1–2 米内)", "门锁电量充足 (低于 20% 先换电池)"]
    }
    // 85 退避节奏文案
    private var retryText: String? {
        guard let w = app.retryWait else { return nil }
        return "第 \(app.retryAttempt) 次 · 等 \(w) 秒"
    }

    // 81 专注开锁: 全屏只剩圆盘与状态文案
    private var focusButton: some View {
        Button { showFocus = true } label: {
            Image(systemName: "chevron.down.circle")
                .font(.system(size: DS.Icon.md, weight: .semibold))
                // 入口画在 hero 卡面上, 前景必须走 heroFg (与 HeroStat/HeroPill 同源), 写死白在 863 降级下会被吃掉
                .foregroundStyle(DS.heroFg)
                .frame(width: DS.Hit.min, height: DS.Hit.min)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("专注开锁")
        .accessibilityHint("进入全屏, 只显示开锁圆盘与状态")
    }

    // ---------- 快捷操作 ----------
// 液态玻璃: 相邻玻璃元素必须放进同一个 GlassEffectContainer 才能融成一体,
    // 否则每块各自折射、边缘会出现难看的接缝。
    private var quickActions: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            SectionTitle(text: "快捷操作")
                .padding(.horizontal, DS.Space.gutter)
            // 230 大格模式: 2 列大格 (长辈友好, 设置-辅助可切); 229 左手模式镜像工具条侧
            let cols = AXPrefs.bigTile ? 2 : 3
            GlassEffectContainer(spacing: DS.Space.s) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s), count: cols),
                          spacing: DS.Space.s) {
                    // 905: 格子来自池子 (默认选中就是原来的六格，观感不变; 921 加了"再开一次")；
                    // 1047: 顺序由 QuickPool.ordered() 决定 —— 默认关还跟一条 30 天规则:
                    //        从未手动调整过且满 30 天 → 只把最常用的一格提到首格, 其余保序。
                    // 仍走 quickLink 这一个渲染器：它带着 .axGlass / .contentShape / 按压态 / 朗读标签，
                    // 在网格里另抄一份 label 就等于把这四样悄悄丢了 (第七十八批差点犯的那条)。
                    ForEach(tiles) { a in
                        if a.id == "again" {
                            // 921: 这一格是 Button 不是 NavigationLink —— 它不推开新页, 而是跨 Tab 定位
                            againTile
                                .contextMenu {
                                    Button {
                                        showTileEdit = true
                                    } label: {
                                        Label("编辑快捷操作格", systemImage: "square.grid.2x2")   // 905 编辑快捷操作格
                                    }
                                }
                        } else {
                            quickLink(icon: a.icon, label: a.label,
                                      onTap: {
                                          // 1047: 静默记一次本机点击 (手动关过开关即停记, 见 QuickPool.recordingOn)
                                          QuickPool.recordTap(a.id)
                                          // 827: 点的正是当前被提示那一格 ⇒ 消掉它, 下次讲下一格
                                          if app.quickTipTile?.id == a.id {
                                              app.ambientTipUsed.insert(a.id)
                                              HintOnce.mark("827seen_" + a.id)
                                          }
                                      }
                            ) { quickDestination(a.id) }
                            // 905: 长按任一格 → 编辑面板。走系统 contextMenu 而不是自挂长按手势:
                            // 与 NavigationLink 的点击零冲突 (同 740 "长按走菜单"的先例), 面板内改动即时生效。
                            .contextMenu {
                                Button {
                                    showTileEdit = true
                                } label: {
                                    Label("编辑快捷操作格", systemImage: "square.grid.2x2")   // 905 编辑快捷操作格
                                }
                            }
                        }
                    }
                    // 812 延迟添加指纹: 这把锁一枚指纹都没有时，格尾多一枚**虚线待添加**格。
                    // 点它直接开真正的录入表单 (quickDestination addFp = 与"添加指纹"大格同一个
                    // 嵌入视图, 不是第二份校验逻辑); 旧版只弹 toast 指点去凭证 Tab, 等于把用户支走。
                    if DB.listFps(app.currentMac).isEmpty {
                        NavigationLink {
                            quickDestination("addFp")
                        } label: {
                            VStack(spacing: DS.Space.xs) {
                                Image(systemName: "hand.raised.dotted")
                                    .font(.system(size: DS.Icon.md))
                                    .foregroundStyle(DS.Palette.textSub)
                                Text("待添加指纹")
                                    .font(.caption2)
                                    .foregroundStyle(DS.Palette.textSub)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DS.Space.m)
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                                    .strokeBorder(DS.Palette.hairline,
                                                  style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            )
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel("这把锁还没有指纹，轻点直接添加")   // 812 这把锁还没有指纹
                    }
                }
            }
            // 827 顺序揭幕提示 (Telegram tips): 每次只提"按显示顺序第一格还没被点过"的那一格，
            // 点过一次就换下一格 (用一次消一格)。
            // 浮签做在网格**下方一行**而不是盖在格子上：Grid 里给一格加 overlay 会压到邻格，
            // 而且盖住正在讲的那格，等于让人看不见它长什么样。
            // 乱源治理第 2 批: 这一行也进预算了 —— 顶部有自检黄条或剪贴板条在说话时，这里就静默，
            // 内容由"还有 N 条提醒"汇总胶囊逐条给回，不丢。
            if let t = app.quickTipTile, app.ambientTop == .quickTileTip {
                HStack(spacing: DS.Space.s) {
                    Image(systemName: "hand.point.up.left")
                        .font(.system(size: DS.Icon.xs))
                        .foregroundStyle(DS.Palette.textSub)
                        .accessibilityHidden(true)
                    Text("试试「" + t.label + "」—— 这一格你还没用过")   // 827 这一格你还没用过
                        .font(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("不再提示") { app.ambientTipOff = true; HintOnce.mark("827off") }
                        .font(.caption2)
                        .foregroundStyle(DS.Palette.accentText)
                        .frame(minHeight: DS.Hit.min - DS.Space.m)
                        // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 没有 minHeight (< 44)。
                        // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Rectangle())
                }
                .padding(.horizontal, DS.Space.gutter)
            }
        }
    }
    // 827 的"还没被点过的第一格"判据搬到 AppState.quickTipTile —— 预算要拿它排位，
    // 而视图层的 private var 预算读不到。判据三选一 (本会话点过 / 以前点过 / 频次表已有点击) 一字未改。
    /// 905/1047: `onTap` 是给 1047 记频次用的**可选**回调。
    /// 用 simultaneousGesture 而不是把 NavigationLink 换成 Button：换掉就会丢导航，
    /// 而 simultaneousGesture 让点击既走导航又能记账。传 nil 时一个手势都不加。
    private func quickLink<Content: View>(icon: String, label: String,
                                          onTap: (() -> Void)? = nil,
                                          @ViewBuilder content: () -> Content) -> some View {
        NavigationLink { content() } label: {
            quickTileBody(icon: icon, label: label)
                .modifier(OptionalTap(onTap: onTap))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(label)
    }
    /// 格子的图标 + 文字本体 (quickLink 与被 921 换成的按钮格共用, 免得两份样式漂移)
    @ViewBuilder
    private func quickTileBody(icon: String, label: String) -> some View {
        let big = AXPrefs.bigTile   // 230 大格: 图标与字号随加大
        VStack(spacing: DS.Space.s) {
            // 图标坐进主色 12% 的圆角底座: 四个入口有了统一的"图标 + 玻璃砖"节奏
            Image(systemName: icon)
                .font(.system(size: big ? DS.Icon.lg : DS.Icon.md, weight: .semibold))
                .foregroundStyle(DS.Palette.accentText)
                .frame(width: big ? 48 : 40, height: big ? 48 : 40)
                .background(DS.Palette.accentText.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            Text(label)
                .font(big ? .callout : .caption)
                .foregroundStyle(DS.Palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: DS.Hit.min + DS.Space.xl)
        .padding(.vertical, DS.Space.m)
        .axGlass(DS.Radius.tile)
        .contentShape(Rectangle())
    }

    /// 921「再开一次」格: 目标 = QuickPool.repeatTarget (星标密码 > 星标指纹 > 高频推断)。
    /// 星标集为空且推不出一条时, 点按给"先去点亮星标"的指路 toast —— 不猜、不假装能开。
    @ViewBuilder
    private var againTile: some View {
        let target = QuickPool.repeatTarget(app.currentMac)
        Button {
            QuickPool.recordTap("again")
            if app.quickTipTile?.id == "again" {
                app.ambientTipUsed.insert("again")
                HintOnce.mark("827seen_again")
            }
            if let t = target {
                app.pendingCredNav = t.nav
                app.pendingCredNavMac = app.currentMac
                app.tabSelection = 1
                app.showToast("已跳到凭证页定位「" + t.name + "」")   // 921 界面文案
            } else {
                app.showToast("还没有星标凭证 —— 先在凭证页给最常用的那条点亮星标")   // 921 还没有星标凭证
            }
        } label: {
            quickTileBody(icon: "arrow.counterclockwise", label: "再开一次")
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("再开一次")   // 921 再开一次
        .accessibilityHint(target.map { "跳到凭证页定位 " + $0.name } ?? "还没有星标凭证, 先去凭证页点亮星标")
    }

    // ---------- 最近开门 ----------
    // ---------- 最近开门 (765: 当前锁 / 全部锁跨锁合并, 行尾带锁名标签) ----------
    private var recentCard: some View {
        let rows = app.recentRecords()
        return Card {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                SectionTitle(text: recentAllLocks ? "最近开门 · 全部锁" : "最近开门",
                             count: recentAllLocks ? mergedRecent.count : rows.count)
                // 只有一把锁时不出现这排: 单锁没有"跨锁"可言, 放上去等于给一个恒真的选项。
                if app.devices.count > 1 {
                    // @layout-allow 触达托管 Picker: 控件本体高度由系统渲染, 我们撑 frame 只会多出一片点不动的死区。
                    // 上机复测: 用拇指点这一行的上下边缘, 看打不打得开 (打得开=系统已给够 44, 这条可以销)
                    Picker("最近开门范围", selection: Binding(   // 765 最近开门范围
                        get: { recentAllLocks },
                        set: { recentAllLocks = $0; DB.store.set("kf_recent_all", $0) })) {
                        Text("当前锁").tag(false)
                        Text("全部锁").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                if recentAllLocks {
                    mergedRecentRows
                } else if rows.isEmpty {
                    Text("还没有开门记录。门锁有新动静时会出现在这里。")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: DS.Space.s) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                            // 170: 整行可点 → 记录 Tab 落到那一条并高亮 (key 格式与 585 引用链接同一个出口;
                            // 被筛选挡掉的行由 RecordsView 自己回一句"不在当前显示范围里", 这里不假装成功)
                            Button { landRecord(r.key) } label: {
                                HStack(alignment: .top, spacing: DS.Space.s) {
                                    Image(systemName: r.warn ? "exclamationmark.triangle.fill" : "person.crop.circle.fill")
                                        .font(.system(size: DS.Icon.sm))
                                        .foregroundStyle(r.warn ? DS.Palette.warn : DS.Palette.textSub)
                                        .accessibilityHidden(true)
                                    Text(r.text)
                                        .font(.footnote)
                                        .foregroundStyle(DS.Palette.text)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: DS.Icon.xs))
                                        .foregroundStyle(DS.Palette.textSub)
                                        .accessibilityHidden(true)
                                }
                                .frame(minHeight: DS.Hit.min)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressableButtonStyle())
                            .accessibilityElement(children: .combine)
                            .accessibilityHint("点按跳到记录页这条并高亮")   // 170 点按跳到记录页这条并
                            // 559: 原句是「行左滑查记录」—— 本区是卡片不是 List, SwiftUI 的 swipeActions
                            // 只对 List 行生效, 左滑在这里拉不出动作; 替代口径 = 行上长按菜单 (与记录页行
                            // 714/761 同一交互档)。跳转并填入成员过滤是真行为, 文案不写"左滑"。
                            // 成员不可证明的行 whoId 为 nil ⇒ 菜单内容为空, 系统不弹空菜单。
                            .contextMenu {
                                if let mid = r.whoId {
                                    Button {
                                        openMemberRecords(mid)
                                    } label: {
                                        Label("查这位成员的记录", systemImage: "magnifyingglass")   // 559 查这位成员的记录
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var mergedRecentRows: some View {
        if mergedRecent.isEmpty {
            Text("这些锁的本地缓存里还没有开门记录 — 连上一次锁、拉一次日志就会出现在这里。")
                .font(.footnote)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: DS.Space.s) {
                ForEach(mergedRecent) { r in
                    // 170 的另一半: 跨锁合并流里的行同样可点 (Rec.id 就是 mac#key, 与落地格式同源)
                    Button { landRecord(r.id) } label: {
                        HStack(alignment: .top, spacing: DS.Space.s) {
                            Image(systemName: r.alarm ? "exclamationmark.triangle.fill" : "person.crop.circle.fill")
                                .font(.system(size: DS.Icon.sm))
                                .foregroundStyle(r.alarm ? DS.Palette.warn : DS.Palette.textSub)
                                .accessibilityHidden(true)
                            Text(mergedLine(r))
                                .font(.footnote)
                                .foregroundStyle(DS.Palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: DS.Space.xs)
                            // 765 要求的行尾锁名标签: 合并流里"哪把锁"必须一眼可见, 不然跨锁就没有意义
                            Text(r.lockName)
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                                .foregroundStyle(DS.Palette.textSub)
                                .padding(.horizontal, DS.Space.s)
                                .padding(.vertical, 2)
                                .background(DS.Palette.surfaceAlt, in: Capsule())
                                .frame(maxWidth: 82)
                        }
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("点按跳到记录页这条并高亮")   // 170 点按跳到记录页这条并
                    // 559: 与单锁行同一口径 (说明见上面那段); 判据换 Rec 的可证明归属。
                    .contextMenu {
                        if let mid = provableMemberId(r) {
                            Button {
                                openMemberRecords(mid)
                            } label: {
                                Label("查这位成员的记录", systemImage: "magnifyingglass")   // 559 查这位成员的记录
                            }
                        }
                    }
                }
            }
            if mergedHasSameMinute {
                Text("同一分钟内的两条不分先后: 日志只到分钟, 这里的次序是入库次序 (与 680 同一口径)。")
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 170 落地：把行身份交给记录 Tab 的同一个入口 (pendingRecordKey → landRecordKey)。
    /// Tab 序号取自 deepLinkHosts 那张表 (device0/credentials1/records2/settings3)：
    /// 再写一份 0/1/2/3 的字面量就会在两处各数各的。
    private func landRecord(_ key: String) {
        guard !key.isEmpty else { return }
        app.pendingRecordKey = key
        app.tabSelection = 2
    }

    /// 559 落地: 「最近开门」行上可证明的成员 → 记录 Tab 并按该成员过滤。
    /// 复用 582 的 pendingRecordsMember → landMember 链路 (记录页消费后清空, 不残留过滤)。
    private func openMemberRecords(_ id: String) {
        app.pendingRecordsMember = id
        app.tabSelection = 2
    }
    /// 559: Rec 行的归属可证明才给"查记录" (与 landMember 的 guard 同判据 —— 动作出现就必然落得下去)。
    private func provableMemberId(_ r: Rec) -> String? {
        guard let id = r.whoId, !id.isEmpty, DB.member(id) != nil else { return nil }
        return id
    }

    /// 合并流的一行正文: 时间 (MM-dd HH:mm) + 可证明归属则说"谁用什么开了门", 推不出就只报事件名。
    /// 与单锁那条 (AppState.recentRecords) 同一口径: 推不出归属**不猜**, 也不显示"未知成员"。
    private func mergedLine(_ r: Rec) -> String {
        let t = r.timeStr.isEmpty ? "" : String(r.timeStr.dropFirst(5).prefix(11))
        let what: String
        if let who = MemberHub.aliasName(r.whoId) ?? r.whoName, let kind = r.kind {
            what = who + " 用" + (Attribution.words[kind] ?? "") + "开了门"
        } else {
            what = r.typeName
        }
        return t.isEmpty ? what : t + " · " + what
    }
    /// 跨锁同分钟检测: 相邻两行的"到分"前缀相同即存在歧义 (与 680 同一判据)。
    private var mergedHasSameMinute: Bool {
        guard mergedRecent.count > 1 else { return false }
        var prev = ""
        for r in mergedRecent {
            let m = String(r.timeStr.prefix(16))
            if m.isEmpty { continue }
            if m == prev { return true }
            prev = m
        }
        return false
    }

    // ---------- 安心夜打卡 (976): 22 点后手动确认 (协议无上锁状态位, 不猜测) ----------
    @ViewBuilder
    private var nightCheckRow: some View {
        if Milestones.canNightCheckIn, Milestones.nightMarks()[Milestones.dayKey()] == nil {
            Card {
                Button {
                    if Milestones.checkInTonight() {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        app.showToast("今晚已安心打卡")
                    }
                } label: {
                    Label("安心夜打卡 · 记录今晚", systemImage: "moon.stars.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DS.Palette.accentText)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
    }

    private var privacyFootnote: some View {
        Text("数据全部保存在本机 · 全程离线，不上传任何服务器")
            .font(.caption)
            .foregroundStyle(DS.Palette.textSub)
            .multilineTextAlignment(.center)
            .padding(.horizontal, DS.Space.xl)
            .padding(.bottom, DS.Space.m)
    }

    /// 480 成员色: 走成员档案 hex 档, 与 RecordsView/SecurityCenterView 同一纪律 (各自本地换算, 不另建共享层)
    private static func memberHexColor(_ m: Member) -> Color {
        var s = m.color
        if s.hasPrefix("#") { s.removeFirst() }
        guard let v = UInt32(s, radix: 16) else { return DS.Palette.accent }
        return Color(hex: v)
    }

    // ---------- 包13 家庭关怀行 (485 生日 / 480 孩子码 / 475 家庭便签): 当前锁的活页面 ----------
    @ViewBuilder
    private var familyCareRows: some View {
        let care = MemberHub.careDue(app.currentMac)
        if let c = care.first {
            let note = MemberHub.ext(c.member.id).careText
            // 480 成员色高亮: 警告语义留给卡片染色 (warn), 身份用成员建档色 —— 色条 + 头像同色,
            // 一眼看出"这是在说谁"; 通用 accentText 头像在多成员家庭里分不出人。
            let who = Self.memberHexColor(c.member)
            Card(tint: .warn) {
                HStack(spacing: DS.Space.s) {
                    Rectangle().fill(who).frame(width: 3).clipShape(Capsule())
                        .accessibilityHidden(true)
                    MemberAvatar(member: c.member, tint: who)
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text("「" + MemberHub.display(c.member) + "」的临时码还有 " + String(c.days) + " 天到期")   // 480 天到期
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(DS.Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if !note.isEmpty {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .frame(minHeight: DS.Hit.min)
            }
        }
        // 485 生日行: Milestones 已有当天寿星与提前一天通知, 这里只补当日祝语行
        // 480 同族: 寿星头像同样随成员色 (与上面那张关怀卡同一"说谁像谁"的口径)
        if let b = Milestones.birthdayCelebrantToday {
            Card {
                HStack(spacing: DS.Space.s) {
                    MemberAvatar(member: b, tint: Self.memberHexColor(b))
                    Text("今天是" + MemberHub.display(b) + "的生日, 替我们说声生日快乐")   // 485 的生日
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.accentText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .frame(minHeight: DS.Hit.min)
            }
        }
        // 387 维护回执: 上次会话本机做过的整理 (清理空值/归档/自动补发) 回一行, 点"知道了"后隐藏
        // 措辞按实际能力写"上次会话" —— 本 App 无后台执行面, "退出期间完成"是不存在的说法
        if let line = MaintenanceLog.lastSessionLine(sessionStart: DB.store.get("kf_session_start", Double.self) ?? 0) {
            Card {
                HStack(spacing: DS.Space.s) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: DS.Icon.sm))
                        .foregroundStyle(DS.Palette.accentText)
                        .accessibilityHidden(true)
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: DS.Space.s)
                    Button("知道了") {
                        MaintenanceLog.markSeen(sessionStart: DB.store.get("kf_session_start", Double.self) ?? 0)
                        app.showToast("已收起维护回执")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                }
            }
        }
        // 437 备份复核钉: 到日的复核催一行 (未到日不出现在这里, 只在备份列表里存档)
        // 按钮只跳设置 Tab —— "本地备份文件"藏在 设置→备份与恢复→备份工作室 三层 sheet 之后,
        // 不为这一行造一套 pending-sheet 路由, 所以文案把路径写全, 不假装"一点就到"。
        if let p = duePins.first {
            Card(tint: .warn) {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    HStack(spacing: DS.Space.s) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: DS.Icon.sm))
                            .foregroundStyle(DS.Palette.warn)
                            .accessibilityHidden(true)
                        Text("该复核 \(BackupStudio.pinDayText(p.day)) 的那份备份了: \(BackupStudio.pinLabel(p.file))")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(DS.Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    Text(p.overDays == 0 ? "复核日就是今天 · 437"
                                         : "已过 \(p.overDays) 天 · 437")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                    Text("路径: 设置 → 备份与恢复 → 备份工作室 → 本地备份文件")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: DS.Space.s) {
                        Button("去设置") { app.tabSelection = 3 }
                        Button("知道了") {
                            BackupStudio.markPinSeen(p.file, p.day)
                            duePins = BackupStudio.duePins()   // 立刻重算: 撤掉的这一钉不该在同一屏上还挂着
                            app.showToast("这一钉不再催；把复核日挪到新一天会重新催")
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                }
            }
            if duePins.count > 1 {
                Text("另有 \(duePins.count - 1) 个复核钉也到期了")   // 437 另有
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
            }
        }
        // 475 家庭便签: 设备页 Hero 卡下浮动一行 (与成员绑定)
        let notes = DB.members().compactMap { m -> (Member, String)? in
            let n = MemberHub.ext(m.id).note
            return n.isEmpty ? nil : (m, n)
        }
        if !notes.isEmpty {
            Card {
                // notes 是 [(Member, String)]: 元组不能遵循 Identifiable, 所以单参 ForEach 用不了 ——
                // 与 key path 无关 (元组元素的 key path 合法, 见 LockStats.grouped 那处 2026-10-13 的查证更正)
                // → 与本页 attentionCard 同型写法, enumerated + offset 作身份
                ForEach(Array(notes.enumerated()), id: \.offset) { _, n in
                    HStack(spacing: DS.Space.s) {
                        MemberAvatar(member: n.0, size: 22)
                        Text(MemberHub.display(n.0) + " 的便签: " + n.1)
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        // 481 本周轮值副标题: 已挂到 Hero 卡 heroMomentText 之后
        if let d = MemberHub.dutyThisWeek, let dm = DB.member(d) {
            Card {
                HStack(spacing: DS.Space.s) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: DS.Icon.sm))
                        .foregroundStyle(DS.Palette.accentText)
                        .accessibilityHidden(true)
                    Text("本周主责: " + MemberHub.display(dm))   // 481 本周主责
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.text)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
            }
        }
    }

    // ---------- 派生数据 (包3: 参数化到任意锁 — 当前页吃实时, 其余页读快照) ----------
    /// 826 聚光教练标: nil = 不显示; 0/1/2 = 当前焦点序号 (只在首进设备 Tab 时出现一次)
    @State private var coachStep: Int? = nil
    // 904 模块排序: 排序表开关 + 改完强制重算 (顺序存在 DB 里)
    @State private var showModuleOrder = false
    @State private var orderTick = 0
    /// 904 三模块的当前顺序 (槽位固定, 默认 = 现状, 所以默认渲染逐字节不变)。
    /// 存的是**顺序串** (kf_dev_order = "hero,quick,recent"), 非法/缺失一律回落默认。
    private var devOrder: [String] {
        let _ = orderTick
        let raw = DB.store.getString("kf_dev_order")
        let ids = raw.isEmpty ? [] : raw.split(separator: ",").map(String.init)
        return (ids.count == 3 && Set(ids) == Set(["hero", "quick", "recent"])) ? ids : ["hero", "quick", "recent"]
    }
    private func moduleName(_ id: String) -> String {
        switch id {
        case "quick": return "快捷操作格"
        case "recent": return "最近开门"
        default: return "状态卡 (Hero)"
        }
    }
    private func moveModule(_ i: Int, _ d: Int) {
        var o = devOrder
        let j = i + d
        guard o.indices.contains(i), o.indices.contains(j) else { return }
        o.swapAt(i, j)
        DB.store.set("kf_dev_order", o.joined(separator: ","))
        orderTick += 1
    }
    /// 904: 把模块放进某个槽位 (868 的扫描组标签随模块走, 不因换槽丢掉)
    @ViewBuilder
    private func moduleSlot(_ id: String, delay: Int) -> some View {
        switch id {
        case "quick":
            quickActions.staggered(delay)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("快捷操作格组")   // 868 快捷操作格组
        case "recent":
            recentCard.staggered(delay)
        default:
            heroPager.staggered(delay)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("状态卡组")   // 868 状态卡组
        }
    }
    private var moduleOrderSheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(devOrder.enumerated()), id: \.offset) { i, id in
                        HStack(spacing: DS.Space.s) {
                            Text(moduleName(id))
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button { moveModule(i, -1) } label: { Image(systemName: "arrow.up") }
                                .disabled(i == 0)
                                .frame(minHeight: DS.Hit.min)
                            Button { moveModule(i, 1) } label: { Image(systemName: "arrow.down") }
                                .disabled(i == devOrder.count - 1)
                                .frame(minHeight: DS.Hit.min)
                        }
                        .frame(minHeight: DS.Hit.min)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(moduleName(id)), 第 \(i + 1) 位")
                    }
                } header: {
                    Text("设备页模块顺序")   // 904 设备页模块顺序
                } footer: {
                    Text("槽位固定 (Hero 槽 / 快捷格槽 / 最近开门槽), 改的是哪个模块占哪个槽 —— 默认顺序就是现在的样子。")
                        .font(.caption).foregroundStyle(DS.Palette.textSub)
                }
                // 乱源治理第 3 批: 显隐面板。默认全开 (一块都不隐), 这一节给的是"能不能关"，不是新默认值。
                Section {
                    ForEach(DevModule.allCases) { m in
                        VStack(alignment: .leading, spacing: DS.Space.xs) {
                            // 系统 Toggle: 标题写明用途, 开/关态由系统播报, 不另写重复值 (232 同口径)
                            Toggle(isOn: Binding(
                                get: { !devHidden.contains(m.rawValue) },
                                set: { on in
                                    DevModuleStore.setHidden(m, !on)
                                    devHidden = DevModuleStore.hidden   // 写盘之外还要即时生效 (UserDefaults 不是可观察源)
                                })) {
                                Text(m.title)
                            }
                            Text(m.cost)
                                .font(.caption2)
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
                        .font(.caption).foregroundStyle(DS.Palette.textSub)
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

    /// 246 凭证选择胶囊: 圆盘上方选"本次用哪条 PIN"。只显示**序号**, 不显示 PIN 值 ——
     /// 口令是密钥材料, 摆在屏上等于给肩窥递梯子; 选中结果以**下标**存 kf_pinpick_<mac>, 开锁时随 pinDec 下发。
    private func pinPickCapsule(_ kc: Keychain) -> some View {
        let idx = app.chosenPinIndex(kc.mac)
        return HStack(spacing: DS.Space.s) {
            Menu {
                ForEach(Array(kc.pins.enumerated()), id: \.offset) { i, _ in
                    Button(idx == i ? "✓ PIN #\(i + 1)" : "PIN #\(i + 1)") { app.setChosenPinIndex(kc.mac, i) }
                }
                if idx >= 0 {
                    Button("恢复默认 (第一条)") { app.setChosenPinIndex(kc.mac, -1) }
                }
            } label: {
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: "key.horizontal.fill").font(.system(size: DS.Icon.xs))
                    Text(idx >= 0 && idx < kc.pins.count ? "本次用 PIN #\(idx + 1)" : "本次用 PIN (默认第一条)")
                        .font(.caption)
                    Image(systemName: "chevron.down").font(.system(size: 10))
                }
                .foregroundStyle(DS.Palette.accentText)
                .padding(.horizontal, DS.Space.s)
                .padding(.vertical, DS.Space.xxs)
                .background(DS.Palette.accent.opacity(0.12), in: Capsule())
            }
            .frame(minHeight: DS.Hit.min)
            .accessibilityLabel(idx >= 0 ? "本次开锁用第 \(idx + 1) 条 PIN, 点按更换" : "本次开锁用默认第一条 PIN, 点按更换")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.gutter)
    }

    /// 826 聚光教练标: 三个焦点 (圆盘 / 快捷格 / 状态卡) 依次聚光讲解, 点任意处推进, 末步写 kf_coach_done。
    /// 遮罩用**偶奇填充**挖洞 (Rect 减去 Ellipse), 不依赖 blendMode —— 后者在 overlay 里容易被合成层吃掉。
    /// 焦点位置是页面内的相对比例近似: 全仓没有 PreferenceKey 取锚点的先例, 为一次引导引入那套链不划算。
    @ViewBuilder
    private func coachOverlay(_ step: Int) -> some View {
        let items: [(title: String, body: String, y: CGFloat, r: CGFloat)] = [
            ("开锁圆盘", "按住圆盘或上滑即可开锁; 失败会给一份排查清单。", 0.46, 96),
            ("快捷操作格", "常用动作都在这里; 长按可换格。", 0.70, 76),   // 169 常用动作都在这里
            ("状态卡", "电量 / 固件 / 锁钟与连接态都在这张卡上。", 0.18, 108),   // 63/119/272 电量
        ]
        let it = items[min(step, items.count - 1)]
        GeometryReader { geo in
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height * it.y)
            ZStack {
                Canvas { ctx, size in
                    var p = Path(CGRect(origin: .zero, size: size))
                    p.addEllipse(in: CGRect(x: c.x - it.r, y: c.y - it.r, width: it.r * 2, height: it.r * 2))
                    ctx.fill(p, with: .color(.black.opacity(0.55)), style: FillStyle(eoFill: true))
                    let ring = Path(ellipseIn: CGRect(x: c.x - it.r, y: c.y - it.r, width: it.r * 2, height: it.r * 2))
                    ctx.stroke(ring, with: .color(.white.opacity(0.85)), lineWidth: 2)
                }
                .ignoresSafeArea()
                VStack(spacing: DS.Space.s) {
                    Text("第 \(step + 1)/\(items.count) 步 · \(it.title)")
                        .font(.subheadline.weight(.semibold))
                    Text(it.body)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(step + 1 < items.count ? "点任意处继续" : "点任意处开始使用")
                        .font(.caption2)
                        .foregroundStyle(DS.heroFg.opacity(0.8))
                }
                // 黑底卡上的前景走 heroFg (不是裸 .white): 它同时承担智能反转 (863) 的幂等色职责
                .foregroundStyle(DS.heroFg)
                .padding(DS.Space.l)
                .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .padding(.horizontal, DS.Space.l)
                .position(x: geo.size.width / 2, y: geo.size.height * (it.y > 0.5 ? it.y - 0.26 : it.y + 0.26))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if step + 1 < items.count { coachStep = step + 1 }
                else { DB.store.set("kf_coach_done", true); coachStep = nil }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("新手引导第 \(step + 1) 步: \(it.title)。\(it.body)。点任意处继续")
        }
    }
    private var bleOn: Bool { app.lock.connectedMAC == app.currentMac }
    // 包2/69 系统蓝牙开关 (btReady): 关时全 App 顶部出引导条; 与 bleOn (该锁会话) 区分
    private var btReady: Bool { bleSvc.isPoweredOn }
    /// 包2/64 三态: 当前锁链路 (非当前锁视为静态预览 → 未连接)
    private func linkState(for kc: Keychain) -> LinkState {
        guard kc.mac == app.currentMac else { return .down }
        return sense.linkState
    }
    // 1000 晚归欢迎语优先; 其次节气问候 (1001, 纯本地寿星公式); 再其次今天的启动一句话 (898)
    private var heroMomentText: String? {
        if let m = app.homeMoment { return m }
        if let term = Milestones.solarTermToday() { return "\(term) · " + Milestones.solarTermHint(term) }
        return Milestones.launchPhrase()
    }
    // 1004/114 低电判定 (0~20, 判定逻辑收敛到 BatteryCare)
    private func isLow(_ kc: Keychain) -> Bool { BatteryCare.isLow(batteryPct(for: kc)) }
    // 113 五档电量档位
    private func battTier(for kc: Keychain) -> BatteryCare.Tier { BatteryCare.tier(batteryPct(for: kc)) }
    /// 120: 告急档 (≤10) 染红, 低电档 (11–20) 染橙, 其余保持常规白。
    /// 染红不跟 tier.severe 走 — severe 现在管 ≤20 的整套降级, 红色仍只到 ≤10 (与 1004 的二级升级同界)。
    private func battTint(for kc: Keychain) -> Color? {
        if (0...10).contains(batteryPct(for: kc)) { return DS.Palette.danger }
        return isLow(kc) ? DS.Palette.warn : nil
    }
    /// 120 低电分级触感档位: 平时 "ok" / ≤20% "low" / ≤10% "sev" — 只有档位变化才响一次
    private func lowBucket(_ kc: Keychain) -> String {
        let p = batteryPct(for: kc)
        if p >= 0, p <= 10 { return "sev" }
        return isLow(kc) ? "low" : "ok"
    }
    private func batteryPct(for kc: Keychain) -> Int {
        if kc.mac == app.currentMac, let live = app.status?.powerLevel, live >= 0 { return live }
        // 包4: 统一走采样最新值 (读 03 即记录), 无采样才落回锁侧快照
        return BatteryCare.displayPct(kc.mac, snapshot: DB.readStatus(kc.mac)?.powerLevel ?? -1)
    }
    private func batteryText(for kc: Keychain) -> String {
        let p = batteryPct(for: kc)
        if p < 0 { return "--" }
        return p > 80 ? ">80%" : "\(p)%"
    }
    private func firmwareText(for kc: Keychain) -> String {
        if kc.mac == app.currentMac, let fw = app.status?.firmware, !fw.isEmpty { return fw }
        let fw = kc.fw.isEmpty ? (DB.readStatus(kc.mac)?.firmware ?? "") : kc.fw
        return fw.isEmpty ? "未知" : fw
    }
    private func lockClockText(for kc: Keychain) -> String {
        if kc.mac == app.currentMac, let lt = app.status?.lockTime { return ProtoTime.localStr(lt) }
        let t = DB.readStatus(kc.mac)?.lockTime ?? 0
        return t > 0 ? ProtoTime.localStr(t) : "--"
    }
    private var staleSync: Bool {
        let t = DB.syncTime(app.currentMac)
        guard t > 0 else { return false }
        return Date().timeIntervalSince1970 * 1000 - t > 30 * 86400 * 1000
    }
}

// ================= 校时页 (App synctime) =================
struct SyncTimeView: View {
    @EnvironmentObject var app: AppState
    @State private var busy = false
    @State private var result = ""
    @State private var failed = false

    private var resultTone: ToneColor { failed ? .danger : .ok }

    var body: some View {
        Form {
            Section {
                if app.current != nil {
                    Text("将手机时间同步到门锁内 (cmd 0E)。校准前会先读锁钟并补偿偏差。")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                    LabeledRow("锁钟", app.status?.lockTime.map { ProtoTime.localStr($0) } ?? "—")
                    LabeledRow("手机时间", DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))
                } else {
                    Text("请先在设备页选择一把门锁").foregroundStyle(DS.Palette.textSub)
                }
            } header: {
                Text("同步时间")
            }
            Section {
                BusyButton(title: "将手机时间同步到锁内",
                           systemImage: "clock.arrow.circlepath",
                           isBusy: busy,
                           disabled: app.current == nil) {
                    Task { await run() }
                }
                if !result.isEmpty {
                    Label(result, systemImage: failed ? "xmark.octagon.fill" : "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(resultTone.color)
                }
            } footer: {
                Text("请将手机靠近门锁 · 请确保手机时间准确")
            }
        }
        .navigationTitle("同步时间")
        .scrollContentBackground(.hidden)
        .dsScreenBackground()
    }

    private func run() async {
        busy = true
        failed = false
        result = ""
        // 第八十八批: 校时页原先不先绑锁就直接 syncTime (服务层按自己的 curMac 取钥)，
        // 于是"在这个锁的页面点校时，19/0E 命令发向上次连过的那把锁"。入口钉住 + 非空才走。
        let m = app.currentMac
        guard !m.isEmpty else {
            busy = false
            failed = true
            result = "未选择门锁"
            app.showToast("未选择门锁")
            return
        }
        do {
            try await app.lock.ensureConnected(mac: m)
            // 留存口径：校时这一步本机**不落任何数** —— 记录的时间戳本来就来自锁端回包 (lockTimeStr)，
            // 与手机钟无关；把它抄一份进本机反而造出第二个"现在是几点"。AutoOpen 那条自动校时走 audit (0E 双确认)。
            try await app.lock.syncTime()
            result = "同步成功"
            app.showToast("时间已同步")
        } catch {
            failed = true
            result = "同步失败：\(error.localizedDescription)"
        }
        busy = false
    }
}

/// 呼吸缩放 (1004 喂电提醒): reduceMotion 时静止
private struct BreathingGlyph: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var rm
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(on ? 1.12 : 1.0)
            .onAppear {
                guard !rm else { return }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

struct LabeledRow: View {
    var label: String
    var value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
            // 668: 这类"中文标签 + 英文缩写/数字"的行最容易看出中西文挤在一起, 统一走排版加距 (不插字符)
            cjkSpaced(label).foregroundStyle(DS.Palette.textSub)
            Spacer(minLength: DS.Space.m)
            cjkSpaced(value)
                .foregroundStyle(DS.Palette.text)
                .multilineTextAlignment(.trailing)
                .lineLimit(2) // MAC/时间等长值换行而不是溢出
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }
}

// ================= 81 全屏专注开锁 =================
// 只剩圆盘与状态文案的覆盖层, 手势/反馈与设备页完全同一份 UnlockDial。
struct FocusUnlockView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var lockSvc = LockService.shared
    @ObservedObject private var bleSvc = BLEService.shared

    var body: some View {
        ZStack {
            DS.Gradient.screen.ignoresSafeArea()
            VStack(spacing: DS.Space.l) {
                HStack(spacing: DS.Space.m) {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(app.displayName)
                            .font(.headline)
                            .foregroundStyle(DS.Palette.text)
                            .lineLimit(1)
                        Text(linkReady ? "已就绪 · 按住圆盘或上滑开锁" : "靠近门锁, 等待就绪")
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    Spacer(minLength: 0)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: DS.Icon.lg, weight: .medium))
                            .foregroundStyle(DS.Palette.textSub)
                            .frame(width: DS.Hit.min, height: DS.Hit.min)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel("退出专注模式")
                }
                Spacer(minLength: 0)
                UnlockDial(state: app.unlockState,
                           phase: app.phase,
                           connected: linkReady,
                           bleReady: bleSvc.isPoweredOn,
                           failStreak: app.failStreak,
                           retryText: retryText,
                           rssi: LinkSense.rssiFor(app.currentMac),
                           action: { app.requestUnlock() },
                           cancelAction: { app.cancelUnlock(notify: true) })
                Spacer(minLength: 0)
            }
            .padding(DS.Space.l)
        }
    }
    private var linkReady: Bool { lockSvc.connectedMAC == app.currentMac }
    private var retryText: String? {
        guard let w = app.retryWait else { return nil }
        return "第 \(app.retryAttempt) 次 · 等 \(w) 秒"
    }
}

// ================= 250 二次开锁应用锁闸 =================
// 同一锁 30 秒内再次开锁需先验证本机密码 (未设密码则无此闸)。
struct UnlockGateView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var pw = ""
    @State private var failed = false

    var body: some View {
        VStack(spacing: DS.Space.l) {
            Image(systemName: "lock.shield")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(DS.Palette.accentText)
                .frame(width: 84, height: 84)
                .axGlassCircle()
                .accessibilityHidden(true)
            VStack(spacing: DS.Space.s) {
                Text("30 秒内再次开锁")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(DS.Palette.text)
                Text("为防误触, 请先验证本机密码")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
            }
            TextField("本机密码", text: Binding(
                get: { pw },
                set: { pw = $0; if failed { withAnimation(DS.Motion.quick) { failed = false } } }))
                .textContentType(.password)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .padding(.vertical, DS.Space.m)
                .padding(.horizontal, DS.Space.l)
                // 2026-10-14 材质统一: 与 AppLock 的口令框同一枚材质/同一条降级通道 (原先两处各写实底)
                .axGlass(DS.Radius.control)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.control)
                        .strokeBorder(failed ? DS.Palette.danger : DS.Palette.hairline, lineWidth: 0.5)
                )
                .frame(maxWidth: 280)
                .submitLabel(.go)
                .onSubmit(verify)
            if failed {
                Label("密码错误, 请重新输入", systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.danger)
                    .transition(.opacity)
            }
            Button("验证并继续开锁", action: verify)
                .buttonStyle(PrimaryActionStyle())
                .frame(maxWidth: 280)
                .disabled(pw.isEmpty)
            Button("取消") { dismiss() }
                .buttonStyle(SecondaryActionStyle())
                .frame(maxWidth: 280)
            Spacer(minLength: DS.Space.xl)
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dsScreenBackground()
        .presentationDetents([.medium])
        .animation(DS.Motion.soft, value: failed)
    }

    private func verify() {
        guard !pw.isEmpty else { return }
        if DB.verifyPasscode(pw) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
            app.startUnlock()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            withAnimation(DS.Motion.quick) { failed = true }
            pw = ""
        }
    }
}