// 数据模型 · Keychain / LedgerPwd / LedgerFp / Ledger / Member / StatusSnapshot / LogCache / Dongle / Gateway / DefendCfg / TailgateCfg / OtpStatus
// 2026-10-29 从 Store.swift（1145 行）拆出。
// 纯 Codable 定义 + 各模型的便利扩展，不含任何 DB 访问逻辑。
import Foundation

struct Keychain: Codable, Identifiable {
    var version: Int = 1
    var mac: String
    var pid: Int = 0
    var pidName: String = ""
    /// 2026-10-27 审核说明 (AUDIT-A F-29)：本仓 `Keychain` 比 vendor 多一个 `name` 字段 ——
    /// 那是给多锁用户起名用的（vendor 单锁，用不上）。备份包里它随包走，
    /// 跨端迁移时 vendor 侧会忽略这个字段，不影响互操作。
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
    // 2026-10-27 审核说明 (AUDIT-A F-33)：`at` 字段有两种单位 ——
    // `LedgerPwd.at` / `LedgerFp.at` 是**毫秒**，`CredBinEntry.at` / `CredSnapshot.at` 是**秒**。
    // 这是历史包袱（两族数据不同时期引入）。**不要统一** —— 改了会让老备份解析错位。
    var at: Double          // epoch **毫秒**
    var pwd: String?
    var owner: String?
    var note: String
    var id: Int { alias }

    enum CodingKeys: String, CodingKey { case alias, from, to, temp, at, pwd, owner, note }

    init(alias: Int, from: String, to: String, temp: Bool, at: Double,
         pwd: String?, owner: String?, note: String) {
        self.alias = alias; self.from = from; self.to = to; self.temp = temp
        self.at = at; self.pwd = pwd; self.owner = owner; self.note = note
    }

    /// 容错解码（2026-10-29）：**缺字段回落默认值**，而不是整份 ledger 解不出。
    ///
    /// 合成解码器对非 Optional 字段要求键必须存在；而这两个 struct 的字段几乎全是非 Optional。
    /// 于是「新增一个字段」或「导入不完全的旧备份」就会让整份 Ledger 解码失败 →
    /// 触发 markLedgerCorrupt → 整个会话里所有凭证写入（含备份恢复的导入）被静默拒绝。
    /// 这就是上一轮那两个「损坏标记永不清除」Bug 的**根因**，在这里堵掉。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        alias = try c.decodeIfPresent(Int.self, forKey: .alias) ?? 0
        from = try c.decodeIfPresent(String.self, forKey: .from) ?? ""
        to = try c.decodeIfPresent(String.self, forKey: .to) ?? ""
        temp = try c.decodeIfPresent(Bool.self, forKey: .temp) ?? false
        at = try c.decodeIfPresent(Double.self, forKey: .at) ?? 0
        pwd = try c.decodeIfPresent(String.self, forKey: .pwd)
        owner = try c.decodeIfPresent(String.self, forKey: .owner)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}
struct LedgerFp: Codable, Identifiable {
    var batch: Int
    var name: String
    var at: Double          // epoch **毫秒** (与 `LedgerPwd.at` 同约定)
    var note: String
    /// 锁端要 UInt32 批次号, 台账里是 Int, 而导入链 (BackupKit.restoreAll / BackupStudioKit 解码与合账)
    /// **不校验符号与上界**。`UInt32(-1)` 在 Swift 里是 **trap** (不是 nil、不是异常) ⇒
    /// 构造/损坏一份含 {"batch": -1} 或超大的备份导进去, 用户在凭证页点一下「删除」进程当场崩。
    var batchU32: UInt32? { (batch >= 0 && batch <= Int(UInt32.max)) ? UInt32(batch) : nil }
    var src: String?
    var owner: String?
    var isAlarm: Bool?
    var id: Int { batch }

    enum CodingKeys: String, CodingKey { case batch, name, at, note, src, owner, isAlarm }

