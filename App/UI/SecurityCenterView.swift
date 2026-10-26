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
    static let sensitiveOnly  = "kf_speek_glast"        // 377 访客模式隐藏敏感成员开关
    static let watermarkOn    = "kf_swmark_on"          // 378 常驻水印
    static let watermarkTxt   = "kf_swmark_txt"         // 378 水印文案种子
    static let auditRetention = "kf_saudit_months"      // 385 保留期 (0=永久)
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
            // 2s 节拍：本页**不读** tick，但它是 bump 的**唯一驱动源** ——
            // LockKeeperApp.swift:1094 的全局水印层读 secTick.tick 靠它重算。
            // 子页拨开关后也会主动 bump（见 :167 上方那条 dismiss 注释），那条路径不依赖这个节拍。
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


}
