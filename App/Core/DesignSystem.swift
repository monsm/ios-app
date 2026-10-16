// ================= 设计系统 =================
// 单一令牌来源: 间距 / 圆角 / 触达 / 图标尺寸 / 动效 / 语义色 / 渐变 + 可复用交互组件。
// 全部界面只允许引用这里的令牌, 不允许在页面里写死颜色与尺寸。
// 明暗双模: Palette 全部走 UIColor 动态色, 跟随系统深浅色自动切换;
// 30/886 包16 增量: 品牌主题三选 (kf_accent) / AMOLED 纯黑 (kf_theme=="black") / 布局密度三档 (kf_density),
// 三者均由 AppState.bumpAppearance 驱动 RootView .id 重建, 切换即时全局生效。
// 对比度由 tools/contrast.js 机检 (正文 ≥4.5:1, 分隔线 ≥1.2:1, 含全部六套主题与 AMOLED 全表)。
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

// ---------- 富文本助手 ----------
/// 把文案里的 `**加粗**` 渲染成真的粗体。
///
/// 为什么不能直接写 `Text(s)`: SwiftUI **只在字符串字面量**上解析 Markdown
/// (`Text("a**b**c")` 走 LocalizedStringKey, 会变粗), 而一旦文案是
/// ① 拼接出来的 (`Text("a" + "b")`)、② 三元表达式的结果、③ 存在数据结构里当 `String` 用
/// (`Text(entry.detail)`), 就走 `Text(_: some StringProtocol)` —— **不解析 Markdown**,
/// 用户看到的是原样的两颗星 `**`。2026-10-14 走查在 `ChangelogView` 的条目详情、
/// `RecoveryTip.detail`、`ScreenCaptureWatch.shotNotice` 与设置页两处脚注上都踩到了这个形状。
///
/// 这里**不引** `AttributedString(markdown:)`: 本仓文案里 `锁管家_` / `demo_` 这类下划线是正常字符,
/// 交给 CommonMark 会被当成强调符吃掉。自己按 `**` 切段反而可预测 —— 只有成对的 `**` 会变粗,
/// 其它字符一个不动。
func mdText(_ s: String) -> Text {
    let parts = s.components(separatedBy: "**")
    guard parts.count > 1, parts.contains(where: { !$0.isEmpty }) else { return Text(s) }
    var out = AttributedString()
    for (i, p) in parts.enumerated() where !p.isEmpty {
        var seg = AttributedString(p)
        if i % 2 == 1 { seg.inlinePresentationIntent = .stronglyEmphasized }
        out.append(seg)
    }
    return Text(out)
}

