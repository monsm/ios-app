// 包7 安全·隐私·审计 — 安全中心 (独立挂载入口, 不侵入既有页面)
// 四分区: 应用锁升级 / 防窥 / 审计留痕 / 数据销毁
// 配置一律 kf_ 前键经 DB.store getString/set 读写 (与 SettingsView 同款范式), 不改 Store。
// 例外 (第一百批): 376/377/383/296 这一族五枚开关的**读侧**统一走 App/Core/LockGuard.swift 的 SecurityPolicy
// (唯一判据口) —— 这五枚此前"只改标签不改变行为"就是因为读点散在本页的文案里, 界面读到的是自己写的那句;
// 写侧仍是 DB.store.set, 键语义与小程序互通不变。
// 接线说明: 后续由 SettingsView 的"安全" Section 加一行
//   NavigationLink("安全中心") { SecurityCenterView() }
// 本文件自含 NavigationStack, 也可独立弹出验证。
import SwiftUI
import UIKit

// ---------- 存储键常量 (包7 专属族, 与 Store 既有键无碰撞) ----------
// 一律 String 常量, 供 DB.store getString/set 直接使用
enum SecKey {
    static let lockCoolOn     = "kf_slock_coolon"      // 389/234 递增冷却总开关
    static let lockStreak     = "kf_slock_streak"       // 连败计数 (冷却 = 30s * 2^n)
    static let lockUntil      = "kf_slock_lockuntil"    // 冷却锁至时刻
    static let lockTiming     = "kf_slock_timing"       // 393 "" 退后台即锁 / m1 / m5 / next
    static let graceOn        = "kf_slock_graceon"      // 394 短时免验总开关
    static let graceSec       = "kf_slock_gracese"      // 394 免验窗口 (秒)
    static let rescueOn       = "kf_srescue_on"         // 395 一次性救援码启用
    static let rescueCode     = "kf_srescue_code"       // 395 码值 (消费后清空)
    static let rescueSeen     = "kf_srescue_seen"       // 395 已手抄确认
    /// 396 前提标记: 本机密码确认为纯数字 (设/改密码时写)。标记为假时锁屏页不出现随机键盘,
    /// 否则历史遗留的含字母密码用户将永远输不进去 = 自己把自己锁死。
    static let randKeyDigits  = "kf_slock_randdig"
    static let decoyOn        = "kf_sdecoy_on"          // 390 伪装模式启用
    static let decoyCode      = "kf_sdecoy_code"        // 390 伪装口令 (明文仅本机)
    static let duressOn       = "kf_sduress_on"         // 391 胁迫码启用
    static let duressCodeRaw  = "kf_sduress_code"       // 391 胁迫码明文 (本机)
    static let duressAt       = "kf_sduress_at"         // 391 最近打标时刻
    static let traceOn        = "kf_strace_on"          // 392 失败留痕总开关
    static let traceEvents    = "kf_strace_events"      // 392 失败事件 [String]
    static let sessionAt      = "kf_sses_at"            // 398 会话开始时刻
    static let sessionHow     = "kf_sses_how"           // 398 验证方式
    static let sessionDuress  = "kf_sses_duress"        // 391 会话胁迫打标
    static let maskStyle      = "kf_smask_style"        // 369 "" 圆点 / stars / tail4
    static let bgBlurOn       = "kf_speek_bgblur"       // 371 切后台即糊
    static let timedReveal    = "kf_speek_timedsec"     // 373 限时可见秒数 (0=关)
    static let frostedOn      = "kf_speek_frost"        // 375 磨砂挡片
    static let shareHalfOn    = "kf_speek_sharehalf"    // 376 分享遮半
    static let guestOn        = "kf_speek_guest"        // 377 访客通道
    static let sensitiveOnly  = "kf_speek_glast"        // 377 访客模式隐藏敏感成员开关
    static let watermarkOn    = "kf_swmark_on"          // 378 常驻水印
    static let watermarkTxt   = "kf_swmark_txt"         // 378 水印文案种子
    static let auditRetention = "kf_saudit_months"      // 385 保留期 (0=永久)
    static let sudoOn         = "kf_saudit_sudo"        // 383 毁灭操作 sudo 口令
    static let safeModeOn     = "kf_sdest_safemode"     // 296 只读安全模式
    static let pwdReuseOn     = "kf_sdest_reuseon"      // 549 口令复用检测
}

