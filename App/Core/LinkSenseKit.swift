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
    @Published private(set) var connectMs: Int? = nil        // 67 握手耗时 (最近一次, ms)
    @Published private(set) var reconnectAttempt = 0          // 126 回连节律轮次
    @Published private(set) var lastReconnectAt: Date = Date.distantPast
    @Published private(set) var sessionSince: Date? = nil    // 272 连接保持时长基准
    @Published private(set) var lastReceipt = 0              // 535 同步回执 (最近一次补发条数)
    @Published private(set) var connectSource = "预热"        // 98 冷热连接标识: 预热/回连 vs 即连
    @Published private(set) var btOn = BLEService.shared.isPoweredOn   // 69 系统蓝牙开关镜像
    @Published private(set) var receiptShownAt: Date = Date.distantPast
    private var lastLadderAt = Date.distantPast
    private var lastDeadlockAt = Date.distantPast
    private var reconnectTask: Task<Void, Never>?
    private var deadWatchTask: Task<Void, Never>?

    private init() {}
    /// 69: 跟随 BLEService 的开关变化 (回连循环 2s tick 顺带刷新, 不另起订阅)
    func syncBtOn() { btOn = BLEService.shared.isPoweredOn }
    /// 69 "去开启": 系统设置无 App 级深链 API, 只能引导用户自行开启 (文案 + 常驻提示条)
    func openBluetoothSettings() {
        lockSvc.log("info", "蓝牙开启引导: 到系统设置 → 蓝牙 打开开关 (无 App 级深链, 69 降级文案)")
        BleTelemetry.recordEvent("蓝牙开启引导", ok: true)
    }

    var lockSvc: LockService { LockService.shared }
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
    func preconnect() async {
        guard !DiagFlags.silent else { return }   // 127 静默排查模式: 暂停全部自动连接
        let app = self.app
        guard let mac = app?.currentMac, !mac.isEmpty, sceneActive,
              app.unlockState == .idle, lockSvc.connectedMAC != mac else { return }
        guard DB.store.getBool("kf_link_auto_" + mac, true) else { return }
        do {
            let dev = try await scan(mac: mac, timeoutMs: 6000)
            if let rssi = dev?.rssi { lastRssi = rssi }
            guard let dev = dev else {
                BleTelemetry.recordAttempt(mac: mac, ok: false, reason: "未发现 (不在广播范围或锁未广播)")
                BleTelemetry.recordEvent("预握手: 未发现 " + String(mac.prefix(6)), ok: false)
                lockSvc.log("warn", "预握手: 扫描未发现 \(mac), 不在广播范围 (134/130)")
                reconnectAttempt += 1
                return
            }
            let fence = DB.store.getInt("kf_rssi_fence", -70)
            if dev.rssi < fence {
                BleTelemetry.recordAttempt(mac: mac, ok: false, reason: "RSSI \(dev.rssi) 低于围栏 \(fence), 跳过预热")
                BleTelemetry.recordEvent("预握手: 信号弱跳过", ok: false)
                lockSvc.log("info", "预握手: RSSI \(dev.rssi) 低于围栏 \(fence), 低信号不浪费电量 (93)")
                reconnectAttempt += 1
                return
            }
            let t0 = CFAbsoluteTimeGetCurrent()
            try await lockSvc.ensureConnected(mac: mac)
            let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            connectSource = "预热"
            markReady(ms: ms, rssi: dev.rssi)
            lockSvc.log("info", "预握手完成: 耗时 \(ms)ms (只预热不执行, 96)")
            if dev.rssi >= -55, let host = AppState.hostRef, !(CareSchedule.quietOn && CareSchedule.isQuietHour()) {   // 99 近场轻提醒 (274 免扰时段静默)
                DS.Haptics.tick.impactOccurred()
                host.showToast("锁就在附近, 已就绪 (99)")
            }
            BleTelemetry.recordAttempt(mac: mac, ok: true, reason: "预握手 \(ms)ms")
            BleTelemetry.recordEvent("预握手完成 \(ms)ms", ok: true)
            DiagOps.record("预握手 \(mac.prefix(6))")
        } catch {
            let kind = classifyFailure(error)
            BleTelemetry.recordAttempt(mac: mac, ok: false, reason: kind.name + " " + error.localizedDescription)
            BleTelemetry.recordEvent("预握手失败 \(kind.name)", ok: false)
            lockSvc.log("warn", "预握手失败 (\(kind.name)): \(error.localizedDescription) (536)")
            reconnectAttempt += 1
        }
    }

    /// 进页/回前台静默预热 (95/135): 把 Hero 卡三态、信号格、耗时标签刷新到最新; 绝不动手开锁。
    func refresh() async {
        guard !DiagFlags.silent else { return }
        let app = self.app
        guard let mac = app?.currentMac, !mac.isEmpty, app.unlockState == .idle else { return }
        if lockSvc.connectedMAC == mac {
            markReady(ms: connectMs, rssi: lastRssi)
            return
        }
        guard DB.store.getBool("kf_link_auto_" + mac, true) else { return }
        do {
            let dev = try await scan(mac: mac, timeoutMs: 6000)
            if let rssi = dev?.rssi { lastRssi = rssi }
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
                try await Self.applyQueueItem(mac: mac, item: item, lock: lockSvc)
                CredentialOrg.markQueue(mac, id: item.id, state: .done, note: item.title + " · 锁端确认")
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
        BleTelemetry.recordEvent("补发成功 \(done) 项", ok: true)
        DiagOps.record("\(from)补发 \(done) 项")
    }

    /// 队列项走既有 LockService 命令 (与 CredentialOrg 重试同一套, 不改命令集)。
    static func applyQueueItem(mac: String, item: CredQueueItem, lock: LockService) async throws {
        switch item.kind {
        case "del_pwd": try await lock.pwdDelete(item.pwd?.alias ?? 0)
        case "del_fp": try await lock.fpDelete(UInt32(item.fp?.batch ?? 0))
        case "period":
            if let p = item.pwd, !item.newFrom.isEmpty { try await lock.pwdExpire(p.alias, item.newFrom, item.newTo) }
        case "restore":
            if let p = item.pwd, let v = p.pwd { _ = try await lock.pwdAdd(pwd: v, validFrom: p.from, validTo: p.to) }
        default: break
        }
        _ = mac
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
    func stopReconnectLoop() {
        reconnectTask?.cancel()
        reconnectTask = nil
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
        }
    }
    private func autoReconnectTick() {
        guard !DiagFlags.silent else { return }
        let app = self.app
        guard let mac = app?.currentMac, !mac.isEmpty, sceneActive,
              lockSvc.connectedMAC != mac else { return }
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
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.lastReconnectAt = Date()
                if kind > 0 {
                    AppState.hostRef?.showToast("回到锁身边 (132)")
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
    private func markReady(ms: Int?, rssi: Int?) {
        connectMs = ms
        sessionSince = Date()
        reconnectAttempt = 0
        if let rssi { lastRssi = rssi }
        objectWillChange.send()
    }

    // ---------- 275 假死检测 + 131 会话重协商: 连接态久无有效会话 → 重新 ensureConnected ----------
    // 看门狗 Watchdog (包11) 已每 45s 读 03 自愈; 本层做"长挂起"兜底:
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
    func stopDeadWatch() {
        deadWatchTask?.cancel()
        deadWatchTask = nil
    }
    private func deadbeatCheck() {
        guard !DiagFlags.silent else { return }
        let mac = lockSvc.connectedMAC
        guard !mac.isEmpty, lockSvc.connectedMAC == mac else { return }
        let idle = sessionSince.map { Date().timeIntervalSince($0) } ?? 0
        guard idle > 600, Date().timeIntervalSince(lastDeadlockAt) > 300 else { return }
        guard CredentialOrg.pendingCount(mac) > 0 else { return }   // 无待办不打扰
        lastDeadlockAt = Date()
        lockSvc.log("info", "会话巡检: 连接已挂 \(Int(idle / 60)) 分钟, 重新校验会话 (275/131)")
        BleTelemetry.recordEvent("会话重协商 (挂起 \(Int(idle / 60)) 分钟)", ok: true)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await self.lockSvc.getStatus(mac: mac)
                self.sessionSince = Date()
            } catch {
                do {
                    try await self.lockSvc.ensureConnected(mac: mac)
                    self.markReady(ms: self.connectMs, rssi: self.lastRssi)
                    self.lockSvc.log("info", "假死判定 → 已重新握手 (275/131)")
                    BleTelemetry.recordEvent("会话重协商成功", ok: true)
                } catch {
                    self.lockSvc.log("warn", "会话重协商失败: \(error.localizedDescription)")
                    BleTelemetry.recordEvent("会话重协商失败", ok: false)
                }
            }
        }
    }

    // ---------- 130 唤醒失败细分 (BLE 未开 / 不在广播范围 / 握手超时) ----------
    struct WakeReason { let name: String; let hint: String }
    func wakeFailureReason(_ error: Error) -> WakeReason {
        let m = error.localizedDescription
        if m.contains("蓝牙未开启") { return WakeReason(name: "蓝牙未开", hint: "打开系统蓝牙后会自动重连") }
        if m.contains("权限") { return WakeReason(name: "蓝牙权限", hint: "系统设置 → 隐私与安全性 → 蓝牙 中允许本 App") }
        if m.contains("未发现") || m.contains("扫描") { return WakeReason(name: "不在广播范围", hint: "走到门锁旁 (1 米内) 再试") }
        if m.contains("超时") { return WakeReason(name: "握手超时", hint: "保持 1 米内、避开信号干扰源重试") }
        return WakeReason(name: "唤醒失败", hint: "换个时间段重试; 仍不行到诊断页跑一键体检")
    }

    // ---------- 536 失败三分类 (设备 / 蓝牙 / 协议) — 本地词表, 不改协议层 ----------
    struct FailKind { let name: String; let hint: String }
    func classifyFailure(_ error: Error) -> FailKind {
        let m = error.localizedDescription
        if m.contains("蓝牙") || m.contains("unauthorized") || m.contains("not powered") {
            return FailKind(name: "蓝牙类", hint: "检查系统蓝牙开关与权限, 开关一次蓝牙再试")
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

    /// 539 高成功率时段: 需下发成败历史, 当前占位
    static func bestHourHint() -> String {
        "时段统计积累中 — 每次下发结果会记录, 满 7 天后可见高成功率时段"
    }

    // ---------- 扫描取 RSSI (63/71 数据源) ----------
    func scan(mac: String, timeoutMs: Int = 6000) async throws -> BLEAdvDevice? {
        let ble = BLEService.shared
        try await ble.startScan(timeoutMs: timeoutMs)
        defer { ble.stopScan() }
        let target = mac.lowercased()
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        var found: BLEAdvDevice?
        while Date() < deadline, found == nil {
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

    // ---------- 每锁 RSSI 记忆 (71 设备列表迷你信号格 / 129 极限距离) ----------
    static func saveRssi(mac: String, rssi: Int) {
        DB.store.set("kf_linkrssi_" + mac, rssi)
    }
    /// 上次扫到的该锁 RSSI; nil = 从未扫到
    static func rssiFor(_ mac: String) -> Int? {
        DB.store.get(Int.self, "kf_linkrssi_" + mac)
    }

    /// 134 冷启动先扫描: App 启动广播扫描一次, 把可见已配对锁的 RSSI 落档 (不连接、不下发)
    func coldStartScan() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let ble = BLEService.shared
            guard ble.isPoweredOn, !DiagFlags.silent else { return }
            do {
                try await ble.startScan(timeoutMs: 5000)
                for adv in ble.allDiscovered() {
                    if let a = ZKProtocol.parseAdv(adv.advertisHex), let m = a.macRaw,
                       DB.keychain(m) != nil {
                        Self.saveRssi(mac: m, rssi: adv.rssi)
                    }
                }
                BleTelemetry.recordEvent("冷启动扫描 (134), 可见设备 \(ble.allDiscovered().count)", ok: true)
                DB.store.set("kf_link_env", ble.allDiscovered().count)
                DiagOps.record("冷启动扫描 (\(ble.allDiscovered().count) 台可见)")
            } catch {
                BleTelemetry.recordEvent("冷启动扫描失败", ok: false)
            }
        }
    }

    /// 128 环境拥挤度: 最近一次冷启动扫描的可见 BLE 设备数
    static var envCount: Int { DB.store.getInt("kf_link_env", 0) }
    static func envConclusion() -> String {
        let n = envCount
        if n == 0 { return "近一次扫描未见 BLE 设备 (无数据或蓝牙关闭)" }
        if n >= 20 { return "环境拥挤 (近一次扫到 \(n) 台 BLE 设备) — 商场/办公楼等密集环境, 连接偶发超时属正常, 保持 1 米内" }
        if n >= 8 { return "环境中度 (近一次扫到 \(n) 台 BLE 设备) — 可用, 干扰稍多时可贴得更近" }
        return "环境安静 (近一次扫到 \(n) 台 BLE 设备) — 连接条件良好"
    }

    /// 272 连接保持时长: 会话至今的分钟数 (异常久时 UI 提示重连)
    var holdMinutes: Int {
        sessionSince.map { Int(Date().timeIntervalSince($0) / 60) } ?? 0
    }
    /// 270/129 弱信号提示: 最近 RSSI 走弱时给"信号在变差"文案 (Hero 卡提示条)
    var weakSignalHint: String? {
        guard let r = lastRssi, r < -75 else { return nil }
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
    var body: some View {
        Form {
            Section("自动预握手") {
                Toggle("进页/回前台自动预热连接 (95/135)", isOn: Binding(
                    get: { DB.store.getBool("kf_link_auto_" + mac, true) },
                    set: { DB.store.set("kf_link_auto_" + mac, $0) }))
                LabeledRow("手动连接模式 (100)",
                           DB.store.getBool("kf_link_auto_" + mac, true) ? "自动" : "手动 — 点圆盘才连")
                LabeledRow("信号围栏 (93)", "RSSI ≥ \(DB.store.getInt("kf_rssi_fence", -70)) 才预热, 低信号不浪费电量")
                LabeledRow("连接偏好记忆 (97)", "每锁记住扫描强度与预握手偏好 (kf_linkrssi_ / kf_link_auto_)")
            }
            Section("连接统计") {
                LabeledRow("连接成功率 (70)", LinkSense.successRateText(mac))
                LabeledRow("高成功率时段 (539)", LinkSense.bestHourHint())
                LabeledRow("占用类错误 (124)", "保守文案 — 协议占用细分未确证")
                Text("成功率需 7 天握手数据积累, 当前为占位; 占用类 (124) 与高成功率时段 (539) 均备案 DEFERRED。")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle("连接与预握手")
        .scrollContentBackground(.hidden)
        .dsScreenBackground()
    }
}

/// 63/71 RSSI 四格信号条 (形状 + 档位文字双通道, 颜色不单独承载信息)。
struct RSSIBars: View {
    var level: Int                 // 0-4
    var tint: Color = DS.Palette.accentText
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < level ? tint : DS.Palette.hairline)
                    .frame(width: 3, height: CGFloat(i + 1) + 3)
            }
        }
        .accessibilityLabel("信号" + LinkSense.rssiLabel(level))
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

/// 64 三态链路胶囊 (hero 渐变专用白字变体): 已连接(绿)/握手中(白+转)/未连接(灰白)。
struct LinkPill: View {
    var state: LinkState
    var connectMs: Int? = nil
    var rssi: Int? = nil
    var source: String = ""
    var body: some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: icon)
                .font(.system(size: DS.Icon.xs, weight: .semibold))
            Text(text)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            // 98 冷热标识: 已连接时标注来源 — 预热/回连("已预热") vs 用户触发的即连, 解释快慢差异
            if state == .ready, source != "" {
                Text(source)
                    .font(.caption2.weight(.medium))
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, DS.Space.s + 2)
        .padding(.vertical, DS.Space.xs + 1)
        .background(tint.opacity(0.18), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.38), lineWidth: 0.5))
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }
    private var icon: String {
        switch state {
        case .ready: return "link.circle.fill"
        case .connecting: return "arrow.triangle.2.circlepath"
        default: return "link.circle.dashed"
        }
    }
    // 68 拟人状态文案: "门锁在线，随时可开"
    private var text: String {
        switch state {
        case .ready: return "门锁在线, 随时可开"
        case .connecting: return "正在敲门…"
        default: return "未连接"
        }
    }
    private var tint: Color {
        switch state {
        case .ready: return Color(hex: 0xBBF7D0)
        case .connecting: return .white.opacity(0.9)
        default: return .white.opacity(0.75)
        }
    }
    private var accessibilityText: String {
        text + (rssi.map { " 信号" + LinkSense.rssiLabel(LinkSense.rssiLevel($0)) } ?? "")
    }
}

