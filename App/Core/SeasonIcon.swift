// 897 四季图标：现有四款图标按**图标自己的底色**对到四季，再可选"回前台时对齐当季"。
//
// 为什么不是"春夏秋冬该是什么色"：四季映射直接取**当初那四组既有色** (默认靛蓝 / Ring 绿 / Key 琥珀 /
// Shield 石墨)，底色写在 SettingsView 的 iconOptions 里。896 后来把备选图标扩到九款，本文件的季节档
// 仍然只认原来这四款 —— 这不是漏改：`alignOnForeground` 里那句"用户选的是别的 (或将来新增的) 图标
// → 尊重选择，只记号不动手"就是为这一批准备的，新增五款因此**不会**被四季自动换掉。
// 反过来，也不给新增的五款再造一套"春季标准色"—— 那属于创意里没有的东西。
//
// 默认**关**：桌面图标是用户手机首屏上看得见的东西，App 在后台把它悄悄换掉属于越界，
// 所以这一档必须显式开，且关掉后行为与旧版一致 (只有手动点图标会换)。
import UIKit

nonisolated enum SeasonIcon {
    static let autoKey = "kf_icon_season"
    static let lastKey = "kf_icon_season_last"

    static var autoOn: Bool { DB.store.getBool(autoKey) }
    static func setAuto(_ v: Bool) { DB.store.set(autoKey, v) }

    /// 月份 → 图标名 (nil = 主图标)。季度划分用气象季 (3-5 春 / 6-8 夏 / 9-11 秋 / 12-2 冬)，
    /// 不用天文季或节气：节气要另一套算法，而这里要的只是"三个月换一次"这种可预期的东西。
    static func name(forMonth month: Int) -> String? {
        switch month {
        case 3, 4, 5: return "AppIcon-Ring"      // 绿 0x178040
        case 6, 7, 8: return nil                  // 夏 = 主图标 (靛蓝 0x5A55EC)
        case 9, 10, 11: return "AppIcon-Key"      // 琥珀 0x9A5B10
        default: return "AppIcon-Shield"          // 冬 = 石墨 0x334155
        }
    }

    static func seasonName(_ month: Int) -> String {
        switch month {
        case 3, 4, 5: return "春"
        case 6, 7, 8: return "夏"
        case 9, 10, 11: return "秋"
        default: return "冬"
        }
    }

    /// 回前台时对齐当季 (scenePhase .active 调)。三道门，任一不过就一个字节都不动：
    /// ① 开关没开; ② 系统不允许换图标 (supportsAlternateIcons == false);
    /// ③ 这一季已经对齐过 (用年-季记号防"每次回前台都调一次 API")。
    /// 与用户手动选过的图标冲突时**不覆盖**：只有当他选的就是别的季节图标且季节确实变了才换。
    static func syncIfNeeded(now: Date = Date()) {
        guard autoOn else { return }
        let app = UIApplication.shared
        guard app.supportsAlternateIcons else { return }
        let cal = WeekCal.calendar
        let y = cal.component(.year, from: now)
        let m = cal.component(.month, from: now)
        let stamp = "\(y)-\(seasonName(m))"
        guard DB.store.getString(lastKey) != stamp else { return }
        let target = name(forMonth: m)
        // 只有当前图标已经是"四季之一"才自动对齐；
        // 用户选的是别的 (或将来新增的) 图标 → 尊重选择，只记号不动手。
        let four = [nil, "AppIcon-Ring", "AppIcon-Key", "AppIcon-Shield"]
        guard four.contains(app.alternateIconName) else {
            DB.store.set(lastKey, stamp)
            return
        }
        DB.store.set(lastKey, stamp)
        app.setAlternateIconName(target) { _ in
            // 失败不追报也不重试：图标是纯装饰，下一次回前台会因记号已写而不再打扰。
            // 这里刻意不 log —— 错误描述可能带系统文案，把它写进日志台账没有价值只有噪音。
        }
    }
}
