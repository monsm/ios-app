import SwiftUI

// MARK: - Collapsible Status Strip (可折叠状态条)
// 使用场景：Hero Card 底部的状态信息栏
// 功能：连接时间/RSSI/最后操作时间 (滑动展开收起)
// 交互：上滑展开，下滑收起，点击快速查看上次操作

struct CollapsibleStatusStrip: View {
    @EnvironmentObject var app: AppViewModel
    @ObservedObject var sense: SenseKit
    
    @State private var isExpanded = false
    @State private var showAnimation = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 收起状态：单行摘要
            HStack(spacing: 16) {
                Image(systemName: "info.circle")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                
                Text(infoSummary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .glassBackground(level: .ambient)
            .contentShape(Rectangle())
            .onTapGesture(count: 1) { toggleExpand() }
            
            if isExpanded || showAnimation {
                // 展开状态：多行详细信息
                ExpandableDetailsView(sense: sense)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear { showAnimation = true }
            }
        }
        .onChange(of: isExpanded) { _, newValue in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                performHaptic(newValue ? .light : .medium)
            }
        }
    }
    
    // MARK: - Computed Properties
    private var infoSummary: String {
        guard let lastRSSI = sense.lastRssi else {
            return "未读取信号"
        }
        
        var parts: [String] = []
        if let connTime = sense.connectionEstablished {
            parts.append("连接 \(connTime.formattedDate)")
        }
        parts.append("\(lastRSSI) dBm")
        
        return parts.joined(separator: " • ")
    }
    
    // MARK: - Actions
    private func toggleExpand() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            isExpanded.toggle()
            performHaptic(.light)
        }
    }
}

// 展开详细视图
struct ExpandableDetailsView: View {
    @ObservedObject var sense: SenseKit
    
    var body: some View {
        VStack(spacing: 16) {
            DetailRow(
                icon: "antenna.radiowaves.left.and.right",
                label: "信号强度",
                value: "\(sense.lastRssi ?? 0) dBm",
                color: signalColor
            )
            
            if let connTime = sense.connectionEstablished {
                DetailRow(
                    icon: "clock",
                    label: "连接时长",
                    value: formattedConnectionTime(connTime),
                    color: .accentColor
                )
            }
            
            DetailRow(
                icon: "checkmark.circle",
                label: "最后操作",
                value: sense.lastOperationDescription,
                color: .green
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    private var signalColor: Color {
        guard let rssi = sense.lastRssi else { return .secondary }
        switch rssi {
        case -30...-40: return .systemGreen
        case -41...-50: return .systemBlue
        default: return .orange
        }
    }
    
    private func formattedConnectionTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        
        if minutes > 0 {
            return "\(minutes) 分 \(seconds) 秒"
        } else {
            return "\(seconds) 秒前"
        }
    }
}

// 详情行组件
struct DetailRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 20)
            
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
        }
    }
}

// MARK: - Preview
#if DEBUG
extension CollapsibleStatusStrip {
    init(sense: SenseKit = SenseKit.preview) {
        self._sense = ObservedObject(wrappedValue: sense)
    }
}
#endif
