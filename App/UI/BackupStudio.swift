// 备份工作室仅存的两块 —— 其余 (导出向导/恢复向导/换机迁移/本地文件/迁移提示卡) 已随大删波4移除。
//
// 为什么这两块留下:
//   · WebDAVStudioView — 坚果云同步的真实入口 (BackupView 经 sheet 打开), 用户自己填服务器与账号,
//     BackupStudio 引擎侧的 testWebdav/listRemote/rotateKey 都还在, 这页是它们的 UI。
//   · UIImageShareItem — DiagnosticsView 分享诊断截图用的 Transferable 包装。
// 删掉的是**向导流程** (ExportWizard/RestoreWizard/MigrationWizard/LocalFiles/MigrationPromptCard),
// 备份本体改由 BackupView 的「存到 iCloud 云盘 / 从文件选择」承担。
import SwiftUI
import UIKit
import UniformTypeIdentifiers


struct UIImageShareItem: Transferable {
    let image: UIImage
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            item.image.pngData() ?? Data()
        }
    }
    init(_ image: UIImage) { self.image = image }
}
