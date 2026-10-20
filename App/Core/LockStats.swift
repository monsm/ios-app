// 包3 设备档案与多锁总览 — 锁档案扩展存储 + 多锁统计 + 设备分组与排序 (纯本地只读现有表)
// 档案字段放独立键 kf_lockmeta_<mac>, 不动 Keychain (备份包 schema 与小程序互通不受影响):
//   106 备注 / 105 符号与色标 / 774 场所副标题 / 290 电池档案 / 258 首连验证 / 292 沉睡基准
//   104/767 分组名 (grp) — 也在档案里
// 排序 (766) 是"锁之间的关系", 不属于单锁档案 → 独立键 kf_lock_order (mac 全序列)
// D-36 (2026-10-11 拍板) 之后的边界: 顺序 (766) / 分组 (104/767) / 分组折叠 (28) / 隐藏 (108) 已随
//   全量备份包的 globals.deviceOrg 走 (BackupKit.collectDeviceOrg / restoreAll), 换机恢复后不必重排;
//   仍只在本机的是本文件这一族档案字段: 场所副标题 (774) / 备注 (106) / 符号与色标 (105) /
//   电池与首连档案 (290/258/292) —— 这些没进包, 界面上如实写着。
// 统计全部读既有本地表 (kf_logcache_ / kf_ledger_ / kf_snap_ / kf_keychains / kf_members),
// 不新增采集, 不碰协议。思路对标 ROADMAP 包3: 776/778/779/784/787/773/768。
import Foundation
import SwiftUI

// ---------- 锁档案 (per-lock 元数据) ----------
struct LockMeta: Codable {
    var note: String = ""             // 106 备注 (备忘录标题正文的双字段案)
    var symbol: String = ""           // 105 符号 (SF Symbol 名; 空 = 默认 lock.fill)
    var colorKey: String = ""         // 105 色标 (LockArchive.swatch 键; 空 = 跟随主题)
    var place: String = ""            // 774 场所副标题 (玄关/车库)
    var batteryModel: String = ""     // 290 电池型号
    var batteryChangedAt: Double = 0  // 290 换电日期 (Unix 秒; 0 = 未记录)
    var verifiedAt: Double = 0        // 258 首连验证时刻 (Unix 秒; 0 = 未验证)
    var lastConnectedAt: Double = 0   // 292 沉睡判定基准 (最近一次连接成功)
    var grp: String = ""              // 104/767 分组名 (家用/仓库/办公… 用户自填; 空 = 未分组)
    var skin: String = ""             // 2026-10-18 门面皮肤 (wood/metal/darkGlass/frosted; 空 = wood)

    // **显式解码器是必需的, 不是风格问题。** 本仓自己在 Store.swift:119 就记着这条事实:
    // 合成 Codable 对有默认值的属性**同样要求键存在** —— 于是第一百三十六批给这个 struct
    // 新加 `grp` 之后, 任何**加字段之前**写下的 kf_lockmeta_<mac> 都会 keyNotFound 解不出来,
    // 而 `DB.get` 在解不出来时返回 nil ⇒ 老用户的昵称色标符号场所电池备注与换电日期**整本档案凭空变空**
    // (界面看不出任何异常, 只是全成了默认值 —— AUDIT-CODE 反复出现的那类"最难查的失效")。
    // 全部 decodeIfPresent + 默认值, 与 Keychain 同一处置。
    private enum CodingKeys: String, CodingKey {
        case note, symbol, colorKey, place, batteryModel, batteryChangedAt, verifiedAt, lastConnectedAt, grp, skin
    }
    init() {}
    init(note: String = "", symbol: String = "", colorKey: String = "", place: String = "",
         batteryModel: String = "", batteryChangedAt: Double = 0, verifiedAt: Double = 0,
         lastConnectedAt: Double = 0, grp: String = "", skin: String = "") {
        self.note = note; self.symbol = symbol; self.colorKey = colorKey; self.place = place
        self.batteryModel = batteryModel; self.batteryChangedAt = batteryChangedAt
        self.verifiedAt = verifiedAt; self.lastConnectedAt = lastConnectedAt; self.grp = grp
        self.skin = skin
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? ""
        colorKey = try c.decodeIfPresent(String.self, forKey: .colorKey) ?? ""
        place = try c.decodeIfPresent(String.self, forKey: .place) ?? ""
        batteryModel = try c.decodeIfPresent(String.self, forKey: .batteryModel) ?? ""
        batteryChangedAt = try c.decodeIfPresent(Double.self, forKey: .batteryChangedAt) ?? 0
        verifiedAt = try c.decodeIfPresent(Double.self, forKey: .verifiedAt) ?? 0
        lastConnectedAt = try c.decodeIfPresent(Double.self, forKey: .lastConnectedAt) ?? 0
        grp = try c.decodeIfPresent(String.self, forKey: .grp) ?? ""
        skin = try c.decodeIfPresent(String.self, forKey: .skin) ?? ""
    }
}

