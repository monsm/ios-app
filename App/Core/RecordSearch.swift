// 包9 记录检索与告警核心 (纯本地, 只读既有台账)
//   检索: 551 全局搜索 / 554 自然语言 / 555 加减号 / 562 实时计数 / 553 历史 /
//         560 命名过滤视图 / 564 时段 / 571 工作日周末 / 572 深夜预设 / 574 活跃凭证 /
//         575 越界开门 / 569 失败事件 (仅 10/13/224 告警级, 锁端无逐次失败明细) /
//         594·671·672 节假日 (内置表按国务院公告核对 · 含调休补班日 · 在线源见 NEXT-DECISIONS 组3) / 737 今日试错
//   告警: 723 跨锁流 / 724 四级色标 / 726 处置留痕 / 734 未处理优先 / 741 同类计数 /
//         745 测试标记排除 / 727 检查清单 (复用处置字段) / 742 响应时长 (占位"积累中")
//   551 的搜索面在 `searchFace` 一处定义, 含 186 备注与 568 凭证标签 (第一百八十九批补齐:
//   此前备注不在任何搜索面上, 而搜索框占位文案写着它可搜)。
// 纪律: 颜色只走 DS 令牌 (danger 派生, 页面层 .opacity); 告警类型只用锁端日志表的
//       2 种 (4 静态电量 / 10 多次密码开门失败锁定);
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
    /// 2026-10-30（第 66 轮）：整表写入 —— 只供备份恢复用（逐条 setNote 会把整表解码 N 遍）。
    /// 与 setNote 同一口径：空文本删键、超长截到 60 字（不让坏备份写进一个比行下灰字更长的值）。
    static func setNotes(_ mac: String, _ table: [String: String]) {
        var m = [String: String]()
        for (k, v) in table {
            let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { m[k] = String(t.prefix(60)) }
        }
        DB.store.setCodable(noteKey(mac), m)
    }
    /// 2026-10-30：多锁旗标合并（时间线逐行渲染时一次取，别逐行解整份表）。
    static func allFlags(macs: [String]) -> Set<String> {
        var out = Set<String>()
        for m in macs where !m.isEmpty { out.formUnion(flags(m)) }
        return out
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
    /// 2026-10-30（第 66 轮）：整表写入 —— 只供备份恢复用。
    static func setFlags(_ mac: String, _ set: Set<String>) {
        DB.store.setCodable(flagKey(mac), set.sorted())
    }
    // ---------- 2026-10-28 补：处置层 ----------
    // 详情页的「标记已处置 / 撤销」此前是**假按钮** —— `disp` 硬编码 nil、点击只 `tick += 1`，
    // 界面闪一下又回到「未处置」。处置记录是告警排查的核心（谁在什么时候确认过这条），
    // 所以按与备注/旗标同一套本机覆盖层补上，不新建第二套存储。
    static func dispKey(_ mac: String) -> String { "kf_rdisp_" + mac }
    static func dispositions(_ mac: String) -> [String: RecordSearch.Disposition] {
        DB.store.get([String: RecordSearch.Disposition].self, dispKey(mac)) ?? [:]
    }
    static func disposition(_ mac: String, _ rowKey: String) -> RecordSearch.Disposition? {
        dispositions(mac)[oid(mac: mac, rowKey: rowKey)]
    }
    static func setDisposition(_ mac: String, _ rowKey: String, _ d: RecordSearch.Disposition?) {
        var m = dispositions(mac)
        let k = oid(mac: mac, rowKey: rowKey)
        if let d { m[k] = d } else { m.removeValue(forKey: k) }
        DB.store.setCodable(dispKey(mac), m)
    }
    /// 2026-10-30（第 66 轮）：整表写入 —— 只供备份恢复用（备份包里存的是 verdict 字符串）。
    static func setDispositions(_ mac: String, _ table: [String: String]) {
        var m = [String: RecordSearch.Disposition]()
        for (k, verdict) in table {
            m[k] = RecordSearch.Disposition(at: 0, verdict: verdict)
        }
        DB.store.setCodable(dispKey(mac), m)
    }
    /// 行下灰字与左旗的读取都由上面几枚函数直接服务 UI; 不再另留 noteLine 这种"看着像入口"的别名。
}


