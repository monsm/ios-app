// 手机钥匙（数字钥匙）发放 —— 原版 APK 的 page-addblekey / page-delblekey 在 iOS 侧的对应实现。
//
// 语义取自 apk_raw/assets/www/build/main.js：
//   · page-addblekey：选永久/自定义有效期 → 从设备 pins 里挑一个未占用的 → generateEKey → 分享给成员
//   · page-delblekey：按 ekeyId 删除
//   · pin 分配：retrieveDeviceMemberInfo(ekey=1) 先拿已用 pin，再线性挑第一个没被占的
//
// 与「硬件钥匙串」的区别（这两件事在 iOS 侧此前只有后者）：
//   · 硬件钥匙串 = 蓝牙 dongle（pid 16289），把钥匙写进**一个随身硬件**，走 cmd41/43/44
//   · 手机钥匙   = 把 ekey 写进**成员的手机**，pin 从锁的 PIN 池里分配，本质是「按 pin 签出的 ekey」
// 两者共用 ekey 算法，但归属对象、pin 来源、撤销方式都不同，所以不能合并成一个功能点。
import Foundation

/// 一把已发放的手机钥匙。落 kf_mkey_<mac>，与 APK 的 ekey 列表同构（pin + ekey + 有效期 + 归属）。
struct MobileKey: Codable, Identifiable {
    var id: String            // ekeyId：本机生成，用于删除与去重
    var pin: String           // 从锁 PIN 池分配的 pin（十进制字符串）
    var ekey: String          // 签出的 ekey（hex）
    var memberID: String      // 归属成员
    var memberName: String    // 冗余一份名字：成员被删后仍能显示这把钥匙原来是谁的
    var forever: Bool         // true = 永久（2118 截止），false = 自定义有效期
    var validFrom: String     // 'yyyy-MM-dd HH:mm:ss'
    var validTo: String
    var at: Double            // 发放时刻（毫秒）

    // 显式解码器：合成 Codable 对「有默认值的非 Optional 字段」同样要求键存在，
    // 于是给结构体加字段之前写下的旧 JSON 会 keyNotFound ⇒ DB.get 返回 nil ⇒
    // 界面上只是静静地变成"没发过钥匙"。全部 decodeIfPresent + 默认值，
    // 与 Keychain / DongleStat 那几处的容错链同口径。
    init(id: String = "", pin: String = "", ekey: String = "", memberID: String = "",
         memberName: String = "", forever: Bool = true, validFrom: String = "",
         validTo: String = "", at: Double = 0) {
        self.id = id; self.pin = pin; self.ekey = ekey
        self.memberID = memberID; self.memberName = memberName
        self.forever = forever; self.validFrom = validFrom
        self.validTo = validTo; self.at = at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        pin = try c.decodeIfPresent(String.self, forKey: .pin) ?? ""
        ekey = try c.decodeIfPresent(String.self, forKey: .ekey) ?? ""
        memberID = try c.decodeIfPresent(String.self, forKey: .memberID) ?? ""
        memberName = try c.decodeIfPresent(String.self, forKey: .memberName) ?? ""
        forever = try c.decodeIfPresent(Bool.self, forKey: .forever) ?? true
        validFrom = try c.decodeIfPresent(String.self, forKey: .validFrom) ?? ""
        validTo = try c.decodeIfPresent(String.self, forKey: .validTo) ?? ""
        at = try c.decodeIfPresent(Double.self, forKey: .at) ?? 0
    }
}

@MainActor
enum MobileKeyService {
    static let foreverTo = "2118-01-01 00:00:00"
    static let epochFrom = "2010-01-01 00:00:00"

    private static func storeKey(_ mac: String) -> String { "kf_mkey_" + mac }

    /// SEC-01：一把手机钥匙两个秘密字段（pin 与 ekey）各一个 Keychain 账户。
    static func pinAccount(_ mac: String, _ id: String) -> String { "mkey." + mac + ".pin." + id }
    static func ekeyAccount(_ mac: String, _ id: String) -> String { "mkey." + mac + ".ekey." + id }

    /// 读**原始存储**（不判空壳）：只给写路径用。
    /// 写路径若走 `list()`，空壳里会拿到 `[]` —— `issue` 会写成"只剩新的一条"、
    /// `revoke` 会写成"空表"，两种都是把整批手机钥匙静默抹掉。
    /// 与 CredentialStudioStores 的 `stored()` / RecordOverlay 的 `rawNotes` 同一纪律。
    static func rawList(_ mac: String) -> [MobileKey] {
        let raw = DB.store.get([MobileKey].self, storeKey(mac)) ?? []
        // SEC-01：plist 里只剩 id/归属/有效期，pin 与 ekey 从 Keychain 回填。
        return raw.map { k in
            var copy = k
            if copy.pin.isEmpty { copy.pin = SecretStore.get(pinAccount(mac, k.id)) ?? "" }
            if copy.ekey.isEmpty { copy.ekey = SecretStore.get(ekeyAccount(mac, k.id)) ?? "" }
            return copy
        }
    }

    static func list(_ mac: String) -> [MobileKey] {
        // SEC-03 残余：空壳不返回手机钥匙（含 ekey/pin）。**仅展示层**用这个。
        if DB.isDecoy { return [] }
        return rawList(mac)
    }

