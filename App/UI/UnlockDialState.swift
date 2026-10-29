// 开锁圆盘 · 状态判断与文案（偏好读取 / 图标 / 标题）
// 2026-10-29 从 UnlockDial.swift（607 行）拆出。private 已提升为 internal。
import SwiftUI

extension UnlockDial {
    var holdConfirmOn: Bool { DB.store.getBool("kf_hold_confirm", true) }
    var fenceRequired: Bool { DB.store.getBool("kf_fence") }
    // 225 最大字号走查 (设备 Tab 这一屏) = 下面这条 859 的字号联动: 圆盘与状态文案同档缩放，
    // 走查清单在 docs/A11Y-FREQUENCY.md + tools/dynamictype.js (静态闸门) —— 不另做一套"大字模式"。
    // 859: 字号 ≥1.5 时圆盘缩到 128pt, 保证大字号下整盘仍在屏内可完成按住手势
    // (手势判定半径按 dial 比例算, 缩小后触发面积同步收窄, 不会留出点不到的死区)
    // --- 包15 无障碍 ---
    // 875 按住时长跟随 (⚠ 系统"按住持续时间"无读取 API, 自定滑杆 0.4–1.6s, 默认 0.9 与包1 对齐)
    var holdDuration: Double { AXPrefs.holdDuration }
    /// 61 起手围栏: 圆盘内部六成面积 (r = √0.6·R ≈ 0.39·直径)
    var dial: CGFloat { DS.Metric.dial }
    func insideFence(_ p: CGPoint) -> Bool {
        let c = CGPoint(x: dial / 2, y: dial / 2)
        return hypot(p.x - c.x, p.y - c.y) <= dial * 0.39
    }

    var isBusy: Bool {
        state == .connecting || state == .opening
    }
    /// 241 中心三态符号: 锁闭(未就绪)/开启(就绪)/警告(失败·双验), 过程态另有信号/旋转
    var iconName: String {
        switch state {
        case .idle:
            if !bleReady { return "antenna.radiowaves.left.and.right.slash" }
            return connected ? "lock.open" : "lock.fill"
        case .connecting: return "antenna.radiowaves.left.and.right"
        case .opening: return "lock.rotation"
        case .success: return "checkmark"
        case .doubleVerify: return "person.badge.key.fill"
        case .failed: return failStreak >= 2 ? "antenna.radiowaves.left.and.right" : "exclamationmark.triangle.fill"
        }
    }
    var title: String {
        switch state {
        case .idle:
            if !bleReady { return "蓝牙未开启" }
            if !connected { return "连接门锁" }
            return holdConfirmOn ? "按住开锁" : "点击开锁"
        case .connecting: return "正在连接"
        case .opening: return "正在开锁"
        case .success: return "已开锁"
        case .doubleVerify: return "需二次验证"
        case .failed: return "开锁失败"
        }
    }
}
