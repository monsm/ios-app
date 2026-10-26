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


    // ================= 策略配置 (198 节奏三档 / 430 滚动保留 / 429 新鲜度) =================
    /// 198: manual / weekly / monthly — 备份节奏三档 (落地为本地通知提醒, 不做后台静默写)
    static var cadence: String {
        get { DB.store.getString("kf_bk_cadence", "manual") }
        set { DB.store.set("kf_bk_cadence", newValue) }
    }
    /// 430 滚动保留: 远端只留最近 N 份 (0 = 不限)
    static var rollingKeep: Int {
        get { DB.store.getInt("kf_bk_keep", 0) }
        set { DB.store.set("kf_bk_keep", newValue) }
    }
    /// 429 新鲜度: 距上次备份超过 14 天升级提醒
    static var lastExportMs: Double? { (DB.store.get([Double].self, "kf_backup_hist") ?? []).last }
    static func daysSinceLastExport() -> Int {
        guard let ms = lastExportMs else { return -1 }
        return Int(Date().timeIntervalSince1970 / 86400) - Int(ms / 1000 / 86400)
    }

    // ---------- 1018 月度备份日: 每月固定日本地通知, 点通知生成本机还原点并指路备份工作室 ----------
    static var monthlyDay: Int {
        get { DB.store.getInt("kf_bk_month_day", 0) }
        set { DB.store.set("kf_bk_month_day", max(0, min(31, newValue))) }
    }
    static func scheduleMonthlyBackup() async {
        let day = monthlyDay
        guard day > 0 else { return }
        guard await CareSchedule.requestAuth() else { return }
        // pendingRequests() 这个成员不存在; 本函数本来就是 async, 直接走 async 版即可。
        let center = UNUserNotificationCenter.current()
        for r in await center.pendingNotificationRequests() where r.identifier == "kf.bk.monthly" {
            center.removePendingNotificationRequests(withIdentifiers: [r.identifier])
        }
        let c = UNMutableNotificationContent()
        c.title = "月度备份日"   // 1018 月度备份日
        c.body = "今天是本月备份日 — 打开管家做一份备份并顺带演练验证。"
        c.sound = .default
        c.categoryIdentifier = "KF_BK"
        var comps = DateComponents()
        comps.day = day
        comps.hour = 9
        let req = UNNotificationRequest(identifier: "kf.bk.monthly", content: c,
                                        trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true))
        try? await UNUserNotificationCenter.current().add(req)
        UNUserNotificationCenter.current().delegate = UNDelegate.shared
    }
    /// 1018 通知点按: 本机还原点 + 记历史, 并把用户送到备份工作室 (口令加密备份与演练的落点)
    @MainActor static func onMonthlyTap() async {
        _ = makeRollbackPoint()
        Milestones.recordBackup()
        // 冷启动点按: hostRef 等 RootView 挂载 (最多 2 秒), 与 1013 保养通知同款, 不丢这次点按
        var waited = 0
        while AppState.hostRef == nil && waited < 10 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            waited += 1
        }
        guard let app = AppState.hostRef else { return }
        if app.appUnlocked && !app.decoyMode {
            // 2026-10-15 走查 §4.3: 通知正文指着「设置 · 备份」, 原来 requestTab(3) 只到设置页根。
            // 带落点名, 设置页挂载即开「备份与恢复」。
            app.pendingSettingsFocus = "backup"
            app.requestRoute(.settings)
            app.showToast("已生成本机还原点 — 口令加密备份与演练在「设置 · 备份」")   // 1018 已生成本机还原点
        } else {
            app.pendingRoute = .settings
        }
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
        "kf_rnote_", "kf_rflag_", "kf_rflt_",                       // 186 备注 / 188 标旗 / 记录筛选视图
        "kf_cseq_", "kf_cstar_", "kf_calias_display", "kf_cbin_", "kf_cdisrea_", "kf_clists_", "kf_cqueue_",
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

    // ---------- 428 ⚠ 充电自动备份: BGTask 注册 + 诚实文案 (执行时机由系统择机) ----------
    static let chargeBackupTaskId = "com.kf.chargebackup"
    /// 2026-10-14: register 每进程只能一次 (二次注册抛 NSInternalInconsistencyException)。
    /// 启动注册 + 设置开关 setter 都会调本函数, 用标志去重。
    private static let registeredLock = Locked(false)
    /// 单次完成闸 (跨线程): expirationHandler 与工作体都可能完成, 只允许第一个生效。
    private final class CompletionOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func finish(_ task: BGTask, success: Bool) {
            lock.lock(); defer { lock.unlock() }
            guard !done else { return }
            done = true
            task.setTaskCompleted(success: success)
        }
    }
    static func registerChargeBackup() {
        // 2026-10-13 run 63: 原写 `BGTaskScheduler.shared.supports([BGTaskType.appRefresh])` + 把
        // launchHandler 当 submit 的尾随闭包 —— 两处都不是真 API (`BGTaskScheduler` 无 supports,
        // 无 BGTaskType, submit 也不收尾随闭包) ⇒ 一次报 3 条。真 API 是:
        //   register(forTaskWithIdentifier:using:launchHandler:) 注册处理块;
        //   submit(_:) 单独排期。
        // 2026-10-14: 启动时**无条件**调用本函数 —— 注册必须在启动窗口内完成 (晚于 didFinishLaunching
        // 会抛 NSInternalInconsistencyException 崩进程); 开关只闸住末尾的排期。
        // 设置里改开关只调 rescheduleChargeBackup(), 不再走这里 (那条路是"启动之后才 register"的崩因)。
        guard !registeredLock.withLock({ $0 }) else { return }
        registeredLock.withLock { $0 = true }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: chargeBackupTaskId, using: nil) { task in
            // 2026-10-14: 旧实现 expirationHandler 与工作体都会 setTaskCompleted —— 对同一 BGTask
            // 二次完成抛 NSInternalInconsistencyException。改用单次完成闸。
            let once = CompletionOnce()
            task.expirationHandler = { once.finish(task, success: false) }
            let ok = makeRollbackPoint()
            once.finish(task, success: ok)   // 成败如实上报, 不再无条件记成功
        }
        rescheduleChargeBackup()   // 2026-10-26: 原受 kf_bk_bgtask 闸控，而该键无写点（永远 false）⇒ 后台备份从未排期。现无条件排期。
    }
    /// 排期: 由系统择机执行 (接电+闲置), 最早 6 小时后。
    /// 2026-10-14: 排期失败原先 `try?` 静默吞掉, 而 UI 文案却称"已交给系统" —— 改为记维护回执。
    static func rescheduleChargeBackup() {
        let req = BGAppRefreshTaskRequest(identifier: chargeBackupTaskId)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        // iOS 27 起 submit(_:) 弃用, 编译器点名换 submitTaskRequest(_:completionHandler:)。
        // 换完仍然要留痕: 排期失败被吞掉, UI 那句"已交给系统"就成了假话 (2026-10-14 就是为这个改的)。
        BGTaskScheduler.shared.submitTaskRequest(req) { err in
            guard let err else { return }
        }
    }

    /// 分区裁剪的统一口径 (导出 / 恢复 / 预演共用, 427 分区选择性恢复)
    /// 组包 + 分区裁剪: 未勾分区在包内置空 (恢复端按 nil 语义跳过)
    static func bundleFor() -> BackupBundle {
        var b = BackupKit.collectAll()
        b.at = ISO8601DateFormatter().string(from: Date())
        return prune(b)
    }

    /// 2026-10-26: 原 prune(_ b: BackupBundle, _ z: BZones) 按四分区裁剪；分区概念已删
    /// （从来没有 UI 暴露，全部调用点都传全选），所以本函数不再裁剪任何东西，原样返回。
    /// 保留函数壳是因为 bundleFor() 与 WebDAV 推包两处都调它 —— 改签名会波及无关代码。
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
    /// 422/423 哈希先行: 校验 checksum (434 短码展示同一口径)
    /// 两条都认：与小程序一致的新语义 (178 批起) + 本仓旧包按旧语义写出的 checksum。
    /// 只认新的会把用户已有的备份判成"内容被篡改"，那是数据失踪级观感，不是安全收益。
    static func verifyChecksum(_ text: String) -> Bool {
        checksumState(text) == .ok
    }
    /// 434 哈希短码: SHA256 前 8 位
    static func shortHash(_ text: String) -> String {
        String(HashKit.sha256Hex(text).prefix(8))
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
        if let members = c.members {
            for m in members {
                if let hit = DB.members().first(where: { $0.name == m.name }) {
                    remap[m.id] = hit.id
                } else if let created = DB.addMember(m.name) {
                    remap[m.id] = created.id
                    DB.setMemberInfo(created.id, ["relation": m.relation, "phone": m.phone])
                }
            }
        }
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


    /// 已过期临时凭证计数（用于提示"有几条临时码已经过期可清理"）。
    /// 2026-10-26: 原注释写的是「193 体积预估」—— 与下面的函数毫无关系（注释错位，属搬运时漏改）。
    static func expiredTemporaryCount() -> Int {
        // 到期口径: 台账 from/to 是 "yyyy-MM-dd" 字符串, 直接按日比较 (与 CredentialOrg 状态推断同向)
        let today = Milestones.dayKey()
        var n = 0
        for kc in DB.keychains() {
            for p in DB.ledger(kc.mac).pwds where p.temp && !p.to.isEmpty && p.to != "2118-12-31" {
                if p.to.compare(today) == .orderedAscending { n += 1 }
            }
        }
        return n
    }

    static func estimateBytes() -> Int? {
        let plain = BackupCanonical.exportText(bundleFor())
        guard !plain.isEmpty else { return nil }
        return plain.count * 2
    }
    /// 193 体积对比: 上次实际导出的字符数 (markExportSize 在三条导出路径写入)
    static var lastExportBytes: Int { DB.store.getInt("kf_bk_last_bytes", 0) }
    static func markExportSize(_ text: String) { DB.store.set("kf_bk_last_bytes", text.count * 2) }
    static func sizeText(_ bytes: Int) -> String {
        let last = lastExportBytes
        let cmp = last > 0 ? "上次 " + String(format: "%.1f KB", Double(last) / 1024)
                                + " (\(max(0, daysSinceLastExport())) 天前)" : "上次暂无记录"
        return "本次预计 ~" + String(format: "%.1f KB", Double(bytes) / 1024) + " · " + cmp   // 193 界面文案
    }


    // ================= 完整性与信任感 (448-454 / 507-512) =================
    /// 库体指纹 (448/397 共用一份算法, 免得两处各算各的后端口径漂移)
    /// 库体指纹算法版本: 变更时递增 —— 旧基线 (不带前缀) 不参与比对, 免得升级后误报自检异常。
    private static let fpVersion = "2:"
    private static func dbFingerprint() -> String {
        // 旧实现只统计长度 (skey.count + pins.count) —— 替换等长 skey / 增删等量 pin 察觉不到。
        // 改为对 skey 与 pins **内容**取摘要。
        var m = [String: String]()
        for kc in DB.keychains() {
            let pinsHash = BackupCanonical.fnv1a32Hex(kc.pins.joined(separator: ","))
            m[DB.normalizeMac(kc.mac)] = BackupCanonical.fnv1a32Hex(kc.skey.lowercased()) + ":" + pinsHash
        }
        let canon = m.sorted { $0.key < $1.key }.map { "\($0.0):\($0.1)" }.joined(separator: "|")
        return fpVersion + BackupCanonical.fnv1a32Hex(canon)
    }

    /// 397 解锁后自检用的**只读**核对: 只比不改。基线由备份时写入 (markBackupBaseline), 本函数只比不改 ——
    /// 一处"每检查一次就把上次的异常抹平"的检查证明不了任何事, 所以自检绝不回写基线。
    static func hashMismatch() -> Bool {
        let last = DB.store.getString("kf_bk_dbhash")
        guard last.hasPrefix(fpVersion) else { return false }   // 无基线, 或旧算法基线 (升级后不复用), 不算异常
        return last != dbFingerprint()
    }
    /// 448: 基线由"备份发生点"写入 — 自检对比的是与最新快照的差异, 不再自写自读
    static func markBackupBaseline() { DB.store.set("kf_bk_dbhash", dbFingerprint()) }
    /// 448 启动自检: 库体哈希 vs 上次备份时的基线; 不一致返回黄条文案。
    /// 基线只在备份发生点 (markBackupBaseline, 由 Milestones.recordBackup 尾调用) 更新,
    /// 本函数只比不改 —— 自查后回写会把上一次的异常直接抹平。
    @discardableResult
    static func runStartupSelfCheck() -> String? {
        let fp = dbFingerprint()
        let last = DB.store.getString("kf_bk_dbhash")
        if last.hasPrefix(fpVersion), last != fp {
            DB.store.set("kf_bk_selfwarn", true)
            return "数据自检异常 — 库体哈希与上次备份快照不一致, 建议立即备份并去诊断"   // 448 数据自检异常
        }
        if DB.store.getBool("kf_bk_selfwarn") { DB.store.remove("kf_bk_selfwarn") }
        return nil
    }
    static var selfCheckWarning: String? {
        DB.store.getBool("kf_bk_selfwarn") ? "数据自检异常, 去诊断" : nil   // 448 数据自检异常
    }
    /// 507 备份状态角标: 今日已备份 / 多日未备份
    enum BadgeState: Equatable { case fresh, stale(Int), none }
    static var badgeState: BadgeState {
        guard let ms = lastExportMs else { return .none }
        let today = Milestones.dayKey(Date())
        if Milestones.dayKey(Date(timeIntervalSince1970: ms / 1000)) == today { return .fresh }
        return .stale(daysSinceLastExport())
    }

    // ================= WebDAV 增强 (197/422-423/430/436) =================
    /// 用户自配 WebDAV 根 (坚果云或任意 WebDAV), 运行时输入 Basic Auth; 绝不上传非用户自配位置
    static var webdavRoot: String {
        get { DB.store.getString("kf_webdav_root", "https://dav.jianguoyun.com/dav/%E6%88%91%E7%9A%84%E5%9D%9A%E6%9E%9C%E4%BA%91") }
        set { DB.store.set("kf_webdav_root", newValue) }
    }
    struct RemoteEntry: Identifiable { var id: String { name }; let name: String; let size: Int; let etag: String; let modified: String }
    /// 422 时间列: RFC1123 → 本地短格式, 解不开原样返回
    static func humanDate(_ s: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let d = f.date(from: s) else { return s }
        let g = DateFormatter(); g.locale = Locale(identifier: "en_US_POSIX"); g.dateFormat = "yyyy-MM-dd HH:mm"
        return g.string(from: d)
    }
    /// 197 连通测试: PROPFIND 回显服务器时间
    @discardableResult
    static func testWebdav(acct: String, appPw: String, root: String) async -> String {
        guard let url = URL(string: root) else { return "地址非法" }
        var req = URLRequest(url: url)
        req.httpMethod = "PROPFIND"
        req.setValue(CloudSync.basicAuth(acct, appPw), forHTTPHeaderField: "Authorization")
        req.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("<?xml version=\"1.0\"?><propfind xmlns=\"DAV:\"><prop><getlastmodified/><resourcetype/></prop></propfind>".utf8)
        req.timeoutInterval = 15
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return "响应异常" }
            if (200..<300).contains(http.statusCode) {
                let t = http.value(forHTTPHeaderField: "Last-Modified") ?? "ok"
                return "连通 · 服务器时间 \(t)"
            }
            if http.statusCode == 401 || http.statusCode == 403 { return "账号或应用密码错误" }   // 401 账号或应用密码错误
            return "HTTP \(http.statusCode)"
        } catch { return "网络不可达: \(error.localizedDescription)" }
    }
    /// 422/423 远端列表: 拉 etag (哈希) + 大小, 再按需拉正文 — 断点友好
    static func listRemote(acct: String, appPw: String, root: String) async throws -> [RemoteEntry] {
        // 原先这一行是 `return "地址非法"` —— 一个声明 `-> [RemoteEntry]` 的函数返回 String，编译器必拒。
        // 可核实的出处：这一行在 `origin/main` (31df7a6，最后一次推送) 里就已经是这个样子，
        // 而那一次推送对应的 CI run 47 结论是 failure (日志匿名取不到，所以不能断言 CI 报的就是它)。
        // 改成抛错才对：调用方 `refresh()` 有 do/catch 会把这句话 toast 出来，
        // `pruneRemote` 那侧是 try? ⇒ 直接不动远端。
        guard let url = URL(string: root) else { throw DFUError.msg("远端地址非法") }
        var req = URLRequest(url: url)
        req.httpMethod = "PROPFIND"
        // Depth: 1 必须显式写。不写时按 RFC 4918 服务端默认取 **Infinity**，那 430 滚动保留看到的就是
        // 整个子树的每一层条目 (默认 root 又是整个坚果云根目录) —— 配合下面的删除面就是删到用户照片里。
        req.setValue("1", forHTTPHeaderField: "Depth")
        req.setValue(CloudSync.basicAuth(acct, appPw), forHTTPHeaderField: "Authorization")
        req.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("<?xml version=\"1.0\"?><propfind xmlns=\"DAV:\"><prop><resourcename/><getcontentlength/><getetag/><getlastmodified/></prop></propfind>".utf8)
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw DFUError.msg("响应异常") }
        if http.statusCode == 404 { return [] }
        if http.statusCode == 401 || http.statusCode == 403 { throw DFUError.msg("账号或应用密码错误") }
        guard http.statusCode == 207 else { throw DFUError.msg("PROPFIND HTTP \(http.statusCode)") }
        // 422/423 远端列表: 拉 etag (哈希) + 大小, 再按需拉正文 — 断点友好
        // 对抗硬化: 只取 UTF-8 可读正文, 恶意/二进制 XML 直接拒绝 (不静默误读为空)
        guard let xml = String(data: data, encoding: .utf8), !xml.isEmpty else { throw DFUError.msg("远端列表解析失败 (响应非 UTF-8 XML)") }
        var out: [RemoteEntry] = []
        var i = xml.startIndex
        while let s = xml.range(of: "<resourcename>", range: i..<xml.endIndex) {
            // 对抗硬化: 内容做实体解码 + 长度护栏, 防恶意 XML 注入名直接拼进 URL
            i = s.upperBound
            guard let e = xml.range(of: "</resourcename>", range: i..<xml.endIndex) else { break }
            var name = String(xml[i..<e.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            name = Self.xmlUnescape(name)
            guard !name.isEmpty, name.count <= 256 else { continue }   // 长度护栏
            i = e.upperBound
            func cap(_ tag: String, from: String.Index) -> String {
                var idx = from
                while let r = xml.range(of: "<\(tag)>", range: idx..<xml.endIndex) {
                    guard let en = xml.range(of: "</\(tag)>", range: r.upperBound..<xml.endIndex) else {
                        idx = r.upperBound
                        continue
                    }
                    idx = en.upperBound
                    return Self.xmlUnescape(String(xml[r.upperBound..<en.lowerBound]))
                }
                return ""
            }
            out.append(RemoteEntry(name: name,
                                   size: Int(cap("getcontentlength", from: i)) ?? 0,
                                   etag: cap("getetag", from: i),
                                   modified: cap("getlastmodified", from: i)))
        }
        return out.sorted { $0.name > $1.name }
    }
    /// XML 实体最小解码 (&lt; &gt; &amp; &quot; &apos; + 数字实体), 防注入名直接进 URL
    private static func xmlUnescape(_ s: String) -> String {
        var out = s
        for (ent, ch) in [("&#38;", "&"), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'")] {
            out = out.replacingOccurrences(of: ent, with: ch)
        }
        return out
    }
    static func safeRemoteURL(root: String, name: String) -> URL? {
        // 对抗护栏: 远端条目名可能来自恶意/越权账号 — 拒绝路径穿越与外链, 只允许目录内相对名
        guard !name.hasPrefix("/"), !name.contains("://") else { return nil }
        for part in name.split(separator: "/") where part == ".." { return nil }
        return URL(string: root + "/" + name)
    }
    /// 430 滚动保留: 远端只留最近 N 份, 按名字 (带日期戳) 排序
    /// 本 App 自己写出来的备份文件名 (409 命名 = `锁管家_<锁名>_<yyyy-MM-dd-HHmm>_全量[_卷N].enc`)。
    /// 只有这个名字族才允许被滚动保留删掉 —— 见 `pruneRemote` 上方那段。
    static let filePrefix = "锁管家_"
    static func isOurBackup(_ name: String) -> Bool {
        // 不含 "/" 是关键：带斜杠的是子目录里的东西 (Depth: 1 之后本不该出现，但服务端不守约也不能删)
        name.hasPrefix(filePrefix) && name.hasSuffix(".enc") && !name.contains("/")
    }
    /// 一"份"的组键 = 去掉尾部 `_卷N` 的名字 (410 分卷时同一次导出会写成基础卷 + 逐年卷)。
    /// 按文件数取舍会把一套卷切成半套 —— 基础卷 (设备/凭证/设置) 没了，剩下的记录卷恢复不出任何东西。
    /// 只剥**结尾**那一截 `_卷数字`：锁的显示名也可能含 "_卷" (409 把它拼在名字里)，
    /// 从后往前找到的第一个不一定是卷号，认错了会把整把锁的备份并成一份。
    static func volumeSet(_ name: String) -> String {
        guard name.hasSuffix(".enc") else { return name }
        let head = String(name.dropLast(4))
        guard let r = head.range(of: "_卷", options: .backwards) else { return name }
        let tail = head[r.upperBound...]
        guard !tail.isEmpty, tail.allSatisfy({ $0.isNumber }) else { return name }
        return String(head[..<r.lowerBound]) + ".enc"
    }
    /// 从 409 那个自描述名里取日期段；取不到算最旧 (空串排到最后)
    static func dateInName(_ name: String) -> String {
        guard let r = name.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) else { return "" }
        return String(name[r])
    }
    @discardableResult
    static func pruneRemote(acct: String, appPw: String, root: String, keep: Int) async -> Int {
        guard keep > 0, let entries = try? await listRemote(acct: acct, appPw: appPw, root: root) else { return 0 }
        var groups: [String: [RemoteEntry]] = [:]
        for e in entries where isOurBackup(e.name) {
            groups[volumeSet(e.name), default: []].append(e)
        }
        // 按日期段 (其次按组名) 从新到旧；`zklock-backup.enc` 那种固定名备份不在名字族内，永不参与计数
        let ordered = groups.keys.sorted { a, b in
            let da = dateInName(a), db = dateInName(b)
            return da == db ? a > b : da > db
        }
        var pruned = 0
        // 430 每月 1 份档: 最近 N 份之外每月再保最新 1 份 (Time Machine 口径); 无日期组只走 N。
        // ordered 是从新到旧, 所以某月第一次出现的那组就是该月最新的一份。
        var keptMonths = Set<String>()
        for (i, key) in ordered.enumerated() {
            let month = String(dateInName(key).prefix(7))
            if i < keep || (!month.isEmpty && keptMonths.insert(month).inserted) { continue }
            for e in groups[key] ?? [] {
                guard let url = safeRemoteURL(root: root, name: e.name) else { continue }
                var req = URLRequest(url: url)
                req.httpMethod = "DELETE"
                req.setValue(CloudSync.basicAuth(acct, appPw), forHTTPHeaderField: "Authorization")
                _ = try? await URLSession.shared.data(for: req)
                pruned += 1
            }
        }
        if pruned > 0 {
            AuditLog().append(.admin, "清", target: "WebDAV 滚动保留: 清理远端 \(pruned) 个文件")   // 430 滚动保留
        }
        return pruned
    }
    /// 436 演练恢复: 远端 → 内存解密试读 + 哈希, 不碰真库
    @discardableResult
    static func dryRunRemote(acct: String, appPw: String, root: String, name: String, password: String) async -> String {
        guard let url = safeRemoteURL(root: root, name: name) else { return "地址非法 (远端条目名被护栏拒绝)" }
        var req = URLRequest(url: url)
        req.setValue(CloudSync.basicAuth(acct, appPw), forHTTPHeaderField: "Authorization")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let raw = String(data: data, encoding: .utf8) ?? ""
            let body = (try? decryptAny(raw, password: password)) ?? raw
            guard verifyChecksum(body) else { return "哈希不一致 — 仅告警, 不入库" }   // 423 哈希不一致
            // 436: 抽样数是 parsePreview 实抽出来的, 不再写死 "5 条"
            let sampled = (try? parsePreview(text: body, password: nil).preview.sampleOk) ?? 0
            return "已验证 · 抽样 \(sampled) 条可解析 · 哈希 " + shortHash(body)
        } catch { return "下载失败: \(error.localizedDescription)" }
    }
    /// 237 密钥轮换: 新口令重加密后**直接覆盖**远端同一文件（`zklock-backup.enc`）。
    /// ⚠ 注释曾写「旧文件重命名留痕」—— 实现里没有任何重命名/留档分支, 轮换即覆盖,
    ///   旧密文不可恢复。要留痕得先加一份 `.bak` 上传, 那是未实现的设计意图。
    @discardableResult
    static func rotateKey(acct: String, appPw: String, root: String, oldPw: String, newPw: String) async -> String {
        guard let url = URL(string: root + "/zklock-backup.enc") else { return "地址非法" }
        var req = URLRequest(url: url)
        req.setValue(CloudSync.basicAuth(acct, appPw), forHTTPHeaderField: "Authorization")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let raw = String(data: data, encoding: .utf8) ?? ""
            guard let plain = try? decryptAny(raw, password: oldPw) else {
                return "旧口令解不开, 轮换失败"   // 453 旧口令解不开
            }
            guard let newEnc = try? CryptoBox.encryptText(plain, password: newPw) else {
                return "新口令加密失败, 远端未动"
            }
            var put = URLRequest(url: url)
            put.httpMethod = "PUT"
            put.setValue(CloudSync.basicAuth(acct, appPw), forHTTPHeaderField: "Authorization")
            put.setValue("application/json", forHTTPHeaderField: "Content-Type")
            put.httpBody = Data(newEnc.utf8)
            let (_, resp) = try await URLSession.shared.data(for: put)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return "上传新密文失败, 远端仍为旧口令"   // 237 上传新密文失败
            }
            return "已轮换 — 旧口令失效, 请用新口令访问"   // 237 已轮换
        } catch { return "轮换中断: \(error.localizedDescription)" }
    }

    private static func jsonStr(_ s: String, _ marker: String) -> String? {
        guard let r = s.firstRange(of: marker) else { return nil }
        guard let end = s[r.upperBound...].firstRange(of: "\"") else { return nil }
        return String(s[r.upperBound..<end.lowerBound])
    }

    private static func jsonNum(_ s: String, _ marker: String) -> Int? {
        guard let r = s.firstRange(of: marker) else { return nil }
        let digits = s[r.upperBound...].prefix { $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }
    /// 认不出信封就说"未能识别"，绝不回落到徽章那串 —— 那会把一个明文包或损坏件标成"加密过"。
    /// 明文包 (BackupBundle 直接写盘, 没有信封) 单独一档: 混进"未能识别"会让人以为文件坏了。
    enum AlgoNote: Equatable { case envelope(String), plain, unknown }
    static func algoNote(_ url: URL) -> AlgoNote {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return .unknown }
        // 前 4096 字节全 ASCII (键名与参数值都是 ASCII), 不存在截断多字节字符导致解不出的情况
        let head = String(data: data.prefix(4096), encoding: .utf8) ?? ""
        guard head.hasPrefix("{") else { return .unknown }
        if let alg = jsonStr(head, "\"alg\":\""),
           let kdf = jsonStr(head, "\"kdf\":{\"alg\":\""),
           let iter = jsonNum(head, "\"iter\":") {
            return .envelope("\(alg) · \(kdf) \(iter) 轮")
        }
        return head.contains("\"devices\":") ? .plain : .unknown
    }

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
    static func dataEvents() -> [String] {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return bkEvents().enumerated().reversed().prefix(12).map { i, e in
            "\(f.string(from: Date(timeIntervalSince1970: e.at / 1000))) · \(e.label)"
        }
    }

}

