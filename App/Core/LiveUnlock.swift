// 77 / 939 / 941 开锁实时活动的主 App 侧: 开始 / 更新 / 收起。
// 属性类型来自 Shared/LiveUnlockActivity.swift —— 那份源码同时编进本 target 与 widget target,
// 所以两边看到的 `UnlockActivityAttributes` 是同一个形状 (ActivityKit 的硬要求)。
import ActivityKit
import Foundation

@MainActor
enum LiveUnlock {
    private static var current: Activity<UnlockActivityAttributes>?
    /// 2026-10-14: 代次令牌 —— 取消/失败路径可能**晚于**下一次 begin 执行, 若只按 `current` 收,
    /// 会把新开锁的活动误收掉 (1.2s 内二次触发开锁即可复现)。begin 返回本场令牌, 收场按令牌校验。
    private static var generation = 0

    /// 开关 (默认开): 关掉就不起活动 —— 开锁链本身一个字不变, 只少一条锁屏/灵动岛展示。
    /// 2026-10-13 对抗式排查: 原先**只有读没有写** —— 全仓没有任何 UI 写 `kf_live_unlock`
    /// (grep 全仓只有这一处 getBool), 于是 `enabled` 恒为 true, 而注释宣称"关掉就不起活动"
    /// 是**假能力宣称**。补 setter, 入口在设置-开锁 (77/939/941)。
    static var enabled: Bool { DB.store.getBool("kf_live_unlock", true) }
    static func setEnabled(_ on: Bool) { DB.store.set("kf_live_unlock", on) }

    /// 开锁开始: 起一场"连接中"的活动 (30 秒后过期, 防一条活动永远挂在锁屏上)。
    /// 返回本场令牌 (收场时回传; -1 = 本场没有起活动)。
    @discardableResult
    static func begin(lockName: String) -> Int {
        guard enabled, current == nil else { return -1 }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return -1 }
        generation += 1
        let token = generation
        let attr = UnlockActivityAttributes(lockName: lockName)
        current = try? Activity.request(
            attributes: attr,
            content: .init(state: .init(phase: .connecting), staleDate: Date().addingTimeInterval(30)),
            pushType: nil)
        return token
    }

    /// 开锁成功: 更新成"已开锁", **10 秒后自动收起** (原句口径)
    static func succeeded(lockName: String) {
        guard let a = current else { return }
        current = nil
        generation += 1
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
        generation += 1
        Task { await a.end(nil, dismissalPolicy: .immediate) }
    }

    /// 只收**自己那一场** (代次不符 = 已被更新的开锁取代, 不动新活动)。
    static func fail(_ token: Int) {
        guard token >= 0, token == generation else { return }
        failed()
    }

    /// 2026-10-14: 进程被杀 / 7 天签名重装后, 锁屏可能残留上一条活动 (current 只在内存里, 重启即失忆),
    /// 而 `begin` 的 `current == nil` 守卫只认内存态 → 会叠出第二条。启动时枚举并全部收起。
    static func reapOrphans() {
        Task {
            for a in Activity<UnlockActivityAttributes>.activities where a.id != current?.id {
                await a.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
