// EngineHost.swift —— 引擎需要宿主提供的最小上下文。
//
// 为什么要有这一层：上一版把 `AppState`（一个 40KB 的界面状态类）直接传进 Engine 的
// 服务函数里。结果是 **引擎离不开界面层** —— 把引擎搬到新 App 时，这些函数全成了悬空引用。
//
// 正确的切法是：引擎只声明"我需要什么"，由宿主实现。
// 这里只列引擎真的用到的五个能力，不多不少。
import Foundation

@MainActor
protocol EngineHost: AnyObject {
    /// 当前选中的门锁钥匙串（nil = 还没选锁）。
    var currentKeychain: Keychain? { get }
    /// 链路服务（连接 / 下发 / 回读）。
    var lockLink: LockService { get }
    /// 最近一次读到的锁状态（nil = 没读过）。
    var lastStatus: StatusSnapshot? { get }
    /// 宿主是否正占用门锁链路（读日志 / 手动开锁）。
    ///
    /// 单条 BLE 链路只挂得下一个 waiter；自动开门在下发 04 前要看这一眼，
    /// 否则会撞上「已有命令在等待响应」并把自动开锁解武装。
    var linkBusy: Bool { get }
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
    /// 宿主还没就绪时收到的动作（**冷启动点通知**就会这样：系统先起 App、再回调，
    /// 而 `RootView.onAppear` 还没跑到）。
    ///
    /// 2026-11-01 修复：旧实现里 `QuickActions` 拿到 `host == nil` 就 `return` ——
    /// 用户点了「密码临期」通知，App 启动了，但**没有跳到那条凭证**，且没有任何提示。
    /// 现在先存起来，等 `register` 时立刻消费。
    private static var pending: [@MainActor (any EngineHost) -> Void] = []

    static func register(_ host: any EngineHost) {
        current = host
        let queued = pending
        pending = []
        for run in queued { run(host) }
    }

    static var host: (any EngineHost)? { current }

    /// 宿主未就绪时把动作排进队列；已就绪则立刻执行。
    static func whenReady(_ run: @escaping @MainActor (any EngineHost) -> Void) {
        if let host = current { run(host) } else { pending.append(run) }
    }
}
