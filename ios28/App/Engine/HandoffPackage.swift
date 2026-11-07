// HandoffPackage.swift —— 把钥匙交给安卓的「一次性交付」（B36）。
//
// 现在的交付包只带 ekey —— 谁扫到谁就能一直用，直到锁端 PIN 被换掉。
//
// 2.0 补三件事，且**全部在本地可执行**（没有服务器，也不假装有）：
//   1. **有效期**：交付包带过期时刻；iOS 侧记着，到期后自动把锁端那枚 PIN 删掉
//      （尽力而为 —— 需要 App 有机会运行才能真删，所以界面要如实说这一点）。
//   2. **一次性确认**：用户在 iOS 上点「已交给对方」并确认，iOS 立刻把锁端那枚 PIN 删掉
//      —— 扫过码的安卓端随即失效。这是**真的**一次性，不是提示语。
//   3. **绑定标识**：交付包里带一枚本机生成的绑定号，双方能对上「这把是哪一把」。
//
// 载荷格式：**保持 v=1**。安卓端 `LockStore.kt` 判 `v != 1` 就拒收，
// 所以新增字段一律是**可选**的（x / b / c），老安卓读不到就当没有 —— 两端都不破。
import Foundation

struct HandoffRecord: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var mac: String = ""
    var memberName: String = ""
    /// 锁端 PIN（十进制字符串）—— 一次性确认时用它删锁端条目。
    var pin: String = ""
    var ekey: String = ""
    var createdAt: Double = Date().timeIntervalSince1970
    /// 过期时刻（epoch 秒）。0 = 永久。
    var expiresAt: Double = 0
    /// 用户已确认交付（一次性生效）。
    var delivered: Bool = false
    /// 锁端 PIN 已被删除。
    var revoked: Bool = false
    /// 绑定号（本机生成，双方对账用）。
    var binding: String = ""

    var isExpired: Bool {
        expiresAt > 0 && Date().timeIntervalSince1970 >= expiresAt
    }
}

enum HandoffService {
    private static let key = "kf_handoff_records"

    static func records() -> [HandoffRecord] {
        DB.store.get([HandoffRecord].self, key) ?? []
    }

    static func save(_ list: [HandoffRecord]) {
        DB.store.setCodable(key, list)
    }

    /// 建一份交付记录。
    static func create(mac: String, memberName: String, pin: String, ekey: String,
                        expiresAt: Double) -> HandoffRecord {
        var r = HandoffRecord(mac: mac, memberName: memberName, pin: pin, ekey: ekey,
                               expiresAt: expiresAt)
        r.binding = String(UUID().uuidString.prefix(8))
        var list = records()
        list.insert(r, at: 0)
        if list.count > 20 { list = Array(list.prefix(20)) }
        save(list)
        return r
    }

    /// 交付包正文（`KFA1:` + JSON）。字段名沿用 v1，另加三个可选字段。
    static func payload(_ r: HandoffRecord) -> String? {
        guard !r.ekey.isEmpty else { return nil }
        var dict: [String: Any] = [
            "v": 1,
            "n": r.memberName.isEmpty ? "门锁" : r.memberName,
            "m": r.mac.lowercased(),
            "e": r.ekey.lowercased(),
        ]
        // 可选字段：老安卓读不到就忽略（它只取 n/m/e/p）。
        if r.expiresAt > 0 { dict["x"] = Int(r.expiresAt) }
        if !r.binding.isEmpty { dict["b"] = r.binding }
        dict["c"] = r.expiresAt > 0 ? 1 : 0     // c = 1 表示这把有有效期
        guard let d = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let s = String(data: d, encoding: .utf8) else { return nil }
        return AndroidPair.prefix + s
    }

    /// 确认交付 → **真的把锁端那枚 PIN 删掉**（一次性生效）。
    ///
    /// 删不掉时不假装成功：记录留在列表里，状态是「已确认但未撤销」。
    @discardableResult
    static func confirmDelivered(id: String) async -> Bool {
        var list = records()
        guard let idx = list.firstIndex(where: { $0.id == id }) else { return false }
        list[idx].delivered = true
        save(list)
        return await revokePin(list[idx])
    }

    /// 从锁端删掉那枚 PIN。
    @discardableResult
    static func revokePin(_ r: HandoffRecord) async -> Bool {
        guard !r.pin.isEmpty else { return false }
        do {
            try await LockService.shared.ensureConnected(mac: r.mac)
            try await LockService.shared.deletePins([r.pin])
            var list = records()
            if let idx = list.firstIndex(where: { $0.id == r.id }) {
                list[idx].revoked = true
                save(list)
            }
            return true
        } catch {
            DiagLogs.append("warn", "交付撤销失败（\(r.memberName.isEmpty ? "未命名" : r.memberName)）：\(error.localizedDescription)",
                            date: DiagLogs.localDay(), time: DiagTime.hhmmss())
            return false
        }
    }

    /// 清理过期的交付（尽力而为：需要 App 有机会运行）。
    ///
    /// 诚实说明：**没有服务器、没有后台常驻**，所以「到期即失效」只在
    /// App 被打开时成立。界面上要写清楚这一点，不能写成「到期自动失效」。
    @discardableResult
    static func sweepExpired() async -> Int {
        var list = records()
        let expired = list.filter { !$0.revoked && $0.isExpired }
        guard !expired.isEmpty else { return 0 }
        var revoked = 0
        for r in expired {
            if await revokePin(r) { revoked += 1 }
        }
        list = records()
        save(list)
        return revoked
    }

    /// 人话摘要。
    static func summary(_ r: HandoffRecord) -> String {
        if r.revoked { return "已撤销（锁端那枚钥匙已删除）" }
        if r.delivered { return "已确认交付，但锁端那枚钥匙还没删掉 —— 打开 App 再试一次" }
        if r.isExpired { return "已过期，下次打开 App 时清理" }
        if r.expiresAt > 0 {
            let left = Int(r.expiresAt - Date().timeIntervalSince1970)
            if left > 0 { return "有效期还剩 \(left / 3600) 小时" }
        }
        return "等待确认交付"
    }
}
