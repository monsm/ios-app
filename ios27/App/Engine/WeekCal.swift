// 912 周起始日偏好 —— 一个共享的"按偏好配好的 Calendar"。
//
// 为什么必须先有这一个读点：周界算法在本仓散在四处 (Milestones 本周整理数 / MemberHub 本周轮值键 /
// RecordSearch 的"上周·本周"时间词 / CredentialCenterView 的月历起始列)。
// 若各页自己读 kf_week_start，就会出现"月历从周一排、'本周'却按周日起算"——
// 同一句"本周"在两处数出不同的天，这比没有该偏好更糟。
//
// 只管**周**：不改 Locale、不改时区、不动 .day/.month 的既有语义。
// 默认档 "" = 跟随系统/地区 (公历化后的当前日历原样)，因此这个功能默认不改变任何人的既有观感。
//
// 第一百五十八批补的口径：上面那句"跟随系统"跟着的是**周序**，不该跟着**历法**。
// iOS「设置 → 语言与地区 → 历法」可以选佛历/民国历/农历，`Calendar.current` 会整个换成那套历法，
// 于是 `.year` 取回 2569、`.month`/`.day` 按农历错位 —— 而本仓所有日期串、节假日表、锁端日志
// 都是公历的。`gregorian` 就是为此存在：只把历法钉成公历，其余四个旋钮原样照抄当前设置。
import Foundation

enum WeekCal {
    /// 公历化的"当前日历"：只钉 identifier = 公历，时区 / Locale / 一周首日 / 年初最少天数
    /// 全部照抄 `Calendar.current`。对系统本就设成公历的用户，这与 `Calendar.current` 同值。
    /// 刻意不缓存：`Calendar` 值类型每次读都反映当下设置 (用户中途改时区/地区不需要重启 App)，
    /// 而缓存要引入可变静态量 (Swift 6 数据竞争) 与失效键 —— 代价大于收益。
    /// 循环里可以先 `let cal = WeekCal.gregorian` 提出来复用；现网仍有几处逐元素取，
    /// 成本与原先逐次写 `Calendar.current` 相同 (那也是一个每次新建值类型的计算属性)，不是这批引入的回归。
    static var gregorian: Calendar {
        let cur = Calendar.current   // 历法例外：全仓唯一一处 `Calendar.current`，取完立刻钉成公历
        var c = Calendar(identifier: .gregorian)
        c.locale = cur.locale
        c.timeZone = cur.timeZone
        c.firstWeekday = cur.firstWeekday
        c.minimumDaysInFirstWeek = cur.minimumDaysInFirstWeek
        return c
    }

    /// kf_week_start: "" 跟随系统 / "mon" 周一 / "sun" 周日 / "sat" 周六
    /// 三个显式档的映射表。刻意不做"任意数字"输入：Sunday=1…Saturday=7 是 Calendar 的内部约定，
    /// 把它暴露成设置项等于让用户猜数字。
    private static let weekdayMap: [String: Int] = ["sun": 1, "mon": 2, "sat": 7]

    /// 加减**日历日**的唯一出口。`addingTimeInterval(±86_400)` 数的是 24 小时，
    /// 而有夏令时的地区里切换那一天是 23 或 25 小时：从某天零点减 24 小时会落到**前天的 23:00**，
    /// 于是 `dayKey(昨天)` 说成前天、两个日 key 之间"隔几天"也会差一格 (§10.33)。
    /// 无夏令时地区两者逐值相同 ⇒ 对国内用户是零行为变化，只是不再依赖这一点。
    /// 真的在算"时长"(例如有效期 = 此刻 + 168 小时) 的调用点**不该**改到这里来 —— 那要的就是秒数。
    static func shifted(_ d: Date, days: Int) -> Date {
        gregorian.date(byAdding: .day, value: days, to: d) ?? d.addingTimeInterval(Double(days) * 86_400)
    }

    static var key: String { DB.store.getString("kf_week_start") }

    /// 每次取都用新 Calendar 值类型 (struct)，不存在"改了 id 忘了同步 firstWeekday"的那类残留状态。
    static var calendar: Calendar {
        let key = WeekCal.key
        let base = gregorian
        guard let wd = weekdayMap[key] else { return base }
        var c = base
        c.firstWeekday = wd
        // minimalDaysInFirstWeek 一并钉死为 4 (ISO 口径)。不钉的话：firstWeekday 改了但"第一年算不算一周"
        // 仍随 Locale 变，weekOfYear 跨年那一周会给出错位的周号 —— 那是本偏好最隐蔽的破口。
        c.minimumDaysInFirstWeek = 4
        return c
    }

    /// 设置页展示用的中文名 (也给"跟随系统"档回显实际生效的那天)
    static func name(_ k: String) -> String {
        switch k {
        case "mon": return "周一"
        case "sun": return "周日"
        case "sat": return "周六"
        default: return "跟随系统"
        }
    }
}
