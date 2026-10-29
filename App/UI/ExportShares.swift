// 记录卡分享 (718) + 成员名册导出 (415) —— 两件仍在用的导出, 从导出中心拆出来单独存活。
//
// App/UI/ExportCenter.swift (2307 行: CSV/JSON/PDF/邮件/二维码报告/口述卡/导出向导)
// 已随大删波 4 移除 (用户决策)。但文件里有两处**别的页面在用**的东西, 不能跟着走:
//   · RecordsTimeline 的「分享本条」: 需要 ExportRecord 行模型 + RecordCardImage + 卡片渲染
//   · MemberCenterView 的「导出成员名册」: 需要 memberRoster/vcfEscape/.vcf 落盘
// 所以这里只保留这两条链所需的最小实现, 不含导出中心那套按钮/范围/预览。
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// ================= 记录行模型 (归属只走 Attribution 可证明链) =================
struct ExportRecord {
    var time: String      // yyyy-MM-dd HH:mm:ss, 无时间戳为 ""
    var typeName: String
    var member: String    // "" = 无法证明归属
    var isAlarm: Bool
    var hex: String       // 缓存层存了协议帧则原样带出, 否则 ""
    var dayKey: String    // yyyy-MM-dd, 未知为 "未知"
    var key: String = ""  // 锁端行键 (idxRaw) — mac#key 即 726 留痕键; 无 idx 的行留空
}


/// 718 卡片版式 (明示仅含本条数据)。渲染入口是 ExportKit.recordCard。
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

enum ExportKit {
    // ---------- 718 单条记录分享卡 ----------
    @MainActor
    static func recordCard(_ r: ExportRecord, lockName: String) -> UIImage? {
        let card = RecordShareCardView(name: lockName, rec: r)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        return renderer.uiImage
    }

    // ---------- 415 成员名册 (vCard 3.0) ----------

    static func vcfEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: ";", with: "\\;")
         .replacingOccurrences(of: ",", with: "\\,")
         .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// 写成 Caches/exports 下的 .vcf 文件。文件名带日期: 415 的用途是核对,
    /// "哪一次的名册"必须能从名字看出来。
    static func writeRoster() -> URL? {
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
        let text = out
        guard !text.isEmpty else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone.current; f.locale = Locale(identifier: "en_US_POSIX")
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // 2026-10-27 审核修复 (AUDIT-D D-24)：写新文件前**先清掉同目录的旧导出**。
        // 原先每次导出都留一份，永不清理 —— 成员名册含姓名/电话/备注，
        // 明文躺在 Caches 里，越狱/备份/文件 App 都能读到，且旧文件会一直累积。
        // 只留"最近一次"：用户分享完就不需要了，下次导出会重新生成。
        if let olds = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for old in olds where old.pathExtension == "vcf" {
                try? FileManager.default.removeItem(at: old)
            }
        }
        let url = dir.appendingPathComponent("锁管家_成员名册_\(f.string(from: Date())).vcf")
        guard (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil else { return nil }
        return url
    }
}

