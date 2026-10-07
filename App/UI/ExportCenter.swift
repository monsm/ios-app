// 包12 导出·打印·分享 — 全离线, 数据只出本机一次且每次明示 (718)
// 收录 478/548/683-722 (⚠703 降级 .eml 文本, 710/711/713 见 DEFERRED.md, 203 舍弃)
// 纪律: 颜色只经 DS 令牌; 导出文件 UTF-8+BOM (中文 Excel 友好); 打印走 UIPrintInteractionController;
//       校验行 SHA-256 复用 CryptoKit (722); 归属只走 Attribution 可证明链, 推不出留空 (CAPABILITY §3)。
import SwiftUI
import UIKit
import CryptoKit
import UniformTypeIdentifiers
import PDFKit
import QuickLook
import LinkPresentation

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
        case .member(let n): return "仅 " + n
        }
    }
}

// 690 列选择: 上次选择沿用到 kf_cred_export_cols (690 原意)
struct ExportCols {
    var time = true, type = true, member = true, alarm = true, cred = false, hex = false
    static let savedKey = "kf_cred_export_cols"
    var all = [time, type, member, alarm, cred, hex]
    func get(_ i: Int) -> Bool { all[i] }
    func set(_ i: Int, _ on: Bool) {
        switch i { case 0: time = on; case 1: type = on; case 2: member = on; case 3: alarm = on; case 4: cred = on; default: hex = on }
    }
    var onIndices: [Int] { (0..<6).filter { all[$0] } }
    static func load() -> ExportCols {
        guard let s = DB.store.getString(savedKey) else { return .init() }
        var c = ExportCols()
        for i in s.indices where i < 6 { c.set(i, s[s.index(s.startIndex, offsetBy: i)] == "1") }
        return c
    }
    static func save(_ c: ExportCols) { DB.store.set(savedKey, c.all.map { $0 ? "1" : "0" }.joined()) }
}

// 705 CSV 转义 (RFC 4180): 含 " , 换行 的字段加引号并双引号转义
enum CSVKit {
    static func escape(_ f: String) -> String {
        if f.contains("\"") || f.contains(",") || f.contains("\n") || f.contains("\r") {
            return "\"" + f.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return f
    }
    /// 705 预检: 导出前扫描哪些字段会触发转义 (预览前 3 行防 Excel 错列)
    static func needEscaping(_ f: String) -> Bool {
        f.contains("\"") || f.contains(",") || f.contains("\n") || f.contains("\r")
    }
}

// 721 双语列头: 中文主列头 + 英文 code 注释行 (便于脚本二次处理)
enum ExportHeaders {
    static let zh = ["时间", "类型", "成员", "告警", "凭证", "原始hex"]
    static let en = ["time", "type", "member", "alarm", "cred", "hex"]
}

// 707 报告语言跟随: 项目仅中文, 键位预留 (设置可写 "zh-Hant"), 当前全部中文中立文案
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
    var fullText: String {
        let body = previewText.isEmpty ? String(decoding: bytes, as: UTF8.self) : previewText
        return body + "\n── 校验 ──\nSHA-256: \(sha256)\n\(shaLabel)\n生成: " + ExportKit.stamp.string(from: Date())
    }

    /// 719/712 写进 Caches/exports (不被系统早清), 返回路径供 Toast 展示
    @discardableResult
    func writeLocal() -> URL? {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(fileName)
        guard (try? bytes.write(to: url)) != nil else { return nil }
        return url
    }

    // 708/709: 共享表示 = 下方各 Transferable struct + linkMetadata() 卡片
}

// 708 原生分享: 按 kind 走系统 UTType 的 Transferable 表示 (csv/json/pdf/图片/文本),
// 709 分享卡片: 聊天内预览 = sharePreview 的渐变封面图 (LPLinkMetadata 见 linkMetadata(),
// 供将来自定义 UIActivityController 路径复用 — SwiftUI 无公开挂接点)。
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
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: UTType.jpeg) {
            $0.image.jpegData(compressionQuality: 0.8) ?? Data()
        }
        .suggestedFileName { $0.item.fileName }
    }
}
struct ExportTextFile: Transferable {
    let item: ExportItem
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: UTType.plainText) { $0.item.bytes }
            .suggestedFileName { $0.item.fileName }
    }
}

