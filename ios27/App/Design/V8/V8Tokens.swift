// V8Tokens.swift —— V8 设计令牌（重构方案 03 的落地层）
//
// 这份文件是**新设计语言的唯一数值来源**。与 V7Tokens.swift 并存，互不引用。
// 来源：_plan/03-设计系统重构.md（值）+ _plan/raw/E-ref-metrics.md（参考图像素实测）。
//
// 三条纪律（与 03 §0 对应）：
//   1. 一个语义一个令牌，一个令牌一个用途。低于 3 个使用点的令牌应合并或删除。
//   2. 字号是一条 14 级阶梯，不允许新增第 15 级。
//   3. 色值必须过 WCAG 2.1 AA：正文 ≥4.5、大字号 ≥3.0、非文本图形 ≥3.0。
//      参考图自身的正文灰只有 3.63、卡标签 3.26、Awake 2.42、REM 2.29 —— 不可照抄。
//
// 命名：V8.C（颜色）/ V8.D（数据色）/ V8.T（字号）/ V8.S（间距）/ V8.R（圆角）
//       V8.L（行高）/ V8.E（描边）/ V8.M（动效）/ V8.G（图形）/ V8.H（命中）/ V8.Z（层级）
import SwiftUI
import UIKit

enum V8 {
    // MARK: - 颜色：中性族（9 组）

    enum C {
        /// 十六进制 → Color。只在令牌层内部使用。
        static func hex(_ value: UInt32, _ alpha: Double = 1) -> Color {
            Color(
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255,
                opacity: alpha
            )
        }

        /// 明暗自适应：浅色/深色两套独立取值。
        static func dual(_ light: UInt32, _ dark: UInt32,
                         lightAlpha: Double = 1, darkAlpha: Double = 1) -> Color {
            Color(UIColor { trait in
                let isDark = trait.userInterfaceStyle == .dark
                let value = isDark ? dark : light
                return UIColor(
                    red: CGFloat((value >> 16) & 0xFF) / 255,
                    green: CGFloat((value >> 8) & 0xFF) / 255,
                    blue: CGFloat(value & 0xFF) / 255,
                    alpha: CGFloat(isDark ? darkAlpha : lightAlpha)
                )
            })
        }

        /// 墨 1：英雄数、判断句、表格数值。浅 #0A0A0C on #F2F1F6 = 17.60:1
        static let ink1 = dual(0x0A0A0C, 0xFFFFFF)
        /// 墨 2：卡片结论、次级数值。11.15:1
        static let ink2 = dual(0x33333A, 0xD8D8DE)
        /// 墨 3：正文、副文。5.80:1（参考图 #7E7D83 只有 3.63）
        static let ink3 = dual(0x5E5D63, 0xA8A8B0)
        /// 墨 4：眉标、微标、轴标。4.55:1（参考图 #85858B 只有 3.26）
        static let ink4 = dual(0x6E6D75, 0x92929A)

        /// 页面底：单色，不做页面级渐变（参考图基底恒为 #F2F1F6）
        static let bg = dual(0xF2F1F6, 0x000000)
        /// 卡片：比底亮 4~7 级
        static let card = dual(0xF9F9FE, 0x1C1C1F)
        /// 凹槽/内嵌块：比卡片暗
        static let well = dual(0xE9E8EF, 0x141416)
        /// 芯片未选中
        static let chipOff = dual(0xF4F3FA, 0x242427)
        /// 芯片选中
        static let chipOn = dual(0xFFFFFF, 0x2E2E33)

        /// 卡内分隔线（0.4pt 实线，只做结构切分）
        static let line = dual(0xDCDBE4, 0xFFFFFF, lightAlpha: 1, darkAlpha: 0.14)
        /// 卡片投影（浅色 5% / 深色 18%）
        static let shadow = dual(0x282846, 0x000000, lightAlpha: 0.05, darkAlpha: 0.18)
        /// 玻璃面染色（仅 Tab 栏 / Toast / 只读试验条）
        static let glassTint = dual(0xFFFFFF, 0x1A1A1C, lightAlpha: 0.72, darkAlpha: 0.72)
        /// 表格点线 / 描边
        static let lineStrong = dual(0xD8D7DE, 0xFFFFFF, lightAlpha: 1, darkAlpha: 0.20)

