// 配网密钥族生成器 — JS utils/keys.js 移植 (系统 CSPRNG: SecRandomCopyBytes)
//   skey  = 16B 随机 (32 hex)
//   pins  = n×4B LE 随机, 顶字节 &0x7F (值 < 2^31), 池内互不重复
//   bkey  = 16B 随机 + 相邻字节约束变换 (|a-prev|<=2 → a+=6; >255 → a=6)
//   trackId = 随机 < 2^31
import Foundation
import Security

enum KeyGen {
    static let delPinSentinel = "ffffffff"

    static func randomBytes(_ n: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: n)
        if n > 0 {
            _ = SecRandomCopyBytes(kSecRandomDefault, n, &out)
        }
        return out
    }
    // pin: 4B → 高位清 0x7F → 按 LE 序输出 hex (JS _pinFromBytes)
    static func genPin() -> String {
        var b = randomBytes(4)
        b[0] &= 0x7f
        return HexKit.hex([b[3], b[2], b[1], b[0]])
    }
    static func genPins(_ n: Int) throws -> [String] {
        var out = [String]()
        var seen = Set<String>()
        var guardBudget = n * 512 + 256
        while out.count < n {
            if guardBudget <= 0 { throw NSError(domain: "KeyGen", code: 1, userInfo: [NSLocalizedDescriptionKey: "随机源异常: 无法生成 \(n) 个唯一 PIN"]) }
            guardBudget -= 1
            let p = genPin()
            if seen.contains(p) { continue }
            seen.insert(p)
            out.append(p)
        }
        return out
    }
    static func genSkey() -> String { HexKit.hex(randomBytes(16)) }
    static func genBkey() -> String {
        var b = randomBytes(16)
        for i in 1..<16 {
            let prev = Int(b[i - 1])
            let cur = Int(b[i])
            if abs(cur - prev) <= 2 {
                var v = cur + 6
                if v > 255 { v = 6 }
                b[i] = UInt8(v)
            }
        }
        return HexKit.hex(b)
    }
    static func genTrackId() -> UInt32 {
        UInt32(truncatingIfNeeded: Int64.random(in: 0..<Int64(0x7fffffff)))
    }
    /// 351 合包导出解密密口令: n 位数字 (CSPRNG)
    static func randomDigits(_ n: Int) -> String {
        String(randomBytes(n).map { "0123456789"[Int($0 % 10)] })
    }
}