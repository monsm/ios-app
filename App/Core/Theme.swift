//
//  swift
//  全新设计系统 · 第一块基石
//
//  设计契约 (Design Contract)
//  ─────────────────────────────
//  隐喻   : 门。App 是一扇可以翻过来的门。
//  性格   : Premium —— 350-600ms、零过冲、优雅克制。
//  材质   : 玻璃 + 金属。门是金属, 光是唯一的装饰。
//  色彩   : 单色灰阶 + 铜色强调 (#B87333), 语义色只在仪表层。
//  字体   : 系统字体, 用尺度制造层级, 不用自定义字重。
//  空间   : 8pt 网格; 锁面周围 56pt 留白 (远离一切)。
//  动效   : 三层视差 (前景/中景/背景), 全部单调曲线, 禁止过冲。
//
//  约束 (不可违反)
//  ─────────────────────────────
//  · 所有动效必须走 XMotion.token, 禁止在视图里写 duration
//  · 所有颜色必须走 Palette, 禁止 Color(hex:) 散落
//  · calm 档 (减弱动效/低电量) 必须能压平任何动效
//  · 对比度: 正文 ≥4.5:1, 大字 ≥3:1 (WCAG AA)
//

import SwiftUI
import UIKit

// ═══════════════════════════════════════════════════════════
// MARK: - 色板
// ═══════════════════════════════════════════════════════════


/// 语义色板 —— 全 App 唯一色源
enum XPalette {
    // ── 中性灰阶 (12 档) ──
    /// 画布最底 (纯黑, AMOLED 友好)
    static var canvas: Color { XAppearance.isAMOLED ? .black : Color.adaptive(0xF5F5F7, 0x0A0A0B) }
    /// 主表面 (卡片/面板)
    static var surface: Color { Color.adaptive(0xFFFFFF, 0x161618) }
    /// 次表面 (内嵌区块)
    static var surfaceAlt: Color { Color.adaptive(0xF2F2F5, 0x1F1F22) }
    /// 第三表面 (输入框底)
    static var surfaceSunken: Color { Color.adaptive(0xEAEAEF, 0x121214) }

    // ── 描边 ──
    static var hairline: Color { Color.adaptive(0xD8D8DE, 0x323236) }
    static var hairlineStrong: Color { Color.adaptive(0xC8C8D0, 0x3A3A40) }

    // ── 文字 ──
    /// 正文 (对比度 ≥7:1)
    static var text: Color { Color.adaptive(0x0A0A0B, 0xF5F5F7) }
    /// 高光 (金属/玻璃上的镜面反射点)。
    /// 单独开一枚而不是复用 onAccent: 白天要的是纯白镜面反光, 夜间要的是
    /// 一层压得住暗底的冷光 —— 两者取值方向相反, 复用会有一头失真。
    static var specular: Color { Color.adaptive(0xFFFFFF, 0xC8C8D4) }

    /// 次级文字 (对比度 ≥4.5:1)
    static var textSub: Color { Color.adaptive(0x5A5A66, 0xA0A0AC) }
    /// 三级文字 (仅用于 ≥15pt)
    static var textTertiary: Color { Color.adaptive(0x72727C, 0x888892) }

    // ── 强调: 铜 (锁芯黄铜), 可被 kf_accent 覆盖 ──
    /// 六套可选强调色。空键 = 默认铜。
    /// 保留这条链的理由: 备份包里带 kf_accent, 恢复后不该"看着没恢复";
    /// 且未来若要给用户换色, 只需接 UI, 不用再改令牌求值路径。
    private static var accentOverride: (light: UInt32, dark: UInt32)? {
        switch DB.store.getString("kf_accent") {
        case "indigo":   return (0x4F46E5, 0x818CF8)
        case "forest":   return (0x15803D, 0x4ADE80)
        case "amber":    return (0xB45309, 0xFBBF24)
        case "graphite": return (0x3F3F46, 0xA1A1AA)
        case "rose":     return (0xBE123C, 0xFB7185)
        case "aurora":   return (0x0E7490, 0x22D3EE)
        default:         return nil
        }
    }
    static var accent: Color {
        if let o = accentOverride { return Color.adaptive(o.light, o.dark) }
        return Color.adaptive(0x9C5A22, 0xD98B45)
    }
    static var accentText: Color { Color.adaptive(0x8F5A28, 0xE8A05C) }
    static var onAccent: Color { Color.adaptive(0xFFFFFF, 0x0A0A0B) }

