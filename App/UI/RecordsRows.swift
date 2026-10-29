// 记录页 · 行渲染（时间线分组 / 单行 / 标题 / 高亮 / 成员色 / 空档行）
// 2026-10-29 从 RecordsView.swift（2036 行）拆出。
// 这些是 RecordsView 的 extension —— 原 private 成员已提升为 internal，跨文件可见。
import SwiftUI

extension RecordsView {



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
        // 2026-10-29 性能：原先逐成员调 ext()（各自整表解码）。提到 Section 外一次取表 ——
        // 写进 filter 闭包内等于每比较一次解一次，等于没改。
        let extTable = MemberHub.allExt()
        return Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s) {
                    chip("", "全部")
                    ForEach(DB.members().filter { !MemberHub.ext($0.id, in: extTable).archived }) { m in   // 795: 归档成员不排 chip
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
        // 2026-10-29 并发：`guard !running` + `running = true` 在 MainActor 上是原子的，
        // 但**同一个按钮连点两次**会各自起一个 Task，第二个在第一个 `running = true` 之后
        // 才真正进入函数体 —— 那时 guard 已能拦住，所以这里够用；
        // 真正需要防的是「第一次 fetch 还没跑完，用户切了锁」—— 那种情况下
        // 第二次 fetch 用新 kc 覆盖 running，第一次结束时的 `running = false` 会把
        // 第二次的守卫提前解掉。用一个自增序号把「过期的那次」直接丢弃。
        // 2026-10-29 补：并发的第二次 fetch 直接丢弃 —— 否则两次分页会互相覆盖 seen/startIdx，
        // 还可能各写一次 DB.writeLogs（合并语义下不会丢数据，但会重复拉 20 页）。
        guard !running else { return }
        guard let kc = app.current else { return }
        let ticket = fetchTicket + 1
        fetchTicket = ticket
        defer { if fetchTicket == ticket { running = false } }
        running = true
        offline = false
        var events = [LogEntry]()
        do {
            // 分页拉日志走的是**无 mac 参数**的 getLogs，它成帧用服务层 curMac、发链用当前 GATT 连接。
            // 原来这里只有 `getStatus(mac:)`（try? 吞失败）：curMac 被绑到 B 锁、链路却还挂在 A 锁上，
            // 等于把"给 B 的帧"从 A 的链路发出去。先 ensureConnected(kc.mac) 才把链和键都对上。
            try await app.lock.ensureConnected(mac: kc.mac)
            // 现场 03 背书 (R2 唯一规则), 失败不阻断
            if let st = try? await app.lock.getStatus(mac: kc.mac) { app.applyStatus(st) }
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
                // 2026-10-29 性能 + 正确性：原来每页都调 DB.writeLogs（最多 20 次全量落盘，且会互相覆盖）。
                // 现在循环结束统一写一次（writeLogs 自己也改成合并语义）。
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
            // 2026-10-29：把本次拉到的全部记录一次性合并落盘（分页循环里不再逐页写）。
            if !events.isEmpty { DB.writeLogs(kc.mac, events) }
            // 存取必须同型: set(Int) 落 JSON 数字, getString 解 String 必失败 → lastSyncAt 恒 nil,
            // 刚读完也会误报"未连接·读取时间未知"
            DB.store.set(syncStampKey, String(Int(Date().timeIntervalSince1970 * 1000)))
            render(events, offline: false)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            // 852 读取失败主动播报 (VoiceOver 运行时即时朗读, 含"离门太远"人话原因)
            AXTools.announceConnectFail(error.localizedDescription)
            // 2026-10-29：分页中途失败时，已拉到的页也要合并落盘（原实现是每页即时写，
            // 改成循环外统一写之后必须在这里补一次，否则中途失败会把已读到的证据丢掉）。
            if !events.isEmpty { DB.writeLogs(kc.mac, events) }
            let cached = DB.readLogs(kc.mac)
            if !cached.isEmpty {
                render(cached.map { LogEntry(type: $0.type, typeName: $0.typeName, idx: $0.idxRaw, idxRaw: $0.idxRaw, lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr, body: "") }, offline: true)
            } else {
                app.showToast("读取失败: \(error.localizedDescription)")
            }
        }
        // running 由 defer 复位（只有"最新那次"才有权复位，见函数头注释）。
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
        // 2026-10-29 性能：listPwds/listFps 原来各读两次（classify 一次、下面又各读一次），
        // 每次都是一份数组拷贝；这里先取一次，两处共用。
        let pwds = DB.listPwds(mac)
        let fps = DB.listFps(mac)
        let cls = Attribution.classify(
            logs: merged,
            pwds: pwds, fps: fps,
            status: app.status.map { ($0.fpStock, $0.pwdStock, $0.lockTime ?? 0) })
        // 791 认领覆盖层: 本机认领结果直接改写 whoId (不改锁端数据)
        let claims = MemberHub.claims(mac)
        // 2026-10-29 性能：原先每行调两次 DB.member(id)（各自从字典重建一次 Member）。
        // 300 行 = 600 次重建；这里一次建表。
        let memberByID = Dictionary(DB.members().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out = [RowVM]()
        for (i, e) in merged.enumerated() {
            guard i < cls.count else { continue }
            let c = cls[i]
            // 行身份只有一个来源: 锁日志 = idxRaw 字符串; 手机侧行 (type 0) = 上面算好的 f_/c_ 前缀键。
            // 791 认领的读写、186 备注、188 标旗、576 详情都从这里起, 不再各拿一份派生数。
            let rowKey = e.type == 0 ? (sideKey[e.idxRaw] ?? String(e.idxRaw)) : String(e.idxRaw)
            let p = Self.rowParts(e.lockTimeStr, todayKey: todayKey)   // 归属日 (649 凌晨归前一晚) + 显示时刻
            var whoId = c.who
            if let claimed = claims[rowKey] { whoId = claimed }   // 791 认领优先
            let whoName = whoId.flatMap { memberByID[$0]?.name }
            // 655 动词化日志文案: "张三 用 指纹 开了门" (保留 791 认领与 1028 关怀行)
            let care = e.type == 0 && (e.typeName.hasPrefix("保养") || e.typeName.hasPrefix("更换电池"))
            let title: String
            if care || e.type == 0 {
                title = e.typeName   // 关怀/失败手机侧行保留原貌
            } else {
                let kindWord = StatsKit.openTypes.contains(e.type) ? (Attribution.words[c.kind ?? ""] ?? nil) : nil
                // 461: 条目显示"称呼（备注）"; whoName 留裸名给 credNav/筛选匹配 (919: 别名开关开时关系称呼顶替)
                let whoShow = MemberHub.aliasName(whoId)
                    ?? whoId.flatMap { memberByID[$0].map(MemberHub.doubleLine) } ?? whoName
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
        // 2026-10-29 性能：去年今日的命中数跟日志一起算一次，别让 body 每次再扫一遍。
        lastYearToday = Self.countLastYearToday(merged)
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
