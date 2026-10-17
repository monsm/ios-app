// ================= 演练与演示数据 (功能包14: 836/837/844/845) =================
// 纪律: 演示/演练数据必须全路径可辨识 — "demo_" 前缀 + 全局横幅 + 一键清除,
// 严禁与真实台账混淆; 演示模式不碰 BLE/协议, 所有开锁/下发走本地模拟结果。
import SwiftUI

enum DemoKit {
    // ---------- 键位 (新 kf_ 键, 全部向后兼容: 旧版本读到默认值即无演示数据) ----------
    static let kMode = "kf_demo_mode"                 // 836 演示模式总开关
    static let kDrillFilter = "kf_demo_drillfilter"   // 839 示例过滤 — **已判 PART 删档**: 全仓零读取方，仅留常量给 clearAll 兜底清键 (详见下方 839 注)
    static let kDrillDemoOn = "kf_demo_drill_on"      // 842 演练备份标记
    static let kDemoLogsActive = "kf_demo_logs_active" // 845 7 天样例已写入
    // 演示锁 MAC 必须是**合法 12 位小写 hex**: 旧值 "DEMOA1B2C3D4E5" 含非 hex 字母且 14 字符,
    // 被 HexKit.bytes 解析成 7 字节垃圾, 且与全库 normalizeMac(小写) 的键序不一致 (kf_* 键大小写错位)。
    static let demoMac = "dea1b2c3d4e5"
    static let demoMemberName = "演示家人"

    static var isOn: Bool { DB.store.getBool(kMode) }

    /// 开: 安装演示锁 + 演示成员 + 铺满台账; 关: 一键清除全部演示数据 (836)
    @MainActor
    static func setOn(_ on: Bool) {
        DB.store.set(kMode, on)
        if on { installDemoLock() } else { clearAll() }
        DB.store.set("kf_demo_drillfilter", false)   // 键口径：839 已判 PART 删档 (开关与读取方一起删掉)，这里只清老版本残留
    }

