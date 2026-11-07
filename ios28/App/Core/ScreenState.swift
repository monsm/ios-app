// ScreenState.swift —— 一屏数据的七态模型。
//
// 之前每一页自己判 loading / 空 / 错，三页三种写法；错误文案也各写各的，
// 于是同一个「连不上门锁」在今日页是一句、在记录页是另一句。
// 现在统一到这一个模型：页面只声明「我在哪个状态」，渲染交给 StateSection。
//
// 七态：idle / loading / data / stale / empty / failed —— 外加一个
// 「部分成功」（PartlyDone），它不是错误，但也不是全成功。
import Foundation
import SwiftUI

// MARK: - 失败

/// 一次失败的完整描述：**发生了什么** + **下一步做什么**。
///
/// `kind` 是给机器看的（B17 的结构化分类），文案是给人看的。
/// 两者必须同时给：只有 kind 没有文案，界面还是得自己编话。
struct ScreenFailure: Equatable {
    enum Kind: String, Equatable {
        case transport        // 链路：连不上 / 断链 / 超时
        case auth             // 凭证被拒
        case lockRejected     // 锁端回了 rc != 0
        case localStorage     // 本机存储
        case permission       // 权限（蓝牙 / 通知 / 面容）
        case cancelled        // 用户取消
        case unknown
    }

    var kind: Kind
    /// 一句话：发生了什么。
    var title: String
    /// 展开后：细节。
    var detail: String
    /// 下一步：可执行的一句话（没有就是 nil —— 不要编）。
    var next: String?
    /// 能不能原样重试。unsafe 命令超时时是 false。
    var canRetry: Bool
    /// 命令**可能已经执行**（超时 / 断链，但帧已经写出去）。
    /// 这时界面必须说「可能已经执行」，不能让用户以为什么都没发生。
    var mayHaveExecuted: Bool = false

    static func transport(_ title: String, detail: String, next: String? = nil,
                          mayHaveExecuted: Bool = false) -> ScreenFailure {
        ScreenFailure(kind: .transport, title: title, detail: detail,
                      next: next, canRetry: !mayHaveExecuted, mayHaveExecuted: mayHaveExecuted)
    }
}

// MARK: - 屏幕状态

/// 一屏数据的七种状态。
enum ScreenState<Value> {
    case idle
    case loading
    case data(Value)
    /// 数据在，但过了新鲜期：读数是旧的，**不能冒充实时**。
    case stale(Value, at: Int64)
    case empty
    case failed(ScreenFailure)
    /// 部分成功：新码写进去了，旧码没删掉 —— 这既不是成功也不是失败。
    case partlyDone(Value, ScreenFailure)

    var value: Value? {
        switch self {
        case .data(let v), .stale(let v, _), .partlyDone(let v, _): return v
        default: return nil
        }
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var isEmpty: Bool {
        if case .empty = self { return true }
        return false
    }

    var failure: ScreenFailure? {
        switch self {
        case .failed(let f), .partlyDone(_, let f): return f
        default: return nil
        }
    }

    /// 有旧数据时失败不该把整页清空 —— 降级成 stale（F39 卡片级错误隔离）。
    func degraded(_ failure: ScreenFailure) -> ScreenState<Value> {
        switch self {
        case .data(let v):
            return .stale(v, at: Int64(Date().timeIntervalSince1970 * 1000))
        case .stale(let v, let at):
            return .stale(v, at: at)
        default:
            return .failed(failure)
        }
    }

    /// 页面进入时把状态推到 loading；已有数据时保留旧值（不要闪空）。
    func loading(keepingPrevious: Bool = true) -> ScreenState<Value> {
        if keepingPrevious, let v = value { return .stale(v, at: Int64(Date().timeIntervalSince1970 * 1000)) }
        return .loading
    }
}

// MARK: - 长任务进度

/// 长任务（配对 / 录指纹 / 读日志 / 刷固件）的进度。
///
/// 进度只写**真的知道**的数字：知道就写 fraction，不知道就写 nil（"在跑"），
/// 不要拿一个假百分比去安慰用户。
struct TaskProgress: Equatable {
    var title: String
    var detail: String = ""
    /// 0…1；nil = 只知道在跑，不知道进度。
    var fraction: Double?
    var step: Int = 0
    var total: Int = 0
    var cancellable: Bool = true

    /// 更新进度。**不能叫 `step`** —— 结构体里已经有一个 `step: Int` 属性，
    /// 同名会让 `progress.step(...)` 被解析成「对 Int 调用」→ 编译错。
    mutating func update(_ detail: String, step: Int, fraction: Double? = nil) {
        self.detail = detail
        self.step = step
        if let fraction { self.fraction = fraction }
    }

    var stepText: String? {
        guard total > 0 else { return nil }
        return "第 \(min(step, total)) / \(total) 步"
    }
}
