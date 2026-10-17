import SwiftUI

// MARK: - Unified Access Hub (统一访问凭证门户)
// 使用场景：凭证 Tab 的完整页面
// 设计原则：按类型分组展示 + 底部 sheet 菜单添加

struct CredentialHub: View {
    @EnvironmentObject var app: AppViewModel
    @StateObject private var sheetManager = SheetManager()
    
    // 凭证分类数据源
    enum CredentialCategory: String, CaseIterable {
        case ekeys = "电子钥匙"
        case pins = "密码"
        case biometrics = "生物识别"
        case timePasses = "临时通行证"
        case shares = "共享权限"
        
        var systemImage: String {
            switch self {
            case .ekeys: return "key.fill"
            case .pins: return "number.circle.fill"
            case .biometrics: return "fingerprint"
            case .timePasses: return "clock.badge.clock"
            case .shares: return "person.crop.circle.badge.plus"
            }
        }
        
        var color: Color {
            switch self {
            case .ekeys: return .blue
            case .pins: return .orange
            case .biometrics: return .green
            case .timePasses: return .purple
            case .shares: return .pink
            }
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        // Category Sections
                        ForEach(CredentialCategory.allCases, id: \.self) { category in
                            credentialSection(for: category)
                                .padding(.horizontal, 20)
                        }
                        
                        Spacer().frame(height: 80)
                    }
                }
                
                AddButton(sheetManager: sheetManager)
                    .offset(x: -16, y: -16)
                    .padding(16)
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
    }
    
    // MARK: - Private Methods
    
    private func credentialSection(for category: CredentialCategory) -> some View {
        Section(header: categoryHeader(category)) {
            ForEach(categorizedCredentials(category), id: \.id) { cred in
                CredentialRowView(credential: cred, category: category)
                    .padding(.vertical, 4)
            }
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
    
    private func categorizedCredentials(_ category: CredentialCategory) -> [Credential] {
        // This would be populated from your actual data source
        // For now returning empty array
        return []
    }
    
    private func categoryHeader(_ category: CredentialCategory) -> some View {
        HStack(spacing: 12) {
            Image(systemName: category.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(category.color)
            
            Text(category.rawValue)
                .font(.headline.weight(.semibold))
                .foregroundColor(.primary)
            
            Spacer()
            
            Text("\(credCount(for: category))")
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 12)
    }
    
    private func credCount(for category: CredentialCategory) -> Int {
        // Would be count from actual data
        return 0
    }
    
    // MARK: - Subviews
    
    struct AddButton: View {
        @ObservedObject var sheetManager: SheetManager
        
        var body: some View {
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    sheetManager.presentAddMenu()
                }
                performHaptic(.heavy)
            }) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(.accentColor)
            }
            .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 8)
        }
    }
}

// MARK: - Credential Row View
struct CredentialRowView: View {
    let credential: Credential
    let category: CredentialHub.CredentialCategory
    
    var body: some View {
        Button(action: {}) {
            HStack(spacing: 16) {
                // Icon badge
                ZStack {
                    Circle()
                        .fill(category.color.opacity(0.1))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: category.systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(category.color)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(credential.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                    
                    Text(credential.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if credential.expireAt != nil {
                        Text("有效期至: \(credential.expireAt?.formattedDate ?? "永久")")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                ChevronIndicator()
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .hapticOnTap(.light)
    }
}

// MARK: - Preview
#if DEBUG
struct CredentialHub_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            CredentialHub()
                .environmentObject(AppViewModel.preview)
        }
    }
}
#endif