    // ── 凭证工坊的四类色 ──
    //
    // 这四色原本写在 StudioPage 里当 Color(hex:)，而 Color(hex:) 不区分明暗 ——
    // 同一个 teal 在浅色底上只有 2.96:1 (低于 WCAG 非文字 3:1)，深色底却是 6.11:1。
    // 现在按档给两份值: 浅色用更深的同色相，深色保持原样。
    /// 指纹 (青)
    static var kindFp: Color { Color.adaptive(0x0E7C7C, 0x2AA6A6) }
    /// OTP (紫)
    static var kindOtp: Color { Color.adaptive(0x5B3FA0, 0x8060C8) }

    // ── 语义 ──
    static var ok: Color { Color.adaptive(0x1B7F4D, 0x3DD68C) }
    static var warn: Color { Color.adaptive(0xB45309, 0xF5A524) }
    static var danger: Color { Color.adaptive(0xB3261E, 0xFF6B6B) }

}

// ═══════════════════════════════════════════════════════════
// MARK: - 间距 / 尺寸
// ═══════════════════════════════════════════════════════════

/// 8pt 网格。所有间距必须取自这里。
enum XSpace {
    static var xxs: CGFloat { d(2) }
    static var xs: CGFloat { d(4) }
    static var s: CGFloat { d(8) }
    static var m: CGFloat { d(12) }
    static var l: CGFloat { d(16) }
    static var xl: CGFloat { d(24) }
    static var xxl: CGFloat { d(32) }
    /// 屏幕左右边距
    static var gutter: CGFloat { d(16) }
    /// 卡片内边距
    static var card: CGFloat { d(16) }
    /// 控件内边距
    static var control: CGFloat { d(12) }
    /// 磁贴内边距
    static var tile: CGFloat { d(14) }
}

/// 圆角。门锁 App 的圆角偏小 (金属感), 不用 iOS 默认的大圆角。
enum XRadius {
    static var card: CGFloat { r(16) }
    static var control: CGFloat { r(12) }
    static var tile: CGFloat { r(14) }
    static var min: CGFloat { r(8) }
}

/// 触达尺寸
enum XHit {
    /// HIG 最小触达
    static let min: CGFloat = 44
    /// 锁面主控
    static let dial: CGFloat = 200
    static let tlGap: CGFloat = 10
}

/// 图标尺寸

// ═══════════════════════════════════════════════════════════
// MARK: - XOpacity — 语义化透明度
// ═══════════════════════════════════════════════════════════
//
// 清 opacity 时发现全仓有 34 种不同取值、113 处 ——
// 光"图标底色"这一类就有 0.12 / 0.13 / 0.14 三种,
// 视觉上几乎看不出差别, 但是三份维护成本, 而且改一处不知道另两处在哪。
//
// 这里按**语义**收敛成五档。不是所有 opacity 都该进来:
//   · 0.001 那种是"开关量"(有/无), 不是透明度语义 → 留在原地
//   · 0.88 / 0.90 / 0.95 是渐变里的停点, 属于渐变定义 → 留在原地
//   · 动画中间态 (charge / burst) 是计算值 → 留在原地
enum XOpacity {
    /// 洗染底: 大面积浅色填充 (危险横幅 / 警告条)
    static let wash: Double = 0.10
    /// 图标/徽章底: 28pt 图标后的那层同色底
    static let badge: Double = 0.12
    /// 柔光: 状态灯外圈、光晕
    static let glow: Double = 0.16
    /// 描边: 卡片 tone 描边
    static let edge: Double = 0.35
    /// 淡底环: 仪表盘的底弧、内圈高光这类"有但不抢眼"的线
    static let track: Double = 0.55
}

enum XIcon {
    static let xs: CGFloat = 13
    static let sm: CGFloat = 16
    static let md: CGFloat = 20
    static let lg: CGFloat = 26
    static let xl: CGFloat = 44
    /// 门锁 App 新增: 锁面主图标
    static let lock: CGFloat = 72
}

/// 度量
enum XMetric {
    static var dial: CGFloat {
        // 尊重用户的锁面尺寸偏好 (既有设置项)
        let v = DB.store.getInt("kf_dial_size", 200)
        return CGFloat(min(max(v, 120), 280))
    }
    static var rowMinH: CGFloat { 44 }
    static var tlGap: CGFloat { XSpace.m }
    static var emptyMascot: Bool { !Milestones.plainMode }

