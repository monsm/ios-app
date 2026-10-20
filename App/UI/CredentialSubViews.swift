import SwiftUI

// 2026-10-20: 从被删除的 CredentialCenterView.swift 中恢复 (Q38 只删了「凭证中心」外壳页,
// 这些子视图仍被凭证页/日历/队列等真实入口使用, 必须保留)。

struct CredCalendarView: View {
    var mac: String
    var onPick: (Date) -> Void
    @State private var ym: Date = Date()
    @State private var picked: Date?

    var body: some View {
        // 912: 月历的 lead 计算走 WeekCal —— 与上面 weekdayHeaders 的轮转必须同源，否则整体错一天
        let cal = WeekCal.calendar
        let year = cal.component(.year, from: ym)
        let month = cal.component(.month, from: ym)
        let dl = CredentialOrg.monthDeadlines(mac, year: year, month: month)
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                HStack(spacing: DS.Space.s) {
                    Button("‹") { move(-1) }
                        .vkFont(.title3, weight: .semibold)
                        .frame(minHeight: DS.Hit.min)
                        .accessibilityLabel("上个月")
                    Spacer(minLength: 0)
                    Text("\(String(year)) 年 \(month) 月")
                        .vkFont(.headline)
                        .foregroundStyle(DS.Palette.text)
                    Spacer(minLength: 0)
                    Button("›") { move(1) }
                        .vkFont(.title3, weight: .semibold)
                        .frame(minHeight: DS.Hit.min)
                        .accessibilityLabel("下个月")
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: DS.Space.xs) {
                    ForEach(weekdayHeaders, id: \.self) { w in
                        Text(w)
                            .vkFont(.caption2)
                            .foregroundStyle(DS.Palette.textSub)
                            .frame(maxWidth: .infinity)
                    }
                    let cells = monthCells(year: year, month: month, ym: ym, cal: cal)
                    ForEach(0..<cells.count, id: \.self) { i in
                        if let d = cells[i] {
                            dayCell(year: year, month: month, day: d, count: dl[cal.date(from: DateComponents(year: year, month: month, day: d))!] ?? 0)
                        } else {
                            Color.clear.frame(height: 44)
                        }
                    }
                }
                if let p = picked {
                    let items = CredentialOrg.dayDeadlines(mac, p)
                    if !items.isEmpty {
                        Section("\(p.formatted(.dateTime.month().day())) 到期 (\(items.count))") {
                            ForEach(items) { x in
                                HStack(spacing: DS.Space.s) {
                                    Text(CredentialOrg.displayPwd(x))
                                        .vkFont(.subheadline)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                    Spacer(minLength: 0)
                                    Text(CredentialOrg.expiryLabel(x.to))
                                        .vkFont(.caption)
                                        .foregroundStyle(DS.Palette.textSub)
                                        .lineLimit(1)
                                }
                                .frame(minHeight: DS.Hit.min)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
                Spacer(minLength: DS.Space.l)
            }
            .padding(DS.Space.gutter)
        }
        .dsScreenBackground()
        .onAppear { picked = nil }
    }

    private var weekdayHeaders: [String] {
        // 912: 表头必须与月历 lead 用**同一个** firstWeekday 轮转。
        // 原来是硬写 ["日","一",…] 的周日开头 —— 它只是恰好等于 zh_CN 的默认值;
        // 一旦周起点可变而表头不动，格子就会整体错位一天 (周一的日期排在"日"下面)。
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        let fw = WeekCal.calendar.firstWeekday      // Calendar 约定 1...7，越界也要夹回来而不是 trap
        let start = min(max(fw - 1, 0), 6)
        return Array(names[start...] + names[..<start])
    }

    @ViewBuilder
    private func dayCell(year: Int, month: Int, day: Int, count: Int) -> some View {
        let d = WeekCal.gregorian.date(from: DateComponents(year: year, month: month, day: day))!
        let isToday = WeekCal.gregorian.isDateInToday(d)
        let isPicked = picked.map { WeekCal.gregorian.isDate($0, inSameDayAs: d) } ?? false
        Button {
            picked = isPicked ? nil : d
            if !isPicked { onPick(d) }
        } label: {
            VStack(alignment: .trailing, spacing: 2) {
                if count > 0 {
                    Text("\(count)")
                        .vkFont(.caption2, weight: .semibold)
                        // warn 是语义填充色, 走"填充上的前景"令牌 (浅档白字/深档墨字, 机检 E1)
                        .foregroundStyle(DS.Palette.onSem)
                        .padding(.horizontal, DS.Space.xs).padding(.vertical, DS.Space.xxs)
                        // @layout-allow VK豁免 语义色填充: 实心语义角标，同上
                        .background(DS.Palette.warn, in: Capsule())
                        .lineLimit(1)
                }
                Text("\(day)")
                    .vkFont(.subheadline)
                    .foregroundStyle(isToday ? DS.Palette.accentText : DS.Palette.text)
                    .frame(minWidth: 14)
            }
            .frame(maxWidth: .infinity, minHeight: DS.Hit.min)
            .background(isPicked ? DS.Palette.accentText.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(year) 年 \(month) 月 \(day) 日, 当日到期 \(count) 条")
    }
    /// 363 月历格: 前置空位 + 1...天数, 补齐到整周。
    /// 抽成函数是因为 `while` 循环不能出现在 ViewBuilder 里
    /// (会报 "closure containing control flow statement cannot be used with result builder 'ViewBuilder'")。
    private func monthCells(year: Int, month: Int, ym: Date, cal: Calendar) -> [Int?] {
        guard let first = cal.date(from: DateComponents(year: year, month: month, day: 1)),
              let days = cal.range(of: .day, in: .month, for: ym)?.count else { return [] }
        let lead = (cal.firstWeekday + 6 - cal.component(.weekday, from: first)) % 7
        var cells: [Int?] = Array(repeating: nil, count: lead)
        // 2026-10-13 run 59: 原写 `cells.append(contentsOf: 1...days)` —— cells 的元素是 `Int?`,
        // 而 `1...days` 的元素是 `Int`, 报 "no exact matches in call to instance method 'append'"
        // (候选要求 Element == Int)。逐个升成 Optional 再拼。
        cells.append(contentsOf: (1...days).map { Optional($0) })
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }
    private func move(_ delta: Int) {
        ym = WeekCal.gregorian.date(byAdding: .month, value: delta, to: ym) ?? ym
    }
}

// ================= 358/505 整理建议中心 =================

struct CredQueueView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    var mac: String
    @State private var busy: Int? = nil
    /// 「全部重试」互斥: 旧写法连点会开出多个并发 Task, 对同一队列重复下发删除/延期命令
    @State private var retryAllRunning = false

    var body: some View { vkBody.destined(.credQueue) }
    var vkBody: some View {
        List {
            let q = CredentialOrg.pendingQueue(mac)
            if q.isEmpty {
                Section {
                    Label {
                        Text("没有待处理项。停用/删除/延期操作在锁端未连接时会自动记入这里。")
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "tray").accessibilityHidden(true)
                    }
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                }
            }
            // 538 按锁排队: 队列头显示目标锁名与剩余项数 — 多锁各自队列不串台
            Section("未完成 (\(q.count)) · 目标锁 \(lockName) · 到场连接后逐条重试") {
                ForEach(q) { item in
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        HStack(spacing: DS.Space.s) {
                            StatusPill(text: stateText(item), systemImage: item.state == 2 ? "exclamationmark.triangle" : "arrow.down.circle", tone: tone(item))
                            Text(item.title)
                                .vkFont(.subheadline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                            if busy == item.id {
                                ProgressView().controlSize(.mini)
                            }
                        }
                        // 365 三步步条: 待下发 → 已下发 → 锁端确认 (rc@#03); 失败态可重试
                        // 2026-10-15 走查: 这三档原先是**取反**算的 (`item.state != 0 ? 2 : 1`),
                        // 而 state 只有 0 待下发 / 1 已完成 / 2 失败 三个值 (CredQueueState)。
                        // 取反的后果: 一条从没发出去的东西, "已下发"画成绿勾; 一条失败的, 前两档全绿。
                        // 屏上等于对用户说"已经发到锁上了"而其实一次都没发。只有 state == 1 才配绿勾。
                        // (第几次尝试、什么时候试过 —— 下面那行本来就写着, 失败标志在左侧那颗 pill 上。)
                        HStack(spacing: DS.Space.xs) {
                            step("待下发", item.state == 1 ? 2 : 1)
                            step("已下发", item.state == 1 ? 2 : 0)
                            step("锁端确认", item.state == 1 ? 2 : 0)
                            Spacer(minLength: 0)
                            Button("重试") { retry(item) }
                                .vkFont(.caption, weight: .medium)
                                .buttonStyle(.bordered)
                                .disabled(busy != nil)
                        }
                        if item.attempt > 0 {
                            Text("第 \(item.attempt) 次尝试 · \(itemTime(item.lastAt))")
                                .vkFont(.caption2)
                                .foregroundStyle(DS.Palette.textSub)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Section {
                Button("全部重试 (按序)") {
                    guard !retryAllRunning else { return }
                    retryAllRunning = true
                    Task {
                        defer { retryAllRunning = false }
                        for item in q {
                            busy = item.id
                            do {
                                try await app.lock.ensureConnected(mac: mac)
                                // 2026-10-13 对抗式排查: 把 sendQueued 的归位提示拼进 note
                                // (原先 `_ = ` 丢掉, 凭证页那处反而拼了 —— 两处口径不一致)
                                let extra = try await applyItem(item)
                                CredentialOrg.markQueue(mac, id: item.id, state: .done,
                                                         note: item.title + " · 锁端确认" + extra)
                            } catch {
                                CredentialOrg.markQueue(mac, id: item.id, state: .failed, note: item.title + " · 失败: " + error.localizedDescription)
                            }
                            busy = nil
                        }
                        app.showToast("已逐条重试 \(q.count) 项")
                    }
                }
                .disabled(retryAllRunning)
                .vkFont(.subheadline, weight: .medium)
                .foregroundStyle(retryAllRunning ? DS.Palette.textSub : DS.Palette.accentText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: DS.Hit.min)
            }
        }
        .navigationTitle("待下发队列")
        .variantList()
        .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) {
                Button("关闭") { dismiss() }
            } }
    }

    private var lockName: String {
        app.devices.first { $0.mac == mac }.map { LockArchive.displayName($0) } ?? String(mac.prefix(6))
    }
    private func stateText(_ i: CredQueueItem) -> String {
        switch i.state {
        case 1: return "已下发"
        case 2: return "失败"
        default: return "待下发"
        }
    }
    private func tone(_ i: CredQueueItem) -> ToneColor {
        switch i.state {
        case 1: return .ok
        case 2: return .danger
        default: return .warn
        }
    }
    /// 步条小段: 0 灰 / 1 当前黄 / 2 完成绿 (颜色 + 数字双通道, 不只靠颜色)
    private func step(_ label: String, _ level: Int) -> some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: level == 0 ? "circle" : (level == 1 ? "circle.inset.filled" : "checkmark.circle.fill"))
                .font(.system(size: 11))
                .foregroundStyle(level == 0 ? DS.Palette.textSub : (level == 1 ? DS.Palette.warn : DS.Palette.ok))
            Text(label)
                .vkFont(.caption2)
                .foregroundStyle(DS.Palette.textSub)
        }
        .accessibilityElement(children: .combine)
    }
    private func retry(_ item: CredQueueItem) {
        guard busy == nil else { return }
        // 第八十八批: 入口一次性钉住锁 (含非空校验)。原先 Task 里连读三次活读的 `mac` ——
        // ensureConnected 一次、成功回写一次、失败回写一次；两次 await 之间当前锁可被 AppIntent /
        // kf:// 深链改掉，于是"命令发给 A 锁、队列状态记到 B 锁"。current 变 nil 时 `?? ""`
        // 还会把队列状态写到空 mac 上 (等于把这条待办弄丢)。
        let m = mac
        guard !m.isEmpty else { app.showToast("未选择门锁"); return }
        busy = item.id
        Task {
            defer { busy = nil }
            do {
                try await app.lock.ensureConnected(mac: m)
                // 第一百五十四批: 这条 switch 曾有独立一份，且**没带**"缺别名就中止"的修正 ——
                // `item.pwd?.alias ?? 0` 会向锁发"删 0 号槽"，删掉的是别人的密码，
                // 回包后还被标成"锁端确认"。三份实现现在收进 CredentialOrg.sendQueued 一处。
                let extra = try await CredentialOrg.sendQueued(m, app.lock, item)
                CredentialOrg.markQueue(m, id: item.id, state: .done, note: item.title + " · 锁端确认" + extra)
                app.showToast("\(item.title) 已下发")
            } catch {
                CredentialOrg.markQueue(m, id: item.id, state: .failed, note: item.title + " · 失败: " + error.localizedDescription)
                app.showToast("重试失败: \(error.localizedDescription)")
            }
        }
    }
    /// 365 队列项下发: 唯一实现收在 CredentialOrg.sendQueued (第一百五十四批),
    /// 这里只做"发一条"的最小包装 —— 原先这一行引用的 applyItem 在全仓从未定义过。
    /// 2026-10-13 对抗式排查: 原写 `_ = try await CredentialOrg.sendQueued(...)` ——
    /// sendQueued 的返回值 (锁端把凭证落到新别名时的归位提示) 被**丢掉**, 而凭证页 :791 那一处
    /// 是 `let extra = try await ...` 并拼进了队列提示。同一件事两处口径不一致 ⇒ 凭证中心
    /// 少提示"锁端落到别名 #N"。改成把 extra 交回调用方。
    private func applyItem(_ item: CredQueueItem) async throws -> String {
        try await CredentialOrg.sendQueued(mac, app.lock, item)
    }
    private func itemTime(_ t: Double) -> String {
        guard t > 0 else { return "" }
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date(timeIntervalSince1970: t))
    }
}


