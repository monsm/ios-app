// ================= 游戏化·情感化·纪念 (功能包18) — 统计与成就引擎 =================
// 纯数据层, 不含 UI。数据源 = 既有本地台账 (kf_logcache_ / kf_ledger_ / kf_keychains / kf_members)
// + 本文件新增的包18 kf_* 键。全离线, 不依赖网络与推送 (提醒一律 UNUserNotificationCenter 本地通知)。
// 性能 (ROADMAP 包18 第5条): 一次结算 O(日志≤300/锁), UI 只读结果, 统计逻辑全部收在这里。
import Foundation
import UIKit
import UserNotifications
import AudioToolbox

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
    var daysSinceFirst = 0
    var bondAnnivDone = false
    var batterySwaps = 0   // 包4/1039
    var careStreak = 0     // 包4/1030
}

enum Milestones {
    // ---------- 日期工具 ----------
    static func dayKey(_ d: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }
    static func monthKey(_ d: Date = Date()) -> String {
        String(dayKey(d).prefix(7))
    }
    static func mdKey(_ d: Date = Date()) -> String {   // "MM-dd"
        String(dayKey(d).suffix(5))
    }
    static func isSameMonthDay(_ a: Date, _ b: Date) -> Bool { mdKey(a) == mdKey(b) }

    // ---------- 一次性标记 / 偏好 ----------
    static func onceDone(_ k: String) -> Bool {
        var m = DB.store.get([String: Bool].self, "kf_once") ?? [:]
        return m[k] == true
    }
    static func markOnce(_ k: String) {
        var m = DB.store.get([String: Bool].self, "kf_once") ?? [:]
        m[k] = true
        DB.store.setCodable("kf_once", m)
    }
    /// 1046 素颜模式: 一键关闭全部庆祝动效 (时刻卡保留内容, 不播粒子)
    static var plainMode: Bool { DB.store.getBool("kf_plain") }
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
        let yest = dayKey(Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        let cur = (lastDay == yest) ? (s["cur"] ?? 0) + 1 : 1
        s["cur"] = cur
        s["best"] = max(s["best"] ?? 0, cur)
        DB.store.setCodable("kf_streak", s)
        DB.store.set("kf_streak_last", today)
    }

    // ---------- 976 安心夜打卡 + 985 衑签 ----------
    /// 22 点后可打卡 (纯手动确认 — 协议无上锁状态位, 不猜测)
    static var canNightCheckIn: Bool { Calendar.current.component(.hour, from: Date()) >= 22 }
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
        let cal = Calendar.current
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
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // ---------- 980/997 备份历史 (上传成功 / 生成本地备份文本 各记一次) ----------
    static func recordBackup() {
        var h = DB.store.get([Double].self, "kf_backup_hist") ?? []
        h.append(Date().timeIntervalSince1970 * 1000)
        if h.count > 60 { h.removeFirst(h.count - 60) }
        DB.store.setCodable("kf_backup_hist", h)
    }
    static var backupThisMonth: Int {
        let mk = monthKey()
        return (DB.store.get([Double].self, "kf_backup_hist") ?? [])
            .filter { monthKey(Date(timeIntervalSince1970: $0 / 1000)) == mk }.count
    }
    /// 980 连续月数 (从本月起; 本月还没备则从上月起)
    static var backupStreakMonths: Int {
        let months = Set((DB.store.get([Double].self, "kf_backup_hist") ?? [])
            .map { monthKey(Date(timeIntervalSince1970: $0 / 1000)) })
        let cal = Calendar.current
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
    /// 本周整理次数 (周一为一周起点)
    static var weekDone: Int {
        let stamps = DB.store.get([Double].self, "kf_organize_log") ?? []
        let cal = Calendar.current
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
        let cal = Calendar.current
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
    static func companionText(_ atMs: Double, prefix: String = "已陪伴") -> String? {
        guard atMs > 0 else { return nil }
        let days = Int(Date().timeIntervalSince1970 * 1000 - atMs) / 86_400_000
        guard days >= 0 else { return nil }
        return days >= 365 ? "\(prefix) \(days) 天 · 满一年了" : "\(prefix) \(days) 天"
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
        let cal = Calendar.current
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
    ]
    static func badge(_ id: String) -> Badge? { definitions.first { $0.id == id } }

    static func unlockedMap() -> [String: Double] {
        DB.store.get([String: Double].self, "kf_ach_done") ?? [:]
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
        let md = mdKey()
        return latestUnlocked(definitions.count).first {
            isSameMonthDay($0.at, Date()) &&
            Calendar.current.component(.year, from: $0.at) < Calendar.current.component(.year, from: Date())
        }?.badge
    }

    // ---------- 结算 ----------
    static func loadStats() -> MStats {
        var s = MStats()
        s.unlockTotal = unlockTotal
        s.streakBest = streak().best
        s.nightCount = nightMarks().count
        var owlMonths: [String: Int] = [:]
        for kc in DB.keychains() {
            let pwds = DB.listPwds(kc.mac)
            let fps = DB.listFps(kc.mac)
            if pwds.contains(where: { !($0.owner ?? "").isEmpty }) || fps.contains(where: { !($0.owner ?? "").isEmpty }) {
                s.ownedCred = true
            }
            for l in DB.readLogs(kc.mac) where Attribution.openKind[l.type] != nil {
                let d = Date(timeIntervalSince1970: Double(ZKProtocol.protoSecondsToMs(l.lockTime)) / 1000)
                if Calendar.current.component(.hour, from: d) < 6 {
                    owlMonths[monthKey(d), default: 0] += 1
                }
            }
        }
        s.nightOwlBest = owlMonths.values.max() ?? 0
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
        AudioServicesPlaySystemSound(1104)
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
        let cal = Calendar.current
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
                let d = Date(timeIntervalSince1970: Double(ZKProtocol.protoSecondsToMs(l.lockTime)) / 1000)
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
        let cal = Calendar.current
        if bdayOn {
            for (mid, md) in Milestones.memberBirthdays() {
                let parts = md.split(separator: "-").compactMap { Int($0) }
                guard parts.count == 2, let m = parts[0], m >= 1, m <= 12, let d = parts[1], d >= 1, d <= 31,
                      let member = DB.member(mid) else { continue }
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
