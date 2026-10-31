// 备份加密信封 + WebDAV 同步 — JS utils/cloudcrypto.js + services/cloudsync.js 移植
//   信封: PBKDF2-HMAC-SHA256(60000) → AES-128-CBC + HMAC-SHA256 (encrypt-then-MAC)
//   端点: 坚果云 WebDAV「我的坚果云/zklock-backup.enc」(Basic 认证, 应用专属密码)
//   与小程序端信封 JSON 格式完全互通 (v1: {v,alg,kdf,ivHex,macHex,cHex,meta})
import Foundation
import CryptoKit
import CommonCrypto

/// 通用错误类型 (原住 DFUKit.swift, 那个文件的 DFU 升级逻辑已随本轮删减移除,
/// 但备份/凭证/协议各处仍在抛这个类型 —— 形状留在这里)。
enum DFUError: LocalizedError {
    case zip(String)
    case msg(String)
    var errorDescription: String? {
        switch self {
        case .zip(let m): return m
        case .msg(let m): return m
        }
    }
}

struct BackupEnvelope: Codable {
    var v: Int
    var alg: String
    var kdf: Kdf
    var ivHex: String
    var macHex: String
    var cHex: String
    var meta: Meta
    struct Kdf: Codable { var alg: String; var iter: Int; var saltHex: String }
    struct Meta: Codable { var size: Int; var at: Double }
}

enum CryptoBox {
    static let defaultIter = 60000

