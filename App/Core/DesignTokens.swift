// 设计令牌 · 圆角 / 触达 / 图标 / 动效 / 时长 / 触感 / 外观 / 渐变
// 2026-10-29 从 DesignSystem.swift（1012 行）拆出 —— 都是 DS 的子 enum，
// 用 `extension DS { ... }` 保持 `DS.Radius.card` 这种调用形式不变。
import SwiftUI

extension DS {
    enum Radius {
        private static var k: CGFloat {
            switch DB.store.getString("kf_radius") {
            case "soft": return 0.62      // 小圆角: 更硬朗, 密集列表更省空间
            case "plump": return 1.3      // 大圆角: 更柔和, 与"儿童友好档"预设同向
            default: return 1.0
            }
        }
        private static func r(_ v: CGFloat) -> CGFloat { (v * k * 2).rounded() / 2 }
        static var card: CGFloat { r(22) }
        static var control: CGFloat { r(16) }
        static var tile: CGFloat { r(18) }
    }
    enum Hit { static let min: CGFloat = 44 }
    enum Haptics {
        static let tick = UIImpactFeedbackGenerator(style: .light)
        static let trigger = UIImpactFeedbackGenerator(style: .medium)
    }
    enum Icon {
        static let xs: CGFloat = 13
        static let sm: CGFloat = 16
        static let md: CGFloat = 20
        static let lg: CGFloat = 26
        static let xl: CGFloat = 44
    }
    enum Motion {
        /// 系统减弱动态 = 强制最静的一档，用户偏好让路 (这不是偏好，是无障碍硬约束)。
        /// 读 AXFlags 而不是自己调 UIAccessibility：本仓的系统旗标只有一个读点。
        /// 这里用的是**快照**而不是 @MainActor 的那个属性: 令牌会被 ButtonStyle/ToggleStyle 的
        /// makeBody (非隔离) 求值, 而系统旗标本身是主 actor 的 —— 快照由 AXFlags 在回前台时刷新。
        // 2026-10-28 修复：这里曾写死 `false`（注释「无障碍层已删」）——
        // 但上面 :227-230 的注释还在说「系统减弱动态 = 强制最静的一档，用户偏好让路
        // （这不是偏好，是无障碍硬约束）」。于是系统「减弱动态效果」对本 App 的所有
        // DS.Motion 令牌（quick/standard/soft/exit）完全无效 —— 一个无障碍硬约束被静默摘掉了。
        // 现接回快照：AXFlags 在启动 + 每次回前台刷新（见 RootView 的 scenePhase 处）。
        private static var systemReduceMotion: Bool { AXFlags.reduceMotionSnapshot }
        private static var tier: String {
            if systemReduceMotion { return "calm" }
            // 120 低电视觉降级: 锁电量 ≤20% 时全 App 动效也压到 calm —— 与系统减弱动态同优先级,
            // 用户显式 lively/standard 也让路 (原句"低电量模式"本就是系统级压降动效的形态)。
            if BatteryCare.appLowBattery { return "calm" }
            let v = DB.store.getString("kf_motion")
            return ["calm", "standard", "lively"].contains(v) ? v : "standard"
        }
        /// 召唤锁核的位移弹簧（跟手后的回位与吸附）。
        /// 放在令牌层而不是写在视图里，只有一个理由：`calm` 档（系统减弱动态 / 低电量）
        static var quick: Animation {
            switch tier {
            case "calm": return .easeOut(duration: 0.10)
            case "lively": return .spring(response: 0.22, dampingFraction: 0.68)
            default: return .spring(response: 0.22, dampingFraction: 0.9)
            }
        }
        static var standard: Animation {
            switch tier {
            case "calm": return .easeInOut(duration: 0.16)
            case "lively": return .spring(response: 0.45, dampingFraction: 0.68)
            default: return .spring(response: 0.4, dampingFraction: 0.85)
            }
        }
        static var soft: Animation {
            switch tier {
            case "calm": return .easeInOut(duration: 0.12)
            case "lively": return .easeInOut(duration: 0.34)
            default: return .easeInOut(duration: 0.25)
            }
        }
        static var exit: Animation {
            switch tier {
            case "calm": return .easeOut(duration: 0.08)
            case "lively": return .easeOut(duration: 0.20)
            default: return .easeOut(duration: 0.15)
            }
        }
    }
    enum Duration {
        static let quick: TimeInterval = 0.15
        static let standard: TimeInterval = 0.25
    }
    enum Appearance {
        /// 品牌主题键 (idea 31): "" = 默认靛蓝
        static var accentKey: String { DB.store.getString("kf_accent") }
        /// AMOLED 纯黑 (idea 30): kf_theme == "black"
        static var isAMOLED: Bool { DB.store.getString("kf_theme") == "black" }
        /// 893 App 内高对比皮肤: 与系统"增加对比度"**并联** (任一为真即加强)，不替代系统开关。
        /// 为什么要 App 内这一个: 系统的对比度开关是全局的，很多人不愿为这一个 App 改整机;
        /// 而"我就是想在看锁的时候字更硬"是 App 内可以满足的。加强项三组 (分隔线/次级文本加深 +
        /// 862 玻璃卡降实底)，不引入新颜色 —— 用的就是原本给系统高对比准备的那对令牌。
        @MainActor static var highContrast: Bool { DB.store.getBool("kf_hc") }
    }
    enum Gradient {
        /// 主控卡 / 开锁盘 idle 态 / 主按钮 — 主题色向深色端的对角渐变 (随 kf_accent 切换)
        static var hero: LinearGradient {
            // 2026-10-26 精简：节日限定色分支已删（festive 整套移除，恒走主题色）。
            return LinearGradient(colors: [Palette.themed("heroA"), Palette.themed("heroB")],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        /// 页面底: 极淡的纵向渐变画布, 替代平涂 (scrollContentBackground 需配 .hidden)
        /// AMOLED 下退化为近纯黑的微渐变, 保住"画布有深度"的层次暗示
        /// 32 Mesh 网格渐变背景 (Headspace 那种柔和网格): 取色与 `screen` **同源** (同一对 canvas 上下色 + 中间过渡色),
        /// 只把两色纵向渐变升级成 3×3 网格, 所以主题/深浅/AMOLED 仍是同一个真相源。
        /// 部署目标 iOS 26.5, MeshGradient 自 18.0 起可用 —— 不写可用性分支。
        /// 三档特殊情形在 dsScreenBackground 里回落线性渐变 (AMOLED 纯黑 / 智能反转幂等色 / 降低透明度实底)。
        static var screenMesh: MeshGradient {
            let top = Appearance.isAMOLED ? Color(hex: 0x050505) : Color.adaptive(0xF7F9FD, 0x0C1120)
            let bottom = Appearance.isAMOLED ? Color(hex: 0x000000) : Color.adaptive(0xE9EDF6, 0x06080E)
            let mid = Color.adaptive(0xF2F5FB, 0x090E1B)
            return MeshGradient(width: 3, height: 3, points: [
                SIMD2<Float>(0.0, 0.0), SIMD2<Float>(0.5, 0.0), SIMD2<Float>(1.0, 0.0),
                SIMD2<Float>(0.0, 0.5), SIMD2<Float>(0.58, 0.44), SIMD2<Float>(1.0, 0.5),
                SIMD2<Float>(0.0, 1.0), SIMD2<Float>(0.5, 1.0), SIMD2<Float>(1.0, 1.0),
            ], colors: [
                top, top, top,
                top, mid, bottom,
                bottom, bottom, bottom,
            ])
        }
        static var screen: LinearGradient {
            let top = Appearance.isAMOLED ? Color(hex: 0x050505) : Color.adaptive(0xF7F9FD, 0x0C1120)
            let bottom = Appearance.isAMOLED ? Color(hex: 0x000000) : Color.adaptive(0xE9EDF6, 0x06080E)
            return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
        }
        /// 主按钮渐变 (PrimaryActionStyle 专用): 浅色 = hero 同值白字; 深色 = accentText→accent
        /// 区间配近黑字。HeroCard/MomentCard/圆盘 idle 仍用 hero 白字渐变, 不受本修复影响。
        static var button: LinearGradient {
            LinearGradient(colors: [Palette.themed("btnA"), Palette.themed("btnB")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
