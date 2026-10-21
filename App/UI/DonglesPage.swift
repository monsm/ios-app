//
//  DonglesPage.swift
//  蓝牙钥匙串 · 全新重写 (2026-10-21)
//
//  ═══════════════════════════════════════════════════════════
//  视觉冲击力: 每枚钥匙串是一张"硬件名片"
//  ═══════════════════════════════════════════════════════════
//
//  旧版: List + 三行文字 + 三个 MetricTile 挤在行内 + 长按菜单
//
//  新版:
//    · 每枚钥匙串一张卡: 顶部 56pt 钥匙图标 (已配钥匙时铜色发光)
//    · 电量做一条 4pt 横条 (低电橙/危险红), 不是纯数字
//    · 钥匙存量用 "3 / 8" 形式, 两侧独立缺失时显示 "—"
//    · 动作全部收进行的 Menu (读状态/写钥匙/查钥匙/删钥匙)
//    · 空态: 一大枚钥匙轮廓 + 引导
//

import SwiftUI

/// 蓝牙钥匙串页
struct DonglesPage: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var dongles: [Dongle] = []
    @State private var busy = false

    var body: some View {
        ZStack {
            XPalette.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: XSpace.l) {
                    headerCard.xScrollLift()

                    if app.current == nil {
                        noLockBanner.xScrollLift()
                    }

                    if dongles.isEmpty {
                        emptyState.xScrollLift()
                    } else {
                        ForEach(dongles) { d in
                            dongleCard(d)
                        }
                    }
                }
                .padding(.horizontal, XSpace.gutter)
                .padding(.vertical, XSpace.l)
            }
        }
        .navigationTitle("蓝牙钥匙串")
        .navigationBarTitleDisplayMode(.inline)
        .task { reload() }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 头部
    // ═══════════════════════════════════════════════════════

    private var headerCard: some View {
        XPanel(kind: .hero) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                HStack(spacing: XSpace.m) {
                    ZStack {
                        Circle()
                            .fill(XPalette.accent.opacity(0.12))
                            .frame(width: 56, height: 56)
                        Image(systemName: "key.horizontal.fill")
                            .font(.system(size: XMetric.decorIcon(24), weight: .medium))
                            .foregroundStyle(XPalette.accentText)
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("随身开门")
                            .xFont(.headline)
                            .foregroundStyle(XPalette.text)
                        Text("钥匙串靠近门锁即可开门, 不用掏手机")
                            .xFont(.footnote)
                            .foregroundStyle(XPalette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                XBusyButton(title: busy ? "搜索中…" : "搜索钥匙串",
                            systemImage: "antenna.radiowaves.left.and.right",
                            busy: busy, style: .primary) {
                    Task { await scan() }
                }
                .disabled(busy)
            }
        }
    }

    private var noLockBanner: some View {
        HStack(alignment: .top, spacing: XSpace.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: XIcon.sm, weight: .semibold))
                .foregroundStyle(XPalette.warn)
                .accessibilityHidden(true)
            Text("尚未配对门锁 — 写入钥匙前需先配对门锁。")
                .xFont(.footnote)
                .foregroundStyle(XPalette.warn)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(XSpace.card)
        .background(XPalette.warn.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: XRadius.control, style: .continuous))
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 钥匙串卡
    // ═══════════════════════════════════════════════════════

    private func dongleCard(_ d: Dongle) -> some View {
        let hasKey = !d.lastKeyLock.isEmpty
        return VStack(alignment: .leading, spacing: XSpace.m) {
            // 标题行
            HStack(spacing: XSpace.s) {
                Image(systemName: "key.horizontal.fill")
                    .font(.system(size: XIcon.md, weight: .medium))
                    .foregroundStyle(hasKey ? XPalette.accent : XPalette.textTertiary)
                    .frame(width: 40, height: 40)
                    .background(
                        (hasKey ? XPalette.accent : XPalette.textTertiary).opacity(0.12),
                        in: Circle())
                    .shadow(color: hasKey ? XPalette.accent.opacity(0.3) : .clear, radius: 8)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(d.name.isEmpty ? "钥匙串" : d.name)
                        .xFont(.body, weight: .medium)
                        .foregroundStyle(XPalette.text)
                    Text(dongleDisplay(d.mac))
                        .xFont(.caption.monospaced())
                        .foregroundStyle(XPalette.textSub)
                }

                Spacer(minLength: 0)

                if hasKey {
                    XStatusPill(text: "已配钥匙", tone: .ok)
                }

                Menu {
                    Button("读取状态") { Task { await readStatus(d) } }
                    Button("给当前门锁写入钥匙") { confirmWriteKey(d) }
                    Button("查询全部钥匙") { Task { await listKeys(d) } }
                    Divider()
                    Button("删除本锁钥匙", role: .destructive) { confirmDeleteKey(d) }
                    Button("删除记录", role: .destructive) { removeRecord(d) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: XIcon.md, weight: .medium))
                        .foregroundStyle(XPalette.textSub)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("更多操作")
            }

            // 读数区
            if let st = d.stat {
                VStack(spacing: XSpace.s) {
                    // 电量横条
                    HStack(spacing: XSpace.s) {
                        Image(systemName: batteryIcon(st.power))
                            .font(.system(size: XIcon.sm, weight: .medium))
                            .foregroundStyle(batteryTone(st.power).color)
                            .accessibilityHidden(true)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(XPalette.surfaceSunken)
                                if st.power >= 0 {
                                    Capsule()
                                        .fill(batteryTone(st.power).color)
                                        .frame(width: geo.size.width * CGFloat(min(max(st.power, 0), 100)) / 100)
                                }
                            }
                        }
                        .frame(height: 6)

                        Text(st.power < 0 ? "—" : "\(st.power)%")
                            .xFont(.caption.monospacedDigit())
                            .foregroundStyle(XPalette.textSub)
                            .frame(width: 40, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("电量 \(st.power < 0 ? "未知" : "\(st.power)%")")

                    HStack(spacing: XSpace.m) {
                        readPair("钥匙存量", keyCountText(st))
                        readPair("固件", st.firmware.isEmpty ? "—" : st.firmware)
                    }
                }
            }
        }
        .padding(XSpace.card)
        .background(
            RoundedRectangle(cornerRadius: XRadius.card, style: .continuous)
                .fill(XPalette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: XRadius.card, style: .continuous)
                        .strokeBorder(hasKey ? XPalette.accent.opacity(0.3) : XPalette.hairline,
                                      lineWidth: 1))
        )
    }

    private func readPair(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .xFont(.caption2)
                .foregroundStyle(XPalette.textTertiary)
            Text(value)
                .xFont(.caption.monospacedDigit())
                .foregroundStyle(XPalette.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func keyCountText(_ st: DongleStat) -> String {
        // 两侧独立解析 (KLV#24/#25 各默认 -1), "读到存量没读到上限" 是正常回字
        if st.ekeyCount < 0 { return "—" }
        if st.ekeyAmount < 0 { return "\(st.ekeyCount) / —" }
        return "\(st.ekeyCount) / \(st.ekeyAmount)"
    }

    private func batteryIcon(_ p: Int) -> String {
        if p < 0 { return "battery.0" }
        if p <= 10 { return "battery.25" }
        if p <= 50 { return "battery.50" }
        if p <= 90 { return "battery.75" }
        return "battery.100"
    }

    private func batteryTone(_ p: Int) -> XToneColor {
        if p < 0 { return .neutral }
        if p <= 20 { return .danger }
        if p <= 40 { return .warn }
        return .ok
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 空态
    // ═══════════════════════════════════════════════════════

    private var emptyState: some View {
        VStack(spacing: XSpace.l) {
            Image(systemName: "key.slash")
                .font(.system(size: XMetric.decorIcon(64), weight: .ultraLight))
                .foregroundStyle(XPalette.textTertiary)
                .accessibilityHidden(true)
            Text("还没有钥匙串")
                .xFont(.title3, weight: .semibold)
                .foregroundStyle(XPalette.text)
            Text("上电后点上方「搜索钥匙串」即可添加")
                .xFont(.subheadline)
                .foregroundStyle(XPalette.textSub)
                .multilineTextAlignment(.center)
            Button("搜索钥匙串") { Task { await scan() } }
                .buttonStyle(XPrimaryButtonStyle(fullWidth: false))
                .disabled(busy)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, XSpace.xxl)
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 逻辑 (与旧实现等价)
    // ═══════════════════════════════════════════════════════

    private func dongleDisplay(_ hex: String) -> String {
        let b = HexKit.bytes(hex).reversed()
        return b.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    private func reload() { dongles = DB.dongles() }

    private func confirmWriteKey(_ d: Dongle) {
        guard !busy else { return }
        let lockName = app.displayName
        confirmDestructive("写入钥匙",
                           "将把「\(lockName)」的门锁密钥写入钥匙串「\(d.name.isEmpty ? "钥匙串" : d.name)」。写入后该钥匙串可独立开门, 且本机无法撤销。",
                           confirmTitle: "确认写入") {
            Task { await writeKey(d) }
        }
    }

    private func confirmDeleteKey(_ d: Dongle) {
        guard !busy else { return }
        confirmDestructive("删除本锁钥匙",
                           "将清除钥匙串「\(d.name.isEmpty ? "钥匙串" : d.name)」中「\(app.displayName)」的钥匙。删除后该钥匙串无法开这把锁。",
                           confirmTitle: "删除") {
            Task { await deleteKey(d) }
        }
    }

    private func removeRecord(_ d: Dongle) {
        guard !busy else { return }
        confirmDestructive("删除记录",
                           "将从本机删除钥匙串「\(d.name.isEmpty ? "钥匙串" : d.name)」(\(dongleDisplay(d.mac))) 的记录。不影响钥匙串硬件本身。",
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
        guard let kc = app.current else { app.showToast("请先选择门锁"); return }
        guard !busy else { return }
        guard !kc.skey.isEmpty, kc.pid != 0 else { app.showToast("请先配对门锁"); return }
        busy = true
        defer { busy = false }
        do {
            try await HardwareService.shared.writeDongleKey(dongleMac: d.mac, lock: kc, trackId: UInt32(0))
            XHaptics.success()
            app.showToast("设置成功: 该钥匙串现已开启「\(app.displayName)」")
        } catch {
            XHaptics.failure()
            app.showToast("失败: \(error.localizedDescription)")
        }
        reload()
    }

    private func deleteKey(_ d: Dongle) async {
        guard let kc = app.current else { app.showToast("请先选择门锁"); return }
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await HardwareService.shared.deleteDongleKey(dongleMac: d.mac, lock: kc)
            XHaptics.success()
            app.showToast("已删除该门锁的钥匙")
        } catch {
            XHaptics.failure()
            app.showToast("失败: \(error.localizedDescription)")
        }
        reload()
    }

    private func listKeys(_ d: Dongle) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let macs = try await HardwareService.shared.dongleKeys(dongleMac: d.mac, lockMac: nil)
            app.showToast(macs.isEmpty ? "没有查询到钥匙" : "共 \(macs.count) 把钥匙")
        } catch {
            app.showToast("失败: \(error.localizedDescription)")
        }
        reload()
    }
}
