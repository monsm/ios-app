// 功能页集合: 添加设备/配网 · 添加密码 · 录指纹 · 设备信息 · 固件 DFU · 钥匙串硬件 · 网关 · 成员 · 动态 · 备份
// 通用约定:
//   1) 破坏性/不可逆动作 (删记录、写硬件、升级固件) 一律先确认, 走全局 confirmDestructive 或 confirmationDialog;
//   2) 纯 VStack 页面套 ScrollView, 大字号下不溢出;
//   3) 装饰性图标 .accessibilityHidden(true), 状态不靠颜色单通道传达。
import SwiftUI
import UIKit
import UniformTypeIdentifiers








// ================= 蓝牙钥匙串硬件 (addkeychain) =================
struct KeychainHWView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var dongles: [Dongle] = []
    @State private var busy = false

    var body: some View { vkBody.destined(.keychainHW) }
    var vkBody: some View {
        NavigationStack {
            List {
                Section("蓝牙钥匙串") {
                    Text("钥匙串是一个随身蓝牙硬件，可写入多把门锁的数字钥匙。持有人靠近门锁时即可开门，无需手机。")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        Task { await scan() }
                    } label: {
                        HStack(spacing: DS.Space.s) {
                            // 常驻菊花 + 透明度过渡, 避免文字被推着走
                            ProgressView().controlSize(.small).opacity(busy ? 1 : 0)
                            Text(busy ? "搜索中…" : "搜索钥匙串")
                        }
                        .frame(minHeight: DS.Hit.min)
                    }
                    .buttonStyle(PrimaryActionStyle())
                    .disabled(busy)
                }
                Section("我的钥匙串") {
                    if dongles.isEmpty {
                        EmptyState(systemImage: "key.slash",
                                   title: "还没有钥匙串",
                                   message: "上电后点上方「搜索钥匙串」即可添加。",
                                   actionTitle: "搜索钥匙串") {
                            Task { await scan() }
                        }
                    }
                    ForEach(dongles) { d in dongleRow(d) }
                        .disabled(busy)
                }
                if app.current == nil {
                    Section {
                        Label {
                            Text("尚未配对门锁 — 写入钥匙前需先配对门锁。")
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
                        }
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.warn)
                    }
                }
            }
            .navigationTitle("蓝牙钥匙串")
            .variantList()
            .dsScreenBackground()
            .task { reload() }
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button(busy ? "写入中…" : "关闭") { dismiss() }.disabled(busy) } } .interactiveDismissDisabled(busy)   // 2026-10-15 走查: 写锁在飞时不给退出入口
        }
    }

    private func dongleRow(_ d: Dongle) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.s) {
                Text(d.name.isEmpty ? "钥匙串" : d.name)
                    .vkFont(.subheadline, weight: .semibold)
                    .foregroundStyle(DS.Palette.text)
                if !d.lastKeyLock.isEmpty {
                    StatusPill(text: "已配钥匙", systemImage: "checkmark.circle.fill", tone: .ok)
                }
                Spacer(minLength: 0)
            }
            Text(dongleDisplay(d.mac))
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
            if let st = d.stat {
                // 电量/钥匙存量/固件是三条独立读数, 用 MetricTile 横排比挤在 caption 里层级更清楚
                HStack(spacing: DS.Space.s) {
                    MetricTile(systemImage: "battery.100",
                               label: "电量",
                               value: st.power < 0 ? "—" : "\(st.power)%",
                               tone: st.power < 0 ? .neutral : (st.power <= 20 ? .warn : .ok))
                    MetricTile(systemImage: "key",
                               label: "钥匙",
                               // -1 = 该字段没读到。两侧是**各自独立**解析的 (KLV#24 与 #25 各默认 -1,
                               // HardwareService.parseKCStatus), 所以"读到了存量、没读到上限"是正常回字 ——
                               // 原先只挡 count 那侧, 屏上就印出 "3 / -1" 这种把缺失当读数的数。
                               value: st.ekeyCount < 0 ? "—"
                                    : (st.ekeyAmount < 0 ? "\(st.ekeyCount) / —" : "\(st.ekeyCount) / \(st.ekeyAmount)"),
                               emphasized: false)
                    MetricTile(systemImage: "cpu",
                               label: "固件",
                               value: st.firmware.isEmpty ? "—" : st.firmware)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .swipeActions {
            Button(role: .destructive) { removeRecord(d) } label: { Label("删除记录", systemImage: "trash") }
        }
        .contextMenu {
            Button("读取状态") { Task { await readStatus(d) } }
            Menu("给当前门锁写入钥匙") {
                // 内层菜单项不重复外层标题, 加省略号表示会再弹确认框
                Button("写入…") { confirmWriteKey(d) }
            }
            Button("查询全部钥匙") { Task { await listKeys(d) } }
            Button("删除本锁钥匙") { confirmDeleteKey(d) }
        }
        // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 命中高仅约 14.5pt (< 44)。
        // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
        .frame(minHeight: DS.Hit.min)
        .contentShape(Rectangle())
    }

    private func dongleDisplay(_ hex: String) -> String {
        let b = HexKit.bytes(hex).reversed()
        return b.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    private func reload() { dongles = DB.dongles() }

    // ---- 写硬件类动作一律先确认: 钥匙串上的钥匙不可撤销 ----
    private func confirmWriteKey(_ d: Dongle) {
        guard !busy else { return }
        let lockName = app.displayName
        confirmDestructive("写入钥匙",
                          "将把「\(lockName)」的门锁密钥写入钥匙串「\(d.name.isEmpty ? "钥匙串" : d.name)」。写入后该钥匙串无需手机即可开这道门，且无法在 App 内撤销。确定写入吗？",
                          confirmTitle: "确认写入") {
            Task { await self.writeKey(d) }
        }
    }

    private func confirmDeleteKey(_ d: Dongle) {
        guard !busy else { return }
        confirmDestructive("删除本锁钥匙",
                          "将清除钥匙串「\(d.name.isEmpty ? "钥匙串" : d.name)」中「\(app.displayName)」的钥匙。删除后该钥匙串将无法再开这道门。确定删除吗？",
                          confirmTitle: "删除") {
            Task { await self.deleteKey(d) }
        }
    }

    private func removeRecord(_ d: Dongle) {
        guard !busy else { return }
        confirmDestructive("删除记录",
                          "将从本机删除钥匙串「\(d.name.isEmpty ? "钥匙串" : d.name)」(\(dongleDisplay(d.mac))) 的记录，硬件本身不受影响。确定删除吗？",
                          confirmTitle: "删除") {
            DB.removeDongle(d.mac)
            reload()
        }
    }

    private func scan() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { _ = try await HardwareService.shared.scanForDongle() }
        catch { app.showToast(error.localizedDescription) }
        reload()
    }

    private func readStatus(_ d: Dongle) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { _ = try await HardwareService.shared.readDongleState(mac: d.mac) }
        catch { app.showToast(error.localizedDescription) }
        reload()
    }

    private func writeKey(_ d: Dongle) async {
        guard let kc = app.current else { app.showToast("请先选择门锁"); return }   // 2026-10-15 走查: 下面那句"请先配对门锁"会说, 上面这句却静默 = 同一条链两种收法
        guard !busy else { return }
        guard !kc.skey.isEmpty, kc.pid != 0 else { app.showToast("请先配对门锁"); return }
        busy = true
        defer { busy = false }
        do {
            try await HardwareService.shared.writeDongleKey(dongleMac: d.mac, lock: kc, trackId: KeyGen.genTrackId())
            app.showToast("设置成功: 该钥匙串现已开启「\(app.displayName)」")
        } catch { app.showToast("失败: \(error.localizedDescription)") }
        reload()
    }

    private func deleteKey(_ d: Dongle) async {
        guard let kc = app.current else { app.showToast("请先选择门锁"); return }   // 2026-10-15 走查: 与 writeKey 同一条口径
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await HardwareService.shared.deleteDongleKey(dongleMac: d.mac, lock: kc)
            app.showToast("已删除该门锁的钥匙")
        } catch { app.showToast("失败: \(error.localizedDescription)") }
        reload()
    }

    private func listKeys(_ d: Dongle) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let macs = try await HardwareService.shared.dongleKeys(dongleMac: d.mac, lockMac: nil)
            app.showToast(macs.isEmpty ? "没有查询到钥匙" : "共 \(macs.count) 把钥匙")
        } catch { app.showToast("失败: \(error.localizedDescription)") }
        reload()
    }
}

