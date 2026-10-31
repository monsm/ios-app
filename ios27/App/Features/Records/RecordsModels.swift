// RecordsModels.swift —— 台账域：纯逻辑 + 本机状态（不含视图）。
//
// ① 检索 / 筛选 / 分组 / 导出行模型（纯函数，可单测，不碰布局）
// ② 本机覆盖层（备注 / 标旗 / 告警处置）与跨屏上下文（详情定位 / 当天收窄 / 回到时间线闪一下）
// ③ CSV / vCard / 上周小结文本生成 —— 导出页三处真动作的数据来源
//
// 数据来源：DB.readLogs(mac) 的锁内日志缓存（经 RecordsSource.load 映射成 LedgerEntry）。
// 拉取链路（cmd16 翻页）仍待 Engine 接线，见 RecordsScreen.read() 的 TODO(engine)。
import SwiftUI

// MARK: - 台账档位（record.filter.fields 在台账模型上可用的子集）

/// 只按 LedgerEntry 真有的语义色分档，不按事件文字猜类型。
enum LedgerScope: String, CaseIterable, Identifiable {
    case all = "全部"
    case open = "开锁"
    case alarm = "告警"
    case failed = "失败"

    var id: String { rawValue }

    func matches(_ entry: LedgerEntry) -> Bool {
        switch self {
        case .all: return true
        case .open: return entry.tone == .ok || entry.tone == .live
        case .alarm: return entry.tone == .attention
        case .failed: return entry.tone == .critical
        }
    }
}

// MARK: - 检索词（record.search 的加减词口径）

/// 解析：加号词必须命中，减号词必须不命中，其余词逐个都要命中。
struct LedgerQuery {
    let text: String
    private(set) var must: [String] = []
    private(set) var exclude: [String] = []

    init(_ raw: String = "") {
        text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var musts: [String] = []
        var excludes: [String] = []
        for token in text.split(separator: " ") {
            let word = String(token).lowercased()
            if word.hasPrefix("-"), word.count > 1 {
                excludes.append(String(word.dropFirst()))
            } else if word.hasPrefix("+"), word.count > 1 {
                musts.append(String(word.dropFirst()))
            } else {
                musts.append(word)
            }
        }
        must = musts
        exclude = excludes
    }

    var isEmpty: Bool { must.isEmpty && exclude.isEmpty }

    /// 搜索面只此一处定义：事件 + 归属 + 详情。
    func matches(_ entry: LedgerEntry) -> Bool {
        let hay = [entry.event, entry.owner ?? "", entry.detail ?? ""]
            .joined(separator: " ")
            .lowercased()
        if exclude.contains(where: { hay.contains($0) }) { return false }
        return must.allSatisfy { hay.contains($0) }
    }
}

// MARK: - 筛选 / 计数（纯函数）

enum LedgerFilter {
    static func apply(_ entries: [LedgerEntry],
                      scope: LedgerScope,
                      member: String,
                      query: LedgerQuery,
                      dayFocus: String?) -> [LedgerEntry] {
        entries.filter { entry in
            scope.matches(entry)
                && (member.isEmpty || (entry.owner ?? "") == member)
                && query.matches(entry)
                && (dayFocus == nil || TimeFormat.dayKey(entry.at) == dayFocus)
        }
    }

    /// chip 只列「真有行」的成员（避免点进去空列表）。
    static func members(in entries: [LedgerEntry]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for entry in entries {
            guard let owner = entry.owner, !owner.isEmpty, !seen.contains(owner) else { continue }
            seen.insert(owner)
            out.append(owner)
        }
        return out
    }

    /// 日键 yyyy-MM-dd → 短标签 MM-dd（只裁字符串，不新建 DateFormatter）。
    static func shortLabel(_ dayKey: String) -> String {
        dayKey.count >= 10 ? String(dayKey.dropFirst(5)) : dayKey
    }

    static func dayCount(_ entries: [LedgerEntry]) -> Int {
        Set(entries.map { TimeFormat.dayKey($0.at) }).count
    }

    static func alarmCount(_ entries: [LedgerEntry]) -> Int {
        entries.filter { $0.tone == .attention || $0.tone == .critical }.count
    }

    static func opens(in entries: [LedgerEntry]) -> [LedgerEntry] {
        entries.filter { $0.tone == .ok || $0.tone == .live }
    }

