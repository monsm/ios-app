// 包2 连接感知与离线同步 — 连接管理包装层 (只预热不执行: 绝不自动开锁/自动下发凭证)
// 编号对照 docs/ROADMAP-DRAFT.md「包2」:
//   预握手 93/95/96/134 · 状态感知 63/64/67/68/69/71 · 韧性 124/125/126/130/131/275/536 ·
//   离线队列 510/533/535/538 · 跨页 135/136/162 · 70/539 积累占位
// 底层纪律: 不改 BLEService 协议帧/命令构造器, 只包一层连接管理与 UI 组件;
// 日志复用 DiagKit 事件流水 (BleTelemetry/DiagOps) 与 LockService 分级日志。
import SwiftUI
import CoreGraphics
import Combine
import AudioToolbox

// ---------- 链路三态 (64 语义色: 已连接 / 握手中 / 未连接) ----------
enum LinkState: Equatable {
    case ready, connecting, down
    var name: String {
        switch self {
        case .ready: return "已连接"
        case .connecting: return "握手中"
        default: return "未连接"
        }
    }
}

/// 包2 连接感知包装层: 预握手链路 / 回连节律 / 假死巡检 / 会话重协商 / 失败三分类。
/// 全部只读协作: 复用 LockService.ensureConnected/getStatus 既有会话自愈, 不新增协议指令;
/// 96 铁律: 预热/回连只到"就绪态", 绝不出手开锁, 也绝不主动下发新凭证。
@MainActor
final class LinkSense: ObservableObject {
    static let shared = LinkSense()
    @Published private(set) var sceneActive = true          // 135 scenePhase 消费点
    @Published private(set) var lastRssi: Int? = nil        // 最近一次见到的该锁 RSSI (63/71)
    private var prevRssi: Int? = nil                        // 270 上一次 RSSI: 骤降检测基准 (只在值变化时翻档)
    @Published private(set) var connectMs: Int? = nil        // 67 握手耗时 (最近一次, ms)
    @Published private(set) var reconnectAttempt = 0          // 126 回连节律轮次
    @Published private(set) var lastReconnectAt: Date = Date.distantPast
    @Published private(set) var sessionSince: Date? = nil    // 272 连接保持时长基准
    @Published private(set) var lastReceipt = 0              // 535 同步回执 (最近一次补发条数)
    @Published private(set) var connectSource = "预热"        // 98 冷热连接标识: 预热/回连 vs 即连
    @Published private(set) var btOn = BLEService.shared.isPoweredOn   // 69 系统蓝牙开关镜像
    /// 「系统蓝牙关着」和「本 App 没拿到权限」是**两件事**，用户要做的事也不同。
    /// 之前只有 btOn，于是在权限被拒时也显示"蓝牙已关闭"，用户去开蓝牙、
    /// 回来还是失败 —— 因为他关掉的是另一扇门。
    @Published private(set) var btDenied = false
    @Published private(set) var receiptShownAt: Date = Date.distantPast
    @Published private(set) var revalidating = false         // 131 会话重协商进行中 (假死巡检触发, 完成即消)
    private var lastLadderAt = Date.distantPast
    private var lastDeadlockAt = Date.distantPast
    private var reconnectTask: Task<Void, Never>?
    private var deadWatchTask: Task<Void, Never>?

    private init() {}
    /// 69: 跟随 BLEService 的开关变化 (回连循环 2s tick 顺带刷新, 不另起订阅)
    func syncBtOn() {
        btOn = BLEService.shared.isPoweredOn
        btDenied = (BLEService.shared.powerState == .unauthorized)
    }
    /// 69 "去开启": 系统设置无 App 级深链 API, 只能引导用户自行开启 (文案 + 常驻提示条)
    func openBluetoothSettings() {
        // 69: iOS 没有直达"蓝牙"面板的 App 级深链, 能跳的只有本 App 的设置页 (与 DiagnosticsView 同一个出口)。
        // 这函数原来只写一行日志 —— 横幅与无障碍标签都在承诺"点按前往系统设置", 那是个不存在的热区。
        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
        lockSvc.log("info", "蓝牙开启引导: 已跳到本 App 的系统设置页 (蓝牙开关仍需在系统设置或控制中心里打开, 69)")
        BleTelemetry.recordEvent("蓝牙开启引导", ok: true)
    }

    var lockSvc: LockService { LockService.shared }

    /// 93 信号围栏的唯一读点：默认值只写这一处。原先三处各写 -70（预握手判定 / 设置页档位 / 圆盘 129 暂缓），
    /// 改默认值的人必须同时想起另外两处 —— 本仓同类缺陷修过好几轮，这里先把它收拢。
    static var rssiFence: Int { DB.store.getInt("kf_rssi_fence", -70) }
    /// 宿主 AppState (RootView 挂载时经 selfRef 注册), LinkSense 只读协作, 不建循环依赖
    var app: AppState? { AppState.hostRef }

    // ---------- 当前锁链路三态 (与 DeviceHomeView.bleOn 同口径: 连着的必须是当前这把) ----------
    var linkState: LinkState {
        let app = self.app
        let mac = app?.currentMac ?? ""
        guard !mac.isEmpty else { return .down }
        if lockSvc.connectedMAC == mac { return .ready }
        switch app?.unlockState {
        case .connecting, .opening: return .connecting
        default: return .down
        }
    }

