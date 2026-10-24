// 647/651 时间显示的两个口径 + 一条真边界。
//
// 为什么需要一个单独的文件而不是各页各写 DateFormatter: 本仓的时间串有三条来路 ——
// 锁内时钟 (`03#04` 协议秒, 基准 2010-01-01)、本机录入时刻、以及日志缓存里已经渲染好的
// `yyyy-MM-dd HH:mm:ss`。制式(12/24)与"要不要秒"如果分别在各页设，同一条记录会在
// 时间线、详情卡、导出 CSV 里显示成三个样子 —— 而那正是 647 想解决的"跨年排查错位"的兄弟问题。
//
// 647 的原句"作用于时间线与详情页全部时间字段"在这里是**逐字执行**的:
// 只有 `clock()` 与 `full()` 两个出口，页面不许自己拼 DateFormatter。
import Foundation

enum TimeFormat {
    /// "跟随系统 / 24 小时 / 12 小时" 三档。空串 = 跟随系统 (默认，老用户观感不变)。
    static let styleKey = "kf_time_style"
    /// 651 到秒: 默认关。协议时刻只到分 (`timeStr` 的秒位来自日志原文，不是每条都有)，
    /// 所以开了之后**没有秒位的行不补零** —— 补 ":00" 等于谎称那条记录精确到秒。
    static let secsKey = "kf_time_secs"

    static let styles = ["", "24", "12"]

    static var style: String {
        let v = DB.store.getString(styleKey)
        return styles.contains(v) ? v : ""
    }
    static var showSeconds: Bool { DB.store.getBool(secsKey) }

    /// 648 双行时间标注: 行内多一行完整日期。**默认关** —— 时间线一页能到上千行，
    /// 每行加一行字是整页密度的变化，不该由一个新功能单方面决定;
    /// 它解决的痛点 (跨年时"10月7日"到底是哪一年) 用开关换来，而不是默认压给所有人。
    static let twoLineKey = "kf_time_2ndline"
    static var twoLine: Bool { DB.store.getBool(twoLineKey) }

