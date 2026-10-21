import SwiftUI
import RealityKit
import simd

// ═══════════════════════════════════════════════════════════════════════
// MARK: - 刃 · 视图层
// ═══════════════════════════════════════════════════════════════════════
//
// 60 × 300 mm 非对称锁体。左缘一根直线，右缘一段 R500 的外凸弧 ——
// 整块体的形，只有这一道弧。剩下都收进 22 mm 的厚度里：
// 一圈压边、一道竖向分缝、一处指腹的凹陷。
//
// 九个零件（与 d-blade.js 一一对应）:
//   1 主锁体      22mm 厚平板, 前后各一道倒角
//   2 背面胶垫    内缩 6mm, 边缘留 1.4mm 落影
//   3 压边左条    守住直线边的窄面
//   4 压边右板    跟着 R500 走的大面, 与左条之间留 0.7mm 分缝
//   5 品牌压线    0.34mm 宽, 沉在缝底, 比压边面低 0.3
//   6 指纹槽口    一圈 0.95mm 高的边, 顶面倒角压进碟里
//   7 指腹浅碟    哑黑内衬, 一路收进 1.13mm 深的碟底
//   8 传感器钢托  椭圆, 压在碟底, 只露一圈 0.9mm 的边
//   9 传感器镜片  比钢托小 0.95, 沉下去, 一圈暗缝
//
// 状态着色: accent(压线) / sensor(镜片) —— 都有 highlight 引用。
// mover = null (刃没有可转动的零件, 反锁靠压线变色表达)
struct XLockBlade: View {
    var isOpen: Bool
    var isFailed: Bool
    var isDeadbolted: Bool
    var charge: CGFloat
    var diameter: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 状态色
    private var tint: UIColor {
        if isFailed { return UIColor(XPalette.danger) }
        if isOpen { return UIColor(XPalette.ok) }
        if isDeadbolted { return UIColor(XPalette.warn) }
        return UIColor(XPalette.accent)
    }

