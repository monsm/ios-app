// 记录行 · 日分组与时间线（daySection / timelineRow / rowTitle / gapRow）
// 2026-10-29 从 RecordsRows.swift（787 行）拆出。
import SwiftUI

extension RecordsRows {
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
}
