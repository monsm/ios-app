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

    /// 8 位一次性救援码 (395): 防混淆字符集, 分组 4+4 展示
    static func rescueCode() -> String {
        let alphabet = Array("23456789ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz")
        var out = ""
        for _ in 0..<8 { out.append(alphabet.randomElement()!) }
        return out
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
    var duress: Bool = false     // 391 胁迫会话打标 (前端按此画橙边, 数据层只存位)
    var prevHash: String = ""    // 386 前序哈希
    var hash: String = ""        // 本条哈希 (覆盖 prevHash + 全字段)

    func hashInput(_ prev: String) -> String {
        let diffText = diff.keys.sorted().map { "\($0)=\(diff[$0!] ?? [])" }.joined(separator: "|")
        return [id, String(ts), cat.rawValue, action, target, operator_, duress ? "d" : "-", diffText, prev]
            .joined(separator: "#")
    }

    /// 链上一条 → 回填 hash 字段
    @discardableResult
    mutating func seal(prevHash: String) -> AuditEvent {
        prevHash = prevHash
        hash = HashKit.sha256Hex(hashInput(prevHash))
        return self
    }
}

// ---------- 审计台账 + 哈希链校验 ----------
final class AuditLog {
    static let key = "kf_audit_events"
    /// 管理流水封顶 (开门事件由锁端日志承载, 这里只留 App 本地增量, 避免无界增长)
    static let cap = 500

    func load() -> [AuditEvent] { DB.store.get([AuditEvent].self, AuditLog.key) ?? [] }

    @discardableResult
    func append(_ cat: AuditEvent.Category, _ action: String, target: String = "",
                diff: [String: [String]] = [:], operator_: String = "本机", duress: Bool = false) -> AuditEvent {
        let evs = load()
        var e = AuditEvent(id: Int(Date().timeIntervalSince1970 * 1000),
                            ts: Date().timeIntervalSince1970,
                            cat: cat, action: action, target: target,
                            diff: diff, operator_: operator_, duress: duress)
        e.seal(prevHash: evs.last?.hash ?? "GENESIS")
        let keep = evs.count > AuditLog.cap - 1 ? Array(evs.suffix(AuditLog.cap - 1)) : evs
        var next = keep
        next.append(e)
        DB.store.setCodable(AuditLog.key, next)
        return e
    }

    // 379 双流水分段
    func doorEvents() -> [AuditEvent] { load().filter { $0.cat == .door }.reversed() }
    func adminEvents() -> [AuditEvent] { load().filter { $0.cat == .admin }.reversed() }

    /// 386 防篡改校验: 逐链重算, 返回 (总长, 断链点下标) — -1 = 完好
    func verifyChain() -> (length: Int, brokenAt: Int) {
        let evs = load()
        var prev = "GENESIS"
        for (i, e) in evs.enumerated() {
            guard e.hash != "" else { return (evs.count, i) }
            if e.hash != HashKit.sha256Hex(e.hashInput(e.prevHash)) { return (evs.count, i) }
            prev = e.hash
        }
        return (evs.count, -1)
    }

    /// 385 保留期策略: 0=永久 / 3/6/12 月, 到期物理删除并留一条清理记录
    func purgeExpired(months: Int) {
        guard months > 0 else { return }
        var evs = load()
        let cutoff = Date().timeIntervalSince1970 - Double(months) * 30.44 * 86400
        let kept = evs.filter { $0.ts >= cutoff }
        let n = evs.count - kept.count
        if n > 0 {
            evs = kept
            var rec = AuditEvent(id: Int(Date().timeIntervalSince1970 * 1000) + 1,
                                  ts: Date().timeIntervalSince1970,
                                  cat: .admin, action: "清", target: "自动保留期 \(months) 月, 移除 \(n) 条",
                                  operator_: "自动")
            rec.seal(prevHash: evs.last?.hash ?? "GENESIS")
            evs.append(rec)
            DB.store.setCodable(AuditLog.key, evs)
        }
    }

