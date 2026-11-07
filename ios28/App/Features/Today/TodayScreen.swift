// TodayScreen.swift —— 今日。整个 App 的主角。
//
// 构图的三个层次：
//   1. 日光窗（室外）：一块有厚度的玻璃，一行衬线字说清现在的状态。
//   2. 门槛（镜头）：解锁镜头骑在窗沿上，环走的是真实命令链。
//   3. 室内（内容）：读数、工具托盘、最近发生的事。
//
// 这一版补上的：
//   · F25 常驻链路状态（LinkPill）与「读一次 / 重画界面」的语义区分；
//   · F15 开锁失败后给**可执行的下一步**（诊断卡），不是一句报错；
//   · F16 开锁成功的回执卡（自动上锁倒计时 + 这次用的凭证）；
//   · F32 首屏骨架屏；F54 首页分区可编排。
import SwiftUI
import UIKit

@MainActor
struct TodayScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    /// F12/B64：尺寸类 —— regular 时（iPad 全屏、横屏）走左右两栏。
    @Environment(\.horizontalSizeClass) private var hSize

    private var wide: Bool { LayoutMode.isWide(hSize) }

    /// 成功的动作也要有回声：原先只有 `app.lastError` 一条出口，
    /// 校时成功、读完日志这类「什么都没发生」的动作在界面上等于没点。
    @State private var notice: String?
    /// 开锁成功的回执卡（F16）。镜头成功后会回到 idle，所以回执由本视图自己记着。
    @State private var receipt: Bool = false

    private var settings = SettingsStore.shared

    var body: some View {
        ScreenScroll {
            if app.lock == nil {
                if app.isLoading {
                    ScreenSkeleton(rows: 2)
                } else {
                    EmptyHome()
                }
            } else {
                // F41：蓝牙没开时，页内说明 + 跳系统设置。
                // 以前这件事只在点开锁失败之后才显形 —— 用户已经站在门口了。
                if !BLEService.shared.isPoweredOn {
                    PermissionNotice(symbol: "antenna.radiowaves.left.and.right.slash",
                                     title: "蓝牙没有开",
                                     detail: "门锁走的是蓝牙直连，不需要网络 —— 但蓝牙得开着。",
                                     openSettings: openBluetoothSettings)
                }
                // F12/B64：宽版（iPad / 横屏）左右两栏，紧凑版仍是一条竖轴。
                twoColumns(wide) {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        hero
                        if receipt { receiptCard }
                    }
                } trailing: {
                    VStack(alignment: .leading, spacing: 0) {
                        if settings.homeSections.contains("readings") { readings }
                        if settings.homeSections.contains("tray") { tray }
                        if settings.homeSections.contains("recent") { recent }
                        // 失败与诊断：结构化的失败走诊断卡（F15），其余仍是一行提示。
                        if app.lastUnlockFailure != nil {
                            diagnosisCard
                        } else if let error = app.lastError {
                            note(error)
                        }
                        if let notice {
                            successNote(notice)
                        }
                    }
                }
            }
        }
        .background(Color.clear)
        .toolbar(.hidden, for: .navigationBar)
        // 「开门时保持亮屏」：这一屏就是门口那一页 —— 亮着才不至于话没说完就息屏。
        // 开关在「外观 · 手感」里；离开这一屏就把息屏交还给系统。
        .onAppear { ScreenAwake.want(SettingsStore.shared.keepScreenAwake) }
        .onDisappear { ScreenAwake.want(false) }
        .onChange(of: SettingsStore.shared.keepScreenAwake) { _, on in ScreenAwake.want(on) }
        // 回执：镜头走到「已打开」时亮出来，6 秒后自己收走。
        .onChange(of: app.phase) { _, phase in
            if phase == .opened {
                receipt = true
                Task {
                    try? await Task.sleep(for: .seconds(6))
                    if receipt { withAnimation(T.M.settle) { receipt = false } }
                }
            }
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Kicker(text: "\(app.lock?.name ?? "门锁") · \(statusWord)", dot: true, tint: T.C.ink2)
                Text(greeting)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink2)
            }
            Spacer(minLength: 12)
            // F25：链路状态常驻。它回答的是「现在能不能开门」——
            // 以前这件事只能靠点一次开锁去试探。
            LinkPill(phase: app.link.phase,
                     rssi: app.link.lastRSSI,
                     busy: app.link.busy) {
                Task { await app.link.reconnect() }
            }
            AvatarBadge(initial: initial, size: 38)
                .accessibilityHidden(true)
        }
        .padding(.top, 8)
        .frame(minHeight: 44)
    }

    private var statusWord: String {
        if app.phase.isBusy { return "正在开锁" }
        if app.link.phase == .ready { return "已连接" }
        return app.link.phase.rawValue
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let word: String
        switch hour {
        case 5 ..< 11: word = "早上好"
        case 11 ..< 14: word = "中午好"
        case 14 ..< 18: word = "下午好"
        case 18 ..< 23: word = "晚上好"
        default: word = "夜深了"
        }
        return "\(word)，\(displayName)"
    }

    private var displayName: String {
        if let owner = app.members.first(where: { $0.role == .owner }) {
            return owner.name
        }
        return app.members.first?.name ?? "你"
    }

    private var initial: String {
        String(displayName.prefix(1))
    }

    // MARK: - 日光窗

    private var hero: some View {
        ZStack(alignment: .bottom) {
            DaylightPane(height: 336) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Kicker(text: "THRESHOLD · \(app.lock?.name ?? "门锁")", dot: true, tint: T.C.ink2)
                        Spacer()
                        // 这一行是「现在几点」。原先直接读 `Date()` —— 视图不重画它就不走，
                        // 停在打开 App 的那一刻。用时间线让它自己每分钟走一格。
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            Text(When.clock(Int64(context.date.timeIntervalSince1970)))
                                .type(T.F.mono)
                                .foregroundStyle(T.C.ink2)
                        }
                    }
                    Spacer(minLength: 12)
                    DisplayLine(text: heroLine, size: 46)
                    Text(heroSub)
                        .type(T.F.footnote)
                        .foregroundStyle(T.C.ink2)
                        .padding(.top, 11)
                        .lineLimit(2)
                    Spacer().frame(height: 62)
                }
                .padding(26)
            }

            UnlockLens(phase: app.phase, enabled: app.lock != nil) {
                Task { await app.unlock() }
            }
            .offset(y: 58)
        }
        .padding(.top, 4)
        .padding(.bottom, 68)
        .animation(T.M.settle, value: app.phase)
    }

    private var heroLine: String {
        switch app.phase {
        case .opened: return "门开了。"
        case .failed: return "没打开。"
        case .reaching, .sending, .waiting: return "稍等。"
        case .idle: break
        }
        if app.todayAlarmCount > 0 { return "今天有一声警报。" }
        return "一切如常。"
    }

    private var heroSub: String {
        switch app.phase {
        case .reaching: return "正在连上门锁"
        case .sending: return "命令已下发 · 正在等门锁回执"
        case .waiting: return "门锁还没有回执"
        case .opened: return "已确认门锁回执 · 约 \(app.autoLockLeft ?? 6) 秒后自动上锁"
        case .failed(let why): return why
        case .idle: break
        }
        // 「上次开门」只在**有日期**的记录里找：锁端没读到时钟的记录不知道发生在什么时候，
        // 拿它的 time = 0 去格式化会印出「08:00」。
        if let last = app.events.first(where: { $0.isOpen && $0.hasTime }) {
            var parts = ["上次开门 \(When.clock(last.time))"]
            if let who = last.whoName { parts.append(who) }
            if !last.credential.isEmpty { parts.append(last.credential) }
            return parts.joined(separator: " · ")
        }
        return "还没有开过门。轻点镜头，试试看。"
    }

    // MARK: - 回执卡（F16）

    private var receiptCard: some View {
        UnlockReceiptCard(credential: app.lastUnlockCredential,
                          autoLockSeconds: app.autoLockLeft ?? 6) {
            router.goToLogRoot()
        }
    }

    // MARK: - 诊断卡（F15）

    private var diagnosisCard: some View {
        UnlockDiagnosisCard(
            failure: app.lastUnlockFailure,
            steps: UnlockDiagnosis.steps(failure: app.lastUnlockFailure,
                                          linkPhase: app.link.phase,
                                          battery: app.lock?.battery ?? -1,
                                          safeMode: app.lock?.safeMode ?? false,
                                          muted: app.lock?.muted ?? false),
            onRetry: { Task { await app.unlock() } },
            onOpenSettings: openBluetoothSettings,
            onDiagnose: {
                router.openSettings()
                router.pushSettings(.diagnostics)
            })
    }

    // MARK: - 读数

    private var readings: some View {
        VStack(alignment: .leading, spacing: 0) {
            // F38：陈旧徽标。读数是「上次读到的」，不能冒充实时 ——
            // 这里用**状态快照**的时间戳，不是日志同步时间（那是另一件事）。
            if let snap = DB.readStatus(app.currentMac), DB.isStatusStale(app.currentMac) {
                StaleBadge(at: Int64(snap.at)) {
                    Task { await app.refreshStatus() }
                }
                .padding(.bottom, T.S.s)
            }
            ReadingRow(items: [
                (label: "电量", value: batteryText, unit: batteryUnit),
                (label: "信号", value: LinkSenseModel.levelWord(app.link.rssiLevel), unit: app.link.lastRSSI.map { "\($0) dBm" }),
                (label: "固件", value: firmwareText, unit: nil),
            ])
        }
    }

    private var batteryText: String {
        let value = app.lock?.battery ?? -1
        if value < 0 { return "—" }
        if value > 80 { return ">80" }
        return "\(value)"
    }

    private var firmwareText: String {
        let fw = app.lock?.firmware ?? ""
        return fw.isEmpty ? "—" : fw
    }

    private var batteryUnit: String? {
        let value = app.lock?.battery ?? -1
        return value < 0 || value > 80 ? nil : "%"
    }

    // MARK: - 工具托盘

    private var tray: some View {
        ToolTray(items: quickItems) { item in
            runQuick(item.id)
        }
        .padding(.top, 20)
    }

    private var quickItems: [ToolTray.Item] {
        let chosen = QuickPool.ordered().prefix(SettingsStore.shared.quickGridCount)
        var items: [ToolTray.Item] = []
        for action in chosen {
            items.append(.init(id: action.id, symbol: symbol(for: action.id, fallback: action.icon), title: shortLabel(action.id, fallback: action.label)))
        }
        return items
    }

    private func symbol(for id: String, fallback: String) -> String {
        switch id {
        case "addPwd": return "key"
        case "otp": return "clock.arrow.circlepath"
        case "syncTime": return "clock"
        case "addFp": return "touchid"
        case "studio": return "square.grid.2x2"
        case "again": return "arrow.counterclockwise"
        case "backup": return "archivebox"
        case "tailgate": return "figure.walk"
        case "safemode": return "lock.shield"
        case "dfu": return "arrow.up.circle"
        default: return fallback
        }
    }

    private func shortLabel(_ id: String, fallback: String) -> String {
        switch id {
        case "addPwd": return "密码"
        case "otp": return "动态码"
        case "syncTime": return "校时"
        case "addFp": return "指纹"
        case "studio": return "凭证"
        case "again": return "再开"
        case "backup": return "备份"
        case "tailgate": return "防尾随"
        case "safemode": return "双验"
        case "dfu": return "固件"
        default: return fallback
        }
    }

    private func runQuick(_ id: String) {
        QuickPool.recordTap(id)
        switch id {
        case "addPwd":
            router.goToAccessRoot()
            router.push(.credentialCreate)
        case "addFp":
            // 「指纹」必须落到指纹那条链上：只 push 新凭证页的话，它默认停在「密码」——
            // 点「指纹」看到的是一张密码表单。
            router.goToAccessRoot()
            router.pendingCreateKind = "fingerprint"
            router.push(.credentialCreate)
        case "otp":
            router.goToAccessRoot()
            router.push(.zotp)
        case "studio":
            router.goToAccessRoot(segment: 0)
        case "again":
            Task { await app.unlock() }
        case "syncTime":
            Task {
                // 校时失败要说话：这个快捷动作没有自己的错误出口，
                // 结果落到页脚那一行（`app.lastError`）。原先 `_ =` 把它扔了 ——
                // 点了「校时」，失败了也一点动静都没有。
                // 成功同样要说一句，否则「点了没反应」和成功长得一模一样。
                switch await app.syncTime() {
                case .success(let pair):
                    app.lastError = nil
                    // `after == nil` 是「指令发了，但没读回来」，不能报成已对齐。
                    flash(pair.1 == nil ? "校时指令已下发，但没能回读确认。"
                                        : "锁钟已对齐。")
                case .failure(let error):
                    app.lastError = error.localizedDescription
                }
            }
        case "backup":
            router.openSettings()
            router.pushSettings(.backup)
        case "tailgate", "safemode":
            router.openSettings()
            router.pushSettings(.lockPolicy)
        case "dfu":
            router.openSettings()
            router.pushSettings(.dfu)
        default:
            router.push(.insights)
        }
    }

    // MARK: - 最近

    private var recent: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHead(index: "01", title: "最近", trailing: "全部") {
                router.goToLogRoot()
            }
            ForEach(recentEvents) { event in
                Button {
                    router.openEvent(event.id)
                } label: {
                    EventRow(event: event)
                }
                .buttonStyle(.plain)
                if event.id != recentEvents.last?.id {
                    Rectangle().fill(T.C.hair).frame(height: 0.5).padding(.leading, 21)
                }
            }
            if recentEvents.isEmpty {
                EmptyNote(line: "还没有记录。",
                          detail: "读一次锁内日志，这里就会出现谁在什么时候开过门。",
                          action: DB.isDecoy ? nil : "读取日志",
                          run: DB.isDecoy ? nil : {
                              Task {
                                  if let result = await app.readLogs() {
                                      flash(result.read == 0 ? "锁里没有新的开门记录。" : "读到 \(result.read) 条记录。")
                                  } else if let message = app.lastError {
                                      // `readLogs` 在另一条命令进行中会返回 nil 并写下
                                      // 「门锁正忙」；其它失败同样落在这里，不再静默。
                                      flash(message)
                                  }
                              }
                          })
            } else if let progress = app.logProgress {
                // F42/F45：读日志的进度 —— 「第 N/20 页、已读 M 条」。
                ProgressMeter(progress: progress) { app.cancelLogRead() }
            }
        }
    }

    private var recentEvents: [EventItem] {
        Array(app.events.prefix(3))
    }

    private func note(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 14))
                .foregroundStyle(T.C.danger)
                .accessibilityHidden(true)   // 语义由旁边文字承担，图标只做视觉提示
            Text(text)
                .type(T.F.caption)
                .foregroundStyle(T.C.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 18)
    }

    private func successNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 14))
                .foregroundStyle(T.C.ok)
                .accessibilityHidden(true)   // 同上
            Text(text)
                .type(T.F.caption)
                .foregroundStyle(T.C.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 18)
    }

    /// 成功提示自己会退场，不占着页脚。
    private func flash(_ text: String) {
        notice = text
        Task {
            try? await Task.sleep(for: .seconds(3))
            if notice == text { notice = nil }
        }
    }

    /// 跳系统设置（蓝牙页）。权限提示卡上的「去系统设置」用它。
    private func openBluetoothSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - 未配锁

