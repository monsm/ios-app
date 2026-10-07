// 包9 记录检索与告警核心 (纯本地, 只读既有台账)
//   检索: 551 全局搜索 / 554 自然语言 / 555 加减号 / 562 实时计数 / 553 历史 /
//         560 命名过滤视图 / 564 时段 / 571 工作日周末 / 572 深夜预设 / 574 活跃凭证 /
//         575 越界开门 / 569 失败事件 (仅 10/13/224 告警级, 锁端无逐次失败明细) /
//         594·671·672 节假日 (内置 2026-2027 简表, 手工维护) / 737 今日试错
//   告警: 723 跨锁流 / 724 四级色标 / 726 处置留痕 / 734 未处理优先 / 741 同类计数 /
//         745 测试标记排除 / 727 检查清单 (复用处置字段) / 742 响应时长 (占位"积累中")
// 纪律: 颜色只走 DS 令牌 (danger 派生, 页面层 .opacity); 告警类型只用 CAPABILITY §3
//       真实存在的 5 种 (6 低电 / 7 防撬 / 10 试错锁定 / 13 指纹告警 / 224 键盘锁定);
//       归属统计走 Attribution 可证明链, 推断值一律标"约"。
import Foundation

/// 一条可检索的记录行 (跨锁聚合单元, 770)
struct Rec: Identifiable {
    var key: String        // 行 key (锁日志 idxRaw)
    var mac: String        // 归属锁 (全部锁模式下定位)
    var lockName: String   // 770 锁名前缀标签
    var type: Int
    var typeName: String
    var idxRaw: UInt32
    var lockTime: Int64
    var timeStr: String    // "yyyy-MM-dd HH:mm:ss"
    var whoId: String?     // 可证明归属成员 id (791 认领在 UI 层叠加)
    var whoName: String?   // 可证明归属才填 (显示名), 否则 nil
    var kind: String?      // fp/pwd/temp/key (开门类才有)
    var provable: String?  // temp/unique
    var cred: String       // 568 凭证维度标签 (归所有凭证历史用)
    var alarm: Bool
    var care: Bool         // 手机侧保养/换电事件 (1028)
    var failMsg: String    // 92 手机侧失败原因 (非空 = kf_fevents_ 行)
    var id: String { mac + "#" + key }
}

/// 724 四级告警色标: 提示/注意/严重/紧急 — 真实 5 种告警类的本地定级
/// (协议无胁迫类, 不虚构; 定级与色标映射在 AlarmCenterView 的 RecordSearch 扩展, 形状冗余保色觉可读)
enum AlarmMeta {
    static let urgent: Set<Int> = [7, 224]   // 防撬 / 键盘锁定
    static let serious: Set<Int> = [10, 13]  // 试错锁定 / 指纹告警
    static let info: Set<Int> = [6]          // 低电量
    static func isAlarm(_ t: Int) -> Bool { urgent.contains(t) || serious.contains(t) || info.contains(t) }
    static func level(_ t: Int) -> Int {
        if urgent.contains(t) { return 3 }
        if serious.contains(t) { return 2 }
        return 1
    }
    static func levelName(_ t: Int) -> String {
        switch level(t) {
        case 3: return "紧急"
        case 2: return "严重"
        default: return "提示"
        }
    }
}

/// 660 告警措辞分级: 紧急强措辞 / 严重关注 / 提示建议式, 文案集中一处
enum AlarmWords {
    static func phrase(_ t: Int) -> String {
        switch t {
        case 7: return "请立即确认门体安全"
        case 224: return "键盘已锁定, 请留意近期异常试错"
        case 10: return "多次密码失败已触发锁定, 请关注"
        case 13: return "指纹模块告警, 建议检查传感器"
        case 6: return "建议两周内更换电池"
        case 0: return failPhrase   // 92 手机侧失败行 (非锁端告警)
        default: return "请留意"
        }
    }
    static let failPhrase = "本次开锁未成功, 请留意原因"
}

/// 674 通勤时段标签: 工作日 7-9 / 17-19 实时计算, 无需积累
enum CommuteLabel {
    static func tag(date: Date, hour: Int) -> String? {
        let c = Calendar(identifier: .chinese)
        let wk = c.component(.weekday, from: date)
        guard wk != 1, wk != 7 else { return nil }   // 周一=2, 周日=7
        if (7...9).contains(hour) { return "通勤" }
        if (17...19).contains(hour) { return "通勤" }
        return nil
    }
}

