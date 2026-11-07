// HealthCheck.swift —— 健康检查（B71）、链路质量历史（B70）、时间漂移（B74）、看门狗（B72）。
//
// 这一族回答的都是同一个问题：「**现在这台 App 对这把锁的状态，是清楚的还是糊涂的？**」
//
//   · 健康检查：一项一项查（蓝牙 / 钥匙串 / 台账 / 日志 / 备份 / 通知 / 权限 / 锁钟），
//     每项给 pass/warn/fail 与一个修复入口 —— 诊断页不再只是「读数」，它能指路。
//   · 链路质量：断链几次、连上几次、信号均值 —— 「老是连不上」要能拿出证据。
//   · 时间漂移：锁钟与手机钟的偏差趋势 —— 偏差是很多失败（rc=3/9/13）的共同上游。
//   · 看门狗：命令卡住、waiter 泄漏、重连风暴 —— 自愈不了就至少别一直卡着。
import Foundation

// MARK: - 链路质量（B70）

enum LinkQuality {
    struct Snapshot: Codable, Equatable {
        /// 属于哪把锁（落盘是数组，要自己带身份）。
        var mac: String = ""
        var connects = 0
        var disconnects = 0
        var failures = 0
        var rssiSum = 0
        var rssiCount = 0
        var lastAt: Double = 0
        /// 最近一次失败的原因（脱敏后的一句话）。
        var lastFailure: String = ""

        var averageRSSI: Int? {
            rssiCount > 0 ? rssiSum / rssiCount : nil
        }

        /// 失败率（0…1）。分母太小的时候不可信。
        var failureRate: Double {
            let total = connects + failures
            guard total >= 3 else { return 0 }
            return Double(failures) / Double(total)
        }
    }

    /// 落盘是**数组**（`DiagLogStore.writeJSON` 只收数组；字典得自己包一层）。
    private static let store = Locked([Snapshot]())
    private static let fileName = "kf_link_quality.json"

    private static func mutate(_ mac: String, _ body: (inout Snapshot) -> Void) {
        guard !mac.isEmpty else { return }
        var list = store.withLock { $0 }
        if let idx = list.firstIndex(where: { $0.mac == mac }) {
            body(&list[idx])
        } else {
            var s = Snapshot()
            s.mac = mac
            body(&s)
            list.append(s)
        }
        store.withLock { $0 = list }
        DiagLogStore.writeJSON(list, name: fileName)
    }

    static func noteConnect(_ mac: String) {
        mutate(mac) { $0.connects += 1; $0.lastAt = Date().timeIntervalSince1970 }
    }

    static func noteDisconnect(_ mac: String) {
        mutate(mac) { $0.disconnects += 1; $0.lastAt = Date().timeIntervalSince1970 }
    }

    static func noteFailure(_ mac: String, _ why: String) {
        mutate(mac) {
            $0.failures += 1
            $0.lastAt = Date().timeIntervalSince1970
            $0.lastFailure = why
        }
    }

    static func noteRSSI(_ mac: String, _ rssi: Int) {
        mutate(mac) { $0.rssiSum += rssi; $0.rssiCount += 1 }
    }

    static func snapshot(_ mac: String) -> Snapshot {
        let list = store.withLock { $0 }
        if let hit = list.first(where: { $0.mac == mac }) { return hit }
        let disk = DiagLogStore.readJSON([Snapshot].self, name: fileName)
        return disk.first(where: { $0.mac == mac }) ?? Snapshot()
    }

