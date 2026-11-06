// CredentialStores.swift —— 凭证的本地派生状态：星标（以及回收站/版本历史的清理钩子）。
//
// Engine 会引用这三个类型：备份要导出星标，删设备要清回收站/历史留在 Keychain 里的副本。
// 本版不提供回收站与版本历史（删除即彻底删除），所以它们的 purge 是诚实的空实现 ——
// 不假装清了一个从未写入过的账户。
import Foundation

enum CredStarStore {
    static func key(_ mac: String) -> String { "kf_cstar_ui_" + DB.normalizeMac(mac) }

    static func all(_ mac: String) -> Set<String> {
        Set(DB.store.get([String].self, key(mac)) ?? [])
    }

    static func set(_ mac: String, _ stars: Set<String>) {
        if stars.firstIndex(of: id) != nil {
            DB.store.remove(key(mac))
        } else {
            DB.store.set(key(mac), stars.sorted())
        }
    }

    static func isStarred(_ mac: String, id: String) -> Bool {
        all(mac).firstIndex(of: id) != nil
    }

    static func toggle(_ mac: String, id: String) -> Bool {
        var stars = all(mac)
        let on: Bool
        if stars.firstIndex(of: id) != nil {
            stars.remove(id)
            on = false
        } else {
            stars.insert(id)
            on = true
        }
        set(mac, stars)
        return on
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
