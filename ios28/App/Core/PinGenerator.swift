// PinGenerator.swift —— 门锁密码的生成与弱模式识别（F19）。
//
// 门锁键盘只有数字，所以密码只能是数字串 —— 这让「随机」比字母密码更容易被猜：
// 6 位只有 100 万种，而**人会挑好记的**（123456、000000、生日）。
// 于是「随机生成」如果不管弱模式，等于替用户挑了一个会被猜中的密码。
//
// 这里生成的码保证：
//   · 至少 3 个不同数字；
//   · 不是全部相同；
//   · 不是连号（含升序与降序）；
//   · 不含常见的弱口令。
//
// 随机源用 `SystemRandomNumberGenerator`（系统 CSPRNG），不用 `Int.random`。
import Foundation

enum PinGenerator {
    /// 常见的弱口令（锁键盘能直接按出来的那些）。
    static let weakCodes: Set<String> = [
        "000000", "111111", "222222", "333333", "444444", "555555",
        "666666", "777777", "888888", "999999",
        "123456", "654321", "123123", "121212", "112233", "696969",
        "000001", "100000", "520520", "1314520", "2580", "135790",
    ]

    /// 生成一串数字码。
    static func generate(length: Int = 6) -> String {
        let n = max(4, min(8, length))
        var rng = SystemRandomNumberGenerator()
        for _ in 0 ..< 64 {
            var digits = ""
            for _ in 0 ..< n {
                digits.append(String(Int.random(in: 0 ... 9, using: &rng)))
            }
            if !isWeak(digits) { return digits }
        }
        // 极端情况（几乎不可能）：退回一个确定不弱的码。
        return fallback(n)
    }

    /// 这串码是不是「弱」的。
    static func isWeak(_ code: String) -> Bool {
        let chars = Array(code)
        guard chars.count >= 4 else { return true }
        if Set(chars).count < 3 { return true }                    // 少于 3 个不同数字
        if chars.allSatisfy({ $0 == chars[0] }) { return true }     // 全同
        if isRun(chars, step: 1) || isRun(chars, step: -1) { return true }  // 连号
        if hasTripleRun(chars) { return true }                     // 含 123 / 321 这类三连
        if weakCodes.contains(code) { return true }
        return false
    }

    /// 弱在哪（给界面一句话）。不弱时返回 nil。
    static func hint(_ code: String) -> String? {
        let chars = Array(code)
        guard chars.count >= 4 else { return "太短了，至少 4 位" }
        if Set(chars).count < 3 { return "只有一两种数字，太好猜" }
        if chars.allSatisfy({ $0 == chars[0] }) { return "全是同一个数字" }
        if isRun(chars, step: 1) || isRun(chars, step: -1) { return "连号，最好猜的一种" }
        if hasTripleRun(chars) { return "含连号片段" }
        if weakCodes.contains(code) { return "这是最常见的那几个密码之一" }
        return nil
    }

    private static func isRun(_ chars: [Character], step: Int) -> Bool {
        guard chars.count >= 4 else { return false }
        for i in 0 ..< (chars.count - 3) {
            let a = chars[i].wholeNumberValue ?? 0
            let b = chars[i + 1].wholeNumberValue ?? 0
            let c = chars[i + 2].wholeNumberValue ?? 0
            let d = chars[i + 3].wholeNumberValue ?? 0
            if b - a == step && c - b == step && d - c == step { return true }
        }
        return false
    }

    private static func hasTripleRun(_ chars: [Character]) -> Bool {
        guard chars.count >= 3 else { return false }
        for i in 0 ..< (chars.count - 2) {
            let a = chars[i].wholeNumberValue ?? 0
            let b = chars[i + 1].wholeNumberValue ?? 0
            let c = chars[i + 2].wholeNumberValue ?? 0
            if (b - a == 1 && c - b == 1) || (a - b == 1 && b - c == 1) { return true }
        }
        return false
    }

    private static func fallback(_ n: Int) -> String {
        // 一个确定的、不弱的 6 位（不是密码，是占位 —— 真的会走到这里的概率约等于 0）。
        let pool = [7, 3, 8, 1, 9, 4, 6, 2]
        var out = ""
        for i in 0 ..< n { out.append(String(pool[i % pool.count])) }
        return out
    }
}
