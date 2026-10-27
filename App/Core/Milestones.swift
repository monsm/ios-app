// 里程碑与账本 — 工具层精简版
//
// 2026-10-25 大删: 徽章引擎/成就页/庆祝动效/胶囊/感恩/节气/伙伴文案/晚归打卡等游戏化面整体剥离,
// 只保留被核心功能当**数据账本**使用的部分: 备份历史(备份页"距上次备份"的依据)、一次性标记(启动结算去重)、
// 日期工具、开锁计数、整理计数。徽章相关的 Badge/MStats/BadgeRarity 类型与 evaluate/notifyAchievement
// 等引擎已删; 外部引用已同步清理。
import Foundation
import UserNotifications

enum Milestones {
    // ---------- 日期工具 ----------
    /// 日 key 的唯一口径是 `StatsKit.dayKey` (yyyy-MM-dd + en_US_POSIX + 当前时区)。
    static func dayKey(_ d: Date = Date()) -> String { StatsKit.dayKey(d) }
    static func monthKey(_ d: Date = Date()) -> String { String(dayKey(d).prefix(7)) }
    // ---------- 一次性标记 (启动结算/审计去重键) ----------
    static func onceDone(_ k: String) -> Bool {
        let m = DB.store.get([String: Bool].self, "kf_once") ?? [:]
        return m[k] == true
    }
    static func markOnce(_ k: String) {
        var m = DB.store.get([String: Bool].self, "kf_once") ?? [:]
        m[k] = true
        DB.store.setCodable("kf_once", m)
    }


    // ---------- 980/997 备份历史 (备份页"距上次备份"与新鲜度判定的唯一数据源) ----------
    @MainActor
    static func recordBackup() {
        var h = DB.store.get([Double].self, "kf_backup_hist") ?? []
        h.append(Date().timeIntervalSince1970 * 1000)
        if h.count > 60 { h.removeFirst(h.count - 60) }
        DB.store.setCodable("kf_backup_hist", h)
        // 448: 备份发生点 = 自检基线更新点 (导出/上传/还原点全覆盖; 自检本身绝不回写)
        let mk = monthKey()
        _ = mk   // 2026-10-27 六轮：backupThisMonth 已删，月度基线不再计算
    }
    /// 822 「还没有备份」要看的那一个事实: 本机最后一次生成/上传备份的时刻。
    static var lastBackupAt: Date? {
        guard let h = DB.store.get([Double].self, "kf_backup_hist"), let t = h.max(), t > 0
        else { return nil }
        return Date(timeIntervalSince1970: t / 1000)
    }

    // ---------- 982 开锁计数 (App 侧成功次数) ----------
    static var unlockTotal: Int { DB.store.getInt("kf_unlock_count") }
    static func recordUnlockSuccess() {
        DB.store.set("kf_unlock_count", unlockTotal + 1)
    }

    // ---------- 1007 整理计数 ----------
    static var organizeTotal: Int { DB.store.getInt("kf_organize_count") }
    static func recordOrganize() {
        DB.store.set("kf_organize_count", organizeTotal + 1)
    }
}