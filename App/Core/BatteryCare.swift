// 包4 电量·维护·固件关怀 — 本地采样与关怀提醒引擎 (纯数据层, 无 UI)
// 数据地基: kf_batt_<mac> 电量采样表 (idea 45 ⚠ 的趋势数据源: 每次读 03 追加点, 90 天截断)。
// 其余键: kf_mevents_<mac> 维护事件 (1014/1028) · kf_maint_<mac> 保养状态 (1012/1013/1025)
//         kf_fwlib 固件包清单 (513/145) · kf_dfu_hist 升级历史 (147) · kf_fwsince_<mac> 固件服役起点 (1019)
//         kf_care_marks 保养月历打点 (1030) · kf_batt_state_<mac> 低电通知武装位 (1004 滞回)
// 协议约束 (CAPABILITY §2/§6): 电量仅百分比、无电压无充电位 — 只做本地采样, 不虚构电压/充电态/续航估算。
// 通知全部本地通知 (UNUserNotificationCenter); 夜间免扰 (1031) 与白天送达 (1038) 在此统一裁决。
import Foundation
import UserNotifications

struct BattSample: Codable {
    var t: Double   // Unix 毫秒
    var pct: Int
}

/// 维护事件 (1014: 记录页"更换电池/保养完成"事件; 1028: 记录页专属过滤)
struct MaintEvent: Codable {
    var ts: Double      // Unix 毫秒
    var kind: String    // "care" | "battery"
    var note: String
}

/// 保养状态 (per-lock, kf_maint_<mac>)
/// 自定义 decodeIfPresent: 与 Keychain 同理 — 后续加字段不能让旧 JSON 解码失败而静默清档
struct CareState: Codable {
    var lastCareAt: Double = 0      // 1013 90 天周期起点 (Unix 毫秒)
    var yearlyBattDay: String = ""  // 1012 每年换电池提醒 "MM-dd" (空 = 未设)
    var ekeyCheckAt: Double = 0     // 1025 应急钥匙半年检上次打卡
    var ekeyRemindOn: Bool = false
    var chargeAt: Double = 0        // 1034 充电记录 (可充电型号): 上次充电日期 (Unix 毫秒)
    var chargeLenMin: Int = 0       // 1034: 充电时长 (分钟; 0 = 未记)

    private enum CodingKeys: String, CodingKey {
        case lastCareAt, yearlyBattDay, ekeyCheckAt, ekeyRemindOn, chargeAt, chargeLenMin
    }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastCareAt = try c.decodeIfPresent(Double.self, forKey: .lastCareAt) ?? 0
        yearlyBattDay = try c.decodeIfPresent(String.self, forKey: .yearlyBattDay) ?? ""
        ekeyCheckAt = try c.decodeIfPresent(Double.self, forKey: .ekeyCheckAt) ?? 0
        ekeyRemindOn = try c.decodeIfPresent(Bool.self, forKey: .ekeyRemindOn) ?? false
        chargeAt = try c.decodeIfPresent(Double.self, forKey: .chargeAt) ?? 0
        chargeLenMin = try c.decodeIfPresent(Int.self, forKey: .chargeLenMin) ?? 0
    }
}

/// 513/145 固件本地清单条目 (只记出处元数据, 不落包体 — zip 最大 8MB 不进 UserDefaults)
struct FWLibItem: Codable, Identifiable {
    var name: String
    var version: String
    var size: Int
    var at: Double
    var id: Double { at }
}

/// 147 升级历史
struct DFURecord: Codable, Identifiable {
    var mac: String
    var name: String
    var from: String
    var to: String
    var at: Double
    var ok: Bool
    var ms: Double?          // 147 本次升级耗时 (毫秒, 连接+传输+校验); 可选型 = 旧记录没有该键也照样能解出来
    var id: Double { at }
}

