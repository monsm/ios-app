// ================= 游戏化·情感化·纪念 (功能包18) — 统计与成就引擎 =================
// 纯数据层, 不含 UI。数据源 = 既有本地台账 (kf_logcache_ / kf_ledger_ / kf_keychains / kf_members)
// + 本文件新增的包18 kf_* 键。全离线, 不依赖网络与推送 (提醒一律 UNUserNotificationCenter 本地通知)。
// 性能 (ROADMAP 包18 第5条): 一次结算 O(日志≤300/锁), UI 只读结果, 统计逻辑全部收在这里。
import Foundation
import UIKit
import UserNotifications

// ---------- 徽章定义 (977 四类 / 979 稀有度 / 978 隐藏) ----------
enum BadgeRarity {
    case common, rare, epic
    var title: String {
        switch self {
        case .common: return "常见"
        case .rare: return "稀有"
        case .epic: return "史诗"
        }
    }
}

enum BadgeCat: String, CaseIterable, Identifiable {
    case butler = "管家"
    case guardDuty = "守护"
    case organize = "整理"
    case explore = "探索"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .butler: return "house.fill"
        case .guardDuty: return "shield.lefthalf.filled"
        case .organize: return "tray.full.fill"
        case .explore: return "sparkles"
        }
    }
}

struct Badge: Identifiable, Equatable {
    let id: String
    let cat: BadgeCat
    let title: String
    let detail: String     // 达成条件文案 (idea 840 未达成卡直接展示)
    let icon: String
    let rarity: BadgeRarity
    let hidden: Bool       // idea 978: 达成前只显示"还差一点点"
}

// ---------- 统计快照 ----------
struct MStats {
    var unlockTotal = 0
    var streakBest = 0
    var nightCount = 0
    var nightOwlBest = 0
    var backupStreak = 0
    var backupThisMonth = 0
    var organizeTotal = 0
    var weekStar = false
    var ownedCred = false
    /// 995 join1 的真判据: **在本 App 里建过档的成员** (建档时刻 `at` > 0) **名下有 ≥1 条归属凭证**。
    /// 与 `ownedCred` 的区别就是这条徽章文案里"新成员"那半截 —— 见 `case "join1"` 的注释。
    var joinedWithCred = false
    var daysSinceFirst = 0
    var bondAnnivDone = false
    var batterySwaps = 0   // 包4/1039
    var careStreak = 0     // 包4/1030
}

enum Milestones {
    // ---------- 日期工具 ----------
    /// 日 key 的**唯一口径是 `StatsKit.dayKey`** (yyyy-MM-dd + en_US_POSIX + 当前时区)。
    /// 此前这里自己 new 了一个 DateFormatter 抄同一段逻辑 —— 值恰好相同，但"同一件事两处写"
    /// 一旦改一处就会让里程碑与统计/日志分组对不齐 (§10.30)。
    static func dayKey(_ d: Date = Date()) -> String { StatsKit.dayKey(d) }
    static func monthKey(_ d: Date = Date()) -> String {
        String(dayKey(d).prefix(7))
    }
    static func mdKey(_ d: Date = Date()) -> String {   // "MM-dd"
        String(dayKey(d).suffix(5))
    }
    static func isSameMonthDay(_ a: Date, _ b: Date) -> Bool { mdKey(a) == mdKey(b) }

    // ---------- 一次性标记 / 偏好 ----------
    static func onceDone(_ k: String) -> Bool {
        let m = DB.store.get([String: Bool].self, "kf_once") ?? [:]
        return m[k] == true
    }
    static func markOnce(_ k: String) {
        var m = DB.store.get([String: Bool].self, "kf_once") ?? [:]
        m[k] = true
        DB.store.setCodable("kf_once", m)
    }
    /// 1046 素颜模式: 一键关闭全部庆祝动效 (时刻卡保留内容, 不播粒子)
    static var plainMode: Bool { DB.store.getBool("kf_plain") }
    /// 898 启动一句话：本机短语表按**当天**取一条 (不是每次刷新随机)。
    /// 为什么必须按日期定值：这条挂在 Hero 卡上，而 Hero 卡在一次会话里会重算很多次；
    /// 用 arc4random 就会每重算一次换一句话，用户看到的是"卡片在自言自语地跳字"。
    /// 素颜模式 (1046) 与晚归欢迎 (1000)、节气问候 (1001) 都排在它前面 —— 有正事时不打扰。
    static func launchPhrase(_ now: Date = Date()) -> String? {
        guard DB.store.getBool("kf_launch_line", true), !plainMode else { return nil }
        let lines = [
            "门在这儿，钥匙也在这儿。",
            "离线也能开 —— 蓝牙就是钥匙。",
            "今天先看一眼电量，省得蹲门跟前。",
            "记录都在本机，没往任何地方传。",
            "备份一次，胜过祈祷十次。",
            "开门这事，慢半拍比错半拍好。",
        ]
        let day = Int(WeekCal.calendar.startOfDay(for: now).timeIntervalSince1970 / 86_400)
        return lines[abs(day) % lines.count]
    }
    /// 996 收集音效 (默认开)
    static var collectSound: Bool { DB.store.getBool("kf_collect_sound", true) }
    /// 986 成就解锁本地通知 (默认开)
    static var achNotify: Bool { DB.store.getBool("kf_ach_notify", true) }

