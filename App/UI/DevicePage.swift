//
//  DevicePage.swift
//  设备页 · 全新重写 (2026-10-21)
//
//  这是门里「这台锁」域的落地页。
//
//  ═══════════════════════════════════════════════════════════
//  与旧 DeviceHomeView (2525 行) 的根本区别
//  ═══════════════════════════════════════════════════════════
//
//  旧版: Hero 翻页卡 + 状态卡 + 快捷操作格 + 模块网格 + 电量条 +
//        信号格 + 唤醒 + 握手角标 + 最近开门 + 关怀行 + 安心夜打卡
//        —— 14 个区块平铺, 用户找不到重点。
//
//  新版: 三层递进
//    ① 这一把锁 (身份 + 连接 + 三个关键读数)  —— 一眼看完
//    ② 需要你处理的 (异常/待办)                —— 只在有时出现
//    ③ 明细 (电量/固件/信号/最近开门)          —— 折叠, 要看才展开
//
//  设计原则 (来自 apple-design / swiftui-pro):
//    · Visual hierarchy: 最重要的在顶部 leading 侧
//    · 条件修饰符不分支视图 (opacity 而非 if)
//    · 每个类型一个文件
//    · 不写魔法数字, 全走 XTheme 令牌
//

import SwiftUI

/// 设备页 —— 门里「这台锁」
struct DevicePage: View {
    @EnvironmentObject private var app: AppState
    @State private var detailExpanded = false

    private var kc: Keychain? { app.current }
    private var mac: String { app.currentMac }
    private var snap: StatusSnapshotData? { mac.isEmpty ? nil : DB.readStatus(mac) }
    private var sense: LinkSense { LinkSense.shared }

    var body: some View {
        ScrollView {
            VStack(spacing: XSpace.l) {
                identityCard
                attentionCard
                metricsRow
                detailSection
                recentSection
            }
            .padding(.horizontal, XSpace.gutter)
            .padding(.vertical, XSpace.l)
        }
        .background(XPalette.canvas)
        .navigationTitle("这台锁")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await refresh() }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - ① 身份卡
    // ═══════════════════════════════════════════════════════

