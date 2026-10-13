// 710 报告校验二维码 — 相机侧 (扫码核对的入口 sheet)。
// 本文件只负责一件事: 把相机读到的一行载荷原文交回导出中心, 由 ReportVerify.verify
// (App/UI/ExportCenter.swift 的 ReportVerify 一节) 与本机当前数据重算的指纹做比对。
// 比对、文案、判定都在那边; 这一侧纯只读 —— 扫到的内容只进闭包, 库里一个字节都不写,
// 全程本机解码, 没有任何网络调用。
import SwiftUI
import VisionKit

/// 710 扫码 sheet: 制式逐字抄既有两处 ——
///   App/UI/BackupStudio.swift:2287-2300 (MigScanSheet, 411 扫码接收侧)
///   App/UI/CredentialStudio.swift:451-465 (CodeScanSheet, 522 相机取号)
/// 相机权限走那两处同一条路径: 直接呈现 DataScannerView, 授权弹窗由系统按 NSCameraUsageDescription
/// (App/Info.plist, 由 project.yml:47 生成 — 「识别备份二维码…全程本地解码无网络」) 负责,
/// 退出走 cancellationAction。相机是本功能申请的唯一权限 (证据: 全仓相机侧只有这两处先例, 本文件与它们同形)。
///
/// ⚠ API-VERIFY: `DataScannerView { session in … } results: { … }` 的 init 形状、
///   `session.supportedDataTypes = [.qr, .dataMatrix]` 的枚举取值、`r.data.item?.string` 这条取值链
///   都是"只有编译器/真机才能定成立"的写法, 本仓尚未编译验证过。docs/API-VERIFY.md:44 对同一形状
///   的裁定是「撞不到 Apple 文档、形状高度可疑、在编译器看过之前不许凭记忆重写」⇒ 本文件把既有
///   两处逐字复用, 参数与调用顺序原样保留 (含 fired 闸: 一帧多结果时只交回第一条, 避免重复弹比对)。
struct ReportScanSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onResult: (String) -> Void
    @State private var fired = false

    var body: some View {
        NavigationStack {
            DataScannerView { results in
                for r in results {
                    if let s = r.codeString {
                        guard fired == false else { return }
                        fired = true
                        onResult(s)
                        dismiss()
                        return
                    }
                }
            }
            // 710 可读标题: VoiceOver 落到导航栏标题上, 相机画面本身由 DataScannerView 自管
            .navigationTitle("扫码核对 (710)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            } }
        }
    }
}