    // ---------- 启动引导: 首用时间 (1050) 与结缘日 (1010) ----------
    static func bootstrap() {
        if DB.store.get(Double.self, "kf_first_at") == nil {
            DB.store.set("kf_first_at", Date().timeIntervalSince1970 * 1000)
        }
        // 结缘日 = 首次绑锁日期 (keychain 最早 pairedAt); 只在首次读到设备时落一次
        if (DB.store.getString("kf_bond_day")).isEmpty, let kc = DB.keychains().first {
            let p = kc.pairedAt
            let day = p.count >= 10 ? String(p.prefix(10)) : dayKey()
            if day.count == 10, day.contains("-") { DB.store.set("kf_bond_day", day) }
        }
    }
    static var firstDate: Date? {
        guard let t = DB.store.get(Double.self, "kf_first_at"), t > 0 else { return nil }
        return Date(timeIntervalSince1970: t / 1000)
    }
    static var daysSinceFirst: Int {
        guard let first = firstDate else { return 0 }
        return max(0, Int(Date().timeIntervalSince(first) / 86400))
    }
    /// 结缘日 "yyyy-MM-dd" (可能为空 — 还没添加过锁)
    static var bondDay: String { DB.store.getString("kf_bond_day") }
    static var isBondAnniversaryToday: Bool {
        let b = bondDay
        return b.count == 10 && String(b.suffix(5)) == mdKey()
    }

    // ---------- 975 管家连续天数 (每日查看记录 Tab) ----------
    struct Streak { var cur = 0; var best = 0 }
    static func streak() -> Streak {
        let s = DB.store.get([String: Int].self, "kf_streak") ?? [:]
        return Streak(cur: s["cur"] ?? 0, best: s["best"] ?? 0)
    }
    static func markRecordsViewed() {
        let today = dayKey()
        var s = DB.store.get([String: Int].self, "kf_streak") ?? [:]
        let lastDay = DB.store.getString("kf_streak_last")   // 单独存字符串键 (与计数字典分型)
        guard lastDay != today else { return }
        let yest = dayKey(WeekCal.gregorian.date(byAdding: .day, value: -1, to: Date())!)
        let cur = (lastDay == yest) ? (s["cur"] ?? 0) + 1 : 1
        s["cur"] = cur
        s["best"] = max(s["best"] ?? 0, cur)
        DB.store.setCodable("kf_streak", s)
        DB.store.set("kf_streak_last", today)
    }

    // ---------- 976 安心夜打卡 + 985 衑签 ----------
    /// 22 点后可打卡 (纯手动确认 — 协议无上锁状态位, 不猜测)
    static var canNightCheckIn: Bool { WeekCal.gregorian.component(.hour, from: Date()) >= 22 }
    static func nightMarks() -> [String: String] {
        DB.store.get([String: String].self, "kf_night_marks") ?? [:]
    }
    @discardableResult
    static func checkInTonight() -> Bool {
        guard canNightCheckIn else { return false }
        var m = nightMarks()
        let k = dayKey()
        guard m[k] == nil else { return false }
        m[k] = "ok"
        DB.store.setCodable("kf_night_marks", m)
        return true
    }
    /// 本月还有补签额度吗 (每月 1 张)
    static var repairQuotaLeft: Bool {
        let used = DB.store.get([String: Int].self, "kf_night_repairs")?[monthKey()] ?? 0
        return used < 1
    }
    /// 可补的日子: 本月内最近一个未标记的过去日期
    static var repairableDay: String? {
        guard repairQuotaLeft else { return nil }
        let marks = nightMarks()
        let cal = WeekCal.gregorian
        var d = cal.date(byAdding: .day, value: -1, to: Date())!
        let mk = monthKey()
        for _ in 0..<31 {
            let k = dayKey(d)
            guard monthKey(d) == mk else { return nil }   // 只补本月
            if marks[k] == nil { return k }
            d = cal.date(byAdding: .day, value: -1, to: d)!
        }
        return nil
    }
    @discardableResult
    static func repairDay(_ k: String) -> Bool {
        guard k == repairableDay else { return false }
        var m = nightMarks()
        m[k] = "repair"
        DB.store.setCodable("kf_night_marks", m)
        var r = DB.store.get([String: Int].self, "kf_night_repairs") ?? [:]
        r[monthKey(), default: 0] += 1
        DB.store.setCodable("kf_night_repairs", r)
        return true
    }

