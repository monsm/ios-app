// 包12 导出·打印·分享 — 全离线, 数据只出本机一次且每次明示 (718)
// 收录 478/548/683-710/712/714-722 (703 系统邮件直发, 无邮箱账号时回退 .eml 文本;
// 710 = 报告校验二维码 + 扫码核对, 实现见 ReportVerify 一节与 ReportVerifyView.swift)
// 未做: 711/713 (iPad 拖出 / 安全作用域书签, 见 DEFERRED.md 包12 节);
// 不提供: 203 (可读 JSON 与 684 重复, 已舍弃)。这几条以前和"收录"写在同一行,
// 于是台账把没做的也当实现证据记了一笔。
// 纪律: 颜色只经 DS 令牌; 导出文件 UTF-8+BOM (中文 Excel 友好); 打印走 UIPrintInteractionController;
//       校验行 SHA-256 复用 CryptoKit (722); 归属只走 Attribution 可证明链, 推不出留空 (CAPABILITY §3)。
import SwiftUI
import UIKit
import CryptoKit
import UniformTypeIdentifiers
import PDFKit
import QuickLook
import LinkPresentation
import MessageUI

// ================= 导出范围 (701 打印范围: 全月/仅告警/仅指定成员) =================
enum ExportRange: Hashable {
    case all
    case month
    case day
    case alarms
    case member(String)

    var label: String {
        switch self {
        case .all: return "全部"
        case .month: return "当月"
        case .day: return "最新单日"
        case .alarms: return "仅告警"
        // 689: 关联值存的是成员 id (tag 必须是稳定 id), 但 label 会进文件名与标题
        // (`:1529 title:` / `:1530 fileName:`), 直接拼 id 就导出成 "仅_<成员id>.csv"。
        // 过滤那侧 (`filtered` 的 `.member`) 一直是先 id→name 再比, 这里与它同一个口径。
        case .member(let id): return "仅 " + (DB.member(id)?.name ?? id)
        }
    }
}

// 690 列选择: 上次选择沿用到 kf_cred_export_cols (690 原意)
struct ExportCols {
    var time = true, type = true, member = true, alarm = true, cred = false, hex = false
    static let savedKey = "kf_cred_export_cols"
    /// 六个字段是唯一真相，`all` 必须现算。原来写成 `var all = [time, ...]` 是**存储属性**：
    /// 它在 init 时就固化成默认值，而 set() 只改字段、get()/onIndices/save() 全读 all
    /// ⇒ 勾选既不改导出列，也不落盘（持久化恒写 111100），而页脚写着「上次选择会沿用」。
    var all: [Bool] { [time, type, member, alarm, cred, hex] }
    func get(_ i: Int) -> Bool { all[i] }
    mutating func set(_ i: Int, _ on: Bool) {
        switch i { case 0: time = on; case 1: type = on; case 2: member = on; case 3: alarm = on; case 4: cred = on; default: hex = on }
    }
    var onIndices: [Int] { (0..<6).filter { all[$0] } }
    static func load() -> ExportCols {
        // Store.getString 返回**非可选** String (无键时为空串): 旧写法 guard let 绑定非可选值, 编译不过
        let s = DB.store.getString(savedKey)
        guard !s.isEmpty else { return .init() }
        var c = ExportCols()
        for i in 0..<6 where i < s.count { c.set(i, s[s.index(s.startIndex, offsetBy: i)] == "1") }
        return c
    }
    static func save(_ c: ExportCols) { DB.store.set(savedKey, c.all.map { $0 ? "1" : "0" }.joined()) }
}

// 705 CSV 转义 (RFC 4180) + 公式注入中和
enum CSVKit {
    /// 以 = + - @ 或制表符开头的字段会被 Excel / Numbers 当公式执行。成员名、凭证别名、备注均用户可控
    /// (还可能来自导入的不可信备份) → 前置单引号强制文本, 同时保留 RFC 4180 的引号转义。
    private static func formulaRisk(_ f: String) -> Bool {
        guard let first = f.first else { return false }
        return first == "=" || first == "+" || first == "-" || first == "@" || first == "\t"
    }
    static func escape(_ f: String) -> String {
        let body = formulaRisk(f) ? "'" + f : f
        if body.contains("\"") || body.contains(",") || body.contains("\n") || body.contains("\r") {
            return "\"" + body.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return body
    }
    /// 705 预检: 导出前扫描哪些字段会触发转义 (预览前 3 行防 Excel 错列)
    static func needEscaping(_ f: String) -> Bool {
        formulaRisk(f) || f.contains("\"") || f.contains(",") || f.contains("\n") || f.contains("\r")
    }
}

// 721 双语列头: 中文主列头 + 英文 code 注释行 (便于脚本二次处理)
enum ExportHeaders {
    static let zh = ["时间", "类型", "成员", "告警", "凭证", "原始hex"]
    static let en = ["time", "type", "member", "alarm", "cred", "hex"]
}

// 707 报告语言: 项目仅中文。**kf_report_lang 目前没有任何写入方** (界面上没有语言开关),
// lang 恒为 zh-Hans —— 这是给繁体预留的键位, 不是"设置可写"的能力。加译时先补设置项再动 table。
enum ReportTexts {
    static var lang: String {
        switch DB.store.getString("kf_report_lang") {
        case "zh-Hant": return "zh-Hant"
        default: return "zh-Hans"
        }
    }
    static func t(_ key: String) -> String {
        // 新增语言只需给 table 加列; 缺列回落简体中文
        let table: [String: [String: String]] = [
            "footer": ["zh-Hans": "离线锁管家导出"],
            "integrity": ["zh-Hans": "完整性核对"],
            "alarmSection": ["zh-Hans": "告警明细 (置前章节)"],
            "detailSection": ["zh-Hans": "逐日明细"],
            "dispoSection": ["zh-Hans": "处置历史 (本机留痕)"],
            "summarySection": ["zh-Hans": "三句摘要"],
        ]
        return table[key]?[lang] ?? table[key]?["zh-Hans"] ?? key
    }
}

// ================= 导出行模型 (归属只走 Attribution 可证明链) =================
struct ExportRecord {
    var time: String      // yyyy-MM-dd HH:mm:ss, 无时间戳为 ""
    var typeName: String
    var member: String    // "" = 无法证明归属
    var credWord: String  // 指纹/密码/一次性密码/数字钥匙; 非开门事件为 ""
    var isAlarm: Bool
    var hex: String       // 缓存层存了协议帧则原样带出, 否则 ""
    var dayKey: String    // yyyy-MM-dd, 未知为 "未知"
    var key: String = ""  // 锁端行键 (idxRaw) — mac#key 即 726 留痕键; 无 idx 的行留空
    var levelName: String = ""  // 724 告警级别字样 (AlarmMeta.levelName); 非告警留空
}

// ================= 导出条目 (708 ShareLink / 709 LPLinkMetadata 卡片) =================
struct ExportItem: Identifiable {
    let id = UUID().uuidString
    var kind: String          // csv/json/txt/pdf/png/eml
    var title: String
    var fileName: String      // 693 命名规范: 锁管家_记录_范围.csv
    var bytes: Data
    var sha256: String
    var shaLabel: String
    var previewText: String = ""   // 705 预检预览 / 714 复制
    var images: [UIImage] = []     // 706 长图分页 (最多 3 张)
    var scopeNote: String = ""     // 718 分享范围明示文案

    static let bom = "\u{EF}\u{BB}\u{BF}"   // UTF-8 BOM (中文 Excel 友好)

    /// 714 复制为完整文本 (正文 + 722 校验行)
    /// 2026-10-15 走查: 正文原先取的是 `previewText` —— 那是给屏幕看的截断预览 (CSV 前 3 行、
    /// PDF 前 500 字, 个别生产者干脆放的是一句说明), 于是复制进剪贴板的**从来不是**全文,
    /// 而按钮旁边那句 toast 一直写着"已复制完整文本"。正文只认真字节; 图与压缩包这类没有文本
    /// 正文的产物 (UTF-8 解出替换符) 退回 previewText, 由 toast 如实说清复制的是什么。
    var decodedBody: String? {
        guard !bytes.isEmpty else { return nil }
        let s = String(decoding: bytes, as: UTF8.self)
        return s.contains("\u{FFFD}") ? nil : s
    }
    var fullText: String {
        (decodedBody ?? previewText)
            + "\n── 校验 ──\nSHA-256: \(sha256)\n\(shaLabel)\n生成: " + ExportKit.stamp.string(from: Date())
    }

    /// 719/712 写盘: **优先**写用户用书签固定的导出目录 (713), 没设过回落 Caches/exports (老行为不变)。
    @discardableResult
    func writeLocal() -> URL? {
        let t = ExportDir.target()
        defer { if t.scoped { t.url.stopAccessingSecurityScopedResource() } }
        let dir = t.url
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(fileName)
        // 2026-10-14: 原子写 —— 写书签目录/大文件时进程被杀或低存储会留截断件, 而调用方只判非 nil 即回执"已生成"。
        guard (try? bytes.write(to: url, options: .atomic)) != nil else { return nil }
        // 2026-10-15 走查: 与 XXXVII 那处分享同一件事落在写盘这一侧 —— 长图切出的第 2、3 张原先只有分享拿得到,
        // 「写入本地文件」仍只落第 1 张: 页面上写着"共 3 张"而文件夹里只躺一份, 又是报的数与给的东西不符。
        // 逐张原子写, 命名与分享那侧同一套 (-序号of张数); 任何一张失败就整体返回 nil, 调用方就此报「没落盘」,
        // 不会报成「全部都已生成」。**不回删已写成的那几张**: 原子写已经把同名旧件覆盖掉了, 再删等于让用户一份不剩。
        if images.count > 1 {
            for (i, img) in images.enumerated() where i > 0 {
                let nm = fileName.replacingOccurrences(of: ".jpg",
                                                       with: "-" + String(i + 1) + "of" + String(images.count) + ".jpg")
                guard let d = img.jpegData(compressionQuality: 0.8),
                      (try? d.write(to: dir.appendingPathComponent(nm), options: .atomic)) != nil else { return nil }
            }
        }
        return url
    }

    // 708: 共享表示 = 下方各 Transferable struct (csv/json/pdf/图片/文本)
    // 注: 本扩展里另有一个 `linkMetadata()` (709)，**目前没有调用点** —— 见下面 709 那段说明。
}

/// 713 固定导出目录: 用**安全作用域书签**记住用户选的文件夹 (fileImporter 选一次, 之后每次导出都落那里),
/// 免得导出件躺在 App 缓存目录里被系统清掉、也免得每次都要重新选。
/// 没设过 / 书签失效 → 一律回落老路径 (Caches/exports), 不改变既有行为。
enum ExportDir {
    private static let key = "kf_export_dir_bm"
    static var name: String {
        guard let u = resolve(startScope: false) else { return "" }
        return u.lastPathComponent
    }
    static func set(_ url: URL) {
        // 生成书签时这一份 URL 必须处于"可访问"状态 (fileImporter 给的是临时可访问 URL)
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        if let bm = try? url.bookmarkData() { DB.store.setCodable(key, bm) }
    }
    static func clear() { DB.store.remove(key) }
    /// 解析书签; startScope=true 时已开启安全作用域 (调用方用完必须 stop)
    static func resolve(startScope: Bool) -> URL? {
        guard let bm = DB.store.get(Data.self, key) else { return nil }
        var stale = false
        guard let u = try? URL(resolvingBookmarkData: bm, bookmarkDataIsStale: &stale) else { return nil }
        if startScope, !u.startAccessingSecurityScopedResource() { return nil }
        return u
    }
    /// 导出落点: (目录, 是否已开安全作用域需 stop)
    static func target() -> (url: URL, scoped: Bool) {
        if let u = resolve(startScope: true) { return (u, true) }
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (dir, false)
    }
}

// 708 原生分享: 按 kind 走系统 UTType 的 Transferable 表示 (csv/json/pdf/图片/文本)。
// 709 聊天内预览: 现役口径是 ShareLink 的 `sharePreview` 渐变封面图。
// `ExportItem.linkMetadata()` (709) 是**留着不开的备用口**: SwiftUI 没有公开挂接 LPLinkMetadata 的位置，
// 只有自建 UIActivityViewController 那条路才用得上 —— 与 LinkSenseKit 的 stop* 两个口同类,
// 由 deadscan 报成零引用是预期内的，判定=留着并写清为什么 (第九十一批把这段说明补到声明旁)。
struct ExportCSVFile: Transferable {
    let item: ExportItem
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: UTType.commaSeparatedText) { $0.item.bytes }
            .suggestedFileName { $0.item.fileName }
    }
}
struct ExportJSONFile: Transferable {
    let item: ExportItem
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: UTType.json) { $0.item.bytes }
            .suggestedFileName { $0.item.fileName }
    }
}
struct ExportPDFFile: Transferable {
    let item: ExportItem
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: UTType.pdf) { $0.item.bytes }
            .suggestedFileName { $0.item.fileName }
    }
}
struct ExportImageFile: Transferable {
    let item: ExportItem
    let image: UIImage
    /// 多张长图共用同一个 ExportItem，而它的 fileName 只有一个 —— 三张同名会被「存储到文件」叠成一份。
    /// 留一个逐张改名口；不给就沿用原名。(同类壳在本文件还有 4 个，它们没有这一字段，所以两处替换都只锁 ExportImageFile 内部的多行块)
    var nameOverride: String? = nil
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: UTType.jpeg) {
            $0.image.jpegData(compressionQuality: 0.8) ?? Data()
        }
        .suggestedFileName { $0.nameOverride ?? $0.item.fileName }
    }
}
/// 718 单条记录卡分享: UIImage 本身不满足 Transferable, 而"分享这一条"不值得为它造一个完整 ExportItem
/// (ExportItem 带 sha/文件名规范/预览那套是导出中心的事)。PNG 而不是 JPEG: 卡上是锐利文字与数字。
struct RecordCardImage: Transferable {
    let image: UIImage
    let fileName: String
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.image.pngData() ?? Data() }
            .suggestedFileName { $0.fileName }
    }
}
struct ExportTextFile: Transferable {
    let item: ExportItem
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: UTType.plainText) { $0.item.bytes }
            .suggestedFileName { $0.item.fileName }
    }
}

// 709 的 `linkMetadata()` 已删 (2026-10-13): 它引用了 LPLinkMetadata 上**不存在**的三个成员
// (subtitle / keywords / thumbnailProvider), 真编译必拒; 而它本身**零调用** (现役聊天卡片走下面的
// sharePreview) —— 留一段编译不过的死码没有意义, 需要时按真 API 重写 (docs 里那条"备用口"说明同步失效)。
extension ExportItem {
    // 2026-10-13 run 59: 此前写 `SharePreview<Image, Image>` —— 但 `init(_:image:)` 的签名是
    //   SharePreview<Image, Never>(title, image: Image)
    // 只带 image 时 icon 推导为 `Never`, 显式写 Image 反而报
    //   "requires the types 'Image' and 'Never' be equivalent"。
    // (另注: 下面其他 PDF 生成处也需要 ctx.beginPage, 见 renderPDF。)
    var sharePreview: SharePreview<Image, Never> {
        // init(_:image:) 要的是 SwiftUI `Image` (不是 UIImage); coverImage 可能为 nil → 空图兜底
        SharePreview(title, image: Image(uiImage: ExportKit.coverImage(item: self, w: 480) ?? UIImage()))
    }
}