extension ExportItem {
    func linkMetadata() -> LPLinkMetadata {
        let m = LPLinkMetadata()
        m.title = title
        m.subtitle = shaLabel + " · 离线锁管家"
        m.keywords = ["离线锁管家", kind]
        if let img = ExportKit.coverImage(item: self, w: 480) {
            let prov = NSItemProvider()
            prov.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
                completion(img.jpegData(compressionQuality: 0.85), nil)
            }
            m.thumbnailProvider = prov
        }
        return m
    }
}

extension ExportItem {
    var sharePreview: SharePreview {
        SharePreview(title, image: ExportKit.coverImage(item: self, w: 480))
    }
}

// 706 长图分页切割: 按屏高上限切 ≤3 张连图 (适配聊天窗口逐张发送)
extension ExportItem {
    static func dayPages(recs: [ExportRecord], mac: String, day: String) -> [UIImage] {
        let w: CGFloat = 720
        let rowH: CGFloat = 44
        let headH: CGFloat = 110
        let perPage = max(Int((844 * 2.2) / rowH), 1)   // 屏高 2.2 倍为一张的上限
        var pages = [UIImage]()
        var i = 0
        var p = 0
        while i < recs.count && pages.count < 3 {
            let chunk = Array(recs[i ..< min(i + perPage, recs.count)])
            // 706: 续张带紧凑表头 (渐变头占位 headH/2), 聊天逐张发不丢锁名上下文
            let header = p == 0 ? 0 : headH / 2
            let h = header + CGFloat(chunk.count) * rowH + 56
            if let img = ExportKit.renderDayPage(recs: chunk, mac: mac, day: day,
                                                 top: header, h: h, w: w, headH: header, rowH: rowH) {
                pages.append(img)
            }
            i += perPage
            p += 1
        }
        return pages
    }
}

// ================= 导出进度 (692 生成可取消, 不阻塞 UI) =================
final class ExportProgress: ObservableObject {
    @Published var running = false
    @Published var step = ""
    @Published var done: ExportItem?
    @Published var failed = ""
    private var task: Task<Void, Never>?

    /// 692 生成放后台 TaskGroup (可取消, UI 不阻塞); 719 结果触感 + finish 主线程回传
    func start(_ label: String,
               work: @escaping () -> ExportItem?,
               finish: @escaping (ExportItem?, String) -> Void) {
        task?.cancel()
        running = true; done = nil; failed = ""
        task = Task { [weak self] in
            guard let self else { return }
            await MainActor.run { self.step = label; self.running = true }
            // 生成放后台线程 (UI 不阻塞); 取消时拦"收尾写回" (692)
            let child = Task.detached(priority: .userInitiated) { work() }
            let item = await child.value
            let cancelled = Task.isCancelled || child.isCancelled
            await MainActor.run {
                self.running = false
                self.step = ""
                if let v = item {
                    self.done = v
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    finish(v, "")
                } else {
                    self.failed = cancelled ? "已取消" : "生成失败"
                    if !cancelled { UINotificationFeedbackGenerator().notificationOccurred(.error) }
                    finish(nil, self.failed)
                }
            }
        }
    }
    func cancel() { task?.cancel() }
}

