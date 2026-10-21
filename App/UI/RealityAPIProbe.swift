import SwiftUI
import RealityKit

// ═══════════════════════════════════════════════════════════════════
// APIPROBE — 临时探针 (拿到签名就删)
// ═══════════════════════════════════════════════════════════════════
//
// 第 1 轮结果: **Model3D 在 iOS 上不可用** (visionOS 专属)。
//   error: 'Model3D' is unavailable in iOS
// 所以 iOS 上做 3D 只有 RealityView 一条路。
//
// 第 2 轮验证:
//   1. RealityView 的 make/update 闭包签名
//   2. Entity 从 usdz 加载的 API (Entity.load / loadModel)
//   3. 用代码造几何体 (MeshResource.generateBox 等) —— 不依赖任何资源文件
//   4. RealityViewAttachment 能否把 SwiftUI 叠在 3D 上
@available(iOS 18.0, *)
struct RealityAPIProbe: View {
    var body: some View {
        RealityView { content in
            // A: 代码造一个圆柱 (验证 MeshResource.generateCylinder 是否存在)
            let mesh = MeshResource.generateCylinder(height: 0.1, radius: 0.5)
            let mat = SimpleMaterial(color: .gray, isMetallic: true)
            let ent = ModelEntity(mesh: mesh, materials: [mat])
            content.add(ent)

            // B: 从 bundle 加载 usdz 的 API (文件不存在, 只看编译期签名)
            _ = { () async in
                if let loaded = try? await Entity(named: "probe") {
                    content.add(loaded)
                }
            }

            // C: 相机与光照
            content.camera = .virtual
        } update: { content in
            _ = content
        }
        .frame(width: 1, height: 1)
    }
}

// 单独验证 loadModel 与 AnimationLibrary 这些容易记错的签名
@available(iOS 18.0, *)
enum RealityAPIProbe2 {
    static func probe() async {
        // 从 URL 加载
        _ = try? await Entity(contentsOf: URL(fileURLWithPath: "/nonexistent.usdz"))
        // 音效/动画资源
        _ = try? await Entity(named: "probe", in: Bundle.main)
    }
}
