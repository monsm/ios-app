import SwiftUI

// ═══════════════════════════════════════════════════════════════════════
// MARK: - 门厅（全 App 唯一主界面）
// ═══════════════════════════════════════════════════════════════════════
//
// 合并原 D 就近 / F 仪表 / B 管家台三个域。
//
// ═══════════════════ 设计契约 ═══════════════════
//
// 【用途】operate。用户举起手机的那一刻只有两种意图：
//   ① 站在门口，要进去 ② 想知道今天家里发生了什么。
//   所以：开锁动作占据唯一的「主视觉焦点」，数据是第二层，管理是第三层。
//
// 【构图】一屏五段，纵向节奏 28pt：
//   ① 页眉（时间 + 连接态）—— 20pt 高，不抢焦点
//   ② 门的身份 + 一句摘要 —— 建立"这是哪把锁"
//   ③ 开锁环 220pt —— 视觉中心，落在拇指舒适区
//   ④ 三个指标 / 今日柱图 / 成员 —— 一眼看懂今天
//   ⑤ 五个管理入口 —— soft 边界，不诱导
//
// 【排版】四级 + 数字层（全部走 .xFont，不裸写 .font）
//   锁名        26pt bold
//   指标数字    28pt rounded semibold（圆体数字在小尺寸下更稳）
//   区块标签    11pt semibold 大写 + 0.8 字距
//   正文 15pt / 辅助 13pt / 极小 11pt
//
// 【色彩】一色一义，中性为主，彩色只给"此刻"与"可操作"
//   accent 铜  = 主操作、当前小时、今日高亮
//   ok 绿      = 已连接、已上锁
//   warn 黄    = 电量低 / 可恢复异常
//   danger 红  = 失败 / 告警
//   灰阶       = 一切结构与说明，不做彩色装饰
//
// 【开锁环】按物理对象设计，不是按钮
//   · 静息：6pt 中性轨道 + 锁图标 + "按住开锁"（明确告知手势）
//   · 按下：瞬时缩放 0.97、图标 lock→lock.open 符号替换、触觉一次
//   · 蓄力：铜色进度弧从 12 点顺时针、带柔光；1.05s 充满（重复使用不能太慢）
//   · 成功：弧转绿 + 勾号 + 成功触觉，0.8s 后回到静息
//   · 失败：弧转红 + 下方一行原因 + 警告触觉，2s 后回静息
//   · 中途松手：0.18s 回零（不惩罚用户，但也不假装成功）
//   · reduceMotion：不缩放、不柔光，进度仍可见（功能不降级）
//
// 【无障碍】VoiceOver：环是一个按钮，标签"开锁"，hint"按住直到进度环充满"；
//   另有 .accessibilityAction 直接开锁，视障用户不必长按。
struct HomeConsole: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var phase: UnlockPhase = .idle
    @State private var progress: CGFloat = 0
    @State private var pressing = false
    @State private var failure: String?
    @State private var chargeTask: Task<Void, Never>?
    @State private var settlingTask: Task<Void, Never>?
    @State private var managerGroup: ManagerGroup?
    @State private var appeared = false

    private var mac: String { app.currentMac }

    // 蓄力时长：1.05s。太短易误触，太长（≥1.5s）重复开门会烦躁。
    private let chargeDuration: Double = 1.05

    var body: some View {
        NavigationStack {
            ZStack {
                XPalette.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: XSpace.xxl) {
                        masthead
                        identity
                        unlockStage
                        metricsRow
                        todaySection
                        memberSection
                        manageSection
                    }
                    .padding(.horizontal, XSpace.gutter)
                    .padding(.top, XSpace.xs)
                    .padding(.bottom, XSpace.xxl)
                    .opacity(appeared ? 1 : 0)
                }
                .scrollIndicators(.hidden)
            }
            .navigationBarHidden(true)
            .onAppear {
                guard !appeared else { return }
                if reduceMotion { appeared = true }
                else { withAnimation(.easeOut(duration: 0.28)) { appeared = true } }
            }
            .onDisappear { chargeTask?.cancel(); settlingTask?.cancel() }
            .sheet(item: $managerGroup) { g in
                ManagerFace(initialGroup: g).environmentObject(app)
            }
        }
    }

    // ─────────────────────────────────────────── ① 页眉
    private var masthead: some View {
        HStack {
            Text(clockText)
                .xFont(.system(size: 15, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(XPalette.textSub)
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Circle().fill(phase.tone).frame(width: 6, height: 6)
                Text(phase.label)
                    .xFont(.system(size: 12, weight: .medium))
                    .foregroundStyle(phase.tone)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("连接状态：\(phase.label)")
        }
        .frame(height: 20)
    }

    // ─────────────────────────────────────────── ② 门的身份
    private var identity: some View {
        VStack(alignment: .leading, spacing: XSpace.xs) {
            Text(lockName)
                .xFont(.system(size: 26, weight: .bold))
                .foregroundStyle(XPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(digest)
                .xFont(.system(size: 13))
                .foregroundStyle(XPalette.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ─────────────────────────────────────────── ③ 开锁环
    private var unlockStage: some View {
        VStack(spacing: XSpace.l) {
            ZStack {
                // 静息轨道 —— 必须在未按下时也可见，否则用户不知道这里能按
                Circle()
                    .strokeBorder(XPalette.surfaceAlt, lineWidth: 7)

                // 蓄力弧
                Circle()
                    .trim(from: 0, to: max(0.0001, progress))
                    .stroke(phase.arcTone,
                            style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: phase.arcTone.opacity(reduceMotion ? 0 : (progress > 0.01 ? 0.45 : 0)),
                            radius: 16)

                // 中心：图标 + 手势提示
                VStack(spacing: XSpace.xs) {
                    Image(systemName: centerGlyph)
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(phase == .idle ? XPalette.textSub : phase.arcTone)
                        .contentTransition(.symbolEffect(.replace))
                    Text(centerCaption)
                        .xFont(.system(size: 13, weight: .medium))
                        .foregroundStyle(XPalette.textTertiary)
                        .contentTransition(.opacity)
                }
            }
            .frame(width: 220, height: 220)
            .scaleEffect(pressing && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.7),
                       value: pressing)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in beginPress() }
                    .onEnded { _ in endPress() }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("开锁")
            .accessibilityHint("按住直到进度环充满")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { Task { await performUnlock() } }

            // 一行说明：电量 / 上次 / 失败原因 —— 同一位置不跳
            Group {
                if let f = failure {
                    Label(f, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(XPalette.warn)
                } else {
                    Text(footnote)
                        .foregroundStyle(XPalette.textTertiary)
                }
            }
            .xFont(.system(size: 13))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(height: 18)
            .animation(reduceMotion ? nil : XMotion.soft, value: failure)
        }
    }

    private var centerGlyph: String {
        switch phase {
        case .idle: return "lock.fill"
        case .charging: return "lock.open.fill"
        case .unlocked: return "checkmark"
        case .failed: return "xmark"
        }
    }

    private var centerCaption: String {
        switch phase {
        case .idle: return "按住开锁"
        case .charging: return "别松手"
        case .unlocked: return "已开锁"
        case .failed: return "重试"
        }
    }

    // ─────────────────────────────────────────── ④ 三指标
    private var metricsRow: some View {
        HStack(spacing: 0) {
            metric(value: String(opensToday), label: "今日开门")
            metricDivider
            metric(value: String(memberRows.count), label: "在家成员")
            metricDivider
            metric(value: firstOpenText, label: "最早开门")
        }
    }

    private func metric(value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .xFont(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(XPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Text(label)
                .xFont(.system(size: 11, weight: .medium))
                .foregroundStyle(XPalette.textTertiary)
                .textCase(.uppercase)
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label)，\(value)")
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(XPalette.hairline)
            .frame(width: 1, height: 34)
            .accessibilityHidden(true)
    }

    // ─────────────────────────────────────────── ⑤ 今天
    private var todaySection: some View {
        VStack(alignment: .leading, spacing: XSpace.m) {
            sectionLabel("今天")
            dayChart
        }
    }

    private var dayChart: some View {
        let counts = hourCounts
        let peak = max(counts.max() ?? 0, 1)
        let nowHour = WeekCal.gregorian.component(.hour, from: Date())
        return VStack(spacing: XSpace.xs) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<24, id: \.self) { h in
                    let c = counts[h]
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: max(3, 46 * CGFloat(c) / CGFloat(peak)))
                        .xPlate(barTone(hour: h, count: c, peak: peak, now: nowHour), .capsule)
                        .frame(height: 46, alignment: .bottom)
                }
            }
            .frame(height: 46, alignment: .bottom)
            HStack {
                Text("0").frame(maxWidth: .infinity, alignment: .leading)
                Text("6").frame(maxWidth: .infinity)
                Text("12").frame(maxWidth: .infinity)
                Text("18").frame(maxWidth: .infinity)
                Text("24").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .xFont(.system(size: 10).monospacedDigit())
            .foregroundStyle(XPalette.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日分时开门，共 \(opensToday) 次，最早 \(firstOpenText)")
    }

    private func barTone(hour: Int, count: Int, peak: Int, now: Int) -> Color {
        if hour == now { return XPalette.accent }
        if count == peak && count > 0 { return XPalette.accent.opacity(0.55) }
        if count > 0 { return XPalette.textSub.opacity(0.5) }
        return XPalette.surfaceAlt
    }

    // ─────────────────────────────────────────── ⑥ 成员
    @ViewBuilder
    private var memberSection: some View {
        let rows = memberRows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: XSpace.m) {
                sectionLabel("成员")
                ScrollView(.horizontal) {
                    HStack(spacing: XSpace.s) { ForEach(rows, id: \.id) { memberChip($0) } }
                        .padding(.vertical, 1)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func memberChip(_ r: (id: String, name: String, n: Int)) -> some View {
        HStack(spacing: XSpace.s) {
            Text(String(r.name.prefix(1)))
                .xFont(.system(size: 14, weight: .semibold))
                .foregroundStyle(XPalette.text)
                .frame(width: 28, height: 28)
                .background(XPalette.surfaceAlt, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(r.name)
                    .xFont(.system(size: 13, weight: .medium))
                    .foregroundStyle(XPalette.text)
                    .lineLimit(1)
                Text("\(r.n) 次")
                    .xFont(.system(size: 11).monospacedDigit())
                    .foregroundStyle(XPalette.textTertiary)
            }
        }
        .padding(.leading, 5)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .xPlate(XPalette.surface, .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(r.name)，近 30 天 \(r.n) 次")
    }

    // ─────────────────────────────────────────── ⑦ 管理入口
    private var manageSection: some View {
        VStack(alignment: .leading, spacing: XSpace.m) {
            sectionLabel("管理")
            HStack(spacing: XSpace.s) {
                ForEach(ManagerGroup.allCases) { g in
                    Button { openGroup(g) } label: {
                        VStack(spacing: 7) {
                            Image(systemName: g.systemImage)
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(XPalette.accentText)
                            Text(g.rawValue)
                                .xFont(.system(size: 10, weight: .medium))
                                .foregroundStyle(XPalette.textSub)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 62)
                        // 用设计系统的 xPlate 而不是手搓 RoundedRectangle ——
                        // 形状定义只允许在 Theme/Components 一处（uicoverage 检查五）
                        .xPlate(XPalette.surface, XRadius.tile)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableScaleStyle())
                    .accessibilityLabel(g.rawValue)
                }
            }
        }
    }

    private func sectionLabel(_ s: String) -> some View {
        Text(s)
            .xFont(.system(size: 11, weight: .semibold))
            .foregroundStyle(XPalette.textTertiary)
            .textCase(.uppercase)
            .tracking(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ─────────────────────────────────────────── 交互
    private func beginPress() {
        guard phase == .idle || phase == .failed else { return }
        if pressing { return }
        pressing = true
        failure = nil
        phase = .charging
        XHaptics.tick.impactOccurred()
        chargeTask?.cancel()
        chargeTask = Task { @MainActor in
            let tick = 0.016
            let inc = CGFloat(tick / chargeDuration)
            while !Task.isCancelled && progress < 1 {
                try? await Task.sleep(for: .milliseconds(16))
                if Task.isCancelled { return }
                progress = min(1, progress + inc)
            }
            if progress >= 1 { await performUnlock() }
        }
    }

    private func endPress() {
        guard pressing else { return }
        pressing = false
        chargeTask?.cancel()
        chargeTask = nil
        if progress < 1 && phase == .charging {
            phase = .idle
            // 用设计系统里语义正确的"充能松手回零"缓动，而不是就地写一个 easeOut
            withAnimation(reduceMotion ? nil : XMotion.chargeReset) { progress = 0 }
        }
    }

    private func performUnlock() async {
        chargeTask?.cancel()
        chargeTask = nil
        withAnimation(XMotion.soft) { progress = 1 }
        do {
            guard !mac.isEmpty else { throw DFUError.msg("请先在「设备」里选择门锁") }
            try await app.lock.ensureConnected(mac: mac)
            _ = try await app.lock.unlock(mac: mac)
            phase = .unlocked
            XHaptics.success()
            scheduleSettle(after: 0.9)
        } catch {
            failure = error.localizedDescription
            phase = .failed
            XHaptics.trigger.impactOccurred()
            scheduleSettle(after: 2.0)
        }
    }

    private func scheduleSettle(after seconds: Double) {
        settlingTask?.cancel()
        settlingTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : XMotion.soft) {
                phase = .idle
                progress = 0
            }
        }
    }

    private func openGroup(_ g: ManagerGroup) {
        XHaptics.tick.impactOccurred()
        managerGroup = g
    }

    // ─────────────────────────────────────────── 数据
    private var clockText: String {
        let c = WeekCal.gregorian.dateComponents([.hour, .minute], from: Date())
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    private var lockName: String {
        guard let kc = app.current else { return "未选择门锁" }
        return LockArchive.displayName(kc)
    }

    /// 一句摘要 —— 页面上第二重要的信息
    private var digest: String {
        let n = opensToday
        let people = memberRows.count
        if n == 0 { return "今天还没有开门记录" }
        if people == 0 { return "今天开过 \(n) 次" }
        return "今天 \(people) 人开过 \(n) 次"
    }

    private var footnote: String {
        var parts: [String] = []
        if let p = app.status?.powerLevel, p >= 0 { parts.append("电量 \(p)%") }
        if let t = lastOpenClock { parts.append("上次 \(t)") }
        if let rc = app.status?.rc { parts.append(rc == 0 ? "已上锁" : "未上锁") }
        return parts.isEmpty ? "靠近门锁即可连接" : parts.joined(separator: " · ")
    }

    private var lastOpenClock: String? {
        guard !mac.isEmpty else { return nil }
        let logs = DB.readLogs(mac).filter { StatsKit.openTypes.contains($0.type) }
        guard let last = logs.max(by: { $0.lockTime < $1.lockTime }) else { return nil }
        let s = last.lockTimeStr
        return s.count >= 16 ? String(s.suffix(5)) : nil
    }

    private var opensToday: Int { hourCounts.reduce(0, +) }

    private var hourCounts: [Int] {
        guard !mac.isEmpty else { return Array(repeating: 0, count: 24) }
        let today = StatsKit.dayKey(Date())
        var out = Array(repeating: 0, count: 24)
        let cal = WeekCal.gregorian
        for l in DB.readLogs(mac) where StatsKit.openTypes.contains(l.type) {
            guard l.lockTimeStr.hasPrefix(today) else { continue }
            let d = Date(timeIntervalSince1970: ZKProtocol.protoSecondsToUnix(l.lockTime))
            let h = cal.component(.hour, from: d)
            if h >= 0 && h < 24 { out[h] += 1 }
        }
        return out
    }

    /// 成员活跃 —— 协议日志没有凭证身份字段（CAPABILITY §3），
    /// 所以归属只能到"约"级。这里用 MemberHub 的 30 天统计，
    /// 并在无障碍标签里如实说"近 30 天"，不假装是今日。
    private var memberRows: [(id: String, name: String, n: Int)] {
        DB.members().compactMap { m in
            let a = MemberHub.activity(m.id)
            guard a.opens30 > 0 else { return nil }
            return (m.id, MemberHub.display(m), a.opens30)
        }
        .sorted { $0.2 > $1.2 }
        .prefix(6)
        .map { $0 }
    }

    private var firstOpenText: String {
        let c = hourCounts
        guard let h = c.firstIndex(where: { $0 > 0 }) else { return "—" }
        return String(format: "%02d:00", h)
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - 开锁阶段
// ═══════════════════════════════════════════════════════════════════════
enum UnlockPhase {
    case idle, charging, unlocked, failed

    var label: String {
        switch self {
        case .idle: return "已连接"
        case .charging: return "开锁中"
        case .unlocked: return "已开锁"
        case .failed: return "失败"
        }
    }

    var tone: Color {
        switch self {
        case .idle, .unlocked: return XPalette.ok
        case .charging: return XPalette.accent
        case .failed: return XPalette.danger
        }
    }

    var arcTone: Color {
        switch self {
        case .idle: return XPalette.accent
        case .charging: return XPalette.accent
        case .unlocked: return XPalette.ok
        case .failed: return XPalette.danger
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - 按压反馈样式
// ═══════════════════════════════════════════════════════════════════════
// 管理入口的按压反馈：0.96 缩放。
// 不用 .opacity 变化 —— 深色底上透明度变化几乎看不出，缩放在触觉之外
// 给出第二重"按到了"的证据。
struct PressableScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.72),
                       value: configuration.isPressed)
    }
}