    static func save(_ mac: String, _ keys: [MobileKey]) {
        // SEC-01：先写 Keychain（写成功才抹掉 plist 明文），与 saveKeychain 同一纪律。
        var safe = keys
        for i in safe.indices {
            if !keys[i].pin.isEmpty, SecretStore.set(keys[i].pin, for: pinAccount(mac, keys[i].id)) {
                safe[i].pin = ""
            }
            if !keys[i].ekey.isEmpty, SecretStore.set(keys[i].ekey, for: ekeyAccount(mac, keys[i].id)) {
                safe[i].ekey = ""
            }
        }
        // 注意参数序：DB.store.setCodable 是**键在前、值在后**（与 DB.setCodable 相反）。
        DB.store.setCodable(storeKey(mac), safe)
    }

    /// SEC-01 迁移：旧版本把 pin/ekey 明文写在 kf_mkey_ 里，搬进 Keychain 后抹掉明文。幂等。
    static func migrateSecrets() {
        for kc in DB.keychains() {
            let mac = DB.normalizeMac(kc.mac)
            guard let raw = DB.store.get([MobileKey].self, storeKey(mac)),
                  raw.contains(where: { !$0.pin.isEmpty || !$0.ekey.isEmpty }) else { continue }
            save(mac, raw)
        }
    }

    /// 从锁的 PIN 池里挑第一个没被本机记录占用的 pin。
    ///
    /// 与 APK 的差别（必须在 UI 上说明，不能假装一样）：
    ///   · APK 的「已占用」来自**服务端**成员列表（retrieveDeviceMemberInfo ekey=1），包含别人发的钥匙；
    ///   · 本机离线，只能看到**自己发的**（kf_mkey_），所以这里的判据是"本机没发过"。
    ///   · 因此额外用锁端状态帧的 pinInfoBinding（KLV#23，已绑定数）做交叉提示：
    ///     若 binding > 本机已发数，说明有别人的钥匙占着 pin，提示用户去服务端核对。
    static func availablePin(_ kc: Keychain, used: [MobileKey]) -> String? {
        let taken = Set(used.map { $0.pin })
        for p in kc.pins where !p.isEmpty && !taken.contains(p) { return p }
        return nil
    }

    /// 锁端「已绑定 pin 数」与本机已发数的差额 —— 用来提示"还有别人的钥匙"。
    /// 返回 nil 表示锁状态没读到（0x23 缺失），此时不该给用户任何断言。
    static func foreignKeyHint(pinInfoBinding: Int, kc: Keychain) -> String? {
        guard pinInfoBinding > 0 else { return nil }
        let mine = list(kc.mac).count
        guard pinInfoBinding > mine else { return nil }
        return "锁端显示已绑定 \(pinInfoBinding) 个 PIN，本机只记录了 \(mine) 个 ——"
             + "差额可能是别人发的手机钥匙，删除前请先确认归属。"
    }

    /// 发放。会把这条记录落库；失败不落库（与布防/防尾随同口径，不给假状态）。
    static func issue(kc: Keychain,
                      member: Member,
                      forever: Bool,
                      validFrom: String,
                      validTo: String) async throws -> MobileKey {
        // 写路径必须用 rawList：空壳里 list() 返回 []，会既选错 PIN 又把整批钥匙覆盖掉。
        let used = rawList(kc.mac)
        guard let pin = availablePin(kc, used: used) else {
            throw BLEErrorX.msg("这把锁的 PIN 池已用尽（\(kc.pins.count) 个都发完了），无法再发手机钥匙")
        }
        // 有效期：永久档对齐 APK 的 2118 截止；自定义档用 UI 传入的值
        let vf = forever ? epochFrom : validFrom
        let vt = forever ? foreverTo : validTo
        let ekey = ZKCmdBuilder.buildEkeyShare(kc.skey.lowercased(),
                                               kc.mac.lowercased(),
                                               pin,
                                               // 2026-10-28：把用户选的有效期真正签进 ekey（此前 `vf`/`vt` 只写进台账字段，没进 ekey）。
                                               validFromSec: ZKCmdBuilder.protoSecU32(vf),
                                               validToSec: ZKCmdBuilder.protoSecU32(vt),
                                               random: { _ in UInt32.random(in: 1...0x7fff_ffff) })
        guard !ekey.isEmpty else {
            throw BLEErrorX.msg("ekey 签发失败（skey 非法或 PIN 不可解析），已中止")
        }
        let key = MobileKey(id: UUID().uuidString,
                            pin: pin,
                            ekey: ekey,
                            memberID: member.id,
                            memberName: member.name,
                            forever: forever,
                            validFrom: vf,
                            validTo: vt,
                            at: Date().timeIntervalSince1970 * 1000)
        save(kc.mac, used + [key])
        return key
    }

    /// 撤销。APK 是先 op=updateShareDevice action=del 再删本地；本机离线只做本地撤销，
    /// **并把 pin 从锁里删掉**（cmd08 delPins），否则下一个拿旧 pin 签的 ekey 仍然能开门。
    static func revoke(host: any EngineHost, kc: Keychain, key: MobileKey) async throws {
        try await host.lockLink.ensureConnected(mac: kc.mac)
        try await host.lockLink.deletePins([key.pin])
        // SEC-01：撤销后清掉这把钥匙的 Keychain 秘密副本，否则残留的 ekey 仍可读。
        SecretStore.remove(pinAccount(kc.mac, key.id))
        SecretStore.remove(ekeyAccount(kc.mac, key.id))
        save(kc.mac, rawList(kc.mac).filter { $0.id != key.id })
    }

    /// 展示用：永久 / 到期时间（前 4 位是 2118 判永久 —— 与 APK page-delblekey 同判据）。
    static func validityLabel(_ k: MobileKey) -> String {
        if k.forever || k.validTo.hasPrefix("2118") { return "永久有效" }
        return "有效至 \(k.validTo)"
    }
}