    static func sha256(_ data: [UInt8]) -> [UInt8] {
        Array(SHA256.hash(data: data))
    }
    static func hmacSha256(_ key: [UInt8], _ msg: [UInt8]) -> [UInt8] {
        Array(HMAC<SHA256>.authenticationCode(for: msg, using: SymmetricKey(data: key)))
    }
    // PBKDF2-HMAC-SHA256 (CommonCrypto)
    static func pbkdf2(_ password: String, salt: [UInt8], iterations: Int, dkLen: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: dkLen)
        let pw = Array(password.utf8)
        _ = pw.withUnsafeBufferPointer { pwBuf in
            salt.withUnsafeBufferPointer { saltBuf in
                out.withUnsafeMutableBufferPointer { outBuf in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                         pwBuf.baseAddress, pwBuf.count,
                                         saltBuf.baseAddress, saltBuf.count,
                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                         UInt32(iterations),
                         outBuf.baseAddress, outBuf.count)
                }
            }
        }
        return out
    }
    /// kdf 参数钳制: iter 来自**不可信备份信封**，且在 HMAC 校验之前就被用于派生密钥。
    /// 旧实现 `UInt32(iterations)` 对负数或 > UInt32.max 的值直接 trap，超大值等于一次远端可触发的 DoS。
    /// 越界值一律收敛到安全区间：恶意/异常包因此派生出错误密钥，被随后的 HMAC 校验正常拒绝。
    static let iterMin = 1_000
    static let iterMax = 2_000_000
    static func deriveKey(_ password: String, saltHex: String, iter: Int) -> (enc: [UInt8], mac: [UInt8]) {
        let safe = min(max(iter, iterMin), iterMax)
        let sk = pbkdf2(password, salt: HexKit.bytes(saltHex), iterations: safe, dkLen: 48)
        return (Array(sk[0..<16]), Array(sk[16..<48]))
    }
    // AES-128-CBC PKCS7
    static func aesCbcEncrypt(_ plain: [UInt8], key: [UInt8], ivHex: String) throws -> [UInt8] {
        // 2026-10-14 对抗式排查 (功能级): 旧实现**手动 pkcs7Pad 之后又传 kCCOptionPKCS7Padding** —— 双重填充;
        // 且输出缓冲只给 padded.count, 而 CommonCrypto 还会再补一整块 ⇒ kCCBufferTooSmall 被 `_ =` 吞掉,
        // outLen=0 ⇒ 密文恒为空 ⇒ 加密封包/加密导出/交接包**一律打不开**
        // (解密侧先在"密文须为 32 的整数倍"处直接拒)。修法: 不手动补位, 交给 CommonCrypto;
        // 缓冲 = 明文长度 + 一个块。这样也才与 JS/标准 PKCS7 互操作。
        var out = [UInt8](repeating: 0, count: plain.count + kCCBlockSizeAES128)
        var outLen = 0
        let iv = HexKit.bytes(ivHex)
        let status = CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES),
                             CCOptions(kCCOptionPKCS7Padding), key, 16, iv,
                             plain, plain.count, &out, out.count, &outLen)
        // 2026-10-14: 失败必须抛 —— 返回空数组会让 cHex="" 落进包体, 解密侧报"文件头损坏: 密文长度不对",
        // 把"加密失败"误诊成"文件损坏"。
        guard status == kCCSuccess else { throw DFUError.msg("AES 加密失败 (CCCrypt status \(status))") }
        return Array(out.prefix(outLen))
    }
    static func aesCbcDecrypt(_ cipher: [UInt8], key: [UInt8], ivHex: String) throws -> [UInt8] {
        var out = [UInt8](repeating: 0, count: cipher.count + 16)
        var outLen = 0
        let iv = HexKit.bytes(ivHex)
        let status = CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                             CCOptions(kCCOptionPKCS7Padding), key, 16, iv,
                             cipher, cipher.count, &out, out.count, &outLen)
        guard status == kCCSuccess else { throw DFUError.msg("填充无效") }
        return Array(out.prefix(outLen))
    }
    static func concat(_ a: [UInt8], _ b: [UInt8]) -> [UInt8] { a + b }

    // 加密: text → 信封 JSON
    static func encryptText(_ text: String, password: String, iter: Int = defaultIter, saltHex: String? = nil, ivHex: String? = nil) throws -> String {
        let salt = saltHex ?? HexKit.hex(KeyGen.randomBytes(16))
        let iv = ivHex ?? HexKit.hex(KeyGen.randomBytes(16))
        let keys = deriveKey(password, saltHex: salt, iter: iter)
        let ct = try aesCbcEncrypt(Array(text.utf8), key: keys.enc, ivHex: iv)
        let mac = hmacSha256(keys.mac, concat(HexKit.bytes(iv), ct))
        let env = BackupEnvelope(v: 1, alg: "aes-128-cbc+hmac-sha256",
                                 kdf: .init(alg: "pbkdf2-hmac-sha256", iter: iter, saltHex: salt),
                                 ivHex: iv, macHex: HexKit.hex(mac), cHex: HexKit.hex(ct),
                                 meta: .init(size: text.count, at: Date().timeIntervalSince1970 * 1000))
        let d = try JSONEncoder().encode(env)
        return String(data: d, encoding: .utf8) ?? ""
    }

    /// 449: 严格十六进制+长度 —— HexKit.bytes 对坏输入是"尽力解"(奇数长/非 hex 字会静默产出偏短的
    /// 结果), 当校验判据用等于放行; 这里逐字符查, 供信封头校验。
    /// 常量时间字符串比对 —— 用于 MAC / 摘要这类"不能从耗时反推内容"的比较。
    /// 2026-10-27 新增（AUDIT-D D-60）：`==` 会在第一个不同字符处短路，
    /// 攻击者能按响应耗时逐字节猜出正确值。
    /// 实现：长度不同直接 false（长度本身不是秘密）；相同长度则全量异或累积。
    static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<x.count { diff |= x[i] ^ y[i] }
        return diff == 0
    }

    static func isHex(_ s: String, len: Int? = nil) -> Bool {
        if let len, s.count != len { return false }
        return !s.isEmpty && s.allSatisfy { $0.isHexDigit }
    }
    // 解密: 信封 JSON → text (口令错/篡改/版本不符同错误)
    static func decryptEnvelope(_ envelope: String, password: String) throws -> String {
        guard let d = envelope.data(using: .utf8),
              let e = try? JSONDecoder().decode(BackupEnvelope.self, from: d),
              e.v == 1 else {
            throw DFUError.msg("信封格式/版本不支持")
        }
        // 449 声明长度校验: 先验文件头写明的形状, 再碰密码学 —— IV 恰 16 字节 / HMAC 恰 32 字节 /
        // 盐恰 16 字节 / 密文是 16 字节块的整数倍 (都写成十六进制)。形状不对报"文件头损坏"点名哪一段,
        // 不再拖到 MAC 层报"口令错误或数据被篡改" —— 那是两件事, 不该一句话。
        guard isHex(e.ivHex, len: 32) else { throw DFUError.msg("文件头损坏： IV 应为 32 个十六进制字符") }   // 449 文件头损坏
        guard isHex(e.macHex, len: 64) else { throw DFUError.msg("文件头损坏： HMAC 应为 64 个十六进制字符") }   // 449 文件头损坏
        guard isHex(e.kdf.saltHex, len: 32) else { throw DFUError.msg("文件头损坏： 盐应为 32 个十六进制字符") }   // 449 文件头损坏
        guard isHex(e.cHex), e.cHex.count % 32 == 0 else {
            throw DFUError.msg("文件头损坏： 密文应为 32 的整数倍个十六进制字符")   // 449 文件头损坏
        }
        let keys = deriveKey(password, saltHex: e.kdf.saltHex, iter: e.kdf.iter)
        let ct = HexKit.bytes(e.cHex)
        let mac = hmacSha256(keys.mac, concat(HexKit.bytes(e.ivHex), ct))
        // 2026-10-27 审核修复 (AUDIT-D D-60)：HMAC 比对改**常量时间**。
        // 原先用 `==` 比字符串 —— Swift 的字符串相等会在第一个不同字节处短路返回，
        // 攻击者能按响应耗时逐字节猜出正确 MAC（时序侧信道）。
        // 本地备份场景威胁不高（要能反复喂包给你），但这是密码学代码的基本纪律，
        // 而且 `CryptoBox` 里已经有常量时间比对的写法（同文件 :118 附近）。
        guard CryptoBox.constantTimeEqual(HexKit.hex(mac), e.macHex.lowercased()) else { throw DFUError.msg("口令错误或数据被篡改") }
        let plain = try aesCbcDecrypt(ct, key: keys.enc, ivHex: e.ivHex)
        return String(bytes: plain, encoding: .utf8) ?? ""
    }
}

