// 设计令牌 · 色板 / 自定义强调色 / 友好预设
// 2026-10-29 从 DesignSystem.swift（883 行）再拆出。
import SwiftUI

extension DS {
    enum Palette {
        // ---------- 机检基础令牌 (tools/contrast.js 解析 static let) ----------
        static let canvasBase  = Color.adaptive(0xF6F3EC, 0x121009)   // 页面底: v10 暖白 / 暖黑 (2026-10-18 两端都转暖)
        static let surfaceBase = Color.adaptive(0xFFFDF9, 0x1C1913)   // 卡片: 暖白 / 暖黑, 比页面底亮一档
        static let surfaceAltBase = Color.adaptive(0xF0ECE3, 0x252017) // 卡片内次级块: 暖灰 / 暖褐
        static let hairline   = Color.adaptive(0xDCD5C9, 0x38322A)   // 分隔线: 暖色 (浅 1.32:1 / 深 1.50:1 对画布)
        static let text       = Color.adaptive(0x17140F, 0xF7F3EA)   // 主文本
        static let textSub    = Color.adaptive(0x5C5245, 0xACA08D)   // 暖灰: 浅 6.90:1 / 深 7.40:1
        static let ok         = Color.adaptive(0x15803D, 0x4ADE80)   // 成功
        static let warn       = Color.adaptive(0xB45309, 0xFBBF24)   // 警告 4.5:1 / 高
        static let danger     = Color.adaptive(0xB91C1C, 0xF87171)   // 错误 6.0:1
        // 594 日型色带三档 (工作日/周末两枚在此, 节假日橙直接复用 warn): **固定语义色, 不随主题** ——
        // 这三档要的是"互相可辨"(哪天不是平常日), 而 accent 在极光/墨绿/琥珀主题里会撞青绿或橙档。
        static let dayKindWorkday = Color.adaptive(0x4F46E5, 0x818CF8)   // 工作日 靛蓝
        static let dayKindWeekend = Color.adaptive(0x0D9488, 0x2DD4BF)   // 周末 青绿
        // 压在三枚语义填充色 (ok/warn/danger) 上的文字与符号色。
        // 第八十三批为什么要新令牌而不是继续写 .white: 语义色是"浅色档深、深色档浅"的 (danger
        // 浅档 B91C1C / 深档 F87171), 纯白在浅档 6.47:1 合格, 到深档只剩 2.77:1 —— 角标数字直接读不出。
        // 与主题表的 onAccent 同一个道理: 浅档白字、深档墨字。实测比值全部写进 tools/contrast.js 断言。
        static let onSem      = Color.adaptive(0xFFFFFF, 0x0A0E15)   // 语义填充上的前景
        // 已经有一层强调填充 (accent / danger / ok) 时, 想在其上再垫一块低对比底板该往哪个方向垫:
        // 底板永远与 onAccent/onSem **反向** (浅档白字→垫黑, 深档墨字→垫白), 这样洗底只会把对比度推高而不是拉平。
        // 第八十三批的教训形状: 原先写死 Color.white.opacity(0.24) 当选中 chip 的角标底, 深色档墨字压洗白 = 越垫越糊。
        static let onFillWash = Color.adaptive(0x000000, 0xFFFFFF)

        // ---------- 862 增强对比映射 (包15): 系统 accessibilityHighContrast 开启时加深一档 ----------
        // 语义角色不变, 只是明端向纯黑 / 暗端向纯白再走一步 (hairline 可辨 1.2:1 余量放大);
        // 页面继续引用 hairline/textSub 不感知, 只有这两组"增强"变体不同。
        private static let hairlineHC = Color.adaptive(0x8A7D6A, 0x6E6454)
        @MainActor static var hairlineStrong: Color { Appearance.highContrast ? hairlineHC : hairline }

