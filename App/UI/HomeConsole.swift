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
// 【构图】纵向节奏 28pt，主路径五段 + 一个空状态：
//   ① 页眉（时间 + 连接态）—— 20pt 高，不抢焦点
//   ② 空状态 —— 未配对门锁时唯一的出口（去配对）
//   ③ 门的身份 + 一句摘要 —— 建立"这是哪把锁"
//   ④ 开锁环 220pt —— 视觉中心，落在拇指舒适区
//   ⑤ 三个指标 / ⑥ 今日柱图 / ⑦ 成员 —— 一眼看懂今天
//   ⑧ 五个管理入口 —— soft 边界，不诱导
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
    @Environment(\.dynamicTypeSize) private var typeSize
    /// 全局刷新中心。开门成功、从后台回前台、安全设置变动都会 bump 它。
    /// 没有这个观察，本页的"今日开门 / 分时柱图 / 成员"在开门之后**不会更新** ——
    /// 因为数据是在 body 里现算的，而 SwiftUI 只在状态变化时重算 body。
    @ObservedObject private var ticker = SecTickCenter.shared

    @State private var phase: UnlockPhase = .idle
    @State private var progress: CGFloat = 0
    @State private var pressing = false
    @State private var failure: String?
    @State private var settlingTask: Task<Void, Never>?
    @State private var managerGroup: ManagerGroup?
    @State private var appeared = false

    // ── 当日统计缓存 ──
    //
    // 原来 hourCounts 是个计算属性，而 opensToday / dayChart / firstOpenText / digest
    // 各自都会调它 —— 一次渲染要**完整扫四遍日志**。加上刷新机制之后
    // （ticker bump、下拉刷新、回前台）这个代价会被放大。
    // 改成：一次扫描写入缓存，渲染时只读。
    @State private var hourCounts: [Int] = Array(repeating: 0, count: 24)
    @State private var memberStats: [MemberStat] = []

    @Environment(\.scenePhase) private var scenePhase

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
                        if mac.isEmpty {
                            // ── 空状态 ──
                            // 没有门锁时，把一屏的 0 和按不动的环摆出来是最没用的界面。
                            // 这里只留一件事：告诉你下一步做什么。
                            noLockState
                        } else {
                            identity
                            if let notice = criticalNotice { noticeRow(notice) }
                            unlockStage
                            metricsRow
                            todaySection
                            memberSection
                        }
                        manageSection
                    }
                    .padding(.horizontal, XSpace.gutter)
                    .padding(.top, XSpace.xs)
                    .padding(.bottom, XSpace.xxl)
                    .opacity(appeared ? 1 : 0)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    // 下拉是**用户显式要求刷新**，所以这里允许主动连门锁拉实时状态。
                    SecTick.bump()
                    await app.refreshStatusQuietly(manual: true)
                }
            }
            .navigationBarHidden(true)
            .onChange(of: scenePhase) { _, phase in
                // 回前台只重算**本地**数据（别处开过门、成员变动都可能让统计过期），
                // 成本只是一次 DB 扫描。
                //
                // 这里刻意**不**调 refreshStatusQuietly：那个方法会真的建立 BLE
                // 连接去读实时状态。每次切回 App 都唤醒一次门锁，既费电也不符合
                // 用户预期（他可能只是回个微信）。要拉实时状态有下拉刷新这条
                // 显式路径。
                if phase == .active {
                    SecTick.bump()
                } else {
                    // 切走就放弃蓄力。否则那个 1.05s 的 Task 会在后台睡完，
                    // 然后真的发出一次 BLE 开锁 —— 用户只是去回了个微信。
                    abortCharge()
                }
            }
            .onChange(of: ticker.tick) { _, _ in recompute() }
            .onAppear {
                recompute()
                guard !appeared else { return }
                if reduceMotion { appeared = true }
                else { withAnimation(.easeOut(duration: 0.28)) { appeared = true } }
            }
            .onDisappear {
                // 视图消失同样要中止，不能只 cancel Task：
                // 不把 pressing/phase 复位，下次回到这一页会停留在一个假的"蓄力中"。
                abortCharge()
                settlingTask?.cancel()
            }
            // ═══ 深链兼容 ═══
            //
            // 删掉 DoorRoot 之后，requestRoute(.settings) 这类编程式跳转
            // 只会把 tabSelection 改掉，却没人接 —— 等于所有深链、快捷指令、
            // 通知点进来的落点全失效。这里把原来的 4 个 Tab 号映射成 5 个管理组，
            // 让旧漏斗继续有落点（纵深页面本身没删，仍在 ManagerFace 里）。
            .onChange(of: app.tabSelection) { _, t in
                guard let r = Route.from(tab: t) else { return }
                managerGroup = ManagerGroup.forRoute(r)
            }
            .sheet(item: $managerGroup) { g in
                ManagerFace(initialGroup: g).environmentObject(app)
            }
        }
    }

    // ─────────────────────────────────────────── ① 页眉
    private var masthead: some View {
        HStack {
            // 用 TimelineView 每分钟重算一次 —— 直接写 Text(clockText) 只在
            // 别的状态变化触发重绘时才更新，时钟会停在打开那一刻。
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                Text(clockText(ctx.date))
                    .xFont(.system(.subheadline, design: .rounded, weight: .medium).monospacedDigit())
                    .foregroundStyle(XPalette.textSub)
                    .accessibilityLabel("现在 \(clockText(ctx.date))")
            }
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Circle().fill(phase.tone).frame(width: 6, height: 6)
                Text(phase.label)
                    .xFont(.system(.caption, weight: .medium))
                    .foregroundStyle(phase.tone)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("连接状态：\(phase.label)")
        }
        .frame(height: 20)
    }

    // ─────────────────────────────────────────── ② 空状态
    private var noLockState: some View {
        VStack(spacing: XSpace.l) {
            Image(systemName: "lock.slash")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(XPalette.textTertiary)
                .accessibilityHidden(true)
            VStack(spacing: XSpace.xs) {
                Text("还没有门锁")
                    .xFont(.system(.title3, weight: .semibold))
                    .foregroundStyle(XPalette.text)
                Text("配对之后，这里会变成你每天的开门台")
                    .xFont(.system(.footnote))
                    .foregroundStyle(XPalette.textTertiary)
                    .multilineTextAlignment(.center)
            }
            Button {
                XHaptics.tick.impactOccurred()
                managerGroup = .devices
            } label: {
                Text("去配对门锁")
                    .xFont(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(XPalette.onAccent)
                    .padding(.horizontal, XSpace.xl)
                    .padding(.vertical, XSpace.m)
                    .xPlate(XPalette.accent, .capsule)
            }
            .buttonStyle(PressableScaleStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, XSpace.xxl)
    }

    // ─────────────────────────────────────────── ③ 门的身份
    private var identity: some View {
        VStack(alignment: .leading, spacing: XSpace.xs) {
            Text(lockName)
                .xFont(.system(.title, weight: .bold))
                .foregroundStyle(XPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(digest)
                .xFont(.system(.footnote))
                .foregroundStyle(XPalette.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ─────────────────────────────────────────── ③.5 关键状态
    //
    // 低电量和未处理告警是"现在就得知道"的事，原来只混在环下方那行 13pt 的
    // 小字里（"电量 12% · 上次 08:12 · 已上锁"）—— 那是**埋没**，不是提示。
    //
    // 这里把它们提到开锁环正上方、独立一条。位置固定、颜色固定，
    // 一眼扫得到；没有问题时整条不占位，不制造噪音。
    //
    // 刻意不挂到全局 topBanners：那套是"全 App 级闲时提醒"（自检/粘贴建议），
    // 而低电量是这把锁自己的事，应该出现在它自己的控制台上。
    private enum CriticalNotice {
        case lowBattery(Int)
        case alarms(Int)
    }

    private var criticalNotice: CriticalNotice? {
        if let n = alarmCount, n > 0 { return .alarms(n) }
        if let p = app.status?.powerLevel, p >= 0, p <= 20 { return .lowBattery(p) }
        return nil
    }

    private var alarmCount: Int? {
        let macs = DB.keychains().map { $0.mac }
        guard !macs.isEmpty else { return nil }
        let n = RecordSearch.unhandledAlarmCount(macs: macs)
        return n > 0 ? n : nil
    }

    private func noticeRow(_ n: CriticalNotice) -> some View {
        let isAlarm: Bool
        let glyph: String
        let text: String
        let tone: Color
        switch n {
        case .alarms(let c):
            isAlarm = true
            glyph = "exclamationmark.shield.fill"
            text = "有 \(c) 条告警还没处理"
            tone = XPalette.danger
        case .lowBattery(let p):
            isAlarm = false
            glyph = "battery.25"
            text = "门锁电量 \(p)%，该换电池了"
            tone = XPalette.warn
        }
        return Button {
            XHaptics.tick.impactOccurred()
            managerGroup = isAlarm ? .security : .devices
        } label: {
            HStack(spacing: XSpace.s) {
                Image(systemName: glyph)
                    .font(.system(size: XIcon.sm, weight: .semibold))
                    .accessibilityHidden(true)
                Text(text)
                    .xFont(.system(.footnote, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: XSpace.xs)
                Image(systemName: "chevron.right")
                    .font(.system(size: XIcon.xs, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(tone)
            .padding(.horizontal, XSpace.m)
            .padding(.vertical, XSpace.m)
            .frame(maxWidth: .infinity, minHeight: XHit.min, alignment: .leading)
            // ⚠ 三参数重载要的是 XPlateShape，不是 CGFloat 圆角 —— 传错会直接编译失败
            .xPlate(tone.opacity(0.12), .control, edge: tone.opacity(0.35))
        }
        .buttonStyle(PressableScaleStyle())
        .accessibilityLabel(text)
        .accessibilityHint(isAlarm ? "打开安全中心" : "打开设备管理")
    }

    // ─────────────────────────────────────────── ④ 开锁环
    private var unlockStage: some View {
        VStack(spacing: XSpace.l) {
            ZStack {
                // ── 静息轨道 ──
                // 必须未按下时也可见，否则用户不知道这里能按。
                // 上缘压一条极淡的暗线 ⇒ 读成"凹进去的槽"，而不是一个圆环贴纸。
                Circle()
                    .strokeBorder(XPalette.surfaceAlt, lineWidth: 7)
                    .overlay {
                        Circle()
                            .strokeBorder(XPalette.canvas.opacity(0.55), lineWidth: 1)
                            .blur(radius: 1.5)
                            .offset(y: 1)
                            .mask(Circle().strokeBorder(XPalette.surfaceAlt, lineWidth: 7))
                    }

                // ── 蓄力弧 ──
                // 用角度渐变而不是纯色：起点是深铜、头部是亮铜 ——
                // 视觉上读成"能量从起点推到了头部"，纯色弧读不出方向。
                Circle()
                    .trim(from: 0, to: max(0.0001, progress))
                    .stroke(
                        AngularGradient(
                            colors: [phase.arcTone.opacity(0.35),
                                     phase.arcTone.opacity(0.75),
                                     phase.arcTone],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: phase.arcTone.opacity(reduceMotion ? 0 : (progress > 0.01 ? 0.45 : 0)),
                            radius: 16)

                // ── 蓄力时的柔光 ──
                // 只在真正蓄力时出现，静息与结果态都没有 —— 让"正在发生"有独立语汇。
                if phase == .charging && !reduceMotion {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [XPalette.accent.opacity(0.16), .clear],
                                center: .center,
                                startRadius: 60,
                                endRadius: 120))
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                // 中心：图标 + 手势提示
                VStack(spacing: XSpace.xs) {
                    Image(systemName: centerGlyph)
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(phase == .idle ? XPalette.textSub : phase.arcTone)
                        .contentTransition(.symbolEffect(.replace))
                    Text(centerCaption)
                        .xFont(.system(.footnote, weight: .medium))
                        .foregroundStyle(XPalette.textTertiary)
                        .contentTransition(.opacity)
                }
            }
            .frame(width: 220, height: 220)
            // 按压缩放：0.97、140ms、纯缓出。
            // 这里刻意**不用 spring** —— 门锁是金属，金属不弹。
            // 动效规范里金属材质是「时长 ×1.2、0% 回弹」；带阻尼的 spring
            // 会给一个刚体加上橡皮的手感，和产品是矛盾的。
            .scaleEffect(ringScale)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: pressing)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.34), value: phase)
            .contentShape(Circle())
            // ═══ 按住开锁：用平台的手势，不手搓定时器 ═══
            //
            // 之前是 DragGesture(minimumDistance: 0) + 一个 sleep(1.05s) 的 Task。
            // 那个写法有一个我 cover 不住的安全洞：手势被系统取消时（来电、弹窗、
            // 视图被移除）onEnded 不一定触发，pressing 会停在 true，
            // 定时器睡完就真的发出一次开锁 —— 用户没按完，门开了。
            //
            // onLongPressGesture 的完成回调由 SwiftUI 保证：只有**按住满 minimumDuration
            // 且期间没有被取消**才会调 perform。这就是"按住开锁"该用的原语。
            //
            // onPressingChanged 只负责视觉（缩放、进度、触觉），不再承担正确性。
            .onLongPressGesture(minimumDuration: chargeDuration, maximumDistance: 44) {
                Task { await performUnlock() }
            } onPressingChanged: { down in
                if down { beginPress() } else { endPress() }
            }
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
            .xFont(.system(.footnote))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(height: 18)
            .animation(reduceMotion ? nil : XMotion.soft, value: failure)
        }
    }

    /// 环的缩放：按下 0.97，成功时 1.03 的短脉冲（300–400ms 档），其余为 1
    private var ringScale: CGFloat {
        if pressing { return 0.97 }
        switch phase {
        case .unlocked: return 1.03
        case .failed: return 0.99
        default: return 1
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

    // ─────────────────────────────────────────── ⑤ 三指标
    // 无障碍字号下，三列横排会挤到每列不足 60pt —— 改为纵向堆叠。
    // 这不是"降级"，是让内容本身换一种排法，字号不缩。
    private var metricsRow: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: XSpace.l))
            : AnyLayout(HStackLayout(spacing: 0))
        return layout {
            metric(value: String(opensToday), label: "今日开门")
            if !typeSize.isAccessibilitySize { metricDivider }
            // 口径是近 30 天，不是"现在在家"—— 标签必须诚实
            metric(value: String(memberRows.count), label: "常用成员")
            if !typeSize.isAccessibilitySize { metricDivider }
            metric(value: firstOpenText, label: "最早开门")
        }
    }

    private func metric(value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .xFont(.system(.title, design: .rounded, weight: .semibold).monospacedDigit())
                .foregroundStyle(XPalette.text)
                .lineLimit(1)
            Text(label)
                .xFont(.system(.caption2, weight: .medium))
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

    // ─────────────────────────────────────────── ⑥ 今天
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
            .xFont(.system(.caption2).monospacedDigit())
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

    // ─────────────────────────────────────────── ⑦ 成员
    @ViewBuilder
    private var memberSection: some View {
        let rows = memberRows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: XSpace.m) {
                sectionLabel("成员")
                ScrollView(.horizontal) {
                    HStack(spacing: XSpace.s) { ForEach(rows) { memberChip($0) } }
                        .padding(.vertical, 1)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func memberChip(_ r: MemberStat) -> some View {
        HStack(spacing: XSpace.s) {
            Text(String(r.name.prefix(1)))
                .xFont(.system(.subheadline, weight: .semibold))
                .foregroundStyle(XPalette.text)
                .frame(width: 28, height: 28)
                .background(XPalette.surfaceAlt, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(r.name)
                    .xFont(.system(.footnote, weight: .medium))
                    .foregroundStyle(XPalette.text)
                    .lineLimit(1)
                Text("近 30 天 \(r.opens30) 次")
                    .xFont(.system(.caption2).monospacedDigit())
                    .foregroundStyle(XPalette.textTertiary)
            }
        }
        .padding(.leading, 5)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .xPlate(XPalette.surface, .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(r.name)，近 30 天 \(r.opens30) 次")
    }

    // ─────────────────────────────────────────── ⑧ 管理入口
    private var manageSection: some View {
        VStack(alignment: .leading, spacing: XSpace.m) {
            sectionLabel("管理")
            // 5 个瓦片在无障碍字号下横排放不下 —— 改 2 列网格，字号不缩
            let cols = typeSize.isAccessibilitySize
                ? [GridItem(.flexible(), spacing: XSpace.s), GridItem(.flexible(), spacing: XSpace.s)]
                : Array(repeating: GridItem(.flexible(), spacing: XSpace.s), count: 5)
            LazyVGrid(columns: cols, spacing: XSpace.s) {
                ForEach(ManagerGroup.allCases) { g in
                    Button { openGroup(g) } label: {
                        VStack(spacing: 7) {
                            Image(systemName: g.systemImage)
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(XPalette.accentText)
                            Text(g.rawValue)
                                .xFont(.system(.caption2, weight: .medium))
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
            .xFont(.system(.caption2, weight: .semibold))
            .foregroundStyle(XPalette.textTertiary)
            .textCase(.uppercase)
            .tracking(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ─────────────────────────────────────────── 交互
    private func beginPress() {
        // 还没选门锁时，按下去只会得到一个技术性报错。
        // 更好的做法：环本身提示"先选门锁"，并且不进入蓄力。
        guard !mac.isEmpty else {
            failure = "先在「设备」里选择门锁"
            return
        }
        guard phase == .idle || phase == .failed else { return }
        if pressing { return }
        pressing = true
        failure = nil
        phase = .charging
        XHaptics.tick.impactOccurred()

        // ═══ 蓄力动画 ═══
        //
        // 上一版用一个 16ms 的循环自己推进 progress —— 等于每秒 62 次
        // 触发 SwiftUI 重算视图（Circle.trim + 阴影 + 文字），主线程压力大且掉帧。
        //
        // 现在：一次 withAnimation 交给 Core Animation 线性插值，进度条是
        // 渲染进程自己跑的，主线程只负责在终点判定完成。这是"动画"和
        // "定时器"该分开的地方 —— 混在一起就是业余做法的典型症状。
        // 视觉进度：交给 Core Animation 线性插值。
        // 完成时机由 onLongPressGesture 的 minimumDuration 决定，两者用同一个
        // chargeDuration 常量，所以进度环填满的瞬间正好就是完成判定点。
        withAnimation(.linear(duration: chargeDuration)) { progress = 1 }
    }

    /// 中止蓄力 —— 供"切到后台 / 视图消失 / 手势被打断"共用。
    /// 与 endPress 的区别：endPress 是用户松手（正常路径），
    /// abortCharge 是外部原因导致的放弃（安全路径），两者都不能留下未清理的 Task。
    private func abortCharge() {
        // onLongPressGesture 自己会在被打断时回调 onPressingChanged(false)，
        // 但如果视图直接消失，那个回调也可能不来 —— 所以这里仍要能兜住。
        guard pressing || phase == .charging else { return }
        pressing = false
        if phase == .charging {
            phase = .idle
            withAnimation(reduceMotion ? nil : XMotion.chargeReset) { progress = 0 }
        }
    }

    private func endPress() {
        guard pressing else { return }
        pressing = false
        // ⚠ 这里不能用 progress < 1 判断"没充满"。
        // withAnimation(.linear) 会**立刻**把 progress 状态置为 1，动画只负责
        // 中间的插值渲染。所以中途松手时 progress 其实已经是 1，
        // 用 progress 判断会让"松手回零"这条路径永远走不到。
        // 正确判据是 phase：只有还停在 .charging 才算没完成。
        if phase == .charging {
            phase = .idle
            withAnimation(reduceMotion ? nil : XMotion.chargeReset) { progress = 0 }
        }
    }

    private func performUnlock() async {
        withAnimation(XMotion.soft) { progress = 1 }
        do {
            guard !mac.isEmpty else { throw DFUError.msg("请先在「设备」里选择门锁") }
            try await app.lock.ensureConnected(mac: mac)
            _ = try await app.lock.unlock(mac: mac)
            phase = .unlocked
            // 这次开门刚刚发生，主界面上的"今日开门 / 分时柱图"必须立刻变。
            // 不 bump 的话要等下一次别的原因触发重绘才更新，用户会以为没开成。
            SecTick.bump()
            // 刚开过锁，连接是热的 —— 顺手把电量/锁态拉新，成本很低。
            // 注意：回前台时**不要**这样做（见 scenePhase 处的说明），
            // 每次回 App 都唤一次门锁既耗电也不符合用户预期。
            await app.refreshStatusQuietly()
            XHaptics.success()
            scheduleSettle(after: 0.9)
        } catch {
            failure = humanMessage(error)
            phase = .failed
            XHaptics.trigger.impactOccurred()
            scheduleSettle(after: 2.0)
        }
    }

    /// 把底层错误翻成"下一步该做什么"。
    ///
    /// 直接抛 localizedDescription 等于把协议层的技术名词丢到用户脸上
    ///（"无钥匙串 skey"、"handshake timeout"），既不解释也不指路。
    /// 这里按可恢复性分三类：能自己解决的 / 需要去别处处理的 / 只能重试的。
    private func humanMessage(_ e: Error) -> String {
        let raw = e.localizedDescription
        let low = raw.lowercased()
        if low.contains("timeout") || raw.contains("超时") {
            return "门锁没响应 · 靠近一点再试"
        }
        if low.contains("disconnect") || raw.contains("未连接") || raw.contains("断开") {
            return "与门锁断开 · 请回到门边"
        }
        if raw.contains("钥匙串") || low.contains("skey") || raw.contains("未配对") {
            return "本机没有这把锁的钥匙 · 去「设备」重新配对"
        }
        if raw.contains("密码") || low.contains("pin") {
            return "密码不对"
        }
        if raw.contains("电量") || low.contains("battery") {
            return "门锁电量不足"
        }
        return raw.isEmpty ? "开锁失败 · 请重试" : raw
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
    private func clockText(_ date: Date) -> String {
        let c = WeekCal.gregorian.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    private var lockName: String {
        guard let kc = app.current else { return "未选择门锁" }
        return LockArchive.displayName(kc)
    }

    /// 一句摘要 —— 页面上第二重要的信息。
    ///
    /// ⚠ 这里不能写"今天 N 人开过"：协议日志里**没有凭证身份字段**
    ///（CAPABILITY §3），"今天几个人开的"这件事在本机根本算不出来。
    /// 成员数是近 30 天的统计，把它塞进"今天"就是在编数据。
    /// 所以两件事分开说，各自标明时间口径。
    private var digest: String {
        let n = opensToday
        let people = memberRows.count
        if n == 0 && people == 0 { return "今天还没有开门记录" }
        if n == 0 { return "今天还没开过门 · 近 30 天 \(people) 人用过" }
        if people == 0 { return "今天开过 \(n) 次" }
        return "今天开过 \(n) 次 · 近 30 天 \(people) 人用过"
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

    /// 一次扫描重建全部当日统计。只由 onAppear / ticker / 下拉刷新触发。
    private func recompute() {
        guard !mac.isEmpty else {
            hourCounts = Array(repeating: 0, count: 24)
            memberStats = []
            return
        }
        let today = StatsKit.dayKey(Date())
        let cal = WeekCal.gregorian
        var counts = Array(repeating: 0, count: 24)
        for l in DB.readLogs(mac) where StatsKit.openTypes.contains(l.type) {
            guard l.lockTimeStr.hasPrefix(today) else { continue }
            let d = Date(timeIntervalSince1970: ZKProtocol.protoSecondsToUnix(l.lockTime))
            let h = cal.component(.hour, from: d)
            if h >= 0 && h < 24 { counts[h] += 1 }
        }
        hourCounts = counts
        memberStats = DB.members().compactMap { m in
            let a = MemberHub.activity(m.id)
            guard a.opens30 > 0 else { return nil }
            return MemberStat(id: m.id, name: MemberHub.display(m), opens30: a.opens30)
        }
        .sorted { $0.opens30 > $1.opens30 }
        .prefix(6)
        .map { $0 }
    }

    /// 成员活跃 —— 协议日志没有凭证身份字段（CAPABILITY §3），
    /// 所以归属只能到"约"级。这里用 MemberHub 的 30 天统计，
    /// 并在无障碍标签里如实说"近 30 天"，不假装是今日。
    private var memberRows: [MemberStat] { memberStats }

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
            // 金属不弹：纯缓出 120ms（按钮反馈 120–180ms 档的下限，要"立刻"）
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - 旧 Tab → 新管理组
// ═══════════════════════════════════════════════════════════════════════
extension ManagerGroup {
    /// 单一界面之后，原来的 4 个顶层 Tab 不再存在，但它们的入口
    ///（深链 kf://settings、摇一摇遁走、粘贴条回凭证页…）仍在调用
    /// requestRoute。为了让这些入口还有落点，把 Tab 映射到最接近的管理组。
    static func forRoute(_ r: Route) -> ManagerGroup {
        switch r {
        case .device: return .devices
        case .credentials: return .ledger
        case .records: return .ledger
        case .settings: return .backupLook
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - 成员统计行
// ═══════════════════════════════════════════════════════════════════════
// 用具名类型而不是三元组：三元组在 ForEach 里要靠 \.id 手工标 identity，
// 字段名 (id, name, n) 也没有语义 —— n 是什么？opens30 才是它真正的含义。
struct MemberStat: Identifiable, Equatable {
    let id: String
    let name: String
    /// 近 30 天开门次数。协议日志没有凭证身份字段，所以只能到"约"级，
    /// 界面上必须写明"近 30 天"，不能写成"今天"。
    let opens30: Int
}
