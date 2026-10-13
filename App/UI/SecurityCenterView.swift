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
    static let randomKeys     = "kf_slock_randkey"      // 396 随机键位
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
final class SecTickCenter: ObservableObject {
    static let shared = SecTickCenter()
    @Published private(set) var tick = 0
    func bump() { tick &+= 1 }
}
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

/// 需要 sudo 时按**既有应用锁口令通道**当场问一次 (SecurityPolicy.sudoTicket → DB.verifyPasscode),
/// 验出来那张 SudoTicket 记在 AppState 会话内复用, 不逐颗按钮追问 (383 的原话是"需重输应用锁密码",
/// 不是"每点一次输一遍")。不新建存储、不新建口令位、不新建第二个解锁面。
/// 开关关着就直放行: 这一支的存在才是这枚开关的意义 —— 关着少一道确认, 开着一定拦得住。
@MainActor
func askSudoThen(_ app: AppState, then action: @escaping () -> Void) {
    guard SecurityPolicy.sudoRequired else { action(); return }
    if app.sudoTicket != nil { action(); return }
    let alert = UIAlertController(title: "重输应用锁密码",
                                  message: "383: 这是毁灭级操作, 需重输本机密码。口令只当场比对, 不写进任何存储。",
                                  preferredStyle: .alert)
    alert.addTextField { f in
        f.isSecureTextEntry = true
        f.placeholder = "应用锁密码"
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "验证", style: .destructive) { _ in
        let input = alert.textFields?[0].text ?? ""
        guard let ticket = sudoTicketFromReview(input) else {
            app.showToast("密码错误, 已拒绝毁灭操作 (383)")
            return
        }
        app.sudoTicket = ticket
        AuditLog().append(.admin, "sudo", target: "毁灭操作复核通过",
                          operator_: DB.store.getString(SecKey.sessionHow, "本机密码"),
                          duress: DB.store.getBool(SecKey.sessionDuress, false))
        SecTick.bump()
        action()
    })
    UIApplication.topViewController()?.present(alert, animated: true)
}

/// 296 + 383 两道闸的合用写法: 先问"只读模式下准不准做", 再问"要不要重输口令"。
/// 顺序是定的: 只读模式开着时连口令都不该问 (问了也做不成, 那是白打扰)。
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
    app.showToast(on ? "访客通道已生效: 已回到设备页, 想进凭证与设置要重输密码 (377)"
                      : "访客通道已关闭: 四页照常, 本次会话内不用再输密码 (377)")
}

