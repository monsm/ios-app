// DB · 凭证台账（密码/指纹 CRUD + 台账损坏标记 + 差异比对）
// 2026-10-29 从 Store.swift 拆出。
import Foundation

extension DB {
    static func markLedgerCorrupt(_ mac: String) { ledgerLock.withLock { $0.insert(mac) } }

    static func isLedgerCorrupt(_ mac: String) -> Bool { ledgerLock.withLock { $0.contains(mac) } }

    /// 2026-10-29：清掉损坏标记。只在"用户显式选择以某份备份为准"（备份恢复）时调用 ——
    /// 否则一次解码失败会让整个会话里所有 ledger 写入（含恢复时的凭证导入）静默失败。
    static func clearAllLedgerCorrupt() { ledgerLock.withLock { $0.removeAll() } }

    static func ledger(_ mac: String) -> Ledger {
        if let l = get(Ledger.self, "kf_ledger_" + mac) { return l }
        // get 返回 nil 有两种语义: ①该键不存在 (真空台账) ②有键但解码抛错 (字段缺任一即整表抛)。
        // 旧实现在 ②下返回空 Ledger, 调用方 (addPwd/addFp/…) 紧接着 save → **台账被空表整表覆盖清空**。
        if store.has("kf_ledger_" + mac) { markLedgerCorrupt(mac) }
        return Ledger()
    }

    /// 台账写入的唯一漏斗。
    ///
    /// 2026-10-27 审核修复：
    ///   · D-19：`corrupt 检查 → 读 → 写` 是 TOCTOU —— 检查通过后、写入前，另一个线程可能
    ///     把台账标成 corrupt 并写空表，于是这次写入把真数据覆盖掉。整个动作放进同一把锁。
    ///   · D-20：原先算出 `ledgerDiff` 却只拿它判断"非空"，diff 内容本身被丢弃 ——
    ///     而 379/380 承诺"增删改会自动记入管理流水"。现在把 diff 真的记进去。
    static func saveLedger(_ mac: String, _ l: Ledger) {
        ledgerWriteLock.withLock { _ in
            // 已判定为不可解的台账一律拒写: 宁可界面显示陈旧数据, 也不要把用户的记录抹掉
            guard !isLedgerCorrupt(mac) else {
                // 不要静默：这条以前是直接 return，用户看到"保存成功"但什么都没落盘。
                BleTelemetry.recordEvent("台账不可解, 本次写入被拒 @" + String(mac.prefix(6)), ok: false)
                return
            }
            let old = get(Ledger.self, "kf_ledger_" + mac)
            set(l, "kf_ledger_" + mac)
            let changes = ledgerDiff(old, l)
            guard !changes.isEmpty else { return }
            let name = keychain(mac).map { LockArchive.displayName($0) } ?? mac
            // ledgerDiff 返回 [字段: [前, 后]]，拼成人读的一行再记
            let desc = changes.map { (k, v) in k + " " + v.joined(separator: " -> ") }
                              .sorted()
                              .joined(separator: "; ")
            BleTelemetry.recordEvent("台账变更 " + name + ": " + desc, ok: true)
        }
    }

    /// 379/380: 台账前后 → [字段: [前, 后]]; 口令只记指纹前 4 位, 明文不落审计链
    static func ledgerDiff(_ old: Ledger?, _ new: Ledger) -> [String: [String]] {
        var d: [String: [String]] = [:]
        let op = old?.pwds ?? [], of = old?.fps ?? []
        for p in new.pwds {
            let tag = "密码#\(p.alias)"
            guard let o = op.first(where: { $0.alias == p.alias }) else { d[tag] = ["", "新增"]; continue }
            if o.pwd != p.pwd { d[tag + "·口令"] = [HashKit.fingerprint(o.pwd ?? ""), HashKit.fingerprint(p.pwd ?? "")] }
            if o.from != p.from || o.to != p.to { d[tag + "·有效期"] = [o.from + "~" + o.to, p.from + "~" + p.to] }
            if o.note != p.note { d[tag + "·备注"] = [o.note, p.note] }
            if o.owner != p.owner { d[tag + "·归属"] = [o.owner ?? "", p.owner ?? ""] }
        }
        for o in op where !new.pwds.contains(where: { $0.alias == o.alias }) { d["密码#\(o.alias)"] = ["删除", ""] }
        for f in new.fps {
            let tag = "指纹#\(f.batch)"
            guard let o = of.first(where: { $0.batch == f.batch }) else { d[tag] = ["", "新增"]; continue }
            if o.name != f.name { d[tag + "·名称"] = [o.name, f.name] }
            if o.note != f.note { d[tag + "·备注"] = [o.note, f.note] }
            if o.isAlarm != f.isAlarm { d[tag + "·防拆"] = [(o.isAlarm ?? false) ? "开" : "关", (f.isAlarm ?? false) ? "开" : "关"] }
        }
        for o in of where !new.fps.contains(where: { $0.batch == o.batch }) { d["指纹#\(o.batch)"] = ["删除", ""] }
        return d
    }

