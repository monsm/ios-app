// RecordsExportSection.swift —— 台账工作室的「导出」段（原 recordExport 页整段并入）
//
// 与 RecordExportScreen 的能力对齐：① 单条记录分享卡（固定 360×640 的 PNG，ImageRenderer 真出图）
// ② 按天勾选的 CSV ③ 成员名册 vCard ④ 上周小结（三句人话 + CSV 一起进剪贴板）。
// 全部走 ShareLink / 剪贴板：不上传、不落盘、本机不留旧文件。
//
// 与旧页的刻意差异：
//   ① 空壳模式（胁迫码）整页不给导出 —— 旧页只靠数据层返回空集，页面仍会把「可导出」的状态词与锁名说出口。
//   ② 导出前先过一次 .v8Confirm：分享出去的文件与已粘贴的内容收不回来，这一步不能装作没发生。
import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers
import UIKit

// MARK: - PNG 载荷（ShareLink 需要 Transferable，UIImage 不满足）

struct RecordExportShareImage: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.data }
            .suggestedFileName("记录卡.png")
    }
}

/// 分享卡的版式几何（360×640 的设计稿尺寸，不是样式令牌）。
private enum RecordExportCardSize {
    static let width: CGFloat = 360
    static let height: CGFloat = 640
}

// MARK: - 页面

