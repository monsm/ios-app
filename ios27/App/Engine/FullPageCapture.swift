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
import CoreGraphics

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
            // AX 档下 contentSize 可能已远超可视区（整页高度上万）—— 不设上限，照常撑开。
            let orig = sv.frame
            UIView.setAnimationsEnabled(false)
            // 2026-11-05（Round 7 · AX 整页空白根因）：AX 档下 contentSize 在**撑开前**，
            // 是 AX 布局自身的高度（可能已上万），frame 撑到 content.height 后内容从
            // contentOffset（用户/系统滚到的位置）开始排 —— 上半张全是空白。
            // 撑开前先把 offset 归零：整版渲染要的是「从第 0 行内容开始」。
            sv.contentOffset = .zero
            sv.frame = CGRect(origin: orig.origin,
                              size: CGSize(width: orig.width, height: content.height))
            sv.layoutIfNeeded()
            // 2026-11-04（黑边根因 · 第三次才对）：full 截图里卡片之间的空隙是**纯黑**，
            // 而 viewport 截图同一位置是纸色。原因不是深色模式（appearance=light 已生效、
            // 卡片内容本来就是浅色），而是：`.background(V.C.bg)` 挂在 **ScrollView 外面**，
            // 而 `drawHierarchy(in: sv.bounds)` 只渲染 ScrollView 自己的层级 ——
            // 它的背景是透明，PNG 里透明落成黑。给 renderer 先铺一层 `V.C.bg`，
            // 再把 ScrollView 的 layer 背景临时设成同色，恢复时还原。
            let paper = UIColor(V8.C.bg)

            // 2026-11-05（Round 7 · AX 整页空白根因 #2）：AX 档下 dynamicTypeSize 改变了
            // 全部字体的度量，撑开 frame 触发的 SwiftUI 重布局是**异步**的 ——
            // 同一 runloop 里 drawHierarchy 拿到的还是空 frame（整版只有纸色）。
            // 修法：先按旧高度占位渲染一次，**把「恢复现场」的闭包留住**，
            // 然后等 0.4s（两个 runloop）再重测 contentSize、二次渲染；
            // 二次渲染产物才落盘，恢复永远执行。
            let origBg = sv.backgroundColor
            sv.backgroundColor = paper

            func render() -> Data? {
                let renderer = UIGraphicsImageRenderer(size: sv.frame.size)
                let img = renderer.image { ctx in
                    paper.setFill()
                    ctx.fill(sv.bounds)
                    sv.drawHierarchy(in: sv.bounds, afterScreenUpdates: true)
                }
                return img.pngData()
            }

            func restore() {
                sv.backgroundColor = origBg
                sv.frame = orig
                sv.contentOffset = .zero
                sv.layoutIfNeeded()
                UIView.setAnimationsEnabled(true)
            }

            var wrote = false
            func write(_ data: Data?) {
                guard let data, !wrote else { return }
                wrote = true
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                    ?? URL(fileURLWithPath: "/tmp", isDirectory: true)
                // 文件名带页面标识（tab 序号 + 可选的 dest 名），子页与根页各自一张。
                let file = "kf-fullpage-" + String(tab) + "-" + name + ".png"
                try? data.write(to: docs.appendingPathComponent(file))
            }

            // 2026-11-05（Round 7 · 第三修）：drawHierarchy 对**超高 frame**（AX 档 9000+pt）
            // 在模拟器上会拿到一版纯底色 —— 两遍渲染都救不了。放弃「撑开一次成像」，
            // 改**滚动拼接**：保持原 frame 不动，逐屏 setContentOffset → drawHierarchy 当前屏 →
            // 把这一屏贴进整版画布。每屏都走真实的屏幕渲染管线，AX 档也必然有内容。
            func captureTiled() -> Data? {
                // 2026-11-05（Round 7 · 定稿）：组版画布在本机模拟器上拿不到正确的
                // AX 布局位图（试过 CGContext / UIGraphicsImageRenderer 两种组版，结果都是黑）。
                // 改**逐屏落盘**：不拼一张大图，而是把每一屏写成独立 PNG（tile-N）。
                // 证据价值一样（AX 布局的每一屏都能看），且每屏都走真实屏幕渲染。
                let total = sv.contentSize.height
                let tile = sv.bounds.height
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                    ?? URL(fileURLWithPath: "/tmp", isDirectory: true)
                var offset = CGFloat(0)
                var index = 0
                while offset < total {
                    sv.contentOffset = CGPoint(x: 0, y: min(offset, max(0, total - tile)))
                    sv.layoutIfNeeded()
                    let renderer = UIGraphicsImageRenderer(bounds: CGRect(origin: .zero, size: sv.bounds.size))
                    let img = renderer.image { c in
                        paper.setFill()
                        c.fill(CGRect(origin: .zero, size: sv.bounds.size))
                        sv.drawHierarchy(in: sv.bounds, afterScreenUpdates: true)
                    }
                    let file = String(format: "kf-fullpage-%d-%@-tile%02d.png", tab, name, index)
                    try? img.pngData()?.write(to: docs.appendingPathComponent(file))
                    offset += tile
                    index += 1
                }
                sv.contentOffset = .zero
                return nil // 不再产出单一大图；驱动端按 tile 文件处理
            }

            _ = captureTiled()
            restore()
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
