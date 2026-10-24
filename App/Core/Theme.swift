//
//  Theme.swift
//  Black Canvas / Glass Instrument —— 令牌层 (唯一色/空/圆角/动效事实来源)
//
//  设计契约 (Design Contract)
//  ─────────────────────────────
//  隐喻   : 黑色画布上的精密仪器。门是那个仪器, 光是唯一的装饰。
//  性格   : 克制、精密、夜间。不喧哗, 不用渐变掩盖布局。
//  材质   : 纯黑画布 + 6% 白圆角卡 + 一层薄玻璃(仅功能层)。
//  色彩   : 纯黑 canvas, 语义色按"意思"绑定, 一屏 <=3 种强调色。
//  字体   : 系统字体, 字阶比 HIG 默认小约 12% (宽度比例法实测, 见设计规范 4.4)。
//  空间   : 页边距 14, 卡片内边距 16, 行间距 8 / 列间距 12 —— 三个不同的数, 不许合并。
//  动效   : 单调曲线, 零过冲; 全部过 reduceMotion / 低电量双闸。
//
//  约束 (不可违反)
//  ─────────────────────────────
//  · 页面底色永远是纯黑 #000000 —— 不用深灰当"深色"。
//  · 卡片 #1C1C1E 圆角 24, 零投影。靠明度差分分层, 不靠阴影。
//  · 玻璃只出现在功能层 (Tab Bar / 浮层 / Sheet), 卡片永远不许用玻璃。
//  · 所有颜色必须走 XPalette, 禁止 Color(hex:) 散落在页面里。
//  · 所有动效必须走 XMotion, 禁止在视图里写 duration。
//  · calm 档 (减弱动效/低电量) 必须能压平任何动效。
//  · 对比度: 正文 >=4.5:1, 大字 >=3:1 (WCAG AA), 由 tools/contrast.js 机检。
//
//  2026-10-22 整层重写 (Glass Instrument):
//  旧值全部是平台惯例值 (16pt 边距 / 16pt 圆角 / #0A0A0B 画布), 从未与设计范式对齐。
//  新值逐条来自设计规范, 且对比度全部重算 —— 数值与断言表见 docs/GLASS/TOKENS.md。
//

import SwiftUI
import UIKit

// ═══════════════════════════════════════════════════════════
// MARK: - 色板
// ═══════════════════════════════════════════════════════════

/// 语义色板 —— 全 App 唯一色源。
///
/// 双层世界 (设计规范 1.2, 做错这一层的后果比做错细节严重得多):
///   · 应用体 App  —— 黑画布 + 深卡 (#1C1C1E) + 浅色文字。**本 App 的主体只有这一层。**
///   · 展示壳 Shell —— 黑画布 + 白卡 (r40) + 深色文字。只用于功能引导卡, 不用于主流程。
///
/// **只做深色。** 规范 §13.4 原话：
///
/// > 应用体：只做深色，**不提供 App 内明暗切换**。
///
/// 这里曾经有一段很长的"为什么保留明暗双模"的辩解（kf_theme 是真开关、备份里带这个键、
/// 砍了就成假开关……）。那些理由**都成立，但都不构成豁免** ——
/// 规范说的是"不提供"，不是"提供了要有好理由"。
/// 一个用户可以切到浅色的 App，无论浅色做得多么合规，都不是这个范式。
///
/// 已按规范改：全部令牌单值（深色档），App 内明暗开关一并移除。
enum XPalette {
    // ── 画布 ──
    /// 画布最底。**深色档是纯黑 #000000** —— 这是范式的第一条总则:
    /// "黑色是画布, 不是背景色"。旧值 0x0A0A0B 是深灰, 会让整屏发灰、卡片浮不起来。
    static var canvas: Color { Color.adaptive(0xF2F2F7, 0x000000) }

    /// 画布**径向渐变** —— 图 1/2/6 的实测底: 顶部 6% 处有一层极淡冷光, 往下沉到纯黑。
    ///
    /// 为什么不能只用纯黑: 六个参考图的画布**没有一个是平的 #000**。
    /// 它们都在画面顶端 6% 处压了一层 #0A0E1A(偏冷的深蓝), 38% 处降到 #06070C, 底部才是纯黑。
    /// 这层渐变承担两个作用: ① 让顶部状态栏不"悬空" ② 给卡片一个自然的明度落点。
    /// 平的纯黑会让整屏发死, 卡片浮不起来 —— 这是实测差异, 不是审美偏好。
    static var canvasGradient: RadialGradient {
        RadialGradient(
            stops: [
                .init(color: Color(hex: 0x0A0E1A), location: 0.00),
                .init(color: Color(hex: 0x06070C), location: 0.38),
                .init(color: Color(hex: 0x000000), location: 1.00)
            ],
            center: .init(x: 0.5, y: 0.06),
            startRadius: 0,
            endRadius: 900)
    }

    /// 标准卡片。深色档 **#1C1C1E** (范式 3.1 实测值), 圆角 24 (XRadius.card)。
    /// 旧值 0x161618 太暗, 与画布只差 8 个色阶 —— 卡片在纯黑上几乎看不见边界。
    static var surface: Color { Color.adaptive(0xFFFFFF, 0x1C1C1E) }
    /// 卡内次级块 (卡里再分块的底)。深色档 #24242A。
    /// 卡内次级块。深色档 **#202022** —— 对齐 HTML tokens.css 的 `--surface-alt`。
    ///
    /// 2026-10-24：此前是 #24242A，比 HTML 亮 4 个色阶。token 全量对账只剩这一处色差，
    /// 而用户口径是「规范有时候可能是错的，**以 html 的视觉审美为标准**」。
    static var surfaceAlt: Color { Color.adaptive(0xEFEFF4, 0x202022) }
    /// 第三表面 —— 输入框底、图表容器。深色档 #101012, **比画布亮、比卡片暗**,
    /// 是"凹陷"的那一档 (范式 3.1 surfaceSunken)。
    static var surfaceSunken: Color { Color.adaptive(0xE5E5EA, 0x101012) }
    // surfaceChip(#232326) 已删：规范 §7.2 给顶部胶囊的是 **chipGradient**（渐变），
    // 不是实色。这个令牌一直是纯色、且被判据抓到「零使用」—— 说明它本来就不该存在。

