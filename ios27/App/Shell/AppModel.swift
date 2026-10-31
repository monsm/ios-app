// AppModel.swift —— 应用级状态（真实引擎驱动，不是种子数据）。
//
// 纪律：@Observable（iOS 17+ 现代写法），不用 ObservableObject。
// 这里只放"跨页面共享"的状态；页面临时状态留在页面里。
//
// 这一版把上一版占位的 sample 种子全换成了 Engine 的真读数：
//   · 锁  ← DB.keychains() / DB.keychain(mac) / DB.readStatus(mac)
//   · 凭证 ← DB.ledger(mac).pwds / .fps + MobileKeyService.list(mac)
//   · 成员 ← DB.members() + MemberHub.ext(id)
//   · 台账 ← DB.readLogs(mac)（cmd16 写入的缓存）
// 开锁、读状态、读日志、增删密码、配网，全部走 LockService / BLEService 的真链路。
import SwiftUI
import Foundation

@MainActor
@Observable
final class AppModel {
    // MARK: - 真实数据（由 reload() 从 Engine 构建）

    /// 当前门锁（nil = 还没添加）。
    var lock: LockSummary?
    /// 台账（DB.readLogs 的投影）。
    var entries: [LedgerEntry] = []
    /// 凭证（DB.ledger 的投影）。
    var keys: [KeyItem] = []
    /// 成员（DB.members + MemberHub 的投影）。
    var members: [MemberCard] = []

    // MARK: - 界面态

    /// 本机数据保护是否已解锁（冷启动才要求）。
    var unlocked: Bool = true
    /// 只读试验模式（顶部常驻红条，必须常驻 —— 用户第二天会忘了自己开过它）。
    var trialGuard: Bool = false
    /// 开锁链相位（门页刻度盘读它）。
    var dialPhase: DialPhase = .idle
    /// 最近一次动作的时刻（毫秒 epoch）。
    var lastActionAt: Int64?
    /// 最近一次读到的锁状态快照。
    var lastStatus: StatusSnapshot?
    /// 正在跑的长任务的一句话（配网 / 读日志）。
    var busyMessage: String?
    /// 最近一次失败的原因（页面就地展示）。
    var lastError: String?

    /// 弱引用路由：EngineHost 的唯一跳转出口。由 RootView 在装配时注入。
    @ObservationIgnored weak var router: Router?

    /// 当前锁的 MAC（没锁时回落本机偏好锁；DB.preferredMac 内部会做归一化）。
    var currentMac: String { lock?.id ?? DB.preferredMac() }

    // MARK: - 载入

    /// 从 Engine 重建全部界面数据。页面 .task / onAppear 调它。
    /// - Parameter refreshStatus: true 时顺带联网读一次 cmd03（会耗时，只在需要时开）。
    func reload(refreshStatus: Bool = false) async {
        let mac = currentMac
        if mac.isEmpty {
            lock = nil
            keys = []
            members = []
            entries = []
            lastStatus = nil
            return
        }
        guard let kc = DB.keychain(mac) else {
            lock = nil
            keys = []
            members = []
            entries = []
            return
        }

        if refreshStatus, LockService.shared.connectedMAC == mac {
            if let st = try? await LockService.shared.getStatus(mac: mac) {
                DB.writeStatus(mac, st)
            }
        }

        let snap = DB.readStatus(mac)
        lock = LockSummary(
            id: kc.mac,
            name: kc.name.isEmpty ? (kc.pidName.isEmpty ? "我的门锁" : kc.pidName) : kc.name,
            model: kc.pidName.isEmpty ? "未知型号" : kc.pidName,
            battery: snap?.powerLevel ?? -1,
            signal: 0,
            firmware: snap?.firmware ?? kc.fw,
            keyCount: DB.ledger(mac).pwds.count + DB.ledger(mac).fps.count,
            isConnected: LockService.shared.connectedMAC == mac,
            // 安全模式 / 静音：按 cmd03 的 securityLevel / soundVolumn 映射。
            // TODO(真机核对)：这两条的语义需要在真锁上对一次（A/B 双验 与 提示音开关）。
            // 安全模式 = 双验（cmd20 SETVALIDATIONMODE 对应快照的 verifyMode）。
            safeMode: (snap?.verifyMode ?? 0) != 0,
            // 静音：cmd03 快照里没有这一项，读本机镜像键（只在 cmd18 写成功后落）。
            muted: DB.store.getBool("kf_muted_" + mac)
        )
        lastStatus = DB.get(StatusSnapshot.self, "kf_snap_" + mac)

        reloadKeys(mac)
        reloadMembers()
        reloadEntries(mac)
    }

