// 包9 告警中心 (723-724/726-743/745-747) — 跨锁告警流 + 四级色标 + 处置留痕 + 回放刻度
// 头注释写成 `723-743` 时把 725 也算了进来，而 725 (胁迫全屏确认卡) 判 ❌: 协议日志类型表
// (CAPABILITY §3) 根本没有胁迫类告警，这个文件里没有它的任何实现。**区间列举不许盖住判 ❌ 的编号** ——
// 覆盖表 (tools/featuremap.js) 就是按这行把头注释里的区间展开的，于是一个没做的编号被记成"有标注"。
// 它的替代"高危告警确认卡"(用真实存在的防撬 7/试错锁定 10/224) 同样未建, 记在 docs/DECISION-NEEDED.md。
// 纪律: 告警类型只用 CAPABILITY §3 真实存在的 5 种; 处置/测试标记走 RecordSearch.dispositions 本地留痕;
//       颜色只经 DS 令牌 (danger 派生 .opacity, 形状冗余); 归属推断标"约";
//       742 响应时长分布占位"积累中" (依赖处置时间积累), 737 试错累计 keyboardErrCount 语义标"?"。
import SwiftUI
import UIKit

struct AlarmCenterView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    /// 768/778: 从全部锁总览的待维护行/活跃度行下钻时带 LockOverviewView 的 mac —
    /// 只流这一把锁的告警。nil = 跨锁流 (记录页铃铛入口的默认形态, 一行行为不变)。
    var lockMac: String? = nil
    @State private var unhandledOnly = true     // 734 未处理队列优先 (默认)
    @State private var typeFilter: Int = 0      // 723 按告警类型过滤 (0 = 全部)
    @State private var openContextKey: String?  // 736 展开的前后事件上下文
    @State private var openDetailKey: String?   // 单条详情段 (处置/清单/对比)
    @State private var scrubHour: Int = RecordSearch.replayHour()  // 730 24 小时回放刻度
    @State private var tick = 0                  // 处置状态刷新
    @State private var showOlder = false         // 682 "更早"组是否展开 (纯视图状态, 不写盘)

    private var macs: [String] { lockMac.map { [$0] } ?? DB.keychains().map { $0.mac } }
    /// 单锁下钻时标题带上锁名 —— 否则进来看见"告警中心"分不清流的是哪把锁的
    private var centerTitle: String {
        guard let m = lockMac, let kc = DB.keychain(m) else { return "告警中心" }   // 723 告警中心
        return LockArchive.displayName(kc) + " · 告警流"
    }

    var body: some View {
        NavigationStack {
            List {
                streamHeader
                replayRuler   // 730
                alarmList
                trialCard     // 737 试错累计
                responseCard   // 742 响应时长 (占位)
            }
            .navigationTitle(centerTitle)
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear { tick += 1 }
        }
    }

    private var stream: [Rec] {
        let recs = RecordSearch.alarmStream(macs: macs, unhandledOnly: unhandledOnly)
            .filter { typeFilter == 0 || $0.type == typeFilter }
        return scrubHour >= 0 ? recs.filter { isHour($0, scrubHour) } : recs
    }
    /// 743 收尾判据的对照集: 同一过滤条件下**不带未处理收窄**的全部告警 ——
    /// "已全部处置"必须拿它判 (拿收窄后的 stream 判恒为空), 与 stream 同一套过滤, 只差收窄一步。
    private var allTyped: [Rec] {
        let recs = RecordSearch.alarmStream(macs: macs, unhandledOnly: false)
            .filter { typeFilter == 0 || $0.type == typeFilter }
        return scrubHour >= 0 ? recs.filter { isHour($0, scrubHour) } : recs
    }
    /// 743 队列收尾文案: 有剩 = 共 N 条; 未处理清零但有已处置 = "已全部处置"; 一条都没有才写"没有告警"
    private var streamNote: String {
        if !stream.isEmpty { return "共 \(stream.count) 条" }
        if unhandledOnly && !allTyped.isEmpty { return "已全部处置" }
        return "没有告警"
    }
    private func isHour(_ r: Rec, _ h: Int) -> Bool {
        guard let d = RecordSearch.dateOf(r) else { return false }
        return WeekCal.gregorian.component(.hour, from: d) == h
    }

    /// 731 多锁联动事件合并: 多把锁在 30 分钟内先后报低电 (type 6) 时, 顶部合并成一张事件卡。
    /// 判据只用**本机读到的日志时刻** —— 协议没有"多锁联动"语义, 不假装有; 这是时间窗启发式, 卡片里写明。
    /// 返回命中的那一条时间窗里涉及到的锁与时刻 (涉及 ≥2 把锁才算命中, 单锁低电不合并)。
    private var lowBatteryCluster: [(lock: String, time: String)] {
        let lows = stream.filter { $0.type == 6 }
        guard lows.count >= 2 else { return [] }
        var best: [Rec] = []
        for (i, a) in lows.enumerated() {
            guard let ta = RecordSearch.dateOf(a) else { continue }
            var group = [a]
            for b in lows[(i + 1)...] {
                guard b.mac != a.mac, let tb = RecordSearch.dateOf(b),
                      abs(tb.timeIntervalSince(ta)) <= 1800 else { continue }
                group.append(b)
            }
            if Set(group.map { $0.mac }).count >= 2, group.count > best.count { best = group }
        }
        return best.map { (lock: $0.lockName, time: String($0.timeStr.prefix(16))) }
    }

    /// 734 队列状态行 + 723 类型过滤 chips
    @ViewBuilder
    private var streamHeader: some View {
        Section {
            HStack(spacing: DS.Space.s) {
                Toggle(isOn: $unhandledOnly) {
                    Text("未处理优先")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DS.Palette.text)
                }
                .tint(DS.Palette.accent)
                Spacer(minLength: 0)
                Text(streamNote)
                    .font(.caption)
                    .foregroundStyle(streamNote == "已全部处置" ? DS.Palette.ok : DS.Palette.textSub)
                    .lineLimit(1)
            }
            .frame(minHeight: DS.Hit.min)
            // 类型过滤 (723: 提示/严重/紧急三档 chips, 真实 5 类)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.xs) {
                    levelChip(0, "全部")
                    levelChip(7, "防撬")
                    levelChip(224, "键盘锁定")
                    levelChip(10, "试错锁定")
                    levelChip(13, "指纹告警")
                    levelChip(6, "低电量")
                }
                .padding(.vertical, DS.Space.xxs)
            }
            // 744 替代: 原案是"胁迫详情里的科普折叠段", 但协议日志类型表没有胁迫类 (与 725 同口径),
            // 于是把科普挂到**真实存在**的告警上讲原理 —— 试错锁定 (10) / 键盘锁定 (224) / 防撬 (7)。
            // 默认折叠: 这一屏的主体是队列, 科普不该占掉首屏高度。
            DisclosureGroup {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("试错锁定：连着输错密码到锁内阈值, 锁端会自行冻结一段时间, 这期间正确的密码也不放行, 等它自己解冻。")   // 10 试错锁定
                    Text("键盘锁定：锁端键盘冻结标志为开, 通常与上面的试错计数同源; 这里只读标志, 不当成「有人在试」。")   // 224 键盘锁定
                    Text("防撬 (7)：锁体被撬动或拆离时锁端自己记的一条, 与试错无关。")
                    Text("关于「胁迫」：锁端日志类型表里没有这一类, 本 App 不虚构一个查不到的类型。")
                }
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, DS.Space.xxs)
            } label: {
                Text("这些告警是什么")   // 744 这些告警是什么
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
            }
        } header: {
            Text(unhandledOnly ? "未处理队列" : "全部告警 (含已处置 743)")   // 734 未处理队列
        }
    }
    private func levelChip(_ t: Int, _ name: String) -> some View {
        let on = typeFilter == t
        return Button {
            typeFilter = on ? 0 : t
            if on, scrubHour >= 0 { scrubHour = -1 }
        } label: {
            HStack(spacing: DS.Space.xs) {
                if t != 0 {
                    Circle().fill(RecordSearch.toneColor(for: t)).frame(width: 6, height: 6).accessibilityHidden(true)
                }
                Text(name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(on ? DS.Palette.accent : DS.Palette.surfaceAlt, in: Capsule())
            .overlay(Capsule().strokeBorder(DS.Palette.hairline, lineWidth: 0.5))
            .foregroundStyle(on ? DS.Palette.onAccent : DS.Palette.text)
            .frame(minHeight: DS.Hit.min)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// 730 24 小时回放刻度: 横向 0-23 时 scrubber, 选中小时过滤下方流
    @ViewBuilder
    private var replayRuler: some View {
        if scrubHour >= 0 || stream.contains(where: { $0.timeStr.hasPrefix(StatsKit.dayKey(Date())) }) {
            Section("24 小时回放") {   // 730 小时回放
                VStack(spacing: DS.Space.xs) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            ForEach(0..<24, id: \.self) { h in
                                let has = stream.contains { isHour($0, h) }
                                let on = scrubHour == h
                                Button {
                                    scrubHour = on ? -1 : h
                                    RecordSearch.setReplayHour(scrubHour)
                                } label: {
                                    Rectangle()
                                        .fill(on ? DS.Palette.accent : (has ? DS.Palette.warn.opacity(0.75) : DS.Palette.surfaceAlt))
                                        .frame(width: has ? 14 : 9, height: on ? 44 : 28)
                                        .overlay(alignment: .top) {
                                            if has {
                                                Circle().fill(DS.Palette.danger).frame(width: 4, height: 4).offset(y: 3)
                                                    .accessibilityHidden(true)
                                            }
                                        }
                                        .accessibilityLabel("\(h) 时" + (has ? ", 有告警" : ""))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, DS.Space.xs)
                    }
                    HStack(spacing: DS.Space.s) {
                        Text(scrubHour >= 0 ? "只看 \(scrubHour) 时前后事件" : "点下方某一小时，只看那一时段前后事件")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .lineLimit(1)
                        if scrubHour >= 0 {
                            Button("清除刻度") { scrubHour = -1; RecordSearch.setReplayHour(-1) }
                                .font(.caption.weight(.medium))
                                .foregroundStyle(DS.Palette.accentText)
                                .frame(minHeight: DS.Hit.min)
                                .contentShape(Rectangle())
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(.vertical, DS.Space.xs)
            }
        }
    }
    // 「今天」的日 key 不再有本地第二份写法：`StatsKit.dayKey` 是唯一口径 (第一百五十八批 §10.30)，
    // 此前这里另抄了一份 DateFormatter —— 值恰好相同，但那份副本正是"改一处就漂"的那一类。

    // ---------- 738 告警行: 左色条 + 浅底 (色条形状冗余: 紧急菱/严重三角/提示圆) ----------
    // 682 更早分组 (邮件归档): 超 30 天**仍未处置**的告警自动收进一条默认折叠的"更早"，
    // 不再长期占据首页。三条判据写在代码里而不是文案里：
    //  · 已处置的不算"拖着没管" ⇒ 不进这一组 (它们本来就被 734 排到后面)；
    //  · 解不出时间戳的行**留在首页** —— 宁可多占一行，也不把一条可能是昨天的告警悄悄藏起来；
    //  · 折叠是视图状态 (`showOlder`)，不写盘：归档的是"这一屏先看哪些"，不是把告警标记成已读。
    @ViewBuilder
    private var alarmList: some View {
        // 729: 误报降权集合每屏算一次 (不是每行算一次), 只用于折叠灰显, 不动 723/741 的口径
        let folded = RecordSearch.misfireFold(macs: macs)
        // 731: 多锁短窗低电合并卡 (只在这一屏顶部出现一次, 逐条处置仍在下面各自的行里)
        let cluster = lowBatteryCluster
        if !cluster.isEmpty {
            Section {
                DisclosureGroup {
                    ForEach(Array(cluster.enumerated()), id: \.offset) { _, e in
                        HStack(spacing: DS.Space.s) {
                            Text(e.lock).font(.caption).foregroundStyle(DS.Palette.text)
                                .lineLimit(1).minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                            Text(e.time).font(.caption2.monospacedDigit()).foregroundStyle(DS.Palette.textSub)
                        }
                    }
                } label: {
                    Label("\(cluster.count) 把锁在 30 分钟内先后报低电", systemImage: "battery.25percent")   // 731 把锁在
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(DS.Palette.warn)
                }
                Text("本机日志时间窗的启发式合并 —— 协议没有多锁联动语义, 不假装有; 逐条处置仍在下面各自的行里。")
                    .font(.caption2).foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        ForEach(stream.filter { !isOlder($0) }) { r in
            alarmSection(r, folded: folded)
        }
        let older = stream.filter { isOlder($0) }
        if !older.isEmpty {
            Section {
                if showOlder {
                    ForEach(older) { r in alarmSection(r, folded: folded) }
                } else {
                    Button {
                        showOlder = true
                    } label: {
                        Label("展开这 \(older.count) 条 (最早 \(String(older.map { $0.timeStr.prefix(10) }.min() ?? "—"))", systemImage: "arrow.down.circle")
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.accentText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            } header: {
                HStack(spacing: DS.Space.xs) {
                    // 682 更早
                    // 682 更早
                    Text(showOlder ? "更早 · 超 30 天仍未处置" : "更早 · 超 30 天仍未处置 \(older.count) 条")
                    Spacer(minLength: 0)
                    if showOlder {
                        Button("收起") { showOlder = false }
                            .font(.caption2)
                            .foregroundStyle(DS.Palette.accentText)
                    }
                }
            }
        }
    }
    /// 距今超过 30 天且仍未处置 ⇒ 归入"更早" (682)
    private func isOlder(_ r: Rec) -> Bool {
        guard RecordSearch.disposition(key: r.mac + "#" + r.key) == nil else { return false }
        guard r.timeStr.count >= 10, let d = RecordSearch.dateFromKey(String(r.timeStr.prefix(10))) else { return false }
        return Date().timeIntervalSince(d) > 30 * 86400
    }
    @ViewBuilder
    private func alarmSection(_ r: Rec, folded: Set<String>) -> some View {
        let isFolded = folded.contains(r.mac + "#" + r.key)
        Section {
            alarmRow(r)
                // 743 逐条滑动处置: 收件箱清零的快捷路径 —— 与行内胶囊写同一份 kf_rdispo 留痕,
                // 不是另一套状态。首按钮"已处理"允许一滑到底直接生效 (误触可走 739 恢复为未处理)。
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button { markDone(r.mac + "#" + r.key, "已处理") } label: { Label("已处理", systemImage: "checkmark.circle") }
                        .tint(DS.Palette.ok)
                    Button { markDone(r.mac + "#" + r.key, "误报") } label: { Label("误报", systemImage: "exclamationmark.bubble") }
                        .tint(DS.Palette.warn)
                }
                .opacity(isFolded ? 0.55 : 1)
            if isFolded {
                // 729: 同锁同类 24 小时内已标过「误报」→ 本行按疑似同类误报折叠灰显 (仍可展开处置)
                Text("疑似同类误报 — 同锁同类型 24 小时内已标过「误报」, 本行折叠灰显")   // 729 疑似同类误报
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if openContextKey == r.id { contextSection(r) }
            if openDetailKey == r.id { detailSection(r) }
        } header: {
            HStack(spacing: DS.Space.xs) {
                Text(r.timeStr.isEmpty ? r.typeName : String(r.timeStr.prefix(16)))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DS.Palette.textSub)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if macs.count > 1 {
                    Text(r.lockName)   // 770 跨锁前缀标签
                        .font(.caption2)
                        .foregroundStyle(DS.Palette.accentText)
                        .lineLimit(1)
                }
            }
        }
    }

    private func alarmRow(_ r: Rec) -> some View {
        let disp = RecordSearch.disposition(key: r.mac + "#" + r.key)
        let tone = RecordSearch.toneColor(for: r.type)
        let shape = shapeName(r.type)
        return VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(alignment: .top, spacing: DS.Space.s) {
                Rectangle()
                    .fill(tone)
                    .frame(width: 4)
                    .padding(.vertical, 2)
                    .accessibilityHidden(true)
                Image(systemName: shape)
                    .font(.system(size: DS.Icon.sm, weight: .medium))
                    .foregroundStyle(tone)
                    .frame(width: DS.Icon.md)
                    .accessibilityLabel(AlarmMeta.levelName(r.type))
                VStack(alignment: .leading, spacing: 2) {
                    Text(RecordSearch.alarmTitle(r))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DS.Palette.text)
                        .lineLimit(1)
                    HStack(spacing: DS.Space.xs) {
                        Text(AlarmWords.phrase(r.type))
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .lineLimit(1)
                        if let d = disp {
                            Text(d.verdict + " · " + d.atLabel())
                                .font(.caption)
                                .foregroundStyle(DS.Palette.ok)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
                Circle().fill(tone).frame(width: 8, height: 8).accessibilityHidden(true)
            }
            .frame(minHeight: DS.Hit.min)
            // 745 测试标记: 已标"测试"的行灰显排除统计口径
            if disp?.verdict == "测试" { opacity(0.55) }
            HStack(spacing: DS.Space.s) {
                rowButton(openDetailKey == r.id ? "收起处置" : "处置与留痕", systemImage: "checklist", on: openDetailKey == r.id) {   // 726 处置与留痕
                    openDetailKey = openDetailKey == r.id ? nil : r.id
                }
                rowButton("前后事件", systemImage: "text.bubble", on: openContextKey == r.id) {   // 736 前后事件
                    openContextKey = openContextKey == r.id ? nil : r.id
                }
                rowButton("同类 \(RecordSearch.sameCountPreview(r))", systemImage: "list.number", on: false) {
                    openDetailKey = r.id
                }
            }
            .accessibilityElement(children: .combine)
        }
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                .fill(tone.opacity(0.08))   // 738 浅底 (danger/warn 派生 8%, 不硬编码)
                .padding(.vertical, DS.Space.xs)
        }
        .contentShape(Rectangle())
    }
    private func shapeName(_ t: Int) -> String {
        switch AlarmMeta.level(t) {
        case 3: return "diamond.fill"       // 紧急: 菱
        case 2: return "triangle.fill"      // 严重: 三角
        default: return "circle.fill"      // 提示: 圆
        }
    }
    private func rowButton(_ title: String, systemImage: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        // 2026-10-13 run 63: 原写 `Button(action) { … }` —— Button 的 init 是 (action:label:),
        // 首个实参也要写标签 ⇒ "missing argument label 'action:' in call"。
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(on ? DS.Palette.accentText : DS.Palette.textSub)
                .padding(.horizontal, DS.Space.s)
                .padding(.vertical, DS.Space.xs + 1)
                .background((on ? DS.Palette.accentText : DS.Palette.textSub).opacity(0.09), in: Capsule())
                .frame(minHeight: DS.Hit.min)
                .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(title)
    }

    /// 736 前后事件上下文: 前后 10 分钟同锁各 3 条
    // 2026-10-13 run 57: 此前写成 `private func contextSection(_ r: Rec) {` —— 没有返回类型 (= Void),
    // 可函数体是 @ViewBuilder 形状 (多个 Section), 在 body 里又被当 View 用 (line 325) ⇒
    // 报 "type '()' cannot conform to 'View'"。补 `-> some View` (原有的 @ViewBuilder 保留, 勿再加第二个 ——
    // run 58 就是加重复了报 "only one result builder attribute can be attached to a declaration")。
    @ViewBuilder
    private func contextSection(_ r: Rec) -> some View {
        let (before, after) = RecordSearch.context(mac: r.mac, aroundKey: r.key)
        if before.isEmpty && after.isEmpty {
            Section("前后事件") {
                Text("前后 10 分钟内没有其他记录 — 孤立事件。")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
            }
        } else {
            Section("前后 10 分钟 · 同锁") {   // 736 前后
                ForEach(Array(before.enumerated()), id: \.offset) { _, x in
                    contextRow(x, tag: "前")
                }
                contextRow(r, tag: "事件")
                ForEach(Array(after.enumerated()), id: \.offset) { _, x in
                    contextRow(x, tag: "后")
                }
            }
        }
    }
    private func contextRow(_ r: Rec, tag: String) -> some View {
        HStack(spacing: DS.Space.s) {
            Text(tag)
                .font(.caption2.weight(.medium))
                .foregroundStyle(tag == "事件" ? DS.Palette.danger : DS.Palette.textSub)
                .frame(width: 30, alignment: .center)
                .lineLimit(1)
            let who = MemberHub.aliasName(r.whoId) ?? r.whoName
            Text((who?.isEmpty ?? true) ? r.typeName : who! + " · " + r.typeName)
                .font(.footnote)
                .foregroundStyle(DS.Palette.text)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(r.timeStr.isEmpty ? "--:--" : String(r.timeStr.dropFirst(11).prefix(5)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(DS.Palette.textSub)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    // ---------- 726 处置留痕 / 727 检查清单 / 739 回退 / 741 同类 / 745 测试标记 / 747 对比 ----------
    // 同 contextSection: 此前有 @ViewBuilder 却漏了 `-> some View`, 在 body 里当 View 用 (line 326) ⇒
    // "type '()' cannot conform to 'View'"。补返回类型。
    @ViewBuilder
    private func detailSection(_ r: Rec) -> some View {
        let dkey = r.mac + "#" + r.key
        let disp = RecordSearch.disposition(key: dkey)
        let same = RecordSearch.sameTypeCount(mac: r.mac, type: r.type, exceptKey: r.key)
        Section {
            // 741 同类告警计数
            HStack(spacing: DS.Space.s) {
                Image(systemName: "list.number").font(.system(size: DS.Icon.sm)).foregroundStyle(DS.Palette.textSub).accessibilityHidden(true)
                Text(same.lastStr.isEmpty
                     ? "该锁第 \(same.total) 次\(r.typeName)"
                     : "该锁第 \(same.total) 次\(r.typeName), 上次 " + String(same.lastStr.dropFirst(5).prefix(11)))
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .lineLimit(1)
            }
            // 747 前后对比小柱
            if r.type == 7 {
                aroundBars(r)
            }
            // 727 防撬检查清单 (勾选状态本地留存)
            if r.type == 7 {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("防撬检查清单")   // 727 防撬检查清单
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DS.Palette.textSub)
                    ForEach(Array(RecordSearch.tamperChecks.enumerated()), id: \.offset) { i, item in
                        let on = RecordSearch.checkState(dkey)[i]
                        Button {
                            RecordSearch.setCheck(dkey, index: i, on: !on)
                            tick += 1
                        } label: {
                            HStack(spacing: DS.Space.xs) {
                                Image(systemName: on ? "checkmark.square.fill" : "square")
                                    .font(.system(size: DS.Icon.sm))
                                    .foregroundStyle(on ? DS.Palette.ok : DS.Palette.textSub)
                                    .accessibilityHidden(true)
                                Text(item)
                                    .font(.footnote)
                                    .foregroundStyle(on ? DS.Palette.textSub : DS.Palette.text)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityLabel(item + (on ? ", 已勾选" : ""))
                    }
                }
            }
            // 728 换电指引折叠段: 低电告警详情内嵌换电注意事项 (型号/步骤/复位), 与维护页那份同一个步骤源。
            // 原句点名的"应急供电方式"本工程无出处 (厂商云停服、无手册可引), 不编; 其余四项与维护页一致。
            if r.type == 6 {
                DisclosureGroup {
                    let hint = LockArchive.meta(r.mac).batteryModel.isEmpty
                        ? "型号见锁信息名片-电池档案" : "已记型号: " + LockArchive.meta(r.mac).batteryModel
                    ForEach(Array(BatterySwapGuide.steps(modelHint: hint).enumerated()), id: \.offset) { i, s in
                        HStack(alignment: .top, spacing: DS.Space.s) {
                            Text("\(i + 1)")
                                .font(.caption2.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(DS.Palette.onAccent)
                                .frame(width: 18, height: 18)
                                .background(DS.Palette.accent, in: Circle())
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                                Text(s.title).font(.footnote.weight(.medium)).foregroundStyle(DS.Palette.text)
                                Text(s.detail).font(.caption2).foregroundStyle(DS.Palette.textSub)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 2)
                    }
                    NavigationLink { BatterySwapGuideView() } label: {
                        Label("打开完整换电指引", systemImage: "arrow.right.circle")
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.accentText)
                            .frame(minHeight: DS.Hit.min)
                    }
                } label: {
                    Label("换电注意事项", systemImage: "battery.25percent")   // 728 换电注意事项
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DS.Palette.textSub)
                }
            }
            // 726 处置结论 (已处理/误报/已处置) + 745 测试标记 + 739 回退
            HStack(spacing: DS.Space.xs) {
                disposeButton("已处理", dkey, disp)
                disposeButton("误报", dkey, disp)
                disposeButton("已处置", dkey, disp)
                disposeButton("标测试", dkey, disp, danger: true)   // 745 标测试
            }
            if disp != nil {
                HStack(spacing: DS.Space.s) {
                    Text("留痕: " + disp!.verdict + " · " + disp!.atLabel())
                        .font(.caption)
                        .foregroundStyle(DS.Palette.ok)
                        .lineLimit(1)
                    Button("恢复为未处理") {   // 739 恢复为未处理
                        RecordSearch.undoDisposition(key: dkey)
                        tick += 1
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                    Spacer(minLength: 0)
                }
            }
        } header: {
            Text("处置与留痕")   // 726 处置与留痕
        }
    }
    /// 726/743 处置落点 (行内胶囊与滑动共用): 写留痕 + 触发刷新
    private func markDone(_ key: String, _ verdict: String) {
        RecordSearch.markDisposition(key: key, verdict: verdict)
        tick += 1
    }
    private func disposeButton(_ verdict: String, _ key: String, _ disp: RecordSearch.Disposition?, danger: Bool = false) -> some View {
        let on = disp?.verdict == verdict
        return Button {
            markDone(key, verdict)
        } label: {
            Text(on ? verdict + " ✓" : verdict)
                .font(.caption.weight(.medium))
                .foregroundStyle(on ? (danger ? DS.Palette.danger : DS.Palette.accentText) : DS.Palette.textSub)
                .padding(.horizontal, DS.Space.s)
                .padding(.vertical, DS.Space.xs + 1)
                .background((on ? (danger ? DS.Palette.danger : DS.Palette.accentText) : DS.Palette.textSub).opacity(0.09), in: Capsule())
                .overlay(Capsule().strokeBorder(on ? (danger ? DS.Palette.danger : DS.Palette.accentText) : DS.Palette.hairline, lineWidth: 0.5))
                .frame(minHeight: DS.Hit.min)
                .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(verdict)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
    /// 747 防撬当日与前后 7 天开门量并排小柱
    private func aroundBars(_ r: Rec) -> some View {
        let days = RecordSearch.aroundDays(mac: r.mac, aroundKey: r.key)
        let maxC = days.map(\.count).max() ?? 1
        return VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("前后 7 天开门量 (747 · 判断试探迹象, 约)")
                .font(.caption.weight(.medium))
                .foregroundStyle(DS.Palette.textSub)
            HStack(alignment: .bottom, spacing: 3) {
                // 2026-10-13 run 63: DayOpen 不是 Identifiable ⇒ ForEach 要显式 id:。
                ForEach(days, id: \.key) { d in
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(d.isAlertDay ? DS.Palette.danger : DS.Palette.accent.opacity(0.65))
                            .frame(width: 10, height: max(4, CGFloat(d.count) / CGFloat(max(maxC, 1)) * 56))
                        Text(String(d.key.suffix(5)))
                            .font(.caption2)
                            .foregroundStyle(d.isAlertDay ? DS.Palette.danger : DS.Palette.textSub)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("红色为告警当日; 前后 7 天为本地日志统计 (约)")
                .font(.caption2)
                .foregroundStyle(DS.Palette.textSub)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    /// 737 试错累计 (⚠ keyboardErrCount 语义不确定 — 计数只用日志条数, 标题带问号)。
    /// 逐次明细只列**锁定级事件行** (锁端就是这么记的); 涉事凭证不在协议里, 明写"无法归属"而不是留白。
    @ViewBuilder
    private var trialCard: some View {
        let events = RecordSearch.trialEventsToday(macs: macs)
        let today = events.count
        // 快照层 StatusSnapshotData 无 keyboardErrCount 字段 (只有协议解析态 LockStatus 有)
        // → 改取内存实时状态; 实时态只属于当前锁 (切锁即清空), 与卡片所查锁同锁才可用, 否则按未知不显示
        let liveHere = macs.first == app.currentMac
        let kbErr = liveHere ? (app.status?.keyboardErrCount ?? 0) : 0
        let kbFreeze = liveHere ? (app.status?.keyboardFreeze ?? 0) : 0
        if today > 0 || kbErr > 0 || kbFreeze > 0 {
            Section("试错累计 (737 · ?)") {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    HStack(spacing: DS.Space.s) {
                        Image(systemName: "key.zarrowpath").font(.system(size: DS.Icon.sm)).foregroundStyle(DS.Palette.warn).accessibilityHidden(true)
                        Text("今日试错告警 \(today) 次")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(DS.Palette.text)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text("?")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(DS.Palette.textSub)
                            .lineLimit(1)
                    }
                    // 737 逐次明细: 锁端记录的每一次锁定事件 (倒序, 最多列 5 条)
                    ForEach(events.prefix(5)) { e in
                        HStack(spacing: DS.Space.xs) {
                            Text(e.timeStr.isEmpty ? "时间未知" : String(e.timeStr.dropFirst(5)))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(DS.Palette.textSub)
                                .lineLimit(1)
                            if macs.count > 1 {
                                Text(e.lockName)
                                    .font(.caption2)
                                    .foregroundStyle(DS.Palette.accentText)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    if today > 5 {
                        Text("仅列最近 5 次, 今日共 \(today) 次")
                            .font(.caption2)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    if kbFreeze > 0 {
                        Text("锁端键盘冻结标志为开 (试错锁定可能生效中)")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.warn)
                            .lineLimit(1)
                    }
                    if kbErr > 0 {
                        Text("锁端键盘错误计数为 " + String(kbErr) + " (语义未确证, 仅供参考)")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .lineLimit(1)
                    }
                    if today > 0 {
                        Text("上面每条即锁端记录的锁定级事件; 其不带凭证槽位 ⇒ 涉事凭证无法归属 (依赖协议失败明细)。")   // 569 上面每条即锁端记录的
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, DS.Space.xs)
            }
        }
    }

    /// 742 响应时长分布 (占位: 依赖处置时间积累, 现在只有 726 留痕的少量样本)
    @ViewBuilder
    private var responseCard: some View {
        let samples = RecordSearch.dispositions().values
        if samples.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    HStack(spacing: DS.Space.s) {
                        Image(systemName: "hourglass").font(.system(size: DS.Icon.sm)).foregroundStyle(DS.Palette.textSub).accessibilityHidden(true)
                        Text("响应时长分布")   // 742 响应时长分布
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(DS.Palette.text)
                            .lineLimit(1)
                    }
                    Text("处置打点后, 这里会出现「告警发生 → 确认处置」间隔分布。现在还没有留痕样本。")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, DS.Space.xs)
            }
        } else {
            Section("响应时长 (742 · 已有 " + String(samples.count) + " 条留痕)") {
                // Disposition 非 Identifiable (只 at/verdict), 单参 ForEach 编译不过;
                // 同一秒内可有多条留痕 → at 不保证唯一, 用 enumerated 的 offset 作身份
                ForEach(Array(samples.sorted { $0.at > $1.at }.prefix(10).enumerated()), id: \.offset) { _, d in
                    Text("· " + d.atLabel() + " 处置「" + d.verdict + "」")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .lineLimit(1)
                }
                Text("间隔分布图需「告警发生时刻」与「处置时刻」成对积累后绘制 (占位)。")
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension RecordSearch {
    /// 724 四级色标 → DS 令牌映射 (紧急 danger / 严重 danger 降饱和 / 提示 warn)
    static func toneColor(for type: Int) -> Color {
        switch AlarmMeta.level(type) {
        case 3: return DS.Palette.danger
        case 2: return DS.Palette.danger.opacity(0.72)
        case 1: return type == 6 ? DS.Palette.warn : DS.Palette.textSub
        default: return DS.Palette.textSub
        }
    }
    /// 730 回放刻度会话记忆 (kf_rreplay)
    static func setReplayHour(_ h: Int) { DB.store.set("kf_rreplay", h) }
    static func replayHour() -> Int { DB.store.getInt("kf_rreplay", -1) }
    // 745 的 testMarkedKeys 已移入 RecordSearch.swift 核心 (StatsKit/LockStats 统计层要从 Core 调, 不再挂在 UI 扩展上)
}

extension RecordSearch.Disposition {
    func atLabel() -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f.string(from: Date(timeIntervalSince1970: at))
    }
}
