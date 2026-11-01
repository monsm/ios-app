// V7Tokens.swift —— v7 设计语言令牌（唯一数值来源）。
//
// 来源：D:\aapk\lock27-preview\v7\TOKENS.md 的像素级实测（402×874pt @3x）：
//   · R1-device.html（参考 A 健康寿命环）：主环外径 279.3pt / 描边 36.3pt、缺口 bearing 163–201°、
//     游标 23.3pt @289° r131、顶部刻度 4.3×23.3、内盘 Ø206.7、中心数字 73pt/700 #3F8EF4、
//     下方标签 13.5pt/600 字距 1.5；芯片 178×53.3 r14、正文 17/23。
//   · R2-credentials.html（参考 B 凭证页）：卡片 #232227 r27、内边距 16.3；分段环 Ø92、环宽 20.3、
//     段间 4–5°、暗层 55% 亮度；标题 29pt/700；正文 17/23 #919096。
//   · R3-records.html（参考 C 记录页）：三环外径 133.7、环宽 14、间隙 1.2、12 点起圆头；
//     迷你卡 170.7×178；24 格柱图网格高 57、柱宽 1.8 r0.9；大写数字 30pt/600。
//   · TOKENS.md 浮动标签栏：268×57 r28.5 bottom 19.7、玻璃 rgba(32,32,32,.72) + blur20/sat180、
//     选中黑胶囊 60×49。
//
// 纪律：v7 的组件与页面只引用 V.*，不写样式字面量。
//
// 2026-11-01 死令牌清理：删掉 24 个"定义了但全仓零消费点"的令牌
// （颜色 C.blueCursor；字号 F.title20 / cardBodyStrong / icon22Medium；动效 M.exit；
//   布局 S.screenH / cardGap / statValueGap、Gauge.gapEnd、Segmented.numberSize、
//   Tab.selectedRadius、List.chevronSize / badgeSize、Metric.miniCardW / miniChartW、
//   Page 的 sectionGap / headerGap / bodySpacing / cardHeaderGap / dividerY / statTop / sparklineH）。
// 为什么必须删：令牌文件被 tokens.js / dynamictype.js **整体豁免**（它是字面量的家），
// 于是没有任何闸门检查"令牌是否被使用"；这些令牌看起来完全合理，
// 后来的人会以为它们是设计系统的一部分、不敢删、甚至照着它们挑新值。
// 现在 tokens.js 对 C / F / M 三个枚举逐令牌检查消费点，再堆积会当场判红。
//
// 动态字号：V.F 的每个命名档位都是 VFont（size + weight + relativeTo），
// 由 VScaledFontModifier 的 @ScaledMetric 在渲染时按 Dynamic Type 缩放 —— 默认字号下
// 仍是参考图的像素值，用户调大字号时跟着长大。页面里不允许再出现 V.F.sans(<数字>)。
import SwiftUI
import UIKit

// MARK: - 可缩放字体

/// 一个命名字体档位。size 是默认（Large）字号下的参考值，relativeTo 决定 Dynamic Type 的缩放曲线。
struct VFont {
    var size: CGFloat
    var weight: Font.Weight = .regular
    var design: Font.Design = .default
    var relativeTo: Font.TextStyle = .body
    var digitMonospaced: Bool = false

    func monospaced() -> VFont {
        var copy = self
        copy.design = .monospaced
        return copy
    }

    func monospacedDigit() -> VFont {
        var copy = self
        copy.digitMonospaced = true
        return copy
    }
}

/// 把 VFont 渲染成随 Dynamic Type 缩放的系统字体。
private struct VScaledFontModifier: ViewModifier {
    @ScaledMetric private var scaledSize: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design
    private let digitMonospaced: Bool

    init(_ token: VFont) {
        _scaledSize = ScaledMetric(wrappedValue: token.size, relativeTo: token.relativeTo)
        weight = token.weight
        design = token.design
        digitMonospaced = token.digitMonospaced
    }

    func body(content: Content) -> some View {
        var font = Font.system(size: scaledSize, weight: weight, design: design)
        if digitMonospaced { font = font.monospacedDigit() }
        return content.font(font)
    }
}

extension View {
    /// V.F.xxx 的唯一接线点。与 SwiftUI 的 .font(Font?) 并存，传 VFont 时走缩放实现。
    func font(_ token: VFont) -> some View {
        modifier(VScaledFontModifier(token))
    }
}

