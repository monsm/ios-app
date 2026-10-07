// 包7 安全·隐私·审计 — 安全中心 (独立挂载入口, 不侵入既有页面)
// 四分区: 应用锁升级 / 防窥 / 审计留痕 / 数据销毁
// 配置一律 kf_ 前键经 DB.store getString/set 读写 (与 SettingsView 同款范式), 不改 Store。
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
    static let offboardTrash  = "kf_sdest_trash"        // 403 回收站 [String]
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

    private func auditChainLine() -> String {
        let v = AuditLog().verifyChain()
        let state = v.brokenAt >= 0 ? "（链断）" : "（完好）"
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
                // 396 随机键位
                SecRow(title: "随机键位键盘",
                       subtitle: "数字键盘每次布局随机, 防肩窥轨迹猜测",
                       icon: "die.face.5") {
                    Toggle("", isOn: binding(SecKey.randomKeys))
                        .labelsHidden()
                }
            } header: {
                Text("救援与键位 (395/396)")
            }

            Section {
                // 390 伪装密码
                SecRow(title: "伪装模式",
                       subtitle: DB.store.getBool(SecKey.decoyOn, false)
                                ? "已启用: 输入伪装口令进空壳界面"
                                : "输入伪装口令进空壳界面 (模拟天气) 防胁迫翻供",
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
                let evs = DB.get([String].self, SecKey.traceEvents) ?? []
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
                        DB.store.set(SecKey.traceEvents, [String]())
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
        let nextCd = Int(30 * pow(2, min(n, 8)))
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
                        Text("请手抄这张救援码 — 消费后不可找回")
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
            if let msg = conflictCheck(f1), !msg.isEmpty {
                app.showToast(msg)
                return
            }
            DB.store.set(key, f1)
            app.showToast("已设置")
            SecTick.bump()
        })
        UIApplication.topViewController()?.present(alert, animated: true)
    }

    private static func dateStr(_ t: Double) -> String {
        fmt.string(from: Date(timeIntervalSince1970: t))
    }
    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
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
                       subtitle: DB.store.getBool(SecKey.shareHalfOn, true) ? "口述卡与导出预览默认遮挡码值下半段" : "关闭",
                       icon: "square.and.arrow.up") {
                    Toggle("", isOn: bindingBool(SecKey.shareHalfOn, true))
                        .labelsHidden()
                }
                // 377 访客通道
                SecRow(title: "访客通道",
                       subtitle: DB.store.getBool(SecKey.guestOn, false)
                                ? "已开: 仅设备/记录 Tab, 退出需密码"
                                : "关（应用锁页“访客进入”入口待接线）",
                       icon: "person.crop.circle.badge.questionmark") {
                    Toggle("", isOn: bindingBool(SecKey.guestOn, false))
                        .labelsHidden()
                }
                if DB.store.getBool(SecKey.guestOn, false) {
                    SecRow(title: "访客隐藏敏感成员",
                           subtitle: "标记敏感的成员不出现在访客视图",
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
        case "stars": return "星号打码 (***) — 凭证全列表统一生效"
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
            .onLongPressGesture(minimumDuration: 0.5) {
                withAnimation(DS.Motion.standard) { self.frosted = false }
                self.revealTick()
            }
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
                        DB.store.set(item.key, !item.on)
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
             PeekItem(key: SecKey.shareHalfOn, name: "分享遮半", on: DB.store.getBool(SecKey.shareHalfOn, true)),
             PeekItem(key: SecKey.guestOn, name: "访客通道", on: DB.store.getBool(SecKey.guestOn, false)),
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
                Picker("", selection: Binding(get: { self.seg }, set: { withAnimation(DS.Motion.quick) { self.seg = $0 } })) {
                    Text("管理操作").tag(0)
                    Text("开门事件").tag(1)
                }
                .pickerStyle(.segmented)
                ForEach(events, id: \.id) { e in
                    auditRow(e)
                }
                if events.isEmpty {
                    Text("暂无条目 — 管理动作(增删改/导入导出/销毁)会自动记入, 可下方手动记一条")
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
                        AuditLog().purgeExpired(months: DB.store.getInt(SecKey.auditRetention, 0))
                        SecTick.bump()
                        self.center.bump()
                        app.showToast("已按保留期清理并留痕")
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
                    exportPlaintext = false
                    doExport("脱敏")
                } label: {
                    Label("导出审计 JSON (脱敏)", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.medium))
                }
                .frame(minHeight: DS.Hit.min)
                Button {
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
                       subtitle: DB.store.getBool(SecKey.sudoOn, true)
                                ? "清空数据库/删除全部备份需重输应用锁密码"
                                : "关闭 (不建议)",
                       icon: "person.crop.circle.badge.xmark") {
                    Toggle("", isOn: Binding(
                        get: { DB.store.getBool(SecKey.sudoOn, true) },
                        set: { DB.store.set(SecKey.sudoOn, $0); SecTick.bump() }))
                        .labelsHidden()
                }
                if !DB.hasPasscode() {
                    Text("需先设置本机密码 (设置 → 本机数据保护) 才有效")
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
        default: return "square.and.arrow.up"
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
        if v.brokenAt < 0 { return "链完好: \(v.length) 条逐链重算全部通过" }
        return "链在第 \(v.brokenAt + 1) 条断裂 — 存在被篡改或删除痕迹"
    }

    private func doExport(_ label: String) {
        let json = AuditLog().exportJSON(includePlaintext: exportPlaintext)
        exportPlaintext = false
        let vc = UIActivityViewController(activityItems: [json], applicationActivities: nil)
        vc.completionWithItemsHandler = { _, _, _, _ in
            // 382 导出本身也进敏感操作台账
            SensitiveLedger().record("导出", target: label)
            SecTick.bump()
        }
        UIApplication.topViewController()?.present(vc, animated: true)
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
    @State private var passcodeOk = false
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
                        if !passcodeOk {
                            HStack(spacing: DS.Space.s) {
                                SecureField("重输应用锁密码", text: $sudoInput)
                                    .textFieldStyle(.roundedBorder)
                                Button("验证") { verifySudo() }
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(DS.Palette.accentText)
                                    .frame(minHeight: DS.Hit.min)
                            }
                        } else {
                            Label("sudo 验证通过", systemImage: "checkmark.seal.fill")
                                .font(.footnote)
                                .foregroundStyle(DS.Palette.ok)
                        }
                    }
                    if ack && passcodeOk {
                        // 第三级: 键入"销毁"二字
                        TextField("键入 销毁 二字以继续", text: $typedWord)
                            .autocorrectionDisabled()
                            .frame(minHeight: DS.Hit.min)
                    }
                    BusyButton(title: "销毁全部数据",
                                isBusy: destroying,
                                disabled: !(ack && passcodeOk && typedWord.trimmingCharacters(in: .whitespaces) == "销毁")) {
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
                                Offboard.markDeparted(m.id, name: m.name)
                                AuditLog().append(.admin, "离", target: m.name)
                                app.showToast("\(m.name) 已归档")
                                SecTick.bump()
                                self.center.bump()
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
                       subtitle: DB.store.getBool(SecKey.safeModeOn, false)
                                ? "已启用: 只读查看日志, 实验开关停用"
                                : "关闭 (异常时手动打开)",
                       icon: "power") {
                    Toggle("", isOn: Binding(
                        get: { DB.store.getBool(SecKey.safeModeOn, false) },
                        set: { DB.store.set(SecKey.safeModeOn, $0); SecTick.bump() }))
                        .labelsHidden()
                }
                if DB.store.getBool(SecKey.safeModeOn, false) {
                    Text("定位手动应急位 (系统级异常钩子不存在); 启动路径接线由诊断包落地。")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
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
        (DB.get([String].self, SecKey.offboardTrash) ?? []).count
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
                .foregroundStyle(holdProgress >= 1 ? .white : DS.Palette.danger)
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

    // ---------- 399/400/401/406 销毁主流程 ----------
    private func verifySudo() {
        // 383/549 sudo 比对: 与 AppLockView 同款 DB.verifyPasscode 摘要比对
        guard sudoInput.count >= 4 else {
            app.showToast("请输入应用锁密码")
            return
        }
        guard DB.verifyPasscode(sudoInput) else {
            app.showToast("密码错误, 拒绝执行毁灭级操作")
            return
        }
        sudoInput = ""
        passcodeOk = true
        AuditLog().append(.admin, "销毁", target: "sudo 验证通过",
                           operator_: DB.store.getString(SecKey.sessionHow, "本机密码"))
        SecTick.bump()
    }

    private func runDestroy() {
        // 400 备份闸: 7 天内无备份先跳导出向导
        guard DestroyKit.backupGatePass else {
            let alert = UIAlertController(title: "销毁前请先备份",
                                          message: "最近 7 天没有备份。建议先导出备份再销毁 — 要直接销毁吗？",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "先去备份", style: .default) { _ in
                app.showToast("请在 设置 → 备份 生成备份后再销毁")
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
        let rep = DestroyKit.destroyAll()
        let done = rep.residueFound == 0
        destroyReport = done
            ? "销毁完成: 已覆写 \(rep.keys.count) 键 / 约 \(rep.randomBytes / 1024) KB 随机字节"
            : "销毁执行完毕但残留检查命中 \(rep.residueFound) 处 — 需人工复核"
        // 406 独立复核一次残留全文检查
        residueMsg = DestroyKit.checkResidue([]) == 0 ? "残留复核: 零残留" : "残留复核: 命中 \(DestroyKit.checkResidue([])) 处"
        AuditLog().append(.admin, "销", target: "全部本地数据, 覆写 \(rep.keys.count) 键",
                           operator_: DB.store.getString(SecKey.sessionHow, "sudo"))
        typedWord = ""
        ack = false
        passcodeOk = false
        destroying = false
        SecTick.bump()
        self.center.bump()
    }

    // ---------- 403 长按填充驱动 (50ms 步进 → 2s 填满) ----------
    private func startHoldTask() {
        self.holdTask?.cancel()
        self.holdProgress = 0
        self.holdTask = Task { @MainActor in
            while !Task.isCancelled, self.holdProgress < 1 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                self.holdProgress = min(1, self.holdProgress + 0.025)
            }
        }
    }

    private func clearTrash() {
        DB.store.set(SecKey.offboardTrash, [String]())
        app.showToast("回收站已清空")
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
        return f.string(from: Date(timeIntervalSince1970: t))
    }
}
