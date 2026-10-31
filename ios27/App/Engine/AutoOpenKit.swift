// AutoOpenKit.swift —— 靠近自动开锁的核心逻辑（纯逻辑 + 存储，UI 在 Features/Settings/AutoOpenScreen）。
//
// 从上一版 AutoOpen.swift 抽出：门控链 F0 前台 / F1 面容双档 / F3 距离标定 / F4 布防互锁 /
// F5 一次性冷却 / F6 锁态，全绿才经既有 LockService.unlock 管线下发 cmd04（不改协议/命令构造）。
// 任一门不过 = 静默拒绝 + 审计落盘（只记哪道门拒了、哪把锁、何时，永不记 ekey/skey 明文）。
// 默认全关、fail-closed。
import Foundation
import LocalAuthentication
import UIKit

// ================= 存储 accessor（kf.* 自动进备份） =================
enum AutoOpen {
    /// 主开关（默认关）
    static var on: Bool {
        get { DB.store.getBool("kf_autoopen", false) }
        set { DB.store.set("kf_autoopen", newValue) }
    }
    /// 面容档位：0 免额外验证 / 1 严格（进前台必刷）
    static var faceTier: Int {
        get { DB.store.getInt("kf_autoopen_face", 0) }
        set { DB.store.set("kf_autoopen_face", newValue) }
    }
    /// rc=26 防拆事件自动关闭 24h：到点前一律 fail-closed 拒
    static func suspendUntil(_ mac: String) -> Int64 {
        DB.store.get("kf_autoopen_suspend_until_" + mac, Int64.self) ?? 0
    }
    static func setSuspendUntil(_ mac: String, _ ms: Int64) {
        DB.store.set("kf_autoopen_suspend_until_" + mac, ms)
    }
    static func isSuspended(mac: String, now: Double = Date().timeIntervalSince1970) -> Bool {
        let t = suspendUntil(mac)
        return t > 0 && Double(t) / 1000.0 > now
    }

    // ---------- F5 冷却的跨会话持久化 ----------
    static func persistedLastDispatch(_ mac: String) -> Double {
        DB.store.getDouble("kf_autoopen_lastdispatch_" + mac)
    }
    static func setPersistedLastDispatch(_ mac: String, _ t: Double) {
        DB.store.setDouble("kf_autoopen_lastdispatch_" + mac, t)
    }

    // ---------- 审计（尾段 500 条） ----------
    struct AuditEntry: Codable {
        var at: String
        var mac: String
        var reason: String
        enum CodingKeys: String, CodingKey { case at, mac, reason }
        init(at: String, mac: String, reason: String) { self.at = at; self.mac = mac; self.reason = reason }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            at = try c.decodeIfPresent(String.self, forKey: .at) ?? ""
            mac = try c.decodeIfPresent(String.self, forKey: .mac) ?? ""
            reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
        }
    }
    private static let auditLast = Locked<[String: Double]>([:])
    static func audit(_ mac: String, _ reason: String) {
        let key = mac + "|" + reason
        let now = Date().timeIntervalSince1970
        let skip = auditLast.withLock { m -> Bool in
            if let t = m[key], now - t < 10 { return true }
            if m.count > 200 { m.removeAll() }
            m[key] = now
            return false
        }
        if skip { return }
        var list = audits(mac)
        list.insert(AuditEntry(at: DiagTime.mmddHHmm(), mac: mac, reason: reason), at: 0)
        if list.count > 500 { list = Array(list.prefix(500)) }
        DB.store.setCodable("kf_autoopen_audit_" + mac, list)
    }
    static func audits(_ mac: String) -> [AuditEntry] {
        DB.store.get([AuditEntry].self, "kf_autoopen_audit_" + mac) ?? []
    }
    static func lastReject(_ mac: String) -> AuditEntry? { audits(mac).first }
    static func recent(_ mac: String, _ n: Int) -> [AuditEntry] { Array(audits(mac).prefix(n)) }

    // ---------- F3 标定 ----------
    struct AutoCal: Codable { var rssiP95: Int; var at: Double }
    static func autocal(_ mac: String) -> AutoCal? {
        DB.store.get(AutoCal.self, "kf_autocal_" + mac)
    }
    @discardableResult
    static func saveAutocal(_ mac: String, samples: [Int]) -> Int? {
        guard let p95 = AutoOpenKit.p95(samples) else { return nil }
        DB.store.setCodable("kf_autocal_" + mac, AutoCal(rssiP95: p95, at: Date().timeIntervalSince1970))
        return p95
    }
    static func clearAutocal(_ mac: String) {
        DB.store.remove("kf_autocal_" + mac)
    }

    /// §3.4 风险披露（强制展示，不弱化）
    static let riskDisclosure = "默认档只认「手机已解锁 + App 在前台」：别人拿你已解锁的手机走近门锁，6 秒后仍可能自动开门。介意请切严格档（每次进前台刷一次脸）。"
}