// ---------- 换行流式布局 ----------
/// 按可用宽度自动换行的横排容器 (给"一排可选片"用)。
///
/// 为什么需要它: 本仓有两处"一排可选片"—— 设置页的分区筛选片与 App 图标选择器。图标那处
/// 早已从横向 ScrollView 改成 `LazyVGrid(.adaptive)` (SettingsView 里写着理由: 横向滚动会把
/// 后几款藏在滚动区外, 用户不知道自己有九款可选)。筛选片那处当时漏了: 六枚片总宽约 656pt,
/// 而行宽只有 ~361pt —— 后两枚永远看不见, 且 `showsIndicators: false` 连"还能滚"都不说。
/// 2026-10-15 走查把这条补上。
///
/// 与 `LazyVGrid` 的分工: 网格会把每格拉成等宽 (胶囊形状变了), 这里保留子视图的**固有宽度**,
/// 只负责在放不下时换行 —— 胶囊还是贴着字的那种胶囊。
struct FlowLayout: Layout {
    var spacing: CGFloat = DS.Space.s

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var rowH: CGFloat = 0
        var totalH: CGFloat = 0
        var widest: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x > 0, x + spacing + size.width > maxWidth {
                totalH += rowH + spacing
                widest = max(widest, x)
                x = 0
                rowH = 0
            }
            x += (x > 0 ? spacing : 0) + size.width
            rowH = max(rowH, size.height)
        }
        widest = max(widest, x)
        totalH += rowH
        return CGSize(width: proposal.width ?? widest, height: totalH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowH: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            sv.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
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
    /// 全局圆角档位 (包16/idea 900): kf_radius "" 标准 / "soft" 小 / "plump" 大。
    /// 三档值都经过检查：card 最大 28pt，卡片仍明显小于半宽，不会出现"圆到看不出是卡片"的破形。
    /// 注: 原第 4 档 `pill = 999` 第九十三批删除 —— 上面那句"刻意保留 pill 不参与缩放"讲的是胶囊语义，
    /// 但全仓胶囊一律走 `Capsule()` (115 处)，没有任何一处读这个值，等于**注释替一个零读取的常量编理由**。
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
    /// iOS 最小触达 44×44pt
    enum Hit { static let min: CGFloat = 44 }
    /// 圆盘直径三档 (idea 249): kf_dial_size 160/176/200。变更经 AppState.setUnlockOption
    /// → 外观重建通道即时生效, 与密度令牌同一机制。
    enum Metric {
        static var dial: CGFloat {
            let v = DB.store.getInt("kf_dial_size", 176)
            return CGFloat([160, 176, 200].contains(v) ? v : 176)
        }
        /// 901 凭证行高两档: kf_row_h ""(紧凑: 44, 隐藏副行只留名称与状态)/"tall"(舒适: 60, 带副行)。
        /// 只做"加高"不做"压矮" —— 矮过内容自己撑开的高度就得靠裁切文字换空间，那是破版不是紧凑。
        /// 与无障碍页的 `kf_ax_bigotp` (OTP 大字) 是两回事：那档改字号，这档改行最小高度。
        static var rowMinH: CGFloat {
            DB.store.getString("kf_row_h") == "tall" ? 60 : 44
        }
        /// 907 时间线行距三档: kf_tl_gap。刻意**乘在 densityScale 之上**而不是替代它 ——
        /// 布局密度 (kf_density) 管的是全 App 的呼吸感，这一档只管记录时间线那一条竖列。
        /// 两档体系叠乘而不是各写一套，是为了避免"密度调了、时间线不动"的那类假设置。
        static var tlGap: CGFloat {
            let f: CGFloat
            switch DB.store.getString("kf_tl_gap") {
            case "tight": f = 0.5
            case "loose": f = 2.0
            default: f = 1.0
            }
            return (DS.Space.m * f * 2).rounded() / 2
        }
        /// 903 空态装饰图形: 复用**已有的** 素颜模式 (kf_plain)，不另立新键。
        /// 理由就写在调用点：一个 App 里同时存在"关庆祝"和"关插画"两个语义重叠开关，
        /// 用户只会记住其中一个，而记住的那个会变成"切了没反应"。
        static var emptyMascot: Bool { !Milestones.plainMode }
        /// 889 Hero 纹理: kf_hero_tex ""(无)/"grid" 网格/"grain" 细点。
        /// 214 噪点质感 (杂志封面颗粒) = 这里的 "grain" 档 —— 纯矢量画点，不引位图 (219 资源纪律)，
        /// 而且和 889 一样在"关掉装饰"的射程内: 装饰层不许越过无障碍与素颜模式开关。
        /// 白名单之外的值一律当"无" —— 偏好键走文本存储，不做区间校验就会读出垃圾值再画垃圾。
        static var heroTexture: String {
            let v = DB.store.getString("kf_hero_tex")
            return ["grid", "grain"].contains(v) ? v : ""
        }
        /// 902 数字字体两档: kf_digit_font ""(圆体 = 默认, 与旧版观感一致) / "plain"(系统默认体)。
        /// 射程如实圈死: 这一档只管**读数令牌的两处落点** (MetricTile 与 HeroStat 的数字 Text),
        /// 902 原句就是"Hero 卡电量数字圆体/默认体可选"。它不是全 App 数字字体总闸 ——
        /// 那版 (§84 撤掉的那种) 要动 58 处各写死 monospacedDigit 的散点, 散点没统一成令牌之前
        /// 加总闸只会造出"切了没反应"；这里只承诺切得到、也切得到的那两处。
        static var digitDesign: Font.Design {
            DB.store.getString("kf_digit_font") == "plain" ? .default : .rounded
        }
    }

    /// 889 Hero 卡纹理层 (纯矢量)。三档里默认档是"无纹理"，即与旧版完全一致。
    struct HeroTexture: View {
        let kind: String
        // @ViewBuilder 是必须的: 这里的 if / else if 没有收尾的 else，
        // 裸 `var body: some View` 在那种形状下编译不过 (要 buildEither/buildOptional)。
        @ViewBuilder
        var body: some View {
            if kind == "grid" {
                Canvas { ctx, size in
                    let step: CGFloat = 14
                    var path = Path()
                    var x: CGFloat = step
                    while x < size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
                    var y: CGFloat = step
                    while y < size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += step }
                    ctx.stroke(path, with: .color(.white.opacity(0.05)), lineWidth: 0.5)
                }
            } else if kind == "grain" {
                Canvas { ctx, size in
                    // 固定种子 (线性同余) 而不是 arc4random: 纹理必须每次重建都长一样，
                    // 否则外观种子每变一次，卡面上的点就整体重掷一次，看着像"闪了一下噪点"。
                    var seed: UInt64 = 0x9E3779B9
                    let n = 130
                    for _ in 0..<n {
                        seed = seed &* 6364136223846793005 &+ 1442695040888963407
                        let u = CGFloat(Double(seed >> 11) / Double(1 << 53))
                        seed = seed &* 6364136223846793005 &+ 1442695040888963407
                        let v = CGFloat(Double(seed >> 11) / Double(1 << 53))
                        let r: CGFloat = 0.9
                        ctx.fill(Path(ellipseIn: CGRect(x: u * size.width, y: v * size.height, width: r * 2, height: r * 2)),
                                 with: .color(.white.opacity(0.07)))
                    }
                }
            }
        }
    }
    /// 909 Hero 指标位显隐: kf_hero_stats 存"要看的参考项"，白名单外的一律丢弃。
    /// **电量不在可选项里**：它决定"还能不能开锁"，能被自己藏掉的读数就不是读数 (DeviceHomeView 恒显示它)。
    /// 默认两项全开 = 与旧版观感一致；两项全关时回退全开，不留一张没有指标的空板卡。
    enum HeroStats {
        static let all = ["firmware", "lockclock"]
        static var visible: Set<String> {
            let stored = DB.store.get([String].self, "kf_hero_stats") ?? []
            let keep = Set(stored.filter { all.contains($0) })
            return keep.isEmpty ? Set(all) : keep
        }
        static func shows(_ id: String) -> Bool { visible.contains(id) }
        static func setVisible(_ ids: [String]) {
            DB.store.set("kf_hero_stats", all.filter { ids.contains($0) })
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
        let h = WeekCal.gregorian.component(.hour, from: Date())
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
    /// 动效档位 (包16/idea 899)：kf_motion 三档 × 系统"减弱动态效果"叠加。
    /// 命名要说实话：创意原文叫"Tab 动效三档"，但 TabView 的切页动画由系统持有，
    /// App 侧没有任何一处 `withAnimation` 包着 tabSelection —— 所以这一档管的是**全 App 的动效令牌**
    /// (81 处调用点)，不是"只换 Tab 那一下"。写清这一点，才不会让人以为调了它 Tab 就一定跟着变。
    /// 默认档 "standard" 的三个值 = 本批之前的字面值，所以不改任何人的既有观感。
    enum Motion {
        /// 系统减弱动态 = 强制最静的一档，用户偏好让路 (这不是偏好，是无障碍硬约束)。
        /// 读 AXFlags.reduceMotion 而不是自己调 UIAccessibility：本仓的系统旗标只有一个读点。
        private static var systemReduceMotion: Bool { AXFlags.reduceMotion }
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
        /// 必须能把它压成直落 —— 动效策略**只有一个读点**，写在视图里就等于把降级规则实现第二遍。
        /// 数值：response 0.35 / damping 1.0（与 Apple 判据同向）
        /// （临界阻尼、不过冲）；`calm` 档不给过冲，换成直落。
        static var summon: Animation {
            switch tier {
            case "calm": return .easeOut(duration: 0.12)
            default: return .spring(response: 0.35, dampingFraction: 1.0)
            }
        }

        /// 带动量的释放（甩出去、松手回弹）：同一张表给 damping 0.82。
        /// **只有手势本身带动量时才用这一档** —— 慢慢拖到一半松手给了它，就会莫名其妙弹过头。
        static var fling: Animation {
            switch tier {
            case "calm": return .easeOut(duration: 0.12)
            default: return .spring(response: 0.35, dampingFraction: 0.82)
            }
        }

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
    /// 时长令牌 (idea 211): 150/250/400 毫秒三档 — 微交互 / 标准转场 / 强调时刻。
    /// 需要 Animation 对象用 Motion, 只需要时长 (如 Task 前的 withAnimation) 用这里。
    /// deadscan B 档点过 `slow` 零引用: 现役强调动作 (开锁成功 / Moment 卡) 都走 Motion 档
    /// (90 处受 899 减弱动态联动), 而这一档给的是"不受档位管的长强调"; 暂无真实的"值得 400ms"动作,
    /// 与 LinkSense stop* / ExportItem.linkMetadata 同类 —— 留口并写清为什么, 不硬接一个动作改观感。
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
        /// 893 App 内高对比皮肤: 与系统"增加对比度"**并联** (任一为真即加强)，不替代系统开关。
        /// 为什么要 App 内这一个: 系统的对比度开关是全局的，很多人不愿为这一个 App 改整机;
        /// 而"我就是想在看锁的时候字更硬"是 App 内可以满足的。加强项三组 (分隔线/次级文本加深 +
        /// 862 玻璃卡降实底)，不引入新颜色 —— 用的就是原本给系统高对比准备的那对令牌。
        static var highContrast: Bool { AXFlags.highContrast || DB.store.getBool("kf_hc") }
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
        private static let hairlineHC = Color.adaptive(0x98A6B8, 0x5C7084)
        private static let textSubHC  = Color.adaptive(0x38445A, 0xC2CFE2)
        static var hairlineStrong: Color { Appearance.highContrast ? hairlineHC : hairline }
        static var textSubStrong: Color { Appearance.highContrast ? textSubHC : textSub }

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
                // 892: 自定义色只在**没有显式指定 key** 时生效 —— 设置页色板小样传的是 key=某预设，
                // 那一路必须显示预设本来的颜色，否则六个色块会全被自定义色染成一样，"选色板"就废了。
                if key == nil, CustomAccent.isActive,
                   let hex = CustomAccent.derived(CustomAccent.rgb, dark: tc.userInterfaceStyle == .dark)[role] {
                    return UIColor(Color(hex: hex))
                }
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
    /// 895 "儿童友好"预设 —— **名字里不写"模式/空间/过滤"**，因为它只调外观档位：
    /// 本 App 没有任何内容分级或过滤机制 (锁台账本身就是成人内容)，把它叫"儿童模式"就是虚假承诺。
    /// 一次把五档推到"看得清、点得准、不闹"的组合，任何一档仍可事后单独改回。
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
    /// 892 自定义强调色 (ColorPicker 管线)。
    ///
    /// 为什么不能"用户选什么就上什么": 系统 ColorPicker 给的是任意 sRGB，
    /// 近白的颜色压在主卡上会让纯白正文变成 1.05:1 (完全看不见)。
    /// 所以这里存的只是**色相来源**，真正上屏的每一档都要被"拉进亮度带"再过一遍 WCAG：
    ///   · 压在色上的白字要 ≥4.5  ⇒ 该色相对亮度 ≤ 0.1833
    ///   · 近黑墨字 (0x0A0E15) 压在该色上要 ≥4.5 ⇒ 亮度 ≥ 0.198
    ///   · 主色文字压在三种浅色底上 ≥4.5 ⇒ 亮度 ≤ 0.154
    /// 落在上面两条中间那个窄带 (0.1833–0.198) 里的颜色，白字墨字都不达标 ⇒ 一律再压暗到白字带内。
    /// 这套判据在 state/accent-sweep.js 里按同一公式扫过 **5400 个自定义色 (360 色相 × 5 饱和 × 3 明度)
    /// × 明暗两态 = 10800 组派生，全部达标**（结论与复跑方式记在 §91，不是"我觉得没问题"）。
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
    /// 890 节日限定色：**默认关**。颜色是用户的既有心智，替他把主控卡换色属于"打扰"，
    /// 所以这一档必须显式开 (kf_festive)，并且关掉时与旧版完全一致。
    /// 数据源复用 671 的假日表 (RecordSearch.holidayName)，不另建一份节日清单 —— 两份迟早对不上。
    enum Festive {
        /// 只给"白字压得住"的深色对 (全部实测 white 对比度 ≥7.4:1)。
        /// 表里没有的节日一律不染色：宁可少一个效果，也不要一个凭印象编出来的"节日常规色"。
        private static let pairs: [String: (UInt32, UInt32)] = [
            "春节": (0x9B1C1C, 0x5E1212),
            "国庆": (0x8A1515, 0x4E0C0C),
            "国庆节": (0x8A1515, 0x4E0C0C),
            "中秋": (0x1F3A5F, 0x14263F),
            "劳动节": (0x7C4A03, 0x4A2C02),
            "端午": (0x14532D, 0x0B3018),
            "元旦": (0x312E81, 0x1E1B4B),
        ]
        static var isOn: Bool { DB.store.getBool("kf_festive") }
        /// 今天该用哪一对；不在表里 / 开关关着 / 补班日 都返回 nil (不染色)。
        /// 补班日必须排除：它按 671 的口径"不是假期"，给它上节日色等于告诉用户今天休息。
        static func todayPair(_ now: Date = Date()) -> (UInt32, UInt32)? {
            guard isOn else { return nil }
            let day = StatsKit.dayKey(now)   // 节假日表是公历日串，自建 formatter 在非公历历法下会全年配不上 (§10.30)
            guard let name = RecordSearch.holidayName(day), !RecordSearch.isMakeupWorkday(day),
                  let p = pairs[name] else { return nil }
            return p
        }
    }
    /// 渐变: 品牌层的"深度"来源。hero 压纯白文字 (装饰层不做动态色, 两端对比度机检于 themeTable)。
    enum Gradient {
        /// 主控卡 / 开锁盘 idle 态 / 主按钮 — 主题色向深色端的对角渐变 (随 kf_accent 切换)
        static var hero: LinearGradient {
            // 890 节日限定色改在**这个出口**上：hero 面有四处消费点 (主控卡 / 成就 / 礼花 / 导出卡)，
            // 在各处各判一次就会出现"有的面变色有的不变"。反转色降级 (863) 在更外层的 DS.heroGradientSafe，
            // 优先级仍由它说了算 —— 系统反转时该中性就中性，节日色不得越过它。
            if let p = Festive.todayPair() {
                return LinearGradient(colors: [Color(hex: p.0), Color(hex: p.1)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
            }
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
        // 886 补齐的后三套 (顺序即设置页色板从左到右的次序)
        AccentTheme(key: "graphite", name: "石墨"),
        AccentTheme(key: "rose", name: "玫瑰"),
        AccentTheme(key: "aurora", name: "极光"),
    ]
}

/// 页面底: 渐变画布, List/Form 需同时 .variantList()
extension View {
    func dsScreenBackground() -> some View {
        // 32: 网格渐变作底; 三档回落线性渐变 —— AMOLED 要纯黑、智能反转要幂等色、降透明要实底,
        // 网格色块会把这三档破坏掉 (与 863/226 的既有降级纪律同源, 不另立判据)。
        //
        // 2026-10-13 (首次真机运行): 原实现**丢掉了 self** ——
        //     func dsScreenBackground() -> some View { Group { …渐变… } }
        // 函数体只构造那个 Group、从不引用接收者, 于是 `X.dsScreenBackground()` 的结果就是
        // "一层渐变", X 整个不见了。全仓 99 处这么用 ⇒ **每个页面都只剩底色 = 打开 App 一片空白**。
        // (对照: 同文件的 dsSheetGlass 写的是 `presentationBackground(...)`, 那是 `self.` 的省略,
        //  所以它是对的 —— 差别就在"是不是对 self 调修饰符"。)
        // 正确写法: 把渐变放进 .background, 内容留在前景。
        //
        // 2026-10-16 晚：两套新界面（「一枚锁核」「近场仪表」）已删，
        // 这里回到唯一那套底色 —— 与 226/863/AMOLED 三条降级纪律逐字一致。
        let flat = DS.Appearance.isAMOLED || AXFlags.invertColors || AXFlags.reduceTransparency
        return self.background {
            if flat { DS.Gradient.screen.ignoresSafeArea() }
            else { DS.Gradient.screenMesh.ignoresSafeArea() }
        }
    }
}

/// 33 玻璃 sheet 底: 弹层(sheet)用薄材料垫底, 开启系统"降低透明度"时降级为实底 surface。
/// 复用 226 那条既有闸门与降级纪律 (AXFlags.reduceTransparency 是本仓降透明的唯一读点,
/// 与 AccessibilityKit 的 axGlass 同源), 不另立第二套"什么算玻璃"的判据。
/// 台账判 PART 的收口: 全仓此前只有 SecurityCenterView 一处把 ultraThinMaterial 落在卡片底,
/// sheet 面没有任何玻璃语义 —— 这一枚令牌就是 sheet 侧的统一入口; 首个真实消费点是
/// 成就页徽章详情 sheet (自带 detents、无自绘底, 材料能透出来)。其余 sheet 按批次逐个换。
extension View {
    @ViewBuilder   // 两支 presentationBackground 的 ShapeStyle 类型不同 (Material vs Color) → 必须 builder
    func dsSheetGlass() -> some View {
        if AXFlags.reduceTransparency {
            presentationBackground(DS.Palette.surface)   // 降透明 = 实底, 信息零丢失
        } else {
            presentationBackground(.ultraThinMaterial)   // 33 玻璃底
        }
    }
}

// ---------- 入场编排 ----------
/// 包15 声音策略 (857 静音开关尊重): App 内 App 音效一律走系统 systemSound —
/// 系统铃声静音开关开启时自动无声 (iOS 行为, 无需自读路由), 触感反馈不走铃音通道。
/// 全 App 不直接调 AudioServicesPlaySystemSound (App 入口与成就音效两处既有调用点同样遵循)。

// ---------- 无障碍布局辅助 (包15) ----------
extension View {
    /// 873/60 单手下沉: 圆盘整体下移落入拇指区 (开关在 设置-辅助, AXPrefs.onehand)
    @ViewBuilder
    func axOnehand(_ on: Bool = AXPrefs.onehand, dy: CGFloat = 48) -> some View {
        // 三目两支 opaque 返回类型不同 (ModifiedContent vs Self) → 必须 @ViewBuilder, 同 axBottomAnchor
        if on { offset(y: dy) } else { self }
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
        // 2026-10-16 晚：变体删掉后只有一套形状（见 VariantGrammar.swift 的 statusPill）。
        VK().statusPill(text: text, systemImage: systemImage, tone: tone.color)
    }
}

/// hero 面上的底板与压纱 (第八十三批): 可读性靠**压暗**背景, 不靠洗白背景。
/// 原来的玻璃做法是"同色低透明度洗底 + 白字", 前景与底板朝同一方向漂, 实测白字掉到 3.51~3.88:1
/// (白@0.14/0.18 洗底压在最亮 hero 端), 看着更"透"但读不出来。换成黑纱后同一位置 ≥5:1,
/// 六套主题 + 节日色 + 863 反转档的组合全部进 tools/contrast.js 机检。
extension DS {
    /// hero 卡整幅薄黑纱: 最亮端上纯白正文本来只剩 4.75~4.80:1, 卡内还有一团 white@0.12 柔光会再抬高局部亮度
    static var heroScrim: Color { Color.black.opacity(0.20) }
    /// 右上那团"光源": 常规是白纱 (压暗纱之下, 机检 E4 已把它算进叠层), 863 反转档换成黑纱,
    /// 否则白纱落在中性浅底上等于什么都没画。
    static var heroGlow: Color { AXFlags.invertColors ? Color.black.opacity(0.10) : Color.white.opacity(0.12) }
    /// hero 面上的玻璃底板 (HeroStat / HeroPill / 节日胶囊 / 状态胶囊 / 耗时标签共用)
    static var heroPlate: Color { Color.black.opacity(0.22) }
    /// hero 面上的淡色状态字 (在线绿 / 超时黄): 常规是淡色压深渐变 (机检 ≥5.7:1),
    /// 863 反转档与 heroFg 同源降级为 text —— 淡色压中性浅底只有 1 点几比, 会整个消失。
    static func heroTint(_ light: Color) -> Color { AXFlags.invertColors ? Palette.text : light }
}

/// 玻璃胶囊 (hero 渐变上的专属变体): 压暗底板 + heroFg 字。
/// 只在 HeroCard 内部使用 — 语义仍由图标形状 + tint 双通道表达。
/// 默认前景与 HeroStat 同源走 DS.heroFg (第八十一批)：写死 .white 会在反转色模式下
/// 撞上 863 降级后的浅色 hero，变成白字压白底。
struct HeroPill: View {
    let text: String
    let systemImage: String
    var tint: Color = DS.heroFg

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: systemImage)
                .font(.system(size: DS.Icon.xs, weight: .semibold))
            Text(text)
                .vkFont(.caption, weight: .medium)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, DS.Space.s + 2)
        .padding(.vertical, DS.Space.xs + 1)
        .background(DS.heroPlate, in: Capsule())
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
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .lineLimit(1)
            }
            Text(value)
                .vkFont(emphasized ? .subheadline.weight(.semibold) : .subheadline)
                .foregroundStyle(emphasized ? DS.Palette.text : DS.Palette.textSub)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                // 苹方数字是比例宽度: 9%→10% 会让整块宽度跳动, 必须等宽
                // 663 等宽数字 (原句"财经数字排版"): 读数换值时字宽不跳，与 207 的逐位滚动是一对 ——
                // 滚动负责"看见变化"，等宽负责"变化时布局不抖"。
                .monospacedDigit()
                .fontDesign(DS.Metric.digitDesign)   // 902 数字字体两档: 圆体/默认体走令牌 (设置-外观可切), 中文自动回退苹方
                // 207 电量数字滚动 = 这一处 contentTransition(.numericText()): 读数换值时逐位滚过去而不是硬跳。
                // 902 那批撤过"全 App 数字字体"，这里保留**点状**采用 —— 只有会变数的读数才需要它。
                .contentTransition(.numericText())   // 电量变化时数字滚动而不是硬跳
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Space.m)
        .padding(.vertical, DS.Space.s + 2)
        .variantPlate(DS.Palette.surfaceAlt, .tile)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }
}