// ---------- 378 常驻水印层 (截图加扰降级案: 页面常驻, 半透明对角重复) ----------
struct SecurityWatermark: View {
    var seed: String
    var body: some View {
        Canvas { ctx, size in
            let tile: CGFloat = 120
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
                    t.draw(Text(stamp).font(.caption2).foregroundColor(DS.Palette.text), at: .zero)
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
struct SecurityCenterView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var center = SecTickCenter.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { SecurityLockConfigView() } label: {
                        Label("应用锁增强", systemImage: "lock.shield")
                    }
                    Text("冷却 / 锁定时机 / 免验 / 救援码 / 随机键位 / 伪装与胁迫")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                } header: {
                    Text("应用锁")
                }

                Section {
                    NavigationLink { SecurityPeekView() } label: {
                        Label("防窥与遮蔽", systemImage: "eye.slash")
                    }
                    Text("遮蔽样式 / 后台即糊 / 限时可见 / 磨砂挡片 / 访客通道 / 水印")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                } header: {
                    Text("防窥")
                }

                // 9 凭证风险体检 (Apple Passwords 那种风险卡): 只读扫描本机台账, 处置动作不在这里,
                // 而是指到凭证 Tab 的改码 (305/306) —— 这一页只回答"有没有该处理的"。
                Section {
                    let risks = CredentialOrg.passwordRisks()
                    if risks.isEmpty {
                        Text("没有发现同值 / 超期 / 弱口令 —— 台账里的密码都还干净 (9)。")
                            .font(.footnote)
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
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(r.kind) · \(r.lockName) 密码 #\(r.alias)")
                                        .font(.subheadline)
                                        .foregroundStyle(DS.Palette.text)
                                    Text(r.detail)
                                        .font(.footnote)
                                        .foregroundStyle(DS.Palette.textSub)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: DS.Hit.min)
                            .accessibilityElement(children: .combine)
                        }
                        if risks.count > 8 {
                            Text("另有 \(risks.count - 8) 条 — 只列前 8 条 (9)。")
                                .font(.footnote)
                                .foregroundStyle(DS.Palette.textSub)
                        }
                    }
                } header: {
                    Text("凭证风险体检 (9)")
                } footer: {
                    Text("只读扫描本机台账: 同值 / 添加超 180 天未改 / 弱口令 (少于 6 位、全部同数字、连续序列)。处置在凭证 Tab 改码 (305/306)。")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section {
                    NavigationLink { SecurityAuditView() } label: {
                        Label("审计流水", systemImage: "list.bullet.rectangle")
                    }
                    Text(auditChainLine())
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                } header: {
                    Text("审计")
                }

                Section {
                    NavigationLink { SecurityDestroyView() } label: {
                        Label("销毁与应急", systemImage: "trash")
                    }
                    Text("三级销毁 / 备份闸 / 残留检查 / 回收站 / 安全模式 / 口令复用")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                } header: {
                    Text("销毁")
                }

                Section {
                    // 只读试验模式: 护栏本体 (ZKProtocol.assertReadOnly) 与执行点 (LockService.request 读
                    // kf_trial_guard) 两边早就写好，**但全仓没有任何写入方** —— 开关不存在，这道保险从来上不上。
                    // 放行清单直接从 readonlyCmds 现取，不在文案里另抄一份十六进制表:
                    // 抄了就会与表漂移，而这条恰好是"看着像有、实际拦错命令"最贵的那种漂移。
                    SecRow(title: "只读试验模式",
                           subtitle: trialGuardLine,
                           icon: "exclamationmark.shield", iconTone: .warn) {
                        Toggle("", isOn: Binding(
                            get: { DB.store.getBool("kf_trial_guard", false) },
                            set: { DB.store.set("kf_trial_guard", $0); SecTick.bump() }))
                            .labelsHidden()
                    }
                    Text("用途: 连真机做只读试验 (读状态/读日志/查钥匙串) 时防止误发写入命令。开启后 04 开门、05 换钥、08 同步 PIN、31 写网关口令等一律在成帧前拦下报错，不会发包。关闭即恢复正常下发，不留残余限制。")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("下发护栏")
                }
            }
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .navigationTitle("安全中心")
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
        }
    }

    /// 只读试验模式状态行。放行清单**取自 ZKProtocol.readonlyCmds** (Set 无序，排序后拼)，
    /// 不在文案里另抄一份命令表 —— 两处各写一遍迟早对不上，而对不上的是"以为被拦住了"这种事故。
    private var trialGuardLine: String {
        guard DB.store.getBool("kf_trial_guard", false) else { return "关闭 — 全部命令正常下发" }
        let list = ZKProtocol.readonlyCmds.map { String(format: "%02X", $0) }.sorted().joined(separator: "/")
        return "已开启 — 仅放行只读命令 " + list
    }

    private func auditChainLine() -> String {
        let v = AuditLog().verifyChain()
        let state = v.brokenAt == -2 ? "（序号异常）" : (v.brokenAt >= 0 ? "（链断）" : "（完好）")
        return "双流水 / 字段 diff / 脱敏导出 / 哈希链 \(v.length) 条 \(state)"
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
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
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

// ================================================================
// 一、应用锁升级 (369-396 区段 + 161/234)
// ================================================================
struct SecurityLockConfigView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var center = SecTickCenter.shared

    var body: some View {
        List {
            Section {
                // 389/234 递增冷却
                SecRow(title: "递增冷却",
                       subtitle: "连败等待逐次翻倍 (30s 起), 锁定页显示需等秒数",
                       icon: "hourglass", iconTone: .warn) {
                    Toggle("", isOn: binding(SecKey.lockCoolOn))
                        .labelsHidden()
                }
                cooldownRow
                if DB.store.getBool(SecKey.lockCoolOn, false), cooldownSeconds > 0 {
                    Button("立即解除冷却") {
                        DB.store.set(SecKey.lockStreak, 0)
                        DB.store.set(SecKey.lockUntil, 0.0)
                        SecTick.bump()
                    }
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.danger)
                    .frame(minHeight: DS.Hit.min)
                }
            } header: {
                Text("错次延时 (234)")
            }

            Section {
                // 393 锁定时机四档
                SecRow(title: "锁定时机",
                       subtitle: lockTimingLabel,
                       icon: "clock") {
                    Picker("", selection: bindingString(SecKey.lockTiming)) {
                        Text("退后台即锁").tag("")
                        Text("1 分钟后").tag("m1")
                        Text("5 分钟后").tag("m5")
                        Text("下次启动").tag("next")
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 100)
                    .tint(DS.Palette.accentText)
                }
                // 394 短时免验
                SecRow(title: "短时免验",
                       subtitle: DB.store.getBool(SecKey.graceOn, false)
                                ? "解锁后 \(DB.store.getInt(SecKey.graceSec, 30)) 秒内切回免重验"
                                : "关闭 (每次切回都重验)",
                       icon: "bolt") {
                    Toggle("", isOn: binding(SecKey.graceOn))
                        .labelsHidden()
                }
                if DB.store.getBool(SecKey.graceOn, false) {
                    SecRow(title: "免验窗口", subtitle: "\(DB.store.getInt(SecKey.graceSec, 30)) 秒") {
                        Picker("", selection: bindingInt(SecKey.graceSec, 30)) {
                            Text("15 秒").tag(15)
                            Text("30 秒").tag(30)
                            Text("60 秒").tag(60)
                            Text("120 秒").tag(120)
                        }
                        .pickerStyle(.menu)
                        .frame(minWidth: 84)
                        .tint(DS.Palette.accentText)
                    }
                }
            } header: {
                Text("锁定与免验 (393/394)")
            }

            Section {
                // 395 一次性救援码
                SecRow(title: "一次性救援码",
                       subtitle: rescueSubtitle,
                       icon: "key") {
                    HStack(spacing: DS.Space.xs) {
                        Toggle("", isOn: binding(SecKey.rescueOn))
                            .labelsHidden()
                            .disabled(!DB.hasPasscode())   // 395: 没开应用锁时救援码无处消费
                        if DB.store.getBool(SecKey.rescueOn, false) {
                            Button(DB.store.getString(SecKey.rescueCode).isEmpty ? "重新生成" : "查看") {
                                rescueDetail()
                            }
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(DS.Palette.accentText)
                            .frame(minHeight: DS.Hit.min)
                        }
                    }
                }
                rescueBody
                // 396 随机键位 — 当前**无法安全实现**, 如实标注而不是留个死开关:
                // 本机密码允许字母/符号 (setCodeAlert 只限"4 位以上"), 一旦换成随机**数字**键盘,
                // 非数字密码的用户就再也输不进去 = 自己把自己锁死。要做得先把密码限定为纯数字。
                // 396 随机键位: 只在"本机密码确为纯数字"时可开 (见 LockGuard/AppLockView 的数字键盘)
                SecRow(title: "随机键位键盘",
                       subtitle: DB.store.getBool(SecKey.randKeyDigits, false)
                                ? "锁屏数字键盘每次进入重排, 防肩窥轨迹猜测"
                                : "需先把本机密码重设为纯数字 (旧密码含字母时不出现数字键盘, 免得把自己锁在门外)",
                       icon: "die.face.5") {
                    Toggle("", isOn: binding(SecKey.randomKeys))
                        .labelsHidden()
                        .disabled(!DB.store.getBool(SecKey.randKeyDigits, false))
                }
                // ★B 迁移引导: 已有密码但含非数字 → 给一条能点的路, 而不是只写"需重设"
                if DB.hasPasscode(), !DB.store.getBool(SecKey.randKeyDigits, false) {
                    Button("去「设置」把本机密码重设为纯数字，即可启用随机键位") { app.tabSelection = 3 }
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.accentText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHint("跳转设置 Tab 的密码区，现有字母数字密码仍可继续使用，不会被强制修改")
                }
            } header: {
                Text("救援与键位 (395/396)")
            }

            Section {
                // 390 伪装密码
                SecRow(title: "伪装模式",
                       subtitle: DB.store.getBool(SecKey.decoyOn, false)
                                ? "已启用: 输入伪装口令进空壳界面"
                                : "输入伪装口令进空壳界面 (只显示本机时钟, 不加载任何门锁数据) 防胁迫翻供",
                       icon: "theatermasks") {
                    Toggle("", isOn: binding(SecKey.decoyOn))
                        .labelsHidden()
                }
                if DB.store.getBool(SecKey.decoyOn, false), !DB.hasPasscode() {
                    Text("伪装口令须与本机密码不同, 请先在「设置 → 本机数据保护」设置密码")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.warn)
                }
                if DB.store.getBool(SecKey.decoyOn, false) {
                    setCodeRow(title: "伪装口令", key: SecKey.decoyCode,
                               hint: "须 4 位以上, 且与胁迫码不同",
                               conflictCheck: { pw in
                                   if DB.verifyPasscode(pw) { return "不能与本机密码相同 (否则真密码会被当成伪装口令)" }
                                   if pw == DB.store.getString(SecKey.duressCodeRaw) { return "与胁迫码相同" }
                                   return "" })
                }
                // 391 App 层胁迫码
                SecRow(title: "胁迫码",
                       subtitle: DB.store.getBool(SecKey.duressOn, false)
                                ? "已设: 进入后界面正常但会话打标, 操作日志橙边"
                                : "输入后伪装放行并给会话打标",
                       icon: "exclamationmark.shield") {
                    Toggle("", isOn: binding(SecKey.duressOn))
                        .labelsHidden()
                }
                if DB.store.getBool(SecKey.duressOn, false) {
                    setCodeRow(title: "胁迫码", key: SecKey.duressCodeRaw,
                               hint: "记住它 — 被胁迫时输入即可放行并打标",
                               conflictCheck: { pw in
                                   // 与本机密码相同 = 打标永远不生效 (真密码分支先命中), 必须在设置时禁止
                                   if DB.verifyPasscode(pw) { return "不能与本机密码相同" }
                                   let hits = PwReuse.reuseWarnings(mac: DB.currentMac, newPwd: pw)
                                   if DB.store.getBool(SecKey.pwdReuseOn, true), !hits.isEmpty {
                                       return "与 " + hits.joined(separator: "、") + " 相同"
                                   }
                                   return "" })
                    if DB.get(Double.self, SecKey.duressAt) ?? 0 > 0 {
                        Text("最近打标: \(Self.dateStr(DB.get(Double.self, SecKey.duressAt) ?? 0))")
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.warn)
                    }
                }
            } header: {
                Text("伪装与胁迫 (390/391)")
            }

            Section {
                // 392 失败留痕
                SecRow(title: "验证失败留痕",
                       subtitle: DB.store.getBool(SecKey.traceOn, false) ? "面容/密码失败事件写日志 (不存图像)" : "关闭",
                       icon: "antenna.radiowaves.left.and.right") {
                    Toggle("", isOn: binding(SecKey.traceOn))
                        .labelsHidden()
                }
                let evs = LockGuard.traces()   // 读侧走 LockGuard 的口径 (此前这里自己摸 key, traces() 反而零调用)
                if !evs.isEmpty {
                    ForEach(Array(evs.prefix(5)), id: \.self) { line in
                        HStack(spacing: DS.Space.xs) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: DS.Icon.xs, weight: .semibold))
                                .foregroundStyle(DS.Palette.danger)
                            Text(line)
                                .font(.footnote)
                                .foregroundStyle(DS.Palette.textSub)
                                .lineLimit(1)
                        }
                    }
                    Button("清空留痕 (\(evs.count))") {
                        LockGuard.clearTraces()
                        SecTick.bump()
                    }
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.danger)
                    .frame(minHeight: DS.Hit.min)
                }
            } header: {
                Text("失败留痕 (392)")
            }

            // 398 会话信息页
            Section {
                SecRow(title: "当前解锁会话",
                       subtitle: sessionLabel,
                       icon: "person.crop.circle.badge.checkmark") {
                    Button("立即重新锁定") { relock() }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(DS.Palette.danger)
                        .frame(minHeight: DS.Hit.min)
                }
                if DB.hasPasscode() {
                    Text("会话开始/验证方式由 AppLockView 解锁成功时写入 (接线点: 置 appUnlocked = true 处同步)；“立即重新锁定”即刻生效。")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                }
            } header: {
                Text("会话 (398)")
            }
        }
        .scrollContentBackground(.hidden)
        .dsScreenBackground()
        .navigationTitle("应用锁增强")
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            self.center.bump()
        }
    }

    // ---------- 派生数据 ----------
    private var cooldownSeconds: Int {
        let until = DB.get(Double.self, SecKey.lockUntil) ?? 0
        let remain = until - Date().timeIntervalSince1970
        return remain > 0 ? Int(remain.rounded(.up)) : 0
    }

    private var cooldownRow: some View {
        let on = DB.store.getBool(SecKey.lockCoolOn, false)
        let n = DB.store.getInt(SecKey.lockStreak, 0)
        // 2026-10-13 run 61: 原写 `Int(30 * pow(2, min(n, 8)))` —— 两个实参都是 Int,
        // 于是 `pow` 解析到 Foundation 的 `pow(Decimal, Int) -> Decimal`, 再 `Int(Decimal)` 报
        //   "initializer 'init(_:)' requires that 'Decimal' conform to 'BinaryInteger'"。
        // 显式走 Double 版: `pow(2.0, Double(min(n, 8)))`。
        let nextCd = Int(30 * pow(2.0, Double(min(n, 8))))
        let title = on
            ? "连败 \(n) 次" + (cooldownSeconds > 0 ? "，还需等 \(cooldownSeconds) 秒" : "，下次冷却 \(nextCd) 秒")
            : "关闭"
        return SecRow(title: title,
                      subtitle: "冷却基线 30s × 2^n (n 封顶 8)",
                      icon: "figure.walk", iconTone: on ? .warn : .neutral) { EmptyView() }
    }

    private var lockTimingLabel: String {
        switch DB.store.getString(SecKey.lockTiming) {
        case "m1": return "后台 1 分钟后锁定"
        case "m5": return "后台 5 分钟后锁定"
        case "next": return "下次启动时锁定"
        default: return "退后台即锁 (最严)"
        }
    }

    private var sessionLabel: String {
        let at = DB.get(Double.self, SecKey.sessionAt) ?? 0
        if at <= 0 { return "尚无会话记录 (解锁成功后写入)" }
        let how = DB.store.getString(SecKey.sessionHow, "本机密码")
        return "开始 \(Self.dateStr(at)) · \(how)" + (DB.store.getBool(SecKey.sessionDuress, false) ? " · 胁迫会话" : "")
    }

    private var rescueSubtitle: String {
        if !DB.store.getBool(SecKey.rescueOn, false) { return "忘记密码时的唯一重置入口" }
        return DB.store.getString(SecKey.rescueCode).isEmpty ? "已消费, 可重新生成" : "已生成待手抄"
    }

    /// 469 手抄码的保管人: 读成员页点名的紧急管理员 (MemberHub.emergencyAdmins)。
    /// 空名单不装没事 —— 如实指路到成员详情去点名, 防单点失能。
    private var rescueCustodyLine: String {
        let admins = MemberHub.emergencyAdmins()
        if admins.isEmpty {
            return "尚未指定保管人 — 到成员详情里点名紧急管理员, 手抄的救援码交其保管 (防单点失能)"
        }
        return "手抄后交给: " + admins.map { MemberHub.display($0) }.joined(separator: "、")
    }

    @ViewBuilder
    private var rescueBody: some View {
        if DB.store.getBool(SecKey.rescueOn, false) {
            let code = DB.store.getString(SecKey.rescueCode)
            if !code.isEmpty {
                HStack(spacing: DS.Space.s) {
                    Image(systemName: "key.fill")
                        .font(.system(size: DS.Icon.sm, weight: .medium))
                        .foregroundStyle(DS.Palette.accentText)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("请手抄这张救援码 — 消费后不可找回; 未点「已手抄」前该码不生效 (395)")
                            .font(.footnote.weight(.medium))
                        Text(code)
                            .font(.title3.weight(.semibold))
                            .monospaced()
                            .textSelection(.enabled)
                        if !DB.store.getBool(SecKey.rescueSeen, false) {
                            Text("尚未确认手抄")
                                .font(.caption)
                                .foregroundStyle(DS.Palette.warn)
                        }
                    }
                    Spacer()
                    Button("已手抄") {
                        DB.store.set(SecKey.rescueSeen, true)
                        SecTick.bump()
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(DB.store.getBool(SecKey.rescueSeen, false) ? DS.Palette.ok : DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                }
                // 469 保管人声明: 名字来自成员页点名的紧急管理员名单 (MemberHub.emergencyAdmins)
                Text(rescueCustodyLine)
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func relock() {
        DB.store.set(SecKey.sessionAt, 0.0)
        DB.store.set(SecKey.sessionDuress, false)
        app.appUnlocked = false
        app.showToast("已重新锁定")
        SecTick.bump()
    }

    private func rescueDetail() {
        // 395: 应用锁没开时救援码没有任何消费口 (rescue 只在锁屏验证里用) —— 别让用户抄一张无用的码
        guard DB.hasPasscode() else {
            app.showToast("未启用应用锁 — 救援码无用武之地 (395)")
            return
        }
        let code = DB.store.getString(SecKey.rescueCode)
        if code.isEmpty {
            DB.store.set(SecKey.rescueCode, HashKit.rescueCode())
            DB.store.set(SecKey.rescueSeen, false)
        }
        SecTick.bump()
    }

    // ---------- 口令录入行 (390/391 共用) ----------
    @ViewBuilder
    private func setCodeRow(title: String, key: String, hint: String,
                            conflictCheck: @escaping (String) -> String) -> some View {
        let stored = DB.store.getString(key)
        SecRow(title: title,
               subtitle: stored.isEmpty ? hint : "已设置 (\(stored.count) 位)",
               icon: "number") {
            HStack(spacing: DS.Space.xs) {
                Button("设置") { setCodeAlert(key: key, conflictCheck: conflictCheck) }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                if !stored.isEmpty {
                    Button("清除") {
                        DB.store.set(key, "")
                        SecTick.bump()
                    }
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.danger)
                    .frame(minHeight: DS.Hit.min)
                }
            }
        }
    }

    private func setCodeAlert(key: String, conflictCheck: @escaping (String) -> String) {
        let alert = UIAlertController(title: "设置口令", message: "4 位以上", preferredStyle: .alert)
        alert.addTextField { $0.isSecureTextEntry = true }
        alert.addTextField { $0.isSecureTextEntry = true; $0.placeholder = "再次输入" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            let f1 = alert.textFields?[0].text ?? ""
            let f2 = alert.textFields?[1].text ?? ""
            guard f1 == f2, f1.count >= 4 else { app.showToast("两次输入不一致或不足 4 位"); return }
            // 2026-10-13 run 61: `conflictCheck` 是 `@escaping (String) -> String` (见本函数签名),
            // 返回**非可选** String; 原写 `if let msg = conflictCheck(f1)` 报
            //   "initializer for conditional binding must have Optional type, not 'String'"。
            let msg = conflictCheck(f1)
            if !msg.isEmpty {
                app.showToast(msg)
                return
            }
            DB.store.set(key, f1)
            app.showToast("已设置")
            SecTick.bump()
        })
        UIApplication.topViewController()?.present(alert, animated: true)
    }

    // 2026-10-13 run 61: 原为 `private static func dateStr` —— 但 SecurityAuditView (379 审计流水)
    // 在 1396 行调 `SecurityLockConfigView.dateStr(e.ts)` 格式化时间戳, 跨类型访问 private 报
    //   "'dateStr' is inaccessible due to 'private' protection level"。
    // 改 internal (同一文件内的复用出口); 它只读私有 fmt, 仍是单一格式源, 不复制一份。
    static func dateStr(_ t: Double) -> String {
        fmt.string(from: Date(timeIntervalSince1970: t))
    }
    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // ---------- Store 绑定辅助 (与上页同范式) ----------
    private func binding(_ k: String) -> Binding<Bool> {
        Binding(get: { DB.store.getBool(k) },
                set: { DB.store.set(k, $0); SecTick.bump() })
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
// 二、防窥 (36/385-392 区段防窥部分)
// ================================================================
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

    var body: some View {
        List {
            // 405 剪贴板自清: 口令/OTP 复制到剪贴板后延时清除。
            // 只有"内容仍是当时那一串"才清 (见 ClipboardCare), 免得把用户后来复制的东西删掉。
            Section {
                SecRow(title: "剪贴板自动清除 (405)",
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
                    .tint(DS.Palette.accentText)
                }
            } footer: {
                Text("加密凭证包与交接包不走这条：那是密文，且你要粘进聊天工具，定时清掉只会打断交接。")
                    .font(.caption2).foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 369 遮蔽样式自选
            Section {
                SecRow(title: "列表遮蔽样式", subtitle: maskStyleLabel, icon: "mask") {
                    Picker("", selection: bindingString(SecKey.maskStyle)) {
                        Text("圆点打码").tag("")
                        Text("星号打码").tag("stars")
                        Text("保留末 4 位").tag("tail4")
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 110)
                    .tint(DS.Palette.accentText)
                }
            } header: {
                Text("遮蔽样式 (369)")
            }

            // 36 隐私仪表盘
            Section {
                NavigationLink { PrivacyDashboard() } label: {
                    SecRow(title: "隐私仪表盘",
                           subtitle: "\(Self.activeCount()) 项防窥已启用",
                           icon: "gauge.with.needle") { EmptyView() }
                }
            } header: {
                Text("隐私总览 (36)")
            }

            Section {
                // 371 切后台即糊
                SecRow(title: "切后台即糊",
                       subtitle: bgBlurLabel,
                       icon: "rectangle.fill.and.rectangle") {
                    Toggle("", isOn: bindingBool(SecKey.bgBlurOn, false))
                        .labelsHidden()
                }
                // 373 限时可见
                SecRow(title: "限时可见",
                       subtitle: timedRevealLabel, icon: "timer") {
                    Picker("", selection: bindingInt(SecKey.timedReveal, 0)) {
                        Text("关").tag(0)
                        Text("10 秒").tag(10)
                        Text("30 秒").tag(30)
                        Text("60 秒").tag(60)
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 84)
                    .tint(DS.Palette.accentText)
                }
                // 375 磨砂挡片演示
                frostedDemoRow
                // 376 分享遮半
                SecRow(title: "分享遮半",
                       subtitle: SecurityPolicy.shareHalf
                                ? "已开: 码值在完成页与详情卡上默认遮半, 点「完整显示」才露全值; 复制与分享跟随屏上显示"
                                : "关: 码值原样显示",
                       icon: "square.and.arrow.up") {
                    Toggle("", isOn: bindingBool(SecKey.shareHalfOn, true))
                        .labelsHidden()
                }
                // 377 访客通道: 判据口 SecurityPolicy.guestActive, 消费点在主 TabView (LockKeeperApp.swift)
                SecRow(title: "访客通道",
                       subtitle: SecurityPolicy.guestActive
                                ? "已开: 主界面只挂 设备/记录 两页, 进 凭证/设置 要先重输密码"
                                : "关: 四页照常。打开即生效 (会先把受限的那两页收起)",
                       icon: "person.crop.circle.badge.questionmark") {
                    Toggle("", isOn: guestSwitch)
                        .labelsHidden()
                }
                if SecurityPolicy.guestActive {
                    SecRow(title: "访客隐藏敏感成员",
                           subtitle: SecurityPolicy.hideSensitiveInGuest
                                    ? "已开但筛不出东西: 成员档案里没有敏感标记位, 判据口已就位等数据侧"
                                    : "关: 成员名单照原样给访客",
                           icon: "person.slash") {
                        Toggle("", isOn: bindingBool(SecKey.sensitiveOnly, false))
                            .labelsHidden()
                    }
                }
            } header: {
                Text("背景与限时 (371/373/375/376/377)")
            }

            Section {
                // 378 常驻水印 (截图加扰降级案)
                SecRow(title: "常驻水印",
                       subtitle: DB.store.getBool(SecKey.watermarkOn, false)
                                ? "全页对角重复 App 名+日期"
                                : "关闭 (截图加扰降级为常驻水印)",
                       icon: "watermark") {
                    Toggle("", isOn: bindingBool(SecKey.watermarkOn, false))
                        .labelsHidden()
                }
                if DB.store.getBool(SecKey.watermarkOn, false) {
                    SecRow(title: "水印文案",
                           subtitle: DB.store.getString(SecKey.watermarkTxt).isEmpty ? "默认: App 名 + 当日日期" : DB.store.getString(SecKey.watermarkTxt),
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
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(DS.Palette.accentText)
                        .frame(minHeight: DS.Hit.min)
                    }
                }
            } header: {
                Text("水印 (378 降级案)")
            }
        }
        .scrollContentBackground(.hidden)
        .dsScreenBackground()
        .navigationTitle("防窥与遮蔽")
        // 371 本地糊屏: 切后台即刻整屏糊, 回前台若已解锁则恢复清晰, 否则先过应用锁
        .onChange(of: scenePhase) { phase in
            let on = DB.store.getBool(SecKey.bgBlurOn, false)
            switch phase {
            case .background:
                withAnimation(DS.Motion.quick) { bgBlurred = on }
            case .active:
                let clear = !DB.hasPasscode() || app.appUnlocked
                withAnimation(clear ? .easeOut(duration: DS.Duration.standard) : .none) {
                    bgBlurred = on && !clear
                }
            default: break
            }
        }
        .overlay {
            if bgBlurred {
                ZStack {
                    DS.Gradient.screen.ignoresSafeArea()
                    VStack(spacing: DS.Space.s) {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: DS.Icon.xl, weight: .medium))
                            .foregroundStyle(DS.Palette.accentText)
                        Text("已切后台 — 回前台过应用锁后恢复清晰")
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                            .multilineTextAlignment(.center)
                    }
                    .blur(radius: 10)
                }
                .transition(.opacity)
            }
        }
        // 373 限时可见驱动: 到期自动收遮蔽 (挡片演示区)
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { now in
            if DB.store.getInt(SecKey.timedReveal, 0) > 0, self.revealUntil > 0, now.timeIntervalSince1970 >= self.revealUntil {
                withAnimation(DS.Motion.standard) {
                    self.revealUntil = 0
                    self.frosted = true
                }
            }
            self.center.bump()
        }
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
               subtitle: DB.store.getBool(SecKey.frostedOn, true) ? "OTP 行常驻磨砂, 长按暂时移开" : "关闭",
               icon: "square.fill.on.square") {
            Toggle("", isOn: bindingBool(SecKey.frostedOn, true))
                .labelsHidden()
        }
        .overlay(alignment: .leading) {
            if DB.store.getBool(SecKey.frostedOn, true), frosted {
                frostedPlate
            }
        }
    }

    @ViewBuilder
    private var frostedPlate: some View {
        Text("0 4 8 2 1  ·  OTP (长按查看)")
            .font(.title3.weight(.semibold))
            .monospaced()
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            // 375 松手复位: pressing=false 时无条件合挡片 (timedReveal=0 下长按后也曾永开);
            // timedReveal>0 时定时器到点也收回同一状态, 两条路一个结局。
            .onLongPressGesture(minimumDuration: 0.5, maximumDistance: 50, pressing: { pressing in
                if !pressing { withAnimation(DS.Motion.standard) { self.frosted = true } }
            }, perform: {
                withAnimation(DS.Motion.standard) { self.frosted = false }
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

// ---------- 36 隐私仪表盘 ----------
struct PrivacyDashboard: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var center = SecTickCenter.shared

    var body: some View {
        List {
            Section {
                HStack(spacing: DS.Space.s) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: DS.Icon.lg, weight: .medium))
                        .foregroundStyle(DS.Palette.accentText)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前启用 \(SecurityPeekView.activeCount()) 项防窥")
                            .font(.subheadline.weight(.semibold))
                        Text("遮蔽 / 背景 / 限时 / 挡片 / 分享 / 访客 / 水印 全状态一目了然")
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                }
                .frame(minHeight: DS.Hit.min)
            }
            Section("逐项状态 (轻点即切换)") {
                ForEach(PeekItem.all) { item in
                    HStack(spacing: DS.Space.s) {
                        Image(systemName: item.on ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: DS.Icon.sm, weight: .semibold))
                            .foregroundStyle(item.on ? DS.Palette.ok : DS.Palette.textSub)
                        Text(item.name)
                            .font(.subheadline)
                        Spacer()
                        Text(item.on ? "已启用" : "未启用")
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // 377: 这一格翻的是同一枚访客通道键, 必须走 setGuestChannel 那唯一一条写侧 ——
                        // 只落键的话仪表盘就留下一条"翻了开关但主 TabView 没收"的侧门 (与防窥页那枚 Toggle 不同轨)
                        if item.key == SecKey.guestOn {
                            setGuestChannel(!item.on, app: app)
                        } else {
                            DB.store.set(item.key, !item.on)
                        }
                        SecTick.bump()
                        self.center.bump()
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .dsScreenBackground()
        .navigationTitle("隐私仪表盘")
    }

    struct PeekItem: Identifiable {
        let key: String
        let name: String
        var on: Bool
        var id: String { key }
        static var all: [PeekItem] {
            [PeekItem(key: SecKey.bgBlurOn, name: "切后台即糊", on: DB.store.getBool(SecKey.bgBlurOn, false)),
             PeekItem(key: SecKey.frostedOn, name: "磨砂挡片", on: DB.store.getBool(SecKey.frostedOn, true)),
             // 376/377: 这两格的显示状态一律读判据口, 不在仪表盘里再写第三份 getBool
             PeekItem(key: SecKey.shareHalfOn, name: "分享遮半", on: SecurityPolicy.shareHalf),
             PeekItem(key: SecKey.guestOn, name: "访客通道", on: SecurityPolicy.guestActive),
             PeekItem(key: SecKey.watermarkOn, name: "常驻水印", on: DB.store.getBool(SecKey.watermarkOn, false))]
        }
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

    var body: some View {
        List {
            // 379 双流水分段
            Section {
                // 2026-10-13 run 61: 原写 `set: { withAnimation(DS.Motion.quick) { self.seg = $0 } }` ——
                // 外层闭包参数隐式 ($0 只出现在**内层**闭包里), 编译器把它算成
                //   "contextual type for closure argument list expects 2 arguments" 与
                //   "expects 0 arguments, but 1 was used in closure body"。
                // 给外层参数起名 newValue 后, 两层闭包各自明确, 歧义消失。
                Picker("", selection: Binding(get: { self.seg }, set: { newValue in
                    withAnimation(DS.Motion.quick) { self.seg = newValue }
                })) {
                    Text("管理操作").tag(0)
                    Text("开门事件").tag(1)
                }
                .pickerStyle(.segmented)
                ForEach(events, id: \.id) { e in
                    auditRow(e)
                }
                if events.isEmpty {
                    Text("暂无条目 — 增删改/导入会自动记入 (导出见敏感流水), 也可下方手动记一条")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                }
            } header: {
                Text("双流水 (379)")
            }

            Section {
                Button {
                    let who = DB.store.getString(SecKey.sessionHow, "本机")
                    AuditLog().append(seg == 0 ? .admin : .door, "记", target: "手动补记",
                                      operator_: who, duress: DB.store.getBool(SecKey.sessionDuress, false))
                    SecTick.bump()
                    self.center.bump()
                } label: {
                    Label(manualEntryTitle, systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                }
                .frame(minHeight: DS.Hit.min)
            }

            // 386 防篡改哈希链
            Section {
                Button {
                    verifyMsg = verifyNow()
                    self.center.bump()
                } label: {
                    Label("校验完整性", systemImage: "checkmark.shield")
                        .font(.subheadline.weight(.medium))
                }
                .frame(minHeight: DS.Hit.min)
                if let m = verifyMsg {
                    HStack(spacing: DS.Space.xs) {
                        Image(systemName: m.contains("完好") ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: DS.Icon.sm, weight: .semibold))
                            .foregroundStyle(m.contains("完好") ? DS.Palette.ok : DS.Palette.danger)
                        Text(m)
                            .font(.footnote)
                            .foregroundStyle(m.contains("完好") ? DS.Palette.textSub : DS.Palette.danger)
                            .lineLimit(2)
                    }
                }
                Text("每条管理日志附前条 SHA-256, 逐链重算验证; 本地轻量口径, 篡改即断链")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
            } header: {
                Text("防篡改 (386)")
            }

            // 385 保留期策略
            Section {
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
                    .tint(DS.Palette.accentText)
                }
                if DB.store.getInt(SecKey.auditRetention, 0) > 0 {
                    Button {
                        // 385 到期清理是**物理删除**流水条目 (还要整段重封链) ⇒ 归入 296 只读闸与 383 sudo 那一族:
                        // 只读模式下不做, 开关开着要先重输应用锁口令。
                        guardedDestroy(app) {
                            AuditLog().purgeExpired(months: DB.store.getInt(SecKey.auditRetention, 0))
                            SecTick.bump()
                            self.center.bump()
                            app.showToast("已按保留期清理并留痕")
                        }
                    } label: {
                        Label("立即清理到期条目", systemImage: "clock.arrow.circlepath")
                            .font(.subheadline.weight(.medium))
                    }
                    .frame(minHeight: DS.Hit.min)
                }
            } header: {
                Text("保留期 (385)")
            }

            // 382 脱敏导出
            Section {
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
                        .font(.subheadline.weight(.medium))
                }
                .frame(minHeight: DS.Hit.min)
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
                        .font(.subheadline.weight(.medium))
                }
                .frame(minHeight: DS.Hit.min)
                .foregroundStyle(DS.Palette.warn)
            } header: {
                Text("脱敏导出 (382)")
            }

            // 383 毁灭操作 sudo 口令
            Section {
                SecRow(title: "毁灭操作 sudo 口令",
                       subtitle: SecurityPolicy.sudoRequired
                                ? "已开: 三级销毁的第二级要重输本机密码, 清空回收站/到期清理/离职清除也先问这一道"
                                : "已关: 上面这几处毁灭动作不再追问口令 (不建议)",
                       icon: "person.crop.circle.badge.xmark") {
                    Toggle("", isOn: Binding(
                        get: { SecurityPolicy.sudoRequired },
                        // 关掉开关顺手收回已发的那张券: 会话里"上一次验过"不该替下一次做主
                        set: { DB.store.set(SecKey.sudoOn, $0); app.sudoTicket = nil; SecTick.bump() }))
                        .labelsHidden()
                }
                if !DB.hasPasscode() {
                    Text("本机没设应用锁密码 ⇒ 口令无从复核 ⇒ 毁灭动作按最严格解释停在门口 (383)。"
                         + "要在这台机器上销毁, 先设本机密码或把这枚开关关掉。")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.warn)
                }
            } header: {
                Text("sudo 口令 (383)")
            }

            // 388 敏感操作视图
            Section {
                let recent = SensitiveLedger().recent(limit: 5)
                if recent.isEmpty {
                    Text("暂无 — 查看/复制/导出明文动作由接线方记入 (查看密码、复制 OTP、导出备份)")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                } else {
                    ForEach(recent) { it in
                        HStack(spacing: DS.Space.xs) {
                            Image(systemName: sensitiveIcon(it.kind))
                                .font(.system(size: DS.Icon.xs, weight: .semibold))
                                .foregroundStyle(DS.Palette.warn)
                            Text("\(it.kind) · \(it.target)")
                                .font(.footnote)
                                .foregroundStyle(DS.Palette.textSub)
                            Spacer()
                            Text(SecurityLockConfigView.dateStr(Double(it.id) / 1000))
                                .font(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                        }
                    }
                }
            } header: {
                Text("敏感操作视图 (388)")
            }

            // 953 快捷指令执行日志: 独立分区 (原先把意图流水混在 388 里, 每次 Siri 调用都记,
            // 会把"最近 5 条"整段挤成意图日志)。被冷却拦下的尝试也留痕 —— 那是风暴的样子。
            Section {
                let intents = SensitiveLedger().intentItems(limit: 10)
                if intents.isEmpty {
                    Text("暂无 — 六条快捷指令意图每次执行都会记到这里 (被冷却拦下的也留痕)")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                } else {
                    ForEach(intents) { it in
                        HStack(spacing: DS.Space.xs) {
                            Image(systemName: "command")
                                .font(.system(size: DS.Icon.xs, weight: .semibold))
                                .foregroundStyle(DS.Palette.accentText)
                            Text(String(it.kind.dropFirst("intent·".count)) + " · " + it.target)
                                .font(.footnote)
                                .foregroundStyle(DS.Palette.textSub)
                            Spacer()
                            Text(SecurityLockConfigView.dateStr(Double(it.id) / 1000))
                                .font(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                        }
                    }
                }
            } header: {
                Text("快捷指令执行 (953)")
            }
        }
        .scrollContentBackground(.hidden)
        .dsScreenBackground()
        .navigationTitle("审计流水")
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            self.center.bump()
        }
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
            HStack(spacing: DS.Space.xs) {
                Image(systemName: e.cat == .door ? "door.open.fill" : "gearshape.fill")
                    .font(.system(size: DS.Icon.xs, weight: .semibold))
                    .foregroundStyle(e.duress ? DS.Palette.warn : DS.Palette.accentText)
                Text("\(e.action) \(e.target)")
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
                Text(SecurityLockConfigView.dateStr(e.ts))
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                Image(systemName: "chevron.down")
                    .font(.system(size: DS.Icon.xs, weight: .semibold))
                    .foregroundStyle(DS.Palette.textSub)
                    .rotationEffect(.degrees(expanded == e.id ? 180 : 0))
            }
            .padding(.vertical, DS.Space.xs)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(DS.Motion.quick) { expanded = expanded == e.id ? nil : e.id }
            }
            if e.duress {
                RoundedRectangle(cornerRadius: 2)
                    .fill(DS.Palette.warn)
                    .frame(height: 3)
                    .padding(.top, DS.Space.xxs)
                Text("胁迫会话产生 (391 橙边标记)")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.warn)
                    .padding(.top, DS.Space.xxs)
            }
            if expanded == e.id {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    // 381 操作者 + 380 diff
                    ForEach(Array(e.diff.keys.sorted()), id: \.self) { field in
                        let vals = e.diff[field] ?? []
                        HStack(spacing: DS.Space.xxs) {
                            Text(field)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(DS.Palette.textSub)
                            Text((vals.first ?? "") + " → " + (vals.count > 1 ? vals[1] : "∅"))
                                .font(.caption.monospaced())
                                .foregroundStyle(DS.Palette.text)
                                .lineLimit(2)
                        }
                    }
                    if e.diff.isEmpty {
                        Text("无字段变更")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    HStack(spacing: DS.Space.xs) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: DS.Icon.xs, weight: .medium))
                            .foregroundStyle(DS.Palette.textSub)
                        Text("操作者: \(e.operator_)")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                        Text(String(e.hash.prefix(12)) + "…")
                            .font(.caption.monospaced())
                            .foregroundStyle(DS.Palette.textSub)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(.vertical, DS.Space.xs)
                .transition(.opacity)
            }
        }
        .frame(minHeight: DS.Hit.min)
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
}

