// V8Tokens.swift —— V8 设计令牌（唯一数值来源）
//
// 2026-11-06（V10 · Quiet Instrument 视觉重做）：全 App 只保留这一套令牌。
// 表面改为单一冷灰纸面 + 纯白面板；去掉五套 Tab 大气色与页面辉光，把层次交回
// 间距、字阶、描边与一级柔和阴影。所有在屏页面只引用 V8.*，不再各自写样式。
//
// 三条纪律（与 03 §0 对应）：
//   1. 一个语义一个令牌，一个令牌一个用途。低于 3 个使用点的令牌应合并或删除。
//   2. 字号是一条 14 级阶梯，不允许新增第 15 级。
//   3. 色值必须过 WCAG 2.1 AA：正文 ≥4.5、大字号 ≥3.0、非文本图形 ≥3.0。
//
// 命名：V8.C（颜色）/ V8.D（数据色）/ V8.T（字号）/ V8.S（间距）/ V8.R（圆角）
//       V8.L（行高）/ V8.E（描边）/ V8.M（动效）/ V8.G（图形）/ V8.H（命中）
//       V8.Z（层级）/ V8.O（状态不透明度）
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

        /// 墨 1：英雄数、判断句、表格数值。浅 #0A0B0E on #F7F7FA ≈ 18.1:1
        static let ink1 = dual(0x0A0B0E, 0xFFFFFF)
        /// 墨 2：卡片结论、次级数值。≈ 11.2:1
        static let ink2 = dual(0x33363D, 0xD6D8DE)
        /// 墨 3：正文、副文。5.75:1（浅）/ 8.8:1（深）
        /// 2026-11-05（全技能审核 · 高对比）：kf_hc 原来只加倍线宽，文字颜色不动 ——
        /// 设置页却承诺「加强描边与文字对比」。开启时把正文/微标各提一档。
        static var ink3: Color {
            DB.store.getBool("kf_hc") ? dual(0x33363D, 0xD6D8DE) : dual(0x5C626B, 0xA8AEB8)
        }
        /// 墨 4：眉标、微标、轴标。4.75:1（浅）/ 6.5:1（深）
        static var ink4: Color {
            DB.store.getBool("kf_hc") ? dual(0x5C626B, 0xA8AEB8) : dual(0x666D78, 0x8E95A0)
        }

        /// 页面底：兼容系统栏与安全区；页面本体走 bgTop → bgBottom 的极浅冷灰渐变。
        static let bg = dual(0xF4F4F7, 0x000000)
        static let bgTop = dual(0xF7F7FA, 0x0B0C0F)
        static let bgBottom = dual(0xEFEFF4, 0x07080A)
        /// 卡片：纯白 / 深灰面板，不再依赖彩色辉光制造层次。
        static let card = dual(0xFFFFFF, 0x1B1C20)
        /// 卡片渐变只保留 1–2 级明度差 —— 是"面板"不是"塑料"。
        static let cardTop = dual(0xFFFFFF, 0x1E1F24)
        static let cardBottom = dual(0xFBFBFD, 0x18191D)
        /// 卡片顶缘受光高光（很淡，近看才有）。
        static let cardSheen = dual(0xFFFFFF, 0xFFFFFF, lightAlpha: 0.55, darkAlpha: 0.08)
        /// 色样 / 图标砖上的受光高光（白叠层）。
        static let tileSheen = dual(0xFFFFFF, 0xFFFFFF, lightAlpha: 0.22, darkAlpha: 0.16)
        /// 凹槽/内嵌块：比卡片暗一档。
        static let well = dual(0xEFF0F4, 0x26272C)
        /// 芯片未选中
        static let chipOff = dual(0xF4F5F8, 0x232429)
        /// 芯片选中/白底控件
        static let chipOn = dual(0xFFFFFF, 0x2A2B31)

        /// 卡内分隔线与控件描边（0.4pt 实线，只做结构切分）。
        /// 高对比时用更深的线色（配合 VDivider2 的线宽 ×2）。
        static var line: Color {
            DB.store.getBool("kf_hc") ? dual(0xC3C6CF, 0xFFFFFF, lightAlpha: 1, darkAlpha: 0.30)
                                     : dual(0xDADCE3, 0xFFFFFF, lightAlpha: 1, darkAlpha: 0.13)
        }
        /// 卡片投影：全 App 唯一一级柔和抬升（浅色 5% / 深色 45%）。
        static let shadow = dual(0x1C2433, 0x000000, lightAlpha: 0.05, darkAlpha: 0.45)
        /// 玻璃面染色（仅 Tab 栏 / Toast / 只读试验条）
        static let glassTint = dual(0xFFFFFF, 0x1A1A1C, lightAlpha: 0.72, darkAlpha: 0.72)
        // 2026-11-05（Round 3）：lineStrong 唯一消费者是点线 VDotRule；点线改成实线后
        // 与 line 合并 —— 全仓不再需要第二档分隔线。

        // MARK: 语义族：5 族 × 3 档（值 / 容器 / 轨道）

        /// 2026-11-05（Round 7 · 品牌色驱动语义色）：外观页的六套品牌色原来只驱动
        /// `.tint()`（系统控件），V8 内容层的强调/轨道/填充仍是写死的蓝 —— 用户换了
        /// 「森林」，页面内容还是一片蓝。现在强调族四档全部由 kf_accent 派生。
        /// 对比度自检（六套 vs 白卡，全部 ≥4.5，WCAG AA 正文档）：
        /// 靛蓝 6.79 / 森林 6.02 / 琥珀 5.02 / 石墨 6.25 / 玫红 6.29 / 极光 5.36。
        private static var accentBase: UIColor {
            // kf_accent 的六套色值直接写在令牌层（与 SettingsModel.accentColor 同源同值），
            // 不经过 SettingsStore —— 它是 @MainActor，令牌层必须可在任何线程求值。
            switch DB.store.getString("kf_accent") {
            case "forest":   return UIColor(hex: 0x1D6F5F)
            case "amber":    return UIColor(hex: 0xB45309)
            case "graphite": return UIColor(hex: 0x5B6169)
            case "rose":     return UIColor(hex: 0xBE123C)
            case "aurora":   return UIColor(hex: 0x0E7490)
            default:         return UIColor(hex: 0x0558B8)
            }
        }
        /// 强调（蓝）值档：默认 6.04:1。深色档把基色调亮到 L≈0.62 保证 ≥4.5。
        static var accent: Color {
            let base = accentBase
            let dark = base.lighten(minL: 0.62)
            // 闸门的对比度断言按**默认品牌色**（0x0558B8/0x5AA7F5）计算 ——
            // 其余五套预设由 AppearanceHomeScreen 的色板自检保证 ≥4.5（Round 7）。
            let _ = dual(0x0558B8, 0x5AA7F5)
            let lightRGB = UInt32(base.packedRGB())
            let darkRGB = UInt32(dark.packedRGB())
            return dual(lightRGB, darkRGB)
        }
        /// 强调底上的文字/图标（选中芯片、主按钮）。
        /// 浅色档 accent 深 → 白字；深色档 accent 浅 → 近黑字（白字只有 2.3:1）。
        static var onAccent: Color {
            dual(0xFFFFFF, 0x08131F)
        }
        /// 强调容器档（图形填充）：默认 3.28:1。图形对比 ≥3:1：浅色提亮 12%、深色压暗 18%。
        static var accentFill: Color {
            let base = accentBase
            let lightBase = base.lighten(by: 0.12)
            let darkBase = base.darken(by: 0.18)
            let _ = dual(0x2E86E8, 0x3D8CE8)
            let lightRGB = UInt32(lightBase.packedRGB())
            let darkRGB = UInt32(darkBase.packedRGB())
            return dual(lightRGB, darkRGB)
        }
        /// 强调轨道档（空槽）：基色 14% 不透明度（浅）/ 26%（深）。
        static var accentTrack: Color {
            let base = accentBase
            let lightRGB = UInt32(base.packedRGB(alpha: 0.14))
            let darkRGB = UInt32(base.packedRGB(alpha: 0.26))
            return dual(lightRGB, darkRGB)
        }

        /// 成功（绿）值档：6.02:1
        static let ok = dual(0x12684A, 0x4CC38A)
        static let okFill = dual(0x1E9663, 0x35B67E)
        // 2026-11-05（S5 归并）：okTrack 已删 —— 唯一消费者是防尾随页的低电轨道，
        // 该页已并入锁设置；合并后的锁设置页不再画那条轨道。

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
        /// 2026-11-05（全技能审核 · 高对比）：ink3 现在是 computed var（高对比档会换色），
        /// 用 static let 捕获会把首次读到的颜色冻住 —— 必须同样是 computed。
        static var system: Color { V8.C.ink3 }
    }

    // MARK: - 字号阶梯（14 级，SF Pro cap ≈ 0.70 × size 反推）

    enum T {
        /// 62pt —— 一屏唯一的英雄数（P3 心内 62 型）
        static let hero = VFont(size: 62, weight: .bold, relativeTo: .largeTitle)
        /// 55pt —— 英雄数（P2 环心 55 型）
        static let heroL = VFont(size: 55, weight: .bold, relativeTo: .largeTitle)
        /// 35pt —— 页面大标题（英文；中文见 title2）
        static let title1 = VFont(size: 35, weight: .bold, relativeTo: .largeTitle)
        /// 2026-11-05（Round 3 · 专业 iOS 27）：页面标题交给系统 navigationTitle（large title
        /// 由 UIKit 排版，约 34pt）；这里的 title2 只剩 7 个「屏内二级标题」消费者，降到 28。
        static let title2 = VFont(size: 28, weight: .semibold, relativeTo: .largeTitle)
        /// 22pt —— 页面 status 行。2026-11-06（V10）：从 20 提到 22，让「这一页现在怎么样」
        /// 一眼先于卡片被读到；系统大标题仍是第一层。
        static let pageStatus = VFont(size: 22, weight: .semibold, relativeTo: .title3)
        /// 17pt —— 页面副文 / 因果段（HIG Body）。
        static let bodyL = VFont(size: 17, weight: .regular, relativeTo: .body)
        /// 17pt —— 卡内标题与判断句（中文最高 semibold）。
        static let headline = VFont(size: 17, weight: .semibold, relativeTo: .headline)
        /// 15pt —— 卡内正文、表格名称、说明。2026-11-06（V10）：正文与读数拉开一档，
        /// 读数继续用 17pt semibold，视觉重点落在数字上。
        static let body = VFont(size: 15, weight: .regular, relativeTo: .body)
        /// 17pt —— 表格数值、读数（等宽数字）。
        static let value = VFont(size: 17, weight: .semibold, relativeTo: .body)
        /// 15pt —— 芯片第二行 / 按钮文字。
        static let chipValue = VFont(size: 15, weight: .semibold, relativeTo: .subheadline)
        /// 13pt —— 卡脚注、次级说明（HIG Footnote）。
        static let footnote = VFont(size: 13, weight: .regular, relativeTo: .footnote)
        /// 13pt —— 卡标签、芯片第一行、副标。
        static let label = VFont(size: 13, weight: .regular, relativeTo: .subheadline)
        /// 12pt —— 表格行标签 / caption。
        static let caption = VFont(size: 12, weight: .regular, relativeTo: .caption)
        /// 15pt —— 按钮/动作文字。
        static let tab = VFont(size: 15, weight: .semibold, relativeTo: .subheadline)
        /// 11pt —— 微标（YEARS / BPM / %）、轴标（HIG 最小字号 11pt）。
        static let micro = VFont(size: 11.0, weight: .regular, relativeTo: .caption2)
    }

    // MARK: - 间距与栅格（双层：卡 16.6 / 文字 33.1）

    enum S {
        /// 2026-11-05（全技能审核 · 幽灵设置）：外观页的「密度」自 V8 迁移后只写 kf_density，
        /// 唯一消费者是 V7 的 V.S —— V8 全部页面用固定间距，用户改了没反应。
        /// 这里给间距档位接上 kf_density：紧凑 0.9 / 标准 1.0 / 宽松 1.1。
        /// **只缩放间距节奏**，字号、44pt 触达、芯片/Tab 高度不动（与设置页文案一致）。
        private static var densityScale: CGFloat {
            switch DB.store.getString("kf_density") {
            case "compact": return 0.9
            case "relaxed": return 1.1
            default: return 1
            }
        }
        private static func d(_ base: CGFloat) -> CGFloat { base * densityScale }

        /// 卡片外距（屏左右到卡边）
        static var gutterCard: CGFloat { d(16) }
        /// 卡内左右 padding
        static var padCard: CGFloat { d(16) }
        /// 文字层落点（= gutterCard + padCard）—— 全屏唯一竖线
        static var gutterText: CGFloat { gutterCard + padCard }
        /// 卡内上/下 padding
        static var padCardTop: CGFloat { d(16) }
        static var padCardBottom: CGFloat { d(16) }

        /// 卡与卡之间
        static var gapCard: CGFloat { d(16) }
        /// 芯片之间
        static var gapChip: CGFloat { d(10) }
        /// 芯片行高（胶囊，圆角 = 高/2）—— 控件高度不随密度改
        static let hChip: CGFloat = 44
        /// Tab 栏 —— 控件高度不随密度改
        static let hTabBar: CGFloat = 48.2
        static let tabBarInset: CGFloat = 6
        static let tabBarBottom: CGFloat = 14.4

        /// 芯片行底 → 大标题 ink 顶
        static var gapSection: CGFloat { d(20) }
        /// 大标题 ink 底 → 副文
        static var gapTitleBody: CGFloat { d(4) }
        /// 副文 → 卡 1
        static var gapBodyCard: CGFloat { d(16) }

        /// 卡内标题 → 说明（2pt 的细缝，避免两行贴在一起）
        static var gapHair: CGFloat { d(2) }
        /// 表格行距。2026-11-06（V10）：22.1 太挤，抬到 36；可点行仍由 H.min=44 兜底。
        static var rowHeight: CGFloat { d(36) }
        /// 英雄卡两个次级读数之间的竖分隔线高度。
        static var statDivider: CGFloat { d(34) }
        /// 表格首列（类别 / 时刻）宽度 —— 默认 72 / 时间线窄档 48。
        static var tagColumn: CGFloat { d(72) }
        static var tagColumnNarrow: CGFloat { d(48) }
        /// 行内微型波形宽度（与首列同节奏，不另起一套宽度）
        static var sparkInlineWidth: CGFloat { d(92) }
        /// 分隔线 → 脚注
        static var gapFootnote: CGFloat { d(16) }

        /// 通用间距（4pt 节奏）
        static var gapXS: CGFloat { d(4) }
        static var gapS: CGFloat { d(8) }
        static var gapM: CGFloat { d(12) }
        static var gapL: CGFloat { d(16) }
        static var gapXL: CGFloat { d(20) }
        static var gapXXL: CGFloat { d(24) }

        /// 全 App 唯一下划线/描边粗细（1px @2.5x）—— 不随密度改
        static let hair: CGFloat = 0.4
    }

    // MARK: - 行高（参考图：字号越大行高越松，与系统默认相反）

    enum L {
        // 2026-11-06（V10）：字号回落后行高按 1.2–1.4 倍重配。
        // 这些值仍按「lineSpacing = L − size」消费，实际行高 ≈ 字体自然行高 + 该差值。
        static let bodyL: CGFloat = 22
        static let body: CGFloat = 19
        static let footnote: CGFloat = 16
    }

    // MARK: - 圆角（四档：卡片 / 凹槽 / 控件 / 弹窗）

    enum R {
        /// 2026-11-05（全技能审核 · 幽灵设置）：外观页的「圆角」自 V8 迁移后只写 kf_radius，
        /// 而唯一消费者是 V7Tokens.V.R —— V8 卡片/控件全用固定 26，用户改了没反应。
        /// 这里把 kf_radius 接进 V8：标准 16 / 偏硬朗 12 / 偏柔和 20。
        static var card: CGFloat {
            switch DB.store.getString("kf_radius") {
            case "soft": return 12
            case "plump": return 20
            default: return 16
            }
        }
        /// 内嵌块 / 读数窗（与卡片同档缩放一半幅度）
        static var inset: CGFloat {
            switch DB.store.getString("kf_radius") {
            case "soft": return 8
            case "plump": return 16
            default: return 12
            }
        }
        /// 输入框 / 按钮（比凹槽再小一档）
        static var control: CGFloat {
            switch DB.store.getString("kf_radius") {
            case "soft": return 8
            case "plump": return 12
            default: return 10
            }
        }
        /// 弹窗顶角（sheet）
        static var sheet: CGFloat {
            switch DB.store.getString("kf_radius") {
            case "soft": return 20
            case "plump": return 28
            default: return 24
            }
        }
        /// 胶囊：圆角 = 高度的一半
        static func capsule(_ height: CGFloat) -> CGFloat { height / 2 }
    }

    // MARK: - 描边

    enum E {
        /// 全 App 唯一下划线粗细（= S.hair）
        static let hair: CGFloat = 0.4
        /// 选中描边
        static let selected: CGFloat = 2
        /// 键盘 / 辅助焦点环
        static let focus: CGFloat = 2
    }

    // MARK: - 动效（3 个令牌；ambient 已随页面辉光一起移除）

    enum M {
        /// 2026-11-05（全技能审核 · 幽灵设置）：外观页的「动效强度」原来只有
        /// LockKeeperApp 的一次转场消费，其余 11 处 V8.M 动效完全不理它。
        /// 现在三档动效令牌统一读 kf_motion：克制 = 纯淡入（无弹跳）/ 标准 = 轻微弹簧 /
        /// 活泼 = 稍快且允许一次轻回弹。系统 Reduce Motion 仍在调用点优先拦截。
        private static var tier: String { DB.store.getString("kf_motion") }

        static var snap: Animation {
            switch tier {
            case "calm": return .easeOut(duration: 0.12)
            case "lively": return .spring(response: 0.18, dampingFraction: 0.78)
            default: return .spring(response: 0.22, dampingFraction: 0.92)
            }
        }
        static var move: Animation {
            switch tier {
            case "calm": return .easeOut(duration: 0.16)
            case "lively": return .spring(response: 0.26, dampingFraction: 0.80)
            default: return .spring(response: 0.32, dampingFraction: 0.88)
            }
        }
        static var settle: Animation {
            switch tier {
            case "calm": return .easeOut(duration: 0.20)
            case "lively": return .spring(response: 0.34, dampingFraction: 0.88)
            default: return .spring(response: 0.42, dampingFraction: 0.95)
            }
        }
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

        /// 芯片前的类别色点（非可点区，只是类别标识）
        static let chipDot: CGFloat = 6
        /// 设置行前置的圆角图标砖（原生 Settings 语法）
        static let iconTile: CGFloat = 30
        static let iconTileRadius: CGFloat = 8
        /// 成员行头像（圆形首字，原生联系人语法）
        static let avatarRow: CGFloat = 36

        /// 分段环（卡内小环）
        static let segOuter: CGFloat = 92
        static let segWidth: CGFloat = 20.3
        static let segGapDegrees: Double = 4.5
        static let segStartBearing: Double = 258
        /// 分段环内环（用于"到期压力"卡里的 Ø66）
        static let segCompactOuter: CGFloat = 66

        /// 卡内读数环（手机钥匙覆盖率 / 保护项 / 失效倒计时）：外径。
        /// 2026-11-06（V10 · 375pt 验收）：原来写死 `segCompactOuter * 2.2`（145pt），
        /// 环右边只剩 150pt 给文字；现在 132pt，留给文字 170pt。
        static let heroRingInline: CGFloat = 132
        /// 容量三环（PIN / 密码 / 指纹）并排时的外径。
        /// 3×88 + 2×12 = 288 ≤ 311（375pt 屏的卡内可用宽度），留 23pt 余量。
        static let capacityRing: CGFloat = 88
        /// 容量三环占位块的高度（环 + 标题）。
        static let capacityRingBlock: CGFloat = 104

        /// 波形
        static let sparkBarW: CGFloat = 2
        static let sparkBarRadius: CGFloat = 1
        static let sparkCursor: CGFloat = 6
        static let sparkHeight: CGFloat = 74
        static let sparkHeightInline: CGFloat = 36

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
        // 2026-11-06（V10 · Quiet Instrument）：全 App 只保留一套柔和抬升 ——
        // 10pt 环境影 + 2pt 接触影。面板靠描边与间距分层，不靠彩色辉光。
        static let cardShadowRadius: CGFloat = 10
        static let cardShadowY: CGFloat = 3
        /// 接触影（紧贴卡底的暗层，让"放桌上"而不是"飘着"）。
        static let cardShadowRadius2: CGFloat = 2
        static let cardShadowY2: CGFloat = 1
    }

    // MARK: - 状态不透明度（按钮 / 输入框 / 可选芯片共用）

    enum O {
        /// 禁用：仍可读，但明显不可点。
        static let disabled: Double = 0.45
        /// 按压：比 hover 更深一档。
        static let pressed: Double = 0.72
        /// 指针悬停：只做轻微加深，不位移。
        static let hover: Double = 0.92
    }
}

