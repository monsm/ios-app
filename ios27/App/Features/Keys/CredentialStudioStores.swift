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

    static func all(_ mac: String) -> [CredBinItem] {
        (DB.store.get([CredBinItem].self, key(mac)) ?? []).sorted { $0.at > $1.at }
    }

    static func addPwds(_ mac: String, _ list: [LedgerPwd], batchId: String, source: String) {
        var items = all(mac)
        let now = Date().timeIntervalSince1970 * 1000
        for p in list {
            items.append(CredBinItem(id: "p:\(p.alias):\(Int(now))", batchId: batchId, at: now,
                                     source: source, pwd: p, fp: nil))
        }
        DB.store.setCodable(key(mac), items)
    }

    static func addFps(_ mac: String, _ list: [LedgerFp], batchId: String, source: String) {
        var items = all(mac)
        let now = Date().timeIntervalSince1970 * 1000
        for f in list {
            items.append(CredBinItem(id: "f:\(f.batch):\(Int(now))", batchId: batchId, at: now,
                                     source: source, pwd: nil, fp: f))
        }
        DB.store.setCodable(key(mac), items)
    }

    static func restore(_ mac: String, _ item: CredBinItem) -> Bool {
        var items = all(mac)
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return false }
        if let p = item.pwd { DB.addPwd(mac, p) }
        if let f = item.fp { DB.addFp(mac, f) }
        items.remove(at: index)
        DB.store.setCodable(key(mac), items)
        return true
    }

    static func purge(_ mac: String, _ item: CredBinItem) {
        var items = all(mac)
        items.removeAll { $0.id == item.id }
        DB.store.setCodable(key(mac), items)
    }

    static func clear(_ mac: String) {
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

    static func all(_ mac: String) -> [CredSnapshot] {
        (DB.store.get([CredSnapshot].self, key(mac)) ?? []).sorted { $0.at > $1.at }
    }

    static func capture(_ mac: String, note: String) {
        var list = all(mac)
        let l = DB.ledger(mac)
        list.insert(CredSnapshot(id: UUID().uuidString, at: Date().timeIntervalSince1970 * 1000,
                                 note: note, pwds: l.pwds, fps: l.fps), at: 0)
        if list.count > 10 { list = Array(list.prefix(10)) }
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