// ---------- 104/767 分组 ----------
/// 一组成员: 组名 + 按总顺序排好的锁。Identifiable 用组名当 id (组名在设备管理里就是它的身份)。
struct LockGroup: Identifiable {
    let name: String
    let locks: [Keychain]
    var id: String { name }
}

enum LockArchive {
    static func meta(_ mac: String) -> LockMeta {
        DB.get(LockMeta.self, "kf_lockmeta_" + mac) ?? LockMeta()
    }
    static func save(_ mac: String, _ m: LockMeta) {
        DB.store.setCodable("kf_lockmeta_" + mac, m)
    }
    /// 292: 连接成功即刷新基准 (开锁成功也会走到这里)
    static func touchConnected(_ mac: String) {
        guard !mac.isEmpty else { return }
        var m = meta(mac)
        m.lastConnectedAt = Date().timeIntervalSince1970
        save(mac, m)
    }
    /// 258: 首次开锁成功 = 全链路 (BLE→会话→04→日志) 跑通, 打"链路已验证"标记
    static func markVerified(_ mac: String) {
        guard !mac.isEmpty else { return }
        var m = meta(mac)
        guard m.verifiedAt == 0 else { return }
        m.verifiedAt = Date().timeIntervalSince1970
        save(mac, m)
    }
    static func isVerified(_ mac: String) -> Bool { meta(mac).verifiedAt > 0 }
    /// 292: 30 天未连接 → 沉睡
    static func isSleeping(_ mac: String) -> Bool {
        let t = meta(mac).lastConnectedAt
        guard t > 0 else { return false }   // 从未连接过的不算沉睡 (新绑定/只导入)
        return Date().timeIntervalSince1970 - t > 30 * 86400
    }
    /// 108 手动隐藏的锁: 退出横滑翻页与胶囊主列表，只从"已隐藏"区可达并可当场恢复。
    /// 为什么不复用上面 isSleeping 那条自动判据: 隐藏是**用户明确说过的**，沉睡是推断出来的 ——
    /// 凑成一个开关就会出现"我没藏它，它自己不见了"，而且两种状态得能在界面上分开说明。
    static func isHidden(_ mac: String) -> Bool { DB.store.getBool("kf_lock_hidden_" + mac) }
    static func setHidden(_ mac: String, _ on: Bool) { DB.store.set("kf_lock_hidden_" + mac, on) }
    /// 启动默认锁 (271/103: 上滑固定 / 首位), 独立键不属于单锁档案
    static var defaultMac: String { DB.store.getString("kf_default_mac") }
    /// 271 与 766 只留一个真相: 手工顺序存在时, "设为启动默认锁"必须同时把它排到首位 ——
    /// 否则顺序表说 A 在前、默认锁说 B 在前, 翻页首位与冷启动落点会分叉成两个答案。
    static func setDefaultMac(_ mac: String) {
        DB.store.set("kf_default_mac", mac)
        var o = orderMacs
        guard !mac.isEmpty, let i = o.firstIndex(of: mac) else { return }
        o.remove(at: i); o.insert(mac, at: 0)
        DB.store.setCodable(orderKey, o)
    }

    // ---------- 104/767 分组 + 766 手工排序 ----------
    /// 分组名建议 (104 原句的"大门/卧室"就是用户自填): 只作快捷选项, 不是枚举白名单
    static let groupPresets = ["家用", "仓库", "办公"]
    static let ungroupedLabel = "未分组"
    private static let orderKey = "kf_lock_order"

