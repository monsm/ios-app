// 本地存储与数据模型 — JS utils/store.js + services/{ledger,snapshot,keychain,gateway,members}.js 移植
// 存储键与小程序完全一致 (kf_*), 便于全量备份跨端互换
import Foundation

// ---------- 存储 ----------
final class Store {
    static let shared = Store()
    private let defaults = UserDefaults.standard
    private func key(_ k: String) -> String { "kf." + k }
    /// 兼容全库既有的 `get(类型, 键)` 写法 (BatteryCare/DiagKit/Milestones/MemberHub/RecordSearch 等约 87 处)。
    /// Swift 按参数序解析重载: 键优先与类型优先两种形态都合法, 语义完全一致 ——
    /// 这样就不必为了一个签名顺序去批量改写 87 个调用点 (那样做风险远大于收益)。
    func get<T: Decodable>(_ type: T.Type, _ k: String) -> T? { get(k, type) }
    func get<T: Decodable>(_ k: String, _ type: T.Type) -> T? {
        guard let d = defaults.data(forKey: key(k)) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: d)
        } catch {
            // **有数据但解不出来**是比写失败更难查的一种失效: 读侧拿到 nil ⇒ 一路回落默认值，
            // 界面上什么都看不出来，而用户确实设置过 (与 §104 那批"恒为默认值"是同一类症状的另一种成因)。
            recordFailure(k, "解码失败 \(type): \((error as NSError).localizedDescription)")
            return nil
        }
    }
    func getDict(_ k: String) -> [String: Any] {
        guard let d = defaults.data(forKey: key(k)) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
    }
    func getString(_ k: String, _ def: String = "") -> String {
        if let s = defaults.string(forKey: key(k)) { return s }
        if let v = get(k, String.self) { return v }
        return def
    }
    func getBool(_ k: String, _ def: Bool = false) -> Bool { get(k, Bool.self) ?? def }
    func getInt(_ k: String, _ def: Int = 0) -> Int { get(k, Int.self) ?? def }
    func set(_ k: String, _ v: Any) {
        // 顶层标量 (String/Bool/Int/Double) 是 JSON fragment: 不开 .fragmentsAllowed 时
        // JSONSerialization 直接抛错, 被 try? + if let 静默吞掉 → 该键从未落盘,
        // 读侧只能拿到默认值 (设置页所有开关/主题/救援码/免验窗口全部失效)。
        // 第九十五批把"吞掉"改成"记一笔": 失败本身仍然不改返回值 (改签名要动几百个调用点，风险远大于收益)，
        // 但从这往后它不再是**只有天知道**——调用方紧接着报"已设置/已保存"时，诊断页至少能看到那是假成功。
        do {
            let d = try JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed])
            defaults.set(d, forKey: key(k))
        } catch {
            recordFailure(k, "JSONSerialization: \((error as NSError).localizedDescription)")
        }
    }
    /// 参数序 = **键在前、值在后**，与 `DB.setCodable(值, 键)` 正好相反 —— 这个反差已经写过 5 处编译器必拒的调用，
    /// 故 swiftlint 第四项按"首参不是键、次参像键"报红线。新增键位时先看清自己在哪一层。
    func setCodable<T: Encodable>(_ k: String, _ v: T) {
        do {
            defaults.set(try JSONEncoder().encode(v), forKey: key(k))
        } catch {
            recordFailure(k, "JSONEncoder: \((error as NSError).localizedDescription)")
        }
    }
    // ---------- 存取失败台账 (kf.wf, 走 defaults 不经 set/setCodable ⇒ 不会自我递归) ----------
    /// 为什么不建内存静态量: Swift 6 下非隔离可变全局本身要处理竞态，而且进程重启就没了 ——
    /// "我明明设了却没生效"这类问题恰恰常常要**下一次打开 App**才看得见。
    /// 只存"键 ← 失败原因"，**不存值** (值可能是口令或 2FA 种子，绝不能在诊断里重现)。
    /// 同键同因只记一次: 热 getter 若每帧都失败，不把 defaults 当日志刷。
    static let failureKey = "wf"
    private func recordFailure(_ k: String, _ why: String) {
        let tail = k + " ← " + why
        if failureLines().contains(where: { $0.hasSuffix(tail) }) { return }
        var next = failureLines()
        next.insert(DiagTime.mmddHHmm() + " " + tail, at: 0)
        if next.count > 40 { next = Array(next.prefix(40)) }
        defaults.set(next, forKey: key(Self.failureKey))
    }
    func failureLines() -> [String] { (defaults.array(forKey: key(Self.failureKey)) as? [String]) ?? [] }
    /// 刻意**不提供**清空口: 这本账的删除动作留在既有语义里 —— 核弹销毁按 `keys()` 全表清 (AuditChain:242)，
    /// 加一个 `clearFailureLog()` 只会多一条零调用声明，而且给了"把证据抹掉但不告诉用户抹了什么"的按钮。
    func remove(_ k: String) { defaults.removeObject(forKey: key(k)) }
    /// 键是否存在 (区分"无数据"与"有数据但解不出")
    func has(_ k: String) -> Bool { defaults.object(forKey: key(k)) != nil }
    /// 取值的文本形态 (供"销毁后残留检索"用): 旧实现只检索键名, 值从未参与检查
    func rawText(_ k: String) -> String? {
        if let s = defaults.string(forKey: key(k)) { return s }
        if let d = defaults.data(forKey: key(k)) { return String(data: d, encoding: .utf8) }
        if let o = defaults.object(forKey: key(k)) { return String(describing: o) }
        return nil
    }
    func keys() -> [String] {
        defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("kf.") }.map { String($0.dropFirst(3)) }
    }
    /// 421 回滚快照: 原样读出 defaults 里那段 JSON Data。
    /// 不走 get/JSONDecoder —— 快照要的是**字节不变**，重新编码会把形状 (键序/可选字段) 改写一遍。
    func rawData(_ k: String) -> Data? { defaults.data(forKey: key(k)) }
    func setRawData(_ k: String, _ d: Data) { defaults.set(d, forKey: key(k)) }
    /// 按前缀族取键 (已去掉 "kf." 头): 回滚只收"恢复会动到"的那几族, 不把日志/遥测这类大块拖进快照
    func matchingKeys(prefixes: [String]) -> [String] {
        keys().filter { k in prefixes.contains { p in k.hasPrefix(p) } }
    }
    // `clearAll()` (一把删光所有 kf.* 键) 第九十二批删除：全库零调用点，而且它比看起来危险 ——
    // 销毁流程走的是"按前缀族回滚/覆写"那套 (matchingKeys)，从来没人调它。
    // 留着这么一把没有主的清空枪，只会让下一个加"重置"按钮的人顺手拿来用；
    // 真要全清得先定清"哪些键属于 App、哪些是日志/遥测"，那是设计不是一行删除。
}

