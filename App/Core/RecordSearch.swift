// 包9 记录检索与告警核心 (纯本地, 只读既有台账)
//   检索: 551 全局搜索 / 554 自然语言 / 555 加减号 / 562 实时计数 / 553 历史 /
//         560 命名过滤视图 / 564 时段 / 571 工作日周末 / 572 深夜预设 / 574 活跃凭证 /
//         575 越界开门 / 569 失败事件 (仅 10/13/224 告警级, 锁端无逐次失败明细) /
//         594·671·672 节假日 (内置表按国务院公告核对 · 含调休补班日 · 在线源见 NEXT-DECISIONS 组3) / 737 今日试错
//   告警: 723 跨锁流 / 724 四级色标 / 726 处置留痕 / 734 未处理优先 / 741 同类计数 /
//         745 测试标记排除 / 727 检查清单 (复用处置字段) / 742 响应时长 (占位"积累中")
//   551 的搜索面在 `searchFace` 一处定义, 含 186 备注与 568 凭证标签 (第一百八十九批补齐:
//   此前备注不在任何搜索面上, 而搜索框占位文案写着它可搜)。
// 纪律: 颜色只走 DS 令牌 (danger 派生, 页面层 .opacity); 告警类型只用 CAPABILITY §3
//       真实存在的 5 种 (6 低电 / 7 防撬 / 10 试错锁定 / 13 指纹告警 / 224 键盘锁定);
//       归属统计走 Attribution 可证明链, 推断值一律标"约"。
import SwiftUI
import Foundation

/// 一条可检索的记录行 (跨锁聚合单元, 770)
/// 186 记录备注 / 188 手动标旗 —— 本机覆盖层, 按 (锁, 行) 存, 不写进锁端也不混入日志缓存。
/// 用行身份 mac#idxRaw 当键: idxRaw 是锁端日志序号, 同一条记录被反复拉取仍是同一个键。
/// 手机侧行没有 idxRaw: 失败行 = "f_" + Unix 秒、保养行 = "c_" + Unix 毫秒。这一族键的出处只有两处 ——
/// `RecordSearch.buildRecs` 与 `RecordsView.render`, 第一百八十九批才并成一份 (原先单锁路径给这两族行
/// 现编了一个 `Int(ts*1000) + 下标` 的派生数当行键, 于是同一条记录在两种范围里身份不同:
/// 详情卡按 Rec 的键写备注、时间线行按派生数读 ⇒ 备注写了永远不显示, 576 详情也点不开)。
/// 备注是用户自己写的自由文本 → 属敏感本地数据, 删设备与销毁流程都按族清 (Store.removeDevice 的族表)。
enum RecordOverlay {
    static func noteKey(_ mac: String) -> String { "kf_rnote_" + mac }
    static func flagKey(_ mac: String) -> String { "kf_rflag_" + mac }
    /// 行身份归一: 多锁模式的 RowVM.key 已带 mac 前缀, 单锁路径没带 → 补齐成同一个键
    static func oid(mac: String, rowKey: String) -> String {
        rowKey.hasPrefix(mac + "#") ? rowKey : mac + "#" + rowKey
    }
    static func notes(_ mac: String) -> [String: String] {
        DB.store.get([String: String].self, noteKey(mac)) ?? [:]
    }
    static func note(_ mac: String, _ rowKey: String) -> String {
        notes(mac)[oid(mac: mac, rowKey: rowKey)] ?? ""
    }
    /// 空文本 = 删键 (不留 kf_rnote 里的空壳, 否则完整性自查会数出无意义的条目)
    static func setNote(_ mac: String, _ rowKey: String, _ text: String) {
        var m = notes(mac)
        let k = oid(mac: mac, rowKey: rowKey)
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { m.removeValue(forKey: k) } else { m[k] = String(t.prefix(60)) }   // 60 字上限: 行下灰字一行放得下
        DB.store.setCodable(noteKey(mac), m)
    }
    static func flags(_ mac: String) -> Set<String> {
        Set(DB.store.get([String].self, flagKey(mac)) ?? [])
    }
    static func isFlagged(_ mac: String, _ rowKey: String) -> Bool {
        flags(mac).contains(oid(mac: mac, rowKey: rowKey))
    }
    @discardableResult
    static func toggleFlag(_ mac: String, _ rowKey: String) -> Bool {
        var set = flags(mac)
        let k = oid(mac: mac, rowKey: rowKey)
        if set.contains(k) { set.remove(k) } else { set.insert(k) }
        DB.store.setCodable(flagKey(mac), set.sorted())
        return set.contains(k)
    }
    /// 行下灰字与左旗的读取都由上面几枚函数直接服务 UI; 不再另留 noteLine 这种"看着像入口"的别名。
}