enum V {
    // MARK: - 色彩（一律 Color(red:green:blue:)）
    enum C {
        static func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> Color {
            Color(red: r / 255, green: g / 255, blue: b / 255, opacity: a)
        }

        /// 明暗自适应色：浅色/深色两套独立取值（DESIGN-CONTRACT §3），
        /// 跟随 preferredColorScheme / 系统外观即时切换。深色值保持 V7 参考图原值，
        /// 浅色值取自契约的 cold-paper 体系，保证「浅色主题」不是黑页。
        static func dual(_ light: UInt32, _ dark: UInt32,
                         lightAlpha: Double = 1, darkAlpha: Double = 1) -> Color {
            Color(UIColor { trait in
                let isDark = trait.userInterfaceStyle == .dark
                let hex = isDark ? dark : light
                return UIColor(
                    red: CGFloat((hex >> 16) & 0xFF) / 255,
                    green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255,
                    alpha: CGFloat(isDark ? darkAlpha : lightAlpha)
                )
            })
        }

        /// 页面底：浅色冷纸 / 深色纯黑（参考图 V7 是深色画布，浅色用契约纸色）
        static let bg = dual(0xF2F2EF, 0x000000)
        static let card = dual(0xFFFFFF, 0x232227)   // 参考 B 卡底（浅色白卡）
        static let cardAlt = dual(0xE9E9E4, 0x1C1C1E) // 参考 C 卡底（浅色凹槽）
        static let cardWarm = dual(0xFAF7F2, 0x282322) // 参考 B 卡 2
        static let chipTop = dual(0xFFFFFF, 0x262626)  // R1 芯片渐变上
        static let chipBottom = dual(0xE9E9E4, 0x1C1C1C) // R1 芯片渐变下
        static let chipTopB = dual(0xFFFFFF, 0x29292B) // R2 芯片渐变上
        static let chipBottomB = dual(0xE9E9E4, 0x202022) // R2 芯片渐变下

        static let text1 = dual(0x14161A, 0xFFFFFF)   // 主文本
        static let text2 = dual(0x4A5057, 0x919096)   // 正文（#828282 在卡底上只有 4.11:1）
        static let text3 = dual(0x61676E, 0x8E8E93)   // 次文本
        /// 原 #6D6D6D 在 #262626 芯片底上只有 2.92:1（11pt 正文要求 4.5:1）。
        /// 提亮到 #9A9A9F：同一灰阶族，5.40:1 达标。
        static let text4 = dual(0x5B6169, 0x9A9A9F)
        /// 原 #48525B 在 #000 上只有 2.63:1。提亮到 #8E98A3：保留蓝灰倾向，7.17:1 达标。
        static let text5 = dual(0x5B6169, 0x8E98A3)
        static let text6 = dual(0x2C3035, 0xC7C7CC)   // 卡标题
        static let text7 = dual(0x3A3F45, 0xD2D0D0)   // 脚注
        static let text8 = dual(0x4A5057, 0xA2A1A6)   // 卡头
        static let text9 = dual(0x4A5057, 0x919096)   // 参考 B 正文
        /// 图表轴标。原 #4E4E50 在 #000 上只有 2.53:1（8.6pt 正文），换成 #8E8E93（6.44:1）。
        static let axisLabel = dual(0x61676E, 0x8E8E93)

        static let blue = dual(0x1F6FEB, 0x3F8EF4)    // 主环数字 / 折线
        /// 压在高亮填充（蓝/红/自定义强调色）上的文字：浅色用白、深色用近黑墨，
        /// 因为 #3F8EF4 白字只有 3.29:1（13pt 不够 4.5:1），而近黑墨有 5.20:1。
        static let onBlue = dual(0xFFFFFF, 0x06201A)
        // blueCursor（游标色）已于 2026-11-01 删除：全仓零消费点，且与 blue 只差最后一个半字节
        // （#3F8EF3 vs #3F8EF4）—— 那种"几乎一样但没人用"的令牌只会让后来的人以为它有意义。
        static let blueBand = dual(0x9CC3F5, 0x2F6FC0) // 区间带
        static let grid = dual(0xD8D8D0, 0x3A3A3C)    // 柱图网格
        static let chartGrid = dual(0xE0E0D8, 0x2E2E30) // 点线
        static let rule1 = dual(0xDEDED6, 0x262626)   // 横线
        static let rule2 = dual(0xCFCFC7, 0x393939)   // 中线
        static let tick = dual(0xB7C3D6, 0x384064)    // 顶部刻度