    // ---------- 预握手 (95 进页预热 / 93 信号围栏 / 96 只预热不执行 / 134 冷启动先扫描) ----------
    /// 冷启动即扫 (134) + 信号围栏自动预握手 (93): 只定位可见锁并记录 RSSI, 越过阈值才预热;
    /// 单锁可关 (100 手动连接模式: 关掉自动预握手, 点圆盘才连);
    /// 96 边界: 预握手完成绝不自动开锁, 也绝不主动下发新凭证 (只回收到场补发路径)。
    // ---------- 276 多锁并行预连 (常用两把锁) ----------
    /// "并行"的正确做法**不是**开两条扫描 —— BLE 只有一个射频, 两条扫描只会互相抢窗口;
    /// 正确做法是**一条扫描把多把常用锁的广播都收下** (单锁 scan(mac:) 每次只认一个 MAC, 换锁要重扫)。
    /// 只写 RSSI 档 (saveRssi), 不建连接、不下发 —— 与 134 冷启动扫描同一纪律。
    /// 当前锁由 preconnect() 负责, 这条只盯**其余**常用锁, 让"切过去即连"不必从零开始扫。
    func preconnectOthers(limit: Int = 2, timeoutMs: Int = 3500) async {
        guard !DiagFlags.silent else { return }
        let mine = (app?.currentMac ?? "").lowercased()
        let targets = Set(Self.warmLocks(limit: limit + 1).map { $0.lowercased() }.filter { $0 != mine })
        guard !targets.isEmpty else { return }
        let ble = BLEService.shared
        guard ble.isPoweredOn else { return }
        let t0 = Date()
        do {
            try await ble.startScan(allowDuplicates: true, timeoutMs: timeoutMs)
            defer {
                ble.stopScan()
                ScanStats.record(seconds: Date().timeIntervalSince(t0))   // 285: 也计入扫描时长
            }
            let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
            var hits = Set<String>()
            while Date() < deadline, hits.count < targets.count {
                for adv in ble.allDiscovered() {
                    guard let a = ZKProtocol.parseAdv(adv.advertisHex), let m = a.macRaw else { continue }
                    let mac = m.lowercased()
                    guard targets.contains(mac), !hits.contains(mac) else { continue }
                    hits.insert(mac)
                    Self.saveRssi(mac: mac, rssi: adv.rssi)
                    lockSvc.log("info", "多锁预连: 收到 \(String(mac.prefix(6))) RSSI \(adv.rssi)")   // 276 多锁预连
                }
                if hits.count < targets.count { try? await Task.sleep(for: .milliseconds(250)) }
            }
        } catch {
            lockSvc.log("warn", "多锁预连扫描失败: \(error.localizedDescription)")
        }
    }
    /// 276 常用锁 (按本机缓存里的日志行数排): 预连只盯它们, 不是把全部锁都扫一遍
    static func warmLocks(limit: Int) -> [String] {
        DB.keychains()
            .map { ($0.mac, DB.readLogs($0.mac).count) }
            .sorted { $0.1 > $1.1 }
            .prefix(max(1, limit))
            .map { $0.0 }
    }

    func preconnect() async {
        guard !DiagFlags.silent else { return }   // 127 静默排查模式: 暂停全部自动连接
        let app = self.app
        guard let mac = app?.currentMac, !mac.isEmpty, sceneActive,
              app?.unlockState == .idle, lockSvc.connectedMAC != mac else { return }
        guard DB.store.getBool("kf_link_auto_" + mac, true) else { return }
        do {
            let dev = try await scan(mac: mac, timeoutMs: 6000)
            if let rssi = dev?.rssi { updateRssi(rssi) }
            guard let dev = dev else {
                BleTelemetry.recordAttempt(mac: mac, ok: false, reason: "未发现 (不在广播范围或锁未广播)")
                BleTelemetry.recordEvent("预握手: 未发现 " + String(mac.prefix(6)), ok: false)
                lockSvc.log("warn", "预握手: 扫描未发现 \(mac), 不在广播范围")   // 134/130 预握手
                reconnectAttempt += 1
                return
            }
            let fence = LinkSense.rssiFence
            if dev.rssi < fence {
                BleTelemetry.recordAttempt(mac: mac, ok: false, reason: "RSSI \(dev.rssi) 低于围栏 \(fence), 跳过预热")
                BleTelemetry.recordEvent("预握手: 信号弱跳过", ok: false)
                lockSvc.log("info", "预握手: RSSI \(dev.rssi) 低于围栏 \(fence), 低信号不浪费电量")   // 93 预握手
                reconnectAttempt += 1
                return
            }
            let t0 = CFAbsoluteTimeGetCurrent()
            try await lockSvc.ensureConnected(mac: mac)
            let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            connectSource = "预热"
            markReady(ms: ms, rssi: dev.rssi)
            lockSvc.log("info", "预握手完成: 耗时 \(ms)ms (只预热不执行, 96)")
            // 276: 同一次节律里顺手把其余常用锁也扫一遍 —— 不另开定时器 (预握手本身就是节律入口),
            // 也不改上面那条单锁链的任何判断 (它仍然只决定当前锁要不要预热)。
            if !Task.isCancelled { await preconnectOthers() }
            if dev.rssi >= -55, let host = AppState.hostRef, !(CareSchedule.quietOn && CareSchedule.isQuietHour()) {   // 99 近场轻提醒 (274 免扰时段静默)
                Task { @MainActor in XHaptics.tick.impactOccurred() }
                host.showToast("锁就在附近, 已就绪")   // 99 锁就在附近
            }
            BleTelemetry.recordAttempt(mac: mac, ok: true, reason: "预握手 \(ms)ms")
            BleTelemetry.recordEvent("预握手完成 \(ms)ms", ok: true)
            DiagOps.record("预握手 \(mac.prefix(6))")
        } catch {
            let kind = classifyFailure(error)
            BleTelemetry.recordAttempt(mac: mac, ok: false, reason: kind.name + " " + error.localizedDescription)
            BleTelemetry.recordEvent("预握手失败 \(kind.name)", ok: false)
            lockSvc.log("warn", "预握手失败 (\(kind.name)): \(error.localizedDescription)")   // 536 预握手失败
            reconnectAttempt += 1
        }
    }