struct CredExtendView: View {
    @EnvironmentObject var app: AppState
    var mac: String
    var aliases: [Int]
    var onDone: () -> Void
    @State private var from = Date()
    @State private var to = Date().addingTimeInterval(30 * 86400)
    @State private var busy = false

    var body: some View { vkBody.destined(.credExtend) }
    var vkBody: some View {
        NavigationStack {
            Form {
                Section("统一延期 (\(aliases.count) 条)") {   // 348 统一延期
                    DatePicker("生效", selection: $from, displayedComponents: .date)
                    DatePicker("延期至", selection: $to, in: from..., displayedComponents: .date)
                    Text("将一次性改写所选密码的过期字段并列出变更清单; 锁端改期记为「待下发」。")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section("变更清单") {
                    ForEach(aliases, id: \.self) { a in
                        if let p = DB.getPwd(mac, a) {
                            HStack(spacing: DS.Space.s) {
                                Text("#\(a)")
                                    .vkFont(.subheadline)
                                    .monospacedDigit()
                                Text(CredentialOrg.expiryLabel(p.to, verb: false) + " → " + to.formatted(.dateTime.year().month().day()))
                                    .vkFont(.caption)
                                    .foregroundStyle(DS.Palette.textSub)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                    }
                }
                Section {
                    BusyButton(title: "延期并登记待下发", isBusy: busy) {
                        Task { apply() }   // apply() 是同步方法: 那个 await 什么都没等 (UnnecessaryEffectMarker)
                    }
                }
            }
            .navigationTitle("统一延期")
            .variantList()
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) {
                Button("关闭") { onDone() }
            } }
        }
    }

    private func apply() {
        busy = true
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let out = CredentialOrg.batchExtend(mac, aliases, f.string(from: from), f.string(from: to))
        busy = false
        app.showToast("已改写 \(out.count) 条有效期, 锁端改期待下发")   // 348 已改写
        _ = Milestones.recordOrganize()
        onDone()
    }
}


struct CredTransferView: View {
    @EnvironmentObject var app: AppState
    var mac: String
    var pwdAliases: [Int]
    var fpBatches: [Int]
    var onDone: () -> Void
    @State private var target: String? = nil

