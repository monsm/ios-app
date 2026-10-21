import SwiftUI
import RealityKit

// ═══════════════════════════════════════════════════════════════════
// APIPROBE — 临时探针: 只用来验证 RealityKit 在 iOS 27 SDK 下的真实签名
// ═══════════════════════════════════════════════════════════════════
//
// 为什么要有这个文件:
//   本机没有 Swift 编译器也没有 Apple 文档访问 (web_fetch 解析到非公网 IP,
//   web_search 无 API key)。上一轮凭记忆写 scrollTransition 的闭包签名
//   (写成单参数, 真实是 (content, phase)) 导致 CI 连续多轮失败。
//   所以这次先用最小探针把签名压出来, 通过 CI 编译再往下写。
//
// 探针验证四件事:
//   1. RealityView 的 make/update 闭包参数名与类型
//   2. Model3D 的 available 阶段枚举怎么取
//   3. Entity 加载 usdz 的 API
//   4. SwiftUI 里能否直接 import RealityKit
@available(iOS 18.0, *)
struct RealityAPIProbe: View {
    var body: some View {
        // 探针 A: Model3D —— 不依赖任何资源文件, 只看它能不能编译
        Model3D(named: "probe-not-exist") { phase in
            switch phase {
            case .empty:
                Color.clear
            case .success(let model):
                model.resizable()
            case .failure:
                Color.clear
            @unknown default:
                Color.clear
            }
        }
        .frame(width: 1, height: 1)
    }
}

// 探针 B: RealityView 的闭包签名
@available(iOS 18.0, *)
struct RealityViewProbe: View {
    var body: some View {
        RealityView { content in
            // make 闭包: content 是 RealityViewContent
            _ = content
        } update: { content in
            // update 闭包: 同类型
            _ = content
        }
        .frame(width: 1, height: 1)
    }
}
