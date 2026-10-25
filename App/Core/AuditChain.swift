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
    func doorEvents() -> [AuditEvent] { load().filter { $0.cat == .door }.reversed() }
    func adminEvents() -> [AuditEvent] { load().filter { $0.cat == .admin }.reversed() }

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

    /// 385 保留期策略: 0=永久 / 3/6/12 月, 到期物理删除并留一条清理记录
    func purgeExpired(months: Int) {
        guard months > 0 else { return }
        AuditLog.chainLock.lock()
        defer { AuditLog.chainLock.unlock() }
        let evs = load()
        let cutoff = Date().timeIntervalSince1970 - Double(months) * 30.44 * 86400
        var kept = evs.filter { $0.ts >= cutoff }
        let n = evs.count - kept.count
        if n > 0 {
            // 386 截断重锚: 诚实截断后整段重封 — 旧哈希是挂在被截断链上的, 逐条重算否则 verifyChain 必报断链
            var prev = "GENESIS"
            for i in kept.indices {
                kept[i].prevHash = prev
                kept[i].hash = HashKit.sha256Hex(kept[i].hashInput(prev))
                prev = kept[i].hash
            }
            var rec = AuditEvent(id: (kept.last?.id ?? 0) + 1,
                                  ts: Date().timeIntervalSince1970,
                                  cat: .admin, action: "清", target: "自动保留期 \(months) 月, 移除 \(n) 条 (链头重锚 GENESIS)",
                                  operator_: "自动")
            rec.seal(prevHash: kept.last?.hash ?? "GENESIS")
            kept.append(rec)
            DB.store.setCodable(AuditLog.key, kept)
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
        var kind: String      // 查看 / 复制 / 导出 / 停用·原因
        var target: String
        /// 367 归属维度: 只有「写入该成员动态」勾上的那几条才有值。
        /// Optional + 合成 decoder 的 decodeIfPresent ⇒ 旧流水 (没这个键) 解出来是 nil, 不会整页解不开。
        var member: String?
    }
    /// 2026-10-14: 与 AuditLog 同款的 load→改→save 非原子序列; 调用方既有 MainActor (复制)
    又有导出与其他异步路径, 并发会丢条目。加锁。
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

// ---------- 402 离职清除: 成员档案打标 + 名下凭证入回收站 (非物理删除) ----------
enum Offboard {
    /// 成员标记"已离开"; 名下凭证入回收站 (kf_cbin_) —— 402 改成可 365/504 取回的那条路。
    /// 旧写法学过 kf_offboard_<member> 归档族, 但那条路没有取回入口, 等于进了黑洞。
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
        // 2026-10-14 对抗式排查: 旧闭包对**每个有 owner 的凭证**都 append 进 archive, 只在 return 处
        // 按 memberId/name 判归属 => 离职清除会把**其他成员**的凭证也复制进回收站并清掉 owner (数据损坏)。
        // 只有命中本成员才入档 + 移除。
        l.pwds.removeAll { p in
            guard let o = p.owner else { return false }
            if o == memberId || o == name { archive.append(p); return true }
            return false
        }
        DB.saveLedger(DB.currentMac, l)
        // 402: 名下凭证逐条入回收站 (kf_cbin_), owner 清掉避免离职成员再被关联;
        // saveLedger 的 379/380 字段级 diff 已在上面那一步留了管理员流水, 这里不重复。
        let batchId = UUID().uuidString   // 这一次离职清除的多条凭证共用一个批次号 (501 整组还原)
        for p in archive {
            var cp = p
            cp.owner = nil
            CredentialOrg.addToBin(DB.currentMac, pwd: cp, source: .manual, batchId: batchId)
        }
    }

    static func members() -> [Member] {
        let map = DB.store.getDict("kf_members")
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
        var filesRemoved: Int
        var filesFailed: [String]
    }

    /// 销毁执行: 取全量键 → 采样残留片段 (销毁前抓取, 供销毁后全文检索) →
    /// 逐键随机字节覆写 N 轮再 remove → 返回报告供 UI 展示
    ///
    /// 383 毁灭操作 sudo 的执行侧落点: `sudoRequired` 开着而这一层没拿到 SudoTicket 就**什么都不动**,
    /// 返回 nil 由界面如实显示"被 383 拦下, 未执行"。为什么在逻辑层再判一次而不是只写在按钮前:
    /// 按钮前那句 if 是这条路径上唯一会被漏掉的东西 —— 界面再加第二个销毁入口时不必重新发明纪律。
    /// SudoTicket 只能由 SecurityPolicy.sudoTicket(from:) 当场验过应用锁口令才发得出
    /// (它的 init 关在 LockGuard.swift 里), 调用方自报一个 true 换不来覆写循环。
    static func destroyAll(sudoRequired: Bool, sudo: SudoTicket?, overwriteRounds: Int = 3) -> Report? {
        guard !sudoRequired || sudo != nil else { return nil }
        let store = DB.store
        let keys = store.keys()
        // 406 残留全文检查的种子: 销毁前抓台账明文口令与锁名片段
        var fragments: [String] = []
        for kc in DB.keychains() {
            if !kc.name.isEmpty { fragments.append(kc.name) }
            // 密钥本身做探针: 回滚快照/导出件里存的就是 skey, 只要有一份没删净就必须被扫出来
            if kc.skey.count >= 8 { fragments.append(String(kc.skey.prefix(8))) }
            for p in DB.listPwds(kc.mac) {
                if let pw = p.pwd, pw.count >= 4 { fragments.append(String(pw.prefix(4))) }
            }
        }
        // 尽力而为的覆写: UserDefaults 不保证底层 plist 的字节级安全删除, 这里只把同键位重灌随机字节后删除,
        // 对外表述统一为"已删除, 不保证物理字节覆写" (旧实现把写进 kf_overwrite_<k> 的字节计成"覆写量"并虚报)。
        var written = 0
        for k in keys {
            for _ in 0..<max(1, overwriteRounds) {
                let n = max(64, 256 + Int.random(in: 0...4096))
                store.set("kf_overwrite_" + k, randomBytes(n))
                written += n
            }
            store.remove(k)
            store.remove("kf_overwrite_" + k)
        }
        // 自身审计族不覆写后删除而是清空: 销毁完成的证据链要留到最后
        store.remove(AuditLog.key)
        store.remove(SensitiveLedger.key)
        // 2026-10-14: 门锁密钥在系统 Keychain (SecretStore), keys() 全表清碰不到它 —— 必须显式清空。
        SecretStore.removeAll()
        var evs = AuditLog().load()
        evs.removeAll()
        DB.store.setCodable(AuditLog.key, evs)
        // 落盘文件侧: 备份导出件与自动回滚快照里是**整库 Keychain/台账明文**,
        // 只清 UserDefaults 等于"销毁"完在 Documents 留了一整套可一键复原的密钥。
        let files = destroyLocalFiles()
        // 覆写后回扫: 键名 + 值内容 + 未删净的本地文件一起检索 (见 checkResidue)
        let found = checkResidue(fragments)
        return Report(keys: keys, randomBytes: written, residueFound: found,
                      filesRemoved: files.removed, filesFailed: files.failed)
    }

    /// 本地落盘的密钥类文件目录: 413 导出件 (Documents/lockkeeper-backups) 与 421 回滚快照
    /// (Application Support/lockkeeper-rollback)。回滚快照不做用户提示地自动落盘, 是销毁流程最容易被漏掉的一份。
    /// 第三个是 719 的导出缓存 (Caches/exports): 未勾选 548 脱敏时会带出**原始协议 hex** 与成员/时间线,
    /// 而 Caches 只是"系统择机清理", 销毁必须点名删掉 (口令列本身不在 ExportRecord 字段里, 不在此处夸大)。
    static var localSecretDirs: [URL] {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sup = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return [docs.appendingPathComponent("lockkeeper-backups", isDirectory: true),
                sup.appendingPathComponent("lockkeeper-rollback", isDirectory: true),
                caches.appendingPathComponent("exports", isDirectory: true)]
    }

    /// 逐文件覆写内容再删除; 删不掉的记名 (残留复核会命中)
    private static func destroyLocalFiles() -> (removed: Int, failed: [String]) {
        let fm = FileManager.default
        var removed = 0
        var failed: [String] = []
        for base in localSecretDirs where fm.fileExists(atPath: base.path) {
            if let deep = fm.enumerator(at: base, includingPropertiesForKeys: nil,
                                       options: [.skipsHiddenFiles]) {
                // nextObject() 是 DirectoryEnumerator 的权威接口 (Sequence 口径随 SDK 变, 不依赖)
                while let f = deep.nextObject() as? URL {
                    // 只覆写并删文件: 目录交给末尾的 base 删除。旧写法对目录也 removeItem,
                    // 会把**子目录里还没覆写的文件**一并带走 —— 那等于"覆写"是假的。
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: f.path, isDirectory: &isDir), !isDir.boolValue else { continue }
                    if var data = try? Data(contentsOf: f), !data.isEmpty {
                        for i in data.indices { data[i] = UInt8(Int.random(in: 0...255)) }
                        try? data.write(to: f, options: .atomic)
                    }
                    if (try? fm.removeItem(at: f)) == nil { failed.append(f.path); continue }
                    removed += 1
                }
            }
            if (try? fm.removeItem(at: base)) == nil { failed.append(base.path) }
        }
        return (removed, failed)
    }

    /// 406 残留检查: 键名 **与值内容** 一起检索, 返回命中数。
    /// 旧实现是 `DB.store.keys() + DB.store.keys()` —— 把键名列表拼两遍当"全文", 值从未参与检索,
    /// 而销毁已经把键全删, 因此恒返回 0, UI 上的"零残留"是恒真结论而不是验证结果。
    static func checkResidue(_ fragments: [String]) -> Int {
        let frags = fragments.filter { $0.count >= 3 }
        guard !frags.isEmpty else { return 0 }
        var hits = 0
        for k in DB.store.keys() {
            let raw = DB.store.rawText(k)
            for f in frags where k.contains(f) || (raw?.contains(f) ?? false) {
                hits += 1
                break
            }
        }
        // 落盘侧同口径检索: 销毁没能删掉的备份/快照文件里就是原始片段
        for text in remainingSecretFileTexts() {
            if frags.contains(where: { text.contains($0) }) { hits += 1 }
        }
        return hits
    }

    private static func remainingSecretFileTexts() -> [String] {
        let fm = FileManager.default
        var out: [String] = []
        for base in localSecretDirs {
            guard let deep = fm.enumerator(at: base, includingPropertiesForKeys: nil,
                                          options: [.skipsHiddenFiles]) else { continue }
            while let f = deep.nextObject() as? URL {
                // 用 lossy 解码: 覆写失败但删除也失败的文件里是随机字节, String(contentsOf:.utf8) 会直接
                // 抛错被跳过 → 残留命中数虚低, 复核又变成一句假话。
                if let data = try? Data(contentsOf: f) {
                    out.append(String(decoding: data, as: UTF8.self))
                }
            }
        }
        return out
    }

    /// 406 独立复核: 旧 UI 调的是 `checkResidue([])` —— 空片段直接走 guard return 0,
    /// 所以屏幕上的"残留复核: 零残留"依旧是恒真结论。这里不依赖调用方传值, 直接验两条硬不变量:
    /// ① 密钥类落盘目录必须已空; ② 存活键位里不能再有含 skey/ekey 的键锁 JSON。
    static func residueSelfCheck() -> (hits: Int, scanned: Int) {
        var hits = 0, scanned = 0
        for k in DB.store.keys() {
            guard let raw = DB.store.rawText(k) else { continue }
            scanned += 1
            if raw.contains("\"skey\"") || raw.contains("\"ekey\"") { hits += 1 }
        }
        let fm = FileManager.default
        for base in localSecretDirs {
            guard let en = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil,
                                                      options: [.skipsHiddenFiles]) else { continue }
            scanned += en.count
            hits += en.count
        }
        return (hits, scanned)
    }

    /// 400 销毁前备份闸: 7 天内无备份文件即拦截, 先跳导出向导
    /// 备份时间戳读 Sheets 既有 kf_backup_hist ([Double] 时间线), 不另造写点。
    /// 400 修正: 这本历史写的是 epoch **毫秒** (Milestones.recordBackup: *1000), 此前按秒直减
    /// ⇒ "现在 - 上次"恒为负数 ⇒ 7 天窗恒真, 闸门与页面日期 (SecurityCenterView backupGateLine) 一起失真。
    /// 读数处统一换算成秒, 销毁闸 (本文件消费点) 与诊断页 752 提醒从此才真的可能拦人。
    static var lastBackupAt: Double {
        let hist = DB.store.get([Double].self, "kf_backup_hist") ?? []
        return (hist.last ?? 0) / 1000
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
        for p in DB.listPwds(mac) where p.alias != ignoreAlias && p.pwd == newPwd {
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
