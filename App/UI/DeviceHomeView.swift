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
    @State private var refreshing = false
    @State private var showFocus = false      // 81 全屏专注开锁
    @State private var flipped = false        // 78 Hero 卡翻面
    @State private var reconnectDot = false   // 91 回连静默小点
    @State private var checks = [false, false, false]   // 87 排查清单勾选态
    // 包3 多锁导航: 101/763 横滑翻页 / 102 胶囊切换器 / 267 换锁二次确认 / 271 上滑默认 / 39 倒计时 / 112 换机向导
    @State private var pageIndex = 0
    @State private var pageOrder: [String] = []
    @State private var confirmMac: String?
    @State private var confirmPulse = false
    @State private var autoLockLeft: Int?
    @State private var wizardBusy = ""
    @State private var wizardDismissed = false
    @State private var showOverview = false
    @State private var showSettings = false   // 包8/507 备份角标跳转

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
                        heroPager.staggered(1)
                        attentionCard.staggered(2)
                        linkSenseCard.staggered(2)
                        unlockDial.staggered(3)
                        quickActions.staggered(4)
                        recentCard.staggered(5)
                        nightCheckRow.staggered(6)
                        familyCareRows.staggered(6)
                        privacyFootnote.staggered(6)
                    }
                }
                .padding(.vertical, DS.Space.m)
            }
            .dsScreenBackground()
            .navigationTitle(app.displayName)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { Task { await refresh() } } label: {
                        if refreshing { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(refreshing)
                    .accessibilityLabel("刷新门锁状态, 键盘 Cmd/Control+R")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("添加设备")
                }
            }
            .sheet(isPresented: $showAdd) { AddDeviceView() }
            // 包3: 全部锁总览与对比 (768/776/778/779/784/787/773)
            .sheet(isPresented: $showOverview) { LockOverviewView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
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
            .onChange(of: app.devices.count) { _ in syncPageOrder() }
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
                syncPageOrder()
                await refresh()
                sense.enterPage()   // 95 进页预热: 静默 ensureConnected + 93 信号围栏 + 96 只预热不执行
                // 包2/136 补充 跨页跳回: 记录/告警入口点"跳回设备页定位该锁"
                if let m = app.pendingJumpLock {
                    app.pendingJumpLock = nil
                    if m != app.currentMac {
                        app.select(m)
                    }
                    app.showToast("已定位到「" + app.displayName + "」 (136 跳回)")
                }
            }
        }
    }

    private func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        await app.refreshStatusQuietly()
        refreshing = false
        // 112: 迁移验证全部通过后清掉向导旗标 (下次恢复备份会重新立起)
        let flag = DB.store.getString("kf_migrate_pending")
        if !flag.isEmpty, !app.devices.isEmpty,
           app.devices.allSatisfy({ DB.store.getBool("kf_migok_" + $0.mac) }) {
            DB.store.remove("kf_migrate_pending")
        }
    }

    // ---------- 设备切换 (包3: 102 胶囊 + 101/763 横滑翻页 + 114 低电置顶 + 292 沉睡跳过) ----------
    /// 翻页顺序: 默认锁 (271) → 低电锁置顶 (114) → 绑定先后; 沉睡锁 (292) 不进横滑序列,
    /// 只从胶囊切换器可达 — 沉睡锁横滑过去大概率连不上, 徒增等待。
    private func syncPageOrder() {
        let def = LockArchive.defaultMac
        let byBatt = DB.store.getBool("kf_sort_batt")   // 1041 电量升序开关
        let lowFirst = app.devices.sorted { a, b in
            if !byBatt {
                if a.mac == def { return true }
                if b.mac == def { return false }
            }
            let la = isLow(a), lb = isLow(b)
            if la != lb { return la }   // 114 低电置顶
            if byBatt { return batteryPct(for: a) < batteryPct(for: b) }
            return a.pairedAt < b.pairedAt
        }
        pageOrder = lowFirst.filter { !LockArchive.isSleeping($0.mac) }.map { $0.mac }
        // 当前锁若已沉睡, 保留一页让它可见 (从胶囊选中的落点)
        if let cur = app.current, !pageOrder.contains(cur.mac) {
            pageOrder.append(cur.mac)
        }
        if let cur = app.current, let i = pageOrder.firstIndex(of: cur.mac) { pageIndex = i }
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
            Section("门锁") {
                ForEach(pagedLocks) { kc in
                    Button {
                        if kc.mac != app.currentMac { app.select(kc.mac) }
                    } label: {
                        HStack {
                            Circle().fill(LockArchive.swatchColor(LockArchive.meta(kc.mac).colorKey))
                                .frame(width: 8, height: 8)
                            Text(LockArchive.displayName(kc))
                            if isLow(kc) { Image(systemName: "battery.25percent").foregroundStyle(DS.Palette.warn) }
                            if LockArchive.isSleeping(kc.mac) { Image(systemName: "moon.zzz.fill").foregroundStyle(DS.Palette.textSub) }
                        }
                    }
                }
            }
            let sleepers = app.devices.filter { LockArchive.isSleeping($0.mac) }
            if !sleepers.isEmpty {
                Section("沉睡 (超 30 天未连接)") {
                    ForEach(sleepers) { kc in
                        Button {
                            app.select(kc.mac)
                        } label: {
                            HStack {
                                Circle().fill(LockArchive.swatchColor(LockArchive.meta(kc.mac).colorKey))
                                    .frame(width: 8, height: 8)
                                Text(LockArchive.displayName(kc))
                                Image(systemName: "moon.zzz.fill").foregroundStyle(DS.Palette.textSub)
                            }
                        }
                    }
                }
            }
            Divider()
            // 1041 电量优先排序: 先照顾最弱的
            Button {
                DB.store.set("kf_sort_batt", !DB.store.getBool("kf_sort_batt"))
                DS.Haptics.tick.impactOccurred()
                syncPageOrder()
            } label: {
                Label(DB.store.getBool("kf_sort_batt") ? "恢复绑定先后排序" : "按电量升序 (先照顾最弱)",
                      systemImage: "arrow.up.arrow.down")
            }
            Divider()
            Button { showOverview = true } label: {
                Label("全部锁总览与对比", systemImage: "chart.bar.horizontal")
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
            .background(DS.Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(DS.Palette.hairline, lineWidth: 0.5))
            // 视觉紧凑胶囊 + 44pt 命中区分离: 胶囊本身不必撑高
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("切换门锁, 当前 \(app.displayName)")
    }
    // 101/763/771: Hero 卡横滑翻页 — 圆盘与状态文本随卡片平行滑动交接 (TabView 原生平移)
    private var heroPager: some View {
        TabView(selection: $pageIndex) {
            ForEach(Array(pagedLocks.enumerated()), id: \.offset) { i, kc in
                statusCard(for: kc)
                    .padding(.horizontal, DS.Space.xs)
                    .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
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
        // 113 五档电量 / 120: 告急档 (≤10%) 关流光边并压亮度
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
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            // 774 场所副标题: 档案里填了场所就替代型号行
                            Text(LockArchive.subtitle(kc))
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            // 1000 晚归欢迎语 / 1001 节气问候 (只属于当前锁的活页面)
                            if isCurrent, let m = heroMomentText {
                                Text(m)
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.9))
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
                            ConnectMsBadge(ms: sense.connectMs)
                            // 268 状态变化历史: 长按胶囊弹出最近 5 次三态切换时间列表
                            .contextMenu {
                                Menu("最近状态变化 (268)") {
                                    ForEach(Array(LinkSense.history().enumerated()), id: \.offset) { _, h in
                                        Text(h.at + " " + h.to)
                                    }
                                }
                            }
                            // 91 回连静默小点
                            if reconnectDot {
                                Circle()
                                    .frame(width: 8, height: 8)
                                    .foregroundStyle(DS.Palette.ok)
                                    .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1))
                                    .transition(.opacity)
                                    .accessibilityHidden(true)
                            }
                            // 81 专注开锁入口 (原案"Hero 卡下拉"与纵向滚动手势冲突, 收敛为明确入口)
                            focusButton
                        } else {
                            HeroPill(text: "滑动到这页即连接", systemImage: "arrow.left.arrow.right",
                                     tint: .white.opacity(0.75))
                        }
                    }
                }
                HStack(spacing: DS.Space.s) {
                    // 电量是一级读数(它决定你还能不能开锁), 固件/锁钟是三级参考信息 —
                    // 三者同级会让人看不出重点
                    HeroStat(systemImage: battTier(for: kc).icon,
                             label: "电量",
                             value: batteryText(for: kc),
                             emphasized: true,
                             tint: battTint(for: kc))
                    HeroStat(systemImage: "memorychip",
                             label: "固件",
                             value: firmwareText(for: kc),
                             emphasized: false)
                    HeroStat(systemImage: "clock",
                             label: "锁钟",
                             value: lockClockText(for: kc),
                             emphasized: false)
                }
                // 982 开门里程碑: Hero 卡角标小旗 (全局计数, 只在当前页展示)
                if isCurrent, Milestones.unlockTotal >= 100 {
                    HStack {
                        HeroPill(text: "已守护 \(Milestones.unlockTotal) 次", systemImage: "flag.fill")
                        Spacer(minLength: 0)
                    }
                }
                // 包8/507 备份状态角标: 两态 (今日已备份 / 多日未备份), 点按跳设置-备份
                if isCurrent {
                    let bs = BackupStudio.badgeState
                    Button { showSettings = true } label: {
                        HStack(spacing: DS.Space.xs) {
                            Circle().fill(bs == .fresh ? DS.Palette.ok : .white)
                                .frame(width: 6, height: 6)
                            Text(bs == .fresh ? "今日已备份" : "多日未备份")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.92))
                        }
                        .padding(.horizontal, DS.Space.xs)
                        .padding(.vertical, DS.Space.xxs)
                        .background(.white.opacity(0.14), in: Capsule())
                    }
                    .frame(minHeight: DS.Hit.min)
                    .accessibilityLabel("备份状态角标 (507), 打开备份设置")
                }
                // 258 首连验证标记: 添加后完成一次开锁前, Hero 卡上挂着待验证提示
                if !LockArchive.isVerified(kc.mac) {
                    HStack(spacing: DS.Space.xs) {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: DS.Icon.sm, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .accessibilityHidden(true)
                        Text("链路待验证 · 成功开一次锁即打标")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.92))
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
                            .foregroundStyle(.white.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                // 116 换电图文引导: 电量告急 (≤10%) 时 Hero 卡直接给出入口
                if isCurrent, tier.severe {
                    NavigationLink { BatterySwapGuideView() } label: {
                        HStack(spacing: DS.Space.xs) {
                            Image(systemName: "arrow.right.circle")
                                .font(.system(size: DS.Icon.sm, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .accessibilityHidden(true)
                            Text("打开换电图文指引")
                                .font(.footnote)
                                .foregroundStyle(.white)
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
                            .foregroundStyle(.white.opacity(0.9))
                            .accessibilityHidden(true)
                        Text("低温季: 电池续航会缩短, 多留意电量")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
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

    // 78 翻面 (背面): 82 对勾弹出 + 本次开门摘要
    private var heroBack: some View {
        HeroCard(flair: Milestones.heroFlairActive) {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: DS.Icon.sm, weight: .semibold))
                        .foregroundStyle(.white)
                        // 82: 每次翻面弹性弹出一次
                        .symbolEffect(.bounce, value: flipped)
                    Text("已开锁")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Text(backSummary)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                Text("轻点翻回正面")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
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
        var rows: [(String, String, String, Bool)] = []   // (text, icon, toneKey, cached)
        if !btReady {
            rows.append(("系统蓝牙已关闭 — 打开后会自动重连 (69)", "antenna.radiowaves.left.and.right.slash", "warn", false))
        }
        if state == .down, sense.reconnectAttempt > 0, CredentialOrg.pendingCount(app.currentMac) > 0 {
            rows.append(("回连节律: " + nextLadderText, "arrow.clockwise", "accent", false))
        }
        // 535 同步回执: 最近一次补发 N 项, 2 分钟内淡出
        if sense.lastReceipt > 0, Date().timeIntervalSince(sense.receiptShownAt) < 120 {
            rows.append(("已同步 \(sense.lastReceipt) 项变更", "checkmark.circle.fill", "ok", false))
        }
        // 130 唤醒失败细分 (保守): 最近一次握手失败时给出三类归因 + 124 占用保守文案
        if state == .down, let last = lastWakeFail {
            rows.append(("唤醒失败 · \(last.name) — \(last.hint)", "exclamationmark.circle", "danger", false))
        }
        // 270/129 信号骤降预警: 最近 RSSI 走弱时建议靠近
        if let w = sense.weakSignalHint {
            rows.append((w, "antenna.radiowaves.left.and.right", "warn", false))
        }
        // 272 连接保持时长: 挂起过久提示重连
        if state == .ready, sense.holdMinutes >= 30 {
            rows.append(("连接已保持 \(sense.holdMinutes) 分钟 — 偏久, 可点刷新重连 (272)", "timer", "sub", false))
        }
        // 273 意图暂存: 断连且有排队变更时, 明示"已暂存, 回连续作"
        if state == .down, CredentialOrg.pendingCount(app.currentMac) > 0 {
            rows.append(("变更已暂存 — 回到锁旁会自动补发 (273)", "tray.full", "sub", false))
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
                                    .padding(.horizontal, 4).padding(.vertical, 1)
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
    private var nextLadderText: String { "第 \(sense.reconnectAttempt) 轮 · 下一轮等 " + String(nextLadderWait) + " 秒" }
    private var nextLadderWait: Int { Int(sense.nextLadderInterval()) }
    private var lastWakeFail: LinkSense.WakeReason? {
        // 130 细分: 取最近一条失败事件, 本地词表归三类; 124 占用细分协议未确证, 超时类走保守文案
        guard let ev = BleTelemetry.events.first(where: { !$0.ok }) else { return nil }
        if ev.what.contains("超时") {
            return LinkSense.WakeReason(name: "握手超时", hint: LinkSense.occupationHint())
        }
        if ev.what.contains("蓝牙") || ev.what.contains("权限") {
            return LinkSense.WakeReason(name: "蓝牙未开", hint: "打开系统蓝牙后会自动重连")
        }
        return LinkSense.WakeReason(name: "不在广播范围", hint: "走到门锁旁 1 米内再试")
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
        // 868 切换控制扫描组: 圆盘为独立扫描组, 外接开关逐项聚焦 (停留时长按 869 自定滑杆)
        VStack(spacing: DS.Space.m) {
            UnlockDial(state: app.unlockState,
                       phase: app.phase,
                       connected: bleOn,
                       bleReady: btReady,
                       failStreak: app.failStreak,
                       retryText: retryText,
                       batteryText: app.current.map { batteryText(for: $0) } ?? "未知",
                       action: { dialAction() },
                       cancelAction: { app.cancelUnlock(notify: true) })
            // 包15 字幕式过程条 (881): 连接/开锁过程逐字文案条给听障用户 (设置-辅助可关)
            if AXPrefs.captions {
                CaptionStepBar(phase: app.phase, unlockState: app.unlockState)
                    .transition(.opacity)
            }
            .axOnehand()   // 873/60 单手下沉: 圆盘区整体下移入拇指区
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
        }
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
                        .background(DS.Palette.surface, in: Capsule())
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
            if !pending.isEmpty, app.devices.count > 1 {
                Card {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        HStack {
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
                .foregroundStyle(.white)
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
                    quickLink(icon: "plus.rectangle.on.rectangle", label: "添加密码") { AddPwdView(embedded: true) }
                    quickLink(icon: "clock.badge.questionmark", label: "临时密码") { SafemodeIntroView(mode: "otp") }
                    quickLink(icon: "clock.arrow.circlepath", label: "校准时间") { SyncTimeView() }
                    quickLink(icon: "finger.print", label: "录指纹") { StartAddFpView(embedded: true) }
                    // 包5: 凭证工坊 (177 扇出, 密码/临时码/指纹/OTP 四类)
                    quickLink(icon: "wrench.and.screwdriver", label: "凭证工坊") { StudioHome(embedded: true) }
                    // 包13/475: 家庭便签格 (一行本地文本, 与成员绑定, 保存后 Hero 卡下浮动显示)
                    quickLink(icon: "note.text", label: "家庭便签") { FamilyNoteView() }
                }
            }
        }
    }
    private func quickLink<Content: View>(icon: String, label: String, @ViewBuilder content: () -> Content) -> some View {
        NavigationLink { content() } label: {
            VStack(spacing: DS.Space.s) {
                // 图标坐进主色 12% 的圆角底座: 四个入口有了统一的"图标 + 玻璃砖"节奏
                Image(systemName: icon)
                    .font(.system(size: DS.Icon.md, weight: .semibold))
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(width: 40, height: 40)
                    .background(DS.Palette.accentText.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                Text(label)
                    .font(.caption)
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
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(label)
    }

    // ---------- 最近开门 ----------
    private var recentCard: some View {
        let rows = app.recentRecords()
        return Card {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                SectionTitle(text: "最近开门", count: rows.count)
                if rows.isEmpty {
                    Text("还没有开门记录。门锁有新动静时会出现在这里。")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: DS.Space.s) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
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
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
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

    // ---------- 包13 家庭关怀行 (485 生日 / 480 孩子码 / 475 家庭便签): 当前锁的活页面 ----------
    @ViewBuilder
    private var familyCareRows: some View {
        let care = MemberHub.careDue(app.currentMac)
        if let c = care.first {
            let note = MemberHub.ext(c.member.id).careText
            Card(tint: .warn) {
                HStack(spacing: DS.Space.s) {
                    MemberAvatar(member: c.member)
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text("「" + MemberHub.display(c.member) + "」的临时码还有 " + String(c.days) + " 天到期 (480)")
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
        if let b = Milestones.birthdayCelebrantToday {
            Card {
                HStack(spacing: DS.Space.s) {
                    MemberAvatar(member: b)
                    Text("今天是" + MemberHub.display(b) + "的生日, 替我们说声生日快乐 (485)")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.accentText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .frame(minHeight: DS.Hit.min)
            }
        }
        // 475 家庭便签: 设备页 Hero 卡下浮动一行 (与成员绑定)
        let notes = DB.members().compactMap { m -> (Member, String)? in
            let n = MemberHub.ext(m.id).note
            return n.isEmpty ? nil : (m, n)
        }
        if !notes.isEmpty {
            Card {
                ForEach(notes, id: \.0.id) { m, note in
                    HStack(spacing: DS.Space.s) {
                        MemberAvatar(member: m, size: 22)
                        Text(MemberHub.display(m) + " 的便签: " + note)
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
                    Text("本周主责: " + MemberHub.display(dm) + " (481)")
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
    private var bleOn: Bool { app.lock.connectedMAC == app.currentMac }
    // 包2/69 系统蓝牙开关 (btReady): 关时全 App 顶部出引导条; 与 bleOn (该锁会话) 区分
    private var btReady: Bool { bleSvc.isPoweredOn }
    /// 包2/64 三态: 当前锁链路 (非当前锁视为静态预览 → 未连接)
    private func linkState(for kc: Keychain) -> LinkState {
        guard kc.mac == app.currentMac else { return .down }
        return sense.linkState
    }
    // 1000 晚归欢迎语优先; 其次节气问候 (1001, 纯本地寿星公式)
    private var heroMomentText: String? {
        if let m = app.homeMoment { return m }
        if let term = Milestones.solarTermToday() { return "\(term) · " + Milestones.solarTermHint(term) }
        return nil
    }
    // 1004/114 低电判定 (0~20, 判定逻辑收敛到 BatteryCare)
    private func isLow(_ kc: Keychain) -> Bool { BatteryCare.isLow(batteryPct(for: kc)) }
    // 113 五档电量档位
    private func battTier(for kc: Keychain) -> BatteryCare.Tier { BatteryCare.tier(batteryPct(for: kc)) }
    /// 120: 告急档染红, 低电档染橙, 其余保持常规白
    private func battTint(for kc: Keychain) -> Color? {
        let t = battTier(for: kc)
        if t.severe { return DS.Palette.danger }
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
        do {
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
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(DS.Palette.textSub)
            Spacer(minLength: DS.Space.m)
            Text(value)
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
                .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.control))
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