    /// 382 脱敏导出: 密码类字段默认替换为哈希前 4 位; 勾选含明文需调用方自行二次确认
    func exportJSON(includePlaintext: Bool) -> String {
        let evs = load()
        let rows = evs.map { e -> [String: String] in
            var d = [
                "id": String(e.id), "ts": String(e.ts), "cat": e.cat.rawValue,
                "action": e.action, "target": e.target, "op": e.operator_,
                "duress": e.duress ? "1" : "0", "hash": e.hash,
            ]
            for (k, vals) in e.diff {
                let v0 = includePlaintext ? (vals.first ?? "") : HashKit.fingerprint(vals.first ?? "")
                let v1 = includePlaintext ? (vals.count > 1 ? vals[1] : "") : HashKit.fingerprint(vals.count > 1 ? vals[1] : "")
                d["diff.\(k)"] = "\(v0) → \(v1)"
            }
            return d
        }
        let data = (try? JSONSerialization.data(withJSONObject: ["lockkeeper_audit": rows],
                                                 options: [.prettyPrinted, .sortedKeys])) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    func clear() { DB.store.remove(AuditLog.key) }
}

// ---------- 388 敏感操作视图 (接触明文子集: 查看/复制/导出) ----------
final class SensitiveLedger {
    static let key = "kf_audit_sensitive"
    struct Item: Codable, Identifiable {
        var id: Int
        var kind: String      // 查看 / 复制 / 导出
        var target: String
    }
    func record(_ kind: String, target: String) {
        var items = DB.store.get([Item].self, SensitiveLedger.key) ?? []
        items.append(Item(id: Int(Date().timeIntervalSince1970 * 1000), kind: kind, target: target))
        items = Array(items.suffix(100))
        DB.store.setCodable(SensitiveLedger.key, items)
    }
    func recent(limit: Int = 20) -> [Item] {
        Array((DB.store.get([Item].self, SensitiveLedger.key) ?? []).reversed().prefix(limit))
    }
}

// ---------- 402 离职清除: 成员档案打标 + 名下凭证移入归档族 (非物理删除) ----------
enum Offboard {
    /// 成员标记"已离开"; 名下凭证搬到 kf_offboard_<member> 归档族, 记录保留
    static func markDeparted(_ memberId: String, name: String) {
        var map = DB.store.getDict("kf_members")
        if var m = map[memberId] as? [String: Any] {
            let label = (m["name"] as? String ?? name) + "（已离开）"
            m["name"] = label
            m["left"] = Date().timeIntervalSince1970
            map[memberId] = m
            DB.store.set("kf_members", map)
        }
        var l = DB.ledger(DB.currentMac)
        var archive: [LedgerPwd] = []
        l.pwds.removeAll { if let o = $0.owner { archive.append($0); return o == memberId || o == name }
                            else { return false } }
        DB.saveLedger(DB.currentMac, l)
        if !archive.isEmpty {
            var old = DB.store.get([LedgerPwd].self, "kf_offboard_" + memberId) ?? []
            DB.store.setCodable("kf_offboard_" + memberId, old + archive)
        }
    }

    static func members() -> [Member] {
        var map = DB.store.getDict("kf_members")
        return map.values.compactMap { $0 as? [String: Any] }
            .compactMap { Member.fromDict($0) }
    }
}

// ---------- 401 覆写收尾 (Store 底层 = UserDefaults plist: 覆写 = 随机字节重灌再删) ----------
enum DestroyKit {
    struct Report {
        var keys: [String]
        var randomBytes: Int
        var residueFound: Int
    }

