// 记录页 · 行渲染（时间线分组 / 单行 / 标题 / 高亮 / 成员色 / 空档行）
// 2026-10-29 从 RecordsView.swift（2036 行）拆出。
// 这些是 RecordsView 的 extension —— 原 private 成员已提升为 internal，跨文件可见。
import SwiftUI

extension RecordsView {
    func daySection(_ g: DayGroup) -> some View {
        // 653 生日组头: 该成员生日日 (MM-dd 命中组头日期) → "今日是妈妈的生日"标签
        let bday = g.key.count == 10 ? String(g.key.suffix(5)) : ""
        let hasAlarm = g.rows.contains(where: \.warn)
        let openN = g.rows.filter { StatsKit.openTypes.contains($0.type) || $0.kind != nil }.count
        let alarmN = g.rows.filter(\.warn).count
        // 589 组内告警置顶: 有告警的日子把告警行提到组首，其余保持它原来的顺序。
        // 为什么不用 `sorted(by:)`: Swift 的比较排序**不保证稳定**，而"其余按原时间随后"这条要的是稳定性 ——
        // 拆成两段再拼是确定性的，还省掉整组比较。
        let ordered = g.rows.filter(\.warn) + g.rows.filter { !$0.warn }
        // 593 日界收尾: 最晚时刻与全天条数都取自 applyFilter 里**过滤与分页截断之前**的行池
        // (`dayLatest` / `dayFullCount`), 因为组尾那句「全天 N 条」说的是这一天, 不是"这一天还剩几行给我看"。
        // 为什么不用 `ordered.last`: 589 刚把告警行提到组首，"显示上的末条"与"一天里最晚的一条"从此不是一回事，
        // 拿前者当后者会在每个有告警的日子说错话。
        // 为什么不用 `g.rows`: 那是筛过、又被 598 截过的一页 —— 原来这句文案写的正是 g.rows.count,
        // 于是每设一次过滤, "全天"就被改小一次 (筛出 3 条却写着"全天 3 条")。
        let dayEnd = dayLatest[g.key]
        // 与「全天」同单位的显示数: 592 一行能装几条, 所以把折起来的尾行摊开再比。
        // 不摊开会写出"全天 5 条 · 当前显示 1 条"这种看着像少读了 4 条的话, 而那 4 条就在那一行里。
        let shownEvents = g.rows.count
        let dayFull = dayFullCount[g.key] ?? shownEvents
            // 2026-10-27 八轮精简：行内注记六张表已删（对应 UI 块一并移除）。
        return Section {
            ForEach(ordered) { r in
                // 583: 整行包一层 Group 才能挂 listRowBackground (ViewBuilder 的 if/else 分支不是同一个类型)。
                Group {
                    timelineRow(r)
                }
                .listRowBackground(FlashWash(on: flashKey == r.id))
            }
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DS.Space.s) {
                    Text(dayLabel(g.key))
                        .vkFont(.headline)
                    // 581 未处置告警蓝点: 该日有未处置告警才出现, 口径与 735 角标同一条 (不另存"已读"位)
                    // 596 替代: 原句是组头红字"含胁迫" —— 胁迫类协议不存在 (§5), 改挂真实存在的三类
                    // (防撬 7 / 试错锁定 10 / 键盘锁定 224)。点按落 586 既有的"当天全景"(landDay),
                    // 与"直接过滤到当日"同一件事; 与上面那枚蓝点**不互相替代**: 蓝点看未处置, 这条看这一天出过事。
                    if damageDays.contains(g.key) {
                        Button {
                            landDay(g.key)
                        } label: {
                            Text("含防撬/试错")   // 596 含防撬
                                .vkFont(.caption2, weight: .semibold)
                                .foregroundStyle(DS.Palette.danger)
                                .frame(minHeight: DS.Hit.min)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("该日有防撬、试错锁定或键盘锁定告警, 点按只看这一天")   // 596 该日有防撬
                    }
                    // 594 日型色带 (4pt 竖条): 工作日靛蓝 / 周末青绿 / 法定节假日橙 (判据见 DayGroup.dayKind)。
                    // 每天都出现 —— 三档互比才有"哪天不是平常日"的读法; 原先只在节假日给 3pt 橙条。
                    if let k = g.dayKind {
                        Capsule()
                            .fill(k.color.opacity(0.9))
                            .frame(width: 4)
                            .accessibilityLabel(k.ax)
                    }
                    // 671 节假日组头标签 (内置表按国务院公告逐日核对) + 594 色带同一数据源, 不另造判定
                    if let h = g.holiday {
                        Text(h)
                            .vkFont(.caption, weight: .medium)
                            .foregroundStyle(DS.Palette.warn)
                            .lineLimit(1)
                    }
                    // 671 调休补班日: 与"放假日"共用同一数据源但分开标记 —— 补班是上班日。
                    // 给它同一条橙色色带，会让人把"这天开门多是正常的"读成"这天放假"。
                    if RecordSearch.isMakeupWorkday(g.key) {
                        Text("补班")
                            .vkFont(.caption2)
                            .foregroundStyle(DS.Palette.textSub)
                            .accessibilityLabel("该日是调休补班日，不是假期")
                    }
                    // 649 凌晨归属: 组内含 0:00-4:59 事件时注明
                    if g.hasNight {
                        Text("含次日凌晨")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    Spacer(minLength: DS.Space.s)
                    // 588 组头计数徽标: 开门 N · 告警 M (含告警日染浅红)
                    HStack(spacing: DS.Space.xs) {
                        Text("\(openN) 开")
                            .vkFont(.caption2, weight: .medium)
                            .lineLimit(1)
                            .foregroundStyle(DS.Palette.textSub)
                        // 556 组头右侧的"该日命中告警数" (系统相册精选分组那一形态)：搜索/筛选后的结果
                        // 用的就是这一个组头 —— 不另开一套"搜索结果专用头"，那会多出第二份口径。
                        if alarmN > 0 {
                            Text("\(alarmN) 警")
                                .vkFont(.caption2, weight: .semibold)
                                .lineLimit(1)
                                .foregroundStyle(DS.Palette.danger)
                        }
                    }
                    .padding(.horizontal, DS.Space.s)
                    .padding(.vertical, 2)
                    .background(hasAlarm ? DS.Palette.danger.opacity(0.10) : DS.Palette.surfaceAlt, in: Capsule())
                }
                HStack(spacing: DS.Space.s) {
                    // 681 农历小字 (中国历法直接支持, 失败静默隐藏)
                    if let lunar = g.lunarLabel {
                        Text(lunar)
                            .vkFont(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    // 796 本日使用者 (组头小字, 归属推断标"约")
                    if g.key == todayKey, g.distinctUsers > 0 {
                        Text("约 \(g.distinctUsers) 位使用者")
                            .vkFont(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    Spacer(minLength: 0)
                    Text("\(g.rows.count) 条")
                        .vkFont(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.xs)
            .background(hasAlarm ? DS.Palette.danger.opacity(0.04) : Color.clear)
        } footer: {
            // 593 日界收尾标注: 交代"这一天的边界在哪"，核对当天有没有拉漏时不用再自己数末条。
            // 只在 ≥2 条的日子出现 —— 单条日子的"最晚"就是那条，写出来是噪音不是信息。
            // 显示数与全天数不一致时把「当前显示」也写出来: 同一句话里的两个口径要各归各的名字,
            // 否则筛完再看组尾, 那句"全天"就又变成一次谎 (598 分页截断时同样会分叉)。
            if let end = dayEnd, dayFull > 1 {
                Text("当日最晚 \(end) · 全天 \(dayFull) 条"
                     + (shownEvents == dayFull ? "" : " · 当前显示 \(shownEvents) 条")
                    )   // 593 界面文案
                    .vkFont(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .padding(.horizontal, DS.Space.l)
            }
        }
    }

    /// 592 合并行的标签 (从 mergedRow 的 Button label 抽出: 该表达式报 type-check 超时)
    @ViewBuilder


    /// 单条: 左时间列 + 时间轴(圆点与连线) + 事件文案
    /// 738 告警行: 左侧 3pt danger 色条 + danger 8% 浅底 (菱形警示点形状冗余);
    /// 184 开门方式图标 / 183 成员色点 (可证明归属才显) / 770 锁名小标签 / 557 命中高亮
    func timelineRow(_ r: RowVM) -> some View {
        HStack(alignment: .top, spacing: DS.Space.m) {
            // 911/647: 主时间线行也必须走 TimeFormat.clock 这一个出口。此前只有合并行 (:1612) 走了,
            // 这一行是裸切片 (rowParts 的 "yyyy-MM-dd HH:mm:ss" 中段), 于是选了"12 小时"后
            // 同一页普通行仍显 24 小时、合并行显 12 小时 —— 一句注释承诺的"全部时间字段"就是这么破的。
            Text(TimeFormat.clock(r.time))
                .vkFont(.caption.monospacedDigit())
                .foregroundStyle(DS.Palette.textSub)
                .frame(width: 42, alignment: .trailing)
                .padding(.top, 2)

            ZStack(alignment: .top) {
                // 连接线: 留半格让线自然收在圆点上下 (592 展开态内也保持贯通)
                Rectangle()
                    .fill(DS.Palette.hairline)
                    .frame(width: 1.5)
                    .frame(maxHeight: .infinity)
                // 告警用菱形警示点, 普通用圆点 — 形状本身即第二信息通道, 不只靠颜色
                Image(systemName: r.warn ? "diamond.fill" : "circle.fill")
                    .font(.system(size: r.warn ? 10 : 8))
                    .foregroundStyle(r.warn ? DS.Palette.danger : DS.Palette.accent)
                    .padding(.top, 5)
            }
            .frame(width: 12)
            .accessibilityHidden(true)

            HStack(spacing: DS.Space.s) {
                // 188 手动标旗: 旗标行左侧常显 (形状+颜色双通道, 不只靠颜色)
                if RecordOverlay.isFlagged(r.rowMac.isEmpty ? mac : r.rowMac, r.key) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: DS.Icon.xs, weight: .semibold))
                        .foregroundStyle(DS.Palette.danger)
                        .accessibilityLabel("已标旗")
                }
                // 184 开门方式图标: fp 指纹 / pwd 数字 / temp 一次性 / key 钥匙
                rowTitle(r)
                    .padding(.top, 1)
                Spacer(minLength: 0)
            }
            // 907 时间线行距三档 (kf_tl_gap, 叠在 kf_density 之上): 竖列越密越难扫,
            // 这一档分别照顾"一眼看完一整天"与"一屏塞更多条"。
            .padding(.bottom, DS.Metric.tlGap)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 738 告警行: 左侧 3pt 色条 + 浅红底 (danger 派生, 形状冗余)
        .background(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: DS.Space.l, bottom: 0, trailing: DS.Space.l))
        .contentShape(Rectangle())
        // 576 行点开进详情 sheet (全字段 + 告警 727 清单 + 736 前后 3 条)。
        // 判据是 `lookupRec` 那一条 oid: 单锁与全部锁同一个口, 不再依赖"这次是哪种范围"。
        .onTapGesture {
            if let rec = lookupRec(r) {
                detailRec = rec
            } else {
                // 打不开要说得出为什么。原先这里 `detailRec = lookupRec(r)` 拿到 nil 就什么都不发生 ——
                // 那正是 576 在默认「当前锁」视图里坏掉两个版本时用户看到的形状: 行能点, 点了没反应。
                app.showToast("本机台账里没有这一行对应的记录数据 — 点右上角重新读取后再试")   // 576 本机台账里没有这一行
            }
        }
        // 185 左滑快捷操作: 只暴露行本来就有能力 (714 复制 / 577 跳凭证 / 186 备注 / 188 标旗)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !r.credKey.isEmpty {
                Button("看凭证") {
                    app.pendingCredNav = r.credKey
                    app.pendingCredNavMac = r.rowMac.isEmpty ? mac : r.rowMac
                    app.requestRoute(.credentials)   // 2026-10-14 走查: 原直写 tabSelection, 访客态绕过 377 门禁
                    // 收摊口径：换页一律走 requestRoute 这个唯一漏斗（先过访客闸再切 Tab），
                    // 而本页是 Tab 根、没有 sheet 盖着，所以这里不需要 dismiss()。
                }
                .tint(DS.Palette.warn)
            }
            Button("复制") {
                Clip.set("[" + (r.lockName.isEmpty ? app.displayName : r.lockName) + "] " + r.time + " " + r.title)
                app.showToast("已复制本条记录")
            }
            .tint(DS.Palette.accent)
        }
        .contextMenu {
            // 714 复制为完整文本: 粘贴即有锁名+时间+归属的完整上下文
            Button {
                Clip.set("[" + (r.lockName.isEmpty ? app.displayName : r.lockName) + "] " + r.time + " " + r.title)
                app.showToast("已复制本条记录")
            } label: {
                Label("复制为文本", systemImage: "doc.on.doc")   // 714 复制为文本
            }
            // 761 溯源: 复制本机缓存行标识 (锁日志序号 idx, 或手机侧事件的 f_/c_ 前缀键) + 日期 + 锁 MAC,
            // 便于和诊断包里的日志逐条对上。不假装能查锁端数据库。
            Button {
                let idLine = "row=" + r.key + " · day=" + r.dayKey + " · mac=" + (r.rowMac.isEmpty ? mac : r.rowMac)
                Clip.set(idLine)
                app.showToast("已复制行标识")   // 761 已复制行标识
            } label: {
                Label("复制行标识", systemImage: "number")   // 761 复制行标识
            }
            if !r.credKey.isEmpty {
                Button {
                    app.pendingCredNav = r.credKey
                    app.pendingCredNavMac = r.rowMac.isEmpty ? mac : r.rowMac
                    app.requestRoute(.credentials)   // 2026-10-14 走查: 原直写 tabSelection, 访客态绕过 377 门禁
                    // 收摊口径：换页一律走 requestRoute 这个唯一漏斗（先过访客闸再切 Tab），
                    // 而本页是 Tab 根、没有 sheet 盖着，所以这里不需要 dismiss()。
                    app.showToast("已定位到来源凭证")   // 577 已定位到来源凭证
                } label: {
                    Label("定位来源凭证", systemImage: "key.horizontal")   // 577 定位来源凭证
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(r.title + ", " + r.time)
        .accessibilityAddTraits([.isButton])
    }



    /// 557 命中词高亮: 搜索词在行文案中染 accentText 浅底 (分段 Text, 换行跟随整体流)
    @ViewBuilder
    func rowTitle(_ r: RowVM) -> some View {
        if highlightTokens.isEmpty {
            Text(r.title)
                .vkFont(.subheadline)
                .foregroundStyle(DS.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(spacing: 0) {
                // 2026-10-13 run 63: 原写 `ForEach(highlightSegments(r.title), id: \.offset)` ——
                // HlSeg 没有 `offset` 成员 (它自带 `id`), id: 键路径推不出来 ⇒ 报
                // "cannot infer key path type from context" 并连带一串重载误判。HlSeg 本就 Identifiable,
                // 直接用它的 id。
                ForEach(highlightSegments(r.title)) { seg in
                    if seg.hit {
                        Text(seg.text)
                            .vkFont(.subheadline)
                            .foregroundStyle(DS.Palette.accentText)
                            .padding(.vertical, DS.Space.xxs)
                            // @layout-allow VK豁免 刻度点: 时间轴上的命中段，是刻度不是容器
                            .background(DS.Palette.accentText.opacity(0.18), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                    } else {
                        Text(seg.text)
                            .vkFont(.subheadline)
                            .foregroundStyle(DS.Palette.text)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
    struct HlSeg: Identifiable {
        var text: String
        var hit: Bool
        var id: Int
    }
    /// 557 高亮分段: 命中的词切出独立段 (贪心首匹配, 大小写不敏感)
    func highlightSegments(_ text: String) -> [HlSeg] {
        guard !highlightTokens.isEmpty else { return [HlSeg(text: text, hit: false, id: 0)] }
        var segs = [HlSeg]()
        var rest = Substring(text)
        var idx = 0
        while !rest.isEmpty {
            var bestOff = -1
            var bestTok = ""
            for tok in highlightTokens where tok.count >= 1 {
                if let rng = rest.range(of: tok, options: .caseInsensitive) {
                    let off = rest.distance(from: rest.startIndex, to: rng.lowerBound)
                    if bestOff < 0 || off < bestOff {
                        bestOff = off
                        bestTok = tok
                    }
                }
            }
            if bestOff < 0 {
                segs.append(HlSeg(text: String(rest), hit: false, id: idx)); idx += 1
                break
            }
            let pre = String(rest.prefix(bestOff))
            let hitTxt = String(rest.dropFirst(bestOff).prefix(bestTok.count))
            if !pre.isEmpty {
                segs.append(HlSeg(text: pre, hit: false, id: idx)); idx += 1
            }
            segs.append(HlSeg(text: hitTxt, hit: true, id: idx)); idx += 1
            rest = rest.dropFirst(bestOff + hitTxt.count)
        }
        return segs
    }
    /// 183 成员色点: 可证明归属才显示 (成员档案色, 6pt 圆点)
    /// 183 成员色 (走成员档案 hex, 与安全中心同一纪律（该页已删，纪律沿用）)
    func memberColor(_ m: Member) -> Color {
        var s = m.color
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt32(s, radix: 16)
        return v.map { Color(hex: $0) } ?? DS.Palette.accent
    }
    /// 576 行 → Rec: 单锁与全部锁**同一条判据**, 键的算术只有 `RecordOverlay.oid` 一份
    /// (行侧就是 `RowVM.id` 那一个 oid, Rec 侧在这里现算, 不再各自拼 "mac#key")。
    /// 旧写法先问 `$0.id == r.key`: Rec.id 恒带 mac 前缀, 而单锁路径的 r.key 不带 ⇒ 那一问永远不中;
    /// 第二问又只有在 recPool 非空时才可能命中, 而 recPool 原先只在 scope == 1 分支赋值
    /// ⇒ 默认「当前锁」视图里点行恒得 nil, 576/583/585/586 整条断供。
    func lookupRec(_ r: RowVM) -> Rec? {
        recPool.first { RecordOverlay.oid(mac: $0.mac, rowKey: $0.key) == r.id }
    }


    var emptyHint: some View {
        Section {
            // 558 零结果救援 —— 顺带堵住一条**说谎的空态**: 这里原来无脑显示"还没有记录，去重新读取"，
            // 而把上千条筛成 0 条时同样走到这一支 —— 那句话是在骗用户去重连一把好端端的锁。
            if activeFilterCount > 0 {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("当前条件下 0 条 —— 是过滤把它们挡掉了，不是这台锁没记录 (本机共 \(allRows.count) 行可读)。")
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: DS.Space.xs) {
                        // 原句三枚: 成员名 / 类型词 / 日期。全部取**真实存在**的值，不造示例词。
                        if let first = DB.members().first {
                            Button("试试成员「\(first.name)」") { sel = first.id; searchText = "" }
                                .vkFont(.caption)
                        }
                        Button("试试类型词「指纹」") { searchText = Attribution.words["fp"] ?? "指纹" }
                            .vkFont(.caption)
                        // 558 日期那枚: 只在今天真有行时才给 (时间短语经 554 成窗, must 摘除修在 RecordSearch.parse)
                        if allRows.contains(where: { $0.dayKey == Self.dayKey(Date()) }) {
                            Button("试试「今天」") { sel = ""; searchText = "今天" }
                                .vkFont(.caption)
                        }
                    }
                    .foregroundStyle(DS.Palette.accentText)
                    Button("清掉全部过滤") { sel = ""; searchText = ""; filters = QueryFilters() }   // 573 清掉全部过滤
                        .vkFont(.caption, weight: .medium)
                        .foregroundStyle(DS.Palette.accentText)
                }
                .padding(.vertical, DS.Space.m)
            } else {
                // 808 示例记录铺底 (Apple Wallet 那条原句): 空态原先只有一枚托盘图标 + 一句话,
                // 读完不知道"记录长什么样、要读多少条进来"。这里按原句铺 3 条**灰阶示例条目**,
                // 点任意一条弹「真实数据从这里开始」引导卡。
                // 三条示例是画出来的形状, 不是 RowVM/Rec ⇒ 不参与过滤、计数、统计、导出与深链,
                // 每条都写明"示例"且整体压在灰阶 (textSub / hairline) 上, 不会冒充真记录。
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    HStack(alignment: .top, spacing: DS.Space.m) {
                        Image(systemName: "tray")
                            .font(.system(size: DS.Icon.lg))
                            .foregroundStyle(DS.Palette.accentText)
                            .accessibilityHidden(true)
                        Text("还没有记录。点右上角「重新读取」从锁内拉取最近 100 条开门/操作记录。")
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                        // 1044 家庭公告板
                    }
                    .accessibilityElement(children: .combine)
                    // 815 空态两个真出路: 记录是锁里拉出来的, 先连设备; 不知道这里记什么就看示例说明。
                    // 旧空态只有一行字 + 右上角一个入口, 用户读完了也不知道下一步点什么。
                    HStack(spacing: DS.Space.s) {
                        Button("连接设备") { app.requestRoute(.device) }
                            .buttonStyle(PrimaryActionStyle())
                            .buttonStyle(SecondaryActionStyle(fullWidth: false))
                    }
                    .vkFont(.footnote)
                }
                .padding(.vertical, DS.Space.m)
            }
        }
    }


    // ---------- 成员过滤 (保留既有 793 访客虚拟分组 / 791 可认领 / 1028 保养) ----------
    var memberChips: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s) {
                    chip("", "全部")
                    ForEach(DB.members().filter { !MemberHub.ext($0.id).archived }) { m in   // 795: 归档成员不排 chip
                        if rows.contains(where: { $0.whoId == m.id }) { chip(m.id, MemberHub.aliasName(m.id) ?? m.name) }   // 919: chip 同走别名开关
                    }
                    if rows.contains(where: { $0.whoId == nil && $0.whoKind == "temp" }) {
                        chip(MemberHub.visitorId, "访客")   // 793 访客
                    }
                    if rows.contains(where: { $0.whoId == nil && $0.whoKind != "temp" }) {
                        chip("__unknown", "无法识别 · 可认领")
                    }
                    if allRows.contains(where: { $0.care }) { chip("__care", "保养") }   // 1028
                }
                .padding(.vertical, DS.Space.xxs)
            }
        } header: {
            HStack(spacing: DS.Space.s) {
                Text("按成员筛选")
                Spacer(minLength: DS.Space.s)
                Text(totalCount == rows.count ? "共 \(totalCount) 条" : "\(rows.count)/\(totalCount) 条")
                    .foregroundStyle(DS.Palette.textSub)
            }
        }
    }
    func chip(_ id: String, _ name: String) -> some View {
        let on = (sel == id)
        return Button {
            sel = id
            // 566: 同步写进会话保留的那一份 (见 QueryFilters.member) —— 点"全部"时 member 归空,
            // 不需要额外分支
            filters.member = id
            applyFilter()
        } label: {
            Text(name)
                // 字重固定: 改字重会改变字形宽度, 胶囊随之跳变
                .vkFont(.subheadline, weight: .medium)
                .lineLimit(1)
                .padding(.horizontal, DS.Space.l)
                .padding(.vertical, 12)   // 撑到 ≥44pt 触达
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



    // ---------- 数据 ----------
    /// 进页收尾 —— 2026-10-13 run 63 从 body 内联的 .onAppear 闭包里抽出 (巨型 body 里那段报 type-check 超时)。
    func onRecordsAppear() {
        // 2026-10-15 走查: 908 的开场过滤策略原先**只在视图构造时生效一次** —— 本页在 TabView 里
        // 长期存活, `filters` 是构造时读的 @State, 之后每次进记录页都不会重读, 于是
        // 「每次都从全部开始 / 每次默认只看告警」这两档从第二次进场起就形同虚设
        // (设置页那句"只改变进入记录页时的起点"落了空)。进场就按策略重取一次, 来源与构造时一致。
        filters = QueryFilters.load(mac: DB.preferredMac())
        // 566 开场恢复成员选择。908 的策略**不在这里重复判**: 策略是 QueryFilters.load 负责的
        // (选"每次空白"时它返回的就是空对象, member 自然为空) —— 这里再判一次就是两套规则。
        // 恢复后必须自己 applyFilter(): loadFromCache 已经跑过一次过滤，那一次还不知道有成员要恢复。
        if sel.isEmpty, !filters.member.isEmpty {
            sel = filters.member
            applyFilter()
        }
        // 包3/779: 多锁矩阵点格带入的成员过滤 (消费后清空, 不影响手动切换)
        if let f = app.pendingRecordsFilter {
            sel = f
            app.pendingRecordsFilter = nil
        }
        // 582 统计页成员条下钻带过来的成员 id (同样消费后清空, 落点走下面那条既有的成员过滤链)
        if let m = app.pendingRecordsMember { landMember(m) }
        // 585 记录引用深链落地 (进页时查一次)
        if let k = app.pendingRecordKey { landRecordKey(k) }
        // 586 当天全景落地
        if let d = app.pendingRecordsDay { landDay(d) }
        // 563 搜索词回填落地 (进页时一次性)
        if let q = app.pendingSearch { landSearch(q) }
        // 2026-10-28 修复：进页先渲染**本机缓存** —— 原来只有手动刷新失败时才 render 缓存，
        // 首次进页即使 DB.readLogs 有数据也显示「还没有记录」（用户会以为记录丢了）。
        // 缓存只在本机，不发起蓝牙连接；真正拉取仍由用户点「重新读取」触发。
        if allRows.isEmpty {
            let cached = DB.readLogs(mac)
            if !cached.isEmpty {
                render(cached.map { LogEntry(type: $0.type, typeName: $0.typeName,
                                               idx: $0.idxRaw, idxRaw: $0.idxRaw,
                                               lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr,
                                               body: "") }, offline: true)
            }
        }
    }
    // 2026-10-27 二轮精简：loadFromCache 已删（HotCache 移除后无缓存可读）。

    func fetch() async {
        guard !running, let kc = app.current else { return }
        running = true
        offline = false
        var events = [LogEntry]()
        do {
            // 分页拉日志走的是**无 mac 参数**的 getLogs，它成帧用服务层 curMac、发链用当前 GATT 连接。
            // 原来这里只有 `getStatus(mac:)`（try? 吞失败）：curMac 被绑到 B 锁、链路却还挂在 A 锁上，
            // 等于把"给 B 的帧"从 A 的链路发出去。先 ensureConnected(kc.mac) 才把链和键都对上。
            try await app.lock.ensureConnected(mac: kc.mac)
            // 现场 03 背书 (R2 唯一规则), 失败不阻断
            if let st = try? await app.lock.getStatus(mac: kc.mac) { app.status = st }
            var startIdx: UInt32 = 0xFFFFFFFF
            var page = 0
            var seen = Set<UInt32>()
            // 749 会话内完整性对账: 记住锁端最后一次报告的"剩余条数", 循环结束仍 > 0 就是本次没拉全
            var lastSurplus: Int?
            var noSurplusReport = false      // 锁端没回 KLV#04 时"拉全/未拉全"都无从判定, 不能当成拉全
            while page < 20 && events.count < 100 {
                let r = try await app.lock.getLogs(orderType: 0, startIdx: startIdx, pageSize: 5)
                guard !r.logs.isEmpty else { break }
                let fresh = r.logs.filter { !seen.contains($0.idxRaw) }
                // 游标回绕防护: 旧实现 startIdx = r.logs.last!.idxRaw &- 1, 在 idxRaw == 0 时回绕成
                // 0xFFFFFFFF → 反复重读最新页 (最多 20 轮), events 出现重复行 (ForEach 重复 id、门神榜与统计虚高)。
                // 现按"本页最小序号"前进, 且无新增即判定到表尾。
                guard !fresh.isEmpty else { break }
                fresh.forEach { seen.insert($0.idxRaw) }
                events.append(contentsOf: fresh)
                DB.writeLogs(kc.mac, fresh)
                let lowest = fresh.map { $0.idxRaw }.min() ?? 0
                guard lowest > 0 else { break }
                startIdx = lowest - 1
                page += 1
                guard let surplus = r.surplus else {
                    // 锁端未回 KLV#04: 只读到本页, 如实告知而非假装"已拉全"
                    noSurplusReport = true
                    app.showToast("锁端未报告剩余条数, 已读 \(events.count) 条")
                    break
                }
                if surplus <= 0 { break }
                lastSurplus = surplus
            }
            // 749 完整性对账 (仅声明本次会话内的事实, 不宣称"锁内日志已全"):
            // 循环因翻页上限退出时 lastSurplus 仍 > 0 → 如实标出缺口。
            if noSurplusReport {
                // 锁端没报告剩余条数 → 对账**不可判**; 这一种最容易被写成"已拉全", 那是假安慰
                pullGap = "锁端未报告剩余条数 (KLV#04)，本次只读到 \(events.count) 条 — 无法判断是否拉全"
                reconLine = "锁 \(app.displayName) · 本次拉取 \(events.count) 条 · 锁端未报告剩余 · 对账不可判 · \(Self.stamp.string(from: Date()))"   // 749 本次拉取
            } else if let gap = lastSurplus, gap > 0 {
                pullGap = "锁端仍报剩余 \(gap) 条，本次取 \(events.count) 条（翻页上限 20 页 / 100 条）— 属未拉全，不是记录缺失"
                reconLine = "锁 \(app.displayName) · 本次拉取 \(events.count) 条 · 锁端报告剩余 \(gap) 条 · 未拉全 · \(Self.stamp.string(from: Date()))"   // 749 本次拉取
            } else {
                pullGap = nil
                reconLine = "锁 \(app.displayName) · 本次拉取 \(events.count) 条 · 锁端报告无剩余 · 本次会话内已拉全 · \(Self.stamp.string(from: Date()))"   // 749 本次拉取
            }
            // 存取必须同型: set(Int) 落 JSON 数字, getString 解 String 必失败 → lastSyncAt 恒 nil,
            // 刚读完也会误报"未连接·读取时间未知"
            DB.store.set(syncStampKey, String(Int(Date().timeIntervalSince1970 * 1000)))
            render(events, offline: false)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            // 852 读取失败主动播报 (VoiceOver 运行时即时朗读, 含"离门太远"人话原因)
            AXTools.announceConnectFail(error.localizedDescription)
            let cached = DB.readLogs(kc.mac)
            if !cached.isEmpty {
                render(cached.map { LogEntry(type: $0.type, typeName: $0.typeName, idx: $0.idxRaw, idxRaw: $0.idxRaw, lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr, body: "") }, offline: true)
            } else {
                app.showToast("读取失败: \(error.localizedDescription)")
            }
        }
        running = false
        // 876 新条目双震: 本次读取有新增记录时两段 success 触感 (听障确认通道, 设置可关)
        if !events.isEmpty { AXTools.newEntryHaptic() }
    }

    func render(_ logs: [LogEntry], offline: Bool) {
        self.offline = offline
        // 92 (包1): 本地开锁失败标记合入时间线 — 手机侧记录 (DB.kf_fevents_), 绝不混入锁日志缓存;
        // type 0 非任何锁端日志类型, 归属推断自然回落"未归属", 行样式走普通灰图标
        var merged = logs
        // 手机侧行 (92 失败 / 1028 保养) 的**行身份**: 与 `RecordSearch.buildRecs` 给同一族事件用的键并成一份
        // ("f_" + Unix 秒 / "c_" + Unix 毫秒)。原先这两族行在单锁路径拿的是 `String(idxRaw)`,
        // 而那个 idxRaw 是 `Int(ts*1000) + 数组下标` 现编的派生数 —— 于是同一条记录在两种范围下行身份不同:
        // 单锁模式里 576 详情打不开、186 备注与 188 标旗写了不显示 (详情卡按 Rec 的键写, 行按派生数读),
        // 而 761 那行"复制行标识 (f_/c_ 前缀键)"的说明一直是假的。
        // 表键就是派生出来的那个 idxRaw: 它只在本机这一份合并数组里唯一, 不参与任何持久化。
        var sideKey = [UInt32: String]()
        let cls = Attribution.classify(
            logs: merged,
            pwds: DB.listPwds(mac), fps: DB.listFps(mac),
            status: app.status.map { ($0.fpStock, $0.pwdStock, $0.lockTime ?? 0) })
        // 791 认领覆盖层: 本机认领结果直接改写 whoId (不改锁端数据)
        let claims = MemberHub.claims(mac)
        var out = [RowVM]()
        let pwds = DB.listPwds(mac)
        let fps = DB.listFps(mac)
        for (i, e) in merged.enumerated() {
            guard i < cls.count else { continue }
            let c = cls[i]
            // 行身份只有一个来源: 锁日志 = idxRaw 字符串; 手机侧行 (type 0) = 上面算好的 f_/c_ 前缀键。
            // 791 认领的读写、186 备注、188 标旗、576 详情都从这里起, 不再各拿一份派生数。
            let rowKey = e.type == 0 ? (sideKey[e.idxRaw] ?? String(e.idxRaw)) : String(e.idxRaw)
            let p = Self.rowParts(e.lockTimeStr, todayKey: todayKey)   // 归属日 (649 凌晨归前一晚) + 显示时刻
            var whoId = c.who
            if let claimed = claims[rowKey] { whoId = claimed }   // 791 认领优先
            let whoName = whoId.flatMap { DB.member($0)?.name }
            // 655 动词化日志文案: "张三 用 指纹 开了门" (保留 791 认领与 1028 关怀行)
            let care = e.type == 0 && (e.typeName.hasPrefix("保养") || e.typeName.hasPrefix("更换电池"))
            let title: String
            if care || e.type == 0 {
                title = e.typeName   // 关怀/失败手机侧行保留原貌
            } else {
                let kindWord = StatsKit.openTypes.contains(e.type) ? (Attribution.words[c.kind ?? ""] ?? nil) : nil
                // 461: 条目显示"称呼（备注）"; whoName 留裸名给 credNav/筛选匹配 (919: 别名开关开时关系称呼顶替)
                let whoShow = MemberHub.aliasName(whoId)
                    ?? whoId.flatMap { DB.member($0).map(MemberHub.doubleLine) } ?? whoName
                title = RecordVerbs.line(type: e.type, who: whoShow, kindWord: kindWord, typeName: e.typeName)
            }
            let warn = StatsKit.alarmTypes.contains(e.type)
            // 791 可认领: 未归属且还没有认领记录 (temp 类进 793 访客虚拟分组, 不认领)
            let claimable = whoId == nil && c.kind != "temp" && !claims.keys.contains(rowKey)
            out.append(RowVM(key: rowKey, time: p.time,
                             dayKey: p.dayKey,
                             hour: p.hour, type: e.type,
                             title: title, whoId: whoId, whoKind: c.kind,
                             kind: c.kind, lockName: "", rowMac: mac,
                             credKey: Self.credNav(kind: c.kind, who: whoName, pwds: pwds, fps: fps),
                             warn: warn, claim: claimable, care: care))
        }
        allRows = out
        applyFilter()
    }
    /// 577 凭证深链: kind+归属 → pwd:<alias> / fp:<batch>; 台账无命中留空 (不深跳)
    static func credNav(kind: String?, who: String?, pwds: [LedgerPwd], fps: [LedgerFp]) -> String {
        switch kind {
        case "pwd":
            if let p = pwds.first(where: { !$0.temp && (who == nil || $0.owner == who) }) { return "pwd:" + String(p.alias) }
        case "temp":
            if let p = pwds.first(where: { $0.temp && (who == nil || $0.owner == who) }) { return "pwd:" + String(p.alias) }
        case "fp":
            if let f = fps.first(where: { (who == nil) || ($0.owner == who) || (!(who ?? "").isEmpty && $0.name.contains(who!)) }) { return "fp:" + String(f.batch) }
        default:
            break
        }
        return ""
    }

    /// 这一处原本自建 DateFormatter 且**没钉 `en_US_POSIX`**：用户在「设置 → 语言与地区 → 历法」
    /// 里选佛历/和历等非公历时，`yyyy` 会输出 2569 这类异 era 年份，与锁端日志的公历日 key 永不相等
    /// (§10.30)。归到 `StatsKit.dayKey` 一并解决。
    static func dayKey(_ d: Date) -> String { StatsKit.dayKey(d) }


    // ---------- 580/584/585 详情翻页与引用深链的数据源 ----------
    // 551/554/555/564/571/572/567/568/569/570/770: 行**内容**两种范围两条来源 (单锁 = 本地行池 allRows,
    // 全部锁 = 跨锁 Rec 现建的行池), 但 576/580/585 的判据池 `recPool` 两种范围喂的是同一份 ——
    // 详情卡认的是「哪把锁的哪一行」, 不是「你现在看着哪种范围」。
    /// 当前**显示顺序**里的记录 (月份跳转生效时同样收窄)。
    /// 为什么不用原始日志顺序: 详情卡的"上一条/下一条"要复现用户刚才扫读的那份结果，
    /// 被他筛掉的记录不该被翻页翻出来 —— 那等于悄悄改了筛选条件。
    /// 池子直接取 `recPool` (applyFilter 两种范围都会喂): 原先这里再调一次 buildRecs, 于是
    /// "点行开详情用的池"与"详情翻页用的池"是两次独立拉取 —— 同一次进页里它们可以不是同一份数据。
    var displayedRecs: [Rec] {
        var byOid = [String: Rec]()
        // 不用 Dictionary(uniqueKeysWithValues:): 本仓跨锁行键理论上能撞，撞了就是一次启动崩溃
        for r in recPool { byOid[RecordOverlay.oid(mac: r.mac, rowKey: r.key)] = r }
        return groups
            .filter { monthJump.isEmpty || $0.key.hasPrefix(monthJump) }
            .flatMap { $0.rows }
            .compactMap { byOid[$0.id] }   // RowVM.id 就是同一个 oid (键的算术只有一份)
    }

    /// 582 落地 (统计页成员条 → 记录 Tab): 把带过来的成员 id 写进**既有的**成员选择变量 `sel`,
    /// 再走既有的过滤链 (applyFilter)。`filters.member` 一起写是刻意的 —— 那是 566/192 会话保留里的
    /// 同一份成员过滤状态, 只改 `sel` 会出现"屏幕上在筛、下次进页又没筛上"的半截行为 (点成员 chip 的 `chip()`
    /// 写的就是这两个, 这里必须一致, 否则同一个功能两套状态)。
    /// id 认不出来时如实说一句并留在原范围, **不静默回落"全部"**: 静默回落等于告诉用户"这人没有记录"。
    /// 原句后半条"滚动到其最近一条"在本页默认倒序下就是列表首行, 不需要第二条滚动实现;
    /// 只有开了 570 正序回放或 187 月份收窄时首行不是它 —— 那半条要 ScrollViewReader, 与 18/187、579
    /// 记在同一张"需要编译器才动得了"的清单上 (§130), 这里不假装做了。
    func landMember(_ id: String) {
        app.pendingRecordsMember = nil
        guard !id.isEmpty else { return }
        guard DB.member(id) != nil else {
            app.showToast("那位成员已不在本机档案里 — 记录过滤没有改变")   // 582 那位成员已不在本机档
            return
        }
        sel = id
        filters.member = id
        applyFilter()
    }

    /// 563 落地: 把词填进搜索框。走 `searchText` 的既有 onChange ⇒ 边输入边更新的同一条链 (562)，
    /// 因此这里**不自己调 applyFilter** —— 两处都调会跑两遍过滤，第二遍才是最终结果，看着一样但白烧一次。
    func landSearch(_ q: String) {
        app.pendingSearch = nil
        let t = q.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        searchText = t
        app.showToast("已带入「\(t)」，可继续编辑")   // 563 已带入
    }

    /// 585 深链落地: 按 `mac#行键` 精确找那一条并开详情。
    /// 找不到就如实说"被筛选挡掉/缓存重整/锁已删除"三种可能，**绝不**打开相邻的一条凑数。
    func landRecordKey(_ k: String) {
        app.pendingRecordKey = nil
        guard !k.isEmpty else { return }
        if let hit = displayedRecs.first(where: { RecordOverlay.oid(mac: $0.mac, rowKey: $0.key) == k }) {
            detailRec = hit
            // 583: 闪与滚**等详情卡关闭后**再做 (见 flashOnClose 的说明)
            flashOnClose = RecordOverlay.oid(mac: hit.mac, rowKey: hit.key)
        } else {
            app.showToast("这条记录不在当前显示范围里 — 可能被筛选挡掉、缓存已重整，或锁已删除")   // 585 这条记录不在当前显示
        }
    }

    /// 657 无记录日占位行 / 675 假期外出分隔行 —— 时间轴的"连续感"由这一行负责，而不是补一堆空天。
    /// 两种写法是刻意的:
    ///   · 缺口 ≤7 天 ⇒ 逐日一行 "当日无开门记录" (几天而已，铺得开，也确实在说每一天);
    ///   · 缺口 >7 天 ⇒ **只给一行** "其间 N 天无记录"。30 天补 29 行灰条比缺口本身更吵，
    ///     而且没人能从那 29 行看出"哪些天真的没人出门"vs"哪些天只是没读到日志"。
    /// 含节假日的那一档才升级成 675 的"假期外出？"问句 (非警告样式 —— 它不是异常，只是一个猜测,
    /// 所以行里带问号也带"约"味, 不写成"假期外出"这种断定)。
    /// 586 当天全景的顶部条: 说明"现在只看这一天"并给出**唯一的退出入口**。
    ///
    /// 少了这条，从统计页/时间线点某天跳进来后，用户看到的是一天孤零零的列表，
    /// 会以为别的记录没了；而且**没有任何回到全部日子的入口**（只能绕去"按月份跳转→清除"）。
    /// 收窄显示范围必须同时告诉用户范围被收窄了 —— 与 657 那行"这不是没记录是筛掉了"同一个原则。
    @ViewBuilder
    var dayFocusBanner: some View {
        if !dayFocus.isEmpty {
            HStack(spacing: DS.Space.s) {
                Image(systemName: "calendar.day.timeline.left").accessibilityHidden(true)
                Text("只看 \(dayFocus) 这一天")   // 586 只看
                    .vkFont(.caption, weight: .medium)
                    .foregroundStyle(DS.Palette.text)
                Spacer(minLength: DS.Space.s)
                Button("看全部日子") { dayFocus = "" }
                    .vkFont(.caption, weight: .medium)
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
            }
            .padding(.vertical, DS.Space.xs)
            .accessibilityElement(children: .combine)
        }
    }

    /// 583 闪一下: 高亮 1.2 秒后自动撤。为什么不做成常亮:
    /// 常亮的"你在这里"会在用户继续往下读时变成"这条特殊"的误导，而它特殊的地方只是刚才被点过。
    func flashRow(_ oid: String) {
        flashKey = oid
        scrolledRow = oid
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            if flashKey == oid { flashKey = "" }
        }
    }

    /// 583 的一次性高亮底。做成小视图而不是三元: `listRowBackground` 只吃一个 View 类型，
    /// 而 `on ? 有色 : Color.clear` 在 `Rectangle().fill()` 里面就同类型了 —— 不用 AnyView。
    struct FlashWash: View {
        let on: Bool
        var body: some View {
            Rectangle()
                .fill(on ? DS.Palette.accent.opacity(0.14) : Color.clear)
                .transaction { $0.animation = nil }
        }
    }

    /// 583 的页内入口: 详情卡点"在时间线里定位这条"⇒ 关详情、滚过去、闪一下。
    func landFlash(_ oid: String) {
        app.pendingFlashKey = nil
        guard !oid.isEmpty else { return }
        flashRow(oid)
    }

    /// 586 落地: 把显示范围收到那一天。
    /// **先确认那一天在当前数据里真有行**才收窄 —— 跳进一个空白日子比不跳更让人以为数据丢了。
    func landDay(_ key: String) {
        app.pendingRecordsDay = nil
        guard !key.isEmpty else { return }
        if groups.contains(where: { $0.key == key && !$0.isGap }) {
            dayFocus = key
        } else {
            app.showToast("那一天在本机台账里没有行 — 未拉取、已过缓存上限，或日期写错")   // 586 那一天在本机台账里没
        }
    }

    func gapRow(_ g: DayGroup) -> some View {
        // 一行话先算清楚再上屏: 原来这里塞了两层三元 + Optional.map，读的人要同时记住"缺口长度"和
        // "有没有节假日"两件事才能确定它到底说什么 —— 那是把分支藏在字面量里。
        let line: String
        if g.gapDays > 7 {
            line = "其间 \(g.gapDays) 天无记录"   // 657 其间
        } else {
            line = "当日无开门记录"   // 657 当日无开门记录
        }
        let withHoliday = g.gapHoliday.map { line + " · 含\($0)，假期外出？" } ?? line   // 675 假期外出
        return HStack(spacing: DS.Space.s) {
            Capsule()
                .fill(DS.Palette.hairline)
                .frame(width: 3)
                .frame(maxHeight: 14)
                .accessibilityHidden(true)
            Text(withHoliday)
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Space.xs)
        .accessibilityElement(children: .combine)
    }
}