// ---------- 配置变更广播: 子页写完 kf_ 键后 bump, 各页派生文案 2s 节拍内刷新 ----------
@MainActor
final class SecTickCenter: ObservableObject {
    static let shared = SecTickCenter()
    @Published private(set) var tick = 0
    func bump() { tick &+= 1 }
}
// ---------- 383 毁灭动作的前置复核 (sudo) ----------
/// 383 口令复核的唯一落地: 判据口验 (SecurityPolicy.sudoTicket) + 验不过按 389/392 那条既有失败通道记一笔。
/// 副作用如实写在这里: sudo 输错与主锁屏输错共用同一条连败计数与冷却, 因为试的是同一把口令 ——
/// 不给这条共用的话, 销毁按钮就成了绕过 389 递增冷却的第二个试错面。
@MainActor
func sudoTicketFromReview(_ input: String) -> SudoTicket? {
    guard let ticket = SecurityPolicy.sudoTicket(from: input) else {
        if !input.isEmpty { LockGuard.registerFailure() }
        return nil
    }
    return ticket
}

/// 383 毁灭操作的当场复核 —— 2026-10-17 拍板 A: **只走面容/指纹**, 不再问本机密码。
/// 原实现弹 UIAlertController 收口令再 `SecurityPolicy.sudoTicket(from:)` 比对摘要;
/// 口令这个凭据已随启动门禁一起删掉, 所以这里换成一次生物识别, 通过即发同一张 SudoTicket。
/// 开关关着就直放行: 这一支的存在才是这枚开关的意义 —— 关着少一道确认, 开着一定拦得住。
@MainActor
func askSudoThen(_ app: AppState, then action: @escaping () -> Void) {
    guard SecurityPolicy.sudoRequired else { action(); return }
    if app.sudoTicket != nil { action(); return }
    Task { @MainActor in
        let ok = await AuthKit.verifyBiometricAsync(reason: "这是毁灭级操作, 请用面容/指纹确认")
        guard ok, let ticket = SecurityPolicy.sudoTicketBiometric(ok) else {
            app.showToast("未通过面容/指纹确认, 已拒绝毁灭操作")   // 383 未通过确认
            return
        }
        app.sudoTicket = ticket
        AuditLog().append(.admin, "sudo", target: "毁灭操作复核通过",
                          operator_: "面容/指纹",
                          duress: DB.store.getBool(SecKey.sessionDuress, false))
        SecTick.bump()
        action()
    }
}

/// 296 + 383 两道闸的合用写法: 先问"只读模式下准不准做", 再问"要不要重输口令"。
/// 顺序是定的: 只读模式开着时连复核都不该问 (问了也做不成, 那是白打扰)。
@MainActor
func guardedDestroy(_ app: AppState, _ action: @escaping () -> Void) {
    guard SecurityPolicy.allows(.destroy) else {
        app.showToast(SecurityPolicy.denialMessage(.destroy))
        return
    }
    askSudoThen(app, then: action)
}

