// 离线锁管家 for iOS — App 入口与全局状态 (SwiftUI 全原生)
import SwiftUI
import UIKit
import AudioToolbox

@main
struct LockKeeperApp: App {
    @StateObject private var app = AppState()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .tint(DS.Palette.accent)
        }
    }
}

// ---------- 主题 (JS utils/theme.js: kf_theme) ----------
// 颜色统一取自设计系统 DesignSystem.swift, 页面不再各自定义颜色
enum Theme {
    static var accent: Color { DS.Palette.accentText }
    static var warn: Color { DS.Palette.warn }
    static var ok: Color { DS.Palette.ok }
    static var isLight: Bool {
        DB.store.getString("kf_theme") == "light"
    }
    // 跟随系统: 未设置时 nil; 设置过则固定。纯黑 (idea 30) 走深色语义, 表面由 Palette 覆盖为纯黑
    static func scheme(for key: String) -> ColorScheme? {
        switch key {
        case "light": return .light
        case "dark", "black": return .dark
        default: return nil
        }
    }
    static var scheme: ColorScheme? {
        scheme(for: DB.store.getString("kf_theme"))
    }
}

// ---------- 全局状态 ----------
@MainActor
final class AppState: ObservableObject {
    @Published var devices: [Keychain] = []
    @Published var currentMac: String = ""
    @Published var status: LockStatus?
    @Published var snapshot: StatusSnapshotData?
    @Published var unlockState: UnlockState = .idle
    @Published var appUnlocked: Bool
    @Published var toast: String?
    // 主题键的镜像: 变更时驱动 RootView 重建, 让配色立即生效
    @Published var themeSeed: String = DB.store.getString("kf_theme")
    /// 外观种子 (包16): 主题/品牌色/密度任一变更 +1, RootView 以 .id 重建全树实现即时换肤
    @Published var appearanceSeed = 0
    @Published var tabSelection = 0 // 设备/凭证/记录/设置
    // 包14: 首启引导完成/跳过的会话内标记 (OnboardingView 触发, 驱动 RootView 切主界面)
    @Published var onboardingFinished = false
    // 包18: Hero 一句话 (1000 晚归) / 连续失败 (1003) / 一次性时刻卡队列 (24/992/1010/1021/1050)
    @Published var homeMoment: String?
    @Published var failStreak = 0
    @Published var moment: Moment?
    @Published var writeReceipt: String?   // 包8/508 写入回执: 凭证保存成功后"已写入本机"对勾浮出
    // 包1: 开锁过程态 — 80 三段进度 / 85 重试节奏 / 250 二次开锁应用锁闸
    @Published var phase = 0            // 0 空闲 · 1 握手 · 2 鉴权 · 3 执行
    @Published var retryWait: Int?      // 85 自动重试倒计时 (秒)
    @Published var retryAttempt = 0     // 85 即将执行第几次尝试
    @Published var showGate = false     // 250 二次开锁需过应用锁
    // 包3/779: 多锁矩阵点格 → 记录 Tab 带入成员过滤 (RecordsView 消费后清空)
    @Published var pendingRecordsFilter: String?
    // 包2/136 补充: 跨页跳回 — 记录/告警入口点"跳回设备页定位该锁"时, 落点即选中并提示
    @Published var pendingJumpLock: String?
    // 包9/577 详情跳凭证: 记录/告警详情"来源凭证"→ 凭证 Tab 定位该条并高亮 (值 = "pwd:<alias>" / "fp:<batch>", mac 另存)
    @Published var pendingCredNav: String?
    @Published var pendingCredNavMac: String?
    // 包9/582 图表下钻: 统计页成员条 → 记录 Tab 按该成员过滤
    @Published var pendingRecordsMember: String?
    private var unlockTask: Task<Void, Never>? = nil
    private var lastDispatch = Date.distantPast   // 244 指令去重
    private var dispatchAt = Date.distantPast     // 56 撤销窗口计时基准
    private var lastUnlockSuccessAt: Date?        // 250 30 秒内二次开锁判定
    private var momentQueue: [Moment] = []
    let lock = LockService.shared
    let hw = HardwareService.shared

    enum UnlockState: Equatable {
        case idle, connecting, opening, success, doubleVerify, failed(String)
        var isFailed: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    init() {
        appUnlocked = !DB.hasPasscode()
        loadDevices(preferDefault: true)   // 包3/271: 冷启动落到上滑固定的默认锁
    }

