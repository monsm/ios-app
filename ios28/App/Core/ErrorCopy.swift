// ErrorCopy.swift —— 错误文案的**唯一出口**（F40）。
//
// 同一件事以前在三个地方写成三句话：今日页写「连不上门锁：xxx」，
// 凭证页写「操作失败」，诊断页写原始错误字符串。现在一律走这里：
// 一份分类、一份话术、一份「下一步」。
//
// 两条硬规矩：
//   1. **不露 hex / 原始码**。用户要的是「怎么办」，不是「0x1007」。
//   2. **空壳里不泄露**。胁迫码场景下一句带锁名或链路口径的话就等于露馅，
//      所以空壳里统一走中性文案（`neutral`）。
import Foundation

enum ErrorCopy {
    /// 引擎错误 → 界面失败描述。
    static func failure(_ error: Error, cmd: UInt8? = nil) -> ScreenFailure {
        let le = LockError.from(error, cmd: cmd)
        return failure(le)
    }

    static func failure(_ le: LockError) -> ScreenFailure {
        if DB.isDecoy { return neutral(le) }
        return ScreenFailure(kind: kind(le.kind),
                             title: le.title,
                             detail: le.detail,
                             next: le.next,
                             canRetry: le.canRetry,
                             mayHaveExecuted: le.mayHaveExecuted)
    }

    /// 锁端 rc → 界面失败描述。
    static func failure(rc: Int) -> ScreenFailure {
        if DB.isDecoy { return neutral(LockError.rejected(rc: rc)) }
        return failure(LockError.rejected(rc: rc))
    }

    /// 权限缺失（蓝牙关闭 / 通知拒绝 / 面容不可用）。
    static func permission(_ title: String, _ detail: String, next: String? = nil) -> ScreenFailure {
        if DB.isDecoy {
            return ScreenFailure(kind: .permission, title: "当前无法完成这个操作",
                                 detail: "请稍后再试。", next: nil, canRetry: true)
        }
        return ScreenFailure(kind: .permission, title: title, detail: detail,
                             next: next, canRetry: true)
    }

    /// 空壳口径：一句中性话，不带锁名、MAC、链路细节。
    static func neutral(_ le: LockError) -> ScreenFailure {
        ScreenFailure(kind: kind(le.kind),
                      title: "当前无法完成这个操作",
                      detail: "请稍后再试。",
                      next: nil,
                      canRetry: true,
                      mayHaveExecuted: false)
    }

    private static func kind(_ k: LockErrorKind) -> ScreenFailure.Kind {
        switch k {
        case .transport: return .transport
        case .auth: return .auth
        case .lockRejected: return .lockRejected
        case .localStorage: return .localStorage
        case .permission: return .permission
        case .cancelled: return .cancelled
        case .unknown: return .unknown
        }
    }

    /// 超时的第二种说法：命令可能已经执行。
    ///
    /// 这一条不能省 —— 「没打开」和「可能开了但没收到回执」对用户是两件事，
    /// 对锁也是两件事（重发一次可能双开）。
    static func maybeExecuted(_ what: String) -> ScreenFailure {
        ScreenFailure(kind: .transport,
                      title: "「\(what)」可能已经执行",
                      detail: "命令已经发出去了，只是没等到门锁的回执。为避免重复执行，App 不会自动重发。",
                      next: "请先看一眼门锁的状态，再决定要不要手动重试。",
                      canRetry: false,
                      mayHaveExecuted: true)
    }
}