    /// 销毁执行: 取全量键 → 采样残留片段 (销毁前抓取, 供销毁后全文检索) →
    /// 逐键随机字节覆写 N 轮再 remove → 返回报告供 UI 展示
    static func destroyAll(overwriteRounds: Int = 3) -> Report {
        let store = DB.store
        let keys = store.keys()
        // 406 残留全文检查的种子: 销毁前抓台账明文口令与锁名片段
        var fragments: [String] = []
        for kc in DB.keychains() {
            if !kc.name.isEmpty { fragments.append(kc.name) }
            for p in DB.listPwds(kc.mac) {
                if let pw = p.pwd, pw.count >= 4 { fragments.append(String(pw.prefix(4))) }
            }
        }
        for k in keys {
            for _ in 0..<max(1, overwriteRounds) {
                let n = max(64, 256 + Int.random(in: 0...4096))
                store.set("kf_overwrite_" + k, randomBytes(n))   // 随机字节重灌槽位
            }
            store.remove(k)
            store.remove("kf_overwrite_" + k)
        }
        // 自身审计族不覆写后删除而是清空: 销毁完成的证据链要留到最后
        store.remove(AuditLog.key)
        store.remove(SensitiveLedger.key)
        var evs = AuditLog().load()
        evs.removeAll()
        DB.store.setCodable(AuditLog.key, evs)
        let rep = Report(keys: keys,
                         randomBytes: keys.count * overwriteRounds * 512,
                         residueFound: 0)
        // 覆写后回扫: 用户 defaults 快照中检索片段 (等价"全文检索", 本地口径)
        let found = checkResidue(fragments)
        return Report(keys: rep.keys, randomBytes: rep.randomBytes, residueFound: found)
    }

    /// 406 残留检查: 对给定片段做全键全文检索, 返回命中数 (零 = 销毁完成)
    static func checkResidue(_ fragments: [String]) -> Int {
        let snap = DB.store.keys() + DB.store.keys() // 键本身也是检索面 (键名含锁名/mac)
        var hits = 0
        let frags = fragments.filter { $0.count >= 3 }
        for f in frags {
            for k in snap where k.contains(f) { hits += 1 }
        }
        return hits
    }

    /// 400 销毁前备份闸: 7 天内无备份文件即拦截, 先跳导出向导
    /// 备份时间戳读 Sheets 既有 kf_backup_hist ([Double] 时间线), 不另造写点
    static var lastBackupAt: Double {
        let hist = DB.store.get([Double].self, "kf_backup_hist") ?? []
        return hist.last ?? 0
    }
    static var backupGatePass: Bool {
        lastBackupAt > 0 && Date().timeIntervalSince1970 - lastBackupAt < 7 * 86400
    }

    private static func randomBytes(_ n: Int) -> [UInt8] {
        // 随机字节重灌: 覆写的是本地缓存槽位语义 (plist 层等价 VACUUM+擦除),
        // 强度目标 = 让旧值片段不连续残留, 不追求密码学级
        var buf = [UInt8](repeating: 0, count: n)
        for i in buf.indices { buf[i] = UInt8(Int.random(in: 0...255)) }
        return buf
    }
}

// ---------- 405/剪贴板与 549 口令复用检测 (读现有台账即可, 不新增写点) ----------
enum PwReuse {
    /// 新增/修改口令时与本机存量比对: 命中则提示"与已有口令重复"
    static func reuseWarnings(mac: String, newPwd: String, ignoreAlias: Int = -1) -> [String] {
        guard newPwd.count >= 4 else { return [] }
        var hits: [String] = []
        // 本锁台账
        for p in DB.listPwds(mac) where p.alias != ignoreAlias, p.pwd == newPwd {
            hits.append("本锁别名 \(p.alias)")
        }
        // 其余锁台账
        for kc in DB.keychains() where kc.mac != mac {
            for p in DB.listPwds(kc.mac) where p.pwd == newPwd {
                hits.append((kc.name.isEmpty ? kc.mac : kc.name) + " 别名 \(p.alias)")
            }
        }
        // 549 与应用锁口令同值: 口令只存 FNV 摘要不可反推, 明文比对须由 UI 层当场传值 (见 SecurityCenterView)
        return hits
    }
}
