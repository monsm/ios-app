// 包9 记录详情 (576/577/727/736/737/742) — 时间线行点开的详情 sheet
// 纪律: 颜色只经 DS 令牌 (danger 派生 .opacity, 形状冗余); 告警类型只用真实 5 种;
//       727 检查清单与 736 前后上下文复用 RecordSearch 的处置/留痕 API;
//       737 今日试错行 keyboardErrCount 语义不确定 → 标题带"?"; 742 响应时长占位"积累中"。
// 583/585/586 这三个出口交出去的都是 oid (mac#行键)。第一百八十九批之前, 记录页在默认「当前锁」视图里
// 没有 Rec 池、行身份也没归一到 oid ⇒ 详情卡根本打不开, 这一页的三个按钮也就从没被按到过;
// 现在两种范围走同一条判据, 这一页的键也全部经 `RecordOverlay.oid` 一处。
import SwiftUI
import UIKit

/// 576 记录详情 sheet: 全字段 + 告警 727 检查清单 + 736 前后 3 条上下文 + 577 来源凭证深跳
/// + 580 上下条翻看 + 584 邻近横滑 + 585 引用深链 + 587 低电跳诊断
struct RecDetailSheet: View {
    // 580 详情内容不再是"打开那一刻的那一条"，而是"结果集里的第 at 条"。
    // 为什么做成计算属性 `rec` 而不是把参数改名: 整页 30 多处都在读 `rec` (字段/告警/备注/分享/深跳)，
    // `let rec` → `var rec: Rec { … }` 让那些代码**一行不动**就跟着翻页走；改名的回归面比翻页本身大得多。
    private let initial: Rec
    private let siblings: [Rec]
    var scopeAll: Bool = false
    @State private var at = 0
    /// 越界一律夹回合法档 (调用方给的 siblings 可能在翻页途中被筛选改短)
    private var rec: Rec {
        siblings.isEmpty ? initial : siblings[min(max(at, 0), siblings.count - 1)]
    }
    private var atSafe: Int { siblings.isEmpty ? 0 : min(max(at, 0), siblings.count - 1) }

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var tick = 0
    @State private var noteDraft = ""      // 186 备注草稿
    @State private var card: UIImage?      // 718 本条记录卡 (只在开卡时渲染一次)