    // ---------- 982/992/1005/1006 开锁计数 (App 侧成功次数, 不受锁端日志条数上限约束) ----------
    struct UnlockCrossing { var first = false; var at100 = false; var at1000 = false }
    static var unlockTotal: Int { DB.store.getInt("kf_unlock_count") }
    static func recordUnlockSuccess() -> UnlockCrossing {
        let n = unlockTotal + 1
        DB.store.set("kf_unlock_count", n)
        return UnlockCrossing(first: n == 1, at100: n == 100, at1000: n == 1000)
    }
    /// 1005 千次心跳触感 (两拍)
    static func heartbeatHaptic() {
        // 触感生成器是主 actor 的; 本函数挂在开锁收尾链上 (那一段不保证在主线程), 所以显式跳一次。
        // 两拍用 Task.sleep 而不是 DispatchQueue.asyncAfter: 同一件事, 但 Task 是结构化并发的一等公民,
        // 也不必把一个 @Sendable 的 GCD 闭包塞进非隔离函数里 (那正是 Swift 6 判错的那种写法)。
        Task { @MainActor in
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try? await Task.sleep(for: .milliseconds(220))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // ---------- 980/997 备份历史 (上传成功 / 生成本地备份文本 各记一次) ----------
    @MainActor
    static func recordBackup() {
        var h = DB.store.get([Double].self, "kf_backup_hist") ?? []
        h.append(Date().timeIntervalSince1970 * 1000)
        if h.count > 60 { h.removeFirst(h.count - 60) }
        DB.store.setCodable("kf_backup_hist", h)
        // 448: 备份发生点 = 自检基线更新点 (导出/上传/还原点全覆盖; 自检本身绝不回写)
        BackupStudio.markBackupBaseline()
    }
    static var backupThisMonth: Int {
        let mk = monthKey()
        return (DB.store.get([Double].self, "kf_backup_hist") ?? [])
            .filter { monthKey(Date(timeIntervalSince1970: $0 / 1000)) == mk }.count
    }
    /// 822 「还没有备份」要看的那一个事实: 本机最后一次生成/上传备份的时刻。
    /// 读的就是 recordBackup 写的那本历史 (毫秒位，与上面两个读者同一换算)，
    /// 不另开一个"上次备份时间"键 —— 两处各存一份迟早分叉。
    static var lastBackupAt: Date? {
        guard let h = DB.store.get([Double].self, "kf_backup_hist"), let t = h.max(), t > 0
        else { return nil }
        return Date(timeIntervalSince1970: t / 1000)
    }
    /// 980 连续月数 (从本月起; 本月还没备则从上月起)
    static var backupStreakMonths: Int {
        let months = Set((DB.store.get([Double].self, "kf_backup_hist") ?? [])
            .map { monthKey(Date(timeIntervalSince1970: $0 / 1000)) })
        let cal = WeekCal.gregorian
        var cursor = Date()
        if !months.contains(monthKey(cursor)) {
            guard let prev = cal.date(byAdding: .month, value: -1, to: cursor) else { return 0 }
            cursor = prev
        }
        var n = 0
        while months.contains(monthKey(cursor)), n < 36 {
            n += 1
            guard let prev = cal.date(byAdding: .month, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return n
    }

    // ---------- 981/1007 整理凭证 (周目标 + 致谢计数) ----------
    static var organizeTotal: Int { DB.store.getInt("kf_organize_count") }
    static var weekTarget: Int {
        get { DB.store.getInt("kf_week_target", 3) }
        set { DB.store.set("kf_week_target", max(1, min(7, newValue))) }
    }
    /// 本周整理次数 (周起点跟随 912 偏好)
    static var weekDone: Int {
        let stamps = DB.store.get([Double].self, "kf_organize_log") ?? []
        let cal = WeekCal.calendar
        let wk = cal.component(.weekOfYear, from: Date())
        let yr = cal.component(.yearForWeekOfYear, from: Date())
        return stamps.filter {
            cal.component(.weekOfYear, from: Date(timeIntervalSince1970: $0 / 1000)) == wk &&
            cal.component(.yearForWeekOfYear, from: Date(timeIntervalSince1970: $0 / 1000)) == yr
        }.count
    }
    /// 记一次整理; 返回是否该弹致谢 (1007: 每 10 次)
    @discardableResult
    static func recordOrganize() -> Bool {
        let n = organizeTotal + 1
        DB.store.set("kf_organize_count", n)
        var log = DB.store.get([Double].self, "kf_organize_log") ?? []
        log.append(Date().timeIntervalSince1970 * 1000)
        if log.count > 200 { log.removeFirst(log.count - 200) }
        DB.store.setCodable("kf_organize_log", log)
        // 981 周目标星: 达成即点亮 (一次性)
        if weekDone >= weekTarget && !DB.store.getBool("kf_week_star") {
            DB.store.set("kf_week_star", true)
        }
        return n % 10 == 0
    }

    // ---------- 成员档案扩展 (989/994 徽章角标 · 991/1017 生日手填) ----------
    static func memberBadges() -> [String: String] {
        DB.store.get([String: String].self, "kf_member_badge") ?? [:]
    }
    static func setMemberBadge(_ memberId: String, _ badgeId: String?) {
        var m = memberBadges()
        if let badgeId { m[memberId] = badgeId } else { m.removeValue(forKey: memberId) }
        DB.store.setCodable("kf_member_badge", m)
    }
    static func memberBirthdays() -> [String: String] {   // memberId → "MM-dd"
        DB.store.get([String: String].self, "kf_member_bday") ?? [:]
    }
    static func setMemberBirthday(_ memberId: String, _ md: String?) {
        var m = memberBirthdays()
        if let md, md.count == 5, md.contains("-") { m[memberId] = md } else { m.removeValue(forKey: memberId) }
        DB.store.setCodable("kf_member_bday", m)
    }
    /// 991 今天的寿星
    static var birthdayCelebrantToday: Member? {
        let today = mdKey()
        guard let id = memberBirthdays().first(where: { $0.value == today })?.key else { return nil }
        return DB.member(id)
    }

    // ---------- 1045 感谢清单 (按月) ----------
    static func gratitude(_ month: String = "") -> [String] {
        (DB.store.get([String: [String]].self, "kf_gratitude") ?? [:])[month.isEmpty ? monthKey() : month] ?? []
    }
    static func addGratitude(_ name: String) {
        var g = DB.store.get([String: [String]].self, "kf_gratitude") ?? [:]
        let list = g[monthKey()] ?? []
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !list.contains(n) else { return }
        g[monthKey(), default: []].append(n)
        DB.store.setCodable("kf_gratitude", g)
    }
    static func removeGratitude(_ name: String) {
        var g = DB.store.get([String: [String]].self, "kf_gratitude") ?? [:]
        g[monthKey()]?.removeAll { $0 == name }
        DB.store.setCodable("kf_gratitude", g)
    }

    // ---------- 1043 时光胶囊 ----------
    struct Capsule: Codable { var text: String; var at: Double; var openOn: String }
    static func capsule() -> Capsule? { DB.store.get(Capsule.self, "kf_capsule") }
    static func saveCapsule(_ text: String) {
        // 开启日 = 下一个结缘日 (无结缘日则写作一年后)
        let cal = WeekCal.gregorian
        let b = bondDay
        let now = Date()
        var openOn = dayKey(cal.date(byAdding: .year, value: 1, to: now)!)
        if b.count == 10 {
            // 开启日 = 下一个结缘日 (今天恰是结缘日则落到明年, 避免当天写当天开)
            let md = String(b.suffix(5))
            let y = cal.component(.year, from: now)
            var candidate = "\(y)-\(md)"
            if candidate <= dayKey(now) { candidate = "\(y + 1)-\(md)" }
            openOn = candidate
        }
        DB.store.setCodable("kf_capsule", Capsule(text: text, at: now.timeIntervalSince1970 * 1000, openOn: openOn))
    }
    static func capsuleIsOpen(_ c: Capsule) -> Bool { dayKey() >= c.openOn }

    // ---------- 1044 家庭公告板 ----------
    static var bulletin: String {
        get { DB.store.getString("kf_bulletin") }
        set { DB.store.set("kf_bulletin", newValue) }
    }

    // ---------- 1049 VoiceOver 陪伴天数 ----------
    static func markVoiceOver() {
        if DB.store.get(Double.self, "kf_vo_first") == nil {
            DB.store.set("kf_vo_first", Date().timeIntervalSince1970 * 1000)
        }
    }
    static var voiceOverDays: Int? {
        guard let t = DB.store.get(Double.self, "kf_vo_first"), t > 0 else { return nil }
        return Int(Date().timeIntervalSince1970 * 1000 - t) / 86_400_000
    }

    // ---------- 999 史诗徽章流光边 (7 天, 素颜模式关) ----------
    static var heroFlairActive: Bool {
        guard !plainMode else { return false }
        let done = unlockedMap()
        let now = Date().timeIntervalSince1970 * 1000
        return definitions.contains { d in
            d.rarity == .epic && !d.hidden && done[d.id].map { now - $0 < 7 * 86400 * 1000 } == true
        }
    }

    // ---------- 1011/1008 陪伴天数文案 ----------
    /// 1011 陪伴天数唯一算术 (companionText 与满年徽章共用; 无效时间/未来时间 = nil)
    static func companionDays(_ atMs: Double) -> Int? {
        guard atMs > 0 else { return nil }
        let days = Int(Date().timeIntervalSince1970 * 1000 - atMs) / 86_400_000
        return days >= 0 ? days : nil
    }
    /// 1011 满年徽章判据: 与副行 "· 满一年了" 后缀同一道天数额 (365 只写这里一处)
    static func companionFullYear(_ atMs: Double) -> Bool {
        (companionDays(atMs) ?? 0) >= 365
    }
    static func companionText(_ atMs: Double, prefix: String = "已陪伴") -> String? {
        guard let days = companionDays(atMs) else { return nil }
        return companionFullYear(atMs) ? "\(prefix) \(days) 天 · 满一年了" : "\(prefix) \(days) 天"
    }

    // ---------- 1001 节气 (寿星公式近似, 纯本地; 问候级容差 ±1 天) ----------
    static let solarTermTable: [(m: Int, name: String, c: Double)] = [
        (1, "小寒", 5.4055), (1, "大寒", 20.12), (2, "立春", 3.87), (2, "雨水", 18.73),
        (3, "惊蛰", 5.63), (3, "春分", 20.646), (4, "清明", 4.81), (4, "谷雨", 20.1),
        (5, "立夏", 5.52), (5, "小满", 21.04), (6, "芒种", 5.678), (6, "夏至", 21.37),
        (7, "小暑", 7.108), (7, "大暑", 22.83), (8, "立秋", 7.5), (8, "处暑", 23.13),
        (9, "白露", 7.646), (9, "秋分", 23.042), (10, "寒露", 8.318), (10, "霜降", 23.438),
        (11, "立冬", 7.438), (11, "小雪", 22.36), (12, "大雪", 7.18), (12, "冬至", 21.94),
    ]
    static func solarTermToday(_ now: Date = Date()) -> String? {
        let cal = WeekCal.gregorian
        let y = cal.component(.year, from: now) % 100
        let m = cal.component(.month, from: now)
        let d = cal.component(.day, from: now)
        for t in solarTermTable where t.m == m {
            let l = m <= 2 ? (y - 1) / 4 : y / 4
            if Int(Double(y) * 0.2422 + t.c) - l == d { return t.name }
        }
        return nil
    }
    static func solarTermHint(_ name: String) -> String {
        switch name {
        case "小寒", "大寒", "冬至": return "一年里最冷的时节, 出门记得添衣"
        case "立春": return "春天从今天算起, 门里门外都是新的"
        case "雨水", "谷雨": return "带伞的日子, 出门前看一眼天"
        case "立夏": return "夏天来了, 记得给门锁喂电"
        case "立秋": return "一叶知秋, 早晚开始凉了"
        case "立冬": return "冬天来了, 指纹头怕冷也怕干"
        default: return "节气更替, 注意冷暖"
        }
    }

    // ---------- 徽章总表 (id 稳定, 勿改 — kf_ach_done 以 id 为键) ----------
    static let definitions: [Badge] = [
        // 管家
        Badge(id: "bond", cat: .butler, title: "初来乍到", detail: "添加第一把门锁", icon: "door.left.hand.open", rarity: .common, hidden: false),
        Badge(id: "streak3", cat: .butler, title: "三日之约", detail: "连续 3 天查看记录", icon: "flame.fill", rarity: .common, hidden: false),
        Badge(id: "streak7", cat: .butler, title: "恒心管家", detail: "连续 7 天查看记录", icon: "flame.fill", rarity: .rare, hidden: false),
        Badge(id: "night1", cat: .butler, title: "安心之夜", detail: "完成一次安心夜打卡", icon: "moon.stars.fill", rarity: .common, hidden: false),
        Badge(id: "night30", cat: .butler, title: "长明灯", detail: "安心夜打卡累计 30 夜", icon: "sparkles.rectangle.stack.fill", rarity: .rare, hidden: false),
        // 守护
        Badge(id: "backup3", cat: .guardDuty, title: "备份卫士", detail: "连续 3 个月每月至少备份一次", icon: "externaldrive.badge.checkmark", rarity: .rare, hidden: false),
        Badge(id: "un100", cat: .guardDuty, title: "百次守护", detail: "累计开锁 100 次", icon: "flag.fill", rarity: .common, hidden: false),
        Badge(id: "un500", cat: .guardDuty, title: "五百门神", detail: "累计开锁 500 次", icon: "flag.checkered", rarity: .rare, hidden: false),
        Badge(id: "un2000", cat: .guardDuty, title: "两千传奇", detail: "累计开锁 2000 次", icon: "crown.fill", rarity: .epic, hidden: false),
        // 993 夜猫守护徽章 (2026-10-10 拍板: 保留**奖励**语义，不改成告警)。判据只用本地日志的凌晨时段
        // 开门计数 (0-6 点单月 ≥5)，不动协议、不上云; 纯计数事实不是推断，所以文案不写"约"。
        Badge(id: "owl", cat: .guardDuty, title: "夜猫子", detail: "单月凌晨 0-6 点开门 5 次", icon: "moon.zzz.fill", rarity: .rare, hidden: true),
        Badge(id: "heart1000", cat: .guardDuty, title: "千次心跳", detail: "累计开锁 1000 次", icon: "heart.fill", rarity: .epic, hidden: true),
        // 整理
        Badge(id: "owner", cat: .organize, title: "各就各位", detail: "把一条凭证归属到成员", icon: "person.crop.circle.badge.checkmark", rarity: .common, hidden: false),
        Badge(id: "tidy10", cat: .organize, title: "整理大师", detail: "累计整理凭证 10 次", icon: "checklist", rarity: .rare, hidden: false),
        Badge(id: "week1", cat: .organize, title: "周目标星", detail: "达成一次每周整理目标", icon: "star.fill", rarity: .common, hidden: false),
        // 探索
        Badge(id: "days90", cat: .explore, title: "老友记", detail: "陪伴这个家 90 天", icon: "leaf.fill", rarity: .rare, hidden: false),
        Badge(id: "year1", cat: .explore, title: "一周年", detail: "陪伴这个家一整年", icon: "rosette", rarity: .epic, hidden: false),
        Badge(id: "bondann", cat: .explore, title: "结缘纪念", detail: "在结缘周年当天开一次锁", icon: "sparkles", rarity: .epic, hidden: true),
        // 包4: 1039 续航管家 / 1030 爱洁之家
        Badge(id: "batt2", cat: .butler, title: "续航管家", detail: "完成 2 次换电池", icon: "battery.100.bolt", rarity: .common, hidden: false),
        Badge(id: "clean3", cat: .butler, title: "爱洁之家", detail: "连续 3 个月完成锁体保养", icon: "checkmark.seal", rarity: .rare, hidden: false),
        // 995: 入伙与 owner 同判据 (归属即入伙完成), 语义入口不同
        Badge(id: "join1", cat: .organize, title: "入伙", detail: "新成员入伙并录下第一条归属凭证", icon: "person.badge.plus", rarity: .common, hidden: false),
    ]
    static func badge(_ id: String) -> Badge? { definitions.first { $0.id == id } }

    static func unlockedMap() -> [String: Double] {
        DB.store.get([String: Double].self, "kf_ach_done") ?? [:]
    }
    /// 点亮时刻 (毫秒 epoch → Date)。kf_ach_done 存的是 `Date().timeIntervalSince1970 * 1000` 的**毫秒**,
    /// 而 UI (BadgeTile/BadgeDetailSheet) 要的是 `Date?` —— 2026-10-13 run 57: 两处直接把
    /// `unlocked[b.id]` (Double?) 当 Date? 传, 报 "cannot convert value of type 'Double?' to expected
    /// argument type 'Date?'"。转换只此一处, 与 latestUnlocked 里的 ts/1000 同口径 (不再各写各的)。
    static func unlockedDate(_ id: String) -> Date? {
        guard let ts = unlockedMap()[id] else { return nil }
        return Date(timeIntervalSince1970: ts / 1000)
    }
    /// 988 陈列架: 最近点亮的 n 枚
    static func latestUnlocked(_ n: Int) -> [(badge: Badge, at: Date)] {
        unlockedMap()
            .compactMap { id, ts -> (Badge, Date)? in
                guard let b = badge(id) else { return nil }
                return (b, Date(timeIntervalSince1970: ts / 1000))
            }
            .sorted { $0.1 > $1.1 }
            .prefix(n)
            .map { (badge: $0.0, at: $0.1) }
    }
    /// 998 徽章周年回忆: 恰好满一年 (同一月日) 的徽章
    static func badgeAnniversaryToday() -> Badge? {
        return latestUnlocked(definitions.count).first {
            isSameMonthDay($0.at, Date()) &&
            WeekCal.gregorian.component(.year, from: $0.at) < WeekCal.gregorian.component(.year, from: Date())
        }?.badge
    }

    // ---------- 结算 ----------
    static func loadStats() -> MStats {
        var s = MStats()
        s.unlockTotal = unlockTotal
        s.streakBest = streak().best
        s.nightCount = nightMarks().count
        var owlMonths: [String: Int] = [:]
        // join1 用: 名下挂到了凭证的成员 id 集合 (逐锁台账里 owner 就是成员 id)
        var ownersWithCred = Set<String>()
        for kc in DB.keychains() {
            let pwds = DB.listPwds(kc.mac)
            let fps = DB.listFps(kc.mac)
            if pwds.contains(where: { !($0.owner ?? "").isEmpty }) || fps.contains(where: { !($0.owner ?? "").isEmpty }) {
                s.ownedCred = true
            }
            // 演示锁的凭证也带 owner (DemoKit 里那个 owner 字段), 但"新成员入伙"不该被一次演示点亮 ⇒ 这一格排除演示锁。
            // 注意 `ownedCred`(上面那枚"指归属"徽章) 没排除演示 —— 那是另一件事, 本轮不动它的口径。
            if kc.mac != DemoKit.demoMac {
                for o in pwds.compactMap(\.owner) + fps.compactMap(\.owner) where !o.isEmpty { ownersWithCred.insert(o) }
            }
            // lockTime == 0 = 锁端时钟没读到/无时钟型号的占位值, 换算后落在协议纪元 (2010-01-01 00:00),
            // 其"小时"必然 < 6 → 会凭空点亮夜猫子徽章并计入最差的月份桶。必须排除。
            for l in DB.readLogs(kc.mac) where Attribution.openKind[l.type] != nil && l.lockTime > 0 {
                let d = Date(timeIntervalSince1970: ZKProtocol.protoSecondsToUnix(l.lockTime))
                if WeekCal.gregorian.component(.hour, from: d) < 6 {
                    owlMonths[monthKey(d), default: 0] += 1
                }
            }
        }
        s.nightOwlBest = owlMonths.values.max() ?? 0
        // join1 的另一半: 那位 owner 得是**在本 App 里建过档**的成员。建档时刻字段其实早就有 ——
        // `DB.addMember` 写 `at` (毫秒), `Member(fromDict:)` 读回、缺字段的迁移旧账才是 0
        // (2026-10-15 走查: 上一批把这条挂成"等拍板要补数据面字段"，那个前提不成立，字段在，判据当场能写)。
        s.joinedWithCred = DB.members().contains { $0.at > 0 && ownersWithCred.contains($0.id) }
        s.backupStreak = backupStreakMonths
        s.backupThisMonth = backupThisMonth
        s.organizeTotal = organizeTotal
        s.weekStar = DB.store.getBool("kf_week_star")
        s.daysSinceFirst = daysSinceFirst
        s.bondAnnivDone = DB.store.getBool("kf_bond_anniv_done")
        // 包4/1039: 换电池事件计数 (kf_mevents_)
        for kc in DB.keychains() {
            s.batterySwaps += BatteryCare.events(kc.mac).filter { $0.kind == "battery" }.count
        }
        s.careStreak = BatteryCare.careStreakMonths   // 包4/1030
        return s
    }

    private static func satisfies(_ id: String, _ s: MStats) -> Bool {
        switch id {
        case "bond": return !DB.keychains().isEmpty
        case "streak3": return s.streakBest >= 3
        case "streak7": return s.streakBest >= 7
        case "night1": return s.nightCount >= 1
        case "night30": return s.nightCount >= 30
        case "backup3": return s.backupStreak >= 3
        case "un100": return s.unlockTotal >= 100
        case "un500": return s.unlockTotal >= 500
        case "un2000": return s.unlockTotal >= 2000
        case "owl": return s.nightOwlBest >= 5
        case "heart1000": return s.unlockTotal >= 1000
        case "owner": return s.ownedCred
        // 995 原句是两条: **新成员添加后生成欢迎卡**引导首录凭证，完成才点亮"入伙"。
        // 2026-10-15 走查(第一次记这条时): 判据与上面 "owner" 完全相同 (`ownedCred`) ⇒ 给一条旧凭证指归属，
        // 两枚徽章一起亮，而屏上写的是"新成员入伙并录下第一条归属凭证"。**没有把文案降到判据的高度**。
        // 同日续查: 当时写的卡点"真判据要成员建档时刻，那是数据面要补的字段"**是错的** ——
        // `Member.at` 已在 `DB.addMember` 里写、`fromDict` 读回（迁移旧账为 0），所以"新成员"这一半现在就能判，
        // 判据换成 `joinedWithCred`（本 App 建的档 + 名下真有归属凭证，且不含演示锁）。
        // ~~还剩 995 的前半截没做~~ ⇒ **2026-10-15 二次核实：前半截已落地** — 建成员成功后
        // `welcome = m` (Sheets.swift:2675) → `.sheet(item: $welcome)` 弹 `MemberWelcomeCard`
        // (Sheets.swift:2748, 三步指路 + 去凭证页动作)。此前的"归产品拍板"是过期口径, 划掉留痕。
        case "join1": return s.joinedWithCred
        case "tidy10": return s.organizeTotal >= 10
        case "week1": return s.weekStar
        case "days90": return s.daysSinceFirst >= 90
        case "year1": return s.daysSinceFirst >= 365
        case "bondann": return s.bondAnnivDone
        case "batt2": return s.batterySwaps >= 2
        case "clean3": return s.careStreak >= 3
        default: return false
        }
    }

    /// 结算新点亮徽章 (写 kf_ach_done, 返回增量供 UI 播庆祝/通知)
    static func evaluate() -> [Badge] {
        let s = loadStats()
        var done = unlockedMap()
        var fresh = [Badge]()
        for d in definitions where done[d.id] == nil && satisfies(d.id, s) {
            done[d.id] = Date().timeIntervalSince1970 * 1000
            fresh.append(d)
        }
        if !fresh.isEmpty { DB.store.setCodable("kf_ach_done", done) }
        return fresh
    }

    // ---------- 996 收集音效 (系统短音, 零资源) ----------
    static func playCollectSound() {
        // 996/848: 音色与开锁成功短音同源, 调用点收敛到 App/Core/AlertTone.swift (全 App 只那一处裸调)
        AlertTone.achievement()
    }

    // ---------- 986 成就本地通知 ----------
    static func notifyAchievement(_ b: Badge) async {
        let c = UNMutableNotificationContent()
        c.title = "徽章点亮"
        c.body = "\(b.title) — \(b.detail)"
        c.sound = .default
        let req = UNNotificationRequest(identifier: "m18.ach." + b.id, content: c, trigger: nil)
        try? await UNUserNotificationCenter.current().add(req)
    }

    // ---------- 1042 季度速览 ----------
    struct QuarterSummary {
        var unlocks = 0
        var topMember = ""
        var newCreds = 0
    }
    static func quarterSummary() -> QuarterSummary {
        var out = QuarterSummary()
        let cal = WeekCal.gregorian
        let q = cal.component(.quarter, from: Date())
        let y = cal.component(.year, from: Date())
        var whoCount: [String: Int] = [:]
        for kc in DB.keychains() {
            let pwds = DB.listPwds(kc.mac)
            let fps = DB.listFps(kc.mac)
            out.newCreds += pwds.filter {
                cal.component(.quarter, from: Date(timeIntervalSince1970: $0.at / 1000)) == q &&
                cal.component(.year, from: Date(timeIntervalSince1970: $0.at / 1000)) == y
            }.count
            out.newCreds += fps.filter {
                cal.component(.quarter, from: Date(timeIntervalSince1970: $0.at / 1000)) == q &&
                cal.component(.year, from: Date(timeIntervalSince1970: $0.at / 1000)) == y
            }.count
            let rows = Attribution.classify(
                logs: DB.readLogs(kc.mac).map {
                    LogEntry(type: $0.type, typeName: $0.typeName, idx: $0.idxRaw, idxRaw: $0.idxRaw,
                             lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr, body: "")
                },
                pwds: pwds, fps: fps, status: nil)
            for (i, l) in DB.readLogs(kc.mac).enumerated() {
                guard i < rows.count else { continue }
                let d = Date(timeIntervalSince1970: ZKProtocol.protoSecondsToUnix(l.lockTime))
                guard cal.component(.quarter, from: d) == q,
                      cal.component(.year, from: d) == y else { continue }
                if let who = rows[i].who {
                    whoCount[who, default: 0] += 1
                    out.unlocks += 1
                }
            }
        }
        if let top = whoCount.max(by: { $0.value < $1.value }), let m = DB.member(top.key) {
            out.topMember = m.name
        }
        return out
    }
}

// ================= 关怀提醒 (本地通知; 免费账号不推送, 全部 UNUserNotificationCenter) =================
enum CareReminders {
    static var bdayOn: Bool { DB.store.getBool("kf_care_bday") }
    static var annivOn: Bool { DB.store.getBool("kf_care_anniv") }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// 重建全部关怀通知 (生日提前一天 9 点 / 结缘纪念日当天 9 点, 年重复)
    static func reschedule() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers:
            (Milestones.memberBirthdays().keys.map { "care.bday." + $0 }) + ["care.anniv"])
        guard await requestAuthorization() else { return }
        let cal = WeekCal.gregorian
        if bdayOn {
            for (mid, md) in Milestones.memberBirthdays() {
                let parts = md.split(separator: "-").compactMap { Int($0) }
                // parts 元素是 Int (compactMap 后非可选), 不能条件绑定 → 先判数量再下标取值
                guard parts.count == 2, parts[0] >= 1, parts[0] <= 12, parts[1] >= 1, parts[1] <= 31,
                      let member = DB.member(mid) else { continue }
                let m = parts[0], d = parts[1]
                // 提前一天: 由日期减一天再取月日, 跨月 (3/1 → 2/28) 也正确
                guard var fire = cal.date(from: DateComponents(year: cal.component(.year, from: Date()), month: m, day: d)) else { continue }
                fire = cal.date(byAdding: .day, value: -1, to: fire) ?? fire
                var comp = cal.dateComponents([.month, .day], from: fire)
                comp.hour = 9
                let c = UNMutableNotificationContent()
                c.title = "生日提醒"
                c.body = "明天是\(member.name)的生日, 记得说一声。"
                c.sound = .default
                let req = UNNotificationRequest(identifier: "care.bday." + mid, content: c,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: comp, repeats: true))
                try? await center.add(req)
            }
        }
        if annivOn {
            let b = Milestones.bondDay
            let parts = b.split(separator: "-").compactMap { Int($0) }
            if parts.count == 3 {
                var comp = DateComponents(month: parts[1], day: parts[2])
                comp.hour = 9
                let c = UNMutableNotificationContent()
                c.title = "结缘纪念日"
                c.body = "这是你与这扇门结缘的日子。这一年, 谢谢你一直在。"
                c.sound = .default
                let req = UNNotificationRequest(identifier: "care.anniv", content: c,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: comp, repeats: true))
                try? await center.add(req)
            }
        }
    }
}