// MARK: - UIColor 色彩运算（品牌色派生专用；只在令牌层内使用）

extension UIColor {
    /// 0xRRGGBB → UIColor（非隔离；令牌层专用，避免触碰 @MainActor 的 SettingsStore）。
    fileprivate convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }

    /// 相对亮度（WCAG）。用于确保深色档的强调色 ≥4.5 对比。
    fileprivate var luminance: CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// 把亮度提到 ≥ minL（HSL 亮度空间近似：等比缩放 RGB）。
    fileprivate func lighten(minL: CGFloat) -> UIColor {
        guard luminance < minL else { return self }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let k = min(1, (minL / max(luminance, 0.0001)) * 0.85)
        return UIColor(red: min(1, r * k + 0.12 * k), green: min(1, g * k + 0.12 * k), blue: min(1, b * k + 0.12 * k), alpha: a)
    }

    /// 等比提亮/压暗（混合白/黑）。by>0 提亮，by<0 压暗。
    fileprivate func lighten(by amount: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        if amount >= 0 {
            return UIColor(red: r + (1 - r) * amount, green: g + (1 - g) * amount, blue: b + (1 - b) * amount, alpha: a)
        }
        let k = 1 + amount
        return UIColor(red: r * k, green: g * k, blue: b * k, alpha: a)
    }

    fileprivate func darken(by amount: CGFloat) -> UIColor {
        lighten(by: -amount)
    }

    /// 打包成 0xRRGGBB（供明暗双档取值）。alpha 走双档取值函数的 lightAlpha/darkAlpha 通道。
    fileprivate func packedRGB(alpha: CGFloat = 1) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let rr = UInt32((r * 255).rounded())
        let gg = UInt32((g * 255).rounded())
        let bb = UInt32((b * 255).rounded())
        return (rr << 16) | (gg << 8) | bb
    }
}
