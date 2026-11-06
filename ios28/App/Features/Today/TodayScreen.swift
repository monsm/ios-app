// TodayScreen.swift —— 今日。整个 App 的主角。
//
// 构图的三个层次：
//   1. 日光窗（室外）：一块有厚度的玻璃，一行衬线字说清现在的状态。
//   2. 门槛（镜头）：解锁镜头骑在窗沿上，环走的是真实命令链。
//   3. 室内（内容）：读数、工具托盘、最近发生的事。
import SwiftUI

@MainActor
struct TodayScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    var body: some View {
        ScreenScroll {
            if app.lock == nil {
                EmptyHome()
            } else {
                header
                hero
                readings
                tray
                recent
                if let error = app.lastError {
                    note(error)
                }
            }
        }
        .background(Color.clear)
        .toolbar(.hidden, for: .navigationBar)
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
            Button {
                router.openSettings()
            } label: {
                AvatarBadge(initial: initial, size: 38)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("设置")
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
                        Text(When.clock(Int64(Date().timeIntervalSince1970)))
                            .type(T.F.mono)
                            .foregroundStyle(T.C.ink2)
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
        if let last = app.events.first(where: { $0.isOpen }) {
            var parts = ["上次开门 \(When.clock(last.time))"]
            if let who = last.whoName { parts.append(who) }
            if !last.credential.isEmpty { parts.append(last.credential) }
            return parts.joined(separator: " · ")
        }
        return "还没有开过门。轻点镜头，试试看。"
    }

    // MARK: - 读数

    private var readings: some View {
        ReadingRow(items: [
            (label: "电量", value: batteryText, unit: batteryUnit),
            (label: "信号", value: LinkSenseModel.levelWord(app.link.rssiLevel), unit: app.link.lastRSSI.map { "\($0) dBm" }),
            (label: "固件", value: firmwareText, unit: nil),
        ])
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
        case "addPwd", "addFp":
            router.tab = .access
            router.push(.credentialCreate)
        case "otp":
            router.tab = .access
            router.push(.zotp)
        case "studio":
            router.tab = .access
        case "again":
            Task { await app.unlock() }
        case "syncTime":
            Task { _ = await app.syncTime() }
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
            SectionHead(index: "01", title: "最近", trailing: "全部")
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
                          action: "读取日志") {
                    Task { _ = await app.readLogs() }
                }
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
            Text(text)
                .type(T.F.caption)
                .foregroundStyle(T.C.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 18)
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
                Button { router.openSettings() } label: { AvatarBadge(initial: "你", size: 38) }
                    .buttonStyle(PressStyle())
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
                            .foregroundStyle(.white)
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
            ContentRow(symbol: "key", title: "凭证", subtitle: "密码、指纹、临时码，一处管完", chevron: true)
            ContentRow(symbol: "list.bullet", tone: .cool, title: "记录", subtitle: "谁在什么时候开过门", chevron: true)
            ContentRow(symbol: "shield", tone: .cool, title: "安全", subtitle: "本机密码、布防、自动开门", chevron: true)
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
            .background {
                Circle().fill(T.C.glass)
                Circle().fill(.ultraThinMaterial)
            }
            .overlay {
                Circle().strokeBorder(T.C.glassEdge, lineWidth: 0.5)
            }
            .shadow(color: T.C.shadow, radius: 8, x: 0, y: 4)
    }
}