/// hero 渐变上的指标块: 前景走 DS.heroFg + 压暗玻璃底 (DS.heroPlate), 是 MetricTile 的主控卡变体。
/// 数值恒为 heroFg (常规=纯白, 叠层机检 E4 在底板上 ≥7.39:1；反转=随明暗的 text)，标签作辅助视觉
/// (≥5.40:1, 无障碍由 accessibilityLabel 合并朗读)。
/// 第八十一批把这里的三处硬编码 `.white` 换成 heroFg；第八十三批再把洗白底板换成压暗底板 ——
/// 前者防的是 863 降级后的中性浅面 (`DS.heroGradientSafe`) 把白字吞掉，
/// 后者防的是"白字 + 白@0.14 洗底"两头朝同一方向漂，实测只剩 3.74:1。写死白色等于把 863 的护栏绕过去。
struct HeroStat: View {
    let systemImage: String
    let label: String
    let value: String
    var emphasized: Bool = true
    /// 语义警示 (如低电量) 时染图标; nil 用常规 heroFg
    var tint: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            HStack(spacing: DS.Space.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: DS.Icon.sm, weight: .medium))
                    .foregroundStyle(tint ?? DS.heroFg.opacity(0.85))
                Text(label)
                    .vkFont(.caption2, weight: .medium)
                    .foregroundStyle(DS.heroFg.opacity(0.8))
                    .lineLimit(1)
            }
            Text(value)
                .vkFont(emphasized ? .subheadline.weight(.semibold) : .subheadline)
                .foregroundStyle(DS.heroFg)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                // 663 等宽数字 (原句"财经数字排版"): 读数换值时字宽不跳，与 207 的逐位滚动是一对 ——
                // 滚动负责"看见变化"，等宽负责"变化时布局不抖"。
                .monospacedDigit()
                .fontDesign(DS.Metric.digitDesign)   // 902 数字字体两档: 与 MetricTile 同一令牌, 一处切换两处同步 (中文自动回退苹方)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Space.m)
        .padding(.vertical, DS.Space.s + 2)
        .background(DS.heroPlate, in: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }
}