/// 67 握手耗时标签 (hero 白字): 最近一次连接 ms, 超 2 秒标黄。
struct ConnectMsBadge: View {
    var ms: Int?
    var body: some View {
        if let ms {
            Label(String(ms) + "ms", systemImage: "stopwatch")
                .font(.caption2.weight(.medium))
                .foregroundStyle(ms >= 2000 ? Color(hex: 0xFFE9A8) : .white.opacity(0.85))
                .accessibilityLabel("最近一次连接耗时 " + String(ms) + " 毫秒")
        }
    }
}

/// 126 回连节律点阵: 5/15/30/60/90 五轮, 高亮当前轮; 0 轮时整排灰 = 待命。
struct ReconnectDots: View {
    var attempt: Int
    var nextWait: Int
    var body: some View {
        HStack(spacing: DS.Space.xs) {
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill(fill(i))
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            }
            Text(attempt > 0 ? "回连第 \(attempt) 轮 · 下一轮等 \(nextWait) 秒"
                 : "失联后自动回连 (5/15/30/60/90 秒)")
                .font(.caption2)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("回连节律 " + (attempt > 0 ? "第 \(attempt) 轮, 下一轮等 \(nextWait) 秒" : "待命"))
    }
    private func fill(_ i: Int) -> Color {
        if attempt > 0 && i < attempt { return DS.Palette.accent }
        if attempt > 0 && i == attempt - 1 { return DS.Palette.warn }
        return DS.Palette.hairline
    }
}

