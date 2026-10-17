import SwiftUI

// MARK: - Unified Modal Sheet Manager (统一弹窗系统)
// 设计原则：单一状态源 + 自动 dismissal + Haptic 反馈同步

@MainActor
class SheetManager: ObservableObject {
    // MARK: - Published Properties
    @Published var isActive = false
    @Published var currentType: SheetType?
    @Published var dismissDelay: TimeInterval = 0.5
    
    // MARK: - Sheet Types
    enum SheetType: String, CaseIterable {
        case addCredential = "添加凭证"
        case shareAccess = "分享权限"
        case deviceSettings = "设备设置"
        case memberProfile = "成员资料"
        case customAutomation = "自定义规则"
        
        var systemImage: String {
            switch self {
            case .addCredential: return "plus.circle.fill"
            case .shareAccess: return "person.badge.plus"
            case .deviceSettings: return "gearshape.fill"
            case .memberProfile: return "person.crop.circle.badge.checkmark"
            case .customAutomation: return "sparkles"
            }
        }
        
        var backgroundColor: Color {
            switch self {
            case .addCredential: return .accentColor
            case .shareAccess: return .purple
            case .deviceSettings: return .orange
            case .memberProfile: return .green
            case .customAutomation: return .blue
            }
        }
    }
    
    // MARK: - Single Instance
    static let shared = SheetManager()
    
    // MARK: - Private Properties
    private var autoDismissTimer: Timer?
    
    // MARK: - Public Methods
    func present(_ type: SheetType, delay: TimeInterval = 0.5) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Cancel any existing timer
            self.autoDismissTimer?.invalidate()
            
            self.currentType = type
            self.isActive = true
            self.dismissDelay = delay
            
            // Schedule automatic dismissal
            if delay > 0 {
                self.autoDismissTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
                    Task { @MainActor in
                        self.presentDismissal()
                    }
                }
                RunLoop.main.add(self.autoDismissTimer!, forMode: .common)
            }
        }
        
        performHaptic(.medium)
    }
    
    func dismiss() {
        presentDismissal()
    }
    
    private func presentDismissal() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            isActive = false
            currentType = nil
        }
        performHaptic(.light)
    }
    
    // MARK: - Convenience Wrappers
    func presentAddMenu() {
        present(.addCredential)
    }
    
    func presentShareView() {
        present(.shareAccess)
    }
}

// MARK: - View Extension for Easy Access
extension View {
    /// Present a modal sheet with unified manager
    func presentingSheet(_ manager: SheetManager) -> some View {
        selfsheet(isPresented: $manager.isActive) {
            if let type = manager.currentType {
                SheetPresenter(type: type, onDismiss: { manager.dismiss() })
            }
        }
    }
}

// MARK: - Sheet Presenter Container
struct SheetPresenter: View {
    let type: SheetManager.Shell
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Header bar
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.gray)
            }
            .padding()
            
            // Content based on sheet type
            switch type {
            case .addCredential:
                AddCredentialSheet(onComplete: onDismiss)
            case .shareAccess:
                ShareAccessSheet(onComplete: onDismiss)
            case .deviceSettings:
                DeviceSettingsSheet(onComplete: onDismiss)
            case .memberProfile:
                MemberProfileSheet(onComplete: onDismiss)
            case .customAutomation:
                CustomAutomationSheet(onComplete: onDismiss)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

// MARK: - Placeholder Sheets (Implementation Required)
struct AddCredentialSheet: View {
    let onComplete: () -> Void
    
    var body: some View {
        Text("🔧 Add Credential Implementation")
            .font(.title2)
            .foregroundColor(.secondary)
    }
}

struct ShareAccessSheet: View {
    let onComplete: () -> Void
    
    var body: some View {
        Text("👥 Share Access Implementation")
            .font(.title2)
            .foregroundColor(.secondary)
    }
}

struct DeviceSettingsSheet: View {
    let onComplete: () -> Void
    
    var body: some View {
        Text("⚙️ Device Settings Implementation")
            .font(.title2)
            .foregroundColor(.secondary)
    }
}

struct MemberProfileSheet: View {
    let onComplete: () -> Void
    
    var body: some View {
        Text("👤 Member Profile Implementation")
            .font(.title2)
            .foregroundColor(.secondary)
    }
}

struct CustomAutomationSheet: View {
    let onComplete: () -> Void
    
    var body: some View {
        Text("✨ Custom Automation Implementation")
            .font(.title2)
            .foregroundColor(.secondary)
    }
}

// MARK: - Preview
#if DEBUG
struct SheetManager_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .sheetManagerInstance()
    }
}
#endif
