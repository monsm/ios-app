// 包8 备份工作室服务层 — 备份·恢复·换机迁移
// 覆盖 idea: 181/193/197/198/237/407-413/417-427/429-431/434-436/438-446/448-450/453/454/456/477/507-509/511/512/1018/1048
// 纪律: 备份文件只去用户自配 WebDAV (Basic Auth 运行时输入), 口令不出本机内存;
//       加密语义 (CryptoBox AES-128-CBC+HMAC/PBKDF2, ZOTP 相关) 不动, 本层只做外围策略。
import Foundation
import UIKit
import CoreImage.CIFilterBuiltins
import BackgroundTasks
@preconcurrency import UserNotifications   // 通知中心对象是系统侧线程安全的, SDK 未标 Sendable


// 2026-10-26: 原 `BZones`（设备/凭证/记录/设置四分区）已删 —— 分区模型从来没有 UI 暴露，
// 全部调用点都传 `BZones()`（= 全选）。既然用户永远只能全量备份，那四个开关就是纯装饰。
// `prune(_:_:)` 与 `bundleFor(_:)` 的分区参数一并去掉，改为一律全量。

@MainActor
enum BackupStudio {
    // ================= 路径与命名 (409/410) =================
    // nonisolated: makeRollbackPoint/pruneRollback 本就是 nonisolated 而引用了这两个路径,
    // 挂在 @MainActor 枚举上会直接编译不过 (纯 FileManager, 无 actor 状态)
    nonisolated static var dir: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("lockkeeper-backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    /// 回滚快照点的是**整库 Keychain (skey/ivKey 明文)**, 旧版把它放在导出目录的 `rollback/` 子目录里:
    /// Documents 下的文件既进 iTunes/Finder 备份, 开了文件共享时还能被"文件"App 直接看到,
    /// 而 413 的分享流程又把同一个目录当作用户可见的备份文件夹。现移入 Application Support 并标记不备份,
    /// 同时把旧目录里已经落盘的明文快照一次性删掉。
    nonisolated static var rollbackDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("lockkeeper-rollback", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var v = URLResourceValues()
        v.isExcludedFromBackup = true
        var mutable = base
        try? mutable.setResourceValues(v)
        let legacy = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("lockkeeper-backups/rollback", isDirectory: true)
        if FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.removeItem(at: legacy)
        }
        return base
    }