        static let disc0 = dual(0xFFFFFF, 0x03101A)    // 内盘亮心
        static let disc1 = dual(0xF2F2EF, 0x020E18)    // 内盘中段
        static let disc2 = dual(0xE9E9E4, 0x01090F)    // 内盘边缘

        static let infoBG = dual(0xE9E9E4, 0x1D1D21)  // i 按钮底
        /// 原 #5D5D62 在 #1D1D21 上只有 2.57:1（非文本要求 3:1）。提亮到 #8E8E93，5.15:1。
        static let infoGlyph = dual(0x61676E, 0x8E8E93)

        /// D-09：高对比档的真实生效点。开启后描边更实、次级文字更亮 ——
        /// 旧实现里这个开关只写 `kf_hc`，全仓零消费者（"死开关"）。
        static var highContrastOn: Bool { DB.store.getBool("kf_hc") }

        static var hairline: Color {   // 卡内分隔线
            highContrastOn ? dual(0x000000, 0xFFFFFF, lightAlpha: 0.26, darkAlpha: 0.34)
                           : dual(0x000000, 0xFFFFFF, lightAlpha: 0.10, darkAlpha: 0.14)
        }
        static var hairlineSoft: Color {   // 芯片内描边
            highContrastOn ? dual(0x000000, 0xFFFFFF, lightAlpha: 0.22, darkAlpha: 0.26)
                           : dual(0x000000, 0xFFFFFF, lightAlpha: 0.07, darkAlpha: 0.08)
        }
        /// D-09：减少透明档的真实生效点（标签栏玻璃退化为不透明面板）。
        static var tabGlass: Color {
            let solid = DB.store.getBool("kf_reduce_trans")
            return solid ? dual(0xFFFFFF, 0x1A1A1C, lightAlpha: 0.99, darkAlpha: 0.99)
                         : dual(0xFFFFFF, 0x202020, lightAlpha: 0.72, darkAlpha: 0.72)
        }
        static let tabEdge = dual(0x4A5057, 0x7896A0, lightAlpha: 0.28, darkAlpha: 0.35)

        static let pink = dual(0xC81E4A, 0xFF6A7A)   // 参考 C 三环粉（深色提亮到 4.5:1）
        static let green = rgb(193, 248, 100)    // #C1F864 参考 C 三环绿
        static let cyan = rgb(99, 237, 231)      // #63EDE7 参考 C 三环青
        static let purple = rgb(155, 143, 217)   // #9B8FD9 参考 C 微卡紫
        static let miniBlue = rgb(92, 169, 232)  // #5CA9E8 参考 C 微卡蓝
        static let lime = rgb(194, 246, 106)     // #C2F66A 参考 C 事件绿
        static let red = dual(0xC81E3C, 0xFF375F)    // #FF375F（浅色压深）
        /// 参考 C 红环渐变两端：(103,0,0) → (255,53,135)。
        static let redDeep = rgb(103, 0, 0)
        static let redBright = rgb(255, 53, 135)
        static let rewardGreen = dual(0x1D6F5F, 0x30D158) // 正常/成功
        static let rewardBlue = dual(0x1F6FEB, 0x0A84FF)

        // 语义色（V7 调色板内承接旧 State.*；不是装饰色）
        static let warning = dual(0x8A5A0B, 0xE2A63A) // 注意
        static let critical = dual(0xA32B22, 0xFF6A5C) // 危险
        static let ok = dual(0x1D6F5F, 0x30D158)

        // 参考 B 分段环三段（R2-credentials.html SEG）
        static let mint = rgb(100, 216, 197)     // #64D8C5
        static let coral = rgb(238, 114, 88)     // #EE7258
        static let indigo = rgb(74, 100, 247)    // #4A64F7

        // 参考 C 活动环暗轨（TOKENS 第 45 行：红 #33080F / 绿 #2E4A12 / 青 #16283A）
        static let ringTrackRed = dual(0xF7DDE2, 0x33080F)
        static let ringTrackGreen = dual(0xE5EFD3, 0x2E4A12)
        static let ringTrackCyan = dual(0xD8E8F2, 0x16283A)

