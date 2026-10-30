// 包2 连接感知与离线同步 — 连接管理包装层 (只预热不执行: 绝不自动开锁/自动下发凭证)
// 编号对照 docs/ROADMAP-DRAFT.md「包2」:
//   预握手 93/95/96/134 · 状态感知 63/64/67/68/69/71 · 韧性 124/125/126/130/131/275/536 ·
//   离线队列 510/533/535/538 · 跨页 135/136/162 · 70/539 积累占位
// 底层纪律: 不改 BLEService 协议帧/命令构造器, 只包一层连接管理与 UI 组件;
// 日志复用 DiagKit 事件流水 (BleTelemetry/DiagOps) 与 LockService 分级日志。
import UIKit
import SwiftUI
import CoreGraphics
import Combine

// ---------- 链路三态 (64 语义色: 已连接 / 握手中 / 未连接) ----------
enum LinkState: Equatable {
    case ready, connecting, down
    /// 2026-10-27 截图核对新增：**连上了但开不了锁**。
    ///
    /// 起因：设备页同一屏上「门锁在线，随时可开」与「密钥尚未绑定，该门锁可能还没完成配网」
    /// 同时显示 —— 而密钥没绑定**根本开不了锁**。两句话都对，组合起来是误导，
    /// 用户会以为能开，点下去失败。
    /// 现在把「密钥未绑定」纳入链路状态，徽章就不会再说"随时可开"。
    case notReady
    var name: String {
        switch self {
        case .ready: return "已连接"
        case .connecting: return "握手中"
        case .notReady: return "密钥未绑定"
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
    /// 2026-10-29 性能：RSSI 节流基准（见 updateRssi）。
    private var lastRssiPublishAt = Date.distantPast
    var prevRssi: Int? = nil                        // 270 上一次 RSSI: 骤降检测基准 (只在值变化时翻档)
    @Published private(set) var connectMs: Int? = nil        // 67 握手耗时 (最近一次, ms)
    @Published var reconnectAttempt = 0          // 126 回连节律轮次
    /// 2026-10-29 性能：只写不读（回连节律只把它当记录），去掉 @Published。
    var lastReconnectAt: Date = Date.distantPast
    @Published private(set) var sessionSince: Date? = nil    // 272 连接保持时长基准
    @Published private(set) var lastReceipt = 0              // 535 同步回执 (最近一次补发条数)
    @Published var connectSource = "预热"        // 98 冷热连接标识: 预热/回连 vs 即连
    @Published private(set) var btOn = BLEService.shared.isPoweredOn   // 69 系统蓝牙开关镜像
    /// 「系统蓝牙关着」和「本 App 没拿到权限」是**两件事**，用户要做的事也不同。
    /// 之前只有 btOn，于是在权限被拒时也显示"蓝牙已关闭"，用户去开蓝牙、
    /// 回来还是失败 —— 因为他关掉的是另一扇门。
    @Published private(set) var btDenied = false
    @Published private(set) var receiptShownAt: Date = Date.distantPast
    @Published private(set) var revalidating = false         // 131 会话重协商进行中 (假死巡检触发, 完成即消)
    var lastLadderAt = Date.distantPast
    var lastDeadlockAt = Date.distantPast
    var reconnectTask: Task<Void, Never>?
    var deadWatchTask: Task<Void, Never>?

    private init() {}
    /// 69: 跟随 BLEService 的开关变化 (回连循环 2s tick 顺带刷新, 不另起订阅)
    func syncBtOn() {
        // 2026-10-29 性能：这个函数由 reconnectTask **每 2 秒**调一次（见 startReconnectLoop）。
        // 原来是无条件给两个 @Published 赋值 —— 即使蓝牙状态没变，也每 2 秒发一次 objectWillChange，
        // 让观察 LinkSense 的 DeviceHomeView 整页重算。等于给整个 App 挂了一个 0.5Hz 的重渲染心跳。
        // 只在真的变化时赋值。
        let on = BLEService.shared.isPoweredOn
        let denied = (BLEService.shared.powerState == .unauthorized)
        if btOn != on { btOn = on }
        if btDenied != denied { btDenied = denied }
    }
    /// 69 "去开启": 系统设置无 App 级深链 API, 只能引导用户自行开启 (文案 + 常驻提示条)
    func openBluetoothSettings() {
        // 69: iOS 没有直达"蓝牙"面板的 App 级深链, 能跳的只有本 App 的设置页 (与 DiagnosticsView 同一个出口)。
        // 这函数原来只写一行日志 —— 横幅与无障碍标签都在承诺"点按前往系统设置", 那是个不存在的热区。
        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
        lockSvc.log("info", "蓝牙开启引导： 已跳到本 App 的系统设置页 (蓝牙开关仍需在系统设置或控制中心里打开， 69)")
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
            }
            let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
            var hits = Set<String>()
            while Date() < deadline, hits.count < targets.count {
                for adv in ble.allDiscovered() {
                    // 2026-10-27 审核修复：warmLocks() 返回的是 kc.mac（显示序），而 macRaw 是线上序。
                    // 原写法拿 macRaw 与 targets 比 —— 永不相等，多锁预连从未成功过（C 线审核发现）。
                    guard let a = ZKProtocol.parseAdv(adv.advertisHex), let disp = a.macDisplay else { continue }
                    let mac = disp.replacingOccurrences(of: ":", with: "").lowercased()
                    guard targets.contains(mac), !hits.contains(mac) else { continue }
                    hits.insert(mac)
                    Self.saveRssi(mac: mac, rssi: adv.rssi)
                    lockSvc.log("info", "多锁预连： 收到 \(String(mac.prefix(6))) RSSI \(adv.rssi)")   // 276 多锁预连
                }
                if hits.count < targets.count { try? await Task.sleep(for: .milliseconds(250)) }
            }
        } catch {
            lockSvc.log("warn", "多锁预连扫描失败： \(error.localizedDescription)")
        }
    }
    /// 276 常用锁 (按本机缓存里的日志行数排): 预连只盯它们, 不是把全部锁都扫一遍
    static func warmLocks(limit: Int) -> [String] {
        // 2026-10-30 性能：这里只需要「每把锁日志缓存的条数」，不需要解码每一条 ——
        // 原来的 DB.readLogs(mac).count 会把每把锁整份 LogCache（≤300 条）解码成结构体再数数。
        // readLogCount 直接用「JSON 数组长度」从原始字节量出来，零条目解码。
        DB.keychains()
            .map { ($0.mac, DB.readLogCount($0.mac)) }
            .sorted { $0.1 > $1.1 }
            .prefix(max(1, limit))
            .map { $0.0 }
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
            // 2026-10-30（提速，第 3 项）：把首次开锁的 cmd01 往返挪到预热里 ——
            // 预热发生在「用户还没点开锁」的时候，多做一次 cmd01 不占用户时间；
            // 等真点开锁时令牌已在 20s 复用窗口内 ⇒ 首次开锁也只剩 cmd04。
            // 只在无命令在飞时预取：用户若已在开锁，宁可跳过也不撞单槽 waiter。
            if lockSvc.waiter == nil { try? await lockSvc.prefetchSession() }
        } catch {
            BleTelemetry.recordAttempt(mac: mac, ok: false, reason: classifyFailure(error).name + " " + error.localizedDescription)
            BleTelemetry.recordEvent("握手失败 " + classifyFailure(error).name, ok: false)
            reconnectAttempt += 1
        }
    }

    // 2026-10-26 精简：onPreconnectDone（预握手后触发到场补发）已删 —— 队列移除后无对象。
    // 2026-10-26 精简：resync（到场/回前台自动补发队列）已删 —— 队列功能整套移除。


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
                // 2026-10-30（提速，第 2 项）：**自动开锁的最大延迟源**。
                // 门锁一旦连上就停止广播，`didDiscover` 不再产生样本 —— 武装判定只能靠这一拍
                // 主动读 `readLinkRSSI`。原来固定 2 秒一拍 ⇒ 到场判定最多滞后 2 秒。
                // 开着自动开锁时提到 0.5 秒（4×），把「走到门口 → 开锁」压到 0.5s 内；
                // **关着时保持 2 秒** —— 不为一个没用到的功能付电量。
                // 注：`readLinkRSSI` 走的是 CoreBluetooth 的 `readRSSI()`（系统 API，不占协议往返），
                // 所以提速不增加协议开销，只多几次系统级 RSSI 查询。
                try? await Task.sleep(for: .seconds(AutoOpen.on ? 0.5 : 2))
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
            }
        } else {
            // 用户口径 2026-10-17: **后台不许扫锁** (不耗手机射频, 也不逼锁一直广播费它的电)。
            // sceneActive=false 让 2s tick 不再发起; 这里补一刀把**正在进行**的那轮立刻停掉 ——
            // 否则退后台后那轮扫描还要跑满 6~10s 超时才自然停。
            BLEService.shared.stopScan()
        }
    }

    /// 98 用户主动路径 (圆盘开锁前 ensureConnected) 标记为"即连", 解释快慢差异
    func noteUserConnect() {
        connectSource = "即连"
        sessionSince = Date()
    }

    // ---------- 状态记账 ----------
    /// 270 统一 RSSI 入口: 旧值翻入 prevRssi 再更新现值 —— 四处喂入共用一份历史, 骤降提示才有基准
    func updateRssi(_ r: Int) {
        if let cur = lastRssi, cur != r { prevRssi = cur }
        // 2026-10-29 性能：BLE 广播每秒来好几次，而 lastRssi 是 @Published ——
        // 每来一次都会让观察 LinkSense 的 DeviceHomeView（hero 卡 + 开锁圆盘 + 快捷格）整页重算。
        // 现在：展示值最多 2 秒刷新一次；只有骤变（≥15 dBm，比如走近/走远）才立刻推。
        // prevRssi 仍逐次记录，骤降检测拿到的历史不受影响。
        let now = Date()
        let bigJump = lastRssi == nil || abs(r - (lastRssi ?? r)) >= 15
        if bigJump || now.timeIntervalSince(lastRssiPublishAt) >= 2 {
            lastRssi = r
            lastRssiPublishAt = now
        }
    }
    func markReady(ms: Int?, rssi: Int?) {
        connectMs = ms
        sessionSince = Date()
        reconnectAttempt = 0
        if let rssi { updateRssi(rssi) }
        // 2026-10-29 性能：上一行的 @Published 赋值已经发过一次，这里再手发一次等于双倍重算。
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
    func deadbeatCheck() {
        guard !DiagFlags.silent else { return }
        let mac = lockSvc.connectedMAC
        guard !mac.isEmpty, lockSvc.connectedMAC == mac else { return }
        let idle = sessionSince.map { Date().timeIntervalSince($0) } ?? 0
        guard idle > 600, Date().timeIntervalSince(lastDeadlockAt) > 300 else { return }
        lastDeadlockAt = Date()
        revalidating = true
        lockSvc.log("info", "会话巡检： 连接已挂 \(Int(idle / 60)) 分钟， 重新校验会话")   // 275/131 会话巡检
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
                    self.lockSvc.log("warn", "会话重协商失败： \(error.localizedDescription)")
                    BleTelemetry.recordEvent("会话重协商失败", ok: false)
                }
            }
        }
    }

    // ---------- 130 唤醒失败细分 ----------
    // 已删: WakeReason 的四分法 (蓝牙未开/权限/不在广播范围/握手超时) 与在用的两处重合 ——
