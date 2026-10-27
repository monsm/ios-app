// 包7 安全·隐私·审计 — 纯逻辑层 (无 SwiftUI 依赖, 便于单测与 golden 差分)
// 三个子模块:
//   AuditLog   审计留痕: 开门/管理双流水 + 字段 diff + 敏感操作台账 + 脱敏导出
//   AuditChain 防篡改哈希链: 每事件哈希覆盖前序哈希 (本地轻量 SHA-256 链)
//   DestroyKit 数据销毁: 等价覆写 (Store 底层是 UserDefaults plist, 覆写 = 随机字节重灌+删除)
//               + 销毁前备份闸 + 残留全文检查
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







enum DestroyKit {
    /// 400 销毁前备份闸: 7 天内无备份文件即拦截。
    /// 备份时间戳读 Sheets 既有 kf_backup_hist ([Double] 时间线), 不另造写点。
    /// 这本历史写的是 epoch **毫秒** (Milestones.recordBackup: *1000), 读数处统一换算成秒。
    static var lastBackupAt: Double {
        let hist = DB.store.get([Double].self, "kf_backup_hist") ?? []
        return (hist.last ?? 0) / 1000
    }
    static var backupGatePass: Bool {
        lastBackupAt > 0 && Date().timeIntervalSince1970 - lastBackupAt < 7 * 86400
    }
}