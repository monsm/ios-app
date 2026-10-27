// 2026-10-14 对抗式查漏补缺: 门锁密钥材料 (skey/bkey/ekey) 的系统 Keychain 存储。
//
// 此前这些密钥与普通偏好一起, 经 Store.set → JSONSerialization → UserDefaults(plist) **明文落盘** ——
// 越狱设备或一份 iTunes/本机备份就能把整库门锁密钥读走, 而 App 侧那套 AES-128-ECB 的信封
// 全靠 skey 保密 (REVERSE_REPORT §8: skey 泄露 = 可离线构造任意开锁帧)。
//
// 只做"按账户存一个字符串"的最小封装, 不动 Keychain 模型与所有 `kc.skey` 调用点:
// Store.saveKeychain 写这里、Keychain.init(fromDict:) 读这里, 对上层完全透明。
//
// 访问级别 WhenUnlockedThisDeviceOnly（2026-10-27 审核收紧，AUDIT-D D-12）：
//   · WhenUnlocked —— **仅设备解锁时可读**。原先用 AfterFirstUnlock，理由是
//     「覆盖锁屏下的后台任务（428 充电备份要读 skey 做回滚点）」—— 而那条功能已删，
//     全仓 0 处 beginBackgroundTask、0 处 BGTaskScheduler.register ⇒ 这个前提不存在了。
//     收紧后：设备锁屏状态下即使被物理接触（越狱/取证/恶意描述文件）也读不到密钥。
//   · ThisDeviceOnly —— 不随 iCloud/iTunes 备份迁出本机（跨机迁移走 App 自己的加密备份）。
import Foundation
import Security

enum SecretStore {
    private static let service = "com.aapk.OfflineLock.secrets"

    private static func baseQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// 覆盖写。**返回是否成功** —— 调用方据此决定能不能抹掉 plist 里的明文
    /// (写失败还抹明文 = 永久丢密钥, 门锁再也开不了)。
    /// 先 SecItemUpdate 再回退 SecItemAdd: 避免"先删后增"在 add 失败时把既有值也弄丢。
    @discardableResult
    static func set(_ value: String, for account: String) -> Bool {
        let data = Data(value.utf8)
        let st = SecItemUpdate(baseQuery(account) as CFDictionary,
                               [kSecValueData as String: data,
                                // 2026-10-27 (D-12)：更新时顺带把 accessible 属性迁移到新值。
                                // 历史条目的属性不会被 SecItemAdd 纠正（它只在新建时生效），必须走 Update。
                                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly] as CFDictionary)
        if st == errSecSuccess { return true }
        guard st == errSecItemNotFound else { return false }
        var q = baseQuery(account)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func get(_ account: String) -> String? {
        var q = baseQuery(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func remove(_ account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

}