        // ---------- 品牌主题表 (idea 31: 靛蓝/墨绿/琥珀) ----------
        // 结构: [主题: [明暗: [角色: hex]]]。tools/contrast.js 机检本表:
        // accentText 对三种底 ≥4.5:1, onAccent 对 accent ≥4.5:1, 纯白对 hero 两端 ≥4.5:1,
        // onAccent 对主按钮渐变 btnA/btnB 两端 ≥4.5:1 (包1)。
        // btnA/btnB = DS.Gradient.button 端点: 浅色与 hero 同值 (白字, 现状达标);
        // 深色改用 accentText→accent 区间 — 旧案直接复用 hero, 近黑 onAccent 压暗端仅 ~2.4:1
        // (包1 必修缺陷), 新案近黑字压浅端 ≥9.8:1、压 accent 端 ≥6.4:1。
        // 891 深浅双端点: 每套主题在表里就是 light/dark 两组值，切深色不产生"断色" (对比度由 contrast.js 逐档机检)。
        // 209 夜间色板 = 同一张表的 dark 分支 (heroA/heroB/btnA/btnB 各自有深色端点)。
        // 原句"另建一套低饱和深靛组"没有单独再做: 深色档已经在这张表里，再造一套就是两个真相源。
        // 886 六套色板与 892 自定义强调色共用这一张表 —— 皮肤只有一处定义，页面各自读令牌。
        static let themeTable: [String: [String: [String: UInt32]]] = [
            // 2026-10-18 v10 暖金/黄铜 —— v10 原型的锁体就是黄铜倒角, 这是与它同族的强调色。
            // 取色口径与其余六套一致: accentText 对三种底 ≥4.5 / onAccent 对 accent 与 btnA/btnB /
            // 纯白对 hero 两端 ≥4.5。浅色 heroA 取 #855915 (白字 6.11), 深色 heroA 取 #9C6B1C (白字 4.63)。
            "brass": [
                "light": ["accent": 0x8F6119, "accentText": 0x6F4A10, "onAccent": 0xFFFFFF, "heroA": 0x855915, "heroB": 0x6F4A10, "btnA": 0x855915, "btnB": 0x6F4A10],
                "dark": ["accent": 0xE8B45C, "accentText": 0xF5CB85, "onAccent": 0x0A0E15, "heroA": 0x9C6B1C, "heroB": 0x855915, "btnA": 0xF5CB85, "btnB": 0xE8B45C]
            ],
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
            ],
            // ---- 886 六色色板: 以下三套是包16 补齐的那一半 ----
            // 取色不是"再调三个色号"：每套都要过 tools/contrast.js 的全部断言 (accentText 对三种底 /
            // onAccent 对 accent 与 btnA/btnB / 纯白对 hero 两端 / dark accentText 对 AMOLED 三表面 ≥4.5)。
            // heroB 一律留深色端 —— 浅色端压白字到不了 4.5，这是这三套 hero 都偏深的真正原因。
            // 注: 每套的说明只能写在**独立行**，`"名字": [` 后面不能跟行尾注释 ——
            //     tools/contrast.js 的解析要求 `[` 之后紧跟 "light"，它会把这种写法当成解析失败。
            // 石墨: 中性蓝灰, 给"不想要彩色"的人; 也是唯一一套接近无彩的主题
            "graphite": [
                "light": ["accent": 0x475569, "accentText": 0x334155, "onAccent": 0xFFFFFF, "heroA": 0x475569, "heroB": 0x1F2937, "btnA": 0x475569, "btnB": 0x1F2937],
                "dark": ["accent": 0x94A3B8, "accentText": 0xCBD5E1, "onAccent": 0x0A0E15, "heroA": 0x475569, "heroB": 0x1E293B, "btnA": 0xCBD5E1, "btnB": 0x94A3B8]
            ],
            // 玫瑰: 低饱和酒红, 深色档刻意偏粉 (纯红在 dark 上压不住对比度)
            "rose": [
                "light": ["accent": 0x9D2B4C, "accentText": 0x83233F, "onAccent": 0xFFFFFF, "heroA": 0xA83255, "heroB": 0x6E1B33, "btnA": 0xA83255, "btnB": 0x6E1B33],
                "dark": ["accent": 0xFB7185, "accentText": 0xFDA4AF, "onAccent": 0x0A0E15, "heroA": 0xA83255, "heroB": 0x6E1B33, "btnA": 0xFDA4AF, "btnB": 0xFB7185]
            ],
            // 极光: 青→靛的双端渐变 (heroA/heroB 色差最大的一套)
            "aurora": [
                "light": ["accent": 0x0E7490, "accentText": 0x155E75, "onAccent": 0xFFFFFF, "heroA": 0x0E7490, "heroB": 0x312E81, "btnA": 0x0E7490, "btnB": 0x312E81],
                "dark": ["accent": 0x22D3EE, "accentText": 0x67E8F9, "onAccent": 0x0A0E15, "heroA": 0x0E7490, "heroB": 0x4338CA, "btnA": 0x67E8F9, "btnB": 0x22D3EE]
            ]
        ]
        /// AMOLED 纯黑覆盖 (idea 30): 表面与画布降为纯黑/近黑。
        /// 机检: text/textSub/ok/warn/danger 与各主题 dark accentText 在这些底上 ≥4.5:1。
        static let amoledOverride: [String: UInt32] = [
            "canvas": 0x000000, "surface": 0x121009, "surfaceAlt": 0x1A1610
        ]

