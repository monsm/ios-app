import SwiftUI

// MARK: - Intelligence Center (智能洞察中心)
// 使用场景：Tab 3 - 替代原来的 Settings+Records 混合页
// 设计原则：上半部可视化数据 + 中间快速设置 + 底部完整入口

struct IntelligenceCenter: View {
    @EnvironmentObject var app: AppViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 第一部分：实时洞察图表
                LiveInsightsGrid()
                
                Divider()
                    .overlay(Color.gray.opacity(0.08))
                
                // 第二部分：高频快捷开关
                QuickAccessSettings()
                
                Divider()
                    .overlay(Color.gray.opacity(0.08))
                
                // 第三部分：高级功能入口
                AdvancedFeaturesSection()
            }
            .padding(.horizontal, 20)
        }
        .background(Color(UIColor.systemGroupedBackground))
    }
}

// MARK: - Live Insights Grid (实时数据网格)
struct LiveInsightsGrid: View {
    @EnvironmentObject var app: AppViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            SectionHeader(title: "今日洞察", description: "解锁频次 & 成员活跃度")
            
            HStack(spacing: 16) {
                // 解锁频率卡
                UnlockFrequencyCard()
                    .flexibleWidth()
                
                // 活跃成员卡
                ActiveMembersCard()
                    .flexibleWidth()
            }
            
            // 周统计趋势图（占满宽度）
            WeeklyTrendChart()
                .frame(maxHeight: 120)
        }
        .glassBackground(level: .ambient)
        .padding(.top, 12)
    }
}

// 通用卡片组件
struct UnlockFrequencyCard: View {
    @EnvironmentObject var app: AppViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            Label("今日开锁次数", systemImage: "lock.shield.fill")
                .font(.headline)
            
            NumberDisplay(value: 8, unit: "次", color: .green)
            
            CircularProgress(progress: 0.65)
                .frame(width: 80, height: 80)
            
            Text("超过上周 23%")
                .font(.caption)
                .foregroundStyle(.green)
        }
        .padding(20)
    }
}

struct ActiveMembersCard: View {
    @EnvironmentObject var app: AppViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            Label("最活跃成员", systemImage: "person.2.fill")
                .font(.headline)
            
            MemberAvatarRing(members: ["张三", "李四"])
                .frame(height: 60)
            
            Text("本周贡献 83% 开锁")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}

struct WeeklyTrendChart: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("近 7 天趋势")
                .font(.subheadline.weight(.medium))
            
            ChartArea(points: Array(repeating: 0, count: 7))
                .frame(height: 80)
        }
        .padding(16)
    }
}

// MARK: - Quick Access Settings (快速访问设置)
struct QuickAccessSettings: View {
    @EnvironmentObject var app: AppViewModel
    
    let quickSettings = [
        SettingItem(icon: "bolt.fill", label: "自动开锁", value: app.autoUnlockEnabled, type: .toggle),
        SettingItem(icon: "wifi.fill", label: "蓝牙优先", value: app.bluetoothPriority, type: .toggle),
        SettingItem(icon: "moon.fill", label: "夜间模式", value: app.nightModeEnabled, type: .toggle),
        SettingItem(icon: "waveform.fill", label: "震动反馈", value: app.hapticStrength, type: .slider),
        SettingItem(icon: "bell.slash.fill", label: "勿扰模式", value: app.doNotDisturb, type: .toggle),
        SettingItem(icon: "battery.low", label: "省电模式", value: app.powerSaveMode, type: .toggle),
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "高频设置", description: "日常使用的 6 个核心开关")
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(quickSettings) { setting in
                    QuickSettingTile(setting: setting)
                }
            }
            
            Button("查看全部 17 个分类设置") {
                openAllSettings()
            }
            .secondaryButton(title: "进入全部设置", icon: "chevron.right") {
                openAllSettings()
            }
        }
        .padding(.top, 12)
    }
    
    private func openAllSettings() {
        // Navigate to full settings page
    }
}

// MARK: - Advanced Features Section (高级功能入口)
struct AdvancedFeaturesSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "进阶功能", description: "数据分析与深度定制")
            
            FeatureListRow(
                title: "自定义自动化规则",
                subtitle: "设置触发条件与响应动作",
                icon: "sparkles",
                action: {}
            )
            
            FeatureListRow(
                title: "家庭成员管理",
                subtitle: "权限分配与角色配置",
                icon: "people",
                action: {}
            )
            
            FeatureListRow(
                title: "设备固件更新",
                subtitle: "检查并安装最新版本",
                icon: "arrow.down.circle",
                action: {}
            )
        }
        .padding(.top, 12)
    }
}

// MARK: - Helper Components

struct SectionHeader: View {
    let title: String
    let description: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.weight(.bold))
            
            if let description = description {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct QuickSettingTile: View {
    let setting: SettingItem
    
    var body: some View {
        VStack(spacing: 8) {
            Label(setting.label, systemImage: setting.icon)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.primary)
            
            if setting.type == .toggle {
                Toggle(isOn: Binding(get: { setting.value as? Bool ?? false }, set: { _ in })) {
                    EmptyView()
                }
                .toggleStyle(.switch)
                .labelsHidden()
            } else if setting.type == .slider {
                Slider(value: Binding(get: { setting.value as? Double ?? 0.5 }, set: { _ in }))
                    .labelsHidden()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glassBackground(level: .ambient)
    }
}

struct FeatureListRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(.accentColor)
                    .frame(width: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.tertiary)
            }
            .padding()
            .glassBackground(level: .ambient)
        }
        .buttonStyle(.plain)
        .hapticOnTap()
    }
}

// MARK: - Preview
#if DEBUG
struct IntelligenceCenter_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            IntelligenceCenter()
                .environmentObject(AppViewModel.preview)
        }
    }
}
#endif
