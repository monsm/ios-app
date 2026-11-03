// FullPageCapture.swift —— 滚动截屏算法（整页一次成像，不丢信息）。
//
// 2026-11-03（用户指正）：锚到底部只拍到页尾，中间内容全漏。
// 正确算法：找窗口里 contentSize 最高的 UIScrollView，临时把 frame 高度改成
// contentSize.height（全部内容一次性进入可见布局），drawHierarchy 整版渲染 PNG，
// 再恢复 frame。一屏装得下的页面跳过。
//
// 触发：-kfFullPage -kfTab N（仅 CI）。产物：Documents/kf-fullpage-N.png，
// workflow 用 simctl get_app_container 拷出。
import SwiftUI
import UIKit

enum FullPageCapture {
    @MainActor
    static func capture(tab: Int, delay: Double = 3.5, name: String = "tab") {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }) else { return }
            guard let sv = largestScrollView(in: window) else { return }
            let content = sv.contentSize
            guard content.height > sv.bounds.height + 50 else { return }
            let orig = sv.frame
            UIView.setAnimationsEnabled(false)
            sv.frame = CGRect(origin: orig.origin,
                              size: CGSize(width: orig.width, height: content.height))
            sv.layoutIfNeeded()
            let renderer = UIGraphicsImageRenderer(size: sv.frame.size)
            let img = renderer.image { _ in
                sv.drawHierarchy(in: sv.bounds, afterScreenUpdates: true)
            }
            sv.frame = orig
            sv.layoutIfNeeded()
            UIView.setAnimationsEnabled(true)
            if let data = img.pngData() {
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                    ?? URL(fileURLWithPath: "/tmp", isDirectory: true)
                // 文件名带页面标识（tab 序号 + 可选的 dest 名），子页与根页各自一张。
                let file = "kf-fullpage-" + String(tab) + "-" + name + ".png"
                try? data.write(to: docs.appendingPathComponent(file))
            }
        }
    }

    private static func largestScrollView(in root: UIView) -> UIScrollView? {
        var best: UIScrollView?
        var bestH: CGFloat = 0
        func walk(_ v: UIView) {
            if let sv = v as? UIScrollView, sv.contentSize.height > bestH, sv.bounds.height > 100 {
                best = sv
                bestH = sv.contentSize.height
            }
            for sub in v.subviews { walk(sub) }
        }
        walk(root)
        return best
    }
}
