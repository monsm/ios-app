// 靠近自动开锁 — AUTOOPEN-PLAN.md 落地 (docs)
// 门控链 F0 前台 / F1 面容双档 / F2' 停留 / F3 距离标定 / F4 布防互锁 / F5 一次性 / F6 锁态,
// 全绿才经既有 LockService.unlock 管线下发 cmd04 (不改协议/命令构造); 任一门不过 = 静默拒绝 + 审计落盘
// (审计只记"哪道门拒了、哪把锁、何时", 永不记 ekey/skey 明文)。默认全关、fail-closed。
// 96 铁律对照: 本特性是 96 的显式用户开关例外 — 未开 = 绝不自动开锁, 开 = 全门绿才出手。
import Foundation
import CoreMotion
import LocalAuthentication
import UIKit

// ================= 存储 accessor (Store.swift 同步, kf.* 自动进备份) =================
enum AutoOpen {
    /// 主开关 (默认关): kf_autoopen
    static var on: Bool {
        get { DB.store.getBool("kf_autoopen", false) }
        set { DB.store.set("kf_autoopen", newValue) }
    }
    /// 面容档位: 0 标准(静默复用≤60s) / 1 严格(进前台必刷): kf_autoopen_face
    static var faceTier: Int {
        get { DB.store.getInt("kf_autoopen_face", 0) }
        set { DB.store.set("kf_autoopen_face", newValue) }
    }
    /// rc=26 防拆事件自动关闭 24h: 到点前一律 fail-closed 拒 (kf_autoopen_suspend_until_<mac>, epoch ms)
    static func suspendUntil(_ mac: String) -> Int64 {
        guard let v = DB.store.get("kf_autoopen_suspend_until_" + mac, Int64.self) else { return 0 }
        return v
    }
    static func setSuspendUntil(_ mac: String, _ ms: Int64) {
        DB.store.set("kf_autoopen_suspend_until_" + mac, ms)
    }
    static func isSuspended(mac: String, now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        let t = suspendUntil(mac)
        return t > 0 && Double(t) / 1000.0 > now
    }

    // ---------- 审计: 只记哪道门拒了, 永不记密钥材料; 尾段 500 条 ----------
    struct AuditEntry: Codable {
        var at: String        // 手机侧 mm-dd HH:mm
        var mac: String
        var reason: String    // 门名 + 拒因 (哪道门 F0-F6)
    }
    static func audit(_ mac: String, _ reason: String) {
        var list = audits(mac)
        list.insert(AuditEntry(at: DiagTime.mmddHHmm(), mac: mac, reason: reason), at: 0)
        if list.count > 500 { list = Array(list.prefix(500)) }
        DB.store.set("kf_autoopen_audit_" + mac, list)
    }
    static func audits(_ mac: String) -> [AuditEntry] {
        DB.store.get([AuditEntry].self, "kf_autoopen_audit_" + mac) ?? []
    }
    static func lastReject(_ mac: String) -> AuditEntry? { audits(mac).first }
    /// 诊断页最近 3 条拒开记录
    static func recent(_ mac: String, _ n: Int) -> [AuditEntry] {
        Array(audits(mac).prefix(n))
    }

    // ---------- F3 标定: kf_autocal_<mac> 锁×手机对的 RSSI P95 ----------
    struct AutoCal: Codable { var rssiP95: Int; var at: Double }
    static func autocal(_ mac: String) -> AutoCal? {
        DB.store.get(AutoCal.self, "kf_autocal_" + mac)
    }
    static func saveAutocal(_ mac: String, _ c: AutoCal) {
        DB.store.set("kf_autocal_" + mac, c)
    }
    static func removeAutocal(_ mac: String) {
        DB.store.remove("kf_autocal_" + mac)
    }
    /// 删除设备时随每锁数据族清 (DB.removeDevice 已按族清 kf_autocal_/kf_autoopen_audit_/kf_autoopen_suspend_until_ 前缀键)