    /// 装饰性大图标随辅助功能字号适度放大 (HIG typography: 承载信息的图标
    /// 在字号变大时也要跟着变大 —— 上限 1.35 倍, 再大就会顶破版面)。
    /// 纯装饰图形 (空态吉祥物 / 成功对勾) 也走这一档, 免得两套口径。
    /// 夜间暗化 (22:00–06:00) —— 圆盘等强光界面用
    static var isNightDim: Bool {
        let h = WeekCal.gregorian.component(.hour, from: Date())
        return h >= 22 || h < 6
    }

    /// Canvas 组件内的**数据文字**按 AX 字号放大。
    ///
    /// 为什么单独开一个而不是直接用 decorIcon:
    ///   decorIcon 是给装饰图标的 (空态吉祥物、成功对勾), 上限 1.35;
    ///   数据文字 (OTP 码 / 电量百分数 / 天数) 是**承载信息**的,
    ///   放大需求比装饰更刚性, 但同样受限于环形/方形器皿的固定尺寸,
    ///   所以上限一样取 1.35 —— 再多就会溢出器皿, 反而更难读。
    ///
    /// 这类文字不能走语义字号 (.title/.body):
    ///   它们要和旁边的 Canvas 图形保持比例, 语义字号在 AX 下会跳档,
    ///   一跳就与环/弧的位置错开。
    static func dataText(_ base: CGFloat) -> CGFloat {
        decorIcon(base)
    }

    static func decorIcon(_ base: CGFloat) -> CGFloat {
        let size = AXFlags.typeSizeSnapshot
        let scale: CGFloat
        switch size {
        case .xSmall, .small, .medium: scale = 1.0
        case .large: scale = 1.05
        case .xLarge: scale = 1.10
        case .xxLarge: scale = 1.15
        case .xxxLarge: scale = 1.20
        case .accessibility1: scale = 1.26
        default: scale = 1.35
        }
        return base * scale
    }
}

/// 从「密度」设置派生 (兼容旧 API)
private func d(_ base: CGFloat) -> CGFloat { base }
private func r(_ base: CGFloat) -> CGFloat { base }

// ═══════════════════════════════════════════════════════════
// MARK: - 动效
// ═══════════════════════════════════════════════════════════

/// 动效令牌 —— 全 App 唯一动效源。
///
/// 三档: calm (减弱动效/低电量) / standard / lively
/// 原则: **单调曲线, 零过冲**。过冲在 3D 翻转里会越过 90° 露出镜像背面。
enum XMotion {
    /// 系统减弱动态 (快照, 非主 actor)
    private static var systemReduceMotion: Bool { AXFlags.reduceMotionSnapshot }

    private static var tier: String {
        if systemReduceMotion { return "calm" }
        if BatteryCare.appLowBattery { return "calm" }
        return "standard"
    }

    // ── 基础档 ──
    /// 微反馈 (按下/切换)
    static var quick: Animation {
        switch tier {
        case "calm": return .easeOut(duration: 0.10)
        case "lively": return .spring(response: 0.22, dampingFraction: 0.68)
        default: return .spring(response: 0.22, dampingFraction: 0.9)
        }
    }

    /// 标准 (状态切换)
    static var standard: Animation {
        switch tier {
        case "calm": return .easeInOut(duration: 0.16)
        case "lively": return .spring(response: 0.45, dampingFraction: 0.68)
        default: return .spring(response: 0.4, dampingFraction: 0.85)
        }
    }

    /// 柔和 (淡入淡出)
    static var soft: Animation {
        switch tier {
        case "calm": return .easeInOut(duration: 0.12)
        case "lively": return .easeInOut(duration: 0.34)
        default: return .easeInOut(duration: 0.25)
        }
    }

    /// 退场
    static var exit: Animation {
        switch tier {
        case "calm": return .easeOut(duration: 0.08)
        case "lively": return .easeOut(duration: 0.20)
        default: return .easeOut(duration: 0.15)
        }
    }

    // ── 召唤 / 甩动 ──
    static var summon: Animation {
        switch tier {
        case "calm": return .easeOut(duration: 0.12)
        default: return .spring(response: 0.35, dampingFraction: 1.0)
        }
    }