enum BatteryCare {
    // ============ 122/113 五档电量 (满/高/中/低/空) ============
    // 122 原句要"电压毫伏精确值"，协议只给百分比 (CAPABILITY §2) —— 按拍板走替代口径:
    // 这一档表就是"档位映射说明"的数据源，界面上展示原值 + 映射，**不标毫伏**，不虚构精度。
    struct Tier {
        let icon: String
        let tone: ToneColor
        let label: String
        let severe: Bool   // 120 低电视觉降级档 (≤20%): 关流光、压亮度、动效令牌降 calm
    }
    static func tier(_ pct: Int) -> Tier {
        switch pct {
        case ..<0:     return Tier(icon: "battery.0percent", tone: .neutral, label: "未知", severe: false)
        case 0...10:   return Tier(icon: "battery.0percent", tone: .danger, label: "空", severe: true)
        case 11...20:  return Tier(icon: "battery.25percent", tone: .warn, label: "低", severe: true)   // 120: 低于两成即降级
        case 21...35:  return Tier(icon: "battery.25percent", tone: .warn, label: "低", severe: false)
        case 36...60:  return Tier(icon: "battery.50percent", tone: .accent, label: "中", severe: false)
        case 61...80:  return Tier(icon: "battery.75percent", tone: .ok, label: "高", severe: false)
        default:       return Tier(icon: "battery.100percent", tone: .ok, label: "满", severe: false)
        }
    }
    /// 1004 喂电提醒判定 (≤20%; 与 287 的可调横幅阈值互相独立)
    static func isLow(_ pct: Int) -> Bool { (0...20).contains(pct) }

    // ---------- 120 全 App 低电分支 ----------
    /// 最近一次读到的电量 (当前锁) 内存缓存: 动效令牌 (DesignSystem.Motion) 每次求值都问这里,
    /// 不能每次都解快照 JSON。sample() 每次读 03 后喂新值; 冷启动首问回源一次统一读数。
    private static let lowCacheLock = Locked((mac: "", low: false))
    /// 120: 当前锁电量 ≤20% (= 低于两成) 时为 true —— 设计令牌据此把全 App 动效压到 calm。
    /// 读法: kf_current_mac (当前锁, 与 Store.preferredMac 同一解析) → 统一展示读数 (displayPct 采样+快照取新)。
    /// 不走 kf_last_device: 它存的是 BLE 外设 id (LockService.connect 写入), 拿它查 kf_batt_/kf_snap_
    /// 永远查不到 (低电分支恒 false 的死路, 2026-10-11 审计实弹)。
    /// 无锁 / 无读数 / 未知(-1) → false: 判不出就不降级, 不瞎猜。
    static var appLowBattery: Bool {
        let mac = DB.preferredMac()
        guard !mac.isEmpty else { return false }
        if let c = lowCacheLock.withLock({ $0 }), c.mac == mac { return c.low }
        let pct = displayPct(mac, snapshot: DB.readStatus(mac)?.powerLevel ?? -1)
        guard pct >= 0 else { return false }
        let low = isLow(pct)
        lowCacheLock.withLock { $0 = (mac, low) }
        return low
    }
    /// 121 低温季提示窗口: 11 月–3 月 (纯本地日期规则)
    static var isColdSeason: Bool {
        let m = WeekCal.gregorian.component(.month, from: Date())
        return m == 11 || m == 12 || m <= 3
    }

    /// 1026 本地气候表: 城市关键词 → 粗粒度寒季窗口 (from > to 即跨年)。表外回退上方 11–3 月默认档。
    /// 按原句口径"城市手动填、本地气候表" —— 固定粗档只调提醒时机与文案, 不做气象预报 (无网络)。
    static let coldCityTable: [(keys: [String], label: String, from: Int, to: Int)] = [
        (["哈尔滨", "长春", "沈阳", "乌鲁木齐", "呼和浩特"], "严寒地区寒季 10–4 月", 10, 4),
        (["北京", "天津", "石家庄", "太原", "济南", "郑州", "西安", "青岛"], "北方寒季 11–3 月", 11, 3),
        (["上海", "南京", "杭州", "合肥", "武汉", "长沙", "重庆", "成都"], "长江流域冷月 12–2 月", 12, 2),
        (["广州", "深圳", "南宁", "福州", "厦门", "海口", "三亚"], "华南低纬 — 仅 1 月提一句", 1, 1),
    ]
    static func cityColdWindow(_ city: String) -> (label: String, from: Int, to: Int)? {
        guard !city.isEmpty else { return nil }
        for row in coldCityTable where row.keys.contains(where: { city.contains($0) }) {
            return (row.label, row.from, row.to)
        }
        return nil
    }
    static func inColdMonth(_ m: Int, from: Int, to: Int) -> Bool {
        from <= to ? (m >= from && m <= to) : (m >= from || m <= to)
    }