    /// §3.4 标准档风险披露文案 (强制展示, 不得弱化)
    static let riskDisclosure = "标准档: 最近 60 秒内无需重新刷脸。注意——这 60 秒内别人拿走手机也能开门。介意请切严格档。"
}

// ================= 纯逻辑: 门控判定 / 标定 / 滤波器 / 0E 双确认 (可单测, 无 UI 依赖) =================
enum AutoOpenKit {

    // ---------- F4 布防互锁: control==2 时段布防, 当前时刻在 start/end 内 → 一票否决 (跨午夜 start>end) ----------
    /// startSec/endSec 为日内秒 (SETDEFENCE 协议口径, 半秒分辨率); 仅 control==2 生效, 0/1/3 不拒。
    /// 跨午夜: start > end 时时段 = [start, 24h) ∪ [0, end); start == end 视为无时段 (fail-closed 不判布防)。
    /// cal 注入保证 CI 可测 (UTC 基准); 生产走设备当前时区。
    static func defendActive(control: Int, startSec: Int, endSec: Int, now: Date, cal: Calendar = .current) -> Bool {
        guard control == 2 else { return false }
        guard startSec != endSec else { return false }
        let comps = cal.dateComponents([.hour, .minute, .second], from: now)
        let secOfDay = ((comps.hour ?? 0) * 3600 + (comps.minute ?? 0) * 60 + (comps.second ?? 0)) * 2
        if startSec < endSec {
            return secOfDay >= startSec && secOfDay < endSec
        }
        return secOfDay >= startSec || secOfDay < endSec
    }

    // ---------- F1 面容双档: 标准=60s 窗口静默复用 / 严格=进前台必刷 (LAContext 经 FaceService 注入) ----------
    /// 窗口边界常量 (表驱动可测): 标准档 60s 内静默通过, 超过即拒; 严格档要求本次进前台刷过脸
    /// (pendingPrompt = 严格档弹窗在途, 视为"正在确认", 由调用方在下发前复核 lastFace 已刷新)。
    static func faceFresh(tier: Int, lastFace: Date?, now: Date, pendingPrompt: Bool) -> Bool {
        let window: TimeInterval = 60
        guard let lf = lastFace else {
            // 从未刷过脸: 严格档弹窗在途可放行本次尝试 (下发前锁仍会因 rc 门兜底), 标准档必拒
            return tier == 1 && pendingPrompt
        }
        let age = now.timeIntervalSince(lf)
        if tier == 0 {
            return age < window
        }
        // 严格档: 60s 窗口内刷过, 或弹窗在途
        return age < window || pendingPrompt
    }

    // ---------- F3 距离标定: P95 取法 (线性插值) ----------
    static func p95(_ samples: [Int]) -> Int? {
        guard samples.count >= 5 else { return nil }
        let sorted = samples.sorted()
        let rank = Double(sorted.count - 1) * 0.95
        let lo = Int(rank.rounded(.down)), hi = Int(rank.rounded(.up))
        let frac = rank - Double(lo)
        if lo == hi { return sorted[lo] }
        let v = Double(sorted[lo]) + (Double(sorted[hi]) - Double(sorted[lo])) * frac
        return Int(v.rounded())
    }
    /// 标定基准: 有按锁标定时取 P95; 未标定 = nil → F3 门不过 (fail-closed)
    static func rssiBase(mac: String) -> Int? {
        AutoOpen.autocal(mac)?.rssiP95
    }
    /// F3 回差阈值: 武装线 = 基准 × 0.7 (RSSI 越接近 0 越强); 解除线 = 基准 × 0.5 (掉回才解除, 防门口来回抖动)。
    /// 调参: 系数 0.7/0.5 为方案默认, 现场标定后可调。
    static func armThreshold(base: Int) -> Int { Int((Double(base) * 0.7).rounded()) }
    static func disarmThreshold(base: Int) -> Int { Int((Double(base) * 0.5).rounded()) }