/// 724 四级告警色标: 提示/注意/严重/紧急 — 锁端日志表里 2 种告警类的本地定级
/// (协议无胁迫类, 不虚构; 定级与色标映射在 AlarmCenterView 的 RecordSearch 扩展, 形状冗余保色觉可读)
enum AlarmMeta {
    static let urgent: Set<Int> = [10]   // 2026-10-29 修正：日志表里只有「多次密码失败锁定」是紧急级
    static let serious: Set<Int> = [4]   // 2026-10-29 修正：13 在日志表里是「交换秘钥」，不是指纹告警
    /// 596 替代: 原句要的是"含胁迫告警"的日警示 —— 协议日志表里没有胁迫类 (§5),
    /// 能挂的只有「多次密码开门失败锁定」(10)：有人反复试密码，这一天确实"出过事"。
    static let damageTypes: Set<Int> = [10]   // 2026-10-29 修正：日志表里只有 10
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
// 【保留未接 2026-10-29】通勤时段标签（工作日 7-9 / 17-19 实时计算）—— 记录页时段分组用
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
// 【保留未接 2026-10-29】自然时段词（清晨/上午/午间…）—— 记录组头与行级小字用
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
    static let openVerb: [Int: String] = [11: "用了数字钥匙开了门", 16: "用了一次性密码开门", 17: "用了密码开门", 19: "用指纹开了门"]
    static let alarmVerb: [Int: String] = [4: "触发低电量提醒", 10: "多次密码开门失败已锁定"]
    static let opVerb: [Int: String] = [
        8: "重新上电", 9: "DFU 后更新版本", 12: "校时完成", 13: "交换秘钥",
        14: "同步 PIN", 15: "同步密码", 20: "录入了指纹", 21: "删除了指纹",
        22: "调整了安全级别", 23: "切换了状态广播", 24: "设置了单双验",
        25: "开通了临时密码", 26: "调整了音量", 27: "设置了 beacom 密钥",
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

    enum CodingKeys: String, CodingKey {
        case segment, dayKind, lateNight, alarmOnly, kind, member, failedOnly, alarmKinds
    }

    /// 全默认构造（调用点只写 QueryFilters()）。
    init(segment: Int = 0, dayKind: Int = 0, lateNight: Bool = false, alarmOnly: Bool = false,
         kind: String = "", member: String = "", failedOnly: Bool = false, alarmKinds: Set<Int> = []) {
        self.segment = segment; self.dayKind = dayKind; self.lateNight = lateNight
        self.alarmOnly = alarmOnly; self.kind = kind; self.member = member
        self.failedOnly = failedOnly; self.alarmKinds = alarmKinds
    }

    /// 容错解码（2026-10-29）：过滤条件是「按锁存一份」的持久化状态，
    /// 加字段后老数据解不出会静默回到「全部」，用户会以为自己设的筛选丢了。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        segment = try c.decodeIfPresent(Int.self, forKey: .segment) ?? 0
        dayKind = try c.decodeIfPresent(Int.self, forKey: .dayKind) ?? 0
        lateNight = try c.decodeIfPresent(Bool.self, forKey: .lateNight) ?? false
        alarmOnly = try c.decodeIfPresent(Bool.self, forKey: .alarmOnly) ?? false
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        member = try c.decodeIfPresent(String.self, forKey: .member) ?? ""
        failedOnly = try c.decodeIfPresent(Bool.self, forKey: .failedOnly) ?? false
        alarmKinds = try c.decodeIfPresent(Set<Int>.self, forKey: .alarmKinds) ?? []
    }
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