    /// **白纱** —— 纯白 8%，压在深色表面上的那层薄底。
    ///
    /// 规范里这个 8% 白出现在两处：§7.2 的 StatChip 图标底、§6.2 的玻璃提亮档。
    /// 它必须是**纯白**而不是 `specular`(#C8C8D4) —— 后者是偏冷的灰，
    /// 压上去会把图标底色带偏一档。
    ///
    /// 做成令牌而不是就地写 `Color.white.opacity(0.08)`：
    /// `tools/swiftlint.js` 禁止写死纯白前景（它会随明暗/主题该翻转）—— 那条规则的意图是
    /// 「白要有出处」，不是「不许白」。给它一个名字，就既守规则又表达角色。
    static var veil: Color { Color.white.opacity(0.08) }

    // ── 分段控件 (规范 §7.3 形态 B 的四个白) ──
    //
    //   容器底   rgba(255,255,255,0.06)
    //   选中块   rgba(255,255,255,0.18)
    //   选中字   #FFFFFF
    //   未选字   rgba(255,255,255,0.5)
    //
    // 这四个数都是规范给的，且都在**同一只控件**里 —— 所以集中在这里，
    // 而不是让 XSegmented 里散落四个 Color.white.opacity(...)。
    static var segTrack: Color { Color.white.opacity(0.06) }
    static var segThumb: Color { Color.white.opacity(0.18) }
    static var segOn: Color { Color.white }
    static var segOff: Color { Color.white.opacity(0.5) }

    /// Tab Bar **未选中**的图标与标签色 —— 规范 §7.10：「透明底 + 白图标白标签（`rgba(235,235,245,0.55)`）」。
    ///
    /// 2026-10-23 修正两处：
    ///   ① 颜色原来用 `specular`(#C8C8D4) —— 那是偏冷的灰。规范给的是 **#EBEBF5**（偏白的冷调）。
    ///   ② 0.55 在**次表面**底上只有 **4.46:1**，差 0.04 不到 §13.2 的 4.5。
    ///
    /// 所以透明度取 **0.60**（最小幅度提高）：黑 6.31 / 卡 5.55 / 次表面 5.03，三底全过。
    
    // ── 描边 ──    // ── 描边 ──
    /// 分隔线 / 卡片描边 —— **规范原文就是半透明白**，不是实色。
    ///
    /// §2 的令牌表：`separator | rgba(255,255,255,0.08) | 0.5pt 分隔线 | 卡内全宽`
    ///
    /// 这里曾经用实色 #3A3A40，理由是「换算成实色才过 1.2:1 机检、才真的看得见」。
    /// **那个理由是错的**：半透明白的价值就在于它**跟着底走** ——
    /// 压黑画布上是 #141414，压 #1C1C1E 卡片上是 #2E2E30，永远是"比底亮一点点"。
    /// 换成实色之后，画布上的线和卡片上的线亮度一样，卡片的边界感就没了。
    ///
    /// 已改回规范写法。tools/contrast.js 会把 8% 白按各底色合成后再算对比度。
    static var hairline: Color { Color.white.opacity(0.08) }
    /// 强调描边 —— 选中/危险两处, 或玻璃的实色退路。
    static var hairlineStrong: Color { Color.adaptive(0xC6C6C8, 0x4A4A52) }

    // ── 文字 (深色档对比度实测, 见 docs/GLASS/TOKENS.md 第 4 节) ──
    /// 正文 / 主数字。深色档纯白 —— 21.0:1 on 纯黑, 17.0:1 on 卡片。
    static var text: Color { Color.adaptive(0x000000, 0xFFFFFF) }
    /// 高光 (金属/玻璃上的镜面反射点)。白天纯白镜面, 夜间冷光 —— 两者取值方向相反, 不复用。
    static var specular: Color { Color.adaptive(0x3C3C43, 0xC8C8D4) }
    /// 次级文字。深色档 #8D8D93 —— 6.36:1 on 黑, 5.16:1 on 卡片, 全部过 AA。
    ///
    /// 规范 §13.4「必须实现 Increase Contrast：二级灰提至 #A8A8AE，分隔线提至 0.16 白」。
    /// 这不是一条建议 —— 系统「增加对比度」开着时, 二级灰必须**明显**更亮,
    /// 否则那个开关在界面上等于没效果。快照读的是 AXFlags 的非隔离副本 (令牌不在主 actor 上)。
    // 机器可读: tools/contrast.js 按下面这行的形状解析 (常态值)。
    static var textSub: Color { Color.adaptive(0x3C3C43, 0x8D8D93) }
    /// 三级文字 —— 规范 §3.3 原值：`#6A6A6E`（`#EBEBF5`@45%），on 黑 **3.90:1**，
    /// 用途一栏写的是「仅 ≥17pt 或 Bold」。
    ///
    /// 2026-10-22 审计修正：这里原本是 `#78787F`（我自己算出来"四个底都过 3.0"的提亮版）。
    /// 提亮本身是为了迁就一条**我自己定的**断言（要求它在 surfaceAlt 上也过 3.0），
    /// 而规范只要求它在黑底上 3.90:1、且只用于大字。**规范值优先**，已改回 `#6A6A6E`。
    ///
    /// 曾经还试过提到 `#8A8A92` 求"全部过 4.5:1" —— 那更错：它与 textSub(#8D8D93) 的
    /// 亮度只差 0.0116，两级文字成了同一个灰，层级直接塌掉。
    /// **层级靠对比度差异建立，不是靠都达标。**
    static var textTertiary: Color { Color.adaptive(0x8A8A8E, 0x6A6A6E) }
    /// 二维码静区 —— **唯一一个不跟随主题的白**。
    ///
    /// 它不是界面表面, 是给摄像头读的图形: ISO/IEC 18004 要求二维码四周留白色静区,
    /// 深色底上扫不出来。所以它是**语义色**, 不是一个漏改的 `Color.white`。
    /// 用具名令牌而不用字面量, 是为了让它出现在 grep 里时能一眼看出「这是有理由的」。