// ================================================================
// 四、数据销毁 (393-406 区段 + 296/549)
// ================================================================
struct SecurityDestroyView: View {
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

    var body: some View {
        List {
            // 400 销毁前备份闸
            Section {
                HStack(spacing: DS.Space.s) {
                    Image(systemName: DestroyKit.backupGatePass ? "checkmark.shield.fill" : "exclamationmark.shield")
                        .font(.system(size: DS.Icon.sm, weight: .semibold))
                        .foregroundStyle(DestroyKit.backupGatePass ? DS.Palette.ok : DS.Palette.danger)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("销毁前备份闸")
                            .font(.subheadline.weight(.medium))
                        Text(backupGateLine)
                            .font(.footnote)
                            .foregroundStyle(DestroyKit.backupGatePass ? DS.Palette.textSub : DS.Palette.danger)
                    }
                    Spacer()
                }
                .frame(minHeight: DS.Hit.min)
            } header: {
                Text("备份闸 (400)")
            }

            // 399 三级销毁: 勾选理解项 → 输应用锁密码 → 键入"销毁"二字
            // 第二级归 383 管: 开关开着才问, 关着就如实显示"本级已跳过"
            Section {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Toggle(isOn: $ack) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("我理解销毁不可恢复")
                                .font(.subheadline)
                            Text("删除+随机覆写全部本地缓存 (钥匙串/台账/日志/审计)")
                                .font(.footnote)
                                .foregroundStyle(DS.Palette.textSub)
                        }
                    }
                    .tint(DS.Palette.accent)
                    if ack {
                        // 第二级: sudo 重输应用锁密码 (383)
                        if SecurityPolicy.sudoRequired, app.sudoTicket == nil {
                            HStack(spacing: DS.Space.s) {
                                SecureField("重输应用锁密码", text: $sudoInput)
                                    .textFieldStyle(.roundedBorder)
                                Button("验证") { verifySudo() }
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(DS.Palette.accentText)
                                    .frame(minHeight: DS.Hit.min)
                            }
                        } else if app.sudoTicket != nil {
                            Label("sudo 验证通过", systemImage: "checkmark.seal.fill")
                                .font(.footnote)
                                .foregroundStyle(DS.Palette.ok)
                        } else {
                            Label("383 开关关着: 本级跳过, 不再追问口令", systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(DS.Palette.warn)
                        }
                    }
                    if ack && sudoSatisfied {
                        // 第三级: 键入"销毁"二字
                        TextField("键入 销毁 二字以继续", text: $typedWord)
                            .autocorrectionDisabled()
                            .frame(minHeight: DS.Hit.min)
                    }
                    BusyButton(title: "销毁全部数据",
                                isBusy: destroying,
                                disabled: !(ack && sudoSatisfied
                                           && typedWord.trimmingCharacters(in: .whitespaces) == "销毁")) {
                        runDestroy()
                    }
                    if let rep = destroyReport {
                        Text(rep)
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                            .lineLimit(4)
                    }
                    if let msg = residueMsg {
                        HStack(spacing: DS.Space.xs) {
                            Image(systemName: msg.contains("零残留") ? "checkmark.seal.fill" : "magnifyingglass")
                                .font(.system(size: DS.Icon.sm, weight: .semibold))
                                .foregroundStyle(msg.contains("零残留") ? DS.Palette.ok : DS.Palette.danger)
                            Text(msg)
                                .font(.footnote)
                                .foregroundStyle(msg.contains("零残留") ? DS.Palette.ok : DS.Palette.danger)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } header: {
                Text("三级销毁 (399/401/406)")
            } footer: {
                Text("覆写 3 轮 · 随机 256–4208 字节/键; 残留全文检查零命中才显示“销毁完成”。")
            }

            // 403 按住 2 秒清空回收站
            Section {
                HStack(spacing: DS.Space.s) {
                    Text("清空回收站 (\(trashCount) 项)")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("长按 2 秒释放, 松手取消")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                }
                holdClearControl
            } header: {
                Text("回收站 (403)")
            }

            // 402 离职清除
            Section {
                let members = Offboard.members()
                if members.isEmpty {
                    Text("尚无成员档案 — 在 设置 → 家人与钥匙 添加后可在此“清除并归档”")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                } else {
                    ForEach(members) { m in
                        HStack(spacing: DS.Space.s) {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: DS.Icon.sm, weight: .medium))
                                .foregroundStyle(memberColor(m))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.name)
                                    .font(.subheadline)
                                Text("名下凭证入归档, 记录保留并标“已离开”")
                                    .font(.footnote)
                                    .foregroundStyle(DS.Palette.textSub)
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
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(DS.Palette.danger)
                            .frame(minHeight: DS.Hit.min)
                        }
                        .frame(minHeight: DS.Hit.min)
                    }
                }
            } header: {
                Text("离职清除 (402)")
            }

            // 296 安全模式
            Section {
                SecRow(title: "只读安全模式",
                       subtitle: SecurityPolicy.readOnly
                                ? "已启用: 圆盘开锁、销毁与清空、审计导出与到期清理一律拦下"
                                : "关闭 (异常时手动打开)",
                       icon: "power") {
                    Toggle("", isOn: Binding(
                        get: { SecurityPolicy.readOnly },
                        set: { DB.store.set(SecKey.safeModeOn, $0); SecTick.bump() }))
                        .labelsHidden()
                }
                if SecurityPolicy.readOnly {
                    Text("已接线的拦点: 开锁 (圆盘 / 手势 / 靠近自动开 / 二次开锁重发)、销毁全族 (三级销毁、清空回收站、"
                         + "到期清理、离职清除)、审计导出与含明文导出。"
                         + "还没接上的: 添加与改造凭证、网关配网、固件升级 —— 那几处的执行点在服务层与配网/升级那几个页面, "
                         + "闸装到之前, 开着这枚开关不等于全 App 只读。")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.warn)
                }
            } header: {
                Text("安全模式 (296)")
            }

            // 549 口令复用检测
            Section {
                SecRow(title: "口令复用检测",
                       subtitle: DB.store.getBool(SecKey.pwdReuseOn, true) ? "加密码时与存量比对提示" : "关闭",
                       icon: "arrow.triangle.2.circlepath") {
                    Toggle("", isOn: Binding(
                        get: { DB.store.getBool(SecKey.pwdReuseOn, true) },
                        set: { DB.store.set(SecKey.pwdReuseOn, $0); SecTick.bump() }))
                        .labelsHidden()
                }
                reuseDemoRow
            } header: {
                Text("口令复用 (549)")
            }

            // 521 二次输入确认开关 (密码保存前重输码值)
            Section {
                SecRow(title: "保存密码二次输入 (521)",
                       subtitle: DB.store.getBool("kf_scred_2nd", true) ? "密码保存前需重输一遍码值核对" : "关闭",
                       icon: "lock.rotationgauge") {
                    Toggle("", isOn: Binding(
                        get: { DB.store.getBool("kf_scred_2nd", true) },
                        set: { DB.store.set("kf_scred_2nd", $0); SecTick.bump() }))
                        .labelsHidden()
                }
            } header: {
                Text("密码保存 (521)")
            }
        }
        .scrollContentBackground(.hidden)
        .dsScreenBackground()
        .navigationTitle("销毁与应急")
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            self.center.bump()
        }
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
            HStack(spacing: DS.Space.xs) {
                Image(systemName: "exclamationmark.bubble")
                    .font(.system(size: DS.Icon.sm, weight: .semibold))
                    .foregroundStyle(DS.Palette.warn)
                Text("示例: 口令 1234 已出现在 " + hit.joined(separator: "、"))
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.warn)
                    .lineLimit(2)
            }
        } else {
            Text("新增口令与本机锁内存量口令 / 应用锁密码比对, 命中即提示“建议分开设置” (加密码处接线, 读现有 listPwds)。")
                .font(.footnote)
                .foregroundStyle(DS.Palette.textSub)
        }
    }

    // ---------- 403 长按填充控件 (按住 2 秒释放, 松手取消, 单击弹说明) ----------
    @State private var pressing = false

    private var holdClearControl: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                .fill(DS.Palette.surfaceAlt)
            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                .fill(DS.Palette.danger.opacity(holdProgress >= 1 ? 0.85 : 0.35))
                .frame(width: holdProgress * 200, height: DS.Hit.min)
            Text(holdProgress >= 1 ? "松开即清空" : "按住")
                .font(.footnote.weight(.medium))
                // 满格时底是 danger.opacity(0.85) 压在 surfaceAlt 上的合成色: 深色档纯白压上去只有
                // 3.51:1 (合成算法与比值都在 tools/contrast.js), 所以走随明暗换向的 onSem。
                .foregroundStyle(holdProgress >= 1 ? DS.Palette.onSem : DS.Palette.danger)
                .frame(width: 200, height: DS.Hit.min)
        }
        .frame(width: 200, height: DS.Hit.min)
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        .simultaneousGesture(
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
            app.showToast("还需重输应用锁密码 (383)")
            return
        }
        // 400 备份闸: 7 天内无备份先跳导出向导
        guard DestroyKit.backupGatePass else {
            let alert = UIAlertController(title: "销毁前请先备份",
                                          message: "最近 7 天没有备份。建议先导出备份再销毁 — 要直接销毁吗？"
                                            + "\n注意: 销毁会一并覆写删除本机上已有的备份导出件与自动回滚快照 (它们内含全部锁密钥)。",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "先去备份", style: .default) { _ in
                // 400: 真跳一步 (切到设置 Tab) + 把路径写全 —— 与 437 复核钉同一口径:
                // 备份工作室在三层 sheet 之后, 不为这一条造 pending-sheet 路由, 但也不假装"一点就到"。
                app.tabSelection = 3
                app.showToast("已切到设置 — 路径: 备份与恢复 → 备份工作室 → 导出向导")
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
            destroyReport = "未执行: 383 要求重输应用锁密码, 本次没有拿到复核凭据, 本机数据未被改动"
            residueMsg = nil
            app.showToast("销毁被 383 拦下")
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
                                     ?? "无 sudo 复核 (383 开关关着)"
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
        app.showToast(cleared > 0 ? "回收站已清空 (\(cleared) 把锁, 403)" : "回收站本来就是空的 (403)")
        holdProgress = 0
        SecTick.bump()
    }

    private func memberColor(_ m: Member) -> Color {
        var s = m.color
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt32(s, radix: 16)
        return v == nil ? DS.Palette.textSub : Color(hex: v!)
    }

    private static func dateStr(_ t: Double) -> String {
        guard t > 0 else { return "无" }
        let f = DateFormatter()
        f.dateFormat = "MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date(timeIntervalSince1970: t))
    }
}
