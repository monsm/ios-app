import SwiftUI
import RealityKit

// ═══════════════════════════════════════════════════════════════════════
// MARK: - XLockBody3D — 真实锁体 (RealityKit)
// ═══════════════════════════════════════════════════════════════════════
//
// 为什么是 3D:
//   首屏那块锁面原来是一层层 SwiftUI 叠出来的 2D 圆环。
//   圆环能表达"充能进度", 但表达不了"这是一块有厚度的金属"。
//   用户每天看它一次, 它该是有实体的。
//
// ═══ 设计纪律 (先读这段再看代码) ═══
//
// 协议**没有门磁** (CAPABILITY §5 / DoorFront.swift:12 原注释):
//   App 永远不知道门现在是开是关。
// 所以这个 3D 体表现的是**锁体本身**, 不是"你家的门":
//   · 面板 / 转轴 / 键位环 —— 这些是锁的零件, 客观存在
//   · 不做"门扇开合" —— 那会暗示 App 知道门的状态, 是撒谎
//
// 可信的状态来源只有 StatusParser.rcMsg 里那几个物理码:
//   rc21 反锁 / rc26 被撬 / rc27 布防 / rc20+rc23 指纹头异常
// 本组件只映射 rc21 (反锁) —— 它对应转轴的真实物理位置。
//
// ═══ 已验证的 API (探针 run #417 SUCCESS) ═══
//   RealityView { content in } update: { content in }
//   MeshResource.generateCylinder(height:radius:)
//   ModelEntity(mesh:materials:) / SimpleMaterial(color:isMetallic:)
//   content.camera = .virtual
// 同批探针还证明了 **Model3D 在 iOS 不可用** (run #416), 所以只有这条路。
struct XLockBody3D: View {
    /// 充能进度 0...1 (按住开锁时从 0 长到 1)
    var charge: CGFloat
    /// 已开 (开锁成功瞬间)
    var isOpen: Bool
    /// 失败 (抖动 + 红色)
    var isFailed: Bool
    /// 门从里面反锁了 (rc21) —— 转轴转到锁定位
    var isDeadbolted: Bool
    /// 直径
    var diameter: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 转轴当前角度: 反锁 90° / 常态 0°
    private var boltAngle: Float { isDeadbolted ? .pi / 2 : 0 }

    /// 面板主色 —— 吃 XPalette 令牌, 与全 App 一致
    private var plateTone: UIColor {
        let c: Color = isFailed ? XPalette.danger : (isOpen ? XPalette.ok : XPalette.accent)
        return UIColor(c)
    }

    var body: some View {
        RealityView { content in
            let root = Entity()
            root.name = "lockBody"
            content.add(root)

            // ── 1. 底盘: 一枚扁圆柱, 给锁体实际厚度 ──
            //     radius 0.5 对应视觉直径, height 0.12 是"面板厚度"
            let baseMesh = MeshResource.generateCylinder(height: 0.12, radius: 0.5)
            var baseMat = SimpleMaterial(color: UIColor(XPalette.surfaceSunken), isMetallic: true)
            baseMat.roughness = .float(0.35)
            let base = ModelEntity(mesh: baseMesh, materials: [baseMat])
            base.name = "base"
            // 圆柱默认竖着, 转 90° 让圆面朝向相机
            base.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            root.addChild(base)

            // ── 2. 金属外环: 比底盘的稍大一圈 ──
            let ringMesh = MeshResource.generateCylinder(height: 0.14, radius: 0.54)
            var ringMat = SimpleMaterial(color: UIColor(XPalette.accent), isMetallic: true)
            ringMat.roughness = .float(0.22)
            let ring = ModelEntity(mesh: ringMesh, materials: [ringMat])
            ring.name = "ring"
            ring.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            ring.position = [0, 0, -0.02]
            root.addChild(ring)

            // ── 3. 中心转轴: 反锁时转到 90° ──
            let hubMesh = MeshResource.generateCylinder(height: 0.20, radius: 0.16)
            var hubMat = SimpleMaterial(color: UIColor(XPalette.textSub), isMetallic: true)
            hubMat.roughness = .float(0.30)
            let hub = ModelEntity(mesh: hubMesh, materials: [hubMat])
            hub.name = "hub"
            hub.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            hub.position = [0, 0, 0.06]
            root.addChild(hub)

            // ── 4. 相机: 略高于水平, 让厚度可见 (纯正视看不到圆柱侧面) ──
            content.camera = .virtual

            root.orientation = simd_quatf(angle: -0.18, axis: [1, 0, 0])
        } update: { content in
            // 状态变化时只改材质色与转轴角度 —— 不重建几何体
            guard let root = content.entities.first(where: { $0.name == "lockBody" }) else { return }
            if let ring = root.findEntity(named: "ring"),
               var m = ring.components[ModelComponent.self] {
                var mat = SimpleMaterial(color: plateTone, isMetallic: true)
                mat.roughness = .float(isFailed ? 0.55 : 0.22)
                m.materials = [mat]
                ring.components.set(m)
            }
            if let hub = root.findEntity(named: "hub") {
                let target = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
                    * simd_quatf(angle: boltAngle, axis: [0, 1, 0])
                if reduceMotion {
                    hub.orientation = target
                } else {
                    hub.move(to: Transform(rotation: target), relativeTo: hub.parent, duration: 0.45, timingFunction: .easeInOut)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        // 无障碍: 3D 内容 VoiceOver 读不到, 语义全靠这一层
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var s = isFailed ? "锁体, 操作失败" : (isOpen ? "锁体, 已开" : "锁体, 已锁")
        if isDeadbolted { s += ", 门从里面反锁" }
        if charge > 0.01 { s += ", 充能 \(Int(charge * 100))%" }
        return s
    }
}