// ================= 纯逻辑：门控判定 / 标定 / 滤波 / 0E 双确认 =================
enum AutoOpenKit {
    /// F4 布防互锁：control != 0（1 不定期 / 2 时段）都是布防态，一票否决。
    static func defendActive(control: Int, startSec: Int, endSec: Int, now: Date,
                             cal: Calendar = WeekCal.gregorian) -> Bool {
        guard control != 0 else { return false }
        guard control == 2 else { return true }
        guard startSec != endSec else { return true }
        let comps = cal.dateComponents([.hour, .minute, .second], from: now)
        let secOfDay = ((comps.hour ?? 0) * 3600 + (comps.minute ?? 0) * 60 + (comps.second ?? 0)) / 2
        if startSec < endSec { return secOfDay >= startSec && secOfDay < endSec }
        return secOfDay >= startSec || secOfDay < endSec
    }

    /// 档位判据：0 = 免额外验证，其余任何值一律按严格档处理（未知值往严的一侧靠）。
    static func isStrict(_ tier: Int) -> Bool { tier != 0 }

    static func facePromptInFlight(startedAt: Date?, lastFace: Date?, now: Date) -> Bool {
        guard let startedAt else { return false }
        if now.timeIntervalSince(startedAt) > 30 { return false }
        if let lastFace, lastFace >= startedAt { return false }
        return true
    }

    static func faceFresh(tier: Int, lastFace: Date?, now: Date, pendingPrompt: Bool,
                          strictSince: Date? = nil) -> Bool {
        if !isStrict(tier) { return true }
        if pendingPrompt { return true }
        guard let lastFace, let strictSince else { return false }
        return lastFace >= strictSince
    }

    /// P95 线性插值（样本 <5 不标定）
    static func p95(_ samples: [Int]) -> Int? {
        guard samples.count >= 5 else { return nil }
        let sorted = samples.sorted()
        let rank = Double(sorted.count - 1) * 0.95
        let lo = Int(rank.rounded(.down))
        let hi = Int(rank.rounded(.up))
        let frac = rank - Double(lo)
        if lo == hi { return sorted[lo] }
        return Int((Double(sorted[lo]) + (Double(sorted[hi]) - Double(sorted[lo])) * frac).rounded())
    }

    static let fallbackBase = -40
    static func rssiBase(mac: String) -> Int { AutoOpen.autocal(mac)?.rssiP95 ?? fallbackBase }
    static func armThreshold(base: Int) -> Int { base }
    static func disarmThreshold(base: Int) -> Int { Int((Double(base) + 10 * log10(0.5)).rounded()) }

    static func rssiSample(prevArmed: Bool, rssi: Int, base: Int) -> Bool {
        if prevArmed { return rssi > disarmThreshold(base: base) }
        return rssi >= armThreshold(base: base)
    }

    /// 3 样本中值武装：抗单点尖峰，但真的走近仍 1 个样本就能过。
    static func rssiArmedByMedian(prevArmed: Bool, history: [Int], base: Int) -> Bool {
        guard let cur = history.first else { return prevArmed }
        let arm = armThreshold(base: base)
        let disarm = disarmThreshold(base: base)
        if prevArmed, cur <= disarm { return false }
        let win = Array(history.prefix(3)).sorted()
        let med = win[win.count / 2]
        if prevArmed { return med > disarm }
        return med >= arm
    }

    static let cooldownSeconds: Double = 6
    static func coolReady(lastDispatch: Double, now: Double) -> Bool {
        lastDispatch == 0 || now - lastDispatch > cooldownSeconds
    }

    /// 0E 双确认：30s < |偏差| < 24h 才写；≥24h 仅 NTP 对表一致时放宽到 48h。
    static func dualTimeSync(phoneProto: Int64, lockProto: Int64, ntpConfirmed: Bool) -> Bool {
        let dev = abs(phoneProto - lockProto)
        if dev < 30 { return false }
        if dev < 24 * 3600 { return true }
        if ntpConfirmed && dev < 48 * 3600 { return true }
        return false
    }

    private static let lastFaceLock = Locked<Date?>(nil)
    static func noteFaceSuccess() { lastFaceLock.withLock { $0 = Date() } }
    static func lastFace() -> Date? { lastFaceLock.withLock { $0 } }
}

