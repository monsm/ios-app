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

    static func decryptHex(_ cipherHex: String, keyHex: String) -> String {
        let cipher = HexKit.bytes(cipherHex)
        guard cipher.count > 0, cipher.count % 16 == 0 else { return "" }
        let key = HexKit.bytes(keyHex)
        guard key.count == 16 else { return "" }
        var out = [UInt8](repeating: 0, count: cipher.count)
        var outLen = 0
        let status = CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                             CCOptions(kCCOptionECBMode),
                             key, key.count, nil,
                             cipher, cipher.count,
                             &out, out.count, &outLen)
        guard status == kCCSuccess else { return "" }
        // JS decryptHex 不剥尾 0 ("ZeroPadding 解密不剥尾 0, 由上层按长度截取") — 保持一致
        return HexKit.hex(Array(out.prefix(outLen)))
    }
}
