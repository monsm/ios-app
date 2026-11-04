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
    ///
    /// 2026-11-01（Round 288 修 Round 282 的编译错误）：本函数要调 `MobileKeyService.reassignMember`，
    /// 而那个枚举是 `@MainActor` —— 非隔离上下文调用会报 `[#ActorIsolatedCall]`（CI 实测两条）。
    /// 本函数唯一的调用点是 `MemberMergeSheet.merge()`（View 方法，本来就在主 actor 上），
    /// 所以这里标 `@MainActor` 不改变任何调用方式。
    @MainActor
    @discardableResult
    static func merge(primaryID: String, secondaryID: String) -> Int {
        guard primaryID != secondaryID,
              let primary = DB.member(primaryID),
              let secondary = DB.member(secondaryID),
              primary.name == secondary.name else { return 0 }
        var moved = 0
        // 2026-11-05（对抗审查）：与 MemberOpsStore.transfer 同源 —— 旧数据的 owner 存的是
        // 成员**名**。只按 id 筛会让那些行留在「已删除的副档名字」上，随后 removeMember 把它们
        // 清成未归属：用户以为合并了，凭证却丢了归属。
        let secondaryName = secondary.name
        for kc in DB.keychains() {
            for p in DB.listPwds(kc.mac) where CredentialOrg.ownerMatches(p.owner, memberID: secondaryID, memberName: secondaryName) {
                DB.setPwdOwner(kc.mac, p.alias, primaryID)
                moved += 1
            }
            for f in DB.listFps(kc.mac) where CredentialOrg.ownerMatches(f.owner, memberID: secondaryID, memberName: secondaryName) {
                DB.setFpOwner(kc.mac, f.batch, primaryID)
                moved += 1
            }
        }
        MemberHub.reassignClaims(from: secondaryID, to: primaryID)
        // 2026-11-01（Round 282）：手机钥匙也要改判 —— 否则下面的 `removeMember` 会把它们删掉，
        // 而锁端那把钥匙仍然有效，用户会失去管理/吊销入口（详见 `reassignMember` 的注释）。
        MobileKeyService.reassignMember(from: secondaryID, to: primaryID)
        DB.removeMember(secondaryID)
        return moved
    }
}
