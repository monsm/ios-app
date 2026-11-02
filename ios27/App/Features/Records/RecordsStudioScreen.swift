// RecordsStudioScreen.swift —— 记录工作室（自然语言检索 / 完整筛选 / 统计 / 原始帧 hex）。
//
// 来源：原 App/Core/RecordSearch*.swift（554 时间短语、555 加减号、564-572 筛选、574 活跃凭证）+
//   App/Core/StatsKit.swift（统计与图表）+ App/UI/RecordsRows.swift（原始协议帧 hex 导出）。
// 这屏干什么：在台账页之外提供一块「检索工作台」：
//   ① 自然语言 + 加减号检索（RecordSearch.parse，支持「上周 / 最近7天 / 昨晚」等时间短语）；
//   ② 时段 / 成员 / 告警 / 失败 / 越界窗口的完整筛选；
//   ③ 上周小结、活跃凭证、近 7 日柱图；
//   ④ 原始协议帧 hex 导出（只导出脱敏后的帧头，绝不含 skey/ekey/PIN）。
// 数据从哪来：RecordSearch.buildRecs / StatsKit / LockService.recentFrames + FrameRedact。
// 主动作：「检索」是输入即算，没有按钮。
import SwiftUI
import UIKit

struct RecordsStudioScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    @State private var query = ""
    @State private var segment = 0
    @State private var member = ""
    @State private var alarmOnly = false
    @State private var failedOnly = false
    @State private var kind = ""
    @State private var outOfWindowOnly = false
    @State private var recs: [Rec] = []
    /// 跨锁时间线里"锁端没读到时钟"的条数（单锁路径会告知，这里此前不告知）。
    @State private var untimed = 0
    @State private var digest: [String] = []
    @State private var activeCreds: [(kind: String, word: String, count: Int)] = []
    @State private var frames: [String] = []
    @State private var outcome: String?

    private var macs: [String] { DB.keychains().map(\.mac) }
    private var mac: String { app.currentMac }

    private var parsed: RecordSearch.Query { RecordSearch.parse(query) }

    private var filtered: [Rec] {
        let outWin = outOfWindowOnly ? Set(RecordSearch.outOfWindow(macs: macs).map { $0.rec.id }) : Set<String>()
        let q = parsed
        return recs.filter { rec in
            var hay = [rec.typeName, rec.lockName, rec.whoName ?? "", rec.cred, rec.timeStr].joined(separator: " ").lowercased()
            if let note = noteText(rec) { hay += " " + note.lowercased() }
            if q.not.contains(where: { hay.contains($0.lowercased()) }) { return false }
            if !q.must.allSatisfy({ hay.contains($0.lowercased()) }) { return false }
            if let m = q.member, !m.isEmpty, (rec.whoName ?? "") != m { return false }
            if let k = q.credKind, !k.isEmpty, (rec.kind ?? "") != k { return false }
            if q.alarmOnly && !rec.alarm { return false }
            if let range = q.range {
                guard let d = date(rec) else { return false }
                if d < range.from || d >= range.to { return false }
            }
            if segment != 0, !inSegment(rec) { return false }
            if !member.isEmpty, (rec.whoName ?? "") != member { return false }
            if alarmOnly && !rec.alarm { return false }
            if failedOnly && rec.type != 10 { return false }
            if !kind.isEmpty, (rec.kind ?? "") != kind { return false }
            if outOfWindowOnly && !outWin.contains(rec.id) { return false }
            return true
        }
    }

    private var members: [String] {
        Array(Set(recs.compactMap { $0.whoName }.filter { !$0.isEmpty })).sorted()
    }

    var body: some View {
        // 全换系统（2026-11-02）：整页容器是系统 `List`（与门页同一配方）。
        // 检索框已交给 `.searchable`（第 2 轮），本页不再自绘搜索框 —— 这里只把五个段落装进 List。
        // 结果列表是**行式内容** → `Section`；其余四段是卡片（筛选芯片组、统计摘要、原始帧），
        // 用 `cardRow()`（`.plain` 样式没有系统左右留白，cardRow 补回 pageGutter）。
        List {
            header.headerRow()
            searchCard.cardRow()
            filterCard.cardRow()
            statsCard.cardRow()
            // 2026-11-01：跨锁时间线此前**不告知**"有 N 条日志锁端没回时刻"（单锁路径会说）。
            // 这些行被 `buildRecs` 跳过（没有时刻就不进时间线），用户只会看到"记录变少了"。
            // 状态行不是卡片，保留 plainRow()（它自带内边距，贴边也不违和）。
            if untimed > 0 {
                VStatusLine(tone: .attention, text: "另有 \(untimed) 条日志锁端没回时刻，未进时间线（不是丢失，是锁钟未读到）。")
                    .plainRow()
            }
            if filtered.isEmpty {
                emptyCard.cardRow()
            } else {
                resultSection
            }
            hexCard.cardRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, V.Page.topSpace, for: .scrollContent)
        .contentMargins(.bottom, V.S.gapL, for: .scrollContent)
        .background(V.C.bg.ignoresSafeArea())
        .navigationTitle("记录工作室")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: Text("如：上周 指纹 -临时码 / 昨晚 告警"))
        .onAppear { reload() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: V.S.gapXXS) {
            Text("记录工作室")
                .font(V.F.displayA).foregroundStyle(V.C.text1)
            Text("自然语言检索 · 完整筛选 · 统计 · 原始帧")
                .font(V.F.footnote).foregroundStyle(V.C.text3)
        }
    }

    private var searchCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "自然语言检索", showsChevron: false)
                // 输入框已交给系统搜索栏（.searchable）——这里只留语法提示，不再自绘一个假搜索框。
                Divider()
                if !parsed.parsedTags.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: V.S.gapS) {
                            // 2026-11-01 修复：`parsedTags` 是按输入 token 逐个 append 的，
                            // 用户写 `+指纹 +指纹`（或重复一个时间范围）就会出现**重复项**，
                            // 而 `ForEach(id: \.self)` 的 ID 必须唯一 —— 重复会让 SwiftUI 报
                            // "ID occurs multiple times within the collection" 并可能让标签错位。
                            // 显示前按首次出现去重（解析结果本身不动，语义不受影响）。
                            ForEach(uniqueTags, id: \.self) { tag in
                                VTag(text: tag, tint: V.C.blue)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                Text("支持 +必含 / -排除 / 时间短语（今天、昨天、上周、本月、最近 N 天、N月D日）/ 成员名 / 凭证类词 / 告警 / 失败。")
                    .font(V.F.micro).foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var filterCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "筛选", showsChevron: false)
                Text("时段").font(V.F.chipLabel).foregroundStyle(V.C.text4)
                HStack(spacing: V.S.gapS) {
                    ForEach([(value: 0, label: "全部"), (value: 1, label: "早 6-10"), (value: 2, label: "午 10-15"), (value: 3, label: "晚 15-22"), (value: 4, label: "深夜")], id: \.value) { item in
                        Button { segment = item.value } label: {
                            VTag(text: item.label, tint: segment == item.value ? V.C.blue : V.C.text3, filled: segment == item.value)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !members.isEmpty {
                    Text("成员").font(V.F.chipLabel).foregroundStyle(V.C.text4)
                    ScrollView(.horizontal) {
                        HStack(spacing: V.S.gapS) {
                            Button { member = "" } label: { VTag(text: "全部", tint: member.isEmpty ? V.C.blue : V.C.text3, filled: member.isEmpty) }
                                .buttonStyle(.plain)
                            ForEach(members, id: \.self) { name in
                                Button { member = name } label: {
                                    VTag(text: name, tint: member == name ? V.C.blue : V.C.text3, filled: member == name)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                Text("凭证类型").font(V.F.chipLabel).foregroundStyle(V.C.text4)
                HStack(spacing: V.S.gapS) {
                    ForEach(Array([(key: "", label: "全部"), (key: "pwd", label: "密码"), (key: "temp", label: "临时码"), (key: "fp", label: "指纹"), (key: "key", label: "手机钥匙")].enumerated()), id: \.offset) { pair in
                        let item = pair.element
                        Button { kind = item.key } label: {
                            VTag(text: item.label, tint: kind == item.key ? V.C.blue : V.C.text3, filled: kind == item.key)
                        }
                        .buttonStyle(.plain)
                    }
                }
                VRowDivider()
                VToggleRow(title: "只看告警", isOn: $alarmOnly)
                VToggleRow(title: "只看失败事件", isOn: $failedOnly)
                VToggleRow(title: "只看越界窗口的临时码开门", detail: "临时码开门落在所有临时码窗口之外 = 可能是伪造或时钟偏差。", isOn: $outOfWindowOnly)
            }
        }
    }

    private var statsCard: some View {
        VCard(style: .warm) {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "统计", showsChevron: false)
                if digest.isEmpty {
                    Text("还没有足够的日志做统计。先到台账页「读取锁内日志」。")
                        .font(V.F.footnote).foregroundStyle(V.C.text3)
                } else {
                    ForEach(digest, id: \.self) { line in
                        Text(line).font(V.F.body).foregroundStyle(V.C.text9)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !activeCreds.isEmpty {
                    VRowDivider()
                    Text("近 30 天活跃凭证（约）").font(V.F.chipLabel).foregroundStyle(V.C.text4)
                    ForEach(Array(activeCreds.prefix(5).enumerated()), id: \.offset) { pair in
                        HStack {
                            Text(pair.element.word).font(V.F.rowDetail).foregroundStyle(V.C.text1)
                            Spacer(minLength: 0)
                            Text("\(pair.element.count) 次").font(V.F.rowDetail).foregroundStyle(V.C.text3).monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    private var emptyCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapM) {
                Text("这些条件下没有记录").font(V.F.displayB).foregroundStyle(V.C.text1)
                Text("检索词或筛选把记录筛掉了。清空条件回到全部记录。")
                    .font(V.F.body).foregroundStyle(V.C.text2)
                VActionButton(title: "清空条件", systemImage: "line.3.horizontal.decrease.circle") {
                    query = ""; segment = 0; member = ""; alarmOnly = false; failedOnly = false; kind = ""; outOfWindowOnly = false
                }
            }
        }
    }

    /// 结果 = 系统 `Section`：一条一行（上限 60 条，与旧版同口径）。
    private var resultSection: some View {
        Section {
            ForEach(filtered.prefix(60)) { rec in
                HStack(spacing: V.S.gapS) {
                    Circle().fill(rec.alarm ? V.C.coral : V.C.rewardGreen)
                        .frame(width: V.List.dotSize, height: V.List.dotSize)
                    VStack(alignment: .leading, spacing: V.S.gapXXS) {
                        Text(rec.typeName).font(V.F.rowDetail).foregroundStyle(V.C.text1).lineLimit(1)
                        Text("\(rec.timeStr) · \(rec.lockName) · \(rec.cred)")
                            .font(V.F.micro).foregroundStyle(V.C.text3).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(rec.whoName ?? "未归属").font(V.F.micro).foregroundStyle(V.C.text3)
                }
                .frame(minHeight: V.List.rowMinHeight)
                .listRowInsets(EdgeInsets(top: 0, leading: V.S.cardPad, bottom: 0, trailing: V.S.cardPad))
            }
        } header: {
            HStack(spacing: V.S.gapS) {
                Text("结果")
                    .font(V.F.section)
                    .foregroundStyle(V.C.text1)
                Spacer(minLength: 0)
                Text("\(filtered.count) 条")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text3)
                    .monospacedDigit()
            }
            .textCase(nil)
        }
    }

    private var hexCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "原始协议帧 hex", showsChevron: false)
                VValueRow(label: "内存环", value: "\(frames.count) 帧", note: "帧头 8 字节已脱敏；载荷（skey / ekey / PIN / 密码）整段遮掉，绝不导出明文。")
                if frames.isEmpty {
                    Text("还没有最近帧。做一次开锁或读状态，帧会出现在这里。")
                        .font(V.F.footnote).foregroundStyle(V.C.text3)
                } else {
                    Text(frames.prefix(8).joined(separator: "\n"))
                        .font(V.F.micro.monospaced())
                        .foregroundStyle(V.C.text3)
                        .lineLimit(8)
                        .textSelection(.enabled)
                    VOutlineButton(title: "复制全部帧（已脱敏）", systemImage: "doc.on.doc") {
                        Clip.set(frames.joined(separator: "\n"))
                        outcome = "已复制 \(frames.count) 条脱敏帧"
                    }
                }
                if let outcome {
                    Text(outcome).font(V.F.footnote).foregroundStyle(V.C.rewardGreen)
                }
            }
        }
    }

    // MARK: - 数据

    /// `parsedTags` 去重后的显示用列表（保持首次出现的顺序）。
    private var uniqueTags: [String] {
        var seen = Set<String>()
        return parsed.parsedTags.filter { seen.insert($0).inserted }
    }

    private func reload() {
        recs = RecordSearch.buildRecs(macs: macs)
        untimed = RecordSearch.untimedCount(macs: macs)
        if !mac.isEmpty {
            digest = StatsKit.build(mac: mac).lastWeekDigest().lines
            activeCreds = RecordSearch.activeCredentials(mac: mac)
        }
        frames = LockService.shared.recentFrames.map { FrameRedact.apply($0) }
    }

    private func noteText(_ rec: Rec) -> String? {
        let note = RecordOverlay.note(rec.mac, rec.key)
        return note.isEmpty ? nil : note
    }

    private func date(_ rec: Rec) -> Date? {
        DF.stamp.date(from: rec.timeStr)
    }

    private func inSegment(_ rec: Rec) -> Bool {
        guard let d = date(rec) else { return false }
        let hour = TimeFormat.calendar.component(.hour, from: d)
        switch segment {
        case 1: return (6 ..< 10).contains(hour)
        case 2: return (10 ..< 15).contains(hour)
        case 3: return (15 ..< 22).contains(hour)
        case 4: return hour >= 22 || hour < 6
        default: return true
        }
    }
}

#Preview("RecordsStudioScreen") {
    NavigationStack { RecordsStudioScreen() }
        .environment(AppModel())
        .environment(Router())
}