// ---------- 钥匙串台账 (services/lock.js) ----------
struct Keychain: Codable, Identifiable {
    var version: Int = 1
    var mac: String
    var pid: Int = 0
    var pidName: String = ""
    var name: String = ""
    var skey: String
    var bkey: String = ""
    var pins: [String] = []
    var ekey: String = ""
    var trackid: String = ""
    var bleId: String = ""
    var fw: String = ""
    var pairedAt: String = ""
    var id: String { mac }

    // 合成 Codable 对有默认值的属性同样要求键存在 — 而 canonical 文本备份会省略空字段,
    // 导致"导出后导不回" (keyNotFound → "不是有效的备份包")。全部 decodeIfPresent + 默认值,
    // 语义与 fromDict 容错链对齐。
    init(version: Int = 1, mac: String, pid: Int = 0, pidName: String = "", name: String = "", skey: String,
         bkey: String = "", pins: [String] = [], ekey: String = "", trackid: String = "",
         bleId: String = "", fw: String = "", pairedAt: String = "") {
        self.version = version; self.mac = mac; self.pid = pid; self.pidName = pidName
        self.name = name; self.skey = skey; self.bkey = bkey; self.pins = pins
        self.ekey = ekey; self.trackid = trackid; self.bleId = bleId
        self.fw = fw; self.pairedAt = pairedAt
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        mac = try c.decodeIfPresent(String.self, forKey: .mac) ?? ""
        pid = try c.decodeIfPresent(Int.self, forKey: .pid) ?? 0
        pidName = try c.decodeIfPresent(String.self, forKey: .pidName) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        skey = try c.decodeIfPresent(String.self, forKey: .skey) ?? ""
        bkey = try c.decodeIfPresent(String.self, forKey: .bkey) ?? ""
        pins = try c.decodeIfPresent([String].self, forKey: .pins) ?? []
        ekey = try c.decodeIfPresent(String.self, forKey: .ekey) ?? ""
        trackid = try c.decodeIfPresent(String.self, forKey: .trackid) ?? ""
        bleId = try c.decodeIfPresent(String.self, forKey: .bleId) ?? ""
        fw = try c.decodeIfPresent(String.self, forKey: .fw) ?? ""
        pairedAt = try c.decodeIfPresent(String.self, forKey: .pairedAt) ?? ""
    }
}

// ---------- 凭证台账 (services/ledger.js) ----------
struct LedgerPwd: Codable, Identifiable {
    var alias: Int
    var from: String
    var to: String
    var temp: Bool
    var at: Double          // epoch **毫秒** (添加时刻；注意 `CredBinEntry.at` / `CredSnapshot.at` 是秒 —— 混用会差一千倍，第一百六十二批就是这么筛出 0 条的)
    var pwd: String?
    var owner: String?
    var note: String
    var id: Int { alias }
}
struct LedgerFp: Codable, Identifiable {
    var batch: Int
    var name: String
    var at: Double          // epoch **毫秒** (添加时刻；与 `LedgerPwd.at` 同约定)
    var note: String
    var src: String?
    var owner: String?
    var isAlarm: Bool?
    var id: Int { batch }
}
struct Ledger: Codable {
    var pwds: [LedgerPwd] = []
    var fps: [LedgerFp] = []
}

// ---------- 成员档案 (services/members.js v3) ----------
struct Member: Codable, Identifiable {
    // 259/623 成员色板 = 这个字段 (新成员建档时分配固定色，头像/时间线/过滤按钮统一取色)。
    // 类型里那个十六进制默认值是品牌靛蓝本身，第一个成员拿到它是巧合，不是"成员色有默认偏好"。
    var id: String
    var name: String
    var relation: String = ""
    var phone: String = ""
    var color: String = "#3D8BFF"
    var at: Double = 0
}

// ---------- 快照 (services/snapshot.js) ----------
struct StatusSnapshot: Codable {
    var at: Double
    var status: StatusSnapshotData
}
struct StatusSnapshotData: Codable {
    var rc: Int = 0
    var powerLevel: Int = 0
    var firmware: String = ""
    var lockTime: Int64 = 0
    var pinStock: Int = 0
    var pwdStock: Int = 0
    var fpStock: Int = 0
    var verifyMode: Int = 0
    var broadcastMode: Int = 0
    var tempPwdMode: Int = 0
    var securityLevel: Int = 0
    var sKeyStatus: Int = 0
    // 947: 临时码周期 (03#05, 单位分钟)。Optional — 旧快照缺键解码为 nil, 生成端回落协议默认 30
    var zotpPeriod: Int?
    // 包3/idea 773: 协议容量族 (03 KLV 21/24/27)。Optional — 旧快照 JSON 缺键时解码为 nil,
    // 保证历史快照仍可读; 容量未知时水位条降级为台账计数。
    var pinCap: Int?
    var pwdCap: Int?
    var fpCap: Int?
}
struct LogCache: Codable {
    var at: Double
    var logs: [CachedLog]
}
struct CachedLog: Codable {
    var type: Int
    var typeName: String
    var idxRaw: UInt32
    var lockTime: Int64
    var lockTimeStr: String
}

// ---------- 钥匙串硬件台账 ----------
struct Dongle: Codable, Identifiable {
    var mac: String
    var name: String = ""
    var bleId: String = ""
    var boundAt: String = ""
    var lastSeenAt: String = ""
    var lastKeyLock: String = ""
    var lastKeyAt: String = ""
    var stat: DongleStat?
    var id: String { mac }