    /// RSSI 回差滤波 (纯函数): 已武装需掉到解除线以下才解除; 未武装需越过武装线才武装。
    /// 基准 P95 (如 -60): 武装线 = 0.7× = -42, 解除线 = 0.5× = -30 — RSSI 比解除线弱才解除, 防门口来回抖动。
    static func rssiSample(prevArmed: Bool, rssi: Int, base: Int) -> Bool {
        let arm = armThreshold(base: base)
        let disarm = disarmThreshold(base: base)
        if prevArmed {
            return rssi > disarm
        }
        return rssi >= arm
    }

    // ---------- F5 冷却: 每次接近事件只发一次 04, 成功后 60s 冷却 ----------
    static let cooldownSeconds: TimeInterval = 60
    static func coolReady(lastDispatch: TimeInterval, now: TimeInterval) -> Bool {
        lastDispatch == 0 || now - lastDispatch > cooldownSeconds
    }

    // ---------- 0E 双确认 (rc=3 自愈校时): 30s < |偏差| < 24h 才写; ≥24h 仅 NTP 对表一致时放宽到 48h ----------
    /// phoneProto = 手机协议秒, lockProto = 锁协议秒 (03 #04), ntpConfirmed = 有网且 NTP 对表偏差 < 5min。
    /// 防"把错手机时间写进锁 → 全凭证时间窗集体错乱"自伤 DoS。
    static func dualTimeSync(phoneProto: Int64, lockProto: Int64, ntpConfirmed: Bool) -> Bool {
        let dev = abs(phoneProto - lockProto)
        if dev < 30 { return false }           // 偏差在容差内, 无需写 (rc=3 走既有刷令牌路径)
        if dev < 24 * 3600 { return true }      // 30s < 偏差 < 24h → 自动写 (自愈)
        if ntpConfirmed && dev < 48 * 3600 { return true }
        return false
    }

    // ---------- F1 面容成功时刻记账 (进程内语义: 重启即失效 = fail-closed) ----------
    private static var _lastFace: Date? = nil
    private static let lock = NSLock()
    static func noteFaceSuccess() {
        lock.lock()
        _lastFace = Date()
        lock.unlock()
    }
    static func lastFace() -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return _lastFace
    }
}

// ================= 门控矩阵: 全绿才允许下发 04 =================
struct AutoOpenGate {
    var f0Foreground: Bool        // App 前台且已解锁 (sceneActive && appUnlocked)
    var faceTier: Int             // 0 标准 / 1 严格
    var lastFace: Date?          // 最近一次面容成功时刻 (nil = 从未)
    var facePendingPrompt: Bool  // 严格档弹窗在途
    var now: Date
    var defendControl: Int       // DB.defend(mac)?.control ?? 0 (无布防 = 0)
    var defendStartSec: Int
    var defendEndSec: Int
    var rssiArmed: Bool          // F3 滤波当前态
    var calibrated: Bool         // 该锁做过距离标定
    var dwellMet: Bool           // F2' 降速/静置 ≥3s 已满足
    var coolReady: Bool          // F5 冷却: 上一次下发距今 >60s
    var lockReady: Bool          // F6: 非 busy(25) 且非防拆(26)

    enum Reject: Equatable {
        case off                 // 主开关未开
        case suspended           // rc=26 自动挂起到点前
        case f0                  // 非前台/App 未解锁
        case f1face             // 面容档不满足 (无面容/过期/严格未刷)
        case f4defend          // 布防时段一票否决
        case f3nocal           // 未标定
        case f3rssi            // 信号未武装
        case f2dwell           // 停留未满足 (移动中)
        case f5cool            // 60s 冷却中
        case f6busy            // 锁忙 / 防拆 (锁态门)
        case none
    }

