// ================= 52/53/58 手势模式单点 =================
/// 圆盘确认方式的**唯一读点**: 设置页 (SettingsView 开锁段) 与主控 (UnlockDial) 都从这里取值，
/// 不各写各的默认值 —— 否则"设置说自己是三连点、圆盘按 hold 生效"这类分叉又得靠人读抓。
/// 非法/空值一律回落 hold (与拍板前的行为逐字一致)。
enum UnlockPrefs {
    static let modes = ["hold"]
    static var mode: String {
        let v = DB.store.getString("kf_gesture_mode")
        return modes.contains(v) ? v : "hold"
    }
    // 2026-10-27 审核删除 (AUDIT-B 3.4)：`gestureHint` 零引用 ——
    // 圆盘演练层（59）与专注页头这两个消费者都已在早前精简里删掉，
    // 只剩一个 `switch mode { default: return "可按住圆盘，也可上滑" }`
    // 的单分支 switch（等于无条件返回常量），留着会让读者以为这里有档位差异。
}

// ================= 呼吸环 =================
// 独立成视图, 而不是 UnlockDial body 里的内联 Circle, 原因有二:
//   1. 属性争用 — 呼吸环用 repeatForever 驱动 scaleEffect/opacity, 而 UnlockDial
//      整棵子树挂着 .animation(DS.Motion.standard, value: state) 也驱动同一批属性,
//      状态一变两层动画会互相覆盖。这里用 .transaction 切断隐式继承。
//   2. 减少动效不等于取消动效 — 开启"减少动效"时改为保留一圈静态指示,
//      只是不再循环, 而不是整个消失(消失 = 用户不知道程序在跑)。

