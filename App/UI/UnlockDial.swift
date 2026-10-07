// ================= 呼吸环 =================
// 独立成视图, 而不是 UnlockDial body 里的内联 Circle, 原因有二:
//   1. 属性争用 — 呼吸环用 repeatForever 驱动 scaleEffect/opacity, 而 UnlockDial
//      整棵子树挂着 .animation(DS.Motion.standard, value: state) 也驱动同一批属性,
//      状态一变两层动画会互相覆盖。这里用 .transaction 切断隐式继承。
//   2. 减少动效不等于取消动效 — 开启"减少动效"时改为保留一圈静态指示,
//      只是不再循环, 而不是整个消失(消失 = 用户不知道程序在跑)。
private struct UnlockPulseRing: View {
    var diameter: CGFloat = 176
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        Circle()
            .strokeBorder(DS.Palette.accent.opacity(0.45), lineWidth: 2)
            .frame(width: diameter, height: diameter)
            .scaleEffect(breathe ? 1.0 : 0.86)
            .opacity(breathe ? 0 : 0.9)
            .allowsHitTesting(false)
            .transaction { $0.animation = nil }
            .onAppear {
                guard !reduceMotion else { return }
                breathe = false
                withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) { breathe = true }
            }
    }
}

// ================= 待机流光 (idea 75) =================
// 已连接空闲时一圈靛蓝流光沿外沿慢速环绕, 断开即停 (调用方只在就绪空闲态挂载);
// reduceMotion 下不出现 — 待机氛围属于纯装饰动效。
private struct UnlockShimmer: View {
    var diameter: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.16)
            .stroke(AngularGradient(colors: [.clear, DS.Palette.accentText.opacity(0.85), .clear],
                                    center: .center),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .frame(width: diameter + 18, height: diameter + 18)
            .rotationEffect(.degrees(angle))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transaction { $0.animation = nil }
            .onAppear {
                guard !reduceMotion else { return }
                angle = 0
                withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) { angle = 360 }
            }
    }
}

// ================= 三段进度细条 (idea 80/89) =================
// 握手 / 鉴权 / 执行 三段填充; 握手超 4 秒由靛蓝转橙 (idea 89)。
private struct PhaseBar: View {
    var phase: Int      // 0 无 · 1 握手 · 2 鉴权 · 3 执行
    var slow: Bool
    var width: CGFloat

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            ForEach(1...3, id: \.self) { i in
                Capsule()
                    .fill(i <= phase ? tint : DS.Palette.hairline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 3)
            }
        }
        .frame(width: width)
        .animation(DS.Motion.quick, value: phase)
        .animation(DS.Motion.quick, value: slow)
        .accessibilityHidden(true)
    }
    private var tint: Color { slow ? DS.Palette.warn : DS.Palette.accentText }
}

// 开锁主控 — App 的唯一高频操作 (包1: 手势收敛后的最终形态)。
// 手势族取舍 (ROADMAP 包1 收录 1-3/51/61-62, 舍弃 52-55/57-58/77 见 docs/DEFERRED.md):
//   · 主交互 A — 按住确认 (idea 1): 按住 0.9s 环形进度填满才发指令 (idea 2 环形进度);
//     三成/六成两记轻触为进度刻度 (idea 22/3 双段触感), 松手提前取消有回弹。
//   · 主交互 B — 上滑触发 (idea 51): 圆盘内起手上滑越过阈值松手即发。
//   · 起手围栏 (idea 61): 手势只认圆盘内部六成面积起手, 边缘起手忽略。
//   · 误触围栏 (idea 62): 设置开启后, 需先"从边缘拖入中心"解锁围栏 (4s 内有效) 手势才响应。
//   · VoiceOver/开关控制: 手势层不拦截辅助功能激活, Button 直接触发 action() —
//     即"替代按钮绕过按住确认"; 也可在设置-开锁关闭按住确认退回轻点。
// 降级: reduceMotion 关闭流光/涟漪/抖动/回弹弹簧, 进度环保留线性填充 (信息型动效)。
// 设计要点:
//   · 触达目标 = 圆盘直径 (160/176/200 三档, idea 249), 远超 44pt 最小值
//   · 状态即颜色 + 图形 + 文字 + 角落状态点四通道表达 (idea 241/242)
//   · 连接/开锁过程有三段细条与心跳触感 (idea 80/79), 失败有抖动与人话原因 (idea 74/84)
import SwiftUI

