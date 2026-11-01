// CredentialStudioStores.swift —— 凭证工作室的本机存储（回收站 / 版本历史 / 星标）。
//
// 来源：原 App/Core/CredentialOrg.swift 的 kf_cbin_（497-506 回收站）、kf_chist_（487/488 版本快照）、
//   kf_cstar_（526 星标置顶）；引擎精简后只保留命名族，本文件按同一键位补回界面层实现。
// 纪律：全部本机键值，不碰协议层，也不进备份包 schema。
import Foundation

// MARK: - 回收站（kf_cbin_ui_<mac>）

struct CredBinItem: Codable, Identifiable {
    var id: String
    var batchId: String
    var at: Double
    var source: String          // 停用来源（本机单条 / 批量 / 成员级联）
    var pwd: LedgerPwd?
    var fp: LedgerFp?
}

enum CredBinStore {
    static func key(_ mac: String) -> String { "kf_cbin_ui_" + mac }

    /// **读原始存储**（不判空壳、不排序）：只给写路径用。
    /// 写路径绝不能走 `all()` —— 那个在空壳模式会返回 `[]`，
    /// 于是"空壳里做一次删除级联"会把整个回收站**覆盖成只剩新条目**（静默数据丢失）。
    /// 空壳过滤是**展示层**语义，不是存储层语义。
    private static func stored(_ mac: String) -> [CredBinItem] {
        DB.store.get([CredBinItem].self, key(mac)) ?? []
    }

    /// 回收站上限（与版本历史的 10 份同一族：都是"最近删除"，不该无限增长）。
    /// 历史上这里**没有**上限，于是 plist 数组与 Keychain 里的口令副本一起无限堆积。
    static let maxItems = 100

    static func all(_ mac: String) -> [CredBinItem] {
        // SEC-03 残余：空壳不列回收站（条目里带明文 pwd/fp）。
        if DB.isDecoy { return [] }
        let raw = stored(mac)
        // SEC-01：回收站条目里同样存过 LedgerPwd —— 明文口令要回填（写侧已搬进 Keychain）。
        return raw.map { item in
            var copy = item
            if var p = copy.pwd, p.pwd == nil { p.pwd = DB.binSecret(mac, item.id); copy.pwd = p }
            return copy
        }.sorted { $0.at > $1.at }
    }

    /// 写入时统一收口：裁到上限，并把被裁掉条目的 Keychain 副本一并清掉。
    private static func commit(_ mac: String, _ items: [CredBinItem]) {
        var list = items
        if list.count > maxItems {
            let dropped = list.suffix(from: maxItems)
            for item in dropped { SecretStore.remove(DB.binSecretAccount(mac, item.id)) }
            list = Array(list.prefix(maxItems))
        }
        DB.store.setCodable(key(mac), safeForPlist(mac, list))
    }

    /// 写回收站：明文口令进 Keychain，plist 副本不带 pwd。与台账同一套纪律。
    private static func safeForPlist(_ mac: String, _ items: [CredBinItem]) -> [CredBinItem] {
        var out = items
        for i in out.indices {
            guard var p = out[i].pwd, let pwd = p.pwd, !pwd.isEmpty else { continue }
            if SecretStore.set(pwd, for: DB.binSecretAccount(mac, out[i].id)) {
                p.pwd = nil
                out[i].pwd = p
            }
        }
        return out
    }

    static func addPwds(_ mac: String, _ list: [LedgerPwd], batchId: String, source: String) {
        var items = stored(mac)
        let now = Date().timeIntervalSince1970 * 1000
        for p in list {
            items.append(CredBinItem(id: "p:\(p.alias):\(Int(now))", batchId: batchId, at: now,
                                     source: source, pwd: p, fp: nil))
        }
        commit(mac, items)
    }

    static func addFps(_ mac: String, _ list: [LedgerFp], batchId: String, source: String) {
        var items = stored(mac)
        let now = Date().timeIntervalSince1970 * 1000
        for f in list {
            items.append(CredBinItem(id: "f:\(f.batch):\(Int(now))", batchId: batchId, at: now,
                                     source: source, pwd: nil, fp: f))
        }
        commit(mac, items)
    }