    /// 进页/回前台静默预热 (95/135): 把 Hero 卡三态、信号格、耗时标签刷新到最新; 绝不动手开锁。
    func refresh() async {
        guard !DiagFlags.silent else { return }
        let app = self.app
        guard let mac = app?.currentMac, !mac.isEmpty, app?.unlockState == .idle else { return }
        if lockSvc.connectedMAC == mac {
            markReady(ms: connectMs, rssi: lastRssi)
            return
        }
        guard DB.store.getBool("kf_link_auto_" + mac, true) else { return }
        do {
            let dev = try await scan(mac: mac, timeoutMs: 6000)
            if let rssi = dev?.rssi { updateRssi(rssi) }
            let t0 = CFAbsoluteTimeGetCurrent()
            try await lockSvc.ensureConnected(mac: mac)
            let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            connectSource = "预热"
            markReady(ms: ms, rssi: lastRssi)
            BleTelemetry.recordAttempt(mac: mac, ok: true, reason: "进页预热 \(ms)ms")
            BleTelemetry.recordEvent("握手完成 (进页预热)", ok: true)
        } catch {
            BleTelemetry.recordAttempt(mac: mac, ok: false, reason: classifyFailure(error).name + " " + error.localizedDescription)
            BleTelemetry.recordEvent("握手失败 " + classifyFailure(error).name, ok: false)
            reconnectAttempt += 1
        }
    }

    // ---------- 到场补发 (535): 只补 kf_cqueue_ 既有队列, 不主动下发新凭证 ----------
    /// 预握手完成且确有排队变更时触发 (96 边界: 无队列绝不动手)。
    func onPreconnectDone() {
        guard !DiagFlags.silent else { return }
        let app = self.app
        guard let mac = app?.currentMac, lockSvc.connectedMAC == mac,
              CredentialOrg.pendingCount(mac) > 0 else { return }
        Task { @MainActor [weak self] in await self?.resync(mac: mac, from: "到场") }
    }
    /// 回前台即刷新 (135): 已连接且有排队 → 补发; 完成后记 535 回执。
    func resync(mac: String, from: String) async {
        guard lockSvc.connectedMAC == mac else { return }
        let q = CredentialOrg.pendingQueue(mac)
        guard !q.isEmpty else { return }
        var done = 0, failed = 0
        for item in q {
            do {
                try await lockSvc.ensureConnected(mac: mac)
                let extra = try await Self.applyQueueItem(mac: mac, item: item, lock: lockSvc)
                CredentialOrg.markQueue(mac, id: item.id, state: .done, note: item.title + " · 锁端确认" + extra)
                done += 1
            } catch {
                CredentialOrg.markQueue(mac, id: item.id, state: .failed,
                                        note: item.title + " · 第 \(item.attempt + 1) 次失败: \(error.localizedDescription)")
                failed += 1
            }
        }
        guard done > 0 else {
            lockSvc.log("warn", "\(from)补发 \(failed) 项未成功")
            return
        }
        lastReceipt = done
        receiptShownAt = Date()
        lockSvc.log("info", "\(from)自动补发 \(done) 项变更" + (failed > 0 ? ", 失败 \(failed) 项" : ""))
        if done > 0 { MaintenanceLog.record("\(from)自动补发 \(done) 项") }   // 387 维护回执
        BleTelemetry.recordEvent("补发成功 \(done) 项", ok: true)
        DiagOps.record("\(from)补发 \(done) 项")
    }

    /// 队列项走既有 LockService 命令。**实现只有 CredentialOrg.sendQueued 一份** (第一百五十四批) ——
    /// 这里原来是第三份 switch，而它走的正是"到场/回前台自动补发"那条**没人盯着**的路：
    /// 缺载荷时 `?? 0` 会静悄悄地向锁发"删 0 号槽"，本机随后还把这条记成"锁端确认"。
    static func applyQueueItem(mac: String, item: CredQueueItem, lock: LockService) async throws -> String {
        try await CredentialOrg.sendQueued(mac, lock, item)
    }

