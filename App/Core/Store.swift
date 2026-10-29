// 本地存储与数据模型 — JS utils/store.js + services/{ledger,snapshot,keychain,gateway,members}.js 移植
// 存储键与小程序完全一致 (kf_*), 便于全量备份跨端互换
import Foundation

// ---------- 存储 ----------
final class Store: @unchecked Sendable {
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
        // 2026-10-27 审核修复 (D-07)：原来解码失败也返回 [:] —— 而 saveKeychain 会拿它
        // 整表写回，于是「一次无关的保存」会把所有其它设备的钥匙串抹掉。
        // 与 ledger() 同一类失效（有数据但解不出来），但后果更重：那不是空台账，是丢密钥。
        // 现在失败时返回带哨兵键的字典，调用方（saveKeychain）见哨兵即放弃写入。
        if let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] { return o }
        corruptDictKeys.insert(k)
        return [:]
    }
    /// 解码失败过的字典键。saveKeychain 写入前查这里，避免用空表覆盖真数据。
    private var corruptDictKeys: Set<String> = []
    func isDictCorrupt(_ k: String) -> Bool { corruptDictKeys.contains(k) }
    func getString(_ k: String, _ def: String = "") -> String {
        if let s = defaults.string(forKey: key(k)) { return s }
        if let v = get(k, String.self) { return v }
        return def
    }
    func getBool(_ k: String, _ def: Bool = false) -> Bool { get(k, Bool.self) ?? def }
    func getInt(_ k: String, _ def: Int = 0) -> Int { get(k, Int.self) ?? def }
    func getDouble(_ k: String, _ def: Double = 0) -> Double { get(k, Double.self) ?? def }
    func setInt(_ k: String, _ v: Int) { set(k, v) }
    func setDouble(_ k: String, _ v: Double) { set(k, v) }
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
    /// 失败台账的读改写串行化。
    /// Store 是 @unchecked Sendable (UserDefaults 本身线程安全), 但"读数组 → 判重 → 插入 → 写回"
    /// 是**复合动作**: 两个线程同时写失败时会各自读到同一份旧数组, 后写的把先写的那条覆盖掉
    /// (丢证据)。Swift 6 的模型把这种无同步的读改写直接算 UB, 所以这一小段上锁 —— 只在失败路径上,
    /// 正常读写一次都不经过它。
    private let failureLock = Locked(false)
    private func recordFailure(_ k: String, _ why: String) {
        failureLock.withLock { _ in
            let tail = k + " ← " + why
            if failureLines().contains(where: { $0.hasSuffix(tail) }) { return }
            var next = failureLines()
            next.insert(DiagTime.mmddHHmm() + " " + tail, at: 0)
            if next.count > 40 { next = Array(next.prefix(40)) }
            defaults.set(next, forKey: key(Self.failureKey))
        }
    }
    func failureLines() -> [String] { (defaults.array(forKey: key(Self.failureKey)) as? [String]) ?? [] }
    /// 刻意**不提供**清空口: 这本账的删除动作留在既有语义里 —— 核弹销毁按 `keys()` 全表清 (AuditChain:242)，
    /// 加一个 `clearFailureLog()` 只会多一条零调用声明，而且给了"把证据抹掉但不告诉用户抹了什么"的按钮。
    func remove(_ k: String) { defaults.removeObject(forKey: key(k)) }
    /// 键是否存在 (区分"无数据"与"有数据但解不出")
    func has(_ k: String) -> Bool { defaults.object(forKey: key(k)) != nil }
    func keys() -> [String] {
        defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("kf.") }.map { String($0.dropFirst(3)) }
    }
    /// 421 回滚快照: 原样读出 defaults 里那段 JSON Data。
    /// 不走 get/JSONDecoder —— 快照要的是**字节不变**，重新编码会把形状 (键序/可选字段) 改写一遍。
    func rawData(_ k: String) -> Data? { defaults.data(forKey: key(k)) }
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
enum DB {
    static let store = Store.shared


