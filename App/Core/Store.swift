// 本地存储与数据模型 — JS utils/store.js + services/{ledger,snapshot,keychain,gateway,members}.js 移植
// 存储键与小程序完全一致 (kf_*), 便于全量备份跨端互换
import Foundation

// ---------- 存储 ----------
final class Store {
    static let shared = Store()
    private let defaults = UserDefaults.standard
    private func key(_ k: String) -> String { "kf." + k }
    func get<T: Decodable>(_ k: String, _ type: T.Type) -> T? {
        guard let d = defaults.data(forKey: key(k)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
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
        if let d = try? JSONSerialization.data(withJSONObject: v) { defaults.set(d, forKey: key(k)) }
    }
    func setCodable<T: Encodable>(_ k: String, _ v: T) {
        if let d = try? JSONEncoder().encode(v) { defaults.set(d, forKey: key(k)) }
    }
    func remove(_ k: String) { defaults.removeObject(forKey: key(k)) }
    func keys() -> [String] {
        defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("kf.") }.map { String($0.dropFirst(3)) }
    }
    func clearAll() { for k in keys() { remove(k) } }
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
    var at: Double
    var pwd: String?
    var owner: String?
    var note: String
    var id: Int { alias }
}
struct LedgerFp: Codable, Identifiable {
    var batch: Int
    var name: String
    var at: Double
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
    }
    static func removeKeychain(_ mac: String) {
        var map = store.getDict("kf_keychains")
        map.removeValue(forKey: normalizeMac(mac))
        store.set("kf_keychains", map)
    }
    // 删除设备: 钥匙串 + 每锁数据族 + 指针 (JS removeDevice 全量语义)
    static func removeDevice(_ mac: String) {
        let m = mac.replacingOccurrences(of: ":", with: "").lowercased()
        removeKeychain(m)
        for p in ["kf_ledger_", "kf_snap_", "kf_logcache_", "kf_defend_", "kf_tailgate_", "kf_synctime_", "otpStatus_", "otpIdx_", "kf_fevents_", "kf_lockmeta_", "kf_migok_",
                  "kf_batt_", "kf_batt_state_", "kf_mevents_", "kf_maint_", "kf_fwsince_", "kf_clock_notify_", "kf_damp_last_", "kf_fp_last_", "kf_care_notify_",
                  "kf_cbin_", "kf_cqueue_", "kf_cstar_", "kf_calert_", "kf_clists_", "kf_cseq_",
                  "kf_linkrssi_", "kf_link_auto_"] {
            store.remove(p + m)
        }
        // 包6 历史表键带 <mac>_ 段 (kf_chist_<mac>_...), 按前缀段整族清
        for p in ["kf_chist_" + m + "_"] {
            for k in store.keys() where k.hasPrefix(p) { store.remove(k) }
        }
        if store.getString("kf_current_mac") == m { store.remove("kf_current_mac") }
        if store.getString("kf_last_device") == m { store.remove("kf_last_device") }
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
    static func ledger(_ mac: String) -> Ledger {
        get(Ledger.self, "kf_ledger_" + mac) ?? Ledger()
    }
    static func saveLedger(_ mac: String, _ l: Ledger) { set(l, "kf_ledger_" + mac) }
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
    }
    static func readLogs(_ mac: String) -> [CachedLog] {
        get(LogCache.self, "kf_logcache_" + mac)?.logs ?? []
    }

    // 配置记忆
    static func defend(_ mac: String) -> DefendCfg? { get(DefendCfg.self, "kf_defend_" + mac) }
    static func saveDefend(_ mac: String, _ c: DefendCfg) { set(c, "kf_defend_" + mac) }
    static func tailgate(_ mac: String) -> TailgateCfg? { get(TailgateCfg.self, "kf_tailgate_" + mac) }
    static func saveTailgate(_ mac: String, _ c: TailgateCfg) { set(c, "kf_tailgate_" + mac) }
    static func syncTime(_ mac: String) -> Double { store.get("kf_synctime_" + mac, Double.self) ?? 0 }
    static func saveSyncTime(_ mac: String, _ t: Double) { store.set("kf_synctime_" + mac, t) }
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
    static func addMember(_ name: String) -> Member? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty || members().contains(where: { $0.name == n }) { return nil }
        let m = Member(id: UUID().uuidString.prefix(8).description, name: n, at: Date().timeIntervalSince1970 * 1000)
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
    static func passcodeDigest(_ pw: String) -> [String: String] {
        let salt = String(UUID().uuidString.prefix(8))
        return ["s": salt, "d": fnv1a32(salt + pw)]
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
        return rec["d"] == fnv1a32((rec["s"] ?? "") + pw)
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
    }
    static func failEvents(_ mac: String) -> [FailEvent] {
        get([FailEvent].self, "kf_fevents_" + mac) ?? []
    }
    static func recordFailEvent(_ mac: String, _ msg: String) {
        var list = failEvents(mac)
        list.insert(FailEvent(ts: Date().timeIntervalSince1970, msg: msg), at: 0)
        if list.count > 50 { list = Array(list.prefix(50)) }
        set(list, "kf_fevents_" + mac)
    }
    static func clearFailEvents(_ mac: String) { store.remove("kf_fevents_" + mac) }

    static func get<T: Decodable>(_ t: T.Type, _ k: String) -> T? {
        Store.shared.get(k, t)
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