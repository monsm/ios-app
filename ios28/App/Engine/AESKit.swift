// AES-128-ECB + ZeroPadding — CommonCrypto 实现, 与 JS utils/crypto.js 字节级一致
// 差分基准: golden.aes.* (NIST 向量 + 回环)
import Foundation
import CommonCrypto

enum AESKit {
    static func encryptHex(_ plainHex: String, keyHex: String) -> String {
        var plain = HexKit.bytes(plainHex)
        // ZeroPadding: 补 0x00 到 16 的倍数 (已对齐则不补)
        let rem = plain.count % 16
        if rem != 0 { plain.append(contentsOf: [UInt8](repeating: 0, count: 16 - rem)) }
        let key = HexKit.bytes(keyHex)
        guard key.count == 16 else { return "" }
        var out = [UInt8](repeating: 0, count: plain.count)
        var outLen = 0
        let status = CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES),
                             CCOptions(kCCOptionECBMode),
                             key, key.count, nil,
                             plain, plain.count,
                             &out, out.count, &outLen)
        guard status == kCCSuccess else { return "" }
        return HexKit.hex(Array(out.prefix(outLen)))
    }

    /// AES-128-ECB 解密（ZeroPadding，不剥填充 —— 调用方按自己的字段偏移取值）。
    ///
    /// 2026-11-02 补：`DiagSnapshot` 要解出「存的那枚 ekey 里嵌的是哪一枚 PIN」，
    /// 用于和锁端存量比对。**只用于诊断比对**，解出的明文不进任何日志/导出。
    static func decryptHex(_ cipherHex: String, keyHex: String) -> String? {
        let cipher = HexKit.bytes(cipherHex)
        let key = HexKit.bytes(keyHex)
        guard key.count == 16, cipher.count % 16 == 0, !cipher.isEmpty else { return nil }
        var out = [UInt8](repeating: 0, count: cipher.count)
        var outLen = 0
        let status = CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                             CCOptions(kCCOptionECBMode),
                             key, key.count, nil,
                             cipher, cipher.count,
                             &out, out.count, &outLen)
        guard status == kCCSuccess else { return nil }
        return HexKit.hex(Array(out.prefix(outLen)))
    }
}