    /// 台账写入的串行化锁。2026-10-27 新增（AUDIT-D D-19）。
    /// `saveLedger` 的「corrupt 检查 → 读 → 写」必须原子：检查通过后若别的线程
    /// 把台账标成 corrupt 并写空表，这次写入就会把真数据覆盖掉。
    private static let ledgerWriteLock = Locked(0)

    /// 钥匙串字典写入的串行化锁。2026-10-27 新增（AUDIT-D D-18）。
    /// `kf_keychains` 是「整表读 → 改一个键 → 整表写」，没有同步时后写者会覆盖先写者，
    /// 表现是「配了两把锁只剩一把」这类偶发数据丢失。
    private static let keychainWriteLock = Locked(0)

    @discardableResult

    static var currentMac: String {
        get { store.getString("kf_current_mac") }
        set { store.set("kf_current_mac", newValue) }
    }
    static var lastDevice: String {
        get { store.getString("kf_last_device") }
        set { store.set("kf_last_device", newValue) }
    }

    // 凭证台账
    /// 台账解码失败的锁 (防"解不出→空表写回"清空数据)。
    /// 2026-10-14: 原为非隔离可变 static var, 后台任务与主线程并发访问是数据竞争; 加锁存取。
    private static let ledgerLock = Locked(Set<String>())