struct UnlockDial: View {
    let state: AppState.UnlockState
    var phase: Int = 0                 // 80 三段进度: 1 握手 / 2 鉴权 / 3 执行
    var connected: Bool = false        // 与当前锁的 BLE 会话已就绪
    var bleReady: Bool = true          // 系统蓝牙已开启 (245)
    var failStreak: Int = 0            // 90 连续失败时中心切换搜索符号
    var retryText: String? = nil       // 85 退避节奏文案
    var batteryText: String = "未知"    // 846/167 转子电量维度 (调用方传入, 与 Hero 卡同源)
    var action: () -> Void             // 手势确认 / VO 直开 → AppState.requestUnlock
    var cancelAction: () -> Void = {}  // 89 握手超时提前取消

    @State private var pop = false
    @State private var shock = false
    @State private var breathe = false
    @State private var slowConnect = false     // 89 握手超 4 秒
    @State private var shakeX: CGFloat = 0     // 74 失败抖动
    // --- 手势态 ---
    @State private var pressing = false
    @State private var holdProgress: CGFloat = 0
    @State private var firedThisTouch = false
    @State private var swipePeakUp: CGFloat = 0
    @State private var touchMoved: CGFloat = 0
    @State private var armed = false           // 62 误触围栏已解锁
    @State private var holdTask: Task<Void, Never>? = nil
    @State private var voRotorIndex = 0        // 846/167 VO 转子: 0 状态 / 1 电量 / 2 连接

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // ---------- 偏好 (设置-开锁, 经 AppState.setUnlockOption 重建生效) ----------
    private var holdConfirmOn: Bool { DB.store.getBool("kf_hold_confirm", true) }
    private var fenceRequired: Bool { DB.store.getBool("kf_fence") }
    private var dial: CGFloat { DS.Metric.dial }
    // --- 包15 无障碍 ---
    // 875 按住时长跟随 (⚠ 系统"按住持续时间"无读取 API, 自定滑杆 0.4–1.6s, 默认 0.9 与包1 对齐)
    private var holdDuration: Double { AXPrefs.holdDuration }
    /// 61 起手围栏: 圆盘内部六成面积 (r = √0.6·R ≈ 0.39·直径)
    private func insideFence(_ p: CGPoint) -> Bool {
        let c = CGPoint(x: dial / 2, y: dial / 2)
        return hypot(p.x - c.x, p.y - c.y) <= dial * 0.39
    }
    /// 夜间降亮度 (idea 248): 22 点后装饰光效降峰值
    private var dim: CGFloat { DS.isNightDim ? 0.55 : 1 }