struct Rec: Identifiable {
    var key: String        // 行 key (锁日志 idxRaw)
    var mac: String        // 归属锁 (全部锁模式下定位)
    var lockName: String   // 770 锁名前缀标签
    var type: Int
    var typeName: String
    var idxRaw: UInt32
    var lockTime: Int64
    var timeStr: String    // "yyyy-MM-dd HH:mm:ss"
    var whoId: String? = nil  // 可证明归属成员 id (791 认领在 UI 层叠加); 失败/保养行无可证明归属 → 留默认 nil
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
    /// 596 替代: 原句要的是"含胁迫告警"的日警示 —— 协议没有胁迫类 (§5), 改挂这三类**真实存在**
    /// 且在意的告警: 防撬 / 试错锁定 / 键盘锁定。比 `urgent`([7,224]) 有意多收 10:
    /// 试错锁定是"有人在试密码"的读数, "这一天出过事"这件事里它必须算。
    static let damageTypes: Set<Int> = [7, 10, 224]
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

extension RecordSearch {
    /// 告警行标题 —— 此前 RecordSearch 根本没有这个成员,
    /// 但 `AlarmCenterView:212` 与 `RecordsTimeline:83` 都在调用它 (编译期未解析符号)。
    static func alarmTitle(_ r: Rec) -> String {
        if !r.typeName.isEmpty { return r.typeName }
        return RecordVerbs.line(type: r.type, who: r.whoName, kindWord: nil, typeName: "告警 #\(r.type)")
    }
}


/// 674 通勤时段标签: 工作日 7-9 / 17-19 实时计算, 无需积累
enum CommuteLabel {
    static func tag(date: Date, hour: Int) -> String? {
        // 原写法用 `Calendar(identifier: .chinese)` 取 weekday, 而它的注释写"周一=2, 周日=7"、代码却排除 1 和 7 ——
        // 口径自相矛盾, 且农历历法的 weekday 归属并不是这里要的东西。上一批改成了裸的
        // `Calendar(identifier: .gregorian)`，但 Apple 对 `init(identifier:)` 的**默认时区没有任何文档承诺**
        // (那份 JSON 只有 declarations + parameters)，拿一个未约定的时区算"周几"，
        // 与调用方按当前时区算出的 `hour` 可能在午夜两侧差一天 (§10.31)。
        // 现在只认 `StatsKit.weekdayIndex` 那一份周序 (1=周一…7=周日，历法与时区都已在 WeekCal 钉死)。
        guard StatsKit.weekdayIndex(date) <= 5 else { return nil }   // 1~5 = 周一~周五
        if (7...9).contains(hour) { return "通勤" }
        if (17...19).contains(hour) { return "通勤" }
        return nil
    }
}

/// 658 自然时段词: 清晨/上午/午前/午间/下午/傍晚/晚间/深夜 (组头与行级小字共用)
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
    /// 566 成员过滤保持: 成员**跟着这一份一起存**，不另开一个键。
    /// 分开存的结果是"过滤组合记住了、成员没记住"这种半截行为，而且 908 的开场策略只管这一份结构,
    /// 成员游离在外面时策略切回"每次空白"也不会清掉它。
    var member: String = ""
    var failedOnly = false          // 569 失败事件 (仅 10/13/224 + 92 手机侧失败, 锁端仅记录告警级)
    /// 565 告警类型多选: 空 = 不限类型 (与 567 的"仅告警"各自独立, 两个都选中时取交集);
    /// 非空 = 只留这些告警类型 (StatsKit.alarmTypes 的子集)。按库里实际类型渲染 ——
    /// 原句列了"胁迫", 但协议日志类型表没有胁迫类 (与 725 判 ❌ 同一理由), 不虚构一个查不到的类型。
    var alarmKinds: Set<Int> = []
}