    static func group(_ mac: String) -> String { meta(mac).grp }
    /// 组名归一 (去空白 + 12 字上限): 设备管理页与锁档案两处写同一个字段, 口径放这一个函数里,
    /// 免得一处截 12 字、另一处不截 —— 组名要当 Section 标题和胶囊 chip 用, 超了就只能裁切。
    static func normalizedGroup(_ g: String) -> String {
        String(g.trimmingCharacters(in: .whitespacesAndNewlines).prefix(12))
    }
    static func setGroup(_ mac: String, _ g: String) {
        guard !mac.isEmpty else { return }
        var m = meta(mac)
        m.grp = normalizedGroup(g)
        save(mac, m)
    }
    /// 现存组 (按组内首锁在总顺序里的先后), "未分组"固定垫底。
    /// 为什么是 struct 而不是 `(name:, locks:)` 元组数组：**不是**因为 key path 不能指元组元素 ——
    /// 2026-10-13 查证更正: 元组元素的 key path 其实是合法的 (Swift 诊断表里根本没有
    /// "key path cannot refer to tuple element" 这条, 公开资料亦以 `id: \.1.id` / `id: \.element.id`
    /// 为可用写法)。真正会编译不过的是**单参 `ForEach`/`Chart`**: 那版初始化器要求元素 `Identifiable`,
    /// 而元组不能遵循协议。换成结构体是为了拿到**稳定身份** (组名唯一、可读), 不是为了绕开 key path。
    static func grouped(_ devices: [Keychain]) -> [LockGroup] {
        var names = [String]()
        var buckets = [String: [Keychain]]()
        for kc in devices {
            let g = group(kc.mac).isEmpty ? ungroupedLabel : group(kc.mac)
            if buckets[g] == nil { names.append(g) }
            buckets[g, default: []].append(kc)
        }
        if let i = names.firstIndex(of: ungroupedLabel) {
            names.remove(at: i); names.append(ungroupedLabel)
        }
        return names.compactMap { n in buckets[n].map { LockGroup(name: n, locks: $0) } }
    }

    static var orderMacs: [String] { DB.store.get([String].self, orderKey) ?? [] }
    static var hasManualOrder: Bool { !orderMacs.isEmpty }
    static func setOrder(_ macs: [String]) {
        // 写侧剪掉已解绑的 mac: 顺序表是全局键, 删设备那一步 (Store.removeDevice) 删不到按键名含 mac 的
        // 逐锁族, 但表里的幽灵条目只会让读侧多做无用的查找, 直接剪掉。
        let alive = Set(DB.keychains().map { $0.mac })
        DB.store.setCodable(orderKey, macs.filter { alive.contains($0) })
    }
    static func clearManualOrder() { DB.store.remove(orderKey) }

    /// 766 设备顺序的唯一读点: 手工顺序优先, 表里没有的 (新绑定) 按绑定先后垫后;
    /// 无手工顺序时按绑定先后, 但**启动默认锁仍占首位** —— 设备管理页的"第一行就是启动默认锁"
    /// 与设备页的 271 兜底排序讲的是同一件事, 这里漏掉默认锁就会两页各说一套。
    /// 低电置顶 (114) 不在这里做 —— 自动置顶会把用户明确排好的顺序挪走, 与 108 隐藏 vs 292 沉睡
    /// 同一口径 (明确动作优先于推断), 低电改由 764 图标行的橙点如实标出 (1041 电量升序是另一条明确开关)。
    static func orderedDevices(_ devices: [Keychain]) -> [Keychain] {
        let o = orderMacs
        guard !o.isEmpty else {
            let def = defaultMac
            return devices.sorted { a, b in
                if a.mac == def { return true }
                if b.mac == def { return false }
                return a.pairedAt < b.pairedAt
            }
        }
        let byMac = Dictionary(devices.map { ($0.mac, $0) }, uniquingKeysWith: { a, _ in a })
        let head = o.compactMap { byMac[$0] }
        let rest = devices.filter { !o.contains($0.mac) }.sorted { $0.pairedAt < $1.pairedAt }
        return head + rest
    }

    /// 组内拖动回写 (104): 只把这一组成员的新内部次序放回它们**原本占据的位置**,
    /// 其他组与未分组的位置一步不动 —— 否则"把仓库组两把锁对调"会把别的组一起挤走。
    static func reordered(_ all: [Keychain], newGroupOrder groupLocks: [Keychain]) -> [Keychain] {
        let member = Set(groupLocks.map { $0.mac })
        guard !member.isEmpty else { return all }
        var queue = groupLocks
        var out = [Keychain]()
        for kc in all {
            if member.contains(kc.mac), queue.isEmpty == false { out.append(queue.removeFirst()) }
            else { out.append(kc) }
        }
        return out
    }