    // ---------- 421 恢复回滚点 (24h 内可撤销): 完整库体 JSON 快照 ----------
    /// 421 回滚点补洞: 这些键族不在六个分区里, 而**覆盖恢复会整表替换台账、按名字重建成员** ——
    /// 它们是按 `mac + 凭证 alias` 或 `成员 id` 挂钩的, 于是恢复之后:
    /// 要么指向已经不存在的行/成员 (用户看到的是"备注和标旗凭空没了"), 要么变成没人清的孤儿键;
    /// 而 undoLastRestore 旧实现只回滚六分区, 这些内容**恢复不过来也撤不回来**。
    /// 判定标准两条: ① 恢复流程确实会改写它们指向的东西; ② 里面是用户自己攒的**内容** (不是遥测、不是开关档位)。
    /// 刻意不收: 日志与遥测 (kf_diag_logs / kf_fevents_ / kf_ble_events …) 体积大且不是内容;
    /// 外观与开关 (kf_theme / kf_ax_* / kf_slock_*) 恢复本来就不该动它们, 收进快照反而会把用户改过的设置回滚掉。
    nonisolated static let rollbackFamilies: [String] = [
        "kf_member_ext", "kf_member_bday", "kf_member_badge",       // 成员档案扩展 (角色/备注/分组/归档)
        "kf_mborrow_", "kf_mclaim_", "kf_house_win_", "kf_offboard_",   // 467 的 kf_mtransfer 族已随待接受区一起撤掉
        "kf_rflt_",                       // 186 备注 / 188 标旗 / 记录筛选视图
        "kf_cseq_", "kf_calias_display", "kf_cbin_", "kf_clists_", 
        "kf_bk_note",                 // 433 备注
        // 2026-10-13 对抗式排查: TOTP/静态口令族漏收。三种导入模式都会写这四个族
        //   · BackupKit.restoreAll :375-376 → otpStatus_ / otpIdx_
        // 而回滚快照只覆盖上面列出的族 ⇒ 导错备份再点「撤销恢复」, 成员/凭证/备注都回去了,
        // **TOTP 种子与静态口令仍停在错包的值** (既是数据错, 也是 2FA 密钥残留, 撤销永远不完整)。
        // 判据①"恢复流程确实会改写它们"②"里面是用户自己攒的内容" 对这四族完全成立。
        "otpStatus_", "otpIdx_", 
        "kf_trace_persist_v1",                                       // 583 最近记录写入回执追踪 (同为恢复写入的用户内容)
        // 2026-10-14 对抗式排查: restoreAll 还会写这七族, 而快照没收 ⇒ 导错备份再"撤销恢复"撤不回来。
        //   · BackupKit.restoreAll 的 meta 段 → kf_defend_ / kf_tailgate_ / kf_synctime_
        //   · deviceOrg 段 → kf_lock_order / kf_lockmeta_ / kf_lock_hidden_ / kf_group_folded
        "kf_defend_", "kf_tailgate_", "kf_synctime_",
        "kf_lock_order", "kf_lockmeta_", "kf_lock_hidden_", "kf_group_folded"
    ]
    struct RollbackBundle: Codable {
        var keychains: [String]      // JSON: [Keychain]
        var ledgers: [[String: String]] // [mac → JSON(Ledger)]
        var dongles: [String]
        var gateways: [String]
        var passcode: String?
        var members: [String]
        /// 键 → 该键在 defaults 里那串 JSON 的 base64。**原样存字节**，
        /// 旧快照没这个字段也照样解得开 (可选字段), 不至于"升级后回滚点全失效"。
        var extras: [String: String]? = nil
    }
    @discardableResult
    nonisolated static func makeRollbackPoint() -> Bool {
        // 421: 先收"分区之外的内容族" (原样字节 → base64), 再打包六分区
        var extra: [String: String] = [:]
        for k in DB.store.matchingKeys(prefixes: rollbackFamilies) {
            if let d = DB.store.rawData(k) { extra[k] = d.base64EncodedString() }
        }
        let snap = RollbackBundle(
            keychains: DB.keychains().compactMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) },
            ledgers: DB.keychains().compactMap { kc in
                guard let d = try? JSONEncoder().encode(DB.ledger(kc.mac)) else { return nil }
                return [kc.mac: String(data: d, encoding: .utf8) ?? ""]
            },
            dongles: DB.dongles().compactMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) },
            gateways: DB.gateways().compactMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) },
            passcode: DB.get([String: String].self, "kf_passcode").flatMap {
                (try? JSONEncoder().encode($0)).flatMap { String(data: $0, encoding: .utf8) }
            },
            members: DB.members().compactMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) },
            extras: extra)
        // 2026-10-13 run 63: 原写 `let url = try? data.write(to: …)` —— `Data.write(to:options:)`
        // 返回 Void, `try?` 得 Void?, 于是 url 是 `()` ⇒ `url.path` 报
        // "value of tuple type '()' has no member 'path'"。URL 单独算, 写盘结果只判成败。
        // 2026-10-14: 秒级时间戳同一秒两次快照会同名覆盖 -> 改毫秒。
        let rollURL = rollbackDir.appendingPathComponent("roll-\(Int(Date().timeIntervalSince1970 * 1000)).json")
        guard let data = try? JSONEncoder().encode(snap),
              (try? data.write(to: rollURL, options: .atomic)) != nil else { return false }
        pruneRollback(keep: 4)
        return true
    }
    private nonisolated static func pruneRollback(keep: Int) {
        let all = (try? FileManager.default.contentsOfDirectory(at: rollbackDir,
                  includingPropertiesForKeys: nil)) ?? []
        let sorted = all.sorted { $0.lastPathComponent > $1.lastPathComponent }
        // 2026-10-13 对抗式排查: 原写 `sorted.suffix(from: keep)` —— keep 恒为 4 (唯一调用点 pruneRollback(keep: 4)),
        // 而**第 1~3 次**生成还原点时目录里只有 1~3 个文件 ⇒ `suffix(from: 4)` 的起始下标越界,
        // Swift 的 `suffix(from:)` 越界是 **preconditionFailure = 直接崩进程**, 不是返回空。
        // 触发路径: 设置-备份点「生成本机还原点」第一次点就崩 (且文件已写盘, 重启后再点还是崩, 直到攒够 4 个)。
        // 用 dropFirst(min(keep, count)) —— 文件不够就一个都不删, 语义与"只留 keep 个"一致。
        for f in sorted.dropFirst(min(keep, sorted.count)) { try? FileManager.default.removeItem(at: f) }
    }

    /// 2026-10-14: register 每进程只能一次 (二次注册抛 NSInternalInconsistencyException)。
    /// 启动注册 + 设置开关 setter 都会调本函数, 用标志去重。
    private static let registeredLock = Locked(false)


    /// 2026-10-26: 原 prune(_ b: BackupBundle, _ z: BZones) 按四分区裁剪；分区概念已删
    /// （从来没有 UI 暴露，全部调用点都传全选），所以本函数不再裁剪任何东西，原样返回。
    /// 2026-10-27 审核：注释原称「bundleFor() 与 WebDAV 推包两处都调它」，
    /// 实际 WebDAV 一族已删，现在只有 bundleFor() 一个调用点。函数本身是恒等映射
    /// （分区概念已删），保留只为不改 bundleFor() 的调用链。
    /// ⚠ 若后续要清理：直接内联到 bundleFor() 即可，无其它牵连。
    static func prune(_ b: BackupBundle) -> BackupBundle { b }



    /// 453 哈希层判定: 与 verifyChecksum 共用一套算法 (新语义 + 旧语义两条都认)
    enum ChecksumState: Equatable { case ok, mismatch, absent }

    struct Preview: Equatable {
        var source: String        // 477 来源信息: 导出时间 + 原设备
        var schema: Int
        var macs: [String]
        var pwdCount: Int
        var fpCount: Int
        var memberCount: Int
        var sampleOk: Int
        var previewTrace: [String]?
        var checksum: ChecksumState = .absent   // 453 哈希层: 解析时算一次, 预览卡直接显示
    }

    static func checksumState(_ text: String) -> ChecksumState {
        guard let data = text.data(using: .utf8),
              let b = try? JSONDecoder().decode(BackupBundle.self, from: data) else { return .absent }
        guard let c = b.checksum else { return .absent }
        var b2 = b; b2.checksum = nil
        let canon = BackupCanonical.canonical(b2)
        // 2026-10-14: 撤回"旧语义只对旧 schema 包放行"的收紧 —— 本仓旧版本导出的包恰恰是
        // schema 5 + 旧 (UTF-8) 语义校验和, 按 schema 判会把用户已有备份误判成篡改 (数据失踪级观感)。
        // 且 FNV 无密钥, 本就只是**意外损坏检测**而非防篡改 (构造者总能按同一算法重算 checksum),
        // 收紧既不增安全又伤兼容。如实两条都认; 真要防篡改得换带密钥的 MAC (另立项)。
        return (BackupCanonical.fnv1a32Hex(canon) == c.lowercased()
            || BackupCanonical.fnv1a32HexLegacy(canon) == c.lowercased()) ? .ok : .mismatch
    }
    /// 195/417/449/450 恢复预演: 魔数/长度先行 (449), 口令解码, schema 升级 (424), 抽 5 条 (450)
    static func preview(text: String, password: String?) throws -> Preview {
        try parsePreview(text: text, password: password).preview
    }
    /// 417 预演与解码包一次产出 (口令层 PBKDF2 只跑一遍);
    /// 453 哈希层: 内容被改过 (mismatch) 在这里就拦下 — 先于任何写库
    static func parsePreview(text: String, password: String?) throws -> (preview: Preview, bundle: BackupBundle) {
        // 2026-10-14: 交接包等文本前面带给人看的 // 说明行 (1048) —— 先剥掉再判机器部分,
        // 否则 JSONDecoder 直接解不出, 本 App 自己导出的交接包反而导不回来。
        var body = stripCommentHeader(text)
        if password != nil || looksEncrypted(body) {
            body = try decryptAny(body, password: password)
        }
        guard let data = body.data(using: .utf8),
              let raw = try? JSONDecoder().decode(BackupBundle.self, from: data) else {
            throw DFUError.msg("口令错误或内容不是备份 (口令层与文件头层都过不了)")
        }
        // 2026-10-14: 比本机新的 schema 直接拒绝 —— 否则字段可能被误读且无任何告警。
        guard raw.schema <= BackupBundle.currentSchema else {
            throw DFUError.msg("备份包 schema \(raw.schema) 高于本机支持的 \(BackupBundle.currentSchema) — 请先升级 App 再导入")
        }
        let ck = checksumState(body)
        if ck == .mismatch {
            throw DFUError.msg("内容哈希不一致 — 已拦下, 未写任何数据; 建议重传这份备份")   // 453 内容哈希不一致
        }
        let m = upgradeChain(raw)
        // 2026-10-26: 这里原有一个 zones 局部数组（设备/凭证/成员/记录四段摘要），
        // 它只用来填 Preview.zones —— 那个字段随分区概念一起删了，所以这里也删。
        // 凭证/指纹计数（Preview 的 pwdCount / fpCount 要用）
        var p = 0, f = 0
        for d in m.devices { p += d.ledger?.pwds.count ?? 0; f += d.ledger?.fps.count ?? 0 }
        let sample = (m.globals?.trace?.lines ?? []).shuffled().prefix(5).count
        let fallback = Keychain(mac: m.currentMac, skey: "")
        let sourceName = m.currentMac.isEmpty ? "" : LockArchive.displayName(DB.keychain(m.currentMac) ?? fallback)
        let pv = Preview(source: "备份时间 \(m.at)" + (sourceName.isEmpty ? "" : " · 来源 \(sourceName)"),
                         schema: m.schema,
                         macs: m.devices.map { $0.mac },
                         pwdCount: p, fpCount: f,
                         memberCount: m.members?.count ?? 0,
                         sampleOk: sample,
                         previewTrace: Array((m.globals?.trace?.lines ?? []).prefix(5)),
                         checksum: ck)
        return (pv, m)
    }
    /// 1048: 剥掉开头连续的 // 说明行与空行 (交接包头部), 返回机器可读部分; 没有头部则原样返回。
    private static func stripCommentHeader(_ s: String) -> String {
        guard s.contains("\n") else { return s }
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
        var idx = 0
        for (i, ln) in lines.enumerated() {
            let t = ln.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("//") { idx = i + 1; continue }
            break
        }
        guard idx > 0 else { return s }
        return lines[idx...].joined(separator: "\n")
    }
    private static func looksEncrypted(_ s: String) -> Bool {
        // 449: 魔数加宽为**信封全键** (v/alg/kdf/ivHex/macHex/cHex 齐) —— 原先只凭 "{"+"cHex"
        // 两个片段, 任何碰巧含这两个片的文本都会被拖进解密层, 报出"此备份带口令"这种指错方向的错。
        // 缺键的文本按明文包走, 由 JSON 层如实报"不是备份"; 长度校验在 CryptoBox.decryptEnvelope 里。
        s.hasPrefix("{") && s.contains("\"cHex\"") && s.contains("\"ivHex\"")
            && s.contains("\"macHex\"") && s.contains("\"kdf\"")
    }
    /// 420/453 失败分层: 口令 / 文件头 / 内容哈希
    static func decryptAny(_ text: String, password: String?) throws -> String {
        guard looksEncrypted(text) else { return text }
        guard let pw = password, !pw.isEmpty else {
            throw DFUError.msg("此备份带口令 — 输入导出时设置的口令")   // 453 此备份带口令
        }
        return try CryptoBox.decryptEnvelope(text, password: pw)
    }
    /// 424 升级链: 旧 schema 键位映射 (v1→v5 逐级, 每级幂等)
    static func upgradeChain(_ b: BackupBundle) -> BackupBundle {
        var out = b
        var s = b.schema
        if s < 2 { out.members = out.members ?? []; s = 2 }
        if s < 3 { for i in out.devices.indices { out.devices[i].mac = DB.normalizeMac(out.devices[i].mac) }; s = 3 }
        if s < 4 {
            // 2026-10-13 run 63: 原写 `if var g = out.globals { g.trace = g.trace; out.globals = g }` ——
            // 自赋值 (编译器报 "assigning a property to itself"), 整段是空操作。v4 无实际迁移动作,
            // 只推进版本号 (幂等: 下一级判断读的就是 s)。
            s = 4
        }
        if s < 5 {
            // v5: otpStatus/otpIdx 从 synctime 序列拆出为独立键位 (旧版塞在 meta 之后)。
            // 2026-10-13 run 63: 原写 `m.otpStatus = m.otpStatus; m.otpIdx = m.otpIdx` (两处自赋值),
            // 同样是空操作 —— 拆键的实际动作当年没落进来, 这里只推进版本号, 不假装做了迁移。
            s = 5
        }
        out.schema = s
        return out
    }
    /// 418/427/441: 策略 + 分区裁剪 + 逐锁动作; 返回 (新增, 覆盖, 跳过)
    /// - lockActs: 441 迁移逐把确认 — mac(已规范化) → merge/keep/skip, 缺省 merge; 只在 .merge 生效
    /// - conflictTakeBackup: 419 冲突裁决 — id (mac:p:别名 / mac:f:批次) 集合, 命中 = 该条取备份, 未命中保本机
    /// - makeSnapshot: 445 迁移事务自己持回滚点, 逐锁调用时传 false, 免得把迁移前的快照覆盖成中途态
    @discardableResult
    static func restore(_ bundle: BackupBundle, 
                        lockActs: [String: String] = [:],
                        conflictTakeBackup: Set<String> = [],
                        makeSnapshot: Bool = true) -> (imported: Int, overwritten: Int, skipped: Int) {
        var b = bundle
        b.currentMac = ""   // 首验清 currentMac, 避免指向另一台设备的锁
        let c = prune(b)
        // 421 恢复回滚点: 执行前自动全库快照
        if makeSnapshot { _ = makeRollbackPoint() }
        // 合并 = **只增不删**。旧实现把 .merge 并入 .overwrite 走 restoreAll,
        // 而 restoreAll 用 DB.saveLedger 整表替换 (BackupKit.swift:206) → 选"合并"仍删掉本机新增凭证。
        var remap = [String: String]()
        if let members = c.members { importMembers(members, remap: &remap) }
        var mimp = 0, mover = 0, mskip = 0
        for d in c.devices {
            guard HexKit.bytes(d.mac).count == 6, !d.kc.skey.isEmpty else { continue }
            let mac = DB.normalizeMac(d.mac)
            // 441 逐把确认: merge(默认) = 钥匙串与凭证都并; keep = 保留本机台账, 只迁直连参数; skip = 整锁跳过
            let act = lockActs[mac] ?? "merge"
            if act == "skip" { mskip += 1; continue }
            var kc = d.kc
            kc.mac = mac
            // 441 BLE 直连参数随锁走: 已有锁也刷新钥匙串, 否则换机后新机连不上这把锁
            let existed = DB.keychain(mac) != nil
            DB.saveKeychain(kc)
            if existed { mover += 1 } else { mimp += 1 }
            // 441 锁端运行参数 (防御/防尾随/同步时间/OTP 状态) 与钥匙串同批迁移;
            // 旧实现只在 .missing 分支写 meta, 合并路径永远迁不过去
            if let meta = d.meta {
                if let x = meta.defend { DB.saveDefend(mac, x) }
                if let x = meta.tailgate { DB.saveTailgate(mac, x) }
                if let t = meta.synctime { DB.saveSyncTime(mac, t) }
                if let o = meta.otpStatus { DB.saveOtpStatus(mac, o) }
                if let o = meta.otpIdx { DB.saveOtpIdx(mac, o) }
                // 2026-10-28 修复：`Meta.mobileKeys` 反向也要回写 —— 否则备份带了、恢复不写，
                // 同一份数据在"导出侧补了序列化"之后仍然进不了本机。
                if let mk = meta.mobileKeys { MobileKeyService.save(mac, mk) }
            }
            guard act != "keep", let l = d.ledger else { continue }
            var cur = DB.ledger(mac)
            let haveP = Set(cur.pwds.map { $0.alias }), haveF = Set(cur.fps.map { $0.batch })
            for p0 in l.pwds {
                var p = p0
                if let o = p.owner { p.owner = remap[o] ?? (DB.member(o) != nil ? o : nil) }
                if haveP.contains(p0.alias) {
                    // 419 同 ID 凭证冲突: 只有用户裁决为"取备份"才覆盖, 未裁决默认保本机 (只增不删)
                    guard conflictTakeBackup.contains("\(mac):p:\(p0.alias)") else { continue }
                    if let i = cur.pwds.firstIndex(where: { $0.alias == p0.alias }) {
                        cur.pwds[i] = p
                        mover += 1
                    }
                } else {
                    cur.pwds.append(p)
                    mimp += 1
                }
            }
            for f0 in l.fps {
                var f = f0
                if let o = f.owner { f.owner = remap[o] ?? (DB.member(o) != nil ? o : nil) }
                if haveF.contains(f0.batch) {
                    guard conflictTakeBackup.contains("\(mac):f:\(f0.batch)") else { continue }
                    if let i = cur.fps.firstIndex(where: { $0.batch == f0.batch }) {
                        cur.fps[i] = f
                        mover += 1
                    }
                } else {
                    cur.fps.append(f)
                    mimp += 1
                }
            }
            DB.saveLedger(mac, cur)
        }
        // 全局项 (dongle/gateway/应用锁/OTP 键位/记录) 旧实现合并分支一个不写 ——
        // WebDAV 下载恢复与换机迁移走的都是 .merge, 结果这些内容整类进不来。与 .missing 同口径补齐。
        if let g = c.globals {
            // 2026-10-14: 外观与设备组织随包落地 (与 .overwrite 同口径)
            BackupKit.applyGlobalsAppearanceAndOrg(g, devices: c.devices)
            for d in g.keychainDongles ?? [] { DB.saveDongle(d) }
            for gw in g.gatewayList ?? [] { DB.saveGateway(gw) }
            if let pc = g.passcode, !pc.s.isEmpty, !pc.d.isEmpty {
                // 同 BackupKit.restoreAll: 只写 s/d (d2 不进 canonical, 包体里没有)
                DB.store.set("kf_passcode", ["s": pc.s, "d": pc.d])
            }
            if let tr = g.trace, let lines = tr.lines, !lines.isEmpty {
                DB.store.set("kf_trace_persist_v1", [
                    "savedAt": tr.savedAt ?? 0, "count": lines.count,
                    "chars": tr.chars ?? 0, "lines": lines,
                ])
            }
        }
        return (mimp, mover, mskip)
    }

    /// 导入成员并建立「旧 id → 本机 id」映射（恢复包里的凭证 owner 要按这个 remap 重写）。
    private func importMembers(_ members: [Member], remap: inout [String: String]) {
            for m in members {
                if let hit = DB.members().first(where: { $0.name == m.name }) {
                    remap[m.id] = hit.id
                } else if let created = DB.addMember(m.name) {
                    remap[m.id] = created.id
                    DB.setMemberInfo(created.id, ["relation": m.relation, "phone": m.phone])
                }
            }
    }





    // ================= 完整性与信任感 (448-454 / 507-512) =================
    /// 库体指纹 (448/397 共用一份算法, 免得两处各算各的后端口径漂移)
    /// 库体指纹算法版本: 变更时递增 —— 旧基线 (不带前缀) 不参与比对, 免得升级后误报自检异常。
    private static let fpVersion = "2:"

    /// 448 启动自检: 库体哈希 vs 上次备份时的基线; 不一致返回黄条文案。
    /// 基线只在备份发生点 (markBackupBaseline, 由 Milestones.recordBackup 尾调用) 更新,
    /// 本函数只比不改 —— 自查后回写会把上一次的异常直接抹平。
    static var selfCheckWarning: String? {
        DB.store.getBool("kf_bk_selfwarn") ? "数据自检异常, 去诊断" : nil   // 448 数据自检异常
    }
    /// 507 备份状态角标: 今日已备份 / 多日未备份
    // 2026-10-26 精简：badgeState（备份状态角标）已删 —— 它依赖的 lastExportMs 随策略类一起移除。

    struct RemoteEntry: Identifiable { var id: String { name }; let name: String; let size: Int; let etag: String; let modified: String }


    /// 认不出信封就说"未能识别"，绝不回落到徽章那串 —— 那会把一个明文包或损坏件标成"加密过"。
    /// 明文包 (BackupBundle 直接写盘, 没有信封) 单独一档: 混进"未能识别"会让人以为文件坏了。
    enum AlgoNote: Equatable { case envelope(String), plain, unknown }

    // ================= 511 数据事件 (导出/恢复/迁移) =================
    /// 事件带名字: 旧实现收 `_ label: String` 却只存毫秒, 列表只能显示"备份事件 #N" ——
    /// 参数像有能力、实际什么都不记, 是本仓反复出现的"命名即承诺"缺陷类, 这里把名字真存下来。
    struct BkEvent: Codable { var at: Double; var label: String }
    static func recordEvent(_ label: String) {
        var h = bkEvents()
        h.append(BkEvent(at: Date().timeIntervalSince1970 * 1000, label: label))
        if h.count > 60 { h.removeFirst(h.count - 60) }
        DB.store.setCodable("kf_bk_events", h)
    }
    /// 读侧兼容旧形态: 万一磁盘上躺着 [Double] (只有毫秒没有名字), 解成新结构并标"未具名", 不静默丢历史
    private static func bkEvents() -> [BkEvent] {
        if let v = DB.store.get([BkEvent].self, "kf_bk_events") { return v }
        if let old = DB.store.get([Double].self, "kf_bk_events") { return old.map { BkEvent(at: $0, label: "未具名") } }
        return []
    }

}

