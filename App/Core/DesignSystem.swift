// ================= 设计系统 =================
// 单一令牌来源: 间距 / 圆角 / 触达 / 图标尺寸 / 动效 / 语义色 / 渐变 + 可复用交互组件。
// 全部界面只允许引用这里的令牌, 不允许在页面里写死颜色与尺寸。
// 明暗双模: Palette 全部走 UIColor 动态色, 跟随系统深浅色自动切换;
// 包16 增量: 品牌主题三选 (kf_accent) / AMOLED 纯黑 (kf_theme=="black") / 布局密度三档 (kf_density),
// 三者均由 AppState.bumpAppearance 驱动 RootView .id 重建, 切换即时全局生效。
// 对比度由 tools/contrast.js 机检 (正文 ≥4.5:1, 分隔线 ≥1.2:1, 含三主题与 AMOLED 全表)。
import SwiftUI
import UIKit

// ---------- 色彩基元 ----------
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

enum DS {
    /// 间距: 统一 4 / 8 节奏。
    /// 布局密度 (包16): kf_density 三档映射为间距缩放系数 — 字号、触达、图标不缩放,
    /// 只动"呼吸感"; 变更由 AppState.bumpAppearance 驱动全局重建, 即时生效。
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
    enum Radius {
        static let card: CGFloat = 22
        static let control: CGFloat = 16
        static let tile: CGFloat = 18
        static let pill: CGFloat = 999
    }
    /// iOS 最小触达 44×44pt
    enum Hit { static let min: CGFloat = 44 }
    /// 圆盘直径三档 (idea 249): kf_dial_size 160/176/200。变更经 AppState.setUnlockOption
    /// → 外观重建通道即时生效, 与密度令牌同一机制。
    enum Metric {
        static var dial: CGFloat {
            let v = DB.store.getInt("kf_dial_size", 176)
            return CGFloat([160, 176, 200].contains(v) ? v : 176)
        }
    }
    /// 触感分级常量 (idea 22): 全 App 触感只允许这三档 —
    ///   tick    = light 档: 围栏解锁/进度刻度/就绪轻震 (269) 等过程触感
    ///   trigger = medium 档: 手势确认触发/断连提醒 (243) 等动作触感
    ///   结果档   = UINotificationFeedbackGenerator 的 success/warning/error, 只用于操作结果
    enum Haptics {
        static let tick = UIImpactFeedbackGenerator(style: .light)
        static let trigger = UIImpactFeedbackGenerator(style: .medium)
    }
    /// 夜间降亮度 (idea 248): 22 点–6 点圆盘光晕与 Hero 卡光源自动降峰值防刺眼。
    /// 只降装饰层透明度, 文字与语义对比度不受影响。
    static var isNightDim: Bool {
        let h = Calendar.current.component(.hour, from: Date())
        return h >= 22 || h < 6
    }
    /// SF Symbols 尺寸令牌 — 全 App 只用这一套, 避免 17/20/28 混用
    enum Icon {
        static let xs: CGFloat = 13
        static let sm: CGFloat = 16
        static let md: CGFloat = 20
        static let lg: CGFloat = 26
        static let xl: CGFloat = 44
    }
    /// 动效令牌 — 不给每个页面各写一个 duration。
    /// 默认接近临界阻尼 (苹果 fluid interfaces 的"日常档"), 只给高频物理感交互留轻微回弹。
    enum Motion {
        static let quick = Animation.spring(response: 0.22, dampingFraction: 0.9)
        static let standard = Animation.spring(response: 0.4, dampingFraction: 0.85)
        static let soft = Animation.easeInOut(duration: 0.25)
        static let exit = Animation.easeOut(duration: 0.15)
    }
    /// 时长令牌 (idea 211): 150/250/400 毫秒三档 — 微交互 / 标准转场 / 强调时刻。
    /// 需要 Animation 对象用 Motion, 只需要时长 (如 Task 前的 withAnimation) 用这里。
    enum Duration {
        static let quick: TimeInterval = 0.15
        static let standard: TimeInterval = 0.25
        static let slow: TimeInterval = 0.40
    }
    /// 外观引擎 (包16): 品牌主题 / AMOLED 的存储键解析点。
    /// 只读 DB.store (UserDefaults), 变更即时性由 AppState.applyAppearance → RootView .id 重建保证。
    enum Appearance {
        /// 品牌主题键 (idea 31): "" = 默认靛蓝
        static var accentKey: String { DB.store.getString("kf_accent") }
        /// AMOLED 纯黑 (idea 30): kf_theme == "black"
        static var isAMOLED: Bool { DB.store.getString("kf_theme") == "black" }
    }