    /// 人话摘要（诊断页用）。
    static func summary(_ mac: String) -> String {
        let s = snapshot(mac)
        var parts: [String] = []
        parts.append("连上 \(s.connects) 次")
        parts.append("断链 \(s.disconnects) 次")
        parts.append("失败 \(s.failures) 次")
        if let a = s.averageRSSI { parts.append("平均信号 \(a) dBm") }
        if s.failureRate > 0.34 { parts.append("失败率偏高（\(Int(s.failureRate * 100))%）") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - 时间漂移（B74）

enum ClockDrift {
    /// 偏差超过这个秒数就算「漂了」（协议侧 60 秒是分水岭）。
    static let warnSeconds = 60
    /// 历史样本保留条数。
    static let sampleCap = 20

    /// 锁钟 − 手机钟（秒）。没有锁钟读数时 nil。
    static func driftSeconds(mac: String) -> Int? {
        // `snap.lockTime` 是非可选的 Int64 —— 在 guard 的条件列表里写 `let lockTime = snap.lockTime`
        // 会被判成「对非可选值做条件绑定」而编译失败。
        guard let snap = DB.readStatus(mac), snap.lockTime > 0 else { return nil }
        let now = ZKProtocol.nowProtoSeconds()
        return Int(snap.lockTime - now)
    }

    /// 人话摘要。
    static func summary(mac: String) -> String {
        guard let d = driftSeconds(mac: mac) else { return "还没读到锁钟" }
        if abs(d) <= warnSeconds { return "锁钟与手机基本一致（差 \(d) 秒）" }
        return d > 0
            ? "锁钟比手机快 \(d) 秒 —— 时间敏感的凭证会判为「未生效」"
            : "锁钟比手机慢 \(-d) 秒 —— 时间敏感的凭证会判为「已过期」"
    }

    /// 记一次偏差（趋势用）。
    static func note(mac: String) {
        guard let d = driftSeconds(mac: mac) else { return }
        table.withLock { t in
            var list = t[mac] ?? []
            list.append(d)
            if list.count > sampleCap { list = Array(list.suffix(sampleCap)) }
            t[mac] = list
        }
    }

    /// 最近的偏差样本。
    static func samples(_ mac: String) -> [Int] {
        table.withLock { $0[mac] ?? [] }
    }

    /// 是否在持续漂移（最近三次同向且越来越大）。
    static func isDrifting(mac: String) -> Bool {
        let list = samples(mac)
        guard list.count >= 3 else { return false }
        let last = list.suffix(3)
        guard last.allSatisfy({ $0 != 0 }) else { return false }
        let sameSign = last.allSatisfy { ($0 > 0) == (last.first! > 0) }
        return sameSign && abs(last.last!) > warnSeconds
    }

    /// 每把锁的偏差样本。
    private static let table = Locked([String: [Int]]())
}

// MARK: - 看门狗（B72）

@MainActor
enum Watchdog {
    /// 一条命令在飞的最长时间（秒）。超过就当它卡住了。
    static let stuckCommandSeconds: Double = 25
    /// 检查周期。
    static let intervalSeconds: Double = 5

    private static var task: Task<Void, Never>?
    private static var waiterSince: Date?

    static func start() {
        guard task == nil else { return }
        task = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(intervalSeconds))
                if Task.isCancelled { break }
                check()
            }
        }
    }

    static func stop() {
        task?.cancel()
        task = nil
        waiterSince = nil
    }

    /// 检查一次。放在主线程（要读 LockService 的状态）。
    static func check() {
        let svc = LockService.shared
        if svc.waiter != nil {
            if waiterSince == nil { waiterSince = Date() }
            if let since = waiterSince, Date().timeIntervalSince(since) > stuckCommandSeconds {
                DiagLogs.append("warn", "看门狗：命令等待超过 \(Int(stuckCommandSeconds)) 秒仍未收到回执，已强制收尾",
                                date: DiagLogs.localDay(), time: DiagTime.hhmmss())
                svc.rejectWaiter("看门狗：等待超时，已放弃本次命令")
                waiterSince = nil
            }
        } else {
            waiterSince = nil
        }
        // 重连风暴：短时间内反复连接失败 —— 记一笔，别让用户以为是偶发。
        if svc.connectedMAC.isEmpty, !svc.connectingMac.isEmpty {
            DiagLogs.append("info", "看门狗：正在重建链路（\(svc.connectingMac)）",
                            date: DiagLogs.localDay(), time: DiagTime.hhmmss())
        }
    }
}

// MARK: - 健康检查（B71）

enum HealthCheck {
    enum Status: Int, Comparable {
        case ok = 0
        case warn = 1
        case fail = 2

        static func < (a: Status, b: Status) -> Bool { a.rawValue < b.rawValue }
    }

    struct Item: Identifiable, Equatable {
        var id: String
        var name: String
        var status: Status
        var detail: String
        /// 修复入口的名字（界面据此决定给不给按钮）。
        var fix: String?
    }

    struct Report: Equatable {
        var items: [Item] = []
        var worst: Status = .ok
        var at: Double = Date().timeIntervalSince1970

        var okCount: Int { items.filter { $0.status == .ok }.count }
        var warnCount: Int { items.filter { $0.status == .warn }.count }
        var failCount: Int { items.filter { $0.status == .fail }.count }

