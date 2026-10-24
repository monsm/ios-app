// 本文件由 `node tools/destmap.js --emit` 生成，**不要手改**。
// 生成时的目的地总数 = 11（呈现通道 9 + 仅被 .destined() 引用 2）。
// 后一半是扫描器认不出、但源码里有 `.destined(.xxx)` 的 case —— 删掉会直接编译失败。
// 并核对 diff —— 少一条就是某套界面会缺一个页面而没人发现。
import SwiftUI

/// 一个目的地 = 界面里的一站（供闸门与台账对账）。
/// rawValue 是 View 类型名，供 tools/uicoverage.js 与本台账对账。
enum Destination: String, CaseIterable, Identifiable {
    case autoCal = "AutoCalView"
    case credentialBin = "CredentialBinView"
    case homeConsole = "HomeConsole"
    case linkPrefs = "LinkPrefsView"
    case memberArchived = "MemberArchivedView"
    case memberDetail360 = "MemberDetail360View"
    case memberWizard = "MemberWizardView"
    case safemodeIntro = "SafemodeIntroView"
    case shareToAndroid = "ShareToAndroidView"
    case syncTime = "SyncTimeView"
    case unclaimedClaim = "UnclaimedClaimView"
    var id: String { rawValue }
}
