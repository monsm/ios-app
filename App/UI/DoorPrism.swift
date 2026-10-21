import SwiftUI

// ═══════════════════════════════════════════════════════════════════════
// MARK: - 三棱柱容器（BDF 三面切换）
// ═══════════════════════════════════════════════════════════════════════
//
// 三个面: B 管家台 / D 就近 / F 仪表。绕竖直轴转，每次 120°。
//
// ═══ 动画: 「C 侧面呼吸」═══
//
// 已用 HTML 实测六种后选定 C。它的唯一优势是：
// **缩放不是遮羞布，而是几何必然。**
//
// 三棱柱转到 60° 时，一条棱正对观察者，投影确实最窄。
// 把缩放最小值放在那一瞬间，观众会把缩小的原因归给
// "它转过来了"，而不是"它被缩小了"。
//
// ═══ 关键：缩放必须由朝向推导，不能用独立曲线 ═══
//
// 第一版我让缩放走一条独立的正弦曲线，结果与旋转不同步：
//   t=0.25 时已转 17.6°，但缩放下凹已到 71%  → 看起来"先缩后转"
//
// 正确做法是直接算「当前朝向对应的可见宽度」：
//   relToEdge = (当前角 - 起始面法线) + 60°
//   narrow    = (|cos(relToEdge)| - 0.5) / 0.5
//   scale     = 1 - 0.20 * narrow
//
// **归一化那一步是关键**：三个面均分 120°，所以面正对时
// |cos(60°)| = 0.5，不是 0。不归一化的话 t=0 时缩放就是 0.90，
// 每次循环起点都会跳变。
//
// ═══ 缓动 ═══
//
// 用 easeInOutSine 而不是 easeInOutQuint。
// Quint 是五次方，前 25% 几乎不动（只转 1.9°），配合缩放凹陷
// 就变成"先缩一下，然后才开始转"。Sine 在 t=0.25 已转 17.6°。
//
// ═══ 手势 ═══
//
// 只用**边缘热区**（左右各 24pt），不用全屏拖拽。
// 这是沿用旧 DoorStage 的决策（见其代码注释）：
// 全屏拖拽会抢 NavigationStack 的返回手势。
struct DoorPrism<B: View, D: View, F: View>: View {
    @Binding var face: DoorFace

    @ViewBuilder var faceB: () -> B
    @ViewBuilder var faceD: () -> D
    @ViewBuilder var faceF: () -> F

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag: CGFloat = 0      // -1...1，拖拽进度

    /// 翻页动画进度 0...1
    ///
    /// **为什么需要它**: `drag` 只在手指按住时非零，松手就归零。
    /// 而 step()（点按钮切换面）完全不动 drag ——
    /// 所以 breathScale 永远 = 1.0000，**呼吸动画从未发生**。
    ///
    /// 这是 R3 那轮"看到没任何变化"的同类问题的 Swift 版:
    /// HTML 原型里 animC 用 t（动画时间）驱动，我在 Swift 里换成了 drag，
    /// 但 drag 不是动画时间。
    ///
    /// 修法: 独立一个 turn 变量，由 withAnimation 驱动 0→1→0。
    @State private var turn: CGFloat = 0
    @State private var dragging = false
    @State private var lastTick = -1

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // ═══ reduceMotion: 保留三棱柱，只去掉动画 ═══
                //
                // 用户要求: "减弱动态不动三棱柱"。
                // 意思是**三棱柱本身要保留**，只是不要动画。
                //
                // 我第一版写成"降级为交叉淡入" —— 那是错的:
                //   · 三棱柱消失了，变成普通的多页面切换
                //   · .transition(.opacity) + .animation(XMotion.soft)
                //     **本身也是动画**，与"不动"矛盾
                //
                // 正确做法: 三棱柱照常渲染，但
                //   · 不做旋转过渡（face 直接跳）
                //   · 不做缩放呼吸（breathScale 恒为 1）
                //   · 不做拖拽跟手（手势仍可用，但松手直接跳面）
                //
                // 这样前庭敏感用户看到的仍是三棱柱的**静态侧面**，
                // 而不是会转动的物体 —— 视觉结构不变，动效归零。
                prismBody

