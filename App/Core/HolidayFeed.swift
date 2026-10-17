// 671 在线假日表接入 —— 2026-10-09 拍板 #22：内置表兜底 + 选源 + 手动拉 + 可开关自动。
// 数据形状来自 holiday-cn (MIT, 自动抓国务院公告)：{year, papers[], days[{name,date,isOffDay}]}。
// `isOffDay=false` 那几条就是**调休补班日** —— 这是这套数据最有价值的部分 (672 顺延与 594 色带都必须把它和假期分开)，
// 所以任何"只看 isOffDay 为真"的简化解析都是丢信息。
//
// 三条硬规矩，都是"离线工具偶尔要联网"这件事的边界：
//   1. 只走 https，且**整份校验通过才替换缓存**；任何一步失败保留上一次的好数据并如实报错 —— 绝不把表清空或半新半旧；
//   2. 回来的 `year` 必须等于请求的年份 —— 防重定向/CDN 把另一年的文件递过来；
//   3. 自动档默认关：这是离线锁管家，静默对外发请求要用户明确开一次。
import Foundation

struct HolidayDayDTO: Codable { var name: String; var date: String; var isOffDay: Bool }
struct HolidayYearDTO: Codable { var year: Int; var papers: [String]?; var days: [HolidayDayDTO] }

// 2026-10-13 run 60: 原先这里挂 @MainActor, 于是 HolidayFeed.rows / lastUpdateSec 都被主 actor 隔离,
// 而 RecordSearch.Holiday.ensureMerged() (非隔离) 读它们 ⇒
//   "main actor-isolated static property 'rows' can not be referenced from a nonisolated context"。
// 去掉 @MainActor 是**顺其自然**的: 本枚举只用 DB.store (Store 是普通 final class, 非隔离) 与 URLSession,
// 没有一处需要主 actor; 而 RecordSearch 那段注释早就写着"本枚举不是 @MainActor ... 所有调用方都在主线程"。
// 隔离层本来就该在调用方 (View), 不在数据源这一层。
enum HolidayFeed {
    /// 内置源：raw.githubusercontent.com 上按年份发布的 JSON (取自该仓库 README 里写明的发布路径, 不是猜的域名)
    static let builtinBase = "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/"
    static let srcKey = "kf_hol_src"
    static let autoKey = "kf_hol_auto"
    static let atKey = "kf_hol_at"          // 最近一次成功收录的 epoch 秒; 同时充当合并结果的失效标记
    static let maxBytes = 256 * 1024
    static func cacheKey(_ y: Int) -> String { "kf_hol_" + String(y) }

