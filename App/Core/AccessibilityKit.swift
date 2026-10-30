// ================= 无障碍与操作辅助核心 (包15) =================
// 五块能力单一读点: 系统旗标 (增强对比/反转/降透明/VO) + App 偏好 (kf_ax_*/kf_dbltap_guard 等)
// 降级纪律: 所有降级分支只读这里的旗标与令牌, 页面不各自查系统开关。
//   · 颜色只经 DS 令牌 (DS.Palette.hairline/textSub 已内置增强对比映射, 862)
//   · 动效频率核查表见 docs/A11Y-FREQUENCY.md (882, 全部 ≤3Hz)
//   · ⚠ 降级备案: 869/875 自定滑杆 / 877 设备生物识别门控 / 163 横屏锁定提示 — 见 docs/DEFERRED.md 包15 节
import SwiftUI
import UIKit
import LocalAuthentication

// ---------- 系统辅助旗标 (226/227/862/863): 每帧评估, 由 RootView .id(appearanceSeed) 重建兜底 ----------
/// Swift 6: 本族读的全是 UIKit 的 @MainActor 旗标 (UIAccessibility.*), 所以整族就住在主 actor 上。
/// 它以前是 nonisolated —— 那不是"能读", 只是 Swift 5 允许跨隔离同步调用; Swift 6 直接判错。
/// 代价为零: 读它的只有视图与设计令牌, 两者本来就在主 actor。
@MainActor
enum AXFlags {
    /// 862 增强对比: hairline/textSub 加深一档的触发条件 (DS.Palette 内部消费)
    /// ⚠ 2026-10-13 run 57 打脸: 此前写 `UIAccessibility.accessibilityDisplayShouldIncreaseContrast` ——
    /// UIKit **没有**这个成员。Apple 文档 (UIAccessibility「Capabilities」清单) 里 "Increase Contrast" 的官方读法
    /// 是 `isDarkerSystemColorsEnabled` (iOS 8+, static var)。此前注释还理直气壮写"长期稳定的系统 API",
    /// 越是没编译证据越要按文档抄全名, 不能凭记忆。
    static var highContrast: Bool { UIAccessibility.isDarkerSystemColorsEnabled }
    /// 863 智能反转保护: 反转色模式 (全量反转或智能反转) 时 hero 渐变降级为反转幂等色
    /// Apple 文档: `static var isInvertColorsEnabled: Bool { get }` —— 是**属性**不是方法。
    /// (此前写成 `isInvertColorsEnabled()` 并注释"只有方法形态", 是凭记忆写反了; run 57 报 "cannot call value of non-function type 'Bool'")
    static var invertColors: Bool { UIAccessibility.isInvertColorsEnabled }
    /// 861 系统加粗文本: 系统"加粗文本"开关 (设置→辅助功能→显示与文字大小)。
    /// 根视图按这一档设 legibilityWeight —— 显式字重的文本 (凭证名/开关标签) 才会跟着加粗;
    /// 系统默认只对系统字体的正文自动加粗, 自定义字重的那一族不会变。
    static var boldText: Bool { UIAccessibility.isBoldTextEnabled }
    /// 899 减弱动态效果: 动效令牌 (DS.Motion) 的强制降档条件。
    /// 视图里已经在用 `@Environment(\.accessibilityReduceMotion)` 的那 11 处不受影响 ——
    /// 这里是**非视图**代码 (令牌层) 的唯一读点，两边判据是同一个系统开关。
    /// Apple 文档: `static var isReduceMotionEnabled: Bool { get }` (iOS 8+), 是**属性** (无括号)。
    static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }
    /// 226 降低透明度: 玻璃效果自绘降级为实底 (DesignSystem.dsGlass)
    /// Apple 文档: `static var isReduceTransparencyEnabled: Bool { get }` —— 同样是**属性**。
    /// 此前写成 `isReduceTransparencyEnabled()` (方法与属性记混) ⇒ run 57 报 "cannot call value of non-function type 'Bool'"。
    static var reduceTransparency: Bool { UIAccessibility.isReduceTransparencyEnabled }
    // ---------- 非隔离读点 (只给动效令牌) ----------
    /// `DS.Motion` 的令牌要在**非隔离**处求值 (ButtonStyle / ToggleStyle 的 makeBody 都不是主 actor),
    /// 而系统"减弱动态效果"是主 actor 旗标。这里留一份"最近一次在主 actor 上读到的值":
    /// 值本身进 Locked, 读写都不越界 —— 不是 unsafe, 也不是 assumeIsolated。
    /// 刷新点 = 启动 + 每次回前台: 改这个系统开关**必须先离开 App 去设置**, 回来一定经过
    /// scenePhase .active, 所以不会读到过期值。
    nonisolated static let reduceMotionBox = Locked(false)
    nonisolated static var reduceMotionSnapshot: Bool { reduceMotionBox.withLock { $0 } }
    static func refreshSnapshots() { reduceMotionBox.withLock { $0 = reduceMotion } }

    /// 系统 Dynamic Type 相对正文 17pt 的倍率 (preferredFont 跟随用户所选字号)
    static var systemTypeRel: Double {
        UIFont.preferredFont(forTextStyle: .body).pointSize / 17.0
    }
    /// 858 生效档: App 档 × 系统相对, 映射到最近的 DynamicTypeSize 预设 (RootView 统一挂)
    /// 866 极限字号自检: bigPreview 开启时按 200% 预览关键页 (仅自检用)
    static func typeSize() -> DynamicTypeSize {
        // 2026-10-26: 原为 bigPreview ? 2.0 : appFontScale。kf_font_scale 无写点 ⇒ 恒 1.0，
        // 键与该读取属性已删，这里直接写 1.0（App 档不再可调；系统 Dynamic Type 仍在 systemTypeRel 里生效）。
        let base = bigPreview ? 2.0 : 1.0
        let rel = base * systemTypeRel
        // 预设近似倍率 (正文 17pt 基线): xLarge≈1.25, xxLarge≈1.5, xxxLarge≈1.75, accessibility1..5 ≈ 2.0/2.5/3.0/4.0/5.0
        // ⚠ 2026-10-13 run 57: 此前写成 .xsmall/.xlarge/.xxlarge —— DynamicTypeSize 的官方 case 是
        // .xSmall/.small/.medium/.large/.xLarge/.xxLarge/.xxxLarge (驼峰里 S/L 大写), 小写那三个不存在。
        let table: [(Double, DynamicTypeSize)] = [
            (0.625, .xSmall), (0.75, .small), (1.0, .large),
            (1.25, .xLarge), (1.5, .xxLarge), (1.75, .xxxLarge),
            (2.0, .accessibility1), (2.5, .accessibility2),
            (3.0, .accessibility3), (4.0, .accessibility4), (5.0, .accessibility5),
        ]
        var best = table[3]
        for t in table where abs(t.0 - rel) < abs(best.0 - rel) { best = t }
        return best.1
    }
    /// 859 AX 档降级布局: 字号 ≥1.5 时圆盘缩至 128pt (UnlockDial.dial 消费本旗标)。
    /// 原设计还含"Hero 指标纵向堆叠", 那半未实现 —— 已从说明文案删除, 不要凭本注释以为已做。
    /// 2026-10-26: 原为 `appFontScale >= 1.5`，而 `kf_font_scale` 无写点 ⇒ 恒 false。
    /// 键与读点已删，这里保留常量 false 以让调用点无需改动（AX 堆叠布局不再触发）。
    static var axStackLayout: Bool { false }
    /// 866 极限字号自检: 诊断开关, 以 200% 字号预览关键页 (仅自检用)
    static var bigPreview: Bool { DB.store.getBool("kf_ax_bigpreview") }
}
// ---------- 863 反转保护色: 降级底走中性色, 避免品牌渐变成"负片" ----------
// 第八十三批实测更正: 原实现把两端写死成"近白 0xF5F7FB → 近黑 0x0B0F18", 而前景 heroFg 取随明暗的
// Palette.text, 于是浅色档下 ink 压近黑端 = 1.06:1, 深色档下近白字压近白端 = 1.01:1 ——
// 降级渐变自己把字吃掉了, 12 个 heroGradientSafe 消费点全中。一条渐变只能配一种前景色,
// 所以两端必须**同侧** (都浅或都深), 由 Color.adaptive 跟着明暗走; 这四组比值已进 tools/contrast.js 断言。
private extension Color {
}