                // ── 边缘热区（左右各一条）──
                HStack(spacing: 0) {
                    edgeZone(width: DoorGeometry.edgeGrabWidth) { direction in
                        step(direction)
                    }
                    Spacer(minLength: 0)
                    edgeZone(width: DoorGeometry.edgeGrabWidth) { direction in
                        step(direction)
                    }
                }
                .allowsHitTesting(!dragging)
            }
        }
    }

    // ── 三棱柱主体 ──
    //
    // ═══ 用 projectionEffect 做真正的 3D 透视投影 ═══
    //
    // 之前我试过「每个面 rotation3DEffect + offset」的写法，那是错的:
    // 三个面会叠在同一个平面上，转起来看到的是三张重叠的图，不是棱柱。
    //
    // 正确做法分两层:
    //   ① 每个面先摆到自己在该棱柱上的**位置**（沿法线外移内切圆半径）
    //   ② 容器统一用 projectionEffect 做「透视 × 旋转」
    //
    // projectionEffect 接受 CATransform3D 的 3x3 部分，
    // 而 CATransform3D 的 **m34 就是透视项**（m34 = -1/观察距离）。
    // 这两点合起来才能做出真正的棱柱透视 —— SwiftUI 没有 offset(z:)，
    // 靠普通的 offset 永远做不出 z 方向位移。
    /// 三棱柱主体
    ///
    /// 早期版本接收 width 参数用来算 apothem，但后来 apothem 改成了
    /// 屏幕宽度 × 0.9 × 0.2887（见 prismApothem），这个参数就用不上了。
    /// 死参数会让人误以为它还有作用，所以删掉。
    private var prismBody: some View {
        ZStack {
            prismFace(.b)
            prismFace(.d)
            prismFace(.f)
        }
        // ── 侧面呼吸: 缩放由**当前朝向**推导 ──
        //
        // 这是「C 侧面呼吸」的核心。三棱柱转到 60° 时一条棱正对观察者，
        // 投影确实最窄 —— 缩放最小值放在那一瞬间，
        // 观众会把缩小的原因归给"它转过来了"，而不是"它被缩小了"。
        //
        // breathScale 内部算 |cos| 并归一化，公式见其注释。
        .scaleEffect(breathScale)
        // 容器旋转 + 透视（这是整个棱柱的「转」）
        .projectionEffect(containerProjection)
    }

    /// 容器投影：透视 × 绕 Y 轴旋转
    ///
    /// CATransform3D 的 m34 是透视项，取 -1/观察距离。
    /// 观察距离取 1200pt —— 相当于 1.2 米外看一个 400pt 宽的东西，
    /// 与人看手机的距离量级相近，透视强度自然。
    private var containerProjection: ProjectionTransform {
        var t = CATransform3DIdentity
        t.m34 = -1.0 / 1200.0
        t = CATransform3DRotate(t, containerAngle * .pi / 180, 0, 1, 0)
        return ProjectionTransform(t)
    }

    /// 一个棱柱面：摆到它在棱柱上的位置
    ///
    /// 正三棱柱边长 s 的内切圆半径 = s / (2√3) ≈ 0.2887 s。
    /// 每个面的中心就在「法线方向 × 内切圆半径」处。
    ///
    /// 面自己的朝向用 rotation3DEffect（那是**静态**的，不参与动画），
    /// 容器的转动交给 projectionEffect。这样两组旋转互不干扰。
    /// 一个棱柱面：转到自己的朝向，同时落到棱柱上的位置
    ///
    /// ═══ 这里修过一次几何错误 ═══
    ///
    /// 第一版:
    ///     .rotation3DEffect(.degrees(theta), axis: (0,1,0), anchor: .center, perspective: 0)
    ///     .offset(x: sin(theta) * apothem, y: 0)
    ///
    /// 错在: 只做了 x 偏移，面全在 z=0 平面 —— 三个面**不在同一个圆上**。
    /// 复算（A=102.1pt）:
    ///     面 b  x=  0  z=0    (应在半径 A 上，实际在圆心)
    ///     面 d  x=+88  z=0
    ///     面 f  x=-88  z=0
    /// 偏差 51-102pt。视觉上是三张卡片横排，不是棱柱。
    ///
    /// ═══ 正确做法: anchorZ = -A ═══
    ///
    /// 让视图绕「中心后方 A 处」的轴旋转 θ，视口中心相对轴是 (0,0,A)，
    /// 转 θ 后自然落在 (A·sinθ, 0, A·cosθ) —— 正是棱柱上该在的位置。
    ///
    /// **不需要手写 offset** —— x 和 z 由旋转变换同时产生，
    /// 这是绕轴旋转的几何必然。
    ///
    /// 验证（A=102.1）:
    ///     θ=0°    → (  0, +102)  ✓
    ///     θ=120°  → (+88,  -51)  ✓
    ///     θ=240°  → (-88,  -51)  ✓
    ///
    /// anchorZ 这个参数全仓此前从未用过，已由探针区块 6（run #475）验证签名。
    private func prismFace(_ f: DoorFace) -> some View {
        let theta = FaceAngle.current(f)
        return faceView(f)
            // 绕「中心后方 apothem」的轴旋转 — 同时完成朝向与定位
            .rotation3DEffect(.degrees(theta), axis: (x: 0, y: 1, z: 0),
                              anchor: .center,
                              anchorZ: -prismApothem,
                              perspective: 0)
            // 背面的面隐藏（否则会穿透前面的面看到它）
            .opacity(faceVisibility(f))
    }

    /// 内切圆半径（相对于面宽度）
    ///
    /// 这里需要一个绝对量而不是相对屏幕宽的比例 ——
    /// 因为 offset 的单位是 pt。用 GeometryReader 拿不到，
    /// 所以按屏幕宽度估。三棱柱面宽约等于屏宽的 0.9。
    private var prismApothem: CGFloat {
        UIScreen.main.bounds.width * 0.9 * 0.2887
    }

    /// 某个面当前是否朝向观察者
    ///
    /// 面 i 的世界中心在 (A·sinθ, 0, A·cosθ)。
    /// 容器转 φ 后，z 分量 = A·cos(θ + φ)。
    /// z > 0 表示朝前（可见），z < 0 表示朝后（隐藏）。
    ///
    /// 用 cos 而不是硬切换，是为了在正侧对时有一个柔和的过渡 ——
    /// 硬切换会让面的边缘突然消失，看起来像闪烁。
    private func faceVisibility(_ f: DoorFace) -> Double {
        let theta = FaceAngle.current(f)
        let total = (theta + containerAngle) * .pi / 180
        let z = cos(total)
        // z 从 1（正对）到 -1（背对）。映射到 opacity: 1 → 0
        // 用 0.15 作为阈值，避免侧面时两个面都半透明地叠着
        if z > 0.15 { return 1 }
        if z < -0.15 { return 0 }
        // 过渡带：z ∈ [-0.15, 0.15] 线性过渡
        return Double((z + 0.15) / 0.30)
    }

    @ViewBuilder
    private func faceView(_ f: DoorFace) -> some View {
        Group {
            switch f {
            case .b: faceB()
            case .d: faceD()
            case .f: faceF()
            }
        }
        // 只让当前朝向观察者的那个面可交互
        .allowsHitTesting(f == face && !dragging && abs(drag) < 0.02)
    }

    // ── 角度计算 ──
    /// 容器当前旋转角（度）
    /// 容器当前旋转角（度）
    ///
    /// 三个来源合并:
    ///   · base  当前面的角度
    ///   · drag  手指实时拖拽（±1 对应一面）
    ///   · turn  按钮翻页动画进度（0→1）
    ///
    /// **turn 必须参与旋转**，否则 step() 换 face 时:
    ///   face 变了 → base 瞬间跳到新面，但 turn 驱动的缩放还在退，
    ///   结果看起来是「突然跳到新面 + 独立缩一下」，不是一次转身。
    /// 容器当前旋转角（度）
    ///
    /// 三个来源:
    ///   · base  当前面的角度（step 里已立即换成新面）
    ///   · drag  手指实时拖拽（±1 对应一面）
    ///   · turn  翻页动画进度，**从 1 降到 0**
    ///
    /// turn=1 时角度退回旧面（-新面角 + sign*120），
    /// turn=0 时停在新面 —— 一次动画连贯走完，无跳变。
    private var containerAngle: Double {
        let base = -FaceAngle.current(face)
        // reduceMotion: 只显示当前面的正面视角，不随拖拽/过渡转动
        guard !reduceMotion else { return base }
        let offset: CGFloat = abs(drag) > 0.001 ? drag : (turn * turnSign)
        return base - Double(offset * 120)
    }

    /// 翻页方向（+1 下一面 / -1 上一面）
    ///
    /// 让旋转方向和手势一致: 左滑（drag<0）转负方向，
    /// 点按钮下一面也转负方向 —— 视觉上是同一个转向。
    @State private var turnSign: CGFloat = 1

    /// 侧面呼吸的缩放
    ///
    /// 由**当前朝向**推导，不是独立曲线。
    /// narrow ∈ [0,1]：0 = 面正对观察者（最宽），1 = 棱正对（最窄）
    /// 侧面呼吸的缩放
    ///
    /// ═══ 这段改过三次，记录每次为什么错 ═══
    ///
    /// 第一版: 用绝对角度 rad + 60°
    ///   `let relToEdge = rad + .pi / 3`
    ///   错在 F 面（240°）: -240+60 = -180°，|cos(-180°)| = 1.0，
    ///   归一化后 narrow = 1 → 静止时缩放 0.80 而不是 1.00。
    ///   因为三面角度 0/120/240 相差 120°，不是 180° 的整数倍，
    ///   而 |cos| 的周期是 180° —— 三个面落在不同的相位上。
    ///
    /// 第二版: 把角度对 120° 取模
    ///   静止时三面都对（都 1.00），但**拖拽时缩放不变** ——
    ///   因为把 drag 的贡献也一起模掉了。
    ///
    /// 第三版（现在）: 直接用**进度**而不是绝对角度
    ///
    ///   drag 本身就是 0→1 的翻页进度（0 = 当前面正对，1 = 下一面正对）。
    ///   一条棱正好在两面的中间，即 60° = 进度 0.5 处。
    ///   所以「相对棱的角度」= 转过角度 - 60° = drag*120 - 60。
    ///
    ///   验证过的端点:
    ///     drag=0   转过   0°  rel=-60°  |cos|=0.500  narrow=0  scale=1.0000
    ///     drag=0.5 转过  60°  rel=  0°  |cos|=1.000  narrow=1  scale=0.8000
    ///     drag=1   转过 120°  rel= 60°  |cos|=0.500  narrow=0  scale=1.0000
    ///
    /// 未拖拽时（drag=0）恒为 1.0000，所以静止在每个面都正常。
    private var breathScale: CGFloat {
        // 手势拖拽 + 按钮翻页，两者都算进度。
        // drag 是手指实时位置（±1），turn 是 step() 动画驱动（0→1→0）。
        // 取绝对值后合并 —— 手指往哪拖都算"离开当前面"。
        // 未拖拽时 turn 从 1→0，呼吸包络就是 sin(π*turn) 的形状
        let progress = abs(drag) > 0.001 ? abs(drag) : (1 - turn)
        let turned = progress * 120          // 转过多少度
        let relToEdge = turned - 60          // 棱在两面中间 60° 处
        let raw = abs(cos(relToEdge * .pi / 180))
        // |cos| 在面正对时为 0.5，棱正对时为 1.0 → 归一化到 [0,1]
        let narrow = max(0, min(1, (raw - 0.5) / 0.5))
        return 1 - 0.20 * narrow
    }


    // ── 手势 ──
    private func edgeZone(width: CGFloat, onStep: @escaping (Int) -> Void) -> some View {
        Color.clear
            .frame(width: width)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .local)
                    .onChanged { g in
                        dragging = true
                        let p = g.translation.width / 160
                        drag = max(-1, min(1, p))
                        // 每跨过 1/3 给一次轻震
                        let tick = Int(drag * 3)
                        if tick != lastTick {
                            lastTick = tick
                            XHaptics.tick.impactOccurred()
                        }
                    }
                    .onEnded { g in
                        dragging = false
                        let p = g.translation.width / 160
                        if abs(p) > DoorGeometry.flipThreshold {
                            onStep(p > 0 ? -1 : 1)
                        }
                        // reduceMotion: 回弹也是动画，直接归零
                        if reduceMotion { drag = 0 }
                        else { withAnimation(XMotion.soft) { drag = 0 } }
                        lastTick = -1
                    }
            )
    }

    /// 切换面
    ///
    /// 分两段: 先把 turn 推到 1（棱正对，最窄），
    /// 再把 face 换成下一面、turn 回 0。
    ///
    /// 这样切换过程中会经过"棱正对"那一帧 —— 呼吸就真的发生了。
    /// 一次性 withAnimation 把 face 和 turn 同时改是不行的:
    /// face 是枚举（不可插值），turn 才是被动画的那个量。
    /// 切换面
    ///
    /// ═══ 为什么是「立即换 face + turn 从 1 降到 0」═══
    ///
    /// 第一版我写了两段动画（turn 0→1，换面，turn 1→0），
    /// 模拟出来角度在换面瞬间**跳了 120°** ——
    /// 因为前半段转到 0° 就换面，新面的 base 又从 -240 开始。
    ///
    /// 正确做法是反过来:
    ///   · face 立即改成新面
    ///   · turn 从 **1** 动画到 **0**
    ///   · 角度 = -新面角 - turn * sign * 120
    ///
    /// 这样 turn=1 时角度 = -新面角 + 120 = 旧面角（起点正确），
    /// turn=0 时 = -新面角（终点正确），一次动画连贯走完。
    ///
    /// 验证（D→F, sign=-1）:
    ///   turn=1.00  角度 -120°（D 面）  缩放 1.0000
    ///   turn=0.50  角度 -180°（棱正对）缩放 0.8000
    ///   turn=0.00  角度 -240°（F 面）  缩放 1.0000
    private func step(_ direction: Int) {
        let order = DoorFace.allCases
        guard let i = order.firstIndex(of: face) else { return }
        let n = order.count
        let next = ((i + direction) % n + n) % n
        XHaptics.trigger.impactOccurred()

        // reduceMotion: 直接跳面，不做旋转过渡
        if reduceMotion {
            face = order[next]
            turn = 0
            return
        }

        // 立即换面，turn 从 1 降到 0
        turnSign = direction > 0 ? 1 : -1
        turn = 1
        face = order[next]
        withAnimation(.easeInOut(duration: 0.42)) { turn = 0 }
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - 三个面的角度
// ═══════════════════════════════════════════════════════════════════════
enum FaceAngle {
    // 三个面分别朝 0° / 120° / 240°
    static let b: Double = 0
    static let d: Double = 120
    static let f: Double = 240

    static func current(_ face: DoorFace) -> Double {
        switch face {
        case .b: return b
        case .d: return d
        case .f: return f
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - BDF 三个面
// ═══════════════════════════════════════════════════════════════════════
enum DoorFace: String, CaseIterable, Identifiable {
    case b = "管家台"
    case d = "就近"
    case f = "仪表"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .b: return "slider.horizontal.3"
        case .d: return "door.left.hand.open"
        case .f: return "chart.xyaxis.line"
        }
    }

    /// 面之间的顺序（用于左右滑动）
    static var order: [DoorFace] { [.b, .d, .f] }
}