        /// 同色「55% 亮度」：把颜色的 RGB 直接乘 0.55，而不是把半透明色叠在卡片上。
        /// UIColor(color) 取到的分量是显示无关的 sRGB 分量，乘亮度不会引入卡片底色。
        static func dimmed(_ color: Color, by factor: CGFloat = 0.55) -> Color {
            let ui = UIColor(color)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            ui.getRed(&r, green: &g, blue: &b, alpha: &a)
            return Color(red: r * factor, green: g * factor, blue: b * factor, opacity: a)
        }
    }

    // MARK: - 字体（TOKENS.md 字体表；默认字号 = 参考图像素值，随 Dynamic Type 缩放）
    enum F {
        /// 令牌层内部的唯一造字入口。页面与组件不得直接调用（Gates/tokens.js 会判违规）。
        static func sans(_ size: CGFloat, weight: Font.Weight = .regular,
                         design: Font.Design = .default,
                         relativeTo style: Font.TextStyle = .body) -> VFont {
            VFont(size: size, weight: weight, design: design, relativeTo: style)
        }

        static let displayA = sans(30, weight: .bold, relativeTo: .largeTitle)      // 参考 A 大标题 30/700
        static let displayB = sans(29, weight: .bold, relativeTo: .largeTitle)      // 参考 B 大标题 29/700
        static let displayHome = sans(34, weight: .bold, relativeTo: .largeTitle)   // 设置/根页大标题 34/700
        static let displayC = sans(19, weight: .bold, relativeTo: .title2)          // 二级页 19/700
        static let displayD = sans(26, weight: .regular, relativeTo: .title)        // 门锁档案 26
        static let displayE = sans(28, weight: .regular, relativeTo: .title)        // 电池档案 28
        static let displayESemibold = sans(28, weight: .semibold, relativeTo: .title)
        static let display24 = sans(24, weight: .regular, relativeTo: .title2)      // 冷启动闸门 24
        static let display22 = sans(22, weight: .regular, relativeTo: .title2)
        static let display26 = sans(26, weight: .regular, relativeTo: .title)
        static let titleC = sans(22, weight: .semibold, relativeTo: .title2)        // 参考 C 头部标题 22/600
        // title20 (20/700) removed 2026-11-01: zero consumers across the whole repo.
        static let body = sans(17)                         // 正文 17
        static let bodyStrong = sans(17, weight: .semibold)
        static let bodyMedium = sans(17, weight: .medium)
        static let bodyLarge = sans(18)
        static let bodyLargeMedium = sans(18, weight: .medium)
        static let bodySmall = sans(14.5)
        static let cardTitle = sans(15, weight: .semibold) // 卡标题 15/600
        static let cardBig = sans(17, weight: .semibold)   // 卡主值 17/600
        static let cardBody = sans(15)
        static let chipLabel = sans(11)                    // 芯片标签 11
        static let chipLabelStrong = sans(11, weight: .semibold)
        static let chipValue = sans(13.5, weight: .semibold) // 芯片值 13.5/600
        static let statLabel = sans(12.5)                  // VStatPair 标签 12.5 #828282
        static let statValue = sans(17, weight: .semibold) // VStatPair 值 17/600
        static let small = sans(11, weight: .medium, relativeTo: .caption)       // 分组小标题 11/500（iOS 最小 11pt）
        static let micro = sans(11, relativeTo: .caption2)                        // 微标签 11
        static let microMedium = sans(11, weight: .medium, relativeTo: .caption2)
        static let microSmall = sans(11, relativeTo: .caption2)
        static let footnote = sans(13, relativeTo: .footnote)                     // 脚注（16.5px 的可用档）
        static let unit = sans(11, relativeTo: .caption)
        static let section = sans(20, weight: .bold, relativeTo: .title3)         // 区块标题 20/700
        static let sectionTitle18 = sans(18, weight: .bold, relativeTo: .title3)
        static let gaugeNumber = sans(73, weight: .bold, design: .rounded, relativeTo: .largeTitle) // 主环中心数字 73/700 · 圆体（默认档）
        static let gaugeNumberPlain = sans(73, weight: .bold, relativeTo: .largeTitle) // 主环数字 · 系统默认体（外观可切）
        static let gaugeLabel = sans(13.5, weight: .semibold, relativeTo: .footnote) // 主环标签 13.5/600
        static let ringCenter = sans(21.3, weight: .bold, relativeTo: .title2)    // 分段环中心 21.3
        static let miniTitle = sans(14, weight: .bold, relativeTo: .subheadline)  // 微卡标题 14/700
        static let miniBig = sans(30, weight: .semibold, relativeTo: .title)      // 微卡大数字 30/600
        static let legendLabel = sans(14, relativeTo: .subheadline)               // 图例标签 14
        static let legendLabelStrong = sans(14, weight: .semibold, relativeTo: .subheadline)
        static let legendValue = sans(27, weight: .bold, relativeTo: .title)      // 图例数值 27/700
        static let number11 = sans(11, weight: .medium, relativeTo: .caption)     // 读数 11
        static let number13 = sans(13, weight: .medium, relativeTo: .footnote)    // 读数 13
        static let number15 = sans(15, weight: .medium, relativeTo: .subheadline) // 读数 15
        static let number17 = sans(17, weight: .medium, relativeTo: .body)        // 读数 17
        static let number18 = sans(18, weight: .medium, relativeTo: .body)        // 读数 18
        static let number20 = sans(20, weight: .medium, relativeTo: .title3)      // 读数 20
        static let number22 = sans(22, weight: .bold, relativeTo: .title2)        // 数字大值 22/700
        static let number26 = sans(26, weight: .medium, relativeTo: .title)       // 读数 26
        static let number30 = sans(30, weight: .medium, relativeTo: .title)       // 读数 30
        static let tab = sans(11, weight: .semibold, relativeTo: .caption2)       // Tab 标签 11/600
        static let chevron = sans(13, weight: .semibold, relativeTo: .footnote)
        static let pageLead = sans(17, relativeTo: .body)                         // 参考 B/C 页导语 17
        static let cardHeader = sans(11, weight: .medium, relativeTo: .caption)   // 参考 B 卡头 11/500
        static let bedValue = sans(11.5, weight: .semibold, relativeTo: .caption) // 卡内小值 11.5/600
        static let bedLabel = sans(11.5, relativeTo: .caption)
        static let rowTitle = sans(16, relativeTo: .body)
        static let rowDetail = sans(13, relativeTo: .footnote)
        static let rowDetailStrong = sans(13, weight: .semibold, relativeTo: .footnote)
        // cardBodyStrong (16/600) removed 2026-11-01: zero consumers.
        static let actionIcon = sans(16, weight: .semibold, relativeTo: .body)
        static let rowIcon = sans(15, weight: .medium, relativeTo: .body)
        static let chartTick = sans(11, relativeTo: .caption2)
        static let axisTick = sans(11, relativeTo: .caption)
        static let stamp = sans(12, weight: .medium, design: .monospaced, relativeTo: .footnote)
        static let heroGlyph56 = sans(56, relativeTo: .largeTitle)
        static let icon15 = sans(15, relativeTo: .body)
        static let icon15Medium = sans(15, weight: .medium, relativeTo: .body)
        static let icon15Semibold = sans(15, weight: .semibold, relativeTo: .body)
        static let icon18 = sans(18, relativeTo: .body)
        static let icon18Medium = sans(18, weight: .medium, relativeTo: .body)
        static let icon22 = sans(22, relativeTo: .title2)
        static let icon22Light = sans(22, weight: .light, relativeTo: .title2)
        // icon22Medium (22/500) removed 2026-11-01: zero consumers.
        static let icon28Semibold = sans(28, weight: .semibold, relativeTo: .title)
        static let otpBig = sans(44, weight: .semibold, relativeTo: .largeTitle)
        static let otpRegular = sans(34, weight: .semibold, relativeTo: .largeTitle)
        static let axTitleBig = sans(28, weight: .semibold, relativeTo: .title)
        static let axTitle = sans(20, weight: .semibold, relativeTo: .title3)
    }