// ================= 网关 (addgw + gwstate 合流) =================
struct GatewayView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var confirmed = false
    @State private var ssid = ""
    @State private var pwd = ""
    @State private var running = false
    @State private var steps: [String] = []
    @State private var error = ""
    @State private var gateways: [Gateway] = []

    var body: some View { vkBody.destined(.gateway) }
    var vkBody: some View {
        NavigationStack {
            List {
                if !confirmed {
                    Section("准备网关") {
                        Text("接通电源，重置网关，待网关指示灯闪烁橙色后点击下一步。").vkFont(.footnote)
                        VariantToggle("橙色灯闪烁中", isOn: $confirmed)
                        Text("长捅网关的重置孔，保持5s左右，至指示灯变为橙色，即重置成功。")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                } else {
                    Section("配置 WiFi") {
                        TextField("WiFi 名称 (2.4GHz)", text: $ssid)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                        SecureField("WiFi 密码", text: $pwd)
                            .submitLabel(.done)
                    }
                    Section {
                        BusyButton(title: "开始配网", systemImage: "wifi", isBusy: running, disabled: ssid.isEmpty || pwd.isEmpty) {
                            confirmProvision()
                        }
                    }
                    if !steps.isEmpty {
                        Section("配网进度") {
                            ForEach(Array(steps.enumerated()), id: \.offset) { _, s in
                                Label {
                                    Text(s).fixedSize(horizontal: false, vertical: true)
                                } icon: {
                                    Image(systemName: "checkmark").accessibilityHidden(true)
                                }
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.ok)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                            if !error.isEmpty {
                                Text(error)
                                    .vkFont(.caption)
                                    .foregroundStyle(DS.Palette.danger)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .animation(DS.Motion.standard, value: steps)
                    }
                }
                gatewayList
            }
            .navigationTitle("智能网关")
            .variantList()
            .dsScreenBackground()
            // sheet 呈现时必须自带退出入口, 否则用户出不去
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button(running ? "写入中…" : "关闭") { dismiss() }.disabled(running) } } .interactiveDismissDisabled(running)   // 2026-10-15 走查: 写锁在飞时不给退出入口
            .task { reload() }
        }
    }

    private var gatewayList: some View {
        Section("我的网关") {
            if gateways.isEmpty {
                EmptyState(systemImage: "antenna.radiowaves.left.and.right.slash",
                           title: "还没有添加网关",
                           message: "先在上方重置网关并勾选指示灯状态，再回来配网。")
            }
            ForEach(gateways) { g in gatewayRow(g) }
                .disabled(running)
        }
    }

    private func gatewayRow(_ g: Gateway) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.s) {
                Text(g.name.isEmpty ? "智能网关" : g.name)
                    .vkFont(.subheadline, weight: .semibold)
                    .foregroundStyle(DS.Palette.text)
                StatusPill(text: g.netState == 1 ? "已联网" : "未联网",
                           systemImage: g.netState == 1 ? "wifi" : "wifi.slash",
                           tone: g.netState == 1 ? .ok : .neutral)
                Spacer(minLength: 0)
            }
            // 版本/网络两条独立读数, 用 MetricTile 横排比挤在一行 caption 里层级更清楚
            HStack(spacing: DS.Space.s) {
                MetricTile(systemImage: "cpu",
                           label: "ROM",
                           value: g.romVer.isEmpty ? "—" : g.romVer)
                MetricTile(systemImage: "wifi",
                           label: "WiFi",
                           value: g.ssid.isEmpty ? "—" : g.ssid,
                           tone: g.netState == 1 ? .ok : .neutral)
            }
        }
        .accessibilityElement(children: .combine)
        .swipeActions {
            Button(role: .destructive) { removeGateway(g) } label: { Label("删除", systemImage: "trash") }
            Button { confirmReboot(g) } label: { Label("重启", systemImage: "arrow.clockwise") }.tint(DS.Palette.accent)
        }
        .contextMenu {
            Button("刷新状态") { Task { await refresh(g) } }
            Button("重启网关") { confirmReboot(g) }
        }
        // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 命中高仅约 14.5pt (< 44)。
        // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
        .frame(minHeight: DS.Hit.min)
        .contentShape(Rectangle())
    }

    private func removeGateway(_ g: Gateway) {
        guard !running else { return }
        confirmDestructive("删除网关",
                          "将从本机删除网关「\(g.name.isEmpty ? "智能网关" : g.name)」的记录。删除后若不再配网将无法找回。确定删除吗？",
                          confirmTitle: "删除") {
            DB.removeGateway(g.mac)
            reload()
        }
    }

    private func reload() { gateways = DB.gateways() }

    // 配网会向网关硬件写入 WiFi 凭据, 配错需重新重置网关才能再配
    private func confirmProvision() {
        guard !running, !ssid.isEmpty, !pwd.isEmpty else { return }
        confirmDestructive("写入网关",
                          "将把 WiFi「\(ssid)」写入网关硬件。写入过程网关会重启并清空原有网络配置，若网络不通需要重新重置网关才能再次配网。确定开始配网吗？",
                          confirmTitle: "开始配网") {
            Task { await self.provision() }
        }
    }

    // 重启会让网关短暂离线, 断电/断网期间无法远程唤醒
    private func confirmReboot(_ g: Gateway) {
        guard !running else { return }
        confirmDestructive("重启网关",
                          "将重启「\(g.name.isEmpty ? "智能网关" : g.name)」。网关会短暂离线，此期间无法远程开锁。确定重启吗？",
                          confirmTitle: "重启") {
            Task { await self.reboot(g) }
        }
    }

    private func provision() async {
        guard !running else { return }
        running = true
        steps.removeAll()
        error = ""
        defer { running = false }
        do {
            let sentWifi = ssid
            _ = try await HardwareService.shared.provisionGateway(ssid: ssid, password: pwd) { s in steps.append(s) }
            ssid = ""; pwd = ""
            confirmed = false
            // 2026-10-15 走查: 成功这一支原先只清空表单 + 退回第一步, 而"配网进度"那段只在
            // confirmed == true 的那一支里渲染 —— 于是连服务回调最后那句"添加成功!"也一起没了,
            // 成功与"点了没反应"完全同形 (失败反倒看得见, error 走的是另一支)。补一句结论,
            // 并把话说准: 到这里为止被网关 errCode 0 认下的是"WiFi 写入", 联网状态得等它自己上报。
            app.showToast("配网指令已被网关接受 · 正在用「\(sentWifi)」重连, 联网状态稍后在下方列表复核")
        } catch {
            self.error = error.localizedDescription
        }
        reload()
    }

    // refresh / reboot 与 provision 互斥: 同一时间只允许一条网关指令在飞
    private func refresh(_ g: Gateway) async {
        guard !running else { return }
        running = true
        defer { running = false }
        do { _ = try await HardwareService.shared.readGatewayState(mac: g.mac) }
        catch { app.showToast(error.localizedDescription) }
        reload()
    }

    private func reboot(_ g: Gateway) async {
        guard !running else { return }
        running = true
        defer { running = false }
        do {
            try await HardwareService.shared.rebootGateway(mac: g.mac)
            app.showToast("重启成功")
        } catch { app.showToast("重启失败: \(error.localizedDescription)") }
        reload()
    }
}