        /// 当前生效主题 (kf_accent, 空值归一到靛蓝)
        private static func effectiveKey(_ key: String?) -> String {
            let k = key ?? Appearance.accentKey
            // 2026-10-18: 新装用户默认暖金 (brass), 与 v10 黄铜语言一致; 老用户 kf_accent 已存值不受影响。
            return k.isEmpty ? "brass" : k
        }
        /// 主题表 → 动态色: 明暗 trait 在 provider 内解析 (与 Color.adaptive 同一机制),
        /// kf_accent 变更经全局重建后重新求值。key 缺省 = 当前主题, 显式传 key 供色板小样预览。
        static func themed(_ role: String, key: String? = nil) -> Color {
            Color(UIColor { tc in
                // 892: 自定义色只在**没有显式指定 key** 时生效 —— 设置页色板小样传的是 key=某预设，
                // 那一路必须显示预设本来的颜色，否则六个色块会全被自定义色染成一样，"选色板"就废了。
                if key == nil, CustomAccent.isActive,
                   let hex = CustomAccent.derived(CustomAccent.rgb, dark: tc.userInterfaceStyle == .dark)[role] {
                    return UIColor(Color(hex: hex))
                }
                let theme = Palette.themeTable[effectiveKey(key)] ?? Palette.themeTable["brass"]!
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
    enum FriendlyPreset {
        static func apply() {
            DB.store.set("kf_accent", "aurora")      // 极光: 六套里明度最高的一套
            DB.store.set("kf_radius", "plump")        // 大圆角
            DB.store.set("kf_density", "relaxed")     // 间距放宽
            DB.store.set("kf_row_h", "tall")          // 凭证行加高
            DB.store.set("kf_motion", "calm")         // 动效克制
            DB.store.set("kf_hero_tex", "")           // 关掉装饰纹理
        }
        // 刻意不写 isApplied 之类的"是否已套用"回显：预设是一次性动作，
        // 用户套完还会单独改某一档，届时"未套用"的显示反而是错的。没有消费点就不留这个 API。
    }
    enum CustomAccent {
        static let key = "kf_accent_custom"
        /// 0 = 未启用自定义色 (走六套预设)
        static var rgb: UInt32 {
            let v = DB.store.getInt(key)          // Store 存 Int, 免得依赖 String 解析的歧义
            return (v >= 0 && v <= 0xFFFFFF) ? UInt32(v) : 0
        }
        static var isActive: Bool { rgb != 0 }
        static func set(_ hex: UInt32) {
            // Store 只有 set(_:Any) (顶层标量走 .fragmentsAllowed)；没有 setInt 这种东西 ——
            // 写之前查过 App/Core/Store.swift:29，别凭手感造方法 (第七十九批刚为这类缺陷扫过全表)。
            if hex == 0 { DB.store.remove(key) } else { DB.store.set(key, Int(hex)) }
        }
        /// SwiftUI Color → 6 位 RGB。
        /// 必须走 UIColor 而不是硬读 Color 的内部值：Color 可能活在 Display P3 等别的色彩空间里，
        /// 直接取分量会得到与 sRGB 不同的数；先转成 UIColor 再取红绿蓝就是系统做的 sRGB 换算。
        /// 取不到分量 (极少数色彩空间) 时返回 0 = 不启用自定义色，而不是猜一个。
        static func rgb(from color: Color) -> UInt32 {
            let u = UIColor(color)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            guard u.getRed(&r, green: &g, blue: &b, alpha: &a) else { return 0 }
            // 先乘后取整，并把越界分量夹回 0...1 (P3 广色域的换算结果可能略微超出 sRGB 范围)
            func q(_ v: CGFloat) -> UInt32 {
                UInt32((max(0.0, min(1.0, Double(v))) * 255.0).rounded())
            }
            return (q(r) << 16) | (q(g) << 8) | q(b)
        }

        // ---------- WCAG 相对亮度 (与 tools/contrast.js 同一公式) ----------
        static func luminance(_ hex: UInt32) -> Double {
            func ch(_ c: UInt32) -> Double {
                let s = Double(c) / 255.0
                return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * ch((hex >> 16) & 0xff) + 0.7152 * ch((hex >> 8) & 0xff) + 0.0722 * ch(hex & 0xff)
        }
        static func ratio(_ a: UInt32, _ b: UInt32) -> Double {
            let la = luminance(a), lb = luminance(b)
            return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
        }
        /// 把颜色沿"向黑插值"的方向压到亮度 ≤ target (色相与饱和度大致保留)
        static func darkenTo(_ hex: UInt32, _ target: Double) -> UInt32 {
            if luminance(hex) <= target { return hex }
            var lo = 0.0, hi = 1.0
            for _ in 0..<24 {
                let mid = (lo + hi) / 2
                if luminance(mix(hex, 0x000000, mid)) > target { lo = mid } else { hi = mid }
            }
            return mix(hex, 0x000000, hi)
        }
        /// 沿"向白插值"抬亮度 (给深色模式下需要抬亮的文字档用)
        static func lightenTo(_ hex: UInt32, _ target: Double) -> UInt32 {
            if luminance(hex) >= target { return hex }
            var lo = 0.0, hi = 1.0
            for _ in 0..<24 {
                let mid = (lo + hi) / 2
                if luminance(mix(hex, 0xFFFFFF, mid)) < target { lo = mid } else { hi = mid }
            }
            return mix(hex, 0xFFFFFF, hi)
        }
        static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
            let k = max(0.0, min(1.0, t))
            func part(_ shift: Int) -> UInt32 {
                let x = Double((a >> shift) & 0xff), y = Double((b >> shift) & 0xff)
                return UInt32((x + (y - x) * k).rounded())
            }
            return (part(16) << 16) | (part(8) << 8) | part(0)
        }
        /// 派生六档角色色。band 值来自上面的判据，改动必须同步重跑 sweep。
        static func derived(_ base: UInt32, dark: Bool) -> [String: UInt32] {
            let white: UInt32 = 0xFFFFFF, ink: UInt32 = 0x0A0E15
            // 填充/hero: 一律压进"白字带" (≤0.1833) —— 深色模式也不放宽，因为 hero 上恒是白字
            let fill = darkenTo(base, 0.1833)
            // 主色文字: 浅色底上 ≤0.154；深色模式下反过来要够亮才压得住深色底 (≥0.40 起判)
            let text = dark ? lightenTo(base, 0.40) : darkenTo(base, 0.154)
            // 压在填充上的字: 白字达标就用白，否则墨字 (墨字要亮度 ≥0.198 才有 4.5:1)
            let onFill = ratio(white, fill) >= 4.5 ? white : ink
            return ["accent": fill, "accentText": text, "onAccent": onFill,
                    "heroA": fill, "heroB": darkenTo(fill, 0.10),
                    "btnA": fill, "btnB": darkenTo(fill, 0.10)]
        }
    }
}