    enum Palette {
        // ---------- 机检基础令牌 (tools/contrast.js 解析 static let) ----------
        static let canvasBase  = Color.adaptive(0xF2F4F9, 0x070B12)   // 页面底 (渐变画布的深端基调)
        static let surfaceBase = Color.adaptive(0xFFFFFF, 0x151D29)   // 卡片
        static let surfaceAltBase = Color.adaptive(0xF5F7FB, 0x1C2534) // 卡片内次级块
        static let hairline   = Color.adaptive(0xD3DCE7, 0x29343F)   // 分隔线 / 描边 (需 ≥1.2:1 才看得见)
        static let text       = Color.adaptive(0x0D1626, 0xF2F6FB)   // 主文本
        static let textSub    = Color.adaptive(0x525E77, 0x9FACBE)   // 次文本 6.5:1 / 7.4:1
        static let ok         = Color.adaptive(0x15803D, 0x4ADE80)   // 成功
        static let warn       = Color.adaptive(0xB45309, 0xFBBF24)   // 警告 4.5:1 / 高
        static let danger     = Color.adaptive(0xB91C1C, 0xF87171)   // 错误 6.0:1

        // ---------- 862 增强对比映射 (包15): 系统 accessibilityHighContrast 开启时加深一档 ----------
        // 语义角色不变, 只是明端向纯黑 / 暗端向纯白再走一步 (hairline 可辨 1.2:1 余量放大);
        // 页面继续引用 hairline/textSub 不感知, 只有这两组"增强"变体不同。
        private static let hairlineHC = Color.adaptive(0x98A6B8, 0x5C7084)
        private static let textSubHC  = Color.adaptive(0x38445A, 0xC2CFE2)
        static var hairlineStrong: Color { AXFlags.highContrast ? hairlineHC : hairline }
        static var textSubStrong: Color { AXFlags.highContrast ? textSubHC : textSub }

        // ---------- 品牌主题表 (idea 31: 靛蓝/墨绿/琥珀) ----------
        // 结构: [主题: [明暗: [角色: hex]]]。tools/contrast.js 机检本表:
        // accentText 对三种底 ≥4.5:1, onAccent 对 accent ≥4.5:1, 纯白对 hero 两端 ≥4.5:1,
        // onAccent 对主按钮渐变 btnA/btnB 两端 ≥4.5:1 (包1)。
        // btnA/btnB = DS.Gradient.button 端点: 浅色与 hero 同值 (白字, 现状达标);
        // 深色改用 accentText→accent 区间 — 旧案直接复用 hero, 近黑 onAccent 压暗端仅 ~2.4:1
        // (包1 必修缺陷), 新案近黑字压浅端 ≥9.8:1、压 accent 端 ≥6.4:1。
        static let themeTable: [String: [String: [String: UInt32]]] = [
            "indigo": [
                "light": ["accent": 0x4F46E5, "accentText": 0x4338CA, "onAccent": 0xFFFFFF, "heroA": 0x5A55EC, "heroB": 0x4338CA, "btnA": 0x5A55EC, "btnB": 0x4338CA],
                "dark": ["accent": 0x818CF8, "accentText": 0xA5B4FC, "onAccent": 0x0A0E15, "heroA": 0x5B5BD6, "heroB": 0x4136C9, "btnA": 0xA5B4FC, "btnB": 0x818CF8]
            ],
            "forest": [
                "light": ["accent": 0x166534, "accentText": 0x14532D, "onAccent": 0xFFFFFF, "heroA": 0x178040, "heroB": 0x0F5A2C, "btnA": 0x178040, "btnB": 0x0F5A2C],
                "dark": ["accent": 0x4ADE80, "accentText": 0x86EFAC, "onAccent": 0x0A0E15, "heroA": 0x188345, "heroB": 0x0F5A2C, "btnA": 0x86EFAC, "btnB": 0x4ADE80]
            ],
            "amber": [
                "light": ["accent": 0x854D0E, "accentText": 0x713F12, "onAccent": 0xFFFFFF, "heroA": 0x9A5B10, "heroB": 0x713F12, "btnA": 0x9A5B10, "btnB": 0x713F12],
                "dark": ["accent": 0xF59E0B, "accentText": 0xFCD34D, "onAccent": 0x0A0E15, "heroA": 0xBA560B, "heroB": 0x713F12, "btnA": 0xFCD34D, "btnB": 0xF59E0B]
            ]
        ]
        /// AMOLED 纯黑覆盖 (idea 30): 表面与画布降为纯黑/近黑。
        /// 机检: text/textSub/ok/warn/danger 与各主题 dark accentText 在这些底上 ≥4.5:1。
        static let amoledOverride: [String: UInt32] = [
            "canvas": 0x000000, "surface": 0x0B0E14, "surfaceAlt": 0x121821
        ]