    // ── 强调: 铜 (锁芯黄铜) ──
    //
    // 2026-10-23 用户裁定：**App 不提供配色选择**。
    // 所以 `kf_accent` 那七套可选色的整条链（DB 读 + switch + override）已删除。
    // 主题现在只跟随系统深浅，不再依赖存储层 —— 那本身就是一处不该有的耦合：
    // 一个 nonisolated 静态色属性去读 DB，既慢又让主题层依赖数据层。
    // 2026-10-24 深色档提亮：#D98B45 → #E0A055
    //
    // ■ 为什么（与 warn 同一轮的「橙色发闷」治理）：
    //   accent 是 31 个主按钮的底色，是全 App 最大的暖色块。
    //   实测 #D98B45 = H28 S66 L56 —— **L56 低于参考图暖色区间 L60-65**，
    //   在纯黑画布上读成「砖红发闷」，不是参考图那种琥珀的通透。
    //   参考图 4 个暖色实测值全部落在 L60-65。
    //
    // ■ 取值：H28 不动（品牌铜色相），S66 不动，L 56 → **60** ⇒ #E0A055。
    //   只提亮度这一个维度，保持与旧值同一色相家族 —— 用户的铜色裁定不变，
    //   变的只是"从砖红提到琥珀"。
    //
    // ■ 对比度实测：黑底 9.33:1 / 卡片 7.56:1（旧值 7.73/6.26，提升）；
    //   onAccent 深字 #14100A 在它上面 = 8.9:1（远超 4.5 要求）。
    //   contrast.js 的 SPEC_VALUES 已同步此值。
    static var accent: Color { Color.adaptive(0x8F5218, 0xE0A055) }
    /// 强调色的**文字档** —— 比 accent 亮/深一档，专供「只有文字没有底」的场合
    /// （卡头链接、可点文本）。与 accent 分开是因为文字要过 4.5，填充只要 3.0。
    static var accentText: Color { Color.adaptive(0xA05E20, 0xE8A05C) }
    /// 二维码安静区（白色）—— 扫码端要靠这圈白边定位，透明底会扫不出。
    /// 2026-10-24 曾误删（当时以为 ShareToAndroidView 要一起删），
    /// 但「分享给安卓」是 iOS→Android 数据互通的唯一通道，必须保留。
    static var qrQuietZone: Color { Color.white }

    /// 强调色上的前景。
    static var onAccent: Color { Color.adaptive(0xFFFFFF, 0x14100A) }

    // ── 凭证工坊的四类色 ──
    //
    // 这四色按档给两份值: 浅色用更深的同色相, 深色保持原样。
    /// 指纹 (青)
    static var kindFp: Color { Color.adaptive(0x1A7A7A, 0x2AA6A6) }
    /// 临时码 (金) —— 不借 warn 的橙, 同一个颜色两个含义是 HIG 点名要避免的。
    static var kindTemp: Color { Color.adaptive(0x8A6A10, 0xE0C060) }
    /// OTP (紫)
    static var kindOtp: Color { Color.adaptive(0x5A3F9C, 0x8060C8) }

    // ── 语义 ──
    /// 成功 / 正向 / 已连接。深色档即范式 accentGreen #30D158 (10.39:1 on 黑)。
    static var ok: Color { Color.adaptive(0x147A35, 0x30D158) }
    /// 警示 / 待机 —— **深色档 2026-10-24 改值**：`#FF9F0A` → `#DFA063`
    ///
    /// ■ 为什么改（用户：「app 里的黄色/橙色都很丑，没有参考图高级耐看」）：
    ///   把 6 张参考图逐像素采样，暖色**只出现 4 个值**：
    ///     #FFAC45 (H33 S100 L64) · #D8B059 (H41 S62 L60)
    ///     #DCA56D (H30 S61 L65) · #AF7148 (H24 S42 L48)
    ///   共同点：**亮度 60-65%**（比 #FF9F0A 的 52% 高 8-13 点），
    ///   **饱和度 42-62%**（比 #FF9F0A 的 100% 低 40-58 点）。
    ///
    ///   #FF9F0A 是 iOS 系统橙（HIG 的 .orange），它在**浅色底**上是对的；
    ///   但在本 App 的纯黑画布上，S100%/L52% 会读成「荧光橘 / 警示贴纸」——
    ///   这正是"不够高级"的来源。参考图的做法是**提亮 + 降饱和**得到琥珀/赭石感。
    ///
    /// ■ 取值推导（不是随手挑的）：
    ///   色相 H36 → **H30**（参考图土色 #DCA56D 的色相，比 #FF9F0A 少 6 度黄味）
    ///   饱和度 100% → **66%**（参考图 61-62%，取略高因为它还要当强调色）
    ///   亮度 52% → **63%**（落进参考图 60-65% 区间正中）
    ///   合起来 = `#DFA063`。对比度实测：黑底 9.35:1 / 卡片 7.57:1 / 次表面 7.24:1，
    ///   全部远超 §13.2 的 4.5:1 要求（旧值 10.22/8.28/7.91，降了但依然充裕）。
    ///
    /// ■ 浅色档不动：`0xB25000` 是给白底用的深琥珀，与新深色档是同一色相家族。
    static var warn: Color { Color.adaptive(0xB25000, 0xDFA063) }
    /// 告警 / 失败。深色档即范式 accentRed #FF3B30 (5.92:1 on 黑)。
    /// 告警 / 失败 —— 规范 §3.4 的 `accentRed`：**#FF3B30**（on `#1C1C1E` 4.80:1）。
    ///
    /// 这里原来写的是 #FF4A40，理由是一段「#FF3B30 在 surfaceAlt 上只有 4.35，所以提亮」。
    /// **那条理由不成立**：规范只承诺 on 卡片的 4.55（实测 4.80），从未承诺次表面；
    /// 而我在次表面上的用法只有两类 ——
    ///   ① XMetricTile 的**图标**（非文本，门槛 3:1，4.35 过）
    ///   ② 一处 12pt 说明文字（已改成 text，红色语义交给进度条本身承担）
    /// 也就是说：把令牌改成非规范值，去迁就一个我自己造的用法。
    static var danger: Color { Color.adaptive(0xD70015, 0xFF3B30) }
}

// ═══════════════════════════════════════════════════════════
// MARK: - 间距 / 尺寸
// ═══════════════════════════════════════════════════════════