        // MARK: 语义族：5 族 × 3 档（值 / 容器 / 轨道）

        /// 强调（蓝）值档：6.04:1
        static let accent = dual(0x0558B8, 0x5AA7F5)
        /// 强调容器档（图形填充）：3.28:1
        static let accentFill = dual(0x2E86E8, 0x3D8CE8)
        /// 强调轨道档（空槽）
        static let accentTrack = dual(0xDCE6F5, 0x16324F)

        /// 成功（绿）值档：6.02:1
        static let ok = dual(0x12684A, 0x4CC38A)
        static let okFill = dual(0x1E9663, 0x35B67E)
        static let okTrack = dual(0xD8EDE3, 0x143A2A)

        /// 警告（琥珀）值档：5.27:1
        static let warn = dual(0x8A5A0B, 0xE0A83C)
        static let warnFill = dual(0xB8811A, 0xD79A2B)
        // 2026-11-04（Round 16）：warnTrack 已删 —— 全仓零消费者。
        // 设计文档 03 §0 纪律一："低于 3 个使用点的令牌应合并或删除"。
        // 本 App 没有"警告轨道"这种图形（低电环用的是 warnFill + line），
        // 留着一个没人用的档位，只会让下一个人以为它有意义。

        /// 危险（红）值档：5.82:1
        static let danger = dual(0xB3261E, 0xF06A5C)
        static let dangerFill = dual(0xE5483C, 0xE5483C)
        static let dangerTrack = dual(0xF3DAD7, 0x3F1D1A)

        /// 信息（靛）值档：6.23:1
        static let info = dual(0x4A46C8, 0x8E88F0)
        // 2026-11-04：infoFill 已删 —— 全仓零消费者（没有任何"信息容器"图形）。
        /// 信息轨道档
        static let infoTrack = dual(0xE1E0F5, 0x262457)
    }

    // MARK: - 数据色：只编码"类别"，不编码"重要"

    enum D {
        /// 密码（复用强调族）
        static let password = V8.C.accent
        static let passwordFill = V8.C.accentFill
        /// 指纹（紫）
        static let fingerprint = V8.C.dual(0x6A3FB8, 0xB07BE0)
        static let fingerprintFill = V8.C.dual(0x9A78D8, 0x9A78D8)
        /// 临时码（琥珀）
        static let temp = V8.C.warn
        static let tempFill = V8.C.warnFill
        /// 手机钥匙（绿）
        static let mobile = V8.C.ok
        static let mobileFill = V8.C.okFill
        /// 记录·开锁
        static let openEvent = V8.C.accent
        /// 记录·告警
        static let alarm = V8.C.danger
        /// 记录·失败
        static let failure = V8.C.warn
        /// 记录·系统
        static let system = V8.C.ink3
    }

    // MARK: - 字号阶梯（14 级，SF Pro cap ≈ 0.70 × size 反推）