@MainActor
struct EmptyHome: View {
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Kicker(text: "还没有门锁", dot: true, tint: T.C.ink2)
                Spacer()
                AvatarBadge(initial: "你", size: 38)
                    .accessibilityHidden(true)
            }
            .padding(.top, 8)

            DaylightPane(height: 396) {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 20)
                    DisplayLine(text: "先连上\n你的门锁。", size: 42)
                    Text("把门锁恢复到配网状态，手机靠近它，按开始配对。整个过程不需要网络。")
                        .type(T.F.footnote)
                        .foregroundStyle(T.C.ink2)
                        .lineSpacing(4)
                        .padding(.top, 14)
                        .frame(maxWidth: 290, alignment: .leading)
                    Spacer()
                    Button {
                        router.openSettings()
                        router.pushSettings(.pairing)
                    } label: {
                        Text("开始配对")
                            .type(T.F.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(T.C.onAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                LinearGradient(colors: [T.C.brassBright, T.C.brass],
                                               startPoint: .topLeading, endPoint: .bottom),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                    }
                    .buttonStyle(PressStyle())
                }
                .padding(26)
            }
            .padding(.top, 18)

            SectionHead(index: "01", title: "配对之后")
            // 这三行原先只是带着 chevron 的静态 ContentRow —— 箭头在，点下去却什么也不会发生。
            // 现在各去各的地方（安全落在设置栈里）。
            Button { router.goToAccessRoot() } label: {
                ContentRow(symbol: "key", title: "凭证", subtitle: "密码、指纹、临时码，一处管完", chevron: true)
            }
            .buttonStyle(.plain)
            Button { router.goToLogRoot() } label: {
                ContentRow(symbol: "list.bullet", tone: .cool, title: "记录", subtitle: "谁在什么时候开过门", chevron: true)
            }
            .buttonStyle(.plain)
            Button {
                router.openSettings()
                router.pushSettings(.security)
            } label: {
                ContentRow(symbol: "shield", tone: .cool, title: "安全", subtitle: "本机密码、胁迫码、通知", chevron: true)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - 头像

@MainActor
struct AvatarBadge: View {
    var initial: String
    var size: CGFloat = 38

    var body: some View {
        Text(initial)
            .font(.system(size: size * 0.37, weight: .semibold))
            .foregroundStyle(T.C.brass)
            .frame(width: size, height: size)
            // 头像只做身份标记，不是可点入口；玻璃由中央 modifier 画在背景层，
            // 且不参与命中测试（见 LiquidGlass.swift）。
            .liquidGlass(in: Circle(), tint: GlassMetrics.tint)
            // 视觉仍是 38pt，布局上留出 44pt 的呼吸位。
            .frame(width: max(44, size), height: max(44, size))
            .shadow(color: T.C.shadow, radius: 8, x: 0, y: 4)
    }
}