    // ---------- 126 回连节律: 5/15/30/60/90 秒梯度, 仅有排队变更的锁才自动回连 ----------
    static let ladderSeconds: [Double] = [5, 15, 30, 60, 90]
    /// 当前轮次对应的等待秒数 (UI 点阵用)
    func nextLadderInterval() -> Double {
        LinkSense.ladderSeconds[min(max(reconnectAttempt, 0), LinkSense.ladderSeconds.count - 1)]
    }
    func startReconnectLoop() {
        guard reconnectTask == nil else { return }
        reconnectTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.autoReconnectTick()
                self.syncBtOn()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
    /// 135 scenePhase 消费点: .active → 回前台即刷新 (静默预热一次 + 补发); 非 active 暂停回连
    func setSceneActive(_ active: Bool) {
        sceneActive = active
        if active {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.refresh()
                self.onPreconnectDone()
            }
        } else {
            // 用户口径 2026-10-17: **后台不许扫锁** (不耗手机射频, 也不逼锁一直广播费它的电)。
            // sceneActive=false 让 2s tick 不再发起; 这里补一刀把**正在进行**的那轮立刻停掉 ——
            // 否则退后台后那轮扫描还要跑满 6~10s 超时才自然停。
            BLEService.shared.stopScan()
        }
    }
    private func autoReconnectTick() {
        guard !DiagFlags.silent else { return }
        let app = self.app
        guard let mac = app?.currentMac, !mac.isEmpty, sceneActive else { return }
        // 靠近自动开锁 (AUTOOPEN): 2s tick 顺带 F2' 停留判定 — RSSI 武装 + 静置满 3s 才走全门判定;
        // 全门不过 = 静默拒绝 + 审计 (绝不自动开锁, 96 铁律由 AutoOpenController 内部门控兜底)
        AutoOpenController.shared.tickDwell(mac: mac)
        // 已连上这把锁: 门锁一旦连接就**停止广播**, didDiscover 那一侧不再产生样本 ——
        // 于是自动开锁的武装位 (feedRssi) 收不到新数, 表现就是用户报的两条:
        //   · 连上之后"信号再也不更新";
        //   · 开完锁走开再回来, 不会再自动开 (armed 回不来)。
        // 解法: 从**已建立的连接**上按节拍取一次 RSSI (readLinkRSSI → didReadRSSI), 喂回同一条
        // saveRssi → updateRssi → feedRssi 链。与安卓 BleUnlocker.observeSignal 的 readRemoteRssi 同解。
        // 只在已连接、前台 (sceneActive, 上面已 guard)、非静默档时取 —— 后台不测不扫, 不耗电。
        if lockSvc.connectedMAC == mac {
            BLEService.shared.readLinkRSSI { rssi in
                guard let rssi else { return }   // 读不到就不发明数据 (与安卓同一口径)
                // saveRssi 是 @MainActor 上的静态方法, 而这个闭包由 BLEService 调用 (非隔离类型);
                // 运行时它确实落在主线程 (CBCentralManager 建在 queue: .main), 但**类型上不保证** ——
                // 显式跳一次, 与本文件 saveRssi 里喂 feedRssi 的写法同构, 不靠"大概都在主线程"。
                Task { @MainActor in Self.saveRssi(mac: mac, rssi: rssi) }
            }
            return
        }
        guard DB.store.getBool("kf_link_auto_" + mac, true) else { return }
        guard CredentialOrg.pendingCount(mac) > 0 else { return }   // 无变更不回连, 省电 (93 同源原则)
        if Date().timeIntervalSince(lastLadderAt) < nextLadderInterval() { return }
        lastLadderAt = Date()
        let kind = reconnectAttempt
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.lockSvc.ensureConnected(mac: mac)
                BleTelemetry.recordAttempt(mac: mac, ok: true, reason: "回连成功 (第 \(kind + 1) 轮)")
                BleTelemetry.recordEvent("回连成功 (第 \(kind + 1) 轮)", ok: true)
                // 274 免打扰时段: 回连是系统替用户跑的动作, 夜里不该凭它震一下 (与 :111 近场提醒同一把闸)
                if !(CareSchedule.quietOn && CareSchedule.isQuietHour()) {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                self.lastReconnectAt = Date()
                if kind > 0 {
                    AppState.hostRef?.showToast("回到锁身边")   // 132 回到锁身边
                }
                self.connectSource = "回连"
                self.markReady(ms: self.connectMs, rssi: self.lastRssi)
            } catch {
                BleTelemetry.recordAttempt(mac: mac, ok: false, reason: "回连失败 (第 \(kind + 1) 轮) \(self.classifyFailure(error).name)")
                BleTelemetry.recordEvent("回连失败 (第 \(kind + 1) 轮)", ok: false)
                self.reconnectAttempt = min(kind + 1, LinkSense.ladderSeconds.count)
            }
        }
    }

    /// 98 用户主动路径 (圆盘开锁前 ensureConnected) 标记为"即连", 解释快慢差异
    func noteUserConnect() {
        connectSource = "即连"
        sessionSince = Date()
    }

    // ---------- 状态记账 ----------
    /// 270 统一 RSSI 入口: 旧值翻入 prevRssi 再更新现值 —— 四处喂入共用一份历史, 骤降提示才有基准
    private func updateRssi(_ r: Int) {
        if let cur = lastRssi, cur != r { prevRssi = cur }
        lastRssi = r
    }
    private func markReady(ms: Int?, rssi: Int?) {
        connectMs = ms
        sessionSince = Date()
        reconnectAttempt = 0
        if let rssi { updateRssi(rssi) }
        objectWillChange.send()
    }

    // ---------- 275 假死检测 + 131 会话重协商: 连接态久无有效会话 → 重新 ensureConnected ----------
    // 更正 (第九十一批): 这里原写着"看门狗 Watchdog (包11) 已每 45s 读 03 自愈" —— 那句是假的,
    // 那个 enum 全仓零调用点 (34 行死码), 已删 (见 DiagKit 同段说明)。
    // 现役的自愈就是本层: 60s 一拍巡检 (:309 的 deadbeatCheck), 挂起 >10 分钟且**有待下发项**才重协商一次。
    // 其余自动动作 (自动连接/预热/补发/重连/冷启动) 也都在本层 :75/:122/:150/:237/:417, 一并受 127 静默档管。
    // 本层做"长挂起"兜底:
    // 连接保持但 10 分钟无刷新标记, 且当前有待下发/正在使用 → 主动重协商一次。
    func startDeadWatch() {
        guard deadWatchTask == nil else { return }
        deadWatchTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self else { return }
                self.deadbeatCheck()
            }
        }
    }
    private func deadbeatCheck() {
        guard !DiagFlags.silent else { return }
        let mac = lockSvc.connectedMAC
        guard !mac.isEmpty, lockSvc.connectedMAC == mac else { return }
        let idle = sessionSince.map { Date().timeIntervalSince($0) } ?? 0
        guard idle > 600, Date().timeIntervalSince(lastDeadlockAt) > 300 else { return }
        guard CredentialOrg.pendingCount(mac) > 0 else { return }   // 无待办不打扰
        lastDeadlockAt = Date()
        revalidating = true
        lockSvc.log("info", "会话巡检: 连接已挂 \(Int(idle / 60)) 分钟, 重新校验会话")   // 275/131 会话巡检
        BleTelemetry.recordEvent("会话重协商 (挂起 \(Int(idle / 60)) 分钟)", ok: true)
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.revalidating = false }
            do {
                _ = try await self.lockSvc.getStatus(mac: mac)
                self.sessionSince = Date()
            } catch {
                do {
                    try await self.lockSvc.ensureConnected(mac: mac)
                    self.markReady(ms: self.connectMs, rssi: self.lastRssi)
                    self.lockSvc.log("info", "假死判定 → 已重新握手")   // 275/131 假死判定
                    BleTelemetry.recordEvent("会话重协商成功", ok: true)
                    // 277 看门狗自恢复累计: 会话假死被巡检判定并重新握手成功的次数 (明细就是上面那条日志)
                    DB.store.set("kf_wd_heals", DB.store.getInt("kf_wd_heals", 0) + 1)
                } catch {
                    self.lockSvc.log("warn", "会话重协商失败: \(error.localizedDescription)")
                    BleTelemetry.recordEvent("会话重协商失败", ok: false)
                }
            }
        }
    }

    // ---------- 130 唤醒失败细分 ----------
    // 已删: WakeReason 的四分法 (蓝牙未开/权限/不在广播范围/握手超时) 与在用的两处重合 ——
    // 日志侧分类走下面的 classifyFailure (536), 人话提示走 DiagnosticsView.friendlyFailReason (133),
    // 后者覆盖面更大 (还含 信号弱/回连轮次/会话重协商)。留第三份同表只会让三处漂移。

    // ---------- 536 失败三分类 (设备 / 蓝牙 / 协议) — 本地词表, 不改协议层 ----------
    struct FailKind {
        let name: String
        let hint: String
        /// 130 图标细分: 三类各配一枚图标。名称全部取自本仓已在用的 SF Symbol
        /// (不臆造 systemName —— 名字错了真机上只会显示空白)。做成计算属性而不是新增字段:
        /// 加字段要全仓改签初始化器 (DiagKit:560 记过这件事), 这里零调用点改动。
        var icon: String {
            switch name {
            case "蓝牙类", "蓝牙未开": return "antenna.radiowaves.left.and.right.slash"
            case "指令被拒": return "xmark.circle.fill"
            case "占用类": return "person.2.slash"
            case "设备类", "不在广播范围": return "dot.radiowaves.left.and.right"
            default: return "exclamationmark.circle"   // 协议类
            }
        }
    }
    func classifyFailure(_ error: Error) -> FailKind {
        let m = error.localizedDescription
        if m.contains("蓝牙") || m.contains("unauthorized") || m.contains("not powered") {
            return FailKind(name: "蓝牙类", hint: "检查系统蓝牙开关与权限, 开关一次蓝牙再试")
        }
        // 536: "指令被拒"档 —— 服务层对锁端 rc != 0 一律以 StatusParser.rcMessage(rc) 抛错
        // (LockService:282/:498、HardwareService:236/:246), 所以错误串命中 rc 表文案 = 锁端拒绝了指令。
        // 只取 4 字及以上的码文案: "丢包"/"溢出" 这类两字词出现在别的串里会误判。
        let rcTexts = StatusParser.rcMsg.filter { $0.key != 0 && $0.value.count >= 4 }.map { $0.value }
        if rcTexts.contains(where: { m.contains($0) }) || m.hasPrefix("错误码 ") {
            return FailKind(name: "指令被拒", hint: "锁端拒绝了这条指令 — 到诊断页「错误码对照表」按码处置; 多为权限/状态不满足, 可重试一次")   // 159 锁端拒绝了这条指令
        }
        if m.contains("未发现") || m.contains("扫描") || m.contains("超时") {
            return FailKind(name: "设备类", hint: "确认门锁通电并靠近 1 米内; 频繁失败先查电量")
        }
        return FailKind(name: "协议类", hint: "会话/指令异常 — 到诊断页跑一键体检, 或重置重配该锁")
    }

    /// 124 占用类保守文案: 协议 rc 未确证占用细分 (DEFERRED 备案), 不虚构错误码语义。
    static func occupationHint() -> String {
        "连接可能正被占用 (如另一台手机刚连过) — 稍候 1–2 分钟再试 (占用细分未确证, 保守文案)"
    }

    // ---------- 70 连接成功率: 样本不足显示"积累中"占位 ----------
    static func successRateText(mac: String) -> String {
        let list = BleTelemetry.attempts.filter { $0.mac == mac }
        guard list.count >= 10 else { return "积累中 (\(list.count)/10)" }
        let ok = list.filter { $0.ok }.count
        return "成功率 \(Int(Double(ok) * 100 / Double(list.count)))% (\(list.count) 次)"
    }

    /// 539 高成功率时段: 从真实留存的连接尝试 (kf_conn_attempts) 按小时分桶算成功率。
    /// 口径与 DiagKit.successRate() 同源 (全部留存, 上限 300 条)，不假装是滚动 7 天。
    /// 每桶至少 10 次、总样本至少 30 次才给结论 —— 样本不够时说"积累中"，不编时段。
    static func bestHourHint() -> String {
        let a = BleTelemetry.attempts
        guard a.count >= 30 else { return "时段统计积累中 (\(a.count)/30) — 每次连接结果都记在本地, 攒够才给结论" }
        // ConnAttempt.t 形如 "MM-dd HH:mm:ss" (DiagKit 写入时就是本地串) ⇒ 直接截小时, 不再过一次历法
        var n = [Int: Int](), ok = [Int: Int]()
        for e in a {
            guard e.t.count >= 10, let h = Int(e.t.dropFirst(6).prefix(2)) else { continue }
            n[h, default: 0] += 1
            if e.ok { ok[h, default: 0] += 1 }
        }
        let buckets = n.keys.filter { (n[$0] ?? 0) >= 10 }
        guard !buckets.isEmpty else { return "各小时样本都还不够 (单时段需 ≥10 次) — 现有 \(a.count) 次连接记录" }
        let best = buckets.max { lhs, rhs in
            let pl = Double(ok[lhs, default: 0]) / Double(n[lhs] ?? 1)
            let pr = Double(ok[rhs, default: 0]) / Double(n[rhs] ?? 1)
            if pl == pr { return (n[lhs] ?? 0) < (n[rhs] ?? 0) }
            return pl < pr
        }!
        let pct = Int(Double(ok[best, default: 0]) * 100 / Double(n[best] ?? 1))
        return "成功率最高的时段: \(best) 时前后 (\(pct)% · \(n[best] ?? 0) 次样本)"
    }

    // ---------- 扫描取 RSSI (63/71 数据源) ----------
    func scan(mac: String, timeoutMs: Int = 6000) async throws -> BLEAdvDevice? {
        let ble = BLEService.shared
        let scanT0 = Date()   // 285: 扫描时长自查的计时起点
        try await ble.startScan(timeoutMs: timeoutMs)
        defer {
            ble.stopScan()
            ScanStats.record(seconds: Date().timeIntervalSince(scanT0))   // 285
        }
        let target = mac.lowercased()
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        var found: BLEAdvDevice?
        // 2026-10-14: 补取消判据 (与 LockService 的扫描循环同口径), 否则上层取消后仍空转到超时。
        while Date() < deadline, found == nil, !Task.isCancelled {
            found = ble.allDiscovered().first { adv in
                guard let a = ZKProtocol.parseAdv(adv.advertisHex), let m = a.macRaw else { return false }
                return m == target || a.macDisplay?.replacingOccurrences(of: ":", with: "").lowercased() == target
            }
            if found == nil { try? await Task.sleep(for: .milliseconds(300)) }
        }
        if let f = found {
            BleTelemetry.recordEvent("扫描命中 RSSI \(f.rssi)", ok: true)
            Self.saveRssi(mac: target, rssi: f.rssi)
        }
        return found
    }
    /// 537 下拉重扫: 把刚扫到的信号推给 UI。**只动"最近见到的信号", 不动连接态** ——
    /// 扫到广播 ≠ 已连接, 把 linkState 一起改掉就是凭空承诺一个没发生的会话。
    func noteScannedRssi(_ rssi: Int) {
        lastRssi = rssi
        objectWillChange.send()
    }

    // ---------- 每锁 RSSI 记忆 (71 设备列表迷你信号格 / 129 极限距离) ----------
    static func saveRssi(mac: String, rssi: Int) {
        DB.store.set("kf_linkrssi_" + mac, rssi)
        LinkSense.shared.updateRssi(rssi)
        // 靠近自动开锁 (AUTOOPEN): 每个 RSSI 事件喂入回差滤波 (未开主开关 = 零开销, 控制器内 guard)
        Task { @MainActor in AutoOpenController.shared.feedRssi(mac: mac, rssi: rssi) }
    }
    /// 上次扫到的该锁 RSSI; nil = 从未扫到
    static func rssiFor(_ mac: String) -> Int? {
        DB.store.get(Int.self, "kf_linkrssi_" + mac)
    }

    /// 134 冷启动先扫描: App 启动广播扫描一次, 把可见已配对锁的 RSSI 落档 (不连接、不下发)
    func coldStartScan() {
        Task { @MainActor [weak self] in
            guard self != nil else { return }   // 只为"已销毁就别扫", 本体内不读 self
            let ble = BLEService.shared
            guard ble.isPoweredOn, !DiagFlags.silent else { return }
            do {
                // 123: 冷启动扫描时长/去重跟随用户档位 (默认 5s = 旧硬编码值, 不改变既有行为)
                let p = BLEService.ScanProfile.current
                let t0 = Date()
                try await ble.startScan(allowDuplicates: p.allowDuplicates, timeoutMs: p.timeoutMs)
                defer { ScanStats.record(seconds: Date().timeIntervalSince(t0)) }   // 285: 冷启动扫描也计入
                // 128 修正: startScan 是"启动即返回"的窗口式 API, 旧写法紧接着读 allDiscovered() 恒读到 ~0 台
                // (委托回调还没进来) ⇒ 拥挤度结论一直在说"未见 BLE 设备"。这里把窗口等满再读数,
                // 顺带量出"首台可见耗时" —— 首次发现越晚, 说明 2.4G 侦听窗口被挤得越厉害, 这才是拥挤度那一半。
                var firstSeenMs = -1
                let deadline = Date().addingTimeInterval(Double(p.timeoutMs) / 1000.0)
                while Date() < deadline {
                    if firstSeenMs < 0, !ble.allDiscovered().isEmpty {
                        firstSeenMs = Int(Date().timeIntervalSince(t0) * 1000)
                    }
                    try? await Task.sleep(for: .milliseconds(150))
                }
                for adv in ble.allDiscovered() {
                    if let a = ZKProtocol.parseAdv(adv.advertisHex), let m = a.macRaw,
                       DB.keychain(m) != nil {
                        Self.saveRssi(mac: m, rssi: adv.rssi)
                    }
                }
                let seen = ble.allDiscovered().count
                BleTelemetry.recordEvent("冷启动扫描, 可见设备 \(seen)", ok: true)   // 134 冷启动扫描
                DB.store.set("kf_link_env", seen)
                DB.store.set("kf_link_envms", firstSeenMs)
                DiagOps.record("冷启动扫描 (\(seen) 台可见, 首台 \(firstSeenMs >= 0 ? "\(firstSeenMs)ms" : "整窗未见"))")
            } catch {
                BleTelemetry.recordEvent("冷启动扫描失败", ok: false)
            }
        }
    }

    /// 128 环境拥挤度: 最近一次冷启动扫描的可见 BLE 设备数 + 首台可见耗时
    static var envCount: Int { DB.store.getInt("kf_link_env", 0) }
    /// 128: 首台可见耗时 (毫秒); -1 = 整窗一台没见
    static var envFirstSeenMs: Int { DB.store.getInt("kf_link_envms", -1) }

    /// 272 连接保持时长: 会话至今的分钟数 (异常久时 UI 提示重连)
    var holdMinutes: Int {
        sessionSince.map { Int(Date().timeIntervalSince($0) / 60) } ?? 0
    }
    /// 270/129 弱信号提示: 骤降优先 (基准 = 上次不同的读数), 否则走绝对值门槛 (Hero 卡提示条)
    var weakSignalHint: String? {
        guard let r = lastRssi else { return nil }
        if let p = prevRssi, p - r >= 12 {
            return "信号骤降 (\(p) → \(r)) — 建议走近门锁"
        }
        guard r < -75 else { return nil }
        return "信号在变差 (RSSI \(r)) — 建议走近门锁"
    }

    // ---------- 268 状态变化历史: 最近 5 次链路三态切换 (长按胶囊时间线) ----------
    struct StateHop: Codable { let at: String; let to: String }
    static func history() -> [StateHop] {
        DB.store.get([StateHop].self, "kf_link_hist") ?? []
    }
    /// 三态切换时记一笔 (LinkPill 宿主 onChange 调用), 封顶 5 条
    func noteStateHop(_ name: String) {
        var list = LinkSense.history()
        list.insert(StateHop(at: DiagTime.mmddHHmm(), to: name), at: 0)
        if list.count > 5 { list = Array(list.prefix(5)) }
        DB.store.setCodable("kf_link_hist", list)
    }

    /// 2026-10-18 冷启动预连接: 在 App 启动链路里**立刻**建链，不等首页渲染。
    ///
    /// 与 enterPage() 的区别只是**发起时机**:
    ///   · enterPage  —— DeviceHomeView 的 .task 里，首页渲染完才跑;
    ///   · startupPreconnect —— bootstrapOnce 里，与 coldStartScan 同一拍。
    /// 两者最终都汇到 preconnect()，所以行为、幂等、失败处理完全一致。
    ///
    /// 仍然受既有开关 `kf_link_auto_<mac>` 管: 用户选了"手动连接模式"就不预热。
    func startupPreconnect(mac: String) {
        guard !mac.isEmpty else { return }
        guard DB.store.getBool("kf_link_auto_" + mac, true) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.preconnect()
            self.onPreconnectDone()
        }
    }

    /// 95 进页预热入口 (DeviceHomeView.task 调用): 静默 ensureConnected, 成功后顺手 135 补发。
    func enterPage() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.preconnect()
            self.onPreconnectDone()
        }
    }
}