    enum T {
        /// 62pt —— 一屏唯一的英雄数（P3 心内 62 型）
        static let hero = VFont(size: 62, weight: .bold, relativeTo: .largeTitle)
        /// 55pt —— 英雄数（P2 环心 55 型）
        static let heroL = VFont(size: 55, weight: .bold, relativeTo: .largeTitle)
        /// 35pt —— 页面大标题（英文；中文见 title2）
        static let title1 = VFont(size: 35, weight: .bold, relativeTo: .largeTitle)
        /// 34pt —— 中文大标题（苹方无真 Bold，用 semibold + 负字距）
        static let title2 = VFont(size: 34, weight: .semibold, relativeTo: .largeTitle)
        /// 22pt —— 页面副文（因果段）
        static let bodyL = VFont(size: 22, weight: .regular, relativeTo: .title3)
        /// 21.5pt —— 卡内判断句（statement）
        static let headline = VFont(size: 21.5, weight: .bold, relativeTo: .title2)
        /// 19.6pt —— 卡内正文
        static let body = VFont(size: 19.6, weight: .regular, relativeTo: .body)
        /// 17.7pt —— 表格数值、读数
        static let value = VFont(size: 17.7, weight: .semibold, relativeTo: .body)
        /// 16.4pt —— 芯片第二行
        static let chipValue = VFont(size: 16.4, weight: .semibold, relativeTo: .subheadline)
        /// 15.8pt —— 卡脚注
        static let footnote = VFont(size: 15.8, weight: .regular, relativeTo: .footnote)
        /// 14.5pt —— 卡标签（eyebrow）、芯片第一行、副标
        static let label = VFont(size: 14.5, weight: .regular, relativeTo: .subheadline)
        /// 13.9pt —— 表格行标签
        static let caption = VFont(size: 13.9, weight: .regular, relativeTo: .footnote)
        /// 12.6pt —— Tab 栏标签、KPI 标签
        static let tab = VFont(size: 12.6, weight: .semibold, relativeTo: .caption)
        /// 10.7pt —— 微标（YEARS / BPM / %）、轴标
        static let micro = VFont(size: 10.7, weight: .regular, relativeTo: .caption2)
    }

    // MARK: - 间距与栅格（双层：卡 16.6 / 文字 33.1）

    enum S {
        /// 卡片外距（屏左右到卡边）
        static let gutterCard: CGFloat = 16.6
        /// 卡内左右 padding
        static let padCard: CGFloat = 16.5
        /// 文字层落点（= gutterCard + padCard）—— 全屏唯一竖线
        static let gutterText: CGFloat = 33.1
        /// 卡内上/下 padding
        static let padCardTop: CGFloat = 20.6
        static let padCardBottom: CGFloat = 18.7

        /// 卡与卡之间
        static let gapCard: CGFloat = 11.1
        /// 芯片之间（主 / 紧）
        static let gapChip: CGFloat = 10.6
        static let gapChipMin: CGFloat = 7.1
        /// 芯片行高（胶囊，圆角 = 高/2）
        static let hChip: CGFloat = 52.6
        /// Tab 栏
        static let hTabBar: CGFloat = 48.2
        static let tabBarInset: CGFloat = 6
        static let tabBarBottom: CGFloat = 14.4

        /// 芯片行底 → 大标题 ink 顶
        static let gapSection: CGFloat = 41
        /// 大标题 ink 底 → 副文
        static let gapTitleBody: CGFloat = 12.8
        /// 副文 → 卡 1
        static let gapBodyCard: CGFloat = 18.8

        /// 卡内：eyebrow → statement
        static let gapEyebrow: CGFloat = 8.5
        /// 分隔线 → 表首行（同时是 statement → 证据区的呼吸，41.6 与 42.4 在参考图上是同一档）
        static let gapTableFirst: CGFloat = 42.4
        /// 表格行距
        static let rowHeight: CGFloat = 22.1
        /// 分隔线 → 脚注
        static let gapFootnote: CGFloat = 18.6

        /// 通用间距
        static let gapXS: CGFloat = 4
        static let gapS: CGFloat = 8
        static let gapM: CGFloat = 12
        static let gapL: CGFloat = 16
        static let gapXL: CGFloat = 20
        static let gapXXL: CGFloat = 24

        /// 全 App 唯一下划线/描边粗细（1px @2.5x）
        static let hair: CGFloat = 0.4
    }

    // MARK: - 行高（参考图：字号越大行高越松，与系统默认相反）