    static func listPwds(_ mac: String) -> [LedgerPwd] {
        ledger(mac).pwds.sorted { ($0.at) > ($1.at) }
    }

    static func listFps(_ mac: String) -> [LedgerFp] {
        ledger(mac).fps.sorted { ($0.at) > ($1.at) }
    }

    static func addPwd(_ mac: String, _ p: LedgerPwd) {
        var l = ledger(mac)
        l.pwds.removeAll { $0.alias == p.alias }
        l.pwds.append(p)
        saveLedger(mac, l)
    }

    static func delPwd(_ mac: String, _ alias: Int) {
        var l = ledger(mac)
        l.pwds.removeAll { $0.alias == alias }
        saveLedger(mac, l)
    }

    static func rePwd(_ mac: String, _ alias: Int, _ pwd: String) {
        var l = ledger(mac)
        for i in l.pwds.indices where l.pwds[i].alias == alias { l.pwds[i].pwd = pwd }
        saveLedger(mac, l)
    }

    static func setPwdPeriod(_ mac: String, _ alias: Int, _ from: String, _ to: String) {
        var l = ledger(mac)
        for i in l.pwds.indices where l.pwds[i].alias == alias { l.pwds[i].from = from; l.pwds[i].to = to }
        saveLedger(mac, l)
    }

    static func setPwdNote(_ mac: String, _ alias: Int, _ note: String) {
        var l = ledger(mac)
        for i in l.pwds.indices where l.pwds[i].alias == alias { l.pwds[i].note = note }
        saveLedger(mac, l)
    }

    static func setPwdOwner(_ mac: String, _ alias: Int, _ owner: String?) {
        var l = ledger(mac)
        for i in l.pwds.indices where l.pwds[i].alias == alias { l.pwds[i].owner = owner }
        saveLedger(mac, l)
    }

    static func addFp(_ mac: String, _ f: LedgerFp) {
        var l = ledger(mac)
        l.fps.removeAll { $0.batch == f.batch }
        l.fps.append(f)
        saveLedger(mac, l)
    }

    static func delFp(_ mac: String, _ batch: Int) {
        var l = ledger(mac)
        l.fps.removeAll { $0.batch == batch }
        saveLedger(mac, l)
    }

    static func renameFp(_ mac: String, _ batch: Int, _ name: String) {
        var l = ledger(mac)
        for i in l.fps.indices where l.fps[i].batch == batch { l.fps[i].name = name }
        saveLedger(mac, l)
    }

    static func setFpNote(_ mac: String, _ batch: Int, _ note: String) {
        var l = ledger(mac)
        for i in l.fps.indices where l.fps[i].batch == batch { l.fps[i].note = note }
        saveLedger(mac, l)
    }

    static func setFpOwner(_ mac: String, _ batch: Int, _ owner: String?) {
        var l = ledger(mac)
        for i in l.fps.indices where l.fps[i].batch == batch { l.fps[i].owner = owner }
        saveLedger(mac, l)
    }

    static func setFpAlarm(_ mac: String, _ batch: Int, _ on: Bool) {
        var l = ledger(mac)
        for i in l.fps.indices where l.fps[i].batch == batch { l.fps[i].isAlarm = on }
        saveLedger(mac, l)
    }

    // 包6 点查辅助 (版本历史/回收站/详情路由用)
    static func getPwd(_ mac: String, _ alias: Int) -> LedgerPwd? {
        ledger(mac).pwds.first { $0.alias == alias }
    }

    static func getFp(_ mac: String, _ batch: Int) -> LedgerFp? {
        ledger(mac).fps.first { $0.batch == batch }
    }

    static func getPwdList(_ aliases: [Int], _ mac: String) -> [LedgerPwd] {
        ledger(mac).pwds.filter { aliases.contains($0.alias) }
    }

    static func getFpList(_ batches: [Int], _ mac: String) -> [LedgerFp] {
        ledger(mac).fps.filter { batches.contains($0.batch) }
    }

}
