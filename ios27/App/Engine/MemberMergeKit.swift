// MemberMergeKit.swift —— 同名成员合并（462）。
//
// 语义：主档保留；副档名下的密码/指纹归属迁到主档，认领覆盖层（kf_mclaim_）一起改判，
// 然后删掉副档。只动本机台账，不碰锁端（锁端凭证仍按各命令面操作）。
import Foundation

enum MemberMergeKit {
    /// 同名的其它成员（副档候选）。
    static func candidates(primaryID: String) -> [Member] {
        guard let primary = DB.member(primaryID) else { return [] }
        return DB.members().filter { $0.id != primaryID && $0.name == primary.name }
    }

    /// 执行合并，返回迁移的凭证条数。
    @discardableResult
    static func merge(primaryID: String, secondaryID: String) -> Int {
        guard primaryID != secondaryID,
              let primary = DB.member(primaryID),
              let secondary = DB.member(secondaryID),
              primary.name == secondary.name else { return 0 }
        var moved = 0
        for kc in DB.keychains() {
            for p in DB.listPwds(kc.mac) where p.owner == secondaryID {
                DB.setPwdOwner(kc.mac, p.alias, primaryID)
                moved += 1
            }
            for f in DB.listFps(kc.mac) where f.owner == secondaryID {
                DB.setFpOwner(kc.mac, f.batch, primaryID)
                moved += 1
            }
        }
        MemberHub.reassignClaims(from: secondaryID, to: primaryID)
        DB.removeMember(secondaryID)
        return moved
    }
}
