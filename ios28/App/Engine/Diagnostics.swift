// Diagnostics.swift —— 本地崩溃记录（B67）与诊断包（B68）。
//
// 这一族解决的是同一个困境：这个 App **没有服务器、也不上传任何东西**，
// 于是用户报障时能给的只有一句「打不开了」。没有证据，开发者只能猜。
//
// 现在做两件都在本地完成的事：
//   · **崩溃记录**（B67）：靠「上次运行时留的心跳标记」判断上一次是不是异常退出，
//     记下时间与当时在做哪一步。不采集任何用户数据。
//   · **诊断包**（B68）：一键把设备、权限、链路质量、健康检查、命令时间线
//     打成一个文本，用户自己决定发给谁（分享面板）。**全部脱敏**。
import Foundation
import UIKit

// MARK: - 崩溃记录（B67）

enum CrashLog {
    /// 运行心跳：App 正常退出时删掉，下次启动还在 ⇒ 上次是异常退出。
    private static let heartbeatKey = "kf_run_heartbeat"
    private static let crashKey = "kf_crash_records"

    struct Record: Codable, Identifiable, Equatable {
        var id: String { at }
        /// epoch 毫秒
        var at: Double
        /// 上次退出前记录的「正在做什么」。
        var stage: String
        /// 上次运行持续了多久（秒）。
        var duration: Double
    }

    /// 启动时调用：检查上一次是不是异常退出。
    @discardableResult
    static func markLaunch() -> Bool {
        let prevStage = DB.store.getString(heartbeatKey + "_stage")
        let prevAt = DB.store.getDouble(heartbeatKey + "_at", 0)
        let crashed = prevAt > 0
        if crashed {
            var list = records()
            list.insert(Record(at: prevAt, stage: prevStage.isEmpty ? "未知" : prevStage,
                                duration: Date().timeIntervalSince1970 - prevAt), at: 0)
            if list.count > 20 { list = Array(list.prefix(20)) }
            DB.store.setCodable(crashKey, list)
        }
        // 写下本次的心跳。
        DB.store.set(heartbeatKey + "_stage", "启动中")
        DB.store.setDouble(heartbeatKey + "_at", Date().timeIntervalSince1970)
        return crashed
    }

    /// 记录「当前在做什么」（异常退出时诊断包会带上它）。
    static func stage(_ text: String) {
        DB.store.set(heartbeatKey + "_stage", text)
        DB.store.setDouble(heartbeatKey + "_at", Date().timeIntervalSince1970)
    }

    /// 正常退出时调用（删掉心跳）。
    static func markCleanExit() {
        DB.store.remove(heartbeatKey + "_stage")
        DB.store.remove(heartbeatKey + "_at")
    }

    static func records() -> [Record] {
        DB.store.get([Record].self, crashKey) ?? []
    }

    static func clear() {
        DB.store.remove(crashKey)
    }

    static func summary() -> String {
        let list = records()
        if list.isEmpty { return "没有异常退出记录" }
        let last = list[0]
        return "上次异常退出：\(DiagTime.mmddHHmm())（当时在做「\(last.stage)」）"
    }
}

// MARK: - 诊断包（B68）

enum DiagnosticBundle {
    /// 打一份纯文本诊断包。**不含任何凭据**：
    /// 帧只有帧头与 KLV 骨架（FrameRedact 的口径），台账只有条数。
    static func build(mac: String?) -> String {
        var lines: [String] = []
        func add(_ s: String) { lines.append(s) }

        add("阈值 · 诊断包")
        add("生成时间：\(DiagTime.full())")
        add("App 版本：\(appVersion())")
        add("系统：\(systemInfo())")
        add("")

        add("—— 门锁 ——")
        if let mac {
            let kc = DB.keychain(mac)
            add("当前锁：\(kc.map { LockArchive.displayName($0) } ?? mac)")
            add("型号：\(kc.map { PidMap.modelName($0.pid) } ?? "未知")")
            let caps = CapabilityResolver.resolve(mac: mac)
            add("能力边界：\(caps.caveat ?? "已收录型号")")
            let snap = DB.readStatus(mac)
            add("电量：\(snap.map { String($0.powerLevel) } ?? "—")")
            add("固件：\(snap?.firmware ?? "—")")
            add("锁钟：\(snap.map { ProtoTime.localStr($0.lockTime) } ?? "—")")
            add("锁钟偏差：\(ClockDrift.summary(mac: mac))")
            add("链路质量：\(LinkQuality.summary(mac))")
            let ledger = DB.ledger(mac)
            add("台账：密码 \(ledger.pwds.count) 枚 / 指纹 \(ledger.fps.count) 枚")
            add("缓存日志：\(DB.readLogCount(mac)) 条")
        } else {
            add("当前锁：（无）")
        }
        add("")

        add("—— 蓝牙与权限 ——")
        add("蓝牙状态：\(BLEService.shared.isPoweredOn ? "已开启" : "未开启")")
        add("通知授权：\(NotificationStatus.current.label)")
        add("本机密码：\(DB.hasPasscode() ? "已设置" : "未设置")")
        add("胁迫码：\(DB.hasDuressCode() ? "已设置" : "未设置")")
        add("只读试验：\(DB.store.getBool("kf_trial_guard", false) ? "开启" : "关闭")")
        add("")

        add("—— 健康检查 ——")
        let report = HealthCheck.run(mac: mac)
        for item in report.items {
            let mark = item.status == .ok ? "✓" : (item.status == .warn ? "!" : "×")
            add("\(mark) \(item.name)：\(item.detail)")
        }
        add("")

        add("—— 最近命令 ——")
        add(CommandTimeline.exportText())
        add("")

        add("—— 异常退出 ——")
        add(CrashLog.summary())
        add("")

        add("—— 性能 ——")
        let over = PerfBudget.recentOverruns
        if over.isEmpty {
            add("没有超出预算的记录")
        } else {
            for o in over.prefix(20) {
                add("\(DiagTime.mmddHHmm()) \(o.name)：\(Int(o.took * 1000))ms（预算 \(Int(o.budget * 1000))ms）")
            }
        }
        add("")

        add("—— 启动里程碑 ——")
        for m in Startup.marks {
            add("\(m.name)：\(Int(m.elapsed * 1000))ms")
        }
        return lines.joined(separator: "\n")
    }

    /// 存成文件（分享面板用）。
    static func writeFile(mac: String?) -> URL? {
        let text = build(mac: mac)
        let name = "threshold-diag-\(DiagTime.mmddHHmm().replacingOccurrences(of: ":", with: "")).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    static func appVersion() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    static func systemInfo() -> String {
        let device = UIDevice.current
        return "\(device.systemName) \(device.systemVersion) · \(device.model)"
    }
}
