// 锁设置 —— 2026-10-29 新增（B 档：独立锁设置页）
//
// 定位：**只放「这一把锁」的 7 项能力**，不承载型号/固件/电量/绑定等只读信息
// （那些在「锁信息名片」DeviceInfoView 里）。
//
// 三条刻意设计（来自六份子程序审核的约束）：
//   1. 不调用 DeviceInfoView.reload() —— 打开设置页不应该自动连接、更不应该自动写锁钟；
//   2. 独立页面，不塞进信息名片 —— 信息/诊断/设置是三种语义，混在一页会撞 modality.md 的
//      「modal 里做 app within app」；
//   3. 清空密码单独一个「危险操作」Section、红色、二次确认 —— 不与其它 6 项并列。
//
// 入口（双入口，旧的设置页 7 行保留不删）：
//   · 设备页工具栏齿轮
//   · 设置 → 门锁 → 「锁设置」
import SwiftUI

struct LockSettingsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss

    @State private var settingMute = false
    @State private var clearingPwd = false

    private var mac: String { app.current?.mac ?? "" }

    var body: some View { vkBody.destined(.lockSettings) }

    var vkBody: some View {
        NavigationStack {
            Form {
                if let kc = app.current {
                    overviewSection(kc)
                    capabilitySection(kc)
                    dangerSection(kc)
                } else {
                    Section {
                        Text("还没有选择门锁。")
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                }
            }
            .navigationTitle("锁设置")
            .variantList()
            .dsScreenBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    // MARK: - 概览（只读，不触发连接）

    /// 读数全部来自 `app.status`（上一次同步的全局快照）+ `kc` 的静态字段。
    /// **刻意不调用 `DeviceInfoView.reload()`** —— 打开设置页不应该连蓝牙、更不应该自动写锁钟。
    /// 要看「进页刷新」的完整诊断，走「锁信息名片」。
    @ViewBuilder
    private func overviewSection(_ kc: Keychain) -> some View {
        Section {
            LabeledRow("型号", PidMap.productName(kc.pid))
            LabeledRow("固件版本", firmwareText(kc))
            if let v = app.status?.verDFU, v > 0 { LabeledRow("Boot 版本", "\(v)") }
            if let v = app.status?.verKeyboard, v > 0 { LabeledRow("键盘版本", "\(v)") }
            LabeledRow("MAC", kc.mac)
            if !kc.pairedAt.isEmpty { LabeledRow("绑定于", kc.pairedAt) }
            LabeledRow("锁钟偏差", driftLabel)
            LabeledRow("门锁电量", batteryLabel)
            if let s = app.status {
                LabeledRow("安全模式", modeLabel(s))
                LabeledRow("锁内时间", s.lockTime.map { ProtoTime.localStr($0) } ?? "—")
            }
            // 2026-10-29 入口去重：锁信息名片收进「概览」底部（唯一入口）。
            NavigationLink("锁信息名片（进页刷新 / 完整诊断）") { DeviceInfoView() }
        } header: {
            Text("概览")
        } footer: {
            Text("读数是上一次同步的快照。要强制刷新请到「锁信息名片」点「重新读取」。")
        }
    }

    private func firmwareText(_ kc: Keychain) -> String {
        if let fw = app.status?.firmware, !fw.isEmpty { return fw }
        return kc.fw.isEmpty ? "未知" : kc.fw
    }

    private var driftLabel: String {
        guard let t = app.status?.lockTime, t > 0 else { return "—" }
        let dev = Int(Date().timeIntervalSince1970) - Int(t)
        return dev == 0 ? "同步" : "\(dev)s"
    }

    private var batteryLabel: String {
        let p = app.status?.powerLevel ?? app.snapshot?.powerLevel ?? -1
        return p < 0 ? "—" : (p > 80 ? ">80%" : "\(p)%")
    }

    private func modeLabel(_ s: LockStatus) -> String {
        if s.verifyMode == 1 && s.broadcastMode == 0 { return "C 模式" }
        return s.verifyMode == 0 ? "A 模式" : "B 模式"
    }

    // MARK: - 能力（6 项，按 pid 裁剪）

    @ViewBuilder
    private func capabilitySection(_ kc: Keychain) -> some View {
        Section {
            // 2026-10-29 入口去重：布防只在设备页圆盘下方那一行（带实时状态）。
            // 本页不再重复 —— 从设备页进来时，那一行就在上一屏。
            if PidMap.canTailgate(kc.pid, fw: kc.fw) {
                NavigationLink {
                    TailgateView()
                } label: {
                    capabilityLabel("防尾随入室", icon: "figure.walk.arrival", detail: "", active: false)
                }
            }
            NavigationLink {
                SafemodeIntroView()
            } label: {
                capabilityLabel("安全模式 A/B", icon: "lock.rotation", detail: safemodeText, active: false)
            }
            // 静音：内联开关（即点即下发，与设置页同一套语义）
            VariantToggle("静音模式", isOn: Binding(
                get: { muteStored },
                set: { silent in
                    guard !settingMute else { return }
                    settingMute = true
                    Task {
                        defer { settingMute = false }
                        do {
                            try await app.lock.ensureConnected(mac: mac)
                            try await app.lock.setSilent(silent)
                            DB.store.set("kf_mute_" + mac, silent)
                            app.showToast(silent ? "已静音" : "已恢复提示音")
                        } catch {
                            app.showToast("设置失败: \(error.localizedDescription)")
                        }
                    }
                }))
                .disabled(settingMute)
            NavigationLink {
                SyncTimeView()
            } label: {
                capabilityLabel("校准门锁时间", icon: "clock.arrow.circlepath", detail: driftText, active: false)
            }
            if PidMap.canDeviceUpgrade(kc.pid) {
                NavigationLink {
                    DFUView()
                } label: {
                    capabilityLabel("固件升级", icon: "arrow.up.circle", detail: "", active: false)
                }
            }
        } header: {
            Text("能力")
        } footer: {
            Text("只影响这一把锁；App 级设置仍在「设置」Tab。不支持的型号不会列出对应项。")
        }
    }

    // MARK: - 危险操作（单独隔离）

    @ViewBuilder
    private func dangerSection(_ kc: Keychain) -> some View {
        if PidMap.canClearPwd(kc.pid) {
            Section {
                Button(role: .destructive) {
                    confirmDestructive("清空密码",
                                       "执行清空密码操作，会作废所有成员的密码（**指纹保留**），门锁需重新逐个添加。确定要清空吗？",
                                       confirmTitle: "清空") {
                        Task { await doClearPwd() }
                    }
                } label: {
                    Label("清空密码", systemImage: "delete.left")
                }
                .disabled(clearingPwd)
            } header: {
                Text("危险操作")
            } footer: {
                Text("需要门锁在场直发。清空后密码全部作废，指纹台账保留。")
            }
        }
    }

    // MARK: - 行渲染

    private func capabilityLabel(_ title: String, icon: String, detail: String, active: Bool) -> some View {
        HStack(spacing: DS.Space.s) {
            Label(title, systemImage: icon)
            Spacer(minLength: 0)
            if !detail.isEmpty {
                Text(detail)
                    .vkFont(.caption)
                    .foregroundStyle(active ? DS.Palette.ok : DS.Palette.textSub)
                    .lineLimit(1)
            }
        }
        .frame(minHeight: DS.Hit.min)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(detail.isEmpty ? title : "\(title)，\(detail)")
    }

    // MARK: - 读数（不触发连接，只读已同步的状态）

    /// 静音：优先读锁端 `app.status.soundVolumn`（1 = 静音），读不到回落本地记录。
    private var muteStored: Bool {
        if let s = app.status { return s.soundVolumn > 0 }
        return DB.store.getBool("kf_mute_" + mac)
    }

    /// 安全模式 A/B/C：与 `DeviceInfoView.modeText` 同一判据链。
    private var safemodeText: String {
        guard let s = app.status else { return "" }
        if s.verifyMode == 1 && s.broadcastMode == 0 { return "C 模式" }
        return s.verifyMode == 0 ? "A 模式" : "B 模式"
    }

    private var driftText: String {
        guard let d = app.status?.lockTime, d > 0 else { return "" }
        let dev = Int(Date().timeIntervalSince1970) - Int(d)
        return dev == 0 ? "同步" : "偏差 \(dev)s"
    }

    // MARK: - 清空密码

    /// 数据丢失级保护（复制自 SettingsView.doClearPwd，两处同源）：
    ///   · `let m = mac` 必须在两次 await **之前**捕获 —— 期间 app.current 可能被 AppIntent / kf:// 深链改掉；
    ///   · `keepLedger.pwds = []` 只清密码，`fps` 原样保留 —— 历史 bug 是 `Ledger()` 把指纹也清了。
    private func doClearPwd() async {
        guard !clearingPwd else { return }
        let m = mac
        guard !m.isEmpty else { app.showToast("未选择门锁"); return }
        clearingPwd = true
        defer { clearingPwd = false }
        do {
            try await app.lock.ensureConnected(mac: m)
            try await app.lock.pwdClear()
            var keepLedger = DB.ledger(m)
            keepLedger.pwds = []
            DB.saveLedger(m, keepLedger)
            app.showToast("清空密码成功")
        } catch {
            app.showToast("清空失败: \(error.localizedDescription)")
        }
    }
}