    // ============ 电量采样 (idea 45 的数据地基) ============
    static func samples(_ mac: String) -> [BattSample] {
        DB.store.get([BattSample].self, "kf_batt_" + mac) ?? []
    }
    static func latest(_ mac: String) -> BattSample? { samples(mac).last }

    /// 统一展示读数 (ROADMAP 包4): Hero 卡/总览条带/档案页共用一个来源 —
    /// 采样表最新值与锁侧快照取时间较新的那个 (采样随读 03 落库, 通常不比快照旧);
    /// 都缺则 -1 未知。调用方另有采样时间标注 (291), 陈旧值由标注兜底, 不在此处猜。
    /// ⚠ 2026-10-15 走查: 这里原先叠着**第二段**旧说明 ("采样最新值优先, 90 天内且非陈旧才信 / 陈旧上限 7 天"),
    /// 而下面的代码既没有 90 天也没有 7 天闸门 —— 它只比"谁更新"。留着那段就是在指一条不存在的规则, 删掉。
    static func displayPct(_ mac: String, snapshot: Int = -1) -> Int {
        let snapAt = DB.get(StatusSnapshot.self, "kf_snap_" + mac)?.at ?? 0
        guard let s = latest(mac), s.pct >= 0 else { return snapshot }
        if snapshot < 0 { return s.pct }      // 快照未知 → 采样是唯一证据 (调用方另有时间标注)
        return s.t >= snapAt ? s.pct : snapshot // 快照已知 → 谁更新用谁
    }

    /// 界面上的那一格电量: 会话实时读数优先, 无则走 displayPct 的采样/快照口径。
    /// `live` 传 -1 表示"这次没有实时读数" —— 只有正在连着的那把锁才有实时读数, 别的锁必须传 -1,
    /// 否则 A 锁的电量会被安到 B 锁头上 (设备页那侧的同名判据)。
    static func facePct(_ mac: String, live: Int = -1) -> Int {
        live >= 0 ? live : displayPct(mac, snapshot: DB.readStatus(mac)?.powerLevel ?? -1)
    }
    /// 电量的界面写法 (<0 未读到 → "--"; >80 只报 ">80%", 锁侧这个量本身就是粗估档)。
    static func faceText(_ p: Int) -> String {
        if p < 0 { return "--" }
        return p > 80 ? ">80%" : "\(p)%"
    }

    /// 每次读 03 成功后调用 (LockService.getStatus 埋点)。
    /// 追加策略: 电量变化必记; 未变化时距上点 ≥1h 记一次 — 日粒度足够趋势拟合且量小。
    /// 截断: 保留 90 天 + 500 条封顶。
    @discardableResult
    static func sample(_ mac: String, pct: Int) -> Bool {
        guard !mac.isEmpty, pct >= 0 else { return false }
        lowCacheLock.withLock { $0 = (mac, isLow(pct)) }   // 120: 无论是否落点都刷新低电缓存
        var list = samples(mac)
        let now = Date().timeIntervalSince1970 * 1000
        if let last = list.last, last.pct == pct, now - last.t < 3_600_000 { return false }
        list.append(BattSample(t: now, pct: pct))
        let cutoff = now - 90 * 86400 * 1000
        list.removeAll { $0.t < cutoff }
        if list.count > 500 { list = Array(list.suffix(500)) }
        DB.store.setCodable("kf_batt_" + mac, list)
        evaluateLowBattery(mac, pct: pct)
        return true
    }

    /// 1040 单日掉电观察: 采样表里同一个**本地日**内, 最早与最晚两个采样点的电量差 > threshold。
    /// 只用真实量到的两个点相减 —— 不拟合、不外推 (与 1029/1032 同一纪律: 本仓不虚构电压/续航)。
    /// 采样表本身是"读 03 时落点"(BatteryCare.sample), 所以这条只对"当天至少读到过两次"的日子成立。
    static func bigDropDays(_ mac: String, days: Int = 30, threshold: Int = 20)
        -> [(day: String, from: Int, to: Int, drop: Int)] {
        let list = samples(mac)
        guard list.count >= 2 else { return [] }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        let since = Date().addingTimeInterval(-Double(days) * 86400)
        var firstOfDay: [String: BattSample] = [:]
        var lastOfDay: [String: BattSample] = [:]
        for s in list {
            let d = Date(timeIntervalSince1970: s.t / 1000)
            guard d >= since else { continue }
            let key = fmt.string(from: d)
            if let f = firstOfDay[key] { if s.t < f.t { firstOfDay[key] = s } } else { firstOfDay[key] = s }
            if let l = lastOfDay[key] { if s.t > l.t { lastOfDay[key] = s } } else { lastOfDay[key] = s }
        }
        var out: [(day: String, from: Int, to: Int, drop: Int)] = []
        for (key, f) in firstOfDay {
            guard let l = lastOfDay[key] else { continue }
            let drop = f.pct - l.pct
            if drop > threshold { out.append((key, f.pct, l.pct, drop)) }
        }
        return out.sorted { $0.day > $1.day }
    }

