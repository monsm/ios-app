// DefendSchedule.swift —— 布防的多时段排程（B22）。
//
// 协议侧的 cmd25 只有**一个**窗口（control + start + end），而且时间字段是半秒刻度。
// 用户心里的「布防」是「工作日晚上 8 点到早上 6 点」这样**好几段**。
//
// 做法（也是唯一诚实的做法）：
//   · **App 本地**排多段（每天可有多段、可选星期几）；
//   · 到了该生效的那一段，**把当前这一段下发到锁**（锁端仍然只存一段）；
//   · 界面明确写清：「锁端只支持一段，App 会在每个时段切换时自动重下」。
//
// 反过来做（把多段塞进协议）不可能 —— 那是协议没有的字段。
import Foundation

/// 一段布防时段。
struct DefendWindow: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    /// 生效的星期（1 = 周日 … 7 = 周六，与 `Calendar.component(.weekday:)` 同口径）。
    var weekdays: Set<Int> = [1, 2, 3, 4, 5, 6, 7]
    /// 日内起始秒。
    var startSec: Int = 0
    /// 日内结束秒（可跨午夜：小于 startSec 表示跨到第二天）。
    var endSec: Int = 0
    /// 布防档（DefendMode 的 rawValue：0 off / 1 once / 2 period）。
    var mode: Int = 2

    var title: String {
        let days: String
        if weekdays.count == 7 { days = "每天" }
        else if weekdays.isEmpty { days = "不生效" }
        else {
            let names = [1: "日", 2: "一", 3: "二", 4: "三", 5: "四", 6: "五", 7: "六"]
            days = "周" + weekdays.sorted().compactMap { names[$0] }.joined(separator: "、")
        }
        return "\(days) \(DefendKit.hhmm(startSec))–\(DefendKit.hhmm(endSec))"
    }
}

enum DefendSchedule {
    private static let key = "kf_defend_plan_"

    /// 读全部时段。
    static func windows(mac: String) -> [DefendWindow] {
        DB.store.get([DefendWindow].self, key + mac) ?? []
    }

    /// 写全部时段。
    static func save(mac: String, _ windows: [DefendWindow]) {
        DB.store.setCodable(key + mac, windows)
    }

    /// 某一天是否生效。
    static func matches(_ w: DefendWindow, weekday: Int) -> Bool {
        w.weekdays.contains(weekday)
    }

    /// 当前应该生效的那一段（考虑跨午夜）。
    static func activeWindow(mac: String, now: Date = Date()) -> DefendWindow? {
        let cal = WeekCal.gregorian
        let weekday = cal.component(.weekday, from: now)
        let sec = cal.component(.hour, from: now) * 3600
            + cal.component(.minute, from: now) * 60
            + cal.component(.second, from: now)
        let yesterday = cal.component(.weekday, from: cal.date(byAdding: .day, value: -1, to: now) ?? now)

        for w in windows(mac: mac) {
            if w.startSec <= w.endSec {
                if matches(w, weekday: weekday), sec >= w.startSec, sec < w.endSec { return w }
            } else {
                // 跨午夜：00:00–endSec 段算昨天那一段
                if sec >= w.startSec, matches(w, weekday: weekday) { return w }
                if sec < w.endSec, matches(w, weekday: yesterday) { return w }
            }
        }
        return nil
    }

    /// 下一个要生效的时段（界面上告诉用户「今晚 20:00 开始布防」）。
    static func nextWindow(mac: String, now: Date = Date()) -> DefendWindow? {
        let cal = WeekCal.gregorian
        let sec = cal.component(.hour, from: now) * 3600
            + cal.component(.minute, from: now) * 60
            + cal.component(.second, from: now)
        let weekday = cal.component(.weekday, from: now)
        var best: (DefendWindow, Int)?
        for w in windows(mac: mac) {
            guard !w.weekdays.isEmpty else { continue }
            for offset in 0 ... 7 {
                let d = cal.date(byAdding: .day, value: offset, to: now) ?? now
                let wd = cal.component(.weekday, from: d)
                guard matches(w, weekday: wd) else { continue }
                let delta = offset == 0 ? max(0, w.startSec - sec) : (86400 - sec) + w.startSec
                if best == nil || delta < best!.1 { best = (w, delta) }
                break
            }
        }
        return best?.0
    }

    /// 给锁下发的那一段：**只有当前生效的那段**。
    ///
    /// 没有生效段时，锁端应该是「不布防」（control=0）。
    static func lockWindow(mac: String, now: Date = Date()) -> (mode: DefendMode, startSec: Int, endSec: Int) {
        if let w = activeWindow(mac: mac, now: now), let mode = DefendMode(rawValue: w.mode) {
            return (mode, w.startSec, w.endSec)
        }
        return (.off, 0, 0)
    }

    /// 人话摘要。
    static func summary(mac: String, now: Date = Date()) -> String {
        let list = windows(mac: mac)
        if list.isEmpty { return "没有排任何时段" }
        if let a = activeWindow(mac: mac, now: now) {
            return "现在生效：\(a.title)"
        }
        if let n = nextWindow(mac: mac, now: now) {
            return "下一段：\(n.title)"
        }
        return "排了 \(list.count) 段，现在不生效"
    }

    /// 锁端只支持一段 —— 界面必须说明这一点。
    static let singleWindowNotice = "门锁本身只支持一段布防。App 会按上面的时段切换，并在切换时自动重新下发。"
}
