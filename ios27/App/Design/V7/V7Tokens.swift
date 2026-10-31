// V7Tokens.swift —— v7 设计语言令牌（唯一数值来源）。
//
// 来源：D:\aapk\lock27-preview\v7\TOKENS.md 的像素级实测（402×874pt @3x）：
//   · R1-device.html（参考 A 健康寿命环）：主环外径 279.3pt / 描边 36.3pt、缺口 bearing 163–201°、
//     游标 23.3pt @289° r131、顶部刻度 4.3×23.3、内盘 Ø206.7、中心数字 73pt/700 #3F8EF4、
//     下方标签 13.5pt/600 字距 1.5 #48525B；芯片 178×53.3 r14、正文 17/23 #828282。
//   · R2-credentials.html（参考 B 凭证页）：卡片 #232227 r27、内边距 16.3；分段环 Ø92、环宽 20.3、
//     段间 4–5°、暗层 55% 亮度；标题 29pt/700；正文 17/23 #919096。
//   · R3-records.html（参考 C 记录页）：三环外径 133.7、环宽 14、间隙 1.2、12 点起圆头；
//     迷你卡 170.7×178；24 格柱图网格高 57、柱宽 1.8 r0.9；大写数字 30pt/600。
//   · TOKENS.md 浮动标签栏：268×57 r28.5 bottom 19.7、玻璃 rgba(32,32,32,.72) + blur20/sat180、
//     选中黑胶囊 56×49（R1 实测；R2/R3 变体为 60×49，本工程统一取 R1 首页规格）。
//
// 纪律：v7 的组件与页面只引用 V.*，不写样式字面量。
import SwiftUI

enum V {
    // MARK: - 色彩（一律 Color(red:green:blue:)）
    enum C {
        static func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> Color {
            Color(red: r / 255, green: g / 255, blue: b / 255, opacity: a)
        }

        static let bg = rgb(0, 0, 0)             // #000000 画布
        static let card = rgb(35, 34, 39)        // #232227 参考 B 卡底
        static let cardAlt = rgb(28, 28, 30)     // #1C1C1E 参考 C 卡底
        static let cardWarm = rgb(40, 35, 34)    // #282322 参考 B 卡 2
        static let chipTop = rgb(38, 38, 38)     // #262626 R1 芯片渐变上
        static let chipBottom = rgb(28, 28, 28)  // #1C1C1C R1 芯片渐变下
        static let chipTopB = rgb(41, 41, 43)    // #29292B R2 芯片渐变上
        static let chipBottomB = rgb(32, 32, 34) // #202022 R2 芯片渐变下

        static let text1 = rgb(255, 255, 255)
        static let text2 = rgb(130, 130, 130)    // #828282 正文
        static let text3 = rgb(142, 142, 147)    // #8E8E93 次文本
        static let text4 = rgb(109, 109, 109)    // #6D6D6D 芯片标签
        static let text5 = rgb(72, 82, 91)       // #48525B YEARS 类小标签
        static let text6 = rgb(199, 199, 204)    // #C7C7CC 卡标题
        static let text7 = rgb(210, 208, 208)    // #D2D0D0 脚注
        static let text8 = rgb(162, 161, 166)    // #A2A1A6 卡头
        static let text9 = rgb(145, 144, 150)    // #919096 参考 B 正文

        static let blue = rgb(63, 142, 244)      // #3F8EF4 主环数字 / 折线
        static let blueCursor = rgb(63, 142, 243)// #3F8EF3 游标
        static let blueBand = rgb(47, 111, 192)  // #2F6FC0 区间带
        static let grid = rgb(58, 58, 60)        // #3A3A3C 柱图网格
        static let chartGrid = rgb(46, 46, 48)   // #2E2E30 点线
        static let rule1 = rgb(38, 38, 38)       // #262626 横线
        static let rule2 = rgb(57, 57, 57)       // #393939 中线
        static let tick = rgb(56, 64, 100)       // #384064 顶部刻度

        static let disc0 = rgb(3, 16, 26)        // #03101A 内盘亮心
        static let disc1 = rgb(2, 14, 24)        // #020E18 内盘中段
        static let disc2 = rgb(1, 9, 15)         // #01090F 内盘边缘

        static let infoBG = rgb(29, 29, 33)      // #1D1D21 i 按钮底
        static let infoGlyph = rgb(93, 93, 98)   // #5D5D62 i 字形

        static let hairline = rgb(255, 255, 255, 0.14) // 卡内分隔线
        static let hairlineSoft = rgb(255, 255, 255, 0.08) // 芯片内描边
        static let tabGlass = rgb(32, 32, 32, 0.72)
        static let tabEdge = rgb(120, 150, 160, 0.35)
        static let tabPill = rgb(0, 0, 0, 0.82)
        static let tabPillEdge = rgb(255, 255, 255, 0.14)

