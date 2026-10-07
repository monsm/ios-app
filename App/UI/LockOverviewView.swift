// 全部锁总览与对比 (包3) — 768 待维护清单 / 776 活跃度条形榜 / 778 告警率对比列 /
// 779 成员×锁交叉矩阵 / 784 固件版本对照表 / 773 凭证容量水位 / 787 对比结论一句话 / 769 绑定时间标注。
// 数据源全部是既有本地表 (日志缓存/台账/快照/钥匙串), 统计逻辑在 App/Core/LockStats.swift。
import SwiftUI

struct LockOverviewView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var usages: [LockUsage] = []
    @State private var matrix: (members: [Member], counts: [[String: Int]]) = ([], [])
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Space.m) {
                    if usages.isEmpty {
                        Card {
                            EmptyState(systemImage: "lock.square.stack",
                                       title: "还没有门锁",
                                       message: "添加第二把门锁后, 这里会给出活跃度、告警率与固件版本的多锁对比。")
                        }
                    } else {
                        summaryCard.staggered(0)        // 787
                        batteryStripCard.staggered(1)   // 288/1041/45 (包4)
                        maintenanceCard.staggered(2)    // 768
                        activityCard.staggered(3)       // 776 + 778
                        signalCard.staggered(3)         // 71 列表信号预览 (包2)
                        if !matrix.members.isEmpty { matrixCard.staggered(4) }   // 779
                        capacityCard.staggered(5)       // 773
                        firmwareCard.staggered(6)       // 784 + 769
                    }
                }
                .padding(.vertical, DS.Space.m)
            }
            .dsScreenBackground()
            .navigationTitle("全部锁总览")
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("完成") { dismiss() } } }
            .task {
                usages = LockStats.usage()
                matrix = LockStats.memberMatrix(usages)
                loaded = true
            }
        }
    }

    // ---------- 787 对比结论一句话 ----------
    private var summaryCard: some View {
        Card {
            HStack(alignment: .top, spacing: DS.Space.s) {
                Image(systemName: "text.quote")
                    .font(.system(size: DS.Icon.sm, weight: .semibold))
                    .foregroundStyle(DS.Palette.accentText)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
                Text(LockStats.summary(usages))
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // ---------- 288 电量总览条带 (低电靠左 = 1041 电量升序) + 45 趋势积累说明 ----------
    private var batteryStripCard: some View {
        // 包4: 展示统一取采样最新值 (BatteryCare.displayPct), 快照仅作兜底
        let resolved: [(u: LockUsage, pct: Int)] = usages.map { u in
            (u, BatteryCare.displayPct(u.mac, snapshot: u.power))
        }
        let sorted = resolved.sorted { a, b in
            let aUnknown = a.pct < 0, bUnknown = b.pct < 0
            if aUnknown != bUnknown { return !aUnknown }
            if a.pct != b.pct { return a.pct < b.pct }
            return a.u.name < b.u.name
        }
        return Card {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                SectionTitle(text: "电量", count: usages.count)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.s) {
                        ForEach(Array(sorted.enumerated()), id: \.offset) { _, item in
                            let u = item.u
                            let t = BatteryCare.tier(item.pct)
                            VStack(spacing: DS.Space.xxs) {
                                Image(systemName: t.icon)
                                    .font(.system(size: DS.Icon.lg, weight: .medium))
                                    .foregroundStyle(t.tone.color)
                                    .accessibilityHidden(true)
                                Text(item.pct < 0 ? "--" : (item.pct > 80 ? ">80%" : "\(item.pct)%"))
                                    .font(.caption2.weight(.medium))
                                    .monospacedDigit()
                                    .foregroundStyle(DS.Palette.text)
                                Text(u.name)
                                    .font(.caption2)
                                    .foregroundStyle(DS.Palette.textSub)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .padding(.horizontal, DS.Space.xs)
                            .padding(.vertical, DS.Space.xs)
                            .frame(width: 68)
                            .background(DS.Palette.surfaceAlt,
                                        in: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(u.name) 电量 \(item.pct < 0 ? "未知" : "\(item.pct)%")")
                        }
                    }
                }
                Text("趋势曲线积累中 — 每次连接门锁自动记录一个电量采样点, 存满约一周后可看走势; 换电池指引见锁详情。")
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // ---------- 768 待维护锁清单 ----------
    @ViewBuilder
    private var maintenanceCard: some View {
        let list = LockStats.maintenance(usages)
        if !list.isEmpty {
            Card(tint: .warn) {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    SectionTitle(text: "待维护", count: list.count)
                    ForEach(LockStats.maintenance(usages)) { item in
                        Button {
                            app.select(item.usage.mac)
                            app.tabSelection = 0
                            dismiss()
                        } label: {
                            HStack(spacing: DS.Space.s) {
                                Image(systemName: "wrench.and.screwdriver.fill")
                                    .font(.system(size: DS.Icon.sm, weight: .semibold))
                                    .foregroundStyle(DS.Palette.warn)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                                    Text(item.usage.name)
                                        .font(.subheadline)
                                        .foregroundStyle(DS.Palette.text)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                    Text(item.reasons.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(DS.Palette.warn)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: DS.Icon.xs, weight: .semibold))
                                    .foregroundStyle(DS.Palette.textSub)
                                    .accessibilityHidden(true)
                            }
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel("\(item.usage.name) 待维护: \(item.reasons.joined(separator: ", ")), 点击查看")
                    }
                }
            }
        }
    }

    // ---------- 776 活跃度条形榜 + 778 告警率对比列 ----------
    private var activityCard: some View {
        let ranked = usages.sorted { $0.opens30d > $1.opens30d }
        let maxOpens = ranked.map { $0.opens30d }.max() ?? 0
        return Card {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                SectionTitle(text: "活跃度 (\(LockStats.windowDays) 天)", count: usages.count)
                if maxOpens == 0 {
                    Text("近 \(LockStats.windowDays) 天还没有开门记录, 连接门锁读取日志后出榜。")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(ranked) { u in
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        HStack(spacing: DS.Space.s) {
                            Text(u.name)
                                .font(.caption)
                                .foregroundStyle(DS.Palette.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(width: 88, alignment: .leading)
                            // 776 水平条形: 条内嵌次数, 不引第三方图表
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(DS.Palette.surfaceAlt)
                                    Capsule()
                                        .fill(u.opens30d == maxOpens ? DS.Palette.accent : DS.Palette.accentText.opacity(0.55))
                                        .frame(width: maxOpens > 0 ? geo.size.width * CGFloat(u.opens30d) / CGFloat(maxOpens) : 1)
                                    Text("\(u.opens30d)")
                                        .font(.caption2)
                                        .monospacedDigit()
                                        .foregroundStyle(DS.Palette.onAccent)
                                        .padding(.leading, DS.Space.xs)
                                        .opacity(u.opens30d > 0 ? 1 : 0)
                                }
                            }
                            .frame(height: 18)
                            .accessibilityHidden(true)
                            // 778 告警率对比列
                            Text(u.alarms30d == 0 ? "无告警" : String(format: "告警 %.0f%%", u.alarmRate * 100))
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(u.alarms30d == 0 ? DS.Palette.textSub : (u.alarmRate >= 0.2 ? DS.Palette.danger : DS.Palette.warn))
                                .frame(width: 62, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(u.name), 近 30 天开门 \(u.opens30d) 次, \(u.alarms30d == 0 ? "无告警" : "告警占比 \(Int((u.alarmRate * 100).rounded()))%")")
                    }
                }
            }
        }
    }

    // ---------- 71 列表信号预览 (包2): 每行右侧迷你信号格, 切换前先看哪把锁在范围内 ----------
    // RSSI 来自各锁最近一次扫描 (kf_linkrssi_), 未扫到 = 无信号格 (不虚构);
    // 540 第三处角标已舍弃, 本卡是列表行的唯一展示位。
    private var signalCard: some View {
        let withSignal = usages.filter { LinkSense.rssiFor($0.mac) != nil }
        if withSignal.isEmpty {
            return Card {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    SectionTitle(text: "信号", count: usages.count)
                    Text("还没扫到任何锁的蓝牙广播 — 到设备页点一次刷新或靠近门锁, 信号格即现。")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        return Card {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                SectionTitle(text: "信号预览", count: withSignal.count)
                ForEach(withSignal) { u in
                    let lvl = LinkSense.rssiLevel(LinkSense.rssiFor(u.mac))
                    HStack(spacing: DS.Space.s) {
                        Text(u.name)
                            .font(.subheadline)
                            .foregroundStyle(DS.Palette.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        Text(LinkSense.rssiLabel(lvl))
                            .font(.caption2)
                            .foregroundStyle(DS.Palette.textSub)
                        RSSIBars(level: lvl, tint: lvl >= 3 ? DS.Palette.ok : DS.Palette.warn)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(u.name) 信号" + LinkSense.rssiLabel(lvl))
                }
                Text("信号格来自最近一次广播扫描 (71) · 切换前先看看哪把锁在范围内。")
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // ---------- 779 成员×锁交叉矩阵 ----------
    private var matrixCard: some View {
        let locks = usages
        return Card {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                SectionTitle(text: "成员 × 锁", count: matrix.members.count)
                ScrollView(.horizontal, showsIndicators: false) {
                    Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                        GridRow {
                            Text("成员")
                                .font(.caption2)
                                .foregroundStyle(DS.Palette.textSub)
                                .frame(width: 72, alignment: .leading)
                                .padding(DS.Space.xs)
                            ForEach(locks, id: \.mac) { u in
                                Text(u.name)
                                    .font(.caption2)
                                    .foregroundStyle(DS.Palette.textSub)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .frame(width: 64)
                                    .padding(DS.Space.xs)
                            }
                        }
                        Divider().gridCellUnsizedAxes(.horizontal)
                        ForEach(Array(matrix.members.enumerated()), id: \.offset) { mi, member in
                            GridRow {
                                HStack(spacing: DS.Space.xs) {
                                    Circle().fill(Color(hex: UInt32(member.color.dropFirst(1), radix: 16) ?? 0x3D8BFF))
                                        .frame(width: 6, height: 6)
                                    Text(member.name)
                                        .font(.caption)
                                        .foregroundStyle(DS.Palette.text)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                                .frame(width: 72, alignment: .leading)
                                .padding(DS.Space.xs)
                                ForEach(Array(locks.enumerated()), id: \.offset) { li, _ in
                                    let n = matrix.counts[li][member.id, default: 0]
                                    Text(n > 0 ? "\(n)" : "·")
                                        .font(.caption)
                                        .monospacedDigit()
                                        .foregroundStyle(n > 0 ? DS.Palette.text : DS.Palette.textSub)
                                        .frame(width: 64)
                                        .padding(DS.Space.xs)
                                        .background(n > 0 ? DS.Palette.accentText.opacity(0.08) : .clear)
                                }
                            }
                            Divider().gridCellUnsizedAxes(.horizontal)
                        }
                    }
                }
                Text("格内是归属到该成员的开门次数 (只统计可证明归属; 点数字可到记录页按成员筛选)。")
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                if let top = topCell() {
                    Button {
                        app.pendingRecordsFilter = top.member.id
                        app.tabSelection = 2
                        dismiss()
                    } label: {
                        Label("看「\(top.member.name)」在「\(top.lockName)」的 \(top.count) 条记录", systemImage: "arrow.right.circle")
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
        }
    }
    private func topCell() -> (member: Member, lockName: String, count: Int)? {
        var best: (Member, String, Int)? = nil
        for (li, u) in usages.enumerated() {
            for m in matrix.members {
                let n = matrix.counts[li][m.id, default: 0]
                if n > (best?.2 ?? 0) { best = (m, u.name, n) }
            }
        }
        guard let b = best else { return nil }
        return (b.0, b.1, b.2)
    }

    // ---------- 773 凭证容量水位 ----------
    private var capacityCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                SectionTitle(text: "凭证容量", count: usages.count)
                ForEach(usages) { u in
                    let util = max(utilization(u), 0)
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        HStack {
                            Text(u.name)
                                .font(.caption)
                                .foregroundStyle(DS.Palette.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Spacer(minLength: DS.Space.s)
                            Text(capText(u))
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(util >= 0.85 ? DS.Palette.warn : DS.Palette.textSub)
                        }
                        if hasKnownCap(u) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(DS.Palette.surfaceAlt)
                                    Capsule()
                                        .fill(util >= 0.85 ? DS.Palette.warn : DS.Palette.accent)
                                        .frame(width: geo.size.width * CGFloat(min(util, 1)))
                                }
                            }
                            .frame(height: 6)
                            .accessibilityHidden(true)
                        }
                        if util >= 0.85, hasKnownCap(u) {
                            Text("接近满载, 建议清理过期凭证")
                                .font(.caption2)
                                .foregroundStyle(DS.Palette.warn)
                        }
                    }
                    .padding(.vertical, DS.Space.xxs)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(u.name) \(capText(u))")
                }
            }
        }
    }
    private func hasKnownCap(_ u: LockUsage) -> Bool { u.pwdCap > 0 || u.fpCap > 0 }
    /// 综合利用率: 密码/指纹取两者已用比例的最大值; 容量未知 → 台账计数对典型上限 (密码 10/指纹 20) 估
    private func utilization(_ u: LockUsage) -> Double {
        let pwdRatio = u.pwdCap > 0 ? Double(u.pwdUsed) / Double(u.pwdCap)
                                    : Double(max(u.pwdUsed, 0)) / 10.0
        let fpRatio = u.fpCap > 0 ? Double(u.fpUsed) / Double(u.fpCap)
                                  : Double(max(u.fpUsed, 0)) / 20.0
        return max(pwdRatio, fpRatio)
    }
    private func capText(_ u: LockUsage) -> String {
        let pwd = u.pwdCap > 0 ? "\(u.pwdUsed)/\(u.pwdCap)" : "\(u.pwdUsed) 条"
        let fp = u.fpCap > 0 ? "\(u.fpUsed)/\(u.fpCap)" : "\(u.fpUsed) 枚"
        return "密码 \(pwd) · 指纹 \(fp)"
    }

    // ---------- 784 固件版本对照表 (+769 绑定时间标注) ----------
    private var firmwareCard: some View {
        let lag = LockStats.fwLag(usages)
        return Card {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                SectionTitle(text: "固件对照", count: usages.count)
                ForEach(usages) { u in
                    HStack(spacing: DS.Space.s) {
                        Image(systemName: "memorychip")
                            .font(.system(size: DS.Icon.sm))
                            .foregroundStyle(lag.lagging.contains(u.mac) ? DS.Palette.warn : DS.Palette.textSub)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text(u.name)
                                .font(.caption)
                                .foregroundStyle(DS.Palette.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            // 769 绑定时间标注
                            Text(boundText(u))
                                .font(.caption2)
                                .foregroundStyle(DS.Palette.textSub)
                        }
                        Spacer(minLength: DS.Space.s)
                        Text(u.fw.isEmpty ? "未读到" : "v" + u.fw)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(lag.lagging.contains(u.mac) ? DS.Palette.warn : DS.Palette.text)
                        if lag.lagging.contains(u.mac) {
                            StatusPill(text: "旧版本", systemImage: "arrow.down.circle", tone: .warn)
                        } else if PidMap.canDeviceUpgrade(pidOf(u.mac)) {
                            StatusPill(text: "可本地升级", systemImage: "arrow.up.circle", tone: .ok)
                        }
                    }
                    .frame(minHeight: DS.Hit.min)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(u.name), 固件 \(u.fw.isEmpty ? "未读到" : u.fw)\(lag.lagging.contains(u.mac) ? ", 落后于本机最新" : "")")
                }
            }
        }
    }
    private func boundText(_ u: LockUsage) -> String {
        guard u.pairedAt.count >= 10 else { return "绑定时间未记录" }
        return "绑定于 " + u.pairedAt.prefix(10).replacingOccurrences(of: "-", with: "/")
    }
    private func pidOf(_ mac: String) -> Int { app.devices.first { $0.mac == mac }?.pid ?? 0 }
}