    init(batch: Int, name: String, at: Double, note: String,
         src: String?, owner: String?, isAlarm: Bool?) {
        self.batch = batch; self.name = name; self.at = at; self.note = note
        self.src = src; self.owner = owner; self.isAlarm = isAlarm
    }

    /// 容错解码 —— 理由同 `LedgerPwd.init(from:)`。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        batch = try c.decodeIfPresent(Int.self, forKey: .batch) ?? 0
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        at = try c.decodeIfPresent(Double.self, forKey: .at) ?? 0
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        src = try c.decodeIfPresent(String.self, forKey: .src)
        owner = try c.decodeIfPresent(String.self, forKey: .owner)
        isAlarm = try c.decodeIfPresent(Bool.self, forKey: .isAlarm)
    }
}
/// 逐元素容错：数组里某个元素解不出时**跳过它**，不连累整个数组。
/// 用途见 `Ledger.init(from:)` —— 一条坏记录不该让整份台账变成"不可解"。
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

struct Ledger: Codable {
    var pwds: [LedgerPwd] = []
    var fps: [LedgerFp] = []

    enum CodingKeys: String, CodingKey { case pwds, fps }

    init(pwds: [LedgerPwd] = [], fps: [LedgerFp] = []) {
        self.pwds = pwds
        self.fps = fps
    }

    /// 容错解码（2026-10-29）：缺键回落空数组；单个元素坏掉只丢那一条。
    /// 原合成的解码器要求 `pwds`/`fps` 两个键都存在，且任一元素坏掉就整份失败 ——
    /// 那会直接触发 `markLedgerCorrupt`，让整个会话的凭证写入被拒。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let p = (try? c.decodeIfPresent([Lossy<LedgerPwd>].self, forKey: .pwds)) ?? nil
        pwds = (p ?? []).compactMap { $0.value }
        let f = (try? c.decodeIfPresent([Lossy<LedgerFp>].self, forKey: .fps)) ?? nil
        fps = (f ?? []).compactMap { $0.value }
    }
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

    enum CodingKeys: String, CodingKey { case id, name, relation, phone, color, at }

    init(id: String, name: String, relation: String = "", phone: String = "",
         color: String = "#3D8BFF", at: Double = 0) {
        self.id = id; self.name = name; self.relation = relation; self.phone = phone
        self.color = color; self.at = at
    }

    /// 容错解码：成员档案是备份/台账的共同底座，缺一个字段不该让整条成员消失。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        relation = try c.decodeIfPresent(String.self, forKey: .relation) ?? ""
        phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? "#3D8BFF"
        at = try c.decodeIfPresent(Double.self, forKey: .at) ?? 0
    }
}

// ---------- 快照 (services/snapshot.js) ----------
struct StatusSnapshot: Codable {
    var at: Double
    var status: StatusSnapshotData

    enum CodingKeys: String, CodingKey { case at, status }

    init(at: Double, status: StatusSnapshotData) { self.at = at; self.status = status }

    /// 容错解码（2026-10-29）：缺字段回落默认值。
    /// 合成解码器对非 Optional 字段要求键必须存在 —— 持久化模型都靠"加字段不破坏老数据"演进，
    /// 所以凡是走 `get(...)` / `setCodable(...)` 的模型都显式写一份。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        at = try c.decodeIfPresent(Double.self, forKey: .at) ?? 0
        status = try c.decodeIfPresent(StatusSnapshotData.self, forKey: .status) ?? .init()
    }
}
    /// 2026-10-27 审核说明 (AUDIT-A F-31)：本仓 `StatusSnapshotData` 只存状态对象的**子集**
    /// （rc/pid/电量/锁钟/固件版本等界面要用的），而 vendor 存整个 status 对象。
    /// 差异不影响功能：本仓用到哪几项就存哪几项，省 UserDefaults 空间。
struct StatusSnapshotData: Codable, Equatable {
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