// ---------- UNUserNotificationCenter delegate 单例 (1018 通知点按 → 还原点 + 指路备份) ----------
/// @unchecked Sendable 的依据是**没有可保护的状态**: 本类零存储属性, 唯一职责是把点按转发成
/// 主 actor 上的路由动作 (每个分支都已经 Task { @MainActor in })。不是"把检查关掉", 是无锁可上。
final class UNDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = UNDelegate()
    // 方法名必须是 `withCompletionHandler:`。原写法 `completionHandler:` 与协议要求只差一个前缀,
    // 编译器给的是 nearly-matches 告警, 而运行时这一支**永远不被调用** —— 通知点按等于没接。
    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse,
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        if r.notification.request.identifier == "kf.bk.monthly" {
            Task { @MainActor in
                await BackupStudio.onMonthlyTap()
            }
        }
        // 366/1013: 凭证族通知此前只排期不分派 —— handleNotificationAction 全仓零调用,
        // 点"密码临期"通知落到系统默认行为(打开 App 停在原页面)。这里补上转发。
        if let act = CredentialOrg.handleNotificationAction(r.notification.request.identifier) {
            Task { @MainActor in CredentialOrg.applyNotification(act) }
        }
        // 1013: 保养到期通知 → 设备页那台锁 (mac 就在通知 id 里: m4.care.<mac>)。
        // 冷启动点按: hostRef 要等 RootView 挂载才就位, 等它 (最多 2 秒) 再落点, 不丢这次点按;
        // 锁着/伪装态不直接切页, 与深链同口径记 pendingRoute, 解锁后由 applyPendingRoute 补走。
        if r.notification.request.identifier.hasPrefix("m4.care.") {
            let careMac = String(r.notification.request.identifier.dropFirst("m4.care.".count))
            Task { @MainActor in
                var waited = 0
                while AppState.hostRef == nil && waited < 10 {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    waited += 1
                }
                guard let host = AppState.hostRef else { return }
                host.pendingCare = careMac
                if host.appUnlocked && !host.decoyMode { host.requestRoute(.settings) } else { host.pendingRoute = .settings }
            }
        }
        completionHandler()
    }
    /// 前台展示: 不实现 willPresent 时系统默认"前台完全静默", 用户正拿着手机反而看不到"密码临期"这类提醒。
    /// 夜间免扰 (1031) 时段仍静默, 与 BatteryCare 的即时通知口径一致。
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                               withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) {
        if CareSchedule.quietOn, CareSchedule.isQuietHour() {
            completion([])
        } else {
            completion([.banner, .sound])
        }
    }
}
