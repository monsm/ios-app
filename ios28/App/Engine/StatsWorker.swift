// StatsWorker.swift —— 把统计重活挪出主线程（B41）。
//
// 成员活跃度是 O(锁 × 日志) 的计算：每条日志都要过一次归属判定。
// 它原先在 `AppModel.reloadMemberCards` 里**同步**跑在主线程 ——
// 锁端日志攒到几百条时，切换锁或恢复备份会让界面卡住一下。
//
// 现在挪进 actor：主线程只发一次请求、拿一次结果。
// 缓存仍按**签名**判定（成员集合 + 事件数 + 首尾时间 + 缓存代次）——
// 签名不变就直接复用，不重算。
import Foundation

actor StatsWorker {
    static let shared = StatsWorker()

    /// 签名 → 结果。actor 内部状态，不跨线程共享。
    private var cache: [String: MemberHub.ActivityBundle] = [:]
    private var lastSignature = ""
    private var lastBundle = MemberHub.ActivityBundle()

    /// 取活跃度。签名相同直接复用上一次的结果。
    func activity(ids: [String], signature: String) -> MemberHub.ActivityBundle {
        if signature == lastSignature, !lastBundle.table.isEmpty || ids.isEmpty {
            return lastBundle
        }
        if let hit = cache[signature] {
            lastSignature = signature
            lastBundle = hit
            return hit
        }
        let took = PerfBudget.measure("成员活跃度", budget: PerfBudget.memberActivity) {
            lastBundle = MemberHub.activityBundle(ids)
        }
        if took > PerfBudget.memberActivity {
            DiagLogs.append("warn", "成员活跃度重算 \(String(format: "%.0f", took * 1000))ms（成员 \(ids.count) 人）",
                            date: DiagLogs.localDay(), time: DiagTime.hhmmss())
        }
        lastSignature = signature
        cache[signature] = lastBundle
        // 只留最近 8 个签名 —— 缓存不是仓库。
        if cache.count > 8 {
            for k in cache.keys.sorted().prefix(cache.count - 8) { cache.removeValue(forKey: k) }
        }
        return lastBundle
    }

    /// 作废缓存（换锁 / 恢复备份 / 凭证变化时调用）。
    func invalidate() {
        cache.removeAll()
        lastSignature = ""
        lastBundle = MemberHub.ActivityBundle()
    }
}
