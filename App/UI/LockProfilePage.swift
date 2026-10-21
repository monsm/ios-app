//
//  LockProfilePage.swift
//  锁档案 · 全新重写 (2026-10-21)
//
//  ═══════════════════════════════════════════════════════════
//  视觉冲击力: 编辑即所见的大预览
//  ═══════════════════════════════════════════════════════════
//
//  旧版: Form 里一行小预览 + 后续若干 Section, 预览只在顶部一小条。
//
//  新版: 顶部一块 160pt 高的"锁牌"
//    · 符号 56pt 大字, 底色是所选色标的渐变
//    · 昵称 28pt, 场所 15pt
//    · 每次改符号/色标, 锁牌当场变色变形 (spring 动画)
//    · 符号网格与色标行都是视觉重点, 不是多选列表
//

import SwiftUI
import UIKit

/// 锁档案页
struct LockProfilePage: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var place = ""
    @State private var grp = ""
    @State private var note = ""
    @State private var symbol = ""
    @State private var colorKey = ""
    @State private var batteryModel = ""
    @State private var batteryHasDate = false
    @State private var batteryDate = Date()
    @State private var loaded = false

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    private var mac: String { app.currentMac }

    var body: some View {
        ZStack {
            XPalette.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: XSpace.xl) {
                    plaque.xScrollLift()
                    identitySection.xScrollLift()
                    symbolSection.xScrollLift()
                    colorSection.xScrollLift()
                    moreSection.xScrollLift()
                    saveButton.xScrollLift()
                }
                .padding(.horizontal, XSpace.gutter)
                .padding(.vertical, XSpace.l)
            }
        }
        .navigationTitle("锁档案")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if !loaded { load() } }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 锁牌 (视觉主角)
    // ═══════════════════════════════════════════════════════

    private var plaque: some View {
        let tint = LockArchive.swatchColor(colorKey)
        return VStack(spacing: XSpace.m) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.9), tint.opacity(0.6)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 96, height: 96)
                    .shadow(color: tint.opacity(0.4), radius: 18)

                Image(systemName: symbol.isEmpty ? "lock.fill" : symbol)
                    .font(.system(size: XMetric.decorIcon(46), weight: .medium))
                    .foregroundStyle(XPalette.onAccent)
                    .contentTransition(.symbolEffect(.replace))
            }
            .animation(XMotion.summon, value: symbol)
            .animation(XMotion.summon, value: colorKey)
            .accessibilityHidden(true)

            VStack(spacing: XSpace.xxs) {
                Text(trimmed.isEmpty ? "未命名" : trimmed)
                    .xFont(.title, weight: .semibold)
                    .foregroundStyle(XPalette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(place.trimmingCharacters(in: .whitespaces).isEmpty
                     ? "未填场所" : place)
                    .xFont(.subheadline)
                    .foregroundStyle(XPalette.textSub)
                    .lineLimit(1)
            }

            // 状态条 —— 锁档案页只管身份（名字/场所/图标/配色），
            // 但用户在这里最想确认的是"这把锁现在什么状况"。
            // 三个实时读数（电量 / 锁态 / 固件）挤在一行，不抢身份卡的视觉重心。
            statusStrip
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, XSpace.xl)
        .background(
            RoundedRectangle(cornerRadius: XRadius.card, style: .continuous)
                .fill(XPalette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: XRadius.card, style: .continuous)
                        .strokeBorder(tint.opacity(XOpacity.edge), lineWidth: 1))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("预览: \(trimmed.isEmpty ? "未命名" : trimmed), \(place.isEmpty ? "未填场所" : place)")
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 身份
    // ═══════════════════════════════════════════════════════

    /// 实时状态条（电量 / 锁态 / 固件 / 凭证容量）
    ///
    /// 数据来自 DB.readStatus —— 本页原来完全没读实时状态。
    @ViewBuilder
    private var statusStrip: some View {
        let snap = DB.readStatus(mac)
        let hasAny = (snap?.powerLevel ?? -1) >= 0
            || !(snap?.firmware ?? "").isEmpty
        if hasAny {
            HStack(spacing: XSpace.s) {
                if let p = snap?.powerLevel, p >= 0 {
                    statusChip("battery.75", String(p) + "%",
                               tone: p <= 20 ? XPalette.danger : (p <= 40 ? XPalette.warn : XPalette.textSub))
                }
                if let rc = snap?.rc {
                    statusChip(rc == 0 ? "lock.fill" : "lock.open", lockStateText(rc),
                               tone: rc == 0 ? XPalette.ok : XPalette.warn)
                }
                if let f = snap?.firmware, !f.isEmpty {
                    statusChip("cpu", f, tone: XPalette.textSub)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func statusChip(_ icon: String, _ text: String, tone: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .medium))
            Text(text)
                .xFont(.caption2.monospacedDigit())
        }
        .foregroundStyle(tone)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(XPalette.surfaceAlt))
    }

    /// 锁态文案（与 LocksPage / 门面同口径）
    private func lockStateText(_ rc: Int) -> String {
        switch rc {
        case 0: return "已锁"
        case 21, 27: return "反锁"
        case 25: return "忙碌"
        case 26: return "防拆"
        default: return "状态 " + String(rc)
        }
    }

    private var identitySection: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                sectionTitle("身份", icon: "textformat")

                field("昵称", text: $name, placeholder: "如 婆婆家·入户门")
                field("场所副标题", text: $place, placeholder: "如 玄关 / 车库")
                field("分组名", text: $grp, placeholder: "如 家用 / 仓库 / 办公")

                VStack(alignment: .leading, spacing: XSpace.xs) {
                    Text("备注")
                        .xFont(.caption)
                        .foregroundStyle(XPalette.textSub)
                    TextField("换电历史 / 安装细节 / 门锁脾气…", text: $note, axis: .vertical)
                        .xFont(.body)
                        .lineLimit(2...5)
                        .padding(XSpace.s)
                        .background(XPalette.surfaceSunken,
                                    in: RoundedRectangle(cornerRadius: XRadius.min, style: .continuous))
                }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: XSpace.xs) {
            Text(label)
                .xFont(.caption)
                .foregroundStyle(XPalette.textSub)
            TextField(placeholder, text: text)
                .xFont(.body)
                .autocorrectionDisabled()
                .padding(XSpace.s)
                .background(XPalette.surfaceSunken,
                            in: RoundedRectangle(cornerRadius: XRadius.min, style: .continuous))
        }
    }

    private func sectionTitle(_ text: String, icon: String) -> some View {
        HStack(spacing: XSpace.s) {
            Image(systemName: icon)
                .font(.system(size: XIcon.sm, weight: .medium))
                .foregroundStyle(XPalette.accentText)
                .accessibilityHidden(true)
            Text(text)
                .xFont(.subheadline, weight: .medium)
                .foregroundStyle(XPalette.text)
            Spacer()
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 符号
    // ═══════════════════════════════════════════════════════

    private var symbolSection: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                sectionTitle("符号", icon: "sparkles")

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: XSpace.s), count: 5),
                          spacing: XSpace.m) {
                    ForEach(LockArchive.symbols) { s in
                        let selected = symbol == s.name
                        Button {
                            symbol = s.name
                            XHaptics.tick.impactOccurred()
                        } label: {
                            VStack(spacing: XSpace.xxs) {
                                Image(systemName: s.name)
                                    .font(.system(size: XIcon.md, weight: .medium))
                                    .foregroundStyle(selected ? XPalette.onAccent : XPalette.textSub)
                                    .frame(width: 48, height: 48)
                                    .background(
                                        Circle().fill(selected
                                            ? LockArchive.swatchColor(colorKey)
                                            : XPalette.surfaceAlt)
                                    )
                                Text(s.label)
                                    .xFont(.caption2)
                                    .foregroundStyle(selected ? XPalette.text : XPalette.textSub)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .animation(XMotion.quick, value: selected)
                        .accessibilityLabel("符号 \(s.label)")
                        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 色标
    // ═══════════════════════════════════════════════════════

    private var colorSection: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                sectionTitle("色标", icon: "paintpalette")

                HStack(spacing: XSpace.m) {
                    ForEach(LockArchive.swatches) { s in
                        let selected = colorKey == s.key
                        Button {
                            colorKey = s.key
                            XHaptics.tick.impactOccurred()
                        } label: {
                            Circle()
                                .fill(LockArchive.swatchColor(s.key))
                                .frame(width: selected ? 40 : 34, height: selected ? 40 : 34)
                                .overlay(
                                    Circle().strokeBorder(
                                        selected ? XPalette.text : XPalette.hairline,
                                        lineWidth: selected ? 2 : 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .animation(XMotion.summon, value: selected)
                        .accessibilityLabel("色标 \(s.name)")
                        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 更多
    // ═══════════════════════════════════════════════════════

    private var moreSection: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                sectionTitle("更多", icon: "ellipsis.circle")

                XToggle("在翻页里隐藏这把锁", isOn: Binding(
                    get: { LockArchive.isHidden(mac) },
                    set: { LockArchive.setHidden(mac, $0) }))
                    .xFont(.footnote)

                VStack(alignment: .leading, spacing: XSpace.xs) {
                    Text("电池型号")
                        .xFont(.caption)
                        .foregroundStyle(XPalette.textSub)
                    TextField("如 CR2032", text: $batteryModel)
                        .xFont(.body)
                        .padding(XSpace.s)
                        .background(XPalette.surfaceSunken,
                                    in: RoundedRectangle(cornerRadius: XRadius.min, style: .continuous))
                }

                XToggle("记录换电日期", isOn: $batteryHasDate)
                    .xFont(.footnote)

                if batteryHasDate {
                    DatePicker("换电日期", selection: $batteryDate, displayedComponents: .date)
                        .xFont(.subheadline)
                }
            }
        }
    }

    private var saveButton: some View {
        XBusyButton(title: "保存档案", systemImage: "checkmark", busy: false, style: .primary) {
            save()
        }
        .disabled(trimmed.isEmpty)
        .opacity(trimmed.isEmpty ? 0.5 : 1)
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 数据
    // ═══════════════════════════════════════════════════════

    private func load() {
        guard let kc = app.current else { return }
        name = kc.name
        let m = LockArchive.meta(kc.mac)
        place = m.place
        grp = m.grp
        note = m.note
        symbol = m.symbol
        colorKey = m.colorKey
        batteryModel = m.batteryModel
        if m.batteryChangedAt > 0 {
            batteryHasDate = true
            batteryDate = Date(timeIntervalSince1970: m.batteryChangedAt)
        }
        loaded = true
    }

    private func save() {
        let n = trimmed
        guard !n.isEmpty, let kc = app.current else {
            app.showToast("昵称不能为空")
            return
        }
        var kc2 = kc
        kc2.name = n
        DB.saveKeychain(kc2)

        var m = LockArchive.meta(kc.mac)
        m.place = place.trimmingCharacters(in: .whitespaces)
        m.grp = LockArchive.normalizedGroup(grp)
        m.note = note
        m.symbol = symbol
        m.colorKey = colorKey
        m.batteryModel = batteryModel.trimmingCharacters(in: .whitespaces)
        m.batteryChangedAt = batteryHasDate ? batteryDate.timeIntervalSince1970 : 0
        LockArchive.save(kc.mac, m)

        app.loadDevices()
        XHaptics.success()
        app.showToast("档案已保存")
        dismiss()
    }
}
