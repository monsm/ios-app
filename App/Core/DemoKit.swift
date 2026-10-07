// ================= 演练与演示数据 (功能包14: 836/837/844/845) =================
// 纪律: 演示/演练数据必须全路径可辨识 — "demo_" 前缀 + 全局横幅 + 一键清除,
// 严禁与真实台账混淆; 演示模式不碰 BLE/协议, 所有开锁/下发走本地模拟结果。
import SwiftUI

enum DemoKit {
    // ---------- 键位 (新 kf_ 键, 全部向后兼容: 旧版本读到默认值即无演示数据) ----------
    static let kMode = "kf_demo_mode"                 // 836 演示模式总开关
    static let kDrillFilter = "kf_demo_drillfilter"   // 839 示例过滤器 (记录页"示例筛选")
    static let kDrillDemoOn = "kf_demo_drill_on"      // 842 演练备份标记
    static let kDemoLogsActive = "kf_demo_logs_active" // 845 7 天样例已写入
    static let demoMac = "DEMOA1B2C3D4E5"
    static let demoMemberName = "演示家人"

    static var isOn: Bool { DB.store.getBool(kMode) }

    /// 开: 安装演示锁 + 演示成员 + 铺满台账; 关: 一键清除全部演示数据 (836)
    @MainActor
    static func setOn(_ on: Bool) {
        DB.store.set(kMode, on)
        if on { installDemoLock() } else { clearAll() }
        DB.store.set("kf_demo_clear_cleared", false)
        DB.store.set("kf_demo_drillfilter", false)
    }

    /// 演示锁档案: 名字与 MAC 全部带 demo_ 标识, 任何列表里一眼可辨
    @MainActor
    static func demoDevice() -> Keychain {
        Keychain(mac: demoMac, pid: PidMap.KX, pidName: "KX", name: "演示门锁",
                 skey: "demo_skey", fw: "2.3.0-demo", pairedAt: Date().timeIntervalSince1970 * 1000)
    }
    /// 演示成员 + 台账铺底: 临时码/指纹条目备注全部 "demo_" 前缀
    @MainActor
    static func demoLedger() -> Ledger {
        let demoOwner = DB.members().first { $0.name == demoMemberName }?.id ?? ""
        let p = LedgerPwd(alias: 1, from: "", to: "", temp: false,
                          at: Date().timeIntervalSince1970 * 1000, pwd: nil,
                          owner: demoOwner.isEmpty ? nil : demoOwner,
                          note: "demo_演示临时码")
        let f = LedgerFp(batch: 1, name: "演示指纹",
                         at: Date().timeIntervalSince1970 * 1000, note: "demo_演示指纹")
        return Ledger(pwds: [p], fps: [f])
    }
    @MainActor
    private static func installDemoLock() {
        if DB.keychain(demoMac) == nil { DB.saveKeychain(demoDevice()) }
        if !DB.members().contains(where: { $0.name == demoMemberName }) {
            DB.addMember(demoMemberName)
        }
        var l = DB.ledger(demoMac)
        if !l.pwds.contains(where: { $0.note.hasPrefix("demo_") }) {
            l.pwds.append(contentsOf: demoLedger().pwds)
            l.fps.append(contentsOf: demoLedger().fps)
            DB.saveLedger(demoMac, l)
        }
        if DB.readStatus(demoMac) == nil { DB.writeStatus(demoMac, LockStatus()) }
        if !DB.store.getBool(kDemoLogsActive) { clearDemoLogs() }
    }
    /// 一键清除: 只删演示数据, 不碰任何真实台账
    @MainActor
    static func clearAll() {
        DB.removeDevice(demoMac)
        if let m = DB.members().first(where: { $0.name == demoMemberName }) {
            DB.removeMember(m.id)
        }
        clearDemoLogs()
        DB.store.remove(kDrillFilter)
    }

