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
enum AXFlags {
    /// 862 增强对比: hairline/textSub 加深一档的触发条件 (DS.Palette 内部消费)
    static var highContrast: Bool { UITraitCollection.current?.accessibilityHighContrast ?? false }
    /// 863 智能反转保护: 反转色模式 (全量反转或智能反转) 时 hero 渐变降级为反转幂等色
    static var invertColors: Bool {
        UIAccessibility.isInvertColors || (UITraitCollection.current?.accessibilityInvertColors ?? false)
    }
    /// 226 降低透明度: 玻璃效果自绘降级为实底 (DesignSystem.dsGlass)
    static var reduceTransparency: Bool { UIAccessibility.isReduceTransparencyEnabled }

    // ---------- App 内字号五档 (858): kf_font_scale 0.8/1.0/1.25/1.5/1.75, 默认 1.0 ----------
    /// 叠加语义 (务必先读): App 档位只决定"相对系统正文 17pt 的放大倍率",
    /// 系统 Dynamic Type 取"用户所选字号"的相对值 — 两者相乘后取更接近的 DynamicTypeSize 档位,
    /// 即 App 放大永远叠加在系统放大之上, 系统更大时系统胜出 (max 语义), 不互相打架。
    static var appFontScale: Double {
        let v = Double(DB.store.getString("kf_font_scale", "1.0")) ?? 1.0
        return [0.8, 1.0, 1.25, 1.5, 1.75].contains(v) ? v : 1.0
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
        // 预设近似倍率 (正文 17pt 基线): xxlarge≈1.5, xxxLarge≈1.75, accessibility1..5 ≈ 2.0/2.5/3.0/4.0/5.0
        let table: [(Double, DynamicTypeSize)] = [
            (0.625, .xsmall), (0.75, .small), (1.0, .large),
            (1.25, .xlarge), (1.5, .xxlarge), (1.75, .xxxLarge),
            (2.0, .accessibility1), (2.5, .accessibility2),
            (3.0, .accessibility3), (4.0, .accessibility4), (5.0, .accessibility5),
        ]
        var best = table[3]
        for t in table where abs(t.0 - rel) < abs(best.0 - rel) { best = t }
        return best.1
    }
    /// 859 AX 档降级布局: 字号 ≥1.5 时 Hero 指标纵向堆叠、圆盘缩至 128pt 保持可操作
    static var axStackLayout: Bool { appFontScale >= 1.5 }
    /// 866 极限字号自检: 诊断开关, 以 200% 字号预览关键页 (仅自检用)
    static var bigPreview: Bool { DB.store.getBool("kf_ax_bigpreview") }
    /// 879 灰度预览自检: 全 App 去饱和渲染, 检查渐变主题无色可读性 (仅自检用)
    static var grayPreview: Bool { DB.store.getBool("kf_ax_gray") }
}

// ---------- 863 反转保护色: 近白/近黑在反转下幂等 (白↔黑互换仍可读), 避免品牌渐变成"负片" ----------
private extension Color {
    static let invHeroLight = Color(hex: 0xF5F7FB)
    static let invHeroDark  = Color(hex: 0x0B0F18)
}

extension DS {
    /// 863: hero 渐变在反转色模式下降级为幂等近中性渐变 (文字用 heroFg)
    static var heroGradientSafe: LinearGradient {
        if AXFlags.invertColors {
            return LinearGradient(colors: [Color.invHeroLight, Color.invHeroDark],
                                  startPoint: .top, endPoint: .bottom)
        }
        return Gradient.hero
    }
    /// 压在 hero 面上的前景色: 常规 = 纯白 (机检两端 ≥4.5:1); 反转 = 随明暗的 text
    static var heroFg: Color { AXFlags.invertColors ? Palette.text : .white }
}

// ---------- 朗读词表 (880): accessibilityLabel 统一走这里, 审计口径 = 本文件 ----------
enum AXTerms {
    static let lock = "门锁"
    static let credential = "凭证"          // 不混用"密钥/口令"
    static let pwd = "密码"
    static let fp = "指纹"
    static let otp = "临时码"
    static let battery = "电量"
    static let firmware = "固件"
    static let lockClock = "锁钟"
    static let connected = "已连接"
    static let notConnected = "未连接"
    static let records = "开门记录"

