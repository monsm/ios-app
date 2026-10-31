// Destinations.swift —— Dest → View 的唯一映射。
//
// 新增页面：① 在 Router.swift 的 Dest 里登记；② 在这里加一行；
// ③ Gates/destmap.js 会对账，少一条就红（避免"某页不存在却有人跳过去"）。
import SwiftUI

enum Destinations {
    @ViewBuilder
    static func view(for dest: Dest) -> some View {
        switch dest {
        case .door: DoorScreen()
        case .keys: KeysScreen()
        case .records: RecordsScreen()
        case .household: HouseholdScreen()
        case .settings: SettingsScreen()

        case .lockStatus: LockStatusScreen()
        case .addLock: AddLockScreen()
        case .gateway: GatewayScreen()
        case .syncTime: SyncTimeScreen()
        case .defend: DefendScreen()

        case .keyDetail: KeyDetailScreen()
        case .keyCreate: KeyCreateScreen()
        case .keyCalendar: KeyCalendarScreen()
        case .mobileKey: MobileKeyScreen()
        case .shareToAndroid: ShareToAndroidScreen()

        case .recordDetail: RecordDetailScreen()
        case .recordExport: RecordExportScreen()

        case .memberDetail: MemberDetailScreen()
        case .memberCreate: MemberCreateScreen()
        case .memberArchive: MemberArchiveScreen()

        case .appearance: AppearanceScreen()
        case .security: SecurityScreen()
        case .backup: BackupScreen()
        case .autoOpen: AutoOpenScreen()
        case .hardware: HardwareScreen()
        case .about: AboutScreen()
        }
    }
}
