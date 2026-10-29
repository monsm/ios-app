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

// 2026-10-29：`enum DS { }` 已空 —— 全部子令牌已拆到
// DesignTokens / DesignPalette / DesignMetrics 三个文件的 `extension DS` 里。
// 下面保留原设计判据注释（它们描述的是那些令牌的取值理由）。

/// 间距: 统一 4 / 8 节奏。
/// 布局密度 (包16): kf_density 三档映射为间距缩放系数 — 字号、触达、图标不缩放,
/// 只动"呼吸感"; 变更由 AppState.bumpAppearance 驱动全局重建, 即时生效。
/// 全局圆角档位 (包16/idea 900): kf_radius "" 标准 / "soft" 小 / "plump" 大。
/// 三档值都经过检查：card 最大 28pt，卡片仍明显小于半宽，不会出现"圆到看不出是卡片"的破形。
/// 注: 原第 4 档 `pill = 999` 第九十三批删除 —— 上面那句"刻意保留 pill 不参与缩放"讲的是胶囊语义，
/// 但全仓胶囊一律走 `Capsule()` (115 处)，没有任何一处读这个值，等于**注释替一个零读取的常量编理由**。
/// iOS 最小触达 44×44pt
/// 圆盘直径三档 (idea 249): kf_dial_size 160/176/200。变更经 AppState.setUnlockOption
/// → 外观重建通道即时生效, 与密度令牌同一机制。
/// 909 Hero 指标位显隐: kf_hero_stats 存"要看的参考项"，白名单外的一律丢弃。
/// **电量不在可选项里**：它决定"还能不能开锁"，能被自己藏掉的读数就不是读数 (DeviceHomeView 恒显示它)。
/// 默认两项全开 = 与旧版观感一致；两项全关时回退全开，不留一张没有指标的空板卡。
/// 触感分级常量 (idea 22): 全 App 触感只允许这三档 —
///   tick    = light 档: 围栏解锁/进度刻度/就绪轻震 (269) 等过程触感
///   trigger = medium 档: 手势确认触发/断连提醒 (243) 等动作触感
///   结果档   = UINotificationFeedbackGenerator 的 success/warning/error, 只用于操作结果
/// UIFeedbackGenerator 是 UIKit 对象 (主 actor)。整族标主 actor: 触感是 UI 反馈,
/// 调用点只有视图动作; 唯一一处非 UI 调用 (预握手节律) 显式跳主 actor, 见 LinkSenseKit.preconnect。
/// SF Symbols 尺寸令牌 — 全 App 只用这一套, 避免 17/20/28 混用
/// 动效令牌 — 不给每个页面各写一个 duration。
/// 默认接近临界阻尼 (苹果 fluid interfaces 的"日常档"), 只给高频物理感交互留轻微回弹。
/// 动效档位 (包16/idea 899)：kf_motion 三档 × 系统"减弱动态效果"叠加。
/// 命名要说实话：创意原文叫"Tab 动效三档"，但 TabView 的切页动画由系统持有，
/// App 侧没有任何一处 `withAnimation` 包着 tabSelection —— 所以这一档管的是**全 App 的动效令牌**
/// (81 处调用点)，不是"只换 Tab 那一下"。写清这一点，才不会让人以为调了它 Tab 就一定跟着变。
/// 默认档 "standard" 的三个值 = 本批之前的字面值，所以不改任何人的既有观感。
/// 时长令牌 (idea 211): 150/250 毫秒两档 — 微交互 / 标准转场。
/// 需要 Animation 对象用 Motion, 只需要时长 (如 Task 前的 withAnimation) 用这里。
/// 外观引擎 (包16): 品牌主题 / AMOLED 的存储键解析点。
/// 只读 DB.store (UserDefaults), 变更即时性由 AppState.applyAppearance → RootView .id 重建保证。
/// 895 "儿童友好"预设 —— **名字里不写"模式/空间/过滤"**，因为它只调外观档位：
/// 本 App 没有任何内容分级或过滤机制 (锁台账本身就是成人内容)，把它叫"儿童模式"就是虚假承诺。
/// 一次把五档推到"看得清、点得准、不闹"的组合，任何一档仍可事后单独改回。
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
// 2026-10-26 精简：Festive（节日限定色）已删。

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
        // 2026-10-18 v10 暖金/黄铜 —— 设为**默认** (与 v10 原型的黄铜锁体同族)。
        // 顺序即设置页色板从左到右的次序: brass 放最前 = 默认)。
        AccentTheme(key: "brass", name: "暖金"),
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
        let flat = DS.Appearance.isAMOLED   // 2026-10-27 三轮：AXFlags 已删，反转色/降透明不再降级
        return self.background {
            if flat { DS.Gradient.screen.ignoresSafeArea() }
            else { DS.Gradient.screenMesh.ignoresSafeArea() }
        }
    }
}

