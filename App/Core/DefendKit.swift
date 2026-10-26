// 包9 布防（cmd25 SETDEFENCE）—— 原版 APK 有、iOS 侧此前只有构造器没有入口。
//
// 口径全部来自 apk_raw/assets/www/build/main.js 的 $o（page-defend）与 iu（page-defendhome）：
//   · control：0 = 撤防 / 1 = 不定期布防 / 2 = 时段布防 / 3 = readonly（本代 App 不发）
//   · 时段布防 = control 2，时间字段是**半秒分辨率的日内秒**（AutoOpenKit.defendActive 里 ×2 的那个口径）
//   · 撤防 = control 0，时间字段全 0
//   · 原版把「外出/在家」当两个视觉档，落到本机统一成 control 1（不定期）/ control 2（时段），
//     因为协议里只有 control 这一个自由度，多出来的区别只影响文案。
//
// 与自动开锁的关系：F4 是一道**否决门** —— 时段内一票否决自动开锁（AutoOpenKit.defendActive）。
// 所以写盘必须与锁端下发同时成立，否则会出现「锁端在布防、本机还在自动开」的错位。
import Foundation

/// 布防三态。rawValue 直接对齐 cmd25 的 control 语义，避免再做一层映射表。
enum DefendMode: Int, CaseIterable, Identifiable {
    case off = 0        // 撤防
    case once = 1       // 不定期布防（不设时段，一直生效到撤防）
    case period = 2     // 时段布防

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .off: return "撤防"
        case .once: return "不定期布防"
        case .period: return "时段布防"
        }
    }

    var subtitle: String {
        switch self {
        case .off: return "退出布防，门锁恢复正常开锁"
        case .once: return "一直布防到手动撤防（原版「外出布防」的常开档）"
        case .period: return "只在设定时段内布防（原版「在家布防」）"
        }
    }
}

enum DefendKit {
    /// 一天的半秒数 —— 协议时间字段的单位。AutoOpenKit.defendActive 内部把秒数 ×2 后与它比较。
    static let halfDay = 172_800
    /// 一天的秒数（用于 UI 与校验）。
    static let daySeconds = 86_400

    /// 时段校验。返回 nil 表示通过，否则是**原样展示给用户的那句话**。
    /// 三条判据对齐 APK：结束 > 开始、结束 > 当前、结束 ≠ 开始。
    /// 时间入参用**秒**（UI 直觉），内部换成半秒对齐协议。
    static func validate(mode: DefendMode, startSec: Int, endSec: Int, now: Date = Date()) -> String? {
        switch mode {
        case .off, .once:
            return nil
        case .period:
            if startSec < 0 || startSec >= daySeconds { return "开始时间不在一天之内" }
            if endSec < 0 || endSec > daySeconds { return "结束时间不在一天之内" }
            if endSec == startSec { return "结束时间不能等于开始时间" }
            if endSec < startSec { return "结束时间必须大于开始时间" }
            if endSec <= secondsOfDay(now) { return "结束时间必须大于当前时间" }
            return nil
        }
    }

    /// 当前时刻在一天内的秒数（本地时区，与锁端 display 时间同口径）。
    static func secondsOfDay(_ d: Date, cal: Calendar = WeekCal.gregorian) -> Int {
        let c = cal.dateComponents([.hour, .minute, .second], from: d)
        return (c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60 + (c.second ?? 0)
    }

    /// 秒 → 协议半秒值。**这是唯一的换算出口**：cmd25 收的是半秒，AutoOpenKit 比的也是半秒。
    static func protoSec(_ sec: Int) -> Int { max(0, min(daySeconds, sec)) * 2 }

    /// 协议半秒值 → 秒（读回历史配置时用）。
    static func secFromProto(_ proto: Int) -> Int { max(0, min(halfDay, proto)) / 2 }

    /// 「时:分」→ 日内秒。
    static func seconds(hour: Int, minute: Int) -> Int { hour * 3600 + minute * 60 }

    /// 日内秒 → 「HH:mm」，给列表与状态行展示。
    static func hhmm(_ sec: Int) -> String {
        let s = max(0, min(daySeconds, sec))
        return String(format: "%02d:%02d", s / 3600, (s % 3600) / 60)
    }

    /// 是不是「全天布防」。协议里 start == end 表示整天，AutoOpenKit 按 fail-closed 读成"全天"；
    /// 本页不会发出这种值，但读侧要能解释别人的历史值。
    static func isAllDay(_ cfg: DefendCfg) -> Bool {
        cfg.control == DefendMode.period.rawValue && cfg.startSec == cfg.endSec
    }

    /// 一句人话描述当前布防状态（首页卡与设置行共用）。
    static func summary(_ cfg: DefendCfg?, now: Date = Date()) -> String {
        guard let cfg else { return "当前无布防" }
        switch DefendMode(rawValue: cfg.control) ?? .off {
        case .off:
            return "当前无布防"
        case .once:
            return "不定期布防中"
        case .period:
            let s = secFromProto(cfg.startSec), e = secFromProto(cfg.endSec)
            if isAllDay(cfg) { return "全天布防中" }
            let active = AutoOpenKit.defendActive(control: cfg.control,
                                                  startSec: cfg.startSec,
                                                  endSec: cfg.endSec,
                                                  now: now)
            return "\(hhmm(s))–\(hhmm(e)) · \(active ? "时段内" : "时段外")"
        }
    }

    /// 当前是否处于布防生效中（含不定期与全天两种）。
    static func isActive(_ cfg: DefendCfg?, now: Date = Date()) -> Bool {
        guard let cfg else { return false }
        if cfg.control == DefendMode.once.rawValue { return true }
        return AutoOpenKit.defendActive(control: cfg.control,
                                        startSec: cfg.startSec,
                                        endSec: cfg.endSec,
                                        now: now)
    }
}