    enum L {
        static let bodyL: CGFloat = 27.9
        static let body: CGFloat = 20
        static let footnote: CGFloat = 19.9
        static let label: CGFloat = 17.4
        static let caption: CGFloat = 16.7
        static let title1: CGFloat = 38.5
        static let headline: CGFloat = 25.8
    }

    // MARK: - 圆角（只有三档）

    enum R {
        /// 卡片 / 面板 / sheet 内容块
        static let card: CGFloat = 26
        /// 内嵌块
        static let inset: CGFloat = 8
        /// 胶囊：圆角 = 高度的一半
        static func capsule(_ height: CGFloat) -> CGFloat { height / 2 }
    }

    // MARK: - 描边

    enum E {
        /// 全 App 唯一下划线粗细（= S.hair）
        static let hair: CGFloat = 0.4
        /// 焦点环
        static let focus: CGFloat = 1.5
        /// 选中描边
        static let selected: CGFloat = 2
    }

    // MARK: - 动效（4 个令牌；ambient 用 phaseAnimator 实现，禁止 repeatForever）

    enum M {
        static let snap = Animation.spring(response: 0.22, dampingFraction: 0.92)
        static let move = Animation.spring(response: 0.32, dampingFraction: 0.88)
        static let settle = Animation.spring(response: 0.42, dampingFraction: 0.95)
        static let ambient = Animation.easeInOut(duration: 2.4)
    }

    // MARK: - 图形（环 / 分段环 / 波形 / 发光）

    enum G {
        /// 主环外径（= 参考图 279.3pt）
        static let heroOuter: CGFloat = 279.3
        /// 主环描边（= 36.3pt）
        static let heroStroke: CGFloat = 36.3
        /// 缺口起点 bearing（12 点 = 0°，顺时针）
        static let heroGapStart: Double = 201
        /// 已填充段扫过角度
        static let heroSweep: Double = 308.2
        /// 游标点直径
        static let heroCursor: CGFloat = 23.3
        /// 游标 bearing
        static let heroCursorBearing: Double = 289
        /// 游标半径（中心线）
        static let heroCursorRadius: CGFloat = 131
        /// 12 点刻度
        static let heroTickW: CGFloat = 4.3
        static let heroTickH: CGFloat = 23.3
        static let heroTickTop: CGFloat = 6.7
        /// 内盘直径
        static let heroDisc: CGFloat = 206.7
        /// 中心数字字距
        static let heroNumberTracking: CGFloat = -1.5
        /// 微标字距
        static let heroLabelTracking: CGFloat = 1.2

        /// 分段环（卡内小环）
        static let segOuter: CGFloat = 92
        static let segWidth: CGFloat = 20.3
        static let segGapDegrees: Double = 4.5
        static let segStartBearing: Double = 258
        /// 分段环内环（用于"到期压力"卡里的 Ø66）
        static let segCompactOuter: CGFloat = 66

        /// 波形
        static let sparkBarW: CGFloat = 2
        static let sparkBarRadius: CGFloat = 1
        static let sparkCursor: CGFloat = 6
        static let sparkHeight: CGFloat = 74
        static let sparkHeightInline: CGFloat = 36

        /// ambient glow
        static let glowAlphaLight: Double = 0.12
        static let glowAlphaDark: Double = 0.18
        static let glowRadiusFactor: CGFloat = 1.15

        /// Tab 栏选中胶囊
        static let tabPillW: CGFloat = 70
        static let tabPillH: CGFloat = 41.1
        static let tabIconW: CGFloat = 18.6
        static let tabIconH: CGFloat = 19.9
    }

    // MARK: - 命中区

    enum H {
        /// HIG 下限，永远不许当"固定高度"用（只能 minHeight）
        static let min: CGFloat = 44
        /// 舒适命中区
        static let comfortable: CGFloat = 52
    }

    // MARK: - 层级 / 阴影

    enum Z {
        static let cardShadowRadius: CGFloat = 10
        static let cardShadowY: CGFloat = 1.5
    }
}