    init(mac: String, name: String = "", bleId: String = "", boundAt: String = "",
         lastSeenAt: String = "", lastKeyLock: String = "", lastKeyAt: String = "", stat: DongleStat? = nil) {
        self.mac = mac; self.name = name; self.bleId = bleId; self.boundAt = boundAt
        self.lastSeenAt = lastSeenAt; self.lastKeyLock = lastKeyLock
        self.lastKeyAt = lastKeyAt; self.stat = stat
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mac = try c.decodeIfPresent(String.self, forKey: .mac) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        bleId = try c.decodeIfPresent(String.self, forKey: .bleId) ?? ""
        boundAt = try c.decodeIfPresent(String.self, forKey: .boundAt) ?? ""
        lastSeenAt = try c.decodeIfPresent(String.self, forKey: .lastSeenAt) ?? ""
        lastKeyLock = try c.decodeIfPresent(String.self, forKey: .lastKeyLock) ?? ""
        lastKeyAt = try c.decodeIfPresent(String.self, forKey: .lastKeyAt) ?? ""
        stat = try c.decodeIfPresent(DongleStat.self, forKey: .stat)
    }
}
struct DongleStat: Codable {
    var power: Int = -1
    var absPower: Int = -1
    var ekeyCount: Int = -1
    var ekeyAmount: Int = -1
    var firmware: String = ""
    var pid: Int = 0
    var eCtrl: String = ""
}

// ---------- 网关台账 ----------
struct Gateway: Codable, Identifiable {
    var mac: String
    var name: String = ""
    var pid: Int = 0
    var bleId: String = ""
    var boundAt: String = ""
    var wifimac: String = ""
    var romVer: String = ""
    var eCtrlVer: String = ""
    var ssid: String = ""
    var wifiIP: String = ""
    var netState: Int = -1
    var lastWifi: String = ""
    var provisionedAt: String = ""
    var id: String { mac }
}

// ---------- 配置记忆 ----------
struct DefendCfg: Codable {
    var control: Int
    var startSec: Int
    var endSec: Int
    var at: Double
}
struct TailgateCfg: Codable {
    var interval: Int
    var at: Double
}
struct OtpStatus: Codable {
    var on: Bool
    var at: Double
}
struct OtpIdx: Codable {
    var idx: Int
    var invalidTime: String
}

// ---------- 存储访问层 ----------
enum DB {
    static var store = Store.shared

    // 钥匙串 (多锁)
    static func keychains() -> [Keychain] {
        let map = store.getDict("kf_keychains")
        return map.values.compactMap { $0 as? [String: Any] }
            .compactMap { Keychain.fromDict($0) }
            .sorted { ($0.pairedAt) < ($1.pairedAt) }
    }
    static func keychain(_ mac: String) -> Keychain? {
        let m = mac.replacingOccurrences(of: ":", with: "").lowercased()
        let map = store.getDict("kf_keychains")
        if let d = map[m] as? [String: Any] { return Keychain.fromDict(d) }
        return nil
    }
    static func normalizeMac(_ m: String) -> String { m.replacingOccurrences(of: ":", with: "").lowercased() }
    static func saveKeychain(_ kc: Keychain) {
        var map = store.getDict("kf_keychains")
        map[normalizeMac(kc.mac)] = kc.toDict()   // 归一化: 防导入冒号/大写 MAC 造成重复条目
        store.set("kf_keychains", map)
        SpotlightKit.scheduleReindex()   // 293 锁的新增/改名/换型号都从这一支出, 索引跟着走
    }
    static func removeKeychain(_ mac: String) {
        var map = store.getDict("kf_keychains")
        map.removeValue(forKey: normalizeMac(mac))
        store.set("kf_keychains", map)
        SpotlightKit.scheduleReindex()   // 951 删掉的锁必须从 Spotlight 撤下来, 否则搜到点不开
    }
    // 删除设备: 钥匙串 + 每锁数据族 + 指针 (JS removeDevice 全量语义)
    static func removeDevice(_ mac: String) {
        let m = mac.replacingOccurrences(of: ":", with: "").lowercased()
        removeKeychain(m)
        for p in ["kf_ledger_", "kf_snap_", "kf_logcache_", "kf_defend_", "kf_tailgate_", "kf_synctime_", "otpStatus_", "otpIdx_", "kf_fevents_", "kf_lockmeta_", "kf_migok_",
                  "kf_batt_", "kf_batt_state_", "kf_mevents_", "kf_maint_", "kf_fwsince_", "kf_clock_notify_", "kf_damp_last_", "kf_fp_last_", "kf_care_notify_",
                  "kf_cbin_", "kf_cqueue_", "kf_cstar_", "kf_calert_", "kf_clists_", "kf_cseq_",
                  // 186/188 记录备注与标旗: 备注是用户写的自由文本 (可能含人名/地址), 必须随锁清除
                  "kf_rnote_", "kf_rflag_",
                  // 361 停用原因便签 (逐条, 只留最近 200 条)
                  "kf_cdisrea_",
                  "kf_linkrssi_", "kf_link_auto_"] {
            store.remove(p + m)
        }
        // 自动开锁每锁键 (kf_autocal_ / kf_autoopen_audit_ / kf_autoopen_suspend_until_, 尾段带 mac)
        for p in ["kf_autocal_", "kf_autoopen_audit_", "kf_autoopen_suspend_until_"] {
            store.remove(p + m)
        }
        // 包6 历史表键带 <mac>_ 段 (kf_chist_<mac>_...), 按前缀段整族清
        for p in ["kf_chist_" + m + "_"] {
            for k in store.keys() where k.hasPrefix(p) { store.remove(k) }
        }
        // 兜底清理 (审计 §6.6): 一批每锁键在 mac 之后**还带尾段**, 精确前缀删永远删不掉 ——
        // kf_calert_<mac>_<kind>_<key>、kf_cestudy_earlyexp_<mac>_<alias>、kf_cotp_t_/<mac>、
        // kf_cdraft_<mac>、kf_logarch_<mac>、kf_mborrow_/kf_mclaim_/kf_mig_lockact_<mac>、kf_offboard_<member> 等。
        // 判据: 键名里含本锁 MAC (大小写不敏感, 兼容 DemoKit 的大写 demoMac) 即属该锁数据族。
        let up = m.uppercased()
        for k in store.keys() where k.contains(m) || k.contains(up) { store.remove(k) }
        // 指针类全局键: 删除后不得悬空
        let defWasThis = store.getString("kf_default_mac") == m
        if defWasThis { store.remove("kf_default_mac") }
        if store.getString("kf_current_mac") == m { store.remove("kf_current_mac") }
        if store.getString("kf_last_device") == m { store.remove("kf_last_device") }
        // 766 手工顺序表是全局键 (mac 数组), 逐锁族前缀删够不着它 → 按元素剪, 否则会留下解绑锁的幽灵位
        var ord = store.get([String].self, "kf_lock_order") ?? []
        if ord.contains(m) {
            ord.removeAll { $0 == m }
            store.setCodable("kf_lock_order", ord)
            // 删掉的正好是首位 → 默认锁交棒给新的首位。不接这一棒, "第一行就是启动默认锁" (271/766)
            // 会一直断到用户下次动顺序为止, 而冷启动落点也悄悄退回"上次选中"。
            if defWasThis, let h = ord.first { store.set("kf_default_mac", h) }
        }
    }
    /// 子页默认锁: 优先用户当前所在锁 (且在台账里真实存在), 否则退回第一把。
    /// 旧写法各处直接 `DB.keychains().first?.mac` → 多锁时子页 (借用登记/791 认领/家政窗)
    /// 默认绑到最旧那把锁, 与用户当前锁不一致。
    static func preferredMac() -> String {
        let ks = keychains().map { $0.mac }
        return ks.contains(currentMac) ? currentMac : (ks.first ?? "")
    }
    static var currentMac: String {
        get { store.getString("kf_current_mac") }
        set { store.set("kf_current_mac", newValue) }
    }
    static var lastDevice: String {
        get { store.getString("kf_last_device") }
        set { store.set("kf_last_device", newValue) }
    }

