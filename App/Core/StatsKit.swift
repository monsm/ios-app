// 包10 统计与图表 — 纯本地聚合层 (Swift Charts 数据源)
// 数据全部来自既有本地台账 (kf_logcache_ 锁日志缓存 / kf_ledger_ 凭证台账 / kf_members 成员),
// 与 LockStats 同纪律: 只读既有表, 不新增采集, 不碰协议层, 归属只走 Attribution 可证明链 (R1/R2),
// 推不出的不猜 (CAPABILITY §3: 日志无身份字段, 成员相关统计一律"约"级)。
import Foundation
import SwiftUI

enum StatsKit {
    /// 2026-10-29 修正：开锁类只认 APK `We` 表里的 11/16/17/19（原来抄的 1-5 是消息中心枚举）。
    static let openTypes: Set<Int> = [11, 16, 17, 19]
    /// 2026-10-29 修正：日志里的告警只有 4 静态电量 / 10 多次密码失败锁定。
    /// （撬锁 7 / 指纹告警 13 / 键盘锁定 224 属于**消息中心**的 mType，不在锁端日志类型表里。）
    static let alarmTypes: Set<Int> = [4, 10]

    // ---------- 日期 ----------
    /// 缓存日志的协议秒 → 本地 `Date`。**`lockTime == 0` 是"锁端时钟没读到/无时钟型号"的占位值**
    /// (Milestones 夜猫子徽章那段早就把这条规则写明了：换算后落在协议纪元 2010-01-01 00:00，
    /// 其小时必然 < 6，会凭空点亮徽章)。这里原本写的是 `guard ms > 0`，而 `ms` 其实是 **Unix 秒**
    /// (1.7e9 量级)，`lockTime = 0` 换算出来是 2010-01-01 也是 > 0 ⇒ **那条守卫恒真、永不生效**：
    /// 全仓 47 个 `dateOf` 调用方都把一条没有时间戳的记录当成 2010-01-01 那条日子在数
    /// (`earliestDate` 被钉死在 2010 ⇒ 642 的"缓存最早从 2010-01-01 起"、`coverageDays` 约 6100 天、
    /// 日/月桶各多一个幽灵日)。口径收在这一个地方：没有锁端时刻 = 没有日期，返回 nil (§10.32)。
    static func dateOf(_ l: CachedLog) -> Date? {
        guard l.lockTime > 0 else { return nil }
        return Date(timeIntervalSince1970: ZKProtocol.protoSecondsToUnix(l.lockTime))
    }
    static func dayKey(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f.string(from: d)
    }
    static func startOfDay(_ d: Date) -> Date {
        WeekCal.gregorian.startOfDay(for: d)
    }
    /// 616 周几分布与 780 工作日判定**共用**这一个周序: Calendar 的 `.weekday` 是 1=周日…7=周六，
    /// 而本仓的桶序是 1=周一…7=周日。两处各写一遍 `(+5)%7+1` 的话，改一处就会让"工作日"和
    /// "周几柱"对不上 —— 616 那条注释记录的正是这类平移一天的 bug。
    static func weekdayIndex(_ d: Date) -> Int {
        (WeekCal.gregorian.component(.weekday, from: d) + 5) % 7 + 1
    }



    // ---------- 查询 ----------
    struct StatModel {
        let mac: String
        let logs: [CachedLog]
        let pwds: [LedgerPwd]

        func lastWeekDigest() -> (csv: String, lines: [String]) {
            let cal = WeekCal.gregorian
            let today = Date()
            guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: today),
                  let from = cal.date(byAdding: .day, value: -7, to: thisWeek.start),
                  let end = cal.date(byAdding: .day, value: 7, to: from) else { return ("", []) }
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.dateFormat = "yyyy-MM-dd"
            let head = fmt.string(from: from) + " 至 " + fmt.string(from: cal.date(byAdding: .day, value: -1, to: end) ?? from)
            let week = logs.filter { l in
                openTypes.contains(l.type) && (dateOf(l).map { $0 >= from && $0 < end } ?? false)
            }
            guard !week.isEmpty else {
                return ("", ["上周 (" + head + ") 没有本机读到的开门记录 — 缓存只留最近 300 条, 更早的翻不到不代表没发生。"])
            }
            let cls = Attribution.classify(
                logs: week.map { LogEntry(type: $0.type, typeName: $0.typeName, idx: $0.idxRaw, idxRaw: $0.idxRaw,
                                          lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr, body: "") },
                pwds: DB.listPwds(mac), fps: DB.listFps(mac),
                status: DB.readStatus(mac).map { ($0.fpStock, $0.pwdStock, $0.lockTime) })
            func esc(_ s: String) -> String {
                s.contains(",") || s.contains("\"") ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
            }
            var per = [String: Int]()
            var rows = ["时间,类型,成员"]
            for (i, c) in cls.enumerated() {
                let l = week[i]
                if let who = c.who { per[who, default: 0] += 1 }
                rows.append(esc(l.lockTimeStr) + "," + esc(l.typeName) + ","
                            + esc(c.who.flatMap { DB.member($0)?.name } ?? "未归属"))
            }
            let alarms = logs.filter { l in
                alarmTypes.contains(l.type) && (dateOf(l).map { $0 >= from && $0 < end } ?? false)
            }.count
            var lines = ["上周 (" + head + ") 共开门 \(week.count) 次。"]
            if let t = per.max(by: { $0.value < $1.value }), let n = DB.member(t.key)?.name {
                lines.append("最活跃成员: \(n) (约 \(t.value) 次)。")
            } else {
                lines.append("成员归属都还证明不了 (归属需要台账与日志窗口对齐)。")
            }
            lines.append("同期告警 \(alarms) 条。")
            return (rows.joined(separator: "\n"), lines)
        }

    }

    // ---------- 构建 ----------
    @MainActor
    static func build(mac: String) -> StatModel {
        // 745 测试标记: 已标"测试"的自测告警不进统计 (键 = mac#idxRaw, 与 kf_rdispo 同一份)。
        let testKeys = RecordSearch.testMarkedKeys
        let logs = DB.readLogs(mac).filter { !testKeys.contains(mac + "#" + String($0.idxRaw)) }
        return StatModel(mac: mac, logs: logs, pwds: DB.listPwds(mac))
    }


}
