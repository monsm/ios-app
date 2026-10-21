import SwiftUI
import RealityKit

// ═══════════════════════════════════════════════════════════════════
// APIPROBE v3 — MeshResource 的几何生成家族 (拿到签名就删)
// ═══════════════════════════════════════════════════════════════════
//
// 已知 (探针 v2 / run #417 SUCCESS):
//   MeshResource.generateCylinder(height:radius:)
//   ModelEntity(mesh:materials:) / SimpleMaterial(color:isMetallic:)
//   RealityView { content in } update: { content in }
//
// 本轮要确认的是:**不用 usdz 文件, 纯代码能不能拼出一个精细锁体。**
// 如果能, 方案 B ("真 3D 精美锁") 就不依赖任何外部资源 ——
// 这正好对应用户说的"不用在意品牌型号, 只要一个精美精致的锁"。
//
// 要验证:
//   generateBox(size:cornerRadius:)      键位 / 面板
//   generateSphere(radius:)              螺钉头
//   generateTorus(...)                   指纹头外环 (可能存在也可能没有)
//   generateCone(height:radius:)         倒角
//   generatePlane(width:depth:)          垫片
//   MeshDescriptor                       兜底: 手搓几何
//   MeshResource.generate(from:)         从 descriptor 生成
@available(iOS 18.0, *)
enum MeshGenProbe {
    static func probe() {
        // 1. 盒 (键位/面板)
        _ = MeshResource.generateBox(size: 0.1)
        _ = MeshResource.generateBox(size: [0.1, 0.08, 0.02], cornerRadius: 0.008)
        _ = MeshResource.generateBox(width: 0.09, height: 0.08, depth: 0.02, cornerRadius: 0.006)

        // 2. 球 (螺钉头)
        _ = MeshResource.generateSphere(radius: 0.02)

        // 3. 圆柱 (已知可用, 再验一次带 segments 的重载)
        _ = MeshResource.generateCylinder(height: 0.02, radius: 0.03, radialSegments: 24)

        // 4. 圆锥 (倒角/斜切)
        _ = MeshResource.generateCone(height: 0.01, radius: 0.05)

        // 5. 平面 (垫片)
        _ = MeshResource.generatePlane(width: 0.1, depth: 0.1)

        // 6. Torus —— 指纹头外环最自然的形状。RealityKit 可能没有这个静态方法,
        //    没有的话就用 generateCylinder 套一个细环代替 (见下方 fallback 注释)
        // _ = MeshResource.generateTorus(majorRadius: 0.1, minorRadius: 0.01)
    }

    // 7. 手搓几何的入口 (如果静态方法不够用)
    static func customMesh() -> MeshResource? {
        var desc = MeshDescriptor(name: "probe")
        let positions: [SIMD3<Float>] = [
            [-0.5, -0.5, 0], [0.5, -0.5, 0], [0.5, 0.5, 0], [-0.5, 0.5, 0]
        ]
        desc.positions = MeshBuffer(positions)
        desc.primitives = .triangles([0, 1, 2, 0, 2, 3])
        return try? MeshResource.generate(from: [desc])
    }

    // 8. 材质细节: 粗糙度 / 金属度 / 自发光
    static func materialProbe() -> SimpleMaterial {
        var m = SimpleMaterial(color: .gray, isMetallic: true)
        m.roughness = .float(0.2)
        m.metallic = .float(0.95)
        return m
    }
}
