// 智能网关（配网/状态/重启）
// 2026-10-29 从 Sheets.swift 拆出
import SwiftUI

struct GatewayView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
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
                        // 2026-10-28 补：APK `GwstatePage`（网关状态页）有三条使用须知，iOS 全文没有 ——
                        // 用户不知道网关该放多远、能做什么不能做什么，容易以为「买了网关就能远程开门」。
                        // 第 2 条原文是「绑定到和门锁相同账号下即可」—— 那是云端账号口径；
                        // iOS 纯离线没有账号，这里改写成等价的本地事实（IoT 凭据随配网一起写入网关）。
                        Text("1. 建议距离门锁不超过五米，不能有障碍物阻隔。")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("2. 无需和门锁配对；配网时 IoT 凭据会随 WiFi 一起写入网关。")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("3. 只能接收门锁状态和通知，无法远程操作门锁。")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Section {
                        TextField("WiFi 名称 (2.4GHz)", text: $ssid)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                        SecureField("WiFi 密码", text: $pwd)
                            .submitLabel(.done)
                    } header: {
                        Text("配置 WiFi")
                    } footer: {
                        // 2026-10-28：APK 用原生的 WifiNamePlugin.getWifiInfo 自动预填当前 SSID；
                        // iOS 读 WiFi 名需要 `com.apple.developer.networking.wifi-info` entitlement + 定位权限，
                        // 本工程两者都没有（也不该为一个配网表单去申请定位）。所以这里如实说明要手输，
                        // 而不是让用户以为是 App 忘了填。
                        Text("iOS 不允许 App 读取当前 WiFi 名，请手动输入（只支持 2.4GHz）。")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                        // 2026-10-28 补：APK 的「更换其他 WiFi」走 NativeSettings.open("wifi") 直达系统 WiFi 面板；
                        // iOS **没有**任何公开 API 能直达 WiFi 设置（openSettingsURLString 只到本 App 设置页）。
                        // 所以这里只能如实告诉用户要自己离开 App 去系统设置，而不是放一个点了没反应的按钮。
                        Text("需要换 WiFi 时，请先到「设置 → Wi-Fi」连上目标网络，再回来点「开始配网」。")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
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