    var body: some View {
        RealityView { content in
            let root = Entity()
            root.name = "bladeRoot"
            if let built = try? buildBlade() {
                root.addChild(built)
            }
            content.add(root)
            content.camera = .virtual
        } update: { content in
            guard let root = content.entities.first(where: { $0.name == "bladeRoot" }) else { return }
            applyState(to: root)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // ── 组装 ──────────────────────────────────────────────────────

    private func buildBlade() throws -> Entity {
        let g = Entity()
        g.name = "blade"
        // 建模用 mm，缩到场景
        g.scale = .init(repeating: 0.01)

        // 用 typealias 而不是 let G = X.self ——
        // 后者拿到的是元类型实例，G.P3 这种嵌套类型访问不到。
        typealias G = BladeGeometry
        let depth = G.depth

        // 1 主锁体
        let bodyTris = G.slabTriangles(G.bladeOutline(inset: 0),
                                       zBack: -depth, zFront: 0,
                                       chBack: 1.1, chFront: 1.7)
        try add(g, tris: bodyTris, name: "body",
                color: Self.alu, metallic: true, roughness: 0.32)

        // 2 背面胶垫
        let padTris = G.slabTriangles(G.bladeOutline(inset: 6),
                                      zBack: -depth - 2.6, zFront: -depth + 1.4,
                                      chBack: 0.8, chFront: 0)
        try add(g, tris: padTris, name: "backPad",
                color: Self.dark, metallic: false, roughness: 0.62)

        // 3 压边左条
        let deckLTris = G.slabTriangles(G.deckLeftPolygon(),
                                        zBack: -1.0, zFront: 1.0,
                                        chBack: 0.3, chFront: 0.45)
        try add(g, tris: deckLTris, name: "deckL",
                color: Self.alu, metallic: true, roughness: 0.32)

        // 4 压边右板
        let deckRTris = G.slabTriangles(G.deckRightPolygon(),
                                        zBack: -1.0, zFront: 1.0,
                                        chBack: 0.3, chFront: 0.45)
        try add(g, tris: deckRTris, name: "deckR",
                color: Self.alu, metallic: true, roughness: 0.32)

        // 5 品牌压线（唯一有颜色的零件 —— 状态色打在这里）
        let accentTris: [G.P3] = {
            let hw: Float = 0.17, hh: Float = 126, z0: Float = 0.44, t: Float = 0.52
            var out = [G.P3]()
            func quad(_ a: G.P3, _ b: G.P3, _ c: G.P3, _ d: G.P3) {
                out.append(a); out.append(b); out.append(c)
                out.append(a); out.append(c); out.append(d)
            }
            let x0 = G.seamX - hw, x1 = G.seamX + hw
            // 正面
            quad(G.P3(x: x0, y: -hh, z: z0 + t), G.P3(x: x1, y: -hh, z: z0 + t),
                 G.P3(x: x1, y: hh, z: z0 + t), G.P3(x: x0, y: hh, z: z0 + t))
            // 四面侧壁
            quad(G.P3(x: x0, y: -hh, z: z0), G.P3(x: x1, y: -hh, z: z0),
                 G.P3(x: x1, y: -hh, z: z0 + t), G.P3(x: x0, y: -hh, z: z0 + t))
            quad(G.P3(x: x0, y: hh, z: z0 + t), G.P3(x: x1, y: hh, z: z0 + t),
                 G.P3(x: x1, y: hh, z: z0), G.P3(x: x0, y: hh, z: z0))
            quad(G.P3(x: x0, y: -hh, z: z0), G.P3(x: x0, y: hh, z: z0),
                 G.P3(x: x0, y: hh, z: z0 + t), G.P3(x: x0, y: -hh, z: z0 + t))
            quad(G.P3(x: x1, y: -hh, z: z0 + t), G.P3(x: x1, y: hh, z: z0 + t),
                 G.P3(x: x1, y: hh, z: z0), G.P3(x: x1, y: -hh, z: z0))
            return out
        }()
        try add(g, tris: accentTris, name: "accent",
                color: Self.orange, metallic: true, roughness: 0.34, emissive: 0.40)

        // 6 指纹槽口
        let rimRings: [(Float, Float)] = [
            (1.000, 0.78), (1.000, 1.95), (0.995, 2.02), (0.985, 2.05),
            (0.900, 2.05), (0.870, 1.98), (0.870, 1.92),
        ]
        let rimTris = G.funnelTriangles(
            rimRings.map { (pts: G.superRing(a: 11, b: 26, n: 2.8, scale: $0.0, segments: 64),
                           z: $0.1) },
            floorZ: nil
        ).map { G.P3(x: $0.x + 3, y: $0.y + 56, z: $0.z) }
        try add(g, tris: rimTris, name: "podRim",
                color: Self.alu, metallic: true, roughness: 0.32)

        // 7 指腹浅碟
        let wellRings: [(Float, Float)] = [
            (0.870, 1.92), (0.830, 1.62), (0.770, 1.40),
            (0.660, 1.24), (0.560, 1.155), (0.520, 1.140),
        ]
        let wellTris = G.funnelTriangles(
            wellRings.map { (pts: G.superRing(a: 11, b: 26, n: 2.8, scale: $0.0, segments: 64),
                            z: $0.1) },
            floorZ: 1.13
        ).map { G.P3(x: $0.x + 3, y: $0.y + 56, z: $0.z) }
        try add(g, tris: wellTris, name: "podWell",
                color: Self.dark, metallic: false, roughness: 0.62)

        // 8 传感器钢托（椭圆：圆柱 X 拉伸 + Y 放大 1.30）
        // generateCylinder 没有段数参数（CI 报 extra argument 'radialSegments'）
        let baseMesh = MeshResource.generateCylinder(height: 0.36, radius: 4.6)
        let base = ModelEntity(mesh: baseMesh,
                               materials: [BladeMesh.material(color: Self.steel, metallic: true, roughness: 0.18)])
        base.name = "sensorBase"
        base.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        base.scale = SIMD3<Float>(1, 1.30, 1)
        base.position = SIMD3<Float>(3, 56, 1.28)
        g.addChild(base)

        // 9 传感器镜片（状态色打这里）
        let lensMesh = MeshResource.generateCylinder(height: 0.20, radius: 3.55)
        let lensMat = BladeMesh.material(color: Self.dark, metallic: false, roughness: 0.10)
        let lens = ModelEntity(mesh: lensMesh, materials: [lensMat])
        lens.name = "sensor"
        lens.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        lens.scale = SIMD3<Float>(1, 1.34, 1)
        lens.position = SIMD3<Float>(3, 56, 1.55)
        g.addChild(lens)

        return g
    }

    private func add(_ parent: Entity, tris: [BladeGeometry.P3], name: String,
                     color: UIColor, metallic: Bool, roughness: Float,
                     emissive: Float = 0) throws {
        guard let mesh = try BladeMesh.build(from: tris) else { return }
        // SimpleMaterial 没有 emissiveColor（CI 报 no member 'emissiveColor'）。
        // 自发光的视觉效果改由「颜色本身更亮」近似 —— 见 brighten() 的说明。
        let c = emissive > 0 ? BladeGeometry.brighten(color, by: emissive) : color
        let mat = BladeMesh.material(color: c, metallic: metallic, roughness: roughness)
        let e = ModelEntity(mesh: mesh, materials: [mat])
        e.name = name
        parent.addChild(e)
    }

    // ── 状态着色 ──────────────────────────────────────────────────

    // SimpleMaterial 没有 emissiveColor，所以"发光"用**更亮的颜色**近似。
    // 这不是真正的自发光（暗环境下不会自己亮），但在深色 UI 里视觉差别不大。
    // 若以后真要发光，得换 PhysicallyBasedMaterial —— 那是另一个 API 面，需再探针一次。
    private func applyState(to root: Entity) {
        let t = tint
        if let accent = root.findEntity(named: "accent") as? ModelEntity {
            var m = SimpleMaterial(color: t, isMetallic: true)
            m.roughness = .float(0.34)
            accent.model?.materials = [m]
        }
        if let sensor = root.findEntity(named: "sensor") as? ModelEntity {
            let base = isFailed ? UIColor(XPalette.danger) : Self.dark
            let c = charge > 0.01 ? BladeGeometry.brighten(t, by: 0.55) : base
            var m = SimpleMaterial(color: c, isMetallic: false)
            m.roughness = .float(0.10)
            sensor.model?.materials = [m]
        }
    }

    private var accessibilityText: String {
        var s = isFailed ? "锁体, 操作失败" : (isOpen ? "锁体, 已开" : "锁体, 已锁")
        if isDeadbolted { s += ", 门从里面反锁" }
        if charge > 0.01 { s += ", 充能 \(Int(charge * 100))%" }
        return s
    }

    // ── 材质色（mm 量级，与 d-blade.js 一致）───────────────────────
    private static let alu    = UIColor(red: 0.204, green: 0.220, blue: 0.243, alpha: 1)  // 0x34383e
    private static let dark   = UIColor(red: 0.047, green: 0.055, blue: 0.067, alpha: 1)  // 0x0c0e11
    private static let steel  = UIColor(red: 0.788, green: 0.808, blue: 0.831, alpha: 1)  // 0xc9ced4
    private static let orange = UIColor(red: 0.910, green: 0.392, blue: 0.173, alpha: 1)  // 0xe8642c
}
