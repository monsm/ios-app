import SwiftUI
import RealityKit
import simd

// ═══════════════════════════════════════════════════════════════════════
// MARK: - 刃 · RealityKit 组装层
// ═══════════════════════════════════════════════════════════════════════
//
// 上一层 BladeGeometry 只算顶点。这一层把顶点交给 MeshDescriptor。
//
// MeshDescriptor 的签名由探针 v4 (run #439 SUCCESS) 验证:
//   desc.positions        = MeshBuffer([SIMD3<Float>])
//   desc.primitives       = .triangles([UInt32])
//   desc.normals          = MeshBuffer([SIMD3<Float>])
//   desc.textureCoordinates = MeshBuffer([SIMD2<Float>])
//   try MeshResource.generate(from: [desc])
//
// 注意: 本仓此前从未用过 MeshDescriptor（旧 XLockBody3D 只有 generateCylinder），
// 所以这一层的每个 API 都是新引入的 —— 有 CI 背书，但真机表现仍需看。
//
// 尺寸单位: 建模用 mm，最后整体 scale 到场景（1/100）。
enum BladeMesh {

    /// 把三角形顶点数组转成 MeshResource。
    ///
    /// - 顶点需要去重（MeshDescriptor 用索引三角形，重复顶点浪费且法线会断）
    /// - 法线按**面法线累加后归一化**计算（平滑着色）
    /// - UV 按 XY 平面投影（刃的正面是平面，够用）
    static func build(from tris: [BladeGeometry.P3]) throws -> MeshResource? {
        guard tris.count >= 3 else { return nil }

        // ── 顶点去重 ──
        // key 用 1e-4 mm 量化，避免浮点误差导致同一顶点被判成两个
        var index: [SIMD3<Int32>: UInt32] = [:]
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        func key(_ p: BladeGeometry.P3) -> SIMD3<Int32> {
            SIMD3<Int32>(
                Int32((p.x * 10000).rounded()),
                Int32((p.y * 10000).rounded()),
                Int32((p.z * 10000).rounded())
            )
        }

        indices.reserveCapacity(tris.count)
        for p in tris {
            let k = key(p)
            if let existing = index[k] {
                indices.append(existing)
            } else {
                let idx = UInt32(positions.count)
                index[k] = idx
                positions.append(SIMD3<Float>(p.x, p.y, p.z))
                indices.append(idx)
            }
        }

        guard positions.count >= 3, indices.count >= 3 else { return nil }

        // ── 法线：面法线累加 ──
        var normals = [SIMD3<Float>](repeating: .zero, count: positions.count)
        var i = 0
        while i + 2 < indices.count {
            let a = Int(indices[i]), b = Int(indices[i + 1]), c = Int(indices[i + 2])
            let p0 = positions[a], p1 = positions[b], p2 = positions[c]
            let n = simd_cross(p1 - p0, p2 - p0)
            // 面积加权（不归一化就自动带了面积）
            normals[a] += n
            normals[b] += n
            normals[c] += n
            i += 3
        }
        for j in 0..<normals.count {
            let len = simd_length(normals[j])
            normals[j] = len > 1e-9 ? normals[j] / len : SIMD3<Float>(0, 0, 1)
        }

        // ── UV：XY 平面投影 ──
        // 用包围盒归一化，贴图会拉伸但不影响纯色材质
        var minX = Float.greatestFiniteMagnitude, maxX = -Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude, maxY = -Float.greatestFiniteMagnitude
        for p in positions {
            minX = Swift.min(minX, p.x); maxX = Swift.max(maxX, p.x)
            minY = Swift.min(minY, p.y); maxY = Swift.max(maxY, p.y)
        }
        let spanX = Swift.max(maxX - minX, 1e-6)
        let spanY = Swift.max(maxY - minY, 1e-6)
        let uvs: [SIMD2<Float>] = positions.map {
            SIMD2<Float>((($0.x - minX) / spanX), (($0.y - minY) / spanY))
        }

        // ── 组装 descriptor ──
        var desc = MeshDescriptor(name: "blade")
        desc.positions = MeshBuffer(positions)
        desc.normals = MeshBuffer(normals)
        desc.textureCoordinates = MeshBuffer(uvs)
        desc.primitives = .triangles(indices)

        return try MeshResource.generate(from: [desc])
    }

    /// 一个简单的纯色材质（刃用 4 种）
    static func material(color: UIColor, metallic: Bool, roughness: Float) -> SimpleMaterial {
        var m = SimpleMaterial(color: color, isMetallic: metallic)
        m.roughness = .float(roughness)
        return m
    }
}
