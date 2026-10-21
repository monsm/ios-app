// ================= 无障碍与操作辅助核心 (包15) =================
// 五块能力单一读点: 系统旗标 (增强对比/反转/降透明/VO) + App 偏好 (kf_ax_*/kf_dbltap_guard 等)
// 降级纪律: 所有降级分支只读这里的旗标与令牌, 页面不各自查系统开关。
//   · 颜色只经 DS 令牌 (XPalette.hairline/textSub 已内置增强对比映射, 862)
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
    /// 862 增强对比: hairline/textSub 加深一档的触发条件 (XPalette 内部消费)
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
    /// 899 减弱动态效果: 动效令牌 (XMotion) 的强制降档条件。
    /// 视图里已经在用 `@Environment(\.accessibilityReduceMotion)` 的那 11 处不受影响 ——
    /// 这里是**非视图**代码 (令牌层) 的唯一读点，两边判据是同一个系统开关。
    /// Apple 文档: `static var isReduceMotionEnabled: Bool { get }` (iOS 8+), 是**属性** (无括号)。
    static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }
    /// 226 降低透明度: 玻璃效果自绘降级为实底 (DesignSystem.dsGlass)
    /// Apple 文档: `static var isReduceTransparencyEnabled: Bool { get }` —— 同样是**属性**。
    /// 此前写成 `isReduceTransparencyEnabled()` (方法与属性记混) ⇒ run 57 报 "cannot call value of non-function type 'Bool'"。
    static var reduceTransparency: Bool { UIAccessibility.isReduceTransparencyEnabled }

    // ---------- App 内字号五档 (858): kf_font_scale 0.8/1.0/1.25/1.5/1.75, 默认 1.0 ----------
    /// 叠加语义 (务必先读): App 档位只决定"相对系统正文 17pt 的放大倍率",
    /// 系统 Dynamic Type 取"用户所选字号"的相对值 — 两者相乘后取更接近的 DynamicTypeSize 档位,
    /// 即 App 放大永远叠加在系统放大之上, 系统更大时系统胜出 (max 语义), 不互相打架。
    static var appFontScale: Double {
        let v = Double(DB.store.getString("kf_font_scale", "1.0")) ?? 1.0
        return [0.8, 1.0, 1.25, 1.5, 1.75].contains(v) ? v : 1.0
    }
    // ---------- 非隔离读点 (只给动效令牌) ----------
    /// `XMotion` 的令牌要在**非隔离**处求值 (ButtonStyle / ToggleStyle 的 makeBody 都不是主 actor),
    /// 而系统"减弱动态效果"是主 actor 旗标。这里留一份"最近一次在主 actor 上读到的值":
    /// 值本身进 Locked, 读写都不越界 —— 不是 unsafe, 也不是 assumeIsolated。
    /// 刷新点 = 启动 + 每次回前台: 改这个系统开关**必须先离开 App 去设置**, 回来一定经过
    /// scenePhase .active, 所以不会读到过期值。
    nonisolated static let reduceMotionBox = Locked(false)
    nonisolated static var reduceMotionSnapshot: Bool { reduceMotionBox.withLock { $0 } }
    /// 同一手法给 Dynamic Type 档位留一份非隔离快照 —— `XMetric.decorIcon` 与 `XMotion`
    /// 一样要在 ButtonStyle / 非主 actor 的构图代码里求值, 而 typeSize() 读的是主 actor 旗标。
    /// 刷新点与 reduceMotionBox 相同 (启动 + 回前台), 理由也一样: 改字号必须先离开 App。
    nonisolated static let typeSizeBox = Locked(DynamicTypeSize.large)
    nonisolated static var typeSizeSnapshot: DynamicTypeSize { typeSizeBox.withLock { $0 } }

    static func refreshSnapshots() {
        reduceMotionBox.withLock { $0 = reduceMotion }
        typeSizeBox.withLock { $0 = typeSize() }
    }

    /// 系统 Dynamic Type 相对正文 17pt 的倍率 (preferredFont 跟随用户所选字号)
    static var systemTypeRel: Double {
        UIFont.preferredFont(forTextStyle: .body).pointSize / 17.0
    }
    /// 858 生效档: App 档 × 系统相对, 映射到最近的 DynamicTypeSize 预设 (RootView 统一挂)
    /// 866 极限字号自检: bigPreview 开启时按 200% 预览关键页 (仅自检用)
    static func typeSize() -> DynamicTypeSize {
        let base = bigPreview ? 2.0 : appFontScale
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
    static var axStackLayout: Bool { appFontScale >= 1.5 }
    /// 866 极限字号自检: 诊断开关, 以 200% 字号预览关键页 (仅自检用)
    static var bigPreview: Bool { DB.store.getBool("kf_ax_bigpreview") }
    /// 879 灰度预览自检: 全 App 去饱和渲染, 检查渐变主题无色可读性 (仅自检用)
    static var grayPreview: Bool { DB.store.getBool("kf_ax_gray") }
}