/// 658 自然时段词: 清晨/上午/午间/下午/傍晚/深夜 (组头与行级小字共用)
enum TimeWord {
    static func word(_ hour: Int) -> String {
        switch hour {
        case 0..<5: return "清晨"
        case 5..<9: return "上午"
        case 9..<11: return "午前"
        case 11..<13: return "午间"
        case 13..<17: return "下午"
        case 17..<19: return "傍晚"
        case 19..<23: return "晚间"
        default: return "深夜"
        }
    }
}

/// 655 动词化日志文案 (统一动词表: "张三 用 指纹 开了门", 告警/操作各用各的动词)
enum RecordVerbs {
    static let openVerb: [Int: String] = [1: "用了数字钥匙开了门", 2: "用了密码开门", 3: "用指纹开了门", 4: "用一次性密码开门", 5: "用 NFC 开了门"]
    static let alarmVerb: [Int: String] = [6: "触发低电量提醒", 7: "出现撬锁告警", 10: "多次密码失败已锁定", 13: "指纹模块告警", 224: "键盘被锁定"]
    static let opVerb: [Int: String] = [
        8: "重新上电", 9: "DFU 后更新版本", 12: "校时完成", 14: "同步 PIN", 15: "同步密码",
        20: "录入了指纹", 21: "删除了指纹", 22: "调整了安全级别", 23: "切换了状态广播",
        24: "设置了单双验", 25: "开通了临时密码", 26: "调整了音量", 27: "设置了 beacom 密钥"
    ]
    /// whoName 可空; kindWord 由 Attribution.words 取
    static func line(type: Int, who: String?, kindWord: String?, typeName: String) -> String {
        let prefix = (who?.isEmpty ?? true) ? "" : who! + " "
        if let v = openVerb[type] {
            if let w = kindWord, !w.isEmpty { return prefix + "用" + w + "开了门" }
            return prefix.isEmpty ? v : prefix + v
        }
        if let v = alarmVerb[type] { return prefix.isEmpty ? v : prefix + v }
        if let v = opVerb[type] { return prefix + v }
        return typeName
    }
}

/// 查询过滤 (564/571/572/567/568 的本地筛选态)
struct QueryFilters: Codable, Equatable {
    var segment: Int = 0            // 564 时段: 0 全部 / 1 早(6-10) / 2 午(10-15) / 3 晚(15-22) / 4 深夜
    var dayKind: Int = 0            // 571: 0 全部 / 1 仅工作日 / 2 仅周末
    var lateNight = false           // 572 深夜预设 (跟随 676 夜间时段配置)
    var alarmOnly = false          // 567
    var kind: String = ""          // 568 凭证维度: fp/pwd/temp/key 或 owner 名
    var failedOnly = false          // 569 失败事件 (仅 10/13/224 + 92 手机侧失败, 锁端仅记录告警级)
}

/// 560 命名过滤视图 (kf_rviews): 文本 + 过滤 + 范围长期复用
struct NamedView: Codable, Identifiable {
    var id: String
    var name: String
    var text: String
    var filters: QueryFilters
    var scopeAll: Bool
}