    /// 近 span 天（含今天）的每日条数，旧 → 新。给「近 7 日」刻度用。
    static func recentDays(_ entries: [LedgerEntry], span: Int = 7, now: Date = Date()) -> [LedgerDayCount] {
        let calendar = TimeFormat.calendar
        let today = calendar.startOfDay(for: now)
        var buckets: [String: Int] = [:]
        for entry in entries {
            buckets[TimeFormat.dayKey(entry.at), default: 0] += 1
        }
        var out: [LedgerDayCount] = []
        for offset in stride(from: span - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = TimeFormat.dayKey(Int64(day.timeIntervalSince1970 * 1000))
            out.append(LedgerDayCount(id: key, count: buckets[key] ?? 0))
        }
        return out
    }
}

/// 一天一行读数的载体（ForEach 需要 Identifiable，元组不能当键路径）。
struct LedgerDayCount: Identifiable, Hashable {
    let id: String
    let count: Int
}

/// 一个自然日的台账组。LedgerGrouping 返回元组，元组不能当 ForEach 的键路径，故包一层。
struct LedgerDayGroup: Identifiable, Hashable {
    let dayKey: String
    let items: [LedgerEntry]
    var id: String { dayKey }

    static func make(_ raw: [(dayKey: String, items: [LedgerEntry])]) -> [LedgerDayGroup] {
        raw.map { LedgerDayGroup(dayKey: $0.dayKey, items: $0.items) }
    }
}

// MARK: - 本机覆盖层（备注 / 标旗 / 处置）

/// 键 = LedgerEntry.id（「哪把锁的哪一行」），与详情、深链、导出共用同一份行身份。
/// TODO(engine) 真实现落 kf_roverlay_（备注/旗标）与 kf_rdispo（处置结论 + 时刻），
/// 删设备时按族清除；这里先用进程内存储，跨屏共用同一份。
@Observable
final class RecordsOverlay {
    static let shared = RecordsOverlay()
    private init() {}

    /// 内存镜像只用于本页计数与即时刷新；真值落 Engine 的 kf_rnote_ / kf_rflag_ / kf_rdisp_（按锁分族）。
    private(set) var notes: [String: String] = [:]
    private(set) var flagged: Set<String> = []
    private(set) var disposed: [String: Int64] = [:]

    var noteCount: Int { notes.count }

    /// 进页时把当前锁的持久覆盖层读进内存（重启后仍能看到之前写的备注/旗标/处置）。
    func hydrate(mac: String) {
        guard !mac.isEmpty else { return }
        for (key, value) in RecordOverlay.notes(mac) { notes[key] = value }
        for key in RecordOverlay.flags(mac) { flagged.insert(key) }
        for (key, value) in RecordOverlay.dispositions(mac) {
            disposed[key] = Int64(value.at * 1000)
        }
    }

    func note(for id: String) -> String { notes[id] ?? "" }

    func setNote(_ text: String, for id: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            notes[id] = nil
        } else {
            notes[id] = trimmed
        }
        let parts = split(id)
        RecordOverlay.setNote(parts.mac, parts.row, trimmed)
    }

    func isFlagged(_ id: String) -> Bool { flagged.contains(id) }

    func toggleFlag(_ id: String) {
        if flagged.contains(id) {
            flagged.remove(id)
        } else {
            flagged.insert(id)
        }
        let parts = split(id)
        _ = RecordOverlay.toggleFlag(parts.mac, parts.row)
    }

    func isDisposed(_ id: String) -> Bool { disposed[id] != nil }

    func disposedAt(_ id: String) -> Int64? { disposed[id] }

    func dispose(_ id: String, at: Int64) {
        disposed[id] = at
        let parts = split(id)
        RecordOverlay.setDisposition(parts.mac, parts.row,
                                     RecordSearch.Disposition(at: Double(at) / 1000, verdict: "已处置"))
    }

    func undoDispose(_ id: String) {
        disposed[id] = nil
        let parts = split(id)
        RecordOverlay.setDisposition(parts.mac, parts.row, nil)
    }

    /// 行 id 口径 = "mac#idxRaw"（与 RecordsSource 同一份行身份）。
    private func split(_ id: String) -> (mac: String, row: String) {
        guard let i = id.firstIndex(of: "#") else { return ("", id) }
        return (String(id[..<i]), String(id[id.index(after: i)...]))
    }
}

// MARK: - 真数据入口（锁内日志缓存 → 台账条目）

/// 台账的唯一数据源：DB.readLogs(mac) 的锁内日志缓存（kf_logcache_<mac>，≤300 条、按 idxRaw 去重）。
/// 归属人按锁端凭证台账反推：type 11/16/17/19 的开门行才可能有归属，推不出来就留空 —— 不猜。
enum RecordsSource {
    /// 锁端日志类型：11 数字钥匙 / 16 一次性密码 / 17 密码 / 19 指纹 才算「开门」。
    static let openTypes: Set<Int> = [11, 16, 17, 19]
    /// 需要人处置的告警级：7 撬锁 / 10 多次密码失败锁定 / 13 指纹模块告警 / 224 键盘被锁定。
    static let alarmTypes: Set<Int> = [7, 10, 13, 224]

