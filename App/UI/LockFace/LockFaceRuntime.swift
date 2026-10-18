//  LockFaceRuntime.swift
//  门面层需要的一点点运行时状态: 上次退后台的时刻。2026-10-18 门面改造新增。
//
//  为什么单独一个类而不是塞进 AppState: 这是**纯展示策略**的输入, 与业务状态无关;
//  塞进 AppState 会让它多一个没人读的 @Published, 每次变化都触发整树重绘。
//  用 Locked 包装 (本仓既有的锁原语) 满足 Swift 6 的 Sendable 要求。

import Foundation

final class LockFaceRuntime: @unchecked Sendable {
    static let shared = LockFaceRuntime()

    private let box = Locked<Date?>(nil)

    private init() {}

    /// 记录"进入后台"的时刻。
    func markBackground() { box.withLock { $0 = Date() } }

    /// 距离上次退后台过了多少秒; 没有记录过就返回 nil (视为冷启动)。
    func awaySeconds() -> TimeInterval? {
        box.withLock { stored -> TimeInterval? in
            guard let stored else { return nil }
            return Date().timeIntervalSince(stored)
        }
    }

    /// 回到前台后清掉, 避免下一次误用旧的间隔。
    func clear() { box.withLock { $0 = nil } }
}
