// CredentialOrg · 批量操作（停用 / 延期 / 前缀 / 移交 / 导出包）
// 2026-10-29 从 CredentialOrg.swift 拆出。
import Foundation

extension CredentialOrg {
    // ---------- 347/348/349/357 批量本地操作 (下发部分只入队, UI 标注本地意图) ----------
    /// 348 统一延期: 本地改写所选过期字段并留变更清单 (逐条入队, 到场后统一补发)
    /// 批量延期。2026-10-27 (D-58)：同 batchDisable —— 找不到的条目如实返回，不静默跳过。
    static func batchExtend(_ mac: String, _ aliases: [Int], _ from: String, _ to: String)
        -> (done: [Int], failed: [Int]) {
        var out: [Int] = []
        var failed: [Int] = []
        // 2026-10-29 性能：原来循环里每轮都 `DB.ledger(mac)` —— 那是一整份台账解码，
        // 选 20 条就是 20 次全量解码。别名唯一，先建一次存在集即可。
        let existing = Set(DB.ledger(mac).pwds.map(\.alias))
        for a in aliases {
            guard existing.contains(a) else {
                failed.append(a)
                continue
            }
            DB.setPwdPeriod(mac, a, from, to)
            out.append(a)
        }
        return (out, failed)
    }

    /// 357 前缀批量备注
    // 【保留未接 2026-10-29】批量给多条凭证加同一个前缀备注（用户 B1 未选，保留待接：凭证页多选菜单可挂）
    static func batchPrefixNote(_ mac: String, pwdAliases: [Int], fpBatches: [Int], prefix: String) -> Int {
        var n = 0
        var l = DB.ledger(mac)
        // 2026-10-29 性能：`数组.contains` 在逐行循环里是 O(n×m)，换成 Set 变 O(n+m)。
        let aliasSet = Set(pwdAliases)
        let batchSet = Set(fpBatches)
        for i in l.pwds.indices where aliasSet.contains(l.pwds[i].alias) && !(l.pwds[i].note.hasPrefix(prefix)) {
            l.pwds[i].note = prefix + l.pwds[i].note; n += 1
        }
        for i in l.fps.indices where batchSet.contains(l.fps[i].batch) && !(l.fps[i].note.hasPrefix(prefix)) {
            l.fps[i].note = prefix + l.fps[i].note; n += 1
        }
        DB.saveLedger(mac, l)
        return n
    }

    /// 353 批量停用: 所选过期/老旧项本地移除并入回收站, 锁端删除入队
    /// 批量停用：把选中的密码/指纹移入回收站（同一批次，可整组还原）。
    ///
    /// 2026-10-27 审核修复 (AUDIT-D D-58)：原先 `guard ... else { continue }` **静默跳过**
    /// 找不到的条目，只返回成功数 —— 用户看到「已停用 8 条」却不知道有 2 条根本没动
    /// （可能是别处已经删了、或台账里编号对不上）。
    /// 现在返回 (done, failed)：failed 是"选中了但没找到"的编号，UI 必须如实报出来。
    static func batchDisable(_ mac: String, pwdAliases: [Int], fpBatches: [Int])
        -> (done: Int, failedPwds: [Int], failedFps: [Int]) {
        var n = 0
        var failedPwds: [Int] = []
        var failedFps: [Int] = []
        let batchId = UUID().uuidString   // 353: 一次批量停用 = 一个批次, 回收站里可整组还原
        // 2026-10-29 性能：同 batchExtend —— 循环里每轮整份解码台账。
        let existingAliases = Set(DB.ledger(mac).pwds.map(\.alias))
        for a in pwdAliases {
            guard existingAliases.contains(a) else {
                failedPwds.append(a)   // D-58：找不到就记下来，不静默跳过
                continue
            }
            DB.delPwd(mac, a)
            n += 1
        }
        let existingBatches = Set(DB.ledger(mac).fps.map(\.batch))
        for b in fpBatches {
            guard existingBatches.contains(b) else {
                failedFps.append(b)
                continue
            }
            DB.delFp(mac, b)
            n += 1
        }
        return (n, failedPwds, failedFps)
    }

    // ---------- 524/526/528 计数与三态 ----------
    static func typeCounts(_ mac: String) -> (all: Int, pwd: Int, fp: Int, otp: Int) {
        let pwds = DB.listPwds(mac), fps = DB.listFps(mac)
        return (pwds.count + fps.count, pwds.count, fps.count, DB.otpStatus(mac)?.on == true ? 1 : 0)
    }

    /// 返回 (Base64 信封文本, 口令)。UI 用 ShareLink 发文本 + 口令单列展示, 不与凭证混排。
    static func exportPackage(_ mac: String, pwdAliases: [Int], fpBatches: [Int], password: String) -> (data: Data, size: Int)? {
        let l = DB.ledger(mac)
        let pwds = l.pwds.filter { pwdAliases.isEmpty || pwdAliases.contains($0.alias) }
        let fps = l.fps.filter { fpBatches.isEmpty || fpBatches.contains($0.batch) }
        guard !pwds.isEmpty || !fps.isEmpty else { return nil }
        let pkg = CredPackage(v: 1, mac: mac, lockName: LockArchive.displayName(DB.keychain(mac) ?? Keychain(mac: mac, skey: "")),
                              pwds: pwds, fps: fps, at: nowSec)
        guard let json = try? JSONEncoder().encode(pkg),
              let text = String(data: json, encoding: .utf8),
              let enc = try? CryptoBox.encryptText(text, password: password) else { return nil }
        return (Data(enc.utf8), pwds.count + fps.count)
    }

    // ---------- 304 全库重复拦截 ----------
    static func duplicatePwdValues(_ mac: String, _ value: String, excluding: Int) -> [LedgerPwd] {
        DB.listPwds(mac).filter { $0.pwd == value && $0.alias != excluding }
    }

    /// 跨锁同值 (304 "全库"): 只报**其它锁**的显示名 (去重)。
    /// 旧版 `duplicatePwdValuesAnyLock` 返回 [LedgerPwd] 却不带 mac —— 调用方拿到条目也说不出是哪把锁,
    /// 还把当前锁的其它别名一起算进来, 与上面的同锁检查重复计数。改成直接给一句警告需要的信息。
    static func duplicatePwdLockNames(_ value: String, excludingMac: String) -> [String] {
        guard !value.isEmpty else { return [] }
        var names: [String] = []
        for k in DB.keychains() where k.mac != excludingMac {
            guard DB.listPwds(k.mac).contains(where: { $0.pwd == value }) else { continue }
            let n = LockArchive.displayName(k)
            if !names.contains(n) { names.append(n) }
        }
        return names
    }

    /// 314 前缀混淆: 同锁内其它密码前 4 位相同, 口头易混淆
    static func prefixConflict(_ mac: String, _ value: String, excluding: Int) -> [LedgerPwd] {
        guard value.count >= 4 else { return [] }
        let pre = value.prefix(4)
        return DB.listPwds(mac).filter { $0.alias != excluding && $0.pwd?.hasPrefix(pre) == true }
    }

}