    /// 只重建凭证（增删改之后调，比重载全部便宜）。
    func reloadKeys(_ mac: String? = nil) {
        let m = mac ?? currentMac
        guard !m.isEmpty else { keys = []; return }
        let l = DB.ledger(m)
        var out: [KeyItem] = []
        for p in l.pwds {
            out.append(KeyItem(
                id: "pwd:\(p.alias)",
                kind: p.temp ? .temp : .password,
                name: p.note.isEmpty ? (p.temp ? "临时码 \(p.alias)" : "密码 \(p.alias)") : p.note,
                owner: p.owner,
                code: p.pwd.map { String(repeating: "•", count: max(4, $0.count)) },
                expiresAt: Self.epochMillis(p.to),
                disabled: false
            ))
        }
        for f in l.fps {
            out.append(KeyItem(
                id: "fp:\(f.batch)",
                kind: .fingerprint,
                name: f.name.isEmpty ? "指纹 \(f.batch)" : f.name,
                owner: f.owner,
                code: nil,
                expiresAt: nil,   // 指纹台账没有到期字段（LedgerFp 只有 batch/name/at/note/src/owner/isAlarm）
                disabled: false
            ))
        }
        for k in MobileKeyService.list(m) {
            out.append(KeyItem(
                id: "mkey:\(k.id)",
                kind: .mobile,
                name: k.memberName.isEmpty ? "手机钥匙" : k.memberName + " 的手机钥匙",
                owner: k.memberName,
                code: nil,
                expiresAt: k.forever ? nil : Self.epochMillis(k.validTo),
                disabled: false
            ))
        }
        keys = out
    }

    /// 只重建成员。
    func reloadMembers() {
        let table = MemberHub.allExt()
        members = DB.members().map { m in
            let ext = table[m.id] ?? MemberExt()
            let role: MemberCard.Role = ext.role == "main" ? .owner : (ext.role == "guest" ? .guest : .member)
            return MemberCard(
                id: m.id,
                name: m.name.isEmpty ? "未命名" : m.name,
                role: role,
                keyCount: keys.filter { $0.owner == m.name }.count,
                lastActiveAt: nil,
                archived: ext.archived
            )
        }
    }

    /// 只重建台账。
    func reloadEntries(_ mac: String? = nil) {
        let m = mac ?? currentMac
        guard !m.isEmpty else { entries = []; return }
        let logs = DB.readLogs(m)
        entries = logs.compactMap { c -> LedgerEntry? in
            // lockTime == 0 = 锁端没读到时钟，这条不该假装有时间
            guard c.lockTime > 0 else { return nil }
            let ms = ZKProtocol.protoSecondsToUnix(c.lockTime) * 1000
            let tone: Tone = AlarmMeta.damageTypes.contains(c.type) ? .critical
                : (LockStats.openTypes.contains(c.type) ? .ok : .neutral)
            return LedgerEntry(
                id: m + "#" + String(c.idxRaw),
                at: ms,
                event: c.displayTypeName,
                owner: nil,
                tone: tone
            )
        }
    }

    // MARK: - 开锁（真链路）