    // 凭证台账
    /// 台账解码失败的锁 (防"解不出→空表写回"清空数据)
    static var ledgerCorrupt: Set<String> = []
    static func ledger(_ mac: String) -> Ledger {
        if let l = get(Ledger.self, "kf_ledger_" + mac) { return l }
        // get 返回 nil 有两种语义: ①该键不存在 (真空台账) ②有键但解码抛错 (字段缺任一即整表抛)。
        // 旧实现在 ②下返回空 Ledger, 调用方 (addPwd/addFp/…) 紧接着 save → **台账被空表整表覆盖清空**。
        if store.has("kf_ledger_" + mac) { ledgerCorrupt.insert(mac) }
        return Ledger()
    }
    static func saveLedger(_ mac: String, _ l: Ledger) {
        // 已判定为不可解的台账一律拒写: 宁可界面显示陈旧数据, 也不要把用户的密码/指纹记录抹掉
        guard !ledgerCorrupt.contains(mac) else { return }
        // 379/380: 台账写入唯一漏斗 — 前后比对出字段级 diff 入管理流水 (增删改/导入恢复全留痕)。
        // 此前 AuditLog().append 只在安全中心手动记账与失败守卫里调用, 而文案宣称"增删改会自动记入"。
        let old = get(Ledger.self, "kf_ledger_" + mac)
        set(l, "kf_ledger_" + mac)
        SpotlightKit.scheduleReindex()   // 951 凭证条目的增删改都过这一支, Spotlight 里不能留着已删的那条
        let changes = ledgerDiff(old, l)
        if !changes.isEmpty {
            let name = keychain(mac).map { LockArchive.displayName($0) } ?? mac
            // 391: 胁迫会话标记要走进**唯一漏斗**。此前 AuditLog.append 的 duress 形参默认 false
            // (AuditChain.swift:92)，而台账增删改全走这一行 → 胁迫码进来后改密码/删指纹的记录
            // 都不画橙条，橙条只出现在 markDuress 当场那一条"应用锁放行"上。
            // LockGuard.inDuressSession 这个读点此前全仓零消费者，就是这行漏传造成的。
            AuditLog().append(.admin, "改", target: name, diff: changes, duress: LockGuard.inDuressSession)
        }
    }
    /// 379/380: 台账前后 → [字段: [前, 后]]; 口令只记指纹前 4 位, 明文不落审计链
    static func ledgerDiff(_ old: Ledger?, _ new: Ledger) -> [String: [String]] {
        var d: [String: [String]] = [:]
        let op = old?.pwds ?? [], of = old?.fps ?? []
        for p in new.pwds {
            let tag = "密码#\(p.alias)"
            guard let o = op.first(where: { $0.alias == p.alias }) else { d[tag] = ["", "新增"]; continue }
            if o.pwd != p.pwd { d[tag + "·口令"] = [HashKit.fingerprint(o.pwd ?? ""), HashKit.fingerprint(p.pwd ?? "")] }
            if o.from != p.from || o.to != p.to { d[tag + "·有效期"] = [o.from + "~" + o.to, p.from + "~" + p.to] }
            if o.note != p.note { d[tag + "·备注"] = [o.note, p.note] }
            if o.owner != p.owner { d[tag + "·归属"] = [o.owner ?? "", p.owner ?? ""] }
        }
        for o in op where !new.pwds.contains(where: { $0.alias == o.alias }) { d["密码#\(o.alias)"] = ["删除", ""] }
        for f in new.fps {
            let tag = "指纹#\(f.batch)"
            guard let o = of.first(where: { $0.batch == f.batch }) else { d[tag] = ["", "新增"]; continue }
            if o.name != f.name { d[tag + "·名称"] = [o.name, f.name] }
            if o.note != f.note { d[tag + "·备注"] = [o.note, f.note] }
            if o.isAlarm != f.isAlarm { d[tag + "·防拆"] = [(o.isAlarm ?? false) ? "开" : "关", (f.isAlarm ?? false) ? "开" : "关"] }
        }
        for o in of where !new.fps.contains(where: { $0.batch == o.batch }) { d["指纹#\(o.batch)"] = ["删除", ""] }
        return d
    }
    static func listPwds(_ mac: String) -> [LedgerPwd] {
        ledger(mac).pwds.sorted { ($0.at) > ($1.at) }
    }
    static func listFps(_ mac: String) -> [LedgerFp] {
        ledger(mac).fps.sorted { ($0.at) > ($1.at) }
    }
    static func addPwd(_ mac: String, _ p: LedgerPwd) {
        var l = ledger(mac)
        l.pwds.removeAll { $0.alias == p.alias }
        l.pwds.append(p)
        saveLedger(mac, l)
    }
    static func delPwd(_ mac: String, _ alias: Int) {
        var l = ledger(mac)
        l.pwds.removeAll { $0.alias == alias }
        saveLedger(mac, l)
    }
    static func rePwd(_ mac: String, _ alias: Int, _ pwd: String) {
        var l = ledger(mac)
        for i in l.pwds.indices where l.pwds[i].alias == alias { l.pwds[i].pwd = pwd }
        saveLedger(mac, l)
    }
    static func setPwdPeriod(_ mac: String, _ alias: Int, _ from: String, _ to: String) {
        var l = ledger(mac)
        for i in l.pwds.indices where l.pwds[i].alias == alias { l.pwds[i].from = from; l.pwds[i].to = to }
        saveLedger(mac, l)
    }
    static func setPwdNote(_ mac: String, _ alias: Int, _ note: String) {
        var l = ledger(mac)
        for i in l.pwds.indices where l.pwds[i].alias == alias { l.pwds[i].note = note }
        saveLedger(mac, l)
    }
    static func setPwdOwner(_ mac: String, _ alias: Int, _ owner: String?) {
        var l = ledger(mac)
        for i in l.pwds.indices where l.pwds[i].alias == alias { l.pwds[i].owner = owner }
        saveLedger(mac, l)
    }
    static func addFp(_ mac: String, _ f: LedgerFp) {
        var l = ledger(mac)
        l.fps.removeAll { $0.batch == f.batch }
        l.fps.append(f)
        saveLedger(mac, l)
    }
    static func delFp(_ mac: String, _ batch: Int) {
        var l = ledger(mac)
        l.fps.removeAll { $0.batch == batch }
        saveLedger(mac, l)
    }
    static func renameFp(_ mac: String, _ batch: Int, _ name: String) {
        var l = ledger(mac)
        for i in l.fps.indices where l.fps[i].batch == batch { l.fps[i].name = name }
        saveLedger(mac, l)
    }
    static func setFpNote(_ mac: String, _ batch: Int, _ note: String) {
        var l = ledger(mac)
        for i in l.fps.indices where l.fps[i].batch == batch { l.fps[i].note = note }
        saveLedger(mac, l)
    }
    static func setFpOwner(_ mac: String, _ batch: Int, _ owner: String?) {
        var l = ledger(mac)
        for i in l.fps.indices where l.fps[i].batch == batch { l.fps[i].owner = owner }
        saveLedger(mac, l)
    }
    static func setFpAlarm(_ mac: String, _ batch: Int, _ on: Bool) {
        var l = ledger(mac)
        for i in l.fps.indices where l.fps[i].batch == batch { l.fps[i].isAlarm = on }
        saveLedger(mac, l)
    }
    // 包6 点查辅助 (版本历史/回收站/详情路由用)
    static func getPwd(_ mac: String, _ alias: Int) -> LedgerPwd? {
        ledger(mac).pwds.first { $0.alias == alias }
    }
    static func getFp(_ mac: String, _ batch: Int) -> LedgerFp? {
        ledger(mac).fps.first { $0.batch == batch }
    }
    static func getPwdList(_ aliases: [Int], _ mac: String) -> [LedgerPwd] {
        ledger(mac).pwds.filter { aliases.contains($0.alias) }
    }
    static func getFpList(_ batches: [Int], _ mac: String) -> [LedgerFp] {
        ledger(mac).fps.filter { batches.contains($0.batch) }
    }