    /// 置顶 = 首位 + 启动默认锁 (271/766 同一动作, 见上面 setDefaultMac)
    static func pinToFront(_ mac: String, _ devices: [Keychain]) {
        guard !mac.isEmpty else { return }
        var l = orderedDevices(devices).map { $0.mac }
        l.removeAll { $0 == mac }
        l.insert(mac, at: 0)
        setOrder(l)
        setDefaultMac(mac)
    }

    // 105 色标: 只走 DS 语义令牌 (不引入自定义 hex, 保证对比度闸门覆盖)
    struct Swatch: Identifiable {
        let key: String
        let name: String
        var id: String { key }
    }
    static let swatches: [Swatch] = [
        Swatch(key: "", name: "主题色"),
        Swatch(key: "ok", name: "绿"),
        Swatch(key: "warn", name: "橙"),
        Swatch(key: "danger", name: "红"),
        Swatch(key: "neutral", name: "灰"),
    ]
    static func swatchColor(_ key: String) -> Color {
        switch key {
        case "ok": return DS.Palette.ok
        case "warn": return DS.Palette.warn
        case "danger": return DS.Palette.danger
        case "neutral": return DS.Palette.textSub
        default: return DS.Palette.accent   // 空 = 跟随品牌主题
        }
    }
    // 105 符号: 与场所语义呼应的一小组, 全部为系统基础符号
    struct SymbolOption: Identifiable {
        let name: String
        let label: String
        var id: String { name }
    }
    static let symbols: [SymbolOption] = [
        SymbolOption(name: "lock.fill", label: "默认"),
        SymbolOption(name: "house.fill", label: "家"),
        SymbolOption(name: "building.2.fill", label: "楼栋"),
        SymbolOption(name: "car.fill", label: "车库"),
        SymbolOption(name: "briefcase.fill", label: "办公"),
        SymbolOption(name: "key.fill", label: "钥匙"),
        SymbolOption(name: "shield.fill", label: "布防"),
        SymbolOption(name: "bell.fill", label: "侧门"),
    ]
    static func symbolName(_ m: LockMeta) -> String { m.symbol.isEmpty ? "lock.fill" : m.symbol }
    /// 锁的显示名 (与 AppState.displayName 同规则, 供统计层/列表复用)
    static func displayName(_ kc: Keychain) -> String {
        let raw = kc.pidName
        let model = (!raw.isEmpty && !raw.contains("pid=") && !raw.contains("未知")) ? raw : PidMap.productName(kc.pid)
        return kc.name.isEmpty ? model : kc.name
    }
    /// Hero 卡副标题 (774): 场所优先, 缺省回退型号
    static func subtitle(_ kc: Keychain) -> String {
        let m = meta(kc.mac)
        return m.place.isEmpty ? PidMap.productName(kc.pid) : m.place
    }
    /// 769 绑定时间小字 (设备管理行 / 总览固件卡同口径: 未记录就不虚构日期)
    static func boundLabel(_ pairedAt: String) -> String {
        guard pairedAt.count >= 10 else { return "绑定时间未记录" }
        return "绑定于 " + pairedAt.prefix(10).replacingOccurrences(of: "-", with: "/")
    }
}

// ---------- 多锁统计 ----------
/// 每把锁一行的聚合读数: 30 天窗口从日志缓存统计, 容量/电量/固件从快照读。
struct LockUsage: Identifiable {
    var mac: String
    var name: String
    var opens30d: Int = 0        // 开门类 (type 1-5)
    var alarms30d: Int = 0       // 告警类 (6 电量低/7 撬锁/10 试错锁定/13 指纹告警/224 键盘锁定)
    var lastOpenAt: String = ""  // 最近一次开门 (日志缓存内)
    /// 这台锁**有没有日志缓存**。`usage()` 是对 `DB.keychains()` 全量 map 出来的, 从未同步过的锁也在集合里、
    /// 各项计数天然是 0 —— 而 0 与"没读到"是两件事 (本文件 recentAlarmMacs 那条注释就写着这个口径:
    /// 界面要标"没有读数"而不是"没有告警")。这一位把那句话变成可以判的数据。
    var logged: Bool = false
    var power: Int = -1          // 快照电量
    var snapAt: Double = 0       // 快照采样时刻 (291 溯源)
    var fw: String = ""          // 固件 (钥匙串优先, 快照兜底)
    var pwdUsed: Int = -1, pwdCap: Int = -1    // 773: -1 = 未知
    var fpUsed: Int = -1, fpCap: Int = -1
    var sleeping: Bool = false   // 292
    var verified: Bool = false   // 258
    var pairedAt: String = ""    // 769 绑定时间
    var id: String { mac }
    /// 778 告警率 = 告警 / (告警+开门), 万一全告警也算 100%
    var alarmRate: Double { opens30d + alarms30d == 0 ? 0 : Double(alarms30d) / Double(opens30d + alarms30d) }
}