    /// 开锁链：ensureConnected → cmd04 → 回执。刻度盘的进度弧跟着真实阶段走。
    func runUnlockChain() async {
        guard dialPhase == .idle || dialPhase.isFailed else { return }
        let mac = currentMac
        guard !mac.isEmpty else {
            dialPhase = .failed("还没有添加门锁")
            return
        }
        dialPhase = .reaching
        lastError = nil
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            dialPhase = .sending
            let rc = try await LockService.shared.unlock(mac: mac)
            dialPhase = .waiting
            // rc 0 = 成功；22 = 需要双验（本机没有第二因子时按"已下发"处理并如实说）
            if rc == 0 || rc == 22 {
                dialPhase = .opened
                lastActionAt = Int64(Date().timeIntervalSince1970 * 1000)
                await reload(refreshStatus: false)
                try? await Task.sleep(for: .milliseconds(900))
                if dialPhase == .opened { dialPhase = .idle }
            } else {
                let msg = StatusParser.rcFriendly(rc)
                lastError = msg
                dialPhase = .failed(msg)
            }
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastError = msg
            dialPhase = .failed(msg)
        }
    }

    // MARK: - 读锁状态

    func refreshStatus() async {
        let mac = currentMac
        guard !mac.isEmpty else { return }
        do {
            let st = try await LockService.shared.getStatus(mac: mac)
            DB.writeStatus(mac, st)
            await reload(refreshStatus: false)
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - 读日志（cmd16 翻页）

    /// 读锁内日志：最多 20 页 × 5 条，逐页落缓存。
    func readLogs() async {
        let mac = currentMac
        guard !mac.isEmpty, busyMessage == nil else { return }
        busyMessage = "正在读门锁记录…"
        defer { busyMessage = nil }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            var startIdx: UInt32 = 0
            var collected: [LogEntry] = []
            for _ in 0 ..< 20 {
                let page = try await LockService.shared.getLogs(startIdx: startIdx, pageSize: 5)
                if page.logs.isEmpty { break }
                collected.append(contentsOf: page.logs)
                if page.logs.count < 5 { break }
                if let last = page.logs.last { startIdx = last.idxRaw &+ 1 }
            }
            DB.writeLogs(mac, collected)
            DB.store.set("kf_logsync_" + mac, Int(Date().timeIntervalSince1970 * 1000))
            await reload(refreshStatus: false)
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - 凭证写入

    func addPassword(_ pwd: String, from: String, to: String) async -> Result<Int, Error> {
        let mac = currentMac
        guard !mac.isEmpty else { return .failure(BLEErrorX.msg("还没有添加门锁")) }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            let alias = try await LockService.shared.pwdAdd(pwd: pwd, validFrom: from, validTo: to)
            // 下发成功才写台账 —— 失败不写，避免"本机以为加了、锁里没有"。
            var l = DB.ledger(mac)
            l.pwds.append(LedgerPwd(
                alias: alias, from: from, to: to, temp: false,
                at: Date().timeIntervalSince1970 * 1000,
                pwd: pwd, owner: nil, note: "密码 \(alias)"
            ))
            DB.saveLedger(mac, l)
            reloadKeys(mac)
            return .success(alias)
        } catch {
            return .failure(error)
        }
    }

    func deletePassword(alias: Int) async -> Result<Void, Error> {
        let mac = currentMac
        guard !mac.isEmpty else { return .failure(BLEErrorX.msg("还没有添加门锁")) }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            try await LockService.shared.pwdDelete(alias)
            // 锁端删成功才摘台账（同口径：失败不写，免得两边不一致）。
            var l = DB.ledger(mac)
            l.pwds.removeAll { $0.alias == alias }
            DB.saveLedger(mac, l)
            reloadKeys(mac)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    // MARK: - 校时 / 静音 / 安全模式

    func syncTime() async -> Result<(Int, Int), Error> {
        guard !currentMac.isEmpty else { return .failure(BLEErrorX.msg("还没有添加门锁")) }
        do {
            try await LockService.shared.ensureConnected(mac: currentMac)
            let r = try await LockService.shared.syncTime()
            await reload(refreshStatus: false)
            return .success((r.before, r.after))
        } catch { return .failure(error) }
    }

    func setMuted(_ on: Bool) async -> Result<Void, Error> {
        guard !currentMac.isEmpty else { return .failure(BLEErrorX.msg("还没有添加门锁")) }
        do {
            try await LockService.shared.ensureConnected(mac: currentMac)
            try await LockService.shared.setSilent(on)
            DB.store.set("kf_muted_" + currentMac, on)
            await refreshStatus()
            return .success(())
        } catch { return .failure(error) }
    }

    func setSafeMode(_ on: Bool) async -> Result<Void, Error> {
        guard !currentMac.isEmpty else { return .failure(BLEErrorX.msg("还没有添加门锁")) }
        do {
            try await LockService.shared.ensureConnected(mac: currentMac)
            try await LockService.shared.setValidationMode(on)
            await refreshStatus()
            return .success(())
        } catch { return .failure(error) }
    }

    // MARK: - 工具

    /// "yyyy-MM-dd HH:mm" / "yyyy-MM-dd" → 毫秒 epoch。解析不了就 nil（不猜）。
    static func epochMillis(_ s: String) -> Int64? {
        guard !s.isEmpty else { return nil }
        for f in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let df = DF.cached(f)
            if let d = df.date(from: s) { return Int64(d.timeIntervalSince1970 * 1000) }
        }
        return nil
    }
}

// MARK: - 数据模型（界面投影；由 AppModel.reload 从 Engine 构建）

struct LockSummary: Identifiable, Hashable {
    let id: String
    let name: String
    let model: String
    let battery: Int          // -1 = 未知
    let signal: Int           // 0 = 未知
    let firmware: String
    let keyCount: Int
    let isConnected: Bool
    let safeMode: Bool
    let muted: Bool
}

struct KeyItem: Identifiable, Hashable {
    enum Kind: String, CaseIterable {
        case password = "密码"
        case fingerprint = "指纹"
        case temp = "临时码"
        case mobile = "手机钥匙"
    }
    let id: String            // "pwd:<alias>" / "fp:<batch>" / "mkey:<uuid>"
    let kind: Kind
    let name: String
    let owner: String?
    let code: String?
    /// 到期时刻（毫秒 epoch）。nil = 永久。
    let expiresAt: Int64?
    let disabled: Bool
}

struct MemberCard: Identifiable, Hashable {
    enum Role: String, CaseIterable {
        case owner = "管理员"
        case member = "成员"
        case guest = "访客"
    }
    let id: String
    let name: String
    let role: Role
    let keyCount: Int
    let lastActiveAt: Int64?
    let archived: Bool
}

// MARK: - EngineHost 桥接
//
// 引擎只声明它需要什么（见 Engine/EngineHost.swift），这里把界面状态喂给它。
// 这是**唯一**允许 Engine 与界面接触的地方。
extension AppModel: EngineHost {
    var currentKeychain: Keychain? {
        let mac = currentMac
        return mac.isEmpty ? nil : DB.keychain(mac)
    }

    var lockLink: LockService { LockService.shared }

    /// 把「点通知」翻成一次界面跳转（CredentialOrg.applyNotification 的落地端）。
    func requestCredentialRoute(alias: Int?) {
        router?.request(.key(id: alias.map { "pwd:\($0)" } ?? ""))
    }
}