/// 136 跨页全局 BLE 状态细条: 非设备 Tab 顶部 2pt 语义细线 + 状态行, 点按跳回设备页。
struct BLEStrip: View {
    var title: String
    var state: LinkState
    var detail: String?
    var action: () -> Void
    var body: some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: stIcon)
                .font(.system(size: DS.Icon.xs, weight: .semibold))
                .foregroundStyle(stTint)
                .accessibilityHidden(true)
            Text(stText)
                .font(.caption2.weight(.medium))
                .foregroundStyle(DS.Palette.textSub)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: action) {
                Label(title, systemImage: "lock.fill")
                    .font(.caption2.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(DS.Palette.accentText)
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
        }
        .padding(.horizontal, DS.Space.gutter)
        .padding(.top, DS.Space.xs)
        .frame(minHeight: 28)
        .background(DS.Palette.surfaceAlt.opacity(0.6))
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
        default: return "wifi.slash"
        }
    }
    private var stTint: Color {
        switch state {
        case .ready: return DS.Palette.ok
        case .connecting: return DS.Palette.warn
        default: return DS.Palette.textSub
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
    var onOpen: () -> Void
    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: DS.Space.s) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: DS.Icon.sm, weight: .semibold))
                    .foregroundStyle(DS.Palette.warn)
                    .accessibilityHidden(true)
                Text("蓝牙已关闭 — 打开系统蓝牙后, 门锁才能被唤醒")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Label("去开启", systemImage: "chevron.right")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(DS.Palette.accentText)
            }
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.s + 2)
            .background(DS.Palette.warn.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("蓝牙已关闭, 点按前往系统设置开启")
        .accessibilityHint("到系统设置打开蓝牙开关")
    }
}