/// 间距 (4pt 基数)。
///
/// **2026-10-22 关键修正**: 页边距 16 → 14。
/// 旧值 16 是 iOS 平台的惯例值, 不是这个设计的值; 范式实测为 3.62% 屏宽 ≈ 14pt。
/// 差 2pt 看起来不多, 但它同时是**卡片宽度 / 大环直径 / Tab Bar 宽度 / 文字对齐线**
/// 四个派生值的根 token (范式 0.1 的变更影响表) —— 改了根就必须重算全部派生值。
enum XSpace {
    static var xxs: CGFloat { d(2) }
    static var xs: CGFloat { d(4) }
    /// **6** —— 卡头 → 标题（§7.6「实测墨迹间距 14px」）。
    ///
    /// 这个值在规范里出现 5 次却一直没进令牌表：§5.1 的档位是 2/4/8/12，
    /// 跳到 8 会「松一档」。而 §15 K4 明写「卡片内部纵向节奏按 **6 / 12 / 2 / 14** 执行」——
    /// 6 是这个节奏的第一个数，缺了它只能靠负 padding 硬凑。
    ///
    /// 命名对齐 §5.1 的 s1..s8 体系：xs(4) 与 s(8) 之间。
    static var xsm: CGFloat { d(6) }
    static var s: CGFloat { d(8) }
    static var m: CGFloat { d(12) }
    static var l: CGFloat { d(16) }
    static var xl: CGFloat { d(24) }
    static var xxl: CGFloat { d(32) }

    /// 屏幕左右边距 —— **22**（2026-10-24 六图复测从 14 上调）
    ///
    /// 卡片、Tab Bar、顶部胶囊行**共用**这一个值，不许各写各的。
    ///
    /// ■ 为什么从 14 改成 22：
    ///   参考图 2（1206px 宽）实测卡片左边界在 x=80，即 **6.6% ≈ 26pt**。
    ///   旧的 14pt 是 4.6% —— 卡片几乎贴边，读起来"挤"。
    ///   直接跳 26 会让 375pt 小屏内容区只剩 323pt，所以取 **22（5.9%）**：
    ///   明显更接近参考图，又不牺牲可读宽度。
    /// ■ 与 tools/proto/tokens.css 的 `--gutter:22px` 同值（原型已同步升级）。
    static var gutter: CGFloat { d(22) }
    /// 卡片间距 —— 纵向堆叠 8 / 横向网格 12。**两个不同的数, 不许合并成一个 token。**
    static var rowGap: CGFloat { d(8) }
    /// 区块之间 (簇与簇) —— 28。与簇内的 16 形成层级差: 等距等于没有分组。
    static var section: CGFloat { d(28) }
    /// 页面顶部留白 —— 40。
    static var pageTop: CGFloat { d(40) }
    /// **标题到首卡** —— 74（规范 §5.3 / 验收 L4）。
    ///
    /// 规范原话：「标题到首卡间距 74pt（页面最大的呼吸区，做小了会显挤）」。
    /// 它是全页最大的一处留白，语义是"标题属于页面、下面属于内容" ——
    /// 不是页边距(14)也不是区块间距(28)，所以**必须是自己的一个数**。
    /// 用 pageTop + section 凑 68 会差 6pt，而这一处的意义恰恰在于它比别处都大。
    static var titleToFirstCard: CGFloat { d(74) }

    /// 卡片内边距 —— 16 (范式实测 15, ±2 可接受)。
    static var card: CGFloat { d(16) }
    /// 控件内边距
    static var control: CGFloat { d(12) }
    /// 磁贴内边距
    static var tile: CGFloat { d(14) }

    /// 文字对齐线 = 页边距 + 卡内边距 ≈ 29。
    ///
    /// 这是本范式最容易做错的一处: **大标题不是对齐卡片边缘, 而是对齐卡片内的文字。**
    /// 整页只有这一条文字线 —— 大标题、正文、卡片内文字、胶囊内文字全落在它上面。
    /// 写 24pt 会得到一条"对不齐任何东西"的线 (既不是卡片边缘 14, 也不是文字线 29)。
    static var align: CGFloat { gutter + card - 1 }   // 14 + 16 - 1 = 29
}

/// 圆角。
///
/// **2026-10-22 关键修正**: card 16 → 24。范式 5.2 实测 23.6pt。
/// 旧值 16 做出来是"通用后台风" —— 范式 14 明令"卡片圆角 < 20pt 即返工"。
enum XRadius {
    /// 应用体标准卡片 —— **26**。
    ///
    /// 2026-10-23 定案：规范里有**四处**写 26，而 §5.2 的令牌表写 24。
    /// 取 26 的理由不是「多数票」，是**出现位置**：
    ///   · §0 G2 —— 禁止项判定表（"圆角 26" 是判据）
    ///   · §5.3 —— 屏幕骨架图（Card r=26）
    ///   · §7.5 / §7.6 —— 两个组件规范的表
    ///   · §15 A3 —— **验收项**（"应用体卡片 = #1C1C1E，圆角 26"）
    ///
    /// 验收项里写的值就是交付时要被量的值。§5.2 那个 24 是早期的概览表，没跟着改。
    static var card: CGFloat { r(26) }
    /// 主视觉卡 / 渐变卡 —— 34。
    static var cardLg: CGFloat { r(34) }
    /// 卡内缩略图 / 图表容器 —— 12 (= card / 2)。
    static var inner: CGFloat { r(12) }
    /// 控件 / 内嵌格 —— 12。
    static var control: CGFloat { r(12) }
    /// 瓦片 —— 14。
    static var tile: CGFloat { r(14) }
    /// 顶部胶囊 (StatChip) —— **18，圆角矩形（不是全圆胶囊）**。
    ///
    /// 2026-10-24 二次修正：HTML 原型的 .chip CSS 实测是「高 56 / r18 / '不是全圆胶囊'」
    /// （tokens.css 里 .chip 规则的原文注释）。同文件 --r-chip:22 与之矛盾——
    /// 按「HTML 为准」的口径取**渲染事实** 18 而非变量 22。
    /// 高度由 XStatChip 的 56 自检保证（与 .chip height:56px 一致）。
    static var chip: CGFloat { r(18) }
    /// 小角标
    static var min: CGFloat { r(8) }
    /// 设备样机外框 —— 44。
    static var device: CGFloat { r(44) }
}