// ================= 核心生成器 =================
enum ExportKit {
    static let stamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; f.timeZone = TimeZone.current; return f
    }()
    static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; f.timeZone = TimeZone.current; return f
    }()

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
            var dayKey = e.lockTimeStr.count >= 10 ? String(e.lockTimeStr.prefix(10)) : "未知"
            let alarm = e.type == 6 || e.type == 7 || e.type == 10 || e.type == 13 || e.type == 224
            out.append(ExportRecord(
                time: e.lockTimeStr.isEmpty ? "时间未知" : e.lockTimeStr,
                typeName: e.typeName,
                member: c.who.map { DB.member($0)?.name ?? "" } ?? "",
                credWord: c.kind.map { Attribution.words[$0] ?? "" } ?? "",
                isAlarm: alarm,
                hex: e.body,
                dayKey: dayKey))
        }
        return out.reversed() // 时间正序, 导出可读
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
            let comps = Calendar.current.dateComponents([.year, .month], from: Date())
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
        let digest = SHA256.hash(data: Data(ExportItem.bom + body.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let tail = "\n# SHA-256(正文): \(hex)\n# 行数: \(recs.count) · 生成: \(stamp.string(from: Date()))\n"
        let finalText = ExportItem.bom + body + tail
        return CSVBuild(
            data: Data(finalText.utf8),
            rowCount: recs.count,
            escapedRows: escapedRows,
            preview3: String(lines.prefix(3).joined(separator: "\n").utf8.prefix(400)))
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
        return Data(ExportItem.bom + String(decoding: d, as: UTF8).utf8)
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
            return Data(ExportItem.bom + String(decoding: d, as: UTF8).utf8)
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

        var text = ReportTexts.t("summarySection") + "\n"
        text += threeSentence(recs: recs, mac: mac) + "\n\n"
        text += ReportTexts.t("alarmSection") + "\n"
        if alarms.isEmpty {
            text += "本期无告警。\n\n"
        } else {
            for a in alarms { text += "· " + a.time + " " + a.typeName + (a.member.isEmpty ? "" : " " + a.member) + "\n" }
            text += "\n"
        }
        text += ReportTexts.t("detailSection") + "\n"
        for r in others {
            var line = "· " + r.time + " " + r.typeName
            if !r.member.isEmpty { line += " " + r.member }
            text += line + "\n"
        }
        text += "\n" + integrity(text, rows: recs.count) + "\n"

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        let pdf = renderer.pdfData { ctx in
            // ---- 页 1: 矢量封面 (696 渐变封条 + 统计区间 + 生成时间, 无图片资源) ----
            let cg = ctx.cgContext
            let heroA = UIColor(DS.Palette.themed("heroA"))
            let heroB = UIColor(DS.Palette.themed("heroB"))
            PDFText.gradient(cg, CGRect(x: 0, y: 0, width: 595, height: 150), [heroA, heroB])
            PDFText.line(cg, "离线锁管家", font: .semibold, size: 24, x: 36, y: 34, color: .white, pageW: 595)
            PDFText.line(cg, "月份: " + rangeLabel + " · 锁: " + lockName, font: .regular, size: 12, x: 36, y: 92, color: UIColor.white.withAlphaComponent(0.85), pageW: 595)
            PDFText.line(cg, "生成: " + stamp.string(from: Date()) + " · 纯本地生成", font: .regular, size: 10, x: 36, y: 116, color: UIColor.white.withAlphaComponent(0.75), pageW: 595)
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
                PDFText.line(cg, "本报告区间: " + rangeLabel, font: .regular, size: 10, x: 44, y: y, color: .darkGray, pageW: 595)
            }
            ctx.endPDFPage()
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
            PDFText.line(cg, ReportTexts.t("footer") + " · " + rangeLabel + " · " + lockName,
                         font: .regular, size: 9, x: 36, y: 28, color: .lightGray, pageW: 460)
            PDFText.line(cg, "第 2 页 · " + ReportTexts.t("footer"),
                         font: .regular, size: 9, x: 36, y: 812, color: .lightGray, pageW: 520)
            ctx.endPDFPage()
            // ---- 正文页: 告警章(697 置前) + 逐日明细, 702 页眉页脚 ----
            var pageIdx = 1
            func startPageHeader(_ title: String) {
                pageIdx += 1
                // 页眉回显筛选条件
                PDFText.line(cg, ReportTexts.t("footer") + " · " + rangeLabel + " · " + lockName,
                             font: .regular, size: 9, x: 36, y: 28, color: .lightGray, pageW: 460)
                PDFText.line(cg, title, font: .semibold, size: 15, x: 36, y: 48, color: .black, pageW: 595)
            }
            func footerPage() {
                PDFText.line(cg, "第 " + String(pageIdx) + " 页 · " + ReportTexts.t("footer"),
                             font: .regular, size: 9, x: 36, y: 812, color: .lightGray, pageW: 520)
            }
            var cursor = 80.0
            func startTablePage(_ title: String, breakPage: Bool = false) {
                if breakPage {
                    footerPage(); ctx.endPDFPage()
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
                    footerPage(); ctx.endPDFPage()
                    startPageHeader("续")
                    cursor = 70
                } else { cursor = max(cursor, 70) }
                let use = cols.onIndices.isEmpty ? [0, 1, 3] : cols.onIndices
                let fields = [r.time, r.typeName, r.member,
                              r.isAlarm ? r.typeName : "",
                              r.credWord.isEmpty ? "" : r.credWord + (r.member.isEmpty ? "·未归属" : "·" + r.member),
                              r.hex.isEmpty ? "" : String(r.hex.prefix(12))]
                let rowText = use.map { fields[$0] }.joined(separator: "  |  ")
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
            // 明细章 (本页满则切新页)
            startTablePage(ReportTexts.t("detailSection"), breakPage: cursor > 740)
            for r in others { emitRow(r) }
            // 722 尾页校验
            if cursor > 770 { footerPage(); ctx.endPDFPage() }
            footerPage()
            ctx.endPDFPage()
        }
        guard !pdf.isEmpty else { return nil }
        return ReportBuild(pdfData: pdf, text: text, rows: recs.count)
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
        var m = [String: Int]()
        for r in recs where !r.isAlarm && !r.member.isEmpty { m[r.member, default: 0] += 1 }
        if let top = m.sorted(by: { $0.value > $1.value }).first { who = top.key }
        var out = [String]()
        out.append("本期开门 \(opens) 次" + (who.isEmpty ? "" : "，最活跃: 约 \(who)"))
        out.append("告警 \(alarms) 条" + (alarms == 0 ? "，记录安静" : "（见置前章节）"))
        out.append("凭证变动 \(cred) 条（版本历史台账口径）")
        return out
    }

    /// 699 矢量图表: 时段分布条形 (直接画进 PDF 上下文, 缩放不糊)
    static func drawHourBars(_ cg: CGContext, recs: [ExportRecord], x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, accent: UIColor) {
        var hs = [Int: Int]()
        for r in recs where !$0.isAlarm {
            if let d = timeFmt.date(from: r.time) {
                hs[Calendar.current.component(.hour, from: d), default: 0] += 1
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

    // ---------- 688 告警分享卡 (9:16 渐变卡, ImageRenderer 出图) ----------
    static func alarmCard(_ r: ExportRecord, lockName: String) -> UIImage? {
        let card = AlarmShareCardView(name: lockName, rec: r)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        return renderer.uiImage
    }

    // ---------- 718 单条记录分享卡 (明示仅含本条数据) ----------
    static func recordCard(_ r: ExportRecord, lockName: String) -> UIImage? {
        let card = RecordShareCardView(name: lockName, rec: r)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        return renderer.uiImage
    }

    // ---------- 478 口述卡 (大字排版 PDF, 供不用智能手机的老人贴门) ----------
    static func oralCardPDF(mac: String, recs: [ExportRecord]) -> Data {
        let lockName = DB.keychain(mac).map { $0.name.isEmpty ? LockArchive.displayName($0) : $0.name } ?? mac
        let alarms = recs.filter { $0.isAlarm }.count
        let last = recs.last.map { $0.time + " " + $0.typeName } ?? "无记录"
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        let data = renderer.pdfData { ctx in
            let cg = ctx.cgContext
            PDFText.line(cg, "请告诉我 — 口述卡", font: .semibold, size: 30, x: 56, y: 90, color: .black, pageW: 480)
            PDFText.line(cg, lockName, font: .semibold, size: 44, x: 56, y: 150, color: .black, pageW: 480)
            PDFText.line(cg, "最近一次: " + last, font: .regular, size: 22, x: 56, y: 250, color: .darkGray, pageW: 480)
            PDFText.line(cg, "本月告警: " + String(alarms) + " 条", font: .regular, size: 22,
                         x: 56, y: 296, color: alarms > 0 ? UIColor(DS.Palette.danger) : .darkGray, pageW: 480)
            PDFText.line(cg, "应急电话 (手填):", font: .regular, size: 22, x: 56, y: 380, color: .black, pageW: 480)
            PDFText.hairline(cg, y: 430); PDFText.hairline(cg, y: 500)
            PDFText.line(cg, "备用钥匙位置 (手填):", font: .regular, size: 22, x: 56, y: 540, color: .black, pageW: 480)
            PDFText.hairline(cg, y: 590)
            PDFText.line(cg, "离线锁管家 · 本地生成 · 数据未经网络", font: .regular, size: 11, x: 56, y: 780, color: .lightGray, pageW: 480)
            ctx.endPDFPage()
        }
        return data
    }

    // ---------- 717 告警一页纸 (当前预警配置 + 最近告警 + 手填栏) ----------
    static func alarmOnePagerPDF(mac: String, recs: [ExportRecord]) -> Data {
        let lockName = DB.keychain(mac).map { $0.name.isEmpty ? LockArchive.displayName($0) : $0.name } ?? mac
        let alarms = recs.filter { $0.isAlarm }
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
            for a in alarms.prefix(10) {
                PDFText.line(cg, a.time + "   " + a.typeName + (a.member.isEmpty ? "" : " · " + a.member),
                             font: .regular, size: 12, x: 44, y: y, color: UIColor(DS.Palette.danger), pageW: 500)
                y += 20
            }
            y += 40
            PDFText.line(cg, "应急电话 (手填): ______________________", font: .regular, size: 18, x: 36, y: y, color: .black, pageW: 520)
            y += 56
            PDFText.line(cg, "物业 / 厂家热线 (手填): ______________________", font: .regular, size: 18, x: 36, y: y, color: .black, pageW: 520)
            ctx.endPDFPage()
        }
        return data
    }

    // ---------- 703 降级: 生成 .eml 文本 (主题预填 + CSV base64 附件), 手动交给系统邮件 ----------
    static func emailTemplate(mac: String, recs: [ExportRecord], cols: ExportCols) -> ExportItem? {
        let build = buildCSV(recs: recs, cols: cols)
        let rangeLabel = ExportRange.month.label
        let fileName = "锁管家_记录_" + rangeLabel + ".csv"
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
            PDFText.line(cg, item.shaLabel, font: .regular, size: w * 0.06, x: w * 0.1, y: h - w * 0.14, color: UIColor.white.withAlphaComponent(0.75), pageW: w)
        }
    }

    // ---------- 单日长图渲染 (686 表头水印 + 行; 706 每张连图独立成页, 表头随行切) ----------
    /// 706 分页: top>0 时页顶带渐变表头 (续张); top==0 首张表头省掉 (总图拼接时顶部即封面)
    static func renderDayPage(recs: [ExportRecord], mac: String, day: String,
                              top: CGFloat, h: CGFloat, w: CGFloat, headH: CGFloat, rowH: CGFloat) -> UIImage? {
        guard h > 60, !recs.isEmpty else { return nil }
        let lockName = DB.keychain(mac).map { $0.name.isEmpty ? LockArchive.displayName($0) : $0.name } ?? mac
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 2
        let headOffset: CGFloat = top == 0 ? 0 : headH   // 首张无表头, 续张带表头 (聊天逐张发不丢上下文)
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { ctx in
            let cg = ctx.cgContext
            UIColor.white.setFill()
            cg.fill(CGRect(x: 0, y: 0, width: w, height: h))
            if top > 0 {
                PDFText.gradient(cg, CGRect(x: 0, y: 0, width: w, height: headH),
                                 [UIColor(DS.Palette.themed("heroA")), UIColor(DS.Palette.themed("heroB"))])
                let sub = day + " · 离线锁管家 (续)"
                PDFText.line(cg, sub, font: .regular, size: 13, x: 24, y: 44, color: UIColor.white.withAlphaComponent(0.9), pageW: w - 48)
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

    // ---------- 687/701 打印: UIPrintInteractionController + 自定义 UIPrintFormatter ----------
    final class OneShotFormatter: UIPrintFormatter {
        var data: Data
        init(data: Data) {
            self.data = data
            super.init()
        }
        required init() { fatalError() }
        private var pages: [PDFPage] { PDFDocument(data: data)?.pages ?? [] }
        private var pageIndex = 0
        override func printPage(_ page: Int, in printPageRange: UIPrintPageRange) -> Bool {
            page < pages.count
        }
        override func size(for actualPageSize: CGSize) -> CGSize { actualPageSize }
        /// 打印控制器逐页调用 draw; 用页序计数取对应 PDF 页 (702 分页打印不重叠)
        override func draw(in printPage: CGRect) {
            let ps = pages
            guard pageIndex < ps.count else { return }
            ps[pageIndex].draw(in: printPage)
            pageIndex += 1
        }
        override func reset() {
            pageIndex = 0
            super.reset()
        }
    }

    @MainActor
    static func presentPrint(pdfData: Data, jobName: String, from view: UIView) {
        let formatter = OneShotFormatter(data: pdfData)
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = jobName
        guard let controller = UIPrintInteractionController.shared else { return }
        controller.printFormatter = formatter
        controller.printInfo = info
        controller.present(animated: true, from: view.bounds, in: view)
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
            ns.draw(with: CGRect(x: x, y: y, width: pageW, height: size * 4), options: [.usesLineFragmentOrigin, .usesFontLeading])
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

// ================= 卡片视图 (ImageRenderer 渲染; 固定尺寸, 不参与动态字体 — 分享卡按设计固定) =================
struct AlarmShareCardView: View {
    let name: String
    let rec: ExportRecord
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: DS.Icon.xl, weight: .semibold))
                .foregroundStyle(.white)
                .accessibilityHidden(true)
            Text(rec.typeName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(name)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            Text(rec.time)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
            Spacer()
            Text("离线锁管家 · 单条告警 · 仅含本条数据")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(DS.Space.xl)
        .frame(width: 360, height: 640, alignment: .top)   // 9:16
        .background(DS.Gradient.hero, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }
}

struct RecordShareCardView: View {
    let name: String
    let rec: ExportRecord
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Image(systemName: rec.isAlarm ? "exclamationmark.triangle.fill" : "lock.open.fill")
                .font(.system(size: DS.Icon.xl, weight: .semibold))
                .foregroundStyle(.white)
                .accessibilityHidden(true)
            Text(rec.typeName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text((rec.member.isEmpty ? name : name + " · " + rec.member) + " · " + rec.time)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Text("离线锁管家 · 单条记录 · 仅含本条数据")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(DS.Space.xl)
        .frame(width: 360, height: 640, alignment: .top)
        .background(DS.Gradient.hero, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
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

    let mac: String
    init(mac: String) { self.mac = mac }

    var body: some View {
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
                            .font(.subheadline)
                            .foregroundStyle(DS.Palette.danger)
                        Text(progress.failed == "生成失败" ? "多为记录为空或空间不足, 重试或稍后再试。" : "已停止生成, 数据未离开本机。")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let item = progress.done { doneSection(item) }
                if !lastPath.isEmpty { pathSection }
            }
            .navigationTitle("导出与分享")
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("关闭") { dismiss() } }
            }
            .fullScreenCover(isPresented: $showQL) {
                if let u = quickLook { QLPreviewView(url: u) }
            }
        }
    }

    // 718 分享范围明示: 入口处文案明示"文件将离开本机"
    @ViewBuilder
    private var scopeSection: some View {
        Section {
            Picker("范围 (701)", selection: rangeBinding) {
                Text("当月").tag(ExportRange.month)
                Text("全部记录").tag(ExportRange.all)
                Text("仅告警").tag(ExportRange.alarms)
                ForEach(DB.members(), id: \.id) { m in
                    Text("仅 " + m.name).tag(ExportRange.member(m.id))
                }
            }
            .pickerStyle(.inline)
            .disabled(false)
            Text("导出与分享会让文件离开本机 (AirPrint/照片/聊天由你选)。生成过程纯本地, 不经过任何网络。")
                .font(.footnote)
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
                Toggle(ExportHeaders.zh[i], isOn: Binding(
                    get: { cols.get(i) },
                    set: { cols.set(i, $0); ExportCols.save(cols) }))
            }
        } header: {
            Text("列选择 (690)")
        } footer: {
            Text("勾选即含; 凭证/原始hex 列默认不含, 上次选择会沿用。")
                .font(.caption)
        }
    }

    private var redactSection: some View {
        Section {
            Toggle("脱敏导出 (548)", isOn: $redact)
            Text("脱敏与格式独立: 关时 JSON 含原始 hex、日志不掩码; 开时 hex 列留空、连续数字掩码。")
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var actionList: some View {
        Section {
            Button { startCSV() } label: { Label("CSV 标准导出 (683)", systemImage: "tablecells") }
            Button { startJSON() } label: { Label("原始 JSON + hex (684)", systemImage: "curlybraces") }
            Button { startPDF() } label: { Label("月度 PDF 报告 (685)", systemImage: "doc.text") }
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Label("运行日志 (548)", systemImage: "text.alignleft")
                    .font(.body)
                    .foregroundStyle(DS.Palette.text)
                Picker("格式", selection: $logFormat) {
                    Text("CSV").tag("csv")
                    Text("JSON").tag("json")
                    Text("纯文本").tag("txt")
                }
                .pickerStyle(.menu)
                .frame(minHeight: DS.Hit.min)
                Button("生成运行日志导出") { startRunLog() }
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
            }
            Button { startEML() } label: { Label("邮件模板 .eml (703 降级)", systemImage: "envelope") }
        }
        .disabled(progress.running)
        Section {
            Button { startDayImages() } label: { Label("单日长图 (686/706)", systemImage: "photo.on.rectangle.angled") }
            Button { startAlarmCard() } label: { Label("告警分享卡 (688/718)", systemImage: "exclamationmark.bubble") }
            Button { printMonthly() } label: { Label("打印月度记录 (687/701)", systemImage: "printer") }
            Button { printOnePager() } label: { Label("告警一页纸 (717)", systemImage: "doc.text.magnifyingglass") }
            Button { printOralCard() } label: { Label("口述卡打印 (478)", systemImage: "person.text.rectangle") }
        }
        .disabled(progress.running)
    }

    /// 688 告警分享卡: 最新一条告警渲染 9:16 卡片图, 进 doneSection 可 ShareLink 直发 (仅含本条数据, 718)
    private func startAlarmCard() {
        progress.start("正在生成告警卡 (688)…") {
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
                              previewText: "718: 卡片只含这一条告警, 不含其他成员与记录。",
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
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("取消") { progress.cancel() }
                    .font(.footnote)
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
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.ok)
            } else {
                Label(item.fileName, systemImage: "circle.fill")
                    .font(.subheadline)
            }
            if !item.previewText.isEmpty {
                Text(item.previewText)
                    .font(.caption.monospaced())
                    .foregroundStyle(DS.Palette.textSub)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(8)
            }
            Text("SHA-256: " + item.sha256)
                .font(.caption.monospaced())
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
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                        Spacer(minLength: 0)
                    }
                }
            }
            HStack(spacing: DS.Space.s) {
                Button {
                    UIPasteboard.general.string = item.fullText
                    app.showToast("已复制完整文本")
                } label: {
                    Label("复制文本 (714)", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryActionStyle(fullWidth: false))
                .frame(minHeight: DS.Hit.min)
                if item.kind == "png" || item.kind == "pdf" {
                    Button { openQL(item) } label: {
                        Label("预览 (712)", systemImage: "eye")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryActionStyle(fullWidth: false))
                    .frame(minHeight: DS.Hit.min)
                }
                shareButton(item)
            }
        } footer: {
            Text("718: 分享/打印/存照片都会让数据离开本机; 生成本身纯本地。")
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pathSection: some View {
        Section {
            LabeledContent("文件位置 (719)", value: lastPath)
                .font(.caption)
                .textSelection(.enabled)
        }
    }
    /// 708 按 kind 走系统 UTType 的 ShareLink 表示; 709 卡片 = sharePreview (渐变封面图)。
    @ViewBuilder
    private func shareButton(_ item: ExportItem) -> some View {
        if item.kind == "eml" {
            // .eml 走复制文本 (系统邮件应用可读), 不进分享面板
            Text("邮件模板请直接复制内容, 粘贴进系统邮件或备忘录手动发送。")
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        } else if item.kind == "csv" {
            ShareLink(item: ExportCSVFile(item: item), preview: item.sharePreview) {
                Label("分享 (708)", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryActionStyle(fullWidth: false))
            .frame(minHeight: DS.Hit.min)
        } else if item.kind == "json" {
            ShareLink(item: ExportJSONFile(item: item), preview: item.sharePreview) {
                Label("分享 (708)", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryActionStyle(fullWidth: false))
            .frame(minHeight: DS.Hit.min)
        } else if item.kind == "pdf" {
            ShareLink(item: ExportPDFFile(item: item), preview: item.sharePreview) {
                Label("分享 (708)", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryActionStyle(fullWidth: false))
            .frame(minHeight: DS.Hit.min)
        } else if item.kind == "png", let img = item.images.first {
            ShareLink(item: ExportImageFile(item: item, image: img),
                      preview: item.sharePreview) {
                Label("分享 (708)", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryActionStyle(fullWidth: false))
            .frame(minHeight: DS.Hit.min)
        } else {
            ShareLink(item: ExportTextFile(item: item), preview: item.sharePreview) {
                Label("分享 (708)", systemImage: "square.and.arrow.up")
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
            if let url = item.writeLocal() { lastPath = url.path }
            lastSuccess = true
            app.showToast("已生成 \(item.fileName) (719)")
        } else if !err.isEmpty {
            lastSuccess = false
            app.showToast(err)
        }
    }

    private func startCSV() {
        progress.start("正在生成 CSV (683)…") {
            let recs = ExportKit.filtered(ExportKit.records(mac: self.mac), range: self.range)
            guard !recs.isEmpty else { return nil }
            let build = ExportKit.buildCSV(recs: recs, cols: self.cols)
            let hex = SHA256.hash(data: build.data).map { String(format: "%02x", $0) }.joined()
            return ExportItem(kind: "csv",
                              title: "记录 " + self.range.label,
                              fileName: "锁管家_记录_" + stampTag() + "_" + self.range.label + ".csv",
                              bytes: build.data, sha256: hex,
                              shaLabel: "CSV · \(build.rowCount) 行 · 转义 \(build.escapedRows) 行 (705 预检)",
                              previewText: build.preview3,
                              scopeNote: "含 " + String(build.rowCount) + " 行, 离开本机后不可撤回")
        } finish: { item, err in
            onDone(item, err)
        }
    }
    private func startJSON() {
        progress.start("正在生成 JSON (684)…") {
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
                              previewText: self.redact ? "脱敏导出: hex 列留空。" : "含协议原始 hex, 供 vendor 夹具比对。")
        } finish: { item, err in
            onDone(item, err)
        }
    }

    private func startPDF() {
        progress.start("正在排版 PDF (685)…") {
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
        progress.start("正在生成运行日志 (548)…") {
            let data = ExportKit.runLogData(format: self.logFormat, redact: self.redact)
            let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let ext = self.logFormat == "txt" ? "txt" : self.logFormat
            return ExportItem(kind: ext,
                              title: "运行日志",
                              fileName: "锁管家_日志_" + stampTag() + "." + ext,
                              bytes: data, sha256: hex,
                              shaLabel: "App 运行日志 · " + String(DiagLogs.all().count) + " 条 · " + self.logFormat + (self.redact ? " · 已脱敏" : ""),
                              previewText: String(decoding: data, as: UTF8).prefix(300))
        } finish: { item, err in
            onDone(item, err)
        }
    }

    private func startEML() {
        progress.start("正在生成邮件模板 (703)…") {
            let recs = ExportKit.filtered(ExportKit.records(mac: self.mac), range: self.range)
            guard !recs.isEmpty else { return nil }
            return ExportKit.emailTemplate(mac: self.mac, recs: recs, cols: self.cols)
        } finish: { item, err in
            onDone(item, err)
        }
    }

    private func startDayImages() {
        progress.start("正在生成长图 (686)…") {
            let all = ExportKit.records(mac: self.mac)
            let day = ExportKit.latestDayKey(all)
            guard !day.isEmpty else { return nil }
            let recs = ExportKit.filtered(all, range: .day)
            guard !recs.isEmpty else { return nil }
            let pages = ExportItem.dayPages(recs: recs, mac: self.mac, day: day)
            guard let first = pages.first, let jpeg = first.jpegData(compressionQuality: 0.8) else { return nil }
            let hex = SHA256.hash(data: jpeg).map { String(format: "%02x", $0) }.joined()
            return ExportItem(kind: "png",
                              title: "单日 " + day,
                              fileName: "锁管家_单日_" + day + ".jpg",
                              bytes: jpeg, sha256: hex,
                              shaLabel: "长图 · \(recs.count) 条" + (pages.count > 1 ? " · 切 \(pages.count) 张" : ""),
                              previewText: pages.count > 1 ? "已按屏高切 \(pages.count) 张连图 (706)。" : "",
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
        let f = DateFormatter(); f.dateFormat = "yyyyMM"; f.timeZone = .current
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
            QLPreviewController.urlPreviewItem(itemAt: index, source: url, controller: controller)
        }
    }
}
