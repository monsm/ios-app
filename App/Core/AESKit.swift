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
}
