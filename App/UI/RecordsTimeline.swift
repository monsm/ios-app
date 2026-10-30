// 包9 记录详情 (576/577/727/736/737/742) — 时间线行点开的详情 sheet
// 纪律: 颜色只经 DS 令牌 (danger 派生 .opacity, 形状冗余); 告警类型只用真实 5 种;
//       727 检查清单与 736 前后上下文复用 RecordSearch 的处置/留痕 API;
//       737 今日试错行 keyboardErrCount 语义不确定 → 标题带"?"; 742 响应时长占位"积累中"。
// 583/585/586 这三个出口交出去的都是 oid (mac#行键)。第一百八十九批之前, 记录页在默认「当前锁」视图里
// 没有 Rec 池、行身份也没归一到 oid ⇒ 详情卡根本打不开, 这一页的三个按钮也就从没被按到过;
// 现在两种范围走同一条判据, 这一页的键也全部经 `RecordOverlay.oid` 一处。
import SwiftUI
import UIKit

/// 576 记录详情 sheet: 全字段 + 告警 727 检查清单 + 736 前后 3 条上下文
/// 2026-10-30 修正（第 117 轮）：原头注还列了 577 来源凭证深跳 / 584 邻近横滑 / 587 低电跳诊断 —— 三项均未实现，已删。
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
    @Environment(\.dismiss) var dismiss
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

    /// 2026-10-29：从 "yyyy-MM-dd HH:mm:ss" 里取小时；格式不对返回 nil（不猜）。
    private static func hourOf(_ s: String) -> Int? {
        guard s.count >= 13 else { return nil }
        let hh = String(s.dropFirst(11).prefix(2))
        return Int(hh)
    }

    /// 2026-10-29：时段标签（自然时段词 + 工作日通勤判断）。
    /// 抽成函数而不是写在 ViewBuilder 里 —— ViewBuilder 只收 View 表达式，
    /// `var seg = ...; seg += ...` 会被当成 `()` 而报 "type () cannot conform to View"。
    private static func segmentLabel(_ r: Rec, hour h: Int) -> String {
        var seg = TimeWord.word(h)
        let day = RecordSearch.dateFromKey(String(r.timeStr.prefix(10))) ?? Date()
        if let c = CommuteLabel.tag(date: day, hour: h) { seg += " · \(c)时段" }
        return seg
    }

    // ---------- 全字段 ----------
    @ViewBuilder
    private var fieldSection: some View {
        let who = MemberHub.aliasName(rec.whoId) ?? rec.whoName ?? "未归属 (推断不出成员时如实显示)"
        let kindWord = rec.kind.map { Attribution.words[$0] ?? $0 } ?? "—"
        Section("时间线与归属") {
            fieldRow("锁", rec.lockName + (scopeAll ? "" : " (当前锁)"))
            fieldRow("类型", rec.typeName + " (#" + String(rec.type) + ")")
            // 2026-10-29 补：`RecordSearch.sameTypeCount` 零调用 —— 单看一条"锁定"不知道是偶发还是惯犯。
            if rec.type != 0 {
                let sc = RecordSearch.sameTypeCount(mac: rec.mac, type: rec.type, exceptKey: rec.key)
                if sc.total > 1 {
                    fieldRow("同类记录", "共 \(sc.total) 条" + (sc.lastStr.isEmpty ? "" : " · 上一条 \(TimeFormat.clock(sc.lastStr))"))
                }
            }
            // 647 制式: 全部时间字段只经 TimeFormat.clock() 这一个出口 (与时间线、导出同一份口径)
            fieldRow("锁端时刻", TimeFormat.clock(rec.timeStr))
            // 2026-10-29 补：`TimeWord`（自然时段词）与 `CommuteLabel`（工作日通勤时段）一直零调用。
            // 放在详情里而不是列表行上：列表行已经在时间前面带日期，再加"上午/下午"是噪声；
            // 详情是"看这一条"的场景，时段与通勤判断才有解释价值。
            if let h = Self.hourOf(rec.timeStr) {
                fieldRow("时段", Self.segmentLabel(rec, hour: h))
            }
            // 650 时间来源徽标: "锁内时钟"=这条时刻来自日志 #04 协议秒; "本机录入"=拉取时补的墙钟。
            // 两者可能差几秒 (锁端靠 21 校时)，所以来源必须写出来，而不是混成"一个时间"。
            // 650 色点: 绿点=锁内时钟 (权威), 灰点=本机录入 (补的墙钟), 一行内区分。
            fieldRow("时间来源", rec.lockTime > 0 ? "锁内时钟 (03#04 协议秒)" : "本机录入时刻 (锁端未回时刻)",
                     dot: rec.lockTime > 0 ? DS.Palette.ok : DS.Palette.textSub)
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
                    fieldRow("陪同进入 (疑似)", "同一凭证 5 分钟内还有别的成员用过 — 短窗启发式， 只作提示")   // 797 同一凭证
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
                // 2026-10-27 布局核对修复：原先 `.frame(width: 108)` 是**硬宽度** ——
                // 系统字号放大到 accessibility 档时，「协议内部索引」这类标签会被截断，
                // 而右侧值列还占着固定空间。改成 `minWidth` + 左对齐：窄字号下宽度不变，
                // 大字号下标签列自己撑开，不会被切。
                .frame(minWidth: 108, alignment: .leading)
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
        // 2026-10-30 删除（第 131 轮）：这里原有一个 `let dkey = RecordOverlay.oid(...)` —— 声明后从未使用，
        // 下面的按钮直接走 RecordOverlay.setDisposition（由 API 内部再算一次 oid）。
        let disp = RecordOverlay.disposition(rec.mac, rec.key)   // 2026-10-28: 接回真实处置存储
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

            // 2026-10-27 三轮精简：防撬检查清单已删（告警处置层移除）。


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
                Text("涉事凭证无法归属： 锁端仅记录锁定级事件行， 不带凭证槽位 (依赖协议失败明细)。")
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
                Text("响应时长： 积累中 — 处置记录够多后自动出分布")   // 742 响应时长
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 726 处置留痕: 结论按钮 (与告警中心同一留痕 API)
            HStack(spacing: DS.Space.s) {
                Button {
                    // 2026-10-28：原先只 `tick += 1` —— 界面闪一下又回「未处置」，处置从未落盘。
                    RecordOverlay.setDisposition(rec.mac, rec.key,
                        RecordSearch.Disposition(at: Date().timeIntervalSince1970, verdict: "已处置"))
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
                        RecordOverlay.setDisposition(rec.mac, rec.key, nil)   // 2026-10-28: 真撤销
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
    // 2026-10-29 补（**后台有实现、前台是空壳**）：`RecordSearch.context` 一直零调用，
    // 而这里就是个空的 `@ViewBuilder` —— 用户在记录详情里看不到「出这事之前和之后发生了什么」。
    // 只取同锁、±10 分钟、前 3 / 后 3 条；不做完整时间线（那是记录页的事）。
    private var contextSection: some View {
        let ctx = RecordSearch.context(mac: rec.mac, aroundKey: rec.key)
        if !ctx.before.isEmpty || !ctx.after.isEmpty {
            Section {
                ForEach(ctx.before, id: \.key) { r in contextRow(r, tag: "前") }
                HStack(spacing: DS.Space.s) {
                    Image(systemName: "arrowtriangle.right.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(DS.Palette.accentText)
                    Text("当前这一条")
                        .vkFont(.caption, weight: .semibold)
                        .foregroundStyle(DS.Palette.accentText)
                    Spacer(minLength: 0)
                }
                ForEach(ctx.after, id: \.key) { r in contextRow(r, tag: "后") }
            } header: {
                Text("前后事件（±10 分钟 · 同锁）")
            } footer: {
                Text("最多前 3 / 后 3 条。用来回答「出这事之前之后发生了什么」，不是完整时间线。")
            }
        }
    }
    
    private func contextRow(_ r: Rec, tag: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
            Text(tag)
                .vkFont(.caption2, weight: .semibold)
                .lineLimit(1)
                .foregroundStyle(DS.Palette.textSub)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(r.timeStr)
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
                // 2026-10-28 修复：原先**只弹 toast，没有写剪贴板** —— 用户以为复制了，粘出来是空的。
                // 现在真写：kf://records?k=<oid>（scheme 与 host 白名单见 project.yml / handleDeepLink）。
                // 2026-10-28 修复：`oid` 的格式是 `mac#行键` —— 里面那个 `#` 在 URL 里是 **fragment 分隔符**，
                // 不编码就直接拼，`k` 参数只会剩下 `mac`，粘到 App 里 `landRecordKey` 永远找不到那一行。
                // 整串用 alphanumerics 编码（`#` → `%23`，其它特殊字符一并转义），
                // `handleDeepLink` 那边用 URLComponents 解析会自动解码回来。
                let oidRaw = RecordOverlay.oid(mac: rec.mac, rowKey: rec.key)
                let oidEnc = oidRaw.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? oidRaw
                let link = "kf://records?k=" + oidEnc
                Clip.set(link)
                app.showToast("已复制本条引用链接")
            } label: {
                Label("复制本条引用链接", systemImage: "link")
                    .vkFont(.subheadline, weight: .medium)
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
            }
            Text("链接只编码「哪把锁的哪一行」(mac + 行键，已 URL 转义)，不含口令、指纹数据与原始帧。"
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
            Text("两个出口都不改你的筛选条件： 一颗只是滚过去并闪一下，另一颗只把显示范围收到那一天，"
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
                // 2026-10-28 修复：原来只在 .onAppear 赋值 —— 上下条翻页时这条视图不重建，
                // 于是草稿框里残留的是**上一条**的备注，点「保存备注」会写到错的行。
                // 现在按 rec.key 变化同步刷新（翻页即换草稿）。
                .onAppear { noteDraft = RecordOverlay.note(rec.mac, rec.key) }
                // 2026-10-30 修复（第 115 轮）：原来监听 `rec.key` —— 而 `Rec.key` 是 `String(idxRaw)`，
                // **不含 mac**；「全部锁」范围下两把锁的日志序号常常相同 ⇒ 翻到另一把锁的同号行时
                // 监听不触发，草稿框留着上一把锁的备注，点「保存备注」会写到错的行。
                // `rec.id` 是 `mac + "#" + key`（Rec 模型里定义），才是真正的行身份。
                .onChange(of: rec.id) { _, _ in noteDraft = RecordOverlay.note(rec.mac, rec.key) }
            HStack(spacing: DS.Space.m) {
                Button("保存备注") { saveNote() }
                    .vkFont(.subheadline, weight: .medium)
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                Spacer(minLength: 0)
            }
            VariantToggle(isOn: Binding(
                get: { RecordOverlay.isFlagged(rec.mac, rec.key) },
                // 2026-10-30 修复（第 124 轮）：`set: { _ in …toggleFlag… }` **丢弃了控件传来的新值**、只做翻转 ——
                // 读屏/快速连点或 getter 尚未刷新时，第二次 set 会把刚写进去的旗标又翻回去。
                // 改成「新值与当前值不同才写」。
                set: { v in
                    if v != RecordOverlay.isFlagged(rec.mac, rec.key) {
                        RecordOverlay.toggleFlag(rec.mac, rec.key)
                        tick += 1
                    }
                })) {
                Label("标为异常： 时间线行左侧常显红旗", systemImage: "flag.fill")   // 188 标为异常
                    .vkFont(.subheadline)
            }
            .frame(minHeight: DS.Hit.min)
        } footer: {
            Text("附言/备注与旗标都是本机标注：不写进门锁；除导出 CSV 外，也会随「备份与恢复」整包带走（回滚时一并还原）。")   // 2026-10-30：原句说「不进导出 CSV 之外的任何出口」，但 BackupBundle.Meta 的 recNotes/recFlags 与回滚族表 kf_rnote_/kf_rflag_ 都含它们
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

    // 2026-10-30 删除（第 130 轮）：`credNav(_:)` 全仓**零调用**（deadscan B 档已列出）。
    // 577「来源凭证深跳」从未接线，这个函数是它的残骸。
}