    /// 850 时间线自然语: "今天 14:02, 张三用指纹开了门" — 字段不堆叠, 拼成一句人话
    static func rowSentence(dayKey: String, time: String, title: String,
                           warn: Bool, isToday: Bool, dayLabel: String) -> String {
        let when = isToday ? "今天 \(time)" : "\(dayLabel) \(time)"
        let s = when + ", " + title
        return warn ? "告警记录, " + s : s
    }

    /// 856 盲文简写表: 数值/状态类控件的 accessibilityValue 走简写, 降低盲文转译音节
    static func br(_ s: String) -> String {
        var v = s
        for (k, a) in [("%", " pct"), ("已连接", "conn"), ("未连接", "no-conn"),
                       ("电量", "bat"), ("固件", "FW"), ("锁钟", "clk"),
                       ("今天", "今"), ("次", "次/")] {
            v = v.replacingOccurrences(of: k, with: a)
        }
        return v
    }
}

// ---------- 主动播报 / 触感 / 焦点巡检 / 对比度 (852/876/855/883) ----------
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
        "凭证": ["总数行", "排序", "月历", "整理", "选择", "类型分段", "按成员", "OTP 卡", "密码列表行", "指纹列表行"],
        "记录": ["读取状态条", "刷新", "更多菜单", "过滤芯片", "天分组行(自然语朗读)", "认领钮(60pt 命中)"],
        "设置": ["门锁", "安全", "开锁", "家人与钥匙", "工具", "本机数据保护", "无障碍(包15)", "外观", "纪念", "提醒", "关于"],
    ]
    /// 打开巡检: 打印 + 播报当前页焦点序列 (DEBUG 入口挂 DiagnosticsView)
    static func runFocusAudit(page: String) {
        let seq = focusReport[page] ?? []
        let line = "焦点顺序 [\(page)]: " + seq.joined(separator: " → ")
        print("[A11Y 855] " + line)
        announce(line)
    }

    // ---------- 883 对比度计算器: 与 tools/contrast.js 同款 WCAG 2.1 相对亮度公式 ----------
    static func contrastRatio(_ a: UInt32, _ b: UInt32) -> Double {
        func lum(_ hex: UInt32) -> Double {
            func ch(_ c: UInt32) -> Double {
                let s = Double(c & 0xff) / 255.0
                return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * ch((a >> 16) & 0xff) + 0.7152 * ch((a >> 8) & 0xff) + 0.0722 * ch(a & 0xff)
        }
        let la = lum(a), lb = lum(b)
        let hi = max(la, lb), lo = min(la, lb)
        return (hi + 0.05) / (lo + 0.05)
    }
    /// 883 令牌表 (App/Core/DesignSystem.swift 的机检同款取值, 明暗各一套)
    struct CalcToken: Identifiable { let name: String; let light: UInt32; let dark: UInt32; var id: String { name } }
    static let calcTokens: [CalcToken] = [
        CalcToken(name: "页面底", light: 0xF2F4F9, dark: 0x070B12),
        CalcToken(name: "卡片", light: 0xFFFFFF, dark: 0x151D29),
        CalcToken(name: "次级块", light: 0xF5F7FB, dark: 0x1C2534),
        CalcToken(name: "分隔线", light: 0xD3DCE7, dark: 0x29343F),
        CalcToken(name: "正文", light: 0x0D1626, dark: 0xF2F6FB),
        CalcToken(name: "次文本", light: 0x525E77, dark: 0x9FACBE),
        CalcToken(name: "成功", light: 0x15803D, dark: 0x4ADE80),
        CalcToken(name: "警告", light: 0xB45309, dark: 0xFBBF24),
        CalcToken(name: "错误", light: 0xB91C1C, dark: 0xF87171),
        CalcToken(name: "靛蓝heroA", light: 0x5A55EC, dark: 0x5B5BD6),
    ]
}

