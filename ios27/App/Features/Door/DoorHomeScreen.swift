// DoorHomeScreen.swift —— 门（Tab 1）· V8 设计语言
//
// 与 DoorScreen 的功能对齐（数据绑定一致：AppModel.lock / dialPhase / entries、LinkSenseModel、QuickPool）。
// 结构（对应参考图 P2 型）：芯片行 → 电量环（英雄）→ 判断句 → 因果段 → 卡 1 今天的门 → 卡 2 快捷操作 → 卡 3 连接
// 底部常驻：GlassSlideToUnlock（唯一主动作）。
import SwiftUI

struct DoorHomeScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    @State private var link = LinkSenseModel()
    @State private var showQuickEdit = false
    @State private var showUnlockGate = false

    private var lock: LockSummary? { app.lock }

    private var batteryPct: Int {
        lock.map { V8.C.accentFill(mac: $0.id, snapshot: $0.battery) } ?? -1
    }

    private var batteryFraction: Double {
        batteryPct < 0 ? 0 : Double(batteryPct) / 100.0
    }

    private var judgement: String {
        guard let lock else { return "还没有添加门锁" }
        if !lock.isConnected { return "门未连接" }
        if batteryPct >= 0 && batteryPct < 15 { return "电量偏低" }
        if lock.safeMode { return "安全模式已开" }
        return "门已就绪"
    }

    private var lead: String {
        guard let lock else {
            return "把锁的后面板打开，长按 RESET 直到三声嘀，然后在这里添加。换过手机的话，也可以先从备份恢复。"
        }
        var bits: [String] = []
        bits.append(lock.model)
        if let first = todayOpenEntries.first {
            bits.append("最近一次 " + TimeDisplay.clock(first.at))
        } else {
            bits.append("今天还没有开门")
        }
        bits.append(lock.muted ? "静音开" : "静音关")
        return bits.joined(separator: "，") + "。"
    }

    private var todayOpenEntries: [LedgerEntry] {
        let start = Int64(TimeFormat.calendar.startOfDay(for: Date()).timeIntervalSince1970 * 1000)
        return app.entries.filter { $0.at >= start && ($0.tone == .ok || $0.tone == .live) }
    }

    private var kindRows: [(String, Color, Int)] {
        let today = todayOpenEntries
        return [
            ("密码", V8.D.password, today.filter { $0.event.contains("密码") }.count),
            ("指纹", V8.D.fingerprint, today.filter { $0.event.contains("指纹") }.count),
            ("临时码", V8.D.temp, today.filter { $0.event.contains("临时") }.count),
            ("手机钥匙", V8.D.mobile, today.filter { $0.event.contains("手机") }.count)
        ]
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            chipRow
        } content: {
            if lock == nil {
                VEmpty(
                    title: "还没有添加门锁",
                    reason: "把锁的后面板打开，长按 RESET 直到三声嘀，然后在这里添加。换过手机的话，也可以先从备份恢复。",
                    actionTitle: "添加门锁"
                ) { router.request(.dest(.addLock)) }
            } else {
                heroCard
                todayCard
                quickCard
                linkCard
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await app.reload(refreshStatus: true)
            link.update(mac: app.currentMac)
            if app.lock != nil { await link.preheat() }
        }
        .onChange(of: app.lock?.id) { _, _ in
            link.update(mac: app.currentMac)
        }
        .sensoryFeedback(.success, trigger: app.dialPhase == .opened) { _, new in new }
        .sensoryFeedback(.error, trigger: app.dialPhase.isFailed) { _, new in new }
        .sheet(isPresented: $showQuickEdit) { QuickPoolEditSheet() }
        .sheet(isPresented: $showUnlockGate) {
            NavigationStack {
                UnlockGateScreen {
                    Task { await app.runUnlockChain() }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if app.lock != nil {
                GlassSlideToUnlock(onUnlock: { requestUnlock() }, busy: app.dialPhase.isBusy)
                    .padding(.horizontal, V8.S.gutterCard)
                    .padding(.bottom, V8.S.gapS)
            }
        }
    }

    // MARK: - 芯片行

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: V8.S.gapChip) {
                VChip2(icon: .ring(lock?.isConnected == true ? 1 : 0.02, lock?.isConnected == true ? V8.C.ok : V8.C.danger),
                       label: "连接", value: lock?.isConnected == true ? "已连接" : "未连接")
                VChip2(icon: .ring(1, V8.D.fingerprint), label: "凭证", value: "\(app.keys.count) 枚")
                VChip2(icon: .ring(lock?.safeMode == true ? 1 : 0.02, V8.C.warn),
                       label: "安全模式", value: lock?.safeMode == true ? "已开" : "关")
                VChip2(icon: .ring(1, V8.C.accent), label: "今天", value: "\(todayOpenEntries.count) 次")
            }
            .padding(.leading, V8.S.gutterCard)
            .padding(.trailing, V8.S.gutterCard)
        }
        .scrollClipDisabled()
    }

    // MARK: - 英雄：电量环

    private var heroCard: some View {
        VCard2 {
            VStack(spacing: V8.S.gapM) {
                ZStack {
                    VHeroRing(
                        fraction: batteryFraction,
                        center: batteryPct < 0 ? "—" : "\(batteryPct)",
                        label: "%",
                        size: V8.G.heroOuter * 0.62,
                        tint: batteryPct >= 0 && batteryPct < 15 ? V8.C.danger : V8.C.accent
                    )
                    if app.dialPhase == .opened {
                        Image(systemName: "checkmark")
                            .font(V8.T.heroL)
                            .foregroundStyle(V8.C.ok)
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                            .accessibilityHidden(true)
                    }
                }
                .animation(reduceMotion ? nil : V8.M.settle, value: app.dialPhase == .opened)
                if let left = app.autoLockLeft {
                    Text("约 \(left) 秒后自动上锁 · 请确认门已关好")
                        .font(V8.T.footnote)
                        .foregroundStyle(V8.C.ink3)
                }
                if let hint = app.retryHint {
                    VBusy(text: hint)
                }
                if case .failed(let msg) = app.dialPhase {
                    VFailure(what: "开锁失败", why: msg, next: "走近门锁再试一次；连续失败请检查钥匙串是否插好。")
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 卡 1 今天的门

    private var todayCard: some View {
        VCard2 {
            VCardHead(eyebrow: "今天的门", statement: "\(todayOpenEntries.count) 次开锁",
                      trailing: todayOpenEntries.first.map { TimeDisplay.clock($0.at) })
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                ForEach(Array(kindRows.enumerated()), id: \.offset) { pair in
                    VDataRow(tag: pair.element.0, tagTint: pair.element.1,
                             title: pair.element.0, detail: nil,
                             value: "\(pair.element.2)", unit: "次")
                    if pair.offset != kindRows.count - 1 { VDotRule() }
                }
            }
            .padding(.top, V8.S.gapS)
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("只统计本机收到的开锁回执；失败的尝试不计数。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapFootnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 卡 2 快捷操作

    private var quickCard: some View {
        VCard2 {
            HStack(alignment: .firstTextBaseline) {
                VCardHead(eyebrow: "一按即开", statement: "\(QuickPool.selected.count) 个快捷位")
                Spacer(minLength: 0)
                Button { showQuickEdit = true } label: {
                    Text("编辑")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.accent)
                        .frame(minHeight: V8.H.min)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("编辑快捷操作")
            }
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                ForEach(Array(QuickPool.selected.enumerated()), id: \.element.id) { pair in
                    VNavRow(title: pair.element.label, detail: nil) {
                        runQuick(pair.element.id)
                    }
                    if pair.offset != QuickPool.selected.count - 1 { VDotRule() }
                }
            }
            .padding(.top, V8.S.gapS)
        }
    }

    // MARK: - 卡 3 连接

    private var linkCard: some View {
        VCard2 {
            VCardHead(eyebrow: "连接", statement: link.phase.rawValue,
                      trailing: link.lastRSSI.map { "\($0) dBm" })
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                VNavRow(title: "预热连接", detail: link.busy ? "进行中…" : "提前连上，开门更快") {
                    Task { await link.preheat() }
                }
                VDotRule()
                VNavRow(title: "重连", detail: "阶梯 \(Int(link.nextLadder))s") {
                    Task { await link.reconnect() }
                }
                VDotRule()
                VNavRow(title: "读信号强度", detail: "RSSI") {
                    link.readRSSI()
                }
                VDotRule()
                VNavRow(title: "门锁设置", detail: "静音 / 防尾随 / 安全模式 / 布防") {
                    router.request(.dest(.lockSettings))
                }
                VDotRule()
                VNavRow(title: "我的锁", detail: "全部锁 / 锁档案") {
                    router.request(.dest(.lockPortfolio))
                }
                VDotRule()
                // 2026-11-04（Round 16b · 能力守恒复核）：旧门页芯片行有一枚「版面」，
                // 点开是 ModuleOrderSheet（三槽排序 + 模块显隐 + 快捷格勾选）。
                // 门页迁 V8 时这一枚丢了 —— .moduleOrder 变成零入口的孤儿 Dest。
                // 这里恢复入口，指向已迁的 ModuleOrderHomeScreen。
                VNavRow(title: "版面", detail: "模块排序与显隐") {
                    router.request(.dest(.moduleOrder))
                }
            }
            .padding(.top, V8.S.gapS)
        }
    }

    // MARK: - 动作

    /// 唯一开锁入口：本机密码闸（30 秒内二次开锁）+ 双击防抖 + 真命令链（与 DoorScreen 同口径）。
    private func requestUnlock() {
        guard app.dialPhase == .idle || app.dialPhase.isFailed else { return }
        if needsGate {
            showUnlockGate = true
        } else {
            Task { await app.runUnlockChain() }
        }
    }

    private var needsGate: Bool {
        guard DB.hasPasscode(), let last = app.lastUnlockSuccessAt else { return false }
        return Date().timeIntervalSince1970 * 1000 - Double(last) > 30_000
    }

    private func runQuick(_ id: String) {
        switch id {
        case "addPwd", "addFp": router.request(.dest(.keyCreate))
        case "otp": router.request(.dest(.zotp))
        case "syncTime": router.request(.dest(.syncTime))
        case "studio": router.request(.dest(.credentialStudio))
        case "backup": router.request(.dest(.backup))
        case "tailgate": router.request(.dest(.tailgate))
        case "safemode": router.request(.dest(.safeMode))
        case "dfu": router.request(.dest(.dfu))
        default: Task { await app.runUnlockChain() }
        }
    }
}