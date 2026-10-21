// ---------- 同屏"闲时提醒"预算 (乱源治理第 2 批) ----------
// 起因: 顶部六条横幅 + 设备页两条教学浮签各自独立 `if`，谁都不知道"这屏已经有别的在说话"——
//       组合起来同屏能同时挂 3~4 条互不相干的指路条，这就是"乱"的最大一坨。
// 口径: 任意时刻只挂 **一条** 闲时提醒; 被压住的那几条不丢，折进顶部一枚汇总胶囊，
//       点开逐条给**它原本就有的动作** (不新造做不到的动作 —— 832 那条教训)。
// 不参赛的四类，因为它们不是"闲时提醒":
//   · 演示模式横幅 344/836: 演示数据必须全程可辨识，让它让位等于撒。
//   · 蓝牙关横幅 69: 主流程被它阻断，藏起来只会让人以为 App 坏了。
//   · toast 与 508 写入回执: 是用户自己刚那个动作的回声，不是提醒。
//   · 377 访客通道入口: 门禁，让位就等于放开受限区。
import SwiftUI

enum Ambient: String, CaseIterable, Identifiable {
    case selfCheck          // 8/448 本机库体自检异常
    case pasteCare          // 344/517 剪贴板粘贴建议 (有时效窗口)
    case firstUseCapsule    // 42/268 首用: 长按胶囊看状态变化
    case quickTileTip       // 827 快捷格逐格揭幕提示

    var id: String { rawValue }

    /// 排位依据: 数据完整性 > 有到期时刻的隐私提示 > 只用一次的首用教学 > 可一直等到用户主动用的逐格教学
    var rank: Int {
        switch self {
        case .selfCheck: return 0
        case .pasteCare: return 1
        case .firstUseCapsule: return 2
        case .quickTileTip: return 3
        }
    }

    var icon: String {
        switch self {
        case .selfCheck: return "exclamationmark.triangle"
        case .pasteCare: return "doc.on.clipboard"
        case .firstUseCapsule: return "hand.point.up.left"
        case .quickTileTip: return "hand.point.up.left"
        }
    }
}

/// 排位这一步单独拆出来: 纯函数, 不碰视图也不碰存储, 便于"同一批候选换了优先级"这种改动可核对
enum NoticeBudget {
    static func ranked(_ present: [Ambient]) -> [Ambient] {
        var out: [Ambient] = []
        for a in present where !out.contains(a) { out.append(a) }   // 去重 + 稳定
        return out.sorted { $0.rank < $1.rank }
    }
}


