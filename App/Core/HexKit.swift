// 十六进制/字节工具 — 与 JS 核心 (utils/crypto.js, kernel/protocol.js) 语义逐项对齐
// 差分基准: fixtures/golden.json (由 vendor JS 核心生成)
import Foundation

nonisolated enum HexKit {
    static func bytes(_ hex: String) -> [UInt8] {
        // 非 hex 字符按 JS hexToBytes 语义落 0x00 且保持长度 (NaN→Uint8Array 强转 0),
        // 否则流会缩短、后续所有偏移错位
        // 旧实现在 Character 含多标量时 (键帽 "1\u{20E3}"、组合音标 é) asciiValue! 直接 fatal。
        // 返回可选并按 JS parseInt(pair,16) 的前缀语义处理: 首字符非 hex → 0; 次字符非 hex → 只取首位。
        func nib(_ c: Character) -> UInt8? {
            guard let a = c.asciiValue else { return nil }
            switch a {
            case 0x30...0x39: return a - 0x30
            case 0x61...0x66: return a - 0x61 + 10
            case 0x41...0x46: return a - 0x41 + 10
            default: return nil
            }
        }
        var out = [UInt8]()
        out.reserveCapacity(hex.count / 2)
        var i = hex.startIndex
        while i < hex.endIndex {
            let c1 = hex[i]
            i = hex.index(after: i)
            guard i < hex.endIndex else { break }   // 奇长末字符两边同丢 (JS substr 语义)
            let c2 = hex[i]
            i = hex.index(after: i)
            // 与 JS parseInt(pair, 16) 对齐: 首字符非 hex → NaN → 0; 次字符非 hex → 只取首位 ("1g"→1 而非 0x10)
            guard let n1 = nib(c1) else { out.append(0); continue }
            if let n2 = nib(c2) { out.append(n1 << 4 | n2) } else { out.append(n1) }
        }
        return out
    }
    static func hex(_ b: [UInt8]) -> String {
        b.map { String(format: "%02x", $0) }.joined()
    }
    static func hex(_ data: Data) -> String { hex([UInt8](data)) }

    // u16/u32 小端写 (JS u16leHex/u32leHex)
    static func u16leHex(_ v: Int) -> String {
        let x = UInt32(truncatingIfNeeded: v)
        return hexPair(x & 0xff) + hexPair((x >> 8) & 0xff)
    }
    static func u32leHex(_ v: UInt32) -> String {
        hexPair(v & 0xff) + hexPair((v >> 8) & 0xff) + hexPair((v >> 16) & 0xff) + hexPair((v >> 24) & 0xff)
    }
    static func hexPair(_ v: UInt32) -> String {
        String(format: "%02x", UInt8(v & 0xff))
    }
    // 小端读
    static func readU16LE(_ hex: String, byteOffset: Int) -> Int {
        let b = bytes(hex)
        guard b.count >= byteOffset + 2 else { return 0 }
        return Int(b[byteOffset]) | (Int(b[byteOffset + 1]) << 8)
    }
    static func readU32LE(_ hex: String, byteOffset: Int) -> UInt32 {
        let b = bytes(hex)
        guard b.count >= byteOffset + 4 else { return 0 }
        return UInt32(b[byteOffset]) | (UInt32(b[byteOffset + 1]) << 8) | (UInt32(b[byteOffset + 2]) << 16) | (UInt32(b[byteOffset + 3]) << 24)
    }
    // JS En.toNormalByteOrder: 字节对反转 (奇数长度返回 '')
    static func reversePairs(_ hex: String) -> String {
        guard hex.count % 2 == 0 else { return "" }
        let b = bytes(hex)
        return Self.hex(Array(b.reversed()))
    }
    // 左补零到 n 字符 (JS fillZeroLeft)
    static func fillZeroLeft(_ s: String, _ chars: Int) -> String {
        var t = s.uppercased()
        while t.count < chars { t = "0" + t }
        return String(t.prefix(max(chars, t.count)))
    }
    // ASCII → hex 右补零到 n 字节 (JS kernel/cmds.js:22 `s.charCodeAt(i) & 0xff` + padEnd, 不截断)
    // 必须按 **UTF-16 码元** 迭代: 旧写法遍历 unicodeScalars, 对 BMP 字符两者一致, 但 emoji 这类
    // 补充平面字符 JS 得到两个代理项 (0xD83D→3d, 0xDE00→00 共 2 字节), Swift 只得到 1 字节 ——
    // 于是"App 台账里的密码"和"实际写进锁的密码"字节不同, 用户下次输入按 JS 口径就开不了锁。
    static func asciiHex(_ s: String, nBytes: Int) -> String {
        var h = ""
        for u in s.utf16 { h += String(format: "%02x", UInt32(u) & 0xff) }
        while h.count < nBytes * 2 { h += "0" }
        return h
    }
    // UTF8 → hex (CryptoJS Utf8.parse().toString() 等价)
    static func utf8Hex(_ s: String) -> String {
        hex(Array(s.utf8))
    }
    static func hexToAscii(_ hex: String) -> String {
        let b = bytes(hex)
        var s = ""
        for x in b {
            if x >= 0x20 && x < 0x7f { s.append(Character(UnicodeScalar(x))) } else { return hex }
        }
        return s
    }
}
