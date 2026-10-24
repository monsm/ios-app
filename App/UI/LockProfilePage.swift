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
    @Environment(\.dynamicTypeSize) private var typeSize

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
        XScreen("锁档案", subtitle: "这台锁的名字 / 符号 / 配色") {
                plaque.xScrollLift()
                // 六图改造 (2026-10-23): 加**图 5 双列 MetricCard**（电量 / 信号）。
                //
                // 图 5 的 Step Count / Step Distance 就是「44px 数字 + 迷你环 + 副标」并排。
                // 锁档案之前只有一排 11pt 小胶囊（电量% / 锁态 / 固件），
                // 三个信息等重、都很小 —— 而"这把锁还有多少电"是回家路上最想知道的。
                fpCapacityCard.xScrollLift()
                identityFactsCard.xScrollLift()
                metricsCards.xScrollLift()
                identitySection.xScrollLift()
                symbolSection.xScrollLift()
                colorSection.xScrollLift()
                moreSection.xScrollLift()
                saveButton.xScrollLift()
        }
        }
        .onAppear { if !loaded { load() } }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 锁牌 (视觉主角)
    // ═══════════════════════════════════════════════════════

    private var plaque: some View {
        let tint = LockArchive.swatchColor(colorKey)
        return VStack(spacing: XSpace.m) {
            ZStack {
                // 圆盘只在**用符号时**出现 —— 3D 图自带体积与落地影，
                // 底下再垫一个 96pt 的彩色圆盘，盘边会从图的外缘露出来，
                // 读成「图没对齐」而不是「锁放在圆盘上」。
                if !symbol.isEmpty {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.9), tint.opacity(0.6)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 96, height: 96)
                }
                // 规范 7.8 通用自检: 环/圆盘**不得有投影，只用辉光**。
                // 这是全页的视觉主角 (锁牌), 18pt 的彩色投影在纯黑上会糊成一圈
                // 与主题色同色的脏边; 换成 radial 辉光才是「它在发光」。
                // 辉光独立于圆盘 —— 3D 图态下只有辉光没有盘。
                Circle()
                    .fill(XGradient.glow(tint))
                    .frame(width: 168, height: 168)
                    .blur(radius: 22)
                    .allowsHitTesting(false)

                // ── 主视觉：3D 锁具渲染图（默认符号时）/ SF Symbol（用户选了别的符号时）──
                //
                // 规范 §6.4.3 要求「主体亮度高于卡片底色 >=3 档」且**背景透明**。
                // 这张图是 three.js 在无头 Edge 里渲的（tools/prism/lock.html）：
                // 深钛锁体 + 铜色锁芯，左上方单一主光，抠成透明底，1x/2x/3x 同源。
                //
                // 为什么只在默认符号时用：用户能从七个符号里挑（家/楼栋/车库/办公/钥匙/
                // 布防/侧门）。挑了「车库」却还显示一把锁，那是把功能吃了。
                // 所以 —— 默认态给主视觉，选了别的符号就回到符号。
                if symbol.isEmpty {
                    Image("LockHero")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150, height: 150)
                        // 150pt：图带落地影，比 96 的盘大一圈。默认态不画盘，
                        // 所以这 150 是它对整行的占位高度，也是辉光的内切尺寸。
                        .offset(y: -6)
                        .contentTransition(.opacity)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: XMetric.decorIcon(46), weight: .medium))
                        .foregroundStyle(XPalette.onAccent)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .animation(XMotion.summon, value: symbol)
            .animation(XMotion.summon, value: colorKey)
            .accessibilityHidden(true)

            VStack(spacing: XSpace.xxs) {
                Text(trimmed.isEmpty ? "未命名" : trimmed)
                    .xFont(.display, weight: .semibold)
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

    private var symbolSection: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                sectionTitle("符号", icon: "sparkles")

                // 规范 §13.1 AX1：多列网格 → 单列。5 列在无障碍字号下每格不足 40pt，
                // 图标本身还在，但下面那行符号名会被压成竖排。
                // 按 AX 档降列而不是缩字号 —— 缩字号等于拒绝放大。
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: XSpace.rowGap),
                                         count: typeSize.isAccessibilitySize ? 3 : 5),
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
                sectionTitle("配色", icon: "paintpalette")

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
                                // 色板圆点视觉最大 40pt（选中态），差 4pt。
                                // 加透明外圈补到 44：圆点看着还是那么大，手指够得着。
                                .frame(width: XHit.min, height: XHit.min)
                                .contentShape(Circle())
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