    enum CodingKeys: String, CodingKey { case rc, powerLevel, firmware, lockTime, pinStock, pwdStock, fpStock, verifyMode, broadcastMode, tempPwdMode, securityLevel, sKeyStatus, zotpPeriod, pinCap, pwdCap, fpCap }

    init(rc: Int = 0, powerLevel: Int = 0, firmware: String = "", lockTime: Int64 = 0,
         pinStock: Int = 0, pwdStock: Int = 0, fpStock: Int = 0, verifyMode: Int = 0,
         broadcastMode: Int = 0, tempPwdMode: Int = 0, securityLevel: Int = 0, sKeyStatus: Int = 0,
         zotpPeriod: Int? = nil, pinCap: Int? = nil, pwdCap: Int? = nil, fpCap: Int? = nil) {
        self.rc = rc; self.powerLevel = powerLevel; self.firmware = firmware; self.lockTime = lockTime
        self.pinStock = pinStock; self.pwdStock = pwdStock; self.fpStock = fpStock
        self.verifyMode = verifyMode; self.broadcastMode = broadcastMode; self.tempPwdMode = tempPwdMode
        self.securityLevel = securityLevel; self.sKeyStatus = sKeyStatus
        self.zotpPeriod = zotpPeriod; self.pinCap = pinCap; self.pwdCap = pwdCap; self.fpCap = fpCap
    }

    /// 容错解码（2026-10-29）：缺字段回落默认值。
    /// 合成解码器对非 Optional 字段要求键必须存在 —— 持久化模型都靠"加字段不破坏老数据"演进，
    /// 所以凡是走 `get(...)` / `setCodable(...)` 的模型都显式写一份。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rc = try c.decodeIfPresent(Int.self, forKey: .rc) ?? 0
        powerLevel = try c.decodeIfPresent(Int.self, forKey: .powerLevel) ?? 0
        firmware = try c.decodeIfPresent(String.self, forKey: .firmware) ?? ""
        lockTime = try c.decodeIfPresent(Int64.self, forKey: .lockTime) ?? 0
        pinStock = try c.decodeIfPresent(Int.self, forKey: .pinStock) ?? 0
        pwdStock = try c.decodeIfPresent(Int.self, forKey: .pwdStock) ?? 0
        fpStock = try c.decodeIfPresent(Int.self, forKey: .fpStock) ?? 0
        verifyMode = try c.decodeIfPresent(Int.self, forKey: .verifyMode) ?? 0
        broadcastMode = try c.decodeIfPresent(Int.self, forKey: .broadcastMode) ?? 0
        tempPwdMode = try c.decodeIfPresent(Int.self, forKey: .tempPwdMode) ?? 0
        securityLevel = try c.decodeIfPresent(Int.self, forKey: .securityLevel) ?? 0
        sKeyStatus = try c.decodeIfPresent(Int.self, forKey: .sKeyStatus) ?? 0
        zotpPeriod = try c.decodeIfPresent(Int.self, forKey: .zotpPeriod)
        pinCap = try c.decodeIfPresent(Int.self, forKey: .pinCap)
        pwdCap = try c.decodeIfPresent(Int.self, forKey: .pwdCap)
        fpCap = try c.decodeIfPresent(Int.self, forKey: .fpCap)
    }
}
struct LogCache: Codable {
    var at: Double
    var logs: [CachedLog]

    enum CodingKeys: String, CodingKey { case at, logs }

    init(at: Double, logs: [CachedLog]) { self.at = at; self.logs = logs }

    /// 容错解码：缺键回落空；单条坏记录只丢那一条（Lossy）。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        at = try c.decodeIfPresent(Double.self, forKey: .at) ?? 0
        let arr = (try? c.decodeIfPresent([Lossy<CachedLog>].self, forKey: .logs)) ?? nil
        logs = (arr ?? []).compactMap { $0.value }
    }
}
struct CachedLog: Codable {
    var type: Int
    var typeName: String
    var idxRaw: UInt32
    var lockTime: Int64
    var lockTimeStr: String