    // 快照
    static func writeStatus(_ mac: String, _ st: LockStatus) {
        let d = StatusSnapshotData(
            rc: st.rc, powerLevel: st.powerLevel, firmware: st.firmware,
            lockTime: st.lockTime ?? 0, pinStock: st.pinStock, pwdStock: st.pwdStock, fpStock: st.fpStock,
            verifyMode: st.verifyMode, broadcastMode: st.broadcastMode, tempPwdMode: st.tempPwdMode,
            securityLevel: st.securityLevel, sKeyStatus: st.sKeyStatus,
            zotpPeriod: st.zotpPeriod > 0 ? st.zotpPeriod : nil,
            pinCap: st.pinInfoCapacity > 0 ? st.pinInfoCapacity : nil,
            pwdCap: st.pwdInfoCapacity > 0 ? st.pwdInfoCapacity : nil,
            fpCap: st.fpInfoCapacity > 0 ? st.fpInfoCapacity : nil)
        set(StatusSnapshot(at: Date().timeIntervalSince1970 * 1000, status: d), "kf_snap_" + mac)
    }
    static func readStatus(_ mac: String) -> StatusSnapshotData? {
        get(StatusSnapshot.self, "kf_snap_" + mac)?.status
    }
    /// 包2/125 最后已知状态: 快照采样时刻 (信封 at), 断连展示"数据截至 14:32 · 缓存"用
    static func statusTime(_ mac: String) -> Double {
        get(StatusSnapshot.self, "kf_snap_" + mac)?.at ?? 0
    }
    static func writeLogs(_ mac: String, _ logs: [LogEntry]) {
        var cache = get(LogCache.self, "kf_logcache_" + mac) ?? LogCache(at: 0, logs: [])
        cache.at = Date().timeIntervalSince1970 * 1000
        var seen = Set<String>()
        var merged = [CachedLog]()
        for l in (logs.map { CachedLog(type: $0.type, typeName: $0.typeName, idxRaw: $0.idxRaw, lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr) } + cache.logs) {
            let k = String(l.idxRaw)
            if seen.contains(k) { continue }
            seen.insert(k)
            merged.append(l)
            if merged.count >= 300 { break }
        }
        cache.logs = merged
        set(cache, "kf_logcache_" + mac)
        HotCache.invalidate(mac)   // 220: 唯一写入口失效热点缓存 (DiagKit 里那句"要接得先定失效策略"定在这)
    }
    static func readLogs(_ mac: String) -> [CachedLog] {
        get(LogCache.self, "kf_logcache_" + mac)?.logs ?? []
    }
    /// 223: 缓存**替换**写入 (不并回旧份)。writeLogs 的语义是 `新 + 旧缓存` 按 idxRaw 去重合并,
    /// 那是给"锁端只回增量"的抓取用的；归档要的是"把这几行从缓存里移走"，用 writeLogs 就等于
    /// 只写了归档侧、缓存里的旧行一条没少 —— "移入"变成"复制"，下一轮还会把同批再归档一遍。
    static func replaceLogs(_ mac: String, _ logs: [CachedLog]) {
        var seen = Set<String>()
        var kept = [CachedLog]()
        for l in logs {
            let k = String(l.idxRaw)
            if seen.contains(k) { continue }
            seen.insert(k)
            kept.append(l)
            if kept.count >= 300 { break }
        }
        set(LogCache(at: Date().timeIntervalSince1970 * 1000, logs: kept), "kf_logcache_" + mac)
        HotCache.invalidate(mac)   // 220: 替换写入同属写入口, 一样作废
    }

