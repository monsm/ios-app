import SwiftUI
import RealityKit

// ═══════════════════════════════════════════════════════════════════
// APIPROBE v4 — MeshDescriptor 手搓多边形（拿到签名就删）
// ═══════════════════════════════════════════════════════════════════
//
// 背景: 选定的锁体「刃」不是圆柱拼的，而是**手搓多边形拉伸体**:
//   左缘直线 + 右缘 R500 弧的轮廓，沿 Z 拉出 22mm 厚，前后各倒角。
//
//   three.js 里这是 BufferGeometry + setIndex。
//   iOS 的对应物是 MeshDescriptor + MeshBuffer + .triangles([UInt32])。
//
// 已知 (探针 v3): generateBox/Sphere/Cylinder/Cone/Plane 都可用；
//                MeshDescriptor / MeshBuffer 名字存在（swiftlint 白名单验过）
//
// 本轮要压出来的是 MeshDescriptor 的**真实成员名与类型**:
//   1. positions 要 MeshBuffer<SIMD3<Float>> 还是别的?
//   2. primitives 用 .triangles([UInt32]) 对吗?
//   3. 需要 normals 吗? 不提供会不会黑面?
//   4. MeshResource.generate(from: [desc]) 的参数
//   5. 法线用 MeshDescriptor 自动算还是必须手填?
@available(iOS 18.0, *)
enum MeshDescriptorProbe {
    static func probe() throws {
        // 一个最简单的三角形
        var desc = MeshDescriptor(name: "tri")

        // 1. 顶点位置
        let verts: [SIMD3<Float>] = [
            [-0.5, -0.5, 0],
            [ 0.5, -0.5, 0],
            [ 0.0,  0.5, 0],
        ]
        desc.positions = MeshBuffer(verts)

        // 2. 三角形索引
        desc.primitives = .triangles([0, 1, 2])

        // 3. 法线（可选？先试试不提供）
        desc.normals = MeshBuffer([
            [0, 0, 1] as SIMD3<Float>,
            [0, 0, 1] as SIMD3<Float>,
            [0, 0, 1] as SIMD3<Float>,
        ])

        // 4. 生成 MeshResource
        _ = try MeshResource.generate(from: [desc])

        // 5. 更复杂: 带 UV 的
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

// 6. 顺便验证: 用 descriptor 生成的 mesh 能否直接建 ModelEntity
@available(iOS 18.0, *)
enum MeshEntityProbe {
    static func probe() throws {
        var d = MeshDescriptor(name: "p")
        d.positions = MeshBuffer([
            [-0.5, -0.5, 0] as SIMD3<Float>,
            [ 0.5, -0.5, 0] as SIMD3<Float>,
            [ 0.0,  0.5, 0] as SIMD3<Float>,
        ])
        d.primitives = .triangles([0, 1, 2])
        let mesh = try MeshResource.generate(from: [d])
        let mat = SimpleMaterial(color: .gray, isMetallic: true)
        _ = ModelEntity(mesh: mesh, materials: [mat])
    }
}
