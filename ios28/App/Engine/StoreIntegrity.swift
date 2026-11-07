// StoreIntegrity.swift —— 存储完整性检查与修复（B73），以及 schema 版本（B1）。
//
// 离线 App 没有云端兜底：**本机数据丢了就是真丢了**。所以要能回答两个问题：
//   1. 现在有哪些数据是坏的？（界面上要能看见，而不是静默回落默认值）
//   2. 能修吗？（能从备份救回来就救；救不回来就把残片导出，让人有机会手工抢救）
//
// 修不回来的**绝不静默**：`DB.isLedgerCorrupt` 那道闸就是干这个的 ——
// 台账读不出来时，写入一律拒绝，宁可界面显示旧数据，也不要用空表覆盖真数据。
import Foundation

/// 本机存储的 schema 版本。
///
/// 版本号的作用只有一个：**挡住在更新的 App 里写的数据被旧 App 读坏**。
/// 数据结构变了（加字段、改语义）时把 `current` 加一，
/// 旧 App 读到版本更高的键就会跳过它，而不是解出半截数据。
enum SchemaVersion {
    static let current = 1
    static let key = "kf_schema_version"

    /// 盘上记录的版本（0 = 从没写过 = 老数据）。
    static var stored: Int { DB.store.getInt(key, 0) }

    /// 启动时打戳（版本变过时写一条日志，便于追「哪一版开始写的」）。
    static func stamp() {
        if stored != current {
            DB.store.setInt(key, current)
            DiagLogs.append("info", "本机存储版本：\(stored) → \(current)",
                            date: DiagLogs.localDay(), time: DiagTime.hhmmss())
        }
    }
}

enum StoreIntegrity {
    struct Issue: Identifiable, Equatable {
        var id: String { key }
        var key: String
        /// 这条数据是什么（人话）。
        var what: String
        /// 坏在哪。
        var problem: String
        /// 能修吗。
        var repairable: Bool
        /// 怎么修（界面上的动作名）。
        var fix: String?
    }

    struct Report: Equatable {
        var issues: [Issue] = []
        var repaired: [String] = []
        var scanned: Int = 0

        var isClean: Bool { issues.isEmpty }
        var summary: String {
            if issues.isEmpty { return scanned == 0 ? "没有可检查的关键数据" : "检查了 \(scanned) 项，都正常" }
            return "发现 \(issues.count) 项问题\(repaired.isEmpty ? "" : "，已修复 \(repaired.count) 项")"
        }
    }

    /// 关键键的中文名（界面用）。
    private static func name(of key: String) -> String {
        if key.hasPrefix("kf_ledger_") { return "凭证台账" }
        if key.hasPrefix("kf_logcache_") { return "记录缓存" }
        if key.hasPrefix("kf_mkey_") { return "手机钥匙" }
        if key == "kf_members" { return "成员名册" }
        if key == "kf_member_ext" { return "成员档案" }
        if key == "kf_keychains" { return "门锁档案" }
        if key == "kf_keychain_dongles" { return "蓝牙钥匙串" }
        if key == "kf_gateways" { return "网关档案" }
        if key.hasPrefix("kf_claims_") { return "记录认领" }
        return key
    }

    /// 扫一遍关键键。
    static func scan() -> Report {
        var report = Report()
        let keys = DB.store.keys().filter { DB.store.isCriticalKey($0) }
        for k in keys {
            report.scanned += 1
            guard let d = DB.store.rawData(k) else { continue }
            // 能不能解：按「字典还是结构体」两种形状试。
            let decodes = (try? JSONSerialization.jsonObject(with: d)) != nil
            if decodes { continue }
            let backupOK = DB.store.rawData(k + Store.backupSuffix) != nil
            report.issues.append(Issue(key: k,
                                       what: name(of: k),
                                       problem: "内容读不出来（可能被截断）",
                                       repairable: backupOK,
                                       fix: backupOK ? "从备份恢复" : "导出残片"))
        }
        return report
    }

    /// 修一遍：能从备份救回来的直接救。
    @discardableResult
    static func repair() -> Report {
        var report = scan()
        var issues: [Issue] = []
        for issue in report.issues {
            guard issue.repairable, let d = DB.store.rawData(issue.key + Store.backupSuffix) else {
                issues.append(issue)
                continue
            }
            // 写回主份（直接写 defaults，不经 set —— set 会重编码，覆盖我们要救的那份字节）。
            DB.store.restoreRaw(issue.key, d)
            report.repaired.append(issue.what)
        }
        report.issues = issues
        return report
    }

    /// 导出救不回来的残片（十六进制 / UTF-8 片段），让人有机会手工抢救。
    static func exportResidue() -> String? {
        let report = scan()
        let bad = report.issues.filter { !$0.repairable }
        guard !bad.isEmpty else { return nil }
        var out: [String] = ["阈值 · 存储残片", "生成时间：\(DiagTime.full())", ""]
        for issue in bad {
            out.append("—— \(issue.what)（\(issue.key)）——")
            if let d = DB.store.rawData(issue.key) {
                out.append("字节数：\(d.count)")
                out.append("十六进制：\(d.prefix(512).map { String(format: "%02x", $0) }.joined())")
                if let text = String(data: d.prefix(512), encoding: .utf8) {
                    out.append("文本：\(text)")
                }
            } else {
                out.append("（键已不存在）")
            }
            out.append("")
        }
        return out.joined(separator: "\n")
    }
}

// MARK: - 快照新鲜期（B38）
//
// 放在 Engine 这一层：健康检查（Engine）在用它，Core 反过来依赖 Engine。

extension DB {
    /// 状态快照的新鲜期：超过 15 分钟就不算「刚刚读到」。
    static let statusTTLms: Double = 15 * 60 * 1000

    /// 快照有多旧（毫秒）；没有快照时 nil。
    static func statusAge(_ mac: String) -> Double? {
        guard let snap = readStatus(mac) else { return nil }
        let age = Date().timeIntervalSince1970 * 1000 - snap.at
        return age < 0 ? 0 : age
    }

    /// 快照是否已经过期。
    static func isStatusStale(_ mac: String) -> Bool {
        guard let age = statusAge(mac) else { return false }
        return age > DB.statusTTLms
    }

}
