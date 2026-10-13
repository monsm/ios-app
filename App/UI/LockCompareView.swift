// 多锁对比 (775 双锁叠加对比 / 783 对比窗口同步 / 781 同名凭证对照 / 782 闲置锁标注)。
// 2026-10-10 拍板：对比族开成一个新页，8 条都在这里做，不再散到各页的"顺带看一眼"。
//
// 三条写在前面的边界：
// 1) **窗口只有一份** (783)。两把锁共用同一个 windowDays —— 分开选窗口就是两份口径，
//    而"对比"这件事唯一的前提就是同一段时间；标签上写清区间是哪几天，而不是各说各话。
// 2) 数据只在**本机读到的日志**里 (StatModel 走 DB.readLogs)。某把锁从没拉取过日志时
//    这一栏直说"没有本机日志"，绝不画一条 0 折线冒充"这把锁没人用" —— 那是把"没读"说成"没有"。
// 3) 781 的同名只按**名字/归属owner** 比对。两个人都给自己妈妈录一枚指纹，名字当然相同；
//    所以这里只说"存在同名，点看对照"，绝不说"重复凭证/建议删除"。
import SwiftUI
import Charts

struct LockCompareView: View {
    @EnvironmentObject var app: AppState
    @State private var leftMac = ""
    @State private var rightMac = ""
    @State private var windowDays = 30
    @State private var showSameNames = false

    private var locks: [Keychain] { app.devices }

    var body: some View {
        List {
            pickerSection
            if ready {
                windowSection
                overlaySection
                metricSection
                rhythmSection
                dualRadarSection   // 777 双锁四时段雷达 (互补规律)
                sameNameSection
                idleSection
            }
        }
        .navigationTitle("多锁对比 (775)")
        .scrollContentBackground(.hidden)
        .dsScreenBackground()
        .onAppear { initSides() }
    }

    private var ready: Bool { !leftMac.isEmpty && !rightMac.isEmpty && leftMac != rightMac }

    private func initSides() {
        guard locks.count >= 2 else { return }
        if leftMac.isEmpty { leftMac = locks[0].mac }
        if rightMac.isEmpty, rightMac != leftMac {
            rightMac = locks.first(where: { $0.mac != leftMac })?.mac ?? ""
        }
    }

    // ---------- 选两把 ----------
    private var pickerSection: some View {
        Section("选两把锁") {
            if locks.count < 2 {
                Text("这台手机只绑了一把锁 —— 对比需要两把 (775)。")
                    .font(.footnote).foregroundStyle(DS.Palette.textSub)
            } else {
                Picker("左侧", selection: $leftMac) {
                    ForEach(locks) { kc in Text(LockArchive.displayName(kc)).tag(kc.mac) }
                }
                Picker("右侧", selection: $rightMac) {
                    ForEach(locks) { kc in Text(LockArchive.displayName(kc)).tag(kc.mac) }
                }
                if leftMac == rightMac {
                    Text("两边选的是同一把锁，比出来的差永远是零 —— 请换一把 (775)。")
                        .font(.caption).foregroundStyle(DS.Palette.warn)
                }
            }
        }
    }

    // ---------- 783 窗口同步 ----------
    private var windowSection: some View {
        Section {
            Picker("时间窗口 (两把同步)", selection: $windowDays) {
                ForEach([7, 30, 90], id: \.self) { w in Text("近 \(w) 天").tag(w) }
            }
            .pickerStyle(.segmented)
            Text(windowLabel)   // 783: 标签写清这段区间到底是哪几天，双锁共用同一个
                .font(.caption).foregroundStyle(DS.Palette.textSub)
        } header: {
            Text("对比窗口 · \(windowLabel) · 双锁")
        }
    }
    private var windowLabel: String {
        let to = Date()
        let from = WeekCal.shifted(to, days: -(windowDays - 1))
        return TimeFormat.range(fromDay: RecordSearch.dayKeyOf(from), toDay: RecordSearch.dayKeyOf(to))
    }

    private var leftModel: StatsKit.StatModel? { ready ? StatsKit.build(mac: leftMac, week: 7, window: windowDays) : nil }
    private var rightModel: StatsKit.StatModel? { ready ? StatsKit.build(mac: rightMac, week: 7, window: windowDays) : nil }

