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
    var id: Double { at }
}

enum BatteryCare {
    // ============ 五档电量 (113: 满/高/中/低/空) ============
    struct Tier {
        let icon: String
        let tone: ToneColor
        let label: String
        let severe: Bool   // 120 低电视觉降级档 (≤10%)
    }
    static func tier(_ pct: Int) -> Tier {
        switch pct {
        case ..<0:     return Tier(icon: "battery.0percent", tone: .neutral, label: "未知", severe: false)
        case 0...10:   return Tier(icon: "battery.0percent", tone: .danger, label: "空", severe: true)
        case 11...35:  return Tier(icon: "battery.25percent", tone: .warn, label: "低", severe: false)
        case 36...60:  return Tier(icon: "battery.50percent", tone: .accent, label: "中", severe: false)
        case 61...80:  return Tier(icon: "battery.75percent", tone: .ok, label: "高", severe: false)
        default:       return Tier(icon: "battery.100percent", tone: .ok, label: "满", severe: false)
        }
    }
    /// 1004 喂电提醒判定 (≤20%; 与 287 的可调横幅阈值互相独立)
    static func isLow(_ pct: Int) -> Bool { (0...20).contains(pct) }
    /// 121 低温季提示窗口: 11 月–3 月 (纯本地日期规则)
    static var isColdSeason: Bool {
        let m = Calendar.current.component(.month, from: Date())
        return m == 11 || m == 12 || m <= 3
    }

    // ============ 电量采样 (idea 45 的数据地基) ============
    static func samples(_ mac: String) -> [BattSample] {
        DB.store.get([BattSample].self, "kf_batt_" + mac) ?? []
    }
    static func latest(_ mac: String) -> BattSample? { samples(mac).last }

    /// 统一展示读数 (ROADMAP 包4): Hero 卡/总览条带/档案页共用一个来源 —
    /// 采样表最新值优先 (90 天内且非陈旧才信), 否则回退锁侧快照; 都缺则 -1 未知。
    /// 陈旧上限 7 天: 采样点再旧于快照也不比快照新, 直接当不可用。
    /// 统一展示读数 (ROADMAP 包4): Hero 卡/总览条带/档案页共用一个来源 —
    /// 采样表最新值与锁侧快照取时间较新的那个 (采样随读 03 落库, 通常不比快照旧);
    /// 都缺则 -1 未知。调用方另有采样时间标注 (291), 陈旧值由标注兜底, 不在此处猜。
    static func displayPct(_ mac: String, snapshot: Int = -1) -> Int {
        let snapAt = DB.get(StatusSnapshot.self, "kf_snap_" + mac)?.at ?? 0
        guard let s = latest(mac), s.pct >= 0 else { return snapshot }
        if snapshot < 0 { return s.pct }      // 快照未知 → 采样是唯一证据 (调用方另有时间标注)
        return s.t >= snapAt ? s.pct : snapshot // 快照已知 → 谁更新用谁
    }

    /// 每次读 03 成功后调用 (LockService.getStatus 埋点)。
    /// 追加策略: 电量变化必记; 未变化时距上点 ≥1h 记一次 — 日粒度足够趋势拟合且量小。
    /// 截断: 保留 90 天 + 500 条封顶。
    @discardableResult
    static func sample(_ mac: String, pct: Int) -> Bool {
        guard !mac.isEmpty, pct >= 0 else { return false }
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
        let cal = Calendar.current
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
        let logs = DB.readLogs(mac).prefix(3)
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
        let h = Calendar.current.component(.hour, from: d)
        return h >= 22 || h < 8
    }

    /// 即时本地通知 (1004/1023/校时/146/1013 到期/1024 防潮): 免扰时段静默丢弃
    static func notifyNow(id: String, title: String, body: String) async {
        if quietOn && isQuietHour() { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
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
        for kc in DB.keychains() {
            let name = LockArchive.displayName(kc)
            // 1013 保养到期: 满 90 天起每天最多一条, 完成保养即停
            let s = BatteryCare.care(kc.mac)
            if s.lastCareAt > 0, now - s.lastCareAt >= 90 * 86400 * 1000,
               DB.store.getString("kf_care_notify_" + kc.mac) != Milestones.dayKey() {
                DB.store.set("kf_care_notify_" + kc.mac, Milestones.dayKey())
                await notifyNow(id: "m4.care." + kc.mac, title: "保养到期",
                                body: "「\(name)」距上次保养已满 90 天, 找个方便的时间清洁锁体吧。")
            }
            // 1024 潮湿位: 场所含湿区关键词 ∧ 6–7 月梅雨 → 每 7 天一条
            let place = LockArchive.meta(kc.mac).place
            let damp = ["浴室", "户外", "院", "阳台", "天台"].contains { place.contains($0) }
            let month = Calendar.current.component(.month, from: Date())
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
        // 146 固件提醒: 本地固件清单里有比锁内更新的版本 (每个版本只提醒一次)
        if fwRemindOn {
            for kc in DB.keychains() where !kc.fw.isEmpty {
                for item in BatteryCare.fwlib {
                    guard let v = _FWVersion(item.version), _FWVersion(kc.fw) != nil,
                          FirmwareKit.versionLt(kc.fw, item.version),
                          DB.store.getBool("kf_fw_notify_" + v) == false else { continue }
                    DB.store.set("kf_fw_notify_" + v, true)
                    await notifyNow(id: "m4.fw." + v, title: "有固件可升级",
                                    body: "本地固件包 v\(item.version) 比锁内 v\(kc.fw) 新, 可到工具-检查固件更新执行。")
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
        let cal = Calendar.current
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
