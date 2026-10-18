//  LockFaceView.swift
//  门面层容器: 相位状态机 + 时间轴 + 手势。2026-10-18 门面改造新增。
//
//  相位 (D2, 唯一实现, 禁止第二处):
//    .locked -> .charging(p) -> .unlocking -> .peeking -> .opening -> .open
//                                        \-> .failed(rc)   (门**完全不动**)
//  红线: .failed 时门一个像素都不许动 —— "门动了 = 锁开了" 是用户唯一可靠的读法。
//
//  开锁入口是 app.requestUnlock() (LockKeeperApp.swift:488), **不是** LockService:
//  那里面有三道闸 (只读 / 去重 / 二次锁), 绕过它们等于绕过安全策略。

import SwiftUI
import UIKit

enum LockFacePhase: Equatable {
    case locked
    case charging(CGFloat)
    case unlocking
    case peeking
    case opening
    case open
    case closing
    case failed(String)

    var isOpen: Bool { self == .open }
}

struct LockFaceView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 门是否展示 (由 LockFacePolicy 决定; 深链/小组件/Siri 一律 false)。
    @Binding var presented: Bool
    /// 已进门 (App 可见)。门转开后由本视图置 true。
    @Binding var entered: Bool

    @State private var phase: LockFacePhase = .locked
    @State private var openProgress: Double = 0
    @State private var shakeX: CGFloat = 0
    @State private var pressed = false
    @State private var lightLeak: Double = 0
    @State private var holdTask: Task<Void, Never>?
    @State private var lastTick = 0
    /// 三连点档: 已点次数 / 重置计时器
    @State private var tapCount = 0
    @State private var tripleReset: Task<Void, Never>?

    /// 皮肤来自当前锁的 LockMeta (不是 LockProfile —— 那个类型不存在)。
    private var skin: LockFaceSkin {
        LockFacePolicy.skin(for: app.currentMac)
    }

    private var plateD: CGFloat {
        LockFaceStyle.plateDiameter(screenWidth: LockFaceGeometry.screenWidth)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 两扇门
                HStack(spacing: 0) {
                    LockLeaf(openProgress: openProgress, isRight: false, skin: skin)
                    LockLeaf(openProgress: openProgress, isRight: true, skin: skin)
                }

                // 中缝透光 (先于门转动亮起)
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear,
                                    Color(hex: 0xFFE4B6).opacity(0.90),
                                    Color(hex: 0xFFECC4).opacity(0.95),
                                    .clear],
                            startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: LockFaceStyle.gapWidth)
                    .shadow(color: Color(hex: 0xFFCE8A).opacity(0.42), radius: 22)
                    .opacity(lightLeak)
                    .allowsHitTesting(false)

                // 状态行 (D13): **只说本机真知道的事**。
                // 协议里没有「在线」「反锁状态」「门磁」——CAPABILITY.md §5 已确证。
                // 允许的三个真源: CoreBluetooth 连接态 / cmd03 的 powerLevel / 本机记录。
                // ⚠️ 2026-10-18 真机截图修正: 原来这个 VStack 直接放在 ZStack 里,
                // ZStack 默认居中 —— 标题跑到屏幕正中间压在锁体上。设计稿是**顶部大标题**。
                // 修法: 用 VStack{ 标题; Spacer() } 把标题顶到顶部, 并让它跟随安全区。
                if isLockedPhase {
                    VStack(spacing: DS.Space.xs) {
                        Text(app.current?.name ?? "门")
                            .vkFont(.largeTitle, weight: .semibold)   // D15 第 2 条: 34pt semibold
                            .foregroundStyle(DS.Palette.text)
                        Text(truthfulStatusLine)
                            .vkFont(.footnote)                        // D15 第 3 条: 13pt
                            .foregroundStyle(DS.Palette.textSub)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, DS.Space.gutter)   // D15 第 1 条: 16pt
                    .padding(.top, geo.safeAreaInsets.top + DS.Space.m)
                    .allowsHitTesting(false)
                }

                // 推门而入: 不解锁也能进 (D2 —— 开锁是安全动作, 进门是导航动作, 两者分开)。
                // 位置: 右下角, 不抢锁体的视觉焦点, 但触达 >= 44pt。
                if isLockedPhase {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            // 2026-10-18 设计审查: 「进入」是门面上**唯一的次要出口** ——
                            // 不想开锁、只想看记录/设置的人全靠它。原来用 textSub 纯文字,
                            // 在门面这种低对比背景上几乎看不见 (Emil: 看不见的细节要服务可用性)。
                            // 改成带底衬的胶囊: 仍然比锁体轻一档 (不是主操作), 但明确是"可以按的"。
                            Button {
                                enterWithoutUnlocking()
                            } label: {
                                Text("进入")
                                    .vkFont(.subheadline, weight: .medium)
                                    .foregroundStyle(DS.Palette.text)
                                    .padding(.horizontal, DS.Space.l)
                                    .frame(minHeight: DS.Hit.min)
                                    .variantPlate(DS.Palette.surfaceAlt, .capsule, edge: DS.Palette.hairline)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, DS.Space.l)
                        }
                    }
                    .padding(.bottom, 74)
                }

                // 关门: 门开着时右上角一颗, 这是 D8 推荐的"只保留按钮 + 左缘拖"中的按钮那半。
                if phase == .open {
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                closeDoor()
                            } label: {
                                Text("关门")
                                    .vkFont(.subheadline, weight: .medium)
                                    .foregroundStyle(DS.Palette.text)
                                    .padding(.horizontal, DS.Space.l)
                                    .frame(minHeight: DS.Hit.min)
                                    .variantPlate(DS.Palette.surfaceAlt, .capsule, edge: DS.Palette.hairline)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, DS.Space.l)
                            .padding(.top, DS.Space.l)
                        }
                        Spacer()
                    }
                }

                // 锁体 (手势按 UnlockPrefs.mode 分派: 按住 / 三连点)
                plateGestureView
                    .position(x: geo.size.width / 2,
                              y: geo.size.height * LockFaceStyle.plateCenterRatio(
                                  isLandscape: geo.size.width > geo.size.height))
                    .opacity(plateOpacity)
                    .allowsHitTesting(isLockedPhase)
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("开锁，\(app.current?.name ?? "前门")")
                    .accessibilityValue(accessibilityValue)
                    .accessibilityHint(UnlockPrefs.gestureHint)
                    .accessibilityAction { startUnlock() }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .background(DS.Palette.canvas)
        .onChange(of: app.unlockState) { _, new in react(to: new) }
        .onChange(of: presented) { _, show in
            if !show { phase = .locked; openProgress = 0; lightLeak = 0; entered = false }
        }
    }

    // MARK: - 派生状态

    private var chargeProgress: CGFloat {
        if case .charging(let p) = phase { return p }
        return 0
    }

    private var isLockedPhase: Bool {
        if case .locked = phase { return true }
        if case .charging = phase { return true }
        return false
    }

    private var unlockedGlyph: Bool {
        switch phase {
        case .peeking, .opening, .open: return true
        default: return false
        }
    }

    private var plateOpacity: Double {
        switch phase {
        case .opening, .open, .closing: return max(0, 1 - openProgress * 2)
        default: return 1
        }
    }

    /// 门面状态行 —— **每一句都必须是真的** (D13)。
    /// 不写「在线」(协议无此状态)、不写「已锁定」(不是锁端事实)、绝不写「门磁未合上」(协议无门磁)。
    private var truthfulStatusLine: String {
        // 连接态: CoreBluetooth 的本机事实
        let link: String
        switch app.unlockState {
        case .connecting, .opening: link = "正在连接"
        default: link = app.current == nil ? "未选择门锁" : "已连接"
        }
        // 电量: 走既有的统一读数口径 (采样 + 快照取新), -1 = 未知。
        // **不自己解快照、不自己猜** —— BatteryCare.facePct 就是这一格的唯一来源。
        let pct = app.current.map { BatteryCare.facePct($0.mac) } ?? -1
        let bat = pct < 0 ? "电量未知" : (pct > 80 ? "电量 >80%" : "电量 \(pct)%")
        return "\(link) · \(bat)"
    }

    private var accessibilityValue: String {
        switch phase {
        case .locked: return "已锁定"
        case .charging(let p): return "充能 \(Int(p * 100))%"
        case .unlocking: return "正在开锁"
        case .failed(let msg): return "开锁失败，\(msg)"
        default: return "已开锁"
        }
    }

    // MARK: - 手势: 按住充能 (连续量, 不是分段状态)

    /// 锁体本体 (不含手势)。手势由 plateGestureView 按档位挂。
    private var plateBase: some View {
        LockPlate(progress: chargeProgress,
                  pressed: pressed,
                  unlocked: unlockedGlyph,
                  shakeX: shakeX,
                  diameter: plateD,
                  skin: skin)
    }

    /// 按用户设置的手势档位分派 (UnlockPrefs.mode: hold / triple / charge)。
    /// 2026-10-18 设计审查修正: 原实现只有"按住"一种, 用户选了另外两档等于设置失效。
    @ViewBuilder
    private var plateGestureView: some View {
        switch UnlockPrefs.mode {
        case "triple":
            plateBase.onTapGesture {
                guard isLockedPhase else { return }
                tapCount += 1
                if tapCount >= 3 { tapCount = 0; startUnlock() }
                // 两次点击间隔超过 0.6s 视为重新开始 (与既有三连点口径一致)
                tripleReset?.cancel()
                tripleReset = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    if !Task.isCancelled { tapCount = 0 }
                }
            }
        default:
            plateBase.gesture(chargeGesture)
        }
    }

    private var chargeGesture: some Gesture {
        // 2026-10-18 设计审查修正 (Apple Design §2 直接操纵 / §1 响应):
        // 原实现用 DragGesture(minimumDistance: 0) 却**丢掉了位移值**(onChanged { _ in }),
        // 于是充能是"按时间自己涨", 手指停住它照涨 —— 那是脚本动画, 不是跟手。
        // 改成: 充能进度由**手指位移**驱动, 手指不动进度就不动, 松手即回零。
        // 同时按 UnlockPrefs.mode 分叉 —— 用户选了三连点/旋转档, 门面不能强行按住。
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isLockedPhase else { return }
                if !pressed {
                    pressed = true
                    phase = .charging(0)
                    lastTick = 0
                }
                // 沿圆盘外沿滑动累计的"转过的角度"当作进度; 按住不动 = 不涨。
                let travel = abs(value.translation.width) + abs(value.translation.height)
                let p = min(1, travel / chargeTravel)
                phase = .charging(p)
                // 触觉节拍: 判据 (ui-ux-pro-max "Don't overuse vibration") ——
                // 全程只震 3 下 (25% / 50% / 75%), 不是每 10% 一下。
                // 充能本身有 1:1 的视觉进度, 触觉只用来"确认在推进", 不需要密。
                let tick = Int(p * 4)   // 0…4, 每档 25%
                if tick > lastTick {
                    lastTick = tick
                    if tick < 4 { DS.Haptics.tick.impactOccurred() }
                }
                if p >= 1 { startUnlock() }
            }
            .onEnded { _ in
                pressed = false
                cancelChargeIfNeeded()
            }
    }

    /// 充满所需的滑动距离 (pt)。约等于盘径的 1.2 倍, 单手拇指一次划得完。
    private var chargeTravel: CGFloat {
        reduceMotion ? plateD * 0.4 : plateD * 1.2
    }
    // MARK: - 时间轴

    @MainActor
    private func cancelChargeIfNeeded() {
        guard isLockedPhase else { return }
        holdTask?.cancel(); holdTask = nil
        withAnimation(DS.Motion.chargeReset) { phase = .locked }
    }

    /// 真正开锁。**唯一入口** app.requestUnlock(); 不直连 LockService。
    /// 注意: requestUnlock() 返回 Void —— 它只是**发指令**, 结果从 app.unlockState 异步回来。
    /// 所以这里不 await 返回值, 而是把相位挂到 onChange(of: app.unlockState) 上 (见 body)。
    @MainActor
    private func startUnlock() {
        guard isLockedPhase else { return }
        holdTask?.cancel(); holdTask = nil
        DS.Haptics.trigger.impactOccurred()
        phase = .unlocking
        app.requestUnlock()
    }

    /// unlockState 变化 -> 推进相位。这是门面与开锁链路的**唯一**耦合点。
    @MainActor
    private func react(to state: AppState.UnlockState) {
        switch state {
        case .success:
            guard phase == .unlocking else { return }
            succeed()
        case .failed(let msg):
            guard phase == .unlocking else { return }
            fail(reason: msg)
        case .doubleVerify:
            // 250 二次开锁闸: 等用户在别处验证, 门面回到可再次按压的状态。
            guard phase == .unlocking else { return }
            withAnimation(DS.Motion.chargeReset) { phase = .locked }
        default:
            break
        }
    }

    @MainActor
    /// 开锁成功后的时间轴。
    ///
    /// 2026-10-18 设计审查修正 (ui-ux-pro-max: "Animate 1-2 key elements per view maximum"):
    /// 原实现同时驱动 7 个独立动画 (字形/中缝光/门扇/锁体淡出/标题淡出/提示淡出/App 层),
    /// 那是"什么都动"= 什么都不突出。现在收敛到**两个主角**:
    ///   ① 中缝光 (先亮, 告诉用户"开了")
    ///   ② 门扇 (后转, 把用户送进去)
    /// 其余元素跟着主角的时序走, 但**不再各自配时长** —— 锁体与标题直接随门扇淡出。
    @MainActor
    private func succeed() {
        // 主角 ①: 中缝光。它先亮, 门才转 —— 这个先后关系是全部叙事。
        withAnimation(DS.Motion.lightLeak) { lightLeak = 1 }
        let turnDelay = reduceMotion ? 0 : LockFaceStyle.doorTurnDelay
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(turnDelay * 1_000_000_000))
            // 主角 ②: 门扇转开。字形换态与它同刻, 不单独计时 (同一条 withAnimation)。
            withAnimation(DS.Motion.doorSwing) {
                openProgress = 1
                phase = .opening
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
            phase = .open
            // 门已转开 -> 交接给根容器: 现在可以显示 App 了。
            withAnimation(DS.Motion.doorReveal) { entered = true }
            try? await Task.sleep(nanoseconds: UInt64(LockFaceStyle.lightLeakFadeDelay * 1_000_000_000))
            withAnimation(DS.Motion.exit) { lightLeak = 0 }
        }
    }
    /// 失败: **门完全不动**, 只抖锁体 + 触觉 + 文案。
    @MainActor
    private func fail(reason: String) {
        phase = .failed(reason)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        Task { @MainActor in
            for _ in 0..<3 {
                withAnimation(.easeInOut(duration: 0.09)) { shakeX = 6 }
                try? await Task.sleep(nanoseconds: 90_000_000)
                withAnimation(.easeInOut(duration: 0.09)) { shakeX = -6 }
                try? await Task.sleep(nanoseconds: 90_000_000)
            }
            withAnimation(DS.Motion.quick) { shakeX = 0 }
            try? await Task.sleep(nanoseconds: 600_000_000)
            withAnimation(DS.Motion.chargeReset) { phase = .locked }
        }
    }
    /// 推门而入: 不解锁, 直接把门打开 (锁状态**不变**)。
    /// 这是"只想看记录/设置"的人的唯一出口 —— 没有它, 每个想改设置的人都得先对真锁发一次开锁指令。
    @MainActor
    private func enterWithoutUnlocking() {
        // 可中断: 门正在关的过程中点"进入", 从当前角度反向转开 (不跳变)
        if phase == .closing { phase = .opening }
        DS.Haptics.tick.impactOccurred()
        phase = .opening
        withAnimation(DS.Motion.doorSwing) { openProgress = 1 }
                Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            phase = .open
            withAnimation(DS.Motion.doorReveal) { entered = true }
        }
    }
    /// 关门 (右缘拖 >=96pt / 导航栏按钮 / Esc)。
    /// 关门 (导航栏按钮 / Esc / 左缘拖)。
    /// 2026-10-18 设计审查修正 (Apple Design §3 可中断性):
    /// 原实现固定等 820ms 再置 locked —— 若用户在门还没转完时又点"进入",
    /// 会看到门停在半路然后突然跳走。现在: 从**当前 openProgress** 出发转回,
    /// 时长按剩余角度等比缩短, 且任何时刻可被 enterWithoutUnlocking 反向打断。
    @MainActor
    func closeDoor() {
        guard phase == .open || phase == .opening else { return }
        let remaining = openProgress   // 0…1, 从中途关也成立
        phase = .closing
        withAnimation(DS.Motion.exit) { entered = false }
        withAnimation(DS.Motion.doorSwing) { openProgress = 0 }
        Task { @MainActor in
            // 按剩余角度等比缩短等待, 不写死 820ms
            let ms = UInt64(max(120, 820 * remaining) * 1_000_000)
            try? await Task.sleep(nanoseconds: ms)
            // 若这期间用户又进门了, 就别把相位打回 locked
            if phase == .closing {
                phase = .locked
                presented = false
                entered = false
            }
        }
    }
}

/// 屏宽读取 (锁体直径换算用)。用 UIScreen 而不是 GeometryReader, 因为直径要在 body 外算好。
enum LockFaceGeometry {
    static var screenWidth: CGFloat {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .screen.bounds.width ?? 393
    }
}
