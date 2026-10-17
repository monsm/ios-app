import os
// 包8 备份工作室服务层 — 备份·恢复·换机迁移
// 覆盖 idea: 181/193/197/198/237/407-413/417-427/429-431/434-436/438-446/448-450/453/454/456/477/507-509/511/512/1018/1048
// 纪律: 备份文件只去用户自配 WebDAV (Basic Auth 运行时输入), 口令不出本机内存;
//       加密语义 (CryptoBox AES-128-CBC+HMAC/PBKDF2, ZOTP 相关) 不动, 本层只做外围策略。
import Foundation
import os
import UIKit
import CoreImage.CIFilterBuiltins
import BackgroundTasks
import UserNotifications

// ---------- 分区模型 (407: 设备/凭证/记录/设置 四分区 + 181 OTP 开关) ----------
struct BZones: Codable, Equatable {
    var devices: Bool = true      // 门锁钥匙串 + BLE 直连参数 (441 迁移逐把确认)
    var credentials: Bool = true  // 台账 (密码/指纹)
    var records: Bool = true      // 锁端日志缓存 + 全局事件
    var settings: Bool = true     // 成员 / 应用锁摘要 / dongle / gateway
}

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

    /// 409 自描述文件名: 锁管家_主锁名_2026-10-08-1830_全量.enc (410 分卷时尾部加 _卷N)
    /// 194 自动命名 = 这一处 (备份页文件行显示的就是它, 用户不用自己起名): 日期时分在名字里, 不在弹窗里。
    static func fileName(vol: Int = 0) -> String {
        let kc = DB.keychains().first
        let name = (kc.map { LockArchive.displayName($0) } ?? "本机").replacingOccurrences(of: "/", with: "-")
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        f.locale = Locale(identifier: "en_US_POSIX")
        let stamp = f.string(from: Date())
        return Self.filePrefix + "\(name)_\(stamp)_全量" + (vol > 0 ? "_卷\(vol)" : "") + ".enc"
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
    /// 509 双向天数行: 上次导入距今
    static func daysSinceLastImport() -> Int {
        guard let ms = DB.store.get(Double.self, "kf_bk_last_import") else { return -1 }
        return Int(Date().timeIntervalSince1970 / 86400) - Int(ms / 1000 / 86400)
    }
    static func markImported() { DB.store.set("kf_bk_last_import", Date().timeIntervalSince1970 * 1000) }

    /// 198: 档位落地为本地通知提醒 (不做后台静默写); manual 不排期, 换档即重排
    static func scheduleCadenceReminder() async {
        let id = "kf.bk.cadence"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        guard cadence != "manual", await CareSchedule.requestAuth() else { return }
        let c = UNMutableNotificationContent()
        c.title = "该备份了"   // 198 该备份了
        c.body = "按「" + (cadence == "weekly" ? "每周" : "每月") + "」节奏, 做一份备份并演练验证。"
        var comps = DateComponents(); comps.hour = 9
        if cadence == "weekly" { comps.weekday = 2 } else { comps.day = monthlyDay > 0 ? monthlyDay : 1 }
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
        UNUserNotificationCenter.current().delegate = UNDelegate.shared
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
        _ = Milestones.recordBackup()
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
        "kf_bk_note", "kf_bk_pin", "kf_bk_pin_seen",                 // 433 备注 / 437 复核钉
        // 2026-10-13 对抗式排查: TOTP/静态口令族漏收。三种导入模式都会写这四个族
        //   · BackupKit.restoreAll :375-376 → otpStatus_ / otpIdx_
        //   · BackupStudioKit :740/:765 → kf_cotp_t_ (TOTP 种子) 与 kf_cotp_s_ (静态口令)
        // 而回滚快照只覆盖上面列出的族 ⇒ 导错备份再点「撤销恢复」, 成员/凭证/备注都回去了,
        // **TOTP 种子与静态口令仍停在错包的值** (既是数据错, 也是 2FA 密钥残留, 撤销永远不完整)。
        // 判据①"恢复流程确实会改写它们"②"里面是用户自己攒的内容" 对这四族完全成立。
        "otpStatus_", "otpIdx_", "kf_cotp_t_", "kf_cotp_s_",
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
        DB.store.set("kf_bk_rollback", rollURL.path)
        return true
    }
    static var canUndoLastRestore: Bool {
        // Store.getString 返回非可选 String: 旧写法 guard let 绑定非可选值 → 编译不过
        let path = DB.store.getString("kf_bk_rollback")
        guard !path.isEmpty,
              let m = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        else { return false }
        return Date().timeIntervalSince(m) < 86400
    }
    @discardableResult
    static func undoLastRestore() -> Bool {
        let path = DB.store.getString("kf_bk_rollback")
        guard restoreRollbackSnapshot(path) else { return false }
        DB.store.remove("kf_bk_rollback")
        _ = Milestones.recordBackup()
        return true
    }
    /// 421/445 快照还原实体: 由 undoLastRestore 与迁移事务回滚 (rollbackMigrationTxn) 共用。
    /// 只写回快照里已有的键, 不碰锁端协议; 快照之后用户新攒的键不会被删 (见下方 extras 段)。
    static func restoreRollbackSnapshot(_ path: String) -> Bool {
        guard !path.isEmpty,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let snap = try? JSONDecoder().decode(RollbackBundle.self, from: data) else { return false }
        // 421: 逐分区还原 — 只写回本机键位, 不碰锁端协议
        for s in snap.keychains {
            if let d = s.data(using: .utf8), let kc = try? JSONDecoder().decode(Keychain.self, from: d) {
                DB.saveKeychain(kc)
            }
        }
        // 2026-10-13 run 63: snap.ledgers 的类型是 [[String: String]] (每锁一个单键字典, 见上方构造),
        // 原写 `for (mac, s) in snap.ledgers` 把元素当元组 ⇒ "tuple pattern cannot match values of
        // non-tuple type '[String : String]'" (并连带 s.data(using:) 报 'utf8' 推不出)。逐层展开。
        for ledger in snap.ledgers {
            for (mac, s) in ledger {
                if let d = s.data(using: .utf8), let l = try? JSONDecoder().decode(Ledger.self, from: d) {
                    DB.saveLedger(mac, l)
                }
            }
        }
        for s in snap.dongles {
            if let d = s.data(using: .utf8), let dl = try? JSONDecoder().decode(Dongle.self, from: d) {
                DB.saveDongle(dl)
            }
        }
        for s in snap.gateways {
            if let d = s.data(using: .utf8), let gw = try? JSONDecoder().decode(Gateway.self, from: d) {
                DB.saveGateway(gw)
            }
        }
        if let s = snap.passcode, let d = s.data(using: .utf8), let pc = try? JSONDecoder().decode([String: String].self, from: d) {
            DB.store.set("kf_passcode", pc)
        }
        for s in snap.members {
            if let d = s.data(using: .utf8), let m = try? JSONDecoder().decode(Member.self, from: d) {
                let existing = DB.members().first(where: { $0.name == m.name })
                if existing != nil {
                    DB.setMemberInfo(existing!.id, ["relation": m.relation, "phone": m.phone, "color": m.color])
                } else {
                    let created = DB.addMember(m.name)
                    if let c = created {
                        DB.setMemberInfo(c.id, ["relation": m.relation, "phone": m.phone, "color": m.color])
                    }
                }
            }
        }
        // 421: 分区之外的内容族原样写回。**只覆盖快照里有的键** ——
        // 快照之后用户新攒的键 (刚钉的 437 复核日、新写的 186 备注) 不在快照里, 删除它们就是把"回滚"变成"抹掉更新的数据"。
        for (k, b64) in snap.extras ?? [:] {
            if let d = Data(base64Encoded: b64) { DB.store.setRawData(k, d) }
        }
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
    private static let registeredLock = OSAllocatedLock(false)
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
        guard !registeredLock.withLock({ $0 }) else { if DB.store.getBool("kf_bk_bgtask") { rescheduleChargeBackup() }; return }
        registeredLock.withLock { $0 = true }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: chargeBackupTaskId, using: nil) { task in
            // 2026-10-14: 旧实现 expirationHandler 与工作体都会 setTaskCompleted —— 对同一 BGTask
            // 二次完成抛 NSInternalInconsistencyException。改用单次完成闸。
            let once = CompletionOnce()
            task.expirationHandler = { once.finish(task, success: false) }
            let ok = makeRollbackPoint()
            if ok { MaintenanceLog.record("充电备份快照") }   // 387: 记账才能进设备页"上次会话本机完成 N 项维护"回执
            once.finish(task, success: ok)   // 成败如实上报, 不再无条件记成功
        }
        if DB.store.getBool("kf_bk_bgtask") { rescheduleChargeBackup() }
    }
    /// 排期: 由系统择机执行 (接电+闲置), 最早 6 小时后。
    /// 2026-10-14: 排期失败原先 `try?` 静默吞掉, 而 UI 文案却称"已交给系统" —— 改为记维护回执。
    static func rescheduleChargeBackup() {
        let req = BGAppRefreshTaskRequest(identifier: chargeBackupTaskId)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        do { try BGTaskScheduler.shared.submit(req) }
        catch { MaintenanceLog.record("后台备份排期失败: \((error as NSError).localizedDescription)") }
    }
    /// UI 文案: 只承诺"注册给系统, 由系统择机执行"
    static var chargeBackupNote: String {
        "已把后台备份任务交给系统, 由系统在你接电且闲置时择机执行 — 具体时刻由系统决定, 不承诺接电即备。"
    }

    // ================= 导出 (407-413 / 181) =================
    /// 分区条数 (向导实时显示, 407)
    static func zoneCounts() -> [String: Int] {
        var out: [String: Int] = [:]
        out["设备"] = DB.keychains().count
        var pw = 0, fp = 0
        for kc in DB.keychains() {
            let l = DB.ledger(kc.mac)
            pw += l.pwds.count; fp += l.fps.count
        }
        out["凭证"] = pw + fp
        // 2026-10-15 走查: 原先这里报 `DB.keychains().count` 并把界面文案写成"锁端日志缓存 (按锁约) 份缓存",
        // 两头都不对 —— 锁端日志缓存 (`kf_logcache_`) **从不进包** (BackupKit 全文零命中)，而这一档真正裁的是
        // `globals.trace` 那**一份**本机记录写入轨迹 (见下方 `if !z.records` 那两条)。勾掉它不会让日志消失,
        // 勾上它也恢复不出锁端日志 —— 报数与单位都说成实际那一件事。
        out["记录"] = DB.get(BackupBundle.Globals.TraceRec.self, "kf_trace_persist_v1") == nil ? 0 : 1
        out["设置"] = DB.members().count + DB.dongles().count + DB.gateways().count
        return out
    }
    /// 181 OTP 备份开关: 默认排除 (独立口令组密钥不进备份), 显式勾选才追加
    static func otpIncluded() -> Bool { DB.store.getBool("kf_bk_otp", false) }

    /// 组包 + 分区裁剪: 未勾分区在包内置空 (恢复端按 nil 语义跳过)
    static func bundleFor(_ zones: BZones) -> BackupBundle {
        var b = BackupKit.collectAll()
        b.at = ISO8601DateFormatter().string(from: Date())
        return prune(b, zones)
    }
    /// 分区裁剪的统一口径 (导出 / 恢复 / 预演共用, 427 分区选择性恢复)
    static func prune(_ b: BackupBundle, _ z: BZones) -> BackupBundle {
        var c = b
        if !z.devices { c.devices = [] }
        if !z.credentials { for i in c.devices.indices { c.devices[i].ledger = nil } }
        if !z.records {
            c.globals = c.globals.map { var g = $0; g.trace = nil; return g }
        }
        if !z.settings {
            c.members = nil
            c.globals = c.globals.map {
                var g = $0
                g.keychainDongles = nil
                g.gatewayList = nil
                g.passcode = nil
                g.otpKeys = nil            // 181 属"设置"分区: 不勾设置就不能带 2FA 种子
                g.appearance = nil         // 894 同属"设置"分区: 不勾设置就不带外观 (外观是偏好不是内容)
                g.trace = z.records ? g.trace : nil
                return g
            }
            if let g = c.globals, g.keychainDongles == nil, g.gatewayList == nil,
               g.passcode == nil, g.otpKeys == nil, g.appearance == nil, g.trace == nil {
                c.globals = nil
            }
        }
        return c
    }
    /// 导出文本 (409): 可选口令加密 (408 两遍输入在 UI 层); 返回 canonical 文本或加密信封
    static func exportText(zones: BZones, encrypt: String?) -> String? {
        var text = BackupCanonical.exportText(bundleFor(zones))
        if text.isEmpty { return nil }
        if let pw = encrypt, !pw.isEmpty {
            text = (try? CryptoBox.encryptText(text, password: pw)) ?? ""
        }
        return text.isEmpty ? nil : text
    }
    /// 写本地文件 (413 分享用), 返回 URL。
    /// 181 的 OTP 密钥段已**收进包体** (见 BackupKit.collectAll 的 globals.otpKeys): 随整包加密、
    /// 进 canonical 校验和、且 restore 能读回来。旧实现在密文信封后追加 `//OTPK` 段 —— 那既让
    /// ".enc 文件含明文 2FA 种子"成为可能, 又全库没有任何导入方读它, 是只写不读的旁路。
    @discardableResult
    static func writeLocal(_ text: String, name: String) -> URL? {
        // `name` 是**完整文件名**：409 的 `fileName()` 本身就以 ".enc" 结尾，这里原先又拼了一次，
        // 于是主路径导出的文件一直叫 `锁管家_主锁_2026-10-10_全量.enc.enc`
        // (413 那句"已写入 …"显示的就是它)。后缀判据 `hasSuffix(".enc")` 看不出来，所以一直没暴露。
        let url = dir.appendingPathComponent(name)
        guard (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil else { return nil }
        _ = Milestones.recordBackup()
        return url
    }

    // ---------- 411 二维码搬运: CIQRCodeGenerator 自绘, 纯本地 ----------
    static func qrImage(_ payload: String, scale: CGFloat = 6) -> UIImage? {
        guard let data = payload.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        guard let out = filter.outputImage else { return nil }
        let scaled = out.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
    /// 411: 仅凭证的小备份 → QR 载荷 (明文 canonical, 接收方 App 扫码导入; 超容量则失败)
    static func credentialQRPayload() -> String? {
        var b = BackupKit.collectAll()
        for i in b.devices.indices {
            b.devices[i].meta = nil          // 只带密钥与台账, 不带锁端运行参数
        }
        b.globals = nil
        // 2026-10-13 run 63: 原写 `b.members = b.members` (自赋值, 编译器报 "assigning a property to
        // itself")。语义上就是"members 原样保留" —— 凭证的 owner 归属要用它, 不能像 globals 那样清掉。
        // 删掉这行空操作, 用注释说清意图。
        let t = BackupCanonical.exportText(b)
        guard !t.isEmpty, t.count < 2000 else { return nil }
        return t
    }

    // ---------- 412/431 导出前体检 + 清理联动 ----------
    struct HealthCheck: Identifiable { var id: String { label + text }; let label: String; let text: String }
    static func preExportHealth() -> [HealthCheck] {
        var rows: [HealthCheck] = []
        let expired = expiredTemporaryCount()
        if expired > 0 {
            rows.append(.init(label: "过期临时码",
                              text: "\(expired) 条已过时效仍占台账, 可勾「先清理」减少条数"))   // 431 条已过时效仍占台账
        }
        let noOwner = DB.keychains().reduce(0) { acc, kc in
            let l = DB.ledger(kc.mac)
            return acc + l.pwds.filter { $0.owner == nil }.count + l.fps.filter { $0.owner == nil }.count
        }
        if noOwner > 0 {
            rows.append(.init(label: "无归属",
                              text: "\(noOwner) 条凭证未指定成员, 恢复后仍需认领"))   // 412 条凭证未指定成员
        }
        if daysSinceLastExport() >= 14 {
            rows.append(.init(label: "数据陈旧",
                              text: "距上次备份已 \(daysSinceLastExport()) 天, 本次建议全量并演练验证"))   // 429 距上次备份已
        } else if lastExportMs == nil {
            rows.append(.init(label: "首次备份",
                              text: "这是第一份备份 — 建议同时开 WebDAV 通道做异地冗余"))
        }
        return rows
    }
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
    /// 431 清理联动: 移除过期临时码 (本地台账; 锁端删除交给既有 0A/0B/15 队列), 返回条数
    @discardableResult
    static func cleanExpired() -> Int {
        var n = 0
        for kc in DB.keychains() {
            let mac = kc.mac
            var l = DB.ledger(mac)
            let before = l.pwds.count
            l.pwds = l.pwds.filter { p in
                if p.temp, !p.to.isEmpty, p.to != "2118-12-31", p.to.compare(Milestones.dayKey()) == .orderedAscending {
                    CredentialOrg.snapshotBeforeDelete(mac, pwd: p, fp: nil)
                    n += 1
                    return false
                }
                return true
            }
            DB.saveLedger(mac, l)
            _ = before
        }
        return n
    }

    // ---------- 410 按年分卷: 记录区超阈值时按年拆卷, 各卷可独立恢复 ----------
    struct Volume: Identifiable { var id: Int { index }; let index: Int; let label: String; let text: String }
    static let volumeThreshold = 400   // 记录条数阈值
    /// 返回 nil = 记录不足不需分卷; 否则 vol0 = 基础卷 (无 trace), vol1..n = 逐年 trace
    static func volumes(zones: BZones, encrypt: String?) -> [Volume]? {
        var b = bundleFor(zones)
        let tr = b.globals?.trace?.lines ?? []
        guard tr.count >= volumeThreshold else { return nil }
        var perYear = [String: [String]]()
        for ln in tr {
            let y = String(ln.prefix(4))
            if Int(y) != nil { perYear[y, default: []].append(ln) }
        }
        var out: [Volume] = []
        var head = b
        head.globals = head.globals.map {
            var g = $0; g.trace = nil; return g
        }
        var headText = BackupCanonical.exportText(head)
        if let pw = encrypt { headText = (try? CryptoBox.encryptText(headText, password: pw)) ?? "" }
        out.append(Volume(index: 0, label: "基础卷 · 设备/凭证/设置", text: headText))
        for (y, lines) in perYear.sorted(by: { $0.key > $1.key }) {
            var v = b
            v.globals = v.globals.map {
                var g = $0
                g.trace = .init(savedAt: b.globals?.trace?.savedAt, count: lines.count,
                                chars: lines.count * 60, lines: lines)
                g.keychainDongles = nil
                g.gatewayList = nil
                return g
            }
            var t = BackupCanonical.exportText(v)
            if let pw = encrypt { t = (try? CryptoBox.encryptText(t, password: pw)) ?? "" }
            out.append(Volume(index: out.count, label: "记录卷 · \(y) 年 (\(lines.count) 条)", text: t))
        }
        return out
    }

    // ================= 恢复 (417-427 / 449-450 / 456) =================
    enum MergeStrategy: String, CaseIterable { case overwrite = "覆盖", merge = "合并", missing = "仅补缺失" }

    /// 453 失败分层第三层: 内容哈希。absent (旧包无字段/人工编辑件) 与 mismatch (内容被改过) 必须分开
    enum ChecksumState: Equatable { case ok, mismatch, absent }

    struct Preview: Equatable {
        var source: String        // 477 来源信息: 导出时间 + 原设备
        var schema: Int
        var zones: [String]
        var macs: [String]
        var pwdCount: Int
        var fpCount: Int
        var memberCount: Int
        var sampleOk: Int
        var previewTrace: [String]?
        var checksum: ChecksumState = .absent   // 453 哈希层: 解析时算一次, 预览卡直接显示
    }
    /// 453 哈希层判定: 与 verifyChecksum 共用一套算法 (新语义 + 旧语义两条都认)
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
        var zones: [String] = []
        if !m.devices.isEmpty { zones.append("设备 \(m.devices.count)") }
        var p = 0, f = 0
        for d in m.devices { p += d.ledger?.pwds.count ?? 0; f += d.ledger?.fps.count ?? 0 }
        if p + f > 0 { zones.append("凭证 \(p + f)") }
        if let ms = m.members, !ms.isEmpty { zones.append("成员 \(ms.count)") }
        if m.globals?.trace?.lines?.isEmpty == false { zones.append("记录") }
        let sample = (m.globals?.trace?.lines ?? []).shuffled().prefix(5).count
        let fallback = Keychain(mac: m.currentMac, skey: "")
        let sourceName = m.currentMac.isEmpty ? "" : LockArchive.displayName(DB.keychain(m.currentMac) ?? fallback)
        let pv = Preview(source: "备份时间 \(m.at)" + (sourceName.isEmpty ? "" : " · 来源 \(sourceName)"),
                         schema: m.schema,
                         zones: zones,
                         macs: m.devices.map { $0.mac },
                         pwdCount: p, fpCount: f,
                         memberCount: m.members?.count ?? 0,
                         sampleOk: sample,
                         previewTrace: Array((m.globals?.trace?.lines ?? []).prefix(5)),
                         checksum: ck)
        return (pv, m)
    }
    /// 424 升级链预览: 逐级步骤列举 (执行侧 upgradeChain 就按这个顺序跑)
    struct UpgradeStep: Identifiable {
        var id: Int { to }
        let from: Int
        let to: Int
        let note: String
    }
    static func upgradeSteps(from schema: Int) -> [UpgradeStep] {
        var out: [UpgradeStep] = []
        if schema < 2 { out.append(UpgradeStep(from: 1, to: 2, note: "初始化成员数组")) }
        if schema < 3 { out.append(UpgradeStep(from: 2, to: 3, note: "设备 MAC 规范化")) }
        if schema < 4 { out.append(UpgradeStep(from: 3, to: 4, note: "记录区键位兼容")) }
        if schema < 5 { out.append(UpgradeStep(from: 4, to: 5, note: "OTP 状态与序号拆为独立键位")) }
        return out
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
    static func restore(_ bundle: BackupBundle, strategy: MergeStrategy, zones: BZones,
                        lockActs: [String: String] = [:],
                        conflictTakeBackup: Set<String> = [],
                        makeSnapshot: Bool = true) -> (imported: Int, overwritten: Int, skipped: Int) {
        var b = bundle
        b.currentMac = ""   // 首验清 currentMac, 避免指向另一台设备的锁
        let c = prune(b, zones)
        // 421 恢复回滚点: 执行前自动全库快照
        if makeSnapshot { _ = makeRollbackPoint() }
        switch strategy {
        case .overwrite:
            // 包6 ⚠488 备案复活点: 全量恢复前打自动还原点 (非按凭证, 用整库回滚点语义; 快照走 421 rollback)
            // 419 冲突 = 同 ID 凭证两边都有: UI 层预列出逐条裁决, 此处置 0 跳过
            let r = BackupKit.restoreAll(c)
            return (r.imported, r.overwritten, 0)
        case .merge:
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
                if let otps = g.otpKeys, !otps.isEmpty {
                    // 与 BackupKit.restoreAll 同口径: 只允许本包内锁的 totp/static 键进库
                    var allowed = Set<String>()
                    for d in c.devices {
                        for m in [d.mac, DB.normalizeMac(d.mac)] {
                            allowed.insert(CredentialOrg.totpKey(m))
                            allowed.insert(CredentialOrg.staticKey(m))
                        }
                    }
                    for (k, v) in otps where allowed.contains(k) && !v.isEmpty { DB.store.set(k, v) }
                }
                if let tr = g.trace, let lines = tr.lines, !lines.isEmpty {
                    DB.store.set("kf_trace_persist_v1", [
                        "savedAt": tr.savedAt ?? 0, "count": lines.count,
                        "chars": tr.chars ?? 0, "lines": lines,
                    ])
                }
            }
            _ = markImported()
            return (mimp, mover, mskip)
        case .missing:
            // 仅补缺失: 跳过已存在的锁, 只写新机没有的
            var imp = 0, skipped = 0
            for d in c.devices {
                guard HexKit.bytes(d.mac).count == 6, !d.kc.skey.isEmpty else { continue }
                let mac = DB.normalizeMac(d.mac)
                guard DB.keychain(mac) == nil else { skipped += 1; continue }
                var kc = d.kc; kc.mac = mac
                DB.saveKeychain(kc)
                if let l = d.ledger { DB.saveLedger(mac, l) }
                if let meta = d.meta {
                    if let x = meta.defend { DB.saveDefend(mac, x) }
                    if let x = meta.tailgate { DB.saveTailgate(mac, x) }
                    if let t = meta.synctime { DB.saveSyncTime(mac, t) }
                    if let o = meta.otpStatus { DB.saveOtpStatus(mac, o) }
                    if let o = meta.otpIdx { DB.saveOtpIdx(mac, o) }
                }
                imp += 1
            }
            if let ms = c.members {
                for m in ms where DB.member(m.id) == nil && DB.members().first(where: { $0.name == m.name }) == nil {
                    if let created = DB.addMember(m.name) {
                        DB.setMemberInfo(created.id, ["relation": m.relation, "phone": m.phone])
                    }
                }
            }
            if let g = c.globals {
                // 2026-10-14: 外观与设备组织随包落地 (与 .overwrite 同口径)
                BackupKit.applyGlobalsAppearanceAndOrg(g, devices: c.devices)
                for d in g.keychainDongles ?? [] { DB.saveDongle(d) }
                for gw in g.gatewayList ?? [] { DB.saveGateway(gw) }
                if let pc = g.passcode, !pc.s.isEmpty, !pc.d.isEmpty {
                    // 同 BackupKit.restoreAll: 只写 s/d (d2 不进 canonical, 包体里没有)
                    DB.store.set("kf_passcode", ["s": pc.s, "d": pc.d])
                }
                if let otps = g.otpKeys, !otps.isEmpty {
                    // 与 BackupKit.restoreAll 同口径: 只允许本包内锁的 totp/static 键进库
                    var allowed = Set<String>()
                    for d in c.devices {
                        for m in [d.mac, DB.normalizeMac(d.mac)] {
                            allowed.insert(CredentialOrg.totpKey(m))
                            allowed.insert(CredentialOrg.staticKey(m))
                        }
                    }
                    for (k, v) in otps where allowed.contains(k) && !v.isEmpty { DB.store.set(k, v) }
                }
                if let tr = g.trace, let lines = tr.lines, !lines.isEmpty {
                    DB.store.set("kf_trace_persist_v1", [
                        "savedAt": tr.savedAt ?? 0, "count": lines.count,
                        "chars": tr.chars ?? 0, "lines": lines,
                    ])
                }
            }
            _ = markImported()
            return (imp, 0, skipped)
        }
    }
    /// 419 冲突裁决: 同 ID 凭证两边都有 → 逐条选新版/旧版, 支持整批。
    /// id 与 restore(conflictTakeBackup:) 同形状: mac:p:别名 / mac:f:批次 — 密码与指纹各算一条。
    struct Conflict: Identifiable {
        let id: String
        let mac: String
        let alias: String
        let kind: String
    }
    static func conflicts(_ bundle: BackupBundle) -> [Conflict] {
        var out: [Conflict] = []
        for d in bundle.devices {
            let mac = DB.normalizeMac(d.mac)
            guard DB.keychain(mac) != nil, let l = d.ledger else { continue }
            for p in l.pwds where DB.getPwd(mac, p.alias) != nil {
                out.append(Conflict(id: "\(mac):p:\(p.alias)", mac: mac, alias: String(p.alias), kind: "密码"))
            }
            for f in l.fps where DB.getFp(mac, f.batch) != nil {
                out.append(Conflict(id: "\(mac):f:\(f.batch)", mac: mac, alias: String(f.batch), kind: "指纹"))
            }
        }
        return out
    }

    // ---------- 444/425 迁移后核对表 + 差异报告 ----------
    struct DiffRow: Identifiable { var id: String { label }; let label: String; let a: Int; let b: Int }
    static func compare(_ bundle: BackupBundle, _ current: BackupBundle) -> [DiffRow] {
        func tally(_ x: BackupBundle) -> [String: Int] {
            var m: [String: Int] = ["设备": x.devices.count]
            m["凭证"] = x.devices.reduce(0) { $0 + ($1.ledger?.pwds.count ?? 0) + ($1.ledger?.fps.count ?? 0) }
            m["成员"] = x.members?.count ?? 0
            m["记录"] = x.globals?.trace?.lines?.count ?? 0
            return m
        }
        let ta = tally(bundle), tb = tally(current)
        return ["设备", "凭证", "成员", "记录"].map {
            DiffRow(label: $0, a: ta[$0] ?? 0, b: tb[$0] ?? 0)
        }
    }
    /// 425/440 逐锁对账行: 备份 vs 本机现况 (id = 规范化 mac)
    struct LockDiff: Identifiable {
        let id: String
        let label: String
        let backup: Int
        let local: Int
        let note: String
        var ok: Bool { backup <= local }
    }
    static func lockDiffRows(_ bundle: BackupBundle) -> [LockDiff] {
        var out: [LockDiff] = []
        for d in bundle.devices {
            let mac = DB.normalizeMac(d.mac)
            let bp = (d.ledger?.pwds.count ?? 0) + (d.ledger?.fps.count ?? 0)
            guard let kc = DB.keychain(mac) else {
                out.append(LockDiff(id: mac, label: LockArchive.displayName(d.kc), backup: bp, local: 0,
                                    note: "本机还没有这把锁"))
                continue
            }
            let l = DB.ledger(mac)
            let lp = l.pwds.count + l.fps.count
            out.append(LockDiff(id: mac, label: LockArchive.displayName(kc), backup: bp, local: lp,
                                note: bp > lp ? "本机少 \(bp - lp) 条凭证" : "已一致"))
        }
        return out
    }
    /// 440 迁移完成页用: 只看"旧机有新机缺"的行
    static func lockGaps(_ bundle: BackupBundle) -> [LockDiff] {
        lockDiffRows(bundle).filter { !$0.ok }
    }

    /// 193 体积预估: 本次 canonical 字符数 × 加密膨胀 (~1.75x hex) 估算, 与上次对比
    static func estimateBytes() -> Int? {
        let plain = BackupCanonical.exportText(bundleFor(BZones()))
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

    // ================= 换机迁移 (438-446) =================
    /// 438 三通道: 备份文件 / 扫码 / WebDAV
    enum Channel: String, CaseIterable { case file = "备份文件", qr = "扫码", webdav = "WebDAV" }
    /// 445 中断续迁: 会话可序列化, 重启检测临时事务表
    struct MigSession: Codable {
        var channel: String
        var startedAt: Double
        var step: Int
        var total: Int
        var imported: Int
        var done: Bool
    }
    static func loadMigSession() -> MigSession? { DB.store.get(MigSession.self, "kf_mig_session") }
    static func saveMigSession(_ s: MigSession) { DB.store.setCodable("kf_mig_session", s) }
    static func clearMigSession() { DB.store.remove("kf_mig_session") }
    /// 445: 冷启动检测未完成的迁移会话
    static func pendingMigration() -> MigSession? {
        let s = loadMigSession()
        return s?.done == false ? s : nil
    }

    /// 445 真事务表: 本次迁移的回滚点 (421 快照) + 已落库的锁。
    /// 中断判定认的是**这个键**, 不是会话百分比 —— 会话只描述进度外观, 事务表才决定能否回滚/续做。
    struct MigTxn: Codable {
        var channel: String
        var rollbackPath: String
        var at: Double
        var doneMacs: [String]
        init(channel: String, rollbackPath: String, at: Double, doneMacs: [String]) {
            self.channel = channel
            self.rollbackPath = rollbackPath
            self.at = at
            self.doneMacs = doneMacs
        }
        /// 显式解码 (缺字段用保守默认, 不静默丢整表): 与 swiftshape R3 对 Codable 带默认字段的要求一致
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            channel = try c.decodeIfPresent(String.self, forKey: .channel) ?? "备份文件"
            rollbackPath = try c.decodeIfPresent(String.self, forKey: .rollbackPath) ?? ""
            at = try c.decodeIfPresent(Double.self, forKey: .at) ?? 0
            doneMacs = try c.decodeIfPresent([String].self, forKey: .doneMacs) ?? []
        }
    }
    static func loadMigTxn() -> MigTxn? { DB.store.get(MigTxn.self, "kf_mig_txn") }
    static func saveMigTxn(_ t: MigTxn) { DB.store.setCodable("kf_mig_txn", t) }
    /// 445 开始/续做迁移: 首次先打全库快照 (打不出就不允许开跑); 有可用旧事务表则沿用其回滚点,
    /// 不重拍快照 —— 否则中途崩溃后"回滚"只能回到半截状态, 等于没有回滚。
    @discardableResult
    static func beginMigrationTxn(channel: String) -> Bool {
        if let t = loadMigTxn(), !t.rollbackPath.isEmpty,
           FileManager.default.fileExists(atPath: t.rollbackPath) {
            return true
        }
        guard makeRollbackPoint() else { return false }
        let path = DB.store.getString("kf_bk_rollback")
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return false }
        saveMigTxn(MigTxn(channel: channel, rollbackPath: path,
                          at: Date().timeIntervalSince1970 * 1000, doneMacs: []))
        return true
    }
    /// 445: 每把锁真实落库后调用 — 这是续迁的断点
    static func noteMigTxnDone(_ mac: String) {
        guard var t = loadMigTxn() else { return }
        let m = DB.normalizeMac(mac)
        if !t.doneMacs.contains(m) { t.doneMacs.append(m) }
        saveMigTxn(t)
    }
    /// 445: 快照文件仍在的事务表才算未完成; 快照被清掉的事务表不可回滚, 当不存在
    static func pendingMigrationTxn() -> MigTxn? {
        guard let t = loadMigTxn(), !t.rollbackPath.isEmpty,
              FileManager.default.fileExists(atPath: t.rollbackPath) else { return nil }
        return t
    }
    static func finishMigrationTxn() { DB.store.remove("kf_mig_txn") }
    /// 445 回滚: 把库体还原到迁移前快照, 并清掉迁移期间立起的全部标记
    @discardableResult
    static func rollbackMigrationTxn() -> Bool {
        guard let t = pendingMigrationTxn() else { return false }
        guard restoreRollbackSnapshot(t.rollbackPath) else { return false }
        DB.store.remove("kf_mig_txn")
        clearMigSession()
        if DB.store.getString("kf_bk_rollback") == t.rollbackPath { DB.store.remove("kf_bk_rollback") }
        DB.store.remove("kf_migrate_pending")
        for kc in DB.keychains() { DB.store.remove("kf_migok_" + kc.mac) }
        _ = Milestones.recordBackup()
        return true
    }
    /// 442 恢复/迁移落库后立起首验清单: 清掉旧勾, 挂待验标记 (DeviceHomeView 逐锁验证写 kf_migok_)
    static func armFirstChecks() {
        for kc in DB.keychains() { DB.store.remove("kf_migok_" + kc.mac) }
        // 2026-10-15 走查: 上面这句注释承诺"清掉旧勾", 而这一支原先只清 kf_migok_, **没清 kf_mig_checks**。
        // 后果是那道"每把锁都要在新机上验一遍"的闸被上一轮自己满足了: 第二次换机迁移一进完成页,
        // 四格首验全是上一次的勾,「完成迁移」不验任何东西就能点。清掉才是注释说的那件事。
        DB.store.remove("kf_mig_checks")
        DB.store.set("kf_migrate_pending", ISO8601DateFormatter().string(from: Date()))
    }

    /// 439/441/445 真实迁移导入: 逐段 (410 分卷可多段) 逐锁真实执行, 每完成一个真实单元回调一次
    /// (进度只跟着真做完的单元走); 每把锁落库后立即写事务表 doneMacs — 中断续做按它跳过,
    /// 不是把百分比接着画。skipMacs = 上次已落库的锁 (整锁跳过, 计 skipped)。
    @discardableResult
    static func migrateImport(_ b: BackupBundle, zones: BZones,
                              lockActs: [String: String] = [:],
                              conflictTakeBackup: Set<String> = [],
                              skipMacs: Set<String> = [],
                              onStep: (Int, Int, String) -> Void) async -> (imported: Int, overwritten: Int, skipped: Int) {
        let valid = b.devices.filter { HexKit.bytes($0.mac).count == 6 && !$0.kc.skey.isEmpty }
        let total = valid.count + 1
        var imp = 0, ov = 0, sk = 0
        // 单元①: 设置/成员/全局 (不含 otpKeys — 它按锁白名单, 放逐锁单元)
        var setBundle = b
        setBundle.globals = setBundle.globals.map { var g = $0; g.otpKeys = nil; return g }
        var z0 = zones
        z0.devices = false
        let r0 = restore(setBundle, strategy: .merge, zones: z0, makeSnapshot: false)
        imp += r0.imported; ov += r0.overwritten; sk += r0.skipped
        onStep(1, total, "设置与成员")
        try? await Task.sleep(for: .milliseconds(60))
        // 单元②…: 逐锁真实执行
        for (i, d) in valid.enumerated() {
            let mac = DB.normalizeMac(d.mac)
            let name = LockArchive.displayName(d.kc)
            if skipMacs.contains(mac) {
                sk += 1
                onStep(i + 2, total, name + " · 已迁移过, 跳过")
                try? await Task.sleep(for: .milliseconds(60))
                continue
            }
            var one = b
            one.devices = [d]
            one.members = nil
            // 全局只留 otpKeys: 白名单按本锁算, 其余全局项已在单元①落库
            one.globals = b.globals.map { var g = $0
                g.trace = nil
                g.keychainDongles = nil
                g.gatewayList = nil
                g.passcode = nil
                g.appearance = nil
                return g
            }
            let r = restore(one, strategy: .merge, zones: zones,
                            lockActs: lockActs, conflictTakeBackup: conflictTakeBackup,
                            makeSnapshot: false)
            imp += r.imported; ov += r.overwritten; sk += r.skipped
            noteMigTxnDone(mac)
            onStep(i + 2, total, name)
            try? await Task.sleep(for: .milliseconds(60))
        }
        return (imp, ov, sk)
    }
    /// 442 首验清单: 恢复后逐项打勾 (开一次门 / 看一条记录 / 验一处遮蔽)
    static func firstChecks() -> [String: Bool] {
        DB.store.get([String: Bool].self, "kf_mig_checks") ?? [:]
    }
    static func markFirstCheck(_ k: String, on: Bool = true) {
        var m = firstChecks()
        m[k] = on   // 2026-10-15 走查: 原先只会写 true —— 取消勾选落不了盘, 而这份字典是完成页那四格的初值
        DB.store.setCodable("kf_mig_checks", m)
    }
    static var firstChecksAllDone: Bool {
        !DB.store.getString("kf_migrate_pending").isEmpty &&
        DB.keychains().allSatisfy { DB.store.getBool("kf_migok_" + $0.mac) }
    }
    /// 446 旧机退役横幅: 首验全勾 → 旧机顶部引导本地销毁
    static var retirementBanner: Bool { DB.store.getBool("kf_mig_retire") }
    static func markRetired() { DB.store.set("kf_mig_retire", true) }

    // ================= 完整性与信任感 (448-454 / 507-512) =================
    /// 库体指纹 (448/397 共用一份算法, 免得两处各算各的后端口径漂移)
    /// 库体指纹算法版本: 变更时递增 —— 旧基线 (不带前缀) 不参与比对, 免得升级后误报自检异常。
    private static let fpVersion = "2:"
    private static func dbFingerprint() -> String {
        // 2026-10-14: 旧实现只统计长度 (skey.count + pins.count) —— 替换等长 skey / 增删等量 pin 察觉不到。
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
    // 删除面：只删本 App 自己写出来的备份文件 —— 名字族 `锁管家_…_全量[_卷N].enc`、且必须在当前目录一层内
    // (不含 "/")；固定名 `zklock-backup.enc` 不参与计数 (423/436 读的就是它)。
    // 为什么这里要窄到名字族：`webdavRoot` 的**默认值就是整个坚果云根目录**
    // (`https://dav.jianguoyun.com/dav/我的坚果云`)，而 430 那枚 Stepper 就摆在备份页上、写着"远端只留 N 份"。
    // 原先的实现是「把 PROPFIND 列表按名字排序、删掉第 N 条以后的**全部**」——
    // 在默认 root 下那些条目是用户的照片、合同、子文件夹 (许多服务端对文件夹的 DELETE 是递归的)，
    // 一旦用户把保留份数从 0 调成任何正数，进这一页就会**不可逆地删掉网盘里其它东西** (§10.40)。
    // 另一处同族错：按整名字典序排 ≠ 按时间排 —— 名字是 `锁管家_<锁名>_…`，锁名先参与比较，
    // 于是"阿爸"那把锁的所有旧备份都排在"大门"今天那份之前，超限被删的正是最新那份。
    /// 430 本地滚动保留: 与 pruneRemote 同一套名字族 (isOurBackup) 与"一份 = 一卷组" (volumeSet) 的口径,
    /// 同样保最近 N 份 + 每月再保 1 份。差别只在删除面是本机目录, 不存在误删网盘相册那一类风险;
    /// 触发点是**写完新备份之后** (BackupStudio 导出流程尾), 不是列表页 onAppear ——
    /// "打开看一眼就把用户的备份文件清掉"是 scanOrphans 那处注释明令禁止的实现。
    @discardableResult
    static func pruneLocal(keep: Int) -> Int {
        guard keep > 0 else { return 0 }
        let fm = FileManager.default
        let all = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var groups: [String: [URL]] = [:]
        for u in all where isOurBackup(u.lastPathComponent) {
            groups[volumeSet(u.lastPathComponent), default: []].append(u)
        }
        let ordered = groups.keys.sorted { a, b in
            let da = dateInName(a), db = dateInName(b)
            return da == db ? a > b : da > db
        }
        var pruned = 0
        var keptMonths = Set<String>()
        for (i, key) in ordered.enumerated() {
            let month = String(dateInName(key).prefix(7))
            if i < keep || (!month.isEmpty && keptMonths.insert(month).inserted) { continue }
            for u in groups[key] ?? [] where (try? fm.removeItem(at: u)) != nil { pruned += 1 }
        }
        return pruned
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
    /// 237 密钥轮换: 新口令重加密替换远端旧备份 (旧文件重命名留痕)
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

    // ================= 1048 管家交接包 =================
    struct Handover { let text: String; let fileName: String }
    /// 1048 交接包 —— 2026-10-14: 必须加密。包体含整库 skey 与台账口令, 旧实现却按明文写出,
    /// 而说明文字还让收件人"输入口令" (名不副实)。改为以交接口令 CryptoBox 加密后再落盘/复制。
    @discardableResult
    static func handoverPackage(password: String) -> Handover? {
        guard !password.isEmpty else { return nil }
        let b = BackupKit.collectAll()
        let canon = BackupCanonical.exportText(b)
        guard !canon.isEmpty else { return nil }
        let use = """
        // 离线锁管家 · 交接信 (1048)
        // 给下一位管家人: 这份备份含 \(b.devices.count) 台门锁 / \(b.members?.count ?? 0) 位成员。
        // 1. 新机装「离线锁管家」, 备份页选「导入」, 粘贴本文件并输入口令。
        // 2. 选「合并」策略, 逐锁验证连接 (换机首验清单)。
        // 3. 旧机走「设置→备份→交接」, 本机数据三级清空。
        // 本文件已用交接口令加密 — 口令另行线下交接, 不要与文件同渠道发出。
        """
        // 只加密**包体**, 说明头留明文 —— parsePreview 先剥 "//" 头再解密。
        // 若把头也加密进去, 解密后仍是 "// ...\n{json}", JSONDecoder 解不出 (本 App 自己导出的包反而导不回来)。
        guard let enc = try? CryptoBox.encryptText(canon, password: password) else { return nil }
        return Handover(text: use + "\n" + enc, fileName: "锁管家_交接_\(Milestones.dayKey()).txt")
    }

    /// 440 增量补传小包: 只打入勾选的锁 (kc + 运行参数 + 台账), 不带记录卷 —— 小包越小越好传;
    /// 恢复端走 .merge 只增不删, 重复导入同一把锁不会产生副本。返回 canonical 文本或加密信封。
    static func incrementalExportText(macs: Set<String>, zones: BZones, encrypt: String?) -> String? {
        var b = bundleFor(zones)
        b.devices = b.devices.filter { macs.contains(DB.normalizeMac($0.mac)) }
        guard !b.devices.isEmpty else { return nil }
        b.globals = b.globals.map { var g = $0; g.trace = nil; return g }
        var text = BackupCanonical.exportText(b)
        guard !text.isEmpty else { return nil }
        if let pw = encrypt, !pw.isEmpty {
            text = (try? CryptoBox.encryptText(text, password: pw)) ?? ""
        }
        return text.isEmpty ? nil : text
    }
    /// 440 增量包文件名: 与 409 同族 (锁管家_主锁名_日期时分_增量.enc), 430 滚动保留能按日期份计数
    static func incrementalFileName() -> String {
        let kc = DB.keychains().first
        let name = (kc.map { LockArchive.displayName($0) } ?? "本机").replacingOccurrences(of: "/", with: "-")
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return Self.filePrefix + "\(name)_\(f.string(from: Date()))_增量.enc"
    }

    // ================= 435 逐文件算法标注 =================
    // 工作室首页那枚徽章写的是"当前代码用什么算法"；435 要的是**这一份备份自己**的参数，
    // 所以直接读信封 JSON 的开头几 KB (alg/kdf/iter 就在文件头)，不解密、不要口令、也不猜。
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

    // ================= 437 备份复核钉 =================
    // 备份的失效方式是"到要用的那天才发现用不了"，所以这里钉的是**复核日期**而不是提醒文案。
    // 三条口径:
    //   1. 键一律用**真实文件名** (433 的别名只改显示、可能被人改), 显示时才换成别名;
    //   2. 只列目录里真存在的文件 —— 文件被删掉而键残留时, 提醒不能再指向一个不存在的东西;
    //   3. "知道了"记的是**那一个复核日**, 把日期往后挪一钉就会重新催 (挪了日期还装看不见是不成立的)。
    static let pinKey = "kf_bk_pin"
    static let pinSeenKey = "kf_bk_pin_seen"
    struct PinDue { let file: String; let day: String; let overDays: Int }
    static func pins() -> [String: String] { DB.store.get([String: String].self, pinKey) ?? [:] }
    static func setPin(_ file: String, _ day: String) {
        var m = pins()
        if day.isEmpty { m.removeValue(forKey: file) } else { m[file] = day }
        DB.store.setCodable(pinKey, m)
    }
    static func dayDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f.date(from: s)
    }
    static func dayString(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f.string(from: d)
    }
    /// 到日 (含) 之后每天都算到期, 因为"错过一天就再也不提"只会让备份更晚被发现坏掉
    static func duePins(now: Date = Date()) -> [PinDue] {
        let cal = WeekCal.gregorian
        let today = cal.startOfDay(for: now)
        let live = Set((try? FileManager.default.contentsOfDirectory(at: dir,
            includingPropertiesForKeys: nil))?.map { $0.lastPathComponent } ?? [])
        let seen = DB.store.get([String: String].self, pinSeenKey) ?? [:]
        var out: [PinDue] = []
        for (file, day) in pins() where live.contains(file) && seen[file] != day {
            guard let d = dayDate(day) else { continue }        // 存坏的日期串不猜, 直接不提
            let pin = cal.startOfDay(for: d)
            guard pin <= today else { continue }
            out.append(PinDue(file: file, day: day, overDays: cal.dateComponents([.day], from: pin, to: today).day ?? 0))
        }
        return out.sorted { $0.day < $1.day }
    }
    static func markPinSeen(_ file: String, _ day: String) {
        var m = DB.store.get([String: String].self, pinSeenKey) ?? [:]
        m[file] = day
        DB.store.setCodable(pinSeenKey, m)
    }
    /// 显示名: 433 别名第一行优先, 没有别名就用真实文件名 (提醒里必须能认出是哪一份)
    static func pinLabel(_ file: String) -> String {
        let note = DB.store.get([String: String].self, "kf_bk_note")?[file] ?? ""
        let alias = note.split(separator: "\n").first.map(String.init) ?? ""
        return alias.isEmpty ? file : alias
    }
    static func pinDayText(_ day: String) -> String {
        guard let d = dayDate(day) else { return day }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M 月 d 日"
        return f.string(from: d)
    }
}