// ---------- 全量备份包 (JS services/bundle.js collectAll/restoreAll 同构) ----------
// BackupBundle 的数据结构已拆到 Engine/BackupBundle.swift（本文件只留读写逻辑）。
@MainActor
enum BackupKit {
    static func collectAll() -> BackupBundle {
        let devices = DB.keychains().map { kc -> BackupBundle.Device in
            let mac = kc.mac
            let l = DB.ledger(mac)
            return BackupBundle.Device(
                mac: mac, kc: kc,
                ledger: (l.pwds.isEmpty && l.fps.isEmpty) ? nil : l,
                meta: BackupBundle.Device.Meta(
                    defend: DB.defend(mac), tailgate: DB.tailgate(mac),
                    synctime: DB.syncTime(mac) == 0 ? nil : DB.syncTime(mac),
                    otpStatus: DB.otpStatus(mac), otpIdx: DB.otpIdx(mac),
                    mobileKeys: MobileKeyService.list(mac).isEmpty ? nil : MobileKeyService.list(mac),
                    // 2026-10-30（第 66 轮）：记录页覆盖层同口径导出。空表置 nil（不写等价空表进备份）。
                    recNotes: RecordOverlay.notes(mac).isEmpty ? nil : RecordOverlay.notes(mac),
                    recFlags: RecordOverlay.flags(mac).isEmpty ? nil : Array(RecordOverlay.flags(mac)).sorted(),
                    recDisps: RecordOverlay.dispositions(mac).isEmpty ? nil
                        : RecordOverlay.dispositions(mac).mapValues { $0.verdict }))
        }
        let dongles = DB.dongles()
        let gws = DB.gateways()
        let passcode = DB.get([String: String].self, "kf_passcode").map {
            BackupBundle.Globals.PasscodeRec(s: $0["s"] ?? "", d: $0["d"] ?? "")
        }
        // 2026-10-30 修复：胁迫码同口径导出（缺省 = 没设过 = 恢复时不动本机）。
        let duress = DB.get([String: String].self, "kf_duress").map {
            BackupBundle.Globals.PasscodeRec(s: $0["s"] ?? "", d: $0["d"] ?? "")
        }
        let trace = DB.get(BackupBundle.Globals.TraceRec.self, "kf_trace_persist_v1")
        return BackupBundle(
            at: DF.iso().string(from: Date()),
            currentMac: DB.currentMac,
            devices: devices,
            members: DB.members().isEmpty ? nil : DB.members(),
            globals: BackupBundle.Globals(
                keychainDongles: dongles.isEmpty ? nil : dongles,
                gatewayList: gws.isEmpty ? nil : gws,
                passcode: passcode,
                duress: duress,
                trace: trace,
                appearance: collectAppearance(),
                deviceOrg: collectDeviceOrg()))
    }
    /// 894 收集外观档。只收**枚举过的档位值**，读到没见过的值就当没这项 (nil)，
    /// 免得把一台机器上的脏数据搬到另一台去。
    /// 外观档的白名单 —— **唯一一份**。
    ///
    /// 2026-10-27 审核修复 (AUDIT-C F6)：原先 `collectAppearance` 与 `applyAppearance`
    /// 各自内联一套**逐字相同**的数组（9 组）。加一个新档位要改两处，
    /// 漏改一处就会出现「能导出但导不回」或反过来的静默丢数据。
    /// 现在两处都读这张表；新增档位只改这里。
    private static let appearanceAllow: [String: [String]] = [
        "kf_theme":      ["", "light", "dark", "black"],
        "kf_accent":     ["", "indigo", "forest", "amber", "graphite", "rose", "aurora"],
        "kf_density":    ["", "compact", "relaxed"],
        "kf_radius":     ["", "soft", "plump"],
        "kf_week_start": ["", "mon", "sun", "sat"],
        "kf_row_h":      ["", "tall"],
        "kf_tl_gap":     ["", "tight", "loose"],
        "kf_motion":     ["", "calm", "standard", "lively"],
        "kf_hero_tex":   ["", "grid", "grain"],
    ]

