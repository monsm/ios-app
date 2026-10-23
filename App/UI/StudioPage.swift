//
//  StudioPage.swift
//  凭证工坊 · 全新重写 (2026-10-21)
//
//  ═══════════════════════════════════════════════════════════
//  视觉冲击力: 四张并排的能力卡, 不是四行列表项
//  ═══════════════════════════════════════════════════════════
//
//  旧版: List + 4 个 fanoutRow (图标 + 标题 + 副标题 + chevron)
//
//  新版: 2×2 网格大卡
//    · 每张卡 150pt 高, 顶部一枚 44pt 图标 (各自配色)
//    · 标题 20pt, 副标题两行
//    · 卡右下角一枚大箭头
//    · 点按时整卡 scale 0.97 + 铜色描边闪烁
//
//  四类的配色各不相同: 密码=铜 / 临时=橙 / 指纹=青 / OTP=紫
//  这是"看一眼就知道点哪个"的设计。
//

import SwiftUI

/// 凭证工坊页
struct StudioPage: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    var embedded: Bool = true

    @State private var showAddPwd = false
    @State private var showTemp = false
    @State private var showFp = false
    @State private var showOtp = false

    @Environment(\.dynamicTypeSize) private var typeSize

    /// 列间距 12 (`XSpace.colGap`)，与行间距 8 (`XSpace.rowGap`) 是两个不同的数。
    /// 规范 §5.1 / 验收 L2 单列了这一项：合并成一个 token 会让纵向堆叠看起来比横向更松，
    /// 而人眼读网格先读列距 —— 列距偏窄时四张卡会挤成一条。
    ///
    /// **规范 §13.1 AX1 规则：双列卡 → 单列。**
    /// 四张能力卡各带标题 + 两行副标题，AX 字号下两列会把副标题压成竖排。
    /// 这不是"降级"——是让同一份内容换一种排法，字号一点不缩。
    private var columns: [GridItem] {
        typeSize.isAccessibilitySize
            ? [GridItem(.flexible(), spacing: XSpace.colGap)]
            : [
                GridItem(.flexible(), spacing: XSpace.colGap),
                GridItem(.flexible(), spacing: XSpace.colGap),
              ]
    }

    var body: some View {
        Group {
            if embedded {
                content
            } else {
                NavigationStack { content }
            }
        }
    }

    /// 图 5 读数卡：四类凭证各自的条数（44px 总数 + 三行彩点）
    private var studioStatsCard: some View {
        let mac = app.current?.mac ?? ""
        let pwN = DB.listPwds(mac).filter { !$0.temp }.count
        let tempN = DB.listPwds(mac).filter { $0.temp }.count
        let fpN = DB.listFps(mac).count
        let otpN = CredentialOrg.totpEntries(mac).count
        let total = pwN + tempN + fpN + otpN
        return XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("全部凭证")
                        .xFont(.subheadline)
                        .foregroundStyle(XPalette.textTertiary)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .center, spacing: XSpace.l) {
                    VStack(alignment: .leading, spacing: 9) {
                        XHeroNumber(
                            text: String(total),
                            color: total == 0 ? XPalette.textTertiary : XPalette.accentText,
                            unit: "份")
                        XDataRow(label: "密码", value: String(pwN), unit: "项", color: XPalette.kindTemp)
                        XDataRow(label: "临时码", value: String(tempN), unit: "个", color: XPalette.kindOtp)
                        XDataRow(label: "指纹", value: String(fpN), unit: "枚", color: XPalette.kindFp)
                    }
                    Spacer(minLength: 4)
                    XTripleThinRing(
                        size: 88,
                        values: (Double(fpN) / Double(max(1, total)),
                                 Double(pwN) / Double(max(1, total)),
                                 Double(tempN) / Double(max(1, total))),
                        colors: (XPalette.kindFp, XPalette.kindTemp, XPalette.kindOtp),
                        centerText: String(total))
                        .accessibilityHidden(true)
                }
                .padding(.top, 8)
                XStatSection {
                    Text("四类凭证各管一段场景 —— 密码最常用，临时码给访客，指纹最快，OTP 给远程。")
                        .xFont(.caption2)
                        .foregroundStyle(XPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var content: some View {
        ZStack {
            XPalette.canvasGradient.ignoresSafeArea()

        // 2026-10-23：改用 XScreen（规范 §5.3 骨架 / §5.4 对齐线）。
        // 改前是手写 ScrollView + VStack(section) + 各自的 padding 与 background。
        XScreen("钥匙工坊") {
                // 六图改造 (2026-10-24): 顶部加**图 5 的四类凭证读数卡**。
                //
                // 工坊是"造东西"的入口页 —— 用户进来第一句想问的是"我现在各有多少"。
                // 之前一进来就是四个入口卡，一个量都没有。
                studioStatsCard
                // 双列网格: 列间距 12 / 行间距 8 (规范 §5.1 两个不同的数)。
                LazyVGrid(columns: columns, spacing: XSpace.rowGap) {
                    card(.pwd)
                    card(.temp)
                    card(.fp)
                    card(.otp)
                }

                footerNote
        }
        }
        .toolbar {
            if !embedded {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showAddPwd) {
            NavigationStack { AddKeyPage().environmentObject(app) }
        }
        .sheet(isPresented: $showTemp) {
            TempCodeStudio().environmentObject(app)
        }
        .sheet(isPresented: $showFp) {
            FpStudio().environmentObject(app)
        }
        .sheet(isPresented: $showOtp) {
            OtpStudio().environmentObject(app)
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 卡片
    // ═══════════════════════════════════════════════════════

    private enum Kind {
        case pwd, temp, fp, otp

        var icon: String {
            switch self {
            case .pwd:  return "key.fill"
            case .temp: return "clock.badge.checkmark"
            case .fp:   return "touchid"
            case .otp:  return "number.square"
            }
        }
        var title: String {
            switch self {
            case .pwd:  return "密码"
            case .temp: return "临时码"
            case .fp:   return "指纹"
            case .otp:  return "OTP 与口令"
            }
        }
        var sub: String {
            switch self {
            case .pwd:  return "逐位回显 · 重复拦截\n可生成随机码"
            case .temp: return "五场景 · 重叠检测\n装修黄条 · 批量下发"
            case .fp:   return "归属先行 · 沉浸录入\n删除双签"
            case .otp:  return "时窗细条 · otpauth\n静态备份码"
            }
        }
        var tint: Color {
            switch self {
            case .pwd:  return XPalette.accent
            case .temp: return XPalette.kindTemp
            case .fp:   return XPalette.kindFp
            case .otp:  return XPalette.kindOtp
            }
        }
    }

    /// 各类凭证的实时数量
    ///
    /// 四宫格原来只写"密码 / 临时码 / 指纹 / OTP"四个词，
    /// 但**不显示有多少** —— 用户得点进去才知道。
    /// DB 早就有数据，只是没接。
    private func count(_ k: Kind) -> Int {
        let mac = app.currentMac
        guard !mac.isEmpty else { return 0 }
        // fp / otp 复用 CredentialOrg.typeCounts（口径与凭证页一致）；
        // pwd / temp 要自己分 —— 因为 typeCounts.pwd 是**含临时码**的总数，
        // 而这里的「密码」卡只算常驻密码。两卡相加才等于 pwds.count。
        let t = CredentialOrg.typeCounts(mac)
        switch k {
        case .pwd:  return DB.listPwds(mac).filter { !$0.temp }.count
        case .temp: return DB.listPwds(mac).filter { $0.temp }.count
        case .fp:   return t.fp
        case .otp:  return t.otp
        }
    }

    private func card(_ k: Kind) -> some View {
        Button {
            XHaptics.trigger.impactOccurred()
            switch k {
            case .pwd:  showAddPwd = true
            case .temp: showTemp = true
            case .fp:   showFp = true
            case .otp:  showOtp = true
            }
        } label: {
            VStack(alignment: .leading, spacing: XSpace.s) {
                Image(systemName: k.icon)
                    .font(.system(size: XIcon.md, weight: .semibold))
                    .foregroundStyle(k.tint)
                    .frame(width: 44, height: 44)
                    .background(k.tint.opacity(XOpacity.badge), in: Circle())
                    .accessibilityHidden(true)

                Spacer(minLength: 0)

                HStack(alignment: .firstTextBaseline, spacing: XSpace.xs) {
                    Text(k.title)
                        .xFont(.title3, weight: .semibold)
                        .foregroundStyle(XPalette.text)
                        .lineLimit(1)
                    // 实时数量 —— 一眼知道这一类有多少条
                    let n = count(k)
                    Text(String(n))
                        .xFontExact(.caption.monospacedDigit(), weight: .semibold)
                        .foregroundStyle(n > 0 ? k.tint : XPalette.textTertiary)
                    Spacer(minLength: 0)
                }

                Text(k.sub)
                    .xFont(.caption2)
                    .foregroundStyle(XPalette.textSub)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: XIcon.xs, weight: .semibold))
                        .foregroundStyle(k.tint)
                }
            }
            .padding(XSpace.card)
            .frame(height: 168)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: XRadius.card, style: .continuous)
                    .fill(XPalette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: XRadius.card, style: .continuous)
                            .strokeBorder(k.tint.opacity(0.28), lineWidth: 1.5))
            )
        }
        .buttonStyle(StudioCardStyle(tint: k.tint))
        .accessibilityLabel("\(k.title): \(k.sub.replacingOccurrences(of: "\n", with: ", "))")
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 尾注
    // ═══════════════════════════════════════════════════════

    private var footerNote: some View {
        HStack(alignment: .top, spacing: XSpace.s) {
            Image(systemName: "info.circle")
                .font(.system(size: XIcon.xs, weight: .medium))
                .foregroundStyle(XPalette.textTertiary)
                .accessibilityHidden(true)
            Text("密码与指纹需现场靠近门锁下发; 临时码与 OTP 为本地台账管理, 锁端语义未定义的一次性/周期按时间窗推断 (标「约」)。")
                .xFont(.footnote)
                .foregroundStyle(XPalette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.top, XSpace.s)
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - 卡片按压样式
// ═══════════════════════════════════════════════════════════

private struct StudioCardStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(XMotion.quick, value: configuration.isPressed)
            .overlay(
                RoundedRectangle(cornerRadius: XRadius.card, style: .continuous)
                    .strokeBorder(tint.opacity(configuration.isPressed ? 0.9 : 0), lineWidth: 2)
            )
    }
}
