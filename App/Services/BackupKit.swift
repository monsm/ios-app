// 备份加密信封 + WebDAV 同步 — JS utils/cloudcrypto.js + services/cloudsync.js 移植
//   信封: PBKDF2-HMAC-SHA256(60000) → AES-128-CBC + HMAC-SHA256 (encrypt-then-MAC)
//   端点: 坚果云 WebDAV「我的坚果云/zklock-backup.enc」(Basic 认证, 应用专属密码)
//   与小程序端信封 JSON 格式完全互通 (v1: {v,alg,kdf,ivHex,macHex,cHex,meta})
import Foundation
import CryptoKit
import CommonCrypto

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
    static func deriveKey(_ password: String, saltHex: String, iter: Int) -> (enc: [UInt8], mac: [UInt8]) {
        let sk = pbkdf2(password, salt: HexKit.bytes(saltHex), iterations: iter, dkLen: 48)
        return (Array(sk[0..<16]), Array(sk[16..<48]))
    }
    // AES-128-CBC PKCS7
    static func aesCbcEncrypt(_ plain: [UInt8], key: [UInt8], ivHex: String) -> [UInt8] {
        let padded = pkcs7Pad(plain)
        var out = [UInt8](repeating: 0, count: padded.count)
        var outLen = 0
        let iv = HexKit.bytes(ivHex)
        _ = CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES),
                    CCOptions(kCCOptionPKCS7Padding), key, 16, iv,
                    padded, padded.count, &out, out.count, &outLen)
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
    static func pkcs7Pad(_ b: [UInt8]) -> [UInt8] {
        let pad = 16 - (b.count % 16)
        return b + [UInt8](repeating: UInt8(pad), count: pad)
    }
    static func concat(_ a: [UInt8], _ b: [UInt8]) -> [UInt8] { a + b }

    // 加密: text → 信封 JSON
    static func encryptText(_ text: String, password: String, iter: Int = defaultIter, saltHex: String? = nil, ivHex: String? = nil) throws -> String {
        let salt = saltHex ?? HexKit.hex(KeyGen.randomBytes(16))
        let iv = ivHex ?? HexKit.hex(KeyGen.randomBytes(16))
        let keys = deriveKey(password, saltHex: salt, iter: iter)
        let ct = aesCbcEncrypt(Array(text.utf8), key: keys.enc, ivHex: iv)
        let mac = hmacSha256(keys.mac, concat(HexKit.bytes(iv), ct))
        let env = BackupEnvelope(v: 1, alg: "aes-128-cbc+hmac-sha256",
                                 kdf: .init(alg: "pbkdf2-hmac-sha256", iter: iter, saltHex: salt),
                                 ivHex: iv, macHex: HexKit.hex(mac), cHex: HexKit.hex(ct),
                                 meta: .init(size: text.count, at: Date().timeIntervalSince1970 * 1000))
        let d = try JSONEncoder().encode(env)
        return String(data: d, encoding: .utf8) ?? ""
    }
    // 解密: 信封 JSON → text (口令错/篡改/版本不符同错误)
    static func decryptEnvelope(_ envelope: String, password: String) throws -> String {
        guard let d = envelope.data(using: .utf8),
              let e = try? JSONDecoder().decode(BackupEnvelope.self, from: d),
              e.v == 1, !e.ivHex.isEmpty, !e.macHex.isEmpty, !e.cHex.isEmpty, !e.kdf.saltHex.isEmpty else {
            throw DFUError.msg("信封格式/版本不支持")
        }
        let keys = deriveKey(password, saltHex: e.kdf.saltHex, iter: e.kdf.iter)
        let ct = HexKit.bytes(e.cHex)
        let mac = hmacSha256(keys.mac, concat(HexKit.bytes(e.ivHex), ct))
        guard HexKit.hex(mac) == e.macHex.lowercased() else { throw DFUError.msg("口令错误或数据被篡改") }
        let plain = try aesCbcDecrypt(ct, key: keys.enc, ivHex: e.ivHex)
        return String(bytes: plain, encoding: .utf8) ?? ""
    }
}

