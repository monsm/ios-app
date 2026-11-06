// HeroStats.swift —— "首页读数里显示哪几项"的本机偏好。
//
// 从上一版 DesignMetrics.swift 搬来。它原来挂在设计系统里，但**不含任何样式** ——
// 只是读/写一个本机键（kf_hero_stats），是纯数据逻辑。
// 搬进 Engine 后 BackupKit 的备份/恢复才能不再依赖设计系统。
import Foundation

enum HeroStats {
    static let all = ["firmware", "lockclock"]

    /// 当前可见项。空集合回退为"全开"（与上一版同口径：不留一张没有指标的光板）。
    static var visible: Set<String> {
        let stored = DB.store.get([String].self, "kf_hero_stats") ?? []
        let keep = Set(stored.filter { all.contains($0) })
        return keep.isEmpty ? Set(all) : keep
    }

    static func shows(_ id: String) -> Bool { visible.contains(id) }

    static func setVisible(_ ids: [String]) {
        DB.store.set("kf_hero_stats", all.filter { ids.contains($0) })
    }
}
