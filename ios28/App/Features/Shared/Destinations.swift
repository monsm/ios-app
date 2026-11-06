// Destinations.swift —— Dest → View 的唯一映射。页面之间不许互相引用。
import SwiftUI

@MainActor
enum Destinations {
    @ViewBuilder
    static func view(for dest: Dest) -> some View {
        switch dest {
        case .credential: CredentialDetailScreen()
        case .credentialCreate: CredentialCreateScreen()
        case .mobileKeys: MobileKeysScreen()
        case .zotp: ZotpScreen()
        case .member: MemberDetailScreen()
        case .memberCreate: MemberCreateScreen()
        case .event: EventDetailScreen()
        case .insights: InsightsScreen()
        case .locks: LocksScreen()
        case .lockPolicy: LockPolicyScreen()
        case .lockInfo: LockInfoScreen()
        case .pairing: PairingScreen()
        case .autoOpen: AutoOpenScreen()
        case .hardware: HardwareScreen()
        case .dfu: DfuScreen()
        case .diagnostics: DiagnosticsScreen()
        case .security: SecurityScreen()
        case .backup: BackupScreen()
        case .appearance: AppearanceScreen()
        case .about: AboutScreen()
        }
    }
}