    private var isBusy: Bool {
        state == .connecting || state == .opening
    }
    private var tone: ToneColor {
        switch state {
        case .idle, .connecting, .opening: return .accent
        case .success: return .ok
        case .doubleVerify: return .warn
        case .failed: return .danger
        }
    }
    /// 241 中心三态符号: 锁闭(未就绪)/开启(就绪)/警告(失败·双验), 过程态另有信号/旋转
    private var iconName: String {
        switch state {
        case .idle:
            if !bleReady { return "antenna.radiowaves.left.and.right.slash" }
            return connected ? "lock.open" : "lock.fill"
        case .connecting: return "antenna.radiowaves.left.and.right"
        case .opening: return "lock.rotation"
        case .success: return "checkmark"
        case .doubleVerify: return "person.badge.key.fill"
        case .failed: return failStreak >= 2 ? "antenna.radiowaves.left.and.right" : "exclamationmark.triangle.fill"
        }
    }
    private var title: String {
        switch state {
        case .idle:
            if !bleReady { return "蓝牙未开启" }
            if !connected { return "连接门锁" }
            return holdConfirmOn ? "按住开锁" : "点击开锁"
        case .connecting: return "正在连接"
        case .opening: return "正在开锁"
        case .success: return "已开锁"
        case .doubleVerify: return "需二次验证"
        case .failed: return "开锁失败"
        }
    }
    private var detail: String? {
        switch state {
        case .connecting: return "正在唤醒门锁…"
        case .opening: return "请稍候 · 轻点圆盘可撤销"
        case .success: return "门已打开"
        case .doubleVerify: return "门锁已开启双重验证，请用指纹或密码开门"
        case .failed(let msg): return msg
        case .idle: return nil
        }
    }
    /// 242 角落状态点: 灰=未连接/蓝牙关, 品牌色=握手中, 绿=就绪 — Hero 卡滚出屏幕也不丢信息
    private var dotColor: Color {
        if !bleReady { return DS.Palette.textSub }
        if connected { return DS.Palette.ok }
        if isBusy { return DS.Palette.accent }
        return DS.Palette.textSub
    }
    /// 90 连续失败: 中心切换为信号搜索符号循环动效
    private var searching: Bool {
        if case .failed = state { return failStreak >= 2 }
        return false
    }

