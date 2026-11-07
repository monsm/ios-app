// CommandTimeline.swift —— 命令时间线（B19）与只读回放（B69）。
//
// 过去想知道「刚才那条命令到底怎么了」只能翻诊断日志 —— 那里是自由文本，
// 有 INFO/WARN 混在一起，没有耗时、没有 rc、没有「这条可能已经执行」的标记。
//
// 现在每条命令都留一条**结构化**记录：命令号、名字、耗时、rc、结果。
// 诊断页据此列出「最近 50 条命令」，一眼看出是哪一步开始不对。
//
// 两条纪律：
//   1. **不落凭据**。落盘的记录只有帧头 + KLV 骨架（字段号与长度），值一律不留。
//   2. **回放不发锁**。回放只是把内存里的原始帧重新过一遍解析器 ——
//      用来复现「解析器把这一帧读成了什么」，绝不碰门锁。
import Foundation

// MARK: - 记录

struct CommandRecord: Codable, Identifiable, Equatable {
    var id: String
    /// epoch 毫秒
    var at: Double
    var cmd: UInt8
    var name: String
    /// 结果：ok / rc=12 / timeout / writeFailed / cancelled / skipped
    var outcome: String
    /// 耗时（毫秒）
    var ms: Int
    var rc: Int?
    /// 这条命令**可能已经执行**（写命令超时 / 写失败）。
    var mayHaveExecuted: Bool
    var note: String
    /// 脱敏后的帧提示（帧头 + KLV 骨架），不含任何凭据值。
    var frameHint: String

    var isFailure: Bool { outcome != "ok" }
}

// MARK: - 时间线

enum CommandTimeline {
    /// 落盘保留条数。诊断看最近几十条就够，再多只是占地方。
    static let cap = 200
    private static let fileName = "kf_command_timeline.json"
    private static let cache = Locked<[CommandRecord]?>(nil)

    /// 记一条。
    static func record(cmd: UInt8, name: String, outcome: String, ms: Int = 0,
                       rc: Int? = nil, mayHaveExecuted: Bool = false,
                       note: String = "", frameHint: String = "") {
        let rec = CommandRecord(id: "\(Int(Date().timeIntervalSince1970 * 1000))-\(cmd)-\(name)",
                                at: Date().timeIntervalSince1970 * 1000,
                                cmd: cmd, name: name, outcome: outcome, ms: ms,
                                rc: rc, mayHaveExecuted: mayHaveExecuted,
                                note: note, frameHint: frameHint)
        var list = cache.withLock { $0 } ?? load()
        list.insert(rec, at: 0)
        if list.count > cap { list = Array(list.prefix(cap)) }
        cache.withLock { $0 = list }
        DiagLogStore.writeJSON(list, name: fileName)
    }

    /// 最近 N 条（新的在前）。
    static func entries(_ n: Int = 50) -> [CommandRecord] {
        let list = cache.withLock { $0 } ?? load()
        return Array(list.prefix(n))
    }

    /// 最近的失败（诊断页第一屏就看它）。
    static func failures(_ n: Int = 20) -> [CommandRecord] {
        entries(cap).filter(\.isFailure).prefix(n).map { $0 }
    }

    static func clear() {
        cache.withLock { $0 = [] }
        if let url = DiagLogStore.fileURL(fileName) { try? FileManager.default.removeItem(at: url) }
    }

    /// 导出成纯文本（诊断包 / 分享用）。
    static func exportText() -> String {
        let list = entries(cap)
        if list.isEmpty { return "（最近没有命令记录）" }
        return list.map { r in
            let rc = r.rc.map { " rc=\($0)" } ?? ""
            let flag = r.mayHaveExecuted ? " ⚠可能已执行" : ""
            let hint = r.frameHint.isEmpty ? "" : "  \(r.frameHint)"
            return "\(DiagTime.mmddHHmmss())  \(r.name)  \(r.outcome)\(rc)  \(r.ms)ms\(flag)\(hint)"
        }.joined(separator: "\n")
    }

    private static func load() -> [CommandRecord] {
        DiagLogStore.readJSON([CommandRecord].self, name: fileName)
    }
}

// MARK: - 回放（B69）

enum CommandReplay {
    /// 内存里的最近回包（**不落盘**）。只给「回放解析」用。
    ///
    /// 为什么存内存而不存盘：原始帧里可能有 skey / PIN / 密码 ——
    /// 落盘就等于把凭据写进文件（哪怕在 Caches）。内存里最多留 20 条，
    /// App 一关就没了，这正是我们要的。
    private static let recent = Locked<[(hex: String, cmd: UInt8, name: String)]>([])
    private static let cap = 20

    static func remember(hex: String, cmd: UInt8, name: String) {
        guard !hex.isEmpty else { return }
        var list = recent.withLock { $0 }
        list.insert((hex, cmd, name), at: 0)
        if list.count > cap { list = Array(list.prefix(cap)) }
        recent.withLock { $0 = list }
    }

    static var available: [(hex: String, cmd: UInt8, name: String)] {
        recent.withLock { $0 }
    }

    /// 回放一帧：只重新解析，**不发锁**。返回一段人能读的解析结果。
    static func replay(_ hex: String) -> String {
        let f = ZKProtocol.parseResponse(hex)
        guard f.ok else {
            return "解析失败：这帧按三种头型都读不出合法的 KLV（长度 \(hex.count / 2) 字节）。"
        }
        let shape = LockService.klvShape(f)
        return "头型 \(f.header)B · cmd 0x\(String(format: "%02x", f.cmd)) · KLV \(shape)"
    }
}