    // 配置记忆
    static func defend(_ mac: String) -> DefendCfg? { get(DefendCfg.self, "kf_defend_" + mac) }
    static func saveDefend(_ mac: String, _ c: DefendCfg) { set(c, "kf_defend_" + mac) }
    static func tailgate(_ mac: String) -> TailgateCfg? { get(TailgateCfg.self, "kf_tailgate_" + mac) }
    static func saveTailgate(_ mac: String, _ c: TailgateCfg) { set(c, "kf_tailgate_" + mac) }
    static func syncTime(_ mac: String) -> Double { store.get("kf_synctime_" + mac, Double.self) ?? 0 }
    static func saveSyncTime(_ mac: String, _ t: Double) { store.set("kf_synctime_" + mac, t) }
    // 靠近自动开锁 (AUTOOPEN-PLAN)：**唯一一份**读写口径在 App/Core/AutoOpen.swift
    // (`AutoOpen.on` / `AutoOpen.faceTier` / `suspendUntil` / `AuditEntry`)。这里曾有四个入口：
    // autoOpenAudit(_:) 用 getDict 取一个存 [AuditEntry] JSON 的键 (类型就不对，取回来必然是空)、
    // autoOpenSuspendUntil(_:) 与 AutoOpen.suspendUntil 逐字重复 —— 那两个先删了；
    // `autoOpen` / `autoOpenFaceTier` 是同一对键的第二处读写入口且全仓零调用
    // (grep `DB.autoOpen\b`、`DB.autoOpenFaceTier` 皆空)，第一百七十一批按同一条理由一并删掉。
    // 留着就是"看着像另一条读法"的假入口：改档位语义时只会改到其中一处，两份默认值也就各自漂 (§10.43)。
    static func otpStatus(_ mac: String) -> OtpStatus? { get(OtpStatus.self, "otpStatus_" + mac) }
    static func saveOtpStatus(_ mac: String, _ s: OtpStatus) { set(s, "otpStatus_" + mac) }
    static func otpIdx(_ mac: String) -> OtpIdx? { get(OtpIdx.self, "otpIdx_" + mac) }
    static func saveOtpIdx(_ mac: String, _ i: OtpIdx) { set(i, "otpIdx_" + mac) }