    // ---------- 845 七天样例生成器: 7 天合理假开门记录, demo_ 前缀隔离 ----------
    @MainActor
    static var demoLogsActive: Bool { DB.store.getBool(kDemoLogsActive) }
    @MainActor
    static func demoLogsCount() -> Int {
        DB.readLogs(demoMac).filter { $0.typeName.hasPrefix("demo_") }.count
    }
    @MainActor
    static func clearDemoLogs() {
        DB.writeLogs(demoMac, DB.readLogs(demoMac).filter { !$0.typeName.hasPrefix("demo_") })
        DB.store.remove(kDemoLogsActive)
        DB.store.set("kf_demo_clear_cleared", true)   // 记录页 @State 观察此键重渲
    }
    @MainActor
    static func generateSevenDaySamples() {
        installDemoLock()
        var out = DB.readLogs(demoMac).filter { !$0.typeName.hasPrefix("demo_") }
        for d in 0..<7 {
            let day = Calendar.current.date(byAdding: .day, value: -d, to: Date())!
            let types: [(Int, String)] = [(1, "demo_家人开门"), (3, "demo_指纹开门")]
                + (d == 2 ? [(7, "demo_试错告警")] : [])
            for (i, t) in types.enumerated() {
                var c = Calendar.current.dateComponents([.year, .month, .day], from: day)
                c.hour = d == 0 ? 8 : 7
                c.minute = 8 + i * 9
                c.second = 12 + d
                guard let date = Calendar.current.date(from: c) else { continue }
                out.append(CachedLog(type: t.0, typeName: t.1,
                                     idxRaw: 0xD0000000 | UInt32(d) &* 0x100 | UInt32(i),
                                     lockTime: Int64(date.timeIntervalSince1970 * 1000),
                                     lockTimeStr: Self.demoStamp(date)))
            }
        }
        DB.writeLogs(demoMac, out)
        DB.store.set(kDemoLogsActive, true)
        DB.store.set("kf_demo_clear_cleared", false)
    }
    private static let demoStampF: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone.current
        return f
    }()
    private static func demoStamp(_ d: Date) -> String { demoStampF.string(from: d) }

    /// 839 示例过滤器: "示例筛选" — 记录页叠加 demo_ 样例行, 删除即恢复净空
    @MainActor
    static func setDrillFilter(_ on: Bool) {
        DB.store.set(kDrillFilter, on)
        if on {
            installDemoLock()
            if !DB.store.getBool(kDemoLogsActive) { generateSevenDaySamples() }
        } else {
            clearDemoLogs()
        }
    }
    @MainActor
    static func clearDrillFilter() {
        DB.store.remove(kDrillFilter)
        clearDemoLogs()
    }

    /// 842 演练备份: 首次备份标"演练" — 导入样例后立起标记, 转正式时摘除
    @MainActor
    static var drillBackupOn: Bool { DB.store.getBool(kDrillDemoOn) }
    @MainActor
    static func finishDrillBackup() { DB.store.remove(kDrillDemoOn) }

    /// 837 样例备份包: 内置合法备份文本, 走完整导入体验; 设备/成员/备注全部 demo_ 前缀
    @MainActor
    static func sampleBackupText() -> String {
        let kc = demoDevice()
        var l = demoLedger()
        let demoOwner = DB.members().first { $0.name == demoMemberName }?.id ?? ""
        for i in l.pwds.indices { l.pwds[i].owner = demoOwner.isEmpty ? nil : demoOwner }
        let b = BackupBundle(at: ISO8601DateFormatter().string(from: Date()),
                             devices: [.init(mac: demoMac, kc: kc, ledger: l, meta: .init())],
                             members: nil, globals: nil)
        guard let data = try? JSONEncoder().encode(b),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    /// 演示开锁: 本地走一遍"握手→鉴权→执行"三阶段, 不写失败日志、不碰 BLE (836 包装层)
    @MainActor
    static func simulateDemoUnlock(phase: @escaping (Int) -> Void,
                                   onDone: @escaping () -> Void) {
        Task { @MainActor in
            for p in [1, 2, 3] {
                phase(p)
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onDone()
        }
    }
}

/// 演示模式常驻横幅 (836): 四 Tab 顶部, 可一键清除演示数据
struct DemoBanner: View {
    @EnvironmentObject var app: AppState
    @State private var cleared = DB.store.getBool("kf_demo_clear_cleared")
    var onCleared: () -> Void = {}

    var body: some View {
        if DemoKit.isOn || DB.store.getBool(DemoKit.kDemoLogsActive) {
            Label {
                HStack(spacing: DS.Space.xs) {
                    Text("演示模式 · 数据全部为 demo_ 样例, 不碰真实门锁")
                    Spacer(minLength: 0)
                    Button("清除演示数据") {
                        DemoKit.setOn(false)
                        cleared = true
                        onCleared()
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DS.Palette.danger)
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
            } icon: {
                Image(systemName: "theatermasks.fill").accessibilityHidden(true)
            }
            .font(.caption)
            .foregroundStyle(DS.Palette.warn)
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.s)
            .background(DS.Palette.surface)
        }
    }
}
