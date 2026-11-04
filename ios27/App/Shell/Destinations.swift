// Destinations.swift —— Dest → View 的唯一映射。
//
// 新增页面：① 在 Router.swift 的 Dest 里登记；② 在这里加一行；
// ③ Gates/destmap.js 会对账，少一条就红（避免"某页不存在却有人跳过去"）。
import SwiftUI

@MainActor
enum Destinations {
    @ViewBuilder
    static func view(for dest: Dest) -> some View {
        switch dest {
        case .door: DoorHomeScreen()
        case .keys: KeysHomeScreen()
        case .records: RecordsHomeScreen()
        case .household: HouseHomeScreen()
        case .settings: SettingsHomeScreen()

        // —— 02 分册 §3.1 归并（S5）：Dest case 保留（Router 与全仓调用点仍在），映射指向宿主页 ——
        // lockStatus / syncTime / defend / tailgate / safeMode → 锁设置（LockSettingsHomeScreen 的五个段）
        case .lockStatus: LockSettingsHomeScreen()
        case .addLock: AddLockHomeScreen()
        // gateway / dfu / batteryProfile / deviceInfo → 锁维护（LockMaintenanceHomeScreen 的四个段）
        case .gateway: LockMaintenanceHomeScreen()
        case .syncTime: LockSettingsHomeScreen()
        case .defend: LockSettingsHomeScreen()
        case .dfu: LockMaintenanceHomeScreen()
        case .lockSettings: LockSettingsHomeScreen()
        case .tailgate: LockSettingsHomeScreen()
        case .safeMode: LockSettingsHomeScreen()
        case .batteryProfile: LockMaintenanceHomeScreen()
        // lockProfile / moduleOrder → 我的锁（LockPortfolioHomeScreen 的两个段）
        case .lockProfile: LockPortfolioHomeScreen()
        case .lockPortfolio: LockPortfolioHomeScreen()
        case .deviceInfo: LockMaintenanceHomeScreen()
        case .moduleOrder: LockPortfolioHomeScreen()

        case .keyDetail: KeyDetailHomeScreen()
        case .keyCreate: KeyCreateHomeScreen()
        case .keyCalendar: CredentialStudioHomeScreen()
        case .mobileKey: MobileKeyHomeScreen()
        case .shareToAndroid: MobileKeyHomeScreen()
        case .credentialStudio: CredentialStudioHomeScreen()
        case .zotp: ZotpHomeScreen()

        case .recordDetail: RecordDetailHomeScreen()
        case .recordExport: RecordsStudioHomeScreen()
        case .recordsStudio: RecordsStudioHomeScreen()

        case .memberDetail: MemberDetailHomeScreen()
        case .memberCreate: MemberCreateHomeScreen()
        case .memberArchive: HouseHomeScreen()
        case .memberOps: MemberDetailHomeScreen()

        case .appearance: AppearanceHomeScreen()
        case .security: SecurityHomeScreen()
        case .backup: BackupHomeScreen()
        case .autoOpen: AutoOpenHomeScreen()
        case .hardware: HardwareHomeScreen()
        case .protocolTest: DiagnosticsHomeScreen()
        case .godMode: DiagnosticsHomeScreen()
        case .about: AboutHomeScreen()
        case .accessibility: AppearanceHomeScreen()
        case .backupStudio: BackupHomeScreen()
        }
    }
}