@MainActor
enum LockStats {
    /// 第一百五十七批：这两组类型集合原本在 `StatsKit.swift:9-10` 与这里各抄一份 (值相同)。
    /// 抄两份的意思是"哪天加一类告警，只改一处就会静悄悄地漂" —— 而那正是本批在设备页刚抓到的缺陷形态
    /// (`recentRecords` 曾自己写了 `7||13||224`，漏掉 6 低电量与 10 试错锁定)。口径只留 StatsKit 一份。
    static var openTypes: Set<Int> { StatsKit.openTypes }
    static var alarmTypes: Set<Int> { StatsKit.alarmTypes }
    static let windowDays = 30

    /// 快照采样时刻 (291): DB.readStatus 只回状态体, 这里取信封时间
    static func snapAt(_ mac: String) -> Double {
        DB.get(StatusSnapshot.self, "kf_snap_" + mac)?.at ?? 0
    }
    static func sampleTimeText(_ at: Double) -> String {
        guard at > 0 else { return "" }
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return "采样于 " + f.string(from: Date(timeIntervalSince1970: at / 1000))
    }

    /// 全锁聚合 (776/778/784/773/769/292/258 的共同数据源)
    static func usage() -> [LockUsage] {
        let cutoff = Date().timeIntervalSince1970 - Double(windowDays) * 86400
        // 2026-10-14: 测试标记集合提到 map 外只算一次 (原先每把锁都重新解析一遍 kf_rdispo)。
        let testKeys = RecordSearch.testMarkedKeys
        return DB.keychains().map { kc -> LockUsage in
            var u = LockUsage(mac: kc.mac, name: LockArchive.displayName(kc))
            // 745 测试标记: 与 StatsKit.build 同一排除口径 (键 = mac#idxRaw)
            let logs = DB.readLogs(kc.mac).filter { !testKeys.contains(kc.mac + "#" + String($0.idxRaw)) }
            for l in logs {
                // 日志 lockTimeStr 是本地串; 时间过滤用日志写入缓存顺序不可靠,
                // 这里按锁端秒换算 Unix 秒对齐窗口 (ProtoTime 基准 2010-01-01)
                let unixSec = ZKProtocol.protoSecondsToUnix(Int64(l.lockTime))
                if unixSec >= cutoff {
                    if openTypes.contains(l.type) { u.opens30d += 1 }
                    if alarmTypes.contains(l.type) { u.alarms30d += 1 }
                }
                if u.lastOpenAt.isEmpty, openTypes.contains(l.type), !l.lockTimeStr.isEmpty {
                    u.lastOpenAt = l.lockTimeStr
                }
            }
            u.logged = !logs.isEmpty   // 缓存是空的 ≠ 这台锁没有告警, 只是从没同步过
            let snap = DB.readStatus(kc.mac)
            u.power = snap?.powerLevel ?? -1
            u.snapAt = snapAt(kc.mac)
            u.fw = kc.fw.isEmpty ? (snap?.firmware ?? "") : kc.fw
            // 773: 优先锁侧真值 (容量-剩余=已用), 台账计数兜底
            let ledger = DB.ledger(kc.mac)
            if let cap = snap?.pwdCap, cap > 0 {
                u.pwdCap = cap
                u.pwdUsed = max(cap - (snap?.pwdStock ?? 0), 0)
            } else {
                u.pwdUsed = ledger.pwds.count
            }
            if let cap = snap?.fpCap, cap > 0 {
                u.fpCap = cap
                u.fpUsed = max(cap - (snap?.fpStock ?? 0), 0)
            } else {
                u.fpUsed = ledger.fps.count
            }
            u.sleeping = LockArchive.isSleeping(kc.mac)
            u.verified = LockArchive.isVerified(kc.mac)
            u.pairedAt = kc.pairedAt
            return u
        }
    }


