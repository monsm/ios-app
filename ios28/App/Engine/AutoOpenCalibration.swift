// AutoOpenCalibration.swift —— 自动开门的标定 2.0（B21）。
//
// 原来的标定只有一件事：采一批 RSSI，取 P95 当阈值。界面给一行「近/远」两档，
// 用户站在门口点两下，完事。
//
// 2.0 补三件事：
//   1. **曲线**：采样带时间戳，界面画得出「我走了这一趟信号怎么变的」，
//      而不是只给一个数字。
//   2. **双向采样**：近处与远处**都要采** —— 只采近处的话，阈值只能靠 P95 猜，
//      采了远处才知道「远」到底是多远。
//   3. **反馈学习**：用户手动开锁时记一笔「自动开门没开成」，
//      连续几次就把阈值收紧一点 —— 宁可少自动开一次，也别在门外替人开门。
import Foundation

enum AutoOpenCalibration {
    /// 采样点的相位。
    enum Phase: String, Codable, CaseIterable {
        case near = "靠近"
        case far = "走开"

        var symbol: String {
            switch self {
            case .near: return "figure.walk.arrival"
            case .far: return "figure.walk.departure"
            }
        }
    }

    struct Sample: Codable, Equatable, Identifiable {
        var id: String { "\(Int(at * 1000))-\(rssi)" }
        var at: Double
        var rssi: Int
        var phase: Phase
    }

    /// 一把锁的标定档案。
    struct Plan: Codable, Equatable {
        var mac: String = ""
        var samples: [Sample] = []
        /// 自动算出来的阈值（RSSI）。
        var threshold: Int? = nil
        var at: Double = 0
        /// 反馈学习留下的调整量（dB，正数 = 更严格）。
        var adjust: Int = 0
        /// 自动开门开成过几次 / 没开成过几次。
        var successCount: Int = 0
        var missCount: Int = 0

        var near: [Int] { samples.filter { $0.phase == .near }.map(\.rssi) }
        var far: [Int] { samples.filter { $0.phase == .far }.map(\.rssi) }

        /// 采样是否够了（至少 3 个近点 + 2 个远点）。
        var isReady: Bool { near.count >= 3 && far.count >= 2 }
    }

    private static let key = "kf_autocal_plan_"
    private static let cache = Locked([String: Plan]())

    private static func load(_ mac: String) -> Plan {
        if let hit = cache.withLock({ $0[mac] }) { return hit }
        let p = DB.store.get(Plan.self, key + mac) ?? Plan(mac: mac)
        cache.withLock { $0[mac] = p }
        return p
    }

    private static func save(_ plan: Plan) {
        cache.withLock { $0[plan.mac] = plan }
        DB.store.setCodable(key + plan.mac, plan)
    }

    /// 记一个采样点。
    @discardableResult
    static func record(mac: String, phase: Phase, rssi: Int) -> Plan {
        var plan = load(mac)
        plan.mac = mac
        plan.samples.append(Sample(at: Date().timeIntervalSince1970, rssi: rssi, phase: phase))
        if plan.samples.count > 60 { plan.samples.removeFirst(plan.samples.count - 60) }
        plan.threshold = computeThreshold(plan)
        plan.at = Date().timeIntervalSince1970
        save(plan)
        return plan
    }

    /// 阈值：近处样本的 P95 与远处样本的中位数之间取中点。
    ///
    /// 只有一种样本时退回「近处 P95」—— 与旧口径一致，不因为换了算法就变行为。
    static func computeThreshold(_ plan: Plan) -> Int? {
        let near = plan.near.sorted()
        let far = plan.far.sorted()
        guard !near.isEmpty else { return nil }
        let p95 = percentile(near, 0.95)
        guard !far.isEmpty else { return p95 }
        let farMedian = percentile(far, 0.5)
        // 近处 P95 与远处中位数之间：近处应当更强，取二者中点，
        // 再按反馈学习收紧。
        let mid = (p95 + farMedian) / 2
        return mid - plan.adjust
    }

    static func percentile(_ sorted: [Int], _ q: Double) -> Int {
        guard !sorted.isEmpty else { return 0 }
        let rank = Double(sorted.count - 1) * q
        let lo = Int(rank.rounded(.down))
        let hi = Int(rank.rounded(.up))
        if lo == hi { return sorted[lo] }
        return (sorted[lo] + sorted[hi]) / 2
    }

    /// 反馈：自动开门开成 / 没开成。
    ///
    /// 连续 3 次没开成 ⇒ 阈值收紧 3dB（更靠近才算「到了门���」）。
    /// 开成过 5 次且没失手过 ⇒ 放宽 2dB（别让人站在门口反复等）。
    static func noteOutcome(mac: String, opened: Bool) {
        var plan = load(mac)
        if opened {
            plan.successCount += 1
            if plan.successCount >= 5, plan.missCount == 0, plan.adjust > -4 {
                plan.adjust -= 2
                plan.successCount = 0
            }
        } else {
            plan.missCount += 1
            if plan.missCount >= 3, plan.adjust < 9 {
                plan.adjust += 3
                plan.missCount = 0
            }
        }
        plan.threshold = computeThreshold(plan)
        save(plan)
    }

    static func plan(mac: String) -> Plan { load(mac) }

    static func threshold(mac: String) -> Int? { load(mac).threshold }

    /// 人话摘要（设置页 / 诊断页）。
    static func summary(mac: String) -> String {
        let p = load(mac)
        guard !p.samples.isEmpty else { return "还没有标定过" }
        var parts: [String] = []
        parts.append("近处 \(p.near.count) 点")
        parts.append("远处 \(p.far.count) 点")
        if let t = p.threshold { parts.append("阈值 \(t) dBm") }
        if p.adjust != 0 { parts.append(p.adjust > 0 ? "收紧 \(p.adjust) dB" : "放宽 \(-p.adjust) dB") }
        if !p.isReady { parts.append("采样还不够（至少 3 近 + 2 远）") }
        return parts.joined(separator: " · ")
    }

    static func clear(mac: String) {
        cache.withLock { $0[mac] = nil }
        DB.store.remove(key + mac)
    }
}