    /// 按日键对齐的两条序列。缺一天的记录补 0 —— 但**只在另一把有这天的时候**补：
    /// 两把都没有的那一天根本不该出现在图上。
    private struct DayPair: Identifiable {
        let day: Date
        let a: Int
        let b: Int
        var id: Date { day }
    }
    private var pairs: [DayPair] {
        guard let l = leftModel, let r = rightModel else { return [] }
        let la = Dictionary(uniqueKeysWithValues: l.dailyPoints.map { ($0.key, $0.opens) })
        let ra = Dictionary(uniqueKeysWithValues: r.dailyPoints.map { ($0.key, $0.opens) })
        let keys = Set(la.keys).union(ra.keys)
        return keys.sorted(by: <).compactMap { k in
            guard let d = RecordSearch.dateFromKey(k) else { return nil }
            return DayPair(day: d, a: la[k] ?? 0, b: ra[k] ?? 0)
        }
    }

    // ---------- 775 双折线叠加 ----------
    @ViewBuilder
    private var overlaySection: some View {
        if pairs.isEmpty {
            Section("开门趋势叠加 (775)") {
                // 两把都没有本机日志时不画空图 (边界 2)
                Text("两把锁在本机都没有日志行 —— 先到设备页各读一次，再回来对比 (775)。")
                    .font(.footnote).foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Section("开门趋势叠加 (775)") {
                Chart(pairs) { p in
                    LineMark(x: .value("日", p.day, unit: .day), y: .value("左", p.a), series: .value("锁", "左"))
                        .foregroundStyle(DS.Palette.accent)
                    LineMark(x: .value("日", p.day, unit: .day), y: .value("右", p.b), series: .value("锁", "右"))
                        .foregroundStyle(DS.Palette.warn)
                }
                .chartYAxis {
                    // 633 的口径同样用在这里: 整数指标不出现小数刻度
                    AxisMarks(values: .automatic(desiredCount: 4))
                }
                .frame(height: 170)
                Text("左：\(leftName) · 右：\(rightName)。两把锁的记录窗口各自受本机缓存限制，条数差异不等于使用差异。")
                    .font(.caption2).foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private var leftName: String { locks.first { $0.mac == leftMac }.map { LockArchive.displayName($0) } ?? "左" }
    private var rightName: String { locks.first { $0.mac == rightMac }.map { LockArchive.displayName($0) } ?? "右" }

    // ---------- 关键指标双列 ----------
    private var metricSection: some View {
        Section("关键指标") {
            HStack(spacing: DS.Space.s) {
                Text("指标").font(.caption).foregroundStyle(DS.Palette.textSub).frame(maxWidth: .infinity, alignment: .leading)
                Text(leftName).font(.caption.weight(.semibold)).frame(maxWidth: .infinity)
                Text(rightName).font(.caption.weight(.semibold)).frame(maxWidth: .infinity)
            }
            row("开门次数", String(leftModel?.opensTotal ?? 0), String(rightModel?.opensTotal ?? 0))
            row("告警条数", String(leftModel?.alarmsTotal ?? 0), String(rightModel?.alarmsTotal ?? 0))
            row("可归属成员", String(leftModel?.memberCounts(days: windowDays).count ?? 0),
                               String(rightModel?.memberCounts(days: windowDays).count ?? 0))
            row("本机日志行", String(leftModel?.dailyPoints.count ?? 0), String(rightModel?.dailyPoints.count ?? 0))
        }
    }
    // ---------- 780 工作日首次开门时刻对照 ----------
    private var rhythmSection: some View {
        let la = leftModel?.workdayFirstOpens.count ?? 0
        let lb = rightModel?.workdayFirstOpens.count ?? 0
        Section("工作日首次开门时刻 (780)") {
            row("中位时刻", firstOpenText(leftModel), firstOpenText(rightModel))
            row("最早 ~ 最晚", firstOpenRange(leftModel), firstOpenRange(rightModel))
            row("参与的工作日", String(la), String(lb))
            Text("取每个工作日里最早的那一次开门，对照值是这些时刻的中位数，不是平均数 —— "
                 + "首次开门是个绕圈的量，23:50 与 01:00 的平均会得出 12:40 那种没人开过的时刻。"
                 + "样本为偶数时取靠早的那一个，它是真发生过的一刻。"
                 + "工作日 = 非法定假日且 (周一~周五或表里写着补班)，与 616 周几分布同一个周序；"
                 + "窗口里没读到日志的日子既不算工作日也不进样本 (与 610/642 同口径)。")
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    // ---------- 777 双锁四时段雷达 (大门早晚 / 车库深夜 的互补规律) ----------
    /// 与 602 单锁雷达同一套四轴口径 (早/午/晚/深夜), 这里把两把锁叠在一张图上。
    /// 关键纪律: 两条多边形**共用一个 maxV 标度** —— 各画各的归一化会让"都很闲"与"都很忙"长得一模一样,
    /// 那正是"看起来在工作其实是缺省值"的同一类毛病。Canvas 不画字, 轴名与读数写在下面 (同 602 的理由)。
    @ViewBuilder
    private var dualRadarSection: some View {
        let a = leftModel?.dayparts ?? []
        let b = rightModel?.dayparts ?? []
        let totA = leftModel?.daypartTotal ?? 0
        let totB = rightModel?.daypartTotal ?? 0
        if a.count == 4, b.count == 4, totA + totB >= 10 {
            Section("双锁四时段雷达 (777)") {
                Canvas { ctx, size in
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    let r = max(20, min(size.width, size.height) / 2 - 14)
                    let maxV = max(1, (a + b).map { $0.opens }.max() ?? 1)
                    func vertex(_ i: Int, _ k: CGFloat) -> CGPoint {
                        let ang = -Double.pi / 2 + Double(i) * Double.pi / 2
                        return CGPoint(x: c.x + cos(ang) * r * k, y: c.y + sin(ang) * r * k)
                    }
                    for k in [0.5, 1.0] {
                        var ring = Path()
                        for i in 0..<4 {
                            let p = vertex(i, CGFloat(k))
                            if i == 0 { ring.move(to: p) } else { ring.addLine(to: p) }
                        }
                        ring.closeSubpath()
                        ctx.stroke(ring, with: .color(DS.Palette.hairline), lineWidth: 0.8)
                    }
                    // dayparts 是**元组数组** `[(name:span:opens:)]` (StatsKit:354), 不是结构体 —— 参数按元组写
                    func poly(_ parts: [(name: String, span: String, opens: Int)]) -> Path {
                        var p = Path()
                        for (i, d) in parts.enumerated() {
                            let v = CGFloat(d.opens) / CGFloat(maxV)
                            let pt = vertex(i, max(0.02, v))
                            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                        }
                        p.closeSubpath()
                        return p
                    }
                    let pa = poly(a), pb = poly(b)
                    ctx.fill(pa, with: .color(DS.Palette.accent.opacity(0.20)))
                    ctx.stroke(pa, with: .color(DS.Palette.accent), lineWidth: 2)
                    ctx.fill(pb, with: .color(DS.Palette.warn.opacity(0.18)))
                    ctx.stroke(pb, with: .color(DS.Palette.warn), lineWidth: 2)
                }
                .frame(height: 190)
                .accessibilityHidden(true)
                HStack(spacing: DS.Space.m) {
                    legendDot(DS.Palette.accent, leftName)
                    legendDot(DS.Palette.warn, rightName)
                    Spacer(minLength: 0)
                }
                // 四行读数: 走 indices + id: \.self (Int 是 Hashable, 这条写法在任何 Swift 版本都成立)
                ForEach(Array(a.indices), id: \.self) { i in
                    row(a[i].name, String(a[i].opens), String(b[i].opens))
                }
                Text("两条多边形共用同一个标度 —— 各画各的归一化会让「都很闲」与「都很忙」长得一样。"
                     + "四轴 = 早/午/晚/深夜 (与 602 同一口径); 只统计窗口内读到的日志, 没读到的时段按 0 画。")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func legendDot(_ c: Color, _ name: String) -> some View {
        HStack(spacing: DS.Space.xs) {
            Capsule().fill(c).frame(width: 14, height: 4)
            Text(name).font(.caption).foregroundStyle(DS.Palette.textSub)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    /// 标签双列行 —— 值一律是**已经格式化好**的字符串 (数字也转成串)，
    /// 这样 780 那种"07:12"的读数不必再写第二套行渲染。
    private func row(_ label: String, _ a: String, _ b: String) -> some View {
        HStack(spacing: DS.Space.s) {
            Text(label).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            Text(a).font(.subheadline.monospacedDigit()).frame(maxWidth: .infinity)
            Text(b).font(.subheadline.monospacedDigit()).frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): 左 \(a), 右 \(b)")
    }
    /// 780 的读数: 中位时刻那一枚。没有工作日样本时给 "—"，不画一个 00:00 冒充"清早"。
    private func firstOpenText(_ m: StatsKit.StatModel?) -> String {
        guard let s = m?.workdayFirstOpenMedian else { return "—" }
        return TimeFormat.clockOnly(s.timeStr)
    }
    /// 780 的跨度行: 让中位数可被读出 ("07:12 落在 06:03~09:40 之间")。
    /// 样本只有一个日子时首末相同 —— 那也照实写两个一样的时刻，不改成"仅一天"那种特殊文案，
    /// 因为旁边那一行已经写着"参与的工作日 1"。
    private func firstOpenRange(_ m: StatsKit.StatModel?) -> String {
        guard let v = m?.workdayFirstOpens, let f = v.first, let l = v.last else { return "—" }
        return TimeFormat.clockOnly(f.timeStr) + " ~ " + TimeFormat.clockOnly(l.timeStr)
    }

    // ---------- 781 同名凭证对照 ----------
    /// 全库扫描: 名字 → 用到它的锁名集合 (指纹名 + 密码归属名)。被 2 把及以上锁用到才列出。
    /// 原实现只比左右两把 —— 第三把锁上的同名从此看不见 (781 的缺口)。
    private var sameNameFleet: [(name: String, locks: [String])] {
        func lockName(_ kc: Keychain) -> String { kc.name.isEmpty ? LockArchive.displayName(kc) : kc.name }
        var map = [String: Set<String>]()
        for kc in DB.keychains() {
            for f in DB.listFps(kc.mac) where !f.name.isEmpty {
                map[f.name, default: []].insert(lockName(kc))
            }
            for p in DB.listPwds(kc.mac) {
                if let o = p.owner, !o.isEmpty { map[o, default: []].insert(lockName(kc)) }
            }
        }
        return map.filter { $0.value.count >= 2 }
            .map { (name: $0.key, locks: $0.value.sorted()) }
            .sorted { $0.name < $1.name }
    }
    @ViewBuilder
    private var sameNameSection: some View {
        let dup = sameNameFleet
        if !dup.isEmpty {
            Section {
                Button { showSameNames.toggle() } label: {
                    Label("全库 \(DB.keychains().count) 把锁上, \(dup.count) 个名字被 2 把及以上锁用到 (781)", systemImage: "person.2")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DS.Palette.accentText)
                }
                if showSameNames {
                    ForEach(dup, id: \.name) { d in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.name).font(.footnote).foregroundStyle(DS.Palette.text)
                            Text(d.locks.joined(separator: " · ")).font(.caption2).foregroundStyle(DS.Palette.textSub)
                        }
                    }
                }
                Text("同名不代表同一个凭证，也不代表录重了 —— 只说明这台手机上有锁用了同样的称呼。"
                     + "要不要改名由你判断，这里不下结论 (781)。")
                    .font(.caption2).foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("同名凭证对照 (781)")
            }
        }
    }

    // ---------- 782 闲置锁标注 + 排除口径 ----------
    private var idleSection: some View {
        Section {
            HStack {
                Text(leftName)
                Spacer(minLength: DS.Space.s)
                idleTag(for: leftMac)
            }
            HStack {
                Text(rightName)
                Spacer(minLength: DS.Space.s)
                idleTag(for: rightMac)
            }
            Text("闲置 = 本机日志里超 30 天没有开门行。它说的是「没读到」，不是「没人开」："
                 + "从没拉取过日志的锁也会落在这里，所以拿它当排除口径之前请自己确认过。")
                .font(.caption2).foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("闲置标注 (782)")
        }
    }
    private func idleTag(for mac: String) -> some View {
        // 782 判据全仓唯一 = StatsKit.isIdleLock (统计页那枚排除口径开关读同一处, 不再各算各的)
        let idle = StatsKit.isIdleLock(mac)
        return Text(idle ? "闲置 (超 30 天无开门行)" : "30 天内有开门")
            .font(.caption2.weight(.medium))
            .foregroundStyle(idle ? DS.Palette.textSub : DS.Palette.ok)
            .padding(.horizontal, DS.Space.s)
            .padding(.vertical, 2)
            .background(Capsule().fill(DS.Palette.surfaceAlt))
    }
}
