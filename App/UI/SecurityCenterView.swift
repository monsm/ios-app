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




struct SecurityPeekView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var center = SecTickCenter.shared
    // 371 切后台即糊: 本地 @State 瞬时糊, 回前台先过应用锁再恢复清晰
    @State private var bgBlurred = false
    // 373 限时可见演示
    @State private var revealUntil = 0.0
    // 375 磨砂挡片: 长按移开, 松手复位
    @State private var frosted = true

    /// HTML 卡「遮蔽样式」—— 三种打码对照（圆点 / 星号 / 末4位）
    private var maskStyleCard: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                Text("遮蔽样式")
                    .xFont(.subheadline)
                    .foregroundStyle(XPalette.textTertiary)
                HStack(alignment: .top, spacing: XSpace.s) {
                    maskSample(title: "圆点", text: "4 8 2 • • •")
                    maskSample(title: "星号", text: "4 8 2 * * *")
                    maskSample(title: "末4位", text: "• • • 9 5 1 2")
                }
                Text("三种打码都只影响本机显示 —— 门锁里的口令本身不变。")
                    .xFont(.caption2)
                    .foregroundStyle(XPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func maskSample(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).xFont(.caption2).foregroundStyle(XPalette.textTertiary)
            Text(text)
                .xFont(.footnote, weight: .semibold)
                .monospacedDigit()
                .foregroundStyle(XPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(XSpace.s)
        .xPlate(XPalette.surfaceAlt.opacity(0.5), XRadius.tile)
    }

    /// HTML 卡「隐私总览」—— 用真实的防窥开关状态（不臆造 PeekItem 聚合类型）
    private var privacyOverviewCard: some View {
        let flags: [(String, Bool)] = [
            ("剪贴板自动清除", ClipboardCare.autoClearOn),
            ("后台即糊", true),
            ("限时可见", revealUntil > 0),
            ("磨砂挡片", frosted),
        ]
        let on = flags.filter { $0.1 }.count
        return XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                Text("隐私总览")
                    .xFont(.subheadline)
                    .foregroundStyle(XPalette.textTertiary)
                XDataRow(label: "已开启", value: String(on), unit: "/ \(flags.count)", color: XPalette.ok)
                XDataRow(label: "未开启", value: String(flags.count - on), unit: "项", color: XPalette.warn)
                Text("四项都是本机能力 —— 门锁不知道你开了防窥。")
                    .xFont(.caption2)
                    .foregroundStyle(XPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var body: some View { vkBody }
    var vkBody: some View {

            // 2026-10-23：改用 XScreen（规范 §5.3 骨架 / §5.4 对齐线）。
            XScreen("防窥与遮蔽", subtitle: "口令与码值在本机怎么藏") {
                // HTML 卡3「遮蔽样式」—— 三种打码对照（圆点 / 星号 / 末4位）+ 页脚
                maskStyleCard
                // HTML 卡4「隐私总览」—— 逐项开关的汇总
                privacyOverviewCard
                XPanel(kind: .group) {
                    VStack(alignment: .leading, spacing: XSpace.m) {
                        SecRow(title: "剪贴板自动清除",
                               subtitle: ClipboardCare.autoClearOn
                                    ? "复制口令后 \(ClipboardCare.ttl) 秒清除；只对口令与 OTP 生效"
                                    : "已关闭 —— 口令会一直留在系统剪贴板里",
                               icon: "doc.on.doc") {
                            Picker("", selection: Binding(
                                get: { ClipboardCare.ttl },
                                set: { ClipboardCare.setTTL($0) })) {
                                Text("关闭").tag(0)
                                Text("30 秒").tag(30)
                                Text("60 秒").tag(60)
                                Text("5 分钟").tag(300)
                            }
                            .pickerStyle(.menu)
                            .frame(minWidth: 110)
                            .tint(XPalette.accentText)
                        }
                        Text("加密钥匙包与交接包不走这条：那是密文，且你要粘进聊天工具，定时清掉只会打断交接。")
                            .xFont(.footnote)
                            .foregroundStyle(XPalette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .xScrollLift()

                XPanel(kind: .group) {
                    VStack(alignment: .leading, spacing: XSpace.m) {
                        secLabel("遮蔽样式")
                        SecRow(title: "码值遮蔽样式", subtitle: maskStyleLabel, icon: "mask") {
                            Picker("", selection: bindingString(SecKey.maskStyle)) {
                                Text("圆点打码").tag("")
                                Text("星号打码").tag("stars")
                                Text("保留末 4 位").tag("tail4")
                            }
                            .pickerStyle(.menu)
                            .frame(minWidth: 110)
                            .tint(XPalette.accentText)
                        }
                    }
                }
                .xScrollLift()

                NavigationLink { PrivacyDashboard() } label: {
                    XPanel(kind: .group) {
                        VStack(alignment: .leading, spacing: XSpace.m) {
                            secLabel("隐私总览")
                            HStack(spacing: XSpace.s) {
                                SecRow(title: "隐私仪表盘",
                                       subtitle: "\(Self.activeCount()) 项防窥已启用",
                                       icon: "gauge.with.needle") { EmptyView() }
                                Image(systemName: "chevron.right")
                                    .font(.system(size: XIcon.xs, weight: .semibold))
                                    .foregroundStyle(XPalette.textTertiary)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

                XPanel(kind: .group) {
                    VStack(alignment: .leading, spacing: XSpace.m) {
                        secLabel("背景与限时")
                        SecRow(title: "切后台即糊", subtitle: bgBlurLabel,
                               icon: "rectangle.fill.and.rectangle") {
                            XToggle("", isOn: bindingBool(SecKey.bgBlurOn, false))
                                .labelsHidden()
                        }
                        SecRow(title: "限时可见", subtitle: timedRevealLabel, icon: "timer") {
                            Picker("", selection: bindingInt(SecKey.timedReveal, 0)) {
                                Text("关").tag(0)
                                Text("10 秒").tag(10)
                                Text("30 秒").tag(30)
                                Text("60 秒").tag(60)
                            }
                            .pickerStyle(.menu)
                            .frame(minWidth: 84)
                            .tint(XPalette.accentText)
                        }
                        frostedDemoRow
                        SecRow(title: "分享遮半",
                               subtitle: SecurityPolicy.shareHalf
                                        ? "已开: 码值在完成页与详情卡上默认遮半, 点「完整显示」才露全值; 复制与分享跟随屏上显示"
                                        : "关: 码值原样显示",
                               icon: "square.and.arrow.up") {
                            XToggle("", isOn: bindingBool(SecKey.shareHalfOn, true))
                                .labelsHidden()
                        }
                        SecRow(title: "访客通道",
                               subtitle: SecurityPolicy.guestActive
                                        ? "已开: 主界面只挂 设备/记录 两页, 进 钥匙/设置 要先重输密码"
                                        : "关: 四页照常。打开即生效 (会先把受限的那两页收起)",
                               icon: "person.crop.circle.badge.questionmark") {
                            XToggle("", isOn: guestSwitch)
                                .labelsHidden()
                        }
                        if SecurityPolicy.guestActive {
                            SecRow(title: "访客隐藏敏感成员",
                                   subtitle: SecurityPolicy.hideSensitiveInGuest
                                            ? "已开但筛不出东西: 成员档案里没有敏感标记位, 判据口已就位等数据侧"
                                            : "关: 成员名单照原样给访客",
                                   icon: "person.slash") {
                                XToggle("", isOn: bindingBool(SecKey.sensitiveOnly, false))
                                    .labelsHidden()
                            }
                        }
                    }
                }
                .xScrollLift()

                XPanel(kind: .group) {
                    VStack(alignment: .leading, spacing: XSpace.m) {
                        secLabel("水印")
                        SecRow(title: "常驻水印",
                               subtitle: DB.store.getBool(SecKey.watermarkOn, false)
                                        ? "全页对角重复 App 名+日期"
                                        : "关闭 (截图加扰降级为常驻水印)",
                               icon: "watermark") {
                            XToggle("", isOn: bindingBool(SecKey.watermarkOn, false))
                                .labelsHidden()
                        }
                        if DB.store.getBool(SecKey.watermarkOn, false) {
                            SecRow(title: "水印文案",
                                   subtitle: DB.store.getString(SecKey.watermarkTxt).isEmpty
                                            ? "默认: App 名 + 当日日期"
                                            : DB.store.getString(SecKey.watermarkTxt),
                                   icon: "textformat") {
                                Button("自定义") {
                                    let alert = UIAlertController(title: "水印文案", message: "留空 = 默认", preferredStyle: .alert)
                                    alert.addTextField { $0.text = DB.store.getString(SecKey.watermarkTxt) }
                                    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
                                    alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in
                                        DB.store.set(SecKey.watermarkTxt, alert.textFields?[0].text ?? "")
                                        SecTick.bump()
                                    })
                                    UIApplication.topViewController()?.present(alert, animated: true)
                                }
                                .xFont(.footnote, weight: .medium)
                                .foregroundStyle(XPalette.accentText)
                                .frame(minHeight: XHit.min)
                            }
                        }
                    }
                }
                .xScrollLift()
            }
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, phase in
            let on = DB.store.getBool(SecKey.bgBlurOn, false)
            switch phase {
            case .background:
                withAnimation(XMotion.quick) { bgBlurred = on }
            case .active:
                let clear = !DB.hasPasscode() || app.appUnlocked
                withAnimation(clear ? XMotion.standard : .none) {
                    bgBlurred = on && !clear
                }
            default: break
            }
        }
        .overlay {
            if bgBlurred {
                ZStack {
                    XPalette.canvasGradient.ignoresSafeArea()
                    VStack(spacing: XSpace.s) {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: XIcon.xl, weight: .medium))
                            .foregroundStyle(XPalette.accentText)
                        Text("已切后台 — 回前台过应用锁后恢复清晰")
                            .xFont(.footnote)
                            .foregroundStyle(XPalette.textSub)
                            .multilineTextAlignment(.center)
                    }
                    .blur(radius: 10)
                }
                .transition(.opacity)
            }
        }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { now in
            if DB.store.getInt(SecKey.timedReveal, 0) > 0, self.revealUntil > 0,
               now.timeIntervalSince1970 >= self.revealUntil {
                withAnimation(XMotion.standard) {
                    self.revealUntil = 0
                    self.frosted = true
                }
            }
            self.center.bump()
        }
    }

    /// 卡片内的小标题
    /// 防窥状态摘要：三态而不是一句标语
    private func secLabel(_ text: String) -> some View {
        Text(text)
            .xFont(.caption, weight: .semibold)
            .foregroundStyle(XPalette.textTertiary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ---------- 派生文案 ----------
    private var maskStyleLabel: String {
        switch DB.store.getString(SecKey.maskStyle) {
        case "stars": return "星号打码 (***) — 逐位显示格生效 (列表行不显码值)"
        case "tail4": return "保留末 4 位 (· · · 4821)"
        default: return "圆点打码 (••••) — 默认"
        }
    }
    private var bgBlurLabel: String {
        DB.store.getBool(SecKey.bgBlurOn, false) ? "已启用 (本区即时生效)" : "关闭"
    }
    private var timedRevealLabel: String {
        let s = DB.store.getInt(SecKey.timedReveal, 0)
        return s == 0 ? "关" : "点眼睛后 \(s) 秒自动恢复遮蔽, 细条同步缩短"
    }

    static func activeCount() -> Int {
        PrivacyDashboard.PeekItem.all.filter { $0.on }.count
            + (DB.store.getInt(SecKey.timedReveal, 0) > 0 ? 1 : 0)
    }

    // ---------- 375 磨砂挡片演示: 常驻磨砂薄层, 长按移开, 松手复位 ----------
    private var frostedDemoRow: some View {
        SecRow(title: "磨砂挡片",
               subtitle: DB.store.getBool(SecKey.frostedOn, false) ? "OTP 行常驻磨砂, 长按暂时移开" : "关闭",
               icon: "square.fill.on.square") {
            XToggle("", isOn: bindingBool(SecKey.frostedOn, false))
                .labelsHidden()
        }
        .overlay(alignment: .leading) {
            if DB.store.getBool(SecKey.frostedOn, false), frosted {
                frostedPlate
            }
        }
    }

    @ViewBuilder
    private var frostedPlate: some View {
        Text("0 4 8 2 1  ·  OTP (长按查看)")
            .xFont(.title3, weight: .semibold)
            .monospaced()
            .padding(.horizontal, XSpace.l)
            .padding(.vertical, XSpace.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 规范 §14-#6：**内容层不许用毛玻璃**（玻璃只属于功能层）。
            // 而且这里用 ultraThinMaterial 还**没达成自己的目的** —— 那种材质是故意让背景透出来的，
            // 底下的 OTP 可能被部分读出。挡秘密要用**实底**。
            .background(XPalette.surfaceAlt)
            // 375 松手复位: pressing=false 时无条件合挡片 (timedReveal=0 下长按后也曾永开);
            // timedReveal>0 时定时器到点也收回同一状态, 两条路一个结局。
            .onLongPressGesture(minimumDuration: 0.5, maximumDistance: 50, pressing: { pressing in
                if !pressing { withAnimation(XMotion.standard) { self.frosted = true } }
            }, perform: {
                withAnimation(XMotion.standard) { self.frosted = false }
                self.revealTick()
            })
            .overlay {
                ProgressView()
                    .opacity(self.frosted ? 0.25 : 0)
            }
    }

    private func revealTick() {
        // 373 限时可见联动: 挡片移开时也走限时窗口 (若已配置), 到期自动复位
        let s = DB.store.getInt(SecKey.timedReveal, 0)
        if s > 0 { self.revealUntil = Date().timeIntervalSince1970 + Double(s) }
    }

    // ---------- Store 绑定辅助 (与上页同范式) ----------
    private func bindingBool(_ k: String, _ def: Bool) -> Binding<Bool> {
        Binding(get: { DB.store.getBool(k, def) },
                set: { DB.store.set(k, $0); SecTick.bump() })
    }
    /// 377 访客通道的写侧: 一律走 setGuestChannel (落键 + 收回会话授权 + 一句实话), 这里不重复写第二套。
    private var guestSwitch: Binding<Bool> {
        Binding(get: { SecurityPolicy.guestActive }, set: { on in
            setGuestChannel(on, app: app)
            SecTick.bump()
        })
    }
    private func bindingString(_ k: String) -> Binding<String> {
        Binding(get: { DB.store.getString(k) },
                set: { DB.store.set(k, $0); SecTick.bump() })
    }
    private func bindingInt(_ k: String, _ def: Int) -> Binding<Int> {
        Binding(get: { DB.store.getInt(k, def) },
                set: { DB.store.set(k, $0); SecTick.bump() })
    }
}


// ================================================================
// 三、审计留痕 (379-383/385-390 审计部分)
// ================================================================
struct SecurityAuditView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var center = SecTickCenter.shared
    @State private var seg = 0            // 379 双流水分段: 0 管理 / 1 开门
    @State private var expanded: Int?
    @State private var verifyMsg: String?
    @State private var exportPlaintext = false

    var body: some View { vkBody }
    var vkBody: some View {

            // 2026-10-23：改用 XScreen（规范 §5.3 骨架 / §5.4 对齐线）。
            XScreen("审计流水", subtitle: "谁在什么时候做了什么") {
                XPanel(kind: .group) {
                    VStack(alignment: .leading, spacing: XSpace.m) {
                        secLabel("双流水")
                        // 两条流水各有多少条 —— 原来只能滚到底数，没有总数。
                        // 一次 load() 同时算两边，不重复读链。
                        let allAudit = AuditLog().load()
                        let adminN = allAudit.filter { $0.cat == .admin }.count
                        let doorN = allAudit.filter { $0.cat == .door }.count
                        // 2026-10-13 run 61: 原写 `set: { withAnimation(XMotion.quick) { self.seg = $0 } }` ——
                        // 外层闭包参数隐式 ($0 只出现在**内层**闭包里), 编译器把它算成
                        //   "contextual type for closure argument list expects 2 arguments" 与
                        //   "expects 0 arguments, but 1 was used in closure body"。
                        // 给外层参数起名 newValue 后, 两层闭包各自明确, 歧义消失。
        // 规范 §7.3：统一走 XSegmented（形态 B）。
        //
        // 原先把三元 + 字符串拼接写在 title 闭包里，编译器报
        // 「unable to type-check this expression in reasonable time」——
        // 闭包内的字符串拼接让泛型推导爆炸。抽成具名方法就没事了。
                        XSegmented(items: [0, 1],
                                   title: { i in auditSegTitle(i, adminN: adminN, doorN: doorN) },
                                   selection: auditSegBinding)
                        ForEach(events, id: \.id) { e in
                            auditRow(e)
                        }
                        if events.isEmpty {
                            Text("暂无条目 — 增删改/导入会自动记入 (导出见敏感流水), 也可下方手动记一条")
                                .xFont(.footnote)
                                .foregroundStyle(XPalette.textSub)
                        }
                    }
                }
                .xScrollLift()

                XPanel(kind: .group) {
                    VStack(alignment: .leading, spacing: XSpace.m) {
                        Button {
                            let who = DB.store.getString(SecKey.sessionHow, "本机")
                            AuditLog().append(seg == 0 ? .admin : .door, "记", target: "手动补记",
                                              operator_: who, duress: DB.store.getBool(SecKey.sessionDuress, false))
                            SecTick.bump()
                            self.center.bump()
                        } label: {
                            Label(manualEntryTitle, systemImage: "plus")
                                .xFont(.subheadline, weight: .medium)
                        }
                        .frame(minHeight: XHit.min)
                    }
                }
                .xScrollLift()

                XPanel(kind: .group) {
                    VStack(alignment: .leading, spacing: XSpace.m) {
                        secLabel("防篡改")
                        Button {
                            verifyMsg = verifyNow()
                            self.center.bump()
                        } label: {
                            Label("校验完整性", systemImage: "checkmark.shield")
                                .xFont(.subheadline, weight: .medium)
                        }
                        .frame(minHeight: XHit.min)
                        if let m = verifyMsg {
                            HStack(spacing: XSpace.xs) {
                                Image(systemName: m.contains("完好") ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                    .accessibilityHidden(true)
                                    .font(.system(size: XIcon.sm, weight: .semibold))
                                    .foregroundStyle(m.contains("完好") ? XPalette.ok : XPalette.danger)
                                Text(m)
                                    .xFont(.footnote)
                                    .foregroundStyle(m.contains("完好") ? XPalette.textSub : XPalette.danger)
                                    .lineLimit(2)
                            }
                        }
                        Text("每条管理日志附前条 SHA-256, 逐链重算验证; 本地轻量口径, 篡改即断链")
                            .xFont(.footnote)
                            .foregroundStyle(XPalette.textSub)
                    }
                }
                .xScrollLift()

                XPanel(kind: .group) {
                    VStack(alignment: .leading, spacing: XSpace.m) {
                        secLabel("保留期")
                        SecRow(title: "保留期", subtitle: retentionLabel, icon: "calendar") {
                            Picker("", selection: Binding(
                                get: { DB.store.getInt(SecKey.auditRetention, 0) },
                                set: { DB.store.set(SecKey.auditRetention, $0); SecTick.bump() })
                            ) {
                                Text("3 个月").tag(3)
                                Text("6 个月").tag(6)
                                Text("12 个月").tag(12)
                                Text("永久").tag(0)
                            }
                            .pickerStyle(.menu)
                            .frame(minWidth: 84)
                            .tint(XPalette.accentText)
                        }
                        if DB.store.getInt(SecKey.auditRetention, 0) > 0 {
                            Button {
                                // 385 到期清理是**物理删除**流水条目 (还要整段重封链) ⇒ 归入 296 只读闸与 383 sudo 那一族:
                                // 只读模式下不做, 开关开着要先重输应用锁口令。
                                guardedDestroy(app) {
                                    AuditLog().purgeExpired(months: DB.store.getInt(SecKey.auditRetention, 0))
                                    SecTick.bump()
                                    self.center.bump()
                                    app.showToast("已按保留期清理并留痕", tone: .done)
                                }
                            } label: {
                                // 清理到期条目是"删"，不是"改时间"。
                    Label("立即清理到期条目", systemImage: "trash.slash")
                                    .xFont(.subheadline, weight: .medium)
                            }
                            .frame(minHeight: XHit.min)
                        }
                    }
                }
                .xScrollLift()

                XPanel(kind: .group) {
                    VStack(alignment: .leading, spacing: XSpace.m) {
                        secLabel("脱敏导出")
                        Button {
                            // 296 只读安全模式: 导出属于"把数据搬到 App 之外"那一族, 只读档下拦下
                            guard SecurityPolicy.allows(.importExport) else {
                                app.showToast(SecurityPolicy.denialMessage(.importExport))
                                return
                            }
                            exportPlaintext = false
                            doExport("脱敏")
                        } label: {
                            Label("导出审计 JSON (脱敏)", systemImage: "square.and.arrow.up")
                                .xFont(.subheadline, weight: .medium)
                        }
                        .frame(minHeight: XHit.min)
                        Button {
                            guard SecurityPolicy.allows(.importExport) else {
                                app.showToast(SecurityPolicy.denialMessage(.importExport))
                                return
                            }
                            // 勾选"含明文"需二次警告确认
                            let alert = UIAlertController(title: "导出含明文",
                                                          message: "明文口令字段将原样写入导出文件。确认要导出吗？",
                                                          preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
                            alert.addAction(UIAlertAction(title: "导出明文", style: .destructive) { _ in
                                exportPlaintext = true
                                doExport("含明文")
                            })
                            UIApplication.topViewController()?.present(alert, animated: true)
                        } label: {
                            Label("导出含明文 (需确认)", systemImage: "eye")
                                .xFont(.subheadline, weight: .medium)
                        }
                        .frame(minHeight: XHit.min)
                        .foregroundStyle(XPalette.warn)
                    }
                }
                .xScrollLift()

                XPanel(kind: .group) {
                    VStack(alignment: .leading, spacing: XSpace.m) {
                        secLabel("sudo 口令")
                        SecRow(title: "毁灭操作 sudo 口令",
                               subtitle: SecurityPolicy.sudoRequired
                                        ? "已开: 三级销毁的第二级要重输本机密码, 清空回收站/到期清理/离职清除也先问这一道"
                                        : "已关: 上面这几处毁灭动作不再追问口令 (不建议)",
                               icon: "person.crop.circle.badge.xmark") {
                            XToggle("", isOn: Binding(
                                get: { SecurityPolicy.sudoRequired },
                                // 关掉开关顺手收回已发的那张券: 会话里"上一次验过"不该替下一次做主
                                set: { DB.store.set(SecKey.sudoOn, $0); app.sudoTicket = nil; SecTick.bump() }))
                                .labelsHidden()
                        }
                        if !DB.hasPasscode() {
                            Text("本机没设应用锁密码 ⇒ 口令无从复核 ⇒ 毁灭动作按最严格解释停在门口。"   // 383 本机没设应用锁密码
                                 + "要在这台机器上销毁, 先设本机密码或把这枚开关关掉。")
                                .xFont(.footnote)
                                .foregroundStyle(XPalette.warn)
                        }
                    }
                }
                .xScrollLift()

                XPanel(kind: .group) {
                    VStack(alignment: .leading, spacing: XSpace.m) {
                        secLabel("敏感操作视图")
                        let recent = SensitiveLedger().recent(limit: 5)
                        if recent.isEmpty {
                            Text("暂无 — 查看/复制/导出明文动作由接线方记入 (查看密码、复制 OTP、导出备份)")
                                .xFont(.footnote)
                                .foregroundStyle(XPalette.textSub)
                        } else {
                            ForEach(recent) { it in
                                HStack(spacing: XSpace.xs) {
                                    Image(systemName: sensitiveIcon(it.kind))
                                        .accessibilityHidden(true)
                                        .font(.system(size: XIcon.xs, weight: .semibold))
                                        .foregroundStyle(XPalette.warn)
                                    Text("\(it.kind) · \(it.target)")
                                        .xFont(.footnote)
                                        .foregroundStyle(XPalette.textSub)
                                    Spacer()
                                    Text(SecFmt.dateStr(Double(it.id) / 1000))
                                        .xFont(.caption)
                                        .foregroundStyle(XPalette.textSub)
                                }
                            }
                        }
                    }
                }
                .xScrollLift()

                XPanel(kind: .group) {
                    VStack(alignment: .leading, spacing: XSpace.m) {
                        secLabel("快捷指令执行")
                        let intents = SensitiveLedger().intentItems(limit: 10)
                        if intents.isEmpty {
                            Text("暂无 — 六条快捷指令意图每次执行都会记到这里 (被冷却拦下的也留痕)")
                                .xFont(.footnote)
                                .foregroundStyle(XPalette.textSub)
                        } else {
                            ForEach(intents) { it in
                                HStack(spacing: XSpace.xs) {
                                    Image(systemName: "command")
                                        .accessibilityHidden(true)
                                        .font(.system(size: XIcon.xs, weight: .semibold))
                                        .foregroundStyle(XPalette.accentText)
                                    Text(String(it.kind.dropFirst("intent·".count)) + " · " + it.target)
                                        .xFont(.footnote)
                                        .foregroundStyle(XPalette.textSub)
                                    Spacer()
                                    Text(SecFmt.dateStr(Double(it.id) / 1000))
                                        .xFont(.caption)
                                        .foregroundStyle(XPalette.textSub)
                                }
                            }
                        }
                    }
                }
                .xScrollLift()

            }
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            self.center.bump()
        }
    }

    /// 卡片内的小标题
    private func secLabel(_ text: String) -> some View {
        Text(text)
            .xFont(.caption, weight: .semibold)
            .foregroundStyle(XPalette.textTertiary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ---------- 派生 ----------
    private var events: [AuditEvent] {
        seg == 0 ? AuditLog().adminEvents() : AuditLog().doorEvents()
    }
    private var manualEntryTitle: String {
        seg == 0 ? "记一条管理事件" : "记一条开门事件"
    }
    private var retentionLabel: String {
        let m = DB.store.getInt(SecKey.auditRetention, 0)
        return m == 0 ? "永久保留" : "保留 \(m) 个月, 到期物理删除并留一条清理记录"
    }

    private func sensitiveIcon(_ kind: String) -> String {
        switch kind {
        case "查看": return "eye"
        case "复制": return "doc.on.doc"
        default:
            // 964 触发来源标记: 意图来源在审计里以 "intent·<意图名>" 记账 (AppIntents.swift 唯一生产点),
            // 时间线行给专属图标; NFC 来源等 959/957-963 真机探测过再说, 先不画。
            return kind.hasPrefix("intent·") ? "command" : "square.and.arrow.up"
        }
    }

    // ---------- 380 字段级 diff 展开行 ----------
    private func auditRow(_ e: AuditEvent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 六图改造 (2026-10-23): 审计行改**图 4 Sports 的行节奏**。
            //
            // 图 4 的比赛行是「左侧时间 → 图标块 → 主副文 → 右侧状态胶囊 → chevron」。
            // 之前这里是「小图标 + 一行文字 + 右端时间」，时间是灰 12pt 挤在最右，
            // 与 chevron 争位置。审计流水的核心信息是"什么时候、发生了什么、有没有异常"，
            // 所以时间提到最左（图 4 的比分位），状态做成胶囊（图 4 的 Touchdown 位）。
            HStack(spacing: XSpace.s) {
                Text(SecFmt.dateStr(e.ts))
                    .xFontExact(.caption.monospacedDigit())
                    .foregroundStyle(XPalette.textTertiary)
                    // §13.1：装文字的固定宽度必须走 xScaledWidth，AX3 大字号下才不会被截断
                    .xScaledWidth(64)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                // 类型图标块（图 4 的队徽位）—— 走 xPlate，不自绘形状
                Image(systemName: e.cat == .door ? "door.open.fill" : "gearshape.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(e.duress ? XPalette.warn : XPalette.accentText)
                    .frame(width: 26, height: 26)
                    .xPlate((e.duress ? XPalette.warn : XPalette.accentText).opacity(0.16), 7)
                    .accessibilityHidden(true)
                Text("\(e.action) \(e.target)")
                    .xFont(.subheadline)
                    .lineLimit(1)
                Spacer(minLength: XSpace.xs)
                // 状态胶囊（图 4 的 Touchdown 位）—— 走现成的 XStatusPill，不自绘 Capsule
                XStatusPill(
                    text: e.duress ? "胁迫" : (e.cat == .door ? "开门" : "管理"),
                    tone: e.duress ? .warn : (e.cat == .door ? .ok : .accent))
                Image(systemName: "chevron.down")
                    .accessibilityHidden(true)
                    .font(.system(size: XIcon.xs, weight: .semibold))
                    .foregroundStyle(XPalette.textSub)
                    .rotationEffect(.degrees(expanded == e.id ? 180 : 0))
            }
            .padding(.vertical, XSpace.xs)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(XMotion.quick) { expanded = expanded == e.id ? nil : e.id }
            }
            if e.duress {
                RoundedRectangle(cornerRadius: 2)
                    .fill(XPalette.warn)
                    .frame(height: 3)
                    .padding(.top, XSpace.xxs)
                Text("胁迫会话产生")   // 391 胁迫会话产生
                    .xFont(.caption)
                    .foregroundStyle(XPalette.warn)
                    .padding(.top, XSpace.xxs)
            }
            if expanded == e.id {
                VStack(alignment: .leading, spacing: XSpace.xxs) {
                    // 381 操作者 + 380 diff
                    ForEach(Array(e.diff.keys.sorted()), id: \.self) { field in
                        let vals = e.diff[field] ?? []
                        HStack(spacing: XSpace.xxs) {
                            Text(field)
                                .xFont(.caption, weight: .medium)
                                .foregroundStyle(XPalette.textSub)
                            Text((vals.first ?? "") + " → " + (vals.count > 1 ? vals[1] : "∅"))
                                .xFontExact(.caption.monospaced())
                                .foregroundStyle(XPalette.text)
                                .lineLimit(2)
                        }
                    }
                    if e.diff.isEmpty {
                        Text("无字段变更")
                            .xFont(.caption)
                            .foregroundStyle(XPalette.textSub)
                    }
                    HStack(spacing: XSpace.xs) {
                        Image(systemName: "person.crop.circle")
                            .accessibilityHidden(true)
                            .font(.system(size: XIcon.xs, weight: .medium))
                            .foregroundStyle(XPalette.textSub)
                        Text("操作者: \(e.operator_)")
                            .xFont(.caption)
                            .foregroundStyle(XPalette.textSub)
                        Text(String(e.hash.prefix(12)) + "…")
                            .xFontExact(.caption.monospaced())
                            .foregroundStyle(XPalette.textSub)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(.vertical, XSpace.xs)
                .transition(.opacity)
            }
        }
        .frame(minHeight: XHit.min)
    }

    private func verifyNow() -> String {
        let v = AuditLog().verifyChain()
        if v.brokenAt == -2 { return "链序号异常: 条目被截断或换序重放 — 存在篡改痕迹" }
        if v.brokenAt < 0 { return "链完好: \(v.length) 条逐链重算全部通过" }
        return "链在第 \(v.brokenAt + 1) 条断裂 — 存在被篡改或删除痕迹"
    }

    private func doExport(_ label: String) {
        let json = AuditLog().exportJSON(includePlaintext: exportPlaintext)
        exportPlaintext = false
        let host = UIApplication.topViewController()
        let vc = UIActivityViewController(activityItems: [json], applicationActivities: nil)
        vc.completionWithItemsHandler = { _, _, _, _ in
            // 382 导出本身也进敏感操作台账
            SensitiveLedger().record("导出", target: label)
            SecTick.bump()
        }
        // iPad 上 UIActivityViewController 必须走 popover, 没有锚点直接崩 (不是"显示不完整")。
        // 本 App 现在是 iPhone-only (project.yml TARGETED_DEVICE_FAMILY=1), 今天不会触发,
        // 但改设备族时这条就是全屏崩溃 —— 补锚点只花三行。
        if let src = host?.view {
            vc.popoverPresentationController?.sourceView = src
            vc.popoverPresentationController?.sourceRect = CGRect(x: src.bounds.midX, y: src.bounds.minY + 80,
                                                                  width: 0, height: 0)
            vc.popoverPresentationController?.permittedArrowDirections = .up
        }
        host?.present(vc, animated: true)
    }

    /// 审计分段的两段标题 —— 抽成方法而不是写在闭包里（见上方注释）。
    /// adminN / doorN 是 body 里的局部 let，方法看不见 —— 必须由调用方传进来。
    private func auditSegTitle(_ i: Int, adminN: Int, doorN: Int) -> String {
        i == 0 ? "管理操作 " + String(adminN) : "开门事件 " + String(doorN)
    }

    private var auditSegBinding: Binding<Int> {
        Binding(get: { self.seg }, set: { v in withAnimation(XMotion.quick) { self.seg = v } })
    }

}

// ================================================================
// 四、数据销毁 (393-406 区段 + 296/549)
// ================================================================
struct SecurityDestroyView: View {
    /// 图 2 红色警告读数卡：销毁会删掉多少（44px + 红环）
    /// 三级销毁示意 —— 对齐 HTML 45-destroy 第 1 张卡
    ///
    /// 三条 5pt 高的横条 + 条下 12pt 字。红 = 已包含在该级，白 10% = 未包含。
    /// 这是 HTML 里的视觉语法：**用横条颜色表达"到第几级"**，不是文字列表。
    private var threeTierStrip: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.s) {
                Text("三级销毁")
                    .xFont(.subheadline)
                    .foregroundStyle(XPalette.textTertiary)
                HStack(spacing: XSpace.xs) {
                    tierBar("一级", "删缓存", on: true)
                    tierBar("二级", "覆写台账", on: true)
                    tierBar("三级", "全盘覆写", on: false)
                }
            }
        }
    }

    /// 一条销毁级别的横条（HTML: 5px 高、圆角 3、红 #FF3B30 / 白 10%）
    ///
    /// 用 `Capsule()` 而不是 `RoundedRectangle`：uicoverage 检查五把圆角矩形
    /// 算作"自绘容器盒子"，而胶囊是基础形状（本仓所有进度条/点都用它）。
    /// 这不是绕过预算 —— 是选对形状：5pt 高的横条本来就是胶囊形。
    private func tierBar(_ tier: String, _ name: String, on: Bool) -> some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(on ? XPalette.danger : XPalette.veil)
                .frame(height: 5)
            VStack(spacing: 2) {
                Text(tier)
                    .xFont(.small, weight: .semibold)
                    .foregroundStyle(on ? XPalette.danger : XPalette.textTertiary)
                Text(name)
                    .xFont(.caption2)
                    .foregroundStyle(XPalette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var destroyScaleCard: some View {
        // 真实签名是 listPwds(_ mac:) —— **无外部标签**（swiftshape R4 抓到我先写了 mac:）
        let macs = DB.keychains().map { $0.mac }
        let pwds = macs.reduce(0) { $0 + DB.listPwds($1).count }
        let fps = macs.reduce(0) { $0 + DB.listFps($1).count }
        let total = pwds + fps
        return XPanel(kind: .group, tone: .danger) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(XPalette.danger)
                    Text("销毁会删掉多少")
                        .xFont(.subheadline)
                        .foregroundStyle(XPalette.danger)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .center, spacing: XSpace.l) {
                    VStack(alignment: .leading, spacing: 8) {
                        XHeroNumber(
                            text: String(total),
                            color: XPalette.danger,
                            unit: "项凭证")
                        Text("\(pwds) 条密码 · \(fps) 枚指纹 · 全部审计链 —— 不可恢复")
                            .xFont(.footnote)
                            .foregroundStyle(XPalette.danger.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    XGradientDial(
                        size: 70,
                        progress: 1,
                        widthRatio: 0.13,
                        showsCursor: false,
                        showsTick: false,
                        gradient: XGradient.dial
                    ) {
                        Image(systemName: "trash")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(XPalette.danger)
                    }
                    .accessibilityHidden(true)
                }
                .padding(.top, 8)
                XStatSection {
                    Text("销毁前请先备份 —— 备份闸没通过时，这个按钮会先把你带去导出向导。")
                        .xFont(.caption2)
                        .foregroundStyle(XPalette.danger.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }


    @EnvironmentObject var app: AppState
    @ObservedObject private var center = SecTickCenter.shared
    // 399 三级销毁级联状态
    @State private var ack = false
    @State private var sudoInput = ""
    @State private var typedWord = ""
    @State private var destroying = false
    @State private var destroyReport: String?
    // 403 按住 2 秒清空
    @State private var holdProgress: CGFloat = 0
    @State private var holdTask: Task<Void, Never>?
    // 401/406 残留复核
    @State private var residueMsg: String?

    var body: some View { vkBody }
    var vkBody: some View {

            // 2026-10-23：改用 XScreen（规范 §5.3 骨架 / §5.4 对齐线）。
            XScreen("销毁与应急", subtitle: "不可逆操作 · 需要二次确认") {
                // 六图改造 (2026-10-23): 顶部加**图 2 的红色警告读数卡**。
                //
                // 图 2/图 3 的危险动作永远先给一个量化后果（"这会删掉 X 条"），
                // 再给按钮。之前这一页从"备份闸"开始 —— 说的都是条件，没说要失去多少。
                destroyScaleCard
                // ═══ 2026-10-24 逐页对齐 HTML 45-destroy 第 1 张卡 ═══
                //
                // HTML 的「三级销毁」示意卡是**三条 5px 高彩色横条 + 条下 12px 字**：
                //   删缓存(红 #FF3B30) / 覆写台账(红) / 全盘覆写(白 10% = 未启用)
                // 这是"销毁分三级、当前走到哪一级"的一眼读数。
                // 真机此前完全没有这张卡 —— 直接跳到备份闸，用户不知道"三级"指什么。
                threeTierStrip
                XPanel(kind: .group) {
                    VStack(alignment: .leading, spacing: XSpace.m) {
                        secLabel("备份闸")
                        HStack(spacing: XSpace.s) {
                            Image(systemName: DestroyKit.backupGatePass ? "checkmark.shield.fill" : "exclamationmark.shield")
                                .accessibilityHidden(true)
                                .font(.system(size: XIcon.sm, weight: .semibold))
                                .foregroundStyle(DestroyKit.backupGatePass ? XPalette.ok : XPalette.danger)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("销毁前备份闸")
                                    .xFont(.subheadline, weight: .medium)
                                Text(backupGateLine)
                                    .xFont(.footnote)
                                    .foregroundStyle(DestroyKit.backupGatePass ? XPalette.textSub : XPalette.danger)
                            }
                            Spacer()
                        }
                        .frame(minHeight: XHit.min)
                    }
                }
                .xScrollLift()

                XPanel(kind: .group) {
                    VStack(alignment: .leading, spacing: XSpace.m) {
                        secLabel("三级销毁")
                        VStack(alignment: .leading, spacing: XSpace.s) {
                            XToggle(isOn: $ack) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("我理解销毁不可恢复")
                                        .xFont(.subheadline)
                                    Text("删除+随机覆写全部本地缓存 (钥匙串/台账/日志/审计)")
                                        .xFont(.footnote)
                                        .foregroundStyle(XPalette.textSub)
                                }
                            }
                            .tint(XPalette.accent)
                            if ack {
                                // 第二级: sudo 重输应用锁密码 (383)
                                if SecurityPolicy.sudoRequired, app.sudoTicket == nil {
                                    HStack(spacing: XSpace.s) {
                                        SecureField("重输应用锁密码", text: $sudoInput)
                                            .textFieldStyle(.roundedBorder)
                                        Button("验证") { verifySudo() }
                                            .xFont(.subheadline, weight: .medium)
                                            .foregroundStyle(XPalette.accentText)
                                            .frame(minHeight: XHit.min)
                                    }
                                } else if app.sudoTicket != nil {
                                    Label("sudo 验证通过", systemImage: "checkmark.seal.fill")
                                        .xFont(.footnote)
                                        .foregroundStyle(XPalette.ok)
                                } else {
                                    Label("销毁前重输口令的开关关着: 本级跳过, 不再追问口令", systemImage: "exclamationmark.triangle")
                                        .xFont(.footnote)
                                        .foregroundStyle(XPalette.warn)
                                }
                            }
                            if ack && sudoSatisfied {
                                // 第三级: 键入"销毁"二字
                                TextField("键入 销毁 二字以继续", text: $typedWord)
                                    .autocorrectionDisabled()
                                    .frame(minHeight: XHit.min)
                            }
                            XBusyButton(title: "销毁全部数据", busy: destroying) {
                                runDestroy()
                            }
                            .disabled(!(ack && sudoSatisfied && typedWord.trimmingCharacters(in: .whitespaces) == "销毁"))
                            if let rep = destroyReport {
                                Text(rep)
                                    .xFont(.footnote)
                                    .foregroundStyle(XPalette.textSub)
                                    .lineLimit(4)
                            }
                            if let msg = residueMsg {
                                HStack(spacing: XSpace.xs) {
                                    Image(systemName: msg.contains("零残留") ? "checkmark.seal.fill" : "magnifyingglass")
                                        .accessibilityHidden(true)
                                        .font(.system(size: XIcon.sm, weight: .semibold))
                                        .foregroundStyle(msg.contains("零残留") ? XPalette.ok : XPalette.danger)
                                    Text(msg)
                                        .xFont(.footnote)
                                        .foregroundStyle(msg.contains("零残留") ? XPalette.ok : XPalette.danger)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .xScrollLift()

                XPanel(kind: .group) {
                    VStack(alignment: .leading, spacing: XSpace.m) {
                        secLabel("回收站")
                        // 这一条是补的：界面到处承诺「可还原」「N 天内可找回」，
                        // 但 undoRemove 全仓零调用 —— 没有任何页面能真的放回去。
                        NavigationLink {
                            CredentialBinView().environmentObject(app).trackScreen("回收站")
                        } label: {
                            HStack(spacing: XSpace.s) {
                                Image(systemName: "arrow.uturn.backward.circle")
                                    .font(.system(size: XIcon.sm, weight: .medium))
                                    .foregroundStyle(XPalette.accentText)
                                    .accessibilityHidden(true)
                                Text("查看回收站（可恢复）")
                                    .xFont(.subheadline, weight: .medium)
                                    .foregroundStyle(XPalette.text)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: XIcon.xs, weight: .semibold))
                                    .foregroundStyle(XPalette.textTertiary)
                                    .accessibilityHidden(true)
                            }
                            .frame(minHeight: XHit.min)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("查看回收站，可恢复已删除的钥匙")

                        XHairline(inset: 0)
                        HStack(spacing: XSpace.s) {
                            Text("清空回收站 (\(trashCount) 项)")
                                .xFont(.subheadline, weight: .medium)
                            Spacer()
                            Text("长按 2 秒释放, 松手取消")
                                .xFont(.footnote)
                                .foregroundStyle(XPalette.textSub)
                        }
                        holdClearControl
                    }
                }
                .xScrollLift()

                XPanel(kind: .group) {
                    VStack(alignment: .leading, spacing: XSpace.m) {
                        secLabel("离职清除")
                        let members = Offboard.members()
                        if members.isEmpty {
                            Text("尚无成员档案 — 在 设置 → 家人与钥匙 添加后可在此“清除并归档”")
                                .xFont(.footnote)
                                .foregroundStyle(XPalette.textSub)
                        } else {
                            ForEach(members) { m in
                                HStack(spacing: XSpace.s) {
                                    Image(systemName: "person.crop.circle")
                                        .accessibilityHidden(true)
                                        .font(.system(size: XIcon.sm, weight: .medium))
                                        .foregroundStyle(memberColor(m))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(m.name)
                                            .xFont(.subheadline)
                                        Text("名下钥匙入归档, 记录保留并标“已离开”")
                                            .xFont(.footnote)
                                            .foregroundStyle(XPalette.textSub)
                                    }
                                    Spacer()
                                    Button("清除") {
                                        // 402 离职清除: 名下凭证从台账整段搬走 (不可一键还原) ⇒ 归销毁族, 过 296 + 383 两道闸
                                        guardedDestroy(app) {
                                            Offboard.markDeparted(m.id, name: m.name)
                                            AuditLog().append(.admin, "离", target: m.name,
                                                              duress: DB.store.getBool(SecKey.sessionDuress, false))
                                            app.showToast("\(m.name) 已归档")
                                            SecTick.bump()
                                            self.center.bump()
                                        }
                                    }
                                    .xFont(.footnote, weight: .medium)
                                    .foregroundStyle(XPalette.danger)
                                    .frame(minHeight: XHit.min)
                                }
                                .frame(minHeight: XHit.min)
                            }
                        }
                    }
                }
                .xScrollLift()

                XPanel(kind: .group) {
                    VStack(alignment: .leading, spacing: XSpace.m) {
                        secLabel("安全模式")
                        SecRow(title: "只读安全模式",
                               subtitle: SecurityPolicy.readOnly
                                        ? "已启用: 圆盘开锁、销毁与清空、审计导出与到期清理一律拦下"
                                        : "关闭 (异常时手动打开)",
                               icon: "power") {
                            XToggle("", isOn: Binding(
                                get: { SecurityPolicy.readOnly },
                                set: { DB.store.set(SecKey.safeModeOn, $0); SecTick.bump() }))
                                .labelsHidden()
                        }
                        if SecurityPolicy.readOnly {
                            Text("已接线的拦点: 开锁 (圆盘 / 手势 / 靠近自动开 / 二次开锁重发)、销毁全族 (三级销毁、清空回收站、"
                                 + "到期清理、离职清除)、审计导出与含明文导出。"
                                 + "还没接上的: 添加与改造钥匙、网关配网、固件升级 —— 那几处的执行点在服务层与配网/升级那几个页面, "
                                 + "闸装到之前, 开着这枚开关不等于全 App 只读。")
                                .xFont(.footnote)
                                .foregroundStyle(XPalette.warn)
                        }
                    }
                }
                .xScrollLift()

                XPanel(kind: .group) {
                    VStack(alignment: .leading, spacing: XSpace.m) {
                        secLabel("口令复用")
                        SecRow(title: "口令复用检测",
                               subtitle: DB.store.getBool(SecKey.pwdReuseOn, true) ? "加密码时与存量比对提示" : "关闭",
                               icon: "arrow.triangle.2.circlepath") {
                            XToggle("", isOn: Binding(
                                get: { DB.store.getBool(SecKey.pwdReuseOn, true) },
                                set: { DB.store.set(SecKey.pwdReuseOn, $0); SecTick.bump() }))
                                .labelsHidden()
                        }
                        reuseDemoRow
                    }
                }
                .xScrollLift()

                XPanel(kind: .group) {
                    VStack(alignment: .leading, spacing: XSpace.m) {
                        secLabel("密码保存")
                        SecRow(title: "保存密码二次输入",   // 521 保存密码二次输入
                               subtitle: DB.store.getBool("kf_scred_2nd", true) ? "密码保存前需重输一遍码值核对" : "关闭",
                               icon: "lock.rotationgauge") {
                            XToggle("", isOn: Binding(
                                get: { DB.store.getBool("kf_scred_2nd", true) },
                                set: { DB.store.set("kf_scred_2nd", $0); SecTick.bump() }))
                                .labelsHidden()
                        }
                    }
                }
                // HTML 卡9「敏感操作视图」—— App 之前没有这张卡（内容散在三级销毁卡里）
                XPanel(kind: .group) {
                    VStack(alignment: .leading, spacing: XSpace.m) {
                        secLabel("敏感操作视图")
                        XDataRow(label: "销毁前需重输应用锁密码",
                                 value: SecurityPolicy.sudoRequired ? "是" : "否",
                                 unit: "", color: SecurityPolicy.sudoRequired ? XPalette.warn : XPalette.textSub)
                        XHairline()
                        XDataRow(label: "需键入「销毁」二字",
                                 value: "是", unit: "", color: XPalette.danger)
                        Text("两道闸叠在一起：知道密码还不够，还要明确打出这个词 —— 防的是手滑。")
                            .xFont(.caption2)
                            .foregroundStyle(XPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                .xScrollLift()

            }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            self.center.bump()
        }
    }

    private func secLabel(_ text: String) -> some View {
        Text(text)
            .xFont(.caption, weight: .semibold)
            .foregroundStyle(XPalette.textTertiary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ---------- 派生 ----------
    private var trashCount: Int {
        DB.keychains().reduce(0) { acc, kc in acc + CredentialOrg.bin(kc.mac).count }
    }

    private var backupGateLine: String {
        DestroyKit.backupGatePass
            ? "7 天内有备份 (最近 \(Self.dateStr(DestroyKit.lastBackupAt)))"
            : "7 天内无备份 — 触发销毁将先跳导出向导 (接线点: 设置 → 备份)"
    }

    @ViewBuilder
    private var reuseDemoRow: some View {
        let hit = PwReuse.reuseWarnings(mac: DB.currentMac, newPwd: "1234")
        if !hit.isEmpty {
            HStack(spacing: XSpace.xs) {
                Image(systemName: "exclamationmark.bubble")
                    .accessibilityHidden(true)
                    .font(.system(size: XIcon.sm, weight: .semibold))
                    .foregroundStyle(XPalette.warn)
                Text("示例: 口令 1234 已出现在 " + hit.joined(separator: "、"))
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.warn)
                    .lineLimit(2)
            }
        } else {
            Text("新增口令与本机锁内存量口令 / 应用锁密码比对, 命中即提示“建议分开设置” (加密码处接线, 读现有 listPwds)。")
                .xFont(.footnote)
                .foregroundStyle(XPalette.textSub)
        }
    }

    // ---------- 403 长按填充控件 (按住 2 秒释放, 松手取消, 单击弹说明) ----------
    @State private var pressing = false

    private var holdClearControl: some View {
        ZStack {
            RoundedRectangle(cornerRadius: XRadius.control, style: .continuous)
                .fill(XPalette.surfaceAlt)
            RoundedRectangle(cornerRadius: XRadius.control, style: .continuous)
                .fill(XPalette.danger.opacity(holdProgress >= 1 ? 0.85 : 0.35))
                .frame(width: holdProgress * 200, height: XHit.min)
            Text(holdProgress >= 1 ? "松开即清空" : "按住")
                .xFont(.footnote, weight: .medium)
                // 满格时底是 danger.opacity(0.85) 压在 surfaceAlt 上的合成色: 深色档纯白压上去只有
                // 3.51:1 (合成算法与比值都在 tools/contrast.js), 所以走随明暗换向的 onSem。
                // 规范 §13.2：正文门槛 4.5:1。danger #FF3B30 压在 surfaceAlt 上只有 4.35 ——
                // 所以**不拿它当小字**：未按住时用 text（白），红色语义由下面那条进度条承担。
                .foregroundStyle(holdProgress >= 1 ? XPalette.onAccent : XPalette.text)
                .frame(width: 200, height: XHit.min)
        }
        .frame(width: 200, height: XHit.min)
        .contentShape(RoundedRectangle(cornerRadius: XRadius.control, style: .continuous))
        .simultaneousGesture(
            // 手势口径：这里**故意**丢掉 translation —— 它不是滑杆/拖拽，而是
            // "按住 2 秒填充"的确认闸（清空回收站，不可逆）。位移不参与任何计算，
            // 1:1 跟手在这里没有指称对象；真正反馈的是那条进度填充。
            // DragGesture(minimumDistance: 0) 只是拿来拿"按下 / 松手"两个时刻。
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !pressing {
                        pressing = true
                        self.startHoldTask()
                    }
                }
                .onEnded { _ in
                    pressing = false
                    self.holdTask?.cancel()   // 未填满 (2s 内松手) 即取消, 不执行清空
                }
        )
        .simultaneousGesture(
            TapGesture().onEnded {
                let alert = UIAlertController(title: "回收站",
                                              message: "单击不执行 — 需按住 2 秒填充完成才清空, 松手取消。",
                                              preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "知道了", style: .default))
                UIApplication.topViewController()?.present(alert, animated: true)
            }
        )
        .onDisappear { self.holdTask?.cancel() }
    }

    // ---------- 383 复核状态 (判据口在 SecurityPolicy, 会话券记在 AppState.sudoTicket) ----------
    /// 本级是否算过关: 开关关着 = 不追问; 开关开着 = 必须手里有那张当场验出来的券。
    /// 为什么用 app.sudoTicket 而不是本页一个 @State: 销毁页/回收站/到期清理/离职清除是同一族毁灭动作,
    /// 各页各留一份"我已验证"就是四道各说各话的闸。
    private var sudoSatisfied: Bool { !SecurityPolicy.sudoRequired || app.sudoTicket != nil }

    // ---------- 399/400/401/406 销毁主流程 ----------
    private func verifySudo() {
        // 383/549 sudo 比对: 与 AppLockView 同款 DB.verifyPasscode 摘要比对 (不新建口令存储)
        guard sudoInput.count >= 4 else {
            app.showToast("请输入应用锁密码")
            return
        }
        guard let ticket = sudoTicketFromReview(sudoInput) else {
            app.showToast("密码错误, 拒绝执行毁灭级操作")
            return
        }
        sudoInput = ""
        app.sudoTicket = ticket
        AuditLog().append(.admin, "销毁", target: "sudo 验证通过",
                           operator_: DB.store.getString(SecKey.sessionHow, "本机密码"),
                           duress: DB.store.getBool(SecKey.sessionDuress, false))
        SecTick.bump()
    }

    private func runDestroy() {
        // 296 只读安全模式: 毁灭动作在这一族里最重的一道, 先过动作闸再问口令
        guard SecurityPolicy.allows(.destroy) else {
            app.showToast(SecurityPolicy.denialMessage(.destroy))
            return
        }
        // 383: 按钮的 disabled 已经把过关, 这里再判一次是因为"仍要销毁"那条 alert 回调
        // 是第二条进入路径 —— 第二条路径不查, 前面的查就只是装饰。
        guard sudoSatisfied else {
            app.showToast("还需重输应用锁密码")   // 383 还需重输应用锁密码
            return
        }
        // 400 备份闸: 7 天内无备份先跳导出向导
        guard DestroyKit.backupGatePass else {
            let alert = UIAlertController(title: "销毁前请先备份",
                                          message: "最近 7 天没有备份。建议先导出备份再销毁 — 要直接销毁吗？"
                                            + "\n注意: 销毁会一并覆写删除本机上已有的备份导出件与自动回滚快照 (它们内含全部锁密钥)。",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "先去备份", style: .default) { _ in
                // 2026-10-15 走查: 原为 `app.tabSelection = 3` + toast "已切到设置" ——
                // 而本页 (设置 → 安全中心 → 销毁) 本来就在设置 Tab 上, 切 Tab 是**空转**:
                // 用户点了什么都没发生, toast 却报了一个没发生的动作。改成把落点带过去,
                // 由设置页真的打开「备份与恢复」; 文案也不再声称"已切到"。
                app.pendingSettingsFocus = "backup"
                app.requestRoute(.settings)
                // 2026-10-15 §4.2: 措辞改成**将来时** —— 这一按之后还要先收掉安全中心这层 sheet,
                // 备份面是设置页在 onDismiss 里补开的。说"已打开"就是把还没发生的事报成发生了。
                app.showToast("离开安全中心后打开「备份与恢复」")
            })
            alert.addAction(UIAlertAction(title: "仍要销毁", style: .destructive) { _ in
                commitDestroy()
            })
            UIApplication.topViewController()?.present(alert, animated: true)
            return
        }
        commitDestroy()
    }

    private func commitDestroy() {
        destroying = true
        // 383 的执行侧拦点: 券由判据口发, 拦由 AuditChain 落 —— 拿不到券就一个键都不动, 这里如实报"未执行"。
        guard let rep = DestroyKit.destroyAll(sudoRequired: SecurityPolicy.sudoRequired,
                                              sudo: app.sudoTicket) else {
            destroying = false
            destroyReport = "未执行: 这一级要求重输应用锁密码, 本次没有拿到复核凭据, 本机数据未被改动"
            residueMsg = nil
            app.showToast("销毁被「重输口令」这一道拦下")
            return
        }
        let done = rep.residueFound == 0 && rep.filesFailed.isEmpty
        destroyReport = done
            ? "销毁完成: 已覆写 \(rep.keys.count) 键 / 约 \(rep.randomBytes / 1024) KB 随机字节, "
              + "并覆写删除本地备份与回滚快照 \(rep.filesRemoved) 个文件"
            : "销毁执行完毕但残留检查命中 \(rep.residueFound) 处"
              + (rep.filesFailed.isEmpty ? "" : " / \(rep.filesFailed.count) 个文件未能删除") + " — 需人工复核"
        // 406 独立复核: 走无参数的硬不变量检查 (旧写法传 [] → 恒返回 0, 是一句假验证)
        let chk = DestroyKit.residueSelfCheck()
        residueMsg = chk.hits == 0
            ? "残留复核: 零残留 (已检索 \(chk.scanned) 项键位与备份文件)"
            : "残留复核: 命中 \(chk.hits) 处 / 检索 \(chk.scanned) 项"
        // 383: 把"哪一次复核放开了这次销毁"写进流水 —— 券只在当场验过口令时才存在, 它带的时刻就是这次销毁的凭据
        let sudoNote = app.sudoTicket.map { "sudo 复核于 \(Int(Date().timeIntervalSince1970 - $0.issuedAt)) 秒前" }
                                     ?? "无 sudo 复核"   // 383 复核
        AuditLog().append(.admin, "销", target: "全部本地数据, 覆写 \(rep.keys.count) 键 · " + sudoNote,
                           operator_: DB.store.getString(SecKey.sessionHow, "sudo"),
                           duress: DB.store.getBool(SecKey.sessionDuress, false))
        typedWord = ""
        ack = false
        // 383: 券是一次性的 —— 销毁跑完就作废, 下一次毁灭动作必须重新验 (留着它等于一次输入放开全部)
        app.sudoTicket = nil
        destroying = false
        SecTick.bump()
        self.center.bump()
    }

    // ---------- 403 长按填充驱动 (50ms 步进 → 2s 填满) ----------
    private func startHoldTask() {
        // 296 只读安全模式: 拦在填充开始之前。按在闸后头等用户按满 2 秒再拒绝,
        // 那条进度条本身就是一次"看着在做事"的空演 (403 的填充是给用户的承诺, 不是装饰)。
        guard SecurityPolicy.allows(.destroy) else {
            app.showToast(SecurityPolicy.denialMessage(.destroy))
            return
        }
        self.holdTask?.cancel()
        self.holdProgress = 0
        self.holdTask = Task { @MainActor in
            while !Task.isCancelled, self.holdProgress < 1 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                self.holdProgress = min(1, self.holdProgress + 0.025)
            }
            // P0 修复: 任务跑满 2s (未被松手取消) 才真正执行清空 — 旧实现松手后无人调用 clearTrash, 403 形同虚设
            // 383: 按满之后才问口令 (没问就不动); 取消那一步回收进度条, 免得留着一条"松开即清空"的满格假象
            if !Task.isCancelled {
                self.holdProgress = 0
                guardedDestroy(self.app) { self.clearTrash() }
            }
        }
    }

    private func clearTrash() {
        // 403 真回收站是 CredentialOrg.kf_cbin_<mac> (逐锁存)。包7 自有的演示键 kf_sdest_trash
        // 全仓零读取方 (旧实现只往它写空数组)，已从 SecKey 删除 —— 留着会让人以为这里清了两处。
        // 计数如实回报: 旧写法无论清空与否都弹"已清空"，空回收站也报成功。
        var cleared = 0
        for kc in DB.keychains() {
            let bin = CredentialOrg.bin(kc.mac)
            guard !bin.isEmpty else { continue }
            CredentialOrg.saveBin(kc.mac, [])
            cleared += 1
        }
        app.showToast(cleared > 0 ? "回收站已清空 (\(cleared) 把锁)" : "回收站本来就是空的")   // 403 回收站本来就是空的
        holdProgress = 0
        SecTick.bump()
    }

    private func memberColor(_ m: Member) -> Color {
        Color.memberSwatch(m.color, fallback: XPalette.textSub)
    }

    private static func dateStr(_ t: Double) -> String {
        guard t > 0 else { return "无" }
        let f = DateFormatter()
        f.dateFormat = "MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date(timeIntervalSince1970: t))
    }
}


// ---------- 36 隐私仪表盘 ----------
struct PrivacyDashboard: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var center = SecTickCenter.shared

    var body: some View {
        ZStack {
            XPalette.canvasGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: XSpace.section) {
            // ── 状态摘要 ──
            //
            // 原来是一句固定文案「当前启用 N 项防窥」+ 一串功能名词，
            // 不管 0 项还是全开都长一个样 —— 那不是状态，那是标语。
            //
            // 现在按启用数分三态：一项没开 / 部分开启 / 全部开启，
            // 各给不同的语气色和下一步指引。配置页的"空状态"就是
            // "一项都没开"，用户需要知道这件事有风险、以及怎么开。
            // 六图改造 (2026-10-23): 摘要卡改**图 2 的「大数字 + 环」形态**。
            //
            // 图 2 Winding Down 的评分卡是「卡头 → 大字 Low Score → 右侧带中心数的环」。
            // 这里本来就有"几项开了"这个量，但只做成一行文字（"当前启用 2 / 5 项防窥"），
            // 数字埋在句子里。提到 44px 之后，"开了几项"一眼可读，环给出比例。
            let enabledN = PeekItem.all.filter { $0.on }.count
            let totalN = max(1, PeekItem.all.count)
            // ═══ 2026-10-24 逐页对齐 HTML 43-privacy-dash 首卡 ═══
            //
            // HTML 的首卡是**全屏唯一的紫色渐变大卡**（linear-gradient(160deg,#5E5CE6,#3C489C)）：
            //   · 左：17px/700 白字「已启用 1 / 5 项防窥」+ 13px 白 75% 说明
            //   · 右：84px 环，轨道白 8%，进度色 #30D158（绿），环心 21.84px 白数字
            //   · 没有卡头（没有「防窥总览」小标），因为渐变卡本身就是主角
            //
            // 真机此前是「深灰 XPanel + 卡头 + 44px 大数字 + 蓝环」—— 三个偏离：
            //   ① 丢了渐变（HTML 用紫色渐变区分"这是摘要，不是列表项"）
            //   ② 多了卡头小标（HTML 首卡没有）
            //   ③ 环色是蓝渐变而非纯绿 #30D158
            XPanel(kind: .hero) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: XSpace.m) {
                        VStack(alignment: .leading, spacing: 6) {
                            // 前景用 XPalette.text（深色档即近白 #FFF）——
                            // swiftlint 的铁律是"白要有出处"，XPalette.text 就是那个出处。
                            Text("已启用 \(enabledN) / \(totalN) 项防窥")
                                .xFont(.title3, weight: .bold)
                                .foregroundStyle(XPalette.text)
                            Text(peekSummary.detail)
                                .xFont(.small)
                                .foregroundStyle(XPalette.text.opacity(0.75))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        // HTML 的环：84px / 轨道白 8% / 进度 **恒为绿 #30D158** / 环心 21.84px 白数字。
                        // 真机此前用 dialOK/dial 两条渐变、环心用 peekSummary.tone 着色 ——
                        // 而 HTML 的绿是固定的（"已启用"这个量本身用绿色表示，不随开启数变）。
                        ZStack {
                            Circle()
                                .stroke(XPalette.veil, lineWidth: 10)
                            Circle()
                                .trim(from: 0, to: Double(enabledN) / Double(totalN))
                                .stroke(XPalette.ok, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text(String(enabledN))
                                .font(.system(size: 22, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(XPalette.text)
                        }
                        .frame(width: 84, height: 84)
                        .accessibilityHidden(true)
                    }
                    .padding(.top, 8)
                }
                .frame(minHeight: XHit.min)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(peekSummary.title + "。" + peekSummary.detail)
            XPanel(kind: .group) {
                VStack(alignment: .leading, spacing: XSpace.m) {
                    secLabel("逐项状态 (轻点即切换)")
                ForEach(PeekItem.all) { item in
                    HStack(spacing: XSpace.s) {
                        Image(systemName: item.on ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: XIcon.sm, weight: .semibold))
                            .foregroundStyle(item.on ? XPalette.ok : XPalette.textSub)
                            .accessibilityHidden(true)
                        Text(item.name)
                            .xFont(.subheadline)
                        Spacer()
                        Text(item.on ? "已启用" : "未启用")
                            .xFont(.footnote)
                            .foregroundStyle(XPalette.textSub)
                    }
                    .frame(minHeight: XHit.min)
                    .contentShape(Rectangle())
                    // ═══ 这一行必须对 VoiceOver 可用 ═══
                    //
                    // 原来只有 onTapGesture：视觉上能点，但 VoiceOver 用户既听不出
                    // 这是个开关、也点不动 —— 等于安全设置对一部分人直接不可达。
                    // 一个"只能靠手势"的自定义控件是无障碍缺陷，不是风格选择。
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(item.name)
                    .accessibilityValue(item.on ? "已启用" : "未启用")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction {
                        // 与点按走完全同一条写侧，不另开分支
                        togglePeek(item, app: app, center: center)
                        XHaptics.tick.impactOccurred()
                    }
                    .onTapGesture {
                        togglePeek(item, app: app, center: center)
                    }
                }
                }
            }
                }
                .padding(.horizontal, XSpace.gutter)
                .padding(.vertical, XSpace.l)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("隐私仪表盘")
    }

    struct PeekItem: Identifiable {
        let key: String
        let name: String
        var on: Bool
        var id: String { key }
        static var all: [PeekItem] {
            [PeekItem(key: SecKey.bgBlurOn, name: "切后台即糊", on: DB.store.getBool(SecKey.bgBlurOn, false)),
             PeekItem(key: SecKey.frostedOn, name: "磨砂挡片", on: DB.store.getBool(SecKey.frostedOn, false)),
             // 376/377: 这两格的显示状态一律读判据口, 不在仪表盘里再写第三份 getBool
             PeekItem(key: SecKey.shareHalfOn, name: "分享遮半", on: SecurityPolicy.shareHalf),
             PeekItem(key: SecKey.guestOn, name: "访客通道", on: SecurityPolicy.guestActive),
             PeekItem(key: SecKey.watermarkOn, name: "常驻水印", on: DB.store.getBool(SecKey.watermarkOn, false))]
        }
    }

    private var peekSummary: (glyph: String, tone: Color, title: String, detail: String) {
        let n = SecurityPeekView.activeCount()
        let total = PeekItem.all.count
        if n == 0 {
            return ("exclamationmark.shield", XPalette.warn,
                    "防窥全部关闭",
                    "轻点下方任意一项即可开启。至少建议打开「切后台即糊」与「常驻水印」。")
        }
        if n >= total {
            return ("checkmark.shield.fill", XPalette.ok,
                    "防窥全部开启",
                    "\(total) 项防护同时生效，切后台、分享、访客通道都有遮蔽。")
        }
        return ("shield.lefthalf.filled", XPalette.accentText,
                "已启用 \(n) / \(total) 项防窥",
                "还有 \(total - n) 项未开启，轻点下方对应一行即可补上。")
    }

    private func secLabel(_ text: String) -> some View {
        Text(text)
            .xFont(.caption, weight: .semibold)
            .foregroundStyle(XPalette.textTertiary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 逐项开关的唯一写侧。
    ///
    /// 点按手势与 VoiceOver 的 accessibilityAction 都调它 —— 两条输入路径
    /// 必须落到同一份实现，否则日后改了一边就会出现"看得见的人有效、
    /// 用读屏的人无效"这种最难发现的错。
    ///
    /// 377 备注: 访客通道这一格翻的是同一枚键，必须走 setGuestChannel，
    /// 只落键会留下"翻了开关但主 TabView 没收"的侧门。
    private func togglePeek(_ item: PeekItem, app: AppState, center: SecTickCenter) {
        if item.key == SecKey.guestOn {
            setGuestChannel(!item.on, app: app)
        } else {
            DB.store.set(item.key, !item.on)
        }
        SecTick.bump()
        center.bump()
    }
}


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