// ---------- 入场编排 ----------
/// 包15 声音策略 (857 静音开关尊重): App 内 App 音效一律走系统 systemSound —
/// 系统铃声静音开关开启时自动无声 (iOS 行为, 无需自读路由), 触感反馈不走铃音通道。
/// 全 App 不直接调 AudioServicesPlaySystemSound (App 入口与成就音效两处既有调用点同样遵循)。

// ---------- 无障碍布局辅助 (包15) ----------
extension View {
    /// 873/60 单手下沉: 圆盘整体下移落入拇指区 (开关 AXPrefs.onehand 已于 2026-10-26 删除，参数默认 false)
    @ViewBuilder
    func axOnehand(_ on: Bool = false, dy: CGFloat = 48) -> some View {
        // 三目两支 opaque 返回类型不同 (ModifiedContent vs Self) → 必须 @ViewBuilder, 同 axBottomAnchor
        if on { offset(y: dy) } else { self }
    }
}

extension View {
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
        @MainActor static var heroGlow: Color { Color.white.opacity(0.12) }
    /// hero 面上的玻璃底板 (HeroStat / HeroPill / 节日胶囊 / 状态胶囊 / 耗时标签共用)
    static var heroPlate: Color { Color.black.opacity(0.22) }
    /// hero 面上的淡色状态字 (在线绿 / 超时黄): 常规是淡色压深渐变 (机检 ≥5.7:1),
    /// 863 反转档与 heroFg 同源降级为 text —— 淡色压中性浅底只有 1 点几比, 会整个消失。
        @MainActor static func heroTint(_ light: Color) -> Color { light }
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
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency   // 226: 纯色底 + 描边
    @State private var drift = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            // 229 左手模式: Hero 卡本体镜像 —— 与 DeviceHomeView 的 barSide(工具条两侧对调)/快捷格 reversed
            // （原按 AXPrefs.lefty 翻卡内排列方向；左手模式已于 2026-10-26 删除，现在恒为 LTR。）
            .environment(\.layoutDirection, .leftToRight)
            .padding(DS.Space.l + DS.Space.xs)
            .background {
                ZStack(alignment: .topTrailing) {
                    // 863 反转保护 + 226 降透明: hero 底的两种降级 (中性渐变 / 纯色) 都收在 DS.heroGradientSafe
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .fill(DS.heroGradientSafe)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    // 889 Hero 纹理三档 (kf_hero_tex)：纯矢量，不引入任何图片资源
                    // (本 App 除 App 图标外零位图，与 Celebration.swift 的礼花同源都走 Canvas 自绘)。
                    // 透明度钉在 0.05–0.09 之间 —— 纹理压在 hero 渐变上，而渐变上永远有纯白正文 (≥4.7:1)；
                    // 再高就会把白字的局部对比拉下来，那是把"好看"换来"看不清"。
                    // 2026-10-26: 这段注释此前**没有对应实现** —— 键/备份/写入口/复算登记都齐，只差这里的消费点。
                    // 实现落在 App/Core/HeroTexture.swift（HeroTextureLayer），降透明档自动不画。
                    HeroTextureLayer(kind: HeroTexture.current, cornerRadius: DS.Radius.card)
                    // 右上一团柔光: 给渐变一个"光源", 缓慢漂移 (±8pt / 9s) 让它活过来,
                    // 慢到只剩"页面在呼吸"的潜意识感受; reduceMotion 时静止
                    Circle()
                        .fill(DS.heroGlow)
                        .frame(width: 170, height: 170)
                        .blur(radius: 42)
                        // 248: 22 点后光源与圆盘同档降峰值
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

/// 空态皆引导 (包14: 814 进度点 / 815 双按钮 / 808 示例铺底 / 834 演示链接 / 1044 便签):
/// 空态卡 = 顶部"第 N/M 步"进度圆点 + 主/次双按钮 + 可选"看 30 秒演示"文字链 + 公告板便签。
/// 2026-10-26: 原注释提到"841 小管家顶饰"，但那个装饰图形**从未实现** ——
/// `if mascot, ... { }` 一直是个空块，`mascot` 参数也没有任何消费者；
/// 连带 `DS.Metric.emptyMascot`（素颜档判定）也已删除。三样全清，不留空壳。
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