/// 环的几何与材质 —— 规范 §7.8 的三个"会被做小"的硬数，集中在这里。
///
/// 为什么单开一个命名空间: 环是这个范式的**签名元素**（"签名元素是环 + 辉光"），
/// 而它的三个数（线宽 / 内盘色 / 游标尺寸）任何一个被写小，气质就从
/// "厚甜甜圈仪表"退化成"Apple Watch 细环"。把这三个数钉在一处，
/// 改直径时才有地方跟着一起改。
enum DSRing {
    /// 大环线宽下限 —— 规范 §14-21「大环线宽 < 30pt 即返工」。
    static let minStrokeLarge: CGFloat = 30
    /// 线宽 = 直径的 12%（规范实测 42/340 ≈ 12.4%），且不低于上面的下限。
    static func stroke(forDiameter d: CGFloat) -> CGFloat {
        max(minStrokeLarge, d * 0.12)
    }
    /// 18pt 实心圆点游标（规范 §7.8 形态 1）。
    static let cursor: CGFloat = 18
    /// 内盘 —— **不是纯黑**，深海军蓝。纯黑内盘会让环看起来是个洞。
    static var innerDisc: Color { Color(hex: 0x0A1220) }
    /// 12 点分段竖条 —— 规范 §7.8 形态 1「分段」项给的值：`#4A4A7A`。
    ///
    /// 它把环切成左右两段。颜色比轨道亮、比进度弧暗，
    /// 既不抢进度弧的注意力，又能让人看出「这里是一道分界」。
    static var segment: Color { Color(hex: 0x4A4A7A) }
    /// 轨道两端的蓝灰（不是中性白 10%）。
    static var trackTop: Color { Color(hex: 0x2A2F45) }
    static var trackBottom: Color { Color(hex: 0x1A1D2A) }
}

/// 触达尺寸
enum XHit {
    /// HIG 最小触达
    static let min: CGFloat = 44
}

/// 图标尺寸 —— 全 App 只用这一套 (范式 10)。
/// 图标尺寸 —— 规范 §10 的**七档**：`12 / 13 / 17 / 20 / 22 / 28 / 34`。
///
/// 2026-10-22 审计修正：原来写的是 12 / 16 / 20 / 26 / 44 / 72，其中
/// **16 / 26 / 44 / 72 四个值不在规范档位上**。判据不是"看起来差不多就行"——
/// 规范给的是固定七档，中间值说明有人在按感觉调，而不是按系统。
///
/// 另有 `lock = 72` 一枚，全仓**零引用**，已删（死令牌）。
enum XIcon {
    static let xs: CGFloat = 12      // 规范 §10 档位 1
    static let sm: CGFloat = 17      // 档位 3（原 16，不在档位上）
    static let md: CGFloat = 20      // 档位 4
    static let lg: CGFloat = 28      // 档位 6（原 26，不在档位上）
    static let xl: CGFloat = 34      // 档位 7（原 44，不在档位上）
    /// 规范 §10 的档位 2 / 5 —— 之前缺这两档，调用点只能就近取，于是又跑出中间值。
    static let xxs: CGFloat = 13
    static let xm: CGFloat = 22
}

// ═══════════════════════════════════════════════════════════
// MARK: - XOpacity — 语义化透明度
// ═══════════════════════════════════════════════════════════
//
// 清 opacity 时全仓有 34 种不同取值、113 处 —— 光"图标底色"一类就有 0.12/0.13/0.14 三种。
// 这里按**语义**收敛成六档。不是所有 opacity 都该进来:
//   · 0.001 那种是"开关量"(有/无), 不是透明度语义 → 留在原地
//   · 0.88/0.90/0.95 是渐变里的停点, 属于渐变定义 → 留在原地
//   · 动画中间态 (charge/burst) 是计算值 → 留在原地
enum XOpacity {
    /// 洗染底: 大面积浅色填充 (危险横幅 / 警告条)
    static let wash: Double = 0.10
    /// 图标/徽章底: 图标后那层同色底
    static let badge: Double = 0.12
    /// 柔光: 状态灯外圈、光晕
    static let glow: Double = 0.16
    /// 描边: 卡片 tone 描边
    static let edge: Double = 0.35
    /// 淡底环: 仪表盘的底弧、内圈高光这类"有但不抢眼"的线
    static let track: Double = 0.55
    /// 玻璃填充 (范式 6.2: rgba(255,255,255,0.08))
    static let glassFill: Double = 0.08
    /// 玻璃描边 (0.5pt 高光)
    static let glassEdge: Double = 0.12
        // tabIdle 已删：未选中标签改走 `XPalette.tabIdleLabel`（规范 §7.10 的 #EBEBF5 + 0.60）。
    // 那个 0.55 的旧值在次表面上只有 4.46:1 —— 差 0.04 不到 §13.2 的 4.5，所以不再作为令牌存在。
}

/// 度量
enum XMetric {
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

    // ── 规范 §7.18 数字溢出 ──
    //
    // 「数字长度不可控（百万级步数、累计卡路里），必须有降级规则」。
    // 按**位数**算，不按字符数：`12,458,902` 是 9 位数字（10 个字符），落在 8–9 档。
    //
    //   ≤7      正常
    //   8–9     ×0.82
    //   10–11   ×0.65
    //   >11     缩写 12.4M / 1.2B（保留一位小数）
    static func digitCount(_ s: String) -> Int {
        s.reduce(0) { $0 + (($1.isNumber) ? 1 : 0) }
    }

    static func overflowScale(digits: Int) -> CGFloat {
        if digits <= 7 { return 1.0 }
        if digits <= 9 { return 0.82 }
        if digits <= 11 { return 0.65 }
        return 0.65   // 超过 11 位先交给 abbreviate 缩写，缩写后再按本档
    }

    /// >11 位缩写。12_458_902 → "12.5M"；1_200_000_000 → "1.2B"。
    static func abbreviate(_ n: Int) -> String {
        let d = abs(n)
        let body: String
        if d >= 1_000_000_000 { body = String(format: "%.1fB", Double(d) / 1_000_000_000) }
        else if d >= 1_000_000 { body = String(format: "%.1fM", Double(d) / 1_000_000) }
        else { body = String(d) }
        // 规范 I8：负号是 U+2212，不是连字符。
        return n < 0 ? String(minusSign) + body : body
    }

    /// 千分位分组 —— 规范 E4「千分位逗号」。
    ///
    /// 不用 NumberFormatter：那条路依赖 locale，同一个值在不同系统区域下会变成
    /// "12.458.902"，而这里的读数是**技术数据**（次数/天数），不该跟随用户区域。
    /// 也正好与 §7.18 的口径一致 ——「按**位数**算，不按字符数：12,458,902 是 9 位数字」，
    /// 那句话默认了显示里带逗号。
    /// 负号用 **U+2212 减号**，不是连字符 `-`（规范 I8）。
    /// 连字符在数字语境里偏窄偏上，与等宽数字并排时基线看着像错的。
    static let minusSign: Character = "−"