    private var identityCard: some View {
        XPanel(kind: .hero) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                // 锁名 + 连接状态
                HStack(alignment: .firstTextBaseline, spacing: XSpace.s) {
                    Text(kc.map { LockArchive.displayName($0) } ?? "未选择门锁")
                        .vkFont(.title2, weight: .semibold)
                        .foregroundStyle(XPalette.text)
                        .lineLimit(1)

                    Spacer(minLength: XSpace.s)

                    connectionPill
                }

                // 连接详情
                if let detail = connectionDetail {
                    Text(detail)
                        .vkFont(.footnote)
                        .foregroundStyle(XPalette.textSub)
                }

                Divider().overlay(XPalette.hairline)

                // 三个关键读数
                HStack(spacing: XSpace.l) {
                    readingItem(
                        value: snap.map { "\($0.powerLevel)%" } ?? "—",
                        label: "电量",
                        tone: batteryTone)
                    readingItem(
                        value: snap.map { "\($0.pwdStock)" } ?? "—",
                        label: "密码余量",
                        tone: .neutral)
                    readingItem(
                        value: snap.map { "\($0.fpStock)" } ?? "—",
                        label: "指纹余量",
                        tone: .neutral)
                }
            }
        }
    }

    private var connectionPill: some View {
        let (text, tone) = connectionState
        return XStatusPill(text: text, tone: tone, systemImage: tone == .ok ? "checkmark.circle.fill" : "circle.dashed")
    }

    private var connectionState: (String, XToneColor) {
        if sense.linkState == .ready { return ("已连接", .ok) }
        if sense.linkState == .connecting { return ("连接中", .accent) }
        return ("未连接", .neutral)
    }

    private var connectionDetail: String? {
        if let ms = sense.connectMs, sense.linkState == .ready {
            return "握手耗时 \(ms)ms · 信号 \(sense.lastRssi ?? 0) dBm"
        }
        let t = DB.statusTime(mac)
        if t > 0 {
            let mins = Int((Date().timeIntervalSince1970 * 1000 - t) / 60000)
            if mins < 60 { return "数据截至 \(mins) 分钟前" }
            return "数据截至 \(mins / 60) 小时前"
        }
        return nil
    }

    private var batteryTone: XToneColor {
        guard let p = snap?.powerLevel else { return .neutral }
        if p <= 10 { return .danger }
        if p <= 20 { return .warn }
        return .ok
    }

    private func readingItem(value: String, label: String, tone: XToneColor) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .vkFont(.title3, weight: .semibold)
                .monospacedDigit()
                .foregroundStyle(tone == .neutral ? XPalette.text : tone.color)
            Text(label)
                .vkFont(.caption2)
                .foregroundStyle(XPalette.textSub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - ② 需要你处理的
    // ═══════════════════════════════════════════════════════

    @ViewBuilder
    private var attentionCard: some View {
        let items = attentionItems
        if !items.isEmpty {
            XPanel(kind: .group, tone: .warn) {
                VStack(alignment: .leading, spacing: XSpace.s) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: XSpace.s) {
                            Image(systemName: item.icon)
                                .font(.system(size: XIcon.sm, weight: .semibold))
                                .foregroundStyle(item.tone.color)
                                .frame(width: 20)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .vkFont(.subheadline, weight: .medium)
                                    .foregroundStyle(XPalette.text)
                                Text(item.detail)
                                    .vkFont(.caption)
                                    .foregroundStyle(XPalette.textSub)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    private struct AttentionItem {
        let icon: String
        let title: String
        let detail: String
        let tone: XToneColor
    }

    private var attentionItems: [AttentionItem] {
        var out: [AttentionItem] = []
        if let p = snap?.powerLevel, p <= 20 {
            out.append(AttentionItem(
                icon: "battery.25", title: "电量偏低 (\(p)%)",
                detail: "建议尽快更换电池", tone: p <= 10 ? .danger : .warn))
        }
        if let s = sense.lastRssi, s < -85, sense.linkState == .ready {
            out.append(AttentionItem(
                icon: "wifi.exclamationmark", title: "信号很弱",
                detail: "靠近门锁可提升连接稳定性", tone: .warn))
        }
        let unhandled = RecordSearch.unhandledAlarmCount(macs: [mac])
        if unhandled > 0 {
            out.append(AttentionItem(
                icon: "exclamationmark.triangle", title: "\(unhandled) 条告警未处理",
                detail: "到「事件」域查看", tone: .warn))
        }
        return out
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - ③ 关键指标行
    // ═══════════════════════════════════════════════════════

    private var metricsRow: some View {
        HStack(spacing: XSpace.s) {
            XMetricTile(
                value: sense.connectMs.map { "\($0)" } ?? "—",
                label: "握手 ms",
                tone: .neutral,
                systemImage: "bolt.horizontal")
            XMetricTile(
                value: sense.lastRssi.map { "\($0)" } ?? "—",
                label: "信号 dBm",
                tone: .neutral,
                systemImage: "antenna.radiowaves.left.and.right")
            XMetricTile(
                value: snap?.firmware.isEmpty == false ? (snap?.firmware ?? "—") : "—",
                label: "固件",
                tone: .neutral,
                systemImage: "cpu")
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - ④ 明细 (折叠)
    // ═══════════════════════════════════════════════════════

    private var detailSection: some View {
        XPanel(kind: .group) {
            VStack(spacing: 0) {
                Button {
                    withAnimation(XMotion.soft) { detailExpanded.toggle() }
                    XHaptics.tick.impactOccurred()
                } label: {
                    HStack {
                        Text("明细")
                            .vkFont(.subheadline, weight: .medium)
                            .foregroundStyle(XPalette.text)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: XIcon.xs, weight: .semibold))
                            .foregroundStyle(XPalette.textTertiary)
                            .rotationEffect(.degrees(detailExpanded ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("明细")
                .accessibilityValue(detailExpanded ? "已展开" : "已折叠")
                .accessibilityAddTraits(.isButton)

                if detailExpanded {
                    VStack(spacing: 0) {
                        detailRow("锁 ID", mac.isEmpty ? "—" : String(mac.suffix(8)))
                        detailRow("配对时间", kc?.pairedAt.isEmpty == false ? (kc?.pairedAt ?? "—") : "—")
                        detailRow("固件版本", snap?.firmware.isEmpty == false ? (snap?.firmware ?? "—") : "未知")
                        detailRow("安全等级", snap.map { "\($0.securityLevel)" } ?? "—")
                        detailRow("广播模式", snap.map { "\($0.broadcastMode)" } ?? "—")
                    }
                    .padding(.top, XSpace.s)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .vkFont(.footnote)
                .foregroundStyle(XPalette.textSub)
            Spacer()
            Text(value)
                .vkFont(.footnote.monospacedDigit())
                .foregroundStyle(XPalette.text)
                .lineLimit(1)
        }
        .padding(.vertical, XSpace.xs)
        .accessibilityElement(children: .combine)
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - ⑤ 最近开门
    // ═══════════════════════════════════════════════════════

    @ViewBuilder
    private var recentSection: some View {
        let records = app.recentRecords(count: 3)
        if !records.isEmpty {
            VStack(alignment: .leading, spacing: XSpace.s) {
                Text("最近")
                    .vkFont(.subheadline, weight: .medium)
                    .foregroundStyle(XPalette.textSub)
                    .padding(.leading, XSpace.xs)

                XPanel(kind: .group, padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(records.enumerated()), id: \.offset) { idx, r in
                            HStack(spacing: XSpace.s) {
                                Circle()
                                    .fill(r.warn ? XPalette.warn : XPalette.ok)
                                    .frame(width: 6, height: 6)
                                    .accessibilityHidden(true)
                                Text(r.text)
                                    .vkFont(.footnote)
                                    .foregroundStyle(XPalette.text)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, XSpace.card)
                            .padding(.vertical, XSpace.s)
                            .accessibilityElement(children: .combine)

                            if idx < records.count - 1 {
                                XHairline(inset: XSpace.card)
                            }
                        }
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 刷新
    // ═══════════════════════════════════════════════════════

    private func refresh() async {
        guard !mac.isEmpty else { return }
        await sense.preconnect()
    }
}