    init(rec: Rec, siblings: [Rec] = [], scopeAll: Bool = false) {
        initial = rec
        self.siblings = siblings
        self.scopeAll = scopeAll
        if let i = siblings.firstIndex(where: { $0.mac == rec.mac && $0.key == rec.key }) {
            _at = State(initialValue: i)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                fieldSection
                navSection      // 580 上下条翻看 (只在结果集 >1 条时长)
                noteSection     // 186 备注 / 188 标旗
                if rec.alarm { alarmSection }
                contextSection
                linkSection     // 585 引用深链
                jumpSection     // 583 定位 / 586 当天全景
            }
            // 718: 卡片图在开卡时渲染一次存进 @State —— 放 body 里每帧重跑 ImageRenderer 是白付的代价
            .task(id: rec.id) {
                card = ExportKit.recordCard(exportRow, lockName: rec.lockName)
            }
            .navigationTitle("记录详情")   // 576 记录详情
            .variantList()
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
        let who = MemberHub.aliasName(rec.whoId) ?? rec.whoName ?? "未归属 (推断不出成员时如实显示)"
        let kindWord = rec.kind.map { Attribution.words[$0] ?? $0 } ?? "—"
        Section("时间线与归属") {
            fieldRow("锁", rec.lockName + (scopeAll ? "" : " (当前锁)"))
            fieldRow("类型", rec.typeName + " (#" + String(rec.type) + ")")
            // 647 制式: 全部时间字段只经 TimeFormat.clock() 这一个出口 (与时间线、导出同一份口径)
            fieldRow("锁端时刻", TimeFormat.clock(rec.timeStr))
            // 650 时间来源徽标: "锁内时钟"=这条时刻来自日志 #04 协议秒; "本机录入"=拉取时补的墙钟。
            // 两者可能差几秒 (锁端靠 21 校时)，所以来源必须写出来，而不是混成"一个时间"。
            // 650 色点: 绿点=锁内时钟 (权威), 灰点=本机录入 (补的墙钟), 一行内区分。
            fieldRow("时间来源", rec.lockTime > 0 ? "锁内时钟 (03#04 协议秒)" : "本机录入时刻 (锁端未回时刻)",
                     dot: rec.lockTime > 0 ? DS.Palette.ok : DS.Palette.textSub)
            // 651 秒级与相邻间隔: 只有**两条都有 lockTime** 才算差值 —— 基准 2010-01-01 在相减时抵消，
            // 所以差值不受那个纪元影响; 单边缺值就直说"不可算"，不拿 timeStr 反解去凑 (那串可能没有秒位)。
            if rec.lockTime > 0 {
            }
            fieldRow("归属 (可证明链)", who)
            fieldRow("开门方式", kindWord)
            // 917 同分钟连开注记 (拍板 2026-10-10: **不折叠时间线的行**，只在这里说明)。
            // 592 已经会把"同日同类型连续 ≥3 条"折成一行；917 原句还要把同一分钟的多次并成 "+2"，
            // 那会让界面条数不再等于真实事件数 —— 与 749 刚定的"记录完整性对账"直接冲突，所以只在详情注一句。
            let stamp = String(rec.timeStr.prefix(16))
            if !rec.cred.isEmpty { fieldRow("凭证维度", rec.cred + " (约)") }
            // 797 陪同进入疑似: 同一凭证 (临时码/密码) 在 5 分钟窗口内被**不同成员**用过的后续行。
            // 只看行上已算好的可证明归属 (whoId) 与凭证维度 —— 短窗是启发式, 所以文案带"疑似";
            // 与 658/674 同一落点纪律: 推断性修饰只进详情卡, 不塞进时间线行 (一页上千条会明显变挤)。
            if !rec.cred.isEmpty, rec.whoId != nil {
                let near = siblings.contains { o in
                    guard o.mac == rec.mac, o.cred == rec.cred, o.key != rec.key,
                          let ow = o.whoId, ow != rec.whoId,
                          let t1 = RecordSearch.dateOf(o), let t2 = RecordSearch.dateOf(rec) else { return false }
                    return abs(t1.timeIntervalSince(t2)) <= 300
                }
                if near {
                    fieldRow("陪同进入 (疑似)", "同一凭证 5 分钟内还有别的成员用过 — 短窗启发式, 只作提示")   // 797 同一凭证
                }
            }
            if rec.provable != nil {
                fieldRow("归属强度", rec.provable == "unique" ? "唯一凭证命中 (可证明)" : "推断 (约)")
            }
            if !rec.failMsg.isEmpty {
                fieldRow("失败原因 (手机侧)", rec.failMsg)
            }
            // 761 行身份自证: 备注/标旗/告警处置都按这枚键落账 (RecordOverlay.oid = mac#key),
            // 支持对账时用户能念出同一把钥匙; 手机侧行 (type 0) 的 key 是 f_/c_ 派生键, idxRaw 为占位 0, 照实显示。
            fieldRow("行标识 (row)", rec.key)
            fieldRow("协议内部索引", String(rec.idxRaw))
        }
    }
    /// 650: `dot` 只给"时间来源"这类需要视觉区分的行用 (锁内时钟=绿点 / 本机录入=灰点);
    /// 其余行不传, 行形状与从前逐字节相同。
    private func fieldRow(_ k: String, _ v: String, dot: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
            Text(k)
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .frame(width: 108, alignment: .leading)
            HStack(spacing: DS.Space.xs) {
                if let dot = dot {
                    Circle().fill(dot).frame(width: 8, height: 8).accessibilityHidden(true)
                }
                Text(v)
                    .vkFont(.subheadline)
                    .foregroundStyle(DS.Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(k + ": " + v)
    }

    // ---------- 告警段: 727 检查清单 + 741 同类计数 + 742 响应时长 + 737 今日试错 ----------
    @ViewBuilder
    private var alarmSection: some View {
        // 处置留痕的键与 186 备注、585 引用深链是同一份行身份算术 (`RecordOverlay.oid`, 全仓只这一处),
        // 所以这里不再自己拼 "mac#key" —— 告警中心与本页必须认得同一个键。
        let dkey = RecordOverlay.oid(mac: rec.mac, rowKey: rec.key)
        let disp: RecordSearch.Disposition? = nil   // 2026-10-27 三轮：处置层已删，恒未处置
        Section {
            HStack(spacing: DS.Space.s) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: DS.Icon.sm))
                    .foregroundStyle(RecordSearch.toneColor(for: rec.type))
                    .accessibilityHidden(true)
                Text(AlarmMeta.levelName(rec.type) + " · " + RecordSearch.alarmTitle(rec))
                    .vkFont(.subheadline, weight: .medium)
                    .foregroundStyle(DS.Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(disp != nil ? "已处置" : "未处置")
                    .vkFont(.caption, weight: .medium)
                    .lineLimit(1)
                    .foregroundStyle(disp != nil ? DS.Palette.ok : DS.Palette.danger)
                    .padding(.horizontal, 8)
                    .padding(.vertical, DS.Space.xs)
                    .background((disp != nil ? DS.Palette.ok : DS.Palette.danger).opacity(0.10), in: Capsule())
            }
            .padding(.vertical, DS.Space.xs)
            .background(rec.alarm ? RecordSearch.toneColor(for: rec.type).opacity(0.08) : Color.clear)

            if rec.type == 7 {
                // 727 防撬检查清单 (勾选状态复用处置字段 kf_rcheck_<key>)
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("防撬检查清单")   // 727 防撬检查清单
                        .vkFont(.footnote, weight: .medium)
                        .foregroundStyle(DS.Palette.text)
                    ForEach(Array(RecordSearch.tamperChecks.enumerated()), id: \.offset) { i, item in
                        VariantToggle(isOn: Binding(
                        )) {
                            Text(item)
                                .vkFont(.footnote)
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
                    .vkFont(.footnote)
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
                Text("今日试错累计? 本锁 " + String(trials) + " 条锁定类日志")   // 737 今日试错累计
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if trials > 0 {
                // 737 涉事凭证明写"无法归属": 锁定级事件行不带凭证槽位 (依赖协议失败明细), 不猜
                Text("涉事凭证无法归属: 锁端仅记录锁定级事件行, 不带凭证槽位 (依赖协议失败明细)。")
                    .vkFont(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 742 响应时长占位 (依赖处置时间积累, 上线初期无数据)
            HStack(spacing: DS.Space.s) {
                Image(systemName: "clock")
                    .font(.system(size: DS.Icon.sm))
                    .foregroundStyle(DS.Palette.textSub)
                    .accessibilityHidden(true)
                Text("响应时长: 积累中 — 处置记录够多后自动出分布")   // 742 响应时长
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 726 处置留痕: 结论按钮 (与告警中心同一留痕 API)
            HStack(spacing: DS.Space.s) {
                Button {
                    tick += 1
                } label: {
                    Label(disp != nil ? "已处置 · 更新" : "标记已处置", systemImage: "checkmark.circle")
                        .vkFont(.footnote, weight: .medium)
                        .foregroundStyle(DS.Palette.accentText)
                }
                .buttonStyle(PlainButtonStyle())
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())

                if disp != nil {
                    Button {
                        tick += 1
                    } label: {
                        Label("撤销", systemImage: "arrow.uturn.left")   // 739 撤销
                            .vkFont(.footnote, weight: .medium)
                            .foregroundStyle(DS.Palette.danger)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
                Spacer(minLength: 0)
            }
        } header: {
            Text("告警")   // 723/724 告警
        }
    }

    // ---------- 736 前后事件上下文 ----------
    @ViewBuilder
    private var contextSection: some View {
    }
    private func contextRow(_ r: Rec, tag: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
            Text(tag)
                .vkFont(.caption2, weight: .semibold)
                .lineLimit(1)
                .foregroundStyle(DS.Palette.textSub)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(RecordSearch.localStr(r.lockTime > 0 ? Double(r.lockTime) : 0).isEmpty ? r.timeStr : r.timeStr)
                    .vkFont(.caption.monospacedDigit())
                    .lineLimit(1)
                    .foregroundStyle(DS.Palette.textSub)
                Text(r.typeName + ((MemberHub.aliasName(r.whoId) ?? r.whoName).map { " · " + $0 } ?? ""))
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.text)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // ---------- 580 上一条 / 下一条: 在**当前筛选结果集**内顺序切换 ----------
    @ViewBuilder
    private var navSection: some View {
        if siblings.count > 1 {
            Section {
                HStack(spacing: DS.Space.m) {
                    Button("上一条") { if atSafe > 0 { at = atSafe - 1 } }
                        .disabled(atSafe <= 0)
                        .frame(maxWidth: .infinity, minHeight: DS.Hit.min)
                    Text("第 \(atSafe + 1) / \(siblings.count) 条")
                        .vkFont(.footnote.monospacedDigit())
                        .foregroundStyle(DS.Palette.textSub)
                    Button("下一条") { if atSafe < siblings.count - 1 { at = atSafe + 1 } }
                        .disabled(atSafe >= siblings.count - 1)
                        .frame(maxWidth: .infinity, minHeight: DS.Hit.min)
                }
                .vkFont(.subheadline, weight: .medium)
                .foregroundStyle(DS.Palette.accentText)
            } footer: {
                Text("顺序就是你刚才在记录页看到的那份筛选结果，不是锁端日志原始序号 —— 被筛掉的记录不会翻页翻出来，"   // 580 顺序就是你刚才在记录
                     + "那等于悄悄改了筛选条件。")
                    .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }



    private var linkSection: some View {
        Section {
            Button {
                app.showToast("已复制本条引用链接")   // 585 已复制本条引用链接
            } label: {
                Label("复制本条引用链接", systemImage: "link")
                    .vkFont(.subheadline, weight: .medium)
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
            }
            Text("链接只编码「哪把锁的哪一行」(mac#行键)，不含口令、指纹数据与原始帧。"
                 + "粘进备忘录点一下 = 回到记录页并按当前显示范围定位本条；"
                 + "行不在显示范围内时页面如实说明原因，不会打开相邻的一条顶替。")   // 585 行不在显示范围内时页
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // ---------- 587 低电告警 → 这台锁的诊断页 ----------

    // ---------- 583 / 586 回到时间线的两个出口 ----------
    /// 586 用哪一天做锚: 与 applyFilter **完全同口径** —— 0:00-4:59 的行归前一晚的组 (649)。
    /// 直接取 timeStr 前 10 位会在凌晨记录上跳到一个"不存在的日子"，那是最难查的错法:
    /// 页面会老实说"那天没有行"，而数据其实就在昨天的组里。
    private var anchorDayKey: String {
        let full = rec.timeStr
        guard full.count >= 13, let hh = Int(full.dropFirst(11).prefix(2)) else {
            return full.count >= 10 ? String(full.prefix(10)) : ""
        }
        let d0 = String(full.prefix(10))
        guard hh < 5, let base = RecordSearch.dateFromKey(d0) else { return d0 }
        return RecordSearch.dayKeyOf(WeekCal.shifted(base, days: -1))
    }

    private var jumpSection: some View {
        Section {
            Button {
                app.pendingFlashKey = RecordOverlay.oid(mac: rec.mac, rowKey: rec.key)
                dismiss()
            } label: {
                Label("在时间线里定位这条", systemImage: "arrow.down.to.line.compact")   // 583 在时间线里定位这条
                    .vkFont(.subheadline, weight: .medium)
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
            }
            Button {
                // 563 带过去的就是这一行显示的**类型词** —— 与搜索框同一个语法，到达后可再编辑。
                app.pendingSearch = rec.typeName
                app.requestRoute(.records)
                dismiss()
            } label: {
                Label("搜这类记录", systemImage: "magnifyingglass.circle")   // 563 搜这类记录
                    .vkFont(.subheadline, weight: .medium)
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
            }
            Button {
                let dk = anchorDayKey
                guard !dk.isEmpty else {
                    app.showToast("这条记录的时刻无法定位到某一天")   // 586 这条记录的时刻无法定
                    return
                }
                app.pendingRecordsDay = dk
                app.requestRoute(.records)
                dismiss()
            } label: {
                Label("查看当天全部", systemImage: "calendar.day.timeline.left")   // 586 查看当天全部
                    .vkFont(.subheadline, weight: .medium)
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
            }
            Text("两个出口都不改你的筛选条件: 一颗只是滚过去并闪一下，另一颗只把显示范围收到那一天，"
                 + "页顶有「看全部日子」可以退回来。")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }


    // ---------- 718 本条导出行 + 分享卡 ----------
    /// Rec → ExportRecord 的映射: 只带这一条**能证明**的字段, 归属不可证明就留空 (与导出中心同一口径)。
    private var exportRow: ExportRecord {
        ExportRecord(time: rec.timeStr, typeName: rec.typeName, member: rec.whoName ?? "",
                     isAlarm: rec.alarm, hex: "",
                     dayKey: rec.timeStr.count >= 10 ? String(rec.timeStr.prefix(10)) : "未知")
    }

    // ---------- 186 记录备注 / 990 开门附言 / 188 手动标旗 ----------
    // 只写本机覆盖层 (RecordOverlay), 不发任何锁端命令、不改日志缓存; 删设备时按族清除。
    // 990「开门时附一句短语、家人查看时展示」= **这一处** (逐行本地文字 + 行下展示), 与 186/597 同一份存储;
    // 不另立第二个编辑面 —— 同一数据两个入口正是 597 那轮明确不做的事 (写侧只有 RecordOverlay 一处)。
    @ViewBuilder
    private var noteSection: some View {
        Section {
            TextField("开门附言 / 备注", text: $noteDraft)   // 990/186 开门附言
                .autocorrectionDisabled()
                .onSubmit { saveNote() }
                .onAppear { noteDraft = RecordOverlay.note(rec.mac, rec.key) }
            HStack(spacing: DS.Space.m) {
                Button("保存备注") { saveNote() }
                    .vkFont(.subheadline, weight: .medium)
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                Spacer(minLength: 0)
            }
            VariantToggle(isOn: Binding(
                get: { RecordOverlay.isFlagged(rec.mac, rec.key) },
                set: { _ in RecordOverlay.toggleFlag(rec.mac, rec.key); tick += 1 })) {
                Label("标为异常: 时间线行左侧常显红旗", systemImage: "flag.fill")   // 188 标为异常
                    .vkFont(.subheadline)
            }
            .frame(minHeight: DS.Hit.min)
        } footer: {
            Text("附言/备注与旗标都是本机标注：不写进门锁，也不进导出 CSV 之外的任何出口；删除这台设备上的锁会一并清除。")
                .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func saveNote() {
        RecordOverlay.setNote(rec.mac, rec.key, noteDraft)
        tick += 1
        // 186 备注已清空
        // 186 备注已保存在这台手机
        app.showToast(noteDraft.trimmingCharacters(in: .whitespaces).isEmpty ? "备注已清空" : "备注已保存在这台手机")
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
                return f.owner == r.whoName || f.name.contains(r.whoName!)
            }
            if let f = fps.first(where: match) { return "fp:\(f.batch)" }
        default:
            break
        }
        return ""
    }
}