enum AXPrefs {
    // 2026-10-20 (Q50 减法): 无障碍面板已删除, App 不再提供自定义无障碍开关。
    // 这些偏好**冻结在各自的默认值**: 行为回到"只用系统设置", 与 iOS 原生 App 一致。
    //   · 字号/灰度/反色/减弱动效/高对比 仍由 AXFlags 读**系统**设置 (不受本改动影响);
    //   · 生物识别仍由 AuthKit 提供 (377/383 的复核依赖它, 不在本次删除范围)。
    /// 872 防连点: 默认开 (防双击误开门)
    static var dbltapGuard: Bool { true }
    /// 875 按住时长: 默认 0.9s
    static var holdDuration: Double { 0.9 }
    /// 869 眼动停留: 默认 2.0s (该值本来也没有行为消费者)
    static var dwellTime: Double { 2.0 }
    /// 881 字幕式过程条: 默认开
    static var captions: Bool { true }
    /// 876 新条目双震: 默认开
    static var doubleHaptic: Bool { true }
    /// 873/60 单手下沉: 默认关
    static var onehand: Bool { false }
    /// 229 左手模式: 默认关
    static var lefty: Bool { false }
    /// 230 大格模式: 默认关
    static var bigTile: Bool { false }
    /// 870 底部对齐表单: 默认关
    static var bottomForm: Bool { false }
}


// ---------- 863 反转保护色: 降级底走中性色, 避免品牌渐变成"负片" ----------
// 第八十三批实测更正: 原实现把两端写死成"近白 0xF5F7FB → 近黑 0x0B0F18", 而前景 heroFg 取随明暗的
// Palette.text, 于是浅色档下 ink 压近黑端 = 1.06:1, 深色档下近白字压近白端 = 1.01:1 ——
// 降级渐变自己把字吃掉了, 12 个 heroGradientSafe 消费点全中。一条渐变只能配一种前景色,
// 所以两端必须**同侧** (都浅或都深), 由 Color.adaptive 跟着明暗走; 这四组比值已进 tools/contrast.js 断言。



// ---------- 主动播报 / 触感 / 焦点巡检 / 对比度 (852/876/855/883) ----------
@MainActor
enum AXTools {
    /// 852 错误主动播报: UIAccessibility.post — VO 运行时即时朗读, 非运行时排队不影响
    static func announce(_ text: String) {
        guard DB.store.getBool("kf_vo_announce", true) else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
    }
    /// 连接失败播报话术 (852 示例: "连接失败, 可能离门太远")
    static func announceConnectFail(_ reason: String) {
        announce("连接失败, 可能离门太远. \(reason)")
    }
    /// 876 新条目双震: 两段 success 触感间隔 220ms — 帮听障用户确认"有新记录";
    /// App 内可关 (AXPrefs.doubleHaptic); 设备级"减少触感/振动"由系统直接拦截, 天然遵循
    static func newEntryHaptic() {
        guard AXPrefs.doubleHaptic else { return }
        let g = UINotificationFeedbackGenerator()
        g.notificationOccurred(.success)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            g.notificationOccurred(.success)
        }
    }

    // ---------- 855 焦点顺序巡检 (开发向, 主页面焦点序列人工编排表) ----------
    static let focusReport: [String: [String]] = [
        "设备": ["状态卡(合并)", "切换胶囊", "开锁圆盘(含转子 adjust)", "快捷格×4", "最近开门", "安心打卡"],
        "钥匙": ["总数行", "排序", "月历", "整理", "选择", "类型分段", "按成员", "OTP 卡", "密码列表行", "指纹列表行"],
        "记录": ["读取状态条", "刷新", "更多菜单", "过滤芯片", "天分组行(自然语朗读)", "认领钮(60pt 命中)"],
        "设置": ["门锁", "安全", "开锁", "家人与钥匙", "工具", "本机数据保护", "无障碍", "外观", "纪念", "提醒", "关于"],
    ]
    /// 855 实屏焦点序列: key window 递归收集无障碍元素标签; 取不到时回落人工表 (不谎报)
    static func liveFocusSequence() -> [String] {
        guard let win = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows }).first(where: { $0.isKeyWindow }),
              let root = win.rootViewController?.view else { return [] }
        var out: [String] = []
        func visit(_ o: Any) {
            if let e = o as? UIAccessibilityElement {
                if let l = e.accessibilityLabel, !l.isEmpty { out.append(l) }
                return
            }
            guard let v = o as? UIView else { return }
            if let kids = v.accessibilityElements, !kids.isEmpty { kids.forEach(visit); return }
            if v.isAccessibilityElement {
                if let l = v.accessibilityLabel, !l.isEmpty { out.append(l) }
            } else { v.subviews.forEach(visit) }
        }
        visit(root)
        return out
    }

    /// 883 令牌表 (App/Core/DesignSystem.swift 的机检同款取值, 明暗各一套)
    struct CalcToken: Identifiable { let name: String; let light: UInt32; let dark: UInt32; var id: String { name } }
    // 2026-10-20 (Q50 减法): 无障碍面板已删除, App 不再提供自定义无障碍开关。
    // 这些偏好**冻结在各自的默认值**: 行为回到"只用系统设置", 与 iOS 原生 App 一致。
    //   · 字号/灰度/反色/减弱动效/高对比 仍由 AXFlags 读**系统**设置 (不受本改动影响);
    //   · 生物识别仍由 AuthKit 提供 (377/383 的复核依赖它, 不在本次删除范围)。
    /// 872 防连点: 默认开 (防双击误开门)
    static var dbltapGuard: Bool { true }
    /// 875 按住时长: 默认 0.9s
    static var holdDuration: Double { 0.9 }
    /// 869 眼动停留: 默认 2.0s (该值本来也没有行为消费者)
    static var dwellTime: Double { 2.0 }
    /// 881 字幕式过程条: 默认开
    static var captions: Bool { true }
    /// 876 新条目双震: 默认开
    static var doubleHaptic: Bool { true }
    /// 873/60 单手下沉: 默认关
    static var onehand: Bool { false }
    /// 229 左手模式: 默认关
    static var lefty: Bool { false }
    /// 230 大格模式: 默认关
    static var bigTile: Bool { false }
    /// 870 底部对齐表单: 默认关
    static var bottomForm: Bool { false }
}

