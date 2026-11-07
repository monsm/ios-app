// LogSync.swift —— 锁内日志的增量同步（B39）与自适应分页（B42）。
//
// 现状（真机审计 2026-11-07）：锁端日志约 2000 条滚存，单轮读取有 20 页上限，
// 一次只取最近 ~200 条；撞上限后靠「断点续读」在下一次点击时继续往更早翻。
//
// 两个补齐：
//   · **后台补读**（B39）：撞上限的那一轮不必等用户再点一次 —— 连着的时候自动排下一轮。
//   · **自适应分页**（B42）：链路稳就多取几页，链路断就少取几页并退避。
//     页面大小默认仍是 5（真机验证过的口径），只有**连续成功**才放宽，断链立刻收回。
import Foundation

enum LogSync {
    /// 单轮最多翻几页（协议侧的安全上限，别轻易动）。
    static let maxPages = 20
    /// 单页条数（真机验证口径）。
    static let defaultPageSize = 5
    /// 自适应分页的取值范围。
    static let minPageSize = 3
    static let maxPageSize = 8
    /// 连续几页成功才放宽页大小。
    static let pagesBeforeGrow = 3

    struct Progress {
        var page: Int
        var pages: Int
        var read: Int
    }

    struct Result {
        var read: Int = 0
        var pages: Int = 0
        var remaining: Int? = nil
        var capped: Bool = false
        var lowest: UInt32? = nil
        var done: Bool = true
        /// 中途断链（已读到的仍落盘）。
        var interrupted: Bool = false
        var message: String? = nil
    }

    /// 每把锁的自适应状态（页大小 + 连续成功页数）。
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

    /// 读一轮。**从游标继续**（有锚点就往更早翻），撞上限时把锚点留下。
    ///
    /// 中途断链不算白读：已读到的先落盘并留锚点，下一轮从断点继续。
    static func sync(mac: String,
                     maxPages: Int = maxPages,
                     onProgress: (@Sendable (Progress) -> Void)? = nil) async -> Result {
        var result = Result()
        var startIdx: UInt32 = RecordsSource.logCursor(mac: mac) ?? 0xFFFF_FFFF
        var collected: [LogEntry] = []
        var surplus: Int?
        var pages = 0
        let size = pageSize(mac)

        do {
            for _ in 0 ..< maxPages {
                // 取消：用户按下「取消」后不再翻下一页（已读的照旧落盘）。
                if Task.isCancelled { break }
                let page = try await LockService.shared.getLogs(startIdx: startIdx, pageSize: size)
                pages += 1
                result.pages = pages
                if let s = page.surplus { surplus = s }
                if page.logs.isEmpty { break }
                collected.append(contentsOf: page.logs)
                result.read = collected.count
                onProgress?(Progress(page: pages, pages: maxPages, read: collected.count))
                if let s = page.surplus, s <= 0 { break }
                if page.logs.count < size { break }
                guard let low = page.logs.map(\.idxRaw).min(), low > 0 else { break }
                startIdx = low - 1
            }
            noteSuccess(mac, pages: pages)
        } catch {
            // 真机断链是常态（审计实测 16 页里断 4 次）—— 已读到的先落盘 + 留锚点。
            noteDisconnect(mac)
            guard !collected.isEmpty else {
                result.interrupted = true
                result.message = error.localizedDescription
                return result
            }
            DB.writeLogs(mac, collected)
            let low = collected.map(\.idxRaw).min()
            if let l = low, l > 0 { RecordsSource.setLogCursor(mac: mac, l - 1) }
            result.read = collected.count
            result.lowest = low
            result.capped = true
            result.done = false
            result.interrupted = true
            result.message = error.localizedDescription
            return result
        }

        let capped = pages >= maxPages && (surplus ?? 0) > 0
        let lowest = collected.map(\.idxRaw).min()
        if capped, let low = lowest, low > 0 {
            RecordsSource.setLogCursor(mac: mac, low - 1)
        } else {
            RecordsSource.setLogCursor(mac: mac, nil)
        }
        DB.writeLogs(mac, collected)
        RecordsSource.markSynced(mac: mac, at: Int64(Date().timeIntervalSince1970 * 1000))
        result.capped = capped
        result.remaining = capped ? surplus : nil
        result.lowest = lowest
        result.done = !capped
        return result
    }

    // MARK: - 后台补读（B39）

    private static let pending = Locked(Set<String>())
    private static var running = false

    /// 排一轮后台补读（同一把锁只排一次）。
    static func scheduleBackground(_ mac: String) {
        guard !mac.isEmpty else { return }
        pending.withLock { $0.insert(mac) }
    }

    static var pendingMacs: [String] {
        pending.withLock { Array($0) }
    }

    /// 跑排队中的补读。**一次一把锁** —— BLE 链路只挂得下一个 waiter。
    @MainActor
    static func runPending() async {
        guard !running else { return }
        running = true
        defer { running = false }
        while let mac = pendingMacs.first {
            pending.withLock { $0.remove(mac) }
            guard !DB.isDecoy else { continue }
            // 只在真的连着的时候补读 —— 否则只是白等 8 秒超时。
            guard LockService.shared.connectedMAC == mac else { continue }
            _ = await sync(mac: mac, maxPages: 4)
        }
    }
}