// 日志侧分类走下面的 classifyFailure (536)。
// 2026-10-27 审核修复 (AUDIT-B 2.8 #5)：原注释说「人话提示走 DiagnosticsView.friendlyFailReason」，
// 而 `DiagnosticsView.swift` 已随十三轮精简整文件删除（全仓 0 命中）。
// 现在人话提示走本文件的 `classifyFailure` + `AXTools.announceConnectFail`。
    // 后者覆盖面更大 (还含 信号弱/回连轮次/会话重协商)。留第三份同表只会让三处漂移。

    // ---------- 536 失败三分类 (设备 / 蓝牙 / 协议) — 本地词表, 不改协议层 ----------
    struct FailKind {
        let name: String
        let hint: String
        /// 130 图标细分: 三类各配一枚图标。名称全部取自本仓已在用的 SF Symbol
        /// (不臆造 systemName —— 名字错了真机上只会显示空白)。做成计算属性而不是新增字段:
        /// 加字段要全仓改签初始化器 (DiagKit（原 :560，该文件已拆分，行号失效） 记过这件事), 这里零调用点改动。
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
            return FailKind(name: "蓝牙类", hint: "检查系统蓝牙开关与权限， 开关一次蓝牙再试")
        }
        // 536: "指令被拒"档 —— 服务层对锁端 rc != 0 一律以 StatusParser.rcMessage(rc) 抛错
        // (LockService（原 :282，该文件已拆分，行号失效）/:498、HardwareService:236/:246), 所以错误串命中 rc 表文案 = 锁端拒绝了指令。
        // 只取 4 字及以上的码文案: "丢包"/"溢出" 这类两字词出现在别的串里会误判。
        let rcTexts = StatusParser.rcMsg.filter { $0.key != 0 && $0.value.count >= 4 }.map { $0.value }
        if rcTexts.contains(where: { m.contains($0) }) || m.hasPrefix("错误码 ") {
            return FailKind(name: "指令被拒", hint: // 2026-10-30 修复（第 86 轮）：原句写「到诊断页『错误码对照表』」——
// 但诊断页已随十三轮精简**整族删除**（见 SettingsView 自述），用户找不到它。
// 改指向真实存在的「设置-锁段-协议自测」（ProtocolTestView，可发回声探测确认链路）。
"锁端拒绝了这条指令 — 多为权限/状态不满足， 可重试一次; 反复失败可到「设置-锁段-协议自测」查链路")   // 159 锁端拒绝了这条指令
        }
        if m.contains("未发现") || m.contains("扫描") || m.contains("超时") {
            return FailKind(name: "设备类", hint: "确认门锁通电并靠近 1 米内; 频繁失败先查电量")
        }
        return FailKind(name: "协议类", hint: "会话/指令异常 — 到「设置-锁段-协议自测」确认链路， 或重置重配该锁")
    }




    // ---------- 扫描取 RSSI (63/71 数据源) ----------
    func scan(mac: String, timeoutMs: Int = 6000) async throws -> BLEAdvDevice? {
        let ble = BLEService.shared
        let scanT0 = Date()   // 285: 扫描时长自查的计时起点
        try await ble.startScan(timeoutMs: timeoutMs)
        defer {
            ble.stopScan()
        }
        let target = mac.lowercased()
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        var found: BLEAdvDevice?
        // 2026-10-14: 补取消判据 (与 LockService 的扫描循环同口径), 否则上层取消后仍空转到超时。
        while Date() < deadline, found == nil, !Task.isCancelled {
            found = ble.allDiscovered().first { adv in
                // 2026-10-27 审核说明 (AUDIT-A F-35)：这里**同时接受两种 MAC 序**
                // （下面一行同时比 macRaw 与 macDisplay），而 Android 只认显示序。
                // 本仓宽松是有意的：老钥匙串可能按另一种序配过，只认一种会让它们连不上。
                // Android 那边只有 3 条命令、不存在历史包袱，所以它不需要两序。
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
        // 用户主动下拉重扫，立即刷新（@Published 赋值本身就会发通知，不需再手发）。
        lastRssi = rssi
        lastRssiPublishAt = Date()
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
    /// 冷启动扫描的任务句柄。2026-10-26: 原来是裸 Task —— 视图销毁后它照跑，
    /// 与 `.task` 的取消语义不一致（`.task` 修饰符内的子任务会随视图取消，裸 Task 不会）。
    /// 现在留着句柄，第二次调用先取消上一次，避免"重复冷扫"叠加。
    var coldScanTask: Task<Void, Never>?
    /// 启动预连接的任务句柄（同上）。startupPreconnect 与 enterPage 都会调 preconnect，
    /// 并存时会各自建链 —— 由 LinkSense 内部去重兜底，但句柄让"后来的覆盖先前"可显式表达。
    var preconnectTask: Task<Void, Never>?

    func coldStartScan() {
        coldScanTask?.cancel()
        coldScanTask = Task { @MainActor [weak self] in
            guard self != nil, !Task.isCancelled else { return }   // 只为"已销毁/已取消就别扫"
            let ble = BLEService.shared
            guard ble.isPoweredOn, !DiagFlags.silent else { return }
            do {
                // 123: 冷启动扫描时长/去重跟随用户档位 (默认 5s = 旧硬编码值, 不改变既有行为)
                let p = BLEService.ScanProfile.current
                let t0 = Date()
                try await ble.startScan(allowDuplicates: p.allowDuplicates, timeoutMs: p.timeoutMs)
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
                    // 2026-10-27 审核修复：DB.keychain 的键是显示序（去冒号小写），
                    // 而 macRaw 是线上序 ⇒ `DB.keychain(macRaw)` 恒 nil，冷启动扫描落档一条都写不进去。
                    if let a = ZKProtocol.parseAdv(adv.advertisHex), let disp = a.macDisplay,
                       DB.keychain(disp.replacingOccurrences(of: ":", with: "").lowercased()) != nil {
                        Self.saveRssi(mac: disp.replacingOccurrences(of: ":", with: "").lowercased(), rssi: adv.rssi)
                    }
                }
                let seen = ble.allDiscovered().count
                BleTelemetry.recordEvent("冷启动扫描， 可见设备 \(seen)", ok: true)   // 134 冷启动扫描
                DB.store.set("kf_link_env", seen)
                DB.store.set("kf_link_envms", firstSeenMs)
                DiagOps.record("冷启动扫描 (\(seen) 台可见， 首台 \(firstSeenMs >= 0 ? "\(firstSeenMs)ms" : "整窗未见"))")
            } catch {
                BleTelemetry.recordEvent("冷启动扫描失败", ok: false)
            }
        }
    }

    /// 128 环境拥挤度: 最近一次冷启动扫描的可见 BLE 设备数 + 首台可见耗时
    static var envCount: Int { DB.store.getInt("kf_link_env", 0) }
    /// 128: 首台可见耗时 (毫秒); -1 = 整窗一台没见
    static var envFirstSeenMs: Int { DB.store.getInt("kf_link_envms", -1) }
    // 【保留未接 2026-10-29】环境结论（信号弱/干扰大）—— 诊断页已删，留给将来的连接自检
    static func envConclusion() -> String {
        let n = envCount
        let ms = envFirstSeenMs
        let t = ms >= 0 ? ", 首台 \(ms)ms 可见" : ""
        if n == 0 { return "近一次扫描未见 BLE 设备 (无数据或蓝牙关闭)" }
        if n >= 20 { return "环境拥挤 (近一次扫到 \(n) 台 BLE 设备\(t)) — 商场/办公楼等密集环境， 连接偶发超时属正常， 保持 1 米内" }
        if n >= 8 { return "环境中度 (近一次扫到 \(n) 台 BLE 设备\(t)) — 可用， 干扰稍多时可贴得更近" }
        return "环境安静 (近一次扫到 \(n) 台 BLE 设备\(t)) — 连接条件良好"
    }

    /// 272 连接保持时长: 会话至今的分钟数 (异常久时 UI 提示重连)
    var holdMinutes: Int {
        sessionSince.map { Int(Date().timeIntervalSince($0) / 60) } ?? 0
    }

    // ---------- 268 状态变化历史: 最近 5 次链路三态切换 (长按胶囊时间线) ----------
    struct StateHop: Codable { let at: String; let to: String }
    static func history() -> [StateHop] {
        DB.store.get([StateHop].self, "kf_link_hist") ?? []
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
        preconnectTask?.cancel()
        preconnectTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            await self.preconnect()
            guard !Task.isCancelled else { return }
        }
    }

}

// ---------- AppState 宿主注册 (LinkSense 只读协作, 不建循环依赖) ----------
extension AppState {
    /// 全 App 唯一的 AppState 弱引用入口 (由 RootView 挂载时赋值)。
    /// `nonisolated(unsafe)`: 读取方跨隔离域 (BLE 回调 / 通知代理 / 后台 Task),
    /// 而写入只在主 actor 的 onAppear。本仓既有约定是「读一次拿局部引用, 不缓存跨调用」,
    /// 所以这里显式标注而不是加 @MainActor —— 加了会让所有后台读点编译不过。
    nonisolated(unsafe) static var hostRef: AppState?
}

// ================= UI 组件 (颜色只经 DS 令牌, hero 渐变白字用既有半透明变体) =================


/// 63/71 RSSI 四格信号条 (形状 + 档位文字双通道, 颜色不单独承载信息)。
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




/// 69 蓝牙直通条: 系统蓝牙关闭时全 App 顶部引导条 (深链不可用 → 系统设置指引文案)。
