// RecordExportScreen.swift —— 导出（record.export / record.rangePick / record.digest）。
//
// 三件真东西：① 单条记录分享卡（360×640 定尺 PNG）② 按天勾选的 CSV ③ 成员名册 vCard。
// 全部走 ShareLink / 剪贴板，不上传、不落盘、不留旧文件。
// 主动作：选一条记录生成分享卡；其余两个出口是 ShareLink，选中天/名册变了才出现。
import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers
import UIKit

// MARK: - 分享卡尺寸（版式几何，不是样式令牌）

private enum CardSize {
    /// record.export.card 的固定版式：360×640。
    static let width: CGFloat = 360
    static let height: CGFloat = 640
}

// MARK: - PNG 载荷（ShareLink 需要 Transferable，UIImage 不满足）

struct RecordCardImage: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.data }
            .suggestedFileName("记录卡.png")
    }
}

// MARK: - 分享卡本体（明示仅含本条数据）

private struct RecordShareCard: View {
    let entry: LedgerEntry
    let lockName: String

    private var member: String { entry.owner ?? "" }

    private var thirdLine: String {
        let who = member.isEmpty ? lockName : lockName + " · " + member
        return who + " · " + TimeFormat.dayKey(entry.at) + " " + TimeFormat.clock(entry.at)
    }

    private var isAlarm: Bool {
        entry.tone == .attention || entry.tone == .critical
    }

