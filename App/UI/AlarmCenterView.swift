// 包9 告警中心 (723-743/745-747) — 跨锁告警流 + 四级色标 + 处置留痕 + 回放刻度
// 纪律: 告警类型只用 CAPABILITY §3 真实存在的 5 种; 处置/测试标记走 RecordSearch.dispositions 本地留痕;
//       颜色只经 DS 令牌 (danger 派生 .opacity, 形状冗余); 归属推断标"约";
//       742 响应时长分布占位"积累中" (依赖处置时间积累), 737 试错累计 keyboardErrCount 语义标"?"。
import SwiftUI
import UIKit

struct AlarmCenterView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var unhandledOnly = true     // 734 未处理队列优先 (默认)
    @State private var typeFilter: Int = 0      // 723 按告警类型过滤 (0 = 全部)
    @State private var scrubHour: Int = -1      // 730 24 小时回放刻度 (-1 = 关闭)
    @State private var openContextKey: String?  // 736 展开的前后事件上下文
    @State private var openDetailKey: String?   // 单条详情段 (处置/清单/对比)
    @State private var scrubHour: Int = RecordSearch.replayHour()  // 730 24 小时回放刻度
    @State private var tick = 0                  // 处置状态刷新

    private var macs: [String] { DB.keychains().map { $0.mac } }

    var body: some View {
        NavigationStack {
            List {
                streamHeader
                replayRuler   // 730
                alarmList
                trialCard     // 737 试错累计
                responseCard   // 742 响应时长 (占位)
            }
            .navigationTitle("告警中心 (723)")
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
    private func isHour(_ r: Rec, _ h: Int) -> Bool {
        guard let d = RecordSearch.dateOf(r) else { return false }
        return Calendar.current.component(.hour, from: d) == h
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
                Text(stream.count == 0 ? "没有告警" : "共 \(stream.count) 条")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
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
        } header: {
            Text(unhandledOnly ? "未处理队列 (734 · 处置完自动归入已归档)" : "全部告警 (含已处置 743)")
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
        if scrubHour >= 0 || stream.contains(where: { $0.timeStr.hasPrefix(todayKey()) }) {
            Section("24 小时回放 (730)") {
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
                        Text(scrubHour >= 0 ? "只看 \(scrubHour) 时前后事件" : "拖动查看 24 小时刻度")
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
    private func todayKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f.string(from: Date())
    }

    // ---------- 738 告警行: 左色条 + 浅底 (色条形状冗余: 紧急菱/严重三角/提示圆) ----------
    @ViewBuilder
    private var alarmList: some View {
        ForEach(stream) { r in
            Section {
                alarmRow(r)
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
                    .accessibilityLabel(RecordSearch.levelName(r.type))
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
                rowButton(openDetailKey == r.id ? "收起处置" : "处置与留痕 (726)", systemImage: "checklist", on: openDetailKey == r.id) {
                    openDetailKey = openDetailKey == r.id ? nil : r.id
                }
                rowButton("前后事件 (736)", systemImage: "text.bubble", on: openContextKey == r.id) {
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
        switch RecordSearch.level(t) {
        case 3: return "diamond.fill"       // 紧急: 菱
        case 2: return "triangle.fill"      // 严重: 三角
        default: return "circle.fill"      // 提示: 圆
        }
    }
    private func rowButton(_ title: String, systemImage: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action) {
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
    @ViewBuilder
    private func contextSection(_ r: Rec) {
        let (before, after) = RecordSearch.context(mac: r.mac, aroundKey: r.key)
        if before.isEmpty && after.isEmpty {
            Section("前后事件") {
                Text("前后 10 分钟内没有其他记录 — 孤立事件。")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
            }
        } else {
            Section("前后 10 分钟 · 同锁 (736)") {
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
            Text((r.whoName?.isEmpty ?? true) ? r.typeName : r.whoName! + " · " + r.typeName)
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
    @ViewBuilder
    private func detailSection(_ r: Rec) {
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
                    Text("防撬检查清单 (727)")
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
            // 726 处置结论 (已处理/误报/已处置) + 745 测试标记 + 739 回退
            HStack(spacing: DS.Space.xs) {
                disposeButton("已处理", dkey, disp)
                disposeButton("误报", dkey, disp)
                disposeButton("已处置", dkey, disp)
                disposeButton("标测试 (745)", dkey, disp, danger: true)
            }
            if disp != nil {
                HStack(spacing: DS.Space.s) {
                    Text("留痕: " + disp!.verdict + " · " + disp!.atLabel())
                        .font(.caption)
                        .foregroundStyle(DS.Palette.ok)
                        .lineLimit(1)
                    Button("恢复为未处理 (739)") {
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
            Text("处置与留痕 (726 · 仅本机)")
        }
    }
    private func disposeButton(_ verdict: String, _ key: String, _ disp: RecordSearch.Disposition?, danger: Bool = false) -> some View {
        let on = disp?.verdict == verdict
        return Button {
            RecordSearch.markDisposition(key: key, verdict: verdict)
            tick += 1
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
                ForEach(days) { d in
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

    /// 737 试错累计 (⚠ keyboardErrCount 语义不确定 — 只给日志条数, 标题带问号)
    @ViewBuilder
    private var trialCard: some View {
        let today = RecordSearch.trialCountToday(macs: macs)
        let snap = macs.first.flatMap { DB.readStatus($0) }
        if today > 0 || (snap?.keyboardErrCount ?? 0) > 0 {
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
                    if let c = snap?.keyboardErrCount, c > 0 {
                        Text("锁端键盘错误计数为 " + String(c) + " (语义未确证, 仅供参考)")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .lineLimit(1)
                    }
                    Text("锁端仅记录告警级锁定事件, 无逐次失败明细 (569)。")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
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
                        Text("响应时长分布 (742 · 积累中)")
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
                ForEach(samples.sorted { $0.at > $1.at }.prefix(10)) { d in
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

    /// 745 测试标记后的排除口径 (统计层调用)
    static var testMarkedKeys: Set<String> {
        dispositions().filter { $0.value.verdict == "测试" }.map(\.key)
    }
}

extension RecordSearch.Disposition {
    func atLabel() -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        f.timeZone = TimeZone.current
        return f.string(from: Date(timeIntervalSince1970: at))
    }
}