        /// 当前生效主题 (kf_accent, 空值归一到靛蓝)
        private static func effectiveKey(_ key: String?) -> String {
            let k = key ?? Appearance.accentKey
            return k.isEmpty ? "indigo" : k
        }
        /// 主题表 → 动态色: 明暗 trait 在 provider 内解析 (与 Color.adaptive 同一机制),
        /// kf_accent 变更经全局重建后重新求值。key 缺省 = 当前主题, 显式传 key 供色板小样预览。
        static func themed(_ role: String, key: String? = nil) -> Color {
            Color(UIColor { tc in
                let theme = Palette.themeTable[effectiveKey(key)] ?? Palette.themeTable["indigo"]!
                let mode = theme[tc.userInterfaceStyle == .dark ? "dark" : "light"] ?? theme["light"]!
                return UIColor(Color(hex: mode[role]!))
            })
        }

        // ---------- 活动令牌 (API 与旧版一致, 全 App 调用点零改动) ----------
        /// AMOLED 时表面降为纯黑/近黑, 其余场景与旧版一致
        static var canvas: Color { Appearance.isAMOLED ? Color(hex: amoledOverride["canvas"]!) : canvasBase }
        static var surface: Color { Appearance.isAMOLED ? Color(hex: amoledOverride["surface"]!) : surfaceBase }
        static var surfaceAlt: Color { Appearance.isAMOLED ? Color(hex: amoledOverride["surfaceAlt"]!) : surfaceAltBase }
        // 压在填充色上的文字。深色模式下 accent/ok/warn/danger 都是高亮浅色,
        // 白字压上去不达 4.5:1 — 故深色模式改用近黑墨色 (机检: tools/contrast.js)。
        static var accent    : Color { themed("accent") }      // 主行动填充 / 全局 tint
        static var accentText : Color { themed("accentText") } // 主色文字
        static var onAccent   : Color { themed("onAccent") }   // 压在 accent/hero 上的文字
    }
    /// 渐变: 品牌层的"深度"来源。hero 压纯白文字 (装饰层不做动态色, 两端对比度机检于 themeTable)。
    enum Gradient {
        /// 主控卡 / 开锁盘 idle 态 / 主按钮 — 主题色向深色端的对角渐变 (随 kf_accent 切换)
        static var hero: LinearGradient {
            LinearGradient(colors: [Palette.themed("heroA"), Palette.themed("heroB")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        /// 页面底: 极淡的纵向渐变画布, 替代平涂 (scrollContentBackground 需配 .hidden)
        /// AMOLED 下退化为近纯黑的微渐变, 保住"画布有深度"的层次暗示
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

// ---------- 品牌主题元数据 (设置页色板小样用, idea 31) ----------
extension DS {
    struct AccentTheme: Identifiable {
        let key: String     // kf_accent 存储值
        let name: String
        var id: String { key }
        /// 色板小样: 与同主题 App 图标 / hero 渐变同色
        var preview: LinearGradient {
            LinearGradient(colors: [DS.Palette.themed("heroA", key: key), DS.Palette.themed("heroB", key: key)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
    static let accentThemes: [AccentTheme] = [
        AccentTheme(key: "indigo", name: "靛蓝"),
        AccentTheme(key: "forest", name: "墨绿"),
        AccentTheme(key: "amber", name: "琥珀"),
    ]
}

/// 页面底: 渐变画布, List/Form 需同时 .scrollContentBackground(.hidden)
extension View {
    func dsScreenBackground() -> some View {
        background(DS.Gradient.screen.ignoresSafeArea())
    }
}

// ---------- 入场编排 ----------
/// 包15 声音策略 (857 静音开关尊重): App 内 App 音效一律走系统 systemSound —
/// 系统铃声静音开关开启时自动无声 (iOS 行为, 无需自读路由), 触感反馈不走铃音通道。
/// 全 App 不直接调 AudioServicesPlaySystemSound (App 入口与成就音效两处既有调用点同样遵循)。

// ---------- 无障碍布局辅助 (包15) ----------
extension View {
    /// 873/60 单手下沉: 圆盘整体下移落入拇指区 (开关在 设置-辅助, AXPrefs.onehand)
    func axOnehand(_ on: Bool = AXPrefs.onehand, dy: CGFloat = 48) -> some View {
        on ? offset(y: dy) : self
    }
}

/// 首屏卡片按序浮起 (每次会话只播一次): 纯 transform/opacity, stagger 50ms;
/// reduceMotion 下退化为纯淡入。惊喜预算只花在"罕见时刻"(应用启动), 高频路径不动。
private struct StaggeredAppear: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                guard !shown else { return }
                let delay = Double(index) * 0.05
                if reduceMotion {
                    withAnimation(.easeOut(duration: 0.2).delay(delay)) { shown = true }
                } else {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.9).delay(delay)) { shown = true }
                }
            }
    }
}

extension View {
    /// 入场编排: index 决定出场次序 (0 起, 每档 50ms)
    func staggered(_ index: Int) -> some View {
        modifier(StaggeredAppear(index: index))
    }
}

// ---------- 状态语义色 (供状态胶囊 / 文案统一取用) ----------
enum ToneColor {
    case neutral, accent, ok, warn, danger
    var color: Color {
        switch self {
        case .neutral: return DS.Palette.textSub
        case .accent:  return DS.Palette.accentText
        case .ok:      return DS.Palette.ok
        case .warn:    return DS.Palette.warn
        case .danger:  return DS.Palette.danger
        }
    }
}

// ---------- 基础组件 ----------

/// 状态胶囊: 底色恒为中性 surfaceAlt, 语义由图标形状 + 图标颜色双通道表达
/// (颜色不作为唯一信息载体), 因此文字对比度始终达标。
struct StatusPill: View {
    let text: String
    let systemImage: String
    var tone: ToneColor = .neutral

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: systemImage)
                .font(.system(size: DS.Icon.xs, weight: .semibold))
                .foregroundStyle(tone.color)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(DS.Palette.textSub)
                .lineLimit(1)
        }
        .padding(.horizontal, DS.Space.s + 2)
        .padding(.vertical, DS.Space.xs + 1)
        .background(DS.Palette.surfaceAlt, in: Capsule())
        .overlay(Capsule().strokeBorder(DS.Palette.hairline, lineWidth: 0.5))
        // 不允许被父容器压缩: 状态文案换行会把胶囊撑成两行, 行高随之错位
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// 玻璃胶囊 (hero 渐变上的专属变体): 半透明白底 + 白字。
/// 只在 HeroCard 内部使用 — 语义仍由图标形状 + tint 双通道表达。
struct HeroPill: View {
    let text: String
    let systemImage: String
    var tint: Color = .white

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: systemImage)
                .font(.system(size: DS.Icon.xs, weight: .semibold))
            Text(text)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, DS.Space.s + 2)
        .padding(.vertical, DS.Space.xs + 1)
        .background(tint.opacity(0.18), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.38), lineWidth: 0.5))
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// 指标块: 图标 + 名称 + 数值, 用于电量 / 固件 / 锁钟这类并列读数。
/// `emphasized` 用来拉开数据层级 — 三块读数若同级, 用户看不出哪个才是关键。
struct MetricTile: View {
    let systemImage: String
    let label: String
    let value: String
    var tone: ToneColor = .neutral
    var emphasized: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: DS.Icon.sm, weight: .medium))
                    .foregroundStyle(tone.color)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .lineLimit(1)
            }
            Text(value)
                .font(emphasized ? .subheadline.weight(.semibold) : .subheadline)
                .foregroundStyle(emphasized ? DS.Palette.text : DS.Palette.textSub)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                // 苹方数字是比例宽度: 9%→10% 会让整块宽度跳动, 必须等宽
                .monospacedDigit()
                .fontDesign(.rounded)   // 数字走 SF 圆体: 仪表的精确里带一点温度 (中文自动回退苹方)
                .contentTransition(.numericText())   // 电量变化时数字滚动而不是硬跳
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Space.m)
        .padding(.vertical, DS.Space.s + 2)
        .background(DS.Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }
}