    var body: some View { vkBody.destined(.credTransfer) }
    var vkBody: some View {
        NavigationStack {
            List {
                Section("批量移交 (\(pwdAliases.count + fpBatches.count) 条)") {   // 349 批量移交
                    Picker("移交给", selection: $target) {
                        Text("解除归属").tag(nil as String?)
                        ForEach(DB.members()) { m in
                            Text(m.name).tag(m.id as String?)
                        }
                    }
                    .pickerStyle(.inline)
                    Text("批量改归属并各写一条本地记录; 锁端无归属字段, 移交只作用于本机台账。")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section {
                    Button("确认移交") {
                        let n = CredentialOrg.batchTransfer(mac, pwdAliases: pwdAliases, fpBatches: fpBatches, to: target)
                        app.showToast("已移交 \(n) 条" + (target.map { " → " + (DB.member($0)?.name ?? "") } ?? " → 无归属"))
                        _ = Milestones.recordOrganize()
                        onDone()
                    }
                    .vkFont(.subheadline, weight: .semibold)
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: DS.Hit.min)
                }
            }
            .navigationTitle("批量移交")
            .variantList()
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) {
                Button("关闭") { onDone() }
            } }
        }
    }
}


struct CredDisableSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    var mac: String
    var pwdAliases: [Int]
    var fpBatches: [Int]
    var onDone: () -> Void
    /// 313 停用必填原因: 空值 = 确认按钮不可点 (不给默认值, 免得"默认原因"变成假记录)
    @State private var reason = ""
    /// 367 写入成员动态: 默认关 —— 默认往别人的档案页写一条东西, 等于未经确认改数据
    @State private var writeToFeed = false
    private static let reasons: [(String, String)] = [
        ("leak", "疑似泄露"), ("rotate", "换码"), ("person", "人员变动"), ("other", "其他")]

    /// 367 影响成员及各自名下条数。**按名册顺序**出, 不用 Array(Set(...)):
    /// Set 的顺序每次启动都可能变 ⇒ 头像列会左右跳, 逐条写动态时同一批凭证还会写到不同顺序里。
    private var ownerCounts: [(id: String, pwd: Int, fp: Int)] {
        let pwds = DB.getPwdList(pwdAliases, mac)
        let fps = DB.getFpList(fpBatches, mac)
        let ids = Set(pwds.compactMap { $0.owner } + fps.compactMap { $0.owner })
        return DB.members().filter { ids.contains($0.id) }.map { m in
            (id: m.id, pwd: pwds.filter { $0.owner == m.id }.count, fp: fps.filter { $0.owner == m.id }.count)
        }
    }
    private var ownerIds: [String] { ownerCounts.map { $0.id } }
    /// 没归属的那几条: 它们不进任何人的动态, 这句话得能在界面上说出来。
    private var unownedCount: Int {
        max(0, (pwdAliases.count + fpBatches.count) - ownerCounts.reduce(0) { $0 + $1.pwd + $1.fp })
    }
    /// 367 勾选行文案。「另有 0 条无归属」是把界面写成噪音, 所以只在真有的时候才出现那一半。
    private var feedToggleLabel: String {
        let head = "写入该成员动态 (影响 \(ownerIds.count) 位成员, 各写自己名下的条数)"   // 367 写入该成员动态
        return unownedCount > 0 ? head + "; 另有 \(unownedCount) 条无归属, 不进任何人的动态" : head
    }

    var body: some View {
        NavigationStack {
            List {
                Section("停用摘要") {   // 353 停用摘要
                    HStack(spacing: DS.Space.s) {
                        // 影响成员头像列 (成员色点 183 风格, 纯本地) —— 名单见 ownerCounts, 顺序稳定
                        ForEach(ownerIds, id: \.self) { id in
                            if let m = DB.member(id) {
                                Circle()
                                    .fill(DS.Palette.accentText)
                                    .frame(width: 26, height: 26)
                                    .overlay(Text(String(m.name.prefix(1)))
                                        .vkFont(.caption2)
                                        // accentText 在深色模式是浅紫, 白首字母压上去几乎看不见
                                        .foregroundStyle(DS.Palette.onAccent)
                                        .lineLimit(1))
                                    .accessibilityLabel("成员 \(m.name)")
                            }
                        }
                        Text("影响 \(ownerIds.count) 位成员")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text("密码 \(pwdAliases.count) 条 · 指纹 \(fpBatches.count) 条")
                            .vkFont(.subheadline, weight: .semibold)
                        ForEach(pwdsLines, id: \.self) { line in
                            Text(line)
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        ForEach(fpLines, id: \.self) { line in
                            Text(line)
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                }
                Section {
                    Text("不可逆说明: 停用后本机台账移除, 锁端删除记为「待下发」— 7 天内可一键恢复, 超期需重新录入/生成。")   // 364 不可逆说明
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                    // 313: 原因四选一, 没选就不许停用 (工单系统的"必填原因"口径)
                    HStack(spacing: DS.Space.xs) {
                        ForEach(Array(Self.reasons.enumerated()), id: \.offset) { _, r in
                            let on = reason == r.0
                            Button(r.1) {
                                reason = r.0
                                DS.Haptics.tick.impactOccurred()
                            }
                            .vkFont(.caption.weight(on ? .semibold : .regular))
                            .padding(.horizontal, DS.Space.s).padding(.vertical, DS.Space.s)
                            .foregroundStyle(on ? DS.Palette.onAccent : DS.Palette.textSub)
                            .background(on ? AnyShapeStyle(DS.Palette.accent) : AnyShapeStyle(DS.Palette.surfaceAlt), in: Capsule())
                            .frame(minHeight: DS.Hit.min - DS.Space.xs)
                            .contentShape(Rectangle())
                            // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 没有 minHeight (< 44)。
                            // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Rectangle())
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("停用原因\(reason.isEmpty ? ", 未选择" : "")")   // 313 停用原因
                    if reason.isEmpty {
                        Text("先选一个停用原因才能继续 — 原因只写进本机审计与运行日志，不会发给门锁。")
                            .vkFont(.caption2).foregroundStyle(DS.Palette.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // 367: 原句就是「勾选写入该成员动态」。勾上之后按归属各写一条 (每人只看到自己名下的条数),
                    // 不勾则维持改动前那一条汇总流水 —— 两种形态各写各的, 绝不双写:
                    // 同一件事在敏感流水里出现两行, 388 那个视图就会把一次停用数成两次。
                    if !ownerIds.isEmpty {
                        VariantToggle(feedToggleLabel, isOn: $writeToFeed)
                            .vkFont(.footnote)
                    }
                    // 353 二次点确认: 摘要页(一次) + 破坏性按钮(二次)
                    Button {
                        let label = Self.reasons.first { $0.0 == reason }?.1 ?? "其他"
                        let n = pwdAliases.count + fpBatches.count
                        // 只记条数与原因: 口令明文与指纹特征绝不进日志 (AUTOOPEN-PLAN §1 同一纪律)
                        app.lock.log("info", "停用 \(n) 条凭证 · 原因 \(label)")   // 313 停用
                        if writeToFeed {
                            for o in ownerCounts {
                                SensitiveLedger().record("停用·\(label)", target: "密码 \(o.pwd) / 指纹 \(o.fp)", member: o.id)
                            }
                        } else {
                            SensitiveLedger().record("停用·\(label)", target: "密码 \(pwdAliases.count) / 指纹 \(fpBatches.count)")
                        }
                        // 361: 逐条落一个回溯便签, 回收站行才答得出"这条当初为什么被停"
                        // 468 代管补记: 属主被点名「由我代管」的条, via 与单条停用同一口径补「管理员代操作」。
                        // 按条拆开各写各的 —— 没代管的条不许整批跟着沾这句 (同单条 disableVia 的判据)。
                        let proxyIDs = MemberHub.proxyNames
                        let proxyPwds = DB.getPwdList(pwdAliases, mac)
                            .filter { p in p.owner.map { proxyIDs.contains($0) } == true }.map(\.alias)
                        let proxyFps = DB.getFpList(fpBatches, mac)
                            .filter { f in f.owner.map { proxyIDs.contains($0) } == true }.map(\.batch)
                        CredentialOrg.markDisabled(mac, kind: "pwd", keys: pwdAliases.filter { !proxyPwds.contains($0) },
                                                   label: label, via: "本机批量停用")
                        CredentialOrg.markDisabled(mac, kind: "pwd", keys: proxyPwds,
                                                   label: label, via: "本机批量停用 · 管理员代操作")   // 468 本机批量停用
                        CredentialOrg.markDisabled(mac, kind: "fp", keys: fpBatches.filter { !proxyFps.contains($0) },
                                                   label: label, via: "本机批量停用")
                        CredentialOrg.markDisabled(mac, kind: "fp", keys: proxyFps,
                                                   label: label, via: "本机批量停用 · 管理员代操作")   // 468 本机批量停用
                        onDone()
                        dismiss()
                    } label: {
                        Text(reason.isEmpty ? "先选择停用原因" : "确认停用 (\(pwdAliases.count + fpBatches.count) 条)")   // 313 先选择停用原因
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: DS.Hit.min)
                    }
                    .buttonStyle(DestructiveActionStyle())
                    .disabled(reason.isEmpty)
                    .opacity(reason.isEmpty ? 0.45 : 1)
                    .accessibilityHint(reason.isEmpty
                        ? "需先选停用原因才能执行"
                        : "已展示影响成员与不可逆说明, 点按即执行停用")
                }
            }
            .navigationTitle("批量停用确认")
            .variantList()
            .dsScreenBackground()
            // 取消 = 只退出, 绝不触发 onDone (调用方 CredentialsView 的 onDone 即 finishDisable, 执行停用与入回收站)
            .toolbar { ToolbarItem(placement: .navigationBarLeading) {
                Button("取消") { dismiss() }
            } }
        }
    }

    private var pwdsLines: [String] {
        DB.getPwdList(pwdAliases, mac).prefix(6).map { "#\($0.alias) · \(CredentialOrg.countdown($0))" }
    }
    private var fpLines: [String] {
        DB.getFpList(fpBatches, mac).prefix(6).map { "「\($0.name)」" }
    }
}
