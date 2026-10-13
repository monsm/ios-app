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
        guard n > 0 else { return [] }
        var out = [UInt8](repeating: 0, count: n)
        // 旧写法 `_ =` 把状态码丢了: SecRandomCopyBytes 一旦失败, out 原样保持**全零**,
        // 于是配网会生成一把"密钥 = 32 个 0"的门锁且毫无提示 —— 这是 fail-open 级缺陷, 不是理论风险。
        if SecRandomCopyBytes(kSecRandomDefault, n, &out) == errSecSuccess { return out }
        // 失败则改用同为 OS 种子的系统随机源 (底层 arc4random_buf), 绝不返回全零缓冲;
        // 若两条路径都异常, isAllZero 仍可被上层检出并拒绝落库。
        for i in out.indices { out[i] = UInt8.random(in: 0...255) }
        return out
    }
    /// 全零 = 随机源故障的特征值。第九十一批删掉了 `isAllZero([UInt8])` 那份:
    /// 它的注释写着"调用点: 配网/钥匙圈生成"，而全仓**一个调用点都没有** (deadscan 剥注释后才报出来)。
    /// 现役的那道闸是**十六进制形式** —— LockService.swift:535-536 在写库前用 isAllZeroHex 逐个核
    /// skey / bkey / pins，字节形态没有独立的产生点，所以不需要两份。
    /// 留着"字节形态那份 + 一句谎话式的调用点注释"比删掉危险: 下一个人会以为已经防住了。
    static func isAllZeroHex(_ hex: String) -> Bool {
        guard hex.count >= 2, hex.allSatisfy({ $0 == "0" }) else { return false }
        return true
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
        // 旧写法 `"0123456789"[Int(...)]`: String 没有 Int 下标 (需 String.Index) → 编译不过
        let digits = Array("0123456789")
        return String(randomBytes(n).map { digits[Int($0) % digits.count] })
    }
}