extension DS {

/// 226+863 hero 面唯一出口（沿用旧名 heroGradientSafe）。
/// 2026-10-27 审核修复 (AUDIT-B 2.8 #2)：原注释写「12 个消费点不用挨个改」——
/// 实测现在只有 **3 处**（DesignSystem 的 .fill / ExportShares 的 .background / UnlockDial 的 AnyShapeStyle）。
/// 数字写大不是无害的：后来者会以为改它的影响面是 12 处而不敢动。
    /// 降透明 → 纯色 (226); 反转色 → 中性降级渐变 (863); 常规 → 品牌渐变。
    /// 之所以做成 ShapeStyle.resolve(in:) 而不是静态判断: 环境只有渲染时可知, 消费点各自读一遍旗标
    /// 迟早在某个页面上漂开 —— 收在这一处, 主控卡/开锁盘/成就卡/导出卡/帮助页/引导页同帧一起换。
    /// hero 面底: 一个 ShapeStyle，三处在役消费点共用（HeroCard 底 / 分享卡底 / 圆盘底）。
    /// 之所以做成 ShapeStyle 而不是静态颜色: 降透明旗标只有渲染时可知，收在这一处才不会在某个页面漂开。
    /// 2026-10-27 审核修复: resolve(in:) 曾被当"零引用"误删，导致空 conformer —— 协议要求它存在。
    /// 现只读 EnvironmentValues（nonisolated 可读）: 降透明 → 实底，其余 → 品牌渐变。
    /// 反转色档（863）回落品牌渐变 —— 那对专用令牌已按用户决策于 704a4c5 删除。
    struct HeroSurface: ShapeStyle {
        func resolve(in environment: EnvironmentValues) -> AnyShapeStyle {
            if environment.accessibilityReduceTransparency {
                return AnyShapeStyle(Palette.surface)
            }
            return AnyShapeStyle(Gradient.hero)
        }
    }
    /// 226 降透明档的卡片描边色: 与 heroFg 同源 (常规档白、反转档 text), 压在同侧纯色底上边界可辨
    @MainActor static var heroSolidStroke: Color { heroFg.opacity(0.30) }