struct RecordsExportSection: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    @State private var selectedID: String?
    @State private var png: Data?
    @State private var renderFailed = false
    @State private var pickedDays: Set<String> = []
    @State private var copied: String?
    @State private var source: [LedgerEntry] = []
    @State private var shareUnlocked = false
    @State private var confirmExport = false
    @State private var confirmCopyDigest = false

    private var cardWidth: CGFloat { RecordExportCardSize.width }
    private var cardHeight: CGFloat { RecordExportCardSize.height }

    private var entries: [LedgerEntry] { source.sorted { $0.at > $1.at } }
    private var mac: String { app.lock?.id ?? "" }
    private var decoyed: Bool { DB.isDecoy }

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

    private var activeMemberCount: Int { app.members.filter { !$0.archived }.count }

    private var ownedKeyCount: Int {
        app.members.filter { !$0.archived }.reduce(0) { $0 + $1.keyCount }
    }

    /// SharePreview 的缩略图：拿到真图就用真图，拿不到退回符号，不留空白。
    private var cardPreview: Image {
        if let png, let image = UIImage(data: png) { return Image(uiImage: image) }
        return Image(systemName: "doc.richtext")
    }

    private var digest: WeeklyDigest.Digest {
        WeeklyDigest.lastWeek(entries: entries, lockName: lockName)
    }

    private var judgement: String {
        if decoyed { return "空壳模式下不导出" }
        if app.lock == nil { return "还没有门锁" }
        if entries.isEmpty { return "台账里还没有记录" }
        return "\(entries.count) 条 · \(days.count) 天可导出"
    }

    private var lead: String {
        if decoyed {
            return DecoyCopy.notProvided("导出会把台账交给系统分享")
        }
        if entries.isEmpty {
            return "导出的都是台账里的真记录。先到门页开一次门，或回台账读取锁内日志。"
        }
        return "三样东西都走系统分享与剪贴板：不上传、不落盘、本机不留旧文件。这一页不连门锁，离线时导出的仍是缓存里那一份。"
    }

    /// 02 §3.3 M10：recordExport 并入台账工作室成为「导出」段。
    /// 这一段以「导出卡」的形状出现：卡头就是原来的判断句，段头脚注就是原来的因果段。
    var body: some View {
        VStack(spacing: V8.S.gapCard) {
            if decoyed {
                decoyCard
            } else if app.lock == nil {
                VEmpty(
                    title: "添加一把门锁",
                    reason: "导出的都是门锁台账里的真记录。先添加并配对一把锁，再回来导出。",
                    actionTitle: "添加门锁"
                ) { router.request(.dest(.addLock)) }
            } else if entries.isEmpty {
                VEmpty(
                    title: "还没有可导出的记录",
                    reason: "导出的都是台账里的真记录。先到门页开一次门，或回台账读取锁内日志。",
                    actionTitle: "去读取台账"
                ) { router.recordsPath = [] }
            } else {
                chipRow
                consentCard
                cardBlock
                daysBlock
                rosterBlock
                digestBlock
                if let copied {
                    copiedCard(copied)
                }
            }
        }
        .onAppear {
            reload()
            ensureSelection()
        }
        .task(id: selected?.id) { await renderCard() }
        .v8Confirm(
            isPresented: $confirmExport,
            title: "确认开始导出？",
            consequence: "导出会把台账内容交给系统分享面板或剪贴板。分享出去的文件与已经粘贴出去的内容都收不回来（对方保存的副本无法收回），本机不落盘、不留副本。",
            confirmTitle: "我明白，开始导出",
            isDestructive: false
        ) {
            shareUnlocked = true
        }
        .v8Confirm(
            isPresented: $confirmCopyDigest,
            title: "复制小结到剪贴板？",
            consequence: "复制的是上周小结的三句人话与对应 CSV。剪贴板 90 秒后自动清空，但已经粘贴出去的文本收不回来。",
            confirmTitle: "复制",
            isDestructive: false
        ) {
            copyDigest()
        }
    }

    // MARK: - 段头（原页的判断句 + 因果段 + 芯片行，收进一张段头卡）

    private var chipRow: some View {
        VStack(spacing: V8.S.gapS) {
            VCardHead(eyebrow: "导出", statement: judgement)
            Text(lead)
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .fixedSize(horizontal: false, vertical: true)
            VHScroll {
                HStack(spacing: V8.S.gapChip) {
                    VChip2(icon: .ring(1, V8.C.accent), label: "可导出", value: "\(entries.count) 条")
                    VChip2(icon: .ring(0.6, V8.C.info), label: "天数", value: "\(days.count) 天")
                    VChip2(icon: .ring(0.4, V8.D.fingerprint), label: "成员", value: "\(activeMemberCount) 位")
                    VChip2(icon: .ring(0.2, V8.C.warn), label: "上周", value: "\(digest.rows) 条")
                }
            }
        }
    }

    // MARK: - 导出确认（危险动作：出去就收不回来）

    private var consentCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "导出确认", statement: shareUnlocked ? "已确认，可以分享" : "先确认一次")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("导出会把台账内容交给系统分享面板或剪贴板：分享出去的文件与已经粘贴出去的内容都收不回来，本机不落盘、不留副本。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            if app.trialGuard {
                Text("只读试验模式开着：导出只读本机台账，不下发任何命令，不受影响。")
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !shareUnlocked {
                Button {
                    confirmExport = true
                } label: {
                    Text("我明白，开始导出")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.chipOn)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.accent))
                }
                .buttonStyle(V8PressStyle())
                .accessibilityLabel("确认开始导出")
                .padding(.top, V8.S.gapM)
            }
        }
    }

    // MARK: - 主角：单条记录分享卡（看到的就是分享出去的）

    private var cardBlock: some View {
        VCard2 {
            VCardHead(eyebrow: "单条记录卡", statement: "看到的就是分享出去的", trailing: "仅含本条")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VHScroll {
                HStack(spacing: V8.S.gapS) {
                    ForEach(entries.prefix(12)) { entry in
                        selectionChip(entry)
                    }
                }
            }
            .padding(.top, V8.S.gapM)
            if let entry = selected {
                RecordExportScaledCard(designWidth: cardWidth, designHeight: cardHeight) {
                    RecordExportShareCard(entry: entry, lockName: lockName)
                }
                .padding(.top, V8.S.gapM)
                if shareUnlocked {
                    if let png {
                        ShareLink(
                            item: RecordExportShareImage(data: png),
                            preview: SharePreview("记录卡", image: cardPreview)
                        ) {
                            Text("分享这张卡")
                                .font(V8.T.tab)
                                .foregroundStyle(V8.C.chipOn)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: V8.H.min)
                                .background(Capsule(style: .continuous).fill(V8.C.accent))
                        }
                        .accessibilityLabel("分享这张记录卡")
                        .padding(.top, V8.S.gapM)
                    } else if renderFailed {
                        VFailure(
                            what: "卡片图没有生成",
                            why: "这一条记录在出图时失败了 —— 预览里的版式还在，但分享不出去。",
                            next: "换一条记录再试一次；如果每条都失败，重启 App 后再来。"
                        )
                        .padding(.top, V8.S.gapM)
                    } else {
                        VBusy(text: "正在生成卡片图…")
                            .padding(.top, V8.S.gapM)
                    }
                } else {
                    Text("确认导出后，这里会出现「分享这张卡」。")
                        .font(V8.T.caption)
                        .foregroundStyle(V8.C.ink4)
                        .padding(.top, V8.S.gapM)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("卡片固定 360×640：内容只有这一条的时间、事件与归属，不含其它记录。")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapFootnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func selectionChip(_ entry: LedgerEntry) -> some View {
        let on = entry.id == selected?.id
        return Button {
            selectedID = entry.id
        } label: {
            VStack(alignment: .leading, spacing: V8.S.gapXS) {
                Text(entry.event)
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink1)
                    .lineLimit(1)
                Text(TimeFormat.dayShort(entry.at) + " " + TimeDisplay.clock(entry.at))
                    .font(V8.T.micro)
                    .foregroundStyle(V8.C.ink4)
                    .monospacedDigit()
            }
            .padding(.horizontal, V8.S.gapM)
            .frame(minHeight: V8.H.min)
            .background(on ? V8.C.chipOn : V8.C.chipOff, in: .rect(cornerRadius: V8.R.inset))
            .overlay(
                RoundedRectangle(cornerRadius: V8.R.inset, style: .continuous)
                    .strokeBorder(on ? V8.C.accent : V8.C.line, lineWidth: V8.S.hair)
            )
        }
        .buttonStyle(V8PressStyle())
        .accessibilityLabel(entry.event + "，" + TimeFormat.dayShort(entry.at) + " " + TimeDisplay.clock(entry.at))
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - 按天勾选的 CSV

    private var daysBlock: some View {
        VCard2 {
            VCardHead(eyebrow: "按天导出 CSV", statement: "勾选日期", trailing: "\(pickedDays.count) 天")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                ForEach(days, id: \.key) { day in
                    if day.key != days.first?.key { VDotRule() }
                    dayRow(day.key, count: day.count)
                }
            }
            .padding(.top, V8.S.gapS)
            HStack(spacing: V8.S.gapM) {
                Button("全选") { pickedDays = Set(days.map { $0.key }) }
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink1)
                    .frame(minHeight: V8.H.min)
                    .accessibilityLabel("全选所有日期")
                Button("清空") { pickedDays = [] }
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .frame(minHeight: V8.H.min)
                    .disabled(pickedDays.isEmpty)
                    .accessibilityLabel("清空日期选择")
            }
            .padding(.top, V8.S.gapS)
            if shareUnlocked && !pickedDays.isEmpty {
                ShareLink(item: pickedCSV, preview: SharePreview("台账 CSV")) {
                    Text("分享 CSV · \(RecordCSV.rowCount(pickedCSV)) 行")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.ink1)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .overlay(
                            RoundedRectangle(cornerRadius: V8.R.capsule(V8.H.min), style: .continuous)
                                .strokeBorder(V8.C.line, lineWidth: V8.S.hair)
                        )
                }
                .accessibilityLabel("分享选中日期的 CSV")
                .padding(.top, V8.S.gapM)
            }
            if pickedDays.isEmpty {
                Text("还没勾日期 —— 勾一天才会出现「分享 CSV」。")
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("CSV 列：日期、时间、内容、成员、锁。成员不可证明时写「未归属」—— 不猜。")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapFootnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func dayRow(_ key: String, count: Int) -> some View {
        let on = pickedDays.contains(key)
        return Button {
            toggleDay(key)
        } label: {
            HStack(spacing: V8.S.gapM) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(V8.T.caption)
                    .foregroundStyle(on ? V8.C.accent : V8.C.ink4)
                    .accessibilityHidden(true)
                Text(TimeFormat.dayTitle(key))
                    .font(V8.T.value)
                    .foregroundStyle(V8.C.ink1)
                Spacer(minLength: V8.S.gapS)
                Text("\(count)")
                    .font(V8.T.value)
                    .foregroundStyle(V8.C.ink3)
                    .monospacedDigit()
                Text("条")
                    .font(V8.T.micro)
                    .foregroundStyle(V8.C.ink4)
            }
            .frame(minHeight: V8.H.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(V8PressStyle())
        .accessibilityLabel(TimeFormat.dayTitle(key) + "，共 \(count) 条")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - 成员名册

    private var rosterBlock: some View {
        VCard2 {
            VCardHead(eyebrow: "成员名册", statement: activeMemberCount == 0 ? "还没有成员可导出" : "在册 \(activeMemberCount) 位", trailing: "vCard 3.0")
            VDivider2()
                .padding(.top, V8.S.gapM)
            if app.members.isEmpty {
                Text("还没有成员可导出。先到「家」页建一位成员，名册才有内容。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .frame(minHeight: V8.H.min)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStatPair2(items: [
                    .init(label: "成员", value: "\(activeMemberCount)", unit: "位"),
                    .init(label: "凭证", value: "\(ownedKeyCount)", unit: "枚")
                ])
                .padding(.top, V8.S.gapM)
                if shareUnlocked {
                    ShareLink(item: roster, preview: SharePreview("成员名册")) {
                        Text("分享名册")
                            .font(V8.T.tab)
                            .foregroundStyle(V8.C.ink1)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: V8.H.min)
                            .overlay(
                                RoundedRectangle(cornerRadius: V8.R.capsule(V8.H.min), style: .continuous)
                                    .strokeBorder(V8.C.line, lineWidth: V8.S.hair)
                            )
                    }
                    .accessibilityLabel("分享成员名册")
                    .padding(.top, V8.S.gapM)
                }
            }
            Text("名册带三项：称呼、角色、持有凭证数。电话与你写的备注留在本机，不会进这份名册。")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapFootnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 上周小结

    private var digestBlock: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "上周小结", statement: "三句人话 + CSV", trailing: "\(digest.rows) 条")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(alignment: .leading, spacing: V8.S.gapS) {
                ForEach(Array(digest.lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(V8.T.body)
                        .foregroundStyle(V8.C.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, V8.S.gapM)
            if shareUnlocked {
                Button {
                    confirmCopyDigest = true
                } label: {
                    Text(copied == nil ? "复制小结与 CSV" : "已复制到剪贴板")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.ink1)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .overlay(
                            RoundedRectangle(cornerRadius: V8.R.capsule(V8.H.min), style: .continuous)
                                .strokeBorder(V8.C.line, lineWidth: V8.S.hair)
                        )
                }
                .buttonStyle(V8PressStyle())
                .accessibilityLabel(copied == nil ? "复制上周小结与 CSV" : "已复制到剪贴板")
                .padding(.top, V8.S.gapM)
            }
        }
    }

    private func copiedCard(_ text: String) -> some View {
        VCard2(style: .well) {
            Text(text)
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ok)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 空壳

    private var decoyCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "导出", statement: "空壳模式不导出")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("空壳模式（胁迫码进入）下不显示可导出条数，也不生成分享卡与 CSV。退出空壳后才能导出。")
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink3)
                .lineSpacing(V8.L.body - V8.T.body.size)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Text("退出空壳请在本机密码界面输入正常密码。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 动作

    /// 与台账页同一份来源（锁内日志缓存），同一套行身份。
    private func reload() {
        guard !decoyed else {
            source = []
            return
        }
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
            renderFailed = false
            return
        }
        let renderer = ImageRenderer(content: RecordExportShareCard(entry: entry, lockName: lockName))
        renderer.scale = 2
        png = renderer.uiImage?.pngData()
        renderFailed = png == nil
    }

    /// 真写剪贴板（与 CSV 走分享是两条不同通路，不混）。
    private func copyDigest() {
        let text = digest.lines.joined(separator: "\n") + "\n\n" + digest.csv
        Clip.set(text)
        copied = "已复制 \(digest.lines.count) 句摘要 + \(digest.rows) 行 CSV"
    }
}

// MARK: - 分享卡本体（明示仅含本条数据；360×640 的版式几何）

private struct RecordExportShareCard: View {
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
        // 2026-11-05（Round 6 · 品牌收口）：分享卡是 App 走出去的脸 —— 产品名必须与
        // CFBundleDisplayName 一致（「锁管家」），不能再写旧文案「离线锁管家」；
        // 事件标题从 17pt 提到 28pt（这是给人看的海报，不是屏幕内的一行）。
        VStack(alignment: .leading, spacing: V8.S.gapM) {
            Image(systemName: isAlarm ? "exclamationmark.triangle.fill" : "lock.open.fill")
                .font(V8.T.title2)
                .foregroundStyle(isAlarm ? V8.C.danger : V8.C.accent)
                .accessibilityHidden(true)
            Text(entry.event)
                .font(V8.T.title2)
                .foregroundStyle(V8.C.ink1)
                .fixedSize(horizontal: false, vertical: true)
            Text(thirdLine)
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack(spacing: V8.S.gapXS) {
                Image(systemName: "lock.rotation")
                    .font(V8.T.label)
                    .foregroundStyle(V8.C.ink4)
                    .accessibilityHidden(true)
                Text("锁管家 · 单条记录 · 仅含本条数据")
                    .font(V8.T.label)
                    .foregroundStyle(V8.C.ink4)
                    .tracking(V8.G.heroLabelTracking)
            }
        }
        .padding(V8.S.gapXXL)
        .frame(width: RecordExportCardSize.width, height: RecordExportCardSize.height, alignment: .topLeading)
        .background(V8.C.card, in: .rect(cornerRadius: V8.R.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: V8.R.card, style: .continuous)
                .strokeBorder(V8.C.line, lineWidth: V8.S.hair)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 等比缩放容器（只缩不放）

private struct RecordExportScaledCard<Content: View>: View {
    let designWidth: CGFloat
    let designHeight: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            let scale = min(1, geo.size.width / designWidth)
            content
                .frame(width: designWidth, height: designHeight)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: designWidth * scale, height: designHeight * scale, alignment: .topLeading)
        }
        .aspectRatio(designWidth / designHeight, contentMode: .fit)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - 过渡别名（待 Lead 改 Destinations.swift 后删除）
