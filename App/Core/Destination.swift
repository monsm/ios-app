// 本文件由 `node tools/destmap.js --emit` 生成，**不要手改**。
// 生成时的目的地总数 = 20。改了界面呈现方式之后重新生成，
// 并核对 diff —— 少一条就是某套界面会缺一个页面而没人发现。
import SwiftUI

/// 一个目的地 = 界面里的一站（供闸门与台账对账）。
/// rawValue 是 View 类型名，供 tools/uicoverage.js 与本台账对账。
enum Destination: String, CaseIterable, Identifiable {
    case autoCal = "AutoCalView"
    case backupStudio = "BackupStudioView"
    case batterySwapGuide = "BatterySwapGuideView"
    case careChecklist = "CareChecklistView"
    case careReminders = "CareRemindersView"
    case credentialBin = "CredentialBinView"
    case exportWizard = "ExportWizardView"
    case homeConsole = "HomeConsole"
    case linkPrefs = "LinkPrefsView"
    case maintenance = "MaintenanceView"
    case memberArchived = "MemberArchivedView"
    case memberDetail360 = "MemberDetail360View"
    case memberFamilySettings = "MemberFamilySettingsView"
    case memberWizard = "MemberWizardView"
    case mergeMembers = "MergeMembersView"
    case restoreWizard = "RestoreWizardView"
    case securityPeek = "SecurityPeekView"
    case shareToAndroid = "ShareToAndroidView"
    case syncTime = "SyncTimeView"
    case unclaimedClaim = "UnclaimedClaimView"
    var id: String { rawValue }
}