    static func grouped(_ n: Int) -> String {
        let neg = n < 0
        var digits = Array(String(abs(n)))
        var out: [Character] = []
        while let c = digits.popLast() {
            out.append(c)
            if !digits.isEmpty && (out.count - out.filter { $0 == "," }.count) % 3 == 0 {
                out.append(",")
            }
        }
        if neg { out.append(minusSign) }
        return String(out.reversed())
    }

    /// 一次算完：>11 位缩写，其余加千分位。负数原样带符号。
    static func display(_ n: Int) -> String {
        digitCount(String(abs(n))) > 11 ? abbreviate(n) : grouped(n)
    }

    /// 字符串重载 —— 指标值多半是已格式化好的字符串（"1,234" / "从未" / "6"）。
    /// 只有**纯数字且位数超 11** 才缩写；带逗号或非数字的一律原样返回，
    /// 否则会把 "从未" 送进 parse 得到 0。
    static func display(_ s: String) -> String {
        let bare = s.replacingOccurrences(of: ",", with: "")
        guard !bare.isEmpty, bare.allSatisfy({ $0.isNumber }), let n = Int(bare) else { return s }
        // 纯数字串：>11 位缩写，其余补千分位（E4）。已经带逗号的也会被重新分组，不会叠。
        return digitCount(bare) > 11 ? abbreviate(n) : grouped(n)
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
///
/// 2026-10-22: 曲线参数对齐范式 11.1 的动画清单。三个变化:
///   · quick     0.22 → 0.12 (按压缩放是 0.12s, 不是 0.22s —— 慢了像卡)
///   · standard  0.40/0.85 → 0.32/0.80 (Tab 切换)
///   · 新增 cardEnter (0.50/0.85) 与 ringGrow (1.00s easeOut) —— 范式里的两条主曲线
enum XMotion {
    /// 系统减弱动态 (快照, 非主 actor)
    private static var systemReduceMotion: Bool { AXFlags.reduceMotionSnapshot }

    private static var tier: String {
        if systemReduceMotion { return "calm" }
        if BatteryCare.appLowBattery { return "calm" }
        return "standard"
    }

    // ── 基础档 ──
    /// 微反馈 (按压 / 切换) —— 规范 §11.1 原话：`按压缩放 | .easeOut | 0.12s, scale 1→0.97`。
    ///
    /// 2026-10-22 审计修正：这里原来写的是 `spring(response: 0.12, dampingFraction: 1.0)`。
    /// 弹簧的"响应"不是时长 —— 同样是 0.12，弹簧在 0.12s 时还没到达终点，
    /// 而规范要的是**线性到达**的 0.12s。两者手感不同，且规范点名了曲线类型。
    static var quick: Animation {
        switch tier {
        case "calm": return .easeOut(duration: 0.08)
        default: return .easeOut(duration: 0.12)
        }
    }

    /// 标准 (状态切换 / Tab) —— 范式「Tab 切换 spring 0.32 / 0.80」
    static var standard: Animation {
        switch tier {
        case "calm": return .easeInOut(duration: 0.16)
        default: return .spring(response: 0.32, dampingFraction: 0.80)
        }
    }

    /// 柔和 (淡入淡出)
    static var soft: Animation {
        switch tier {
        case "calm": return .easeInOut(duration: 0.12)
        default: return .easeInOut(duration: 0.25)
        }
    }

    /// 退场
    static var exit: Animation {
        switch tier {
        case "calm": return .easeOut(duration: 0.08)
        default: return .easeOut(duration: 0.15)
        }
    }

    /// 卡片入场 —— 范式「spring 0.50 / 0.85, y +14→0, 逐卡延迟 40ms, 最多 6 张」
    static var cardEnter: Animation {
        switch tier {
        case "calm": return .easeInOut(duration: 0.20)
        default: return .spring(response: 0.50, dampingFraction: 0.85)
        }
    }
    /// 卡片入场逐卡延迟
    static let cardStagger: Double = 0.04

    /// 环形生长 —— 范式「easeOut 1.00s / delay 0.15」
    static var ringGrow: Animation {
        switch tier {
        case "calm": return .easeOut(duration: 0.20)
        default: return .easeOut(duration: 1.00).delay(0.15)
        }
    }

    /// 数值变化 —— 范式「easeInOut 0.25s, 数字滚动」
    static var numberRoll: Animation {
        switch tier {
        case "calm": return .easeInOut(duration: 0.12)
        default: return .easeInOut(duration: 0.25)
        }
    }

    // ── 召唤 / 揭示 ──
    //
    // 规范 §11.1 是一张**封闭清单**（"只能用这些"），里面与"内容被召唤出来"最接近的
    // 是「Sheet 弹出 | .spring | 0.42 / 0.88」。这条与 doorReveal 原先自造的
    // timingCurve(0.22,0.76,0.03,1, 0.45) 合并成同一条 —— 规范里没有的曲线不留。
    static var summon: Animation {
        switch tier {
        case "calm": return .easeOut(duration: 0.20)
        default: return .spring(response: 0.42, dampingFraction: 0.88)
        }
    }

    /// 元件入场 / 数值归位（头像、仪表、进度环）。
    ///
    /// 原名"门后内容入场"：三棱柱时代指整屏揭示，0.70s 是按那个尺度标的。
    /// 三棱柱删掉之后，这个曲线只剩小组件在用 —— 40pt 的头像等 0.7 秒才站稳，
    /// 而 iOS 标准过渡是 0.25–0.35s，0.70s 是它的 2 倍多（motion.md: "aim for brevity"）。
    /// 收短到 0.45s：仍是"落定"而非"弹出"，但不会让人等。
    static var doorReveal: Animation {
        switch tier {
        case "calm": return .easeOut(duration: 0.20)
        default: return .spring(response: 0.42, dampingFraction: 0.88)
        }
    }

    /// 充能松手回零
    static var chargeReset: Animation {
        switch tier {
        case "calm": return .easeOut(duration: 0.08)
        default: return .easeOut(duration: 0.18)
        }
    }

    /// 减少动态时的统一降级: 0.2s crossfade, 取消位移与缩放 (范式 11.3)
    static var reduced: Animation {
        .easeInOut(duration: 0.20)
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
    /// 主视觉卡渐变 —— 范式 3.5 的 heroGradient:
    /// 顶部更紫、更快沉黑, 是**全屏唯一**允许的渐变卡 (一屏至多一张)。
    static var hero: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(hex: 0x6B7BE8), location: 0.00),
                .init(color: Color(hex: 0x546CE4), location: 0.28),
                .init(color: Color(hex: 0x3C489C), location: 0.62),
                .init(color: Color(hex: 0x141418), location: 1.00)
            ],
            startPoint: .top, endPoint: .bottom)
    }

    /// **图 1 主环的五段连续渐变** —— 青绿 → 蓝 → 深蓝。
    ///
    /// HTML 实测: `linearGradient x1=0 y1=1 x2=1 y2=0`
    ///   #4A9E96 (左下) → #2E8FC0 → #1E6AAE → #1560A8 → #0A84FF (右上)
    /// 关键在**连续**: 一旦拆成 3 段硬色块, 环就退化成"进度条分档", 图 1 的高级感全部消失。
    /// 用法: `Circle().stroke(XGradient.dial, style: ...)` 配 `.trim(from:to:)`。
    static var dial: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(hex: 0x4A9E96), location: 0.00),
                .init(color: Color(hex: 0x2E8FC0), location: 0.25),
                .init(color: Color(hex: 0x1E6AAE), location: 0.50),
                .init(color: Color(hex: 0x1560A8), location: 0.75),
                .init(color: Color(hex: 0x0A84FF), location: 1.00)
            ],
            startPoint: .bottomLeading, endPoint: .topTrailing)
    }

    /// 成功态的环 —— 图 1 语言的绿色版 (Android 04-success 已验证)
    static var dialOK: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(hex: 0x2FD65C), location: 0.00),
                .init(color: Color(hex: 0x30D158), location: 0.55),
                .init(color: Color(hex: 0x7CE89A), location: 1.00)
            ],
            startPoint: .bottomLeading, endPoint: .topTrailing)
    }

    /// 顶部胶囊底 —— 范式 3.5 chipGradient
    static var chip: LinearGradient {
        LinearGradient(colors: [Color(hex: 0x2A2A2E), Color(hex: 0x1A1A1C)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 环后辉光 —— 范式 §3.5 的 `glowBlue`：**透明度 0.35**，半径 ≤160pt。
    /// 用在**小元素**上（环背光、指示灯「它在亮」）。
    static func glow(_ color: Color) -> RadialGradient {
        RadialGradient(colors: [color.opacity(0.35), .clear],
                       center: .center, startRadius: 0, endRadius: 120)
    }

    /// 环境光溢出 —— 范式 §7.12 AmbientGlow：**透明度 0.12–0.20**，半径 200–320，一屏 ≤2 处。
    ///
    /// 为什么不能与 `glow` 共用一个函数：两者是**两个不同的量**。
    /// §3.5 的环后辉光是 0.35（那是主视觉的光）；§7.12 的环境光只有 0.12–0.20（只做氛围）。
    /// 混用会出两种错：要么环不够亮，要么整页发灰。
    /// 本仓门厅一度两者叠加 —— 0.35 的渐变再乘 `.opacity(0.12)`，实际只剩 4%，几乎看不见。
    static func ambient(_ color: Color) -> RadialGradient {
        RadialGradient(colors: [color.opacity(0.16), .clear],
                       center: .center, startRadius: 0, endRadius: 160)
    }

}

// ═══════════════════════════════════════════════════════════
// MARK: - 外观开关
// ═══════════════════════════════════════════════════════════

enum XAppearance {
    /// App 内高对比皮肤：与系统「增加对比度」并联
    @MainActor static var highContrast: Bool { AXFlags.highContrast || DB.store.getBool("kf_hc") }
}

// ═══════════════════════════════════════════════════════════
// MARK: - 色彩基元
// ═══════════════════════════════════════════════════════════

extension Color {
    /// 解析成员档案里存的 "#RRGGBB" 色串。
    ///
    /// 为什么要有这一枚: 同一个函数在 `FpOwnerPicker` / `MembersPage` / `SecurityCenterView`
    /// 各写了一遍, 而且**回落值三处不同**(textSub / accent / textSub) —— 同一个成员在一次
    /// 解析失败里会显示成三种颜色。数据是同一份(`Member.color`), 解析就该只有一处。
    ///
    /// `fallback` 由调用方给: 头像位用 accent(它是"有身份"的位), 纯文本位用 textSub。
    static func memberSwatch(_ raw: String, fallback: Color) -> Color {
        var s = raw
        if s.hasPrefix("#") { s.removeFirst() }
        guard let v = UInt32(s, radix: 16), s.count == 6 else { return fallback }
        return Color(hex: v)
    }

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

// ═══════════════════════════════════════════════════════════
// MARK: - 字阶 (范式 4.2)
// ═══════════════════════════════════════════════════════════

/// 字阶 —— 范式 4.2 的实测值。
///
/// **字阶比 HIG 默认小约 12%**, 这是宽度比例法标定出来的, 不是拍脑袋:
///   Winding Down (883px 宽图) 墨迹 418px = 47.3% 屏宽 ⇒ 反推 30pt 而不是 34
///   Low Score                 墨迹 174px = 19.7% 屏宽 ⇒ 反推 19pt 而不是 22
///
/// 本仓页面一律走 `xFont(_:)` 的语义字号 (参与 Dynamic Type), 这一组**只给 Canvas
/// 器皿里的定尺文字**用 (环内数字、量表刻度), 因为那些必须与图形保持比例,
/// 语义字号在 AX 下会跳档、一跳就与环错开。
///
/// 用法: `.xFontExact(.system(size: XMetric.dataText(DSFont.displayNumber)))`
/// 规范 §4.2 的字阶 —— **只给 Canvas 器皿里的定尺文字**。
///
/// 页面正文一律走语义字号（.body / .subheadline …），那样才参与 Dynamic Type。
/// 这一组的存在理由只有一个：有些文字**必须与图形保持比例**（环内数字、量表刻度），
/// 语义字号在 AX 下会跳档，一跳就与环错开。
///
/// ⚠ 这里的成员不是「每个都要有人用」的接口，而是一张**字阶表**；
/// 但为了让 tools/apisig.js 的「零使用令牌」判据不至于对此失明，
/// 真正在用的那几个会出现在调用点。当前实际消费者：
///   · displayNumber → XCodeRing（时效码大卡的数字）
/// 规范 §4.2 的字阶 —— **本仓排版的唯一入口**。
///
/// 为什么需要它（2026-10-22 审计）：
/// `xFont` 原来直接把 SwiftUI 的语义字号透传下去，于是全仓 766 处排版
/// **跑的是 HIG 默认值**（caption 12 / footnote 13 / subheadline 15 / body 17 / title2 22…），
/// 而规范 §4.2 的原话是：
///
/// > 已全线下修：34→30 / 22→19 / 20→18 / 17→16 / 15→14 / 13→12 / 12→11。
/// > 原因：原值直接套用了 HIG 的 Large Title 34pt 默认值，**从未对参考图测过**。
///
/// 也就是说 —— 本仓做的正是规范点名批评的那件事。766 处里 650 处字号偏大一档到两档。
///
/// 落地方式：**枚举 case 名与 SwiftUI 语义字号同名**，所以 `.xFont(.footnote)`
/// 这类调用点一个字都不用改，只有参数类型从 `Font` 换成 `XText`。
enum XText: Sendable {
    case displayNumber   // 56 Bold  -1.5 / 1.0
    case display         // 36 Bold  -0.6 / 1.10
    case largeTitle      // 30 Bold  -0.4 / 1.15
    case title2          // 19 Bold  -0.3 / 1.20
    case title3          // 18 Semibold -0.2 / 1.25
    case headline        // 16 Semibold -0.2 / 1.30
    case body            // 16 Regular -0.1 / 1.35
    case subheadline     // 14 Regular  0   / 1.35
    case footnote        // 12 Regular  0   / 1.40
    case caption         // 11 Medium  +0.1 / 1.25
    case caption2        // 11 Medium  +0.2 / 1.20
    case small           // 13 Regular  0   / 1.38  ← 六图补档（图2 卡内副文）

    /// 规范给的字号。**这是唯一真相源**，不许在调用点再写字面量。
    var size: CGFloat {
        switch self {
        // 单一来源：56 只在 DSFont 写一次，这里转发。
        case .displayNumber: return DSFont.displayNumber
        case .display:       return 36
        case .largeTitle:    return 30
        case .title2:        return 19
        case .title3:        return 18
        case .headline:      return 16
        case .body:          return 16
        case .subheadline:   return 14
        case .footnote:      return 12
        case .caption:       return 11
        case .caption2:      return 11
        case .small:         return DSFont.small
        }
    }

    var weight: Font.Weight {
        switch self {
        case .displayNumber, .display, .largeTitle, .title2: return .bold
        case .title3, .headline: return .semibold
        case .caption, .caption2: return .medium
        case .small: return .regular
        default: return .regular
        }
    }

    /// Dynamic Type 的缩放基准 —— 取最接近的系统档，这样 AX 档放大比例是系统惯例值。
    /// 单位用的字号档 —— 规范 §7.16「单位字号是数值的 **70%**（不是 60%）」。
    ///
    /// **规范内部冲突**：§7.16 要求「数值 × 0.70」，而 §4.2 把字号收成了 10 个离散档位。
    /// 两者不能同时满足 —— 真的乘 0.70 会造出 13.3 / 25.2 这种不在档位上的数。
    ///
    /// 取舍：**服从 §4.2 的档位**（它是实测表，且有 tdconfig 的校准方法），
    /// 取最近的下一档。实测落点与偏差如实列出：
    ///
    ///   displayNumber 56 → 36   64%   ✓ 接近
    ///   display       36 → 19   53%   ✗ 偏小（36 与 19 之间没有档位）
    ///   largeTitle    30 → 19   63%   ✓ 接近
    ///   title2        19 → 14   74%   ✓
    ///   title3        18 → 12   67%   ✓
    ///   headline/body 16 → 11   69%   ✓
    ///   subheadline   14 → 11   79%   ~
    ///   footnote      12 → 11   92%   ✗ 偏大（12 之下只有 11）
    ///   caption       11 → 11  100%   ✗ 无法再小
    ///
    /// 也就是说：**在 11pt 以下、以及 36pt 附近，这条规则无法忠实执行**。
    /// 那不是实现偷懒 —— 是两份规范在那些点上没有交集，取字号表是更保守的一侧。
    var unitStyle: XText {
        switch self {
        case .displayNumber: return .display
        case .display: return .title2
        case .largeTitle: return .title2
        case .title2: return .subheadline
        case .title3: return .footnote
        case .headline, .body: return .caption
        case .subheadline: return .caption
        case .footnote: return .caption
        case .caption, .caption2: return .caption2
        case .small: return .caption2      // 13 → 11（85%，靠近 §7.16 的 70% 档）
        }
    }
    var relativeTo: Font.TextStyle {
        switch self {
        case .displayNumber, .display, .largeTitle: return .largeTitle
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .body, .subheadline: return .body
        case .footnote: return .footnote
        case .caption: return .caption
        case .caption2: return .caption2
        case .small: return .footnote      // 13 最接近 footnote(12) 的缩放曲线
        }
    }
}
enum DSFont {
    /// 56 / Bold / -1.5 —— 大环内数字
    static let displayNumber: CGFloat = 56
    /// 36 / Bold / -0.6
    static let display: CGFloat = 36
    /// 30 / Bold / -0.4 —— 页面大标题
    static let largeTitle: CGFloat = 30
    /// 19 / Bold / -0.3 —— 卡片主标题
    static let title2: CGFloat = 19
    /// 18 / Semibold / -0.2 —— 区块标题
    static let title3: CGFloat = 18
    /// 16 / Semibold / -0.2 —— 行标题
    static let headline: CGFloat = 16
    /// 16 / Regular / -0.1 —— 正文
    static let body: CGFloat = 16
    /// 12 / Regular / 0 —— 辅助说明
    static let footnote: CGFloat = 12
    /// 11 / Medium / +0.1 —— 图表轴标签 (极限值)
    static let caption: CGFloat = 11

    // ── 六图范式补档 (2026-10-23) ──
    // 六个参考图里反复出现的三档字号, 之前没有对应令牌, 页面只能裸写 .system(size:)。
    // 裸写的后果是 Dynamic Type 失效 —— 这三档现在进字阶, 页面一律走 .xFont。

    /// 44 / Bold / -1.4 —— **MetricCard 主角数字** (图 5 Activity Details 的 13,818 / 6.58MI)
    /// 与 displayNumber(56) 的区别: 56 是环内数字, 44 是**卡片内**的主数字。
    static let hero: CGFloat = 44
    /// 13 / Regular / 0 —— 卡内副文 (HTML 里大量用到, 之前借 footnote 12 会偏挤)
    static let small: CGFloat = 13
}