// 开锁主控 — App 的唯一高频操作 (包1: 手势收敛后的最终形态)。
// 手势族取舍 (ROADMAP 包1 收录 1-3/51/61-62; `docs/DEFERRED.md:36-41` 曾把 52-55/57-58 整族划掉):
//   2026-10-10 拍板"手势族 6 条全做"，第九十八批据此补回 **52/53/58/59** —— 但划掉时写的两条理由仍然成立，
//   所以落地口径按理由收紧: ①52/58 做成与按住确认**互斥的单选档** (默认 hold，老用户观感不变，
//   不再有"旋转一圈把 10 秒动线拉长"的默认路径)；②53 双击直开**默认关**，开=明写"绕过按住确认"的减配，
//   且只在 hold 档生效；③54 摇一摇与 372 摇一摇遁走抢同一个传感器，未在本批动 (遁走是安全动作，
//   优先级必须先定，见第九十九批)；57 方位手势仍依赖协议不存在的上锁命令 (CAPABILITY §5)，不动。
//   主交互 A — 按住确认 (idea 1): 按住 0.9s 环形进度填满才发指令 (idea 2 环形进度);
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
    var rssi: Int? = nil               // 66 最近一次扫到的锁内信号, 驱动呼吸速率
    var action: () -> Void             // 手势确认 / VO 直开 → AppState.requestUnlock
    var cancelAction: () -> Void = {}  // 89 握手超时提前取消

    @State var pop = false
    @State var shock = false
    @State var breathe = false
    @State var slowConnect = false     // 89 握手超 4 秒
    @State var shakeX: CGFloat = 0     // 74 失败抖动
    // --- 手势态 ---
    @State var pressing = false
    @State var holdProgress: CGFloat = 0
    @State var firedThisTouch = false
    @State var swipePeakUp: CGFloat = 0
    @State var touchMoved: CGFloat = 0
    @State var armed = false           // 62 误触围栏已解锁
    @State var weakNudge = false        // 129 已因信号偏弱暂缓过一次
    @State var holdTask: Task<Void, Never>? = nil

    @Environment(\.accessibilityReduceMotion) var reduceMotion

    // ---------- 偏好 (设置-开锁, 经 AppState.setUnlockOption 重建生效) ----------
    var detail: String? {
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
    var dotColor: Color {
        if !bleReady { return DS.Palette.textSub }
        if connected { return DS.Palette.ok }
        if isBusy { return DS.Palette.accent }
        return DS.Palette.textSub
    }
    /// 90 连续失败: 中心切换为信号搜索符号循环动效
    var searching: Bool {
        if case .failed = state { return failStreak >= 2 }
        return false
    }

    var body: some View {
        VStack(spacing: DS.Space.m) {
            ZStack {
                // 呼吸光晕: 径向渐变模拟柔光, 只动 scale/opacity (比动画阴影便宜得多);
                // 让主控"活着", 站在门口余光也知道该按哪里 (248: 夜间降峰值)
                Circle()
                    .fill(RadialGradient(colors: [dialGlow.opacity(0.38), .clear],
                                         center: .center, startRadius: 24, endRadius: 120))
                    .frame(width: 240, height: 240)
                    .scaleEffect(breathe ? 1.1 : 0.96)
                    .opacity(breathe ? 0.85 : 0.55)
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
                if isBusy { UnlockPulseRing(diameter: dial, rssi: rssi) }
                Button {
                    // VO/开关控制/转子激活直达: 绕过按住确认 (替代按钮降级), 蓝牙关时给出失败解释
                    guard bleReady else { return }
                    action()
                } label: { dialButtonLabel() }
                .buttonStyle(PressableButtonStyle())
                // 164 Cmd+U 开锁 (与 Cmd+1..4 同族); 蓝牙关的 guard 在 Button action 里, 照常挡
                .accessibilityLabel("开锁")
                .accessibilityHint(voHint)
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
                    .overlay(Circle().strokeBorder(DS.heroFg.opacity(0.65), lineWidth: 1))
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
                    .vkFont(.footnote, weight: .medium)
                    .foregroundStyle(DS.Palette.accentText)
                    .transition(.opacity)
            } else if let detail {
                Text(detail)
                    .vkFont(.footnote)
                    .foregroundStyle(detailTone)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DS.Space.l)
                    .transition(.opacity)
            }
            // 62 围栏开启但未解锁时的教学一句
            if fenceRequired, !armed, !isBusy, bleReady, state == .idle {
                Text("误触围栏开启中： 先从圆盘边缘拖到中心， 再执行开锁手势")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Space.xl)
                    .transition(.opacity)
            }
            // 129 极限距离提示: 最近一次 RSSI 逼近 93 信号围栏下限时, 第一次手势只提示不发出
            if nearRssiLimit {
                Text(weakNudge
                     ? "已暂缓这一次： 离门锁再走近一步， 然后重新按住圆盘"   // 129 界面文案
                     : "信号偏弱， 走近一步再开更稳")   // 129 信号偏弱
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.warn)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Space.xl)
                    .transition(.opacity)
            }
        }
        .animation(DS.Motion.standard, value: state)
        .animation(DS.Motion.soft, value: armed)
        .animation(DS.Motion.soft, value: weakNudge)
        // 59 演练层只在"从没真手势过"时浮现一次
        // 系统级触觉反馈: 跟随"减少触感"系统开关, 也省掉手动生成器
        .sensoryFeedback(trigger: state) { _, newState in
            switch newState {
            case .success: return .success
            case .doubleVerify: return .warning
            case .failed: return .error
            default: return nil
            }
        }
        // 269 就绪轻震: BLE 会话刚就绪 (connected false→true) 的一瞬给一次轻触感, 提示"可以按圆盘了"。
        // 只报"就绪"这一件事; 成功/双验/失败仍由上面那条 state 触感负责, 两条触发源不重叠。
        .sensoryFeedback(trigger: connected) { old, new in
            new && !old ? .impact(weight: .light) : nil
        }
        // 79 心跳触感: 握手期间按心跳节奏双轻触 (成功由结果档收尾)
        // 274 免打扰时段整段不震: 心跳是"陪着等"的装饰性触感, 夜里连接时它最扰人
        .task(id: state) {
            guard case .connecting = state else { return }
            guard !(CareSchedule.quietOn && CareSchedule.isQuietHour()) else { return }
            while !Task.isCancelled {
                DS.Haptics.tick.impactOccurred()
                // 2026-10-27 (AUDIT-D D-21)：取消后立即返回，不推进状态（原 try? 会吞掉 CancellationError）
                do { try await Task.sleep(for: .milliseconds(130)) } catch { return }
                // `try?` 把 CancellationError 咽成一个 nil 继续往下走 ⇒ 取消如果落在这 130ms 里,
                // 第二记触感照样会震, 而这一刻正是"结果回来"的那一瞬 (成功/失败触感同帧叠加),
                // 用户摸到的是"门开了还多一跳"。必须显式判一次再收尾。
                guard !Task.isCancelled else { break }
                DS.Haptics.tick.impactOccurred()
                // 2026-10-27 (AUDIT-D D-21)：取消后立即返回，不推进状态（原 try? 会吞掉 CancellationError）
                do { try await Task.sleep(for: .milliseconds(950)) } catch { return }
            }
        }
        // 状态变化: 成功庆祝 / 失败抖动 / 超时计时复位
        .onChange(of: state) { _, s in
            slowConnect = false
            slowTask?.cancel()
            // 73 指令确认瞬间 (.idle→.opening) 放一次涟漪。靠 id 换键重挂，而不是给同一个视图改属性:
            // 连开两次时上一段 0.72s 的动画余帧会接着播，看着像"涟漪只出现了一半"。
            if case .connecting = s {
                slowTask = Task { @MainActor in
                    // 2026-10-27 (AUDIT-D D-21)：取消后立即返回，不推进状态（原 try? 会吞掉 CancellationError）
                    do { try await Task.sleep(for: .seconds(4)) } catch { return }
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
                // 2026-10-27 (AUDIT-D D-21)：取消后立即返回，不推进状态（原 try? 会吞掉 CancellationError）
                do { try await Task.sleep(for: .seconds(0.9)) } catch { return }
                withAnimation(DS.Motion.soft) { pop = false; shock = false }
            }
        }
    }

    @State var slowTask: Task<Void, Never>? = nil





    /// 74 失败抖动: 左右衰减摆动, 不打断下方原因文案
    func shake() {
        Task { @MainActor in
            for x in [CGFloat(-12), 12, -8, 8, -4, 4, 0] {
                withAnimation(.easeOut(duration: 0.05)) { shakeX = x }
                // 2026-10-27 (AUDIT-D D-21)：取消后立即返回，不推进状态（原 try? 会吞掉 CancellationError）
                do { try await Task.sleep(for: .milliseconds(55)) } catch { return }
            }
            shakeX = 0
        }
    }

    // ---------- 手势 (61 起手围栏 / 62 误触围栏 / 1 按住 / 51 上滑 / 56 撤销轻点) ----------
    var dragGesture: some Gesture {
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
                            // 2026-10-27 (AUDIT-D D-21)：取消后立即返回，不推进状态（原 try? 会吞掉 CancellationError）
                            do { try await Task.sleep(for: .seconds(4)) } catch { return }
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
                // 设置关闭按住确认 (单手/VO 降级): 轻点直发, 围栏开启时仍需已解锁。
                // 三连点档**不许**在这里单发 —— 否则"数满三下"被这行偷走，等于没做。
                if !holdConfirmOn {
                    pressing = false
                    if moved < 12, (!fenceRequired || armed) { fire() }
                    return
                }
                if firedThisTouch { return }
                if swipeReady, g.translation.height < -30 {
                    fire()
                } else if holdProgress >= 1, !swipeReady {
                    // 上滑越过 :441 阈值后 holdProgress 被锁存为 1; 用户把手指收回原点再松手是**取消意图**,
                    // 旧实现这里无条件 fire() → "拉回取消"手势照样开门。现让该情形落到下面的取消回弹分支。
                    fire()
                } else if pressing {
                    // 松手取消回弹: 进度环弹回零位
                    // 2026-10-13 对抗式点击审计: 补 `swipeReady = false`。原实现在取消分支只复位
                    // pressing/holdProgress, 不碰 swipeReady ⇒ 上滑预填后拉回原点松手 (取消) 时
                    // swipeReady 残留 true。后果两个: ① 上滑预填捷径失效; ② 上面的阈值判断
                    // (`!swipeReady`) 失效后, 松手阈值从 -56 变 -30 —— 用户会碰到"轻扫一下就开锁"。
                    swipeReady = false
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
    @State var swipeReady = false

    /// 按住充能循环: 0.9s 线性填充 + 三成/六成两记刻度触感, 填满自动触发
    func beginHold() {
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
                // 2026-10-27 (AUDIT-D D-21)：取消后立即返回，不推进状态（原 try? 会吞掉 CancellationError）
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            fire()
        }
    }
    func stopHold() {
        holdTask?.cancel()
        holdTask = nil
    }
    /// 129 极限距离: 拿最近一次扫到的 RSSI 与 93 信号围栏比，余量 ≤5 dBm 就算逼近下限。
    /// 无读数 (nil 或 BLE 下界以下) 不判弱 —— 把"没扫到"读成"很远"是另一种假。
    var nearRssiLimit: Bool {
        guard let r = rssi, r > -127 else { return false }
        return r <= LinkSense.rssiFence + 5
    }

    func fire() {
        guard !isBusy, bleReady, !firedThisTouch else { return }
        // 129 暂缓: 第一次手势只提示不发指令，同一轮里第二次确认才真发 ——
        // 原句是"提示再走近一步并暂缓发指令"，暂缓不等于把人不关在门外，所以不做硬拦。
        if nearRssiLimit && !weakNudge {
            weakNudge = true
            pressing = false
            armed = false
            holdProgress = 0
            swipeReady = false
            stopHold()
            DS.Haptics.trigger.impactOccurred()   // 129 暂缓那一次给一下中等触感，不额外引入生成器
            return
        }
        weakNudge = false
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
    var detailTone: Color {
        if case .failed = state { return DS.Palette.danger }
        return DS.Palette.textSub
    }

    /// idle/连接/开锁中走品牌渐变, 上面必须是纯白 (两端 ≥4.5:1);
    /// 成功/警告/失败沿用 onAccent 的明暗自适应语义 (深色模式压近黑墨色)
    var contentColor: Color {
        switch state {
        // 反转模式 (863) 下 hero 底会降级成近白, 前景必须随之下沉为墨色
        case .idle, .connecting, .opening: return DS.heroFg
        default: return DS.Palette.onAccent
        }
    }

    /// 光晕颜色随状态走, 让"开锁成功"在视觉上也亮一下
    var dialGlow: Color {
        switch state {
        case .idle, .connecting, .opening: return DS.Palette.accent
        case .success: return DS.Palette.ok
        case .doubleVerify: return DS.Palette.warn
        case .failed: return DS.Palette.danger
        }
    }

    /// 圆盘中心图标 (从 dialButtonLabel 再抽一层: 两个 symbolEffect 的重载推断把整个标签拖超时;
    /// 并把 options 写成显式 SymbolEffectOptions.repeating 进一步消歧)
    @ViewBuilder
    func dialIcon() -> some View {
        Image(systemName: iconName)
            .font(.system(size: 46, weight: .medium))
            .foregroundStyle(contentColor)
            // 状态切换时图标形变过渡 (锁→信号→勾), 比"换了张图"更有生命感
            // 2026-10-13 run 68: `.symbolEffect(.replace.downUp, value:)` 报 "requires that
            // 'ReplaceSymbolEffect' conform to 'DiscreteSymbolEffect'" —— 符号替换的正确写法是
            // `.contentTransition(.symbolEffect(.replace))` (Apple 文档里的图标替换动画),
            // 不是把 replace 当离散 symbolEffect 用。
            .contentTransition(.symbolEffect(.replace))
            // VariableColorSymbolEffect 是**持续**效果 ⇒ 只配 `isActive:` (原写又带 value: 已去掉)。
            .symbolEffect(.variableColor.iterative, options: SymbolEffectOptions.repeating,
                          isActive: !reduceMotion && searching)
    }

    /// 圆盘按钮的标签 (从 body 内联的 Button label 里抽出 —— 巨型表达式报 type-check 超时)
    @ViewBuilder
    func dialButtonLabel() -> some View {
        VStack(spacing: DS.Space.s) {
            dialIcon()
            Text(title)
                .vkFont(.headline)
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
                .fill(LinearGradient(colors: [DS.heroFg.opacity(0.20), .clear],
                                     startPoint: .top, endPoint: .center))
                .allowsHitTesting(false)
        }
        // 206 双层材质: 外沿磨砂环 (控制中心按键质感) —— 内圈高光 (上一条) + 外沿磨砂 (本条),
        // strokeBorder 画在圆内侧, 与既有 hairline/径向光晕叠出厚度; 不吞点击。
        .overlay {
            Circle()
                .strokeBorder(.ultraThinMaterial, lineWidth: max(5, dial * 0.075))
                .allowsHitTesting(false)
        }
        .shadow(color: dialGlow.opacity(0.32), radius: 22, y: 10)
        // 开锁成功是罕见的高情绪时刻, 允许一次克制的弹跳 (find-animation 的"稀有档")
        .scaleEffect(pop ? 1.04 : 1)
    }

    // 226 后 heroGradientSafe 是 ShapeStyle (HeroSurface), 不再是 LinearGradient —— 盘子底收成 AnyShapeStyle 一起装
    var dialFill: AnyShapeStyle {
        // 245 蓝牙关: 整盘置灰 —— 此时 state 多半还是 idle (靛蓝), 盘面看着能点而 action 里的
        // guard 挡着不动, 灰面让"不可用"先于点按可见。无专门 disabled 灰度令牌, 用现有两色组合。
        if !bleReady {
            return AnyShapeStyle(LinearGradient(colors: [DS.Palette.surfaceAltBase, DS.Palette.hairline],
                                                startPoint: .top, endPoint: .bottom))
        }
        switch state {
        case .idle, .connecting, .opening:
            return AnyShapeStyle(DS.heroGradientSafe)
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
        return AnyShapeStyle(LinearGradient(colors: [base.opacity(0.86), base],
                                            startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    var baseLinkValue: String {
        let link = !bleReady ? "蓝牙未开启" : (connected ? "已连接就绪" : "未连接")
        switch state {
        case .idle: return link + (connected ? ", 可开锁" : ", 点击后自动唤醒门锁蓝牙")
        case .connecting, .opening: return link + ", 进行中"
        case .success: return "已成功打开门锁"
        case .doubleVerify: return "需要指纹或密码二次验证"
        case .failed(let msg): return msg
        }
    }
    var voHint: String {
        "轻点两下直接开锁， 无需按住. 转子上下滑可切换 状态/电量/连接 播报. "
            + "按住时长可自定 (0.4–1.6s, 设置-辅助)"
    }
}