    /// 568 凭证维度标签: 可证明归属才给人名，否则给类型 (推断值前端标"约")。
    /// 310 别名：台账里那条凭证自己的备注 (`LedgerPwd.note` / `LedgerFp.note`，添加页那行
    /// "给谁·哪扇门·用多久") 的首段。刻意**不新增第二个别名字段** —— 备注已经是别名，
    /// 再造一个就会出现"两处各写一半、显示时不知道取哪个"。
    /// 只取首段并截 12 字：整条 note 常在 20 字以上，行里放不下；截断的别名不如不显示。
    /// 匹配用 `e.idx` = 锁端日志里的凭证槽号，与台账 `alias`/`batch` 同一个数 (协议确证，非推断)。
    static func credLabel(kind: String?, who: String?, pws: [LedgerPwd], fps: [LedgerFp], e: LogEntry) -> String {
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

    /// 569 越界开门 (575): 临时码时间窗 (台账 from/to) 之外仍产生开门 — 本地检测, 标"约"
    struct OutWin {
        var rec: Rec
        var window: String     // "约 10-01 08:00 – 10-02 08:00"
    }
    static func parseStamp(_ s: String) -> Int64 {
        // 与 Attribution.ms 同语义 (JS 生态把本地串按 UTC 读)。
        // 2026-10-29 性能：改用共享的 UTC 变体 —— **不能**对缓存实例改 timeZone，那会污染所有其它使用者。
        return Int64(DF.stampUTC.date(from: s)?.timeIntervalSince1970 ?? 0)
    }


    /// 737 今日试错判据 (唯一一份): 锁定类事件行 (type 10) 且落在今日 —— 计数与逐次明细共用
    static func trialRowsToday(mac: String) -> [CachedLog] {
        let today = dayKeyOf(Date())
        return DB.readLogs(mac).filter { $0.type == 10 && String($0.lockTimeStr.prefix(10)) == today }
    }
    /// 737 今日试错 (⚠ keyboardErrCount 语义不确定, 只用日志条数, 标题带"?"由 UI 层标)
    static func trialCountToday(macs: [String]) -> Int {
        macs.reduce(0) { $0 + trialRowsToday(mac: $1).count }
    }

    static func dateOf(_ r: Rec) -> Date? {
        if !r.timeStr.isEmpty {
            let f = DF.stamp
            return f.date(from: r.timeStr)
        }
        return nil
    }
    /// 676 夜间时段配置 (默认 22-6): 572 深夜预设 / 564 深夜段共用。
    /// 写入一律夹到 0...23 —— 键位是 UserDefaults, 手改或导入可能塞进越界值, 判定函数不再做"回落合法值"的静默纠错。
    static var nightFrom: Int { clamp23(DB.store.getInt("kf_night_from", 22)) }
    static var nightTo: Int { clamp23(DB.store.getInt("kf_night_to", 6)) }
    static func setNightFrom(_ h: Int) { DB.store.set("kf_night_from", clamp23(h)) }
    static func setNightTo(_ h: Int) { DB.store.set("kf_night_to", clamp23(h)) }
    static func setHolidayExtend(_ on: Bool) { DB.store.set("kf_holiday_extend", on) }
    static func clamp23(_ h: Int) -> Int { min(max(h, 0), 23) }
    /// 起==止 时区间为空集 (什么都筛不出), 界面要如实提示而不是让用户对着空列表猜
    static var nightWindowDegenerate: Bool { nightFrom == nightTo }

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
    struct Merged: Sendable {
        var rows: [Holiday] = []
        var map: [String: String] = [:]
        var makeup: Set<String> = []
        var stamp = 0
    }
    static let mergedLock = Locked(Merged())
    static func ensureMerged() {
        mergedLock.withLock { m in
            guard m.stamp == 0 else { return }
            m.rows = builtinRows
            m.map = Dictionary(builtinRows.filter { $0.off }.map { ($0.day, $0.name) }, uniquingKeysWith: { a, _ in a })
            m.makeup = Set(builtinRows.filter { !$0.off }.map { $0.day })
            m.stamp = 1
        }
    }
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
    /// "当年 N月D日" → 一个合法 Date; 解不出 (2月30日 之类) 返 nil
    /// 2026-10-13 对抗式点击审计: 从 inline 的 `cal.date(from: c)!` 抽出来 —— 那两处强解包就是
    /// 搜索框敲「13月1日」即崩的根因。
    static func monthDayComps(cal: Calendar, now: Date, month: Int, day: Int) -> Date? {
        var c = DateComponents()
        c.year = cal.component(.year, from: now)
        c.month = max(1, min(12, month))
        c.day = max(1, min(31, day))
        return cal.date(from: c)
    }
    /// "最近(\d+)" 取括号内数字
    static func intAfter(_ s: String, _ head: String) -> Int? {
        guard let i = s.range(of: head) else { return nil }
        let tail = s[i.upperBound...]
        var digits = ""
        for ch in tail {
            if ch.isNumber { digits.append(ch) } else { break }
        }
        return Int(digits)
    }
    /// 取 "月" 前的数字 (同一词内)
    static func intBefore(_ tok: String, _ tail: String) -> Int? {
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
    static func intBetween(_ tok: String, _ a: String, _ b: String) -> Int? {
        guard let ra = tok.range(of: a),
              let rb = tok.range(of: b, range: ra.upperBound..<tok.endIndex),
              ra.upperBound <= rb.lowerBound else { return nil }
        let mid = tok[ra.upperBound..<rb.lowerBound]
        guard !mid.isEmpty, mid.allSatisfy({ $0.isNumber }) else { return nil }
        return Int(mid)
    }
    /// 含"月"的最短匹配词 (空格切词后找, 取首个)
    static func tokensFirstContaining(joined: String, _ marker: String) -> String? {
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

    enum CodingKeys: String, CodingKey { case at, verdict }
    init(at: Double, verdict: String) { self.at = at; self.verdict = verdict }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        at = try c.decodeIfPresent(Double.self, forKey: .at) ?? 0
        verdict = try c.decodeIfPresent(String.self, forKey: .verdict) ?? ""
    }
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





}


extension RecordSearch {
    /// 724 四级色标 → DS 令牌映射 (紧急 danger / 严重 danger 降饱和 / 提示 warn)
    /// 原住 AlarmCenterView (已删), 但 RecordsTimeline 的记录行仍用它上色。
    static func toneColor(for type: Int) -> Color {
        switch AlarmMeta.level(type) {
        case 3: return DS.Palette.danger
        case 2: return DS.Palette.danger.opacity(0.72)
        // 2026-10-29：type 6 在 APK We 表里不存在（旧枚举的"电量低"）；告警 4/10 已由 level 2/3 接走。
        case 1: return DS.Palette.textSub
        default: return DS.Palette.textSub
        }
    }
}