    var body: some View {
        VStack(spacing: DS.Space.m) {
            ZStack {
                // 呼吸光晕: 径向渐变模拟柔光, 只动 scale/opacity (比动画阴影便宜得多);
                // 让主控"活着", 站在门口余光也知道该按哪里 (248: 夜间降峰值)
                Circle()
                    .fill(RadialGradient(colors: [dialGlow.opacity(0.38 * dim), .clear],
                                         center: .center, startRadius: 24, endRadius: 120))
                    .frame(width: 240, height: 240)
                    .scaleEffect(breathe ? 1.1 : 0.96)
                    .opacity((breathe ? 0.85 : 0.55) * dim)
                    .allowsHitTesting(false)
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { breathe = true }
                    }
                // 静态外环: 给主控一个"表盘"的结构感, 也让呼吸环的扩散有参照
                Circle()
                    .strokeBorder(DS.Palette.hairline, lineWidth: 1)
                    .frame(width: dial + 16, height: dial + 16)
                    .allowsHitTesting(false)
                // 75 待机流光: 只在就绪空闲时环绕
                if connected, case .idle = state {
                    UnlockShimmer(diameter: dial)
                }
                // 成功冲击波: 一次性扩散, 罕见时刻才配得的庆祝 (reduceMotion 下不出现)
                if shock {
                    Circle()
                        .strokeBorder(DS.Palette.ok.opacity(0.55), lineWidth: 2.5)
                        .frame(width: dial, height: dial)
                        .scaleEffect(shock ? 1.5 : 1)
                        .opacity(shock ? 0 : 0.85)
                        .allowsHitTesting(false)
                }
                // 呼吸环独立成视图并切断隐式动画继承, 见 UnlockPulseRing 的注释
                if isBusy { UnlockPulseRing(diameter: dial) }
                Button {
                    // VO/开关控制/转子激活直达: 绕过按住确认 (替代按钮降级), 蓝牙关时给出失败解释
                    guard bleReady else { return }
                    action()
                } label: {
                    VStack(spacing: DS.Space.s) {
                        Image(systemName: iconName)
                            .font(.system(size: 46, weight: .medium))
                            .foregroundStyle(contentColor)
                            // 状态切换时图标形变过渡 (锁→信号→勾), 比"换了张图"更有生命感
                            .symbolEffect(.replace.downUp, isActive: !reduceMotion, value: iconName)
                            .symbolEffect(.variableColor.iterative, options: .repeating,
                                          isActive: !reduceMotion && searching, value: iconName)
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(contentColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .contentTransition(.opacity)   // 状态色变化时交叉淡化, 而不是 RGB 硬跳
                    .frame(width: dial, height: dial)
                    .background(dialFill, in: Circle())
                    // 871 命中域扩容: 圆盘外沿再留 10pt 命中余量 (直径本身 ≥44pt 远超标)
                    .contentShape(Circle().inset(by: -10))
                    // 顶部内高光: 一层"玻璃厚度" (248: 夜间降峰值)
                    .overlay {
                        Circle()
                            .fill(LinearGradient(colors: [.white.opacity(0.20 * dim), .clear],
                                                 startPoint: .top, endPoint: .center))
                            .allowsHitTesting(false)
                    }
                    .shadow(color: dialGlow.opacity(0.32), radius: 22, y: 10)
                    // 开锁成功是罕见的高情绪时刻, 允许一次克制的弹跳 (find-animation 的"稀有档")
                    .scaleEffect(pop ? 1.04 : 1)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("开锁")
                .accessibilityValue(voValue)
                .accessibilityHint(voHint)
                // 846/167 圆盘转子调节: VO 转子上下滑 = 在 状态/电量/连接 间切换播报值
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: voRotorIndex = (voRotorIndex + 1) % 3
                    case .decrement: voRotorIndex = (voRotorIndex + 2) % 3
                    default: voRotorIndex = 0
                    }
                    // 播报切换后的值 (转子切维度的即时反馈)
                    AXTools.announce(voValue + " — " + voRotorName())
                }
                // 手势层: 按住确认 + 上滑 + 双围栏 ( sighted 用户路径, VO 激活不走这里 )
                .highPriorityGesture(dragGesture)
                // 2 环形进度: 按住时在盘外沿填充
                Circle()
                    .trim(from: 0, to: holdProgress)
                    .stroke(DS.Palette.accentText.opacity(0.9),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: dial + 20, height: dial + 20)
                    .rotationEffect(.degrees(-90))
                    .opacity(holdProgress > 0.001 ? 0.95 : 0)
                    .allowsHitTesting(false)
                // 62 围栏已解锁的虚线提示环
                if armed {
                    Circle()
                        .strokeBorder(DS.Palette.ok.opacity(0.75),
                                      style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                        .frame(width: dial + 20, height: dial + 20)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                // 242 角落状态点: 右上角常显
                Circle()
                    .frame(width: 10, height: 10)
                    .foregroundStyle(dotColor)
                    .overlay(Circle().strokeBorder(.white.opacity(0.65), lineWidth: 1))
                    .offset(x: dial * 0.44, y: -dial * 0.44)
                    .accessibilityHidden(true)
            }
            .offset(x: shakeX)
            // 80 三段进度细条
            if isBusy, phase > 0 {
                PhaseBar(phase: phase, slow: slowConnect, width: dial + 40)
                    .transition(.opacity)
            }
            // 89 握手超 4 秒: 细条转橙 + 允许提前取消
            if slowConnect, isBusy {
                Button("取消等待", action: cancelAction)
                    .buttonStyle(SecondaryActionStyle(fullWidth: false))
                    .transition(.opacity)
            }
            // 85 退避节奏文案优先; 其次状态详情
            if let retryText {
                Text(retryText)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(DS.Palette.accentText)
                    .transition(.opacity)
            } else if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(detailTone)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DS.Space.l)
                    .transition(.opacity)
            }
            // 62 围栏开启但未解锁时的教学一句
            if fenceRequired, !armed, !isBusy, bleReady, state == .idle {
                Text("误触围栏开启中: 先从圆盘边缘拖到中心, 再执行开锁手势")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Space.xl)
                    .transition(.opacity)
            }
        }
        .animation(DS.Motion.standard, value: state)
        .animation(DS.Motion.soft, value: armed)
        // 系统级触觉反馈: 跟随"减少触感"系统开关, 也省掉手动生成器
        .sensoryFeedback(trigger: state) { _, newState in
            switch newState {
            case .success: return .success
            case .doubleVerify: return .warning
            case .failed: return .error
            default: return nil
            }
        }
        // 79 心跳触感: 握手期间按心跳节奏双轻触 (成功由结果档收尾)
        .task(id: state) {
            guard case .connecting = state else { return }
            while !Task.isCancelled {
                DS.Haptics.tick.impactOccurred()
                try? await Task.sleep(for: .milliseconds(130))
                DS.Haptics.tick.impactOccurred()
                try? await Task.sleep(for: .milliseconds(950))
            }
        }
        // 状态变化: 成功庆祝 / 失败抖动 / 超时计时复位
        .onChange(of: state) { _, s in
            slowConnect = false
            slowTask?.cancel()
            if case .connecting = s {
                slowTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(4))
                    guard !Task.isCancelled, case .connecting = state else { return }
                    slowConnect = true   // 89
                }
            }
            if case .failed = s, !reduceMotion {
                shake()   // 74
            }
            guard case .success = s, !reduceMotion else { return }
            pop = false
            shock = false
            withAnimation(.spring(response: 0.32, dampingFraction: 0.45)) { pop = true }
            withAnimation(.easeOut(duration: 0.75)) { shock = true }
            Task {
                try? await Task.sleep(for: .seconds(0.9))
                withAnimation(DS.Motion.soft) { pop = false; shock = false }
            }
        }
    }

    @State private var slowTask: Task<Void, Never>? = nil

    /// 74 失败抖动: 左右衰减摆动, 不打断下方原因文案
    private func shake() {
        Task { @MainActor in
            for x in [CGFloat(-12), 12, -8, 8, -4, 4, 0] {
                withAnimation(.easeOut(duration: 0.05)) { shakeX = x }
                try? await Task.sleep(for: .milliseconds(55))
            }
            shakeX = 0
        }
    }

    // ---------- 手势 (61 起手围栏 / 62 误触围栏 / 1 按住 / 51 上滑 / 56 撤销轻点) ----------
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { g in
                touchMoved = abs(g.translation.width) + abs(g.translation.height)
                guard bleReady, !isBusy else { return }
                let startInside = insideFence(g.startLocation)
                // 62: 围栏开启且未解锁时, "从边缘拖入中心" = 解锁围栏 (4s 内响应开锁手势)
                if fenceRequired, !armed {
                    if !startInside, insideFence(g.location) {
                        armed = true
                        DS.Haptics.tick.impactOccurred()
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(4))
                            armed = false
                        }
                    }
                    return
                }
                guard startInside else { return }   // 61: 边缘起手忽略
                if !pressing {
                    pressing = true
                    firedThisTouch = false
                    swipePeakUp = 0
                    if holdConfirmOn {
                        DS.Haptics.tick.impactOccurred()   // 3 双段触感 · 第一段 (落手)
                        beginHold()
                    }
                }
                guard holdConfirmOn else { return }
                swipePeakUp = min(swipePeakUp, g.translation.height)
                // 51 上滑: 越过阈值后进度环预填满, 松手触发
                if swipePeakUp < -56, !swipeReady {
                    stopHold()
                    holdProgress = 1
                    swipeReady = true
                }
            }
            .onEnded { g in
                let moved = touchMoved
                touchMoved = 0
                // 56: 指令已发出 (开锁中) 轻点圆盘 = 撤销等待/重试链 (0.8s 窗口由 AppState 判定)
                if isBusy {
                    if case .opening = state, moved < 12 {
                        DS.Haptics.tick.impactOccurred()
                        action()
                    }
                    return
                }
                guard bleReady else { return }
                // 设置关闭按住确认 (单手/VO 降级): 轻点直发, 围栏开启时仍需已解锁
                if !holdConfirmOn {
                    pressing = false
                    if moved < 12, (!fenceRequired || armed) { fire() }
                    return
                }
                if firedThisTouch { return }
                if swipeReady, g.translation.height < -30 {
                    fire()
                } else if holdProgress >= 1 {
                    fire()
                } else if pressing {
                    // 松手取消回弹: 进度环弹回零位
                    stopHold()
                    pressing = false
                    if reduceMotion {
                        holdProgress = 0
                    } else {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) { holdProgress = 0 }
                    }
                }
            }
    }
    @State private var swipeReady = false

    /// 按住充能循环: 0.9s 线性填充 + 三成/六成两记刻度触感, 填满自动触发
    private func beginHold() {
        let start = Date()
        holdTask?.cancel()
        holdTask = Task { @MainActor in
            var ticked = 0
            while !Task.isCancelled {
                let p = min(1, Date().timeIntervalSince(start) / holdDuration)
                holdProgress = CGFloat(p)
                let marks = Int(p / 0.33)
                if marks > ticked, p < 1 {
                    ticked = marks
                    DS.Haptics.tick.impactOccurred()   // 22 进度触感刻度
                }
                if p >= 1 { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
            guard !Task.isCancelled else { return }
            fire()
        }
    }
    private func stopHold() {
        holdTask?.cancel()
        holdTask = nil
    }
    private func fire() {
        guard !isBusy, bleReady, !firedThisTouch else { return }
        firedThisTouch = true
        stopHold()
        pressing = false
        armed = false
        holdProgress = 0
        swipeReady = false
        DS.Haptics.trigger.impactOccurred()   // 3 双段触感 · 第二段 (确认)
        action()
    }

    /// 失败态用 danger 色。单独抽出来避免在 View 体内对 enum 做相等比较
    /// (复杂三元表达式在大型 body 里会拖慢类型检查, 且在 SDK 26 上曾导致重载解析失败)
    private var detailTone: Color {
        if case .failed = state { return DS.Palette.danger }
        return DS.Palette.textSub
    }

    /// idle/连接/开锁中走品牌渐变, 上面必须是纯白 (两端 ≥4.5:1);
    /// 成功/警告/失败沿用 onAccent 的明暗自适应语义 (深色模式压近黑墨色)
    private var contentColor: Color {
        switch state {
        case .idle, .connecting, .opening: return .white
        default: return DS.Palette.onAccent
        }
    }

    /// 光晕颜色随状态走, 让"开锁成功"在视觉上也亮一下
    private var dialGlow: Color {
        switch state {
        case .idle, .connecting, .opening: return DS.Palette.accent
        case .success: return DS.Palette.ok
        case .doubleVerify: return DS.Palette.warn
        case .failed: return DS.Palette.danger
        }
    }

    private var dialFill: LinearGradient {
        switch state {
        case .idle, .connecting, .opening:
            return DS.Gradient.hero
        default:
            break
        }
        let base: Color
        switch state {
        case .success: base = DS.Palette.ok
        case .doubleVerify: base = DS.Palette.warn
        case .failed: base = DS.Palette.danger
        default: base = DS.Palette.accent
        }
        return LinearGradient(colors: [base.opacity(0.86), base],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 847 Hero 卡合并播报同思路: 圆盘播报值按当前转子维度输出 (167 状态/电量/连接切换)
    private var voValue: String {
        switch voRotorIndex {
        case 1: return "电量 " + AXTerms.br(batteryText)
        case 2: return bleReady ? (connected ? AXTerms.connected : AXTerms.notConnected) : "蓝牙未开启"
        default: return baseLinkValue
        }
    }
    private var baseLinkValue: String {
        let link = !bleReady ? "蓝牙未开启" : (connected ? "已连接就绪" : "未连接")
        switch state {
        case .idle: return link + (connected ? ", 可开锁" : ", 点击后自动唤醒门锁蓝牙")
        case .connecting, .opening: return link + ", 进行中"
        case .success: return "已成功打开门锁"
        case .doubleVerify: return "需要指纹或密码二次验证"
        case .failed(let msg): return msg
        }
    }
    private func voRotorName() -> String {
        switch voRotorIndex { case 1: return "电量" case 2: return "连接" default: return "状态" }
    }
    private var voHint: String {
        "轻点两下直接开锁, 无需按住. 转子上下滑可切换 状态/电量/连接 播报. "
            + "875 按住时长可自定 (0.4–1.6s, 设置-辅助)"
    }
}