// ---------- AppState 宿主注册 (LinkSense 只读协作, 不建循环依赖) ----------
extension AppState {
    static var hostRef: AppState?
}

// ================= UI 组件 (颜色只经 DS 令牌, hero 渐变白字用既有半透明变体) =================

/// 包2 连接偏好页 (70/97/100/539): 每锁自动预握手开关 + 成功率积累占位 + 信号围栏记忆。
/// 落点 设置-门锁 "连接与预握手"; 全部本地偏好键, 不碰协议。
struct LinkPrefsView: View {
    var mac: String
    @EnvironmentObject var app: AppState
    /// 当前信号（实时读，进页 + 手动刷新都走这个）
    @State private var rssi: Int?
    @State private var refreshTick = 0

    var body: some View { vkBody.destined(.linkPrefs) }
    var vkBody: some View {
        ZStack {
            XPalette.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: XSpace.l) {
                    signalCard
                    prefsCard
                    statsCard
                }
                .padding(.horizontal, XSpace.gutter)
                .padding(.vertical, XSpace.l)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("连接与预握手")
        .onAppear { rssi = LinkSense.rssiFor(mac) }
        .id(refreshTick)
    }

    // ── 信号卡（新增，本页最该有的东西）──
    //
    // 原来整页只有开关和文字，用户看不到"现在信号多强"。
    // 而这页讲的是"预握手门槛" —— 不看当前信号，调门槛就是盲调。
    private var signalCard: some View {
        let level = LinkSense.rssiLevel(rssi)
        return XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                HStack {
                    secLabel("当前信号")
                    Spacer(minLength: 0)
                    Button {
                        rssi = LinkSense.rssiFor(mac)
                        refreshTick += 1
                        XHaptics.tick.impactOccurred()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: XIcon.sm, weight: .medium))
                            .foregroundStyle(XPalette.accent)
                            .frame(width: XHit.min, height: XHit.min)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("刷新信号")
                }

