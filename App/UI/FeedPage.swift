//
//  FeedPage.swift
//  动态消息 · 全新重写 (2026-10-21)
//
//  ═══════════════════════════════════════════════════════════
//  视觉冲击力: 跨锁事件流, 告警用左侧光条竖穿行高
//  ═══════════════════════════════════════════════════════════
//
//  旧版: List + 小圆点 + 两行文字
//
//  新版: 一张卡片式事件流
//    · 每条一行高 72pt, 左侧 4pt 竖条 (告警橙/普通铜)
//    · 事件名 17pt, 副行是 时间 · 锁名
//    · 告警行: 左侧竖条发光 + 图标, 三通道
//    · 顶部一条"共 N 条动态"的统计条
//

import SwiftUI

/// 动态消息页
struct FeedPage: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showAddDevice = false
    @State private var filterAlarm = false

    struct FeedRow: Identifiable {
        var id: String
        var text: String
        var time: String
        var lockName: String
        var warn: Bool
    }

    var body: some View {
        ZStack {
            XPalette.canvas.ignoresSafeArea()

            if rows.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: XSpace.m) {
                        headerBar
                        LazyVStack(spacing: XSpace.s) {
                            ForEach(displayRows) { r in
                                feedRow(r)
                            }
                        }
                    }
                    .padding(.horizontal, XSpace.gutter)
                    .padding(.vertical, XSpace.l)
                }
            }
        }
        .navigationTitle("动态")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    XToggle("只看告警", isOn: $filterAlarm)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("筛选")
            }
        }
        .sheet(isPresented: $showAddDevice) {
            NavigationStack {
                AddLockPage()
                    .environmentObject(app)
            }
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 头部
    // ═══════════════════════════════════════════════════════

    private var headerBar: some View {
        let alarmCount = rows.filter { $0.warn }.count
        return HStack(spacing: XSpace.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(displayRows.count) 条动态")
                    .xFont(.headline)
                    .foregroundStyle(XPalette.text)
                if alarmCount > 0 {
                    Text("\(alarmCount) 条告警")
                        .xFont(.caption)
                        .foregroundStyle(XPalette.warn)
                }
            }
            Spacer()
        }
        .padding(.bottom, XSpace.xs)
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 行
    // ═══════════════════════════════════════════════════════

    private func feedRow(_ r: FeedRow) -> some View {
        HStack(spacing: 0) {
            // 左侧竖条 (告警橙 / 普通铜)
            RoundedRectangle(cornerRadius: 2)
                .fill(r.warn ? XPalette.warn : XPalette.accent.opacity(0.6))
                .frame(width: 4)
                .shadow(color: r.warn ? XPalette.warn.opacity(0.5) : .clear, radius: 6)

            HStack(spacing: XSpace.m) {
                VStack(alignment: .leading, spacing: XSpace.xxs) {
                    HStack(spacing: XSpace.xs) {
                        if r.warn {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: XIcon.xs, weight: .semibold))
                                .foregroundStyle(XPalette.warn)
                                .accessibilityHidden(true)
                        }
                        Text(r.text)
                            .xFont(.body, weight: r.warn ? .medium : .regular)
                            .foregroundStyle(XPalette.text)
                            .lineLimit(2)
                    }
                    HStack(spacing: XSpace.xs) {
                        Text(r.time)
                            .xFont(.caption.monospacedDigit())
                            .foregroundStyle(XPalette.textSub)
                        Text("·")
                            .foregroundStyle(XPalette.textTertiary)
                        Text(r.lockName)
                            .xFont(.caption)
                            .foregroundStyle(XPalette.textSub)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, XSpace.card)
            .padding(.vertical, XSpace.m)
        }
        .frame(minHeight: 72)
        .background(
            RoundedRectangle(cornerRadius: XRadius.control, style: .continuous)
                .fill(XPalette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: XRadius.control, style: .continuous)
                        .strokeBorder(r.warn ? XPalette.warn.opacity(0.3) : XPalette.hairline,
                                      lineWidth: 1))
        )
        .clipShape(RoundedRectangle(cornerRadius: XRadius.control, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(r.warn ? "告警: \(r.text), \(r.time), \(r.lockName)"
                                   : "\(r.text), \(r.time), \(r.lockName)")
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 空态
    // ═══════════════════════════════════════════════════════

    private var emptyState: some View {
        VStack(spacing: XSpace.l) {
            Image(systemName: "bell.slash")
                .font(.system(size: XMetric.decorIcon(64), weight: .ultraLight))
                .foregroundStyle(XPalette.textTertiary)
                .accessibilityHidden(true)
            Text("还没有动态")
                .xFont(.title3, weight: .semibold)
                .foregroundStyle(XPalette.text)
            Text("连接门锁读取记录后, 这里会汇总全部门锁的开门与告警事件。")
                .xFont(.subheadline)
                .foregroundStyle(XPalette.textSub)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, XSpace.xxl)
            Button("去添加门锁") { showAddDevice = true }
                .buttonStyle(XPrimaryButtonStyle(fullWidth: false))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 数据
    // ═══════════════════════════════════════════════════════

    private var displayRows: [FeedRow] {
        filterAlarm ? rows.filter { $0.warn } : rows
    }

    private var rows: [FeedRow] {
        var out = [FeedRow]()
        for kc in DB.keychains() {
            let devName = kc.name.isEmpty
                ? PidMap.productName(kc.pid) + " …" + kc.mac.suffix(4)
                : kc.name
            for l in DB.readLogs(kc.mac) {
                let warn = StatsKit.alarmTypes.contains(l.type)
                out.append(FeedRow(
                    id: kc.mac + "#\(l.idxRaw)",
                    text: l.typeName,
                    time: l.lockTimeStr,
                    lockName: devName,
                    warn: warn))
            }
        }
        return out.sorted { $0.time > $1.time }
    }
}