// 192 过滤会话保留: 按锁记住最后一次过滤组合, 再次进记录页不必重设 (与 NamedView 的长期存档不同, 这是"会话续用")
// 908 默认策略: 在"会话续用"之上加一层可改的开场规则 (见 load 里的 policy)。
extension QueryFilters {
    private static func key(_ mac: String) -> String { "kf_rflt_" + mac }
    /// 908 kf_filter_default: "" 记住上次(=192 原行为) / "fresh" 每次从空白起 / "alarm" 每次默认只看告警
    static let policyKey = "kf_filter_default"
    static let policies = ["", "fresh", "alarm"]
    static var policy: String {
        let v = DB.store.getString(policyKey)
        return policies.contains(v) ? v : ""
    }
    static func setPolicy(_ v: String) {
        // 白名单外一律当"记住上次"，不做"未知值就原样存"——那是把脏数据留在偏好里
        DB.store.set(policyKey, policies.contains(v) ? v : "")
    }
    static func load(mac: String) -> QueryFilters {
        switch policy {
        case "fresh": return QueryFilters()
        case "alarm": var f = QueryFilters(); f.alarmOnly = true; return f
        default: return DB.store.get(QueryFilters.self, key(mac)) ?? QueryFilters()
        }
    }
    /// 非默认策略下**照常保存**是有意的: 用户切回"记住上次"时，他上一次真的过滤组合还在。
    /// 设置页把这句讲明白，否则"我选了每次空白，为什么还在写？"会变成一条缺陷单。
    func save(mac: String) {
        guard !mac.isEmpty else { return }
        if self == QueryFilters() { DB.store.remove(Self.key(mac)) } else { DB.store.set(Self.key(mac), self) }
    }
}