        static let pink = rgb(240, 55, 95)       // #F0375F 参考 C 三环粉
        static let green = rgb(193, 248, 100)    // #C1F864 参考 C 三环绿
        static let cyan = rgb(99, 237, 231)      // #63EDE7 参考 C 三环青
        static let purple = rgb(155, 143, 217)   // #9B8FD9 参考 C 微卡紫
        static let miniBlue = rgb(92, 169, 232)  // #5CA9E8 参考 C 微卡蓝
        static let lime = rgb(194, 246, 106)     // #C2F66A 参考 C 事件绿
        static let red = rgb(255, 55, 95)        // #FF375F
        static let rewardGreen = rgb(48, 209, 88) // #30D158
        static let rewardBlue = rgb(10, 132, 255) // #0A84FF

        // 参考 B 分段环三段（R2-credentials.html SEG）
        static let mint = rgb(100, 216, 197)     // #64D8C5
        static let coral = rgb(238, 114, 88)     // #EE7258
        static let indigo = rgb(74, 100, 247)    // #4A64F7
    }

    // MARK: - 字体（TOKENS.md 字体表；全部固定 pt，v7 是像素复刻版）
    enum F {
        static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            Font.system(size: size, weight: weight)
        }

        static let displayA = sans(30, weight: .bold)      // 参考 A 大标题 30/700
        static let displayB = sans(29, weight: .bold)      // 参考 B 大标题 29/700
        static let titleC = sans(22, weight: .semibold)    // 参考 C 头部标题 22/600
        static let body = sans(17)                         // 正文 17
        static let bodyStrong = sans(17, weight: .semibold)
        static let cardTitle = sans(15, weight: .semibold) // 卡标题 15/600
        static let cardBig = sans(17, weight: .semibold)   // 卡主值 17/600
        static let chipLabel = sans(11)                    // 芯片标签 11 #6D6D6D
        static let chipValue = sans(13.5, weight: .semibold) // 芯片值 13.5/600
        static let statLabel = sans(12.5)                  // VStatPair 标签 12.5 #828282
        static let statValue = sans(17, weight: .semibold) // VStatPair 值 17/600
        static let small = sans(10.7, weight: .medium)     // 分组小标题 10.7/500
        static let micro = sans(10)                        // 微标签 10
        static let footnote = sans(12)                     // 脚注 12
        static let section = sans(20, weight: .bold)       // 区块标题 20/700
        static let gaugeNumber = sans(73, weight: .bold)   // 主环中心数字 73/700
        static let gaugeLabel = sans(13.5, weight: .semibold) // 主环标签 13.5/600
        static let ringCenter = sans(21.3, weight: .bold)  // 分段环中心 21.3
        static let miniTitle = sans(14, weight: .bold)     // 微卡标题 14/700
        static let miniBig = sans(30, weight: .semibold)   // 微卡大数字 30/600
        static let legendLabel = sans(14)                  // 图例标签 14
        static let legendValue = sans(27, weight: .bold)   // 图例数值 27/700
        static let tab = sans(9, weight: .semibold)        // Tab 标签 9/600
        static let tabIcon = sans(20)                      // Tab 图标 20
        static let chevron = sans(13, weight: .semibold)
        static let pageLead = sans(17)                     // 参考 B/C 页导语 17
        static let cardHeader = sans(11, weight: .medium)  // 参考 B 卡头 11/500
        static let bedValue = sans(11.5, weight: .semibold)
        static let rowTitle = sans(16)
        static let rowDetail = sans(13)
    }

    // MARK: - 间距 / 画布（TOKENS.md 布局栅格）
    enum S {
        static let screenW: CGFloat = 402
        static let screenH: CGFloat = 874
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
        static let cardGutter: CGFloat = 14.67
        static let cardGap: CGFloat = 14.3
        static let cardPad: CGFloat = 16.3
        static let miniPad: CGFloat = 14.7

        static let gapXXS: CGFloat = 2
        static let gapXS: CGFloat = 4
        static let gapS: CGFloat = 7.7
        static let gapM: CGFloat = 14.3
        static let gapL: CGFloat = 20
        static let gapXL: CGFloat = 22
        static let statGap: CGFloat = 16
        static let statLabelGap: CGFloat = 2
        static let statValueGap: CGFloat = 1
    }

    // MARK: - 圆角
    enum R {
        static let chip: CGFloat = 14
        static let card: CGFloat = 27
        static let mini: CGFloat = 16
        static let tab: CGFloat = 28.5
        static let tabSelected: CGFloat = 24.5
        static let action: CGFloat = 14
    }

    // MARK: - 主环（参考 A / R1-device.html 实测）
    enum Gauge {
        static let outer: CGFloat = 279.3
        static let stroke: CGFloat = 36.3
        /// 中心线半径 = (279.3 - 36.3) / 2 = 121.5（R1 SVG 实测）。
        static let radius: CGFloat = 121.5
        /// 缺口：bearing 163°–201°（宽 38°）。
        static let gapStart: Double = 201
        static let gapEnd: Double = 163
        static let sweepDegrees: Double = 322
        static let cursorDiameter: CGFloat = 23.3
        static let cursorBearing: Double = 289
        static let cursorRadius: CGFloat = 131
        static let tickW: CGFloat = 4.3
        static let tickH: CGFloat = 23.3
        static let tickTop: CGFloat = 6.7
        static let discDiameter: CGFloat = 206.7
        static let infoSize: CGFloat = 20.7
        static let infoX: CGFloat = 325
        static let infoY: CGFloat = 337
        /// 环心在 402×874 画布上的 y（x 恒为屏宽一半 = 201）。
        static let centerY: CGFloat = 276
        static let labelTracking: CGFloat = 1.5
        static let numberTracking: CGFloat = -3.4
        static let glowOpacity: Double = 0.55
        static let baseOpacity: Double = 0.72

        /// TOKENS.md：角向连续渐变 bearing 0→360°。
        static var gradient: [Gradient.Stop] {
            [
            .init(color: C.rgb(25, 29, 46), location: 0.0 / 360.0),
            .init(color: C.rgb(21, 26, 37), location: 45.0 / 360.0),
            .init(color: C.rgb(25, 29, 36), location: 90.0 / 360.0),
            .init(color: C.rgb(32, 40, 47), location: 135.0 / 360.0),
            .init(color: C.rgb(40, 63, 69), location: 202.0 / 360.0),
            .init(color: C.rgb(45, 78, 97), location: 230.0 / 360.0),
            .init(color: C.rgb(55, 101, 143), location: 270.0 / 360.0),
            .init(color: C.rgb(58, 121, 199), location: 282.0 / 360.0),
            .init(color: C.rgb(46, 72, 103), location: 300.0 / 360.0),
            .init(color: C.rgb(31, 40, 59), location: 340.0 / 360.0),
            .init(color: C.rgb(25, 29, 46), location: 360.0 / 360.0),
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
        static let numberSize: CGFloat = 21.3
        /// 中心线半径 = (92 - 20.3) / 2 = 35.85。
        static let radius: CGFloat = 35.85
    }

    // MARK: - 同心活动环（参考 C / TOKENS.md 活动环）
    enum Ring {
        static let width: CGFloat = 14
        static let gap: CGFloat = 1.2
        static let trackOpacity: Double = 0.22
        static let referenceOuter: CGFloat = 133.7
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
    }

    // MARK: - 面积图（参考 A）
    enum Chart {
        static let height: CGFloat = 125
        static let verticals: Int = 6
        static let lineWidth: CGFloat = 1.6
        static let dot: CGFloat = 2.4
        static let xStart: CGFloat = 0.22
        static let xEnd: CGFloat = 0.82
        static let topGap: CGFloat = 8
        static let usable: CGFloat = 0.54
        static let ruleMidY: CGFloat = 36
        static let dash: [CGFloat] = [1.2, 2.4]
        static let plotWidth: CGFloat = 282.4
    }

    // MARK: - 浮动标签栏（TOKENS.md）
    enum Tab {
        static let width: CGFloat = 268
        static let height: CGFloat = 57
        static let radius: CGFloat = 28.5
        static let bottom: CGFloat = 19.7
        static let selectedW: CGFloat = 56
        static let selectedH: CGFloat = 49
        static let selectedRadius: CGFloat = 24.5
        static let iconSize: CGFloat = 20
        static let labelGap: CGFloat = 2
        static let contentInset: CGFloat = 92
    }

    // MARK: - 列表行（设置 / 快捷入口）
    enum List {
        static let iconSize: CGFloat = 30
        static let rowMinHeight: CGFloat = 54
        static let toggleMinHeight: CGFloat = 50
        static let dotSize: CGFloat = 8
        static let ringDotSize: CGFloat = 12.5
        static let chevronSize: CGFloat = 14
        static let badgeSize: CGFloat = 26
    }

    // MARK: - 页面度量（参考 C 记录页 / 参考 R4 设置页）
    enum Metric {
        static let avatar: CGFloat = 34
        static let miniCardH: CGFloat = 178
        static let miniCardW: CGFloat = 170.7
        static let eventIcon: CGFloat = 36
        static let medal: CGFloat = 76
        static let searchRow: CGFloat = 44
        static let miniChartW: CGFloat = 143
    }

    // MARK: - 动作按钮（v7 没有参考按钮；沿用 14pt 圆角的卡片语言）
    enum Action {
        static let height: CGFloat = 50
        static let radius: CGFloat = 14
    }

    // MARK: - 页面局部节奏（四个根页共用）
    enum Page {
        static let topSpace: CGFloat = 8
        static let sectionGap: CGFloat = 22
        static let headerGap: CGFloat = 7
        static let chipToTitle: CGFloat = 26
        static let titleToBody: CGFloat = 6
        static let bodyLine: CGFloat = 23
        static let bodySpacing: CGFloat = 6
        static let cardHeaderGap: CGFloat = 6
        static let dividerY: CGFloat = 14
        static let statTop: CGFloat = 12
        static let sparklineH: CGFloat = 72
        static let chartTop: CGFloat = 10
    }
}