    var current: Keychain? {
        devices.first { $0.mac == currentMac } ?? devices.first
    }
    var displayName: String {
        guard let kc = current else { return "离线锁管家" }
        let raw = kc.pidName
        let model = (!raw.isEmpty && !raw.contains("pid=") && !raw.contains("未知")) ? raw : PidMap.productName(kc.pid)
        return kc.name.isEmpty ? model : kc.name
    }
    // 包3/idea 271: 上滑固定的启动默认锁 — 冷启动落在默认锁; 无默认时维持原有"上次选中"行为
    func loadDevices(preferDefault: Bool = false) {
        devices = DB.keychains()
        let def = LockArchive.defaultMac
        let saved = DB.currentMac
        var next: String
        if preferDefault, devices.contains(where: { $0.mac == def }) {
            next = def
        } else if devices.contains(where: { $0.mac == saved }) {
            next = saved
        } else {
            next = devices.last?.mac ?? ""
        }
        if next != currentMac { status = nil }   // 设备身份变了 → 清实时状态 (原会沿用上一把锁的电量/固件)
        currentMac = next
        snapshot = DB.readStatus(currentMac)
    }
    func select(_ mac: String) {
        DB.currentMac = mac
        currentMac = mac
        status = nil
        snapshot = DB.readStatus(mac)
        Task { await refreshStatusQuietly() }
    }
    func refreshStatusQuietly() async {
        guard let kc = current else { return }
        do {
            try await lock.ensureConnected(mac: kc.mac)
            status = try await lock.getStatus()
            LockArchive.touchConnected(kc.mac)   // 包3/292: 连接成功刷新沉睡判定基准
        } catch {
            status = nil
        }
    }
    /// 包8/508 写入回执: 2 秒内浮出对勾, 替代云同步反馈 (纯本地, 不碰网络)
    func flashReceipt(_ msg: String) {
        writeReceipt = msg
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if writeReceipt == msg { writeReceipt = nil }
        }
    }
    func showToast(_ msg: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { toast = msg }
        // 长文案多停留一会儿, 保证读得完
        let stay: UInt64 = msg.count > 20 ? 3_400_000_000 : 1_800_000_000
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: stay)
            if toast == msg {
                withAnimation(.easeIn(duration: DS.Duration.quick)) { toast = nil } // idea 211 时长令牌
            }
        }
    }

    // 开锁 (App opendevice 语义: rc=0 成功 / rc=22 双验继续 / 其余报错)
    // 包1 手势族统一入口: 按住确认/上滑/VO 直开都汇到 requestUnlock。
    // 防误触三保险: 244 去重队列 → 250 二次开锁应用锁 → 56 撤销窗口 (执行期轻点)。
    func requestUnlock() {
        guard current != nil else { return }
        if unlockState == .connecting || unlockState == .opening {
            // 56: 指令发出后 0.8s 内轻点圆盘 = 撤销 — 拦截回执等待与自动重试链
            // (BLE 字节一旦发出无法撤回, 与 244/250 共同构成防误触保险, 不虚构"已撤回指令");
            // 自动重试等待期轻点 = 取消重试, 转手动
            if unlockState == .opening,
               Date().timeIntervalSince(dispatchAt) < 0.8 || retryWait != nil {
                cancelUnlock(notify: true)
            }
            return
        }
        let now = Date()
        // 244 指令去重: 1.2s 内的重复触发只提示, 不重复入队
        guard now.timeIntervalSince(lastDispatch) > 1.2 else {
            showToast("指令已收到, 正在执行")
            return
        }
        lastDispatch = now
        // 250: 同一锁 30 秒内再次开锁, 先过应用锁验证 (未设本机密码则无此闸)
        if DB.hasPasscode(), let t = lastUnlockSuccessAt, now.timeIntervalSince(t) < 30 {
            showGate = true
            return
        }
        startUnlock()
    }

    func startUnlock() {
        unlockTask?.cancel()
        // 836 演练包装层: 演示模式下开锁全走本地模拟 (不碰 BLE/协议/失败日志), 三阶段节奏同真实路径
        if DemoKit.isOn {
            demoUnlock()
            return
        }
        unlockTask = Task { await runUnlock() }
    }

    private func demoUnlock() {
        DemoKit.simulateDemoUnlock(phase: { p in
            self.phase = p
            self.unlockState = p == 1 ? .connecting : .opening
        }, onDone: {
            self.unlockState = .success
            self.phase = 0
            self.finishDemoDwell()
            self.showToast("演示开锁成功 (demo_ 不碰真实门锁)")
        })
    }
    private func finishDemoDwell() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if unlockState == .success {
                unlockState = .idle
                phase = 0
            }
        }
    }

    /// 56/89: 提前取消 (撤销窗口 / 握手超时取消按钮)
    func cancelUnlock(notify: Bool = false) {
        unlockTask?.cancel()
        unlockTask = nil
        phase = 0
        retryWait = nil
        if unlockState == .connecting || unlockState == .opening {
            unlockState = .idle
            if notify { showToast("已取消") }
        }
    }

    private func runUnlock() async {
        guard let kc = current else { return }
        let attempts = DB.store.getBool("kf_auto_retry", true) ? 3 : 1
        var lastMsg = ""
        for attempt in 1...attempts {
            phase = 1
            unlockState = .connecting
            do {
                try await lock.ensureConnected(mac: kc.mac)
                LinkSense.shared.noteUserConnect()   // 98 冷热标识: 用户触发的连接标"即连"
                phase = 2
                dispatchAt = Date()   // 56 撤销窗口从指令真正发出起算
                unlockState = .opening
                let rc = try await lock.unlock(mac: kc.mac)
                phase = 3
                if rc == 0 {
                    settleUnlockSuccess()
                    return
                }
                if rc == 22 {
                    unlockState = .doubleVerify
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    finishDwell(.doubleVerify)
                    return
                }
                lastMsg = StatusParser.rcFriendly(rc)   // 84 人话直读
            } catch is CancellationError {
                return   // cancelUnlock 已复位, 不计入失败
            } catch {
                lastMsg = error.localizedDescription
            }
            failStreak += 1   // 87 三连败排查清单按尝试次数累计
            // 83/85: 前两次自动静默重试, 退避 2s/5s 并显示节奏文案; 之后转手动
            if attempt < attempts, !Task.isCancelled {
                retryAttempt = attempt + 1
                for w in stride(from: attempt == 1 ? 2 : 5, through: 1, by: -1) {
                    retryWait = w
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
                retryWait = nil
                continue
            }
            break
        }
        // 终态失败: 直读原因 (84) + 写入时间线标记 (92)
        unlockState = .failed(lastMsg)
        phase = 0
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        DB.recordFailEvent(kc.mac, lastMsg)
        finishDwell(.failed(lastMsg))
    }

    /// 收尾复位: 只复位"本次操作的结果态", 用户中途已重试则不得覆盖。
    /// 成功档 2s 回待机并轻提示可查记录 (idea 247, 每天只提示一次)。
    private func finishDwell(_ finished: UnlockState) {
        let dwell: UInt64
        switch finished {
        case .success: dwell = 2_000_000_000
        case .doubleVerify: dwell = 4_200_000_000
        default: dwell = finished.isFailed ? 3_000_000_000 : 4_200_000_000
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: dwell)
            if unlockState == finished {
                unlockState = .idle
                phase = 0
                if case .success = finished { unlockReturnedHint() }
            }
            await refreshStatusQuietly()
        }
    }
    private func unlockReturnedHint() {
        let day = Milestones.dayKey()
        if DB.store.getString("kf_unlock_hint_day") != day {
            DB.store.set("kf_unlock_hint_day", day)
            showToast("本次开门已记录, 可到「记录」回看")
        }
    }
    // ---------- 外观变更 (包16: idea 21/30/31/202/910) ----------
    // 统一入口: 写存储键 → withAnimation 播 crossfade (idea 21) → 种子驱动 RootView .id 重建
    private func applyAppearance(_ mutate: () -> Void) {
        mutate()
        withAnimation(DS.Motion.soft) { appearanceSeed &+= 1 }
    }
    /// 外观模式: ""/light/dark/black
    func setTheme(_ key: String) {
        applyAppearance {
            DB.store.set("kf_theme", key)
            themeSeed = key
        }
    }
    /// 品牌主题: indigo/forest/amber
    func setAccent(_ key: String) {
        applyAppearance { DB.store.set("kf_accent", key) }
    }
    /// 布局密度: ""(标准)/compact/relaxed
    func setDensity(_ key: String) {
        applyAppearance { DB.store.set("kf_density", key) }
    }
    /// 最近开门条数 (idea 910): 3/5/10
    func setRecentCount(_ n: Int) {
        applyAppearance { DB.store.set("kf_recent_count", n) }
    }
    /// 包1 开锁偏好 (76 提示音 / 62 围栏 / 249 圆盘尺寸 / 按住确认 / 自动重试):
    /// 写存储键并经外观重建通道让圆盘即时生效 (与密度/主题同一机制)
    func setUnlockOption(_ key: String, _ v: Any) {
        applyAppearance { DB.store.set(key, v) }
    }
    /// 恢复默认外观 (idea 202): 只重置外观偏好, 不触碰任何门锁数据
    func resetAppearance() {
        applyAppearance {
            DB.store.set("kf_theme", "")
            DB.store.remove("kf_accent")
            DB.store.remove("kf_density")
            themeSeed = ""
        }
    }

    // ---------- 包18: 庆祝与成就 ----------
    /// 一次性时刻队列: 去重入队, 逐张呈现 (MomentCardView 见 Celebration.swift)
    func enqueueMoment(_ m: Moment) {
        guard !momentQueue.contains(where: { $0.id == m.id }), moment?.id != m.id else { return }
        momentQueue.append(m)
        if moment == nil { advanceMoment() }
    }
    func advanceMoment() {
        withAnimation(DS.Motion.soft) { moment = momentQueue.isEmpty ? nil : momentQueue.removeFirst() }
    }
    /// 成就结算 (开锁/备份/整理/打卡后调用): 音效(996)/本地通知(986)/时刻卡或 toast
    func evaluateAchievements() {
        for b in Milestones.evaluate() {
            if Milestones.collectSound && !Milestones.plainMode { Milestones.playCollectSound() }
            if Milestones.achNotify { Task { await Milestones.notifyAchievement(b) } }
            if Milestones.plainMode {
                showToast("徽章点亮: \(b.title)")
            } else if b.rarity == .epic {
                enqueueMoment(Moment(id: "m18." + b.id, icon: b.icon, title: "徽章点亮",
                                     subtitle: "\(b.title) · \(b.rarity.title)", celebrate: true))
            } else {
                showToast("成就达成: \(b.title)")
            }
        }
    }
    /// 启动结算: 跨年烟花(1021) / 安装周年卡(1050) / VoiceOver 记录(1049) / 成就补结算
    func onLaunch() {
        Milestones.bootstrap()
        let cal = Calendar.current
        let now = Date()
        let year = cal.component(.year, from: now)
        if cal.component(.month, from: now) == 1, cal.component(.day, from: now) == 1,
           !Milestones.onceDone("ny\(year)") {
            Milestones.markOnce("ny\(year)")
            enqueueMoment(Moment(id: "ny\(year)", icon: "sparkles", title: "陪你跨入新一年",
                                 subtitle: "日历翻过一页, 这扇门继续交给你。", celebrate: true))
        }
        if let first = Milestones.firstDate, Milestones.daysSinceFirst >= 365,
           Milestones.isSameMonthDay(first, now), !Milestones.onceDone("appann\(year)") {
            Milestones.markOnce("appann\(year)")
            enqueueMoment(Moment(id: "appann\(year)", icon: "rosette",
                                 title: "一起管了 \(Milestones.daysSinceFirst) 天",
                                 subtitle: "从第一天到现在, 谢谢你一直在。", celebrate: true))
        }
        if UIAccessibility.isVoiceOverRunning { Milestones.markVoiceOver() }
        evaluateAchievements()
        // 包4: 关怀提醒巡检 (1013 保养到期/1023 指纹头/校时 30 天/1024 防潮/146 固件, 全部本地通知)
        Task { await CareSchedule.refreshOnLaunch() }
        // 包6: 凭证流转巡检 — 回收站 30 天自动清 (497) + 月度清理任务排程 (366, 幂等)
        Task { _ = CredentialOrg.launchTick() }
        // 包8: 448 启动自检 (库体哈希 vs 上次快照, 异常挂黄条) + 1018 月度备份日排程
        //       + 428 充电备份 BGTask 注册 (系统择机执行, 不承诺接电即备) + 445 中断迁移检测
        Task { @MainActor in
            _ = BackupStudio.runStartupSelfCheck()
            await BackupStudio.scheduleMonthlyBackup()
            if DB.store.getBool("kf_bk_bgtask") { BackupStudio.registerChargeBackup() }
            if let s = BackupStudio.pendingMigration() {
                self.showToast("检测到未完成的换机迁移 (\(s.channel) \(s.step)%), 445 可回滚或继续")
            }
        }
    }
    /// 开锁成功后的里程碑结算 (24/992/1005/1010/1000); 凌晨静默态(1002)只计数不播时刻
    private func settleUnlockSuccess() {
        unlockState = .success
        phase = 0
        failStreak = 0
        lastUnlockSuccessAt = Date()   // 250
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // 包3: 258 首连验证标记 (开锁成功=全链路跑通) + 292 连接基准刷新
        LockArchive.markVerified(kc.mac)
        LockArchive.touchConnected(kc.mac)
        // 76 成功短音效: 默认只震动, 开关在设置-开锁 (系统铃声开关静音时自动无声)
        if DB.store.getBool("kf_unlock_sound") { AudioServicesPlaySystemSound(1104) }
        let crossing = Milestones.recordUnlockSuccess()
        let hour = Calendar.current.component(.hour, from: Date())
        defer { evaluateAchievements() }
        guard hour >= 6 else { return }   // 1002: 0-6 点只留触感, 不播全屏时刻
        if crossing.first {
            enqueueMoment(Moment(id: "m18.first", icon: "key.horizontal.fill",
                                 title: "第一扇门, 由你打开",
                                 subtitle: "这是你和这个家故事的开始。", celebrate: !Milestones.plainMode))
        } else if crossing.at100 {
            // 里程碑开锁触发一次庆祝: 与包18 礼花打通 (素颜模式只亮卡不撒花)
            enqueueMoment(Moment(id: "m18.100", icon: "flag.fill",
                                 title: "你已守护这个家 100 次",
                                 subtitle: "寻常的日子, 不寻常的守护。",
                                 celebrate: !Milestones.plainMode))
        }
        if crossing.at1000 { Milestones.heartbeatHaptic() }
        let year = Calendar.current.component(.year, from: Date())
        if Milestones.isBondAnniversaryToday, !Milestones.onceDone("bondann\(year)") {
            Milestones.markOnce("bondann\(year)")
            DB.store.set("kf_bond_anniv_done", true)
            enqueueMoment(Moment(id: "m18.bondann", icon: "sparkles", title: "结缘纪念日快乐",
                                 subtitle: "这一年的每一次开关, 都有你。", celebrate: !Milestones.plainMode))
        }
        if hour >= 22 { publishHomeMoment("欢迎回家, 辛苦了") }
    }
    /// Hero 卡一句话 (1000 晚归欢迎语), 8 秒后自行淡出
    private func publishHomeMoment(_ text: String) {
        withAnimation(DS.Motion.soft) { homeMoment = text }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if homeMoment == text { withAnimation(DS.Motion.exit) { homeMoment = nil } }
        }
    }

    // 最近开门 (attribution R1/R2); 条数偏好见 idea 910 (kf_recent_count, 默认 5)
    func recentRecords(count: Int? = nil) -> [(text: String, time: String, warn: Bool)] {
        guard let kc = current else { return [] }
        let n = count ?? DB.store.getInt("kf_recent_count", 5)
        let logs = DB.readLogs(kc.mac).prefix(n)
        let rows = Attribution.classify(
            logs: logs.map { LogEntry(type: $0.type, typeName: $0.typeName, idx: $0.idxRaw, idxRaw: $0.idxRaw, lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr, body: "") },
            pwds: DB.listPwds(kc.mac), fps: DB.listFps(kc.mac),
            status: status.map { ($0.fpStock, $0.pwdStock, $0.lockTime ?? 0) })
        var out = [(String, String, Bool)]()
        for (i, e) in logs.enumerated() {
            guard i < rows.count else { continue }
            let c = rows[i]
            var text = e.lockTimeStr.isEmpty ? e.typeName : String(e.lockTimeStr.dropFirst(5).prefix(11)) + " · " + e.typeName
            if let who = c.who, let m = DB.member(who) {
                text = (e.lockTimeStr.isEmpty ? "" : String(e.lockTimeStr.dropFirst(5).prefix(11)) + " · ") + m.name + " 用" + (Attribution.words[c.kind ?? ""] ?? "") + "开了门"
            }
            let warn = e.type == 7 || e.type == 13 || e.type == 224
            out.append((text, e.lockTimeStr, warn))
        }
        return out
    }
}