enum RecordSearch {
    // ---------- 数据源: 聚合多锁 + 手机侧事件 (561/770 跨锁范围切换) ----------
    static func buildRecs(macs: [String], includeFails: Bool = true, includeCare: Bool = true) -> [Rec] {
        var out = [Rec]()
        let members = DB.members()
        func memberName(_ id: String?) -> String? {
            guard let id, !id.isEmpty else { return nil }
            return members.first(where: { $0.id == id })?.name
        }
        for mac in macs {
            let kc = DB.keychain(mac)
            let lockName = LockArchive.displayName(kc ?? Keychain(mac: mac, skey: ""))
            let logs = DB.readLogs(mac)
            let pws = DB.listPwds(mac)
            let fps = DB.listFps(mac)
            let snap = DB.readStatus(mac)
            let entries = logs.map { LogEntry(type: $0.type, typeName: $0.typeName, idx: $0.idxRaw, idxRaw: $0.idxRaw, lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr, body: "") }
            let cls = Attribution.classify(logs: entries, pwds: pws, fps: fps, status: snap.map { ($0.fpStock, $0.pwdStock, $0.lockTime ?? 0) })
            for (i, e) in entries.enumerated() {
                guard i < cls.count else { continue }
                let c = cls[i]
                let who = memberName(c.who)
                let cred = credLabel(kind: c.kind, who: who, pws: pws, fps: fps, e: e)
                out.append(Rec(key: String(e.idxRaw), mac: mac, lockName: lockName, type: e.type,
                               typeName: e.typeName, idxRaw: e.idxRaw, lockTime: e.lockTime,
                               timeStr: e.lockTimeStr, whoId: c.who, whoName: who, kind: c.kind,
                               provable: c.provable, cred: cred,
                               alarm: StatsKit.alarmTypes.contains(e.type), care: false, failMsg: ""))
            }
            if includeFails {
                for fe in DB.failEvents(mac) {
                    out.append(Rec(key: "f_" + String(Int(fe.ts)), mac: mac, lockName: lockName, type: 0,
                                   typeName: fe.msg.isEmpty ? "开锁失败" : "开锁失败 · " + fe.msg,
                                   idxRaw: 0, lockTime: 0,
                           timeStr: Self.localStr(fe.ts), whoName: nil, kind: nil, provable: nil,
                                   cred: "", alarm: false, care: false, failMsg: fe.msg))
                }
            }
            if includeCare {
                for ce in BatteryCare.events(mac) {
                    let isBatt = ce.kind == "battery"
                    out.append(Rec(key: "c_" + String(Int(ce.ts)), mac: mac, lockName: lockName, type: 0,
                                   typeName: isBatt ? "更换电池" : "保养完成 · " + ce.note,
                                   idxRaw: 0, lockTime: 0,
                           timeStr: Self.localStr(ce.ts / 1000), whoName: nil, kind: nil, provable: nil,
                                   cred: "", alarm: false, care: true, failMsg: ""))
                }
            }
        }
        out.sort { $0.timeStr > $1.timeStr }   // 字符串序 = 时间倒序 (同格式)
        return out
    }
    /// 568 凭证维度标签: 可证明归属才给人名, 否则给类型 (推断值前端标"约")
    private static func credLabel(kind: String?, who: String?, pws: [LedgerPwd], fps: [LedgerFp], e: LogEntry) -> String {
        switch kind {
        case "fp":
            if let who, !who.isEmpty { return "指纹 · " + who }
            return "指纹"
        case "pwd", "temp":
            if let who, !who.isEmpty { return (kind == "temp" ? "临时码" : "密码") + " · " + who }
            return kind == "temp" ? "临时码" : "密码"
        case "key": return "数字钥匙"
        default: return ""
        }
    }
    static func localStr(_ ts: Double) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone.current
        return f.string(from: Date(timeIntervalSince1970: ts))
    }

    /// 569 越界开门 (575): 临时码时间窗 (台账 from/to) 之外仍产生开门 — 本地检测, 标"约"
    struct OutWin {
        var rec: Rec
        var window: String     // "约 10-01 08:00 – 10-02 08:00"
    }
    static func outOfWindow(macs: [String]) -> [OutWin] {
        var out = [OutWin]()
        for mac in macs {
            let pws = DB.listPwds(mac).filter { $0.temp }
            guard !pws.isEmpty else { continue }
            for r in buildRecs(macs: [mac], includeFails: false, includeCare: false) where r.type == 4 {
                guard let d = dateOf(r) else { continue }
                let t = d.timeIntervalSince1970
                for p in pws {
                    guard let f = parseStamp(p.from), let to = parseStamp(p.to), f > 0, to > 0 else { continue }
                    let ts = Int(t)
                    if ts > to || ts < f {
                        out.append(OutWin(rec: r, window: "约 " + String(p.from.dropFirst(5).prefix(11)) + " – " + String(p.to.dropFirst(5).prefix(11))))
                        break
                    }
                }
            }
        }
        return out.sorted { $0.rec.timeStr > $1.rec.timeStr }
    }
    private static func parseStamp(_ s: String) -> Int64 {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")     // 与 Attribution.ms 同语义 (JS 生态本地串按 UTC 读)
        return Int64(f.date(from: s)?.timeIntervalSince1970 ?? 0)
    }

    /// 574 活跃凭证 (台账推断, 展示层必须标"约"): 近 30 天开门日志按类型计次
    static func activeCredentials(mac: String) -> [(kind: String, word: String, count: Int)] {
        let now = Date().timeIntervalSince1970
        let logs = DB.readLogs(mac).filter { l in
            guard let d = StatsKit.dateOf(l) else { return false }
            return d.timeIntervalSince1970 >= now - 30 * 86400
        }
        var c: [String: Int] = ["fp": 0, "pwd": 0, "temp": 0, "key": 0]
        let typeToKind: [Int: String] = [3: "fp", 2: "pwd", 4: "temp", 1: "key"]
        for l in logs { if let k = typeToKind[l.type] { c[k, default: 0] += 1 } }
        return c.sorted { $0.value > $1.value }.map { ($0.key, Attribution.words[$0.key] ?? $0.key, $0.value) }
    }

    /// 737 今日试错 (⚠ keyboardErrCount 语义不确定, 只用日志条数, 标题带"?"由 UI 层标)
    static func trialCountToday(macs: [String]) -> Int {
        let today = dayKeyOf(Date())
        var n = 0
        for mac in macs {
            for l in DB.readLogs(mac) where l.type == 10 && String(l.lockTimeStr.prefix(10)) == today { n += 1 }
        }
        return n
    }

    static func dateOf(_ l: CachedLog) -> Date? { StatsKit.dateOf(l) }
    static func dateOf(_ r: Rec) -> Date? {
        if !r.timeStr.isEmpty {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            f.timeZone = TimeZone.current
            return f.date(from: r.timeStr)
        }
        return nil
    }
    static func dayKeyOf(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f.string(from: d)
    }
    /// "yyyy-MM-dd" → 该日 0 点 (本地时区)
    static func dateFromKey(_ key: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f.date(from: key)
    }
    /// 649 凌晨归属前一晚: 0:00-4:59 归前一天
    static func dayKeyOfNight(_ d: Date) -> String {
        let c = Calendar.current
        if c.component(.hour, from: d) < 5 {
            return dayKeyOf(c.date(byAdding: .day, value: -1, to: d) ?? d)
        }
        return dayKeyOf(d)
    }
    /// 676 夜间时段配置 (默认 22-6, 设置可调): 572 深夜预设 / 564 深夜段共用
    static var nightFrom: Int { DB.store.getInt("kf_night_from", 22) }
    static var nightTo: Int { DB.store.getInt("kf_night_to", 6) }
    static func isLateNight(_ hour: Int) -> Bool {
        let a = nightFrom, b = nightTo
        return a > b ? (hour >= a || hour < b) : (hour >= a && hour < b)
    }

    // ---------- 594/671/672 节假日内置简表 (手工维护 2026-2027, UI 层标注"手工维护") ----------
    struct Holiday {
        var day: String    // "yyyy-MM-dd"
        var name: String
    }
    static let holidays: [Holiday] = [
        Holiday(day: "2026-01-01", name: "元旦"),
        Holiday(day: "2026-02-16", name: "春节"),
        Holiday(day: "2026-02-17", name: "春节"),
        Holiday(day: "2026-04-05", name: "清明"),
        Holiday(day: "2026-05-01", name: "劳动节"),
        Holiday(day: "2026-06-19", name: "端午"),
        Holiday(day: "2026-09-25", name: "中秋"),
        Holiday(day: "2026-10-01", name: "国庆"),
        Holiday(day: "2027-01-01", name: "元旦"),
        Holiday(day: "2027-02-05", name: "春节"),
        Holiday(day: "2027-02-06", name: "春节"),
        Holiday(day: "2027-04-05", name: "清明"),
        Holiday(day: "2027-05-01", name: "劳动节"),
        Holiday(day: "2027-06-09", name: "端午"),
        Holiday(day: "2027-09-15", name: "中秋"),
        Holiday(day: "2027-10-01", name: "国庆"),
    ]
    private static let holidayMap: [String: String] = Dictionary(holidays.map { ($0.day, $0.name) }, by: { a, _ in a })
    /// 671 节假日名 (组头标签); 调休工作日不内置 (无逐年数据源), 只标法定节假日
    static func holidayName(_ dayKey: String) -> String? { holidayMap[dayKey] }
    /// 672 假日顺延: 节假日当日"异常时段"判定结束时间 +2 小时 (设置可关)
    static var holidayExtendOn: Bool { DB.store.getBool("kf_holiday_extend", true) }
    static func extendedEndHour(_ dayKey: String) -> Int? {
        guard holidayExtendOn, holidayName(dayKey) != nil else { return nil }
        return (nightTo + 2) % 24
    }

    // ---------- 554 自然语言 + 555 加减号: 关键词抽取 ----------
    struct Query {
        var must: [String]      // 正词 (含 + 前缀与裸词)
        var not: [String]      // - 前缀
        var member: String?    // 551 成员名
        var range: (from: Date, to: Date)?   // 554 时间短语
        var alarmOnly: Bool    // "告警" 关键词
        var credKind: String?  // 凭证类词 (指纹/密码/临时码/NFC/钥匙)
        var parsedTags: [String]   // 555 预览标签
    }
    static func parse(_ raw: String) -> Query {
        var q = Query(must: [], not: [], member: nil, range: nil, alarmOnly: false, credKind: nil, parsedTags: [])
        // 555 加减号: 空格切词, 识别 +/- 前缀 (其余为裸词)
        for tok in raw.components(separatedBy: " ") where !tok.isEmpty {
            if let f = tok.first, f == "-" {
                if tok.count > 1 {
                    q.not.append(String(tok.dropFirst()))
                    q.parsedTags.append(String(tok))
                }
            } else if let f = tok.first, f == "+" {
                if tok.count > 1 {
                    q.must.append(String(tok.dropFirst()))
                    q.parsedTags.append(String(tok))
                }
            } else {
                q.must.append(tok)
                q.parsedTags.append(tok)
            }
        }
        let tokens = q.must
        let joined = tokens.joined(separator: " ")
        // 554 时间短语
        for (phrase, range) in timePhrases(joined: joined) {
            _ = phrase
            q.range = range
            q.parsedTags.append(rangeLabel(range))
        }
        // 告警关键词
        if tokens.contains(where: { $0.contains("告警") || $0.contains("异常") }) {
            q.alarmOnly = true
        }
        // 凭证类词 (551 按类型词检索)
        for (word, kind) in [("指纹", "fp"), ("密码", "pwd"), ("临时码", "temp"), ("一次性密码", "temp"), ("钥匙", "key"), ("NFC", "key"), ("nfc", "key")] {
            if tokens.contains(where: { $0.localizedCaseInsensitiveContains(word) }) {
                q.credKind = kind
                break
            }
        }
        // 569 失败事件词
        if tokens.contains(where: { $0.contains("失败") || $0.contains("未成功") }) {
            q.credKind = nil
            q.parsedTags.append("失败(仅告警级)")
        }
        q.must.removeAll { $0.hasPrefix("告警") || $0.hasPrefix("失败") || $0.hasPrefix("异常") }
        // 551 成员名匹配
        let names = DB.members().map { $0.name }
        for t in tokens {
            if let hit = names.first(where: { $0.contains(t) && t.count >= 1 }) {
                q.member = hit
            }
        }
        // 自然语言时间短语在裸词里 (不含 +/-) 也识别一遍
        if q.range == nil, let r = timePhrases(joined: raw).first?.1 {
            q.range = r
            q.parsedTags.append(rangeLabel(r))
        }
        return q
    }
    private static func rangeLabel(_ r: (from: Date, to: Date)?) -> String {
        guard let r = r else { return "" }
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        f.timeZone = TimeZone.current
        return f.string(from: r.from) + " – " + f.string(from: r.to)
    }
    /// 554 中文时间短语表 (今天/昨天/昨晚/本周/上周/本月/上月/最近N天/N月D日)
    static func timePhrases(joined: String) -> [(String, (from: Date, to: Date)?)] {
        let now = Date()
        let cal = Calendar.current
        func dayRange(_ d: Date) -> (Date, Date) {
            let s = cal.startOfDay(for: d)
            return (s, cal.date(byAdding: .day, value: 1, to: s)!)
        }
        var out: [(String, (from: Date, to: Date)?)] = []
        if joined.contains("昨天") { out.append(("昨天", dayRange(cal.date(byAdding: .day, value: -1, to: now)!))) }
        else if joined.contains("今天") || joined.contains("今日") { out.append(("今天", dayRange(now))) }
        if joined.contains("昨晚") {
            let y = cal.date(byAdding: .day, value: -1, to: now)!
            let s = cal.startOfDay(for: y)
            out.append(("昨晚", (s, s.addingTimeInterval(4 * 3600))))
        }
        if joined.contains("凌晨") {
            let s = cal.startOfDay(for: now)
            out.append(("凌晨", (s, s.addingTimeInterval(5 * 3600))))
        }
        if joined.contains("上周") {
            let curWeek = cal.dateInterval(of: .weekOfYear, for: now)!
            out.append(("上周", (curWeek.start.addingTimeInterval(-7 * 86400), curWeek.start)))
        }
        if joined.contains("本周") {
            let curWeek = cal.dateInterval(of: .weekOfYear, for: now)!
            out.append(("本周", (curWeek.start, now)))
        }
        if joined.contains("上月") {
            let m = cal.dateInterval(of: .month, for: cal.date(byAdding: .month, value: -1, to: now)!)!
            out.append(("上月", (m.start, m.end)))
        }
        if joined.contains("本月") {
            let m = cal.dateInterval(of: .month, for: now)!
            out.append(("本月", (m.start, now)))
        }
        if let n = intAfter(joined, "最近"), n > 0 {
            let s = now.addingTimeInterval(-Double(n) * 86400)
            out.append(("最近 \(n) 天", (cal.startOfDay(for: s), now)))
        }
        // "N月D日" (只认含"月"的那个词, 避免"工作日"里的"日"误命中; 当年, 已过则去年)
        if let tok = tokensFirstContaining(joined: joined, "月"),
           let mo = intBefore(tok, "月"), mo > 0, let dy = intAfter(tok, "日"), dy > 0 {
            var c = DateComponents(); c.year = cal.component(.year, from: now); c.month = mo; c.day = dy
            var d = cal.date(from: c)!
            if d > now {
                c.year! -= 1
                d = cal.date(from: c)!
            }
            let label = String(tok)
            out.append((label, dayRange(d)))
        }
        return out
    }
    /// "最近(\d+)" 取括号内数字
    private static func intAfter(_ s: String, _ head: String) -> Int? {
        guard let i = s.range(of: head) else { return nil }
        let tail = s[i.upperBound...]
        var digits = ""
        for ch in tail {
            if ch.isNumber { digits.append(ch) } else { break }
        }
        return Int(digits)
    }
    /// 取 "月" 前的数字 (同一词内)
    private static func intBefore(_ tok: String, _ tail: String) -> Int? {
        guard let i = tok.range(of: tail) else { return nil }
        let head = tok[..<i.lowerBound]
        var digits = ""
        for ch in head {
            if ch.isNumber { digits.append(ch) } else { return nil }
        }
        return Int(digits)
    }
    /// 含"月"的最短匹配词 (空格切词后找, 取首个)
    private static func tokensFirstContaining(joined: String, _ marker: String) -> String? {
        for tok in joined.components(separatedBy: " ") where tok.contains(marker) {
            return tok
        }
        return nil
    }

    /// 551 全局搜索 + 过滤: 文本命中 (成员名/凭证/类型名/备注式合成文本) + 过滤条件
    static func search(recs: [Rec], query: Query, filters: QueryFilters) -> [Rec] {
        let cal = Calendar.current
        var out = [Rec]()
        let hasTextCond = !(query.must.isEmpty && query.member == nil && !query.alarmOnly && query.credKind == nil)
        for r in recs {
            if hasTextCond {
                let hay = hayOf(r)
                // 555: 全部正词须命中 (OR 成员名), 全部负词须未命中
                let memberHit = query.member.map { hay.localizedCaseInsensitiveContains($0) } ?? false
                let mustHit = query.must.isEmpty || query.must.allSatisfy { hay.localizedCaseInsensitiveContains($0) } || memberHit
                let notHit = query.not.allSatisfy { !hay.localizedCaseInsensitiveContains($0) }
                guard mustHit, notHit else { continue }
                if query.alarmOnly, !r.alarm { continue }
                if let k = query.credKind, r.kind != k { continue }
                // 纯成员查询 (无其他关键词): 只看有归属且相符的行; 有关键词时非归属行由关键词裁决
                if let m = query.member, query.must.isEmpty {
                    guard r.whoName == m else { continue }
                } else if let m = query.member, let w = r.whoName, w != m {
                    continue
                }
            }
            // 554 时间窗
            if let rng = query.range, let d = dateOf(r) {
                if d < rng.from || d > rng.to { continue }
            }
            // 567 仅告警
            if filters.alarmOnly {
                guard r.alarm else { continue }
            }
            if filters.failedOnly {
                // ⚠569: 锁端仅记录告警级 (10/13/224), 无逐次失败明细 — UI 文案已标注
                guard r.failMsg.isEmpty ? ([10, 13, 224].contains(r.type)) : true else { continue }
            }
            // 564/572 时段 (深夜预设跟随 676 夜间时段配置)
            if let d = dateOf(r) {
                let hour = cal.component(.hour, from: d)
                let inLate = isLateNight(hour)
                if filters.lateNight && !inLate { continue }
                switch filters.segment {
                case 1: if !(6...9).contains(hour) { continue }
                case 2: if !(10...14).contains(hour) { continue }
                case 3: if !(15...21).contains(hour) { continue }
                case 4: if !inLate { continue }
                default: break
                }
                // 571 工作日/周末
                let wk = cal.component(.weekday, from: d)
                let isWeekend = wk == 1 || wk == 7
                if filters.dayKind == 1 && isWeekend { continue }
                if filters.dayKind == 2 && !isWeekend { continue }
            }
            // 568 凭证维度
            if !filters.kind.isEmpty {
                if r.kind != filters.kind && !r.cred.contains(filters.kind) { continue }
            }
            out.append(r)
        }
        return out
    }
    private static func hayOf(_ r: Rec) -> String {
        var s = r.typeName + " " + r.cred + " " + r.lockName
        if let w = r.whoName { s += " " + w }
        if !r.failMsg.isEmpty { s += " " + r.failMsg }
        return s
    }

    /// 553 搜索历史 (本地偏好, 最近 5 条, 可单删)
    private static let histKey = "kf_rsearch_hist"
    static func history() -> [String] {
        (DB.store.get([String].self, histKey) ?? []).reversed()
    }
    static func pushHistory(_ q: String) {
        var h = DB.store.get([String].self, histKey) ?? []
        let t = q.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        h.removeAll { $0 == t }
        h.insert(t, at: 0)
        DB.store.setCodable(histKey, Array(h.suffix(5)))
    }
    static func removeHistory(_ q: String) {
        var h = DB.store.get([String].self, histKey) ?? []
        h.removeAll { $0 == q }
        DB.store.setCodable(histKey, h)
    }
    static func clearHistory() { DB.store.remove(histKey) }

    /// 560 命名过滤视图 (kf_rviews)
    private static let viewsKey = "kf_rviews"
    static func namedViews() -> [NamedView] { DB.store.get([NamedView].self, viewsKey) ?? [] }
    static func saveNamedView(name: String, text: String, filters: QueryFilters, scopeAll: Bool) {
        var v = namedViews()
        v.removeAll { $0.name == name }
        v.insert(NamedView(id: UUID().uuidString.prefix(8).description, name: name, text: text, filters: filters, scopeAll: scopeAll), at: 0)
        DB.store.setCodable(viewsKey, Array(v.prefix(20)))
    }
    static func deleteNamedView(_ name: String) {
        DB.store.setCodable(viewsKey, namedViews().filter { $0.name != name })
    }

    // ---------- 726 处置留痕 (本地工单字段, 导出含处置历史) ----------
    /// 处置: key = mac#idxRaw → 结论 + 时刻; 745 测试标记存结论 "测试"
    struct Disposition: Codable {
        var at: Double        // 处置时刻 (Unix 秒)
        var verdict: String   // "已处理" / "误报" / "已处置" / "测试" / "已人工检查"
    }
    private static let dispKey = "kf_rdispo"
    static func dispositions() -> [String: Disposition] { DB.store.get([String: Disposition].self, dispKey) ?? [:] }
    static func disposition(key: String) -> Disposition? { dispositions()[key] }
    static func markDisposition(key: String, verdict: String) {
        var all = dispositions()
        all[key] = Disposition(at: Date().timeIntervalSince1970, verdict: verdict)
        DB.store.setCodable(dispKey, all)
    }
    /// 739 处置回退: 恢复未处理
    static func undoDisposition(key: String) {
        var all = dispositions()
        all.removeValue(forKey: key)
        DB.store.setCodable(dispKey, all)
    }

    // ---------- 727 防撬检查清单 (勾选状态复用处置字段, 存 kf_rcheck_<key>) ----------
    static let tamperChecks = ["确认门体与锁体完好", "检查门框合页与螺丝", "核对门扇是否被顶住", "确认门锁未被拆卸"]
    static func checkState(_ key: String) -> [Bool] {
        let saved = DB.store.get([Bool].self, "kf_rcheck_" + key) ?? [Bool](repeating: false, count: tamperChecks.count)
        var s = saved
        while s.count < tamperChecks.count { s.append(false) }
        return Array(s.prefix(tamperChecks.count))
    }
    static func setCheck(_ key: String, index: Int, on: Bool) {
        var s = checkState(key)
        if index < s.count { s[index] = on }
        DB.store.setCodable("kf_rcheck_" + key, s)
    }

    /// 741 同类告警计数: 该锁同类型累计次数 + 上次时刻 (只读既有日志, 可证明)
    struct SameCount {
        var total: Int
        var lastStr: String   // 除当前条外最近一条
    }
    static func sameTypeCount(mac: String, type: Int, exceptKey: String) -> SameCount {
        let hits = DB.readLogs(mac).filter { $0.type == type && String($0.idxRaw) != exceptKey }
        let last = hits.first?.lockTimeStr ?? ""
        return SameCount(total: hits.count + 1, lastStr: last)
    }

    /// 736 前后事件上下文: 告警前后 10 分钟同锁记录 (前 3 条 / 后 3 条)
    static func context(mac: String, aroundKey: String, minutes: Int = 10, n: Int = 3) -> (before: [Rec], after: [Rec]) {
        let recs = buildRecs(macs: [mac], includeFails: false, includeCare: false)
        guard let mid = recs.first(where: { $0.key == aroundKey }), let md = dateOf(mid) else { return ([], []) }
        let win = Double(minutes) * 60
        let t0 = md.timeIntervalSince1970
        // 前事件: [t0-win, t0) 内紧邻的 3 条 (recs 倒序 → 最新 3 条在尾部, 取 suffix 再反转为时间正序)
        let before = recs.filter { r in
            guard let d = dateOf(r) else { return false }
            return r.id != mid.id && d.timeIntervalSince1970 >= t0 - win && d.timeIntervalSince1970 < t0
        }.suffix(n)
        // 后事件: 时刻在 (t0, t0+win] 的最早 n 条 (按时间正序返回)
        let after = recs.filter { r in
            guard let d = dateOf(r) else { return false }
            return r.id != mid.id && d.timeIntervalSince1970 > t0 && d.timeIntervalSince1970 <= t0 + win
        }.prefix(n)
        return (Array(before).reversed(), Array(after))
    }

    /// 747 前后对比: 当日与前后 7 天每日开门量 (辅助判断试探迹象, 只读统计)
    struct DayOpen {
        var key: String
        var count: Int
        var isAlertDay: Bool
    }
    static func aroundDays(mac: String, aroundKey: String, days: Int = 7) -> [DayOpen] {
        let recs = buildRecs(macs: [mac], includeFails: false, includeCare: false)
        guard let mid = recs.first(where: { $0.key == aroundKey }),
              let md = dateOf(mid) else { return [] }
        let cal = Calendar.current
        let alertKey = dayKeyOf(md)
        var out = [DayOpen]()
        for i in stride(from: -days, through: days, by: 1) {
            let k = cal.date(byAdding: .day, value: i, to: md).map { dayKeyOf($0) } ?? alertKey
            guard let start = dateFromKey(k) else { continue }
            let end = cal.date(byAdding: .day, value: 1, to: start)!
            let c = recs.filter {
                guard let d = dateOf($0) else { return false }
                return d >= start && d < end && StatsKit.openTypes.contains($0.type)
            }.count
            out.append(DayOpen(key: k, count: c, isAlertDay: k == alertKey))
        }
        return out
    }

    /// 735 Tab 未读角标数据源: 未处置告警数 (734 未处理队列)
    static func unhandledAlarmCount(macs: [String]) -> Int {
        let disp = dispositions()
        var n = 0
        for mac in macs {
            for l in DB.readLogs(mac) where StatsKit.alarmTypes.contains(l.type) {
                if disp[mac + "#" + String(l.idxRaw)] == nil { n += 1 }
            }
        }
        return n
    }
    /// 723 跨锁告警流: 全部锁的告警行, 未处置优先排序
    static func alarmStream(macs: [String], unhandledOnly: Bool) -> [Rec] {
        let recs = buildRecs(macs: macs, includeFails: true, includeCare: false).filter { $0.alarm }
        let disp = dispositions()
        func rank(_ r: Rec) -> Int {
            unhandledOnly ? (disp[r.mac + "#" + r.key] == nil ? 0 : 1) : 2
        }
        // 734 未处理置顶; 处理过的按时间倒序垫后
        let unhandled = recs.filter { disp[$0.mac + "#" + $0.key] == nil }
        let handled = recs.filter { disp[$0.mac + "#" + $0.key] != nil }
        return unhandledOnly ? unhandled : unhandled + handled
    }
}
