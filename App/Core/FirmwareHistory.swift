// 755 固件版本随行标注: 每次成功读状态 (03#31) 顺带把"哪天看到的是哪个固件"记下来,
// 让时间线/详情能注明"该日前后观测到的固件版本"。
// 刻意不叫"固件历史": 观测点只在读状态时产生, 中间升级过几次、具体哪天升的, 本机无从得知。
import Foundation

enum FirmwareHistory {
    private static func key(_ mac: String) -> String { "kf_fw_hist_" + mac }
    private static let cap = 120          // 按日存, 120 天足够排障用; 超出丢最旧的

    /// 记录一次观测。dayKey 用本机日界 (与日志分组同一口径 = `StatsKit.dayKey`), fw 为空则不记 (未回该字段)。
    static func record(mac: String, fw: String, date: Date = Date()) {
        guard !mac.isEmpty, !fw.isEmpty else { return }
        let day = StatsKit.dayKey(date)
        var map = DB.store.get([String: String].self, key(mac)) ?? [:]
        if map[day] == fw { return }          // 同一天同版本重复读 → 不写盘
        map[day] = fw
        if map.count > cap {
            let keep = map.keys.sorted().suffix(cap)
            map = Dictionary(uniqueKeysWithValues: keep.map { ($0, map[$0] ?? fw) })
        }
        DB.store.set(key(mac), map)
    }

    /// 取"该日或更早"最近一次观测到的固件版本, 连同观测日一起返回。
    /// 找不到就返回 nil —— 不用当前版本冒充历史版本。
    static func observed(mac: String, onOrBefore dayKey: String) -> (day: String, fw: String)? {
        let map = DB.store.get([String: String].self, key(mac)) ?? [:]
        guard !dayKey.isEmpty else { return nil }
        let hit = map.keys.filter { $0 <= dayKey }.sorted().last
        guard let d = hit, let v = map[d], !v.isEmpty else { return nil }
        return (d, v)
    }

    /// 详情页用: 列出该机已知观测点 (最新在前)
    static func observations(mac: String) -> [(day: String, fw: String)] {
        let map = DB.store.get([String: String].self, key(mac)) ?? [:]
        return map.keys.sorted(by: >).compactMap { k in map[k].map { (k, $0) } }
    }
}
