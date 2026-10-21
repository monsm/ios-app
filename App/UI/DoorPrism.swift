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
    @State private var dragging = false
    @State private var lastTick = -1

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if reduceMotion {
                    // ── 降级: 不做 3D，只交叉淡入 ──
                    // 前庭敏感用户依赖这条路径，行为必须完整可用
                    Group {
                        switch face {
                        case .b: faceB()
                        case .d: faceD()
                        case .f: faceF()
                        }
                    }
                    .transition(.opacity)
                    .animation(XMotion.soft, value: face)
                } else {
                    prismBody(width: geo.size.width)
                }

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
    private func prismBody(width: CGFloat) -> some View {
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
    private func prismFace(_ f: DoorFace) -> some View {
        let theta = FaceAngle.current(f)
        let rad = theta * .pi / 180
        return faceView(f)
            // ① 转到自己的朝向（静态）
            .rotation3DEffect(.degrees(theta), axis: (0, 1, 0),
                              anchor: .center, perspective: 0)
            // ② 外移到棱柱上的位置
            .offset(x: sin(rad) * prismApothem, y: 0)
            // ③ 背面的面隐藏（否则会穿透前面的面看到它）
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
    private var containerAngle: Double {
        let base = -FaceAngle.current(face)
        // 拖拽时叠加偏移：每 1.0 的 drag 对应一整面（120°）
        return base - (drag * 120)
    }

    /// 侧面呼吸的缩放
    ///
    /// 由**当前朝向**推导，不是独立曲线。
    /// narrow ∈ [0,1]：0 = 面正对观察者（最宽），1 = 棱正对（最窄）
    private var breathScale: CGFloat {
        let rad = containerAngle * .pi / 180
        // 起始面法线方向即 base 角；棱相对面法线偏 +60°
        let relToEdge = rad + .pi / 3
        // |cos| 在面正对时 = 0.5（三面均分 120°，相邻棱在 ±60°），
        // 在棱正对时 = 1.0。归一化到 [0,1]。
        let raw = abs(cos(relToEdge))
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
                        withAnimation(XMotion.soft) { drag = 0 }
                        lastTick = -1
                    }
            )
    }

    private func step(_ direction: Int) {
        let order = DoorFace.allCases
        guard let i = order.firstIndex(of: face) else { return }
        let n = order.count
        let next = ((i + direction) % n + n) % n
        withAnimation(XMotion.doorSwing) {
            face = order[next]
        }
        XHaptics.trigger.impactOccurred()
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
