//
//  GatewayPage.swift
//  智能网关 · 全新重写 (2026-10-21)
//
//  ═══════════════════════════════════════════════════════════
//  视觉冲击力: 两步配网做成"阶梯"
//  ═══════════════════════════════════════════════════════════
//
//  旧版: List + 一段说明 + Toggle + 两个输入框 + 进度 Section
//
//  新版:
//    · 第一步: 一整块"重置网关"引导卡 (大图标 + 指示灯状态 + 勾选)
//    · 完成勾选后卡整体淡出, 第二步"配网"卡顺次进 (move + opacity)
//    · 配网进度: 逐行落下 + 每行左侧竖线连接成"脊梁"
//    · 网关列表: 每台一张卡, 联网状态用铜色发光圆点
//

import SwiftUI

/// 智能网关页
struct GatewayPage: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var confirmed = false
    @State private var ssid = ""
    @State private var pwd = ""
    @State private var running = false
    @State private var steps: [String] = []
    @State private var error = ""
    @State private var gateways: [Gateway] = []
    @State private var refreshTick = 0

    var body: some View {
        ZStack {
            XPalette.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: XSpace.l) {
                    if !confirmed {
                        stepOneCard.xScrollLift()
                    } else {
                        stepTwoCard.xScrollLift()
                        if !steps.isEmpty || !error.isEmpty { progressCard.xScrollLift() }
                    }

                    if !gateways.isEmpty {
                        ForEach(gateways) { g in gatewayCard(g).xScrollLift() }
                    } else {
                        emptyState.xScrollLift()
                    }
                }
                .padding(.horizontal, XSpace.gutter)
                .padding(.vertical, XSpace.l)
                .animation(XMotion.soft, value: confirmed)
            }
        }
        .navigationTitle("智能网关")
        .navigationBarTitleDisplayMode(.inline)
        .task { reload() }
        .id(refreshTick)
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 第一步: 重置
    // ═══════════════════════════════════════════════════════

    private var stepOneCard: some View {
        XPanel(kind: .hero) {
            VStack(spacing: XSpace.m) {
                ZStack {
                    Circle()
                        .fill(XPalette.warn.opacity(0.12))
                        .frame(width: 96, height: 96)
                    Image(systemName: "light.beacon.max")
                        .font(.system(size: XMetric.decorIcon(40), weight: .light))
                        .foregroundStyle(XPalette.warn)
                }
                .accessibilityHidden(true)

                Text("先把网关重置")
                    .xFont(.title3, weight: .semibold)
                    .foregroundStyle(XPalette.text)

                Text("接通电源 → 长捅重置孔约 5 秒 → 等待指示灯变成橙色")
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.textSub)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().overlay(XPalette.hairline)

                XToggle("指示灯已变成橙色", isOn: $confirmed)
                    .xFont(.body)

                if !confirmed {
                    Text("勾选后进入下一步")
                        .xFont(.caption2)
                        .foregroundStyle(XPalette.textTertiary)
                }
            }
            .padding(.vertical, XSpace.s)
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 第二步: 配 WiFi
    // ═══════════════════════════════════════════════════════

    private var stepTwoCard: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                HStack(spacing: XSpace.s) {
                    Image(systemName: "wifi")
                        .font(.system(size: XIcon.sm, weight: .medium))
                        .foregroundStyle(XPalette.accentText)
                        .accessibilityHidden(true)
                    Text("配置 WiFi")
                        .xFont(.subheadline, weight: .medium)
                        .foregroundStyle(XPalette.text)
                    Spacer()
                    Button {
                        withAnimation(XMotion.soft) { confirmed = false }
                    } label: {
                        Text("上一步")
                            .xFont(.caption)
                            .foregroundStyle(XPalette.accentText)
                    }
                    .disabled(running)
                }

                field("WiFi 名称", text: $ssid, placeholder: "仅支持 2.4GHz", secure: false)
                field("WiFi 密码", text: $pwd, placeholder: "输入密码", secure: true)

                XBusyButton(title: running ? "配网中…" : "开始配网",
                            systemImage: "wifi", busy: running, style: .primary) {
                    confirmProvision()
                }
                .disabled(running || ssid.isEmpty || pwd.isEmpty)
                .opacity(ssid.isEmpty || pwd.isEmpty ? 0.5 : 1)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String, secure: Bool) -> some View {
        VStack(alignment: .leading, spacing: XSpace.xs) {
            Text(label)
                .xFont(.caption)
                .foregroundStyle(XPalette.textSub)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                        .textInputAutocapitalization(.never)
                }
            }
            .xFont(.body)
            .autocorrectionDisabled()
            .padding(XSpace.s)
            .background(XPalette.surfaceSunken,
                        in: RoundedRectangle(cornerRadius: XRadius.min, style: .continuous))
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 进度
    // ═══════════════════════════════════════════════════════

    private var progressCard: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.s) {
                Text("配网进度")
                    .xFont(.subheadline, weight: .medium)
                    .foregroundStyle(XPalette.textSub)

                ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .top, spacing: XSpace.s) {
                        // 左侧脊梁
                        VStack(spacing: 0) {
                            Circle()
                                .fill(XPalette.ok)
                                .frame(width: 8, height: 8)
                            if i < steps.count - 1 {
                                Rectangle()
                                    .fill(XPalette.ok.opacity(0.3))
                                    .frame(width: 1.5)
                            }
                        }
                        .padding(.top, 5)

                        Text(s)
                            .xFont(.caption.monospaced())
                            .foregroundStyle(XPalette.text)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if !error.isEmpty {
                    HStack(alignment: .top, spacing: XSpace.s) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: XIcon.xs, weight: .semibold))
                            .foregroundStyle(XPalette.danger)
                        Text(error)
                            .xFont(.caption)
                            .foregroundStyle(XPalette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(XSpace.s)
                    .background(XPalette.danger.opacity(0.10),
                                in: RoundedRectangle(cornerRadius: XRadius.min, style: .continuous))
                }
            }
            .animation(XMotion.standard, value: steps.count)
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 网关卡
    // ═══════════════════════════════════════════════════════

    private func gatewayCard(_ g: Gateway) -> some View {
        let online = g.netState == 1
        return VStack(alignment: .leading, spacing: XSpace.m) {
            HStack(spacing: XSpace.s) {
                ZStack {
                    Circle()
                        .fill(online ? XPalette.ok.opacity(0.15) : XPalette.textTertiary.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: online ? "wifi" : "wifi.slash")
                        .font(.system(size: XIcon.sm, weight: .medium))
                        .foregroundStyle(online ? XPalette.ok : XPalette.textTertiary)
                }
                .shadow(color: online ? XPalette.ok.opacity(0.4) : .clear, radius: 8)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(g.name.isEmpty ? "智能网关" : g.name)
                        .xFont(.body, weight: .medium)
                        .foregroundStyle(XPalette.text)
                    Text(online ? "已联网" : "未联网")
                        .xFont(.caption)
                        .foregroundStyle(online ? XPalette.ok : XPalette.textSub)
                }

                Spacer(minLength: 0)

                Menu {
                    Button("刷新状态") { Task { await refresh(g) } }
                    Button("重启网关") { confirmReboot(g) }
                    Divider()
                    Button("删除记录", role: .destructive) { removeGateway(g) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: XIcon.md, weight: .medium))
                        .foregroundStyle(XPalette.textSub)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(running)
                .accessibilityLabel("更多操作")
            }

            HStack(spacing: XSpace.m) {
                readPair("ROM", g.romVer.isEmpty ? "—" : g.romVer)
                readPair("WiFi", g.ssid.isEmpty ? "—" : g.ssid)
            }
        }
        .padding(XSpace.card)
        .background(
            RoundedRectangle(cornerRadius: XRadius.card, style: .continuous)
                .fill(XPalette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: XRadius.card, style: .continuous)
                        .strokeBorder(online ? XPalette.ok.opacity(0.3) : XPalette.hairline,
                                      lineWidth: 1))
        )
    }

    private func readPair(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .xFont(.caption2)
                .foregroundStyle(XPalette.textTertiary)
            Text(value)
                .xFont(.caption.monospaced())
                .foregroundStyle(XPalette.text)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: XSpace.m) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: XMetric.decorIcon(56), weight: .ultraLight))
                .foregroundStyle(XPalette.textTertiary)
                .accessibilityHidden(true)
            Text("还没有添加网关")
                .xFont(.headline)
                .foregroundStyle(XPalette.text)
            Text("先在上方重置网关并勾选指示灯状态, 再回来配网")
                .xFont(.footnote)
                .foregroundStyle(XPalette.textSub)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, XSpace.xl)
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 逻辑 (与旧实现等价)
    // ═══════════════════════════════════════════════════════

    private func reload() { gateways = DB.gateways() }

    private func removeGateway(_ g: Gateway) {
        guard !running else { return }
        confirmDestructive("删除网关",
                           "将从本机删除网关「\(g.name.isEmpty ? "智能网关" : g.name)」的记录。删除后若不再配网将无法找回。",
                           confirmTitle: "删除") {
            DB.removeGateway(g.mac)
            reload()
        }
    }

    private func confirmProvision() {
        guard !running, !ssid.isEmpty, !pwd.isEmpty else { return }
        confirmDestructive("写入网关",
                           "将把 WiFi「\(ssid)」写入网关硬件。写入过程网关会重启并清空原有网络配置, 若网络不通需要重新重置网关才能再次配网。",
                           confirmTitle: "开始配网") {
            Task { await provision() }
        }
    }

    private func confirmReboot(_ g: Gateway) {
        guard !running else { return }
        confirmDestructive("重启网关",
                           "将重启「\(g.name.isEmpty ? "智能网关" : g.name)」。网关会短暂离线, 此期间无法远程开锁。",
                           confirmTitle: "重启") {
            Task { await reboot(g) }
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
            _ = try await HardwareService.shared.provisionGateway(ssid: ssid, password: pwd) { s in
                steps.append(s)
            }
            ssid = ""; pwd = ""
            withAnimation(XMotion.soft) { confirmed = false }
            XHaptics.success()
            app.showToast("配网指令已被网关接受 · 正在用「\(sentWifi)」重连, 联网状态稍后在下方列表复核")
        } catch {
            self.error = error.localizedDescription
            XHaptics.failure()
        }
        reload()
    }

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
            XHaptics.success()
            app.showToast("重启成功")
        } catch {
            XHaptics.failure()
            app.showToast("重启失败: \(error.localizedDescription)")
        }
        reload()
    }
}
