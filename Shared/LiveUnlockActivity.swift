// 77 / 939 / 941 开锁实时活动 (灵动岛 + 锁屏) 的**共享定义**。
//
// 为什么单独放 Shared/ 而不是放 App/ 或 Widget/: ActivityKit 要求"活动属性类型"在
// **主 App 与 widget extension 两个 target 里是同一个类型**(名字 + Codable 形状必须一致)。
// app-extension 是独立编译单元、不能 import 主 App 的类型, 所以这个文件被 project.yml
// 同时挂进 OfflineLock 与 OfflineLockWidget 两个 target 的 sources —— 两边各编一份, 形状一致。
// 本文件只依赖 ActivityKit / Foundation, 不碰主 App 的任何类型 (DB / AppState / DesignSystem 都不在这里)。
import ActivityKit
import Foundation

/// 开锁过程的三阶段 (原句: 连接中 → 已开锁; 失败走 失败 档, 立刻收起)。
enum LiveUnlockPhase: String, Codable, Hashable {
    case connecting   // 连接中
    case unlocked     // 已开锁
    case failed       // 失败

    var label: String {
        switch self {
        case .connecting: return "连接中"
        case .unlocked: return "已开锁"
        case .failed: return "开锁失败"
        }
    }
    var symbol: String {
        switch self {
        case .connecting: return "arrow.triangle.2.circlepath"
        case .unlocked: return "lock.open.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
}

/// 活动属性: 锁名是**静态**的 (整场活动不变), 阶段是**动态**的 (随状态更新)。
/// `Activity<Attributes>` 的 Sendable 是**条件式**的 (`where Attributes: Sendable`), 而
/// ActivityAttributes 本身并不要求 Sendable —— 不显式写这一行, 主 actor 上取到的活动实例
/// 就是"不可跨隔离发送", Swift 6 下 update/end 那几处直接判错。
/// 本类型的成员只有 String 与一个纯值 enum, 所以这个一致性是事实, 不是声明式免检。
struct UnlockActivityAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        var phase: LiveUnlockPhase
    }
    var lockName: String
}