/// 870 底部对齐表单: 开启后 List/Form 默认贴底锚定 (iOS 17 defaultScrollAnchor)
extension View {
    @ViewBuilder
    func axBottomAnchor() -> some View {
        // 三目两支 opaque 返回类型不同 (ModifiedContent vs Self) → 必须 @ViewBuilder
        if AXPrefs.bottomForm { defaultScrollAnchor(.bottom) } else { self }
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
    @discardableResult
    /// 392: 面容失败的原因翻成人话 —— 留痕要能读到"到哪一步没成" (不匹配/取消/锁停分开),
    /// 只记一句笼统的"失败"等于有记录读不出事。取消/改用密码是人的选择, 由调用方决定不计连败。
    /// 纯函数 (只做 LAError 到中文的映射, 不碰 UI) —— 显式 nonisolated, 让非 UI 层也能直接问原因。
    nonisolated static func reasonText(_ err: Error?) -> String {
        guard let e = err as? LAError else { return "未知原因" }
        switch e.code {
        case .authenticationFailed: return "识别不匹配"
        case .userCancel: return "用户取消"
        case .userFallback: return "用户选择改用密码"
        case .systemCancel: return "系统中断"
        case .biometryLockout: return "连续失败已锁停生物识别"
        case .biometryNotEnrolled, .biometryNotAvailable: return "本机未录入或不可用"
        default: return "错误码 \(e.code.rawValue)"
        }
    }
    /// 945: 供 Intent await 的生物验证 (与 verifyBiometric 同 canEvaluate 判据)
    static func verifyBiometricAsync(reason: String) async -> Bool {
        await withCheckedContinuation { cont in
            let ctx = LAContext()
            var err: NSError?
            guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err),
                  err?.code != LAError.biometryNotAvailable.rawValue else { cont.resume(returning: false); return }
            ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { ok, _ in
                // 同上: 真实面容通过就记账。Siri 开锁 (AppIntents:113)、受限区复核
                // (LockKeeperApp:1647)、毁灭操作复核 (SecurityCenterView:88) 都走这一支 ——
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
        if reduceTransparency || XAppearance.highContrast {
            switch shape {
            case .rect(let r):
                let s = RoundedRectangle(cornerRadius: r, style: .continuous)
                content.background(XPalette.surface, in: s)
                    .overlay(s.strokeBorder(XPalette.hairlineStrong, lineWidth: 0.5))
            case .circle:
                content.background(XPalette.surface, in: Circle())
                    .overlay(Circle().strokeBorder(XPalette.hairlineStrong, lineWidth: 0.5))
            case .capsule:
                content.xPlate(XPalette.surface, .capsule)
                    .overlay(Capsule().strokeBorder(XPalette.hairlineStrong, lineWidth: 0.5))
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

// 871 命中域扩容 (44pt 基础上再留 16pt = 60pt): 时间线认领行已内联写了同一组算术 (RecordsView:1094)。
// 这里曾另有一个 axHit60() 修饰器零调用 —— 留着两份 60pt 算术迟早漂移, 且它把 contentShape 写死成
// Rectangle 而认领行要的是 Capsule, 换过去反而是视觉退化 → 删修饰器, 保留在用的一处实现。
