// 设计令牌 · 间距 / 度量 / 主控卡指标
// 2026-10-29 从 DesignSystem.swift（666 行）再拆出。
import SwiftUI

extension DS {
    enum Space {
        /// 紧凑 0.85 / 标准 1.0 / 宽松 1.18
        static var densityScale: CGFloat {
            switch DB.store.getString("kf_density") {
            case "compact": return 0.85
            case "relaxed": return 1.18
            default: return 1.0
            }
        }
        /// 缩放并吸附到 0.5pt, 避免亚像素抖动
        private static func d(_ v: CGFloat) -> CGFloat { (v * densityScale * 2).rounded() / 2 }
        static var xxs: CGFloat { d(2) }
        static var xs: CGFloat { d(4) }
        static var s: CGFloat { d(8) }
        static var m: CGFloat { d(12) }
        static var l: CGFloat { d(16) }
        static var xl: CGFloat { d(24) }
        static var xxl: CGFloat { d(32) }
        /// 页面左右边距 (统一 gutter)
        static var gutter: CGFloat { d(16) }
    }
    enum Metric {
        static var dial: CGFloat {
            let v = DB.store.getInt("kf_dial_size", 176)
            return CGFloat([160, 176, 200].contains(v) ? v : 176)
        }
        /// 901 凭证行高两档: kf_row_h ""(紧凑: 44, 隐藏副行只留名称与状态)/"tall"(舒适: 60, 带副行)。
        /// 只做"加高"不做"压矮" —— 矮过内容自己撑开的高度就得靠裁切文字换空间，那是破版不是紧凑。
        /// 与无障碍页的 `kf_ax_bigotp` (OTP 大字) 是两回事：那档改字号，这档改行最小高度。
        static var rowMinH: CGFloat {
            DB.store.getString("kf_row_h") == "tall" ? 60 : 44
        }
        /// 907 时间线行距三档: kf_tl_gap。刻意**乘在 densityScale 之上**而不是替代它 ——
        /// 布局密度 (kf_density) 管的是全 App 的呼吸感，这一档只管记录时间线那一条竖列。
        /// 两档体系叠乘而不是各写一套，是为了避免"密度调了、时间线不动"的那类假设置。
        static var tlGap: CGFloat {
            let f: CGFloat
            switch DB.store.getString("kf_tl_gap") {
            case "tight": f = 0.5
            case "loose": f = 2.0
            default: f = 1.0
            }
            return (DS.Space.m * f * 2).rounded() / 2
        }
        /// 902 数字字体两档: kf_digit_font ""(圆体 = 默认, 与旧版观感一致) / "plain"(系统默认体)。
        /// 射程如实圈死: 这一档只管**读数令牌的两处落点** (MetricTile 与 HeroStat 的数字 Text),
        /// 902 原句就是"Hero 卡电量数字圆体/默认体可选"。它不是全 App 数字字体总闸 ——
        /// 那版 (§84 撤掉的那种) 要动 58 处各写死 monospacedDigit 的散点, 散点没统一成令牌之前
        /// 加总闸只会造出"切了没反应"；这里只承诺切得到、也切得到的那两处。
        static var digitDesign: Font.Design {
            DB.store.getString("kf_digit_font") == "plain" ? .default : .rounded
        }
    }
    enum HeroStats {
        static let all = ["firmware", "lockclock"]
        static var visible: Set<String> {
            let stored = DB.store.get([String].self, "kf_hero_stats") ?? []
            let keep = Set(stored.filter { all.contains($0) })
            return keep.isEmpty ? Set(all) : keep
        }
        static func shows(_ id: String) -> Bool { visible.contains(id) }
        static func setVisible(_ ids: [String]) {
            DB.store.set("kf_hero_stats", all.filter { ids.contains($0) })
        }
    }
}