enum RecordSearch {
    // 2026-10-26 精简：resurrectionHints（回收站「已删凭证可复活」提示）已删 ——
    // 它读的是 CredBinEntry 回收站条目，而回收站整套移除。

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
            let cls = Attribution.classify(logs: entries, pwds: pws, fps: fps, status: snap.map { ($0.fpStock, $0.pwdStock, $0.lockTime) })  // StatusSnapshotData.lockTime 非可选
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
            }
        }
        out.sort { $0.timeStr > $1.timeStr }   // 字符串序 = 时间倒序 (同格式)
        return out
    }
    /// 568 凭证维度标签: 可证明归属才给人名，否则给类型 (推断值前端标"约")。
    /// 310 别名：台账里那条凭证自己的备注 (`LedgerPwd.note` / `LedgerFp.note`，添加页那行
    /// "给谁·哪扇门·用多久") 的首段。刻意**不新增第二个别名字段** —— 备注已经是别名，
    /// 再造一个就会出现"两处各写一半、显示时不知道取哪个"。
    /// 只取首段并截 12 字：整条 note 常在 20 字以上，行里放不下；截断的别名不如不显示。
    /// 匹配用 `e.idx` = 锁端日志里的凭证槽号，与台账 `alias`/`batch` 同一个数 (协议确证，非推断)。
    private static func credLabel(kind: String?, who: String?, pws: [LedgerPwd], fps: [LedgerFp], e: LogEntry) -> String {
        let slot = Int(e.idx)
        func alias(_ raw: String) -> String {
            let first = raw.components(separatedBy: " · ").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return first.isEmpty ? "" : String(first.prefix(12))
        }
        let pwdAlias = kind == "pwd" || kind == "temp" ? pws.first { $0.alias == slot }?.note ?? "" : ""
        let fpAlias = kind == "fp" ? fps.first { $0.batch == slot }?.note ?? "" : ""
        let a = alias(kind == "fp" ? fpAlias : pwdAlias)
        let base: String
        switch kind {
        case "fp": base = "指纹"
        case "pwd": base = "密码"
        case "temp": base = "临时码"
        case "key": return "数字钥匙"
        default: return ""
        }
        var parts = [base]
        if let who, !who.isEmpty { parts.append(who) }
        if !a.isEmpty, a != who { parts.append(a) }
        return parts.joined(separator: " · ")
    }
    static func localStr(_ ts: Double) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
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
                    let f = parseStamp(p.from), to = parseStamp(p.to)
                    guard f > 0, to > 0 else { continue }
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

    /// 574 活跃凭证 (台账推断, 展示层必须标"约"): 近 30 天开门日志按「类型 #槽位」计次,
    /// 槽位翻台账出备注 (指纹查批次 / 密码·临时查别名), 翻不到回落"类型 #槽号" ——
    /// 旧版只汇总到四类大字, 用户看到"指纹 5 次"不知道是哪一个。
    static func activeCredentials(mac: String) -> [(kind: String, word: String, count: Int)] {
        let now = Date().timeIntervalSince1970
        let logs = DB.readLogs(mac).filter { l in
            guard let d = StatsKit.dateOf(l) else { return false }
            return d.timeIntervalSince1970 >= now - 30 * 86400
        }
        var c: [String: Int] = [:]
        let typeToKind: [Int: String] = [3: "fp", 2: "pwd", 4: "temp", 1: "key"]
        for l in logs { if let k = typeToKind[l.type] { c[k + "#" + String(l.idxRaw), default: 0] += 1 } }
        let lg = DB.ledger(mac)
        return c.sorted { $0.value > $1.value }.map { key, n in
            let parts = key.split(separator: "#", maxSplits: 1).map(String.init)
            let kind = parts.first ?? "", slot = parts.count > 1 ? parts[1] : ""
            let base = Attribution.words[kind] ?? kind
            let note = kind == "fp"
                ? lg.fps.first { String($0.batch) == slot }?.note
                : lg.pwds.first { String($0.alias) == slot }?.note
            let seg = (note ?? "").split(separator: "\n").first.map(String.init) ?? ""
            let short = seg.count > 12 ? String(seg.prefix(12)) + "…" : seg
            return (kind, short.isEmpty ? base + " #" + slot : base + " #" + slot + " · " + short, n)
        }
    }

    /// 737 今日试错判据 (唯一一份): 锁定类事件行 (type 10) 且落在今日 —— 计数与逐次明细共用
    private static func trialRowsToday(mac: String) -> [CachedLog] {
        let today = dayKeyOf(Date())
        return DB.readLogs(mac).filter { $0.type == 10 && String($0.lockTimeStr.prefix(10)) == today }
    }
    /// 737 今日试错 (⚠ keyboardErrCount 语义不确定, 只用日志条数, 标题带"?"由 UI 层标)
    static func trialCountToday(macs: [String]) -> Int {
        macs.reduce(0) { $0 + trialRowsToday(mac: $1).count }
    }

    static func dateOf(_ l: CachedLog) -> Date? { StatsKit.dateOf(l) }
    static func dateOf(_ r: Rec) -> Date? {
        if !r.timeStr.isEmpty {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone.current
            return f.date(from: r.timeStr)
        }
        return nil
    }
    /// 日 key 口径与 `StatsKit.dayKey` 合并为一份 (§10.30)：此前两处各抄一遍同样的
    /// yyyy-MM-dd + POSIX + 当前时区，值恰好相同，但改一处就会让检索分组与统计柱对不齐。
    static func dayKeyOf(_ d: Date) -> String { StatsKit.dayKey(d) }
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
        let c = WeekCal.gregorian
        if c.component(.hour, from: d) < 5 {
            return dayKeyOf(c.date(byAdding: .day, value: -1, to: d) ?? d)
        }
        return dayKeyOf(d)
    }
    /// 676 夜间时段配置 (默认 22-6): 572 深夜预设 / 564 深夜段共用。
    /// 写入一律夹到 0...23 —— 键位是 UserDefaults, 手改或导入可能塞进越界值, 判定函数不再做"回落合法值"的静默纠错。
    static var nightFrom: Int { clamp23(DB.store.getInt("kf_night_from", 22)) }
    static var nightTo: Int { clamp23(DB.store.getInt("kf_night_to", 6)) }
    static func setNightFrom(_ h: Int) { DB.store.set("kf_night_from", clamp23(h)) }
    static func setNightTo(_ h: Int) { DB.store.set("kf_night_to", clamp23(h)) }
    static func setHolidayExtend(_ on: Bool) { DB.store.set("kf_holiday_extend", on) }
    private static func clamp23(_ h: Int) -> Int { min(max(h, 0), 23) }
    /// 起==止 时区间为空集 (什么都筛不出), 界面要如实提示而不是让用户对着空列表猜
    static var nightWindowDegenerate: Bool { nightFrom == nightTo }
    /// 564/572 深夜判定。**672 假日顺延接在这里**: 节假日当日把区间终点 +2 小时。
    /// 此前 extendedEndHour/holidayExtendOn 组成一条没人走的链 = 设置形同虚设。
    /// dayKey 传 "" (或不传) = 不做假日判定, 与旧行为一致。
    static func isLateNight(_ hour: Int, dayKey: String = "") -> Bool {
        let a = nightFrom
        let b = extendedEndHour(dayKey) ?? nightTo
        return a > b ? (hour >= a || hour < b) : (hour >= a && hour < b)
    }

    // ---------- 594/671/672 节假日内置表 ----------
    // 2026 段按国务院公告逐日核对 (含 `off=false` 的调休补班日)。**2027 不内置**：公告尚未发布，
    // 原先那些 2027 行是无来源的推测值 —— 节假日表猜错会让"假日顺延/色带/春节注记"整族静默失真，
    // 所以宁可空着，等 671 的在线源拉到了再填。
    struct Holiday {
        var day: String    // "yyyy-MM-dd"
        var name: String
        var off: Bool      // true=放假日 · false=调休补班日
    }
    static let builtinRows: [Holiday] = [
        Holiday(day: "2026-01-01", name: "元旦", off: true),
        Holiday(day: "2026-01-02", name: "元旦", off: true),
        Holiday(day: "2026-01-03", name: "元旦", off: true),
        Holiday(day: "2026-01-04", name: "元旦", off: false),
        Holiday(day: "2026-02-14", name: "春节", off: false),
        Holiday(day: "2026-02-15", name: "春节", off: true),
        Holiday(day: "2026-02-16", name: "春节", off: true),
        Holiday(day: "2026-02-17", name: "春节", off: true),
        Holiday(day: "2026-02-18", name: "春节", off: true),
        Holiday(day: "2026-02-19", name: "春节", off: true),
        Holiday(day: "2026-02-20", name: "春节", off: true),
        Holiday(day: "2026-02-21", name: "春节", off: true),
        Holiday(day: "2026-02-22", name: "春节", off: true),
        Holiday(day: "2026-02-23", name: "春节", off: true),
        Holiday(day: "2026-02-28", name: "春节", off: false),
        Holiday(day: "2026-04-04", name: "清明", off: true),
        Holiday(day: "2026-04-05", name: "清明", off: true),
        Holiday(day: "2026-04-06", name: "清明", off: true),
        Holiday(day: "2026-05-01", name: "劳动节", off: true),
        Holiday(day: "2026-05-02", name: "劳动节", off: true),
        Holiday(day: "2026-05-03", name: "劳动节", off: true),
        Holiday(day: "2026-05-04", name: "劳动节", off: true),
        Holiday(day: "2026-05-05", name: "劳动节", off: true),
        Holiday(day: "2026-05-09", name: "劳动节", off: false),
        Holiday(day: "2026-06-19", name: "端午", off: true),
        Holiday(day: "2026-06-20", name: "端午", off: true),
        Holiday(day: "2026-06-21", name: "端午", off: true),
        Holiday(day: "2026-09-20", name: "国庆节", off: false),
        Holiday(day: "2026-09-25", name: "中秋", off: true),
        Holiday(day: "2026-09-26", name: "中秋", off: true),
        Holiday(day: "2026-09-27", name: "中秋", off: true),
        Holiday(day: "2026-10-01", name: "国庆", off: true),
        Holiday(day: "2026-10-02", name: "国庆", off: true),
        Holiday(day: "2026-10-03", name: "国庆", off: true),
        Holiday(day: "2026-10-04", name: "国庆", off: true),
        Holiday(day: "2026-10-05", name: "国庆", off: true),
        Holiday(day: "2026-10-06", name: "国庆", off: true),
        Holiday(day: "2026-10-07", name: "国庆", off: true),
        Holiday(day: "2026-10-10", name: "国庆节", off: false),
    ]
    /// 671 生效表 = 内置表 (按国务院公告逐日核对)。在线拉取已随波 2 移除。
    /// 本枚举不是 @MainActor，但这里只加**只读语义的缓存**：合并结果只由内置表派生，启动后不再变。
    /// 生效表不再随偏好变化 (无在线缓存), 所以不需要外部失效键。
    // 三个缓存 + 失效键是一组 (ensureMerged 一次写全, accessor 只读) —— 用一把原生锁护住整组。
    // 选 Locked (值活在临界区内) 而不是 unsafe: 它是 Swift 并发组里的标准互斥原语,
    // withLock 保证 unlock 一定执行; 内置表是常量, 合并只在首次访问时发生一次。
    private struct Merged: Sendable {
        var rows: [Holiday] = []
        var map: [String: String] = [:]
        var makeup: Set<String> = []
        var stamp = 0
    }
    private static let mergedLock = Locked(Merged())
    private static func ensureMerged() {
        mergedLock.withLock { m in
            guard m.stamp == 0 else { return }
            m.rows = builtinRows
            m.map = Dictionary(builtinRows.filter { $0.off }.map { ($0.day, $0.name) }, uniquingKeysWith: { a, _ in a })
            m.makeup = Set(builtinRows.filter { !$0.off }.map { $0.day })
            m.stamp = 1
        }
    }
    /// 671 节假日名 (组头标签); 补班日不在此列
    static func holidayName(_ dayKey: String) -> String? { ensureMerged(); return mergedLock.withLock { $0.map[dayKey] } }
    /// 671 调休补班日 (上班的日子, 不是假期) —— 色带与"假日顺延"都必须把它和放假日分开
    static func isMakeupWorkday(_ dayKey: String) -> Bool { ensureMerged(); return mergedLock.withLock { $0.makeup.contains(dayKey) } }
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
    /// 551 搜索面 = 一行「能被搜到的文字」, 全仓只有这一份定义。
    /// 搜索框占位文案承诺了「成员 / 凭证 / 备注」三段 (RecordsView 的 searchBar), 那三段就得真在串里:
    ///   · title —— 655 动词化的行标题 (行上显示的那句话, 含成员名与类型词)
    ///   · lockName —— 770 锁名
    ///   · whoName —— 可证明归属的成员名
    ///   · cred —— 568 凭证维度标签 (含 310 那条凭证别名)
    ///   · note —— 186 本机备注 (RecordOverlay, 用户自己写的字)
    /// 备注此前完全不在搜索面上, 而界面上写着它可搜 = 承诺了一个搜不到的热区 (第一百八十九批)。
    /// 备注要按 (锁, 行) 去查本机覆盖层, 只有拿着行的 UI 给得起这个数, 所以它是个参数而不是在这里自己读表。
    static func searchFace(title: String, lockName: String, whoName: String, cred: String, note: String) -> String {
        var s = title + " " + lockName + " " + whoName + " " + cred
        if !note.isEmpty { s += " " + note }
        return s
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
        // 554 时间短语; 558 配套修: 命中的时间词从 must 摘除, 否则去掉时间窗后它仍被当字面词对搜索面, 必然 0 条
        var timeHit: [String] = []
        for (phrase, range) in timePhrases(joined: joined) {
            timeHit.append(phrase)
            q.range = range
            q.parsedTags.append(rangeLabel(range))
        }
        q.must.removeAll { t in timeHit.contains { $0.contains(t) } }
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
    /// 554 中文时间短语表 (今天/昨天/昨晚/本周/上周/本月/上月/最近N天/N月D日)
    static func timePhrases(joined: String) -> [(String, (from: Date, to: Date)?)] {
        let now = Date()
        let cal = WeekCal.gregorian
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
            // 912: 周界走 WeekCal (只影响 firstWeekday / 最小周天数，日与月的边界不动)
            let curWeek = WeekCal.calendar.dateInterval(of: .weekOfYear, for: now)!
            out.append(("上周", (WeekCal.shifted(curWeek.start, days: -7), curWeek.start)))
        }
        if joined.contains("本周") {
            let curWeek = WeekCal.calendar.dateInterval(of: .weekOfYear, for: now)!
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
            let s = WeekCal.shifted(now, days: -n)
            out.append(("最近 \(n) 天", (cal.startOfDay(for: s), now)))
        }
        // "N月D日" (只认含"月"的那个词, 避免"工作日"里的"日"误命中; 当年, 已过则去年)
        if let tok = tokensFirstContaining(joined: joined, "月"),
           let mo = intBefore(tok, "月"), mo > 0, let dy = intBetween(tok, "月", "日"), dy > 0
           // 2026-10-13 对抗式点击审计: 原写只校下界 (mo>0 / dy>0) 不校上界 ⇒ 用户在搜索框敲
           // 「13月1日」「2月30日」「4月31日」时 `Calendar.date(from:)` 返回 nil, 下一行 `!` 直接 trap。
           // 记录页搜索框是 onChange 逐字符触发的 (RecordsView 的 onRecordsAppear/onChange 里 sel = 该值),
           // 所以**不用回车, 敲到"1""3"那两个字符就崩**。先把月/日夹到合法区间, 再用 guard 兜住
           // 任何 Calendar 仍然解不出的组合 (2月30日 这种夹不动的)。
           , mo <= 12, dy <= 31,
           let d = monthDayComps(cal: cal, now: now, month: mo, day: dy) {
            var dd = d
            if dd > now {
                var cc = DateComponents(); cc.year = cal.component(.year, from: now) - 1; cc.month = mo; cc.day = dy
                guard let d2 = cal.date(from: cc) else { return out }
                dd = d2
            }
            let label = String(tok)
            out.append((label, dayRange(dd)))
        }
        return out
    }
    private static func rangeLabel(_ r: (from: Date, to: Date)?) -> String {
        guard let r = r else { return "" }
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f.string(from: r.from) + " – " + f.string(from: r.to)
    }
    /// "当年 N月D日" → 一个合法 Date; 解不出 (2月30日 之类) 返 nil
    /// 2026-10-13 对抗式点击审计: 从 inline 的 `cal.date(from: c)!` 抽出来 —— 那两处强解包就是
    /// 搜索框敲「13月1日」即崩的根因。
    private static func monthDayComps(cal: Calendar, now: Date, month: Int, day: Int) -> Date? {
        var c = DateComponents()
        c.year = cal.component(.year, from: now)
        c.month = max(1, min(12, month))
        c.day = max(1, min(31, day))
        return cal.date(from: c)
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
    /// 2026-10-14: "N月D日" 里 a 与 b **之间**的纯数字。intBefore(tok,"日") 要求"日"前全是数字,
    /// 而 "3月15" 里有"月" ⇒ 恒 nil ⇒ 日期短语分支从未命中。这里按区间取。
    private static func intBetween(_ tok: String, _ a: String, _ b: String) -> Int? {
        guard let ra = tok.range(of: a),
              let rb = tok.range(of: b, range: ra.upperBound..<tok.endIndex),
              ra.upperBound <= rb.lowerBound else { return nil }
        let mid = tok[ra.upperBound..<rb.lowerBound]
        guard !mid.isEmpty, mid.allSatisfy({ $0.isNumber }) else { return nil }
        return Int(mid)
    }
    /// 含"月"的最短匹配词 (空格切词后找, 取首个)
    private static func tokensFirstContaining(joined: String, _ marker: String) -> String? {
        for tok in joined.components(separatedBy: " ") where tok.contains(marker) {
            return tok
        }
        return nil
    }




    // ---------- 726 处置留痕 (本地工单字段, 导出含处置历史) ----------
    /// 处置: key = mac#idxRaw → 结论 + 时刻; 745 测试标记存结论 "测试"
    struct Disposition: Codable {
        var at: Double        // 处置时刻 (Unix 秒)
        var verdict: String   // "已处理" / "误报" / "已处置" / "测试" / "已人工检查"
    }
    /// 745 测试标记的键集 (统计口径排除用, 键 = mac#idxRaw): 与处置留痕同一份 kf_rdispo,
    /// 不另造"测试"状态 —— 标记本身就是一条处置结论。此前这个查询零调用, 统计层并未真排除。
    /// 745 测试标记的键集 (统计口径排除用, 键 = mac#idxRaw): 直读 kf_rdispo，
    /// 不另造"测试"状态 —— 标记本身就是一条处置结论。处置写入口已随告警处置层移除，
    /// 这里读的是历史数据 (卸载前可能残留)。
    static var testMarkedKeys: Set<String> {
        let all = DB.store.get([String: Disposition].self, "kf_rdispo") ?? [:]
        return Set(all.filter { $0.value.verdict == "测试" }.map(\.key))
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
        // 2026-10-14: 取错极值。recs 是**倒序** (新在前) ——
        //   前事件 [t0-win, t0) 里"紧邻"的在前 ⇒ 应取 prefix (旧写法 suffix 取到窗内最旧 3 条);
        //   后事件 (t0, t0+win] 里"最早"的在尾 ⇒ 应取 suffix (旧写法 prefix 取到最新 3 条)。
        // 两支都反转为时间正序返回, 调用方用 `.before.last` 当"紧邻上一条"才成立。
        let before = recs.filter { r in
            guard let d = dateOf(r) else { return false }
            return r.id != mid.id && d.timeIntervalSince1970 >= t0 - win && d.timeIntervalSince1970 < t0
        }.prefix(n)
        let after = recs.filter { r in
            guard let d = dateOf(r) else { return false }
            return r.id != mid.id && d.timeIntervalSince1970 > t0 && d.timeIntervalSince1970 <= t0 + win
        }.suffix(n)
        return (Array(before).reversed(), Array(after).reversed())
    }



    /// 596 替代: 该日发生过防撬 (7) / 试错锁定 (10) / 键盘锁定 (224) 的日键集合。
    /// 与 `unhandledAlarmDays` 同一份 IO 形状 (各锁缓存日志) 但**不看处置** ——
    /// "这一天出过事"与"还没人看过"是两件事, 处置过的也照留; 日的归属沿用 649 (dayKeyOfNight)。
    static func damageDays(macs: [String]) -> Set<String> {
        var days = Set<String>()
        for mac in macs {
            for l in DB.readLogs(mac) where AlarmMeta.damageTypes.contains(l.type) {
                guard let d = dateOf(l) else { continue }
                days.insert(dayKeyOfNight(d))
            }
        }
        return days
    }

    /// 765 跨锁合并"最近开门": 各锁日志按时间并成一条流 (行尾的锁名标签由 UI 用 Rec.lockName 打)。
    /// 为什么按 `timeStr` 而不是 `lockTime` 数值排: 与 658 同一口径 —— 那串是本页显示的权威时间,
    ///   epoch 还带秒/毫秒口径差, 按它排完再显示另一套就成了自相矛盾。空时间串自然沉底,
    ///   不会伪装成"最近一条"。
    /// 为什么加 offset 当 tiebreak: 日志只到分钟, 同一分钟内的两行 (尤其跨锁) 先后是**入库次序**
    ///   而不是时间信息 (与 680 同一坦白)。Swift 的 sorted(by:) 不保证稳定, 不写这一条,
    ///   同样的数据两次进页可能给出相反的顺序。
    static func mergedRecentOpens(macs: [String], count: Int) -> [Rec] {
        let rows = buildRecs(macs: macs, includeFails: false, includeCare: false)
            .filter { StatsKit.openTypes.contains($0.type) }
        let sorted = rows.enumerated().sorted { a, b in
            if a.element.timeStr != b.element.timeStr { return a.element.timeStr > b.element.timeStr }
            return a.offset < b.offset
        }
        return sorted.prefix(max(0, count)).map { $0.element }
    }
}


extension RecordSearch {
    /// 724 四级色标 → DS 令牌映射 (紧急 danger / 严重 danger 降饱和 / 提示 warn)
    /// 原住 AlarmCenterView (已删), 但 RecordsTimeline 的记录行仍用它上色。
    static func toneColor(for type: Int) -> Color {
        switch AlarmMeta.level(type) {
        case 3: return DS.Palette.danger
        case 2: return DS.Palette.danger.opacity(0.72)
        case 1: return type == 6 ? DS.Palette.warn : DS.Palette.textSub
        default: return DS.Palette.textSub
        }
    }
}