    /// 返回拒因; .none = 全绿可下发。顺序即门序: 开关/挂起 → F0 → F1 → F4 → F3 → F2' → F5 → F6。
    func rejectReason(
        autoOpenOn: Bool,
        suspended: Bool,
        faceAvailable: Bool
    ) -> Reject {
        guard autoOpenOn else { return .off }
        guard !suspended else { return .suspended }
        guard f0Foreground else { return .f0 }
        guard faceAvailable else { return .f1face }
        guard AutoOpenKit.faceFresh(tier: faceTier, lastFace: lastFace, now: now, pendingPrompt: facePendingPrompt)
        else { return .f1face }
        guard !AutoOpenKit.defendActive(control: defendControl, startSec: defendStartSec, endSec: defendEndSec, now: now)
        else { return .f4defend }
        guard calibrated else { return .f3nocal }
        guard rssiArmed else { return .f3rssi }
        guard dwellMet else { return .f2dwell }
        guard coolReady else { return .f5cool }
        guard lockReady else { return .f6busy }
        return .none
    }

    /// 人话拒因 (审计文案: 门名 + 时刻 + 哪道门)
    static func rejectText(_ r: Reject) -> String {
        switch r {
        case .off: return "主开关未开"
        case .suspended: return "rc=26 防拆挂起, 自动开锁 24h 内禁用"
        case .f0: return "F0 非前台/App 未解锁"
        case .f1face: return "F1 面容未确认或已过期 (标准 60s 窗口 / 严格必刷)"
        case .f4defend: return "F4 布防时段内, 一票否决"
        case .f3nocal: return "F3 未做距离标定"
        case .f3rssi: return "F3 信号未达武装线"
        case .f2dwell: return "F2' 未停留满 3s (移动中)"
        case .f5cool: return "F5 60s 冷却中"
        case .f6busy: return "F6 锁态未知或忙 (rc=25/无 03 回显)"
        case .none: return "可开"
        }
    }
}

// ================= 面容抽象 (F1, LAContext 可 mock) =================
protocol FaceService {
    var biometricAvailable: Bool { get }
    /// 严格档: 进前台必弹 (LAContext.evaluatePolicy 系统弹窗), 成功即记 lastFace
    func promptFace()
    /// 标准档: 静默复用 ≤60s 生物窗口 — 不弹窗, 窗口内成功才刷新 lastFace, 窗口外不刷 = F1 门保持不过
    func silentRefresh()
}

struct SystemFaceService: FaceService {
    func promptFace() {
        Task { @MainActor in
            var err: NSError?
            let ctx = LAContext()
            guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err),
                  err?.code != LAError.biometryNotAvailable.rawValue else { return }
            ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                               localizedReason: "确认是你, 才允许靠近自动开门") { ok, _ in
                if ok { AutoOpenKit.noteFaceSuccess() }
            }
        }
    }
    func silentRefresh() {
        Task { @MainActor in
            var err: NSError?
            let ctx = LAContext()
            guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err),
                  err?.code != LAError.biometryNotAvailable.rawValue else { return }
            ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                               localizedReason: "静默确认在场") { ok, _ in
                if ok { AutoOpenKit.noteFaceSuccess() }
            }
        }
    }
}

// ================= F2' 停留判定: 加速度计方差窗口 (降速/静置 ≥3s) =================
/// 简化: 加速度计 20Hz, 滑窗 30 帧 (1.5s), 方差 < 阈值 判为静置; 连续静置 ≥3s = 停留满足 (堵"骑车路过")。
/// 阈值 0.05 (m/s²)² 为常量。调参: 口袋/桌面微动 vs 走动, 现场标定后可调。
enum MotionStillness {
    static let varianceThreshold = 0.05
    static let stillnessSeconds: Double = 3.0
    static let windowFrames = 30
    private static var samples: [(t: Double, x: Double, y: Double, z: Double)] = []
    private static var stillSince: Double? = nil
    private static var mgr: CMMotionManager? = nil