    /// 演示锁档案: 名字与 MAC 全部带 demo_ 标识, 任何列表里一眼可辨
    @MainActor
    static func demoDevice() -> Keychain {
        // 真实锁 pairedAt = ISO8601 文本 (LockService:498); demo 锁同口径, 防 1010 结缘日解析误读
        let iso = ISO8601DateFormatter().string(from: Date())
        return Keychain(mac: demoMac, pid: PidMap.KX, pidName: "KX", name: "演示门锁",
                        skey: "demo_skey", fw: "2.3.0-demo", pairedAt: iso)
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
        // 一次性清理旧版大写非 hex demoMac 的遗留条目 (值曾为 "DEMOA1B2C3D4E5"):
        // 否则设备列表会同时出现新旧两把演示锁。removeDevice 的"含本锁 MAC 即属该锁数据族"兜底可清掉大小写两套键。
        if DB.keychain("DEMOA1B2C3D4E5") != nil { DB.removeDevice("DEMOA1B2C3D4E5") }
        if DB.keychain(demoMac) == nil { DB.saveKeychain(demoDevice()) }
        if !DB.members().contains(where: { $0.name == demoMemberName }) {
            _ = DB.addMember(demoMemberName)
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
        // 2026-10-13 对抗式点击审计: 补一句取消在飞的演示开锁任务。原实现在这里只清数据,
        // 而 simulateDemoUnlock 的 Task 是 0.7~2.1s 的三段式 —— 用户点"清除演示数据"后
        // 旧任务的回调继续跑, 把 unlockState 置成 .success 并弹"演示开锁成功" (数据已经删了还在报成功)。
        demoUnlockTask?.cancel()
        demoUnlockTask = nil
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
        // 演示锁已经不在了 (clearAll 先 removeDevice, 再调本函数) ⇒ **不能**走 replaceLogs:
        // 那条路会为一把不存在的锁重建一个空缓存, 于是体检里永远挂着
        // "已删门锁 dea1b2 的日志缓存残留 (0 条)" (真机报告 2026-10-17 抓到 —— clearAll 的顺序就是成因)。
        // 这种时候要的是把键彻底拿掉, 而不是写一份"空"进去。
        guard DB.keychain(demoMac) != nil else {
            DB.store.remove("kf_logcache_" + demoMac)
            DB.store.remove(kDemoLogsActive)
            return
        }
        DB.replaceLogs(demoMac, DB.readLogs(demoMac).filter { !$0.typeName.hasPrefix("demo_") })
        DB.store.remove(kDemoLogsActive)
    }
    @MainActor
    static func generateSevenDaySamples() {
        installDemoLock()
        var out = DB.readLogs(demoMac).filter { !$0.typeName.hasPrefix("demo_") }
        for d in 0..<7 {
            let day = WeekCal.gregorian.date(byAdding: .day, value: -d, to: Date())!
            let types: [(Int, String)] = [(1, "demo_家人开门"), (3, "demo_指纹开门")]
                + (d == 2 ? [(7, "demo_试错告警")] : [])
            for (i, t) in types.enumerated() {
                var c = WeekCal.gregorian.dateComponents([.year, .month, .day], from: day)
                c.hour = d == 0 ? 8 : 7
                c.minute = 8 + i * 9
                c.second = 12 + d
                guard let date = WeekCal.gregorian.date(from: c) else { continue }
                out.append(CachedLog(type: t.0, typeName: t.1,
                                     idxRaw: 0xD0000000 | UInt32(d) &* 0x100 | UInt32(i),
                                     lockTime: Int64(date.timeIntervalSince1970 * 1000),
                                     lockTimeStr: Self.demoStamp(date)))
            }
        }
        DB.replaceLogs(demoMac, out)
        DB.store.set(kDemoLogsActive, true)
    }
    private static let demoStampF: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()
    private static func demoStamp(_ d: Date) -> String { demoStampF.string(from: d) }

    // 839 "示例筛选"开关: **已删, 判 PART**。原 setDrillFilter/clearDrillFilter 只写 kf_demo_drillfilter 这一个
    // 标记, 而全仓没有任何读取方 (记录页取数按锁维度, demo_ 样例本来就挂在演示锁 demoMac 下)。接上它等于
    // 给一个没人看的旗子加按钮 —— 真要做"把样例叠加进真实记录列表"要改 RecordsView 的取数链, 无编译基线不盲做。
    // 现有可用面: generateSevenDaySamples / clearDemoLogs / clearAll。kDrillFilter 常量只为 clearAll 的兜底清键留着。

    /// 842 演练备份: 首次备份标"演练" — 导入样例后立起标记, 转正式时摘除
    @MainActor
    static var drillBackupOn: Bool { DB.store.getBool(kDrillDemoOn) }
    /// 842 唯一写点：这一族此前只有"读"与"摘除"，没有任何一处把旗立起来
    /// ⇒ 设置页那块「转正式备份」(SettingsView:173) 是永不出现的死文案。
    @MainActor
    static func beginDrillBackup() { DB.store.set(kDrillDemoOn, true) }
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
    /// 2026-10-13 对抗式排查: 原写的 `Task { @MainActor in ... }` **没有句柄、不可取消**, 且
    /// `Task.sleep(nanoseconds:)` 在取消后照样睡完。连点圆盘会再起一个任务, 旧任务 0.7~2.1s 后
    /// 继续覆写 phase/unlockState, 打到新一次开锁态上 (演示态也会把真实态显示覆盖掉)。
    /// 改成"重启前先 cancel, 每段 sleep 前后各查一次 isCancelled"。
    @MainActor
    static var demoUnlockTask: Task<Void, Never>?

    @MainActor
    static func simulateDemoUnlock(phase: @escaping (Int) -> Void,
                                   onDone: @escaping () -> Void) {
        demoUnlockTask?.cancel()
        demoUnlockTask = Task { @MainActor in
            for p in [1, 2, 3] {
                if Task.isCancelled { return }
                phase(p)
                try? await Task.sleep(nanoseconds: 700_000_000)
                if Task.isCancelled { return }
            }
            if Task.isCancelled { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onDone()
        }
    }
}

/// 演示模式常驻横幅 (836): 四 Tab 顶部, 可一键清除演示数据
struct DemoBanner: View {
    @EnvironmentObject var app: AppState
    var onCleared: () -> Void = {}

    var body: some View {
        if DemoKit.isOn || DB.store.getBool(DemoKit.kDemoLogsActive) {
            Label {
                HStack(spacing: DS.Space.xs) {
                    Text("演示模式 · 数据全部为 demo_ 样例, 不碰真实门锁")
                    Spacer(minLength: 0)
                    Button("清除演示数据") {
                        DemoKit.setOn(false)
                        onCleared()
                    }
                    .vkFont(.footnote, weight: .semibold)
                    .foregroundStyle(DS.Palette.danger)
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
            } icon: {
                Image(systemName: "theatermasks.fill").accessibilityHidden(true)
            }
            .vkFont(.caption)
            .foregroundStyle(DS.Palette.warn)
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.s)
            // 2026-10-14 材质统一: 演示横幅原先是全 App 唯一一块直角实底带 —— 同一条顶部横幅栈里
            // 蓝牙条/自检条/粘贴条都是 control 圆角, 只有它是方的。走 axGlass 后它与那几条同几何,
            // 且 226 降透明 / 862 增强对比时仍落回实底。
            .axGlass(DS.Radius.control)
        }
    }
}
