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

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255)
    }

    /// 明暗自适应
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light))
        })
    }
}

/// 语义色板 —— 全 App 唯一色源
enum XPalette {
    // ── 中性灰阶 (12 档) ──
    /// 画布最底 (纯黑, AMOLED 友好)
    static var canvas: Color { DS.Appearance.isAMOLED ? .black : Color.adaptive(0xF5F5F7, 0x0A0A0B) }
    /// 主表面 (卡片/面板)
    static var surface: Color { Color.adaptive(0xFFFFFF, 0x161618) }
    /// 次表面 (内嵌区块)
    static var surfaceAlt: Color { Color.adaptive(0xF2F2F5, 0x1F1F22) }
    /// 第三表面 (输入框底)
    static var surfaceSunken: Color { Color.adaptive(0xEAEAEF, 0x121214) }

    // ── 描边 ──
    static var hairline: Color { Color.adaptive(0xE2E2E8, 0x2A2A2E) }
    static var hairlineStrong: Color { Color.adaptive(0xC8C8D0, 0x3A3A40) }

    // ── 文字 ──
    /// 正文 (对比度 ≥7:1)
    static var text: Color { Color.adaptive(0x0A0A0B, 0xF5F5F7) }
    /// 次级文字 (对比度 ≥4.5:1)
    static var textSub: Color { Color.adaptive(0x5A5A66, 0xA0A0AC) }
    /// 三级文字 (仅用于 ≥15pt)
    static var textTertiary: Color { Color.adaptive(0x8A8A96, 0x707078) }

    // ── 强调: 铜 (锁芯黄铜) ──
    static var accent: Color { Color.adaptive(0x9C5A22, 0xD98B45) }
    static var accentText: Color { Color.adaptive(0x8F5A28, 0xE8A05C) }
    static var onAccent: Color { Color.adaptive(0xFFFFFF, 0x0A0A0B) }

    // ── 语义 ──
    static var ok: Color { Color.adaptive(0x1B7F4D, 0x3DD68C) }
    static var warn: Color { Color.adaptive(0xB45309, 0xF5A524) }
    static var danger: Color { Color.adaptive(0xB3261E, 0xFF6B6B) }

    // ── 兼容旧名 (底层代码在用) ──
    static var canvasBase: Color { canvas }
    static var surfaceBase: Color { surface }
    static var surfaceAltBase: Color { surfaceAlt }
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
    /// 锁面留白 (远离一切)
    static var lockFace: CGFloat { d(56) }
}

/// 圆角。门锁 App 的圆角偏小 (金属感), 不用 iOS 默认的大圆角。
enum XRadius {
    static var card: CGFloat { r(16) }
    static var control: CGFloat { r(12) }
    static var tile: CGFloat { r(14) }
    /// 锁面圆环
    static var dial: CGFloat { r(999) }
    static var min: CGFloat { r(8) }
    static var rowMinH: CGFloat { r(12) }
    static var tlGap: CGFloat { r(10) }
}

/// 触达尺寸
enum XHit {
    /// HIG 最小触达
    static let min: CGFloat = 44
    /// 锁面主控
    static let dial: CGFloat = 200
    static let rowMinH: CGFloat = 44
    static let tlGap: CGFloat = 10
    static let emptyMascot: CGFloat = 96
    static let heroTexture: CGFloat = 120
}

/// 图标尺寸
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
    static var heroTexture: String { "" }
    static var digitDesign: Font.Design { .rounded }
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
    static var fling: Animation {
        switch tier {
        case "calm": return .easeOut(duration: 0.12)
        default: return .spring(response: 0.35, dampingFraction: 0.82)
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

    /// 中缝透光 (先于门转动 340ms)
    static var lightLeak: Animation {
        switch tier {
        case "calm": return .easeOut(duration: 0.10)
        default: return .easeOut(duration: 0.42)
        }
    }

    /// 门后内容入场
    static var doorReveal: Animation {
        switch tier {
        case "calm": return .easeOut(duration: 0.20)
        default: return .timingCurve(0.22, 0.76, 0.03, 1, duration: 0.70)
        }
    }

    /// 锁体字形闭环/开环
    static var glyphSwap: Animation {
        switch tier {
        case "calm": return .easeOut(duration: 0.12)
        default: return .easeOut(duration: 0.26)
        }
    }

    /// 充能松手回零
    static var chargeReset: Animation {
        switch tier {
        case "calm": return .easeOut(duration: 0.08)
        default: return .easeOut(duration: 0.18)
        }
    }

    /// 三层视差的延迟错峰
    static func parallaxDelay(_ layer: Int) -> Double {
        switch tier {
        case "calm": return 0
        default: return Double(layer) * 0.04
        }
    }
}

/// 时长 (兼容旧 API)
enum XDuration {
    static var quick: Double { 0.18 }
    static var standard: Double { 0.30 }
    static var slow: Double { 0.52 }
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
enum XHaptics {
    static let tick = UIImpactFeedbackGenerator(style: .light)
    static let trigger = UIImpactFeedbackGenerator(style: .medium)
    static let soft = UIImpactFeedbackGenerator(style: .soft)
    static let rigid = UIImpactFeedbackGenerator(style: .rigid)

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

    /// 门缝透光
    static var seamLight: LinearGradient {
        LinearGradient(
            colors: [.clear,
                     Color(hex: 0xFFE4B6).opacity(0.90),
                     Color(hex: 0xFFECC4).opacity(0.95),
                     .clear],
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
    static var button: LinearGradient {
        LinearGradient(colors: [XPalette.accent, XPalette.accent.opacity(0.85)],
                       startPoint: .top, endPoint: .bottom)
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - 兼容层 (底层代码依赖的旧 API)
// ═══════════════════════════════════════════════════════════