    // ---------- 1004 低电本地通知 (滞回: ≤20% 提醒 / ≤10% 升级, 恢复 >30% 重新武装) ----------
    private static func evaluateLowBattery(_ mac: String, pct: Int) {
        let key = "kf_batt_state_" + mac
        if pct > 30 {
            if DB.store.getInt(key) != 0 { DB.store.set(key, 0) }
            return
        }
        guard pct <= 20 else { return }
        let level = pct <= 10 ? 2 : 1
        guard DB.store.getInt(key) < level else { return }
        // 先记账再发送: 发送被免扰静默也不反复轰炸
        DB.store.set(key, level)
        // 733 低电单音: 告警**到达**这一刻响 (两档滞回各响一次, 与通知同一时机), 总开关默认关
        AlertTone.alert(.lowBattery)
        let name = DB.keychain(mac).map { LockArchive.displayName($0) } ?? mac
        let body = level == 2
            ? "「\(name)」只剩 \(pct)%, 请尽快更换电池"
            : "「\(name)」电量 \(pct)%, 建议备好电池择日更换"
        Task { await CareSchedule.notifyNow(id: "m4.batt." + mac,
                                            title: level == 2 ? "电量告急" : "该喂电了",
                                            body: body) }
    }

    /// 118 换电复位: 强制落一个基线采样点 + 重置低电通知武装位 + 写入 1014 事件。
    /// 采样表不清空 — 换电后电量跳升本身就是有效样本; 电池档案 (batteryChangedAt) 由调用方写。
    static func recordBatterySwap(_ mac: String) {
        guard !mac.isEmpty else { return }
        var list = samples(mac)
        let now = Date().timeIntervalSince1970 * 1000
        if let pct = DB.readStatus(mac)?.powerLevel, pct >= 0 {
            lowCacheLock.withLock { $0 = (mac, isLow(pct)) }   // 120: 换电后电量跳变, 缓存立刻跟上
            list.append(BattSample(t: now, pct: pct))
            let cutoff = now - 90 * 86400 * 1000
            list.removeAll { $0.t < cutoff }
            if list.count > 500 { list = Array(list.suffix(500)) }
            DB.store.setCodable("kf_batt_" + mac, list)
        }
        DB.store.set("kf_batt_state_" + mac, 0)
        addEvent(mac, kind: "battery", note: "更换电池")
    }

    // ============ 维护事件 (1014/1028) ============
    static func events(_ mac: String) -> [MaintEvent] {
        DB.store.get([MaintEvent].self, "kf_mevents_" + mac) ?? []
    }
    static func addEvent(_ mac: String, kind: String, note: String) {
        guard !mac.isEmpty else { return }
        var l = events(mac)
        l.insert(MaintEvent(ts: Date().timeIntervalSince1970 * 1000, kind: kind, note: note), at: 0)
        if l.count > 100 { l = Array(l.prefix(100)) }
        DB.store.setCodable("kf_mevents_" + mac, l)
    }

    // ============ 保养状态 (1012/1013/1025) ============
    /// 1022 保养周期档: 近 30 天开门 ≥60 次的锁算高频, 周期从 90 天缩到 60 天。
    /// 这条判据此前有**三份** —— 通知侧 (本文件)、保养清单页的 `periodDays`、以及"保养已记录"那句
    /// toast; 第三份把 90 写死在字面量里, 于是高频锁按屏幕说的等 90 天, 实际 60 天就被催。收成一处。
    static func carePeriodDays(opens30d: Int) -> Int { opens30d >= 60 ? 60 : 90 }
    /// 按 mac 取那一档 (usage 那份读法留在主线程侧, 与通知侧那条 await 同一口径)
    @MainActor static func carePeriodDays(mac: String) -> Int {
        carePeriodDays(opens30d: LockStats.usage().first(where: { $0.mac == mac })?.opens30d ?? 0)
    }
    static func care(_ mac: String) -> CareState {
        DB.store.get(CareState.self, "kf_maint_" + mac) ?? CareState()
    }
    static func saveCare(_ mac: String, _ s: CareState) {
        DB.store.setCodable("kf_maint_" + mac, s)
    }