// 706 长图分页切割: 按屏高上限切 ≤3 张连图 (适配聊天窗口逐张发送)
extension ExportItem {
    static func dayPages(recs: [ExportRecord], mac: String, day: String) -> [UIImage] {
        let w: CGFloat = 720
        let rowH: CGFloat = 44
        let headH: CGFloat = 110
        let perPage = max(Int((844 * 2.2) / rowH), 1)   // 屏高 2.2 倍为一张的上限
        // 2026-10-15 走查: 方向。`ExportKit.records` 是**时间正序** (`out.reversed() // 时间正序`),
        // 而下面这张循环从下标 0 起切、最多切 3 张 ⇒ 当日超过 perPage*3 条时, 丢掉的是**最新那批**,
        // 屏上的条数却按全量报 (本仓军规: 要截断, 截断方向必须与"用户要的那一头"同侧 —— 这里要留的是最近)。
        // 正序表上取 `suffix` 就是"留最新的一段, 且张与张之间仍是旧的在前"。
        let window = Array(recs.suffix(perPage * 3))
        var pages = [UIImage]()
        var i = 0
        var p = 0
        while i < window.count && pages.count < 3 {
            let chunk = Array(window[i ..< min(i + perPage, window.count)])
            // 706: 续张带紧凑表头 (渐变头占位 headH/2), 聊天逐张发不丢锁名上下文;
            // 686: 首张此前无表头 —— 单张发出去看不出锁名/日期, 现在首张带完整表头
            let header = p == 0 ? headH : headH / 2
            let h = header + CGFloat(chunk.count) * rowH + 56
            if let img = ExportKit.renderDayPage(recs: chunk, mac: mac, day: day,
                                                 top: header, h: h, w: w, headH: header, rowH: rowH,
                                                 first: p == 0) {
                pages.append(img)
            }
            i += perPage
            p += 1
        }
        return pages
    }
}

// ================= 导出进度 (692 生成可取消, 不阻塞 UI) =================
/// 导出进度是纯界面状态 (@Published 三枚), 整类住在主 actor:
/// · @Published 必须在主线程写 (BLEService 头注里那条真机崩溃就是这个原因);
/// · 生成体仍走 Task.detached —— 重活一点都没有被拉回主线程, 性能口径不变。
@MainActor
final class ExportProgress: ObservableObject {
    @Published var running = false
    @Published var step = ""
    @Published var done: ExportItem?
    @Published var failed = ""
    private var task: Task<Void, Never>?
    /// 692: 生成体是 detached 子任务 —— 它不继承外层取消, 只 task?.cancel() 拦不住它。
    /// 存一份引用, cancel() 同时打到生成体; 完成分支清掉防残留。
    private var child: Task<ExportItem?, Never>?

    /// 719 失败重试: 记住上一次 start 的入参, 「重试」原地重放 (不复制各生成逻辑)。
    private var lastLabel = ""
    private var lastWork: (() -> ExportItem?)?
    private var lastFinish: ((ExportItem?, String) -> Void)?
    func retry() {
        guard let w = lastWork, let f = lastFinish else { return }
        start(lastLabel, work: w, finish: f)
    }

    /// 692 生成放后台 TaskGroup (可取消, UI 不阻塞); 719 结果触感 + finish 主线程回传
    func start(_ label: String,
               work: @escaping () -> ExportItem?,
               finish: @escaping (ExportItem?, String) -> Void) {
        lastLabel = label; lastWork = work; lastFinish = finish
        cancel()
        running = true; done = nil; failed = ""
        // Task { } 从 @MainActor 的 start() 里创建, 因此**继承主 actor 隔离** ——
        // 原来那三层 await MainActor.run 是多余的 (而且每层都要把一个 @Sendable 闭包
        // 连人带 self 一起塞过去, 正是告警的来源)。生成体依旧 Task.detached, 不占主线程。
        task = Task { [weak self] in
            guard let self else { return }
            self.step = label
            self.running = true
            // 生成放后台线程 (UI 不阻塞); 取消时拦"收尾写回" (692)
            let child = Task.detached(priority: .userInitiated) { work() }
            self.child = child
            let item = await child.value
            let cancelled = Task.isCancelled || child.isCancelled
            self.child = nil
            self.running = false
            self.step = ""
            // finish 走 self.lastFinish 而不是捕获局部闭包: 后者不是 Sendable,
            // 一旦被送进 Task 闭包就是 Swift 6 的"non-Sendable capture"。
            if let v = item, !cancelled {
                self.done = v
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.lastFinish?(v, "")
            } else {
                self.failed = cancelled ? "已取消" : "生成失败"
                if !cancelled { UINotificationFeedbackGenerator().notificationOccurred(.error) }
                self.lastFinish?(nil, self.failed)
            }
        }
    }
    func cancel() { task?.cancel(); child?.cancel() }
}

// ================= 核心生成器 =================
enum ExportKit {
    static let stamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; f.timeZone = TimeZone.current; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
    static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; f.timeZone = TimeZone.current; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
    /// 封面正文色: 输出面压的永远是 heroA/heroB 那条**深渐变** (位图/PDF 一旦生成就不再随系统
    /// 明暗与"智能反转"变化), 所以这里就是纯白 —— 收成一处常量, 让"为什么白在这里是对的"
    /// 只有一个解释点 (swiftlint 的纯白名额也因此收敛, 不再逐行占额度)。
    static let coverInk = UIColor.white

    // ---------- 数据源 (只读既有表) ----------
    /// 锁日志缓存 → 导出行 (member 列只有 Attribution 可证明归属才填)
    static func records(mac: String) -> [ExportRecord] {
        let cached = DB.readLogs(mac)
        let entries = cached.map { LogEntry(type: $0.type, typeName: $0.typeName, idx: $0.idxRaw,
                                            idxRaw: $0.idxRaw, lockTime: $0.lockTime,
                                            lockTimeStr: $0.lockTimeStr, body: "") }
        let cls = Attribution.classify(logs: entries, pwds: DB.listPwds(mac), fps: DB.listFps(mac), status: nil)
        var out = [ExportRecord]()
        for (i, e) in entries.enumerated() where i < cls.count {
            let c = cls[i]
            let dayKey = e.lockTimeStr.count >= 10 ? String(e.lockTimeStr.prefix(10)) : "未知"
            // 口径只有一份：StatsKit.alarmTypes (这行原来自己写着 5 个 `type ==`，值今天恰好相同，
            // 但"恰好相同"不是保证 —— 加一类告警时漏改这里，导出就会把告警标成正常行)
            let alarm = StatsKit.alarmTypes.contains(e.type)
            out.append(ExportRecord(
                time: e.lockTimeStr.isEmpty ? "时间未知" : e.lockTimeStr,
                typeName: e.typeName,
                member: c.who.map { DB.member($0)?.name ?? "" } ?? "",
                credWord: c.kind.map { Attribution.words[$0] ?? "" } ?? "",
                isAlarm: alarm,
                hex: e.body,
                dayKey: dayKey,
                key: String(e.idxRaw),
                levelName: alarm ? AlarmMeta.levelName(e.type) : ""))
        }
        return out.reversed() // 时间正序, 导出可读
    }

