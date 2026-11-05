// RecordsStudioHomeScreen.swift —— 记录工作室（V8 设计语言）
//
// 与 RecordsStudioScreen 的能力对齐：① 自然语言 + 加减号检索（RecordSearch.parse，支持「上周 / 最近 7 天 / 昨晚」等时间短语）
// ② 时段 / 成员 / 告警 / 失败 / 越界窗口的完整筛选 ③ 上周小结、活跃凭证 ④ 原始帧（已脱敏）导出
//    ⑤「导出」段（原 recordExport 页整段并入：RecordsExportSection，同源 WeeklyDigest）。
// 数据仍来自 RecordSearch.buildRecs / StatsKit / LockService.recentFrames + FrameRedact / RecordsSource。
//
// 与旧页的刻意差异：
//   ① 空壳模式（胁迫码）整页不检索、不显示帧 —— 帧是内存里真实的协议记录，不属于「数据层返回空集」那一类。
//   ② 统计与列表两个范围写在卡头上（列表=全部锁，统计=当前锁），不再靠用户自己发现两个数字对不上。
import SwiftUI
import UIKit

struct RecordsStudioHomeScreen: View {
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
    @State private var untimed = 0
    @State private var digest: [String] = []
    @State private var activeCreds: [(kind: String, word: String, count: Int)] = []
    @State private var frames: [String] = []
    @State private var outcome: String?
    @State private var confirmCopyFrames = false
    /// 越界窗口的判定要遍历「全部锁 × 全部临时码 × 全部日志」，很贵 ——
    /// 进页算一次存起来，不在每次 body 求值时重算。
    @State private var outOfWindowIDs: Set<String> = []

    private var macs: [String] { DB.keychains().map(\.mac) }
    private var mac: String { app.currentMac }
    private var decoyed: Bool { DB.isDecoy }
    private var readOnly: Bool { app.trialGuard }

    private var parsed: RecordSearch.Query { RecordSearch.parse(query) }


