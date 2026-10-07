// 包8 备份工作室服务层 — 备份·恢复·换机迁移
// 覆盖 idea: 181/193/197/198/237/407-413/417-427/429-431/434-436/438-446/448-450/453/454/456/477/507-509/511/512/1018/1048
// 纪律: 备份文件只去用户自配 WebDAV (Basic Auth 运行时输入), 口令不出本机内存;
//       加密语义 (CryptoBox AES-128-CBC+HMAC/PBKDF2, ZOTP 相关) 不动, 本层只做外围策略。
import Foundation
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
    static var dir: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("lockkeeper-backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    static var rollbackDir: URL { dir.appendingPathComponent("rollback", isDirectory: true) }

    /// 409 自描述文件名: 锁管家_主锁名_2026-10-08_全量.enc (410 分卷时尾部加 _卷N)
    static func fileName(vol: Int = 0) -> String {
        let kc = DB.keychains().first
        let name = (kc.map { LockArchive.displayName($0) } ?? "本机").replacingOccurrences(of: "/", with: "-")
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        let stamp = f.string(from: Date())
        return "锁管家_\(name)_\(stamp)_全量" + (vol > 0 ? "_卷\(vol)" : "") + ".enc"
    }

    // ================= 策略配置 (198 节奏三档 / 430 滚动保留 / 429 新鲜度) =================
    /// 198: manual / daily / weekly — 备份节奏三档 (落地为本地通知提醒, 不做后台静默写)
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

    // ---------- 1018 月度备份日: 每月固定日本地通知, 点通知一键备份 ----------
    static var monthlyDay: Int {
        get { DB.store.getInt("kf_bk_month_day", 0) }
        set { DB.store.set("kf_bk_month_day", max(0, min(31, newValue))) }
    }
    static func scheduleMonthlyBackup() async {
        let day = monthlyDay
        guard day > 0 else { return }
        guard await CareSchedule.requestAuth() else { return }
        for r in UNUserNotificationCenter.current().pendingRequests() where r.identifier == "kf.bk.monthly" {
            UNUserNotificationCenter.current().removePendingNotificationRequests(identifiers: [r.identifier])
        }
        let c = UNMutableNotificationContent()
        c.title = "月度备份日 (1018)"
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
    /// 通知点按: 本机快照 + 记历史 (无口令, 口令只走向导)
    static func onMonthlyTap() {
        _ = makeRollbackPoint()
        _ = Milestones.recordBackup()
    }

    // ---------- 421 恢复回滚点 (24h 内可撤销): 完整库体 JSON 快照 ----------
    struct RollbackBundle: Codable {
        var keychains: [String]      // JSON: [Keychain]
        var ledgers: [[String: String]] // [mac → JSON(Ledger)]
        var dongles: [String]
        var gateways: [String]
        var passcode: String?
        var members: [String]
    }
    @discardableResult
    nonisolated static func makeRollbackPoint() -> Bool {
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
            members: DB.members().compactMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) })
        guard let data = try? JSONEncoder().encode(snap),
              let url = try? data.write(to: rollbackDir.appendingPathComponent(
                  "roll-\(Int(Date().timeIntervalSince1970)).json"), options: .atomic) else { return false }
        pruneRollback(keep: 4)
        DB.store.set("kf_bk_rollback", url.path)
        return true
    }
    static var canUndoLastRestore: Bool {
        guard let path = DB.store.getString("kf_bk_rollback"), !path.isEmpty,
              let url = URL(fileURLWithPath: path),
              let m = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        else { return false }
        return Date().timeIntervalSince(m) < 86400
    }
    @discardableResult
    static func undoLastRestore() -> Bool {
        guard let path = DB.store.getString("kf_bk_rollback"), !path.isEmpty,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let snap = try? JSONDecoder().decode(RollbackBundle.self, from: data) else { return false }
        // 421: 逐分区还原 — 只写回本机键位, 不碰锁端协议
        for s in snap.keychains {
            if let d = s.data(using: .utf8), let kc = try? JSONDecoder().decode(Keychain.self, from: d) {
                DB.saveKeychain(kc)
            }
        }
        for (mac, s) in snap.ledgers {
            if let d = s.data(using: .utf8), let l = try? JSONDecoder().decode(Ledger.self, from: d) {
                DB.saveLedger(mac, l)
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
        DB.store.remove("kf_bk_rollback")
        _ = Milestones.recordBackup()
        return true
    }
    private nonisolated static func pruneRollback(keep: Int) {
        let all = (try? FileManager.default.contentsOfDirectory(at: rollbackDir,
                  includingPropertiesForKeys: nil)) ?? []
        let sorted = all.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for f in sorted.suffix(from: keep) { try? FileManager.default.removeItem(at: f) }
    }

    // ---------- 428 ⚠ 充电自动备份: BGTask 注册 + 诚实文案 (执行时机由系统择机) ----------
    static let chargeBackupTaskId = "com.kf.chargebackup"
    static func registerChargeBackup() {
        guard BGTaskScheduler.shared.supports([BGTaskType.appRefresh]) else { return }
        BGTaskScheduler.shared.submit(
            BGAppRefreshTaskRequest(identifier: chargeBackupTaskId)) { request in
            guard request.expirationHandler == nil else { request.setTaskCompleted(true); return }
            _ = makeRollbackPoint()
            request.setTaskCompleted(true)
        }
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
        out["记录"] = DB.keychains().count      // 每锁一份日志缓存 (条数按卷估算, UI 标"约")
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
                g.trace = z.records ? g.trace : nil
                return g
            }
            if let g = c.globals, g.keychainDongles == nil, g.gatewayList == nil,
               g.passcode == nil, g.trace == nil {
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
    /// 写本地文件 (413 分享用), 返回 URL; 181 勾选时追加 OTP 密钥段
    @discardableResult
    static func writeLocal(_ text: String, name: String, otp: Bool) -> URL? {
        let url = dir.appendingPathComponent(name + ".enc")
        var body = text
        if otp {
            var otps = [String: String]()
            for kc in DB.keychains() {
                let k = CredentialOrg.totpKey(kc.mac)
                let v = DB.store.getString(k)
                if !v.isEmpty { otps[k] = v }
                let ks = CredentialOrg.staticKey(kc.mac)
                let vs = DB.store.getString(ks)
                if !vs.isEmpty { otps[ks] = vs }
            }
            if !otps.isEmpty, let d = try? JSONEncoder().encode(otps) {
                body += "\n//OTPK " + (String(data: d, encoding: .utf8) ?? "")
            }
        }
        guard (try? body.write(to: url, atomically: true, encoding: .utf8)) != nil else { return nil }
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
        b.members = b.members
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
                              text: "\(expired) 条已过时效仍占台账, 可勾「先清理」减少条数 (431)"))
        }
        let noOwner = DB.keychains().reduce(0) { acc, kc in
            let l = DB.ledger(kc.mac)
            return acc + l.pwds.filter { $0.owner == nil }.count + l.fps.filter { $0.owner == nil }.count
        }
        if noOwner > 0 {
            rows.append(.init(label: "无归属",
                              text: "\(noOwner) 条凭证未指定成员, 恢复后仍需认领 (412)"))
        }
        if daysSinceLastExport() >= 14 {
            rows.append(.init(label: "数据陈旧",
                              text: "距上次备份已 \(daysSinceLastExport()) 天, 本次建议全量并演练验证 (429)"))
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
    }
    /// 417/449/450 恢复预演: 魔数/长度先行 (449), 口令解码, schema 升级 (424), 抽 5 条 (450)
    static func preview(text: String, password: String?) throws -> Preview {
        var body = text
        if password != nil || looksEncrypted(text) {
            body = try decryptAny(text, password: password)
        }
        guard let data = body.data(using: .utf8),
              let bundle = try? JSONDecoder().decode(BackupBundle.self, from: data) else {
            throw DFUError.msg("口令错误或内容不是备份 (420/453 口令/文件头层)")
        }
        let m = upgradeChain(bundle)
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
        return Preview(source: "备份时间 \(m.at)" + (sourceName.isEmpty ? "" : " · 来源 \(sourceName)"),
                       schema: m.schema,
                       zones: zones,
                       macs: m.devices.map { $0.mac },
                       pwdCount: p, fpCount: f,
                       memberCount: m.members?.count ?? 0,
                       sampleOk: sample,
                       previewTrace: Array((m.globals?.trace?.lines ?? []).prefix(5)))
    }
    private static func looksEncrypted(_ s: String) -> Bool {
        s.hasPrefix("{") && s.contains("\"cHex\"")
    }
    /// 420/453 失败分层: 口令 / 文件头 / 内容哈希
    static func decryptAny(_ text: String, password: String?) throws -> String {
        guard looksEncrypted(text) else { return text }
        guard let pw = password, !pw.isEmpty else {
            throw DFUError.msg("此备份带口令 — 输入导出时设置的口令 (453 口令层)")
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
            if var g = out.globals {
                g.trace = g.trace
                out.globals = g
            }
            s = 4
        }
        if s < 5 {
            // v5: otpStatus/otpIdx 从 synctime 序列拆出为独立键位 (旧版塞在 meta 之后)
            for i in out.devices.indices {
                var m = out.devices[i].meta ?? .init()
                m.otpStatus = m.otpStatus
                m.otpIdx = m.otpIdx
                out.devices[i].meta = m
            }
            s = 5
        }
        out.schema = s
        return out
    }
    /// 422/423 哈希先行: 校验 checksum (434 短码展示同一口径)
    static func verifyChecksum(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8),
              let b = try? JSONDecoder().decode(BackupBundle.self, from: data),
              let c = b.checksum else { return false }
        var b2 = b; b2.checksum = nil
        return BackupCanonical.fnv1a32Hex(BackupCanonical.canonical(b2)) == c.lowercased()
    }
    /// 434 哈希短码: SHA256 前 8 位
    static func shortHash(_ text: String) -> String {
        String(HashKit.sha256Hex(text).prefix(8))
    }
    /// 418/427: 策略 + 分区裁剪; 返回 (新增, 覆盖, 跳过)
    @discardableResult
    static func restore(_ bundle: BackupBundle, strategy: MergeStrategy, zones: BZones) -> (imported: Int, overwritten: Int, skipped: Int) {
        var b = bundle
        b.currentMac = ""   // 首验清 currentMac, 避免指向另一台设备的锁
        let c = prune(b, zones)
        // 421 恢复回滚点: 执行前自动全库快照
        _ = makeRollbackPoint()
        switch strategy {
        case .overwrite, .merge:
            // 419 冲突 = 同 ID 凭证两边都有: UI 层预列出逐条裁决, 此处置 0 跳过
            let r = BackupKit.restoreAll(c)
            return (r.imported, r.overwritten, 0)
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
                for d in g.keychainDongles ?? [] { DB.saveDongle(d) }
                for gw in g.gatewayList ?? [] { DB.saveGateway(gw) }
                if let pc = g.passcode, !pc.s.isEmpty, !pc.d.isEmpty {
                    DB.store.set("kf_passcode", ["s": pc.s, "d": pc.d])
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
    /// 419 冲突裁决: 同 ID 凭证两边都有 → 逐条选新版/旧版, 支持整批
    struct Conflict: Identifiable { var id: String { mac + ":" + alias }; let mac: String; let alias: String }
    static func conflicts(_ bundle: BackupBundle) -> [Conflict] {
        var out: [Conflict] = []
        for d in bundle.devices {
            guard DB.keychain(d.mac) != nil, let l = d.ledger else { continue }
            for p in l.pwds where DB.getPwd(d.mac, p.alias) != nil {
                out.append(Conflict(mac: d.mac, alias: String(p.alias)))
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

    /// 193 体积预估: 本次 canonical 字符数 × 加密膨胀 (~1.75x hex) 估算, 与上次对比
    static func estimateBytes() -> Int? {
        let plain = BackupCanonical.exportText(bundleFor(BZones()))
        guard !plain.isEmpty else { return nil }
        return plain.count * 2
    }
    static func sizeText(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        return "本次预计 ~" + String(format: "%.1f KB", kb) + " (193, 近 30 天备份 " + String(Milestones.backupThisMonth) + " 次)"
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
    static func saveMigSession(_ s: MigSession) { DB.store.setCodable(s, "kf_mig_session") }
    static func clearMigSession() { DB.store.remove("kf_mig_session") }
    /// 445: 冷启动检测未完成的迁移会话
    static func pendingMigration() -> MigSession? {
        let s = loadMigSession()
        return s?.done == false ? s : nil
    }
    /// 442 首验清单: 恢复后逐项打勾 (开一次门 / 看一条记录 / 验一处遮蔽)
    static func firstChecks() -> [String: Bool] {
        DB.store.get([String: Bool].self, "kf_mig_checks") ?? [:]
    }
    static func markFirstCheck(_ k: String) {
        var m = firstChecks()
        m[k] = true
        DB.store.setCodable(m, "kf_mig_checks")
    }
    static var firstChecksAllDone: Bool {
        !DB.store.getString("kf_migrate_pending").isEmpty &&
        DB.keychains().allSatisfy { DB.store.getBool("kf_migok_" + $0.mac) }
    }
    /// 446 旧机退役横幅: 首验全勾 → 旧机顶部引导本地销毁
    static var retirementBanner: Bool { DB.store.getBool("kf_mig_retire") }
    static func markRetired() { DB.store.set("kf_mig_retire", true) }

    // ================= 完整性与信任感 (448-454 / 507-512) =================
    /// 448 启动自检: 库体哈希 vs 上次快照; 不一致返回黄条文案
    @discardableResult
    static func runStartupSelfCheck() -> String? {
        var m = [String: Int]()
        for kc in DB.keychains() { m[DB.normalizeMac(kc.mac)] = kc.skey.count + kc.pins.count }
        let canon = m.sorted { $0.key < $1.key }.map { "\($0.0):\($0.1)" }.joined(separator: "|")
        let fp = BackupCanonical.fnv1a32Hex(canon)
        let last = DB.store.getString("kf_bk_dbhash")
        if !last.isEmpty, last != fp {
            DB.store.set("kf_bk_selfwarn", true)
            return "数据自检异常 — 库体哈希与上次备份快照不一致, 建议立即备份并去诊断 (448)"
        }
        if DB.store.getBool("kf_bk_selfwarn") { DB.store.remove("kf_bk_selfwarn") }
        DB.store.set("kf_bk_dbhash", fp)
        return nil
    }
    static var selfCheckWarning: String? {
        DB.store.getBool("kf_bk_selfwarn") ? "数据自检异常, 去诊断 (448)" : nil
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
    struct RemoteEntry: Identifiable { var id: String { name }; let name: String; let size: Int; let etag: String }
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
            if http.statusCode == 401 || http.statusCode == 403 { return "账号或应用密码错误 (401)" }
            return "HTTP \(http.statusCode)"
        } catch { return "网络不可达: \(error.localizedDescription)" }
    }
    /// 422/423 远端列表: 拉 etag (哈希) + 大小, 再按需拉正文 — 断点友好
    static func listRemote(acct: String, appPw: String, root: String) async throws -> [RemoteEntry] {
        guard let url = URL(string: root) else { throw DFUError.msg("地址非法") }
        var req = URLRequest(url: url)
        req.httpMethod = "PROPFIND"
        req.setValue(CloudSync.basicAuth(acct, appPw), forHTTPHeaderField: "Authorization")
        req.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("<?xml version=\"1.0\"?><propfind xmlns=\"DAV:\"><prop><resourcename/><getcontentlength/><getetag/></prop></propfind>".utf8)
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw DFUError.msg("响应异常") }
        if http.statusCode == 404 { return [] }
        if http.statusCode == 401 || http.statusCode == 403 { throw DFUError.msg("账号或应用密码错误") }
        guard http.statusCode == 207 else { throw DFUError.msg("PROPFIND HTTP \(http.statusCode)") }
        let xml = String(data: data, encoding: .utf8) ?? ""
        var out: [RemoteEntry] = []
        var i = xml.startIndex
        while let s = xml.range(of: "<resourcename>", range: i..<xml.endIndex) {
            i = s.upperBound
            guard let e = xml.range(of: "</resourcename>", range: i..<xml.endIndex) else { break }
            let name = String(xml[i..<e.lowerBound]).trimmingCharacters(in: .whitespaces)
            i = e.upperBound
            guard !name.isEmpty else { continue }
            func cap(_ tag: String, from: String.Index) -> String {
                var idx = from
                while let r = xml.range(of: "<\(tag)>", range: idx..<xml.endIndex) {
                    guard let en = xml.range(of: "</\(tag)>", range: r.upperBound..<xml.endIndex) else {
                        idx = r.upperBound
                        continue
                    }
                    idx = en.upperBound
                    return String(xml[r.upperBound..<en.lowerBound])
                }
                return ""
            }
            out.append(RemoteEntry(name: name,
                                   size: Int(cap("getcontentlength", from: i)) ?? 0,
                                   etag: cap("getetag", from: i)))
        }
        return out.sorted { $0.name > $1.name }
    }
    /// 430 滚动保留: 远端只留 N 份, 按名字 (带日期戳) 排序
    @discardableResult
    static func pruneRemote(acct: String, appPw: String, root: String, keep: Int) async -> Int {
        guard keep > 0, let entries = try? await listRemote(acct: acct, appPw: appPw, root: root) else { return 0 }
        let sorted = entries.sorted { $0.name > $1.name }
        var pruned = 0
        for e in Array(sorted.suffix(from: keep)) {
            guard let url = URL(string: root + "/" + e.name) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "DELETE"
            req.setValue(CloudSync.basicAuth(acct, appPw), forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: req)
            pruned += 1
        }
        return pruned
    }
    /// 436 演练恢复: 远端 → 内存解密试读 + 哈希, 不碰真库
    @discardableResult
    static func dryRunRemote(acct: String, appPw: String, root: String, name: String, password: String) async -> String {
        guard let url = URL(string: root + "/" + name) else { return "地址非法" }
        var req = URLRequest(url: url)
        req.setValue(CloudSync.basicAuth(acct, appPw), forHTTPHeaderField: "Authorization")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let raw = String(data: data, encoding: .utf8) ?? ""
            let body = (try? decryptAny(raw, password: password)) ?? raw
            return verifyChecksum(body) ? "已验证 · 抽样 5 条可解析 · 哈希 " + shortHash(body)
                : "哈希不一致 — 仅告警, 不入库 (423)"
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
                return "旧口令解不开, 轮换失败 (453 口令层)"
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
                return "上传新密文失败, 远端仍为旧口令 (237)"
            }
            return "已轮换 — 旧口令失效, 请用新口令访问 (237)"
        } catch { return "轮换中断: \(error.localizedDescription)" }
    }

    // ================= 1048 管家交接包 =================
    struct Handover { let text: String; let fileName: String }
    @discardableResult
    static func handoverPackage() -> Handover? {
        let b = BackupKit.collectAll()
        let canon = BackupCanonical.exportText(b)
        guard !canon.isEmpty else { return nil }
        let use = """
        // 离线锁管家 · 交接信 (1048)
        // 给下一位管家人: 这份备份含 \(b.devices.count) 台门锁 / \(b.members?.count ?? 0) 位成员。
        // 1. 新机装「离线锁管家」, 备份页选「导入」, 粘贴本文件并输入口令。
        // 2. 选「合并」策略, 逐锁验证连接 (换机首验清单)。
        // 3. 旧机走「设置→备份→交接」, 本机数据三级清空。
        // 口令不要写在这里 — 另行线下交接。
        """
        return Handover(text: use + "\n" + canon, fileName: "锁管家_交接_\(Milestones.dayKey()).txt")
    }

    /// 440 差异补提示语: "旧机有新机缺" 的分区差异 (会话标记未补齐时给出)
    static func diffHint() -> String? {
        let skip = DB.keychains().filter {
            DB.store.getString("kf_mig_lockact_" + $0.mac) == "skip"
        }.count
        let pending = firstChecks().count - firstChecks().values.filter { $0 == true }.count
        var parts = [String]()
        if skip > 0 { parts.append("跳过 \(skip) 把锁") }
        if pending > 0 { parts.append("\(pending) 项首验未勾") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    // ================= 511 数据事件 (建库/首次备份/恢复/迁移/清理) =================
    static func recordEvent(_ label: String) {
        var h = DB.store.get([Double].self, "kf_bk_events") ?? []
        h.append(Date().timeIntervalSince1970 * 1000)
        if h.count > 60 { h.removeFirst(h.count - 60) }
        DB.store.setCodable(h, "kf_bk_events")
    }
    static func dataEvents() -> [String] {
        let ms = DB.store.get([Double].self, "kf_bk_events") ?? []
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return ms.enumerated().reversed().prefix(12).map { i, t in
            "\(f.string(from: Date(timeIntervalSince1970: t / 1000))) · 备份事件 #\(i + 1)"
        }
    }
}

// ---------- UNUserNotificationCenter delegate 单例 (1018 通知点按 → 一键备份) ----------
final class UNDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = UNDelegate()
    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse,
                               completionHandler @escaping () -> Void) {
        if r.request.identifier == "kf.bk.monthly" {
            Task { @MainActor in
                BackupStudio.onMonthlyTap()
            }
        }
        completionHandler()
    }
}
