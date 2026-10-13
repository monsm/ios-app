// 77 / 939 / 941 开锁实时活动的主 App 侧: 开始 / 更新 / 收起。
// 属性类型来自 Shared/LiveUnlockActivity.swift —— 那份源码同时编进本 target 与 widget target,
// 所以两边看到的 `UnlockActivityAttributes` 是同一个形状 (ActivityKit 的硬要求)。
import ActivityKit
import Foundation

@MainActor
enum LiveUnlock {
    private static var current: Activity<UnlockActivityAttributes>?

    /// 开关 (默认开): 关掉就不起活动 —— 开锁链本身一个字不变, 只少一条锁屏/灵动岛展示。
    /// 2026-10-13 对抗式排查: 原先**只有读没有写** —— 全仓没有任何 UI 写 `kf_live_unlock`
    /// (grep 全仓只有这一处 getBool), 于是 `enabled` 恒为 true, 而注释宣称"关掉就不起活动"
    /// 是**假能力宣称**。补 setter, 入口在设置-开锁 (77/939/941)。
    static var enabled: Bool { DB.store.getBool("kf_live_unlock", true) }
    static func setEnabled(_ on: Bool) { DB.store.set("kf_live_unlock", on) }

    /// 开锁开始: 起一场"连接中"的活动 (30 秒后过期, 防一条活动永远挂在锁屏上)
    static func begin(lockName: String) {
        guard enabled, current == nil else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attr = UnlockActivityAttributes(lockName: lockName)
        current = try? Activity.request(
            attributes: attr,
            content: .init(state: .init(phase: .connecting), staleDate: Date().addingTimeInterval(30)),
            pushType: nil)
    }

    /// 开锁成功: 更新成"已开锁", **10 秒后自动收起** (原句口径)
    static func succeeded(lockName: String) {
        guard let a = current else { return }
        current = nil
        Task {
            await a.update(.init(state: .init(phase: .unlocked), staleDate: Date().addingTimeInterval(10)))
            try? await Task.sleep(for: .seconds(10))
            await a.end(nil, dismissalPolicy: .after(.now + 1))
        }
    }

    /// 失败: 立刻收起 —— 不留一条失败态挂在锁屏上等人误会
    static func failed() {
        guard let a = current else { return }
        current = nil
        Task { await a.end(nil, dismissalPolicy: .immediate) }
    }
}