/// hero 渐变上的指标块: 白字 + 半透明玻璃底, 是 MetricTile 的主控卡变体。
/// 数值恒为纯白 (对比度 ≥4.7:1), 标签作辅助视觉 (无障碍由 accessibilityLabel 合并朗读)。
struct HeroStat: View {
    let systemImage: String
    let label: String
    let value: String
    var emphasized: Bool = true
    /// 语义警示 (如低电量) 时染图标; nil 用常规白
    var tint: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            HStack(spacing: DS.Space.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: DS.Icon.sm, weight: .medium))
                    .foregroundStyle(tint ?? Color.white.opacity(0.85))
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
            Text(value)
                .font(emphasized ? .subheadline.weight(.semibold) : .subheadline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .monospacedDigit()
                .fontDesign(.rounded)   // 数字走 SF 圆体: 仪表的精确里带一点温度 (中文自动回退苹方)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Space.m)
        .padding(.vertical, DS.Space.s + 2)
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }
}

/// 主控卡: 页面唯一的品牌渐变面, 用光效和投影把视觉权重压在最重要的信息上。
/// 深浅色共用同一套渐变与白色文字 (两端对比度均 ≥4.5:1)。
struct HeroCard<Content: View>: View {
    var flair: Bool
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false
    /// `flair` (idea 999): 史诗徽章点亮后 7 天的一圈流光边, 素颜模式不显示
    init(flair: Bool = false, @ViewBuilder content: () -> Content) {
        self.flair = flair
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.l + DS.Space.xs)
            .background {
                ZStack(alignment: .topTrailing) {
                    // 863 反转保护: 反转色模式下 hero 渐变降级为幂等中性渐变 (DS.heroGradientSafe)
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .fill(DS.heroGradientSafe)
                    // 右上一团柔光: 给渐变一个"光源", 缓慢漂移 (±8pt / 9s) 让它活过来,
                    // 慢到只剩"页面在呼吸"的潜意识感受; reduceMotion 时静止
                    Circle()
                        .fill(.white.opacity(0.12))
                        .frame(width: 170, height: 170)
                        .blur(radius: 42)
                        .offset(x: drift ? 54 : 46, y: drift ? -51 : -44)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .overlay {
                if flair { HeroFlairBorder() }
            }
            .shadow(color: DS.Palette.accent.opacity(0.30), radius: 18, y: 10)
            .padding(.horizontal, DS.Space.gutter)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { drift = true }
            }
    }
}