// ---------- 根视图 (AppLock 门禁 + TabView) ----------
struct RootView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var sense = LinkSense.shared
    @Environment(\.scenePhase) private var scenePhase
    // 读取 themeSeed: 设置页切换主题时立即重建配色
    private var colorScheme: ColorScheme? { Theme.scheme(for: app.themeSeed) }
    var body: some View {
        Group {
            if !Onboarding.allDone && !app.onboardingFinished {
                // 包14 首启五步: 承诺/导览/角色/权限/演示/自检/证书, 进度逐键存档 (804);
                // 完成后切换进主界面, 其 .task 触发 onLaunch 结算
                OnboardingView(onExit: { app.onboardingFinished = true })
                    .environmentObject(app)
            } else if app.appUnlocked {
                // iOS 18+ 的 Tab 声明式写法: 类型安全, 系统按平台自动选择底栏/侧栏形态
                // 包15 全键盘导航 (854/164/530): Tab 遍历 + Cmd/Control 1-4 切 Tab
                // 包2/136 跨页状态细条: 非设备 Tab 顶部一条 BLE 状态细线, 点按跳回设备页定位当前锁;
                // 162 握手可离开: 切走 Tab 不取消进行中的握手 (回连循环/看门狗继续跑)
                TabView(selection: $app.tabSelection) {
                    Tab("设备", systemImage: "lock.fill", value: 0) { DeviceHomeView() }
                        .keyboardShortcut("1", modifiers: .command)
                    Tab("凭证", systemImage: "key.horizontal.fill", value: 1) {
                        CredentialsView()
                            .safeAreaInset(edge: .top, spacing: 0) { bleStatusStrip(app: app, sense: sense) }
                    }
                    .keyboardShortcut("2", modifiers: .command)
                    Tab("记录", systemImage: "list.bullet.rectangle.fill", value: 2) {
                        RecordsView()
                            .safeAreaInset(edge: .top, spacing: 0) { bleStatusStrip(app: app, sense: sense) }
                    }
                    .keyboardShortcut("3", modifiers: .command)
                    Tab("设置", systemImage: "gearshape.fill", value: 3) {
                        SettingsView()
                            .safeAreaInset(edge: .top, spacing: 0) { bleStatusStrip(app: app, sense: sense) }
                    }
                    .keyboardShortcut("4", modifiers: .command)
                }
                // 用 safeAreaInset 而不是 overlay — 覆盖式会压住导航栏标题
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        // 包14/836 演示模式常驻横幅: 四 Tab 共用, 演示数据全路径可辨识
                        DemoBanner()
                        // 包2/69 蓝牙直通条: 系统蓝牙关闭时全 App 顶部提示 (深链系统设置不可用 → 指引文案)
                        if !LinkSense.shared.btOn {
                            BLEOffBanner { LinkSense.shared.openBluetoothSettings() }
                        }
                        // 包8/448 启动自检黄条: 库体哈希与上次快照不一致 → 设备 Tab 顶部黄条 "去诊断"
                        if let w = BackupStudio.selfCheckWarning {
                            HStack(spacing: DS.Space.xs) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: DS.Icon.sm, weight: .semibold))
                                    .accessibilityHidden(true)
                                Text(w).font(.caption).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Button("去诊断") { app.tabSelection = 3 }
                                    .font(.caption.weight(.medium))
                            }
                            .foregroundStyle(DS.Palette.warn)
                            .padding(.horizontal, DS.Space.l)
                            .padding(.vertical, DS.Space.s)
                            .background(DS.Palette.warn.opacity(0.14))
                        }
                        if let t = app.toast {
                            ToastView(text: t)
                                .allowsHitTesting(false)   // 顶部提示不吃点击
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        // 包8/508 写入回执: 凭证保存/停用成功后对勾浮出 (替代云同步反馈)
                        if let r = app.writeReceipt {
                            HStack(spacing: DS.Space.xs) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: DS.Icon.md))
                                    .foregroundStyle(DS.Palette.ok)
                                    .accessibilityHidden(true)
                                Text(r)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(DS.Palette.text)
                            }
                            .padding(.horizontal, DS.Space.l)
                            .padding(.vertical, DS.Space.s)
                            .background(DS.Palette.surface, in: Capsule())
                            .shadow(color: .cardElevation, radius: 8, y: 3)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .allowsHitTesting(false)
                        }
                    }
                }
                // 包18: 一次性时刻卡 (里程碑/周年/史诗徽章) 覆盖层
                .overlay {
                    if let m = app.moment {
                        MomentCardView(moment: m) { app.advanceMoment() }
                            .transition(.opacity.combined(with: .scale(0.96)))
                    }
                }
                .animation(DS.Motion.soft, value: app.moment)
                .task {
                    app.onLaunch()
                    RootView.registerHost(app)   // 包2: LinkSense 宿主注册 + 回连/巡检循环
                    LinkSense.shared.coldStartScan()   // 包2/134 冷启动先扫描 (定位可见锁, 不连接)
                }
                .onChange(of: scenePhase) { _, phase in   // 135 回前台即刷新
                    LinkSense.shared.setSceneActive(phase == .active)
                    // 靠近自动开锁 (AUTOOPEN): F0 前台门 + F1 进前台按档位刷面容 (挂起期静默)
                    if phase == .active {
                        AutoOpenController.shared.onForeground(mac: app.currentMac)
                    } else {
                        AutoOpenController.shared.onBackground()
                    }
                }
            } else {
                AppLockView()
                    // 解锁的"穿越感": 门禁界面轻微放大溶解, 主界面从后面浮现
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .scale(1.08).combined(with: .opacity)))
            }
        }
        // 包16: 外观种子变更时整树重建 — 配色/密度即时全局生效; withAnimation 提供淡入淡出 (idea 21)
        .id(app.appearanceSeed)
        // 包15: App 字号五档 × 系统 Dynamic Type 叠加 (858, 含 866 极限字号自检 200% 预览)
        .dynamicTypeSize(AXFlags.typeSize())
        // 包15: 灰度预览自检 (879) — 全 App 去饱和, 检查渐变主题无色可读性
        .saturation(AXFlags.grayPreview ? 0 : 1)
        .animation(DS.Motion.soft, value: app.appUnlocked)
        .sensoryFeedback(.selection, trigger: app.tabSelection)   // Tab 切换的轻触感
        .preferredColorScheme(colorScheme)
    }
    // 包2/136 跨页状态细条: 非设备 Tab 顶部一条 BLE 状态细线 (2pt 语义色 + 状态行),
    // 点按跳回设备 Tab 并定位当前锁; 135 scenePhase .active 时静默刷新, 退后台暂停回连。
    @ViewBuilder
    private func bleStatusStrip(app: AppState, sense: LinkSense) -> some View {
        BLEStrip(title: "跳回设备页", state: sense.linkState,
                 detail: sense.lastRssi.map { "RSSI \($0)" }) {
            app.tabSelection = 0
            app.pendingJumpLock = app.currentMac
        }
    }
}