    // 成员
    static func members() -> [Member] {
        let map = store.getDict("kf_members")
        return map.values.compactMap { $0 as? [String: Any] }.compactMap(Member.fromDict)
    }
    static func member(_ id: String?) -> Member? {
        guard let id else { return nil }
        return members().first { $0.id == id }
    }
    /// 259 新成员建档色板: 与 DS 主题表 dark 档的六个 accent 同色号 (靛蓝/绿/琥珀/玫瑰/青/石墨),
    /// 头像与矩阵圆点的读侧照旧只认 hex 字段; 超过六人从头轮转。
    static let memberPalette = ["#818CF8", "#4ADE80", "#F59E0B", "#FB7185", "#22D3EE", "#94A3B8"]
    static func addMember(_ name: String) -> Member? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty || members().contains(where: { $0.name == n }) { return nil }
        let m = Member(id: UUID().uuidString.prefix(8).description, name: n,
                       color: memberPalette[members().count % memberPalette.count],   // 259: 建档即分配, 不再全员品牌靛蓝
                       at: Date().timeIntervalSince1970 * 1000)
        var map = store.getDict("kf_members")
        map[m.id] = m.toDict()
        store.set("kf_members", map)
        return m
    }
    static func renameMember(_ id: String, _ name: String) {
        var map = store.getDict("kf_members")
        if var d = map[id] as? [String: Any] { d["name"] = name; map[id] = d }
        store.set("kf_members", map)
    }
    static func setMemberInfo(_ id: String, _ info: [String: String]) {
        var map = store.getDict("kf_members")
        if var d = map[id] as? [String: Any] {
            for (k, v) in info where !v.isEmpty { d[k] = v }
            map[id] = d
        }
        store.set("kf_members", map)
    }
    static func removeMember(_ id: String) {
        var map = store.getDict("kf_members")
        map.removeValue(forKey: id)
        store.set("kf_members", map)
        // 解除全部台账归属 (凭证保留)
        for kc in keychains() {
            var l = ledger(kc.mac)
            var changed = false
            for i in l.pwds.indices where l.pwds[i].owner == id { l.pwds[i].owner = nil; changed = true }
            for i in l.fps.indices where l.fps[i].owner == id { l.fps[i].owner = nil; changed = true }
            if changed { saveLedger(kc.mac, l) }
        }
    }

    // 钥匙串硬件
    static func dongles() -> [Dongle] {
        let map = store.getDict("kf_keychain_dongles")
        return map.values.compactMap { $0 as? [String: Any] }.compactMap(Dongle.fromDict)
    }
    static func dongle(_ mac: String) -> Dongle? {
        let m = mac.replacingOccurrences(of: ":", with: "").lowercased()
        if let d = store.getDict("kf_keychain_dongles")[m] as? [String: Any] { return Dongle.fromDict(d) }
        return nil
    }
    static func saveDongle(_ d: Dongle) {
        var map = store.getDict("kf_keychain_dongles")
        var merged = d
        if let old = dongle(d.mac) {
            merged = Dongle(mac: d.mac,
                            name: d.name.isEmpty ? old.name : d.name,
                            bleId: d.bleId.isEmpty ? old.bleId : d.bleId,
                            boundAt: d.boundAt.isEmpty ? old.boundAt : d.boundAt,
                            lastSeenAt: d.lastSeenAt.isEmpty ? old.lastSeenAt : d.lastSeenAt,
                            lastKeyLock: d.lastKeyLock.isEmpty ? old.lastKeyLock : d.lastKeyLock,
                            lastKeyAt: d.lastKeyAt.isEmpty ? old.lastKeyAt : d.lastKeyAt,
                            stat: d.stat ?? old.stat)
        }
        map[merged.mac] = merged.toDict()
        store.set("kf_keychain_dongles", map)
    }
    static func removeDongle(_ mac: String) {
        var map = store.getDict("kf_keychain_dongles")
        map.removeValue(forKey: mac.replacingOccurrences(of: ":", with: "").lowercased())
        store.set("kf_keychain_dongles", map)
    }

    // 网关
    static func gateways() -> [Gateway] {
        let map = store.getDict("kf_gateways")
        return map.values.compactMap { $0 as? [String: Any] }.compactMap(Gateway.fromDict)
    }
    static func gateway(_ mac: String) -> Gateway? {
        let m = mac.replacingOccurrences(of: ":", with: "").lowercased()
        if let d = store.getDict("kf_gateways")[m] as? [String: Any] { return Gateway.fromDict(d) }
        return nil
    }
    static func saveGateway(_ g: Gateway) {
        var map = store.getDict("kf_gateways")
        var merged = g
        if let old = gateway(g.mac) {
            merged = Gateway(mac: g.mac,
                             name: g.name.isEmpty ? old.name : g.name,
                             pid: g.pid != 0 ? g.pid : old.pid,
                             bleId: g.bleId.isEmpty ? old.bleId : g.bleId,
                             boundAt: g.boundAt.isEmpty ? old.boundAt : g.boundAt,
                             wifimac: g.wifimac.isEmpty ? old.wifimac : g.wifimac,
                             romVer: g.romVer.isEmpty ? old.romVer : g.romVer,
                             eCtrlVer: g.eCtrlVer.isEmpty ? old.eCtrlVer : g.eCtrlVer,
                             ssid: g.ssid.isEmpty ? old.ssid : g.ssid,
                             wifiIP: g.wifiIP.isEmpty ? old.wifiIP : g.wifiIP,
                             netState: g.netState != -1 ? g.netState : old.netState,
                             lastWifi: g.lastWifi.isEmpty ? old.lastWifi : g.lastWifi,
                             provisionedAt: g.provisionedAt.isEmpty ? old.provisionedAt : g.provisionedAt)
        }
        map[merged.mac] = merged.toDict()
        store.set("kf_gateways", map)
    }
    static func removeGateway(_ mac: String) {
        var map = store.getDict("kf_gateways")
        map.removeValue(forKey: mac.replacingOccurrences(of: ":", with: "").lowercased())
        store.set("kf_gateways", map)
    }

    // 门禁 (utils/passcode.js)
    static func hasPasscode() -> Bool {
        get([String: String].self, "kf_passcode") != nil
    }
    /// 门禁口令摘要轮数 (PBKDF2-HMAC-SHA256)
    static let pcIter = 60_000
    static func passcodeDigest(_ pw: String) -> [String: String] {
        let salt = String(UUID().uuidString.prefix(8))
        return passcodeRecord(pw, salt: salt)
    }
    /// 同时写强摘要 d2 与旧 FNV 摘要 d:
    /// d 保留是为了向后兼容 (跨端迁移与旧备份包只带 s/d), 不是主验证路径。
    private static func passcodeRecord(_ pw: String, salt: String) -> [String: String] {
        ["s": salt, "d": fnv1a32(salt + pw), "d2": pcStrong(pw, salt: salt)]
    }
    private static func pcStrong(_ pw: String, salt: String) -> String {
        CryptoBox.pbkdf2(pw, salt: Array(salt.utf8), iterations: pcIter, dkLen: 32)
            .map { String(format: "%02x", $0) }.joined()
    }
    static func fnv1a32(_ s: String) -> String {
        var hash: UInt32 = 0x811c9dc5
        for ch in Array(s.utf8) {
            hash ^= UInt32(ch)
            hash = hash &* 0x01000193
        }
        return String(hash, radix: 16)
    }
    static func verifyPasscode(_ pw: String) -> Bool {
        guard let rec = get([String: String].self, "kf_passcode") else { return false }
        let salt = rec["s"] ?? ""
        // 主路径: PBKDF2。旧版只有 32bit 零迭代的 fnv1a32(salt+pw) —
        // 4 位数字码 10^4 次即可穷举, 2^32 空间也能生日碰撞伪造, 故必须换强摘要。
        if let strong = rec["d2"], !strong.isEmpty {
            return pcStrong(pw, salt: salt) == strong
        }
        // 只有旧摘要的历史库: 按旧口径验, 验过即静默升级 (无感迁移, 不会把老用户锁在外面)
        guard rec["d"] == fnv1a32(salt + pw) else { return false }
        set(passcodeRecord(pw, salt: salt), "kf_passcode")
        return true
    }
    static func setPasscode(_ pw: String?) {
        if let pw { set(passcodeDigest(pw), "kf_passcode") } else { store.remove("kf_passcode") }
    }

    // ---------- 包1 (idea 92): 开锁失败的本地时间线标记 ----------
    // 与锁端日志缓存 (kf_logcache_, 随 cmd16 同步整表覆写) 严格分开, 绝不混入锁日志;
    // 时间线是回溯线索不是台账, 每锁封顶 50 条。
    struct FailEvent: Codable {
        var ts: Double    // 手机侧时间 (Unix 秒)
        var msg: String   // 失败原因 (rcFriendly / 异常文案)
        // 86 失败快照三要素: 失败当时的信号/电量/错误码。
        // **可选是刻意的** —— 本机已存的旧记录没有这三个键, 写成非可选会让整份数组解码失败, 老留痕全丢。
        var rssi: Int? = nil
        var pct: Int? = nil
        var rc: Int? = nil
    }
    static func failEvents(_ mac: String) -> [FailEvent] {
        get([FailEvent].self, "kf_fevents_" + mac) ?? []
    }
    static func recordFailEvent(_ mac: String, _ msg: String,
                                rssi: Int? = nil, pct: Int? = nil, rc: Int? = nil) {
        var list = failEvents(mac)
        list.insert(FailEvent(ts: Date().timeIntervalSince1970, msg: msg, rssi: rssi, pct: pct, rc: rc), at: 0)
        if list.count > 50 { list = Array(list.prefix(50)) }
        set(list, "kf_fevents_" + mac)
    }
    /// 清空本机开锁失败标记 (kf_fevents_)。入口在记录页"失败"筛选下 (拍板 #5, 2026-10-09)：
    /// 必须走 `confirmDestructive` 二次确认, 且确认文案要写清"这些标记会以「失败」行混进时间线 (92), 清掉=那些行消失",
    /// 同时说清它**不解除**任何冷却/挂起、不动锁端日志 —— 否则容易被当成"开锁失败的总开关"。
    /// 自然清理路径仍在: 每锁 50 条滚动上限 + DB.removeDevice 按族清, 不会无限增长。
    static func clearFailEvents(_ mac: String) { store.remove("kf_fevents_" + mac) }

    static func get<T: Decodable>(_ t: T.Type, _ k: String) -> T? {
        Store.shared.get(k, t)
    }
    /// 跨文件写 Codable 的唯一入口 (参数序 = 值在前、键在后, 与内部 set 一致)
    static func setCodable<T: Encodable>(_ v: T, _ k: String) {
        Store.shared.setCodable(k, v)
    }
    private static func set<T: Encodable>(_ v: T, _ k: String) {
        Store.shared.setCodable(k, v)
    }
}