    // MARK: - 间距 / 画布（TOKENS.md 布局栅格）
    enum S {
        static let screenW: CGFloat = 402
        static let hair: CGFloat = 0.5

        static let chipLeftA: CGFloat = 19.3
        static let chipLeftB: CGFloat = 14.67
        static let chipW: CGFloat = 178
        static let chipH: CGFloat = 53.3
        static let chipGap: CGFloat = 7.7
        static let chipPadH: CGFloat = 11
        static let chipIconBox: CGFloat = 25
        static let chipIconGap: CGFloat = 9

        static let pageGutterA: CGFloat = 37.3
        static let pageGutterB: CGFloat = 29.67
        static let pageGutterC: CGFloat = 21
        static let pageGutter: CGFloat = 16
        static let cardGutter: CGFloat = 14.67
        static let cardPad: CGFloat = 16.3
        static let miniPad: CGFloat = 14.7

        /// 布局密度系数（D-09 残余修复）。
        ///
        /// 2026-11-01：`LayoutDensity`（紧凑/标准/宽松）原本**是个死开关** ——
        /// 存了、进了备份、界面上也给了三档，但全仓**没有任何地方读它**，
        /// 改档位界面上一点变化都没有。HIG `settings` 明确要求
        /// "Avoid using settings to ask for setup information you can get in other ways"，
        /// 更基本的是：**给了开关就必须有效果**，否则比不给更糟（用户会以为 App 坏了）。
        ///
        /// 这里只缩放**间距节奏**（不是字号、不是命中区）—— 与枚举注释的口径一致：
        /// "只缩放间距节奏，字号与 44pt 触达不动"。紧凑 -12%，宽松 +12%，标准 1.0。
        /// 必须用 **nonisolated** 的 `SettingsStore.densityFromStore` 而不是 `SettingsStore.shared.density`：
        /// 这些间距令牌在 `body`、`init`、非隔离 `static let` 里都会被求值，那些位置拿不到 MainActor，
        /// 直接读 @MainActor 属性会报 "main actor-isolated property can not be referenced from a
        /// nonisolated context"（CI 实测 4 条错）。
        /// 重绘由设置页自身的 binding 驱动（它读 `store.density`，是 @Observable 依赖）。
        static var densityScale: CGFloat {
            switch SettingsStore.densityFromStore {
            case .compact: return 0.88
            case .relaxed: return 1.12
            case .standard: return 1.0
            }
        }