    static func collectAppearance() -> BackupBundle.Globals.Appearance {
        func enumVal(_ key: String) -> String? {
            let v = DB.store.getString(key)
            guard let allowed = Self.appearanceAllow[key] else { return nil }
            return allowed.contains(v) ? v : nil
        }
        let stats = HeroStats.visible
        let recent = DB.store.getInt("kf_recent_count", 5)
        return BackupBundle.Globals.Appearance(
            theme: enumVal("kf_theme"),
            accent: enumVal("kf_accent"),
            density: enumVal("kf_density"),
            radius: enumVal("kf_radius"),
            hc: DB.store.has("kf_hc") ? DB.store.getBool("kf_hc") : nil,
            weekStart: enumVal("kf_week_start"),
            rowH: enumVal("kf_row_h"),
            tlGap: enumVal("kf_tl_gap"),
            motion: enumVal("kf_motion"),
            heroTex: enumVal("kf_hero_tex"),
            plain: DB.store.has("kf_plain") ? DB.store.getBool("kf_plain") : nil,
            recentCount: [3, 5, 10].contains(recent) ? recent : nil,
            heroStats: stats.count == HeroStats.all.count ? nil : Array(stats).sorted(),
            // 2026-10-30 补（第 65 轮）：无障碍/交互偏好同口径导出。
            // 读侧全部走「键存在才带值」—— 没拨过的开关不该在包里出现一个假默认。
            axBigOtp: DB.store.has("kf_ax_bigotp") ? DB.store.getBool("kf_ax_bigotp") : nil,
            axBigPreview: DB.store.has("kf_ax_bigpreview") ? DB.store.getBool("kf_ax_bigpreview") : nil,
            axHold: DB.store.has("kf_ax_hold") ? DB.store.getString("kf_ax_hold") : nil,
            bigTile: DB.store.has("kf_bigtile") ? DB.store.getBool("kf_bigtile") : nil,
            dialSize: DB.store.has("kf_dial_size") ? DB.store.getInt("kf_dial_size", 176) : nil,
            digitFont: DB.store.has("kf_digit_font") ? DB.store.getString("kf_digit_font") : nil,
            gestureMode: DB.store.has("kf_gesture_mode") ? DB.store.getString("kf_gesture_mode") : nil,
            holdConfirm: DB.store.has("kf_hold_confirm") ? DB.store.getBool("kf_hold_confirm", true) : nil,
            dbltapGuard: DB.store.has("kf_dbltap_guard") ? DB.store.getBool("kf_dbltap_guard", true) : nil,
            elderMode: DB.store.has("kf_elder_mode") ? DB.store.getBool("kf_elder_mode") : nil)
    }
    /// D-36 收集设备组织 (顺序 / 分组 / 分组折叠 / 隐藏)。
    /// 四项全空就整段不带 (缺字段 = 恢复时不动本机); groups 按 mac 排序, 同一份数据两次导出得到同一 canonical。
    static func collectDeviceOrg() -> BackupBundle.Globals.DeviceOrg? {
        let order = LockArchive.orderMacs
        let groups = DB.keychains()
            .map { kc -> (String, String) in (kc.mac, LockArchive.normalizedGroup(LockArchive.group(kc.mac))) }
            .filter { !$0.1.isEmpty }
            .sorted { $0.0 < $1.0 }
            .map { BackupBundle.Globals.DeviceOrg.GroupRec(mac: $0.0, name: $0.1) }
        let folded = (DB.store.get([String].self, "kf_group_folded") ?? []).sorted()
        let hidden = DB.keychains().map { $0.mac }.filter { LockArchive.isHidden($0) }.sorted()
        if order.isEmpty && groups.isEmpty && folded.isEmpty && hidden.isEmpty { return nil }
        return BackupBundle.Globals.DeviceOrg(
            order: order.isEmpty ? nil : order,
            groups: groups.isEmpty ? nil : groups,
            folded: folded.isEmpty ? nil : folded,
            hidden: hidden.isEmpty ? nil : hidden)
    }
    /// 894 应用外观档：**逐值再过一遍白名单**才落盘。
    /// 包体可能来自别的版本或被人改过，读侧的 enumVal 不能只信一次；
    /// 这里每个字段都独立判定，不合格的就跳过 (本机保持原样)，绝不"整包接受"。
    /// 894/D-36: 外观与设备组织随包落地的**唯一**实现 —— overwrite / merge / missing 三条恢复路共用。
    /// 2026-10-14: 原先只有 restoreAll(.overwrite) 走这段, 而 WebDAV 与换机迁移走的是 .merge/.missing
    /// ⇒ 外观与设备顺序/分组/折叠/隐藏整类进不来。抽成一处, 三条路同口径。
    /// 白名单式落地: 顺序只认本包里真有的 mac, 分组只写这些 mac, 折叠只收现在真存在的组, 隐藏只对包内 mac 生效。
    static func applyGlobalsAppearanceAndOrg(_ globals: BackupBundle.Globals, devices: [BackupBundle.Device]) {
        if let ap = globals.appearance { applyAppearance(ap) }
        guard let org = globals.deviceOrg else { return }
        // 2026-10-14: 只对本机**真存在**的锁写 per-lock 键 —— merge 路径下被标 skip 的锁仍在 devices 里,
        // 不取交集会给不存在的锁写 kf_lockmeta_/kf_lock_hidden_ 孤儿键。两侧都归一化, 免得
        // 冒号/大小写差异让交集过小、把本机已有的分组恢复漏掉。
        let known = Set(devices.map { DB.normalizeMac($0.mac) })
            .intersection(DB.keychains().map { DB.normalizeMac($0.mac) })
        if let order = org.order {
            let keep = order.map { DB.normalizeMac($0) }.filter { known.contains($0) }
            // 本机已有、这份包里没有的锁垫在包内顺序之后 (按绑定先后), 不把它们从表里挤掉
            let rest = DB.keychains().map { $0.mac }.filter { !keep.contains($0) }
                .sorted { (DB.keychain($0)?.pairedAt ?? "") < (DB.keychain($1)?.pairedAt ?? "") }
            LockArchive.setOrder(keep + rest)
        }
        if let groups = org.groups {
            for rec in groups where known.contains(DB.normalizeMac(rec.mac)) {
                LockArchive.setGroup(DB.normalizeMac(rec.mac), rec.name)
            }
        }
        if let folded = org.folded {
            let live = Set(LockArchive.grouped(DB.keychains()).map { $0.name })
            let keep = folded.map { LockArchive.normalizedGroup($0) }.filter { live.contains($0) }
            DB.store.setCodable("kf_group_folded", Array(Set(keep)).sorted())
        }
        if let hidden = org.hidden {
            let hid = Set(hidden.map { DB.normalizeMac($0) })
            for mac in known { LockArchive.setHidden(mac, hid.contains(mac)) }
        }
    }
    static func applyAppearance(_ a: BackupBundle.Globals.Appearance) {
        func set(_ key: String, _ v: String?) {
            guard let v, let allowed = Self.appearanceAllow[key], allowed.contains(v) else { return }
            DB.store.set(key, v)
        }
        set("kf_theme", a.theme)
        set("kf_accent", a.accent)
        set("kf_density", a.density)
        set("kf_radius", a.radius)
        set("kf_week_start", a.weekStart)
        set("kf_row_h", a.rowH)
        set("kf_tl_gap", a.tlGap)
        set("kf_motion", a.motion)
        set("kf_hero_tex", a.heroTex)
        if let v = a.hc { DB.store.set("kf_hc", v) }
        if let v = a.plain { DB.store.set("kf_plain", v) }
        if let n = a.recentCount, [3, 5, 10].contains(n) { DB.store.set("kf_recent_count", n) }
        if let stats = a.heroStats {
            // 白名单外的项丢掉; 全空由 HeroStats 自己回退全开 (不留一张没有指标的光板卡)
            DB.store.set("kf_hero_stats", HeroStats.all.filter { stats.contains($0) })
        }
        // 2026-10-30 补（第 65 轮）：无障碍/交互偏好。缺字段 = 这次备份没带 = 不动本机。
        // 拨过这些开关的人换机后最痛：大字/大格/长按时长全回默认 = App 突然不可用。
        if let v = a.axBigOtp { DB.store.set("kf_ax_bigotp", v) }
        if let v = a.axBigPreview { DB.store.set("kf_ax_bigpreview", v) }
        // kf_ax_hold 存的是字符串形态的秒数（"0.9"），恢复时先校验可解析再写
        if let v = a.axHold, Double(v) != nil { DB.store.set("kf_ax_hold", v) }
        if let v = a.bigTile { DB.store.set("kf_bigtile", v) }
        if let n = a.dialSize, [160, 176, 200].contains(n) { DB.store.set("kf_dial_size", n) }
        if let v = a.digitFont, ["", "plain"].contains(v) { DB.store.set("kf_digit_font", v) }
        if let v = a.gestureMode { DB.store.set("kf_gesture_mode", v) }
        if let v = a.holdConfirm { DB.store.set("kf_hold_confirm", v) }
        if let v = a.dbltapGuard { DB.store.set("kf_dbltap_guard", v) }
        if let v = a.elderMode { DB.store.set("kf_elder_mode", v) }
    }
}