// ================= 门控矩阵 =================
struct AutoOpenGate {
    var f0Foreground: Bool
    var faceTier: Int
    var lastFace: Date?
    var facePendingPrompt: Bool
    var facePromptStartedAt: Date? = nil
    var now: Date
    var defendControl: Int
    var defendStartSec: Int
    var defendEndSec: Int
    var rssiArmed: Bool
    var coolReady: Bool
    var lockReady: Bool

    enum Reject: Equatable {
        case off, suspended, f0, f1face, f4defend, f3rssi, f5cool, f6busy, none
    }

    func rejectReason(autoOpenOn: Bool, suspended: Bool, faceAvailable: Bool) -> Reject {
        guard autoOpenOn else { return .off }
        guard !suspended else { return .suspended }
        guard f0Foreground else { return .f0 }
        if AutoOpenKit.isStrict(faceTier) {
            guard faceAvailable else { return .f1face }
        }
        guard AutoOpenKit.faceFresh(tier: faceTier, lastFace: lastFace, now: now,
                                    pendingPrompt: facePendingPrompt, strictSince: facePromptStartedAt)
        else { return .f1face }
        guard !AutoOpenKit.defendActive(control: defendControl, startSec: defendStartSec,
                                        endSec: defendEndSec, now: now) else { return .f4defend }
        guard rssiArmed else { return .f3rssi }
        guard coolReady else { return .f5cool }
        guard lockReady else { return .f6busy }
        return .none
    }

    static func rejectText(_ r: Reject) -> String {
        switch r {
        case .off: return "主开关未开"
        case .suspended: return "rc=26 防拆挂起，自动开锁 24h 内禁用"
        case .f0: return "F0 非前台/App 未解锁"
        case .f1face: return "F1 面容未确认（严格档要求本次进前台刷过脸）"
        case .f4defend: return "F4 布防时段内，一票否决"
        case .f3rssi: return "F3 信号未达武装线"
        case .f5cool: return "F5 冷却中（6 秒）"
        case .f6busy: return "F6 锁态未知或忙（rc=25/无 03 回显）"
        case .none: return "可开"
        }
    }
}

// ================= 面容抽象 =================
protocol FaceService {
    var biometricAvailable: Bool { get }
    func promptFace()
}

struct SystemFaceService: FaceService {
    var biometricAvailable: Bool {
        var err: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
    }
    func promptFace() {
        Task { @MainActor in
            var err: NSError?
            let ctx = LAContext()
            guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else { return }
            ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                               localizedReason: "确认是你，才允许靠近自动开门") { ok, _ in
                if ok { AutoOpenKit.noteFaceSuccess() }
            }
        }
    }
}

// ================= 控制器：状态机 + 全门绿才走既有 unlock 管线下发 04 =================
@MainActor
final class AutoOpenController {
    static let shared = AutoOpenController()
    let face: FaceService
    private var armed = false
    private var armedMac = ""
    private var lastDispatch: [String: Double] = [:]
    private var eventFired: Set<String> = []
    private var promptStartedAt: Date?
    private var rssiHistory: [Int] = []
    private var wasInBackground = true
    private var inFlight = false
    private var pollTask: Task<Void, Never>?

    init(face: FaceService = SystemFaceService()) { self.face = face }

    var isDispatching: Bool { inFlight }

    // ---------- 生命周期 ----------
    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func pollOnce() async {
        guard AutoOpen.on, let host = EngineHostRegistry.host,
              let mac = host.currentKeychain?.mac, !mac.isEmpty else { return }
        if LockService.shared.connectedMAC.lowercased() != mac.lowercased() {
            try? await LockService.shared.ensureConnected(mac: mac)
        }
        guard LockService.shared.connectedMAC.lowercased() == mac.lowercased() else { return }
        let rssi: Int? = await withCheckedContinuation { cont in
            BLEService.shared.readLinkRSSI(timeoutMs: 1200) { cont.resume(returning: $0) }
        }
        if let rssi { feedRssi(mac: mac, rssi: rssi) }
    }

    func onForeground(mac: String) {
        guard AutoOpen.on, !mac.isEmpty else { return }
        guard !AutoOpen.isSuspended(mac: mac) else {
            AutoOpen.audit(mac, "拒开 rc=26 防拆挂起中，面容不刷新")
            return
        }
        eventFired.removeAll()
        if AutoOpenKit.isStrict(AutoOpen.faceTier), wasInBackground {
            promptStartedAt = Date()
            wasInBackground = false
            face.promptFace()
        }
    }

    func onBackground() {
        wasInBackground = true
        armed = false
        eventFired.removeAll()
        promptStartedAt = nil
    }

