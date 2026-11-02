// Destinations.swift —— Dest → View 的唯一映射。
//
// 新增页面：① 在 Router.swift 的 Dest 里登记；② 在这里加一行；
// ③ Gates/destmap.js 会对账，少一条就红（避免"某页不存在却有人跳过去"）。
//
// 2026-11-02（六页并两页，见 _audit/ui-ia.md §5.1）：三个目的地**改指向吸收页**，case 一个都没删 ——
//   全仓还有 `.dest(.syncTime)` / `.dest(.tailgate)` / `.dest(.safeMode)` 的调用点（门页快捷操作、锁设置入口），
//   删 case 会直接编译失败。改映射让用户点进去看到的就是合并后的页：
//     .syncTime → 锁实况（校时已并入该页的「同步门锁时间」）
//     .safeMode → 锁实况（A/B 切换已并入该页的「安全模式」卡）
//     .tailgate → 锁设置（2–6 秒档已并入该页的「防尾随」段）
//   三个旧页面文件仍留在磁盘上（本轮不删），但已不再被映射 —— 下一轮连同 case 一起清。
import SwiftUI

@MainActor
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
        // 校时 / 安全模式 → 锁实况（两者已并入该页，见文件头说明）
        case .syncTime: LockStatusScreen()
        case .defend: DefendScreen()
        case .dfu: DFUScreen()
        case .lockSettings: LockSettingsScreen()
        // 防尾随 → 锁设置（2–6 秒档已并入该页）
        case .tailgate: LockSettingsScreen()
        case .safeMode: LockStatusScreen()
        case .batteryProfile: BatteryProfileScreen()
        case .lockProfile: LockProfileScreen()
        case .lockPortfolio: LockPortfolioScreen()
        case .deviceInfo: DeviceInfoScreen()
        case .unlockGate: UnlockGateScreen()
        case .moduleOrder: ModuleOrderScreen()

        case .keyDetail: KeyDetailScreen()
        case .keyCreate: KeyCreateScreen()
        case .keyCalendar: KeyCalendarScreen()
        case .mobileKey: MobileKeyScreen()
        case .shareToAndroid: ShareToAndroidScreen()
        case .credentialStudio: CredentialStudioScreen()
        case .zotp: ZotpScreen()

        case .recordDetail: RecordDetailScreen()
        case .recordExport: RecordExportScreen()
        case .recordsStudio: RecordsStudioScreen()

        case .memberDetail: MemberDetailScreen()
        case .memberCreate: MemberCreateScreen()
        case .memberArchive: MemberArchiveScreen()
        case .memberOps: MemberOpsScreen()

        case .appearance: AppearanceScreen()
        case .security: SecurityScreen()
        case .backup: BackupScreen()
        case .autoOpen: AutoOpenScreen()
        case .hardware: HardwareScreen()
        case .protocolTest: ProtocolTestScreen()
        case .about: AboutScreen()
        case .accessibility: AccessibilityScreen()
        case .backupStudio: BackupStudioScreen()
        }
    }
}