    static var sourceBase: String { let s = DB.store.getString(srcKey); return s.isEmpty ? builtinBase : s }
    static var usingBuiltinSource: Bool { sourceBase == builtinBase }
    static func setSource(_ s: String) {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t == builtinBase { DB.store.remove(srcKey) } else { DB.store.set(srcKey, t) }
    }
    static var autoOn: Bool { DB.store.getBool(autoKey) }
    static func setAuto(_ on: Bool) { DB.store.set(autoKey, on) }
    static var lastUpdateSec: Int { DB.store.getInt(atKey) }
    static var lastUpdateText: String {
        let s = lastUpdateSec
        guard s > 0 else { return "从未联网更新 (只用内置表)" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f.string(from: Date(timeIntervalSince1970: Double(s)))
    }

    static func cached(_ y: Int) -> [HolidayDayDTO]? { DB.store.get([HolidayDayDTO].self, cacheKey(y)) }

    /// 校验后才落缓存。返回 nil = 接受, 返回字符串 = 拒绝原因 (调用方原样给用户看)。
    @discardableResult
    static func accept(_ p: HolidayYearDTO, wantYear: Int) -> String? {
        guard p.year == wantYear else { return "文件年份 \(p.year) 与请求的 \(wantYear) 不一致 — 拒绝" }
        guard p.days.count >= 1, p.days.count <= 200 else { return "条目数异常 (\(p.days.count)) — 拒绝" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        for d in p.days {
            guard d.date.count == 10, f.date(from: d.date) != nil else { return "日期格式异常 (\(d.date)) — 拒绝" }
            guard !d.name.isEmpty, d.name.count <= 40 else { return "节日名异常 — 拒绝" }
        }
        DB.store.setCodable(cacheKey(p.year), p.days)
        DB.store.set(atKey, Int(Date().timeIntervalSince1970))   // 这一步同时让合并结果失效重算
        return nil
    }

    /// 拉取结果: 失败载荷是**一句人话**, 但它必须是个 Error —— `Result` 的 Failure 要求 Error,
    /// 直接写 `Result<String, String>` 编译报 "type 'String' does not conform to protocol 'Error'"。
    struct FeedError: Error, CustomStringConvertible {
        let message: String
        init(_ m: String) { message = m }
        var description: String { message }
    }

    static func fetch(year: Int) async -> Result<String, FeedError> {
        let url = sourceBase + String(year) + ".json"
        guard url.hasPrefix("https://"), url.count <= 300, url.range(of: #"^\S+$"#, options: .regularExpression) != nil,
              let u = URL(string: url) else {
            return .failure(FeedError("源地址不合法 (只允许 https、无空格的完整前缀)"))
        }
        var req = URLRequest(url: u, timeoutInterval: 12)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let h = resp as? HTTPURLResponse, h.statusCode == 200 else {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                return .failure(FeedError("HTTP \(code) — 保留上次数据"))
            }
            guard data.count <= maxBytes else { return .failure(FeedError("响应超过 256KB — 拒绝解析")) }
            let p = try JSONDecoder().decode(HolidayYearDTO.self, from: data)
            if let why = accept(p, wantYear: year) { return .failure(FeedError(why + " — 保留上次数据")) }
            let off = p.days.filter { $0.isOffDay }.count
            return .success("已收录 \(year)：放假 \(off) 天 · 补班 \(p.days.count - off) 天")
        } catch is DecodingError {
            return .failure(FeedError("JSON 结构与约定不符 — 保留上次数据"))
        } catch let e as URLError {
            return .failure(FeedError("网络不可达 (\(e.code.rawValue)) — 保留上次数据"))
        } catch {
            return .failure(FeedError("拉取失败 — 保留上次数据"))
        }
    }

    /// 清除在线缓存, 回到只信内置表 (公告改期或源不可信时用)。
    static func clearCache() {
        for y in 2020...2040 { DB.store.remove(cacheKey(y)) }
        DB.store.remove(atKey)
    }

    // ---------- 合并视图 ----------
    // 缓存**按年整体覆盖**内置表：同一年里不混两副表, 否则公告临时改期会出现"春节前一天还在内置表里"的错位。
    private static var mergedCache: [RecordSearch.Holiday] = []
    private static var mergedStamp = -2
    static var rows: [RecordSearch.Holiday] {
        let stamp = lastUpdateSec
        if stamp != mergedStamp {
            mergedCache = buildRows()
            mergedStamp = stamp
        }
        return mergedCache
    }
    private static func buildRows() -> [RecordSearch.Holiday] {
        var cachedYears: [Int] = []
        for y in 2020...2040 where cached(y) != nil { cachedYears.append(y) }
        let cs = Set(cachedYears)
        var out = RecordSearch.builtinRows.filter { h in
            guard let n = Int(h.day.prefix(4)) else { return true }
            return !cs.contains(n)
        }
        for y in cachedYears.sorted() {
            for d in cached(y) ?? [] {
                out.append(RecordSearch.Holiday(day: d.date, name: d.name, off: d.isOffDay))
            }
        }
        return out
    }
    /// 界面上的来源说明: 哪几年是在线缓存、最近一次什么时候拉的。
    static var coverageText: String {
        let ys = (2020...2040).filter { cached($0) != nil }
        if ys.isEmpty { return "当前只用内置表 (按公告核对至 \(RecordSearch.builtinHolidayYearMax) 年)" }
        return "在线缓存覆盖 " + ys.map(String.init).joined(separator: "/") + " 年 · 拉取于 " + lastUpdateText
    }
    /// 自动档：本会话只发一次, 且只在用户明确开过开关后发 (RootView 的前台钩子调)。
    private static var autoDoneYear = 0
    static func autoRefreshIfNeeded() async {
        guard autoOn else { return }
        let y = WeekCal.gregorian.component(.year, from: Date())
        guard y != autoDoneYear else { return }
        autoDoneYear = y
        _ = await fetch(year: y)
    }
}