    enum CodingKeys: String, CodingKey { case type, typeName, idxRaw, lockTime, lockTimeStr }

    init(type: Int, typeName: String, idxRaw: UInt32, lockTime: Int64, lockTimeStr: String) {
        self.type = type; self.typeName = typeName; self.idxRaw = idxRaw
        self.lockTime = lockTime; self.lockTimeStr = lockTimeStr

    /// 2026-10-30 补（第 163 轮）：`typeName` 是**取日志那一刻快照下来的字符串**。
    /// 老版本写入的「未知(19)」会永久留在 `kf_logcache_` 里 —— 即使后来 `StatusParser.logTypes`
    /// 已经补上 `19: 指纹开门`，界面上仍显示「未知(19)」。**显示时总是用当前表重算**，缺失才回落缓存值。
    var displayTypeName: String { StatusParser.logTypes[type] ?? typeName }
    }

    /// 容错解码（2026-10-29）：与 Ledger 同理 —— 加字段不该让整份日志缓存解不出，
    /// 那会让记录页在升级后突然"一条都没有"（readLogs 返回 []）。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(Int.self, forKey: .type) ?? 0
        typeName = try c.decodeIfPresent(String.self, forKey: .typeName) ?? ""
        idxRaw = try c.decodeIfPresent(UInt32.self, forKey: .idxRaw) ?? 0
        lockTime = try c.decodeIfPresent(Int64.self, forKey: .lockTime) ?? 0
        lockTimeStr = try c.decodeIfPresent(String.self, forKey: .lockTimeStr) ?? ""
    }
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

    enum CodingKeys: String, CodingKey { case power, absPower, ekeyCount, ekeyAmount, firmware, pid, eCtrl }
    init(power: Int = -1, absPower: Int = -1, ekeyCount: Int = -1, ekeyAmount: Int = -1,
         firmware: String = "", pid: Int = 0, eCtrl: String = "") {
        self.power = power; self.absPower = absPower; self.ekeyCount = ekeyCount
        self.ekeyAmount = ekeyAmount; self.firmware = firmware; self.pid = pid; self.eCtrl = eCtrl
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        power = try c.decodeIfPresent(Int.self, forKey: .power) ?? -1
        absPower = try c.decodeIfPresent(Int.self, forKey: .absPower) ?? -1
        ekeyCount = try c.decodeIfPresent(Int.self, forKey: .ekeyCount) ?? -1
        ekeyAmount = try c.decodeIfPresent(Int.self, forKey: .ekeyAmount) ?? -1
        firmware = try c.decodeIfPresent(String.self, forKey: .firmware) ?? ""
        pid = try c.decodeIfPresent(Int.self, forKey: .pid) ?? 0
        eCtrl = try c.decodeIfPresent(String.self, forKey: .eCtrl) ?? ""
    }
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

    enum CodingKeys: String, CodingKey { case control, startSec, endSec, at }
    init(control: Int, startSec: Int, endSec: Int, at: Double) {
        self.control = control; self.startSec = startSec; self.endSec = endSec; self.at = at
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        control = try c.decodeIfPresent(Int.self, forKey: .control) ?? 0
        startSec = try c.decodeIfPresent(Int.self, forKey: .startSec) ?? 0
        endSec = try c.decodeIfPresent(Int.self, forKey: .endSec) ?? 0
        at = try c.decodeIfPresent(Double.self, forKey: .at) ?? 0
    }
}
struct TailgateCfg: Codable {
    var interval: Int
    var at: Double

    enum CodingKeys: String, CodingKey { case interval, at }
    init(interval: Int, at: Double) { self.interval = interval; self.at = at }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        interval = try c.decodeIfPresent(Int.self, forKey: .interval) ?? 0
        at = try c.decodeIfPresent(Double.self, forKey: .at) ?? 0
    }
}
struct OtpStatus: Codable {
    var on: Bool
    var at: Double

