// 包4 电量·维护·固件关怀 — 本地采样与关怀提醒引擎 (纯数据层, 无 UI)
// 数据地基: kf_batt_<mac> 电量采样表 (idea 45 ⚠ 的趋势数据源: 每次读 03 追加点, 90 天截断)。
// 其余键: kf_fwsince_<mac> 固件服役起点 (1019) · kf_care_marks 保养月历打点 (1030)
//         kf_batt_state_<mac> 低电通知武装位 (1004 滞回)
// ⚠ 未实现: kf_mevents_<mac> 维护事件与 kf_maint_<mac> 保养状态 —— 头注曾列为已实现,
//   但本文件与全仓**没有读写点**, 保养计划（换电/保养提醒）也从未建过 UI。留在这里当待办, 不是既有能力。
// 协议约束 (CAPABILITY §2/§6): 电量仅百分比、无电压无充电位 — 只做本地采样, 不虚构电压/充电态/续航估算。
// 通知全部本地通知 (UNUserNotificationCenter); 夜间免扰 (1031) 与白天送达 (1038) 在此统一裁决。
import Foundation
import UserNotifications

struct BattSample: Codable {
    var t: Double   // Unix 毫秒
    var pct: Int
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
        // 缓存值是**非可选**元组 (Locked 里存的永远是最后一组读数, 空值由 mac == "" 表示),
        // 原写法 `if let c = ...` 是 OSAllocatedLock 时代的残留 —— 那时 withLock 返回 Optional。
        let cached = lowCacheLock.withLock { $0 }
        if cached.mac == mac { return cached.low }
        let pct = displayPct(mac, snapshot: DB.readStatus(mac)?.powerLevel ?? -1)
        guard pct >= 0 else { return false }
        let low = isLow(pct)
        lowCacheLock.withLock { $0 = (mac, low) }
        return low
    }


    // ============ 电量采样 (idea 45 的数据地基) ============
    static func samples(_ mac: String) -> [BattSample] {
        DB.store.get([BattSample].self, "kf_batt_" + mac) ?? []
    }

    /// 电量采样：每次读到锁状态就记一笔（LockService.readStatus 调用）。
    /// 90 天截断 —— 更早的样本对「续航趋势」已经没有意义，留着只是占体积。
    @discardableResult
    static func sample(_ mac: String, pct: Int) -> Bool {
        guard pct >= 0, pct <= 100 else { return false }
        var list = samples(mac)
        let nowMs = Date().timeIntervalSince1970 * 1000
        let cutoff = nowMs - 90 * 24 * 3600 * 1000
        list.removeAll { $0.t < cutoff }
        // 同一分钟同一读数不重复记（一次开锁会连读两三遍状态）。
        if let last = list.last, nowMs - last.t < 60_000, last.pct == pct { return false }
        list.append(BattSample(t: nowMs, pct: pct))
        DB.store.setCodable("kf_batt_" + mac, list)
        evaluateLowBattery(mac, pct: pct)
        return true
    }
    /// 采样表里最新一条（displayPct 与档案页共用）。
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
        let name = DB.keychain(mac).map { LockArchive.displayName($0) } ?? mac
        let body = level == 2
            ? "「\(name)」只剩 \(pct)%, 请尽快更换电池"
            : "「\(name)」电量 \(pct)%, 建议备好电池择日更换"
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



    // 2026-10-26: 这里原有 `versionLt`（版本串逐段比较），与 ZipKit/FirmwareKit 里的那份**逐字相同**。
    // 本文件那份零调用，已删；版本比较统一走 `FirmwareKit.versionLt`（4 个调用点 + 两组表驱动测试）。
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

    static func isQuietHour(_ d: Date = Date()) -> Bool {
        let h = WeekCal.gregorian.component(.hour, from: d)
        return h >= 22 || h < 8
    }




}