                HStack(alignment: .firstTextBaseline, spacing: XSpace.s) {
                    Text(rssi.map { String($0) } ?? "—")
                        .xFont(.title2, weight: .semibold)
                        .foregroundStyle(signalTone(level))
                        .monospacedDigit()
                    Text("dBm")
                        .xFont(.caption)
                        .foregroundStyle(XPalette.textSub)
                    Text(LinkSense.rssiLabel(level))
                        .xFont(.subheadline, weight: .medium)
                        .foregroundStyle(signalTone(level))
                    Spacer(minLength: 0)
                }

                // 五格信号条 —— 与 rssiLevel 的 0-4 档一一对应
                HStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(i < level ? signalTone(level) : XPalette.surfaceAlt)
                            .frame(maxWidth: .infinity)
                            .frame(height: CGFloat(6 + i * 4))
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
                .frame(height: 26)
                .accessibilityHidden(true)

                // 当前围栏线在哪 —— 让"门槛"这件事可见
                let fence = LinkSense.rssiFence
                // 把 `rssi != nil && (rssi! >= fence)` 抽成一个 Bool ——
                // 这个带强制解包的三元在同一个 view 里重复了三次，
                // 类型检查器超时 (CI: unable to type-check this expression in reasonable time)。
                let meetsFence: Bool = rssi.map { $0 >= fence } ?? false
                if fence != -127 {
                    HStack(spacing: XSpace.xs) {
                        Image(systemName: meetsFence ? "checkmark.circle.fill" : "xmark.circle")
                            .font(.system(size: XIcon.xs, weight: .semibold))
                            .foregroundStyle(meetsFence ? XPalette.ok : XPalette.warn)
                        Text(meetsFence
                             ? "已达预握手门槛 (\(fence) dBm)"
                             : "低于门槛 \(fence) dBm — 不会自动预热")
                            .xFont(.caption2)
                            .foregroundStyle(XPalette.textSub)
                        Spacer(minLength: 0)
                    }
                }