// LinkSense 宿主注册 (RootView 首次挂载时): 包装层只读协作, 不建循环依赖
extension RootView {
    @MainActor
    static func registerHost(_ app: AppState) {
        AppState.hostRef = app
        LinkSense.shared.startReconnectLoop()
        LinkSense.shared.startDeadWatch()
    }
}

// ---------- 全局 Toast (悬浮在内容之上, 用 iOS 26 的液态玻璃) ----------
struct ToastView: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .foregroundStyle(DS.Palette.text)
            .lineLimit(3)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.s + 2)
            .frame(maxWidth: 420)
            // 玻璃层自带深浅色适配与背景折射, 不需要再叠一层描边
            .axGlass(DS.Radius.control)
            .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
            .padding(.horizontal, DS.Space.xl)
            .padding(.top, DS.Space.xs)
            .accessibilityAddTraits(.isStaticText)
    }
}

// ---------- 应用锁 (JS utils/passcode.js 语义) ----------
struct AppLockView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pw = ""
    @State private var failed = false
    @State private var breathe = false
    @State private var failCount = 0   // 877 应用锁连败计数: 3 次后切大字替代键降级路径
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: DS.Space.l) {
            Spacer(minLength: DS.Space.xl)

            // 门禁入口的第一眼: 玻璃圆盘托住盾形锁, 缓慢呼吸 (±3% / 3.2s) —
            // 静止的锁屏像贴图, 会呼吸的像正在值守的门卫
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(DS.Palette.accentText)
                .frame(width: 92, height: 92)
                .axGlassCircle()
                .scaleEffect(breathe ? 1.03 : 1)
                .accessibilityHidden(true)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { breathe = true }
                }

            VStack(spacing: DS.Space.s) {
                Text("离线锁管家已锁定")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(DS.Palette.text)
                Text("输入本机密码以查看门锁与凭证")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: DS.Space.s) {
                // 自定义 Binding 而非 onChange: 后者在新 SDK 已废弃, 且会连带触发弃用警告
                TextField("本机密码", text: Binding(get: { pw }, set: { newValue in
                    pw = newValue
                    if failed { withAnimation(DS.Motion.quick) { failed = false } }
                }))
                    .textContentType(.password)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, DS.Space.m)
                    .padding(.horizontal, DS.Space.l)
                    .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.control))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.control)
                            .strokeBorder(failed ? DS.Palette.danger : DS.Palette.hairline,
                                          lineWidth: focused || failed ? 1.5 : 0.5)
                    )
                    .frame(maxWidth: 280)
                    .focused($focused)
                    .submitLabel(.go)
                    .onSubmit(unlockAttempt)

                if failed {
                    Label("密码错误, 请重新输入", systemImage: "exclamationmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.danger)
                        .transition(.opacity)
                }
            }

            Button("解锁", action: unlockAttempt)
                .buttonStyle(PrimaryActionStyle())
                .frame(maxWidth: 280)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(pw.isEmpty)
            // 877 验证降级大键: 连败 3 次后, 设备支持 Face ID / Touch ID 时给大字替代键 (56pt+)
            if failCount >= 3, AuthKit.biometricAvailable {
                Button("用 Face ID / Touch ID 解锁 (大字)") {
                    AuthKit.verifyBiometric {
                        app.appUnlocked = true
                        failCount = 0
                    }
                }
                .font(.title2.weight(.semibold))
                .padding(.vertical, DS.Space.m)
                .padding(.horizontal, DS.Space.xl)
                .frame(maxWidth: 280)
                .frame(minHeight: 56)
                .background(DS.Palette.accentText.opacity(0.09),
                            in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                .foregroundStyle(DS.Palette.accentText)
                .accessibilityLabel("生物识别解锁, 大字替代键")
            }

            Spacer(minLength: DS.Space.xl)
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dsScreenBackground()
        .animation(DS.Motion.soft, value: failed)
    }

    private func unlockAttempt() {
        guard !pw.isEmpty else { return }
        if DB.verifyPasscode(pw) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            focused = false
            failCount = 0
            withAnimation(DS.Motion.standard) { app.appUnlocked = true }
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            failCount += 1
            if failCount >= 3 { AXTools.announce("密码连续输错, 可改用下方大字生物识别解锁") }
            withAnimation(DS.Motion.quick) { failed = true }
        }
        pw = ""
    }
}