        var summary: String {
            if items.isEmpty { return "还没有检查过" }
            if worst == .ok { return "一切正常（\(items.count) 项全过）" }
            var parts: [String] = []
            if failCount > 0 { parts.append("\(failCount) 项异常") }
            if warnCount > 0 { parts.append("\(warnCount) 项要注意") }
            return parts.joined(separator: "，")
        }
    }

    /// 跑一遍检查。
    static func run(mac: String?) -> Report {
        var items: [Item] = []

        // 蓝牙
        let btOn = BLEService.shared.isPoweredOn
        items.append(Item(id: "bluetooth", name: "蓝牙",
                          status: btOn ? .ok : .fail,
                          detail: btOn ? "已开启" : "未开启 —— 连不上门锁",
                          fix: btOn ? nil : "去系统设置"))

        // 钥匙串
        let kcs = DB.keychains()
        items.append(Item(id: "keychain", name: "门锁档案",
                          status: kcs.isEmpty ? .warn : .ok,
                          detail: kcs.isEmpty ? "还没有配对任何门锁" : "已配对 \(kcs.count) 把",
                          fix: kcs.isEmpty ? "去配对" : nil))

        // 台账
        if let mac, DB.isLedgerCorrupt(mac) {
            items.append(Item(id: "ledger", name: "凭证台账",
                              status: .fail,
                              detail: "台账读取异常，写入门锁的动作已被拒绝",
                              fix: "去备份与恢复"))
        } else {
            items.append(Item(id: "ledger", name: "凭证台账", status: .ok, detail: "正常", fix: nil))
        }

        // 日志与读数
        if let mac {
            let age = DB.statusAge(mac)
            if let age {
                let stale = age > DB.statusTTLms
                items.append(Item(id: "logs", name: "锁端读数",
                                  status: stale ? .warn : .ok,
                                  detail: stale ? "已经 \(When.ago(Int64(Date().timeIntervalSince1970 * 1000 - age)))没更新" : "是新的",
                                  fix: stale ? "读一次" : nil))
            } else {
                items.append(Item(id: "logs", name: "锁端读数", status: .warn, detail: "还没读到过", fix: "读一次"))
            }
            // 锁钟
            let drift = ClockDrift.driftSeconds(mac: mac)
            if let d = drift {
                items.append(Item(id: "clock", name: "锁钟",
                                  status: abs(d) <= ClockDrift.warnSeconds ? .ok : .warn,
                                  detail: ClockDrift.summary(mac: mac),
                                  fix: abs(d) <= ClockDrift.warnSeconds ? nil : "去校时"))
            } else {
                items.append(Item(id: "clock", name: "锁钟", status: .warn, detail: "还没读到锁钟", fix: nil))
            }
            // 链路质量
            let q = LinkQuality.snapshot(mac)
            let bad = q.failureRate > 0.34
            items.append(Item(id: "link", name: "链路质量",
                              status: bad ? .warn : .ok,
                              detail: LinkQuality.summary(mac),
                              fix: bad ? "看诊断" : nil))
        } else {
            items.append(Item(id: "logs", name: "锁端读数", status: .warn, detail: "没有选中的门锁", fix: nil))
        }

        // 备份
        let lastBackup = Milestones.lastBackupAt
        let backupAge = lastBackup.map { Date().timeIntervalSince($0) } ?? Double.infinity
        let backupFresh = backupAge < 7 * 86400
        items.append(Item(id: "backup", name: "备份",
                          status: backupFresh ? .ok : .warn,
                          detail: lastBackup == nil ? "还没有备份过" : "上次备份 \(When.ago(Int64(lastBackup!.timeIntervalSince1970 * 1000)))",
                          fix: backupFresh ? nil : "去备份"))

        // 通知
        let notify = NotificationStatus.current
        let notified = notify == .authorized
        items.append(Item(id: "notification", name: "通知",
                          status: notified ? .ok : .warn,
                          detail: notified
                              ? "已授权，到期与低电提醒会送达"
                              : "\(notify.label) —— 到期提醒收不到",
                          fix: notified ? nil : "去开启"))

        // 能力边界
        if let mac {
            let caps = CapabilityResolver.resolve(mac: mac)
            if caps.unknownModel {
                items.append(Item(id: "capability", name: "型号",
                                  status: .warn,
                                  detail: caps.caveat ?? "这把锁的型号还没收录",
                                  fix: nil))
            }
        }

        var r = Report(items: items)
        r.worst = items.map(\.status).max() ?? .ok
        return r
    }
}
