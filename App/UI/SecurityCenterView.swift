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
    static let traceOn        = "kf_strace_on"          // 392 失败留痕总开关
    static let traceEvents    = "kf_strace_events"      // 392 失败事件 [String]
    static let sessionHow     = "kf_sses_how"           // 398 验证方式
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
@MainActor
enum SecTick {
    static func bump() { SecTickCenter.shared.bump() }
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
)
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
    app.showToast(on ? "访客通道已生效: 已回到设备页, 想进凭证与设置要用面容/指纹确认"   // 377 访客通道已生效
                      : "访客通道已关闭: 四页照常, 本次会话内不再复核")   // 377 访客通道已关闭
}

// ---------- 378 常驻水印层 (截图加扰降级案: 页面常驻, 半透明对角重复) ----------
struct SecurityWatermark: View {
    var seed: String
    /// 水印是画在 `Canvas` 里的 `Text`：`GraphicsContext.draw` 收 `Text`，**不收 `some View`**，
    /// 所以这里不能写 `.vkFont(...)`（它返回的是 `some View`），改取排版语法的
    /// `Font` 结果——`VKTypography.font(...)` 与 `.vkFont` 是**同一个实现处**。
    var body: some View {
        Canvas { ctx, size in
            let tile: CGFloat = 120
            let stampFont = VKTypography.font(.caption2, weight: nil)
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
                    t.draw(Text(stamp).font(stampFont).foregroundColor(DS.Palette.text), at: .zero)
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

// ---------- 主入口 ----------
// 审计流水的时间戳格式 (原 SecurityLockConfigView.dateStr 的落点: 那个页随应用锁一起删了,
// 本页各处共用同一个格式串, 不复制第二份)。
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

struct SecurityCenterView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var center = SecTickCenter.shared

    var body: some View { vkBody.destined(.securityCenter) }
    var vkBody: some View {
        NavigationStack {
            List {

                // 9 凭证风险体检 (Apple Passwords 那种风险卡): 只读扫描本机台账, 处置动作不在这里,
                // 而是指到凭证 Tab 的改码 (305/306) —— 这一页只回答"有没有该处理的"。
                Section {
                    let risks = CredentialOrg.passwordRisks()
                    if risks.isEmpty {
                        // 2026-10-14: 去掉标签里的规格编号 "(9)"。
                        Text("没有发现同值 / 超期 / 弱口令 —— 台账里的密码都还干净。")
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(risks.prefix(8)) { r in
                            HStack(alignment: .top, spacing: DS.Space.s) {
                                Image(systemName: r.kind == "同值" ? "doc.on.doc"
                                      : (r.kind == "超期" ? "clock.badge.exclamationmark" : "exclamationmark.shield"))
                                    .font(.system(size: DS.Icon.sm))
                                    .foregroundStyle(r.kind == "弱口令" ? DS.Palette.danger : DS.Palette.warn)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                                    Text("\(r.kind) · \(r.lockName) 密码 #\(r.alias)")
                                        .vkFont(.subheadline)
                                        .foregroundStyle(DS.Palette.text)
                                    Text(r.detail)
                                        .vkFont(.footnote)
                                        .foregroundStyle(DS.Palette.textSub)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: DS.Hit.min)
                            .accessibilityElement(children: .combine)
                        }
                        if risks.count > 8 {
                            // 2026-10-14: 原句把总数硬编码成 "(9)" —— 实际 12 条风险时会显示"另有 4 条 (9)",
                            // 那个 9 是**假总数**。改成取真实 count; 同时去掉规格编号。
                            Text("另有 \(risks.count - 8) 条 — 只列前 8 条, 共 \(risks.count) 条。")
                                .vkFont(.footnote)
                                .foregroundStyle(DS.Palette.textSub)
                        }
                    }
                } header: {
                    Text("凭证风险体检")
                } footer: {
                    Text("只读扫描本机台账: 同值 / 添加超 180 天未改 / 弱口令 (少于 6 位、全部同数字、连续序列)。处置在凭证 Tab 改码。")   // 305/306 只读扫描本机台账
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }


                Section {
                    // 只读试验模式: 护栏本体 (ZKProtocol.assertReadOnly) 与执行点 (LockService.request 读
                    // kf_trial_guard) 两边早就写好，**但全仓没有任何写入方** —— 开关不存在，这道保险从来上不上。
                    // 放行清单直接从 readonlyCmds 现取，不在文案里另抄一份十六进制表:
                    // 抄了就会与表漂移，而这条恰好是"看着像有、实际拦错命令"最贵的那种漂移。
                    SecRow(title: "只读试验模式",
                           subtitle: trialGuardLine,
                           icon: "exclamationmark.shield", iconTone: .warn) {
                        VariantToggle("", isOn: Binding(
                            get: { DB.store.getBool("kf_trial_guard", false) },
                            set: { DB.store.set("kf_trial_guard", $0); SecTick.bump() }))
                            .labelsHidden()
                    }
                    Text("用途: 连真机做只读试验 (读状态/读日志/查钥匙串) 时防止误发写入命令。开启后 04 开门、05 换钥、08 同步 PIN、31 写网关口令等一律在成帧前拦下报错，不会发包。关闭即恢复正常下发，不留残余限制。")
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("下发护栏")
                }
            }
            .variantList()
            .dsScreenBackground()
            .navigationTitle("安全中心")
            // 2026-10-15 走查: 本页由 push 改为 **sheet** 呈现 (它自带 NavigationStack, push 会套两层
            // 导航栏 —— 判据见 SettingsView 里「动态消息」那条注释)。而它此前**没有任何关闭出口**:
            // push 时有系统返回键, sheet 里没有, 用户只能下滑。补一枚与其余 sheet 页同款的前置「关闭」。
            .toolbar { ToolbarItem(placement: .navigationBarLeading) {
                Button("关闭") { dismiss() }
            } }
            // 378 常驻水印层: 全页对角重复, 设置可关
            .overlay {
                if DB.store.getBool(SecKey.watermarkOn, false) {
                    SecurityWatermark(seed: DB.store.getString(SecKey.watermarkTxt))
                }
            }
            // 2s 节拍重算派生文案 (哈希链长度/启用数等), 子页 bump 后立即生效
            .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
                self.center.bump()
            }
            // 2026-10-15 走查 §4.2: 栈内两枚"去设置…"按钮 (`SecurityLockConfigView` 的重设纯数字密码、
            // 子页里那些"去设置…"按钮) 把落点写进 app.pendingSettingsFocus,
            // 而**本页是盖在设置页上的 sheet** —— 设置页当场消费, 等于在
            // 被盖住的 List 上再开一个 sheet: 同一呈现上下文里已经有一个了, 新的不会显示, 而 pending
            // 已经清空, 按钮就退回成"点了没反应"。改成由这层 sheet 自己收摊, 设置页等收到 onDismiss
            // 再落地 (见 SettingsView 里 showSecurity 那条)。
            // dismiss 读的是**本视图**的 @Environment —— 与上面「关闭」那颗按钮同一个动作、同一个值,
            // 不是从 push 进来的子页里调 (那种情况下它可能只退一层)。整条安全中心栈随 sheet 消失,
            // 所以不需要给 NavigationStack 另加 path binding。
            .onChange(of: app.pendingSettingsFocus) { _, f in
                guard f != nil else { return }
                dismiss()
            }
        }
    }

    /// 只读试验模式状态行。放行清单**取自 ZKProtocol.readonlyCmds** (Set 无序，排序后拼)，
    /// 不在文案里另抄一份命令表 —— 两处各写一遍迟早对不上，而对不上的是"以为被拦住了"这种事故。
    private var trialGuardLine: String {
        guard DB.store.getBool("kf_trial_guard", false) else { return "关闭 — 全部命令正常下发" }
        let list = ZKProtocol.readonlyCmds.map { String(format: "%02X", $0) }.sorted().joined(separator: "/")
        return "已开启 — 仅放行只读命令 " + list
    }

}

// ---------- 通用行组件 (触达 ≥44pt, 颜色只走 DS 令牌) ----------
struct SecRow<Trailing: View>: View {
    private let title: String
    private let subtitle: String
    private let icon: String
    private let iconTone: ToneColor
    private let trailing: Trailing

    init(title: String, subtitle: String = "", icon: String = "circle.fill",
         iconTone: ToneColor = .neutral, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconTone = iconTone
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: icon)
                .font(.system(size: DS.Icon.sm, weight: .medium))
                .foregroundStyle(iconTone.color)
                .frame(width: DS.Icon.md, height: DS.Icon.md)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title)
                    .vkFont(.subheadline, weight: .medium)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                }
            }
            Spacer(minLength: DS.Space.s)
            trailing
        }
        .frame(minHeight: DS.Hit.min)
        .contentShape(Rectangle())
    }
}
