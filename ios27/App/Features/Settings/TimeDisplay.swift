// TimeDisplay.swift —— 时间显示制式的界面出口（12/24、秒、双行日期）。
//
// 来源：原 App/Core/TimeFormat.swift（12/24 制式、显示秒、双行日期）。
// 引擎 TimeFormat 只保留机器口径（clock/dayKey 固定格式，不改 Engine/**）；
// 这里按 SettingsStore 的档位在**界面层**换写法：制式不做时区换算，锁端键盘几点就显示几点。
import Foundation

enum TimeDisplay {
    static var store: SettingsStore { SettingsStore.shared }

    /// 时刻。跟随系统时用系统 12/24 设置；显式档位时用该档。
    static func clock(_ epochMillis: Int64) -> String {
        let date = TimeFormat.date(epochMillis)
        let parts = TimeFormat.calendar.dateComponents([.hour, .minute, .second], from: date)
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        let second = parts.second ?? 0
        let use12: Bool
        switch store.timeStyle {
        case .h24: use12 = false
        case .h12: use12 = true
        case .system:
            let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: Locale.current) ?? ""
            use12 = template.contains("a")
        }
        var h = hour
        var suffix = ""
        if use12 {
            suffix = hour < 12 ? " AM" : " PM"
            h = hour % 12 == 0 ? 12 : hour % 12
        }
        let base = use12
            ? String(format: "%d:%02d", h, minute)
            : String(format: "%02d:%02d", h, minute)
        return store.showSeconds ? base + String(format: ":%02d", second) + suffix : base + suffix
    }

    /// 双行日期：开了两行档才给第二行；否则 nil（调用方不写空行）。
    static func dayLine(_ epochMillis: Int64) -> String? {
        guard store.twoLineDate else { return nil }
        return TimeFormat.dayShort(epochMillis)
    }

    /// 记录时间戳（带秒）：原文真带秒时用，缺位不补 :00。
    static func stamp(_ text: String) -> String {
        guard store.showSeconds else { return String(text.prefix(16)) }
        return text
    }
}
