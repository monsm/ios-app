// 本文件由 `node tools/destmap.js --emit` 生成，**不要手改**。
// 生成时的目的地总数 = 28。改了界面呈现方式之后重新生成，
// 并核对 diff —— 少一条就是某套界面会缺一个页面而没人发现。
import SwiftUI

/// 一个目的地 = 界面里的一站（供闸门与台账对账）。
/// rawValue 是 View 类型名，供 tools/uicoverage.js 与本台账对账。
enum Destination: String, CaseIterable, Identifiable {
    case addDevice = "AddDeviceView"
    case backup = "BackupView"
    case credentialCalendar = "CredentialCalendarView"
    case credentials = "CredentialsView"
    case credExtend = "CredExtendView"
    case defend = "DefendView"
    case deviceHome = "DeviceHomeView"
    case deviceInfo = "DeviceInfoView"
    case dFU = "DFUView"
    case dongle = "DongleView"
    case gateway = "GatewayView"
    case lockProfile = "LockProfileView"
    case lockSettings = "LockSettingsView"
    case memberArchived = "MemberArchivedView"
    case memberCenter = "MemberCenterView"
    case memberDetail360 = "MemberDetail360View"
    case members = "MembersView"
    case memberWizard = "MemberWizardView"
    case mergeMembers = "MergeMembersView"
    case mobileKey = "MobileKeyView"
    case protocolTest = "ProtocolTestView"
    case records = "RecordsView"
    case safemodeIntro = "SafemodeIntroView"
    case settings = "SettingsView"
    case shareToAndroid = "ShareToAndroidView"
    case syncTime = "SyncTimeView"
    case tailgate = "TailgateView"
    case unlockGate = "UnlockGateView"
    var id: String { rawValue }
}