        /// 间距统一过密度系数。**命中区（V.Hit.min）与字号绝不经过这里** ——
        /// 压小按钮不是"紧凑"，是点不准（44pt 是 HIG 下限，不是可调参数）。
        ///
        /// **不要 `.rounded()`**。设计令牌是刻意的**亚像素**值（7.7 / 14.3 / 16.3 / 14.67），
        /// 取整会在**默认档（标准，系数 1.0）**就把设计参考值改掉：
        ///   7.7 → 8、14.3 → 14、16.3 → 16、14.67 → 15。
        /// 也就是说"什么都没选"的状态不再是设计稿，而这是最常被看到的状态。
        /// 另外取整还会把最小的两档压平：gapXXS(2) 与 gapXS(4) 在三档下都取整成同一个值，
        /// 用户改档位时**最小的间距纹丝不动** —— 观感上像"只改了一半"。
        /// SwiftUI 的布局是浮点运算，亚像素值本来就合法（与设计稿逐值一致）。
        private static func d(_ base: CGFloat) -> CGFloat { base * densityScale }

        static var gapXXS: CGFloat { d(2) }
        static var gapXS: CGFloat { d(4) }
        static var gapS: CGFloat { d(7.7) }
        static var gapMS: CGFloat { d(12) }
        static var gapM: CGFloat { d(14.3) }
        static var gap16: CGFloat { d(16) }
        static var gapL: CGFloat { d(20) }
        static var gapXL: CGFloat { d(22) }
        static var gap24: CGFloat { d(24) }
        static var gapXXL: CGFloat { d(32) }
        static let statGap: CGFloat = 16
        static let statLabelGap: CGFloat = 2
    }

    // MARK: - 圆角
    enum R {
        /// 外观「圆角」档："" 标准 / soft 偏硬朗 / plump 偏柔和。
        /// 卡片、控件、面板三档一起缩放；胶囊（999）不参与。
        private static var factor: CGFloat {
            switch DB.store.getString("kf_radius") {
            case "soft": return 0.72
            case "plump": return 1.24
            default: return 1
            }
        }
        static let chip: CGFloat = 14
        static var card: CGFloat { 27 * factor }
        static var mini: CGFloat { 16 * factor }
        static var action: CGFloat { 14 * factor }
        static var panel: CGFloat { 20 * factor }
        static var inset: CGFloat { 16 * factor }
        static var control: CGFloat { 12 * factor }
        static let pill: CGFloat = 999
    }

