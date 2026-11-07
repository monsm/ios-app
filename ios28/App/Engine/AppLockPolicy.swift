// AppLockPolicy.swift —— 应用锁的可调策略（B33）。
//
// 原来这三件事全是写死的常量：
//   · 回前台 30 秒就重新上锁（`willEnterForeground(lockAfter: 30)`）；
//   · 失败 3 次开始冷却，梯度 30s → 5min → 30min；
//   · 失败 5 次自动开门自我关闭 24 小时。
//
// 写死的后果：一个人通勤 10 分钟，一接电话回来就要重新输密码；
// 另一个人要更严，改不了。现在这三档都变成**可调项**，
// 且默认值与原来完全一致（老用户升级后行为不变）。
import Foundation

struct AppLockPolicy: Codable, Equatable {
    /// 要不要本机密码（关掉 = 冷启动直接进）。
    var requirePasscode: Bool = true
    /// 回前台超过多少秒后重新上锁。
    var foregroundLockSeconds: Int = 30
    /// 连续错几次开始冷却。
    var escalateAfter: Int = 3
    /// 冷却梯度（秒）：下标 = 连续失败次数。
    var cooldownLadder: [Int] = [0, 0, 0, 30, 30, 300, 300, 1800]
    /// 允许用面容/指纹解锁本机（设了胁迫码时这一档无效 —— 刷脸会暴露不是伪装模式）。
    var allowBiometric: Bool = true
    /// 自动开门连续失败几次后自我关闭。
    var autoOpenDisableAfter: Int = 5

    /// 连续失败 `streak` 次要冷却多少秒。
    func cooldown(for streak: Int) -> Double {
        guard !cooldownLadder.isEmpty else { return 0 }
        let idx = min(max(streak, 0), cooldownLadder.count - 1)
        return Double(cooldownLadder[idx])
    }

    /// 冷却阶梯的可选档（界面上给几个整档，不让用户填 37 秒）。
    static let ladderChoices: [(label: String, seconds: Int)] = [
        ("不冷却", 0), ("30 秒", 30), ("5 分钟", 300), ("30 分钟", 1800), ("2 小时", 7200)
    ]

    /// 回前台超时可选档。
    static let timeoutChoices: [(label: String, seconds: Int)] = [
        ("立即", 0), ("30 秒", 30), ("1 分钟", 60), ("5 分钟", 300), ("15 分钟", 900)
    ]
}

enum AppLockPolicyStore {
    private static let key = "kf_applock_policy"
    private static let cache = Locked<AppLockPolicy?>(nil)

    static func current() -> AppLockPolicy {
        if let hit = cache.withLock({ $0 }) { return hit }
        let p = DB.store.get(AppLockPolicy.self, key) ?? AppLockPolicy()
        cache.withLock { $0 = p }
        return p
    }

    static func save(_ policy: AppLockPolicy) {
        cache.withLock { $0 = policy }
        DB.store.setCodable(key, policy)
    }

    static func reset() {
        cache.withLock { $0 = nil }
        DB.store.remove(key)
    }
}
