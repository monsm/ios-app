// 包8 备份工作室服务层 — 备份·恢复·换机迁移
// 覆盖 idea: 181/193/197/198/237/407-413/417-427/429-431/434-436/438-446/448-450/453/454/456/477/507-509/511/512/1018/1048
// 纪律: 备份文件只去用户自配 WebDAV (Basic Auth 运行时输入), 口令不出本机内存;
//       加密语义 (CryptoBox AES-128-CBC+HMAC/PBKDF2, ZOTP 相关) 不动, 本层只做外围策略。
import Foundation
import UIKit
import CoreImage.CIFilterBuiltins
@preconcurrency import UserNotifications   // 通知中心对象是系统侧线程安全的, SDK 未标 Sendable


// 2026-10-26: 原 `BZones`（设备/凭证/记录/设置四分区）已删 —— 分区模型从来没有 UI 暴露，
// 全部调用点都传 `BZones()`（= 全选）。既然用户永远只能全量备份，那四个开关就是纯装饰。
// `prune(_:_:)` 与 `bundleFor(_:)` 的分区参数一并去掉，改为一律全量。

@MainActor
enum BackupStudio {
    // ================= 路径与命名 (409/410) =================
    /// FileManager 在 iOS 上必然返回一个 documentDirectory；取 .first 加兜底只是
    /// 为了避免任何未来环境（沙箱/测试宿主）下的空数组下标崩溃。
    nonisolated private static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: "/tmp", isDirectory: true).appendingPathComponent("Documents", isDirectory: true)
    }
    nonisolated private static var appSupportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: "/tmp", isDirectory: true).appendingPathComponent("Library/Application Support", isDirectory: true)
    }
    // nonisolated: makeRollbackPoint/pruneRollback 本就是 nonisolated 而引用了这两个路径,
    // 挂在 @MainActor 枚举上会直接编译不过 (纯 FileManager, 无 actor 状态)
    nonisolated static var dir: URL {
        let base = documentsURL
            .appendingPathComponent("lockkeeper-backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        // SEC-02/SEC-10：备份目录里装的是完整 skey/pins/ekey，绝不能随 iCloud/iTunes 备份出机。
        var v = URLResourceValues()
        v.isExcludedFromBackup = true
        var mutable = base
        try? mutable.setResourceValues(v)
        return base
    }
    /// 回滚快照点的是**整库 Keychain (skey/ivKey 明文)**, 旧版把它放在导出目录的 `rollback/` 子目录里:
    /// Documents 下的文件既进 iTunes/Finder 备份, 开了文件共享时还能被"文件"App 直接看到,
    /// 而 413 的分享流程又把同一个目录当作用户可见的备份文件夹。现移入 Application Support 并标记不备份,
    /// 同时把旧目录里已经落盘的明文快照一次性删掉。
    nonisolated static var rollbackDir: URL {
        let base = appSupportURL
            .appendingPathComponent("lockkeeper-rollback", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var v = URLResourceValues()
        v.isExcludedFromBackup = true
        var mutable = base
        try? mutable.setResourceValues(v)
        let legacy = documentsURL
            .appendingPathComponent("lockkeeper-backups/rollback", isDirectory: true)
        if FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.removeItem(at: legacy)
        }
        return base
    }




// ---------- 421 恢复回滚点（**只生成、无消费**） ----------
//
// ⚠ 2026-10-30 核实（第 98 轮）：本段的 `makeRollbackPoint()` 只被 `restore(…)` 在恢复前调用一次，
// 把当前全库打包成 `roll-<ms>.json` 写到 `rollbackDir`；**全仓没有任何代码读取或应用这些快照** ——
// 既没有 `loadRollbackPoint`，UI 里也没有「撤销恢复」入口（`BackupView` 全文无相关按钮）。
//
// 也就是说：421 当初设计的「恢复后 24h 内可撤销」**从未实现**，现在的行为是
// 「每次恢复前写一个快照文件，留 4 个轮换，然后永远不用」。
//
// 为什么不删：这些文件是**恢复前唯一的数据副本** —— 手工抢救时用户/支持人员可以直接解
// `roll-*.json`（结构见 `RollbackBundle`）把内容读回来。它是有价值的"逃生舱"，只是没有 UI。
// 但注释必须如实，不能继续写「24h 内可撤销」（那是本仓反复清理的「文档虚构能力」）。
//
// 真要接 UI：需要新增 `loadRollbackPoint(url) -> RollbackBundle?` + `applyRollback(_:)`，
// 并在设置页给出「最近 4 个还原点」列表。那是独立特性，不是一行接线。

// ---------- 421 回滚点补洞: 这些键族不在六个分区里 ----------
    /// 421 回滚点补洞: 这些键族不在六个分区里, 而**覆盖恢复会整表替换台账、按名字重建成员** ——
    /// 它们是按 `mac + 凭证 alias` 或 `成员 id` 挂钩的, 于是恢复之后:
    /// 要么指向已经不存在的行/成员 (用户看到的是"备注和标旗凭空没了"), 要么变成没人清的孤儿键;
    /// 2026-10-30 修正（第 98 轮）：原句写「`undoLastRestore` 旧实现只回滚六分区」——
    /// 而全仓**没有 `undoLastRestore` 这个函数**（它只出现在这一句注释里）。
    /// 这句「旧实现」描述的是 421 最初设计里的撤销流程，该流程**从未落地**。
    /// 现在的实际约束是：快照本身要收全这些族，才谈得上「将来若接上撤销能撤完整」。
    /// 判定标准两条: ① 恢复流程确实会改写它们指向的东西; ② 里面是用户自己攒的**内容** (不是遥测、不是开关档位)。
    /// 刻意不收: 日志与遥测 (kf_diag_logs / kf_fevents_ / kf_ble_events …) 体积大且不是内容;
    /// 外观与开关的**分界**（2026-10-30 第 63 轮修正）：
    ///   · `collectAppearance` 里**会导出、restore 会写回**的那 13 个外观键 → **必须收**（否则撤销恢复不完整，见下）；
    ///   · 纯开关类（`kf_ax_*` / `kf_slock_*` / `kf_quick_*` …）恢复流程从不碰 → **仍然刻意不收**，
    ///     收进快照反而会把用户这段时间改过的设置一起回滚掉。
    nonisolated static let rollbackFamilies: [String] = [
        "kf_member_ext", "kf_member_bday", "kf_member_badge",       // 成员档案扩展 (角色/备注/分组/归档)
        "kf_mborrow_", "kf_mclaim_", "kf_house_win_", "kf_offboard_",   // 467 的 kf_mtransfer 族已随待接受区一起撤掉
        // 2026-10-30 修正（第 66 轮）：原注释「186 备注 / 188 标旗」**写错了族** ——
        // `kf_rflt_<mac>` 是 QueryFilters 的**过滤会话**（记住上次的筛选组合），不含备注也不含旗标。
        // 真正的记录页覆盖层是另外三族，它们此前**既不进备份、也不进回滚**：
        //   · kf_rnote_<mac>  行备注（用户手写的自由文本，Store.removeDevice 的族表注释明确写着"敏感本地数据"）
        //   · kf_rflag_<mac>  行标旗
        //   · kf_rdisp_<mac>  行处置（「标记已处置 / 撤销」，告警排查的核心：谁在什么时候确认过这条）
        // 这三族是用户自己攒的**内容**，且 restore 会整表替换台账/重建成员 ⇒ 恢复后行键全部失效，
        // 不收进快照就等于「备注和旗标凭空没了」，也撤不回来 —— 与 421 当初补洞的判据同源。
        "kf_rflt_", "kf_rnote_", "kf_rflag_", "kf_rdisp_", "kf_rdispo",
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
        "kf_lock_order", "kf_lockmeta_", "kf_lock_hidden_", "kf_group_folded",
        // 2026-10-30 对抗式排查（第 63 轮）：外观段的这四个键同样由 restore 写，而快照没收 ⇒
        // 导错备份再「撤销恢复」时，主题/密度/圆角/星期起始都回来了，但**高对比、素色、
        // 首页统计可见集、最近开门条数**停在了错包的值 —— 用户看到的界面和点撤销之前不一样。
        //   · BackupKit.applyGlobalsAppearanceAndOrg → kf_hc / kf_plain / kf_hero_stats / kf_recent_count
        // 判据与上面两批同源：①恢复流程确实会改写它们 ②里面是用户自己攒的偏好。
        // 其余外观键（kf_theme / kf_accent / kf_density / kf_radius / kf_week_start / kf_row_h /
        // kf_tl_gap / kf_motion / kf_hero_tex）在 collectAppearance 里**只导出枚举白名单内的值**，
        // 恢复时写回的也一定是那几档 —— 但它们同样是"恢复会写"，一并补进来才叫撤销完整。
        "kf_hc", "kf_plain", "kf_hero_stats", "kf_recent_count",
        "kf_theme", "kf_accent", "kf_density", "kf_radius", "kf_week_start",
        "kf_row_h", "kf_tl_gap", "kf_motion", "kf_hero_tex",
        // 2026-10-30 补（第 65 轮）：**无障碍/交互偏好**这批既没进备份、也没进回滚。
        // 它们与外观同性质（用户主动拨、restore 会写回），因此两条路都要覆盖：
        //   · 备份：BackupBundle.Globals.Appearance 新增 10 个 Optional 字段
        //   · 回滚：本名单（否则「撤销恢复」把大字/大格/圆盘大小停在错包的值）
        "kf_ax_bigotp", "kf_ax_bigpreview", "kf_ax_hold", "kf_bigtile",
        "kf_dial_size", "kf_digit_font", "kf_gesture_mode",
        "kf_hold_confirm", "kf_dbltap_guard", "kf_elder_mode"
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
    /// SEC-19：删设备时清理含该 MAC 的本机备份文件与还原点。
    /// 判据：备份是 canonical JSON，文件里出现该 MAC（小写或大写）即视为含这把锁的数据。
    /// 宁可多删一个「可能含它的」文件，也不要留下一个能恢复母钥的包。
    nonisolated static func purgeLocalArtifacts(mac: String) {
        let m = DB.normalizeMac(mac)
        guard !m.isEmpty else { return }
        for dir in [dir, rollbackDir] {
            let files = (try? FileManager.default.contentsOfDirectory(at: dir,
                        includingPropertiesForKeys: nil)) ?? []
            for f in files where f.pathExtension == "json" {
                guard let data = try? Data(contentsOf: f),
                      let text = String(data: data, encoding: .utf8) else { continue }
                if text.lowercased().contains(m) { try? FileManager.default.removeItem(at: f) }
            }
        }
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
        // SEC-09/SEC-10：快照里有整库 skey/pins 明文 —— 必须「锁屏即不可读」。
        guard let data = try? JSONEncoder().encode(snap),
              (try? data.write(to: rollURL, options: [.atomic, .completeFileProtection])) != nil else { return false }
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



    /// SEC-30：导入体积上限。正常全量备份是几百 KB 量级，32MB 已经留了三个数量级余量；
    /// 超过就当不是备份拒绝掉，免得一个超大文件在 JSONDecoder 之前就把内存吃满。
    /// 界面上选文件时也要用同一个常量**先查大小再读内容**（见 BackupScreen.readBackupFile）。
    nonisolated static let maxImportBytes = 32 * 1024 * 1024

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
        /// 恢复时**会被跳过**的锁数（非法 skey / 非法 pin）。
        /// 2026-11-01 补：`pwdCount` 统计的是"包里声明了多少条"，而恢复时 SEC-08 会整把锁跳过 ——
        /// 预演若只说"包里有 8 条"，用户点确认后实际只回来 3 条，会以为备份坏了。
        /// 预演阶段就把这个数报出来，用户可在确认前决定。
        var skippedLocks: Int = 0
    }

    /// SEC-14 与"旧版本包校验和本就该不同"之间的**折中：二次确认，不是硬拦**（2026-11-01）。
    ///
    /// 我第 8 轮把 .mismatch 改成了直接拒绝恢复 —— 那是**过度收紧的回归**：
    /// 本仓早期版本导出的包用的是旧键序 canonical，算出的 FNV 必然与当前不同
    /// （见 checksumState 里 2026-10-14 的注释，那里已明确"按 schema 判会把用户已有
    /// 备份误判成篡改"）。硬拒绝的实际后果是把用户自己的合法备份挡在门外 ——
    /// "恢复不了"比"被半截包覆盖"更糟，因为它让唯一的数据出口失效。
    ///
    /// 但完全不提示也不对。所以：第一次点只要求确认，第二次点才真恢复。
    /// 既防误触与截断包意外覆盖，又不摧毁兼容性。
    /// 真要防篡改得换带密钥的 MAC（另立项），FNV 无密钥本就不是防篡改手段。
    static func checksumNeedsAck(_ state: ChecksumState) -> Bool { state == .mismatch }

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
        // SEC-30：先做长度闸。一个几 GB 的「备份」会在 JSONDecoder 阶段把内存吃光。
        guard text.count <= Self.maxImportBytes else {
            throw DFUError.msg("备份文本过大（>32MB）—— 正常备份远小于此，请确认选对了文件")
        }
        var body = stripCommentHeader(text)
        if password != nil || looksEncrypted(body) {
            body = try decryptAny(body, password: password)
        }
        guard let data = body.data(using: .utf8),
              let raw = try? JSONDecoder().decode(BackupBundle.self, from: data) else {
            throw DFUError.msg("口令错误或内容不是备份 (口令层与文件头层都过不了)")
        }
        // 2026-10-14: 比本机新的 schema 直接拒绝 —— 否则字段可能被误读且无任何告警。
        // SEC-30：类型与规模闸 —— 只接受本 App 的备份包，且设备数有上限。
        guard raw.type == "kf-bundle" else {
            throw DFUError.msg("这不是锁管家备份包（type=\(raw.type)）")
        }
        guard raw.devices.count <= 64 else {
            throw DFUError.msg("备份包含 \(raw.devices.count) 把锁，超过上限 64 —— 拒绝导入")
        }
        guard raw.schema <= BackupBundle.currentSchema else {
            throw DFUError.msg("备份包 schema \(raw.schema) 高于本机支持的 \(BackupBundle.currentSchema) — 请先升级 App 再导入")
        }
        let ck = checksumState(body)
        // 2026-10-31: 校验和不一致**不再硬拦**。
        // 原因：旧 App（以及本仓早期版本）导出的包里 members/globals 的键序与当前 canonical 不同，
        // 同一个包在两边算出的 FNV 值必然不同 —— 硬拦会把用户自己的合法备份判成"篡改"，
        // 直接表现就是"恢复不了"。FNV1a32 本身无密钥、只用于检测意外损坏，不是防篡改手段
        // （见 checksumState 里的注释），所以这里降级为**告警**：预览页如实显示 .mismatch，
        // 由用户自己决定是否继续；结构解析（JSON/魔数/schema）仍然照旧强校验。
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
                         checksum: ck,
                         skippedLocks: m.devices.filter { d in
                             !(HexKit.bytes(d.mac).count == 6 && CryptoBox.isHex(d.kc.skey, len: 32))
                                 || d.kc.pins.contains { !CryptoBox.isHex($0, len: 8) }
                         }.count)
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
        // SEC-17：只清**本次真要恢复的那些锁**的损坏标记。
        // 旧实现无条件 clearAllLedgerCorrupt()：用户只为 A 锁导入备份，却把 B 锁
        // "解不出但可人工恢复"的台账标记一起清掉，B 锁下一次 saveLedger 就会按空表覆盖 —— 数据永久丢失。
        for d in c.devices {
            let mac = DB.normalizeMac(d.mac)
            if (lockActs[mac] ?? "merge") != "skip" { DB.clearLedgerCorrupt(mac) }
        }
        // 421 恢复回滚点: 执行前自动全库快照
        if makeSnapshot { _ = makeRollbackPoint() }
        // 合并 = **只增不删**。旧实现把 .merge 并入 .overwrite 走 restoreAll,
        // 而 restoreAll 用 DB.saveLedger 整表替换 (BackupKit.swift:206) → 选"合并"仍删掉本机新增凭证。
        var remap = [String: String]()
        if let members = c.members { importMembers(members, remap: &remap) }
        // 成员档案扩展（角色/备注/关怀文案/…）按同一张 remap 写回。
        // 只在目标成员**仍是全默认档案**时写：已存在的成员保留本机现状，不被旧包覆盖。
        if let ext = c.globals?.memberExt { importMemberExt(ext, remap: remap) }
        var mimp = 0, mover = 0, mskip = 0
        for d in c.devices {
            // SEC-08：不只看"非空" —— 非 32 位十六进制的 skey 会覆盖 Keychain 里的真密钥，
            // 此后所有加密帧用错密钥，原锁再也开不了（软砖）。pin 必须是 8 位十六进制。
            guard HexKit.bytes(d.mac).count == 6, CryptoBox.isHex(d.kc.skey, len: 32) else {
                BleTelemetry.recordEvent("备份里有非法 skey，已跳过该锁 @" + String(d.mac.prefix(6)), ok: false)
                mskip += 1
                continue
            }
            let badPins = d.kc.pins.filter { !CryptoBox.isHex($0, len: 8) }
            guard badPins.isEmpty else {
                BleTelemetry.recordEvent("备份里有非法 pin，已跳过该锁 @" + String(d.mac.prefix(6)), ok: false)
                mskip += 1
                continue
            }
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
                // 2026-10-30 补（第 66 轮）：记录页覆盖层（备注 / 标旗 / 处置）。
                // 与 mobileKeys 同一条纪律 —— 备份带了、恢复不写，等于"导出侧补了序列化"却进不了本机。
                // 缺字段 = 这次备份没带 = 不动本机（不主动清掉用户本机已有的备注）。
                if let n = meta.recNotes { RecordOverlay.setNotes(mac, n) }
                if let f = meta.recFlags { RecordOverlay.setFlags(mac, Set(f)) }
                if let dd = meta.recDisps { RecordOverlay.setDispositions(mac, dd) }
                // 2026-11-01：到期提醒档位回写（键形如 `pwd:<alias>`）。
                // 缺字段 = 这次备份没带 = 不动本机（与上面几族同口径）。
                if let sq = meta.seq { CredentialOrg.setSeq(mac, sq) }
                if let st = meta.stars { CredStarStore.set(mac, Set(st)) }
                if let al = meta.alerts {
                    for (k, a) in al {
                        guard k.hasPrefix("pwd:"), let alias = Int(k.dropFirst(4)) else { continue }
                        DB.setCodable(a, CredentialOrg.alertKey(mac, "pwd", alias))
                    }
                }
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
                // SEC-06：包里有 d2（强摘要）就写 d2 —— 只写 d 等于把 App 密码降级成 32 位 FNV。
                // 旧包没有 d2 时：若本机已有 d2，**保留本机 d2**（不要把强摘要降级成弱摘要）。
                DB.store.set("kf_passcode", Self.mergedPasscodeRecord(pc, key: "kf_passcode"))
            }
            if let dc = g.duress, !dc.s.isEmpty, !dc.d.isEmpty {
                // 2026-10-30 修复（第 64 轮）：胁迫码与正常密码同一套 PBKDF2 摘要，但存在独立键里。
                // 原先只导出/恢复 kf_passcode ⇒ 换机后胁迫码静默消失，
                // 而「被胁迫时输它会进空壳模式」是一条安全承诺 —— 承诺随换机失效属「不正常」。
                // 与 passcode 同口径：缺字段/空摘要 = 这次备份没带 = 不动本机（不主动清除用户已设的码）。
                DB.store.set("kf_duress", Self.mergedPasscodeRecord(dc, key: "kf_duress"))
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

    /// SEC-06：合并包内口令摘要与本机既有摘要，**绝不把强摘要降级成弱摘要**。
    /// - 包里有 d2（新包）→ 直接用包的（s/d/d2 必须成对，salt 也随包走）。
    /// - 包里没有 d2（旧包）→ 若本机同一 salt 下已有 d2，保留本机 d2；否则只写 s/d。
    static func mergedPasscodeRecord(_ pc: BackupBundle.Globals.PasscodeRec, key: String) -> [String: String] {
        var rec: [String: String] = ["s": pc.s, "d": pc.d]
        if let d2 = pc.d2, !d2.isEmpty {
            rec["d2"] = d2
        } else if let local = DB.get([String: String].self, key),
                  (local["s"] ?? "") == pc.s,
                  let localD2 = local["d2"], !localD2.isEmpty {
            rec["d2"] = localD2
        }
        return rec
    }

    /// 导入成员并建立「旧 id → 本机 id」映射（恢复包里的凭证 owner 要按这个 remap 重写）。
    /// 写回成员档案扩展。`remap` 是旧 id → 本机 id（`importMembers` 建的）。
    /// 判据是「目标成员仍是全默认档案」—— 这样二次恢复同一个包不会覆盖用户此后改过的内容。
    private static func importMemberExt(_ table: [String: MemberExt], remap: [String: String]) {
        for (oldID, e) in table {
            guard let newID = remap[oldID], DB.member(newID) != nil else { continue }
            guard MemberHub.ext(newID) == MemberExt() else { continue }
            MemberHub.saveExt(newID, e)
        }
    }

    private static func importMembers(_ members: [Member], remap: inout [String: String]) {
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

    // 448「数据自检异常」常驻黄条：**已删除**（2026-11-01）。
    // 原实现读 `kf_bk_selfwarn`，而全仓**没有任何地方写这个键** —— 一条永远不会出现的警告，
    // 属于本文件下面自己命名的"命名即承诺"缺陷类。
    // 而且它想表达的是"上次备份后数据有变化"，那在正常使用中是**常态**（改一条凭证就会变），
    // 做成常驻黄条只会天天喊狼来了。
    // 真正有用的是**按需自检**：`BackupStudioScreen.runSelfCheck()` 用 `kf_bk_base` 基线现算现报。
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