    /// 日志缓存只为**还在台账里的锁**而写。为什么要在写入口拦一道: 删除设备会按族清掉 kf_logcache_<mac>,
    /// 而任何在删锁之后又跑一遍的"改写日志"都会把它重新写回来 —— 于是体检里凭空多出一条
    /// "已删门锁 … 的日志缓存残留" 的孤儿 (真机报告 2026-10-17: 演示数据的清除路径就踩在这一处)。
    /// 首次配网的锁在写完钥匙串之后才可能拉日志 (pair 末步才 saveKeychain), 所以这道闸不会拦真实写入。
    private static func cacheWritable(_ mac: String) -> Bool {
        guard keychain(mac) != nil else {
            // 已经存在的话顺手拿掉: 它就是孤儿本身, 留着只会让体检一直报。
            store.remove("kf_logcache_" + mac)
            return false
        }
        return true
    }



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
        // 2026-10-14: 旧写法按 count % 6 取色 —— 删成员后 count 回退会与现存成员撞色 (头像/时间线靠色区分)。
        // 先挑一个当前没被占用的色, 六色用满才按人数轮转。
        let used = Set(members().map { $0.color })
        let color = memberPalette.first { !used.contains($0) } ?? memberPalette[members().count % memberPalette.count]
        let m = Member(id: UUID().uuidString.prefix(8).description, name: n,
                       color: color,   // 259: 建档即分配, 不再全员品牌靛蓝
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
            // 2026-10-14: 认领映射 (kf_mclaim_) 里指向该成员的条目必须删掉 —— 否则记录页 whoId 指向
            // 已删 id 既显示不出人, 又因 claims 里仍有该 id 而**永远无法重新认领** (悬空引用)。
            var claims = store.get([String: String].self, "kf_mclaim_" + kc.mac) ?? [:]
            let before = claims.count
            claims = claims.filter { $0.value != id }
            if claims.count != before { store.setCodable("kf_mclaim_" + kc.mac, claims) }
        }
        // 档案扩展 / 徽章 / 生日 (均以成员 id 为键) 与值班周表: 删成员后成永久孤儿键, 一并清。
        for key in ["kf_member_ext", "kf_member_badge", "kf_member_bday"] {
            var d = store.getDict(key)
            if d.removeValue(forKey: id) != nil { store.set(key, d) }
        }
        var duty = store.get([String: String].self, "kf_duty_week") ?? [:]
        let dbefore = duty.count
        // 2026-10-14: 该表是 weekKey → memberId (MemberHub), 上一版误按 key 过滤 → 恒不命中, 值班记录成孤儿。
        duty = duty.filter { $0.value != id }
        if duty.count != dbefore { store.setCodable("kf_duty_week", duty) }
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
    /// 是否设了本机密码。
    ///
    /// 2026-10-27 审核修复 (AUDIT-D D-59)：原先只看键**存在**，不看内容 ——
    /// 一个 `{}` 或残缺记录（如只有 salt 没有摘要）也会被当成"有密码"，
    /// 于是：① 应用锁界面出现，但任何输入都验不过 → 用户被永久锁在外面；
    /// ② `verifyPasscode` 的 `guard rec["d"] == ...` 在 `d` 缺失时永远 false。
    /// 现在要求：「salt 非空」且「至少有一种摘要（d2 或 d）」。
    static func hasPasscode() -> Bool {
        guard let rec = get([String: String].self, "kf_passcode") else { return false }
        let salt = rec["s"] ?? ""
        guard !salt.isEmpty else { return false }
        let hasStrong = !(rec["d2"] ?? "").isEmpty
        let hasLegacy = !(rec["d"] ?? "").isEmpty
        return hasStrong || hasLegacy
    }
    /// 门禁口令摘要轮数 (PBKDF2-HMAC-SHA256)
    /// 2026-10-27 审核说明 (AUDIT-A F-17)：**vendor 没有 PBKDF2 实现** ——
    /// 小程序侧的门禁口令是 32-bit FNV（`fnv1a32`），本仓加了 PBKDF2-HMAC-SHA256 6 万轮。
    /// 所以这不是「对齐 vendor」而是**本仓自造的更强方案**；跨端互操作靠 d/d2 双写：
    /// 旧包只有 d（FNV）时按旧口径验、验过即静默升级到 d2。
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
        // 2026-10-27 (D-10)：升级成强摘要后清掉「弱保护」标记。
        store.remove("kf_passcode_weak")
        set(passcodeRecord(pw, salt: salt), "kf_passcode")
        return true
    }
    static func setPasscode(_ pw: String?) {
        // 2026-10-27 (D-10)：新设/改设密码一律是强摘要，清掉弱标记。
        store.remove("kf_passcode_weak")
        if let pw { set(passcodeDigest(pw), "kf_passcode") } else { store.remove("kf_passcode") }
    }

    // ── 胁迫码（伪装模式）── 2026-10-27 新增（AUDIT-D D-48）
    //
    // 与正常密码同一套 PBKDF2 摘要，但存在**独立的键** `kf_duress` 里：
    // 输正常密码 → 正常解锁；输胁迫码 → 进空壳模式（门能开、数据看不见）。
    // 不共用 kf_passcode 的槽位，是因为「改正常密码」不该连带影响胁迫码 ——
    // 用户设了胁迫码之后最不希望它被别的操作悄悄改掉或清掉。
    private static let duressKey = "kf_duress"

    static func hasDuressCode() -> Bool {
        get([String: String].self, duressKey) != nil
    }

    /// 设置胁迫码。传 nil 或空串 = 清除。
    /// 返回 false 表示输入不合法（<4 位 / 非纯数字 / 与正常密码相同）。
    /// ⚠ 与正常密码相同会被拒 —— 否则输入正常密码就进伪装模式，人会被自己的配置坑到。
    @discardableResult
    static func setDuressCode(_ code: String?) -> Bool {
        guard let code, !code.isEmpty else {
            store.remove(duressKey)
            return true
        }
        guard code.count >= 4, code.allSatisfy({ $0.isNumber }) else { return false }
        if verifyPasscode(code) { return false }
        set(passcodeDigest(code), duressKey)
        return true
    }

    /// 验证胁迫码。没设过则恒 false。
    static func verifyDuress(_ pw: String) -> Bool {
        guard let rec = get([String: String].self, duressKey) else { return false }
        let salt = rec["s"] ?? ""
        if let strong = rec["d2"], !strong.isEmpty {
            return pcStrong(pw, salt: salt) == strong
        }
        return rec["d"] == fnv1a32(salt + pw)
    }

    static func clearDuressCode() { store.remove(duressKey) }


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
