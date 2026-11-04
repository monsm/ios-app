// KeysIntents.swift —— 凭证域的纯逻辑类型（从旧页搬出，内容原样）
//
// 为什么单独成文件（2026-11-04 · S4 前置）：
//   `KeyCreateIntent` 原本声明在 KeyCreateScreen.swift 里，而 KeyCreateHomeScreen 要用它 ——
//   只要这两个类型还住在旧页文件里，旧页就删不掉（删了就编译不过）。
//   搬出来之后，旧页与它的 V7 渲染层可以整份删除，逻辑不受影响。
//
// 纪律：本文件只有**纯逻辑 / 位图工具**，不含任何渲染层代码。
import SwiftUI

// MARK: - 新建凭证的入口意图（跨页传参）

/// 「新增凭证」被打开时想预选哪一种类型。由入口页写入，由凭证工坊读走并清零。
enum KeyCreateIntent {
    static var pending: KeyItem.Kind?
}

// MARK: - 分享给安卓的二维码

enum KeysQR {
    static func image(_ text: String) -> UIImage? {
        guard !text.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale: CGFloat = 10
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        // 静区与白底烘进图里：扫码规范要求四周留白，深色模式下也必须白底黑码 ——
        // 这不是配色选择，是「能不能扫出来」。所以白只存在于这一张位图里，不进颜色令牌。
        // （HIG 审计把 CIColor(red:1,green:1,blue:1) 标为硬编码颜色 —— 这里是位图素材，
        //  不是界面颜色，不能走 V.C.card：深色模式下 V.C.card 是深灰，扫不出来。）
        let quiet: CGFloat = scale * 4
        let canvas = scaled.extent.insetBy(dx: -quiet, dy: -quiet)
        let paper = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)).cropped(to: canvas)
        let composed = scaled.composited(over: paper)
        guard let cg = CIContext().createCGImage(composed, from: canvas) else { return nil }
        return UIImage(cgImage: cg)
    }
}
