// 包7 安全·隐私·审计 — 纯逻辑层 (无 SwiftUI 依赖, 便于单测与 golden 差分)
// 三个子模块:
//   AuditLog   审计留痕: 开门/管理双流水 + 字段 diff + 敏感操作台账 + 脱敏导出
//   AuditChain 防篡改哈希链: 每事件哈希覆盖前序哈希 (本地轻量 SHA-256 链)
//   DestroyKit 数据销毁: 等价覆写 (Store 底层是 UserDefaults plist, 覆写 = 随机字节重灌+删除)
//               + 销毁前备份闸 + 残留全文检查
// 存储键全部 kf_ 前缀, 与小程序/备份互通语义一致; 只经 DB.store 读写, 不改 Store 本身。
import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(CommonCrypto)
import CommonCrypto
#endif

// ---------- 哈希基元 (SHA-256 hex, 本地轻量防篡改) ----------
enum HashKit {
    /// SHA-256 → 小写十六进制。CryptoKit 不可用 (旧工具链) 时退化为 FNV-1a32 双轮拼接,
    /// 只要求"改一条即破链"的防篡改性质, 不要求密码学强度 (离线 App, 无中心校验方)。
    static func sha256Hex(_ s: String) -> String {
        #if canImport(CryptoKit)
        return SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
        #else
        let a = String(fnv1a32(s), radix: 16)
        let b = String(fnv1a32("kf2." + s.reversed().map { $0 } .description), radix: 16)
        return a + b
        #endif
    }

    /// HMAC 风格的"口令→指纹" (382 脱敏导出用): 只留前 4 位, 不可逆推原值
    static func fingerprint(_ s: String) -> String {
        String(sha256Hex(s).prefix(4))
    }

    static func fnv1a32(_ s: String) -> UInt32 {
        var hash: UInt32 = 0x811C9DC5
        for ch in s.unicodeScalars {
            hash ^= UInt32(ch.value & 0xFF)
            hash = hash &* 0x01000193
        }
        return hash
    }
}

// ---------- 审计事件 (379 双流水: 开门事件 / 管理操作) ----------
struct AuditEvent: Codable, Identifiable {
    enum Category: String, Codable { case door = "door", admin = "admin" }
    var id: Int                 // 毫秒级序号, 链上唯一定位
    var ts: Double               // Unix 秒
    var cat: Category
    var action: String           // 开/删/改/发/导/入/清 等短动词
    var target: String = ""      // 对象 (锁名/成员/凭证别名)
    var diff: [String: [String]] = [:]   // 380 字段级 diff: 字段 → [前值, 后值]
    var operator_: String = ""   // 381 操作者: 会话验证方式 (本机密码/面容/会话续期)
    var duress: Bool = false     // 391 胁迫会话打标: 只在操作日志里画橙标 (刻意不给全局可见边框, 免得打标本身成为破绽)
    var prevHash: String = ""    // 386 前序哈希
    var hash: String = ""        // 本条哈希 (覆盖 prevHash + 全字段)

    func hashInput(_ prev: String) -> String {
        // 2026-10-13 run 62: `diff.keys.sorted()` 的元素已经是 String, 原来写 `diff[$0!]` 是
        // 对一个**非可选**值强制解包 ⇒ "cannot force unwrap value of non-optional type
        // 'Dictionary<String, [String]>.Keys.Element' (aka 'String')"。去掉 `!`。
        let diffText = diff.keys.sorted().map { "\($0)=\(diff[$0] ?? [])" }.joined(separator: "|")
        // 第二处: 数组首元素 `id` 是 Int, 其余是 String, 字面量元素类型被推成 String ⇒
        // "cannot convert value of type 'Int' to expected element type 'String'"。显式转 String。
        return [String(id), String(ts), cat.rawValue, action, target, operator_, duress ? "d" : "-", diffText, prev]
            .joined(separator: "#")
    }

    /// 链上一条 → 回填 hash 字段
    @discardableResult
    mutating func seal(prevHash: String) -> AuditEvent {
        self.prevHash = prevHash
        hash = HashKit.sha256Hex(hashInput(prevHash))
        return self
    }
}

// ---------- 审计台账 + 哈希链校验 ----------
final class AuditLog {
    static let key = "kf_audit_events"
    /// 管理流水封顶 (开门事件由锁端日志承载, 这里只留 App 本地增量, 避免无界增长)
    static let cap = 500
    /// 2026-10-14: append/purgeExpired 都是 load→改→save 的非原子序列, 并发调用会丢事件或断链; 加锁串行。
    private static let chainLock = NSLock()

    func load() -> [AuditEvent] { DB.store.get([AuditEvent].self, AuditLog.key) ?? [] }

    @discardableResult
    func append(_ cat: AuditEvent.Category, _ action: String, target: String = "",
                diff: [String: [String]] = [:], operator_: String = "本机", duress: Bool = false) -> AuditEvent {
        AuditLog.chainLock.lock()
        defer { AuditLog.chainLock.unlock() }
        let evs = load()
        // 386 截断重锚 (2026-10-14 对抗式排查): 达 cap 后截头, 但旧实现不重封哈希链 —— 被留首条的
        // prevHash 仍指向已丢弃条 => verifyChain 恒在下标 0 报"断链"(假阳性)。与 purgeExpired 同法重锚。
        var next = evs
        if evs.count > AuditLog.cap - 1 {
            next = Array(evs.suffix(AuditLog.cap - 1))
            var prev = "GENESIS"
            for i in next.indices {
                next[i].prevHash = prev
                next[i].hash = HashKit.sha256Hex(next[i].hashInput(prev))
                prev = next[i].hash
            }
        }
        // id 单调递增 (last+1): 防毫秒同刻碰撞注入 / 换序重放伪造断点
        var e = AuditEvent(id: (next.last?.id ?? 0) + 1,
                           ts: Date().timeIntervalSince1970,
                           cat: cat, action: action, target: target,
                           diff: diff, operator_: operator_, duress: duress)
        e.seal(prevHash: next.last?.hash ?? "GENESIS")
        next.append(e)
        DB.store.setCodable(AuditLog.key, next)
        return e
    }