    /// 告警用注意色（还有下一步可做），其余告警用危险色（已失效/被锁）。
    private static let criticalTypes: Set<Int> = [10, 224]

    /// 装载结果：能上时间线的条目 + 锁端没回时刻、无法定位到某一天的条数。
    /// 后者单独计数，是因为把它塞进时间线等于谎报一个 1970 年的日期。
    struct Load {
        let entries: [LedgerEntry]
        let untimed: Int
    }

    static func load(mac rawMac: String, lockName: String, members: [MemberCard]) -> Load {
        let mac = DB.normalizeMac(rawMac)
        var timed: [LedgerEntry] = []
        var untimed = 0
        for log in DB.readLogs(mac) {
            // lockTime == 0 = 锁端没读到时钟（不是 2010-01-01）。没有时刻就不进时间线。
            guard log.lockTime > 0 else {
                untimed += 1
                continue
            }
            let at = Int64(ZKProtocol.protoSecondsToUnix(log.lockTime) * 1000)
            timed.append(LedgerEntry(
                id: mac + "#" + String(log.idxRaw),
                at: at,
                event: log.displayTypeName,
                owner: owner(log, members: members),
                tone: tone(log),
                detail: detail(log, lockName: lockName)
            ))
        }
        return Load(entries: timed.sorted { $0.at > $1.at }, untimed: untimed)
    }

    private static func tone(_ log: CachedLog) -> Tone {
        if alarmTypes.contains(log.type) {
            return criticalTypes.contains(log.type) ? .critical : .attention
        }
        return openTypes.contains(log.type) ? .ok : .neutral
    }

    /// TODO(engine) 归属：锁端日志只有类型与序号，没有凭证槽位，
    /// 真要可证明归属得靠 Attribution 的「日志 × 临时码/密码台账」交叉（旧层已删，需重写）。
    /// 单成员家庭可以确定是他；多成员时**如实留空**，不按名字猜。
    private static func owner(_ log: CachedLog, members: [MemberCard]) -> String? {
        guard openTypes.contains(log.type) else { return nil }
        let active = members.filter { !$0.archived }
        return active.count == 1 ? active[0].name : nil
    }

    private static func detail(_ log: CachedLog, lockName: String) -> String {
        let kind: String
        switch log.type {
        case 11: kind = "数字钥匙开门"
        case 16: kind = "一次性密码开门"
        case 17: kind = "密码开门"
        case 19: kind = "指纹开门"
        default: kind = log.displayTypeName
        }
        var parts = [lockName, kind, "序号 " + String(log.idxRaw)]
        if log.lockTime == 0 { parts.append("锁端未回时刻") }
        return parts.joined(separator: " · ")
    }

    /// 上次成功读取的时刻（kf_logsync_<mac>，毫秒）。0 = 从没读到过。
    static func lastSync(mac rawMac: String) -> Int64? {
        let raw = DB.store.getString("kf_logsync_" + DB.normalizeMac(rawMac))
        guard let value = Double(raw), value > 0 else { return nil }
        return Int64(value)
    }

    /// 读取后写回时间戳 —— 与真链路的落点同一个键（kf_logsync_<mac>，毫秒字符串）。
    static func markSynced(mac rawMac: String, at: Int64) {
        DB.store.set("kf_logsync_" + DB.normalizeMac(rawMac), String(at))
    }
}

// MARK: - 跨屏上下文（落到哪一条、只看哪一天，由这里承载）

@Observable
final class RecordsRoute {
    static let shared = RecordsRoute()
    private init() {}

    /// 详情页要读的那一条。
    var focusID: String?
    /// 时间线收窄到某一天。这是「显示范围」，不是筛选条件，不进条件数。
    var dayFocus: String?
    /// 回到时间线后要闪一下的行。
    var flashID: String?
    /// 详情页「搜这类记录」带回来的检索词。
    var searchSeed: String?
    /// 告警类型多选（空 = 不限）。记录页与「告警类型」页共用这一份。
    var alarmKinds: Set<Int> = []
    /// 访客过滤（家页「访客 · 临时码未归属」带过来的上下文）。
    var visitorOnly = false
}

// MARK: - 导出行模型（record.export.fields）

/// 归属只走可证明链：member 为空 = 无法证明，不猜。
struct RecordExportRow {
    let entry: LedgerEntry
    let lockName: String