    enum CodingKeys: String, CodingKey { case on, at }
    init(on: Bool, at: Double) { self.on = on; self.at = at }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        on = try c.decodeIfPresent(Bool.self, forKey: .on) ?? false
        at = try c.decodeIfPresent(Double.self, forKey: .at) ?? 0
    }
}
struct OtpIdx: Codable {
    var idx: Int
    var invalidTime: String

    enum CodingKeys: String, CodingKey { case idx, invalidTime }
    init(idx: Int, invalidTime: String) { self.idx = idx; self.invalidTime = invalidTime }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        idx = try c.decodeIfPresent(Int.self, forKey: .idx) ?? 0
        invalidTime = try c.decodeIfPresent(String.self, forKey: .invalidTime) ?? ""
    }
}

// ---------- 存储访问层 ----------

extension Keychain {
    static func fromDict(_ d: [String: Any]) -> Keychain? { Keychain(fromDict: d) }
    init?(fromDict d: [String: Any]) {
        guard let mac = d["mac"] as? String else { return nil }
        self.mac = mac
        // 2026-10-14: 密钥优先读系统 Keychain; 旧 plist 明文 (历史数据) 作兜底并顺手迁移进 Keychain。
        func secret(_ field: String, _ legacy: String?) -> String {
            if let v = SecretStore.get(DB.secretAccount(mac, field)) { return v }
            if let legacy, !legacy.isEmpty {
                SecretStore.set(legacy, for: DB.secretAccount(mac, field))
                return legacy
            }
            return legacy ?? ""
        }
        self.skey = secret("skey", d["skey"] as? String)
        self.bkey = secret("bkey", d["bkey"] as? String)
        self.ekey = secret("ekey", d["ekey"] as? String)
        self.version = d["version"] as? Int ?? 1
        self.pid = d["pid"] as? Int ?? 0
        self.pidName = d["pidName"] as? String ?? ""
        self.name = d["name"] as? String ?? ""
        // pins 与 skey/bkey/ekey 同路径：优先 Keychain，旧 plist 明文作兜底并迁移。
        let pinStr = secret("pins", (d["pins"] as? [String])?.joined(separator: ","))
        self.pins = pinStr.isEmpty ? [] : pinStr.components(separatedBy: ",")
        self.trackid = d["trackid"] as? String ?? ""
        self.bleId = d["bleId"] as? String ?? ""
        self.fw = d["fw"] as? String ?? ""
        self.pairedAt = d["pairedAt"] as? String ?? ""
    }
    func toDict() -> [String: Any] {
        // 2026-10-14: skey/bkey/ekey 不落 plist (见 SecretStore); 这里只写非密字段。
        var d: [String: Any] = ["version": version, "mac": mac, "pid": pid, "pidName": pidName]
        if !name.isEmpty { d["name"] = name }
        // 2026-10-27 审核修复 (AUDIT-D D-06)：**pins 不再写 plist**。
        // 原先 skey/bkey/ekey 走 Keychain 而 pins 明文落 plist —— 等于钥匙劈两半：
        // `buildEkeyOpen(skey, mac, pin)` 需要 **skey + pin 两件**才能签出开锁凭据，
        // 一半锁进保险箱、一半贴在冰箱上。现在 pins 与其它密钥同一套（见 saveKeychain）。
        // 备份不受影响：`BackupCanonical` 读的是**内存里的 kc.pins**，不经过 plist。
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
        // 2026-10-29：原来还要求 name 必须存在 —— 缺名成员会被**整条丢弃**，
        // 名下凭证随之变成"未归属"（而 MemberHub.display 本来就有 unnamedLabel 兜底）。
        // 这里只把 id 当必需（没有 id 无法归属），name 允许空。
        guard let id = d["id"] as? String else { return nil }
        self.id = id
        self.name = d["name"] as? String ?? ""
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