// ---------- App 偏好读点 (包15 全 App 开关集中于此, 页面不直接查 DB) ----------
enum AXPrefs {
    /// 872 防连点开关: 高频按钮 300ms 内重复点击忽略 (默认开, 防双击误开门)
    static var dbltapGuard: Bool { DB.store.getBool("kf_dbltap_guard", true) }
    /// 875 按住时长跟随 (⚠ 系统"按住持续时间"无读取 API, 自定滑杆 0.4–1.6s, 默认 0.9 与包1 对齐)
    static var holdDuration: Double {
        let v = Double(DB.store.getString("kf_ax_hold", "0.9")) ?? 0.9
        return min(1.6, max(0.4, v))
    }
    /// 869 眼动停留参数 (⚠ 系统停留时长无公开 API, 自定滑杆 0.5–4s, 默认 2s):
    /// 扫描组 (868) 逐项聚焦的停留基准, VoiceOver 练习场演示用
    static var dwellTime: Double {
        let v = Double(DB.store.getString("kf_ax_dwell", "2.0")) ?? 2.0
        return min(4.0, max(0.5, v))
    }
    /// 881 字幕式过程条: 开锁/连接过程底部三步文字字幕 (可关)
    static var captions: Bool { DB.store.getBool("kf_ax_captions", true) }
    /// 876 新条目双震 (默认开, 设置可关; 设备级"振动"总开关由系统拦截)
    static var doubleHaptic: Bool { DB.store.getBool("kf_ax_doublehaptic", true) }
    /// 873/60 圆盘热区偏移 (单手下沉): 圆盘整体下移落入拇指区, 快捷格随之贴底
    static var onehand: Bool { DB.store.getBool("kf_onehand") }
    /// 229 左手模式: 工具栏与快捷格镜像 (落点设备 Tab)
    static var lefty: Bool { DB.store.getBool("kf_lefty") }
    /// 230 大格模式: 快捷操作格 2 列大格 (默认 3 列), 长辈友好
    static var bigTile: Bool { DB.store.getBool("kf_bigtile") }
    /// 870 底部对齐表单: 键盘弹起时表单贴底不滚动跳
    static var bottomForm: Bool { DB.store.getBool("kf_form_bottom") }
}

/// 870 底部对齐表单: 开启后 List/Form 默认贴底锚定 (iOS 17 defaultScrollAnchor)
extension View {
    func axBottomAnchor() -> some View {
        AXPrefs.bottomForm ? defaultScrollAnchor(.bottom) : self
    }
}

// ---------- 877 生物识别降级验证: 应用锁连败 3 次后的大字替代键 (设备支持时) ----------
enum AuthKit {
    /// 设备是否可用 Face ID / Touch ID 验证本机门禁 (无生物硬件 = false, 该项走 DEFERRED)
    static var biometricAvailable: Bool {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err),
              !(err?.code == errBiometryNotAvailable) else { return false }
        return true
    }
    @discardableResult
    static func verifyBiometric(_ onSuccess: @escaping () -> Void) -> Bool {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err),
              !(err?.code == errBiometryNotAvailable) else { return false }
        return ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                  localizedReason: "用 Face ID / Touch ID 代替本机密码") { ok, _ in
            Task { @MainActor in if ok { onSuccess() } }
        }
    }
}

// ---------- 226 降低透明度: 玻璃效果自绘降级 (DesignSystem 挂载点) ----------
/// 降低透明度开启时玻璃效果降级为实底卡片 (surface + hairline 描边), 信息零丢失;
/// 否则保持 iOS 26 液态玻璃。227 减少动效在动效层另行处理。
extension View {
    /// 矩形玻璃 (Toast/确认胶囊等) 的降级通道
    func axGlass(_ radius: CGFloat) -> some View {
        GlassModifier(radius: radius, circle: false).modify(self)
    }
    /// 圆形玻璃 (AppLock/门禁盾) 的降级通道
    func axGlassCircle() -> some View {
        GlassModifier(radius: 0, circle: true).modify(self)
    }
}

private struct GlassModifier: ViewModifier {
    let radius: CGFloat
    let circle: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        // 读系统旗标 (比 AXFlags 静态读更稳, 随环境更新); 降低透明度时降为实底
        if reduceTransparency {
            if circle {
                content.background(DS.Palette.surface, in: Circle())
                    .overlay(Circle().strokeBorder(DS.Palette.hairlineStrong, lineWidth: 0.5))
            } else {
                let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
                content.background(DS.Palette.surface, in: shape)
                    .overlay(shape.strokeBorder(DS.Palette.hairlineStrong, lineWidth: 0.5))
            }
        } else {
            if circle {
                content.glassEffect(.regular, in: Circle())
            } else {
                let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
                content.glassEffect(.regular, in: shape)
            }
        }
    }
}

// ---------- 871 命中域扩容: 44pt 基础上再留 10pt 余量 (时间线行次级按钮 60pt) ----------
extension View {
    func axHit60() -> some View {
        frame(minWidth: DS.Hit.min + 16, minHeight: DS.Hit.min + 16)
            .contentShape(Rectangle())
    }
}
