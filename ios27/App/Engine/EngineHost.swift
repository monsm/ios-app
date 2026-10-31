// EngineHost.swift —— 引擎需要宿主提供的最小上下文。
//
// 为什么要有这一层：上一版把 `AppState`（一个 40KB 的界面状态类）直接传进 Engine 的
// 服务函数里。结果是 **引擎离不开界面层** —— 把引擎搬到新 App 时，这些函数全成了悬空引用。
//
// 正确的切法是：引擎只声明"我需要什么"，由宿主实现。
// 这里只列引擎真的用到的四个能力，不多不少。
import Foundation

@MainActor
protocol EngineHost: AnyObject {
    /// 当前选中的门锁钥匙串（nil = 还没选锁）。
    var currentKeychain: Keychain? { get }
    /// 链路服务（连接 / 下发 / 回读）。
    var lockLink: LockService { get }
    /// 最近一次读到的锁状态（nil = 没读过）。
    var lastStatus: StatusSnapshot? { get }
    /// 请求把界面切到「钥匙」页并定位到某条凭证。
    func requestCredentialRoute(alias: Int?)
}
/// 宿主注册点。
///
/// 为什么需要它：通知回调（`UNUserNotificationCenterDelegate`）没有视图上下文，
/// 拿不到 `AppModel`；但"点通知 → 定位到那条凭证"这条链必须落到界面上。
/// 由 App 启动时注册一次，引擎侧按需取用。
@MainActor
enum EngineHostRegistry {
    private static weak var current: (any EngineHost)?

    static func register(_ host: any EngineHost) {
        current = host
    }

    static var host: (any EngineHost)? { current }
}