                Text("信号强度来自最近的 BLE 广播。走近门锁后刷新可看到变化。")
                    .xFont(.caption2)
                    .foregroundStyle(XPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .xScrollLift()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rssi == nil ? "信号未知" : "信号 " + String(rssi!) + " dBm, " + LinkSense.rssiLabel(level))
    }

    private func signalTone(_ level: Int) -> Color {
        switch level {
        case 4, 3: return XPalette.ok
        case 2: return XPalette.accent
        case 1: return XPalette.warn
        default: return XPalette.textTertiary
        }
    }

    // ── 偏好卡 ──
    private var prefsCard: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                secLabel("自动预握手")
                XToggle("进页/回前台自动预热连接", isOn: Binding(
                    get: { DB.store.getBool("kf_link_auto_" + mac, true) },
                    set: { DB.store.set("kf_link_auto_" + mac, $0) }))
                LabeledRow("手动连接模式",
                           DB.store.getBool("kf_link_auto_" + mac, true) ? "自动" : "手动 — 点圆盘才连")
                // 93 信号围栏: 原先这一行只是 LabeledRow 把常量 -70 显示出来，全仓没有任何写入方
                // (LinkSenseKit 的预握手判定读的就是这个键) ⇒ "围栏"是个不可调的装饰值。补成真实档位。
                // -127 当"关"用: 判定式是 `dev.rssi < fence`，取 BLE 可达的最弱下界就等效不设限。
                Picker(selection: Binding(
                    get: { LinkSense.rssiFence },
                    set: { DB.store.set("kf_rssi_fence", $0) })) {
                    Text("严格 (≥ -60)").tag(-60)
                    Text("标准 (≥ -70)").tag(-70)
                    Text("宽松 (≥ -80)").tag(-80)
                    Text("关闭围栏").tag(-127)
                } label: {
                    Text("信号围栏")
                }
                .pickerStyle(.menu)
                .tint(XPalette.accentText)
                Text("RSSI 达标才预热, 低信号不浪费电量。只影响自动预握手的启动门槛；手动点圆盘、靠近自动开锁 (AUTOOPEN) 的判定不受这一档约束。")
                    .xFont(.caption)
                    .foregroundStyle(XPalette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledRow("连接偏好记忆", "每锁 kf_link_auto_ 偏好 + rssiFor 实读; 扫描强度档走全局")
            }
        }
        .xScrollLift()
    }

    // ── 统计卡 ──
    private var statsCard: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                secLabel("连接统计")
                LabeledRow("连接成功率", LinkSense.successRateText(mac: mac))
                LabeledRow("高成功率时段", LinkSense.bestHourHint())
                LabeledRow("占用类错误", LinkSense.occupationHint())
                Text("成功率需 7 天握手数据积累，当前为占位；高成功率时段与占用类提示已接入 LinkSense 的真实读数。")
                    .xFont(.caption)
                    .foregroundStyle(XPalette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .xScrollLift()
    }

    private func secLabel(_ text: String) -> some View {
        Text(text)
            .xFont(.caption, weight: .semibold)
            .foregroundStyle(XPalette.textTertiary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension LinkSense {
    /// RSSI 档位: -55 满 / -65 近 / -75 中 / -85 远
    static func rssiLevel(_ rssi: Int?) -> Int {
        guard let r = rssi else { return 0 }
        if r >= -55 { return 4 }
        if r >= -65 { return 3 }
        if r >= -75 { return 2 }
        if r >= -85 { return 1 }
        return 0
    }
    static func rssiLabel(_ level: Int) -> String {
        ["不可测", "远", "中", "近", "满"][min(max(level, 0), 4)]
    }
}




/// 136 跨页全局 BLE 状态细条: 非设备 Tab 顶部 2pt 语义细线 + 状态行, 点按跳回设备页。
struct BLEStrip: View {
    var title: String
    var state: LinkState
    var detail: String?
    var action: () -> Void
    var body: some View {
        HStack(spacing: XSpace.xs) {
            Image(systemName: stIcon)
                .font(.system(size: XIcon.xs, weight: .semibold))
                .foregroundStyle(stTint)
                .accessibilityHidden(true)
            Text(stText)
                .xFont(.caption2, weight: .medium)
                .foregroundStyle(XPalette.textSub)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .xFont(.caption2)
                    .foregroundStyle(XPalette.textSub)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: action) {
                Label(title, systemImage: "lock.fill")
                    .xFont(.footnote, weight: .medium)
            }
            .buttonStyle(.plain)
            .foregroundStyle(XPalette.accentText)
            .frame(minHeight: XHit.min)
            .contentShape(Rectangle())
        }
        .padding(.horizontal, XSpace.gutter)
        .padding(.top, XSpace.xs)
        .frame(minHeight: 28)
        .background(XPalette.surfaceAlt.opacity(0.6))
        .overlay(alignment: .bottom) {
            Rectangle().fill(stTint).frame(height: 2)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(stText + " " + title)
        .accessibilityHint("点按跳回设备页, 定位到该锁")
    }
    private var stIcon: String {
        switch state {
        case .ready: return "checkmark.circle.fill"
        case .connecting: return "arrow.triangle.2.circlepath"
        // 2026-10-14 走查: 原来是 `wifi.slash` —— 这把锁走的是 BLE, 全 App 不碰网络。
        // 用带斜杠的 Wi-Fi 图标会让用户以为"要连 Wi-Fi 才能开锁", 而真正该开的是蓝牙。
        // 换成无线电波图标 (不带斜杠 = 链路空闲, 不是"被关掉"); 「蓝牙已关闭」那条
        // (BLEOffBanner) 仍用带斜杠的同一族, 两者形状与配色都不同, 不会看混。
        default: return "antenna.radiowaves.left.and.right"
        }
    }
    private var stTint: Color {
        switch state {
        case .ready: return XPalette.ok
        case .connecting: return XPalette.warn
        default: return XPalette.textSub
        }
    }
    private var stText: String {
        switch state {
        case .ready: return "门锁已连接"
        case .connecting: return "正在握手"
        default: return "未连接"
        }
    }
}

/// 69 蓝牙直通条: 系统蓝牙关闭时全 App 顶部引导条 (深链不可用 → 系统设置指引文案)。
struct BLEOffBanner: View {
    /// true = 本 App 没有蓝牙权限（要去设置里**允许**）；false = 系统蓝牙开关关着。
    var denied: Bool = false
    var onOpen: () -> Void
    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: XSpace.s) {
                Image(systemName: denied
                      ? "exclamationmark.shield.fill"
                      : "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: XIcon.sm, weight: .semibold))
                    .foregroundStyle(XPalette.warn)
                    .accessibilityHidden(true)
                Text(denied
                     ? "本 App 没有蓝牙权限 — 到设置里允许后, 才能配对与开锁"
                     : "蓝牙已关闭 — 打开系统蓝牙后, 门锁才能被唤醒")
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Label("去开启", systemImage: "chevron.right")
                    .xFont(.footnote, weight: .medium)
                    .foregroundStyle(XPalette.accentText)
            }
            .padding(.horizontal, XSpace.l)
            .padding(.vertical, XSpace.s + 2)
            .xCallout(XPalette.warn, .control, wash: 0.12)
            .frame(minHeight: XHit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(denied
                            ? "本 App 没有蓝牙权限, 点按前往系统设置允许"
                            : "蓝牙已关闭, 点按前往系统设置开启")
        .accessibilityHint(denied ? "到系统设置允许本 App 使用蓝牙" : "到系统设置打开蓝牙开关")
    }
}