// ---------- 通用组件 ----------
// 按压反馈 (idea 213 统一按压态): 轻缩放 0.96 + 阴影抬升, 只做 transform 不改 bounds,
// 不引起周围布局抖动。全 App 通用按钮统一走这一份。
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .shadow(color: .black.opacity(configuration.isPressed ? 0.16 : 0), radius: 7, y: 3)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(DS.Motion.quick, value: configuration.isPressed)
    }
}

/// 卡片表面: 靠 surface 与渐变画布的明度差分层, 不加描边。
/// 每张卡都套 0.5pt 描边会让所有卡片看起来出自同一个模板 —— 描边是 1px Web 做法,
/// iOS 上 surface/canvas 的明度差已经足够表达层级, 描边反而是重复劳动。
/// 阴影在深色模式下纯黑不可见, 故改用极淡的提亮。
/// `tint` 给"需要处理"的卡混入语义色底 (8%), 让异常自带色温而不靠描边。
private extension Color {
    static var cardElevation: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(Color.white).withAlphaComponent(0.04)
                : UIColor(Color.black).withAlphaComponent(0.05)
        })
    }
}

struct Card<Content: View>: View {
    var tint: ToneColor?
    var content: Content
    init(tint: ToneColor? = nil, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }
    private var tintWash: Color {
        tint.map { $0.color.opacity(0.08) } ?? .clear
    }
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.l)
            .background {
                let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                shape.fill(DS.Palette.surface)
                    .overlay(shape.fill(tintWash))
            }
            .shadow(color: .cardElevation, radius: 12, y: 4)
            .padding(.horizontal, DS.Space.gutter)
    }
}
struct SectionTitle: View {
    var text: String
    var count: Int?
    var body: some View {
        HStack(spacing: DS.Space.s) {
            // 品牌色小竖标: 不占一行的宽度, 却让分区标题有自己的"签名"
            Capsule()
                .fill(DS.Palette.accent)
                .frame(width: 3, height: 14)
                .accessibilityHidden(true)
            Text(text)
                .font(.headline)
                .foregroundStyle(DS.Palette.text)
            if let count {
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DS.Palette.textSub)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(DS.Palette.surfaceAlt, in: Capsule())
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}