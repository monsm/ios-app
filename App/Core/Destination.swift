// 本文件由 `node tools/destmap.js --emit` 生成，**不要手改**。
// 生成时的目的地总数 = 34。改了界面呈现方式之后重新生成，
// 并核对 diff —— 少一条就是某套界面会缺一个页面而没人发现。
import SwiftUI

/// 一个目的地 = 界面里的一站（供闸门与台账对账）。
/// rawValue 是 View 类型名，供 tools/uicoverage.js 与本台账对账。
enum Destination: String, CaseIterable, Identifiable {
    case addDevice = "AddDeviceView"
    case addPwd = "AddPwdView"
    case autoCal = "AutoCalView"
    case backup = "BackupView"
    case credentials = "CredentialsView"
    case credExtend = "CredExtendView"
    case defend = "DefendView"
    case deviceHome = "DeviceHomeView"
    case deviceInfo = "DeviceInfoView"
    case dFU = "DFUView"
    case diagnostics = "DiagnosticsView"
    case gateway = "GatewayView"
    case keychainHW = "KeychainHWView"
    case linkPrefs = "LinkPrefsView"
    case lockProfile = "LockProfileView"
    case memberArchived = "MemberArchivedView"
    case memberCenter = "MemberCenterView"
    case memberDetail360 = "MemberDetail360View"
    case members = "MembersView"
    case memberWizard = "MemberWizardView"
    case mergeMembers = "MergeMembersView"
    case messages = "MessagesView"
    case mobileKey = "MobileKeyView"
    case records = "RecordsView"
    case safemodeIntro = "SafemodeIntroView"
    case settings = "SettingsView"
    case shareToAndroid = "ShareToAndroidView"
    case startAddFp = "StartAddFpView"
    case syncTime = "SyncTimeView"
    case tailgate = "TailgateView"
    case unlockGate = "UnlockGateView"
    case webDAVStudio = "WebDAVStudioView"
    var id: String { rawValue }
}
