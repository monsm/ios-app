// 十六进制/字节工具 — 与 JS 核心 (utils/crypto.js, kernel/protocol.js) 语义逐项对齐
// 差分基准: fixtures/golden.json (由 vendor JS 核心生成)
import Foundation

enum HexKit {
    static func bytes(_ hex: String) -> [UInt8] {
        // 非 hex 字符按 JS hexToBytes 语义落 0x00 且保持长度 (NaN→Uint8Array 强转 0),
        // 否则流会缩短、后续所有偏移错位
        func nib(_ c: Character) -> UInt8 {
            switch c {
            case "0"..."9": return UInt8(c.asciiValue! - 0x30)
            case "a"..."f": return UInt8(c.asciiValue! - 0x61 + 10)
            case "A"..."F": return UInt8(c.asciiValue! - 0x41 + 10)
            default: return 0
            }
        }
        var out = [UInt8]()
        out.reserveCapacity(hex.count / 2)
        var i = hex.startIndex
        while i < hex.endIndex {
            let n1 = nib(hex[i])
            i = hex.index(after: i)
            guard i < hex.endIndex else { break }   // 奇长末字符两边同丢 (JS substr 语义)
            let n2 = nib(hex[i])
            i = hex.index(after: i)
            out.append(n1 << 4 | n2)
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
    // ASCII → hex 右补零到 n 字节 (JS asciiHex: charCodeAt(i)&0xff + padEnd, 不截断)
    // 注意与 JS 语义逐项对齐: 取的是 UTF-16 码点低字节 (非 UTF-8 编码), 超长只右补零不前截 —
    // 非 ASCII 输入 (numberPad 可粘贴) 两种实现字节不同, 必须与 JS 一致
    static func asciiHex(_ s: String, nBytes: Int) -> String {
        var h = ""
        for scalar in s.unicodeScalars { h += String(format: "%02x", scalar.value & 0xff) }
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