    private var filtered: [Rec] {
        let outWin = outOfWindowOnly ? outOfWindowIDs : Set<String>()
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

    private var hasAnyFilter: Bool {
        segment != 0 || !member.isEmpty || alarmOnly || failedOnly || !kind.isEmpty || outOfWindowOnly
    }

    private var uniqueTags: [String] {
        var seen = Set<String>()
        return parsed.parsedTags.filter { seen.insert($0).inserted }
    }

    private var currentLockName: String {
        guard !mac.isEmpty, let kc = DB.keychain(mac) else { return "当前锁" }
        return LockArchive.displayName(kc)
    }

    private var judgement: String {
        if decoyed { return "空壳模式下不检索" }
        if app.lock == nil && macs.isEmpty { return "还没有门锁" }
        if recs.isEmpty { return "还没有读到的记录" }
        if filtered.isEmpty { return "这些条件下没有记录" }
        return "\(filtered.count) 条命中"
    }

    private var lead: String {
        if decoyed {
            return DecoyCopy.notProvided("检索与原始帧都会把日志摊开")
        }
        return "检索是输入即算，没有按钮。列表是全部锁，统计只算当前锁 —— 两个范围分开写，不混在一起。"
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            if decoyed {
                EmptyView()
            } else {
                chipRow
            }
        } content: {
            if decoyed {
                decoyCard
            } else if app.lock == nil && macs.isEmpty {
                VEmpty(
                    title: "添加一把门锁",
                    reason: "记录工作室检索的是锁内日志缓存。先添加并配对一把锁，读一次日志再回来。",
                    actionTitle: "添加门锁"
                ) { router.request(.dest(.addLock)) }
            } else {
                searchCard
                filterCard
                statsCard
                if untimed > 0 {
                    untimedCard
                }
                if recs.isEmpty {
                    VFailure(
                        what: "锁内日志还没读出来",
                        why: "这台锁的日志缓存是空的 —— 可能从没读过，也可能换过手机后缓存还没重建。",
                        next: "到记录页点「读取锁内日志」，回来再检索。",
                        retry: { router.request(.dest(.records)) }
                    )
                } else if filtered.isEmpty {
                    emptyResultCard
                } else {
                    resultCard
                }
                frameCard
                // 02 §3.3 M10：recordExport 并入为「导出」段（同源 WeeklyDigest，不再单独成路由）。
                RecordsExportSection()
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .v8Confirm(
            isPresented: $confirmCopyFrames,
            title: "复制这些帧到剪贴板？",
            consequence: "复制的是已脱敏的帧头（密钥、PIN 与密码整段遮掉），不含明文。剪贴板 90 秒后自动清空，但已经粘贴出去的文本收不回来。",
            confirmTitle: "复制",
            isDestructive: false
        ) {
            copyFrames()
        }
    }

    // MARK: - 芯片行

    private var chipRow: some View {
        VHScroll {
            HStack(spacing: V8.S.gapChip) {
                VChip2(icon: .ring(1, V8.C.accent), label: "记录", value: "\(recs.count) 条")
                VChip2(icon: .ring(recs.isEmpty ? 0.02 : Double(filtered.count) / Double(max(recs.count, 1)), V8.C.info),
                       label: "命中", value: "\(filtered.count) 条")
                VChip2(icon: .ring(0.02, V8.C.warn), label: "越界", value: "\(outOfWindowIDs.count) 条")
                VChip2(icon: .ring(0.4, V8.D.fingerprint), label: "最近帧", value: "\(frames.count) 帧")
            }
            .padding(.leading, V8.S.gutterCard)
            .padding(.trailing, V8.S.gutterCard)
        }
        .scrollClipDisabled()
    }

    // MARK: - 卡 1 自然语言检索

    private var searchCard: some View {
        VCard2 {
            VCardHead(eyebrow: "自然语言检索", statement: "输入即算", trailing: uniqueTags.isEmpty ? nil : "\(uniqueTags.count) 个条件")
            VDivider2()
                .padding(.top, V8.S.gapM)
            HStack(spacing: V8.S.gapS) {
                Image(systemName: "magnifyingglass")
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
                    .accessibilityHidden(true)
                TextField("如：上周 指纹 -临时码 / 昨晚 告警", text: $query)
                    .font(V8.T.body)
                    .foregroundStyle(V8.C.ink1)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .frame(minHeight: V8.H.min)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(V8.T.caption)
                            .foregroundStyle(V8.C.ink4)
                    }
                    .buttonStyle(V8PressStyle())
                    .accessibilityLabel("清空检索词")
                }
            }
            .padding(.top, V8.S.gapM)
            if !uniqueTags.isEmpty {
                VHScroll {
                    HStack(spacing: V8.S.gapS) {
                        ForEach(uniqueTags, id: \.self) { tag in
                            Text(tag)
                                .font(V8.T.caption)
                                .foregroundStyle(V8.C.info)
                                .padding(.horizontal, V8.S.gapM)
                                .frame(minHeight: V8.H.min)
                                .background(Capsule(style: .continuous).fill(V8.C.infoTrack))
                        }
                    }
                }
                .padding(.top, V8.S.gapS)
            }
            Text("支持 +必含 / -排除 / 时间短语（今天、昨天、上周、本月、最近 N 天、N 月 D 日）/ 成员名 / 凭证类词 / 告警 / 失败。")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
            Text("这一页只读本机缓存，不连门锁 —— 离线或未连接时，检索结果与统计完全一样。")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapXS)
                .fixedSize(horizontal: false, vertical: true)
            if query.isEmpty && !hasAnyFilter {
                Text("还没有输入检索词 —— 下面是全部记录。输入 +必含 / -排除 或时间短语就会立刻缩小。")
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
                    .padding(.top, V8.S.gapXS)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 卡 2 筛选

    private var filterCard: some View {
        VCard2 {
            VCardHead(eyebrow: "筛选", statement: filterStatement, trailing: "全部本机")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("时段")
                .font(V8.T.label)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
            VHScroll {
                HStack(spacing: V8.S.gapS) {
                    ForEach(Self.segments, id: \.value) { item in
                        choiceChip(item.label, on: segment == item.value) { segment = item.value }
                    }
                }
            }
            .padding(.top, V8.S.gapS)
            if !members.isEmpty {
                Text("成员")
                    .font(V8.T.label)
                    .foregroundStyle(V8.C.ink4)
                    .padding(.top, V8.S.gapM)
                VHScroll {
                    HStack(spacing: V8.S.gapS) {
                        choiceChip("全部", on: member.isEmpty) { member = "" }
                        ForEach(members, id: \.self) { name in
                            choiceChip(name, on: member == name) { member = name }
                        }
                    }
                }
                .padding(.top, V8.S.gapS)
            }
            Text("凭证类型")
                .font(V8.T.label)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
            VHScroll {
                HStack(spacing: V8.S.gapS) {
                    ForEach(Self.credKinds, id: \.key) { item in
                        choiceChip(item.label, on: kind == item.key) { kind = item.key }
                    }
                }
            }
            .padding(.top, V8.S.gapS)
            VDivider2()
                .padding(.top, V8.S.gapM)
            toggleRow("只看告警", isOn: $alarmOnly)
            toggleRow("只看失败事件", isOn: $failedOnly)
            toggleRow("只看越界窗口的临时码开门", detail: "临时码开门落在所有临时码窗口之外 = 可能是伪造或时钟偏差。", isOn: $outOfWindowOnly)
            Button {
                resetFilters()
            } label: {
                Text("清空条件")
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
            .accessibilityLabel("清空全部筛选条件")
            .padding(.top, V8.S.gapM)
        }
    }

    private var filterStatement: String {
        let bits = [segmentLabel, member, credKindLabel].filter { !$0.isEmpty }
        if bits.isEmpty && !alarmOnly && !failedOnly && !outOfWindowOnly { return "未设条件" }
        return bits.isEmpty ? "只看状态" : bits.joined(separator: " · ")
    }

    private var segmentLabel: String {
        Self.segments.first { $0.value == segment }?.label ?? ""
    }

    private var credKindLabel: String {
        guard !kind.isEmpty else { return "" }
        return Self.credKinds.first { $0.key == kind }?.label ?? ""
    }

    private static let segments: [(value: Int, label: String)] = [
        (0, "全部"), (1, "早 6-10"), (2, "午 10-15"), (3, "晚 15-22"), (4, "深夜")
    ]

    private static let credKinds: [(key: String, label: String)] = [
        ("", "全部"), ("pwd", "密码"), ("temp", "临时码"), ("fp", "指纹"), ("key", "手机钥匙")
    ]

    private func choiceChip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(V8.T.tab)
                .foregroundStyle(on ? V8.C.chipOn : V8.C.ink1)
                .padding(.horizontal, V8.S.gapM)
                .frame(minHeight: V8.H.min)
                .background(Capsule(style: .continuous).fill(on ? V8.C.accent : V8.C.chipOff))
        }
        .buttonStyle(V8PressStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func toggleRow(_ title: String, detail: String? = nil, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: V8.S.gapXS) {
                Text(title)
                    .font(V8.T.value)
                    .foregroundStyle(V8.C.ink1)
                if let detail {
                    Text(detail)
                        .font(V8.T.caption)
                        .foregroundStyle(V8.C.ink4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(minHeight: V8.H.min)
        .padding(.top, V8.S.gapS)
    }

    // MARK: - 卡 3 统计

    private var statsCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "统计 · " + currentLockName, statement: digest.isEmpty ? "还没有足够的日志" : "上周与近 30 天", trailing: mac.isEmpty ? nil : "只算当前锁")
            VDivider2()
                .padding(.top, V8.S.gapM)
            if digest.isEmpty {
                Text("还没有足够的日志做统计。先到记录页「读取锁内日志」。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: V8.S.gapS) {
                    ForEach(Array(digest.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(V8.T.body)
                            .foregroundStyle(V8.C.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, V8.S.gapM)
            }
            if !activeCreds.isEmpty {
                VDivider2()
                    .padding(.top, V8.S.gapM)
                Text("近 30 天开门构成（约）")
                    .font(V8.T.label)
                    .foregroundStyle(V8.C.ink4)
                    .padding(.top, V8.S.gapM)
                VStack(spacing: 0) {
                    ForEach(Array(activeCreds.prefix(5).enumerated()), id: \.offset) { index, pair in
                        if index > 0 { VDotRule() }
                        // 2026-11-05（截图审查带出的同类问题）：tag 与 title 传同一个词，
                        // 每行把「密码」「指纹」写两遍。类别名归 tag，title 留空。
                        VDataRow(tag: pair.word, tagTint: V8.C.ink4, title: "", value: "\(pair.count)", unit: "次")
                    }
                }
                .padding(.top, V8.S.gapS)
            }
        }
    }

    private var untimedCard: some View {
        VCard2(style: .well) {
            Text("另有 \(untimed) 条日志锁端没回时刻，未进时间线（不是丢失，是锁钟未读到）。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.warn)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 卡 4 结果

    private var emptyResultCard: some View {
        VEmpty(
            title: "清空筛选条件",
            reason: "检索词或筛选把记录筛掉了 —— 上面的记录本身还在。清空条件就能回到全部记录。",
            actionTitle: "清空条件"
        ) {
            resetFilters()
        }
    }

    private var resultCard: some View {
        VCard2 {
            VCardHead(eyebrow: "结果", statement: "\(filtered.count) 条命中", trailing: "最多列 60 条")
            VDivider2()
                .padding(.top, V8.S.gapM)
            if filtered.count > 60 {
                Text("共 \(filtered.count) 条，下面只列最近 60 条 —— 用上面的搜索词缩小范围。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.warn)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                ForEach(Array(filtered.prefix(60).enumerated()), id: \.offset) { index, rec in
                    if index > 0 { VDotRule() }
                    VDataRow(
                        tag: rec.timeStr,
                        tagTint: rec.alarm ? V8.C.danger : V8.C.ok,
                        title: rec.typeName,
                        detail: rec.lockName + " · " + rec.cred,
                        value: rec.whoName ?? "未归属"
                    )
                }
            }
            .padding(.top, V8.S.gapS)
            VNavRow(title: "到记录页打开（可选行看详情）", detail: "这一页的结果行只读，详情要到记录页打开") {
                router.request(.dest(.records))
            }
            .padding(.top, V8.S.gapS)
        }
    }

    // MARK: - 卡 5 原始帧（已脱敏）

    private var frameCard: some View {
        VCard2 {
            VCardHead(eyebrow: "最近帧（已脱敏）", statement: frames.isEmpty ? "还没有最近帧" : "帧头已脱敏", trailing: "\(frames.count) 帧")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("帧头 8 字节已脱敏；载荷（密钥、PIN、密码）整段遮掉，绝不导出明文。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            if frames.isEmpty {
                Text("还没有最近帧。做一次开锁或读状态，帧会出现在这里。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink4)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(frames.prefix(8).joined(separator: "\n"))
                    .font(V8.T.micro)
                    .foregroundStyle(V8.C.ink3)
                    .lineLimit(20)
                    .textSelection(.enabled)
                    .padding(.top, V8.S.gapS)
                Button {
                    confirmCopyFrames = true
                } label: {
                    Text("复制全部帧（已脱敏）")
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
                .accessibilityLabel("复制全部已脱敏帧")
                .padding(.top, V8.S.gapM)
            }
            if let outcome {
                Text(outcome)
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ok)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if readOnly {
                Text("只读试验模式开着：本页只读本机缓存，不下发任何命令，不受影响。")
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 空壳

    private var decoyCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "记录工作室", statement: "空壳模式不检索")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("空壳模式（胁迫码进入）下不显示台账、统计与帧 —— 检索会把整本台账摊在屏幕上，这里不提供。")
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

    private func reload() {
        guard !decoyed else {
            recs = []
            untimed = 0
            digest = []
            activeCreds = []
            frames = []
            outOfWindowIDs = []
            return
        }
        recs = RecordSearch.buildRecs(macs: macs)
        untimed = RecordSearch.untimedCount(macs: macs)
        if !mac.isEmpty {
            digest = StatsKit.build(mac: mac).lastWeekDigest().lines
            activeCreds = RecordSearch.activeCredentials(mac: mac)
        }
        frames = LockService.shared.recentFrames.map { FrameRedact.apply($0) }
        outOfWindowIDs = Set(RecordSearch.outOfWindow(macs: macs).map { $0.rec.id })
    }

    private func resetFilters() {
        query = ""
        segment = 0
        member = ""
        alarmOnly = false
        failedOnly = false
        kind = ""
        outOfWindowOnly = false
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

    private func copyFrames() {
        Clip.set(frames.joined(separator: "\n"))
        outcome = "已复制 \(frames.count) 条脱敏帧"
    }
}
