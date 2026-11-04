// QuickPool.swift —— 快速操作池（10 选 6 / 常用排前 / 再开一次）。
//
// 从上一版 QuickPool.swift 抽出纯数据部分（无关卡视图）。页面在 DoorScreen 的「快捷操作」卡。
// id 一旦发布就是存储值，只能加不能改；否则会把用户已有的 kf_quick_ids 打空。
import Foundation

struct QuickAction: Identifiable, Hashable {
    let id: String
    let icon: String
    let label: String
}

enum QuickPool {
    static let all: [QuickAction] = [
        QuickAction(id: "addPwd",   icon: "plus.rectangle.on.rectangle", label: "添加密码"),
        QuickAction(id: "otp",      icon: "clock.badge.questionmark",    label: "临时密码"),
        QuickAction(id: "syncTime", icon: "clock.arrow.circlepath",      label: "校准时间"),
        QuickAction(id: "addFp",    icon: "touchid",                     label: "录指纹"),
        QuickAction(id: "studio",   icon: "wrench.and.screwdriver",      label: "凭证工坊"),
        QuickAction(id: "again",    icon: "arrow.counterclockwise",      label: "再开一次"),
        QuickAction(id: "backup",   icon: "archivebox",                  label: "备份与恢复"),
        QuickAction(id: "tailgate", icon: "figure.walk.arrival",         label: "防尾随"),
        QuickAction(id: "safemode", icon: "lock.rotation",               label: "安全模式"),
        QuickAction(id: "dfu",      icon: "arrow.up.circle",             label: "固件升级"),
    ]
    static let defaultIds = ["addPwd", "otp", "syncTime", "addFp", "studio"]

    static let idsKey = "kf_quick_ids"
    static let freqKey = "kf_quick_freq"
    static let smartKey = "kf_quick_smart"
    static let sinceKey = "kf_quick_since"
    static let smartSetKey = "kf_quick_smart_set"

    /// 读池子：白名单过滤 + 去重 + 保用户排的序；空/全不认识 → 回退默认。
    static var selected: [QuickAction] {
        let stored = DB.store.get([String].self, idsKey) ?? defaultIds
        var seen = Set<String>()
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let picked = stored.filter { seen.insert($0).inserted }.compactMap { byID[$0] }
        return picked.isEmpty ? all.filter { defaultIds.contains($0.id) } : picked
    }

    static func setSelected(_ ids: [String]) {
        // 2026-11-03（全功能点排查）：这里原来用 `all.filter { ids.contains(...) }` —— 它按
        // **all 的固定顺序**输出，调用方传进来的顺序被整段丢弃。而 `selected` 的注释承诺
        // "保用户排的序"、设置页也写着"按你在这里的勾选顺序"。三处口径互相矛盾，实际顺序恒等于 all。
        // 现在按传入顺序去重保序（未知 id 丢弃）。
        var seen = Set<String>()
        let known = Set(all.map { $0.id })
        let clean = ids.filter { known.contains($0) && seen.insert($0).inserted }
        // 2026-11-03：这里原来比的是**排序后相等** —— 用户把默认那 5 个重新排了序，
        // 也会被判成"就是默认值"而把键删掉，顺序静默还原。改成**按序相等**才回退默认。
        if clean == defaultIds {
            DB.store.remove(idsKey)
        } else {
            DB.store.set(idsKey, clean)
        }
    }

    static var smartFirst: Bool { DB.store.getBool(smartKey) }
    static func setSmartFirst(_ v: Bool) {
        DB.store.set(smartKey, v)
        DB.store.set(smartSetKey, true)
    }
    static var recordingOn: Bool { !DB.store.getBool(smartSetKey) || smartFirst }
    static var reached30d: Bool {
        guard let since = DB.store.get(Double.self, sinceKey) else { return false }
        let now = Date().timeIntervalSince1970
        // 2026-11-01：与 `LockStats.isSleeping` / `touchConnected` 同口径 ——
        // `since` 若在未来（用户调过系统时间 / 换机带来别的设备的时钟），
        // `now - since` 为负 ⇒ 这里恒 false（"永远攒不够 30 天"），智能排序永不启用。
        guard TimeFormat.timestampIsPlausible(since, now: now) else { return false }
        return now - since >= 30 * 86400
    }
    static var counts: [String: Int] { DB.store.get([String: Int].self, freqKey) ?? [:] }

    static func recordTap(_ id: String) {
        guard recordingOn else { return }
        if DB.store.get(Double.self, sinceKey) == nil {
            DB.store.set(sinceKey, Date().timeIntervalSince1970)
        }
        var c = counts
        c[id, default: 0] += 1
        DB.store.set(freqKey, c)
    }
    // 2026-11-04：`clearCounts()` 已删 —— 全仓零调用、也没有任何界面提供"清除使用频率"入口。

    /// 三档排序：智能开 = 点过的按次数降序（平次保序）；关但满 30 天 = 最常用提首；否则原序。
    static func ordered() -> [QuickAction] {
        let picked = selected
        let c = counts
        if smartFirst {
            return picked.enumerated().sorted { a, b in
                let ca = c[a.element.id] ?? 0, cb = c[b.element.id] ?? 0
                if ca != cb { return ca > cb }
                return a.offset < b.offset
            }.map { $0.element }
        }
        guard !DB.store.getBool(smartSetKey), reached30d,
              let top = picked.max(by: { (c[$0.id] ?? 0) < (c[$1.id] ?? 0) }),
              (c[top.id] ?? 0) > 0 else { return picked }
        var out = picked.filter { $0.id != top.id }
        out.insert(top, at: 0)
        return out
    }

    /// 921「再开一次」目标：只在高频推断可证明时给一条长期密码。
    static func repeatTarget(_ mac: String) -> (name: String, keyID: String)? {
        guard !mac.isEmpty else { return nil }
        let pwds = DB.ledger(mac).pwds
        guard !pwds.isEmpty else { return nil }
        let archived = MemberHub.archivedIDs()
        let ownedCount = pwds.filter { !$0.temp && $0.owner != nil }.count
        let since = Date().timeIntervalSince1970 - 30 * 86400
        var opens = 0
        for l in DB.readLogs(mac) where l.type == 17 {
            if ZKProtocol.protoSecondsToUnix(Int64(l.lockTime)) >= since { opens += 1 }
        }
        guard opens > 0, ownedCount == 1 else { return nil }
        for p in pwds where !p.temp {
            guard let o = p.owner, !archived.contains(o) else { continue }
            return ("#\(p.alias)", "pwd:\(p.alias)")
        }
        return nil
    }
}
