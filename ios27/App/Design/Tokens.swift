// Tokens.swift —— 设计令牌的唯一来源。
//
// 纪律：页面/组件里**不许**出现颜色字面量、间距字面量、圆角字面量、字号字面量。
// 一切走 T.* 与 Reading 组件；硬编码由 Gates/tokens.js 判失败。
//
// 色彩族只有两个：石墨（无彩）+ 铜锈（唯一品牌色）。状态色是语义色，不作装饰。
import SwiftUI

enum T {

    // MARK: - 间距（4/8 节奏）
    enum S {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        /// 页面左右边距。仪器面板靠边，不居中留白。
        static let gutter: CGFloat = 16
    }

    // MARK: - 圆角（同心：20 → 16 → 12）
    enum R {
        static let plate: CGFloat = 20
        static let inset: CGFloat = 16
        static let control: CGFloat = 12
        static let pill: CGFloat = 999
    }

    // MARK: - 触达与描边
    enum Hit {
        /// iOS 最小触达目标。
        static let min: CGFloat = 44
    }

    // MARK: - 控件高度（固定高度的唯一来源）
    enum H {
        /// chip / 分段控件。
        static let chip: CGFloat = 32
        /// 主动作 / 次级动作按钮。
        static let action: CGFloat = 50
        /// 台账行。
        static let row: CGFloat = 56
    }
    enum Stroke {
        /// 面板描边：0.5pt 在 Retina 上就是 1 物理像素的蚀刻线。
        static let hair: CGFloat = 0.5
        static let focus: CGFloat = 1.5
    }

    // MARK: - 图标尺寸（与相邻文字同视觉重量）
    enum Icon {
        static let s: CGFloat = 15
        static let m: CGFloat = 18
        static let l: CGFloat = 22
        static let xl: CGFloat = 28
    }

    // MARK: - 字体
    //
    // **全部走语义字阶（TextStyle），不写死 point size。** 这样 Dynamic Type 才是真的生效：
    // 用户在「设置 → 辅助功能 → 更大字体」里调大一档，整屏文字会一起跟着长大，
    // 而不是只有系统控件动、我们的文字纹丝不动（那是最常见的一类"假适配"）。
    //
    // 设计上要的 34 / 22 / 17 / 15 / 13 / 11 这些档位，在默认字号下**正好**等于系统
    // largeTitle / title2 / body / subheadline / footnote / caption2 —— 所以视觉不变，
    // 只是从"写死"变成"可缩放"。
    enum F {
        /// 把设计稿上的字号映射到最接近的系统字阶。只影响"用哪个字阶"，不改变默认视觉。
        static func style(for size: CGFloat) -> Font.TextStyle {
            switch size {
            case ..<12: return .caption2      // 11
            case 12..<14: return .footnote    // 13
            case 14..<16: return .subheadline // 15
            case 16..<18: return .body        // 17
            case 18..<21: return .title3      // 20
            case 21..<25: return .title2      // 22
            case 25..<32: return .title       // 28
            default: return .largeTitle       // 34
            }
        }

        /// 显示标题。中文最高 semibold —— 苹方无 Bold，.bold() 会静默回退。
        static func display(_ size: CGFloat = 34) -> Font {
            .system(style(for: size), weight: .semibold)
        }
        /// 小节标题（中文不加 tracking；只有全大写拉丁才加）。
        static let section = Font.system(.footnote, weight: .semibold)
        /// 正文。中文正文下限 12pt。
        static let body = Font.system(.subheadline, weight: .regular)
        static let bodyStrong = Font.system(.subheadline, weight: .medium)
        static let caption = Font.system(.footnote, weight: .regular)
        /// 单位小字：只出现在读数旁，从不单独成句。
        static let unit = Font.system(.caption2, weight: .regular)
        /// 读数：等宽。所有数字走这个，换值不跳宽。
        static func reading(_ size: CGFloat = 17, weight: Font.Weight = .medium) -> Font {
            .system(style(for: size), design: .monospaced, weight: weight)
        }
        /// 等宽时刻（台账行用）。
        static let stamp = Font.system(.footnote, design: .monospaced, weight: .medium)
        /// 图标字号（Image(systemName:) 用）：同样走字阶，才能随 Dynamic Type 缩放。
        static func icon(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(style(for: size), weight: weight)
        }
    }

    // MARK: - 动效（Premium：精密、克制、无回弹）
    enum M {
        static let snap = Animation.spring(response: 0.22, dampingFraction: 0.92)
        static let move = Animation.spring(response: 0.32, dampingFraction: 0.88)
        /// 只给刻度盘的真实进度弧。弹簧过冲会让"进度"撒谎。
        static let sweep = Animation.timingCurve(0.32, 0, 0.16, 1, duration: 0.6)
        static let exit = Animation.easeOut(duration: 0.18)
        /// 逐格点亮：每格 8ms，最多 60 格 = 480ms 上限。
        static let tickStep: Double = 0.008
    }
}

// MARK: - 色彩（明暗两套独立取值，不是反相）

extension Color {
    /// 由 0xRRGGBB 构造。仅 Tokens 内部使用。
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// 明暗自适应色。UIKit 动态色，跟随系统外观即时切换。
    static func dual(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

enum Ink {
    /// 页面底：冷纸 / 冷石墨。不是奶油，不是纯黑。
    static let paper = Color.dual(light: 0xF2F2EF, dark: 0x0B0C0D)
    /// 卡片 / 面板。
    static let plate = Color.dual(light: 0xFFFFFF, dark: 0x15171A)
    /// 凹槽 / 内嵌块 / 刻度底。
    static let plateAlt = Color.dual(light: 0xE9E9E4, dark: 0x1D2024)
    /// 分割线。需 ≥1.25:1 才看得见。
    static let hairline = Color.dual(light: 0xC9C9C2, dark: 0x2E3237)
    /// 主文本。
    static let ink = Color.dual(light: 0x14161A, dark: 0xF3F4F2)
    /// 次文本。与 inkFaint 保持 1.5:1 以上的层级差（否则"次要"看不出来）。
    static let inkSub = Color.dual(light: 0x4A5057, dark: 0xB0B7C0)
    /// 单位小字 / 刻度标注。仅 ≥11pt 且非关键信息；实测在三种底上都 ≥4.5:1。
    static let inkFaint = Color.dual(light: 0x61676E, dark: 0x828A93)
}

enum Signal {
    /// 品牌 / 铜锈：主行动填充、选中态、live 游标。同屏只出现在一处主动作。
    static let base = Color.dual(light: 0x1D6F5F, dark: 0x47C9A6)
    /// 压填充上的文字。深色用近黑墨色（白字压高亮浅色只有 3:1）。
    static let on = Color.dual(light: 0xFFFFFF, dark: 0x06201A)
    /// 弱化版：选中底 / 微光。由 base 调透明度得到，不另取色。
    static var wash: Color { base.opacity(0.12) }
}

enum State {
    /// 注意：低电 / 待同步 / 待下发。
    static let attention = Color.dual(light: 0x8A5A0B, dark: 0xE2A63A)
    /// 危险：开锁失败 / 越界 / 已失效。
    static let critical = Color.dual(light: 0xA32B22, dark: 0xFF6A5C)
    /// 正常：与品牌色同族（铜锈），不另取绿色。
    static var ok: Color { Signal.base }
}
