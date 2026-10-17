// 原生互斥容器 —— 一把 NSLock + 一个值，值只活在临界区内。
//
// 为什么需要它而不是直接 `static var`：
//   Swift 6 把"非隔离的可变全局状态"判为错误。原生效法是 `static var + 一把锁`，
//   但那个 static var 本身仍然是全局可变存储，编译器照样看得见 —— 必须让**值由锁持有**。
//
// 为什么用 NSLock 而不是 OSAllocatedLock：
//   OSAllocatedLock (iOS 16+) 在 CI 的 Xcode 27.2 / iOS 27.2 上实测 `cannot find in scope`，
//   而 NSLock 是 Foundation 一等公民、可用性覆盖所有部署版本，行为一致（互斥语义相同）。
//
// 为什么可以 Sendable（这是"有依据的 unchecked"，不是把检查关掉）：
//   · 所有读写都必须经过 `withLock`，`value` 没有任何其他访问路径；
//   · NSLock 自身保证临界区互斥，`defer unlock` 保证异常路径也解锁；
//   · 与系统库（CompletionOnce / NotificationCenter 等）里"内部锁 + @unchecked Sendable"同一形态。
// 判据可核对：把这里改成 `final class Locked<Value> { var value: Value }`（去掉锁）就该编译不过。
//
// 用法（与 OSAllocatedLock 同语法，之前按它写的调用点一行不用改）：
//   private static let cache = Locked([String: Int]())
//   static func get(_ k: String) -> Int? { cache.withLock { $0[k] } }
//   static func put(_ k: String, _ v: Int) { cache.withLock { $0[k] = v } }
import Foundation

final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    /// 临界区内独占访问。闭包抛错也保证解锁（defer）。
    @discardableResult
    func withLock<R>(_ body: (inout Value) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}
