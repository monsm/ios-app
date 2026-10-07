// 包9 记录详情 (576/577/727/736/737/742) — 时间线行点开的详情 sheet
// 纪律: 颜色只经 DS 令牌 (danger 派生 .opacity, 形状冗余); 告警类型只用真实 5 种;
//       727 检查清单与 736 前后上下文复用 RecordSearch 的处置/留痕 API;
//       737 今日试错行 keyboardErrCount 语义不确定 → 标题带"?"; 742 响应时长占位"积累中"。
import SwiftUI

/// 576 记录详情 sheet: 全字段 + 告警 727 检查清单 + 736 前后 3 条上下文 + 577 来源凭证深跳
struct RecDetailSheet: View {
    let rec: Rec
    var scopeAll: Bool = false
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var tick = 0

    var body: some View {
        NavigationStack {
            List {
                fieldSection
                if rec.alarm { alarmSection }
                contextSection
                credJumpSection
            }
            .navigationTitle("记录详情 (576)")
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

    // ---------- 全字段 ----------
    @ViewBuilder
    private var fieldSection: some View {
        let who = rec.whoName ?? "未归属 (推断不出成员时如实显示)"
        let kindWord = rec.kind.map { Attribution.words[$0] ?? $0 } ?? "—"
        Section("时间线与归属") {
            fieldRow("锁", rec.lockName + (scopeAll ? "" : " (当前锁)"))
            fieldRow("类型", rec.typeName + " (#" + String(rec.type) + ")")
            fieldRow("锁端时刻", rec.timeStr)
            fieldRow("归属 (可证明链)", who)
            fieldRow("开门方式", kindWord)
            if !rec.cred.isEmpty { fieldRow("凭证维度", rec.cred + " (约)") }
            if rec.provable != nil {
                fieldRow("归属强度", rec.provable == "unique" ? "唯一凭证命中 (可证明)" : "推断 (约)")
            }
            if !rec.failMsg.isEmpty {
                fieldRow("失败原因 (手机侧)", rec.failMsg)
            }
        }
    }
    private func fieldRow(_ k: String, _ v: String) -> some View {
        HStack(alignment: .leading, spacing: DS.Space.s) {
            Text(k)
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .frame(width: 108, alignment: .leading)
            Text(v)
                .font(.subheadline)
                .foregroundStyle(DS.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(k + ": " + v)
    }

    // ---------- 告警段: 727 检查清单 + 741 同类计数 + 742 响应时长 + 737 今日试错 ----------
    @ViewBuilder
    private var alarmSection: some View {
        let dkey = rec.mac + "#" + rec.key
        let disp = RecordSearch.disposition(key: dkey)
        let same = RecordSearch.sameTypeCount(mac: rec.mac, type: rec.type, exceptKey: rec.key)
        Section {
            HStack(spacing: DS.Space.s) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: DS.Icon.sm))
                    .foregroundStyle(RecordSearch.toneColor(for: rec.type))
                    .accessibilityHidden(true)
                Text(RecordSearch.levelName(rec.type) + " · " + RecordSearch.alarmTitle(rec))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DS.Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(disp != nil ? "已处置" : "未处置")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(disp != nil ? DS.Palette.ok : DS.Palette.danger)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((disp != nil ? DS.Palette.ok : DS.Palette.danger).opacity(0.10), in: Capsule())
            }
            .padding(.vertical, DS.Space.xs)
            .background(rec.alarm ? RecordSearch.toneColor(for: rec.type).opacity(0.08) : Color.clear)

            if rec.type == 7 {
                // 727 防撬检查清单 (勾选状态复用处置字段 kf_rcheck_<key>)
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("防撬检查清单 (727)")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(DS.Palette.text)
                    ForEach(Array(RecordSearch.tamperChecks.enumerated()), id: \.offset) { i, item in
                        Toggle(isOn: Binding(
                            get: { RecordSearch.checkState(dkey)[i] },
                            set: { RecordSearch.setCheck(dkey, index: i, on: $0) }
                        )) {
                            Text(item)
                                .font(.footnote)
                                .foregroundStyle(DS.Palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .tint(DS.Palette.accent)
                    }
                }
                .padding(.vertical, DS.Space.xs)
            }

            // 741 同类告警计数
            HStack(spacing: DS.Space.s) {
                Image(systemName: "list.number")
                    .font(.system(size: DS.Icon.sm))
                    .foregroundStyle(DS.Palette.textSub)
                    .accessibilityHidden(true)
                Text("本锁同类累计 " + String(same.total) + " 次" + (same.lastStr.isEmpty ? "" : " · 上次 " + same.lastStr))
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // ⚠737 今日试错累计 (keyboardErrCount 语义不确定, 标题带"?", 只数日志条数)
            let trials = RecordSearch.trialCountToday(macs: [rec.mac])
            HStack(spacing: DS.Space.s) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: DS.Icon.sm))
                    .foregroundStyle(DS.Palette.warn)
                    .accessibilityHidden(true)
                Text("今日试错累计 (737)? 本锁 " + String(trials) + " 条锁定类日志")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 742 响应时长占位 (依赖处置时间积累, 上线初期无数据)
            HStack(spacing: DS.Space.s) {
                Image(systemName: "clock")
                    .font(.system(size: DS.Icon.sm))
                    .foregroundStyle(DS.Palette.textSub)
                    .accessibilityHidden(true)
                Text("响应时长 (742): 积累中 — 处置记录够多后自动出分布")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 726 处置留痕: 结论按钮 (与告警中心同一留痕 API)
            HStack(spacing: DS.Space.s) {
                Button {
                    RecordSearch.markDisposition(key: dkey, verdict: "已处理")
                    tick += 1
                } label: {
                    Label(disp != nil ? "已处置 · 更新" : "标记已处置", systemImage: "checkmark.circle")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(DS.Palette.accentText)
                }
                .buttonStyle(PlainButtonStyle())
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())

                if disp != nil {
                    Button {
                        RecordSearch.undoDisposition(key: dkey)
                        tick += 1
                    } label: {
                        Label("撤销 (739)", systemImage: "arrow.uturn.left")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(DS.Palette.danger)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
                Spacer(minLength: 0)
            }
        } header: {
            Text("告警 (723/724)")
        }
    }

    // ---------- 736 前后事件上下文 ----------
    @ViewBuilder
    private var contextSection: some View {
        let ctx = RecordSearch.context(mac: rec.mac, aroundKey: rec.key)
        if !ctx.before.isEmpty || !ctx.after.isEmpty {
            Section("前后 10 分钟上下文 (736)") {
                ForEach(Array(ctx.before.enumerated()), id: \.offset) { _, r in
                    contextRow(r, tag: "前")
                }
                ForEach(Array(ctx.after.enumerated()), id: \.offset) { _, r in
                    contextRow(r, tag: "后")
                }
            }
        }
    }
    private func contextRow(_ r: Rec, tag: String) -> some View {
        HStack(alignment: .leading, spacing: DS.Space.s) {
            Text(tag)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(DS.Palette.textSub)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(RecordSearch.localStr(r.lockTime > 0 ? Double(r.lockTime) : 0).isEmpty ? r.timeStr : r.timeStr)
                    .font(.caption.monospacedDigit())
                    .lineLimit(1)
                    .foregroundStyle(DS.Palette.textSub)
                Text(r.typeName + (r.whoName.map { " · " + $0 } ?? ""))
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.text)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // ---------- 577 详情跳凭证: 开门方式 → 对应凭证, 深跳凭证 Tab 定位高亮 ----------
    @ViewBuilder
    private var credJumpSection: some View {
        let nav = Self.credNav(rec)
        if !nav.isEmpty {
            Section {
                Button {
                    app.pendingCredNav = nav
                    app.pendingCredNavMac = rec.mac
                    app.tabSelection = 1
                    dismiss()
                    app.showToast("已定位到来源凭证 (577)")
                } label: {
                    Label("定位来源凭证 (577)", systemImage: "key.horizontal")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DS.Palette.accentText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
            }
        }
    }
    private static func credNav(_ r: Rec) -> String {
        guard let kind = r.kind else { return "" }
        let pws = DB.listPwds(r.mac)
        let fps = DB.listFps(r.mac)
        switch kind {
        case "pwd":
            if let p = pws.first(where: { !$0.temp && (r.whoName == nil || $0.owner == r.whoName) }) { return "pwd:" + String(p.alias) }
        case "temp":
            if let p = pws.first(where: { $0.temp && (r.whoName == nil || $0.owner == r.whoName) }) { return "pwd:" + String(p.alias) }
        case "fp":
            let match: (LedgerFp) -> Bool = { f in
                if r.whoName == nil { return true }
                return f.owner == r.whoName || (f.name ?? "").contains(r.whoName!)
            }
            if let f = fps.first(where: match) { return "fp:\(f.batch)" }
        default:
            break
        }
        return ""
    }
}