    static func start() {
        guard mgr == nil else { return }
        let m = CMMotionManager()
        guard m.isAccelerometerAvailable else { return }
        m.accelerometerUpdateInterval = 1.0 / 20.0
        mgr = m
        m.startAccelerometerUpdates(to: .main) { data, _ in
            guard let d = data else { return }
            feed(x: Double(d.acceleration.x), y: Double(d.acceleration.y), z: Double(d.acceleration.z))
        }
    }
    static func stop() {
        mgr?.stopAccelerometerUpdates()
        mgr = nil
        samples.removeAll()
        stillSince = nil
    }
    /// 喂入一帧 (可单测: 喂模拟轨迹判 静止/路过)
    static func feed(x: Double, y: Double, z: Double) {
        let now = Date().timeIntervalSince1970
        samples.append((now, x, y, z))
        if samples.count > windowFrames { samples.removeFirst(samples.count - windowFrames) }
        if variance() < varianceThreshold {
            if stillSince == nil { stillSince = now }
        } else {
            stillSince = nil
        }
    }
    /// 当前是否已静置满 3s (单测口径: 喂入时间戳判定)
    static func met(at now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard let s = stillSince else { return false }
        return now - s >= stillnessSeconds
    }
    private static func variance() -> Double {
        guard samples.count >= windowFrames else { return 1 }
        let n = Double(samples.count)
        let mx = samples.reduce(0) { $0 + $1.x } / n
        let my = samples.reduce(0) { $0 + $1.y } / n
        let mz = samples.reduce(0) { $0 + $1.z } / n
        var acc = 0.0
        for s in samples {
            acc += (s.x - mx) * (s.x - mx) + (s.y - my) * (s.y - my) + (s.z - mz) * (s.z - mz)
        }
        return acc / (n * 3.0)
    }
}

// ================= 控制器: 状态机 + 全门绿才走既有 unlock 管线下发 04 =================
@MainActor
final class AutoOpenController {
    static let shared = AutoOpenController()
    let face: FaceService
    private var armed = false
    private var armedMac = ""
    private var lastDispatch: TimeInterval = 0     // F5: 上次成功下发时刻
    private var inFlight = false

    init(face: FaceService = SystemFaceService()) {
        self.face = face
    }

    // ---------- F0/F1: 进前台 (RootView scenePhase .active) ----------
    func onForeground(mac: String) {
        guard AutoOpen.on, !mac.isEmpty else { return }
        guard !AutoOpen.isSuspended(mac: mac) else { return }   // rc=26 挂起期不弹面容, 门保持不过
        MotionStillness.start()
        if AutoOpen.faceTier == 1 {
            face.promptFace()
        } else {
            face.silentRefresh()
        }
    }
    func onBackground() {
        guard AutoOpen.on else { return }
        // 退后台: 清武装态 (F0 同时失效, 双保险)
        armed = false
    }

    // ---------- F3 喂入: RSSI 事件 (LinkSenseKit saveRssi 后调) ----------
    func feedRssi(mac: String, rssi: Int) {
        guard AutoOpen.on else { return }
        if mac != armedMac { armedMac = mac; armed = false }
        guard let base = AutoOpenKit.rssiBase(mac: mac) else { return }
        armed = AutoOpenKit.rssiSample(prevArmed: armed, rssi: rssi, base: base)
    }
    func rssiArmed() -> Bool { armed }

    // ---------- F2': RSSI 武装 + 静置 ≥3s → 触发一次门判定 (LinkSense 2s tick 驱动) ----------
    func tickDwell(mac: String) {
        guard AutoOpen.on, armed else { return }
        guard MotionStillness.met() else { return }
        attempt(mac: mac)
    }

    // ---------- 全门判定 + 下发 (每个接近事件只发一次: F5) ----------
    func attempt(mac: String) {
        guard AutoOpen.on, !inFlight else { return }
        guard let app = AppState.hostRef else { return }
        guard app.currentMac == mac, !mac.isEmpty else { return }
        guard app.unlockState == .idle else { return }

        let ctx = makeContext(mac: mac, app: app)
        let rej = ctx.rejectReason(
            autoOpenOn: true,
            suspended: AutoOpen.isSuspended(mac: mac),
            faceAvailable: face.biometricAvailable
        )
        switch rej {
        case .none:
            inFlight = true
            Task { await self.dispatch(mac: mac, app: app) }
        default:
            let door = Self.doorName(mac: mac)
            AutoOpen.audit(mac, "拒开 " + AutoOpenGate.rejectText(rej) + " · " + door)
        }
    }

