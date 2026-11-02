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
        return who + " · " + TimeFormat.dayKey(entry.at) + " " + TimeDisplay.clock(entry.at)
    }

    private var isAlarm: Bool {
        entry.tone == .attention || entry.tone == .critical
    }

    var body: some View {
        VStack(alignment: .leading, spacing: V.S.gapMS) {
            Image(systemName: isAlarm ? "exclamationmark.triangle.fill" : "lock.open.fill")
                .font(V.F.icon28Semibold)
                .foregroundStyle(isAlarm ? V.C.critical : V.C.text1)
                .accessibilityHidden(true)
            Text(entry.event)
                .font(V.F.display22)
                .foregroundStyle(V.C.text1)
                .fixedSize(horizontal: false, vertical: true)
            Text(thirdLine)
                .font(V.F.footnote)
                .foregroundStyle(V.C.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text("离线锁管家 · 单条记录 · 仅含本条数据")
                .font(V.F.unit)
                .foregroundStyle(V.C.text3)
                .tracking(0.6)
        }
        .padding(V.S.gap24)
        .frame(width: CardSize.width, height: CardSize.height, alignment: .topLeading)
        .background(V.C.card, in: .rect(cornerRadius: V.R.panel))
        .overlay {
            RoundedRectangle(cornerRadius: V.R.panel, style: .continuous)
                .strokeBorder(V.C.hairline, lineWidth: V.S.hair)
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
    /// 屏上「单条记录卡」预览的缩放系数：容器实际宽 ÷ 360，上限 1。
    /// 不用 V.S.screenW（那是写死的 402，等于把同一个写死宽度的病换个地方再犯）。
    @State private var cardScale: CGFloat = 1

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
    /// 返回类型必须是 Image（要 Transferable），挂不了无障碍修饰符 ——
    /// 这是分享卡预览位（系统渲染），语义由 SharePreview 的 title 承载，不进 VoiceOver 焦点。
    private var cardPreview: Image {
        if let png, let image = UIImage(data: png) { return Image(uiImage: image) }
        return Image(systemName: "doc.richtext")
    }

    private var digest: WeeklyDigest.Digest {
        WeeklyDigest.lastWeek(entries: entries, lockName: lockName)
    }

    var body: some View {
        // 全换系统（2026-11-02）：整页容器是系统 `List`（与前几轮同一配方）。
        // 四件导出物按 `_audit/ui-ia.md` §2.4 拆成四段：单条卡 / 表格类(CSV) / 名册类 / 小结。
        // 分享卡预览的**按容器宽缩放**（L5 溢出修复）保留：量的是卡片所在行的实际宽，
        // 比原来的「页宽 − 2×pageGutter」更准，绝不会撑出屏幕。
        List {
            header.plainRow()
            if entries.isEmpty {
                emptyBlock.plainRow()
            } else {
                cardSection
                daysSection
                rosterSection
                digestSection
                if let copied { copiedBlock(copied).plainRow() }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(V.S.gap16)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, V.S.gap16, for: .scrollContent)
        .contentMargins(.bottom, V.S.gapL, for: .scrollContent)
        .background(CanvasBackground())
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
        VStack(alignment: .leading, spacing: V.S.gapXS) {
            Text("导出")
                .font(V.F.displayHome)
                .foregroundStyle(V.C.text1)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: V.S.gapS) {
                VStateDot(tone: entries.isEmpty ? .neutral : .ok,
                         word: entries.isEmpty ? "无可导出" : "可导出")
                Text(entries.isEmpty
                     ? "台账里还没有记录"
                     : String(entries.count) + " 条 · " + String(days.count) + " 天 · 全走分享，不上传")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text2)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 主角：单条记录分享卡（看到的就是分享出去的）

    /// ① 单条记录卡：横向选择器一行 + 预览卡（卡内含按容器宽缩放的预览与分享按钮）。
    private var cardSection: some View {
        Section {
            ScrollView(.horizontal) {
                HStack(spacing: V.S.gap16) {
                    ForEach(entries.prefix(12)) { entry in
                        Button {
                            selectedID = entry.id
                        } label: {
                            VStack(alignment: .leading, spacing: V.S.gapXS) {
                                Text(entry.event)
                                    .font(V.F.footnote)
                                    .foregroundStyle(V.C.text1)
                                    .lineLimit(1)
                                Text(TimeFormat.dayShort(entry.at) + " " + TimeDisplay.clock(entry.at))
                                    .font(V.F.unit)
                                    .foregroundStyle(V.C.text3)
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, V.S.gapMS)
                            .frame(minHeight: V.Hit.min)
                            .background(entry.id == selected?.id ? V.C.card : V.C.cardAlt,
                                        in: .rect(cornerRadius: V.R.control))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(entry.event)
                        .accessibilityAddTraits(entry.id == selected?.id ? [.isButton, .isSelected] : .isButton)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: V.S.cardPad, bottom: 0, trailing: V.S.cardPad))

            if let entry = selected {
                VCard {
                    VStack(spacing: V.S.gapMS) {
                        // 屏上预览按容器实际宽缩放；外面再套一层横向 ScrollView 只是为了兜底 ——
                        // 卡片内边距由系统决定，缩放算得略保守时宁可能横移，也绝不撑出屏幕。
                        // 量的是这一行实际宽（GeometryReader 挂在卡片里），比「页宽 − 2×gutter」更准。
                        ScrollView(.horizontal, showsIndicators: false) {
                            RecordShareCard(entry: entry, lockName: lockName)
                                .scaleEffect(cardScale, anchor: .topLeading)
                                .frame(width: CardSize.width * cardScale,
                                       height: CardSize.height * cardScale,
                                       alignment: .topLeading)
                        }
                        // 量「这一行卡片的实际内容宽」：List 行的 inset 由系统决定，
                        // 用容器宽反推比「页宽 − 2×gutter」更准（L5 溢出修复的同一口径）。
                        .background {
                            GeometryReader { proxy in
                                Color.clear
                                    .onAppear { updateCardScale(proxy.size.width) }
                                    .onChange(of: proxy.size.width) { _, width in updateCardScale(width) }
                            }
                        }
                        if let png {
                            ShareLink(
                                item: RecordCardImage(data: png),
                                preview: SharePreview("记录卡", image: cardPreview)
                            ) {
                                HStack(spacing: V.S.gapS) {
                                    Image(systemName: "square.and.arrow.up")
                                        .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                                        .font(V.F.icon18Medium)
                                    Text("分享这张卡")
                                        .font(V.F.bodyStrong)
                                }
                                .foregroundStyle(V.C.text1)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: V.H.action)
                                .background(V.C.blue, in: .rect(cornerRadius: V.R.control))
                            }
                            .accessibilityLabel("分享这张记录卡")
                        } else {
                            VBusyRow(text: "正在生成卡片图…")
                        }
                    }
                }
                .plainRow()
            }
        } header: {
            HStack(spacing: V.S.gapS) {
                Text("单条记录卡")
                    .font(V.F.section)
                    .foregroundStyle(V.C.text1)
                    .textCase(nil)
                Spacer(minLength: 0)
                Text("仅含本条数据")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text3)
                    .textCase(nil)
            }
        }
    }

    // MARK: - 按天勾选的 CSV

    /// ② 表格类：按天勾选 → CSV。行式内容（每天一行可勾）→ Section。
    private var daysSection: some View {
        Section {
                ForEach(days, id: \.key) { day in
                    Button {
                        toggleDay(day.key)
                    } label: {
                        HStack(spacing: V.S.gapMS) {
                            Image(systemName: pickedDays.contains(day.key) ? "checkmark.circle.fill" : "circle")
                                .font(V.F.icon18)
                                .foregroundStyle(pickedDays.contains(day.key) ? V.C.text1 : V.C.text3)
                                .accessibilityHidden(true)
                            Text(TimeFormat.dayTitle(day.key))
                                .font(V.F.body)
                                .foregroundStyle(V.C.text1)
                            Spacer(minLength: V.S.gapS)
                            VReading(value: String(day.count), unit: "条", font: V.F.number13,
                                    tint: V.C.text3, animated: false)
                        }
                        .frame(minHeight: V.Hit.min)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(TimeFormat.dayTitle(day.key) + "，共 " + String(day.count) + " 条")
                    .accessibilityAddTraits(pickedDays.contains(day.key) ? [.isButton, .isSelected] : .isButton)
                }
                if !pickedDays.isEmpty {
                    ShareLink(item: pickedCSV, preview: SharePreview("台账 CSV")) {
                        HStack(spacing: V.S.gapS) {
                            Image(systemName: "tablecells")
                                .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                                .font(V.F.icon18Medium)
                            Text("分享 CSV · " + String(RecordCSV.rowCount(pickedCSV)) + " 行")
                                .font(V.F.bodyStrong)
                        }
                        .foregroundStyle(V.C.text1)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V.H.action)
                        .overlay {
                            RoundedRectangle(cornerRadius: V.R.control, style: .continuous)
                                .strokeBorder(V.C.hairline, lineWidth: V.S.hair)
                        }
                    }
                    .accessibilityLabel("分享选中日期的 CSV")
                }
                HStack(spacing: V.S.gapMS) {
                    Button("全选") { pickedDays = Set(days.map { $0.key }) }
                        .font(V.F.footnote)
                        .foregroundStyle(V.C.text1)
                        .frame(minHeight: V.Hit.min)
                        .accessibilityLabel("全选所有日期")
                    Button("清空") { pickedDays = [] }
                        .font(V.F.footnote)
                        .foregroundStyle(V.C.text2)
                        .frame(minHeight: V.Hit.min)
                        .disabled(pickedDays.isEmpty)
                        .accessibilityLabel("清空日期选择")
                }
                Text("CSV 列：日期, 时间, 内容, 成员, 锁。成员不可证明时写「未归属」—— 不猜。")
                    .font(V.F.unit)
                    .foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
        } header: {
            HStack(spacing: V.S.gapS) {
                Text("按天导出 CSV")
                    .font(V.F.section)
                    .foregroundStyle(V.C.text1)
                    .textCase(nil)
                Spacer(minLength: 0)
                Text(String(pickedDays.count) + " 天")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text3)
                    .monospacedDigit()
                    .textCase(nil)
            }
        }
    }

    // MARK: - 成员名册

    /// ③ 名册类：成员名册 vCard。
    private var rosterSection: some View {
        Section {
                if app.members.isEmpty {
                    Text("还没有成员可导出。先到「家」页建一位成员，名册才有内容。")
                        .font(V.F.footnote)
                        .foregroundStyle(V.C.text2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: V.Hit.min)
                } else {
                    VReadingGrid(items: [
                        .init(label: "成员", value: String(app.members.filter { !$0.archived }.count), unit: "位"),
                        // 2026-11-01（Round 266）：原来「凭证」这一格对**全部成员**求和（含已归档），
                        // 而同一张卡里的「成员」只数在册、导出的 vCard 名册也只含在册成员 ——
                        // 于是这个数字**描述的不是它旁边那份导出内容**（归档成员名下的凭证被算进来了）。
                        // 与 `HouseholdScreen` 的 `HHStats.ownedKeys(activeMembers)` 口径对齐。
                        .init(label: "凭证", value: String(app.members.filter { !$0.archived }.reduce(0) { $0 + $1.keyCount }), unit: "枚")
                    ], columns: 2)
                    ShareLink(item: roster, preview: SharePreview("成员名册")) {
                        HStack(spacing: V.S.gapS) {
                            Image(systemName: "person.2")
                                .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                                .font(V.F.icon18Medium)
                            Text("分享名册")
                                .font(V.F.bodyStrong)
                        }
                        .foregroundStyle(V.C.text1)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V.H.action)
                        .overlay {
                            RoundedRectangle(cornerRadius: V.R.control, style: .continuous)
                                .strokeBorder(V.C.hairline, lineWidth: V.S.hair)
                        }
                    }
                    .accessibilityLabel("分享成员名册")
                }
                Text("名册只带称呼与角色；电话与备注留在本机（TODO(engine) 待接成员扩展档案）。")
                    .font(V.F.unit)
                    .foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
        } header: {
            HStack(spacing: V.S.gapS) {
                Text("成员名册")
                    .font(V.F.section)
                    .foregroundStyle(V.C.text1)
                    .textCase(nil)
                Spacer(minLength: 0)
                Text("vCard 3.0")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text3)
                    .textCase(nil)
            }
        }
    }

    // MARK: - 上周小结（三句人话 + CSV，一起进剪贴板）

    /// ④ 小结类：上周三句人话 + CSV，一起进剪贴板。
    private var digestSection: some View {
        Section {
            ForEach(digest.lines.indices, id: \.self) { index in
                Text(digest.lines[index])
                    .font(V.F.body)
                    .foregroundStyle(V.C.text1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VOutlineButton(title: copied == nil ? "复制小结与 CSV" : "已复制到剪贴板",
                            systemImage: "doc.on.clipboard") {
                copyDigest()
            }
        } header: {
            HStack(spacing: V.S.gapS) {
                Text("上周小结")
                    .font(V.F.section)
                    .foregroundStyle(V.C.text1)
                    .textCase(nil)
                Spacer(minLength: 0)
                Text(String(digest.rows) + " 条")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text3)
                    .monospacedDigit()
                    .textCase(nil)
            }
        }
    }

    private func copiedBlock(_ text: String) -> some View {
        VCard {
            VStatusLine(tone: .ok, text: text)
        }
    }

    // MARK: - 空态（必须给出路）

    private var emptyBlock: some View {
        VCard {
            VEmptyState(
                title: "还没有可导出的记录",
                message: "导出的都是台账里的真记录。先到「门」页开一次门，或回台账读取锁内日志。",
                actionTitle: "去读取台账",
                systemImage: "square.and.arrow.up"
            ) {
                router.recordsPath = []
            }
            .padding(.vertical, V.S.gapXXL)
        }
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

    /// 可用宽 → 屏上预览缩放。
    /// **2026-11-02（List 化）**：GeometryReader 现在挂在**卡片内部**的预览 ScrollView 上，
    /// 量到的已经就是卡片内容宽（系统 GroupBox 的内边距已扣掉）—— 再减 2×cardPad 会二次扣除、
    /// 把预览无谓缩小。所以这里直接用测量值；上限仍是 1（不放大）。
    /// 只影响屏上预览；导出 PNG 走 renderCard() 的 ImageRenderer，版式仍是固定的 360×640。
    private func updateCardScale(_ usable: CGFloat) {
        guard usable > 0 else { return }
        let next = min(1, usable / CardSize.width)
        if abs(next - cardScale) > 0.0005 { cardScale = next }
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
        Clip.set(text)
        copied = "已复制 " + String(digest.lines.count) + " 句摘要 + " + String(digest.rows) + " 行 CSV"
    }
}
