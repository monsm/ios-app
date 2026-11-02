// 包7 安全·隐私·审计 — 纯逻辑层 (无 SwiftUI 依赖, 便于单测与 golden 差分)
//
// ⚠ 2026-11-01（Round 305）逐条核实：**本文件只有 `HashKit`（3 个哈希基元），没有别的。**
//
// 头注此前列出三个「子模块」，实际全仓**一个都没有**：
//   · `AuditLog`   —— 无任何类型声明、无调用点。
//   · `AuditChain` —— 同上；也没有任何"哈希覆盖前序哈希"的链式实现（`sha256Hex` 只是无状态的哈希函数）。
//   · `DestroyKit` —— 第 99 轮已核实不存在。
//   第 99 轮修 `DestroyKit` 那句时，把 `AuditLog / AuditChain` 当成了「实际有的两项」，
//   **于是修掉一条假声明的同时留下了一条新的**（原句「实际只有上面两项」）。
//
// 真实的留痕是什么（写在这里，免得下一个人再去找 `AuditLog`）：
//   · 台账变更：`StoreLedger.ledgerDiff` 算出字段前后差异 → `BleTelemetry.recordEvent`（**200 条上限、落 Caches、不进备份**）。
//   · 口令只记 `HashKit.fingerprint` 前 4 位，明文不落任何留痕（SEC-13）。
//   · `HashKit.sha256Hex` / `fnv1a32` 作为基元保留，供上面的指纹使用；**没有任何防篡改链**。
//
// 真要「审计留痕 / 防篡改链 / 核弹销毁」，都得先定清：审计对象是谁、存哪里、谁来验、删除边界在哪。
// 在那之前，任何「本 App 有防篡改审计链」的说法都不成立。
// 存储键全部 kf_ 前缀, 与小程序/备份互通语义一致; 只经 DB.store 读写, 不改 Store 本身。
import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(CommonCrypto)
import CommonCrypto
#endif

// ---------- 哈希基元 (SHA-256 hex, 本地轻量防篡改) ----------
enum HashKit {
    /// SHA-256 → 小写十六进制。CryptoKit 不可用 (旧工具链) 时退化为 FNV-1a32 双轮拼接,
    /// 只要求"改一条即破链"的防篡改性质, 不要求密码学强度 (离线 App, 无中心校验方)。
    static func sha256Hex(_ s: String) -> String {
        #if canImport(CryptoKit)
        return SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
        #else
        let a = String(fnv1a32(s), radix: 16)
        let b = String(fnv1a32("kf2." + s.reversed().map { $0 } .description), radix: 16)
        return a + b
        #endif
    }

    /// HMAC 风格的"口令→指纹" (382 脱敏导出用): 只留前 4 位, 不可逆推原值
    static func fingerprint(_ s: String) -> String {
        String(sha256Hex(s).prefix(4))
    }

    static func fnv1a32(_ s: String) -> UInt32 {
        var hash: UInt32 = 0x811C9DC5
        for ch in s.unicodeScalars {
            hash ^= UInt32(ch.value & 0xFF)
            hash = hash &* 0x01000193
        }
        return hash
    }
}






