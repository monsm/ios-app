// LogReadJournal.swift —— 每一次「从门锁读日志」都留一条记录。
//
// 为什么要留：读日志是**唯一**会覆盖本机记录副本的动作，而且现在每轮都是
// 「先清空本地、再把锁里的全量循环读回来」—— 一次中断就会留下半本。
// 事后要能回答三个问题：上次什么时候读的、读到多少、为什么没读完。
//
// 落盘在 Caches（不进备份）：记录里有锁名与时间，属于使用痕迹。
import Foundation

enum LogReadJournal {
    struct Entry: Codable, Identifiable, Equatable {
        var id: String { "\(Int(at))-\(mac)" }
        /// epoch 毫秒
        var at: Double
        var mac: String
        var lockName: String
        /// 本轮翻了多少页
        var pages: Int
        /// 本轮写入缓存的条数
        var read: Int
        /// 是否读到了锁端历史的尽头
        var done: Bool
        /// 用户取消
        var cancelled: Bool
        /// 中途断链（已读到的仍已落盘）
        var interrupted: Bool
        /// 总耗时（毫秒）
        var durationMs: Int
        /// 结果说明（人话）
        var note: String

        var outcome: String {
            if cancelled { return "已取消" }
            if interrupted { return "中断" }
            return done ? "完整" : "未读完"
        }

        var outcomeIsOK: Bool { !cancelled && !interrupted && done }
    }

    /// 保留最近多少次（够看一屏即可）。
    static let cap = 50
    private static let fileName = "kf_log_read_journal.json"
    private static let cache = Locked<[Entry]?>(nil)

    static func record(_ entry: Entry) {
        var list = cache.withLock { $0 } ?? load()
        list.insert(entry, at: 0)
        if list.count > cap { list = Array(list.prefix(cap)) }
        cache.withLock { $0 = list }
        DiagLogStore.writeJSON(list, name: fileName)
    }

    static func entries(_ n: Int = 20) -> [Entry] {
        let list = cache.withLock { $0 } ?? load()
        return Array(list.prefix(n))
    }

    static func clear() {
        cache.withLock { $0 = [] }
        if let url = DiagLogStore.fileURL(fileName) { try? FileManager.default.removeItem(at: url) }
    }

    private static func load() -> [Entry] {
        DiagLogStore.readJSON([Entry].self, name: fileName)
    }

    /// 人话摘要（诊断页一行）。
    static func summary(_ e: Entry) -> String {
        "\(DiagTime.mmddHHmm()) · \(e.outcome) · \(e.pages) 页 / \(e.read) 条 · \(e.durationMs / 1000) 秒"
    }
}