    // ---------- F3 喂入 ----------
    func feedRssi(mac: String, rssi: Int) {
        guard AutoOpen.on else { return }
        if mac != armedMac {
            armedMac = mac
            armed = false
            eventFired.remove(mac)
            rssiHistory.removeAll()
        }
        rssiHistory.insert(rssi, at: 0)
        if rssiHistory.count > 3 { rssiHistory.removeLast(rssiHistory.count - 3) }
        let base = AutoOpenKit.rssiBase(mac: mac)
        armed = AutoOpenKit.rssiArmedByMedian(prevArmed: armed, history: rssiHistory, base: base)
        if rssi < AutoOpenKit.disarmThreshold(base: base) - 3 { eventFired.remove(mac) }
        if armed { attempt(mac: mac) }
    }

    func attempt(mac: String) {
        guard AutoOpen.on, !inFlight else { return }
        guard let host = EngineHostRegistry.host, host.currentKeychain?.mac == mac else { return }
        guard !eventFired.contains(mac) else { return }
        let ctx = makeContext(mac: mac, host: host)
        let rej = ctx.rejectReason(autoOpenOn: true,
                                   suspended: AutoOpen.isSuspended(mac: mac),
                                   faceAvailable: face.biometricAvailable)
        switch rej {
        case .none:
            inFlight = true
            Task { await self.dispatch(mac: mac) }
        default:
            AutoOpen.audit(mac, "拒开 " + AutoOpenGate.rejectText(rej) + " · " + Self.doorName(mac))
        }
    }

    private func makeContext(mac: String, host: any EngineHost) -> AutoOpenGate {
        let d = DB.defend(mac)
        let lastAt = lastDispatch[mac] ?? AutoOpen.persistedLastDispatch(mac)
        let snap = host.lastStatus
        return AutoOpenGate(
            f0Foreground: UIApplication.shared.applicationState == .active && !AppLock.shared.decoy,
            faceTier: AutoOpen.faceTier,
            lastFace: AutoOpenKit.lastFace(),
            facePendingPrompt: AutoOpenKit.facePromptInFlight(startedAt: promptStartedAt,
                                                              lastFace: AutoOpenKit.lastFace(), now: Date()),
            facePromptStartedAt: promptStartedAt,
            now: Date(),
            defendControl: d?.control ?? 0,
            defendStartSec: d?.startSec ?? 0,
            defendEndSec: d?.endSec ?? 0,
            rssiArmed: armed,
            coolReady: AutoOpenKit.coolReady(lastDispatch: lastAt, now: Date().timeIntervalSince1970),
            lockReady: snap != nil && snap?.status.rc != 25 && snap?.status.rc != 26
        )
    }

    private func dispatch(mac: String) async {
        defer { inFlight = false }
        eventFired.insert(mac)
        lastDispatch[mac] = Date().timeIntervalSince1970
        AutoOpen.setPersistedLastDispatch(mac, lastDispatch[mac]!)
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            guard AutoOpen.on, UIApplication.shared.applicationState == .active else {
                AutoOpen.audit(mac, "下发前复查：开关已关或 App 不在前台，放弃本次自动开锁")
                return
            }
            let rc = try await LockService.shared.unlock(mac: mac)
            switch rc {
            case 0:
                armed = false
                AutoOpen.audit(mac, "自动开锁成功")
            case 3:
                await selfHealTime(mac: mac)
            case 5:
                AutoOpen.audit(mac, "rc=5 次数用完 — 提示联系主人换钥，不自动重签")
            case 25:
                AutoOpen.audit(mac, "rc=25 锁正忙，拒绝自动开锁")
            case 26:
                AutoOpen.setSuspendUntil(mac, Int64(Date().timeIntervalSince1970 * 1000) + 24 * 3600 * 1000)
                AutoOpen.audit(mac, "rc=26 防拆事件 → 自动关自动开锁 24h")
            default:
                AutoOpen.audit(mac, "rc=\(rc) " + StatusParser.rcFriendly(rc))
            }
        } catch {
            armed = false
            AutoOpen.audit(mac, "下发异常 " + error.localizedDescription)
        }
    }

    private func selfHealTime(mac: String) async {
        guard let lockSec = try? await LockService.shared.readLockTime() else {
            AutoOpen.audit(mac, "rc=3 读锁钟失败，未自动校时")
            return
        }
        let phone = ZKProtocol.nowProtoSeconds()
        if AutoOpenKit.dualTimeSync(phoneProto: phone, lockProto: lockSec, ntpConfirmed: false) {
            try? await LockService.shared.syncTime()
            AutoOpen.audit(mac, "rc=3 → 已自动校时（0E 双确认）")
        } else {
            AutoOpen.audit(mac, "rc=3 → 偏差超出双确认窗，只提示不写")
        }
    }

    static func doorName(mac: String) -> String {
        DB.keychain(mac)?.name ?? String(mac.prefix(6))
    }
}