    static var heroGradientSafe: HeroSurface { HeroSurface() }
    /// 压在 hero 面上的前景色: 常规 = 纯白 (机检六套主题两端 ≥4.5:1); 反转 = 与降级底同侧的 text
    @MainActor static var heroFg: Color { AXFlags.invertColors ? Palette.text : .white }
}

// 2026-10-27 审核删除 (AUDIT-B 3.3)：这里原有一行「朗读词表 (880): AXTerms」的注释标题，
// 而 AXTerms 枚举体早已不存在（全仓 0 命中）。下一行的 AXPrefs 与它无关 ——
// 留一个指向不存在类型的标题，会让读者去找一个永远找不到的类型。
// ---------- App 偏好读点 (包15 全 App 开关集中于此, 页面不直接查 DB) ----------
enum AXPrefs {
    /// 872 防连点开关: 高频按钮 300ms 内重复点击忽略 (默认开, 防双击误开门)
    static var dbltapGuard: Bool { DB.store.getBool("kf_dbltap_guard", true) }
    /// 875 按住时长跟随 (⚠ 系统"按住持续时间"无读取 API, 自定滑杆 0.4–1.6s, 默认 0.9 与包1 对齐)
    static var holdDuration: Double {
        let v = Double(DB.store.getString("kf_ax_hold", "0.9")) ?? 0.9
        return min(1.6, max(0.4, v))
    }
    /// 230 大格模式: 快捷操作格 2 列大格 (默认 3 列), 长辈友好
    static var bigTile: Bool { DB.store.getBool("kf_bigtile") }
}


// ---------- 主动播报 / 触感 / 焦点巡检 / 对比度 (852/876/855/883) ----------
@MainActor
enum AXTools {
    /// 852 错误主动播报: UIAccessibility.post — VO 运行时即时朗读, 非运行时排队不影响
    static func announce(_ text: String) {
        UIAccessibility.post(notification: .announcement, argument: text)
    }
    /// 连接失败播报话术 (852 示例: "连接失败, 可能离门太远")
    static func announceConnectFail(_ reason: String) {
        announce("连接失败， 可能离门太远。 \(reason)")
    }
    /// 876 新条目双震: 两段 success 触感间隔 220ms — 帮听障用户确认"有新记录";
    /// App 内恒开（AXPrefs.doubleHaptic 已于 2026-10-26 删除）; 设备级"减少触感/振动"由系统直接拦截, 天然遵循
    static func newEntryHaptic() {
        let g = UINotificationFeedbackGenerator()
        g.notificationOccurred(.success)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            g.notificationOccurred(.success)
        }
    }


}

/// 870 底部对齐表单: 开启后 List/Form 默认贴底锚定 (iOS 17 defaultScrollAnchor)
extension View {
    @ViewBuilder
    func axBottomAnchor() -> some View {
        // 三目两支 opaque 返回类型不同 (ModifiedContent vs Self) → 必须 @ViewBuilder
        self
    }
}

// ---------- 877 生物识别降级验证: 应用锁连败 3 次后的大字替代键 (设备支持时) ----------
enum AuthKit {
    /// 设备是否可用 Face ID / Touch ID 验证本机门禁 (无生物硬件 = false, 该项走 DEFERRED)
    static var biometricAvailable: Bool {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err),
              err?.code != LAError.biometryNotAvailable.rawValue else { return false }
        return true
    }
    /// 945: 供 Intent await 的生物验证 (与 verifyBiometric 同 canEvaluate 判据)
    static func verifyBiometricAsync(reason: String) async -> Bool {
        await withCheckedContinuation { cont in
            let ctx = LAContext()
            var err: NSError?
            guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err),
                  err?.code != LAError.biometryNotAvailable.rawValue else { cont.resume(returning: false); return }
            ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { ok, _ in
                // 同上: 真实面容通过就记账。受限区复核
                // (LockKeeperApp（原 :1647，该文件已拆分，行号失效）)、毁灭操作复核（原 SecurityCenterView:88，该页已于 2026-10-26 删除） 都走这一支 ——
                // 这三处是标准档下唯一能拿到"最近刷过脸"这个事实的地方。
                if ok { AutoOpenKit.noteFaceSuccess() }
                cont.resume(returning: ok)
            }
        }
    }
}

