// MemberOpsStore.swift —— 成员流转与家庭场景的本机存储。
//
// 来源：原 App/Core/MemberHub.swift（472 借用 kf_mborrow_ / 483 家政窗 kf_house_win_ / 481 轮值 kf_duty_week）。
// 引擎保留了键名与读侧（MemberHub.borrows/dutyThisWeek），本文件补齐写侧与展示模型。
import Foundation

extension MemberBorrow {
    /// 引擎结构只声明了容错解码 init；这里补一个界面用的构造，避免全字段手工拼。
    init(by: String, due: String, at: Double) {
        self.by = by
        self.due = due
        self.at = at
    }
}

/// 家政窗：每周固定时段，服务人员凭临时码进出。
struct HouseWindow: Codable, Identifiable {
    var id: String
    var weekday: Int        // 1 = 周一 … 7 = 周日
    var startHour: Int
    var endHour: Int
    var note: String

    var weekdayText: String { ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"][min(max(weekday, 1), 7)] }
}

enum MemberOpsStore {
    // MARK: - 借用登记（kf_mborrow_<mac>）
    static func borrows(_ mac: String) -> [String: MemberBorrow] {
        DB.store.get([String: MemberBorrow].self, "kf_mborrow_" + mac) ?? [:]
    }

    static func setBorrow(_ mac: String, memberID: String, by: String, due: String) {
        var map = borrows(mac)
        map[memberID] = MemberBorrow(by: by, due: due, at: Date().timeIntervalSince1970 * 1000)
        DB.store.setCodable("kf_mborrow_" + mac, map)
    }

    static func removeBorrow(_ mac: String, memberID: String) {
        var map = borrows(mac)
        map.removeValue(forKey: memberID)
        DB.store.setCodable("kf_mborrow_" + mac, map)
    }

    // MARK: - 家政窗（kf_house_win_<mac>）
    static func windows(_ mac: String) -> [HouseWindow] {
        DB.store.get([HouseWindow].self, "kf_house_win_" + mac) ?? []
    }

    static func addWindow(_ mac: String, _ window: HouseWindow) {
        var list = windows(mac)
        list.removeAll { $0.id == window.id }
        list.append(window)
        DB.store.setCodable("kf_house_win_" + mac, list)
    }

    static func removeWindow(_ mac: String, id: String) {
        var list = windows(mac)
        list.removeAll { $0.id == id }
        DB.store.setCodable("kf_house_win_" + mac, list)
    }

    // MARK: - 移交：把一位成员名下凭证改归属到另一位
    static func transfer(mac: String, from: String, to: String) -> Int {
        var n = 0
        for p in DB.listPwds(mac) where p.owner == from {
            DB.setPwdOwner(mac, p.alias, to)
            n += 1
        }
        for f in DB.listFps(mac) where f.owner == from {
            DB.setFpOwner(mac, f.batch, to)
            n += 1
        }
        return n
    }

    // MARK: - 成员级联删除（凭证进回收站）
    /// 先在界面层把名下凭证原样存进回收站，再走 Engine 的 cascadeBinMember（它只删台账）。
    static func cascadeDelete(mac: String, memberID: String) -> Int {
        let pwds = DB.listPwds(mac).filter { $0.owner == memberID }
        let fps = DB.listFps(mac).filter { $0.owner == memberID }
        let batchId = UUID().uuidString
        CredBinStore.addPwds(mac, pwds, batchId: batchId, source: "成员删除级联")
        CredBinStore.addFps(mac, fps, batchId: batchId, source: "成员删除级联")
        _ = CredentialOrg.cascadeBinMember(mac, memberID, revokeLocks: true)
        return pwds.count + fps.count
    }
}