    /// 是否走 24 小时制: 显式档优先，跟随系统时问系统。
    static var hour24: Bool {
        switch style {
        case "24": return true
        case "12": return false
        default:
            // 系统模板里含 'H' 才是 24 小时制；含 'a'(AM/PM) 的是 12 小时制。
            let t = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: nil) ?? ""
            if t.contains("a") { return false }
            return t.contains("H") || t.contains("k")
        }
    }

    /// 把源串里**已经存在**的 `HH:mm` 或 `HH:mm:ss` 段按设置改写；识别不出时刻段时原样返回。
    /// 不做时区换算: 源串是锁端/本机记下的墙上时钟，换一次就与锁端键盘上的数字不一致了。
    /// 从 `yyyy-MM-dd HH:mm:ss` 里截出 `HH:mm`。**唯一实现**。
    ///
    /// 2026-10-23：这段曾在两个页面各写一遍（连注释都一样）；那两页已按原版对照删除。
    /// 它不涉及时制改写（那是上面的 `clock`），只是取时刻段，所以单独一支。
    static func shortClock(_ full: String) -> String {
        guard full.count >= 16 else { return full }
        let start = full.index(full.startIndex, offsetBy: 11)
        let end = full.index(full.startIndex, offsetBy: 16)
        return String(full[start..<end])
    }
    static func clock(_ raw: String) -> String {
        let parts = raw.split(separator: " ", omittingEmptySubsequences: true)
        let tail = parts.last.map(String.init) ?? raw
        guard tail.count >= 5, Self.isDigits(Array(tail.prefix(2))), tail[tail.index(tail.startIndex, offsetBy: 2)] == ":"
        else { return raw }                                   // 不是 HH:mm 开头 ⇒ 不猜
        let h = Int(tail.prefix(2)) ?? 0
        let rest = String(tail.dropFirst(3))                  // "mm" 或 "mm:ss"
        let hasSec = rest.count >= 5
        var hourText = "\(h)"
        if !hour24 {
            let mod = h % 12
            hourText = mod == 0 ? "12" : "\(mod)"
        } else if h < 10 && tail.prefix(1) == "0" {
            hourText = "0\(h)"                                 // 24 制且源串有前导零 ⇒ 保留零宽
        }
        var out = hourText + ":" + (rest.isEmpty ? "00" : String(rest.prefix(2)))
        // 651: 只有源串真的带秒才显示秒，缺位不补
        if showSeconds, hasSec, rest.count >= 5 {
            out += ":" + String(rest.dropFirst(3).prefix(2))
        }
        if !hour24 { out += h < 12 ? " 上午" : " 下午" }
        guard parts.count > 1 else { return out }
        return String(parts.dropLast().joined(separator: " ")) + " " + out
    }


    /// 665 区间日期精简: 同年省年份、同月省月份，跨年才补全。"2026-10-01"~"2026-10-07" → "10月1日–7日"。
    /// 按数字比较而不是按字符串找"月"字 —— 字符串写法一变 (补零、非零填充) 判断就悄悄失效。
    static func range(fromDay: String, toDay: String) -> String {
        func p(_ d: String) -> (y: Int, m: Int, day: Int)? {
            let s = d.split(separator: "-")
            guard s.count == 3, let y = Int(s[0]), let m = Int(s[1]), let dd = Int(s[2]) else { return nil }
            return (y, m, dd)
        }
        guard let a = p(fromDay), let b = p(toDay) else { return fromDay + "–" + toDay }
        if a.y == b.y, a.m == b.m { return "\(a.m)月\(a.day)日–\(b.day)日" }
        if a.y == b.y { return "\(a.m)月\(a.day)日–\(b.m)月\(b.day)日" }
        return "\(a.y)年\(a.m)月\(a.day)日–\(b.y)年\(b.m)月\(b.day)日"
    }

    /// 今晚 23:59 (本地) —— "今天内"这类快捷时长的终点。**唯一出口**：原先凭证工坊的两个表单
    /// 各抄了一份 `todayEnd()`，两份都写成了
    /// `Calendar.current.date(bySetting: .hourAndMinute(23, 59), of: Date())`。
    /// 那是不存在的 API：`date(bySetting:value:of:)` 要的 `Calendar.Component` 只有 `.hour` 与 `.minute`
    /// 两档 (机检依据 = Apple 文档 Foundation/Calendar/Component 的全部 case 列表)，而且 case 不能带参数；
    /// `.hourAndMinute` 只在 `DatePicker(displayedComponents:)` 那一侧合法。这一句在 CI 上是编译失败。
    /// 「距今几天」的**唯一算法**。
    ///
    /// 2026-10-23：本仓此前有两种写法，同一个时间戳会差 1 天 ——
    ///   · 多数地方：`Int((nowMs - ms) / 86_400_000)` —— 按**经过的 24 小时段**算；
    ///   · `BackupStudioKit`：`Int(now/86400) - Int(ms/86400)` —— 按**纪元日号**相减。
    /// 跨零点时两者答案不同（23:00 与次日 01:00 相差 2 小时：前者 0 天、后者 1 天）。
    ///
    /// 取前者：用户问「上次多久以前」时想的是**经过多久**，不是翻了几次日历。
    /// 负数（未来时间/时钟回拨）一律归 0，不返回负天数。
    static func daysSince(ms: Double) -> Int {
        guard ms > 0 else { return -1 }
        let d = Int((Date().timeIntervalSince1970 * 1000 - ms) / 86_400_000)
        return max(0, d)
    }
    static func dayEnd(_ now: Date = Date()) -> Date {
        WeekCal.gregorian.date(bySettingHour: 23, minute: 59, second: 0, of: now)
            ?? now.addingTimeInterval(86400)
    }

    private static func isDigits(_ c: [Character]) -> Bool { c.allSatisfy { $0.isNumber } }
}