    var at: Int64 { entry.at }
    var member: String { entry.owner ?? "" }
    var isAlarm: Bool { entry.tone == .attention || entry.tone == .critical }
    var dayKey: String { TimeFormat.dayKey(entry.at) }
    /// TODO(engine) 协议帧 hex：缓存层存了才原样带出，否则留空。
    var hex: String { "" }
    var key: String { entry.id }
}

// MARK: - CSV（record.rangePick 的列口径）

enum RecordCSV {
    static func field(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// 列：日期, 时间, 内容, 成员, 锁。成员不可证明写「未归属」，不猜。
    static func build(_ rows: [RecordExportRow]) -> String {
        var out = ["日期,时间,内容,成员,锁"]
        for row in rows.sorted(by: { $0.at < $1.at }) {
            let member = row.member.isEmpty ? "未归属" : row.member
            let cells = [
                field(row.dayKey),
                field(TimeDisplay.clock(row.at)),
                field(row.entry.event),
                field(member),
                field(row.lockName)
            ]
            out.append(cells.joined(separator: ","))
        }
        return out.joined(separator: "\n")
    }

    static func rowCount(_ csv: String) -> Int {
        max(0, csv.split(separator: "\n").count - 1)
    }
}

// MARK: - 成员名册 vCard 3.0（record.export 的名册那半）

enum MemberVCard {
    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// 只取成员模型真有的字段。
    /// TODO(engine) 电话与备注在 kf_member_ext 里，接上后再补 TEL / NOTE。
    static func build(_ members: [MemberCard]) -> String {
        var out = ""
        for member in members where !member.archived {
            out += "BEGIN:VCARD\n"
            out += "VERSION:3.0\n"
            out += "FN:" + escape(member.name) + "\n"
            out += "ROLE:" + escape(member.role.rawValue) + "\n"
            out += "NOTE:" + escape("持有凭证 " + String(member.keyCount) + " 枚") + "\n"
            out += "END:VCARD\n"
        }
        return out
    }
}

// MARK: - 上周小结（record.digest：上一个完整自然周，周一–周日）

enum WeeklyDigest {
    struct Digest {
        let lines: [String]
        let csv: String
        let rows: Int
        let from: Int64
        let to: Int64
    }

    /// 周一为一周之始（公历 weekday 1 = 周日 … 7 = 周六）。
    static func mondayStart(_ date: Date) -> Date {
        let calendar = TimeFormat.calendar
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let offset = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: day) ?? day
    }

    static func lastWeek(entries: [LedgerEntry], lockName: String, now: Date = Date()) -> Digest {
        let calendar = TimeFormat.calendar
        let thisMonday = mondayStart(now)
        let start = calendar.date(byAdding: .day, value: -7, to: thisMonday) ?? thisMonday
        let from = Int64(start.timeIntervalSince1970 * 1000)
        let to = Int64(thisMonday.timeIntervalSince1970 * 1000)
        let week = entries.filter { $0.at >= from && $0.at < to }.sorted { $0.at < $1.at }

        let opens = LedgerFilter.opens(in: week).count
        let alarms = LedgerFilter.alarmCount(week)
        let span = TimeFormat.dayShort(from) + " – " + TimeFormat.dayShort(to - 1)

        var lines: [String] = []
        if week.isEmpty {
            lines.append("上周（" + span + "）本机台账里没有记录。")
        } else {
            lines.append("上周（" + span + "）共 " + String(week.count) + " 条记录：开门 " + String(opens) + " 次、告警 " + String(alarms) + " 条。")
            if let busiest = busiestDay(week) {
                lines.append("最忙的一天是 " + TimeFormat.dayShort(busiest.at) + "，" + String(busiest.count) + " 条。")
            }
            let people = LedgerFilter.members(in: week)
            lines.append(people.isEmpty
                         ? "这些记录都没有可证明的归属人。"
                         : "涉及 " + String(people.count) + " 位成员：" + people.joined(separator: "、") + "。")
        }

        let rows = week.map { RecordExportRow(entry: $0, lockName: lockName) }
        return Digest(lines: lines, csv: RecordCSV.build(rows), rows: rows.count, from: from, to: to)
    }

    /// 条数最多的一天（同数取较晚的一天）。
    private static func busiestDay(_ week: [LedgerEntry]) -> (at: Int64, count: Int)? {
        var buckets: [String: (at: Int64, count: Int)] = [:]
        for entry in week {
            let key = TimeFormat.dayKey(entry.at)
            let old = buckets[key]
            buckets[key] = (at: max(old?.at ?? entry.at, entry.at), count: (old?.count ?? 0) + 1)
        }
        return buckets.values.max { lhs, rhs in
            lhs.count == rhs.count ? lhs.at < rhs.at : lhs.count < rhs.count
        }
    }
}