/// 主控卡: 页面唯一的品牌渐变面, 用光效和投影把视觉权重压在最重要的信息上。
/// 深浅色共用同一套渐变与白色文字；卡内叠层 (渐变→纹理→柔光→heroScrim) 之后白正文实测 ≥5.11:1
/// (六套主题 × 明暗 × 最亮端 + 节日色, 机检 tools/contrast.js E4)。
struct HeroCard<Content: View>: View {
    var flair: Bool
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency   // 226: 纯色底 + 描边
    @State private var drift = false
    /// `flair` (idea 999): 史诗徽章点亮后 7 天的一圈流光边, 素颜模式不显示
    init(flair: Bool = false, @ViewBuilder content: () -> Content) {
        self.flair = flair
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            // 229 左手模式: Hero 卡本体镜像 —— 与 DeviceHomeView 的 barSide(工具条两侧对调)/快捷格 reversed
            // 同一档 (AXPrefs.lefty)。只翻卡内排列方向, 不动卡外页面结构; 未开左手模式时是恒等值。
            .environment(\.layoutDirection, AXPrefs.lefty ? .rightToLeft : .leftToRight)
            .padding(DS.Space.l + DS.Space.xs)
            .background {
                ZStack(alignment: .topTrailing) {
                    // 863 反转保护 + 226 降透明: hero 底的两种降级 (中性渐变 / 纯色) 都收在 DS.heroGradientSafe
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .fill(DS.heroGradientSafe)
                    // 889 Hero 纹理三档 (kf_hero_tex)：纯矢量，不引入任何图片资源
                    // (本 App 除 App 图标外零位图，与 Celebration.swift 的礼花同源都走 Canvas 自绘)。
                    // 透明度钉在 0.05–0.09 之间 —— 纹理压在 hero 渐变上，而渐变上永远有纯白正文 (≥4.7:1)；
                    // 再高就会把白字的局部对比拉下来，那是把"好看"换来"看不清"。
                    DS.HeroTexture(kind: DS.Metric.heroTexture)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    // 右上一团柔光: 给渐变一个"光源", 缓慢漂移 (±8pt / 9s) 让它活过来,
                    // 慢到只剩"页面在呼吸"的潜意识感受; reduceMotion 时静止
                    Circle()
                        .fill(DS.heroGlow)
                        .frame(width: 170, height: 170)
                        .blur(radius: 42)
                        // 248: 22 点后光源与圆盘同档降峰值
                        .opacity(DS.isNightDim ? 0.55 : 1)
                        .offset(x: drift ? 54 : 46, y: drift ? -51 : -44)
                    // 整幅薄黑纱压在渐变+柔光之上 (第八十三批): 最亮 hero 端上纯白正文只有 4.75~4.80:1,
                    // 光斑再把局部亮度抬上去就掉出 4.5。纱在上、光在下 ⇒ 光斑处实测仍 ≥5.16:1,
                    // 观感上只是"渐变更深了一档", 光源感保留。
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .fill(DS.heroScrim)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .overlay {
                if flair { HeroFlairBorder() }
                // 226 降透明: 渐变退纯色后补一圈描边, 找回卡片边界 (色走 heroSolidStroke, 反转档自动跟随)
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .strokeBorder(DS.heroSolidStroke, lineWidth: 1)
                }
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
            .strokeBorder(LinearGradient(colors: [DS.Palette.themed("heroA"), DS.heroFg, DS.Palette.themed("heroB")],
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

/// 空态皆引导 (包14: 814 进度点 / 815 双按钮 / 808 示例铺底 / 834 演示链接 / 841 小管家 / 1044 便签):
/// 空态卡 = 顶部"第 N/M 步"进度圆点 + 小管家顶饰 + 主/次双按钮 + 可选"看 30 秒演示"文字链 + 公告板便签。
/// 默认值口径 (本轮包14 缺陷整改): mascot 默认开 —— 841 原句是"贯穿**全部**空态"，关掉走素颜模式 (kf_plain) 统一闸；
/// showDemoLink 默认开 —— 演示链出不出现由 demoAction 决定 (调用方给了动作就上屏，没给就没有)，
/// 而不是由一个全仓没人置真的旗标决定 (旧写法: showDemoLink 默认 false 且零处置真 ⇒ 834 从未渲染)。
struct GuidedEmptyView: View {
    let systemImage: String
    let title: String
    let message: String
    var step: Int = 0                 // 814 当前引导阶段 (0 = 不显示进度点; >0 显示在空态**顶部**, 与原句一致)
    var stepTotal: Int = 3            // 814 引导总步数 (连锁→录凭证→开门, 与 801 三卡导览同口径)
    var primaryTitle: String = ""     // 815 主动作
    var primary: (() -> Void)?
    var secondaryTitle: String = ""   // 815 次按钮
    var secondary: (() -> Void)?
    var showDemoLink: Bool = true     // 834 30 秒演示链接; 传了 demoAction 才可能上屏, 不想要时显式传 false
    var demoAction: (() -> Void)?
    var mascot: Bool = true           // 841 小管家顶饰 (素颜模式整体熄灭, 见 DS.Metric.emptyMascot)

    // 自定义 init(systemImage:title:message:) 会顶掉编译器合成的 memberwise init, 于是 step/双按钮/
    // 演示链/小管家 这族带默认值的参数一个都传不进去 —— 整族成了装饰。删掉它, 用合成 init:
    // 三个 let 必填, 其余 var 自动带默认值 (调用方按声明顺序选着传)。
    var body: some View {
        VStack(spacing: DS.Space.m) {
            // 814 进度圆点在**顶部** (原句"各 Tab 空态顶部"): 先告诉用户走到哪一步, 再摆内容与动作
            if step > 0 {
                HStack(spacing: DS.Space.xs) {
                    ForEach(0..<stepTotal, id: \.self) { i in
                        Circle()
                            .fill(i < step ? DS.Palette.accent : DS.Palette.hairline)
                            .frame(width: 7, height: 7)
                    }
                    Text("第 \(step)/\(stepTotal) 步")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                }
                .accessibilityLabel("引导阶段 第 \(step) 步, 共 \(stepTotal) 步")
            }
            // 903 空态装饰图形挂素颜模式 (kf_plain)，见 DS.Metric.emptyMascot：
            // 不再造第二个"关插画"开关，理由写在那条令牌的注释里。
            if mascot, DS.Metric.emptyMascot {
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
            // 1044 家庭公告板: 便签也进引导空态 (此前只有设备页/记录页两处直挂, 组件本身不认它)
            if !Milestones.bulletin.isEmpty {
                Label("公告: " + Milestones.bulletin, systemImage: "pin.fill")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.accentText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let demoAction, showDemoLink {
                Button("看看它如何工作 (30 秒演示)") { demoAction() }
                    .vkFont(.footnote, weight: .medium)
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
        // 2026-10-16 P1 批二: 外形交给语法层 (一处定义、两套各一份)，本结构只负责把 Button 的
        // 状态 (pressed / fullWidth) 递下去。legacy 分支是原实现的**逐字**拷贝 ⇒ 现行界面零变化。
        // 改这里等于同时改全仓 29 处主按钮 —— 这就是选它当杠杆的理由。
        VK.current.primaryActionChrome(fullWidth: fullWidth, pressed: configuration.isPressed) {
            configuration.label
        }
    }
}

/// 次级按钮样式 (描边)
struct SecondaryActionStyle: ButtonStyle {
    var fullWidth: Bool = true
    /// 底色染料的来源。默认就是原来那个 `accentText` —— 传参只是为了不改 legacy 像素。
    var tint: Color = DS.Palette.accentText
    func makeBody(configuration: Configuration) -> some View {
        // 2026-10-16 P1 批二: 同 PrimaryActionStyle，外形交给语法层。
        VK.current.secondaryActionChrome(fullWidth: fullWidth, pressed: configuration.isPressed, tint: tint) {
            configuration.label
        }
    }
}

/// 破坏性按钮样式 (红字描边)
struct DestructiveActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        // 2026-10-16 P1 批二: 同 PrimaryActionStyle，外形交给语法层。
        VK.current.destructiveActionChrome(pressed: configuration.isPressed) {
            configuration.label
        }
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
        // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 命中高仅约 16.5pt (< 44)。
        // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
        .frame(minHeight: DS.Hit.min)
        .contentShape(Rectangle())
    }
}