    // ---------- 415 成员名册单独导出 (零凭证值) ----------
    /// vCard 3.0 逐位成员。名册回答的是"家里有谁"，所以**刻意不写**：锁 MAC、凭证 alias/批次、口令、
    /// 甚至 MemberExt.commonLocks (常用锁的 mac 列表) —— 要搬库走备份，名册不承担那个职责，
    /// 也正因为写得少，它才适合打印/发给家人线下核对。
    static func memberRoster() -> String {
        var out = ""
        for m in DB.members() {
            let ext = MemberHub.ext(m.id)
            out += "BEGIN:VCARD\nVERSION:3.0\n"
            out += "FN:" + vcfEscape(MemberHub.display(m)) + "\n"
            if !ext.remark.isEmpty { out += "NICKNAME:" + vcfEscape(ext.remark) + "\n" }
            if !m.phone.isEmpty { out += "TEL;TYPE=CELL:" + vcfEscape(m.phone) + "\n" }
            if !ext.groupTag.isEmpty { out += "CATEGORIES:" + vcfEscape(ext.groupTag) + "\n" }
            var note: [String] = []
            if !m.relation.isEmpty { note.append("关系 " + m.relation) }
            if ext.role == "main" { note.append("主管理员") }
            if ext.archived { note.append("已归档") }
            if ext.proxy { note.append("代管中") }
            if !ext.emergency.isEmpty { note.append("紧急联系 " + ext.emergency) }
            if !ext.note.isEmpty { note.append("便签 " + ext.note) }
            if !ext.careText.isEmpty { note.append("关怀 " + ext.careText) }
            if !note.isEmpty { out += "NOTE:" + vcfEscape(note.joined(separator: " · ")) + "\n" }
            out += "END:VCARD\n"
        }
        return out
    }
    /// vCard 转义: 反斜杠必须先转，否则后加的 `\;` `\\,` 会被二次转义成 `\\;`。
    static func vcfEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: ";", with: "\\;")
         .replacingOccurrences(of: ",", with: "\\,")
         .replacingOccurrences(of: "\n", with: "\\n")
    }
    /// 写成 Caches/exports 下的 .vcf 文件 (与 ExportItem.writeLocal 同目录同理由: 系统不会早清)。
    /// 文件名带日期: 415 的用途是核对，"哪一次的名册"必须能从名字看出来。
    static func writeRoster() -> URL? {
        let text = memberRoster()
        guard !text.isEmpty else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone.current; f.locale = Locale(identifier: "en_US_POSIX")
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("锁管家_成员名册_\(f.string(from: Date())).vcf")
        guard (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil else { return nil }
        return url
    }

    /// 按范围过滤 (701: 全月/仅告警/仅指定成员; day = 最新单日供 686)
    static func filtered(_ recs: [ExportRecord], range: ExportRange) -> [ExportRecord] {
        switch range {
        case .all: return recs
        case .alarms: return recs.filter { $0.isAlarm }
        case .member(let mid):
            let name = DB.member(mid)?.name ?? ""
            return recs.filter { $0.member == name }
        case .month:
            let comps = WeekCal.gregorian.dateComponents([.year, .month], from: Date())
            let cur = String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
            return recs.filter { $0.time.hasPrefix(cur) }
        case .day:
            let latest = recs.map { $0.dayKey }.filter { $0 != "未知" }.max() ?? "未知"
            return recs.filter { $0.dayKey == latest }
        }
    }

    static func latestDayKey(_ recs: [ExportRecord]) -> String {
        recs.map { $0.dayKey }.filter { $0 != "未知" }.max() ?? ""
    }

    // ---------- 683 CSV 标准导出 (BOM + 721 双语注释行 + 705 预检 + 722 校验行) ----------
    struct CSVBuild {
        var data: Data
        var rowCount: Int
        var escapedRows: Int     // 705 预检: 有多少行发生转义
        var preview3: String     // 前 3 行防错列预览
    }
    static func buildCSV(recs: [ExportRecord], cols: ExportCols) -> CSVBuild {
        let idx = cols.onIndices
        let use = idx.isEmpty ? [0, 1, 3] : idx   // 全不勾时保底三列, 避免空表
        var lines = [String()]
        lines.append(use.map { ExportHeaders.zh[$0] }.joined(separator: ","))
        // 721 英文 code 注释行 (# 开头, 脚本可按注释定位列)
        lines.append("# " + use.map { ExportHeaders.en[$0] }.joined(separator: ","))
        var escapedRows = 0
        for r in recs {
            let fields = [r.time, r.typeName, r.member,
                          r.isAlarm ? r.typeName : "",
                          r.credWord.isEmpty ? "" : r.credWord + (r.member.isEmpty ? "·未归属" : "·" + r.member),
                          r.hex]
            let rowF = use.map { CSVKit.escape(fields[$0]) }
            if use.contains(where: { CSVKit.needEscaping(fields[$0]) }) { escapedRows += 1 }
            lines.append(rowF.joined(separator: ","))
        }
        let body = lines.joined(separator: "\n") + "\n"
        // 722 校验行随文件尾部 (与报告尾页同口径)
        let digest = SHA256.hash(data: Data((ExportItem.bom + body).utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let tail = "\n# SHA-256(正文): \(hex)\n# 行数: \(recs.count) · 生成: \(stamp.string(from: Date()))\n"
        let finalText = ExportItem.bom + body + tail
        return CSVBuild(
            data: Data(finalText.utf8),
            rowCount: recs.count,
            escapedRows: escapedRows,
            preview3: String(String(lines.prefix(3).joined(separator: "\n")).prefix(400)))
    }

    // 684 hex 源: 诊断原始收发日志 (kf_diag_logs, 开启"记录原始收发 hex"后含协议帧 hex 行)
    static func rawHexLines() -> [String] {
        DiagLogs.all().compactMap { l in
            l.msg.contains("hex") || l.msg.contains("0x") ? l.msg : nil
        }
    }
    // ---------- 684 原始 JSON+hex (协议字节进文件, 供 vendor 夹具比对; 脱敏开关 548) ----------
    // hex 来源诚实标注: 锁日志缓存只存 type/typeName/时间 (无原始帧), 帧级 hex 来自
    // 诊断原始收发日志 (kf_diag_logs, 需开"记录原始收发 hex"); 脱敏时留空不导出。
    static func rawJSON(mac: String, recs: [ExportRecord], redactHex: Bool) -> Data {
        var typeIdx = [String: Int]()
        for l in DB.readLogs(mac) { typeIdx[l.typeName] = l.type }
        let rows: [[String: Any]] = recs.map { r in
            [
                "time": r.time,
                "type": typeIdx[r.typeName] ?? -1,
                "typeName": r.typeName,
                "member": r.member,
                "cred": r.credWord,
                "alarm": r.isAlarm,
                "levelName": r.levelName,
                "hex": redactHex ? "" : r.hex,
            ]
        }
        let snap = DB.readStatus(mac)
        let snapDict: [String: Any] = snap.map {
            ["powerLevel": $0.powerLevel, "firmware": $0.firmware, "verifyMode": $0.verifyMode,
             "securityLevel": $0.securityLevel, "pinStock": $0.pinStock,
             "pwdStock": $0.pwdStock, "fpStock": $0.fpStock]
        } ?? [:]
        let payload: [String: Any] = [
            "app": "离线锁管家",
            "version": "1.0",
            "lock": DB.keychain(mac).map { ["name": $0.name, "mac": $0.mac, "pid": $0.pid, "fw": $0.fw] } ?? [:],
            "snapshot": snapDict,
            "count": rows.count,
            "logs": rows,
            "hexFrameLines": redactHex ? [String]() : rawHexLines(),
            "hexSource": redactHex ? "已脱敏留空" : "kf_diag_logs 原始收发帧 (未开则为空)",
            "generatedAt": stamp.string(from: Date()),
        ]
        let d = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return Data((ExportItem.bom + String(decoding: d, as: UTF8.self)).utf8)
    }

    // ---------- 548 日志三选 (App 运行日志 txt/csv/json, 脱敏独立于格式) ----------
    static func runLogData(format: String, redact: Bool) -> Data {
        let logs = DiagLogs.all()
        let msg = { (e: DiagLogEntry) in redact ? redactText(e.msg) : e.msg }
        switch format {
        case "csv":
            var lines = ["日期,时间,级别,消息"]
            for l in logs {
                lines.append([
                    CSVKit.escape(l.date),
                    CSVKit.escape(l.time),
                    CSVKit.escape(l.level),
                    CSVKit.escape(msg(l))
                ].joined(separator: ","))
            }
            return Data((ExportItem.bom + lines.joined(separator: "\n") + "\n").utf8)
        case "json":
            let arr = logs.map { l in ["date": l.date, "time": l.time, "level": l.level, "msg": msg(l)] }
            let d = (try? JSONSerialization.data(withJSONObject: arr, options: [.prettyPrinted])) ?? Data()
            return Data((ExportItem.bom + String(decoding: d, as: UTF8.self)).utf8)
        default:
            let body = logs.map { "[\($0.date) \($0.time)] \($0.level) \(msg($0))" }.joined(separator: "\n")
            return Data((ExportItem.bom + body + "\n").utf8)
        }
    }
    /// 548 脱敏: 掩掉 6 位以上连续数字 (口令/序号类); 12 位 MAC 仅留后 4 位
    static func redactText(_ s: String) -> String {
        var out = s.replacingOccurrences(of: #"\d{6,}"#, with: "####", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\b[0-9a-fA-F]{8}([0-9a-fA-F]{4})\b"#,
                                       with: "****$1", options: .regularExpression)
        return out
    }

    // ---------- 722 校验文本 (报告尾页: 行数 + SHA-256 + 生成时间) ----------
    static func integrity(_ text: String, rows: Int) -> String {
        let hex = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        return ReportTexts.t("integrity") + "\nSHA-256: \(hex)\n行数: \(rows)\n生成: \(stamp.string(from: Date()))"
    }

    // ---------- 685/696/697/699/700/702/704 PDF 月度报告 ----------
    struct ReportBuild {
        var pdfData: Data
        var text: String
        var rows: Int
    }
    /// 排版流程: 矢量封面(696) → 三句摘要(704) → 告警章置前(697) → 逐日明细(702 页眉页脚)
    /// 多锁时封面列覆盖设备表(700); 图表位内嵌矢量图(699)
    static func buildReport(mac: String, recs: [ExportRecord], cols: ExportCols, rangeLabel: String, memberName: String? = nil) -> ReportBuild? {
        let kc = DB.keychain(mac)
        let lockName = kc.map { $0.name.isEmpty ? LockArchive.displayName($0) : $0.name } ?? mac
        let alarms = recs.filter { $0.isAlarm }
        let others = recs.filter { !$0.isAlarm }
        // 726 处置历史: 文本段与 PDF 章共用这一份 —— 只取**本报告范围内**告警行的本地留痕
        // (kf_rdispo, 键 = mac#行键), 范围外的留痕不混进这份报告。
        let dispo = RecordSearch.dispositions()
        var disposed = [(ExportRecord, RecordSearch.Disposition)]()
        for a in alarms { if let d = dispo[mac + "#" + a.key] { disposed.append((a, d)) } }

        // 665 导出页眉走区间精简: "当月/全部"这类档名旁边加上**数据落地的具体日子**
        // (与统计页 665 同一份 TimeFormat.range 规则, 不另写一套省略逻辑); 无有效日期时只说档名。
        let dayKeys = recs.map { $0.dayKey }.filter { !$0.isEmpty && $0 != "未知" }.sorted()
        let rangeText: String
        if let f = dayKeys.first, let l = dayKeys.last {
            rangeText = rangeLabel + " · " + TimeFormat.range(fromDay: f, toDay: l)
        } else {
            rangeText = rangeLabel
        }

        var text = ReportTexts.t("summarySection") + "\n"
        text += threeSentence(recs: recs, mac: mac) + "\n\n"
        text += ReportTexts.t("alarmSection") + "\n"
        if alarms.isEmpty {
            text += "本期无告警。\n\n"
        } else {
            for a in alarms {
                var line = "· " + (a.levelName.isEmpty ? "" : "[" + a.levelName + "] ") + a.time + " " + a.typeName + (a.member.isEmpty ? "" : " " + a.member)
                if let d = dispo[mac + "#" + a.key] { line += "  [处置: " + d.verdict + "]" }   // 726 行内带上结论
                text += line + "\n"
            }
            text += "\n"
        }
        text += ReportTexts.t("detailSection") + "\n"
        for r in others {
            var line = "· " + r.time + " " + r.typeName
            if !r.member.isEmpty { line += " " + r.member }
            text += line + "\n"
        }
        // 726 处置历史段 (与 PDF 章同序: 明细之后、校验之前)
        text += "\n" + ReportTexts.t("dispoSection") + "\n"
        if disposed.isEmpty {
            text += "本期无处置留痕。\n"
        } else {
            for (r, d) in disposed { text += "· " + r.time + " " + r.typeName + " → " + d.verdict + " (" + d.atLabel() + ")\n" }
        }
        let integrityLine = integrity(text, rows: recs.count)
        text += "\n" + integrityLine + "\n"

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        // 702 两遍渲染: 总页数只有画完才知道 —— 首遍数出 M, 次遍页脚写「第 N / M 页」。
        // 全是内存矢量绘制, 两遍是报告可接受的代价; 生成期间 UI 不阻塞 (692 的 Task.detached 链不变)。
        func renderPDF(knownTotal: Int?) -> (data: Data, pages: Int) {
        var finalPages = 0
        let pdf = renderer.pdfData { ctx in
            // ---- 页 1: 矢量封面 (696 渐变封条 + 统计区间 + 生成时间, 无图片资源) ----
            let cg = ctx.cgContext
            let heroA = UIColor(DS.Palette.themed("heroA"))
            let heroB = UIColor(DS.Palette.themed("heroB"))
            PDFText.gradient(cg, CGRect(x: 0, y: 0, width: 595, height: 150), [heroA, heroB])
            PDFText.line(cg, "离线锁管家", font: .semibold, size: 24, x: 36, y: 34, color: coverInk, pageW: 595)
            // 封面上的副信息不再用 withAlphaComponent 稀释白字: 白@0.85 裸压主题渐变最亮端实测只有
            // 3.89:1 (0.75/0.9 更低), 层级本来已由字号 (24/12/10pt) 表达, 颜色保持满白 = contrast.js B/C 节口径。
            // 774 场所副标题: Hero 卡与锁列表一直在用，导出报告此前从不引用它
            // ⇒ 同一把锁在 App 里叫"车库"，导出去的报告上只剩型号，跨设备对账时认不出来。
            let placeNote = LockArchive.meta(mac).place.isEmpty ? "" : " · 场所: " + LockArchive.meta(mac).place
            PDFText.line(cg, "月份: " + rangeText + " · 锁: " + lockName + placeNote, font: .regular, size: 12, x: 36, y: 92, color: coverInk, pageW: 595)
            PDFText.line(cg, "生成: " + stamp.string(from: Date()) + " · 纯本地生成", font: .regular, size: 10, x: 36, y: 116, color: coverInk, pageW: 595)
            // 697 封面告警数: 一翻开先知道"有没有事"
            PDFText.line(cg, "本期告警 " + String(alarms.count) + " 条" + (alarms.isEmpty ? " · 记录安静" : " · 见置前章节"),
                         font: .regular, size: 10, x: 36, y: 134, color: coverInk, pageW: 595)
            // 700 多锁封面表
            let allMacs = DB.keychains().map { $0.mac }
            if allMacs.count > 1 {
                PDFText.line(cg, "覆盖设备", font: .semibold, size: 13, x: 36, y: 170, color: .black, pageW: 595)
                var y: CGFloat = 192
                for m in allMacs {
                    let n = DB.keychain(m).map { $0.name.isEmpty ? LockArchive.displayName($0) : $0.name } ?? m
                    let cnt = String(DB.readLogs(m).count)
                    PDFText.line(cg, "· " + n + " (mac " + String(m.suffix(4)) + ") 缓存 " + cnt + " 条",
                                 font: .regular, size: 10, x: 44, y: y, color: .darkGray, pageW: 595)
                    y += 16
                }
                y += 6
                PDFText.line(cg, "本报告区间: " + rangeText, font: .regular, size: 10, x: 44, y: y, color: .darkGray, pageW: 595)
            }
            // 697 目录行: 封面先给章节序 (页码由各页页脚给, 702)
            PDFText.line(cg, "本报告: 封面 → 摘要与图表 → 告警章 → 逐日明细 → 处置历史 → 尾页校验",
                         font: .regular, size: 9, x: 36, y: 780, color: .lightGray, pageW: 520)
            // ---- 摘要页: 三句摘要 + 699 矢量图 (时段分布条, 直接画在 PDF 里缩放不糊) ----
            PDFText.line(cg, ReportTexts.t("summarySection"), font: .semibold, size: 16, x: 36, y: 40, color: .black, pageW: 595)
            var sy: CGFloat = 70
            for s in threeSentenceLines(recs: recs, mac: mac) {
                PDFText.line(cg, s, font: .regular, size: 12, x: 36, y: sy, color: .darkGray, pageW: 520)
                sy += 20
            }
            sy += 10
            PDFText.line(cg, "时段分布 (矢量图)", font: .medium, size: 12, x: 36, y: sy, color: .black, pageW: 595)
            sy += 10
            drawHourBars(cg, recs: recs, x: 36, y: sy, w: 520, h: 140, accent: UIColor(DS.Palette.accent))
            // 699 成员占比第二组 (时段条之下, 复盘"主要谁在用")
            sy += 150
            PDFText.line(cg, "成员分布 (矢量图)", font: .medium, size: 12, x: 36, y: sy, color: .black, pageW: 595)
            sy += 12
            drawMemberBars(cg, recs: recs, x: 36, y: sy, w: 520, h: 120, accent: UIColor(DS.Palette.accent))
            PDFText.line(cg, ReportTexts.t("footer") + " · " + rangeText + " · " + lockName,
                         font: .regular, size: 9, x: 36, y: 28, color: .lightGray, pageW: 460)
            PDFText.line(cg, totalLabel(2),
                         font: .regular, size: 9, x: 36, y: 812, color: .lightGray, pageW: 520)
            // ---- 正文页: 告警章(697 置前) + 逐日明细, 702 页眉页脚 ----
            var pageIdx = 2   // 封面=1 / 摘要=2 已消耗 (初值 1 会让首个正文页与摘要页都印「第 2 页」)
            func totalLabel(_ n: Int) -> String {
                "第 " + String(n) + (knownTotal.map { " / " + String($0) } ?? "") + " 页 · " + ReportTexts.t("footer")
            }
            func startPageHeader(_ title: String) {
                pageIdx += 1
                // 页眉回显筛选条件
                PDFText.line(cg, ReportTexts.t("footer") + " · " + rangeText + " · " + lockName,
                             font: .regular, size: 9, x: 36, y: 28, color: .lightGray, pageW: 460)
                PDFText.line(cg, title, font: .semibold, size: 15, x: 36, y: 48, color: .black, pageW: 595)
            }
            func footerPage() {
                PDFText.line(cg, totalLabel(pageIdx),
                             font: .regular, size: 9, x: 36, y: 812, color: .lightGray, pageW: 520)
            }
            var cursor = 80.0
            func startTablePage(_ title: String, breakPage: Bool = false) {
                if breakPage {
                    footerPage(); ctx.beginPage()
                }
                startPageHeader(title)
                let head = (cols.onIndices.isEmpty ? [0, 1, 3] : cols.onIndices).map { ExportHeaders.zh[$0] }
                cursor = 70
                PDFText.line(cg, head.joined(separator: " / "), font: .medium, size: 10, x: 36, y: cursor, color: .darkGray, pageW: 520)
                cursor += 16
                PDFText.hairline(cg, y: cursor); cursor += 6
            }
            func emitRow(_ r: ExportRecord) {
                if cursor > 780 {
                    footerPage(); ctx.beginPage()
                    startPageHeader("续")
                    cursor = 70
                } else { cursor = max(cursor, 70) }
                let use = cols.onIndices.isEmpty ? [0, 1, 3] : cols.onIndices
                let fields = [r.time, r.typeName, r.member,
                              r.isAlarm ? (r.levelName.isEmpty ? r.typeName : r.levelName + "·" + r.typeName) : "",
                              r.credWord.isEmpty ? "" : r.credWord + (r.member.isEmpty ? "·未归属" : "·" + r.member),
                              r.hex.isEmpty ? "" : String(r.hex.prefix(12))]
                var rowText = use.map { fields[$0] }.joined(separator: "  |  ")
                // 726 告警行紧贴结论 (完整历史见文末"处置历史"章)
                if r.isAlarm, let d = dispo[mac + "#" + r.key] { rowText += "  · 处置: " + d.verdict }
                let color: UIColor = r.isAlarm ? UIColor(DS.Palette.danger) : .darkGray
                PDFText.line(cg, rowText, font: .regular, size: 10, x: 36, y: cursor, color: color, pageW: 520)
                cursor += 16
            }
            // 697 告警章置前 (摘要页之后总是新页)
            startTablePage(ReportTexts.t("alarmSection"), breakPage: cursor > 100)
            if alarms.isEmpty {
                PDFText.line(cg, "本期无告警。", font: .regular, size: 10, x: 36, y: cursor, color: .darkGray, pageW: 520)
                cursor += 16
            }
            for a in alarms { emitRow(a) }
            // 明细章 (本页满则切新页); 685 按日分节: 日期变点插小标题 (dayKey = 日志时间串前 10 位)
            startTablePage(ReportTexts.t("detailSection"), breakPage: cursor > 740)
            var lastDay = ""
            for r in others {
                if r.dayKey != lastDay {
                    lastDay = r.dayKey
                    if cursor > 760 {
                        footerPage(); ctx.beginPage()
                        startPageHeader("续")
                        cursor = 70
                    }
                    cursor += 4
                    PDFText.line(cg, r.dayKey, font: .medium, size: 11, x: 36, y: cursor, color: .black, pageW: 520)
                    cursor += 18
                }
                emitRow(r)
            }
            // 726 处置历史章 (明细之后、校验之前, 与纯文本报告同一序)
            if !disposed.isEmpty {
                startTablePage(ReportTexts.t("dispoSection"), breakPage: cursor > 740)
                for (r, d) in disposed {
                    if cursor > 780 {
                        footerPage(); ctx.beginPage()
                        startPageHeader("续")
                        cursor = 70
                    }
                    PDFText.line(cg, r.time + "  " + r.typeName + "  →  " + d.verdict + "  (" + d.atLabel() + ")",
                                 font: .regular, size: 10, x: 36, y: cursor, color: .darkGray, pageW: 520)
                    cursor += 16
                }
            }
            // 722 尾页校验: 行数 + SHA-256 + 生成时间必须真画在纸面上。
            // 原来这条注释下面只有一句页脚 + ctx.beginPage —— 纯文本报告里有对账行，打印出来的 PDF 却没有，
            // 而 722 原句要的就是"报告尾页"那一行。
            // (2026-10-13 run 59: 原写 `ctx.endPDFPage()`, 那是**臆造 API** —— 真名是 beginPage(),
            //  它结束上一页并开启下一页; 全文件 5 处已统一改回真名。)
            if cursor > 760 {
                footerPage(); ctx.beginPage()
                startPageHeader("续")
                cursor = 70
            }
            PDFText.hairline(cg, y: cursor); cursor += 10
            for seg in integrityLine.split(separator: "\n") {
                PDFText.line(cg, String(seg), font: .regular, size: 9, x: 36, y: cursor,
                             color: .darkGray, pageW: 520)
                cursor += 13
            }
            footerPage()
            finalPages = pageIdx
        }
        return (pdf, finalPages)
        }
        let first = renderPDF(knownTotal: nil)     // 首遍只为数页数, 页脚无总数
        let second = renderPDF(knownTotal: first.pages)
        guard !second.data.isEmpty else { return nil }
        return ReportBuild(pdfData: second.data, text: text, rows: recs.count)
    }

    /// 704 三句摘要 (按任务口径: 本月 N 次开门 / M 条告警 / 凭证变动 N 条, 归属带"约")
    static func threeSentence(recs: [ExportRecord], mac: String) -> String {
        threeSentenceLines(recs: recs, mac: mac).joined(separator: "  ")
    }
    static func threeSentenceLines(recs: [ExportRecord], mac: String) -> [String] {
        let opens = recs.filter { !$0.isAlarm && $0.credWord != "" }.count
        let alarms = recs.filter { $0.isAlarm }.count
        var cred = 0
        for p in DB.listPwds(mac) { cred += CredentialOrg.history(mac, "pwd", p.alias).count }
        for f in DB.listFps(mac) { cred += CredentialOrg.history(mac, "fp", f.batch).count }
        var who = ""
        var whoN = 0
        var m = [String: Int]()
        for r in recs where !r.isAlarm && !r.member.isEmpty { m[r.member, default: 0] += 1 }
        if let top = m.sorted(by: { $0.value > $1.value }).first { who = top.key; whoN = top.value }
        var out = [String]()
        // 704 占比: 分母用同段 opens; who 集合(成员非空)与 opens 集合(凭证词非空)口径略有差 ⇒ 带「约」。
        out.append("本期开门 \(opens) 次" + (who.isEmpty ? "" : "，最活跃: 约 \(who)（占比约 \(whoN * 100 / max(opens, 1))%）"))
        out.append("告警 \(alarms) 条" + (alarms == 0 ? "，记录安静" : "（见置前章节）"))
        out.append("凭证变动 \(cred) 条（版本历史台账口径）")
        return out
    }

    /// 699 矢量图表: 时段分布条形 (直接画进 PDF 上下文, 缩放不糊)
    static func drawHourBars(_ cg: CGContext, recs: [ExportRecord], x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, accent: UIColor) {
        var hs = [Int: Int]()
        // for-in 的 where 子句**不是闭包**: `where !$0.isAlarm` 会报
        // "anonymous closure argument not contained in a closure", 必须用循环变量本身。
        for r in recs where !r.isAlarm {
            if let d = timeFmt.date(from: r.time) {
                hs[WeekCal.gregorian.component(.hour, from: d), default: 0] += 1
            }
        }
        let maxV = max(hs.values.max() ?? 1, 1)
        let cell = w / 24
        let baseY = y + h - 24
        for hr in 0..<24 {
            let v = hs[hr] ?? 0
            let bh: CGFloat = v == 0 ? 2 : CGFloat(v) / CGFloat(maxV) * (h - 40)
            accent.setFill()
            cg.fill(CGRect(x: x + CGFloat(hr) * cell + cell * 0.2, y: baseY - bh, width: cell * 0.6, height: bh))
            if hr % 4 == 0 {
                PDFText.line(cg, String(hr), font: .regular, size: 8, x: x + CGFloat(hr) * cell, y: y + h - 18, color: .lightGray, pageW: cell)
            }
        }
        // 图例
        PDFText.line(cg, "0 时", font: .regular, size: 8, x: x, y: y + h - 18, color: .lightGray, pageW: 20)
        PDFText.line(cg, "24 时 (矢量内嵌, 缩放不糊)", font: .regular, size: 8, x: x + 200, y: y + h - 18, color: .lightGray, pageW: 300)
    }

    /// 699 成员占比横条 (与时段条同页): 只统计可证明归属的开门行 —— 推不出的不计,
    /// 与报表正文 member 列的同一判据 (推不出留空, 不猜)。
    static func drawMemberBars(_ cg: CGContext, recs: [ExportRecord], x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, accent: UIColor) {
        var m = [String: Int]()
        for r in recs where !r.isAlarm && !r.member.isEmpty { m[r.member, default: 0] += 1 }
        let top = m.sorted(by: { $0.value > $1.value }).prefix(6)
        let maxV = max(top.first?.value ?? 1, 1)
        let cell = h / CGFloat(max(top.count, 1))
        var i = 0
        for (name, n) in top {
            let yy = y + CGFloat(i) * cell
            let bw = CGFloat(n) / CGFloat(maxV) * (w - 170)
            accent.setFill()
            cg.fill(CGRect(x: x + 120, y: yy + 5, width: max(bw, 2), height: cell - 10))
            PDFText.line(cg, name, font: .regular, size: 9, x: x, y: yy + 7, color: .darkGray, pageW: 110)
            PDFText.line(cg, String(n), font: .regular, size: 9, x: x + 126 + max(bw, 2), y: yy + 7, color: .lightGray, pageW: 40)
            i += 1
        }
        if top.isEmpty {
            PDFText.line(cg, "本期无可证明归属的开门", font: .regular, size: 9, x: x, y: y + 7, color: .lightGray, pageW: 520)
        }
    }

    // ---------- 688 告警分享卡 (9:16 渐变卡, ImageRenderer 出图) ----------
    @MainActor
    static func alarmCard(_ r: ExportRecord, lockName: String) -> UIImage? {
        let card = AlarmShareCardView(name: lockName, rec: r)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        return renderer.uiImage
    }

    // ---------- 718 单条记录分享卡 (明示仅含本条数据) ----------
    @MainActor
    static func recordCard(_ r: ExportRecord, lockName: String) -> UIImage? {
        let card = RecordShareCardView(name: lockName, rec: r)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        return renderer.uiImage
    }

    // ---------- 478 口述卡 (大字排版 PDF, 供不用智能手机的老人贴门) ----------
    static func oralCardPDF(mac: String, recs: [ExportRecord]) -> Data {
        let lockName = DB.keychain(mac).map { $0.name.isEmpty ? LockArchive.displayName($0) : $0.name } ?? mac
        // 2026-10-15 走查: 纸面印「本月告警」而原先数的是**全量** —— `recs` 就是 `ExportKit.records(mac:)` 那份整缓存，
        // 没有任何期间过滤 (调用点 `printOralCard()` 直接把全量传进来)。同页 `threeSentenceLines` 那句「告警 N 条」
        // 才是全量口径，两处措辞不同而算法相同 ⇒ 三个月前的告警也会被算进"本月"。
        // 月 key 用仓里唯一的口径 `Milestones.monthKey()`；`dayKey == "未知"` 那批不计入本月
        // (它证明不了自己在本月)，宁可少报也不虚报。
        let month = Milestones.monthKey()
        let alarms = recs.filter { $0.isAlarm && $0.dayKey.hasPrefix(month) }.count
        let last = recs.last.map { $0.time + " " + $0.typeName } ?? "无记录"
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        let data = renderer.pdfData { ctx in
            let cg = ctx.cgContext
            PDFText.line(cg, "请告诉我 — 口述卡", font: .semibold, size: 30, x: 56, y: 90, color: .black, pageW: 480)
            PDFText.line(cg, lockName, font: .semibold, size: 44, x: 56, y: 150, color: .black, pageW: 480)
            PDFText.line(cg, "最近一次: " + last, font: .regular, size: 22, x: 56, y: 250, color: .darkGray, pageW: 480)
            PDFText.line(cg, "本月告警: " + String(alarms) + " 条", font: .regular, size: 22,
                         x: 56, y: 296, color: alarms > 0 ? UIColor(DS.Palette.danger) : .darkGray, pageW: 480)
            // 465: 成员档案里的紧急联系 (纯本地) 汇一行; 没有就印"保密档"占位
            let em = DB.members().compactMap { m -> String? in
                let e = MemberHub.ext(m.id).emergency
                return e.isEmpty ? nil : "\(m.name) \(e)"
            }.joined(separator: " / ")
            PDFText.line(cg, em.isEmpty ? "应急电话: 保密档" : "应急电话: " + em, font: .regular, size: 22, x: 56, y: 380, color: .black, pageW: 480)
            PDFText.hairline(cg, y: 430); PDFText.hairline(cg, y: 500)
            PDFText.line(cg, "备用钥匙位置 (手填):", font: .regular, size: 22, x: 56, y: 540, color: .black, pageW: 480)
            PDFText.hairline(cg, y: 590)
            PDFText.line(cg, "离线锁管家 · 本地生成 · 数据未经网络", font: .regular, size: 11, x: 56, y: 780, color: .lightGray, pageW: 480)
        }
        return data
    }

    // ---------- 746 单条告警事实单页 (事实 + 原始报文 + 处置 + 签名栏; 用于物业沟通) ----------
    /// 与 717 的区别: 717 是"最近 10 条合页"的通报, 这条是**一条告警一页**的事实单, 带签名栏。
    /// 原始报文取 ExportRecord.hex (缓存层存了协议帧才非空, 否则如实写"未留存") —— 不编字节。
    static func alarmFactSheetPDF(mac: String, rec: ExportRecord) -> Data {
        let lockName = DB.keychain(mac).map { $0.name.isEmpty ? LockArchive.displayName($0) : $0.name } ?? mac
        let dispo = RecordSearch.disposition(key: mac + "#" + rec.key)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        return renderer.pdfData { ctx in
            let cg = ctx.cgContext
            PDFText.line(cg, "门锁告警事实单 · " + lockName, font: .semibold, size: 20, x: 36, y: 36, color: .black, pageW: 520)
            PDFText.line(cg, "本单只含这一条告警的数据 · 导出时间 " + ExportKit.stamp.string(from: Date()),   // 746 本单只含这一条告警的
                         font: .regular, size: 10, x: 36, y: 66, color: .darkGray, pageW: 520)
            var y: CGFloat = 104
            func kv(_ k: String, _ v: String) {
                PDFText.line(cg, k, font: .medium, size: 12, x: 36, y: y, color: .black, pageW: 520)
                PDFText.line(cg, v.isEmpty ? "—" : v, font: .regular, size: 12, x: 150, y: y, color: .darkGray, pageW: 410)
                y += 24
            }
            kv("时间", rec.time)
            kv("告警类型", rec.typeName + (rec.levelName.isEmpty ? "" : " (" + rec.levelName + ")"))
            kv("涉事成员", rec.member.isEmpty ? "无法归属 (可证明归属才填)" : rec.member)
            kv("门锁", lockName)
            kv("原始报文", rec.hex.isEmpty ? "本机未留存 (未开启「记录原始收发 hex」)" : rec.hex)
            kv("处置结论", dispo.map { $0.verdict + " · " + $0.atLabel() } ?? "未处置")
            y += 18
            PDFText.line(cg, "签名栏 (物业 / 处置人)", font: .medium, size: 12, x: 36, y: y, color: .black, pageW: 520)
            // hairline 的签名只有 (cg, y:) —— 它是全宽横线 (x 36→559), 所以两格签名位共用这一条;
            // 早先这里写过 x2: 300 (凭空多一个参数), 被 swiftshape 的 R5 调用元数检查当场拦下。
            PDFText.hairline(cg, y: y + 44)
            PDFText.line(cg, "签名 / 日期", font: .regular, size: 10, x: 36, y: y + 50, color: .lightGray, pageW: 240)
            PDFText.line(cg, "确认 / 日期", font: .regular, size: 10, x: 316, y: y + 50, color: .lightGray, pageW: 240)
            PDFText.line(cg, "离线锁管家 · 本机生成 · 数据未经网络", font: .regular, size: 10, x: 36, y: 790, color: .lightGray, pageW: 520)
        }
    }

    // ---------- 717 告警一页纸 (当前预警配置 + 最近告警 + 手填栏) ----------
    static func alarmOnePagerPDF(mac: String, recs: [ExportRecord]) -> Data {
        let lockName = DB.keychain(mac).map { $0.name.isEmpty ? LockArchive.displayName($0) : $0.name } ?? mac
        let alarms = recs.filter { $0.isAlarm }
        // 726 处置历史随行: 每条告警旁边带上本地留痕结论
        let dispo = RecordSearch.dispositions()
        var cfgs = [String]()
        for p in DB.listPwds(mac) {
            let a = CredentialOrg.alert(mac, p)
            if a.day || a.h24 || a.h2 {
                var parts = [String]()
                if a.day { parts.append("7 天") }
                if a.h24 { parts.append("24 小时") }
                if a.h2 { parts.append("2 小时") }
                let disp = p.note.isEmpty ? "#" + String(p.alias) : p.note
                cfgs.append(disp + " 提前 " + parts.joined(separator: "/"))
            }
        }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        let data = renderer.pdfData { ctx in
            let cg = ctx.cgContext
            PDFText.line(cg, "告警一页纸 · " + lockName, font: .semibold, size: 20, x: 36, y: 36, color: .black, pageW: 520)
            PDFText.line(cg, "当前预警配置: " + (cfgs.isEmpty ? "（未设置）" : cfgs.joined(separator: "；")),
                         font: .regular, size: 11, x: 36, y: 66, color: .darkGray, pageW: 520)
            var y: CGFloat = 96
            PDFText.line(cg, "最近 " + String(min(alarms.count, 10)) + " 条告警", font: .medium, size: 14, x: 36, y: y, color: .black, pageW: 520)
            y += 22
            // 2026-10-15 走查: 上一行写「最近 N 条告警」而这一圈原先取的是 `prefix(10)` ——
            // `ExportKit.records` 是**时间正序** (`return out.reversed()`)，正序表上的 prefix 就是**最早那 10 条**，
            // 印出来的是"这张锁第一次报警一直到第十条"，而标题说的是最近。同 §7.2 长图那张一个病：截断方向要与用户要的那一头同侧
            // ⇒ 改 `suffix(10)` (仍按时间先后排列，只是留的是最后 10 条)。
            for a in alarms.suffix(10) {
                var line = a.time + "   " + a.typeName + (a.member.isEmpty ? "" : " · " + a.member)
                if let d = dispo[mac + "#" + a.key] { line += " · 处置:" + d.verdict }   // 726
                PDFText.line(cg, line,
                             font: .regular, size: 12, x: 44, y: y, color: UIColor(DS.Palette.danger), pageW: 500)
                y += 20
            }
            y += 40
            PDFText.line(cg, "应急电话 (手填): ______________________", font: .regular, size: 18, x: 36, y: y, color: .black, pageW: 520)
            y += 56
            PDFText.line(cg, "物业 / 厂家热线 (手填): ______________________", font: .regular, size: 18, x: 36, y: y, color: .black, pageW: 520)
        }
        return data
    }

    // ---------- 703 系统邮件直发 ----------
    /// MFMailCompose 的完成回调 (取消/发送/失败后关闭编辑器)。delegate 是 weak —— 必须常驻, 不留实例引用。
    /// 无状态单例: 零存储属性, 唯一职责是把邮件编辑器收起来 —— 所以 @unchecked Sendable 有依据
    /// (没有可保护的状态, 不是把检查关掉)。
    /// MessageUI 的 delegate 要求**不是** @MainActor 隔离的 (与 UIKit 本体不同), 而 dismiss 是 ——
    /// 因此不能把本类整体拉上主 actor (那样会与协议要求冲突), 只能在回调里跳一次。
    final class MailDismisser: NSObject, MFMailComposeViewControllerDelegate, @unchecked Sendable {
        static let shared = MailDismisser()
        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            Task { @MainActor in controller.dismiss(animated: true) }
        }
    }

    // ---------- 703 降级: 生成 .eml 文本 (主题预填 + CSV base64 附件), 手动交给系统邮件 ----------
    static func emailTemplate(mac: String, recs: [ExportRecord], cols: ExportCols) -> ExportItem? {
        let build = buildCSV(recs: recs, cols: cols)
        let rangeLabel = ExportRange.month.label
        // 693 与 startCSV 同名规范同步 (eml 附件名也不缺锁名)
        let kc = DB.keychain(mac)
        let lockName = kc.map { $0.name.isEmpty ? LockArchive.displayName($0) : $0.name } ?? mac
        let fileName = "锁管家_记录_" + lockName + "_" + rangeLabel + ".csv"
        let b64 = build.data.base64EncodedString()
        let subject = "「离线锁管家」" + rangeLabel + " 开门记录"
        let bodyFinal = "请查收附件 " + fileName + " (共 " + String(build.rowCount) + " 行)。\n\n此邮件为本地文本模板, 请粘贴进系统邮件或备忘录手动发送。"
        let eml = [
            "From: local@offline-lock.local",
            "To:",
            "Subject: " + subject,
            "MIME-Version: 1.0",
            "Content-Type: multipart/mixed; boundary=\"LK\"",
            "",
            "--LK",
            "Content-Type: text/plain; charset=UTF-8",
            "",
            bodyFinal,
            "--LK",
            "Content-Type: text/csv; name=\"" + fileName + "\"",
            "Content-Disposition: attachment; filename=\"" + fileName + "\"",
            "Content-Transfer-Encoding: base64",
            "",
            b64,
            "--LK--",
        ].joined(separator: "\n")
        let data = Data((ExportItem.bom + eml).utf8)
        let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return ExportItem(kind: "eml", title: "邮件模板 " + subject, fileName: fileName + ".eml",
                          bytes: data, sha256: hex, shaLabel: "邮件模板 · 手动发送",
                          previewText: subject + "\n" + bodyFinal,
                          scopeNote: "含 " + String(build.rowCount) + " 行记录")
    }

    // ---------- 709 封面缩略图 (分享卡片预览) ----------
    static func coverImage(item: ExportItem, w: CGFloat) -> UIImage {
        let h = w * 4 / 3
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 2
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { ctx in
            let cg = ctx.cgContext
            PDFText.gradient(cg, CGRect(x: 0, y: 0, width: w, height: h),
                             [UIColor(DS.Palette.themed("heroA")), UIColor(DS.Palette.themed("heroB"))])
            PDFText.line(cg, "离线锁管家", font: .semibold, size: w * 0.1, x: w * 0.1, y: w * 0.1, color: .white, pageW: w)
            PDFText.line(cg, item.title, font: .regular, size: w * 0.08, x: w * 0.1, y: w * 0.24, color: .white, pageW: w)
            PDFText.line(cg, item.shaLabel, font: .regular, size: w * 0.06, x: w * 0.1, y: h - w * 0.14, color: .white, pageW: w)
        }
    }

    // ---------- 单日长图渲染 (686 表头水印 + 行; 706 每张连图独立成页, 表头随行切) ----------
    /// 706 分页: top>0 时页顶带渐变表头; 686 起首张也带完整表头 (此前首张无表头, 单张发出去看不出锁名/日期)
    static func renderDayPage(recs: [ExportRecord], mac: String, day: String,
                              top: CGFloat, h: CGFloat, w: CGFloat, headH: CGFloat, rowH: CGFloat,
                              first: Bool = false) -> UIImage? {
        guard h > 60, !recs.isEmpty else { return nil }
        let lockName = DB.keychain(mac).map { $0.name.isEmpty ? LockArchive.displayName($0) : $0.name } ?? mac
        let fmt = UIGraphicsImageRendererFormat()
        // 720: 原句要"宽 1080px 适配聊天窗口"。此前 w=720pt 配 scale=2 ⇒ 实际 1440px,
        // 比承诺的更宽, "控制体积"方向做反。版面仍按 720pt 排, 只把出图密度改成 1.5
        // (720 × 1.5 = 1080px 整), 宽度与文案一致、体积随之下降。
        fmt.scale = 1.5
        let headOffset: CGFloat = top == 0 ? 0 : headH   // 行从本页表头下起画; dayPages 首张给完整 headH、续张给 headH/2 (都画), top==0 只是裸页兜底
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { ctx in
            let cg = ctx.cgContext
            UIColor.white.setFill()
            cg.fill(CGRect(x: 0, y: 0, width: w, height: h))
            if top > 0 {
                PDFText.gradient(cg, CGRect(x: 0, y: 0, width: w, height: headH),
                                 [UIColor(DS.Palette.themed("heroA")), UIColor(DS.Palette.themed("heroB"))])
                let sub = day + " · 离线锁管家" + (first ? "" : " (续)")
                PDFText.line(cg, sub, font: .regular, size: 13, x: 24, y: 44, color: .white, pageW: w - 48)
            }
            var i = 0
            for r in recs {
                let yy = headOffset + CGFloat(i) * rowH
                if yy + rowH > h { break }
                if i % 2 == 1 {
                    UIColor(white: 0.96, alpha: 1).setFill()
                    cg.fill(CGRect(x: 0, y: yy, width: w, height: rowH))
                }
                let color: UIColor = r.isAlarm ? UIColor(DS.Palette.danger) : .black
                PDFText.line(cg, r.time, font: .regular, size: 13, x: 24, y: yy + 13, color: color, pageW: 170)
                PDFText.line(cg, (r.isAlarm ? "⚠ " : "") + r.typeName, font: r.isAlarm ? .semibold : .regular, size: 14, x: 210, y: yy + 13, color: color, pageW: 190)
                let who = r.member.isEmpty ? (r.credWord.isEmpty ? "" : "·" + r.credWord + "·未归属")
                         : "·" + r.member + (r.credWord.isEmpty ? "" : " " + r.credWord)
                if !who.isEmpty {
                    PDFText.line(cg, who, font: .regular, size: 12, x: 420, y: yy + 13, color: .darkGray, pageW: 260)
                }
                i += 1
            }
            if h - (headOffset + CGFloat(recs.count) * rowH) > 44 {
                PDFText.line(cg, "本页 " + String(i) + " 条 · 本地生成 · 数据未经网络", font: .regular, size: 11, x: 24, y: h - 30, color: .lightGray, pageW: w - 48)
            }
        }
    }

    // ---------- 687/701 打印: UIPrintInteractionController 直接印这份 PDF ----------
    // 旧写法自造了一个 UIPrintFormatter 子类, 覆写 `printPage(_:in:)` / `size(for:)` 两个
    // **SDK 里不存在的方法**, 还引用了不存在的 `UIPrintPageRange` —— 真编译报 5 条错。
    // `printingItem` 是官方支持 PDF 的入口 (行为等价: 整份 PDF 交给系统打印面板), 且少一个自造类。
    @MainActor
    static func presentPrint(pdfData: Data, jobName: String, from view: UIView) {
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = jobName
        // .shared 是**非可选**单例 (旧写法 guard let 会被编译器拒), present 的真实标签序是 (from:in:animated:)
        let controller = UIPrintInteractionController.shared
        controller.printingItem = pdfData
        controller.printInfo = info
        controller.present(from: view.bounds, in: view, animated: true, completionHandler: nil)
    }
}

// ---------- PDF 矢量排版助手 (无图片资源, 缩放不糊) ----------
extension ExportKit {
    enum PDFText {
        /// y 坐标按 UIKit 顶下向 (UIGraphicsPDFRenderer 页面原点在左上), 经
        /// UIGraphicsPushContext + NSString.draw 保证文字不倒置、中文排版正确
        static func line(_ cg: CGContext, _ s: String, font: UIFont.Weight, size: CGFloat,
                         x: CGFloat, y: CGFloat, color: UIColor, pageW: CGFloat) {
            let f = UIFont(name: font == .semibold ? "PingFangSC-Semibold" : (font == .medium ? "PingFangSC-Medium" : "PingFangSC-Regular"),
                           size: size) ?? .systemFont(ofSize: size, weight: font == .semibold ? .semibold : .regular)
            let p = NSMutableParagraphStyle()
            p.lineSpacing = 2
            let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color, .paragraphStyle: p]
            let ns = NSAttributedString(string: s, attributes: attrs)
            // 调用点均在 UIGraphics 渲染器 (PDF/图片) 内, UIKit 图形上下文已就位
            ns.draw(with: CGRect(x: x, y: y, width: pageW, height: size * 4),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }
        static func gradient(_ cg: CGContext, _ rect: CGRect, _ colors: [UIColor]) {
            let space = CGColorSpaceCreateDeviceRGB()
            guard let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil) else { return }
            cg.drawLinearGradient(g, start: CGPoint(x: rect.minX, y: rect.minY),
                                  end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
        }
        static func hairline(_ cg: CGContext, y: CGFloat) {
            UIColor(white: 0.8, alpha: 1).setStroke()
            cg.setLineWidth(0.5)
            cg.move(to: CGPoint(x: 36, y: y))
            cg.addLine(to: CGPoint(x: 559, y: y))
            cg.strokePath()
        }
    }
}

// ================= 710 报告校验二维码 (出码侧 + 本机扫码核对侧) =================
// 这张码的语义只有一句, 页面文案也只承诺这一句: 它记的是"本机数据按下面口径重算出的指纹"
// (行数 + SHA-256 摘要)。报告文件分享出去之后就不在本机了, 所以这一步能做的是
// "这份码 vs 本机当前数据"的一致性核对 —— 比对全走只读读链 (records / filtered),
// 扫到的原文只进结果文案, 库里一个字节都不会被写。
// 复用既有基础设施: 哈希 = HashKit.sha256Hex (App/Core/AuditChain.swift:20),
// 出图 = BackupStudio.qrImage (App/Services/BackupStudioKit.swift:364, CIQRCodeGenerator),
// 相机侧 = ReportScanSheet (App/UI/ReportVerifyView.swift, 逐字抄 BackupStudio.swift:2287)。
enum ReportVerify {
    /// 710 载荷前缀: "是不是本 App 的校验码"的唯一判据 (三态里的第三态就靠它)
    static let magic = "KFRPT1"
    /// 710 摘要降级档长度 = 12 位 hex, 与 753 诊断摘要同档 (App/Core/DiagKit.swift:1018)
    static let shortLen = 12
    /// 710 QR 载荷预算: 120 字符在 CIQRCodeGenerator 的默认纠错档 M 下落在版本 7 上下
    /// (≈45×45 模块), qrImage 的 scale 6 出图约 270pt —— 相机对得上, 整码也读得完。
    static let payloadBudget = 120
    /// 710 小写 hex 字符集 (摘要形状校验用; Character.isLowercase 对数字为 false, 故自己列表)
    static let hexChars: Set<Character> = Set("0123456789abcdef")

    /// 710 一张码: 行数 + 摘要 + (按预算保留的) 锁与范围口径
    struct Code {
        var rows: Int
        var digest: String
        var mac: String?
        var rangeToken: String?
        var payload: String
        /// 710 档位: 1 = 64 位摘要 + 口径全带 / 2 = 摘要截到 12 位, 口径仍带 / 3 = 只剩行数 + 12 位摘要
        var tier: Int
    }

    /// 710 载荷解析三态: 自家码 / 别人家的码 / 开头对但载荷残缺
    enum Load {
        case ours(Code)
        case foreign
        case broken
    }

    /// 710 核对结论: 直接进 UI 的标题 + 逐行说明 (tone/icon 走 DS 语义档)
    struct Verdict {
        var tone: ToneColor
        var icon: String
        var title: String
        var lines: [String]
        var at: String
    }

    /// 710 摘要口径 —— 改这里必须同步改页面上的口径说明, 否则同一批数据会出现两个"官方口径":
    /// 一行 = 时间 / 类型名 / 成员名 / 是否告警 / 凭证词 / 锁端行键 六字段, 以 U+001F 分隔;
    /// 行序 = 报告正文的实际出场序, 判据在 buildReport 里: 告警/明细的分拣 (:561-562) 与两章的
    /// 逐行循环 (告警章 :585-589 在前、明细章 :593-597 在后), 章内保持 records(mac:) 的行序。
    /// 原始 hex、级别字样、处置结论、生成时间、列选择 (690) 都在口径之外: 那五项要么由这六项派生,
    /// 要么每次导出都不同 (含时间戳), 算进去会让同一批数据每次导出得到不同指纹, 核对失去可复现性。
    static func rowToken(_ r: ExportRecord) -> String {
        [r.time, r.typeName, r.member, r.isAlarm ? "1" : "0", r.credWord, r.key]
            .joined(separator: "\u{1F}")
    }
    static func reportLineTokens(_ recs: [ExportRecord]) -> [String] {
        recs.filter { $0.isAlarm }.map { rowToken($0) } + recs.filter { !$0.isAlarm }.map { rowToken($0) }
    }
    /// 710 摘要 = SHA-256(报告正文行集合按口径拼出的文本), 全小写 hex (64 位)
    static func digest(of recs: [ExportRecord]) -> String {
        HashKit.sha256Hex(reportLineTokens(recs).joined(separator: "\n"))
    }

    /// 710 范围口径进载荷: 核对侧要能知道这份码是按哪一档算的, 否则页面上换个范围永远对不上。
    /// 成员用稳定 id 作 tag (689 的教训: 名字会改进文件名, id 才是稳定标识)。
    static func token(of range: ExportRange) -> String {
        switch range {
        case .all: return "all"
        case .month: return "month"
        case .day: return "day"
        case .alarms: return "alarms"
        case .member(let id): return "member-" + id
        }
    }
    static func range(fromToken t: String) -> ExportRange? {
        switch t {
        case "all": return .all
        case "month": return .month
        case "day": return .day
        case "alarms": return .alarms
        default:
            guard t.hasPrefix("member-") else { return nil }
            let id = String(t.dropFirst("member-".count))
            guard !id.isEmpty, DB.member(id) != nil else { return nil }
            return .member(id)
        }
    }

    /// 710 本机数据 → 一张码; 载荷超预算时按 tier1 → tier2 → tier3 逐级降级 (规则同时进文案)
    static func code(mac: String, range: ExportRange) -> Code {
        let recs = ExportKit.filtered(ExportKit.records(mac: mac), range: range)
        let full = digest(of: recs)
        let head = magic + "|" + String(recs.count) + "|"
        let ctx = "|" + mac + "|" + token(of: range)
        let tok = token(of: range)
        // 710 第一档: 行数 + 64 位摘要 + 锁 + 范围
        let tier1 = head + full + ctx
        if tier1.count <= payloadBudget {
            return Code(rows: recs.count, digest: full, mac: mac, rangeToken: tok, payload: tier1, tier: 1)
        }
        // 710 第二档: 摘要只带前 12 位 (QR 容量优先保口径上下文)
        let short = String(full.prefix(shortLen))
        let tier2 = head + short + ctx
        if tier2.count <= payloadBudget {
            return Code(rows: recs.count, digest: short, mac: mac, rangeToken: tok, payload: tier2, tier: 2)
        }
        // 710 第三档: 口径段一并退出载荷, 只剩行数 + 摘要前 12 位; 核对口径回落到本页当前选择
        return Code(rows: recs.count, digest: short, mac: nil, rangeToken: nil, payload: head + short, tier: 3)
    }

    /// 710 解析: 前缀 + 段数 + 摘要形状三道闸都在这里收口, 判定只认形状
    static func parse(_ s: String) -> Load {
        let text = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = text.components(separatedBy: "|")
        guard parts.first == magic else { return .foreign }
        guard parts.count == 3 || parts.count == 5 else { return .broken }
        guard let rows = Int(parts[1]), isDigest(parts[2]) else { return .broken }
        let hasCtx = parts.count == 5
        return .ours(Code(rows: rows,
                          digest: parts[2],
                          mac: hasCtx ? parts[3] : nil,
                          rangeToken: hasCtx ? parts[4] : nil,
                          payload: text,
                          tier: hasCtx ? (parts[2].count == 64 ? 1 : 2) : 3))
    }
    /// 710 摘要形状: 64 位完整档或 12 位降级档, 字符限小写 hex
    static func isDigest(_ s: String) -> Bool {
        (s.count == 64 || s.count == shortLen) && s.allSatisfy { hexChars.contains($0) }
    }
    /// 710 摘要比对: 两边可能一档 64 一档 12 ⇒ 按共有长度比前缀, 降级不改变判定含义
    static func digestMatch(_ a: String, _ b: String) -> Bool {
        let n = min(a.count, b.count)
        guard n > 0 else { return false }
        return String(a.prefix(n)) == String(b.prefix(n))
    }

    /// 710 口径说明: 核对拿什么数据重算的必须写在结果里, 否则"不一致"没法解释
    static func caliberText(_ scanned: Code, mac: String, range: ExportRange) -> String {
        var s = "重算口径: 锁 mac 尾 " + String(mac.suffix(4)) + " · 范围 " + range.label
        if scanned.mac == nil || scanned.rangeToken == nil {
            s += " · 这一档码上只带行数与摘要, 口径按本页当前选择"
        }
        return s
    }
    /// 710 降级规则写在码旁边, 让"这张码带什么"在页面上可读
    static func tierText(_ c: Code) -> String {
        switch c.tier {
        case 1: return "完整档载荷 (" + String(c.payload.count) + " 字符 / 预算 " + String(payloadBudget) + "): 行数 + 64 位摘要 + 锁与范围口径。"
        case 2: return "降级一档: 载荷超 " + String(payloadBudget) + " 字符 ⇒ 摘要只带前 " + String(shortLen) + " 位, 锁与范围口径仍带着。"
        default: return "降级两档: 摘要降档后仍超 " + String(payloadBudget) + " 字符 ⇒ 载荷只剩行数 + 摘要前 " + String(shortLen) + " 位, 核对口径回落到本页当前的锁与范围。"
        }
    }

    /// 710 核对入口: 扫到的载荷原文 + 本页当前锁与范围 (码上带口径时以码为准)
    static func verify(_ text: String, currentMac: String, currentRange: ExportRange) -> Verdict {
        let now = ExportKit.stamp.string(from: Date())
        switch parse(text) {
        case .foreign:
            return Verdict(tone: .neutral, icon: "questionmark.circle.fill",
                           title: "这不是本 App 的校验码",
                           lines: ["校验码的载荷以 " + magic + " 开头, 扫到的这段开头是 " + String(text.prefix(20)) + "。",
                                   "相机认得各种码, 这里只比自己家这一种前缀; 扫到的内容只进这屏文案, 不进任何库。"],
                           at: now)
        case .broken:
            return Verdict(tone: .warn, icon: "exclamationmark.triangle.fill",
                           title: "码读到了, 载荷读不成",
                           lines: ["开头是 " + magic + ", 但后面缺行数、缺摘要, 或摘要长度落在 64/12 位之外 —— 这张码被裁切过或出自别的版本。",
                                   "扫到的原文: " + String(text.prefix(96))],
                           at: now)
        case .ours(let scanned):
            let m = scanned.mac ?? currentMac
            let r = scanned.rangeToken.flatMap { range(fromToken: $0) } ?? currentRange
            let local = code(mac: m, range: r)
            var lines = [caliberText(scanned, mac: m, range: r)]
            let sameRows = scanned.rows == local.rows
            let sameDigest = digestMatch(scanned.digest, local.digest)
            if sameRows && sameDigest {
                lines.append("行数: 双方都是 " + String(local.rows) + " 行。")
                lines.append("摘要: 双方都是 " + local.digest + " (按共有长度比前缀, 降级档照样可比)。")
                lines.append("对上的是「这份码记的指纹」与「本机现在的数据」; 报告文件分享出去后就不在本机了, 它自身的真伪在这一条核对之外。")
                return Verdict(tone: .ok, icon: "checkmark.circle.fill",
                               title: "一致: 本机数据与这份码对得上", lines: lines, at: now)
            }
            if sameRows {
                lines.append("行数: 双方都是 " + String(local.rows) + " 行, 摘要不同 ⇒ 变的是行内容本身 (成员改名、凭证增删引起的归属变化这类)。")
            } else {
                let diff = local.rows - scanned.rows
                lines.append("行数: 码上 " + String(scanned.rows) + " 行, 本机 " + String(local.rows) + " 行 (本机"
                             + (diff > 0 ? "多出 " + String(diff) : "少了 " + String(-diff)) + " 行)。")
            }
            lines.append("摘要: 码上 " + scanned.digest + " , 本机 " + local.digest + "。")
            lines.append("本机数据在导出之后又变了才会走到这一态: 新增或删除记录、改成员名、增删凭证都会改变重算结果。")
            lines.append("核对的两端是「这份码」与「本机当前数据」; 分享出去的报告文件已不在本机, 它的真伪不在核对范围。")
            return Verdict(tone: .warn, icon: "exclamationmark.triangle.fill",
                           title: "不一致: 本机数据与这份码对不上", lines: lines, at: now)
        }
    }
}

// ================= 卡片视图 (ImageRenderer 渲染; 固定尺寸, 不参与动态字体 — 分享卡按设计固定) =================
struct AlarmShareCardView: View {
    let name: String
    let rec: ExportRecord
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: DS.Icon.xl, weight: .semibold))
                .foregroundStyle(DS.heroFg)
                .accessibilityHidden(true)
            Text(rec.typeName)
                .vkFont(.title2, weight: .semibold)
                .foregroundStyle(DS.heroFg)
                .fixedSize(horizontal: false, vertical: true)
            Text(name)
                .vkFont(.subheadline)
                .foregroundStyle(DS.heroFg.opacity(0.85))
                .lineLimit(1)
            Text(rec.time)
                .vkFont(.footnote)
                .foregroundStyle(DS.heroFg.opacity(0.7))
                .lineLimit(1)
            Spacer()
            Text("离线锁管家 · 单条告警 · 仅含本条数据")
                .vkFont(.caption2)
                .foregroundStyle(DS.heroFg.opacity(0.7))
        }
        .padding(DS.Space.xl)
        .frame(width: 360, height: 640, alignment: .top)   // 9:16
        .background(DS.heroGradientSafe, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }
}

