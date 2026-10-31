// AutoOpenKit.swift —— 靠近自动开锁的**纯逻辑**部分（可单测，无 UI 依赖）。
//
// 从上一版 AutoOpen.swift 抽出。那个文件 849 行，尾部有一大段 SwiftUI 视图
// （标定页 / 面板），所以整份搬不进来 —— 但门控判定是安全级逻辑，必须原样保留。
// 这里只收「布防互锁」这一条，因为 DefendKit 的 F4 否决门要读它。
import Foundation

enum AutoOpenKit {
    // ---------- F4 布防互锁：control==2 时段布防，当前时刻在 start/end 内 → 一票否决 ----------
    /// startSec/endSec 为日内秒（SETDEFENCE 协议口径，半秒分辨率）；仅 control==2 生效。
    /// 跨午夜：start > end 时时段 = [start, 24h) ∪ [0, end)。
    /// start == end 按**全天布防**处理（fail-closed）：把退化成空集的窗口读成"不布防"，
    /// 等于让一次配错直接把门关掉 —— 门序里没有其它门会替它兜住这段时段。
    static func defendActive(control: Int, startSec: Int, endSec: Int, now: Date,
                             cal: Calendar = WeekCal.gregorian) -> Bool {
        // 安全级：只有 control==0（撤防）不否决；1（不定期）与 2（时段）都是布防态。
        guard control != 0 else { return false }
        guard control == 2 else { return true }
        guard startSec != endSec else { return true }
        let comps = cal.dateComponents([.hour, .minute, .second], from: now)
        // 协议值是「一天内秒数 ÷ 2」，当前时刻也要 ÷2 才同口径（上一版在这里错过一次）。
        let secOfDay = ((comps.hour ?? 0) * 3600 + (comps.minute ?? 0) * 60 + (comps.second ?? 0)) / 2
        if startSec < endSec {
            return secOfDay >= startSec && secOfDay < endSec
        }
        return secOfDay >= startSec || secOfDay < endSec
    }
}
