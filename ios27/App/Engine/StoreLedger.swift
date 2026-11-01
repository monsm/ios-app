// DB · 凭证台账（密码/指纹 CRUD + 台账损坏标记 + 差异比对）
// 2026-10-29 从 Store.swift 拆出。
import Foundation

extension DB {
    static func markLedgerCorrupt(_ mac: String) { ledgerLock.withLock { $0.insert(mac) } }

    static func isLedgerCorrupt(_ mac: String) -> Bool { ledgerLock.withLock { $0.contains(mac) } }

    /// 2026-10-29：清掉损坏标记。只在"用户显式选择以某份备份为准"（备份恢复）时调用 ——
    /// 否则一次解码失败会让整个会话里所有 ledger 写入（含恢复时的凭证导入）静默失败。
    static func clearAllLedgerCorrupt() { ledgerLock.withLock { $0.removeAll() } }

    /// 只清一把锁的损坏标记（备份恢复按锁清理时用，见 SEC-17）。
    static func clearLedgerCorrupt(_ mac: String) { ledgerLock.withLock { $0.remove(mac) } }

    /// SEC-03：空壳（胁迫码）模式下所有凭证读取返回空台账。
    /// 数据层强制，而不是只靠页面清 @State —— 凭证工作室/备份工作室/记录工作室都直接读 DB。
    /// 写入路径不受影响（空壳里不做写入），退出空壳后立刻恢复真实数据。
    /// SEC-01：门锁密码明文的 Keychain 账户名。
    /// 每条密码一个账户（不用"整表一个串"）：单条更新只碰一个 Keychain 项，
    /// 不必为了改一条而整份台账重写。
    static func pwdSecretAccount(_ mac: String, _ alias: Int) -> String {
        "ledger." + normalizeMac(mac) + ".pwd." + String(alias)
    }

    /// 把台账里的明文口令搬进 Keychain，**返回一份 pwd 字段被清空的副本**给 plist。
    ///
    /// 与 `saveKeychain` 的既有纪律完全一致：
    ///   · 先写 Keychain，写成功才允许抹掉明文；写失败就保留明文（宁可有明文也不能丢口令）。
    ///   · 空口令（nil / ""）不进 Keychain，并把历史条目删掉。
    private static func ledgerForPlist(_ mac: String, _ l: Ledger) -> Ledger {
        var safe = l
        var failed: [Int] = []
        for i in safe.pwds.indices {
            guard let pwd = safe.pwds[i].pwd, !pwd.isEmpty else {
                SecretStore.remove(pwdSecretAccount(mac, safe.pwds[i].alias))
                continue
            }
            if SecretStore.set(pwd, for: pwdSecretAccount(mac, safe.pwds[i].alias)) {
                safe.pwds[i].pwd = nil
            } else {
                failed.append(safe.pwds[i].alias)
            }
        }
        if !failed.isEmpty {
            BleTelemetry.recordEvent("凭证口令未能进 Keychain，暂留本机明文： #"
                                     + failed.map(String.init).joined(separator: "/")
                                     + " @ " + String(mac.prefix(6)), ok: false)
        }
        return safe
    }

    /// 从 plist 解出的台账 + Keychain 里的口令 → 完整台账（读侧的唯一回填点）。
    private static func ledgerWithSecrets(_ mac: String, _ l: Ledger) -> Ledger {
        var full = l
        for i in full.pwds.indices where full.pwds[i].pwd == nil {
            full.pwds[i].pwd = SecretStore.get(pwdSecretAccount(mac, full.pwds[i].alias))
        }
        return full
    }

    /// SEC-01：回收站条目的 Keychain 账户名（条目 id 里已含 alias/batch 与时刻，天然唯一）。
    static func binSecretAccount(_ mac: String, _ itemID: String) -> String {
        "ledger." + normalizeMac(mac) + ".bin." + itemID
    }

    /// SEC-01：读回收站条目的口令副本（写侧已搬进 Keychain，plist 里只剩 nil）。
    static func binSecret(_ mac: String, _ itemID: String) -> String? {
        SecretStore.get(binSecretAccount(mac, itemID))
    }

    /// SEC-01：版本历史快照的 Keychain 账户名（快照 id 是 UUID，天然唯一）。
    static func snapshotSecretAccount(_ mac: String, _ snapshotID: String, _ alias: Int) -> String {
        "ledger." + normalizeMac(mac) + ".snap." + snapshotID + "." + String(alias)
    }

