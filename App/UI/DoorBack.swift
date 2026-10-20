//
//  DoorBack.swift
//  门里 · 全新设计
//
//  门里 = 管理面。四个域, 不设 Tab。
//
//  ═══════════════════════════════════════════════════════════
//  为什么是四个域
//  ═══════════════════════════════════════════════════════════
//
//  52 个 destination 按"谁/什么事/这把锁/这台手机"归为四类:
//
//    钥匙   = 谁能进 (凭证 + 成员 + 临时码)
//    事件   = 发生了什么 (记录 + 告警 + 审计)
//    这台锁 = 锁本身 (设备 + 固件 + 保养 + 网关)
//    这台手机 = 这台设备 (安全 + 备份 + 外观 + 通知)
//
//  四个问题穷尽了人与门锁的关系, 没有第五个。
//
//  ═══════════════════════════════════════════════════════════
//  为什么是单列 List 而不是 2×2 网格
//  ═══════════════════════════════════════════════════════════
//
//  Dynamic Type AX 档最大 5 倍 (LockKeeperApp 挂 .dynamicTypeSize)。
//  2×2 网格在 5 倍字体下必然溢出, 单列 List 天然可滚动。
//  这是无障碍硬要求, 不是审美选择。
//

import SwiftUI

/// 门里的四个域
enum DoorDomain: String, CaseIterable, Identifiable {
    case keys = "钥匙"
    case events = "事件"
    case lock = "这台锁"
    case device = "这台手机"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .keys: return "key.horizontal"
        case .events: return "list.bullet.rectangle"
        case .lock: return "lock.shield"
        case .device: return "iphone"
        }
    }

    /// 该域的动态摘要 —— 必须显示真实数字, 不是空入口
    var summary: String {
        switch self {
        case .keys:
            let n = DB.keychains().reduce(0) { acc, kc in
                acc + DB.listPwds(kc.mac).count + DB.listFps(kc.mac).count
            }
            return n > 0 ? "\(n) 份生效" : "还没有凭证"
        case .events:
            let n = RecordSearch.unhandledAlarmCount(macs: DB.keychains().map { $0.mac })
            return n > 0 ? "\(n) 条待处理" : "无待处理"
        case .lock:
            if let kc = DB.keychain(DB.store.getString("kf_current_mac")) {
                let p = DB.readStatus(kc.mac)?.powerLevel ?? -1
                return p >= 0 ? "电量 \(p)%" : "未连接"
            }
            return "还没有门锁"
        case .device:
            let sec = DB.store.getBool("kf_applock")
            return sec ? "应用锁已开" : "应用锁未开"
        }
    }
}

/// 门里 —— 首屏背面
struct DoorBack: View {
    @EnvironmentObject private var app: AppState
    @Binding var flipped: Bool

    /// 点某个域 → 进入该域
    var onEnter: (DoorDomain) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // ── 顶部 ──
            HStack {
                Text("门里")
                    .vkFont(.headline)
                    .foregroundStyle(XPalette.text)
                Spacer()
                DoorFlipButton(flipped: $flipped)
            }
            .padding(.horizontal, XSpace.gutter)
            .padding(.top, XSpace.s)

            Spacer(minLength: XSpace.l)

            // ── 四域列表 ──
            VStack(spacing: XSpace.s) {
                ForEach(DoorDomain.allCases) { domain in
                    domainRow(domain)
                }
            }
            .padding(.horizontal, XSpace.gutter)

            Spacer(minLength: XSpace.xl)
        }
    }

    private func domainRow(_ domain: DoorDomain) -> some View {
        Button {
            XHaptics.tick.impactOccurred()
            onEnter(domain)
        } label: {
            HStack(spacing: XSpace.m) {
                Image(systemName: domain.systemImage)
                    .font(.system(size: XIcon.md, weight: .medium))
                    .foregroundStyle(XPalette.accentText)
                    .frame(width: 32)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(domain.rawValue)
                        .vkFont(.body, weight: .medium)
                        .foregroundStyle(XPalette.text)
                    Text(domain.summary)
                        .vkFont(.caption)
                        .foregroundStyle(XPalette.textSub)
                }

                Spacer(minLength: XSpace.s)

                Image(systemName: "chevron.right")
                    .font(.system(size: XIcon.xs, weight: .semibold))
                    .foregroundStyle(XPalette.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(XSpace.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(XPalette.surface, in: RoundedRectangle(cornerRadius: XRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: XRadius.card, style: .continuous)
                    .strokeBorder(XPalette.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(domain.rawValue), \(domain.summary)")
        .accessibilityAddTraits(.isButton)
    }
}
