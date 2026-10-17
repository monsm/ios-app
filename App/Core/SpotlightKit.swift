// 293/951 Spotlight 系统搜索索引 — 锁名 (293) 与凭证条目 (951) 写入 CoreSpotlight,
// 点搜索结果回到本 App 已有的落点: 设备页那把锁 / 凭证页那条详情 (pwd:/fp: 两条 nav 早就存在)。
//
// 为什么这一条不需要 App Groups: CSSearchableIndex 由主 App 自己写、系统进程自己读,
// 索引不是跨进程共享容器 —— 小组件那族 (924/925) 缺的是"扩展读本机台账", 与这里两回事。
// 此前 AppIntents.swift 那行"设备/成员名称已入系统搜索"是全仓唯一证据, 而 import 清单里没有
// CoreSpotlight, CSSearchableIndex 零命中 —— 界面在替一份不存在的索引说话。这一份把索引真写出来。
//
// 成员名**不在**本版索引里: 凭证页有 pwd:/fp: 两条真落点, 成员详情没有对应的编程式入口,
// 索引进去点不开就是第二次谎报。落点接通后再补, 不在这里挂空条目。
import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

nonisolated enum SpotlightKit {
    /// 按域整删再整写: 改名与删除不会在系统里留下旧条目 (逐条增删容易漏掉 rename 那一支)
    static let domainDevice = "lockkeeper.device"
    static let domainCredential = "lockkeeper.credential"

    // ---------- 条目 id 制式 (只有这三种前缀会被接住) ----------
    /// 2026-10-14: id 里不再内嵌明文 MAC (CSSearchableIndex 会持久化 identifier) —— 改用 MAC 的 SHA-256 前 16 位。
    /// 反查靠遍历本机钥匙串比对 (数量级几十, 代价可忽略); 索引与台账同生命周期, 不引入新状态。
    private static func macToken(_ mac: String) -> String {
        String(HashKit.sha256Hex(DB.normalizeMac(mac)).prefix(16))
    }
    private static func macFromToken(_ token: String) -> String? {
        DB.keychains().first { macToken($0.mac) == token }?.mac
    }
    static func deviceID(_ mac: String) -> String { "dev:" + macToken(mac) }
    static func pwdID(_ mac: String, _ alias: Int) -> String { "pwd:\(macToken(mac))#\(alias)" }
    static func fpID(_ mac: String, _ batch: Int) -> String { "fp:\(macToken(mac))#\(batch)" }

    /// 系统回传的 identifier → kf:// 深链。认不出的格式一律 nil (不猜、不跳)。
    /// 凭证类不走 URL 而走 handleCredential, 因为凭证定位用的是 pendingCredNav 那对既有状态。
    static func deviceURL(for identifier: String) -> URL? {
        guard identifier.hasPrefix("dev:") else { return nil }
        guard let mac = macFromToken(String(identifier.dropFirst(4))) else { return nil }
        return URL(string: "kf://device?mac=" + DB.normalizeMac(mac))
    }
    /// 凭证 identifier → (mac, nav) —— nav 串制式与 CredentialsView.consumeCredJump 的解析端一致。
    /// mac 与 alias/batch 以 `#` 分界 (MAC 里没有 #), 只有 pwd:/fp: 两种前缀被接住。
    /// 陌生 mac / 查不到的条目一律 nil: 索引可能比台账慢半拍, 点不开就不跳 (与深链白名单同一口径)。
    static func credentialTarget(for identifier: String) -> (mac: String, nav: String)? {
        guard let hash = identifier.firstIndex(of: "#") else { return nil }
        let head = String(identifier[..<hash])              // "pwd:<mac>" / "fp:<mac>"
        let tail = String(identifier[identifier.index(after: hash)...])
        let m: String
        let nav: String
        if head.hasPrefix("pwd:") {
            guard let m0 = macFromToken(String(head.dropFirst(4))) else { return nil }
            m = DB.normalizeMac(m0)
            guard let a = Int(tail) else { return nil }
            nav = "pwd:\(a)"
            guard DB.getPwd(m, a) != nil else { return nil }
        } else if head.hasPrefix("fp:") {
            guard let m0 = macFromToken(String(head.dropFirst(3))) else { return nil }
            m = DB.normalizeMac(m0)
            guard let b = Int(tail) else { return nil }
            nav = "fp:\(b)"
            guard DB.getFp(m, b) != nil else { return nil }
        } else { return nil }
        guard DB.keychain(m) != nil else { return nil }
        return (m, nav)
    }

    // ---------- 写入 ----------
    /// 档案有任何变化就排队重刷 (0.6s 合并): 一次连续改名不该写索引五次。
    static func scheduleReindex() {
        pending?.cancel()
        let item = DispatchWorkItem { reindexNow() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: item)
    }
    private static var pending: DispatchWorkItem?

    static func reindexNow() {
        let items = buildItems()
        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: [domainDevice, domainCredential]) { err in
            if let err {
                // 索引失败不影响主流程, 但要留在维护回执里可见 (与 223 归档同一份记账口)
                MaintenanceLog.record("Spotlight 索引清理失败: \((err as NSError).localizedDescription)")
                return
            }
            index.indexSearchableItems(items) { err2 in
                if let err2 {
                    MaintenanceLog.record("Spotlight 索引写入失败 (\(items.count) 条): \((err2 as NSError).localizedDescription)")
                }
            }
        }
    }

    /// 索引内容 = 本机台账的真子集: 锁名 + 每条密码/每个指纹批次。空台账 → 只清不写。
    /// ⚠ API-VERIFY: `CSSearchableItemAttributeSet(contentType:)` 与 `UTType.item` 的形状
    ///    未编译、未证实 (本仓此前没有 CoreSpotlight 任何用法可抄); 旧形是 `init(itemContentType:)`。
    private static func buildItems() -> [CSSearchableItem] {
        var out: [CSSearchableItem] = []
        for kc in DB.keychains() {
            let name = LockArchive.displayName(kc)
            let a = CSSearchableItemAttributeSet(contentType: .item)
            a.title = name
            a.contentDescription = lockSubtitle(kc)
            out.append(CSSearchableItem(uniqueIdentifier: deviceID(kc.mac),
                                        domainIdentifier: domainDevice, attributeSet: a))
            let ledger = DB.ledger(kc.mac)
            for p in ledger.pwds {
                let pa = CSSearchableItemAttributeSet(contentType: .item)
                pa.title = p.note.isEmpty ? "密码 #\(p.alias)" : p.note
                pa.contentDescription = "\(name) · \(TimeFormat.range(fromDay: p.from, toDay: p.to))"
                    + ownerSuffix(p.owner)
                out.append(CSSearchableItem(uniqueIdentifier: pwdID(kc.mac, p.alias),
                                            domainIdentifier: domainCredential, attributeSet: pa))
            }
            for f in ledger.fps {
                let fa = CSSearchableItemAttributeSet(contentType: .item)
                fa.title = f.name.isEmpty ? "指纹批次 #\(f.batch)" : f.name
                fa.contentDescription = "\(name) · 指纹凭证" + ownerSuffix(f.owner)
                out.append(CSSearchableItem(uniqueIdentifier: fpID(kc.mac, f.batch),
                                            domainIdentifier: domainCredential, attributeSet: fa))
            }
        }
        return out
    }

    /// 归属成员只报台账里查得到的名字; 查不到就什么也不加 (不拿 id 冒充人名)
    private static func ownerSuffix(_ owner: String?) -> String {
        guard let owner, let m = DB.member(owner) else { return "" }
        return " · " + m.name
    }

    /// 副标题只用档案里真有的字段: 型号 / 场所 / 分组。没有就不写, 不编"最近连接"那种算不出来的话。
    private static func lockSubtitle(_ kc: Keychain) -> String {
        let meta = LockArchive.meta(kc.mac)
        var parts: [String] = [kc.pidName.isEmpty ? "门锁" : kc.pidName]
        if !meta.place.isEmpty { parts.append(meta.place) }
        if !meta.grp.isEmpty { parts.append(meta.grp) }
        return parts.joined(separator: " · ")
    }
}