struct RecordShareCardView: View {
    let name: String
    let rec: ExportRecord
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Image(systemName: rec.isAlarm ? "exclamationmark.triangle.fill" : "lock.open.fill")
                .font(.system(size: DS.Icon.xl, weight: .semibold))
                .foregroundStyle(DS.heroFg)
                .accessibilityHidden(true)
            Text(rec.typeName)
                .vkFont(.title2, weight: .semibold)
                .foregroundStyle(DS.heroFg)
                .fixedSize(horizontal: false, vertical: true)
            Text((rec.member.isEmpty ? name : name + " · " + rec.member) + " · " + rec.time)
                .vkFont(.subheadline)
                .foregroundStyle(DS.heroFg.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Text("离线锁管家 · 单条记录 · 仅含本条数据")
                .vkFont(.caption2)
                .foregroundStyle(DS.heroFg.opacity(0.7))
        }
        .padding(DS.Space.xl)
        .frame(width: 360, height: 640, alignment: .top)
        .background(DS.heroGradientSafe, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }
}

// ================= 导出中心页 (记录 Tab 导出菜单落点; 683/684/685/686/548/687/708/712/714/718/719) =================
struct ExportCenterView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var progress = ExportProgress()
    @State private var range: ExportRange = .month
    @State private var cols = ExportCols.load()
    @State private var redact = false
    @State private var logFormat: String = "csv"   // 548 三选 txt/csv/json
    @State private var quickLook: URL?
    @State private var showQL = false
    @State private var lastPath = ""
    @State private var lastSuccess = false
    @State private var dayPick = ""            // 686 单日长图选中的日子 (空 = 最新一天)
    @State private var dayOpts: [String] = []  // 686 可选日 = 有记录的最近 14 天
    // 710 校验二维码: 指纹与出图各缓存一份 @State (同 686 的"进页算一次, 不在 Form 热路径现算"),
    // 换范围/手动重算时刷新; 核对结论也留在页面上, 让"码"和"比对结果"同屏可读。
    @State private var verifyCode: ReportVerify.Code?
    @State private var verifyQR: UIImage?
    @State private var verifyVerdict: ReportVerify.Verdict?
    @State private var showVerifyScan = false

    let mac: String
    init(mac: String) { self.mac = mac }

    var body: some View { vkBody.destined(.exportCenter) }
    var vkBody: some View {
        NavigationStack {
            Form {
                scopeSection
                colsSection
                redactSection
                actionList
                if progress.running { progressSection }
                if !progress.failed.isEmpty {
                    Section {
                        Label(progress.failed, systemImage: "xmark.circle")
                            .vkFont(.subheadline)
                            .foregroundStyle(DS.Palette.danger)
                        Text(progress.failed == "生成失败" ? "多为记录为空或空间不足, 重试或稍后再试。" : "已停止生成, 数据未离开本机。")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                        // 719 重试: 重放上次起点的闭包 (取消不重试 —— 取消是用户的决定, 不是失败)
                        if progress.failed != "已取消" {
                            Button("重试") { progress.retry() }   // 719 重试
                                .vkFont(.subheadline)
                                .foregroundStyle(DS.Palette.accentText)
                                .frame(minHeight: DS.Hit.min)
                                .contentShape(Rectangle())
                        }
                    }
                }
                if let item = progress.done { doneSection(item).animation(DS.Motion.standard, value: lastSuccess) }
                // 710 校验二维码区: 出码 + 扫码核对, 与上面的导出动作同页 (报告落点页)
                verifySection
                if !lastPath.isEmpty { pathSection }
            }
            .navigationTitle("导出与分享")
            .variantList()
            .dsScreenBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("关闭") { dismiss() } }
            }
            .fullScreenCover(isPresented: $showQL) {
                if let u = quickLook { QLPreviewView(url: u) }
            }
            // 710 扫码核对的相机侧: 独立 sheet (与 411/522 两处同一制式), 载荷原文交回 runVerify
            .sheet(isPresented: $showVerifyScan) {
                ReportScanSheet { runVerify($0) }
            }
            // 686: 可选日期进页时算一次 (读本地缓存日志; 不在 Form 热路径里现算)
            .onAppear {
                loadDayOptions()
                loadVerifyCode()          // 710
            }
            // 710: 范围一改, 指纹与二维码就重算一次 (口径跟着范围走, 旧结论随之作废)
            .onChange(of: range) { _, _ in loadVerifyCode() }
        }
    }

    private func loadDayOptions() {
        guard dayOpts.isEmpty else { return }
        let keys = ExportKit.records(mac: mac).map { $0.dayKey }.filter { $0 != "未知" }
        dayOpts = Array(Array(Set(keys)).sorted().suffix(14).reversed())
    }

    // 718 分享范围明示: 入口处文案明示"文件将离开本机"
    @ViewBuilder
    private var scopeSection: some View {
        Section {
            Picker("范围", selection: rangeBinding) {   // 701 范围
                Text("当月").tag(ExportRange.month)
                Text("全部记录").tag(ExportRange.all)
                Text("仅告警").tag(ExportRange.alarms)
                // 701: 暴露既有 .day 档 (原句要自定义日期; 最小形态先给"最新单日" +
                // 686 的「导出哪一天」选择器)。两者并不相通: .day 恒导最新一天 (filtered 不读 dayPick),
                // 686 选择器只驱动"单日长图"这一条出口且只列近 14 天 —— 别并成"任意单日"一句
                Text("最新单日").tag(ExportRange.day)
                ForEach(DB.members(), id: \.id) { m in
                    Text("仅 " + m.name).tag(ExportRange.member(m.id))
                }
            }
            .pickerStyle(.inline)
            // 2026-10-14 走查: 这里原来挂着 `.disabled(false)` —— 空修饰符, 既不会解除任何上级禁用
            // (SwiftUI 的 disabled 是沿树向下传播的, 子级写 false 压不住祖先的 true), 也不改任何行为。
            // 删掉, 免得下一个读代码的人以为"这里本来有个禁用条件, 后来被关掉了"。
            Text("导出与分享会让文件离开本机 (AirPrint/照片/聊天由你选)。生成过程纯本地, 不经过任何网络。")
                .vkFont(.footnote)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private var rangeBinding: Binding<ExportRange> {
        Binding(get: { range }, set: { range = $0 })
    }

    private var colsSection: some View {
        Section {
            ForEach(0..<6, id: \.self) { i in
                VariantToggle(ExportHeaders.zh[i], isOn: Binding(
                    get: { cols.get(i) },
                    set: { cols.set(i, $0); ExportCols.save(cols) }))
            }
        } header: {
            Text("列选择")   // 690 列选择
        } footer: {
            Text("勾选即含; 凭证/原始hex 列默认不含, 上次选择会沿用。")
                .vkFont(.caption)
        }
    }

    private var redactSection: some View {
        Section {
            VariantToggle("脱敏导出", isOn: $redact)   // 548 脱敏导出
            Text("脱敏与格式独立: 关时 JSON 含原始 hex、日志不掩码; 开时 JSON 的 hex 列留空、日志导出把连续数字掩码。")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var actionList: some View {
        Section {
            Button { startCSV() } label: { Label("CSV 标准导出", systemImage: "tablecells") }   // 683 标准导出
            Button { startJSON() } label: { Label("原始 JSON + hex", systemImage: "curlybraces") }   // 684 原始
            Button { startPDF() } label: { Label("月度 PDF 报告", systemImage: "doc.text") }   // 685 月度
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Label("运行日志", systemImage: "text.alignleft")   // 548 运行日志
                    .vkFont(.body)
                    .foregroundStyle(DS.Palette.text)
                Picker("格式", selection: $logFormat) {
                    Text("CSV").tag("csv")
                    Text("JSON").tag("json")
                    Text("纯文本").tag("txt")
                }
                .pickerStyle(.menu)
                .frame(minHeight: DS.Hit.min)
                Button("生成运行日志导出") { startRunLog() }
                    .vkFont(.subheadline)
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
            }
            // 703 直发: 配置了邮箱就走系统邮件 (附件与 CSV 导出同源); canSendMail=false 时回退 .eml 模板
            Button { sendByMail() } label: { Label("用系统邮件发送", systemImage: "envelope.open") }   // 703 用系统邮件发送
            Button { startEML() } label: { Label("邮件模板 .eml", systemImage: "envelope") }   // 703 邮件模板
        }
        .disabled(progress.running)
        Section {
            // 686 导出哪一天: 默认"最新一天" (与旧行为一致), 换日重导; 选项=有记录的最近 14 天
            if !dayOpts.isEmpty {
                Picker("导出哪一天", selection: $dayPick) {   // 686 导出哪一天
                    Text("最新一天").tag("")
                    ForEach(dayOpts, id: \.self) { d in Text(d).tag(d) }
                }
                .pickerStyle(.menu)
                .frame(minHeight: DS.Hit.min)
            }
            Button { startDayImages() } label: { Label("单日长图", systemImage: "photo.on.rectangle.angled") }   // 686/706 单日长图
            Button { startAlarmCard() } label: { Label("告警分享卡", systemImage: "exclamationmark.bubble") }   // 688/718 告警分享卡
            Button { startAlarmFactSheet() } label: { Label("告警事实单页 (PDF)", systemImage: "doc.text") }
            // 691 加密压缩导出: 口令线下告知, 本机不留 (与备份包同一套信封)
            SecureField("加密口令 (至少 6 位)", text: $zipPw)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .vkFont(.footnote)
            Button { startEncryptedZip() } label: { Label("加密压缩导出", systemImage: "lock.doc") }   // 691 加密压缩导出
                .disabled(zipPw.trimmingCharacters(in: .whitespaces).count < 6)
            Button { printMonthly() } label: { Label("打印月度记录", systemImage: "printer") }   // 687/701 打印月度记录
            Button { printOnePager() } label: { Label("告警一页纸", systemImage: "doc.text.magnifyingglass") }   // 717 告警一页纸
            Button { printOralCard() } label: { Label("口述卡打印", systemImage: "person.text.rectangle") }   // 478 口述卡打印
        }
        .disabled(progress.running)
    }

    /// 746 单条告警事实单页: 最新一条告警出 PDF (事实 / 原始报文 / 处置 / 签名栏), 用于物业沟通
    private func startAlarmFactSheet() {
        progress.start("正在生成告警事实单…") {   // 746 正在生成告警事实单
            let alarms = ExportKit.filtered(ExportKit.records(mac: self.mac), range: .alarms).reversed()
            guard let a = alarms.first else { return nil }
            let pdf = ExportKit.alarmFactSheetPDF(mac: self.mac, rec: a)
            guard !pdf.isEmpty else { return nil }
            let hex = SHA256.hash(data: pdf).map { String(format: "%02x", $0) }.joined()
            return ExportItem(kind: "pdf",
                              title: "告警事实单 " + a.typeName,
                              fileName: "锁管家_告警事实单_" + a.dayKey + ".pdf",
                              bytes: pdf, sha256: hex,
                              shaLabel: "单条告警 · 仅含本条数据",
                              previewText: "事实 / 原始报文 / 处置 / 签名栏 — 只含这一条告警。")
        } finish: { item, err in
            onDone(item, err)
        }
    }

    /// 688 告警分享卡: 最新一条告警渲染 9:16 卡片图, 进 doneSection 可 ShareLink 直发 (仅含本条数据, 718)
    private func startAlarmCard() {
        progress.start("正在生成告警卡…") {   // 688 正在生成告警卡
            let alarms = ExportKit.filtered(ExportKit.records(mac: self.mac), range: .alarms).reversed()
            guard let a = alarms.first else { return nil }
            let lockName = DB.keychain(self.mac).map { $0.name.isEmpty ? LockArchive.displayName($0) : $0.name } ?? self.mac
            guard let img = ExportKit.alarmCard(a, lockName: lockName),
                  let jpeg = img.jpegData(compressionQuality: 0.8) else { return nil }
            let hex = SHA256.hash(data: jpeg).map { String(format: "%02x", $0) }.joined()
            return ExportItem(kind: "png",
                              title: "告警卡 " + a.typeName,
                              fileName: "锁管家_告警卡_" + a.dayKey + ".jpg",
                              bytes: jpeg, sha256: hex,
                              shaLabel: "单条告警 · 仅含本条数据",
                              previewText: "卡片只含这一条告警, 不含其他成员与记录。",
                              images: [img])
        } finish: { item, err in
            onDone(item, err)
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        Section {
            HStack(spacing: DS.Space.s) {
                ProgressView()
                Text(progress.step.isEmpty ? "处理中…" : progress.step)
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("取消") { progress.cancel() }
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
            }
        }
    }

    // 719 导出完成反馈: 成功触感 + 路径; 失败说明原因
    @ViewBuilder
    private func doneSection(_ item: ExportItem) -> some View {
        Section {
            if lastSuccess {
                Label(item.fileName, systemImage: "checkmark.circle.fill")
                    .vkFont(.subheadline)
                    .foregroundStyle(DS.Palette.ok)
                    // 719 完成动效: 成功态出现时轻弹 (由调用处的 .animation(value: lastSuccess) 驱动)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            } else {
                Label(item.fileName, systemImage: "circle.fill")
                    .vkFont(.subheadline)
            }
            if !item.previewText.isEmpty {
                Text(item.previewText)
                    .vkFont(.caption.monospaced())
                    .foregroundStyle(DS.Palette.textSub)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(8)
            }
            Text("SHA-256: " + item.sha256)
                .vkFont(.caption.monospaced())
                .foregroundStyle(DS.Palette.textSub)
                .lineLimit(2)
            if !item.images.isEmpty {
                // 706 分页连图逐张预览
                ForEach(Array(item.images.enumerated()), id: \.offset) { i, img in
                    HStack(spacing: DS.Space.s) {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 80)
                            .clipped()
                        Text("第 \(i + 1)/\(item.images.count) 张")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                        Spacer(minLength: 0)
                    }
                }
            }
            HStack(spacing: DS.Space.s) {
                Button {
                    UIPasteboard.general.string = item.fullText
                    // 2026-10-15 走查: 不再一律报"完整" —— 长图/压缩包那几项没有文本正文, 复制出去的是
                    // 预览那几句, 说"完整文本"就是把截断的东西报成全部。
                    app.showToast(item.decodedBody == nil ? "已复制预览文本 · 这一项是图或包, 没有文本正文"
                                                          : "已复制完整文本")
                } label: {
                    Label("复制文本", systemImage: "doc.on.doc")   // 714 复制文本
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryActionStyle(fullWidth: false))
                .frame(minHeight: DS.Hit.min)
                if item.kind == "png" || item.kind == "pdf" || item.kind == "csv" {   // 712: CSV 也走同一预览 (openQL 已认得)
                    Button { openQL(item) } label: {
                        Label("预览", systemImage: "eye")   // 712 预览
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryActionStyle(fullWidth: false))
                    .frame(minHeight: DS.Hit.min)
                }
                shareButton(item)
            }
        } footer: {
            Text("分享/打印/存照片都会让数据离开本机; 生成本身纯本地。")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // ---------- 710 校验二维码区 (出码 + 扫码核对, 比对全程只读) ----------
    /// 710 取数走 records + filtered 这条既有读链 (与 683/686 同一口径), 出图交既有的
    /// BackupStudio.qrImage (BackupStudioKit.swift:364)。换范围或手动重算后旧结论作废:
    /// 上一次核对讲的是旧口径的事。
    private func loadVerifyCode() {
        let c = ReportVerify.code(mac: mac, range: range)
        verifyCode = c
        verifyQR = c.rows == 0 ? nil : BackupStudio.qrImage(c.payload)
        verifyVerdict = nil
    }
    /// 710 扫到的载荷原文 → 与本机当前数据重算的指纹比对; 原文只进这屏文案, 库里一个字节都不写。
    private func runVerify(_ text: String) {
        guard !text.isEmpty else { return }
        let v = ReportVerify.verify(text, currentMac: mac, currentRange: range)
        verifyVerdict = v
        app.showToast(v.title)
    }

    @ViewBuilder
    private var verifySection: some View {
        Section {
            if let c = verifyCode {
                if c.rows == 0 {
                    EmptyState(systemImage: "qrcode.viewfinder",
                               title: "这一范围还没有记录",
                               message: "指纹要由记录行算出来; 换上方「范围」那一档, 或等锁端记录同步到本机后再回这屏, 码就画得出来。扫码核对入口在下面。")
                } else {
                    if let img = verifyQR {
                        Image(uiImage: img)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(maxWidth: 220, maxHeight: 220)
                            // 无障碍: QR 是纯图形, VoiceOver 读不出模块 ⇒ 行数与摘要直接写进标签
                            .accessibilityLabel("报告校验二维码, " + String(c.rows) + " 行, 摘要 " + c.digest)   // 710 报告校验二维码
                        ShareLink(item: UIImageShareItem(img), preview: SharePreview("报告校验二维码")) {
                            Label("分享这张二维码", systemImage: "square.and.arrow.up")   // 710 分享这张二维码
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryActionStyle(fullWidth: false))
                        .frame(minHeight: DS.Hit.min)
                    } else {
                        // 710 CoreImage 这一趟没回图 (与 753 同一处置): 载荷原文顶同一份内容
                        Label("二维码这次没出成图, 下面那段载荷文本与码是同一份内容, 扫码核对照常用。",
                              systemImage: "qrcode")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    LabeledRow("行数", String(c.rows) + " 行")   // 710 行数
                    Text("摘要: " + c.digest)
                        .vkFont(.caption.monospaced())
                        .foregroundStyle(DS.Palette.textSub)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(c.payload)
                        .vkFont(.caption.monospaced())
                        .foregroundStyle(DS.Palette.textSub)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(ReportVerify.tierText(c))
                        .vkFont(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("这张码代表的是「本页上方所选范围的数据, 在本机重算出的指纹」(行数 + SHA-256 摘要)。"
                         + "扫码核对做的是: 把这份码记的指纹与本机当前数据重算的结果比一比 —— 报告文件分享出去后就不在本机了, 它自身的真伪在这一步之外。")
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: DS.Space.s) {
                    Button { showVerifyScan = true } label: {
                        Label("扫码核对", systemImage: "viewfinder")   // 710 扫码核对
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryActionStyle(fullWidth: false))
                    .frame(minHeight: DS.Hit.min)
                    Button("重算本机指纹") { loadVerifyCode() }
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.accentText)
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Rectangle())
                }
                if let v = verifyVerdict { verifyVerdictBlock(v) }
            } else {
                Text("正在按本机数据算指纹…")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
            }
        } header: {
            Text("报告校验二维码")   // 710 报告校验二维码
        } footer: {
            Text("摘要口径 (逐行六字段): 时间 / 类型 / 成员 / 是否告警 / 凭证词 / 锁端行键; 行序按报告两章出场序 (告警章在前、明细章在后)。"
                 + "原始 hex、级别字样、处置结论、生成时间与列选择都在口径之外 ⇒ 换勾选不改指纹。"
                 + "相机之外没有任何权限申请, 出图与比对全在本机, 不联网。")
                .vkFont(.caption2)
        }
    }

    /// 710 核对结论块: 标题 + 逐行说明, 图标与颜色双通道表达语义 (与 StatusPill 同一判据)
    @ViewBuilder
    private func verifyVerdictBlock(_ v: ReportVerify.Verdict) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Label(v.title, systemImage: v.icon)
                .vkFont(.subheadline, weight: .semibold)
                .foregroundStyle(v.tone.color)
            ForEach(v.lines, id: \.self) { line in
                Text(line)
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            StatusPill(text: "核对于 " + v.at, systemImage: v.icon, tone: v.tone)
        }
        .accessibilityElement(children: .combine)
    }

    private var pathSection: some View {
        Section {
            LabeledContent("文件位置", value: lastPath)   // 719 文件位置
                .vkFont(.caption)
                .textSelection(.enabled)
        }
    }
    /// 708 按 kind 走系统 UTType 的 ShareLink 表示; 709 卡片 = sharePreview (渐变封面图)。
    @ViewBuilder
    private func shareButton(_ item: ExportItem) -> some View {
        if item.kind == "eml" {
            // .eml 走复制文本 (系统邮件应用可读), 不进分享面板
            Text("邮件模板请直接复制内容, 粘贴进系统邮件或备忘录手动发送。")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        } else if item.kind == "csv" {
            ShareLink(item: ExportCSVFile(item: item), preview: item.sharePreview) {
                Label("分享", systemImage: "square.and.arrow.up")   // 708 分享
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryActionStyle(fullWidth: false))
            .frame(minHeight: DS.Hit.min)
        } else if item.kind == "json" {
            ShareLink(item: ExportJSONFile(item: item), preview: item.sharePreview) {
                Label("分享", systemImage: "square.and.arrow.up")   // 708 分享
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryActionStyle(fullWidth: false))
            .frame(minHeight: DS.Hit.min)
        } else if item.kind == "pdf" {
            ShareLink(item: ExportPDFFile(item: item), preview: item.sharePreview) {
                Label("分享", systemImage: "square.and.arrow.up")   // 708 分享
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryActionStyle(fullWidth: false))
            .frame(minHeight: DS.Hit.min)
        } else if item.kind == "png", let first = item.images.first {
            // 修饰符不能直接挂在 if/else 整体上 (Swift 里 `if … } else … } .buttonStyle(…)` 不成表达式) —— 本机没编译器，不赌，套一层 Group。
            Group {
            // 2026-10-15 走查: 这里原先只把 images.first 交出去 —— 单日超过三张容量时切得出第 2、3 张，
            // 而那几张除了在这一页看看没有任何出口：分享与落盘都只覆盖第 1 张。API 形状按 Apple 文档核过：
            // init(items:subject:message:preview:label:) (iOS 16 起)，items 要 RandomAccessCollection 且元素
            // Transferable，preview 是**逐元素**闭包 —— 不是照记忆拼的。只有一张时仍走单 item 那条，行为不变。
            if item.images.count > 1 {
                ShareLink(items: item.images.enumerated().map { i, img in
                            ExportImageFile(item: item, image: img,
                                            nameOverride: item.fileName.replacingOccurrences(of: ".jpg",
                                                    with: "-" + String(i + 1) + "of" + String(item.images.count) + ".jpg"))
                        },
                          preview: { _ in item.sharePreview }) {
                    Label("分享全部 " + String(item.images.count) + " 张", systemImage: "square.and.arrow.up")   // 708 分享
                        .frame(maxWidth: .infinity)
                }
            } else {
                ShareLink(item: ExportImageFile(item: item, image: first),
                          preview: item.sharePreview) {
                    Label("分享", systemImage: "square.and.arrow.up")   // 708 分享
                        .frame(maxWidth: .infinity)
                }
            }
            }
            .buttonStyle(SecondaryActionStyle(fullWidth: false))
            .frame(minHeight: DS.Hit.min)
        } else {
            ShareLink(item: ExportTextFile(item: item), preview: item.sharePreview) {
                Label("分享", systemImage: "square.and.arrow.up")   // 708 分享
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryActionStyle(fullWidth: false))
            .frame(minHeight: DS.Hit.min)
        }
    }

    // ---------- 各导出动作 (692: 全部经 ExportProgress 生成, 可取消) ----------
    /// 719 完成反馈: 成功触感/失败触感已由 progress.start 触发, 这里补路径与 Toast
    private func onDone(_ item: ExportItem?, _ err: String) {
        if let item {
            // 2026-10-14: 写盘失败也报"已生成"是假成功; 内容仍可分享, 但如实告知没落盘。
            if let url = item.writeLocal() {
                lastPath = url.path
                lastSuccess = true
                app.showToast("已生成 \(item.fileName)")   // 719 已生成
            } else {
                lastSuccess = true
                app.showToast("已生成 \(item.fileName) — 但写入本地文件失败, 可直接分享")
            }
        } else if !err.isEmpty {
            lastSuccess = false
            app.showToast(err)
        }
    }

    // 691 加密压缩导出的口令 (只在本页内存里, 不落盘)
    @State private var zipPw = ""

    /// 691 加密压缩导出: 记录 CSV + 说明 → store-only ZIP → 备份同源信封 (PBKDF2 + AES-128-CBC + HMAC)。
    /// 写完先做**往返自检** (自家 ZipKit.parse 读回 + 逐条 CRC), 通过才加密 —— 读侧就是判据。
    private func startEncryptedZip() {
        let pw = zipPw.trimmingCharacters(in: .whitespaces)
        guard pw.count >= 6 else { app.showToast("口令至少 6 位"); return }   // 691 口令至少
        progress.start("正在打包并加密…") {   // 691 正在打包并加密
            let recs = ExportKit.filtered(ExportKit.records(mac: self.mac), range: self.range)
            guard !recs.isEmpty else { return nil }
            let build = ExportKit.buildCSV(recs: recs, cols: self.cols)
            let kc = DB.keychain(self.mac)
            let lockName = kc.map { $0.name.isEmpty ? LockArchive.displayName($0) : $0.name } ?? self.mac
            let stamp = stampTag()
            let note = "离线锁管家 加密导出\n锁: \(lockName)\n范围: \(self.range.label)\n行数: \(recs.count)\n"   // 691 离线锁管家
                + "生成: \(Date().formatted(date: .abbreviated, time: .standard))\n\n"
                + "本文件是 aes-128-cbc+hmac-sha256 信封, 内含一个 zip (store 方式); 用同款 App 的备份口令流程解开即可。"
            let entries: [(name: String, data: [UInt8])] = [
                ("锁管家_记录_" + lockName + "_" + stamp + ".csv", Array(build.data)),
                ("说明.txt", Array(note.utf8)),
            ]
            let zip = ZipKit.write(entries: entries)
            guard let back = try? ZipKit.parse(zip), back.count == entries.count, back.allSatisfy({ $0.crcOk }) else {
                return nil   // 往返自检不过就不加密 —— 宁可不给, 不给一个解不开的包
            }
            guard let env = try? CryptoBox.encryptBytes(zip, password: pw) else { return nil }
            let data = Data(env.utf8)
            let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return ExportItem(kind: "json",
                              title: "加密压缩包",
                              fileName: "锁管家_加密导出_" + lockName + "_" + stamp + ".zip.enc",
                              bytes: data, sha256: hex,
                              shaLabel: "AES-128-CBC + HMAC-SHA256 (与备份包同源)",
                              previewText: "内含记录 CSV 与说明; 口令线下告知, 本机不留。")
        } finish: { item, err in
            onDone(item, err)
        }
    }

    private func startCSV() {
        progress.start("正在生成 CSV…") {   // 683 正在生成
            let recs = ExportKit.filtered(ExportKit.records(mac: self.mac), range: self.range)
            guard !recs.isEmpty else { return nil }
            let build = ExportKit.buildCSV(recs: recs, cols: self.cols)
            let hex = SHA256.hash(data: build.data).map { String(format: "%02x", $0) }.joined()
            // 693 CSV 文件名带锁名 (与 :532 报告页同一取名规范), 多锁导出不再同名
            let kc = DB.keychain(self.mac)
            let lockName = kc.map { $0.name.isEmpty ? LockArchive.displayName($0) : $0.name } ?? self.mac
            return ExportItem(kind: "csv",
                              title: "记录 " + self.range.label,
                              fileName: "锁管家_记录_" + lockName + "_" + stampTag() + "_" + self.range.label + ".csv",
                              bytes: build.data, sha256: hex,
                              shaLabel: "CSV · \(build.rowCount) 行 · 转义 \(build.escapedRows) 行",   // 705 转义
                              previewText: build.preview3,
                              scopeNote: "含 " + String(build.rowCount) + " 行, 离开本机后不可撤回")
        } finish: { item, err in
            onDone(item, err)
        }
    }
    private func startJSON() {
        progress.start("正在生成 JSON…") {   // 684 正在生成
            // 388 敏感操作留痕: 原始 JSON 含协议 hex, 记账进 SensitiveLedger
            SensitiveLedger().record("导出", target: "原始 JSON " + self.range.label)
            let recs = ExportKit.filtered(ExportKit.records(mac: self.mac), range: self.range)
            let data = ExportKit.rawJSON(mac: self.mac, recs: recs, redactHex: self.redact)
            let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return ExportItem(kind: "json",
                              title: "原始 JSON " + self.range.label,
                              fileName: "锁管家_原始_" + stampTag() + "_" + self.range.label + ".json",
                              bytes: data, sha256: hex,
                              shaLabel: "JSON · \(recs.count) 条" + (self.redact ? " · 已脱敏" : ""),
                              previewText: self.redact
                                ? "脱敏导出: hex 列与帧 hex 段都留空。"
                                : "帧 hex 取自诊断原始收发日志 (需开「记录原始收发 hex」，未开则该段为空)。")
        } finish: { item, err in
            onDone(item, err)
        }
    }

    private func startPDF() {
        progress.start("正在排版 PDF…") {   // 685 正在排版
            let recs = ExportKit.filtered(ExportKit.records(mac: self.mac), range: self.range)
            guard !recs.isEmpty else { return nil }
            let memberName = self.memberLabel()
            guard let build = ExportKit.buildReport(mac: self.mac, recs: recs, cols: self.cols,
                                                    rangeLabel: self.range.label, memberName: memberName),
                  !build.pdfData.isEmpty else { return nil }
            let hex = SHA256.hash(data: build.pdfData).map { String(format: "%02x", $0) }.joined()
            return ExportItem(kind: "pdf",
                              title: "月度报告" + (memberName.map { " 仅 " + $0 } ?? ""),
                              fileName: "锁管家_报告_" + stampTag() + ".pdf",
                              bytes: build.pdfData, sha256: hex,
                              shaLabel: "PDF · \(build.rows) 行",
                              previewText: String(build.text.prefix(500)),
                              scopeNote: "报告含全部所选范围记录, 离开本机后不可撤回")
        } finish: { item, err in
            onDone(item, err)
        }
    }
    private func memberLabel() -> String? {
        if case .member(let mid) = range { return DB.member(mid)?.name }
        return nil
    }

    private func startRunLog() {
        progress.start("正在生成运行日志…") {   // 548 正在生成运行日志
            let data = ExportKit.runLogData(format: self.logFormat, redact: self.redact)
            let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let ext = self.logFormat == "txt" ? "txt" : self.logFormat
            return ExportItem(kind: ext,
                              title: "运行日志",
                              fileName: "锁管家_日志_" + stampTag() + "." + ext,
                              bytes: data, sha256: hex,
                              shaLabel: "App 运行日志 · " + String(DiagLogs.all().count) + " 条 · " + self.logFormat + (self.redact ? " · 已脱敏" : ""),
                              previewText: String(String(decoding: data, as: UTF8.self).prefix(300)))
        } finish: { item, err in
            onDone(item, err)
        }
    }

    /// 703 系统邮件直发: 装配 MFMailComposeViewController (主题/正文/CSV 附件), 发送动作交给系统邮件。
    /// 附件数据与 CSV 导出同源 (buildCSV), 不复制生成逻辑; 未配置邮箱时回退既有 .eml 降级路径。
    @MainActor
    private func sendByMail() {
        let recs = ExportKit.filtered(ExportKit.records(mac: mac), range: range)
        guard !recs.isEmpty else { app.showToast("无记录可发送"); return }
        guard MFMailComposeViewController.canSendMail(), let host = UIApplication.topViewController() else {
            app.showToast("本机未配置邮箱账号, 已改用 .eml 模板")
            startEML()
            return
        }
        let build = ExportKit.buildCSV(recs: recs, cols: cols)
        let lockName = DB.keychain(mac).map { $0.name.isEmpty ? LockArchive.displayName($0) : $0.name } ?? mac
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = ExportKit.MailDismisser.shared
        vc.setSubject("「离线锁管家」" + range.label + " 开门记录")
        vc.setMessageBody("请查收附件 (共 " + String(build.rowCount) + " 行)。导出在本机完成, 发送动作由系统邮件执行。", isHTML: false)
        vc.addAttachmentData(build.data, mimeType: "text/csv", fileName: "锁管家_记录_" + lockName + "_" + range.label + ".csv")
        host.present(vc, animated: true)
    }

    private func startEML() {
        progress.start("正在生成邮件模板…") {   // 703 正在生成邮件模板
            let recs = ExportKit.filtered(ExportKit.records(mac: self.mac), range: self.range)
            guard !recs.isEmpty else { return nil }
            return ExportKit.emailTemplate(mac: self.mac, recs: recs, cols: self.cols)
        } finish: { item, err in
            onDone(item, err)
        }
    }

    private func startDayImages() {
        progress.start("正在生成长图…") {   // 686 正在生成长图
            let all = ExportKit.records(mac: self.mac)
            // 686: 指定哪天就导哪天 (此前恒导最新一天); 空 = 最新
            let day = self.dayPick.isEmpty ? ExportKit.latestDayKey(all) : self.dayPick
            guard !day.isEmpty else { return nil }
            let recs = all.filter { $0.dayKey == day }
            guard !recs.isEmpty else { return nil }
            let pages = ExportItem.dayPages(recs: recs, mac: self.mac, day: day)
            guard let first = pages.first, let jpeg = first.jpegData(compressionQuality: 0.8) else { return nil }
            let hex = SHA256.hash(data: jpeg).map { String(format: "%02x", $0) }.joined()
            return ExportItem(kind: "png",
                              title: "单日 " + day,
                              fileName: "锁管家_单日_" + day + ".jpg",
                              bytes: jpeg, sha256: hex,
                              // 2026-10-15 走查: 这一行原先写「N 条 · 切 M 张」, 而 `bytes`、SHA、分享与落盘
                              // 覆盖的只是**第 1 张** (ShareLink 走的是 item.images.first) —— 第 2、3 张只能在
                              // 这一页里看, 没有任何出口。说了"切 3 张"却不给那 3 张, 就是把承诺写成事实。
                              // 现在说的是这份文件真正包含的东西; 当日条数超出三张容量时, 留在图里的是最近那段。
                              shaLabel: "长图 · 当日 \(recs.count) 条 · 出图 \(pages.count) 张",
                              previewText: pages.count > 1
                                ? "已按屏高切 \(pages.count) 张连图 (上限 3 张)。\n分享与写入本地文件都会带上全部张数, 文件名按 -序号of张数 区分。"
                                : "",   // 706 已按屏高切
                              images: pages)
        } finish: { item, err in
            onDone(item, err)
        }
    }

    // ---------- 打印 (687/701/717/478) ----------
    @MainActor
    private func printMonthly() {
        guard let host = hostView() else { app.showToast("打印需要前台界面"); return }
        let recs = ExportKit.filtered(ExportKit.records(mac: mac), range: range)
        let memberName = memberLabel()
        guard let build = ExportKit.buildReport(mac: mac, recs: recs, cols: cols, rangeLabel: range.label, memberName: memberName),
              !build.pdfData.isEmpty else {
            app.showToast("无记录可打印")
            return
        }
        ExportKit.presentPrint(pdfData: build.pdfData, jobName: "锁管家月度记录", from: host)
    }
    @MainActor
    private func printOnePager() {
        guard let host = hostView() else { return }
        let recs = ExportKit.records(mac: mac)
        let data = ExportKit.alarmOnePagerPDF(mac: mac, recs: recs)
        ExportKit.presentPrint(pdfData: data, jobName: "告警一页纸", from: host)
    }
    @MainActor
    private func printOralCard() {
        guard let host = hostView() else { return }
        let recs = ExportKit.records(mac: mac)
        let data = ExportKit.oralCardPDF(mac: mac, recs: recs)
        ExportKit.presentPrint(pdfData: data, jobName: "口述卡", from: host)
    }
    private func hostView() -> UIView? {
        // 复用 CredentialsView 的 UIApplication.topViewController() (打印面板需挂前台窗口)
        UIApplication.topViewController()?.view
    }

    private func openQL(_ item: ExportItem) {
        guard let url = item.writeLocal() else {
            app.showToast("无法生成预览文件")
            return
        }
        quickLook = url
        showQL = true
    }

    private func stampTag() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyyMM"; f.timeZone = .current; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }
}

// 712 QuickLook 包装 (iOS 26.5: QLPreviewController + QLPreviewItem)
struct QLPreviewView: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let c = QLPreviewController()
        c.dataSource = context.coordinator
        context.coordinator.ctrl = c
        return c
    }
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        weak var ctrl: QLPreviewController?
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            // URL 本身就是 QLPreviewItem (NSURL 遵循该协议); 旧写法调的 urlPreviewItem 不存在
            url as NSURL
        }
    }
}