    static func restore(_ mac: String, _ item: CredBinItem) -> Bool {
        var items = stored(mac)
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return false }
        if let p = item.pwd { DB.addPwd(mac, p) }
        if let f = item.fp { DB.addFp(mac, f) }
        items.remove(at: index)
        // 还原/彻底删除：条目离开回收站，它的 Keychain 口令副本也一并清掉。
        SecretStore.remove(DB.binSecretAccount(mac, item.id))
        commit(mac, items)
        return true
    }

    static func purge(_ mac: String, _ item: CredBinItem) {
        var items = stored(mac)
        items.removeAll { $0.id == item.id }
        SecretStore.remove(DB.binSecretAccount(mac, item.id))
        commit(mac, items)
    }

    static func clear(_ mac: String) {
        // 清空回收站 = 连 Keychain 里的口令副本一起清（否则残留可读的开门口令）。
        // 用 stored()：空壳里 all() 返回空，那样会把密钥留下而条目被删（孤儿密钥）。
        for item in stored(mac) { SecretStore.remove(DB.binSecretAccount(mac, item.id)) }
        DB.store.remove(key(mac))
    }
}

// MARK: - 版本历史（kf_chist_ui_<mac>）

struct CredSnapshot: Codable, Identifiable {
    var id: String
    var at: Double
    var note: String
    var pwds: [LedgerPwd]
    var fps: [LedgerFp]
}

enum CredHistoryStore {
    static func key(_ mac: String) -> String { "kf_chist_ui_" + mac }

    /// 同 CredBinStore.stored：写路径必须读**原始存储**，不能走空壳过滤后的 `all()`，
    /// 否则空壳里做一次 capture 会把整段版本历史覆盖成只剩这一份。
    private static func stored(_ mac: String) -> [CredSnapshot] {
        DB.store.get([CredSnapshot].self, key(mac)) ?? []
    }

    static func all(_ mac: String) -> [CredSnapshot] {
        // SEC-03 残余：空壳不列版本历史（快照里带整份台账副本）。
        if DB.isDecoy { return [] }
        let raw = (DB.store.get([CredSnapshot].self, key(mac)) ?? [])
        // SEC-01：快照是整份台账的副本 —— 明文口令回填（写侧已搬进 Keychain）。
        return raw.map { snap in
            var copy = snap
            for i in copy.pwds.indices where copy.pwds[i].pwd == nil {
                copy.pwds[i].pwd = DB.snapshotSecret(mac, snap.id, copy.pwds[i].alias)
            }
            return copy
        }.sorted { $0.at > $1.at }
    }

    static func capture(_ mac: String, note: String) {
        var list = stored(mac)
        let l = DB.ledger(mac)
        var snap = CredSnapshot(id: UUID().uuidString, at: Date().timeIntervalSince1970 * 1000,
                                note: note, pwds: l.pwds, fps: l.fps)
        // SEC-01：先写 Keychain，写成功才抹掉快照里的明文（与台账同一纪律）。
        for i in snap.pwds.indices {
            guard let pwd = snap.pwds[i].pwd, !pwd.isEmpty else { continue }
            if SecretStore.set(pwd, for: DB.snapshotSecretAccount(mac, snap.id, snap.pwds[i].alias)) {
                snap.pwds[i].pwd = nil
            }
        }
        list.insert(snap, at: 0)
        // 只留 10 份：被裁掉的快照的 Keychain 副本也一并清（否则口令无限堆积）。
        while list.count > 10 {
            let dropped = list.removeLast()
            for p in dropped.pwds { SecretStore.remove(DB.snapshotSecretAccount(mac, dropped.id, p.alias)) }
        }
        DB.store.setCodable(key(mac), list)
    }

    static func restore(_ mac: String, _ snap: CredSnapshot) {
        var l = Ledger()
        l.pwds = snap.pwds
        l.fps = snap.fps
        DB.saveLedger(mac, l)
    }
}

// MARK: - 星标（kf_cstar_ui_<mac>）

enum CredStarStore {
    static func key(_ mac: String) -> String { "kf_cstar_ui_" + mac }

    static func all(_ mac: String) -> Set<String> {
        Set(DB.store.get([String].self, key(mac)) ?? [])
    }

    static func isStarred(_ mac: String, _ id: String) -> Bool { all(mac).contains(id) }

    @discardableResult
    static func toggle(_ mac: String, _ id: String) -> Bool {
        var set = all(mac)
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        DB.store.set(key(mac), set.sorted())
        return set.contains(id)
    }
}