    // ── 门面层 (全新) ──
    //
    //  门的翻转必须用**单调 timingCurve**, 不能用 spring。
    //  原因: 180° 翻转中, spring 即使 damping 1.0 也可能因 response 与初速度过冲,
    //  越过 90° 会露出镜像背面。timingCurve 单调, 绝不越过终点。
    //
    /// 门板旋转 (0→180°)
    static var doorSwing: Animation {
        switch tier {
        case "calm": return .easeOut(duration: 0.12)
        default: return .timingCurve(0.22, 0.76, 0.03, 1, duration: 0.82)
        }
    }


    /// 门后内容入场
    static var doorReveal: Animation {
        switch tier {
        case "calm": return .easeOut(duration: 0.20)
        default: return .timingCurve(0.22, 0.76, 0.03, 1, duration: 0.70)
        }
    }


    /// 充能松手回零
    static var chargeReset: Animation {
        switch tier {
        case "calm": return .easeOut(duration: 0.08)
        default: return .easeOut(duration: 0.18)
        }
    }

}


// ═══════════════════════════════════════════════════════════
// MARK: - 触感
// ═══════════════════════════════════════════════════════════

/// 触感 —— 只用 UIKit 三档, 不引入 CoreHaptics。
///
/// 语义约定 (全 App 一致):
///   tick    = 我在 / 步进 / 边界
///   trigger = 完成 / 确认
///   warning = 需要你注意
///   error   = 失败 / 拒绝
///
/// UIFeedbackGenerator 是 UIKit 对象 (主 actor), 整族标 @MainActor。
/// 调用点都在视图动作里; 非 UI 调用需显式跳主 actor。
@MainActor
enum XHaptics {
    static let tick = UIImpactFeedbackGenerator(style: .light)
    static let trigger = UIImpactFeedbackGenerator(style: .medium)
    static let soft = UIImpactFeedbackGenerator(style: .soft)

    /// 成功 (完成一件事)
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    /// 警告
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    /// 错误
    static func failure() { UINotificationFeedbackGenerator().notificationOccurred(.error) }

    /// 预准备 (降低延迟)
    static func prepare() {
        tick.prepare(); trigger.prepare()
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - 渐变
// ═══════════════════════════════════════════════════════════

enum XGradient {
    /// 门面底色 (三停: 上暗 → 中亮 → 下暗)
    static var doorSurface: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.adaptive(0xE8E8ED, 0x0E0E10), location: 0.0),
                .init(color: Color.adaptive(0xF5F5F7, 0x1A1A1D), location: 0.42),
                .init(color: Color.adaptive(0xD8D8DF, 0x0B0B0D), location: 1.0)
            ],
            startPoint: .top, endPoint: .bottom)
    }


    /// 锁面金属环
    static var lockRing: AngularGradient {
        AngularGradient(
            colors: [
                Color.adaptive(0xC0C0C8, 0x3A3A42),
                Color.adaptive(0x8A8A96, 0x6A6A74),
                Color.adaptive(0xE0E0E8, 0x2A2A30),
                Color.adaptive(0x8A8A96, 0x6A6A74),
                Color.adaptive(0xC0C0C8, 0x3A3A42)
            ],
            center: .center)
    }

    // ── 兼容旧名 ──
    static var hero: LinearGradient { doorSurface }
}

// ═══════════════════════════════════════════════════════════
// MARK: - 兼容层 (底层代码依赖的旧 API)
// ═══════════════════════════════════════════════════════════



// ═══════════════════════════════════════════════════════════
// MARK: - 外观开关 (2026-10-21 从 DS.Appearance 迁出)
// ═══════════════════════════════════════════════════════════

enum XAppearance {
    /// AMOLED 纯黑 (kf_theme == "black")
    static var isAMOLED: Bool { DB.store.getString("kf_theme") == "black" }
    /// App 内高对比皮肤：与系统「增加对比度」并联
    @MainActor static var highContrast: Bool { AXFlags.highContrast || DB.store.getBool("kf_hc") }
}


// ═══════════════════════════════════════════════════════════
// MARK: - 色彩基元 (2026-10-21 从已删的 DesignSystem.swift 迁入)
// ═══════════════════════════════════════════════════════════

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255)
    }

    /// 明暗自适应色。light / dark 为 6 位 RGB 十六进制
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light))
        })
    }
}