// ---------- Codable ↔ [String: Any] 桥 (小程序的 Map 结构) ----------
extension Keychain {
    static func fromDict(_ d: [String: Any]) -> Keychain? { Keychain(fromDict: d) }
    init?(fromDict d: [String: Any]) {
        guard let mac = d["mac"] as? String, let skey = d["skey"] as? String else { return nil }
        self.mac = mac
        self.skey = skey
        self.version = d["version"] as? Int ?? 1
        self.pid = d["pid"] as? Int ?? 0
        self.pidName = d["pidName"] as? String ?? ""
        self.name = d["name"] as? String ?? ""
        self.bkey = d["bkey"] as? String ?? ""
        self.pins = d["pins"] as? [String] ?? []
        self.ekey = d["ekey"] as? String ?? ""
        self.trackid = d["trackid"] as? String ?? ""
        self.bleId = d["bleId"] as? String ?? ""
        self.fw = d["fw"] as? String ?? ""
        self.pairedAt = d["pairedAt"] as? String ?? ""
    }
    func toDict() -> [String: Any] {
        var d: [String: Any] = ["version": version, "mac": mac, "pid": pid, "pidName": pidName, "skey": skey]
        if !name.isEmpty { d["name"] = name }
        if !bkey.isEmpty { d["bkey"] = bkey }
        if !pins.isEmpty { d["pins"] = pins }
        if !ekey.isEmpty { d["ekey"] = ekey }
        if !trackid.isEmpty { d["trackid"] = trackid }
        if !bleId.isEmpty { d["bleId"] = bleId }
        if !fw.isEmpty { d["fw"] = fw }
        if !pairedAt.isEmpty { d["pairedAt"] = pairedAt }
        return d
    }
}
extension Member {
    static func fromDict(_ d: [String: Any]) -> Member? { Member(fromDict: d) }
    init?(fromDict d: [String: Any]) {
        guard let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
        self.id = id; self.name = name
        self.relation = d["relation"] as? String ?? ""
        self.phone = d["phone"] as? String ?? ""
        self.color = d["color"] as? String ?? "#3D8BFF"
        self.at = d["at"] as? Double ?? 0
    }
    func toDict() -> [String: Any] {
        ["id": id, "name": name, "relation": relation, "phone": phone, "color": color, "at": at]
    }
}
extension Dongle {
    static func fromDict(_ d: [String: Any]) -> Dongle? { Dongle(fromDict: d) }
    init?(fromDict d: [String: Any]) {
        guard let mac = d["mac"] as? String else { return nil }
        self.mac = mac
        self.name = d["name"] as? String ?? ""
        self.bleId = d["bleId"] as? String ?? ""
        self.boundAt = d["boundAt"] as? String ?? ""
        self.lastSeenAt = d["lastSeenAt"] as? String ?? ""
        self.lastKeyLock = d["lastKeyLock"] as? String ?? ""
        self.lastKeyAt = d["lastKeyAt"] as? String ?? ""
        if let s = d["stat"] as? [String: Any] {
            self.stat = DongleStat(power: s["power"] as? Int ?? -1, absPower: s["absPower"] as? Int ?? -1,
                                   ekeyCount: s["ekeyCount"] as? Int ?? -1, ekeyAmount: s["ekeyAmount"] as? Int ?? -1,
                                   firmware: s["firmware"] as? String ?? "", pid: s["pid"] as? Int ?? 0,
                                   eCtrl: s["eCtrl"] as? String ?? "")
        }
    }
    func toDict() -> [String: Any] {
        var d: [String: Any] = ["mac": mac]
        if !name.isEmpty { d["name"] = name }
        if !bleId.isEmpty { d["bleId"] = bleId }
        if !boundAt.isEmpty { d["boundAt"] = boundAt }
        if !lastSeenAt.isEmpty { d["lastSeenAt"] = lastSeenAt }
        if !lastKeyLock.isEmpty { d["lastKeyLock"] = lastKeyLock }
        if !lastKeyAt.isEmpty { d["lastKeyAt"] = lastKeyAt }
        if let s = stat {
            d["stat"] = ["power": s.power, "absPower": s.absPower, "ekeyCount": s.ekeyCount,
                         "ekeyAmount": s.ekeyAmount, "firmware": s.firmware, "pid": s.pid, "eCtrl": s.eCtrl]
        }
        return d
    }
}
extension Gateway {
    static func fromDict(_ d: [String: Any]) -> Gateway? { Gateway(fromDict: d) }
    init?(fromDict d: [String: Any]) {
        guard let mac = d["mac"] as? String else { return nil }
        self.mac = mac
        self.name = d["name"] as? String ?? ""
        self.pid = d["pid"] as? Int ?? 0
        self.bleId = d["bleId"] as? String ?? ""
        self.boundAt = d["boundAt"] as? String ?? ""
        self.wifimac = d["wifimac"] as? String ?? ""
        self.romVer = d["romVer"] as? String ?? ""
        self.eCtrlVer = d["eCtrlVer"] as? String ?? ""
        self.ssid = d["ssid"] as? String ?? ""
        self.wifiIP = d["wifiIP"] as? String ?? ""
        self.netState = d["netState"] as? Int ?? -1
        self.lastWifi = d["lastWifi"] as? String ?? ""
        self.provisionedAt = d["provisionedAt"] as? String ?? ""
    }
    func toDict() -> [String: Any] {
        ["mac": mac, "name": name, "pid": pid, "bleId": bleId, "boundAt": boundAt, "wifimac": wifimac,
         "romVer": romVer, "eCtrlVer": eCtrlVer, "ssid": ssid, "wifiIP": wifiIP, "netState": netState,
         "lastWifi": lastWifi, "provisionedAt": provisionedAt]
    }
}