    private func makeContext(mac: String, app: AppState) -> AutoOpenGate {
        let d = DB.defend(mac)
        let snap = app.snapshot
        let coolReady = AutoOpenKit.coolReady(lastDispatch: lastDispatch, now: Date().timeIntervalSince1970)
        return AutoOpenGate(
            f0Foreground: LinkSense.shared.sceneActive && app.appUnlocked,
            faceTier: AutoOpen.faceTier,
            lastFace: AutoOpenKit.lastFace(),
            facePendingPrompt: false,
            now: Date(),
            defendControl: d?.control ?? 0,
            defendStartSec: d?.startSec ?? 0,
            defendEndSec: d?.endSec ?? 0,
            rssiArmed: armed,
            calibrated: AutoOpenKit.rssiBase(mac: mac) != nil,
            dwellMet: armed && MotionStillness.met(),
            coolReady: coolReady,
            lockReady: !(snap?.rc == 25 || snap?.rc == 26)
        )
    }

    private func dispatch(mac: String, app: AppState) async {
        defer { inFlight = false }
        do {
            try await app.lock.ensureConnected(mac: mac)
            lastDispatch = Date().timeIntervalSince1970
            let rc = try await app.lock.unlock(mac: mac)
            switch rc {
            case 0:
                // 成功: 60s 冷却起算 (lastDispatch 已置), 复位武装让下次需重新靠近
                armed = false
                _ = try? await app.lock.getStatus()   // 顺带刷新 F6 锁态快照
            case 3:
                // 0E 双确认自愈 (rc=3 命令过期): 30s < |偏差| < 24h 才写, ≥24h 只提示不写
                await selfHealTime(mac: mac)
            case 5:
                // G3 times 语义未确证: 只提示, 不自动重签 (方案 §3.3 前置实验未过前保持保守)
                AutoOpen.audit(mac, "rc=5 次数用完 — 提示联系主人换钥, 不自动重签")
                app.showToast("凭证次数用完 (rc=5) — 请联系主人换钥, 不自动重签")
            case 25:
                AutoOpen.audit(mac, "rc=25 锁正忙, 拒绝自动开锁")
            case 26:
                // 防拆: 拒 + 自动关自动开锁 24h (记审计 + 挂起键)
                AutoOpen.setSuspendUntil(mac, Int64(Date().timeIntervalSince1970 * 1000) + 24 * 3600 * 1000)
                AutoOpen.audit(mac, "rc=26 防拆事件 → 自动关自动开锁 24h")
                app.showToast("检测到防拆事件, 自动开锁已暂停 24 小时")
            default:
                AutoOpen.audit(mac, "rc=\(rc) " + StatusParser.rcFriendly(rc))
            }
        } catch {
            AutoOpen.audit(mac, "下发异常 " + error.localizedDescription)
        }
    }

    /// 0E 双确认自愈校时: 读锁钟算偏差, 按 dualTimeSync 判定; ≥24h 只提示不写 (防自伤 DoS)
    private func selfHealTime(mac: String) async {
        guard let app = AppState.hostRef else { return }
        guard let lockSec = try? await app.lock.readLockTime() else {
            AutoOpen.audit(mac, "rc=3 读锁钟失败, 未自动校时")
            return
        }
        let phone = ZKProtocol.nowProtoSeconds()
        let write = AutoOpenKit.dualTimeSync(phoneProto: phone, lockProto: lockSec, ntpConfirmed: false)
        if write {
            do {
                try await app.lock.syncTime()
                AutoOpen.audit(mac, "rc=3 → 偏差 \(abs(phone - lockSec))s 在 30s~24h 窗内, 已自动校时 (0E 双确认)")
            } catch {
                AutoOpen.audit(mac, "rc=3 → 自动校时失败 " + error.localizedDescription)
            }
        } else {
            let dev = Int(abs(phone - lockSec))
            AutoOpen.audit(mac, "rc=3 → 偏差 \(dev)s 超出双确认窗, 只提示不写 (0E 双确认)")
            app.showToast("锁钟偏差约 \(dev / 3600) 小时 — 为避免误写仅提示, 请手动校准门锁时间")
        }
    }