    // 379 双流水分段

    /// 386 防篡改校验: 逐链重算, 返回 (总长, 断链点下标) — -1 = 完好; -2 = id 单调性被破坏
    /// (头部裁剪/换序重放: 旧实现只验哈希, 攻击者截掉前 N 条重封 GENESIS 链即通过, 此处堵死)
    func verifyChain() -> (length: Int, brokenAt: Int) {
        let evs = load()
        var prev = "GENESIS"
        var lastId = 0
        for (i, e) in evs.enumerated() {
            guard e.hash != "" else { return (evs.count, i) }
            if e.id <= lastId { return (evs.count, -2) }
            lastId = e.id
            // 386 链连接校验: 旧实现维护了 prev 却从不比较 e.prevHash != prev → 只验每条自洽,
            // 删掉中间任意条 (含 391 胁迫打标) 后逐条重算即可显示"链完好"。
            if e.prevHash != prev { return (evs.count, i) }
            if e.hash != HashKit.sha256Hex(e.hashInput(e.prevHash)) { return (evs.count, i) }
            prev = e.hash
        }
        return (evs.count, -1)
    }

    // 2026-10-26: 「385 保留期策略」purgeExpired(months:) 已删 ——
    // 它读的 SecKey.auditRetention 从来没有写点（设置页无保留期选项）⇒ 唯一调用点永不进入，
    // 上批删掉那个自动调用后本函数零调用。审计记录的核对/校验能力（verifyChain）不受影响。



    func clear() { DB.store.remove(AuditLog.key) }
}

// ---------- 388 敏感操作视图 (接触明文子集: 查看/复制/导出) ----------
final class SensitiveLedger {
    static let key = "kf_audit_sensitive"
    struct Item: Codable, Identifiable {
        var id: Int
        var kind: String      // 查看 / 复制 / 导出 / 停用·原因
        var target: String
        /// 367 归属维度: 只有「写入该成员动态」勾上的那几条才有值。
        /// Optional + 合成 decoder 的 decodeIfPresent ⇒ 旧流水 (没这个键) 解出来是 nil, 不会整页解不开。
        var member: String?
    }
    /// 2026-10-14: 与 AuditLog 同款的 load→改→save 非原子序列; 调用方既有 MainActor (复制)
    /// 又有导出与其他异步路径, 并发会丢条目。加锁。
    private static let recordLock = NSLock()
    /// 默认不写 member: 默认形态与改动前逐字相同 (同一条事件不在敏感流水里出现两行)。
    func record(_ kind: String, target: String, member: String? = nil) {
        SensitiveLedger.recordLock.lock(); defer { SensitiveLedger.recordLock.unlock() }
        var items = DB.store.get([Item].self, SensitiveLedger.key) ?? []
        items.append(Item(id: Int(Date().timeIntervalSince1970 * 1000), kind: kind, target: target, member: member))
        items = Array(items.suffix(100))
        DB.store.setCodable(SensitiveLedger.key, items)
    }
    /// 388 敏感操作视图的取数 (先倒序再筛, 「新在前」)。
    func recent(limit: Int = 20) -> [Item] {
        Array((DB.store.get([Item].self, SensitiveLedger.key) ?? [])
              .reversed().prefix(limit))
    }
    /// 367 成员详情页读的那一支: 先倒序再筛, 与 recent 同一套「新在前」口径。
    func memberItems(_ member: String, limit: Int = 10) -> [Item] {
        Array((DB.store.get([Item].self, SensitiveLedger.key) ?? [])
              .filter { $0.member == member }
              .reversed().prefix(limit))
    }
    /// 367 流水时刻。单位口径：`id` 存的是 epoch **毫秒** (record 里那个 *1000)，
    /// 这里的 /1000 才是 Unix 秒 —— 不是协议秒, 也不是台账里那种按秒存的 `at`。
    static func stamp(_ item: Item) -> String {
        let c = WeekCal.gregorian
        let d = Date(timeIntervalSince1970: Double(item.id) / 1000)
        return String(format: "%02d-%02d %02d:%02d", c.component(.month, from: d), c.component(.day, from: d),
                      c.component(.hour, from: d), c.component(.minute, from: d))
    }
}


// ---------- 401 覆写收尾 (Store 底层 = UserDefaults plist: 覆写 = 随机字节重灌再删) ----------
enum DestroyKit {
    /// 400 销毁前备份闸: 7 天内无备份文件即拦截。
    /// 备份时间戳读 Sheets 既有 kf_backup_hist ([Double] 时间线), 不另造写点。
    /// 这本历史写的是 epoch **毫秒** (Milestones.recordBackup: *1000), 读数处统一换算成秒。
    static var lastBackupAt: Double {
        let hist = DB.store.get([Double].self, "kf_backup_hist") ?? []
        return (hist.last ?? 0) / 1000
    }
    static var backupGatePass: Bool {
        lastBackupAt > 0 && Date().timeIntervalSince1970 - lastBackupAt < 7 * 86400
    }
}