/// 999 流光边: 品牌渐变描边缓慢呼吸; reduceMotion 时静态常亮
private struct HeroFlairBorder: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glow = false
    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
            .strokeBorder(LinearGradient(colors: [DS.Palette.themed("heroA"), .white, DS.Palette.themed("heroB")],
                                         startPoint: .topLeading, endPoint: .bottomTrailing),
                          lineWidth: 1.5)
            .opacity(glow ? 0.9 : 0.45)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { glow = true; return }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { glow = true }
            }
    }
}

/// 空状态: 复用系统 ContentUnavailableView, 图标 + 说明 + 主动作三件套齐全,
/// 避免用户停在无路可走的页面上; 也能自动跟随系统深浅色与动态字体。
struct EmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String = ""
    var action: (() -> Void)?

    init(systemImage: String, title: String, message: String) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
    }

    init(systemImage: String, title: String, message: String, actionTitle: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if !actionTitle.isEmpty, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(.vertical, DS.Space.l)
        .padding(.horizontal, DS.Space.l)
    }
}

/// 空态皆引导 (包14: 814 进度点 / 815 双按钮 / 808 示例铺底 / 834 演示链接 / 841 小管家):
/// 空态页显示"第 N/M 步"进度圆点 + 主/次双按钮 + 可选"看 30 秒演示"文字链。
struct GuidedEmptyView: View {
    let systemImage: String
    let title: String
    let message: String
    var step: Int = 0                 // 814 当前引导阶段 (0 = 不显示进度点)
    var stepTotal: Int = 3
    var primaryTitle: String = ""     // 815 主动作
    var primary: (() -> Void)?
    var secondaryTitle: String = ""   // 815 次按钮
    var secondary: (() -> Void)?
    var showDemoLink: Bool = false    // 834 30 秒演示链接
    var demoAction: (() -> Void)?
    var mascot: Bool = false          // 841 小管家顶饰

