// CredentialStores.swift —— 凭证的本地派生状态：星标（以及回收站/版本历史的清理钩子）。
//
// Engine 会引用这三个类型：备份要导出星标，删设备要清回收站/历史留在 Keychain 里的副本。
// 本版不提供回收站与版本历史（删除即彻底删除），所以它们的 purge 是诚实的空实现 ——
// 不假装清了一个从未写入过的账户。
import Foundation

enum CredStarStore {
    static func key(_ mac: String) -> String { "kf_cstar_ui_" + DB.normalizeMac(mac) }

    /// 读星标集合。注意取值的参数序：`DB.get` 是「类型在前、键在后」；
    /// 而底层 `Store.get` 两个序都合法，Swift 按参数序解析重载 —— 写反了会静默拿到 nil。
    static func all(_ mac: String) -> Set<String> {
        // 空壳里没有凭证，也就不该有星标：星标集合本身会泄露「这台手机上有多少枚常用凭证」。
        if DB.isDecoy { return [] }
        return Set(DB.get([String].self, key(mac)) ?? [])
    }

    /// 写星标集合。空集合直接删键，不留一个 `[]` 的空壳。
    /// 注意写值的参数序：`Store.set` 是「键在前、值在后」，与 `DB.set`（值在前）相反。
    static func set(_ mac: String, _ stars: Set<String>) {
        // 写路径一律拒绝空壳。界面层的两处写调用（详情页的加星 / 取消星标）
        // 都不经过 AppModel，守卫放在这里才是唯一可靠的落点。
        if DB.isDecoy { return }
        if stars.isEmpty {
            DB.store.remove(key(mac))
        } else {
            DB.store.set(key(mac), stars.sorted())
        }
    }

    static func isStarred(_ mac: String, id: String) -> Bool {
        all(mac).firstIndex(of: id) != nil
    }

    /// 切换星标，返回切换之后的状态（true = 现在是星标）。
    @discardableResult
    static func toggle(_ mac: String, id: String) -> Bool {
        var stars = all(mac)
        let wasOn = stars.remove(id) != nil
        if !wasOn { stars.insert(id) }
        set(mac, stars)
        return !wasOn
    }
}

enum CredBinStore {
    /// 回收站上限（与上一版同口径；本版不启用回收站，保留常量给备份/文档对照）。
    static let maxItems = 100

    /// 本版没有回收站：删除凭证时不会写 `ledger.<mac>.bin.*`，因此没有 Keychain 副本要清。
    /// 保留入口，避免 `DB.removeDevice` 的清理清单出现缺口（将来加回收站时只改这里）。
    static func purgeSecretsForDevice(_ mac: String) {}
}

enum CredHistoryStore {
    /// 本版没有版本历史：不会写 `ledger.<mac>.snap.*`，因此没有 Keychain 副本要清。
    static func purgeSecretsForDevice(_ mac: String) {}
}