    var body: some View {
        VStack(alignment: .leading, spacing: T.S.m) {
            Image(systemName: isAlarm ? "exclamationmark.triangle.fill" : "lock.open.fill")
                .font(T.F.icon(T.Icon.xl, weight: .semibold))
                .foregroundStyle(isAlarm ? State.critical : Ink.ink)
                .accessibilityHidden(true)
            Text(entry.event)
                .font(T.F.display(22))
                .foregroundStyle(Ink.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(thirdLine)
                .font(T.F.caption)
                .foregroundStyle(Ink.inkSub)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text("离线锁管家 · 单条记录 · 仅含本条数据")
                .font(T.F.unit)
                .foregroundStyle(Ink.inkFaint)
                .tracking(0.6)
        }
        .padding(T.S.xl)
        .frame(width: CardSize.width, height: CardSize.height, alignment: .topLeading)
        .background(Ink.plate, in: .rect(cornerRadius: T.R.plate))
        .overlay {
            RoundedRectangle(cornerRadius: T.R.plate, style: .continuous)
                .strokeBorder(Ink.hairline, lineWidth: T.Stroke.hair)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 页面

struct RecordExportScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    @State private var selectedID: String?
    @State private var png: Data?
    @State private var pickedDays: Set<String> = []
    @State private var copied: String?
    @State private var source: [LedgerEntry] = []

    private var entries: [LedgerEntry] { source.sorted { $0.at > $1.at } }

    private var mac: String { app.lock?.id ?? "" }

    private var selected: LedgerEntry? {
        if let id = selectedID, let hit = entries.first(where: { $0.id == id }) { return hit }
        return entries.first
    }

    private var lockName: String { app.lock?.name ?? "门锁" }

    /// 按自然日分组的天（只列真有记录的天，不造空天）。
    private var days: [(key: String, count: Int)] {
        var buckets: [String: Int] = [:]
        for entry in entries {
            buckets[TimeFormat.dayKey(entry.at), default: 0] += 1
        }
        return buckets
            .map { (key: $0.key, count: $0.value) }
            .sorted { $0.key > $1.key }
    }

    private var pickedRows: [RecordExportRow] {
        entries
            .filter { pickedDays.contains(TimeFormat.dayKey($0.at)) }
            .map { RecordExportRow(entry: $0, lockName: lockName) }
    }

    private var pickedCSV: String { RecordCSV.build(pickedRows) }

    private var roster: String { MemberVCard.build(app.members) }

    /// SharePreview 的缩略图：拿到真图就用真图，拿不到退回符号，不留空白。
    /// 这是分享卡预览位（系统渲染），语义由 SharePreview 的 title 承载 —— 标装饰。
    private var cardPreview: Image {
        if let png, let image = UIImage(data: png) { return Image(uiImage: image) }
        return Image(systemName: "doc.richtext").accessibilityHidden(true)
    }

    private var digest: WeeklyDigest.Digest {
        WeeklyDigest.lastWeek(entries: entries, lockName: lockName)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: T.S.l) {
                header
                if entries.isEmpty {
                    emptyBlock
                } else {
                    cardBlock
                    daysBlock
                    rosterBlock
                    digestBlock
                    if let copied { copiedBlock(copied) }
                }
            }
            .padding(.vertical, T.S.l)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("导出")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            reload()
            ensureSelection()
        }
        .task(id: selected?.id) { await renderCard() }
    }

    // MARK: - 页头

    private var header: some View {
        VStack(alignment: .leading, spacing: T.S.xs) {
            Text("导出")
                .font(T.F.display())
                .foregroundStyle(Ink.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: T.S.s) {
                StateDot(tone: entries.isEmpty ? .neutral : .ok,
                         word: entries.isEmpty ? "无可导出" : "可导出")
                Text(entries.isEmpty
                     ? "台账里还没有记录"
                     : String(entries.count) + " 条 · " + String(days.count) + " 天 · 全走分享，不上传")
                    .font(T.F.caption)
                    .foregroundStyle(Ink.inkSub)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, T.S.gutter)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 主角：单条记录分享卡（看到的就是分享出去的）

    private var cardBlock: some View {
        VStack(spacing: T.S.m) {
            SectionLabel(text: "单条记录卡", trailing: "仅含本条数据")
            ScrollView(.horizontal) {
                HStack(spacing: T.S.l) {
                    ForEach(entries.prefix(12)) { entry in
                        Button {
                            selectedID = entry.id
                        } label: {
                            VStack(alignment: .leading, spacing: T.S.xs) {
                                Text(entry.event)
                                    .font(T.F.caption)
                                    .foregroundStyle(Ink.ink)
                                    .lineLimit(1)
                                Text(TimeFormat.dayShort(entry.at) + " " + TimeFormat.clock(entry.at))
                                    .font(T.F.unit)
                                    .foregroundStyle(Ink.inkFaint)
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, T.S.m)
                            .frame(minHeight: T.Hit.min)
                            .background(entry.id == selected?.id ? Ink.plate : Ink.plateAlt,
                                        in: .rect(cornerRadius: T.R.control))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(entry.event)
                        .accessibilityAddTraits(entry.id == selected?.id ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(.horizontal, T.S.gutter)
            }
            .scrollIndicators(.hidden)

            if let entry = selected {
                Panel {
                    VStack(spacing: T.S.m) {
                        RecordShareCard(entry: entry, lockName: lockName)
                        if let png {
                            ShareLink(
                                item: RecordCardImage(data: png),
                                preview: SharePreview("记录卡", image: cardPreview)
                            ) {
                                HStack(spacing: T.S.s) {
                                    Image(systemName: "square.and.arrow.up")
                                        .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                                        .font(T.F.icon(T.Icon.m, weight: .medium))
                                    Text("分享这张卡")
                                        .font(T.F.bodyStrong)
                                }
                                .foregroundStyle(Signal.on)
                                .frame(maxWidth: .infinity)
                                .frame(height: T.H.action)
                                .background(Signal.base, in: .rect(cornerRadius: T.R.control))
                            }
                            .accessibilityLabel("分享这张记录卡")
                        } else {
                            BusyRow(text: "正在生成卡片图…")
                        }
                    }
                }
                .padding(.horizontal, T.S.gutter)
            }
        }
    }

    // MARK: - 按天勾选的 CSV

    private var daysBlock: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "按天导出 CSV", trailing: String(pickedDays.count) + " 天")
                ForEach(days, id: \.key) { day in
                    Button {
                        toggleDay(day.key)
                    } label: {
                        HStack(spacing: T.S.m) {
                            Image(systemName: pickedDays.contains(day.key) ? "checkmark.circle.fill" : "circle")
                                .font(T.F.icon(T.Icon.m, weight: .regular))
                                .foregroundStyle(pickedDays.contains(day.key) ? Ink.ink : Ink.inkFaint)
                                .accessibilityHidden(true)
                            Text(TimeFormat.dayTitle(day.key))
                                .font(T.F.body)
                                .foregroundStyle(Ink.ink)
                            Spacer(minLength: T.S.s)
                            Reading(value: String(day.count), unit: "条", size: 13, weight: .regular,
                                    tint: Ink.inkFaint, animated: false)
                        }
                        .frame(minHeight: T.Hit.min)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(TimeFormat.dayTitle(day.key) + "，共 " + String(day.count) + " 条")
                    .accessibilityAddTraits(pickedDays.contains(day.key) ? [.isButton, .isSelected] : .isButton)
                }
                if !pickedDays.isEmpty {
                    ShareLink(item: pickedCSV, preview: SharePreview("台账 CSV")) {
                        HStack(spacing: T.S.s) {
                            Image(systemName: "tablecells")
                                .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                                .font(T.F.icon(T.Icon.m, weight: .medium))
                            Text("分享 CSV · " + String(RecordCSV.rowCount(pickedCSV)) + " 行")
                                .font(T.F.bodyStrong)
                        }
                        .foregroundStyle(Ink.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: T.H.action)
                        .overlay {
                            RoundedRectangle(cornerRadius: T.R.control, style: .continuous)
                                .strokeBorder(Ink.hairline, lineWidth: T.Stroke.hair)
                        }
                    }
                    .accessibilityLabel("分享选中日期的 CSV")
                }
                HStack(spacing: T.S.m) {
                    Button("全选") { pickedDays = Set(days.map { $0.key }) }
                        .font(T.F.caption)
                        .foregroundStyle(Ink.ink)
                        .frame(minHeight: T.Hit.min)
                        .accessibilityLabel("全选所有日期")
                    Button("清空") { pickedDays = [] }
                        .font(T.F.caption)
                        .foregroundStyle(Ink.inkSub)
                        .frame(minHeight: T.Hit.min)
                        .disabled(pickedDays.isEmpty)
                        .accessibilityLabel("清空日期选择")
                }
                Text("CSV 列：日期, 时间, 内容, 成员, 锁。成员不可证明时写「未归属」—— 不猜。")
                    .font(T.F.unit)
                    .foregroundStyle(Ink.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    // MARK: - 成员名册

    private var rosterBlock: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "成员名册", trailing: "vCard 3.0")
                if app.members.isEmpty {
                    Text("还没有成员可导出。先到「家」页建一位成员，名册才有内容。")
                        .font(T.F.caption)
                        .foregroundStyle(Ink.inkSub)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: T.Hit.min)
                } else {
                    ReadingGrid(items: [
                        .init(label: "成员", value: String(app.members.filter { !$0.archived }.count), unit: "位"),
                        .init(label: "凭证", value: String(app.members.reduce(0) { $0 + $1.keyCount }), unit: "枚")
                    ], columns: 2)
                    ShareLink(item: roster, preview: SharePreview("成员名册")) {
                        HStack(spacing: T.S.s) {
                            Image(systemName: "person.2")
                                .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                                .font(T.F.icon(T.Icon.m, weight: .medium))
                            Text("分享名册")
                                .font(T.F.bodyStrong)
                        }
                        .foregroundStyle(Ink.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: T.H.action)
                        .overlay {
                            RoundedRectangle(cornerRadius: T.R.control, style: .continuous)
                                .strokeBorder(Ink.hairline, lineWidth: T.Stroke.hair)
                        }
                    }
                    .accessibilityLabel("分享成员名册")
                }
                Text("名册只带称呼与角色；电话与备注留在本机（TODO(engine) 待接成员扩展档案）。")
                    .font(T.F.unit)
                    .foregroundStyle(Ink.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    // MARK: - 上周小结（三句人话 + CSV，一起进剪贴板）

    private var digestBlock: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "上周小结", trailing: String(digest.rows) + " 条")
                ForEach(digest.lines.indices, id: \.self) { index in
                    Text(digest.lines[index])
                        .font(T.F.body)
                        .foregroundStyle(Ink.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                SecondaryAction(title: copied == nil ? "复制小结与 CSV" : "已复制到剪贴板",
                                systemImage: "doc.on.clipboard") {
                    copyDigest()
                }
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    private func copiedBlock(_ text: String) -> some View {
        Panel {
            StatusLine(tone: .ok, text: text)
        }
        .padding(.horizontal, T.S.gutter)
    }

    // MARK: - 空态（必须给出路）

    private var emptyBlock: some View {
        Panel {
            EmptyPanel(
                title: "还没有可导出的记录",
                message: "导出的都是台账里的真记录。先到「门」页开一次门，或回台账读取锁内日志。",
                actionTitle: "去读取台账",
                systemImage: "square.and.arrow.up"
            ) {
                router.recordsPath = []
            }
            .padding(.vertical, T.S.xxl)
        }
        .padding(.horizontal, T.S.gutter)
    }

    // MARK: - 动作

    /// 与台账页同一份来源（锁内日志缓存），同一套行身份。
    private func reload() {
        guard !mac.isEmpty else {
            source = []
            return
        }
        source = RecordsSource.load(mac: mac, lockName: lockName, members: app.members).entries
    }

    private func ensureSelection() {
        if selectedID == nil { selectedID = entries.first?.id }
    }

    private func toggleDay(_ key: String) {
        if pickedDays.contains(key) {
            pickedDays.remove(key)
        } else {
            pickedDays.insert(key)
        }
    }

    /// 真渲染 PNG：ImageRenderer 出图，不是摆一个假按钮。
    @MainActor
    private func renderCard() async {
        guard let entry = selected else {
            png = nil
            return
        }
        let renderer = ImageRenderer(content: RecordShareCard(entry: entry, lockName: lockName))
        renderer.scale = 2
        png = renderer.uiImage?.pngData()
    }

    /// 真写剪贴板（与 CSV 走分享是两条不同通路，不混）。
    private func copyDigest() {
        let text = digest.lines.joined(separator: "\n") + "\n\n" + digest.csv
        UIPasteboard.general.string = text
        copied = "已复制 " + String(digest.lines.count) + " 句摘要 + " + String(digest.rows) + " 行 CSV"
    }
}