    // MARK: - 触达
    enum Hit {
        static let min: CGFloat = 44
    }

    // MARK: - 控件高度
    enum H {
        static let chip: CGFloat = 32
        static let action: CGFloat = 50
        static let row: CGFloat = 56
    }

    // MARK: - 描边 / 图标尺寸
    enum Stroke {
        static let hair: CGFloat = 0.5
        static let focus: CGFloat = 1.5
    }

    enum Icon {
        static let s: CGFloat = 15
        static let m: CGFloat = 18
        static let l: CGFloat = 22
        static let xl: CGFloat = 28
    }

    // MARK: - 动效（沿用旧设计系统的精密人格；页面必须带 reduceMotion 守卫）
    enum M {
        static let snap = Animation.spring(response: 0.22, dampingFraction: 0.92)
        static let move = Animation.spring(response: 0.32, dampingFraction: 0.88)
        static let settle = Animation.spring(response: 0.42, dampingFraction: 0.95)
        static let sweep = Animation.timingCurve(0.32, 0, 0.16, 1, duration: 0.6)
        // exit (easeOut 0.18) removed 2026-11-01: zero consumers. An unused animation is
        // worse than an unused colour - it implies a designed exit transition that never shipped.
    }

    // MARK: - 主环（参考 A / R1-device.html 实测）
    enum Gauge {
        static let outer: CGFloat = 279.3
        static let stroke: CGFloat = 36.3
        /// 中心线半径 = (279.3 - 36.3) / 2 = 121.5（R1 SVG 实测）。
        static let radius: CGFloat = 121.5
        /// 缺口：bearing 163°–201°（宽 38°）。
        static let gapStart: Double = 201
        /// R1 JS 实测 A0=208.4 / A1=516.6 → 中心线扫过 308.2°；两端圆头各吃 8.58°，
        /// 可见缺口 = 360 - 308.2 - 17.16 ≈ 34.6°（与像素实测 34.4° 一致）。
        static let sweepDegrees: Double = 308.2
        static let cursorDiameter: CGFloat = 23.3
        static let cursorBearing: Double = 289
        static let cursorRadius: CGFloat = 131
        static let tickW: CGFloat = 4.3
        static let tickH: CGFloat = 23.3
        static let tickTop: CGFloat = 6.7
        static let discDiameter: CGFloat = 206.7
        static let infoSize: CGFloat = 20.7
        static let infoX: CGFloat = 340.7
        static let infoY: CGFloat = 157.7
        /// 环心在 402×874 画布上的 y（x 恒为屏宽一半 = 201）。
        static let centerY: CGFloat = 276
        static let labelTracking: CGFloat = 1.5
        static let numberTracking: CGFloat = -3.4
        static let glowOpacity: Double = 0.55
        static let baseOpacity: Double = 0.72

        /// TOKENS.md：角向连续渐变 bearing 0→360°。
        static var gradient: [Gradient.Stop] {
            [
            .init(color: C.dual(0xB9BCC4, 0x191D2E), location: 0.0 / 360.0),
            .init(color: C.dual(0xB7BAC1, 0x151A25), location: 45.0 / 360.0),
            .init(color: C.dual(0xB7BABE, 0x191D24), location: 90.0 / 360.0),
            .init(color: C.dual(0xBCBFC2, 0x20282F), location: 135.0 / 360.0),
            .init(color: C.dual(0xC3C6C8, 0x283F45), location: 202.0 / 360.0),
            .init(color: C.dual(0xD6DEE2, 0x2D4E61), location: 230.0 / 360.0),
            .init(color: C.dual(0xC3D1DE, 0x37658F), location: 270.0 / 360.0),
            .init(color: C.dual(0xA6C4E7, 0x3A79C7), location: 282.0 / 360.0),
            .init(color: C.dual(0xC0CCD9, 0x2E4867), location: 300.0 / 360.0),
            .init(color: C.dual(0xBABEC5, 0x1F283B), location: 340.0 / 360.0),
            .init(color: C.dual(0xB9BCC4, 0x191D2E), location: 360.0 / 360.0),
            ]
        }
    }

