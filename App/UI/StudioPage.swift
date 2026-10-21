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

    private let columns = [
        GridItem(.flexible(), spacing: XSpace.m),
        GridItem(.flexible(), spacing: XSpace.m),
    ]

    var body: some View {
        Group {
            if embedded {
                content
            } else {
                NavigationStack { content }
            }
        }
    }

    private var content: some View {
        ZStack {
            XPalette.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: XSpace.l) {
                    LazyVGrid(columns: columns, spacing: XSpace.m) {
                        card(.pwd)
                        card(.temp)
                        card(.fp)
                        card(.otp)
                    }

                    footerNote
                }
                .padding(.horizontal, XSpace.gutter)
                .padding(.vertical, XSpace.l)
            }
        }
        .navigationTitle("凭证工坊")
        .navigationBarTitleDisplayMode(.large)
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
            case .temp: return XPalette.warn
            case .fp:   return XPalette.kindFp
            case .otp:  return XPalette.kindOtp
            }
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
                    .background(k.tint.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)

                Spacer(minLength: 0)

                Text(k.title)
                    .xFont(.title3, weight: .semibold)
                    .foregroundStyle(XPalette.text)
                    .lineLimit(1)

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
                .xFont(.caption2)
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