// ---------- 226 降低透明度: 玻璃效果自绘降级 (DesignSystem 挂载点) ----------
/// 降低透明度开启时玻璃效果降级为实底卡片 (surface + hairline 描边), 信息零丢失;
/// 否则保持 iOS 26 液态玻璃。227 减少动效在动效层另行处理。
extension View {
    /// 矩形玻璃 (Toast/确认胶囊等) 的降级通道
    func axGlass(_ radius: CGFloat) -> some View {
        // ViewModifier 没有 modify(_:): 应为 View.modifier(_:)
        modifier(GlassModifier(shape: .rect(radius)))
    }
    /// 圆形玻璃 (AppLock/门禁盾) 的降级通道
    func axGlassCircle() -> some View {
        modifier(GlassModifier(shape: .circle))
    }
    /// 胶囊玻璃 (顶部切换 chip / 写入回执 / 二次确认提示) 的降级通道。
    /// 2026-10-14: 这三处原本是 `.background(surface, in: Capsule())`，实底改玻璃时必须走这里，
    /// 而不是就地再写一份 glassEffect —— 胶囊没有半径参数，塞进 axGlass(_:) 只能瞎猜一个 r，
    /// 于是"降透明/增强对比要落回哪枚形状"就会和玻璃支分家。形状族只在这一处枚举里。
    func axGlassCapsule() -> some View {
        modifier(GlassModifier(shape: .capsule))
    }
}

/// 玻璃面的形状族: 玻璃支与实底降级支必须落回同一枚形状，只是材质不同。
private enum GlassShape {
    case rect(CGFloat)
    case circle
    case capsule
}

private struct GlassModifier: ViewModifier {
    let shape: GlassShape
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme

    // 为什么这里是两个 switch 而不是一枚擦除器: CI run #90 报
    // `value of type 'AnyShape' has no member 'strokeBorder'` —— SwiftUI 只有 AnyShape (只擦 Shape),
    // **没有 AnyInsettableShape** (查过 developer.apple.com: 该页 404，社区里那些都是各仓库自己写的)。
    // 而实底退路要 `strokeBorder`，它在 InsettableShape 上。自造擦除器得让 inset(by:) 返回 Self，
    // 这条在 Swift 里做不干净 (stackoverflow 上问了很多年)，所以几何映射写两遍、材质判据只留一处:
    // 会漂移的是"什么时候不该是玻璃"(那个 if)，不是同一枚形状怎么画。
    @ViewBuilder
    func body(content: Content) -> some View {
        // 读系统旗标 (比 AXFlags 静态读更稳, 随环境更新); 降低透明度时降为实底
        // 862: 增强对比 (系统或 App 内 kf_hc) 同样降实底 —— 半透明叠字在高对比模式下属实底色
        if reduceTransparency || DS.Appearance.highContrast {
            switch shape {
            case .rect(let r):
                let s = RoundedRectangle(cornerRadius: r, style: .continuous)
                content.background(DS.Palette.surface, in: s)
                    .overlay(s.strokeBorder(DS.Palette.hairlineStrong, lineWidth: 0.5))
            case .circle:
                content.background(DS.Palette.surface, in: Circle())
                    .overlay(Circle().strokeBorder(DS.Palette.hairlineStrong, lineWidth: 0.5))
            case .capsule:
                content.variantPlate(DS.Palette.surface, .capsule)
                    .overlay(Capsule().strokeBorder(DS.Palette.hairlineStrong, lineWidth: 0.5))
            }
        } else {
            switch shape {
            case .rect(let r):
                content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: r, style: .continuous))
            case .circle:
                content.glassEffect(.regular, in: Circle())
            case .capsule:
                content.glassEffect(.regular, in: Capsule())
            }
        }
    }
}

// 871 命中域扩容 (44pt 基础上再留 16pt = 60pt): 时间线认领行已内联写了同一组算术 (RecordsView（原 :1094，该文件已拆分，行号失效）)。
// 这里曾另有一个 axHit60() 修饰器零调用 —— 留着两份 60pt 算术迟早漂移, 且它把 contentShape 写死成
// Rectangle 而认领行要的是 Capsule, 换过去反而是视觉退化 → 删修饰器, 保留在用的一处实现。
