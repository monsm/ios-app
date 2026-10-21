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
            let macs = DB.keychains().map { $0.mac }
            let n = DB.keychains().reduce(0) { acc, kc in
                acc + DB.listPwds(kc.mac).count + DB.listFps(kc.mac).count
            }
            // 到期预警 —— 与 Tab 角标同源 (CredentialOrg.expiringSoonCount)
            let soon = CredentialOrg.expiringSoonCount(macs: macs)
            if soon > 0 { return "\(n) 份生效 · \(soon) 份将到期" }
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
    @Binding var face: DoorFace

    /// 点某个域 → 进入该域
    var onEnter: (DoorDomain) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // ── 顶部 ──
            HStack {
                Text("门里")
                    .xFont(.headline)
                    .foregroundStyle(XPalette.text)
                Spacer()
                DoorFlipButton(face: $face)
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
        // 用 XPanel + XRow, 不再手写卡片 ——
        // 改之前这行是手搓的 surface + hairline + chevron, 拿不到设计系统
        // 后续给 XRow 加的图标徽章、状态过渡它也全都吃不到,
        // 而「门里」是翻转之后第一眼看到的内容, 最该与全 App 一致。
        XPanel(kind: .group) {
            XRow(
                systemImage: domain.systemImage,
                title: domain.rawValue,
                subtitle: domain.summary,
                showsChevron: true
            ) {
                XHaptics.tick.impactOccurred()
                onEnter(domain)
            }
        }
    }
}