    init(systemImage: String, title: String, message: String) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
    }

    var body: some View {
        VStack(spacing: DS.Space.m) {
            if mascot {
                EmptyMascotHeader()
            }
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text(message)
            }
            if !primaryTitle.isEmpty, let primary {
                Button(primaryTitle, action: primary)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            if !secondaryTitle.isEmpty, let secondary {
                Button(secondaryTitle, action: secondary)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
            if step > 0 {
                HStack(spacing: DS.Space.xs) {
                    ForEach(0..<stepTotal, id: \.self) { i in
                        Circle()
                            .fill(i < step ? DS.Palette.accent : DS.Palette.hairline)
                            .frame(width: 7, height: 7)
                    }
                    Text("第 \(step)/\(stepTotal) 步")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                }
                .accessibilityLabel("引导阶段 第 \(step) 步, 共 \(stepTotal) 步")
            }
            if showDemoLink, let demoAction {
                Button("看看它如何工作 (30 秒演示)") { demoAction() }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                    .accessibilityHint("打开演示锁, 完整走一遍添加与开锁")
            }
        }
        .padding(.vertical, DS.Space.l)
        .padding(.horizontal, DS.Space.l)
    }
}

/// 主行动按钮样式: 品牌渐变填充 + 光晕投影, 统一圆角 / 最小高度 50pt。
/// 文字压渐变两端均 ≥4.5:1 — 浅色白字压 btnA/btnB (hero 同值),
/// 深色近黑字压 accentText→accent 区间 (包1 修复: 旧深色复用 hero 暗端仅 ~2.4:1)。
/// 机检: tools/contrast.js 断言表 D 节 (3 主题 × 明暗/纯黑 × 渐变两端)。
struct PrimaryActionStyle: ButtonStyle {
    var fullWidth: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(DS.Palette.onAccent)
            .padding(.vertical, DS.Space.m + 2)
            .padding(.horizontal, DS.Space.l)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: DS.Hit.min + 6)
            .background(DS.Gradient.button,
                        in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            .shadow(color: DS.Palette.accent.opacity(0.26), radius: 12, y: 5)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(DS.Motion.quick, value: configuration.isPressed)
    }
}

/// 次级按钮样式 (描边)
struct SecondaryActionStyle: ButtonStyle {
    var fullWidth: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DS.Palette.accentText)
            .padding(.vertical, DS.Space.s + 2)
            .padding(.horizontal, DS.Space.l)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: DS.Hit.min)
            .background(DS.Palette.accentText.opacity(configuration.isPressed ? 0.16 : 0.09),
                                in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(DS.Motion.quick, value: configuration.isPressed)
    }
}

/// 破坏性按钮样式 (红字描边)
struct DestructiveActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DS.Palette.danger)
            .padding(.vertical, DS.Space.s + 2)
            .padding(.horizontal, DS.Space.l)
            .frame(maxWidth: .infinity)
            .frame(minHeight: DS.Hit.min)
            .background(DS.Palette.danger.opacity(configuration.isPressed ? 0.16 : 0.09),
                                in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            .animation(DS.Motion.quick, value: configuration.isPressed)
    }
}

/// 忙碌态按钮: 自动显示菊花并禁用, 杜绝重复触发
struct BusyButton: View {
    let title: String
    var systemImage: String?
    var isBusy: Bool
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s) {
                if isBusy {
                    ProgressView().controlSize(.small)
                } else if let systemImage {
                    Image(systemName: systemImage).font(.system(size: DS.Icon.sm, weight: .semibold))
                }
                Text(isBusy ? "处理中…" : title)
            }
        }
        .buttonStyle(PrimaryActionStyle())
        .disabled(isBusy || disabled)
    }
}