    // MARK: - 分段环（参考 B / R2-credentials.html 实测）
    enum Segmented {
        static let diameter: CGFloat = 92
        static let width: CGFloat = 20.3
        static let coreWidth: CGFloat = 14
        static let gapDegrees: Double = 4.5
        static let startBearing: Double = 258
        /// 中心线半径 = (92 - 20.3) / 2 = 35.85。
        static let radius: CGFloat = 35.85
        /// 暗层 = 同色 55% 亮度（不是把 55% 不透明度叠在卡面上）。
        static let dimBrightness: CGFloat = 0.55
    }

    // MARK: - 同心活动环（参考 C 实测：外径 133.7 / 环宽 14 / 间隙 1.2）
    enum Ring {
        static let width: CGFloat = 14
        static let gap: CGFloat = 1.2
        static let trackOpacity: Double = 0.22
        static let referenceOuter: CGFloat = 133.7
        /// 小尺寸下环宽按比例收，避免三条环挤成实心点。size:88 → 7.92pt。
        static func lineWidth(for size: CGFloat) -> CGFloat {
            min(width, size * 0.09)
        }

        /// 参考 C 的每条环暗轨色；未知颜色回退为同色 22% 叠层。
        static func track(for color: Color) -> Color {
            if color == C.pink || color == C.red { return C.ringTrackRed }
            if color == C.green || color == C.rewardGreen { return C.ringTrackGreen }
            if color == C.cyan || color == C.rewardBlue { return C.ringTrackCyan }
            return color.opacity(trackOpacity)
        }
    }

    // MARK: - 迷你柱图（参考 C）
    enum Mini {
        static let gridCount: Int = 24
        static let gridH: CGFloat = 57
        static let gridW: CGFloat = 1
        static let barW: CGFloat = 1.8
        static let barRadius: CGFloat = 0.9
        static let glowRadius: CGFloat = 5
        static let minBarH: CGFloat = 3
        static let axisLabelGap: CGFloat = 4
    }

    // MARK: - 面积图（参考 A）
    enum Chart {
        /// TOKENS：绘图区 y720–831 = 111pt。
        static let height: CGFloat = 111
        static let verticals: Int = 6
        /// 实测 6 条点线间距 43.0pt，首条距绘图区左沿 14.4pt。
        static let verticalSpacing: CGFloat = 43
        static let firstInset: CGFloat = 14.4
        static let lineWidth: CGFloat = 1.6
        static let dot: CGFloat = 2.4
        static let xStart: CGFloat = 0.22
        static let xEnd: CGFloat = 0.82
        static let topGap: CGFloat = 8
        static let usable: CGFloat = 0.54
        static let ruleMidY: CGFloat = 36
        /// TOKENS：1px 亮 / 2.6px 暗。
        static let dash: [CGFloat] = [1, 2.6]
        static let plotWidth: CGFloat = 282.4
        static let axisLabelGap: CGFloat = 4
    }

    // MARK: - 列表行（设置 / 快捷入口）
    enum List {
        static let iconSize: CGFloat = 30
        static let rowMinHeight: CGFloat = 54

        /// 凭证行「舒适」档额外高度（外观 → 凭证行高）。
        static let rowTallExtra: CGFloat = 16
        static let toggleMinHeight: CGFloat = 50
        static let dotSize: CGFloat = 8
        static let stateDotSize: CGFloat = 7
        static let ringDotSize: CGFloat = 12.5
    }

    // MARK: - 页面度量（参考 C 记录页 / 参考 R4 设置页）
    enum Metric {
        static let avatar: CGFloat = 34
        static let miniCardH: CGFloat = 178
        static let eventIcon: CGFloat = 36
        static let medal: CGFloat = 76
        static let searchRow: CGFloat = 44
    }

    // MARK: - 动作按钮（v7 没有参考按钮；沿用 14pt 圆角的卡片语言）
    enum Action {
        static let height: CGFloat = 50
        static let radius: CGFloat = 14
    }

    // MARK: - 页面局部节奏（四个根页共用）
    enum Page {
        static let topSpace: CGFloat = 8
        static let chipToTitle: CGFloat = 26
        static let titleToBody: CGFloat = 6
        /// 正文行高 23pt（17pt 字体系统行高约 20.3pt，差值为 lineSpacing）。
        static let bodyLine: CGFloat = 23
        static let bodyLineGap: CGFloat = bodyLine - 20.3
        static var bodyLineSpacing: CGFloat { bodyLineGap }
        static let chartTop: CGFloat = 10
    }
}