// ---------- UNUserNotificationCenter delegate 单例 (1018 通知点按 → 还原点 + 指路备份) ----------
final class UNDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = UNDelegate()
    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse,
                               completionHandler: @escaping () -> Void) {
        if r.notification.request.identifier == "kf.bk.monthly" {
            Task { @MainActor in
                await BackupStudio.onMonthlyTap()
            }
        }
        // 963 每晚状态确认: 点它就落到设备页 (与深链/快速操作同一个 requestTab 口,
        // 应用锁还锁着时只记 pendingRoute, 不因为"是从通知进来的"就放行)。
        if r.notification.request.identifier == StatusCheckNotice.notifID {
            Task { @MainActor in
                var waited = 0
                while AppState.hostRef == nil && waited < 10 {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    waited += 1
                }
                // 2026-10-14: 与月度/保养通知同口径 —— 锁着或伪装态只记 pendingRoute, 不因"从通知进来"放行。
                if let app = AppState.hostRef {
                    if app.appUnlocked && !app.decoyMode { app.requestRoute(.device) } else { app.pendingRoute = .device }
                }
            }
        }
        // 366/1013: 凭证族通知此前只排期不分派 —— handleNotificationAction 全仓零调用,
        // 点"密码临期"通知落到系统默认行为(打开 App 停在原页面)。这里补上转发。
        if let act = CredentialOrg.handleNotificationAction(r.notification.request.identifier) {
            Task { @MainActor in CredentialOrg.applyNotification(act) }
        }
        // 1013: 保养到期通知 → 保养清单页。mac 就在通知 id 里 (m4.care.<mac>)。
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
