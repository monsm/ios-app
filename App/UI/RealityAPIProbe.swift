import SwiftUI
import RealityKit
import simd

// ═══════════════════════════════════════════════════════════════════════
// REALITYKIT API 探针 —— 累加式，只增不删
// ═══════════════════════════════════════════════════════════════════════
//
// 本仓没有 Swift 编译器，也没有 Apple 文档访问（web_fetch 把 developer.apple.com
// 解析到非公网 IP）。所以每个 RealityKit API 都要靠"探针 → CI → 读错误"来确定。
//
// **纪律: 只增不删。**
//
// 为什么: v4 时我把 v3 里的 generateCylinder 验证代码删掉了，
// 结果写视图层时又凭记忆加了 radialSegments 参数 —— run #442 报 extra argument。
// 验证结果不留在代码里，等于没验证过。
//
// 每一块都标注「哪个 run 验证过」。若某块后来报错，说明 SDK 变了，值得注意。
// ============================================================================

// ───────────────────────────────────────────────────────────────────────
// 区块 1 · RealityView 与几何生成器        【run #417 / #420 SUCCESS】
// ───────────────────────────────────────────────────────────────────────
@available(iOS 18.0, *)
enum ProbeBlock1_RealityView {
    static func probe() {
        _ = RealityView { content in
            // make 闭包: content 是 RealityViewContent
            let mesh = MeshResource.generateCylinder(height: 0.1, radius: 0.5)
            let mat = SimpleMaterial(color: .gray, isMetallic: true)
            let ent = ModelEntity(mesh: mesh, materials: [mat])
            content.add(ent)
            content.camera = .virtual
        } update: { content in
            _ = content
        }

        // 各生成器（无段数参数！—— run #442 报 extra argument radialSegments）
        _ = MeshResource.generateBox(size: 0.1)
        _ = MeshResource.generateBox(size: [0.1, 0.08, 0.02], cornerRadius: 0.008)
        _ = MeshResource.generateSphere(radius: 0.02)
        _ = MeshResource.generateCylinder(height: 0.02, radius: 0.03)
        _ = MeshResource.generateCone(height: 0.01, radius: 0.05)
        _ = MeshResource.generatePlane(width: 0.1, depth: 0.1)
    }
}

// ───────────────────────────────────────────────────────────────────────
// 区块 2 · MeshDescriptor 手搓多边形       【run #439 SUCCESS】
// ───────────────────────────────────────────────────────────────────────
@available(iOS 18.0, *)
enum ProbeBlock2_MeshDescriptor {
    static func probe() throws {
        var desc = MeshDescriptor(name: "tri")
        desc.positions = MeshBuffer([
            [-0.5, -0.5, 0] as SIMD3<Float>,
            [ 0.5, -0.5, 0] as SIMD3<Float>,
            [ 0.0,  0.5, 0] as SIMD3<Float>,
        ])
        desc.primitives = .triangles([0, 1, 2])
        desc.normals = MeshBuffer([
            [0, 0, 1] as SIMD3<Float>,
            [0, 0, 1] as SIMD3<Float>,
            [0, 0, 1] as SIMD3<Float>,
        ])
        _ = try MeshResource.generate(from: [desc])

        // 带 UV 的四边形
        var d2 = MeshDescriptor(name: "quad")
        d2.positions = MeshBuffer([
            [-0.5, -0.5, 0] as SIMD3<Float>,
            [ 0.5, -0.5, 0] as SIMD3<Float>,
            [ 0.5,  0.5, 0] as SIMD3<Float>,
            [-0.5,  0.5, 0] as SIMD3<Float>,
        ])
        d2.primitives = .triangles([0, 1, 2, 0, 2, 3])
        d2.textureCoordinates = MeshBuffer([
            [0, 0] as SIMD2<Float>,
            [1, 0] as SIMD2<Float>,
            [1, 1] as SIMD2<Float>,
            [0, 1] as SIMD2<Float>,
        ])
        _ = try MeshResource.generate(from: [d2])
    }
}

// ───────────────────────────────────────────────────────────────────────
// 区块 3 · SimpleMaterial 的真实能力      【run #442 FAILURE → 结论在此】
// ───────────────────────────────────────────────────────────────────────
//
// 已知**不支持**的:
//   ✗ emissiveColor   —— run #442: value of type 'SimpleMaterial' has no member 'emissiveColor'
//
// 若要自发光，只能换 PhysicallyBasedMaterial。但那要再探一次针（本区块暂不覆盖）。
@available(iOS 18.0, *)
enum ProbeBlock3_Material {
    static func probe() {
        var m = SimpleMaterial(color: .gray, isMetallic: true)
        m.roughness = .float(0.2)       // ✓ 支持
        m.metallic = .float(0.95)       // ✓ 支持
        // m.emissiveColor = .red       // ✗ 不支持（保留注释作为证据）
        _ = m
    }
}

// ───────────────────────────────────────────────────────────────────────
// 区块 4 · 实体层级与变换       【✓ 已由 XLockBlade 在 run #458 验证】
// ───────────────────────────────────────────────────────────────────────
@available(iOS 18.0, *)
enum ProbeBlock4_Entity {
    static func probe() throws {
        let root = Entity()
        root.name = "root"
        root.scale = SIMD3<Float>(repeating: 0.01)          // ✓ XLockBlade 用它做 mm→m 缩放

        let mesh = MeshResource.generateSphere(radius: 0.1)
        let mat = SimpleMaterial(color: .gray, isMetallic: true)
        let child = ModelEntity(mesh: mesh, materials: [mat])
        child.name = "child"
        child.position = SIMD3<Float>(0, 0, 0)              // ✓ XLockBlade 用它定位零件
        child.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        root.addChild(child)

        // 查找与向下转型
        _ = root.findEntity(named: "child")                  // ✓ XLockBlade.applyState 用它找 accent/sensor
        if let e = root.findEntity(named: "child") as? ModelEntity {
            e.model?.materials = [mat]                       // ✓ XLockBlade.applyState 用它换状态色
        }

        // RealityViewContent 的实体枚举
        //
        // ✗ 不能显式写 RealityViewContent —— run #444 报
        //   cannot find type 'RealityViewContent' in scope
        // 这个类型名不在公开作用域里。正确做法是让它从闭包参数**自动推断**，
        // 见区块 1 的 RealityView { content in ... }（那里 content 的类型是推断出来的）。
        // 实测 XLockBlade 里 content.entities.first(where:) 编译通过（run #443 SUCCESS）——
        // 说明只要不显式标注类型名，这个用法是合法的。
    }
}

// ───────────────────────────────────────────────────────────────────────
// 区块 5 · typealias vs .self 访问嵌套类型   【run #442 FAILURE → 结论在此】
// ───────────────────────────────────────────────────────────────────────
//
// ✗ let G = SomeEnum.self   然后 G.NestedType    —— cannot find type 'G'
// ✓ typealias G = SomeEnum  然后 G.NestedType
//
// .self 拿的是元类型实例（用于反射/动态派发），不是命名空间。
enum ProbeBlock5_Nesting {
    struct Inner { var v: Int = 0 }

    static func bad() {
        // let G = ProbeBlock5_Nesting.self
        // _ = G.Inner()      // ✗ cannot find type 'G'
    }
    static func good() {
        typealias G = ProbeBlock5_Nesting
        _ = G.Inner()        // ✓
    }
}