    static func snapshotSecret(_ mac: String, _ snapshotID: String, _ alias: Int) -> String? {
        SecretStore.get(snapshotSecretAccount(mac, snapshotID, alias))
    }

    /// SEC-01 迁移：把旧版本留在 plist 里的明文口令搬进 Keychain，然后**把明文从 plist 抹掉**。
    /// 幂等：已经搬过的条目在 plist 里已经没有 pwd，本函数对它是 no-op。
    static func migrateLedgerSecrets() {
        for kc in keychains() {
            let mac = normalizeMac(kc.mac)
            guard let raw = get(Ledger.self, "kf_ledger_" + mac) else { continue }
            guard raw.pwds.contains(where: { ($0.pwd ?? "").isEmpty == false }) else { continue }
            let safe = ledgerForPlist(mac, raw)
            guard safe.pwds.contains(where: { $0.pwd == nil }) else { continue }
            set(safe, "kf_ledger_" + mac)
            BleTelemetry.recordEvent("台账口令已迁入 Keychain @" + String(mac.prefix(6)), ok: true)
        }
    }

    static func ledger(_ mac: String) -> Ledger {
        if DB.isDecoy { return Ledger() }
        if let l = get(Ledger.self, "kf_ledger_" + mac) { return ledgerWithSecrets(mac, l) }
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
        // N-01（安全审计复核发现，P1）：空壳模式下 ledger(mac) 返回**空台账**，
        // 而写入路径没有对应守卫 —— 空壳里任何一次 saveLedger 都会用「只有这一条」的空表
        // 覆盖真实台账，其余凭证全部丢失（可达链路：回收站「还原」→ addPwd → saveLedger）。
        // 空壳模式本来就禁止写入，这里直接拒绝，并记一条遥测（不静默）。
        if isDecoy {
            BleTelemetry.recordEvent("空壳模式下拒绝台账写入 @" + String(mac.prefix(6)), ok: false)
            return
        }
        ledgerWriteLock.withLock { _ in
            // 已判定为不可解的台账一律拒写: 宁可界面显示陈旧数据, 也不要把用户的记录抹掉
            guard !isLedgerCorrupt(mac) else {
                // 不要静默：这条以前是直接 return，用户看到"保存成功"但什么都没落盘。
                BleTelemetry.recordEvent("台账不可解， 本次写入被拒 @" + String(mac.prefix(6)), ok: false)
                return
            }
            let old = get(Ledger.self, "kf_ledger_" + mac)
            // SEC-01：明文口令先搬进 Keychain，plist 只落非密字段。
            // 写失败时 `ledgerForPlist` 会保留明文并记遥测 —— 宁可有明文，也不能丢口令。
            set(ledgerForPlist(mac, l), "kf_ledger_" + mac)
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
            // SEC-13：备注与归属**不进审计链**。用户备注常含「给谁、哪扇门、备用码提示」，
            // 而 kf_ble_events 落 UserDefaults、随 iCloud/iTunes 备份出机。只记"变了没变"。
            if o.note != p.note { d[tag + "·备注"] = ["已改", "已改"] }
            if o.owner != p.owner { d[tag + "·归属"] = ["已改", "已改"] }
        }
        for o in op where !new.pwds.contains(where: { $0.alias == o.alias }) { d["密码#\(o.alias)"] = ["删除", ""] }
        for f in new.fps {
            let tag = "指纹#\(f.batch)"
            guard let o = of.first(where: { $0.batch == f.batch }) else { d[tag] = ["", "新增"]; continue }
            if o.name != f.name { d[tag + "·名称"] = ["已改", "已改"] }
            if o.note != f.note { d[tag + "·备注"] = ["已改", "已改"] }
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
        // SEC-01 残余（2026-11-01）：口令明文在 Keychain 里另存一份（`ledger.<mac>.pwd.<alias>`）。
        // `ledgerForPlist` 只处理"仍在数组里的条目"，条目一旦被移除，那份副本就再没人碰过 ——
        // 于是**每删一条凭证，钥匙串里就永久多一份可读的开门口令**。
        // 这里是全仓所有删除路径的唯一落点（见下方注释），所以清理放这一处就够。
        SecretStore.remove(pwdSecretAccount(mac, alias))
        // 2026-10-30 修复（第 94 轮）：删凭证必须一并取消它的到期提醒。
        // 这里是全仓所有 `DB.delPwd` 的唯一落点（停用/彻底删除/批量/换槽/恢复都走它），
        // 所以取消放在这一处即可覆盖全部删除路径。
        CredentialOrg.cancelAlerts(mac: mac, alias: alias)
        // 2026-11-01（Round 227）：**派生数据也要随删** —— 星标与拖拽顺序里都还留着这个别名的条目。
        // 锁端会复用别名（删掉再新增常常拿到同一个 #N），于是新凭证会"自带旧星标 / 排到旧位置"，
        // 用户完全看不出原因。删除是唯一落点，清在这里即可覆盖全部路径。
        var stars = CredStarStore.all(mac)
        if stars.remove("pwd:\(alias)") != nil { CredStarStore.set(mac, stars) }
        // 「本机停用位」也是同一族的派生数据（键同样是 `pwd:<别名>`）。
        CredentialLocalState.setDisabled(mac: mac, id: "pwd:\(alias)", false)
        var sq = CredentialOrg.seq(mac)
        if var p = sq["p"], let i = p.firstIndex(of: alias) {
            p.remove(at: i)
            sq["p"] = p
            CredentialOrg.setSeq(mac, sq)
        }
    }

    static func rePwd(_ mac: String, _ alias: Int, _ pwd: String) {
        var l = ledger(mac)
        for i in l.pwds.indices where l.pwds[i].alias == alias { l.pwds[i].pwd = pwd }
        saveLedger(mac, l)
    }

    static func setPwdPeriod(_ mac: String, _ alias: Int, _ from: String, _ to: String) {
        var l = ledger(mac)
        var hit = false
        for i in l.pwds.indices where l.pwds[i].alias == alias { l.pwds[i].from = from; l.pwds[i].to = to; hit = true }
        saveLedger(mac, l)
        // 有效期变了 ⇒ 提醒必须按新日期重排（否则旧通知还在旧日期上）
        if hit { CredentialOrg.rescheduleAlerts(mac: mac, alias: alias) }
    }

    static func setPwdNote(_ mac: String, _ alias: Int, _ note: String) {
        var l = ledger(mac)
        for i in l.pwds.indices where l.pwds[i].alias == alias { l.pwds[i].note = note }
        saveLedger(mac, l)
    }

    /// 返回**是否真的改到了**一条（找不到编号时静默不写，调用方要能区分）。
    /// 2026-11-01：原来返回 Void —— 于是 `applyTransfer` 按"选中数"报「已移交 N 项」，
    /// 而台账里已被删掉的编号一条都没改，用户看到的数字是假的（与 D-58 同族）。
    @discardableResult
    static func setPwdOwner(_ mac: String, _ alias: Int, _ owner: String?) -> Bool {
        var l = ledger(mac)
        var hit = false
        for i in l.pwds.indices where l.pwds[i].alias == alias { l.pwds[i].owner = owner; hit = true }
        if hit { saveLedger(mac, l) }
        return hit
    }

    /// 2026-10-30（第 161 轮）：一次读改写完成 `pwd` / `note` / `owner` 三处修改。
    /// 原来调用方连调 `rePwd` / `setPwdNote` / `setPwdOwner` —— 那是**三次整表解码 + 编码 + 三条台账变更记录**，
    /// 而它们逻辑上是同一个动作（改造一条密码）。合并后只有一条 `台账变更` 审计记录。
    static func updatePwd(_ mac: String, _ alias: Int, pwd: String, note: String, owner: String?) {
        var l = ledger(mac)
        for i in l.pwds.indices where l.pwds[i].alias == alias {
            l.pwds[i].pwd = pwd
            l.pwds[i].note = note
            l.pwds[i].owner = owner
        }
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
        // 同 `delPwd`：指纹的星标与拖拽顺序同样要随删（批次号也会被锁端复用）。
        var stars = CredStarStore.all(mac)
        if stars.remove("fp:\(batch)") != nil { CredStarStore.set(mac, stars) }
        CredentialLocalState.setDisabled(mac: mac, id: "fp:\(batch)", false)
        var sq = CredentialOrg.seq(mac)
        if var p = sq["f"], let i = p.firstIndex(of: batch) {
            p.remove(at: i)
            sq["f"] = p
            CredentialOrg.setSeq(mac, sq)
        }
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

    /// 同 `setPwdOwner`：返回是否真的改到了。
    @discardableResult
    static func setFpOwner(_ mac: String, _ batch: Int, _ owner: String?) -> Bool {
        var l = ledger(mac)
        var hit = false
        for i in l.fps.indices where l.fps[i].batch == batch { l.fps[i].owner = owner; hit = true }
        if hit { saveLedger(mac, l) }
        return hit
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
