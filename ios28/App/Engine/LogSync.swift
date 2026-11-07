// LogSync.swift —— 从门锁读日志：**每次清空本地、循环读全量**（2026-11-07 改）。
//
// 口径（用户拍板）：
//   1. 每轮开始前**先清空本机那份记录缓存** —— 不留旧副本；
//   2. 从锁端**最新一页往回循环翻**，一直翻到锁说「没有了」为止（不是增量、不是断点续读）；
//   3. 每轮都写进 `LogReadJournal`：什么时候读的、读了多少、为什么没读完。
//
// 代价要说清楚：锁端日志约 2000 条滚存，一页 5–8 条 ⇒ 一轮 250–400 页，
// 真机上要跑几分钟。所以界面上必须有进度、可取消；取消时**已读到的仍然落盘**
// （那是"最新的一段"，不是新旧混合）。
//
// 断链的处理：把已读到的写回去并如实记一条中断 —— 不清成空、也不重试整轮。
import Foundation

enum LogSync {
    /// 单页条数（真机验证口径）。链路稳时自适应放宽。
    static let defaultPageSize = 5
    static let minPageSize = 3
    static let maxPageSize = 8
    /// 连续几页成功才放宽页大小。
    static let pagesBeforeGrow = 3
    /// 单轮硬上限：防固件 bug 导致「永远说还有」的死循环。
    /// 600 页 × 8 条 = 4800 条，覆盖 2000 条滚存还有余量。
    static let pageCap = 600

    struct Progress {
        var page: Int
        var read: Int
        /// 锁端还剩多少（没报就是 nil）
        var remaining: Int?
    }

    struct Result {
        var read: Int = 0
        var pages: Int = 0
        /// 读到了锁端历史的尽头
        var done: Bool = false
        /// 用户取消
        var cancelled: Bool = false
        /// 中途断链（已读到的仍已落盘）
        var interrupted: Bool = false
        var message: String? = nil
        var durationMs: Int = 0
    }

    // MARK: - 自适应页大小

    private static let pageState = Locked([String: (pageSize: Int, streak: Int)]())

    private static func pageSize(_ mac: String) -> Int {
        pageState.withLock { $0[mac]?.pageSize } ?? defaultPageSize
    }

    private static func noteSuccess(_ mac: String, pages: Int) {
        pageState.withLock { s in
            var st = s[mac] ?? (pageSize: defaultPageSize, streak: 0)
            st.streak += pages
            if st.streak >= pagesBeforeGrow, st.pageSize < maxPageSize {
                st.pageSize = min(maxPageSize, st.pageSize + 2)
                st.streak = 0
            }
            s[mac] = st
        }
    }

    private static func noteDisconnect(_ mac: String) {
        pageState.withLock { s in
            var st = s[mac] ?? (pageSize: defaultPageSize, streak: 0)
            st.pageSize = max(minPageSize, st.pageSize - 1)
            st.streak = 0
            s[mac] = st
        }
    }

    // MARK: - 一轮完整读取

    /// 读一轮：**先清空本地**，再从最新往回翻到尽头。
    ///
    /// 调用方负责：链路已连上、不在空壳（这些在 AppModel 里判）。
    static func sync(mac: String, onProgress: (@Sendable (Progress) -> Void)? = nil) async -> Result {
        let t0 = Date()
        var result = Result()

        // 1) 先清空本机那一份 —— 从这一刻起，界面上看到的就是「这一轮读到的」，
        //    而不是上一轮留下的旧副本。
        DB.clearLogs(mac)

        var startIdx: UInt32 = 0xFFFF_FFFF
        var collected: [LogEntry] = []
        var surplus: Int?
        let size = pageSize(mac)
        var reachedEnd = false

        do {
            while true {
                if Task.isCancelled {
                    result.cancelled = true
                    break
                }
                if result.pages >= pageCap { break }

                let page = try await LockService.shared.getLogs(startIdx: startIdx, pageSize: size)
                result.pages += 1
                if let s = page.surplus { surplus = s }

                if page.logs.isEmpty { reachedEnd = true; break }
                collected.append(contentsOf: page.logs)
                result.read = collected.count
                onProgress?(Progress(page: result.pages, read: result.read, remaining: surplus))

                if let s = page.surplus, s <= 0 { reachedEnd = true; break }
                if page.logs.count < size { reachedEnd = true; break }
                guard let low = page.logs.map(\.idxRaw).min(), low > 0 else { reachedEnd = true; break }
                startIdx = low - 1
            }
            if !result.cancelled { noteSuccess(mac, pages: result.pages) }
        } catch {
            // 断链：已读到的照旧落盘（它们是"最新的那一段"），并如实记一条中断。
            noteDisconnect(mac)
            result.interrupted = true
            result.message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        // 2) 一次写入（缓存刚被清空，这里写进去的就是本轮读到的全量）。
        if !collected.isEmpty {
            DB.writeLogs(mac, collected)
            RecordsSource.markSynced(mac: mac, at: Int64(Date().timeIntervalSince1970 * 1000))
        }

        // 3) `done` 的判据只有一个：翻到了尽头（不是「够 20 页」）。
        result.done = reachedEnd && !result.interrupted && !result.cancelled
        result.durationMs = Int(Date().timeIntervalSince(t0) * 1000)

        // 4) 每一次读取都记一条（包括取消与中断）。
        let name = DB.keychain(mac).map { LockArchive.displayName($0) } ?? mac
        LogReadJournal.record(LogReadJournal.Entry(
            at: Date().timeIntervalSince1970 * 1000,
            mac: mac,
            lockName: name,
            pages: result.pages,
            read: result.read,
            done: result.done,
            cancelled: result.cancelled,
            interrupted: result.interrupted,
            durationMs: result.durationMs,
            note: result.message ?? (result.done ? "读到锁端历史尽头" : "未读完")
        ))
        return result
    }
}
