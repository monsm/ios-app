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
    // 2026-10-29：锁设置 sheet（B 档）—— 设备页工具栏齿轮打开
    @State private var showLockSettings = false
    @State private var refreshing = false
    @State private var reconnectDot = false   // 91 回连静默小点
    @State private var checks = [false, false, false]   // 87 排查清单勾选态
    // 包3 多锁导航: 101/763 横滑翻页 / 102 胶囊切换器 / 267 换锁二次确认 / 271 上滑默认 / 39 倒计时 / 112 换机向导
    @State private var pageIndex = 0
    // 2026-10-29 修（**两处联动**）：pageOrder 原来是 @State 却**从未赋值**（只有 firstIndex 读点），
    // 恒空数组 ⇒ 换锁时永远走「不在翻页序列」分支。同时 groupFilter 只被 chip 写、**没人读**
    // （唯一读它的 inGroup 零调用）⇒ 组筛选点了没反应。改成从 app.devices 经 inGroup 派生，
    // 一次修好两处：组 chip 真生效，翻页序列也跟着过滤后的顺序走。
    private var pageOrder: [String] {
        app.devices.filter { inGroup($0) }.map { $0.mac }
    }
    // 767 设备 Tab 按组切换: "" = 全部组。只影响"这一屏看得见哪些锁", 不动档案也不动数据。
    @State private var groupFilter = ""
    @State private var confirmMac: String?
    @State private var confirmPulse = false
    @State private var autoLockLeft: Int?
    // 同屏提醒要按预算排位，视图层的 @State 预算读不到。判据一字未改，只是换了存放处。
    @State private var showRssi = false   // 63 点信号格弹出 dBm 数值 (格数看不出 1 格还是 2 格时看数字化)
    // 乱源治理第 3 批: 设备页模块显隐。默认空集 = 一块都不隐 (拍板口径), 面板只给能力不给默认。
    @State private var devHidden = DevModuleStore.hidden
    /// 这一块现在该不该画 (必留的五块不走这里, 见 DevModules 文件头)
    private func shown(_ m: DevModule) -> Bool { !devHidden.contains(m.rawValue) }

    var body: some View { vkBody.destined(.deviceHome) }
    var vkBody: some View {
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
                    // 2026-10-29：锁设置入口（齿轮放工具栏，不放 Hero 卡 —— 卡内 .accessibilityElement(.combine) 会吞按钮）
                    ToolbarItem(placement: barSide) {
                        Button { showLockSettings = true } label: { Image(systemName: "gearshape") }
                            .accessibilityLabel("锁设置")
                    }
                        .accessibilityLabel("添加设备")
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
    private func inGroup(_ kc: Keychain) -> Bool {
        if groupFilter.isEmpty { return true }
        let g = LockArchive.group(kc.mac)
        return groupFilter == LockArchive.ungroupedLabel ? g.isEmpty : g == groupFilter
    }
    /// 图标行的锁集: 组过滤后**全部**可见 (含沉睡/隐藏) — 它是"看一眼有没有事"的面,
    /// 把沉睡锁藏起来正好会让最该被看见的那把消失。
    /// 229 左手模式：工具条两侧对调、快捷格顺序镜像（常用那格落到拇指侧）。
    /// （左手模式已于 2026-10-26 删除，工具栏位置/次序现为恒定。）此前它被设置页读写、
    /// 全仓没有任何消费者 —— "镜像"是两个只改自己标签的按钮之一，这两行把它接上。
    private var barSide: ToolbarItemPlacement {
        .navigationBarTrailing
    }
    private var tiles: [QuickAction] {
        let o = QuickPool.ordered()
        return o
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
            DS.Haptics.tick.impactOccurred()
        } label: {
            Text(label)
                .vkFont(.subheadline, weight: .medium)
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


    // 243 断连灰化: 连接断开时整卡去饱和, 恢复即回彩
    // 包3: 参数化到任意锁 — 当前页吃实时状态, 其余页读各锁快照 (101/763 横滑预览)
    private func heroCard(for kc: Keychain, isCurrent: Bool) -> some View {
        let connected = isCurrent && bleOn
        // 113 五档电量 / 120: 低电降级档 (≤20%) 关流光边并压亮度, 动效令牌同步降 calm
        let tier = BatteryCare.tier(batteryPct(for: kc))
        return HeroCard {
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
                                .vkFont(.title3, weight: .semibold)
                                .foregroundStyle(DS.heroFg)
                                .lineLimit(1)
                                // 2026-10-27 截图核对修复：这个 HStack 右侧是 LinkPill（很宽的胶囊），
                                // 左侧名称只有 `.lineLimit(1)` 没有布局优先级 —— 于是被挤成「智能...」。
                                // 给名称更高的优先级，压缩时优先压右侧胶囊而不是锁名。
                                .layoutPriority(1)
                            // 774 场所副标题: 档案里填了场所就替代型号行
                            Text(LockArchive.subtitle(kc))
                                .vkFont(.footnote)
                                .foregroundStyle(DS.heroFg.opacity(0.9))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
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
                                        Text(sense.lastRssi.map { "\($0) dBm" } ?? "未读到信号")
                                            .vkFont(.caption2.monospacedDigit())
                                            .foregroundStyle(DS.heroFg)
                                            .padding(.horizontal, DS.Space.xs)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(.black.opacity(0.55)))
                                            .offset(y: -18)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .accessibilityLabel(isCurrent
                                    ? (sense.lastRssi.map { "信号 \($0) dBm, 轻点显示数值" } ?? "信号未读到")   // 63 信号
                                    : "信号")
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
                        } else {
                            HeroPill(text: "滑动到这页即连接", systemImage: "arrow.left.arrow.right",
                                     tint: DS.heroFg.opacity(0.75))
                        }
                    }
                }
                    // 电量是一级读数(它决定你还能不能开锁), 固件/锁钟是三级参考信息 —
                    // 三者同级会让人看不出重点
                    HStack(spacing: DS.Space.s) {
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
                    // 2026-10-29 补：APK `OpendevicePage` 有「钥匙有效期」横幅（`bleKeyValid`，`dState=1`
                    // 显示 createTime~expireTime，等于永久则显示"永久"）。iOS 没有云端下发的这两个字段 ——
                    // 本机 ekey 全部由 `buildEkeyOpen` 用 "2010-01-01 ~ 2118-01-01" 签发，所以如实写「永久」，
                    // 不编一个假日期；没有 ekey 时写「未生成」（与「链路验证」同一条"读不到就说读不到"的口径）。
                    HeroStat(systemImage: "key.horizontal",
                             label: "钥匙",
                             value: kc.ekey.isEmpty ? "未生成" : "永久",
                             emphasized: false)
}   // 2026-10-27 三轮：原 statsLayout 降级布局已删，恒横排
                // 790 最近活跃成员头像圈: 卡角叠放最近活跃 3 位, 点开列成员名, 选谁直接查谁的记录。
                if isCurrent {
                    HStack(spacing: DS.Space.s) {
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .saturation(connected ? 1 : 0.55)
        .brightness(tier.severe ? -0.06 : 0)   // 120 低电视觉降级
        // 847 Hero 卡合并播报: 单元素合读 连接态+电量 (盲文简写 856)
        .accessibilityElement(children: .combine)
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
                                .vkFont(.footnote)
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
        // 2026-10-28 补入口：`CredentialOrg.dueSoonPwds` 实现了「到期前 2 小时且开了 h2 提醒」
        // 这一档（注释里明写"设备 Tab Hero 卡下插提醒行"），但全仓零调用 ——
        // 用户开了"2 小时前提醒"却永远收不到这一行。现在接上。
        // 只报条数、不点名（详情在凭证页），避免这张卡变成第二份凭证列表。
        if let kc = app.current {
            let due = CredentialOrg.dueSoonPwds(kc.mac)
            if !due.isEmpty {
                out.append(("有 \(due.count) 条凭证将在 2 小时内到期（最近一条 #\(due[0].alias)）—— 需要续期请到凭证页",
                            "clock.badge.exclamationmark.fill", .warn))
            }
        }
        // 1023 指纹头清洁: 连续 3 次指纹识别告警
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
                                .vkFont(.footnote)
                                .foregroundStyle(r.3 ? DS.Palette.textSub : DS.Palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                            if r.3 {
                                Text("缓存")
                                    .vkFont(.caption2, weight: .medium)
                                    .foregroundStyle(DS.Palette.textSub)
                                    .padding(.horizontal, 4).padding(.vertical, DS.Space.xxs)
                                    .variantPlate(DS.Palette.surfaceAlt, .capsule)
                            }
                            Spacer(minLength: 0)
                        }
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
        // 2026-10-27 四轮精简：弱信号提示已删（weakSignalHint 移除）。
        // 272 连接保持时长: 挂起过久提示重连
        if state == .ready, sense.holdMinutes >= 30 {
            rows.append(("连接已保持 \(sense.holdMinutes) 分钟 — 偏久, 可点刷新重连", "timer", "sub", false))   // 272 连接已保持
        }
        // 273 意图暂存: 断连且有排队变更时, 明示"已暂存, 回连续作"
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
        // 2026-10-27 审核修复：这个分支原先是空的，协议/会话失败会落进下面的兜底
        // 「不在广播范围」—— 用户看到"走到门锁旁 1 米内再试"，跑到门边也没用（锁的问题是协议层）。
        if ev.what.contains("协议类") || ev.what.contains("会话重协商失败") {
            return LinkSense.FailKind(
                name: "锁端未应答协议",
                hint: "门锁回了帧但内容对不上 — 先校准锁内时间；仍不行就重启门锁电池")
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


    // ---------- 开锁主控 ----------
    private var unlockDial: some View {
        // 868 切换控制扫描组: 圆盘为独立扫描组 (调用处 `unlockDial` 后面那两行
        // `.accessibilityElement(children: .contain)` + `accessibilityLabel("开锁圆盘组")`), 外接开关可以按组逐项聚焦。⚠ 2026-10-15 走查修正: 这里原先写着"停留时长按 869 自定滑杆" —— 那枚滑杆
        // (`kf_ax_dwell`) 全仓**没有行为消费者**，只被辅助页的滑杆自己与练习区演示文字读 (判据见
        // 聚焦节奏实际由系统 VoiceOver/切换控制决定。
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
            CaptionStepBar(phase: app.phase, unlockState: app.unlockState)
                .transition(.opacity)
            // 39 自动上锁倒计时 (协议 cmd24 档位的本地回放, 不虚构门磁): 开锁成功后提醒关手
            if let left = autoLockLeft {
                Label("约 \(left) 秒后自动上锁 · 请确认门已关好", systemImage: "timer")
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.accentText)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                    .accessibilityLabel("自动上锁倒计时 \(left) 秒, 请确认门已关好")
            }
            if !btReady {
                Text("打开系统蓝牙后即可开锁")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
            } else if !bleOn {
                Text("未连接时点击会自动唤醒门锁蓝牙")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
            }
            // 88 临时码备援: BLE 反复失败时, 已开通的临时码可在锁键盘直接输入 (纯提示, 不涉协议)
            if app.failStreak >= 2, DB.otpStatus(app.currentMac)?.on == true {
                Label("蓝牙连不稳? 已开通的临时码可直接在门锁键盘输入开门", systemImage: "keyboard")
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.accentText)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            // 1003 安慰式报错: 一次失败轻声安慰, 三次后给可勾排查清单 (87)
            if app.failStreak > 0 {
                VStack(spacing: DS.Space.xs) {
                    Text(app.failStreak < 3 ? "再试一次, 别着急" : "连着几次没成, 逐项自查一遍:")
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if app.failStreak >= 3 {
                        checklist
                    }
                }
                .transition(.opacity)
            }
            // 83: 自动重试 (2s/5s) 用尽进入终态失败 → 圆盘下方主按钮手动再试
            // (超时失败不涨 failStreak, 所以钩在 .failed 上, 不能挂进上面 failStreak 块)
            if case .failed = app.unlockState {
                Button("再试一次") { dialAction() }
                    .vkFont(.subheadline, weight: .semibold)
                    .foregroundStyle(DS.Palette.accentText)
                    .padding(.horizontal, DS.Space.xl)
                    .frame(minHeight: DS.Hit.min)
                    .variantPlate(DS.Palette.accentText.opacity(0.12), .capsule)
                    .buttonStyle(PressableButtonStyle())
            }
        }
        .axOnehand()   // 873/60 单手下沉: 圆盘区整体下移入拇指区
                       // (挂在整个圆盘区 VStack 上 —— 原先误挂在一个条件分支后（if AXPrefs.captions，该开关已于 2026-10-26 删除）,
                       //  那是把修饰符接在 if 语句上, 编译器按隐式成员解析报 "cannot be used on type 'View'")
        .padding(.vertical, DS.Space.l)
        .animation(DS.Motion.soft, value: app.failStreak)
        .animation(DS.Motion.soft, value: autoLockLeft)
        // 267 换锁二次确认: 横滑换锁后第一次点圆盘 → 放大的锁名胶囊提示, 再点才执行
        .overlay {
            if confirmPulse {
                VStack(spacing: DS.Space.xs) {
                    Text("即将开锁")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                    Text(app.displayName)
                        .vkFont(.headline)
                        .foregroundStyle(DS.Palette.accentText)
                        .padding(.horizontal, DS.Space.l)
                        .padding(.vertical, DS.Space.s)
                        // 2026-10-18 表面预算: **玻璃不叠玻璃** (MASTER.md §3.1 的 0 预算)。
                        // 外层卡片已经是 axGlass, 内层胶囊再上玻璃就是两层材质叠一起 ——
                        // 观感上只是更糊, 信息上什么也没增加。改成实底 + accent 描边:
                        // 那圈 1.5pt 是"还没执行, 再点才开锁"的告警边, 属于信息不是装饰, 保留。
                        .variantPlate(DS.Palette.surfaceAlt, .capsule)
                        .overlay(Capsule().strokeBorder(DS.Palette.accent, lineWidth: 1.5))
                        .scaleEffect(confirmPulse ? 1.06 : 1)
                    Text("再点一次圆盘开始开锁")
                        .vkFont(.caption)
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
                            .vkFont(.footnote)
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

    // 2026-10-27 三轮精简：focusButton（专注开锁入口）已删。

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
                                    // 2026-10-28 界面审核修复：这里原本是空的 Button 动作 ——
                                    // 「编辑快捷操作格」点了什么都不发生。而上方注释还写着"面板内改动即时生效"，
                                    // 说明面板本该存在，只是调用被删空了。
                                    // 现在接到模块排序与显隐面板（同一张面板，快捷格顺序也在里面调）。
                                    Button {
                                        DS.Haptics.tick.impactOccurred()
                                        showModuleOrder = true
                                    } label: {
                                        Label("编辑快捷操作格", systemImage: "square.grid.2x2")   // 905 编辑快捷操作格
                                    }
                                }
                        } else {
                            quickLink(icon: a.icon, label: a.label,
                                      onTap: {
                                          // 1047: 静默记一次本机点击 (手动关过开关即停记, 见 QuickPool.recordingOn)
                                          QuickPool.recordTap(a.id)
                                      }
                            ) { quickDestination(a.id) }
                            // 905: 长按任一格 → 编辑面板。走系统 contextMenu 而不是自挂长按手势:
                            // 与 NavigationLink 的点击零冲突 (同 740 "长按走菜单"的先例), 面板内改动即时生效。
                            .contextMenu {
                                // 2026-10-28 界面审核修复：这里原本是空的 Button 动作 ——
                                // 「编辑快捷操作格」点了什么都不发生。而上方注释还写着"面板内改动即时生效"，
                                // 说明面板本该存在，只是调用被删空了。
                                // 现在接到模块排序与显隐面板（同一张面板，快捷格顺序也在里面调）。
                                Button {
                                    DS.Haptics.tick.impactOccurred()
                                    showModuleOrder = true
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
                                    .vkFont(.caption2)
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
        }
    }
    /// 905/1047: `onTap` 是给 1047 记频次用的**可选**回调。
    /// 用 simultaneousGesture 而不是把 NavigationLink 换成 Button：换掉就会丢导航，
    /// 而 simultaneousGesture 让点击既走导航又能记账。传 nil 时一个手势都不加。
    private func quickLink<Content: View>(icon: String, label: String,
                                          onTap: (() -> Void)? = nil,
                                          @ViewBuilder content: () -> Content) -> some View {
        // 2026-10-17 真机勘误「首页快捷操作点了没反应」: 记账原先是挂在 NavigationLink 的 **label**
        // 上的 simultaneousGesture(TapGesture) —— 同一次点击被两个手势系统抢 (label 的 Tap 与
        // NavigationLink 自身的激活), 结果就是"次数记上了、页面没进去"。label 现在零手势,
        // 记账挪到**目的地出现时**, 语义也更准 (用过这一格 = 进过它的页面)。
        NavigationLink {
            content().onAppear { onTap?() }
        } label: {
            quickTileBody(icon: icon, label: label)
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
                .vkFont(big ? .callout : .caption)
                .foregroundStyle(DS.Palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: DS.Hit.min + DS.Space.xl)
        .padding(.vertical, DS.Space.m)
        // 2026-10-18 表面预算 (MASTER.md §3.1): 快捷格是 **4 格一屏的网格**,
        // 每格都上玻璃 = 同屏 4 层玻璃面, 直接把「同屏 ≤3」顶穿。
        // 改成实底 + hairline 描边: 4 格之间仍有清晰的块面节奏, 但不再叠材质。
        // 用语法层的 variantPlate (它同时管底衬 + 可选发丝描边), 而不是自己写 background/overlay:
        // ① 自绘预算只认字面 token, 走语法层才不会被计成"新写的盒子";
        // ② `.overlay(.rect(...))` 里 `.rect` 会被推断成 ShapeStyle 而报
        //    "type 'ShapeStyle' has no member 'rect'" —— 这是 CI run 39107518727 抓到的真实编译错误。
        .variantPlate(DS.Palette.surface, .tile, edge: DS.Palette.hairline)
        .contentShape(Rectangle())
    }

    /// 921「再开一次」格: 目标 = QuickPool.repeatTarget (星标密码 > 星标指纹 > 高频推断)。
    /// 星标集为空且推不出一条时, 点按给"先去点亮星标"的指路 toast —— 不猜、不假装能开。
    @ViewBuilder
    private var againTile: some View {
        let target = QuickPool.repeatTarget(app.currentMac)
        Button {
            QuickPool.recordTap("again")
            if let t = target {
                app.pendingCredNav = t.nav
                app.pendingCredNavMac = app.currentMac
                app.requestRoute(.credentials)   // 2026-10-14 走查: 原为直写 tabSelection, 访客态会绕过 377 门禁
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




    /// 559 落地: 「最近开门」行上可证明的成员 → 记录 Tab 并按该成员过滤。
    /// 复用 582 的 pendingRecordsMember → landMember 链路 (记录页消费后清空, 不残留过滤)。
    // 【保留未接 2026-10-29】「最近开门」行点成员 → 跳记录页按 TA 过滤（配套 provableMemberId/mergedLine）
    private func openMemberRecords(_ id: String) {
        app.pendingRecordsMember = id
        app.requestRoute(.records)
    }


    // ---------- 派生数据 (包3: 参数化到任意锁 — 当前页吃实时, 其余页读快照) ----------
    /// 826 聚光教练标: nil = 不显示; 0/1/2 = 当前焦点序号 (只在首进设备 Tab 时出现一次)
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
            quickActions
                .accessibilityElement(children: .contain)
                .accessibilityLabel("快捷操作格组")   // 868 快捷操作格组
        // 2026-10-28 修复：原来这个 switch 只判 "quick"，
        // devOrder 默认是 ["hero","quick","recent"] ⇒ hero 与 recent **都落 default 画成 heroCard**，
        // 同屏两张几乎相同的身份卡，而「最近开门」模块根本不存在。
        // 现在三个槽各有各的渲染器。
        case "hero":
            if let kc = app.current {
                heroCard(for: kc, isCurrent: true)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("状态卡组")
            }
        case "recent":
            recentModule
        default:
            EmptyView()
        }
    }

    /// 2026-10-28 新增：「最近开门」模块（devOrder 的第三个槽）。
    /// 数据来自 `app.recentRecords()` —— 那个方法早就实现了（含成员归属推断与告警标红），
    /// 但全仓零调用；`kf_recent_count`（设置-外观「最近开门条数」3/5/10）也因此一直空转。
    private var recentModule: some View {
        let rows = app.recentRecords()
        return VStack(alignment: .leading, spacing: DS.Space.m) {
            SectionTitle(text: "最近开门")
                .padding(.horizontal, DS.Space.gutter)
            Card {
                if rows.isEmpty {
                    Text("还没有开门记录。连上锁后到「记录」页拉取一次。")
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                                Image(systemName: r.warn ? "exclamationmark.triangle.fill" : "door.left.hand.open")
                                    .font(.system(size: DS.Icon.sm, weight: .semibold))
                                    .foregroundStyle(r.warn ? DS.Palette.danger : DS.Palette.textSub)
                                    .accessibilityHidden(true)
                                Text(r.text)
                                    .vkFont(.footnote)
                                    .foregroundStyle(DS.Palette.text)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                // 2026-10-29 补（**后台有实现、前台一直零调用**）：`openMemberRecords` 就是给这行用的 ——
                                // `recentRecords()` 已带出 `whoId`（只在归属**可证明**时才带），这里接成可点：
                                // 点成员行 → 记录页按 TA 过滤。不可证明的行不响应（不猜、不弹"未知成员"）。
                                .contentShape(Rectangle())
                                .onTapGesture { if let id = r.whoId { openMemberRecords(id) } }
                                .accessibilityHint(r.whoId == nil ? "这条记录的归属推断不出来，不能按成员筛选" : "查看这位成员的全部记录")
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, DS.Space.gutter)
        }
    }
    private var moduleOrderSheet: some View {
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


    private var bleOn: Bool { app.lock.connectedMAC == app.currentMac }
    // 包2/69 系统蓝牙开关 (btReady): 关时全 App 顶部出引导条; 与 bleOn (该锁会话) 区分
    private var btReady: Bool { bleSvc.isPoweredOn }
    /// 包2/64 三态: 当前锁链路 (非当前锁视为静态预览 → 未连接)
    /// 链路三态 + 「密钥未绑定」。
    ///
    /// 2026-10-27 截图核对修复：原实现只返回 `sense.linkState`（纯 BLE 连接态），
    /// 于是蓝牙连着就显示「门锁在线，随时可开」，而同一屏的黄条又说「密钥尚未绑定」。
    /// 密钥没绑定 ⇒ 签不出开锁凭据 ⇒ **开不了**。现在把 sKeyStatus 纳入判据：
    /// 连着但密钥未绑定 ⇒ `.notReady`，徽章文案随之改成「密钥未绑定」而不是「随时可开」。
    private func linkState(for kc: Keychain) -> LinkState {
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
    private func isLow(_ kc: Keychain) -> Bool { BatteryCare.isLow(batteryPct(for: kc)) }
    // 113 五档电量档位
    private func battTier(for kc: Keychain) -> BatteryCare.Tier { BatteryCare.tier(batteryPct(for: kc)) }
    /// 120: 告急档 (≤10) 染红, 低电档 (11–20) 染橙, 其余保持常规白。
    /// 染红不跟 tier.severe 走 — severe 现在管 ≤20 的整套降级, 红色仍只到 ≤10 (与 1004 的二级升级同界)。
    private func battTint(for kc: Keychain) -> Color? {
        if (0...10).contains(batteryPct(for: kc)) { return DS.Palette.danger }
        return isLow(kc) ? DS.Palette.warn : nil
    }
    private func batteryPct(for kc: Keychain) -> Int {
        // 包4 + 2026-10-15 走查: 读数与写法都收进 BatteryCare.facePct/faceText, 这里只留"实时读数只属于当前这把"这一条判据
        // —— 专注模式那块的圆盘以前拿不到这个式子, 转子播电量时只会念"未知"。
        BatteryCare.facePct(kc.mac, live: kc.mac == app.currentMac ? (app.status?.powerLevel ?? -1) : -1)
    }
    private func batteryText(for kc: Keychain) -> String {
        BatteryCare.faceText(batteryPct(for: kc))
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
    /// 2026-10-27 (D-50)：冷却剩余秒数（0 = 无冷却）。
    @State private var coolLeft = 0

    private var resultTone: ToneColor { failed ? .danger : .ok }

    var body: some View { vkBody.destined(.syncTime) }
    var vkBody: some View {
        Form {
            Section {
                if app.current != nil {
                    Text("将手机时间同步到门锁内 (cmd 0E)。校准前会先读锁钟并补偿偏差。")
                        .vkFont(.footnote)
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
                        .vkFont(.footnote)
                        .foregroundStyle(resultTone.color)
                }
            } footer: {
                Text("请将手机靠近门锁 · 请确保手机时间准确")
            }
        }
        .navigationTitle("同步时间")
        .variantList()
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
        .vkFont(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }
}


// ================= 250 二次开锁应用锁闸 =================
// 同一锁 30 秒内再次开锁需先验证本机密码 (未设密码则无此闸)。
struct UnlockGateView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var pw = ""
    @State private var failed = false
    /// 2026-10-27 (D-50)：冷却剩余秒数（0 = 无冷却）。
    @State private var coolLeft = 0

    var body: some View { vkBody.destined(.unlockGate) }
    var vkBody: some View {
        VStack(spacing: DS.Space.l) {
            Image(systemName: "lock.shield")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(DS.Palette.accentText)
                .frame(width: 84, height: 84)
                .axGlassCircle()
                .accessibilityHidden(true)
            VStack(spacing: DS.Space.s) {
                Text("30 秒内再次开锁")
                    .vkFont(.title3, weight: .semibold)
                    .foregroundStyle(DS.Palette.text)
                Text("为防误触, 请先验证本机密码")
                    .vkFont(.footnote)
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
            // 2026-10-27 (D-50)：冷却中优先显示冷却提示（比「密码错误」更准确 —— 这次根本没验）
            if coolLeft > 0 {
                Label("尝试次数过多，请等 \(coolLeft) 秒", systemImage: "clock.badge.exclamationmark")
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.warn)
                    .transition(.opacity)
            } else if failed {
                Label("密码错误, 请重新输入", systemImage: "exclamationmark.circle.fill")
                    .vkFont(.footnote)
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
        // 2026-10-27 审核修复 (AUDIT-D D-50)：接上失败计数与冷却。
        // 原先失败只清空输入框，可无限重试 —— 4 位数字码人工 1 万次可穷举，
        // 脚本化更快（本机 UI 没有系统级节流）。
        // 冷却梯度与 LockScreen 同一套（AppLock.cooldownSeconds）：3 次→30s，5 次→5min，7 次→30min。
        let lock = AppLock.shared
        let left = lock.cooldownRemaining()
        if left > 0 {
            coolLeft = left
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            withAnimation(DS.Motion.quick) { failed = true }
            pw = ""
            return
        }
        if DB.verifyPasscode(pw) {
            coolLeft = 0
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
            app.startUnlock()
        } else {
            // 走同一套计数：`recordFailure()` 会更新 failStreak 与 cooldownUntil
            coolLeft = lock.recordFailure()
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            withAnimation(DS.Motion.quick) { failed = true }
            pw = ""
        }
    }
}