    /// 768 待维护锁清单: 低电 / 近 30 天有告警 / 密钥未绑定, 全部来自可读证据
    struct MaintenanceItem: Identifiable {
        let usage: LockUsage
        let reasons: [String]
        var id: String { usage.mac }
    }
    static func maintenance(_ usages: [LockUsage]) -> [MaintenanceItem] {
        var out: [MaintenanceItem] = []
        for u in usages {
            var reasons: [String] = []
            if (0...20).contains(u.power) { reasons.append("电量 \(u.power)%") }
            if u.alarms30d > 0 { reasons.append("近 30 天 \(u.alarms30d) 条告警") }
            // 快照缺失 = 密钥状态未知, 不能当成"正常": 旧写法 (…?.sKeyStatus ?? 0) != 0 在 nil 时判假,
            // 从未连过的锁直接跳过这一项检查 (fail-open)。
            if let snap = DB.readStatus(u.mac) {
                if snap.sKeyStatus != 0 { reasons.append("密钥未绑定") }
            } else {
                reasons.append("密钥状态未知 (无 03 快照)")
            }
            if !reasons.isEmpty { out.append(MaintenanceItem(usage: u, reasons: reasons)) }
        }
        return out
    }

    /// 764 图标行的告警判据: 近 windowDays 天内**日志缓存里**有告警类记录的锁。
    /// 只读已有缓存、不主动连锁 —— 图标行每次 body 都会重算, 这里必须是可以放在刷新里算一次的纯本地聚合。
    /// 读不到日志的锁 (从未同步) 不在集合里, 界面上标成"没有读数"而不是"没有告警" (空心圈)。
    static func recentAlarmMacs(_ usages: [LockUsage]? = nil) -> Set<String> {
        let src = usages ?? usage()
        var set = Set<String>()
        for u in src where u.alarms30d > 0 { set.insert(u.mac) }
        return set
    }

    /// 787 对比结论一句话 (财报解读式模板, 只引用上方同源数字)
    static func summary(_ usages: [LockUsage]) -> String {
        let active = usages.filter { !$0.sleeping }
        guard usages.count > 1 else {
            return "当前只有一把锁, 添加更多门锁后即可在这里对比活跃度与告警。"
        }
        guard let top = active.max(by: { $0.opens30d < $1.opens30d }), top.opens30d > 0 else {
            return "近 \(windowDays) 天各锁都还没有开门记录, 连接门锁读取日志后再来看对比。"
        }
        var parts: [String] = ["近 \(windowDays) 天「\(top.name)」开门 \(top.opens30d) 次, 是最活跃的一把"]
        let rest = active.filter { $0.mac != top.mac && $0.opens30d > 0 }
        if let second = rest.max(by: { $0.opens30d < $1.opens30d }), second.opens30d > 0 {
            let ratio = Double(top.opens30d) / Double(second.opens30d)
            parts.append(String(format: "约为「%@」的 %.1f 倍", second.name, ratio))
        }
        let alarmTop = active.max(by: { $0.alarmRate < $1.alarmRate })
        if let a = alarmTop, a.alarmRate >= 0.1, a.alarms30d > 0 {
            parts.append(String(format: "「%@」告警占比最高 (%.0f%%), 建议看看告警记录", a.name, a.alarmRate * 100))
        }
        if usages.contains(where: { $0.sleeping }) {
            parts.append("另有 \(usages.filter { $0.sleeping }.count) 把锁已 30 天未连接, 归入沉睡组")
        }
        return parts.joined(separator: "; ") + "。"
    }

    /// 784 固件对照: 返回 (该锁版本是否落后于本机最任一把, 本机最新版本)
    static func fwLag(_ usages: [LockUsage]) -> (latest: String, lagging: Set<String>) {
        let vers = usages.map { $0.fw }.filter { !$0.isEmpty }
        guard !vers.isEmpty else { return ("", []) }
        let latest = vers.max { fwCmp($0, $1) < 0 } ?? ""
        var lagging = Set<String>()
        for u in usages where !u.fw.isEmpty && fwCmp(u.fw, latest) < 0 { lagging.insert(u.mac) }
        return (latest, lagging)
    }
    static func fwCmp(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<3 {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y ? 1 : -1 }
        }
        return 0
    }
}
