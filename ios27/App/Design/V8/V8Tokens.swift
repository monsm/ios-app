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
        /// 2026-11-05（全技能审核 · 高对比）：kf_hc 原来只加倍线宽，文字颜色不动 ——
        /// 设置页却承诺「加强描边与文字对比」。开启时把正文/微标各提一档。
        static var ink3: Color {
            DB.store.getBool("kf_hc") ? dual(0x33333A, 0xD8D8DE) : dual(0x5E5D63, 0xA8A8B0)
        }
        /// 墨 4：眉标、微标、轴标。4.55:1（参考图 #85858B 只有 3.26）
        static var ink4: Color {
            DB.store.getBool("kf_hc") ? dual(0x5E5D63, 0xA8A8B0) : dual(0x6E6D75, 0x92929A)
        }

        /// 页面底：单色，不做页面级渐变（参考图基底恒为 #F2F1F6）
        static let bg = dual(0xF2F1F6, 0x000000)
        /// 卡片：比底亮 4~7 级
        static let card = dual(0xFFFFFF, 0x1C1C1E)
        /// 凹槽/内嵌块：比卡片暗
        static let well = dual(0xF2F2F7, 0x2C2C2E)
        /// 芯片未选中
        static let chipOff = dual(0xF4F3FA, 0x242427)
        /// 芯片选中
        static let chipOn = dual(0xFFFFFF, 0x2E2E33)

        /// 卡内分隔线（0.4pt 实线，只做结构切分）
        /// 高对比时用更深的线色（配合 VDivider2 的线宽 ×2）。
        static var line: Color {
            DB.store.getBool("kf_hc") ? dual(0xB8B7C4, 0xFFFFFF, lightAlpha: 1, darkAlpha: 0.28)
                                     : dual(0xDCDBE4, 0xFFFFFF, lightAlpha: 1, darkAlpha: 0.14)
        }
        /// 卡片投影（浅色 5% / 深色 18%）
        static let shadow = dual(0x282846, 0x000000, lightAlpha: 0.05, darkAlpha: 0.18)
        /// 玻璃面染色（仅 Tab 栏 / Toast / 只读试验条）
        static let glassTint = dual(0xFFFFFF, 0x1A1A1C, lightAlpha: 0.72, darkAlpha: 0.72)
        /// 表格点线 / 描边
        static var lineStrong: Color {
            DB.store.getBool("kf_hc") ? dual(0xA9A8B4, 0xFFFFFF, lightAlpha: 1, darkAlpha: 0.34)
                                     : dual(0xD8D7DE, 0xFFFFFF, lightAlpha: 1, darkAlpha: 0.20)
        }

        // MARK: 语义族：5 族 × 3 档（值 / 容器 / 轨道）

        /// 强调（蓝）值档：6.04:1
        static let accent = dual(0x0558B8, 0x5AA7F5)
        /// 强调底上的文字/图标（选中芯片、主按钮）。
        /// 浅色档 accent 深 → 白字；深色档 accent 浅 → 近黑字（白字只有 2.3:1）。
        static let onAccent = dual(0xFFFFFF, 0x08131F)
        /// 强调容器档（图形填充）：3.28:1
        static let accentFill = dual(0x2E86E8, 0x3D8CE8)
        /// 强调轨道档（空槽）
        static let accentTrack = dual(0xDCE6F5, 0x16324F)

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
        /// 22pt —— 页面 status 行（原 34pt 自绘大标题降级后的位置）。
        /// 2026-11-05（Round 3）：页面标题归系统 navigationTitle，这句话不再是标题，
        /// 而是「这一页现在怎么样」的状态句 —— 22pt semibold 足够强调，又不冒充标题。
        static let pageStatus = VFont(size: 22, weight: .semibold, relativeTo: .title2)
        /// 17pt —— 页面副文（因果段 / status 行）。HIG Body = 17。
        static let bodyL = VFont(size: 17, weight: .regular, relativeTo: .body)
        /// 21.5pt —— 卡内判断句（statement）
        /// 2026-11-05（全技能审核）：项目自己的字体纪律是「中文标题最高 semibold」
        /// （苹方无 Bold，.bold() 会静默回退/合成）。这里从 .bold 改成 .semibold。
        static let headline = VFont(size: 17, weight: .semibold, relativeTo: .headline)
        /// 17pt —— 卡内正文（HIG Body）。原 19.6 是「大号正文」，在 iOS 里读起来像标题。
        static let body = VFont(size: 17, weight: .regular, relativeTo: .body)
        /// 17pt —— 表格数值、读数
        static let value = VFont(size: 17, weight: .semibold, relativeTo: .body)
        /// 15pt —— 芯片第二行
        static let chipValue = VFont(size: 15, weight: .semibold, relativeTo: .subheadline)
        /// 15pt —— 卡脚注（HIG Footnote = 13；这里保留 15 作为中文可读下限）
        static let footnote = VFont(size: 15, weight: .regular, relativeTo: .footnote)
        /// 13pt —— 卡标签、芯片第一行、副标
        static let label = VFont(size: 13, weight: .regular, relativeTo: .subheadline)
        /// 12pt —— 表格行标签 / caption
        static let caption = VFont(size: 12, weight: .regular, relativeTo: .caption)
        /// 15pt —— 按钮/动作文字（原 12.6 比 HIG 的 17 小两档，按钮看起来像脚注）
        static let tab = VFont(size: 15, weight: .semibold, relativeTo: .subheadline)
        /// 11pt —— 微标（YEARS / BPM / %）、轴标（HIG 最小字号 11pt；原 10.7 低于下限）
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
        static var gapChip: CGFloat { d(10.6) }
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
        /// 分隔线 → 表首行（同时是 statement → 证据区的呼吸，41.6 与 42.4 在参考图上是同一档）
        static var gapTableFirst: CGFloat { d(42.4) }
        /// 表格行距
        static var rowHeight: CGFloat { d(22.1) }
        /// 分隔线 → 脚注
        static var gapFootnote: CGFloat { d(18.6) }

        /// 通用间距
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
        // 2026-11-05（Round 3）：字号回落后行高按 1.2–1.4 倍重配。
        // 这些值仍按「lineSpacing = L − size」消费，实际行高 ≈ 字体自然行高 + 该差值。
        static let bodyL: CGFloat = 20.5
        static let body: CGFloat = 20.5
        static let footnote: CGFloat = 17
        // 2026-11-05（全技能审核 · 死令牌清理）：label / caption / title1 三条行高
        // 全仓零消费者（只有字号档在用它们，行高从未被读过）—— 删掉，避免"看起来有 7 级行高"。
        // L.headline 已随 VCardHead 层级反转删除（标题走 T.headline，不再单独配行高）。
    }

    // MARK: - 圆角（只有三档）

    enum R {
        /// 2026-11-05（全技能审核 · 幽灵设置）：外观页的「圆角」自 V8 迁移后只写 kf_radius，
        /// 而唯一消费者是 V7Tokens.V.R —— V8 卡片/控件全用固定 26，用户改了没反应。
        /// 这里把 kf_radius 接进 V8：标准 26 / 偏硬朗 20 / 偏柔和 32。默认值保持 26 不变。
        static var card: CGFloat {
            // 2026-11-05（Round 3 · 专业 iOS 27）：26pt 的「胶囊卡」是模板感的主要来源。
            // 原生分组列表圆角 10–16：标准 14 / 偏硬朗 12 / 偏柔和 18。
            switch DB.store.getString("kf_radius") {
            case "soft": return 12
            case "plump": return 18
            default: return 14
            }
        }
        /// 内嵌块（与卡片同档缩放一半幅度）
        static var inset: CGFloat {
            switch DB.store.getString("kf_radius") {
            case "soft": return 8
            case "plump": return 12
            default: return 10
            }
        }
        /// 胶囊：圆角 = 高度的一半
        static func capsule(_ height: CGFloat) -> CGFloat { height / 2 }
    }

    // MARK: - 描边

    enum E {
        /// 全 App 唯一下划线粗细（= S.hair）
        static let hair: CGFloat = 0.4
        // 2026-11-05（全技能审核 · 死令牌清理）：focus 全仓零消费者 —— 没有自定义焦点环。
        /// 选中描边
        static let selected: CGFloat = 2
    }

    // MARK: - 动效（4 个令牌；ambient 用 phaseAnimator 实现，禁止 repeatForever）

    enum M {
        /// 2026-11-05（全技能审核 · 幽灵设置）：外观页的「动效强度」原来只有
        /// LockKeeperApp 的一次转场消费，其余 11 处 V8.M 动效完全不理它。
        /// 现在四档动效令牌统一读 kf_motion：克制 = 纯淡入（无弹跳）/ 标准 = 轻微弹簧 /
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
        static var ambient: Animation {
            switch tier {
            case "calm": return .easeInOut(duration: 3.2)
            case "lively": return .easeInOut(duration: 2.0)
            default: return .easeInOut(duration: 2.4)
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
        // 2026-11-05（Round 3）：原生分组卡片没有投影。原来的 10pt 阴影是「浮岛卡片」
        // 的来源之一，也是每张卡都要合成一层 blur 的性能开销。
        static let cardShadowRadius: CGFloat = 0
        static let cardShadowY: CGFloat = 0
    }
}