/// 377 访客通道的**唯一写侧**: 落键之后必须把会话级授权一起收回。
/// 拨开关的人此刻正站在受限的那一页上 (设置页 = Tab 3), AppState.revokeSessionGrants 会把
/// 选中位 snap 回设备页 —— 不并这一脚就是一句"翻了标签但层级树还没收"的空承诺。
/// 防窥页那枚 Toggle 与隐私仪表盘那枚轻点即切换的格子都走这里, 别留第二条只落键的侧门。
@MainActor
func setGuestChannel(_ on: Bool, app: AppState) {
    DB.store.set(SecKey.guestOn, on)
    app.revokeSessionGrants()
    app.showToast(on ? "访客通道已生效: 已回到设备页, 想进钥匙与设置要用面容/指纹确认"   // 377 访客通道已生效
                      : "访客通道已关闭: 四页照常, 本次会话内不再复核")   // 377 访客通道已关闭
}

// ---------- 378 常驻水印层 (截图加扰降级案: 页面常驻, 半透明对角重复) ----------
struct SecurityWatermark: View {
    var seed: String
    /// 水印是画在 `Canvas` 里的 `Text`：`GraphicsContext.draw` 收 `Text`，**不收 `some View`**，
    /// 所以这里不能写 `.xFontExact(...)`（它返回的是 `some View`），改取排版语法的
    /// `Font` 结果——`VKTypography.font(...)` 与 `.vkFont` 是**同一个实现处**。
    var body: some View {
        Canvas { ctx, size in
            let tile: CGFloat = 120
            let stampFont = Font.caption2
            let stamp = seed.isEmpty ? "离线锁管家 \(Date().formatted(.dateTime.year().month().day()))" : seed
            var row = 0
            var y: CGFloat = -tile / 3
            while y < size.height + tile {
                var x: CGFloat = row.isMultiple(of: 2) ? 0 : -tile / 2
                while x < size.width + tile {
                    var t = ctx
                    t.translateBy(x: x, y: y)
                    t.rotate(by: .degrees(-18))
                    t.opacity = 0.05   // 装饰层: 只留潜意识, 不破正文对比度 (颜色仍取 text 令牌的动态色)
                    t.draw(Text(stamp).font(stampFont).foregroundStyle(XPalette.text), at: .zero)
                    x += tile
                }
                y += tile / 1.6
                row += 1
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}




// 2026-10-24 已删除 SecurityPeekView（用户裁定：不需要防窥功能）



// 2026-10-24 精简：SecurityAuditView 已删（原 App 无此功能）


// 2026-10-24 精简：SecurityDestroyView 已删（原 App 无此功能）



// 2026-10-24 已删除 PrivacyDashboard（用户裁定：不需要防窥功能）



// ---------- 通用行组件 (触达 ≥44pt, 颜色只走 DS 令牌) ----------
struct SecRow<Trailing: View>: View {
    private let title: String
    private let subtitle: String
    private let icon: String
    private let iconTone: XToneColor
    private let trailing: Trailing

    init(title: String, subtitle: String = "", icon: String = "circle.fill",
         iconTone: XToneColor = .neutral, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconTone = iconTone
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: XSpace.s) {
            Image(systemName: icon)
                .font(.system(size: XIcon.sm, weight: .medium))
                .foregroundStyle(iconTone.color)
                .frame(width: XIcon.md, height: XIcon.md)
            VStack(alignment: .leading, spacing: XSpace.xxs) {
                Text(title)
                    .xFont(.subheadline, weight: .medium)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .xFont(.footnote)
                        .foregroundStyle(XPalette.textSub)
                }
            }
            Spacer(minLength: XSpace.s)
            trailing
        }
        .frame(minHeight: XHit.min)
        .contentShape(Rectangle())
    }
}


enum SecTick {
    @MainActor static func bump() { SecTickCenter.shared.bump() }
}


// ---------- 主入口 ----------
// 审计流水的时间戳格式 (原 SecurityLockConfigView.dateStr 的落点: 那个页随应用锁一起删了,
// 但 SecurityAuditView 还在用它, 所以搬成一个独立的小工具, 不复制第二份格式串)。
enum SecFmt {
    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    static func dateStr(_ t: Double) -> String {
        fmt.string(from: Date(timeIntervalSince1970: t))
    }
}
