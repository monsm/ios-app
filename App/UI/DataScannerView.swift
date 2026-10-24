// 522/411/710 扫码取景 —— UIKit `DataScannerViewController` 的 SwiftUI 包装。
//
// 为什么不是 SwiftUI 侧的 `DataScannerView`: docs/API-VERIFY.md:44 记过一次撞页 ——
// Apple 文档里根本找不到 SwiftUI 的 `DataScannerView`; `session.supportedDataTypes = [.qr, .dataMatrix]`
// (该属性在 UIKit 侧只读) 与 `r.data.item?.string` 这条取值链也都对不上任何真实符号。
// 那张表的裁定是「撞不到 + 高度可疑 = 不要靠猜改; 一旦编译器报错就把整块换成 UIKit
// `DataScannerViewController` 包 `UIViewControllerRepresentable`」。三个调用点
// (CredentialStudio 522 相机取号 / BackupStudio 411 扫码接收 / ReportVerifyView 710 扫码核对)
// 现按该退路统一走这里 —— 只此一份, 不再各自抄形状。
//
// 只认条码: 三处要的都是二维码载荷原文; 文本块 (RecognizedItem.text) 一律忽略。
import SwiftUI
import VisionKit
import Vision

struct DataScannerView: UIViewControllerRepresentable {
    /// 要识别的码制。默认与三个调用点原写法一致 (QR + DataMatrix)。
    let symbologies: [VNBarcodeSymbology]
    /// 每次新增识别到的条目 (回调在主线程)
    let results: ([RecognizedItem]) -> Void

    init(symbologies: [VNBarcodeSymbology] = [.qr, .dataMatrix],
         results: @escaping ([RecognizedItem]) -> Void) {
        self.symbologies = symbologies
        self.results = results
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: symbologies)],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        // 设备不支持 / 相机不可用 (模拟器) 时 startScanning 会抛错 —— 扫码本身是可选路径,
        // 失败就停在取景页让用户退回手工输入 (522 原句「失败回退人工输入」), 不静默崩。
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(results: results) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let results: ([RecognizedItem]) -> Void
        init(results: @escaping ([RecognizedItem]) -> Void) {
            self.results = results
        }
        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            results(addedItems)
        }
    }
}

extension RecognizedItem {
}