// ---------- 全量备份包 (JS services/bundle.js collectAll/restoreAll 同构) ----------
struct BackupBundle: Codable {
    var type: String = "kf-bundle"
    var bundleVer: Int = 2
    var schema: Int = 5
    var at: String
    var currentMac: String = ""
    var devices: [Device]
    var members: [Member]?
    var globals: Globals?
    struct Device: Codable {
        var mac: String
        var kc: Keychain
        var ledger: Ledger?
        var meta: Meta?
        struct Meta: Codable {
            var defend: DefendCfg?
            var tailgate: TailgateCfg?
            var synctime: Double?
            var otpStatus: OtpStatus?
            var otpIdx: OtpIdx?
        }
    }
    struct Globals: Codable {
        var keychainDongles: [Dongle]?
        var gatewayList: [Gateway]?
        var passcode: PasscodeRec?   // JS 包互通: {s,d} 应用锁摘要
        var trace: TraceRec?         // JS 包互通: LOCK 日志恢复档 (原样存取)
        struct PasscodeRec: Codable { var s: String; var d: String }
        struct TraceRec: Codable { var savedAt: Double?; var count: Int?; var chars: Int?; var lines: [String]? }
    }
    var checksum: String?
}

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
                    otpStatus: DB.otpStatus(mac), otpIdx: DB.otpIdx(mac)))
        }
        let dongles = DB.dongles()
        let gws = DB.gateways()
        let passcode = DB.get([String: String].self, "kf_passcode").map {
            BackupBundle.Globals.PasscodeRec(s: $0["s"] ?? "", d: $0["d"] ?? "")
        }
        let trace = DB.get(BackupBundle.Globals.TraceRec.self, "kf_trace_persist_v1")
        return BackupBundle(
            at: ISO8601DateFormatter().string(from: Date()),
            currentMac: DB.currentMac,
            devices: devices,
            members: DB.members().isEmpty ? nil : DB.members(),
            globals: BackupBundle.Globals(
                keychainDongles: dongles.isEmpty ? nil : dongles,
                gatewayList: gws.isEmpty ? nil : gws,
                passcode: passcode,
                trace: trace))
    }
    @discardableResult
    static func restoreAll(_ bundle: BackupBundle) -> (imported: Int, overwritten: Int) {
        // 成员先归位 (同名并入)
        var remap = [String: String]()
        if let members = bundle.members {
            for m in members {
                if let hit = DB.members().first(where: { $0.name == m.name }) {
                    remap[m.id] = hit.id
                    DB.setMemberInfo(hit.id, ["relation": m.relation, "phone": m.phone])
                } else if let created = DB.addMember(m.name) {
                    remap[m.id] = created.id
                    DB.setMemberInfo(created.id, ["relation": m.relation, "phone": m.phone])
                }
            }
        }
        var imported = 0, overwritten = 0
        for d in bundle.devices {
            guard HexKit.bytes(d.mac).count == 6, !d.kc.skey.isEmpty else { continue }
            var kc = d.kc
            kc.mac = DB.normalizeMac(d.mac)   // 归一化 (JS 包可能带冒号/大写)
            let existed = DB.keychain(kc.mac) != nil
            DB.saveKeychain(kc)
            if let l = d.ledger {
                var fixed = l
                for i in fixed.pwds.indices where fixed.pwds[i].owner != nil { fixed.pwds[i].owner = remap[fixed.pwds[i].owner!] ?? fixed.pwds[i].owner }
                for i in fixed.fps.indices where fixed.fps[i].owner != nil { fixed.fps[i].owner = remap[fixed.fps[i].owner!] ?? fixed.fps[i].owner }
                DB.saveLedger(kc.mac, fixed)
            }
            if let meta = d.meta {
                if let c = meta.defend { DB.saveDefend(kc.mac, c) }
                if let c = meta.tailgate { DB.saveTailgate(kc.mac, c) }
                if let t = meta.synctime { DB.saveSyncTime(kc.mac, t) }
                if let o = meta.otpStatus { DB.saveOtpStatus(kc.mac, o) }
                if let o = meta.otpIdx { DB.saveOtpIdx(kc.mac, o) }
            }
            if existed { overwritten += 1 } else { imported += 1 }
        }
        if let globals = bundle.globals {
            for d in globals.keychainDongles ?? [] { DB.saveDongle(d) }
            for g in globals.gatewayList ?? [] { DB.saveGateway(g) }
            if let pc = globals.passcode, !pc.s.isEmpty, !pc.d.isEmpty {
                DB.store.set("kf_passcode", ["s": pc.s, "d": pc.d]) // 应用锁摘要跨端迁移
            }
            if let tr = globals.trace, let lines = tr.lines, !lines.isEmpty {
                DB.store.set("kf_trace_persist_v1", [
                    "savedAt": tr.savedAt ?? 0, "count": lines.count,
                    "chars": tr.chars ?? 0, "lines": lines,
                ])
            }
        }
        let normCurrent = DB.normalizeMac(bundle.currentMac)
        if DB.keychain(normCurrent) != nil { DB.currentMac = normCurrent }
        return (imported, overwritten)
    }
}

// ---------- WebDAV 同步 (JS services/cloudsync.js) ----------
enum CloudSync {
    static let remoteURL = "https://dav.jianguoyun.com/dav/%E6%88%91%E7%9A%84%E5%9D%9A%E6%9E%9C%E4%BA%91/zklock-backup.enc"
    static func basicAuth(_ acct: String, _ app: String) -> String {
        let raw = Data("\(acct):\(app)".utf8).base64EncodedString()
        return "Basic \(raw)"
    }
    static func push(acct: String, app: String, envelope: String) async throws {
        var req = URLRequest(url: URL(string: remoteURL)!)
        req.httpMethod = "PUT"
        req.timeoutInterval = 20
        req.setValue(basicAuth(acct, app), forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(envelope.utf8)
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw DFUError.msg("网络请求失败") }
        if (200..<300).contains(http.statusCode) { return }
        if http.statusCode == 401 || http.statusCode == 403 { throw DFUError.msg("账号或应用密码错误 (坚果云需「应用专属密码」)") }
        if http.statusCode == 507 || http.statusCode == 509 { throw DFUError.msg("坚果云免费额度已满, 请清理或升级") }
        throw DFUError.msg("上传失败 HTTP \(http.statusCode)")
    }
    static func download(acct: String, app: String) async throws -> String? {
        var req = URLRequest(url: URL(string: remoteURL)!)
        req.httpMethod = "GET"
        req.timeoutInterval = 20
        req.setValue(basicAuth(acct, app), forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw DFUError.msg("网络请求失败") }
        if http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 { throw DFUError.msg("账号或应用密码错误") }
            throw DFUError.msg("下载失败 HTTP \(http.statusCode)")
        }
        return String(data: data, encoding: .utf8)
    }
}