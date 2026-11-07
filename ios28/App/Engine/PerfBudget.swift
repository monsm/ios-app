// PerfBudget.swift —— 性能预算（B47）、启动里程碑（B44）、内存上限（B43）。
//
// 「性能」过去没有口径：改慢了没人知道，改快了也没人记。
// 现在给几个关键路径各设一条预算，超了就记一笔（诊断页看得到），
// 于是「这次改动让记录页慢了 80ms」会留在证据里，而不是留在感觉里。
//
// 纪律：预算不是 KPI，是**报警线**。偶尔超一点不致命，但连续超说明该改了。
import Foundation

// MARK: - 预算表

enum PerfBudget {
    /// 首屏可交互（秒）
    static let firstScreen: Double = 1.0
    /// 单次日志解析（每批 100 条，秒）
    static let logParse: Double = 0.12
    /// 成员活跃度重算（秒）
    static let memberActivity: Double = 0.30
    /// 中文检索一次（秒）
    static let search: Double = 0.12
    /// 锁内日志读取一页（秒，不含链路等待）
    static let logPage: Double = 1.5

    /// 超预算的记录。
    struct Overrun: Codable, Identifiable, Equatable {
        var id: String { at + name }
        var at: Double
        var name: String
        var took: Double
        var budget: Double
    }

    private static let overruns = Locked<[Overrun]>([])
    private static let fileName = "kf_perf_overruns.json"

    /// 记一次测量。超预算才留痕。
    @discardableResult
    static func measure(_ name: String, budget: Double, _ body: () -> Void) -> Double {
        let t0 = Date()
        body()
        let took = Date().timeIntervalSince(t0)
        record(name: name, took: took, budget: budget)
        return took
    }

    /// 记一次测量（异步）。**单独命名** —— 与同步重载同名会让闭包字面量产生歧义。
    @discardableResult
    static func measureAsync(_ name: String, budget: Double, _ body: () async -> Void) async -> Double {
        let t0 = Date()
        await body()
        let took = Date().timeIntervalSince(t0)
        record(name: name, took: took, budget: budget)
        return took
    }

    static func record(name: String, took: Double, budget: Double) {
        guard took > budget else { return }
        let o = Overrun(at: Date().timeIntervalSince1970, name: name, took: took, budget: budget)
        var list = overruns.withLock { $0 }
        list.insert(o, at: 0)
        if list.count > 100 { list = Array(list.prefix(100)) }
        overruns.withLock { $0 = list }
        DiagLogStore.writeJSON(list, name: fileName)
        DiagLogs.append("warn", "性能超预算：\(name) 用了 \(String(format: "%.0f", took * 1000))ms（预算 \(String(format: "%.0f", budget * 1000))ms）",
                        date: DiagLogs.localDay(), time: DiagTime.hhmmss())
    }

    static var recentOverruns: [Overrun] {
        let cached = overruns.withLock { $0 }
        if !cached.isEmpty { return cached }
        let list = DiagLogStore.readJSON([Overrun].self, name: fileName)
        overruns.withLock { $0 = list }
        return list
    }

    static func clearOverruns() {
        overruns.withLock { $0 = [] }
        if let url = DiagLogStore.fileURL(fileName) { try? FileManager.default.removeItem(at: url) }
    }
}

// MARK: - 启动里程碑（B44）

enum Startup {
    /// 进程启动时刻。取「App 入口第一次被加载」的那一刻 —— 不是 `main()`，
    /// 因为 SwiftUI 的 `App` 结构体初始化才是用户感知的开始。
    static let startedAt = Date()

    private static let milestones = Locked<[(String, Double)]>([])

    /// 记一个里程碑（相对启动的秒数）。
    static func mark(_ name: String) {
        let elapsed = Date().timeIntervalSince(startedAt)
        var list = milestones.withLock { $0 }
        list.append((name, elapsed))
        milestones.withLock { $0 = list }
        if elapsed > PerfBudget.firstScreen {
            DiagLogs.append("warn", "启动超预算：\(name) 在 \(String(format: "%.0f", elapsed * 1000))ms 才出现（预算 \(String(format: "%.0f", PerfBudget.firstScreen * 1000))ms）",
                            date: DiagLogs.localDay(), time: DiagTime.hhmmss())
        }
    }

    /// 全部里程碑（诊断页用）。
    static var marks: [(name: String, elapsed: Double)] {
        milestones.withLock { $0.map { (name: $0.0, elapsed: $0.1) } }
    }

    /// 启动总耗时（到最后一个里程碑）。
    static var elapsed: Double {
        marks.last?.elapsed ?? Date().timeIntervalSince(startedAt)
    }
}

// MARK: - 内存上限（B43）

enum MemoryCap {
    /// 内存里最多留多少条记录投影。超出部分按「最新的留下」裁剪 ——
    /// 记录缓存盘上仍有全量（300 条），这里只是**不进内存**。
    static let eventsInMemory = 400

    /// 成员活跃度一次最多处理多少条日志（防止一把锁有几万条时卡住主线程）。
    static let activitySampleLimit = 2000

    /// 裁剪事件数组。
    static func trim<T>(_ items: [T]) -> [T] {
        items.count <= eventsInMemory ? items : Array(items.prefix(eventsInMemory))
    }
}
