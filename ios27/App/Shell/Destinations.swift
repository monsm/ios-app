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

        case .lockStatus: LockStatusHomeScreen()
        case .addLock: AddLockHomeScreen()
        case .gateway: GatewayHomeScreen()
        case .syncTime: SyncTimeHomeScreen()
        case .defend: DefendHomeScreen()
        case .dfu: DFUHomeScreen()
        case .lockSettings: LockSettingsHomeScreen()
        case .tailgate: TailgateHomeScreen()
        case .safeMode: SafeModeHomeScreen()
        case .batteryProfile: BatteryProfileHomeScreen()
        case .lockProfile: LockProfileHomeScreen()
        case .lockPortfolio: LockPortfolioHomeScreen()
        case .deviceInfo: DeviceInfoHomeScreen()
        case .moduleOrder: ModuleOrderHomeScreen()

        case .keyDetail: KeyDetailHomeScreen()
        case .keyCreate: KeyCreateHomeScreen()
        case .keyCalendar: KeyCalendarHomeScreen()
        case .mobileKey: MobileKeyHomeScreen()
        case .shareToAndroid: ShareToAndroidHomeScreen()
        case .credentialStudio: CredentialStudioHomeScreen()
        case .zotp: ZotpHomeScreen()

        case .recordDetail: RecordDetailHomeScreen()
        case .recordExport: RecordExportHomeScreen()
        case .recordsStudio: RecordsStudioHomeScreen()

        case .memberDetail: MemberDetailHomeScreen()
        case .memberCreate: MemberCreateHomeScreen()
        case .memberArchive: MemberArchiveHomeScreen()
        case .memberOps: MemberOpsHomeScreen()

        case .appearance: AppearanceHomeScreen()
        case .security: SecurityHomeScreen()
        case .backup: BackupHomeScreen()
        case .autoOpen: AutoOpenHomeScreen()
        case .hardware: HardwareHomeScreen()
        case .protocolTest: ProtocolTestHomeScreen()
        case .godMode: GodModeHomeScreen()
        case .about: AboutHomeScreen()
        case .accessibility: AccessibilityHomeScreen()
        case .backupStudio: BackupStudioHomeScreen()
        }
    }
}