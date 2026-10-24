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
            XPalette.canvasGradient.ignoresSafeArea()

        // 2026-10-23：改用 XScreen（规范 §5.3 骨架 / §5.4 对齐线）。
        // 改前是手写 ScrollView + VStack(section) + 各自的 padding 与 background。
        XScreen("锁档案", subtitle: "这台锁的名字与真实读数") {
                // ═══ 2026-10-24 逐页对齐 HTML 21-lock-profile 的**卡片顺序** ═══
                //
                // HTML 的顺序是：①指纹余量 → ②锁牌(大图) → ③身份 → ④符号 → ⑤配色 → ⑥更多
                // 真机此前把**锁牌放第一**、指纹余量第二 —— 正好反了。
                //
                // 为什么 HTML 把指纹余量放最前：它是这一页唯一带"锁里还剩几个槽位"的
                // **容量读数**（12 可录 / 38 已用 of 50），是用户来这里的第一目的；
                // 而锁牌是视觉主角，放在第二屏位置反而更耐看（先给数据，再给形象）。
                // ═══ 2026-10-24 坚决精简 ═══
                //
                // 用户裁定「保留锁的真实信息即可」。原 App 的锁设置只有「改设备名 + 删除设备」。
                // 删掉纯视觉定制：锁牌（3D 视觉主角）/ 符号选择 / 配色选择 —— 这三块原 App 完全没有。
                // 留下的是这把锁**是什么**：指纹余量 · 电量信号读数 · 身份事实 · 状态条 · 改名 · 删除。
                fpCapacityCard.xScrollLift()
                identityFactsCard.xScrollLift()
                metricsCards.xScrollLift()
                statusStrip.xScrollLift()
                identitySection.xScrollLift()
                moreSection.xScrollLift()
                saveButton.xScrollLift()
        }
        }
        .onAppear { if !loaded { load() } }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 锁牌 (视觉主角)
    // ═══════════════════════════════════════════════════════


    // ═══════════════════════════════════════════════════════
    // MARK: - 身份
    // ═══════════════════════════════════════════════════════

    /// 实时状态条（电量 / 锁态 / 固件 / 凭证容量）
    ///
    /// 数据来自 DB.readStatus —— 本页原来完全没读实时状态。
    @ViewBuilder
    /// 图 5 双列 MetricCard：电量 / 信号
    private var metricsCards: some View {
        let snap = DB.readStatus(mac)
        let power = snap?.powerLevel ?? -1
        let fw = snap?.firmware ?? ""
        return HStack(spacing: XSpace.s) {
            XPanel(kind: .group) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("电量").xFont(.caption, weight: .medium)
                        .foregroundStyle(XPalette.textSub)
                    XHeroNumber(
                        text: power >= 0 ? String(power) : "—",
                        color: power < 0 ? XPalette.textTertiary
                            : (power <= 20 ? XPalette.danger : (power <= 40 ? XPalette.warn : XPalette.ok)),
                        unit: "%")
                    Text(power < 0 ? "还没读到" : (power <= 20 ? "需要换电池" : "还够用"))
                        .xFont(.caption2)
                        .foregroundStyle(XPalette.textTertiary)
                    XGradientDial(size: 44, progress: power >= 0 ? Double(power) / 100 : 0.02,
                                  widthRatio: 0.14, showsCursor: false, showsTick: false)
                        .opacity(0.9)
                }
            }
            XPanel(kind: .group) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("固件").xFont(.caption, weight: .medium)
                        .foregroundStyle(XPalette.textSub)
                    Text(fw.isEmpty ? "—" : fw)
                        .font(.system(size: XMetric.dataText(22), weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(fw.isEmpty ? XPalette.textTertiary : XPalette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(fw.isEmpty ? "还没读到" : "锁端版本")
                        .xFont(.caption2)
                        .foregroundStyle(XPalette.textTertiary)
                    Image(systemName: "cpu")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(XPalette.textTertiary)
                        .frame(height: 44)
                }
            }
        }
    }

    /// HTML 对齐 (2026-10-24): 补「指纹余量」卡 —— HTML 21-lock-profile 的第一张卡。
    /// 安全的名字（keychains 为空时给占位，不取 [0] 索引）
    private var nameText: String {
        guard let kc = DB.keychains().first(where: { $0.mac == mac }) else { return "未选锁" }
        return LockArchive.displayName(kc)
    }

    private var fpCapacityCard: some View {
        let snap = DB.readStatus(mac)
        let cap = snap?.fpCap ?? 0
        let left = snap?.fpStock ?? -1
        let used = cap > 0 && left >= 0 ? max(0, cap - left) : 0
        return XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: 0) {
                Text("指纹余量")
                    .xFont(.subheadline)
                    .foregroundStyle(XPalette.textTertiary)
                HStack(alignment: .center, spacing: XSpace.l) {
                    VStack(alignment: .leading, spacing: 8) {
                        XHeroNumber(
                            text: cap > 0 ? String(left) : "—",
                            color: left <= 0 && cap > 0 ? XPalette.warn : XPalette.ok,
                            unit: "枚可录")
                        Text(cap > 0 ? "已用 \(used) / \(cap)" : "还没读到锁容量")
                            .xFont(.footnote)
                            .foregroundStyle(XPalette.textTertiary)
                    }
                    Spacer(minLength: 4)
                    XGradientDial(
                        size: 62,
                        progress: cap > 0 ? Double(used) / Double(max(1, cap)) : 0.02,
                        widthRatio: 0.14, showsCursor: false, showsTick: false
                    ) { EmptyView() }
                    .accessibilityHidden(true)
                }
                .padding(.top, 8)
            }
        }
    }

    /// HTML 对齐 (2026-10-24): 「锁态 / 名字」两列（HTML 21-lock-profile 的身份卡）
    private var identityFactsCard: some View {
        let snap = DB.readStatus(mac)
        let rc = snap?.rc
        return XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                Text("身份")
                    .xFont(.subheadline)
                    .foregroundStyle(XPalette.textTertiary)
                HStack(alignment: .top, spacing: XSpace.s) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("名字").xFont(.caption2).foregroundStyle(XPalette.textTertiary)
                        // 只用本页已有的 mac，不做 keychain 兜底（placeholderKC 不存在）
                        Text(nameText)
                            .xFont(.footnote, weight: .semibold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("锁态").xFont(.caption2).foregroundStyle(XPalette.textTertiary)
                        Text(rc == nil ? "未知" : lockStateText(rc!))
                            .xFont(.footnote, weight: .semibold)
                            .foregroundStyle(rc == 0 ? XPalette.ok : XPalette.warn)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

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
            // 规范 §10：图标最小 12pt（原 9pt 低于档位下限）。
            Image(systemName: icon)
                .font(.system(size: XIcon.xs, weight: .medium))
            Text(text)
                .xFontExact(.caption2.monospacedDigit())
        }
        .foregroundStyle(tone)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(XPalette.surfaceAlt))
    }

    /// 锁态文案（与 LocksPage / 门面同口径）
    /// 锁态文案的唯一实现在 StatusParser（rc 是协议语义，不属于某个页面）。
    private func lockStateText(_ rc: Int) -> String { StatusParser.lockStateText(rc) }

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


    // ═══════════════════════════════════════════════════════
    // MARK: - 色标
    // ═══════════════════════════════════════════════════════


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