    // ---------- 1030 清洁月历打点 + 连续月数 ----------
    static func careMarks() -> [String: Bool] {
        DB.store.get([String: Bool].self, "kf_care_marks") ?? [:]
    }
    static func markCareToday() {
        var m = careMarks()
        m[Milestones.dayKey()] = true
        DB.store.setCodable("kf_care_marks", m)
    }
    /// 连续有保养的月数 (从本月起, 本月没打则从上月起 — 与 backupStreakMonths 同语义)
    static var careStreakMonths: Int {
        let months = Set(careMarks().keys.map { String($0.prefix(7)) })
        let cal = WeekCal.gregorian
        var cursor = Date()
        if !months.contains(Milestones.monthKey(cursor)) {
            guard let prev = cal.date(byAdding: .month, value: -1, to: cursor) else { return 0 }
            cursor = prev
        }
        var n = 0
        while months.contains(Milestones.monthKey(cursor)), n < 36 {
            n += 1
            guard let prev = cal.date(byAdding: .month, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return n
    }

    // ============ 1019 固件服役天数 (诚实口径: 从本机首次读到该版本起算, 不猜锁端出厂时间) ============
    struct FwSince: Codable { var fw: String; var at: Double }
    static func fwSince(_ mac: String, fw: String) -> FwSince? {
        guard !mac.isEmpty, !fw.isEmpty else { return nil }
        if let s = DB.store.get(FwSince.self, "kf_fwsince_" + mac), s.fw == fw { return s }
        let s = FwSince(fw: fw, at: Date().timeIntervalSince1970 * 1000)
        DB.store.setCodable("kf_fwsince_" + mac, s)
        return s
    }

    // ============ 513/145 固件本地清单 · 147 升级历史 ============
    static var fwlib: [FWLibItem] { DB.store.get([FWLibItem].self, "kf_fwlib") ?? [] }
    static func addFWLib(name: String, version: String?, size: Int) {
        var l = fwlib
        guard !l.contains(where: { $0.name == name }) else { return }
        l.insert(FWLibItem(name: name, version: version ?? "未知", size: size,
                           at: Date().timeIntervalSince1970 * 1000), at: 0)
        if l.count > 20 { l = Array(l.prefix(20)) }
        DB.store.setCodable("kf_fwlib", l)
    }
    static var dfuHist: [DFURecord] { DB.store.get([DFURecord].self, "kf_dfu_hist") ?? [] }
    static func addDFURecord(_ r: DFURecord) {
        var l = dfuHist
        l.insert(r, at: 0)
        if l.count > 20 { l = Array(l.prefix(20)) }
        DB.store.setCodable("kf_dfu_hist", l)
    }

    // ============ 1023 指纹头清洁: 锁日志最近 3 条连续为指纹告警 (type 13) ============
    static func fpCleanNeeded(_ mac: String) -> Bool {
        // 1023: 缓存数组序≠时间序 (新抓的拼在旧缓存前), 先按锁端时间戳降序再取前 3
        let logs = DB.readLogs(mac).sorted { $0.lockTime > $1.lockTime }.prefix(3)
        guard logs.count == 3 else { return false }
        return logs.allSatisfy { $0.type == 13 }
    }
}

// ================= 包4 关怀提醒调度 (本地通知; 1031 夜间免扰 / 1038 白天送达) =================
enum CareSchedule {
    /// 1031 夜间免扰 (默认开): 免扰时段不发即时通知, 首页横幅仍在
    static var quietOn: Bool { DB.store.getBool("kf_quiet_night", true) }
    /// 287 低电横幅阈值 (默认 15%, 可选 10/15/20)
    static var battThreshold: Int {
        let v = DB.store.getInt("kf_batt_threshold", 15)
        return [10, 15, 20].contains(v) ? v : 15
    }
    /// 146 下次打开 App 提醒升级 (默认开, 只对照本地固件清单)
    static var fwRemindOn: Bool { DB.store.getBool("kf_fw_remind", true) }

    static func isQuietHour(_ d: Date = Date()) -> Bool {
        let h = WeekCal.gregorian.component(.hour, from: d)
        return h >= 22 || h < 8
    }

    /// 即时本地通知 (1004/1023/校时/146/1013 到期/1024 防潮): 免扰时段静默丢弃 (1031)
    /// dayDeliver=true 的升级提醒 (1038): 夜间不丢, 挂到下一个 08:00 白天送达
    static func notifyNow(id: String, title: String, body: String, dayDeliver: Bool = false) async {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        if quietOn && isQuietHour() {
            guard dayDeliver else { return }
            let cal = WeekCal.gregorian
            var target = cal.startOfDay(for: Date())
            if cal.component(.hour, from: Date()) >= 22 {
                target = cal.date(byAdding: .day, value: 1, to: target) ?? target
            }
            target = cal.date(byAdding: .hour, value: 8, to: target) ?? target
            let comp = cal.dateComponents([.year, .month, .day, .hour, .minute], from: target)
            try? await UNUserNotificationCenter.current()
                .add(UNNotificationRequest(identifier: id, content: c,
                                           trigger: UNCalendarNotificationTrigger(dateMatching: comp, repeats: false)))
            return
        }
        try? await UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }

    static func requestAuth() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// 启动巡检 (app.onLaunch 调用): 1013 保养到期 / 1023 指纹头 / 校时 30 天 / 1024 防潮 / 146 固件
    static func refreshOnLaunch() async {
        guard !DB.keychains().isEmpty else { return }
        guard await requestAuth() else { return }
        let now = Date().timeIntervalSince1970 * 1000
        // 1022: 到期判据走 carePeriodDays(opens30d:) 那一处 (本文件上方), 通知侧不再自己算 60/90
        let usage30 = await MainActor.run { LockStats.usage() }
        for kc in DB.keychains() {
            let name = LockArchive.displayName(kc)
            // 1013 保养到期: 满周期起每天最多一条, 完成保养即停
            let s = BatteryCare.care(kc.mac)
            let opens30d = usage30.first(where: { $0.mac == kc.mac })?.opens30d ?? 0
            let carePeriod = BatteryCare.carePeriodDays(opens30d: opens30d)
            if s.lastCareAt > 0, now - s.lastCareAt >= Double(carePeriod) * 86400 * 1000,
               DB.store.getString("kf_care_notify_" + kc.mac) != Milestones.dayKey() {
                DB.store.set("kf_care_notify_" + kc.mac, Milestones.dayKey())
                await notifyNow(id: "m4.care." + kc.mac, title: "保养到期",
                                body: "「\(name)」距上次保养已满 \(carePeriod) 天, 找个方便的时间清洁锁体吧。")
            }
            // 1024 潮湿位: 场所含湿区关键词 ∧ 6–7 月梅雨 → 每 7 天一条
            let place = LockArchive.meta(kc.mac).place
            let damp = ["浴室", "户外", "院", "阳台", "天台"].contains { place.contains($0) }
            let month = WeekCal.gregorian.component(.month, from: Date())
            if damp, month == 6 || month == 7 {
                let last = DB.store.get(Double.self, "kf_damp_last_" + kc.mac) ?? 0
                if now - last > 7 * 86400 * 1000 {
                    DB.store.set("kf_damp_last_" + kc.mac, now)
                    await notifyNow(id: "m4.damp." + kc.mac, title: "防潮提醒",
                                    body: "梅雨季湿气重, 「\(name)」装在湿区, 记得检查电池触点与锁体。")
                }
            }
            // 校时关怀: 超 30 天未校时, 30 天内只提醒一次 (ZOTP 与时间窗凭证依赖锁钟)
            let t = DB.syncTime(kc.mac)
            if t > 0, now - t > 30 * 86400 * 1000 {
                let lastN = DB.store.get(Double.self, "kf_clock_notify_" + kc.mac) ?? 0
                if now - lastN > 30 * 86400 * 1000 {
                    DB.store.set("kf_clock_notify_" + kc.mac, now)
                    await notifyNow(id: "m4.clock." + kc.mac, title: "该校时了",
                                    body: "「\(name)」已超 30 天未校时, 临时密码可能失效。")
                }
            }
            // 1023 指纹头清洁: 连续 3 次指纹告警, 7 天一条
            if BatteryCare.fpCleanNeeded(kc.mac) {
                let last = DB.store.get(Double.self, "kf_fp_last_" + kc.mac) ?? 0
                if now - last > 7 * 86400 * 1000 {
                    DB.store.set("kf_fp_last_" + kc.mac, now)
                    await notifyNow(id: "m4.fp." + kc.mac, title: "擦擦指纹头",
                                    body: "「\(name)」连续 3 次指纹识别告警 — 指纹头可能脏了或手指太干。")
                }
            }
        }
        // 146 固件提醒: 本地固件清单里有比锁内更新的版本。1038: 夜间不丢 → 挂白天 08:00;
        // 置位不再"只此一次"— 未升级期间每 30 天复提醒 (与校时 30 天同节奏)
        if fwRemindOn {
            for kc in DB.keychains() where !kc.fw.isEmpty {
                for item in BatteryCare.fwlib {
                    guard let v = _FWVersion(item.version), _FWVersion(kc.fw) != nil,
                          FirmwareKit.versionLt(kc.fw, item.version) else { continue }
                    let lastN = DB.store.get(Double.self, "kf_fw_notify_at_" + v) ?? 0
                    if now - lastN > 30 * 86400 * 1000 {
                        DB.store.set("kf_fw_notify_at_" + v, now)
                        await notifyNow(id: "m4.fw." + v, title: "有固件可升级",
                                        body: "本地固件包 v\(item.version) 比锁内 v\(kc.fw) 新, 可到工具-检查固件更新执行。",
                                        dayDeliver: true)
                    }
                }
            }
        }
        // 1012 年度换电日 / 1025 应急钥匙半年检: 日历型提醒重建
        await rescheduleCalendar()
    }

    /// 日历型提醒: 统一 10:00 送达 (1038 白天送达), 年/半年重复
    static func rescheduleCalendar() async {
        let center = UNUserNotificationCenter.current()
        let ids = DB.keychains().flatMap { ["m4.ybatt." + $0.mac, "m4.ekey." + $0.mac] }
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard await requestAuth() else { return }
        let cal = WeekCal.gregorian
        for kc in DB.keychains() {
            let s = BatteryCare.care(kc.mac)
            // 1012 每年换电池提醒
            if s.yearlyBattDay.count == 5 {
                let p = s.yearlyBattDay.split(separator: "-").compactMap { Int($0) }
                if p.count == 2, p[0] >= 1, p[0] <= 12, p[1] >= 1, p[1] <= 31 {
                    var comp = DateComponents(month: p[0], day: p[1])
                    comp.hour = 10
                    let c = UNMutableNotificationContent()
                    c.title = "年度换电日"
                    c.body = "今天是「\(LockArchive.displayName(kc))」的年度换电日, 换完顺手记录到电池档案。"
                    c.sound = .default
                    try? await center.add(UNNotificationRequest(
                        identifier: "m4.ybatt." + kc.mac, content: c,
                        trigger: UNCalendarNotificationTrigger(dateMatching: comp, repeats: true)))
                }
            }
            // 1025 应急钥匙半年检 (从上次打卡起算 182 天; 从未打卡则从开启日算)
            if s.ekeyRemindOn {
                let base = s.ekeyCheckAt > 0 ? s.ekeyCheckAt : Date().timeIntervalSince1970 * 1000
                var due = Date(timeIntervalSince1970: base / 1000 + 182 * 86400)
                if due < Date() { due = cal.date(byAdding: .day, value: 1, to: Date()) ?? due }
                var comp = cal.dateComponents([.year, .month, .day], from: due)
                comp.hour = 10
                let c = UNMutableNotificationContent()
                c.title = "应急钥匙半年检"
                c.body = "半年到了 — 确认「\(LockArchive.displayName(kc))」的应急钥匙还在老地方, 到维护页打卡。"
                c.sound = .default
                try? await center.add(UNNotificationRequest(
                    identifier: "m4.ekey." + kc.mac, content: c,
                    trigger: UNCalendarNotificationTrigger(dateMatching: comp, repeats: false)))
            }
        }
    }
}

/// "5.2.9" → 可比较字符串; 非法版本返回 nil (146 提醒只对两段都能解析的版本生效)
private func _FWVersion(_ s: String) -> String? {
    let parts = s.split(separator: ".")
    guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
    return s
}
