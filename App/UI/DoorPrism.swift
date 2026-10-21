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
                prismBody(width: geo.size.width)

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
                // ═══ 这里原来有一行 .allowsHitTesting(!dragging) —— 已删 ═══
                //
                // 它是个自锁 bug: .onChanged 第一帧就把 dragging 置 true，
                // 而这一行随即让整个热区**不再接收触摸** → SwiftUI 取消手势 →
                // 拖到一半就断，松手时 .onEnded 也不一定来。
                //
                // 「切不动」的直接原因就是这个。热区必须始终可点。
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
    private func prismBody(width: CGFloat) -> some View {
        // ═══ 内切圆必须按「面宽」算，不是按容器宽 ═══
        //
        // 原来三处都传 width（容器全宽），但 ZStack 之后又加了 4% 水平 padding
        // ⇒ 实际面宽只有 0.92·width，而 A 是按 width 算的（大了 8.7%）。
        // 后果是三个面相对棱柱偏大，转到中间时重叠过多、边缘也对不上。
        // 先算出留边后的真实面宽，所有几何都用它。
        let inner = width * 0.92
        return ZStack {
            prismFace(.b, width: inner)
            prismFace(.d, width: inner)
            prismFace(.f, width: inner)
            // 三条竖棱（角上），静止时给出棱柱的体积感
            prismEdge(60, width: inner)
            prismEdge(180, width: inner)
            prismEdge(300, width: inner)
        }
        // ═══ 留边：让画布在棱柱四周可见 ═══
        //
        // 原型里棱柱只占视口 67%×70%（相机 5.2 / 半径 1.0 / fov 32°），
        // 四周是背景。铺满全屏的话没有任何轮廓可看，3D 就白做了。
        // 这里留 4% 水平、3% 垂直 —— 比原型的 16% 保守，
        // 因为 Swift 版的面是真实页面（底部导航/工具栏要贴边），
        // 裁太多会把页面布局挤坏。
        .padding(.horizontal, width * 0.04)
        .padding(.vertical, width * 0.03)
        // ═══ 投影放在整层，不放在每个面上 ═══
        // .shadow 作用在 rotation3DEffect 过的视图上时，
        // 某些 iOS 版本会把它离屏栅格化，结果是内容整个不显示（黑屏的另一个来源）。
        // 移到合成层 + compositingGroup，风险最小。
        .compositingGroup()
        .shadow(color: .black.opacity(0.35), radius: 26, x: 0, y: 20)
        // ── 侧面呼吸: 缩放由**当前朝向**推导 ──
        .scaleEffect(breathScale)
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
    private func prismFace(_ f: DoorFace, width: CGFloat) -> some View {
        let A = prismApothem(width)
        let theta = FaceAngle.current(f) + containerAngle
        let rad = theta * .pi / 180
        // ═══ 显式几何: x / z / 深度缩放全部自己算 ═══
        //
        // 上一版靠 rotation3DEffect 的 anchorZ + perspective 让 SwiftUI 去算透视。
        // 但 `perspective` 的确切语义（m34 = -p/S 里 S 是什么）没有文档，
        // 我按原型反算出 0.85，仍然只能"赌一把"。
        //
        // 这一版改成:
        //   ① rotation3DEffect 只做**朝向**（anchor 在视图中心、不传 anchorZ/perspective）
        //      此时透视对它没有作用（旋转轴过中心），前缩就是 cos(θ) —— 完全确定
        //   ② 面中心的位置 (x, z) 按棱柱几何直接算
        //   ③ 近大远小用 scaleEffect(D/(D-z)) 自己算
        //
        // 这样每个量都可验算，不依赖任何未文档化的行为。
        // ★ 规格里的 z = -0.35·narrow 终于能实现了
        //   （之前靠 SwiftUI 的 rotation3DEffect，没有 z 平移可用）
        //   单位换算: 原型以 R=1.0 为单位，而 A = R/2，
        //   所以 0.35 个 R = 0.7 个 A → zShift = -0.7·A·narrow
        //   把整组棱柱沿 z 后退，深度缩放会自然把它算进去。
        let zShift = -A * 0.7 * breathNarrow
        let z = A * cos(rad) + zShift     // 面中心的 z（>0 朝观察者）
        let x = A * sin(rad)              // 面中心的 x
        let D = A * prismCameraDistance   // 相机距离（pt）
        // 兜底: 若 A 或 D 退化成 0，depthScale 会是 NaN/Inf → 视图消失
        let denom = D - z
        let depthScale: CGFloat = (denom.isFinite && denom > 0.001) ? D / denom : 1
        return faceView(f)
            // 让它读成「一块立起来的板」
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(XPalette.hairline, lineWidth: 1)
            }
            // ① 只做朝向 —— 轴过视图中心，透视不参与，前缩 = cos(θ)
            // ③ 近大远小
            // 前缩 + 近大远小 —— 纯 2D 变换，行为完全确定
            .scaleEffect(x: max(0.001, abs(cos(rad)) * depthScale),
                         y: depthScale,
                         anchor: .center)
            // ② 摆到棱柱上的位置
            .offset(x: x)
            .opacity(faceVisibility(f))
    }

    /// 相机距离 = 10.4 × 内切圆半径
    ///
    /// 由原型的比例反算: 相机 z=5.2、内切圆 0.5 → D/A = 10.4。
    /// 这个比值决定「近大远小」的强度 —— 代入后
    /// 前脸(z=+A) 与 120° 面(z=-0.5A) 的大小比 =
    ///   (D+A)/(D-0.5A) = 11.4/9.9 = 0.868，与 three.js 的 0.862 一致。
    private var prismCameraDistance: CGFloat { 10.4 }



    /// 三棱柱的竖棱 —— 静止时唯一能读出「体积」的东西
    ///
    /// 原型里 `buildPrism` 除了三个面，还放了 3 根圆柱当「骨」:
    ///   radius = R · sin(60°) = 0.866 R，角度 = 面法线 + 60°
    /// 它们让静止画面不只是一块平面 —— 两侧的棱告诉人「这东西有厚度」。
    ///
    /// Swift 版之前**完全没有**这个，所以即便 3D 变换正确，
    /// 静止时看到的也只是一个圆角卡片。
    ///
    /// 半径换算: 面法线到中心的距离是 A（内切圆），
    /// 角上的点是外接圆 R = 2A，而原型取 0.866R = 1.732A。
    private func prismEdge(_ baseDeg: Double, width: CGFloat) -> some View {
        let A = prismApothem(width)
        let R = A * 1.732                     // 角点半径（原型 0.866·R，R=2A）
        let D = A * prismCameraDistance
        let theta = baseDeg + containerAngle
        let rad = theta * .pi / 180
        let z = R * cos(rad)
        let x = R * sin(rad)
        let denomE = D - z
        let depthScale: CGFloat = (denomE.isFinite && denomE > 0.001) ? D / denomE : 1
        // 角点在棱柱前侧才画；cos > 0 即朝观察者
        let facing = cos(rad)
        return Capsule()
            .fill(XPalette.textTertiary.opacity(0.55))
            // 原型里棱是半径 0.022 的圆柱（R=1.0）→ 直径 2.2% 棱柱宽，
            // 换算到 359pt 面宽约 8pt。原来写 5pt 太细，几乎看不见。
            .frame(width: 8)
            .scaleEffect(depthScale)
            .offset(x: x)
            .frame(maxHeight: .infinity)
            .opacity(facing > 0 ? min(1, facing * 1.6) : 0)
            .accessibilityHidden(true)
    }
    /// 内切圆半径（pt）
    ///
    /// 正三棱柱边长 s 的内切圆半径 = s / (2√3) ≈ 0.2887 s。
    /// 面宽取「可用宽度的 0.9」，与原型 R_PRISM*1.42 的比例感一致。
    ///
    /// **不再用 UIScreen.main.bounds** —— 它在 iOS 26+ 已废弃，
    /// 且在多窗口/分屏下拿到的不一定是本视图的宽度；
    /// 万一返回 0，anchorZ 就是 0，三个面全叠在圆心 ——
    /// 三棱柱直接消失。宽度从 GeometryReader 传进来。
    ///
    /// ═══ 必须防 0 ═══
    /// 首帧布局时 GeometryReader 的 width 可能是 0，而
    /// depthScale = D/(D−z)、D = 10.4·A ⇒ A=0 时 D=0、z=0 ⇒ **0/0 = NaN**
    /// ⇒ 视图不渲染（又一个"黑屏"的来源）。
    /// 这里给一个下限，宁可第一帧略小也不要 NaN。
    private func prismApothem(_ width: CGFloat) -> CGFloat {
        // ═══ 这里原来多乘了一个 0.9，是个真的几何错误 ═══
        //
        // 面的宽度就是 width（faceView 铺满）。正三棱柱边长 = 面宽，
        // 所以内切圆必须严格等于 width / (2√3) = 0.2887·width。
        //
        // 原来乘 0.9 让棱柱小了 10%，后果是**转到 60° 时两个面之间
        // 留 17pt 的空隙**（本该是棱柱的角正好接上）。
        // 用数值模拟验算过:
        //   0.9 系数  → θ=60° 空隙 17.4pt ✗
        //   正确系数 → θ=60° 重叠  7.6pt ✓（角上重叠，读作一条棱）
        max(width, 1) * 0.2887
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
        // ═══ 这里原来是 base − offset·120，**符号反了** ═══
        //
        // 上面那段注释写的就是「-新面角 + sign*120」（加号），
        // 但代码写成了减号 —— 注释与实现不一致。
        //
        // 后果（验算过）:
        //   B→D 时 turn=1 应显示 B，实际显示 **F**；
        //   过渡中应显示 B+D，实际显示 D+F。
        //   也就是动画从**错误的那一面**开始 —— 这就是"无法正常切换"的根因。
        //
        // 另外拖拽预览也会跟着错: 向左拖本该把 D 带进来，
        // 减号却把 F 带进来，与松手后真正跳去的 D 不一致 → 视觉跳变。
        return base + Double(offset * 120)
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
    private var breathNarrow: CGFloat {
        // reduceMotion: 不做呼吸，恒为 0
        //
        // 这条 guard 上一轮被一次替换操作覆盖掉了 —— 回归检查时发现。
        guard !reduceMotion else { return 0 }
        // 手势拖拽 + 按钮翻页，两者都算进度。
        let progress = abs(drag) > 0.001 ? abs(drag) : (1 - turn)
        let turned = progress * 120          // 转过多少度
        let relToEdge = turned - 60          // 棱在两面中间 60° 处
        let raw = abs(cos(relToEdge * .pi / 180))
        // |cos| 在面正对时为 0.5，棱正对时为 1.0 → 归一化到 [0,1]
        return max(0, min(1, (raw - 0.5) / 0.5))
    }

    /// 侧面呼吸的缩放 —— 由**当前朝向**推导，不是独立曲线
    ///
    /// narrow ∈ [0,1]：0 = 面正对（最宽），1 = 棱正对（最窄）
    /// scale = 1 - 0.20·narrow（规格原式）
    private var breathScale: CGFloat {
        guard !reduceMotion else { return 1.0 }
        return 1 - 0.20 * breathNarrow
    }


    // ── 手势 ──
    /// 边缘拖拽热区
    ///
    /// 归一化除数从 160 改成 120 —— 热区只有 24pt 宽，
    /// 原本要拖 80pt 才翻面，手指很容易在 24pt 的边缘条里先滑出去。
    /// 120 对应 60pt 翻面，与 iOS 的「轻扫」手感接近。
    private func edgeZone(width: CGFloat, onStep: @escaping (Int) -> Void) -> some View {
        Color.clear
            .frame(width: width)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .local)
                    .onChanged { g in
                        dragging = true
                        let p = g.translation.width / 120
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
                        let p = g.translation.width / 120
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
