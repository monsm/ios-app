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
                identityCard.xScrollLift()
                attentionCard.xScrollLift()
                capacityCard
                metricsRow.xScrollLift()
                detailSection.xScrollLift()
                recentSection.xScrollLift()
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
                        .xFont(.title2, weight: .semibold)
                        .foregroundStyle(XPalette.text)
                        .lineLimit(1)

                    Spacer(minLength: XSpace.s)

                    connectionPill
                }

                // 连接详情
                if let detail = connectionDetail {
                    Text(detail)
                        .xFont(.footnote)
                        .foregroundStyle(XPalette.textSub)
                }

                Divider().overlay(XPalette.hairline)

                // 电量仪表环 + 两个余量读数
                //
                // 电量原来是三个并排数字里的一个, 看不出"还剩多少余量";
                // 弧形能。余量类读数 (密码/指纹) 没有"耗尽感", 保持数字形态。
                HStack(alignment: .center, spacing: XSpace.l) {
                    XBatteryGauge(level: snap?.powerLevel, size: 116)
                
                    VStack(alignment: .leading, spacing: XSpace.m) {
                        readingItem2(
                            value: snap.map { "\($0.pwdStock)" } ?? "—",
                            label: "密码余量",
                            icon: "number.square")
                        readingItem2(
                            value: snap.map { "\($0.fpStock)" } ?? "—",
                            label: "指纹余量",
                            icon: "touchid")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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



    /// 带图标的余量读数 (电量已独立成仪表环, 这里只剩两个余量)
    /// 卡片小标题（本文件原来没有这个辅助，capacityCard 用了才补）
    private func secLabel(_ text: String) -> some View {
        Text(text)
            .xFont(.caption, weight: .semibold)
            .foregroundStyle(XPalette.textTertiary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func readingItem2(value: String, label: String, icon: String) -> some View {
        HStack(spacing: XSpace.s) {
            Image(systemName: icon)
                .font(.system(size: XIcon.sm, weight: .medium))
                .foregroundStyle(XPalette.textTertiary)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .xFont(.headline, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(XPalette.text)
                Text(label)
                    .xFont(.caption2)
                    .foregroundStyle(XPalette.textSub)
            }
            Spacer(minLength: 0)
        }
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
                                    .xFont(.subheadline, weight: .medium)
                                    .foregroundStyle(XPalette.text)
                                Text(item.detail)
                                    .xFont(.caption)
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

    // ── 容量占用格子表 ──
    //
    // 协议真实返回 pwdInfoCapacity / pwdStock / fpInfoCapacity / fpStock
    // (StatusParser 0x25/0x28)。这是全 App 唯一揭示"锁的物理限额"的数据，
    // 原来只显示成两个数字 —— 用户看不出"还剩几个坑位"。
    //
    // 格子表把容量变成可数的东西:
    //   已占用 → 实色格；剩余 → 凹陷虚线格
    //   一行小字: "还可录 3 枚指纹"
    private var capacityCard: some View {
        // StatusSnapshotData 的真实字段是 pwdCap / fpCap (**可选 Int**)，
        // 不是 pwdInfoCapacity / fpInfoCapacity —— 后者在 StatusParser 的另一个结构上。
        let pwdCap = snap?.pwdCap ?? 0
        let fpCap = snap?.fpCap ?? 0
        let pwdLeft = snap?.pwdStock ?? 0
        let fpLeft = snap?.fpStock ?? 0
        // 容量未知（0）时整卡隐去 —— 不画一个空壳
        return Group {
            if pwdCap > 0 || fpCap > 0 {
                XPanel(kind: .group) {
                    VStack(alignment: .leading, spacing: XSpace.m) {
                        secLabel("锁内容量")
                        if pwdCap > 0 {
                            capacityRow(label: "密码", cap: pwdCap, left: pwdLeft, icon: "number.square")
                        }
                        if fpCap > 0 {
                            capacityRow(label: "指纹", cap: fpCap, left: fpLeft, icon: "touchid")
                        }
                    }
                }
                .xScrollLift()
            }
        }
    }

    /// 一行容量格子 + 结论文字
    private func capacityRow(label: String, cap: Int, left: Int, icon: String) -> some View {
        let used = max(0, cap - left)
        let tone: Color = left == 0 ? XPalette.danger
            : (left <= 1 ? XPalette.warn : XPalette.textSub)
        return VStack(alignment: .leading, spacing: XSpace.xs) {
            HStack(spacing: XSpace.s) {
                Label(label, systemImage: icon)
                    .xFont(.caption, weight: .medium)
                    .foregroundStyle(XPalette.textSub)
                Spacer(minLength: 0)
                Text("\(used) / \(cap)")
                    .xFont(.caption.monospacedDigit())
                    .foregroundStyle(XPalette.textTertiary)
            }
            // 格子条：已占用实色，剩余凹陷
            HStack(spacing: 3) {
                ForEach(0..<cap, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(i < used ? XPalette.accent.opacity(0.75) : XPalette.surfaceAlt)
                        .frame(maxWidth: .infinity)
                        .frame(height: 14)
                        .overlay {
                            if i >= used {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .strokeBorder(XPalette.hairline, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                            }
                        }
                }
            }
            .frame(height: 14)
            Text(left == 0 ? "已满 —— 新增前请先删除一条" : "还可录 " + String(left) + (label == "指纹" ? " 枚" : " 条"))
                .xFont(.caption2)
                .foregroundStyle(tone)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label + " 已用 " + String(used) + " 共 " + String(cap) + ", " + (left == 0 ? "已满" : "剩余 " + String(left)))
    }

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

    /// 近 30 天里单日掉电超过 20% 的日子（最多列 3 条）。
    private var bigDrops: [(day: String, from: Int, to: Int, drop: Int)] {
        mac.isEmpty ? [] : BatteryCare.bigDropDays(mac)
    }

    private var detailSection: some View {
        XPanel(kind: .group) {
            VStack(spacing: 0) {
                Button {
                    withAnimation(XMotion.soft) { detailExpanded.toggle() }
                    XHaptics.tick.impactOccurred()
                } label: {
                    HStack {
                        Text("明细")
                            .xFont(.subheadline, weight: .medium)
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
                        // 1040 单日掉电观察一直被实现、从未被显示。
                        // 它只对"当天至少读到过两次电量"的日子成立（只用真实两个点相减，
                        // 不拟合不外推）—— 所以没数据显示是正常的，别写成"电池健康"之类的结论。
                        if !bigDrops.isEmpty {
                            detailRow("单日掉电 >20%", bigDrops.prefix(3)
                                .map { "\($0.day.suffix(5)) −\($0.drop)%" }
                                .joined(separator: " · "))
                        }
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
                .xFont(.footnote)
                .foregroundStyle(XPalette.textSub)
            Spacer()
            Text(value)
                .xFont(.footnote.monospacedDigit())
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
                    .xFont(.subheadline, weight: .medium)
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
                                    .xFont(.footnote)
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
