// ConcurrencyTests.swift —— `Locked`（全仓所有 `@unchecked Sendable` 的地基）的并发压力测试。
//
// 为什么必须测它：BLEService / DFUSession / Store / QuickActions 的 `@unchecked Sendable`
// 都是**建立在 Locked 真的互斥**这个前提上的。那个前提一旦破了，
// 编译器不会报错（`@unchecked` 就是"我保证过"的意思），
// 而表现是"偶发丢日志 / 偶发计数偏少 / 偶发界面数字对不上" —— 最难查的那类 bug。
//
// 这些断言跑得很快（毫秒级），但能让"去掉锁"这类改动立刻变红。
import XCTest
@testable import LockKeeper

final class ConcurrencyTests: XCTestCase {

    /// 并发自增不丢：2000 次 × 8 线程，结果必须正好等于总次数。
    /// 若临界区失效，这个计数器会明显偏小（经典 lost update）。
    func testLockedIncrementIsAtomic() {
        let counter = Locked(0)
        let threads = 8
        let perThread = 2000
        DispatchQueue.concurrentPerform(iterations: threads) { _ in
            for _ in 0..<perThread {
                counter.withLock { $0 += 1 }
            }
        }
        XCTAssertEqual(counter.withLock { $0 }, threads * perThread,
                       "并发自增丢了 —— 临界区没互斥住（会表现为偶发计数偏少）")
    }

    /// 复合操作（读-判-写）必须整体在临界区内：
    /// 这正是全仓 `Store.addUnique` 那类"读数组 → 判重 → 插入 → 写回"的写法。
    /// 拆成两次 withLock 就会插进重复项 —— 这里用同样的形状验证语义。
    func testLockedReadModifyWriteIsIndivisible() {
        let bag = Locked([Int]())
        DispatchQueue.concurrentPerform(iterations: 8) { t in
            for i in 0..<200 {
                let v = t * 1000 + i          // 每个线程的值域不重叠
                bag.withLock { arr in
                    if !arr.contains(v) { arr.append(v) }   // 读-判-写必须在同一次 withLock 里
                }
            }
        }
        let out = bag.withLock { $0 }
        XCTAssertEqual(out.count, 8 * 200, "复合操作被拆开 ⇒ 出现重复/丢失")
        XCTAssertEqual(Set(out).count, out.count, "不允许有重复元素")
    }

    /// 闭包抛错也必须解锁（`defer unlock` 的真正考验）。
    /// 若异常路径漏了解锁，第二次访问会直接死锁 —— 本用例会超时卡住（在 CI 上表现为超时红）。
    func testLockedUnlocksOnThrownError() throws {
        struct Boom: Error {}
        let box = Locked(1)
        XCTAssertThrowsError(try box.withLock { _ -> Int in throw Boom() })
        // 能走到这里就说明锁已释放；再取一次值确认容器仍可用。
        XCTAssertEqual(box.withLock { $0 }, 1)
        XCTAssertEqual(box.withLock { $0 += 1; return $0 }, 2)
    }

    /// 返回值语义：withLock 的返回值就是闭包最后表达式（@discardableResult 不吞结果）。
    func testLockedReturnsBodyResult() {
        let box = Locked([String: Int]())
        let inserted = box.withLock { dict -> Bool in
            dict["a"] = 1
            return dict["a"] == 1
        }
        XCTAssertTrue(inserted)
        XCTAssertEqual(box.withLock { $0["a"] }, 1)
    }

    /// 引用类型值也能安全共享（Locked 包住一个 class 实例时的常见用法）。
    func testLockedWithReferenceValue() {
        final class Box { var n = 0 }
        let box = Locked(Box())
        DispatchQueue.concurrentPerform(iterations: 6) { _ in
            for _ in 0..<1000 { box.withLock { $0.n += 1 } }
        }
        XCTAssertEqual(box.withLock { $0.n }, 6000)
    }
}