    static func doorName(mac: String) -> String {
        DB.keychain(mac)?.name ?? String(mac.prefix(6))
    }
}

// ================= 标定页 (F3): 静止走近一次采集 RSSI P95 → 存 kf_autocal_<mac> =================
struct AutoCalView: View {
    var mac: String
    @EnvironmentObject var app: AppState
    @State private var calibrating = false
    @State private var collected = 0

    var body: some View {
        Form {
            Section("距离标定 (F3)") {
                if let c = AutoOpen.autocal(mac) {
                    LabeledRow("当前 P95 基准", "RSSI \(c.rssiP95)")
                    LabeledRow("武装线 / 解除线 (回差)",
                               "\(AutoOpenKit.armThreshold(base: c.rssiP95)) / \(AutoOpenKit.disarmThreshold(base: c.rssiP95))")
                } else {
                    LabeledRow("当前基准", "未标定 — 未标定则 F3 门不过")
                }
                BusyButton(title: calibrating ? "采集中 (\(collected) 样本)" : "重新标定",
                           systemImage: "dot.radiowaves.left.and.right",
                           isBusy: calibrating) {
                    Task { await run() }
                }
            } footer: {
                Text("静止走近门锁一次, 采 30 秒 RSSI 取 P95 作为武装基准。回差: 越过武装线才武装, 掉回 0.5×基准才解除, 防门口抖动误触发。")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("标定数据") {
                Button("清除标定", role: .destructive) { AutoOpen.removeAutocal(mac) }
            }
        }
        .navigationTitle("距离标定")
        .scrollContentBackground(.hidden)
        .dsScreenBackground()
    }

    private func run() async {
        guard !calibrating else { return }
        calibrating = true
        collected = 0
        defer { calibrating = false }
        var samples: [Int] = []
        let t0 = Date()
        while Date().timeIntervalSince(t0) < 30 {
            do {
                let dev = try await LinkSense.shared.scan(mac: mac, timeoutMs: 2500)
                if let r = dev?.rssi {
                    samples.append(r)
                    collected = samples.count
                    LinkSense.saveRssi(mac: mac, rssi: r)
                }
            } catch {}
            try? await Task.sleep(for: .milliseconds(500))
        }
        if let p = AutoOpenKit.p95(samples) {
            AutoOpen.saveAutocal(mac, AutoOpen.AutoCal(rssiP95: p, at: Date().timeIntervalSince1970))
            app.showToast("标定完成: P95 RSSI \(p)")
        } else {
            app.showToast("样本不足, 请走近门锁再试")
        }
    }
}

// ================= 设置 Section (§4 原文 + §3.4 强制风险披露) =================
struct AutoOpenSection: View {
    var mac: String
    var body: some View {
        Section {
            Toggle("走近自动开门", isOn: Binding(
                get: { AutoOpen.on },
                set: { AutoOpen.on = $0 }))
            if AutoOpen.on {
                Picker("面容确认", selection: Binding(
                    get: { AutoOpen.faceTier },
                    set: { AutoOpen.faceTier = $0 })) {
                    Text("标准 (静默≤60s)").tag(0)
                    Text("严格 (每次必刷)").tag(1)
                }
                .pickerStyle(.menu)
                Text(AutoOpen.riskDisclosure)
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
                NavigationLink("距离标定 (走近多近才算到)") { AutoCalView(mac: mac) }
            }
        } header: {
            Text("靠近自动开锁")
        } footer: {
            Text("仅 App 在前台且门不在布防时段生效; 布防时段与防拆事件自动关闭自动开锁。睡觉场景请确认布防时段覆盖夜间。")
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
