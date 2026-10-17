import SwiftUI

// MARK: - Hero Lock Card (智能首页主卡片)
// 使用场景：设备 Tab 顶部的 60% 屏幕高度区域
// 功能：显示当前锁状态 + 解锁 dial + RSSI 信号强度
// 设计原则：最小操作步数，手势优先交互

struct HeroLockCard: View {
    // MARK: - Properties
    @EnvironmentObject var app: AppViewModel
    @StateObject private var sense: SenseKit
    
    let lockDevice: Device
    
    // MARK: - Computed Properties
    var connectionStatus: ConnectionStatus {
        guard let status = sense.connectionState else { return .disconnected }
        return status
    }
    
    var rssiValue: Int? {
        sense.lastRssi
    }
    
    var connectionTime: Date? {
        sense.connectionEstablished
    }
    
    var isConnected: Bool {
        connectionStatus == .connected
    }
    
    var unlockAnimationProgress: CGFloat {
        guard let rssi = rssiValue else { return 0.5 }
        // RSSI -60 ~ -40 → progress 0 ~ 1
        let clamped = min(max(rssi, -60), -40)
        return CGFloat((clamped - (-60)) / 20)
    }
    
    var signalStrengthColor: Color {
        guard let rssi = rssiValue else { return .secondary }
        switch rssi {
        case -30...-40: return .systemGreen      // 极好
        case -41...-50: return .systemBlue       // 好
        case -51...-55: return .accentColor      // 中等
        case -56...-60: return .orange           // 弱
        default: return .red                    // 极弱
        }
    }
    
    // MARK: - Body
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background gradient layer
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.15),
                    Color.accentColor.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack(spacing: 0) {
                // Top section: lock icon + status
                LockHeaderSection(isConnected: isConnected, connectionTime: connectionTime)
                
                Divider()
                    .overlay(Color.gray.opacity(0.08))
                
                // Middle section: unlock dial
                UnlockDialSection(progress: unlockAnimationProgress, color: signalStrengthColor)
                
                Divider()
                    .overlay(Color.gray.opacity(0.08))
                
                // Bottom section: quick actions
                QuickActionsSection(lockDevice: lockDevice)
            }
            .padding(.top, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
            .glassBackground(level: .elevated)
            
            // Floating action button (FAB) for main unlock
            FloatingActionButton(isConnected: isConnected, action: { manuallyUnlock() })
                .offset(y: -12)
        }
        .onAppear {
            Task { await sense.update() }
        }
    }
    
    // MARK: - Actions
    private func manuallyUnlock() {
        performHaptic(.heavy)
        BLEService.shared.unlock(mac: lockDevice.mac)
    }
    
    // MARK: - Subviews
    
    // 顶部状态栏
    struct LockHeaderSection: View {
        let isConnected: Bool
        let connectionTime: Date?
        
        var body: some View {
            HStack(spacing: 16) {
                Image(systemName: "lock.closed")
                    .font(.system(size: 32))
                    .foregroundStyle(isConnected ? .systemGreen : .gray)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("门锁")
                        .font(.title2.weight(.bold))
                    
                    Text(isConnected ? "已连接 • \(connectionTime?.formattedDate ?? "未知")" : "未连接")
                        .font(.subheadline)
                        .foregroundColor(isConnected ? .green : .gray)
                }
                
                Spacer()
                
                if isConnected {
                    CircularProgress(progress: Double(unlockAnimationProgress))
                        .frame(width: 40, height: 40)
                } else {
                    Image(systemName: "wifi.off")
                        .font(.title3)
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }
    
    // 中间解锁盘
    struct UnlockDialSection: View {
        let progress: CGFloat
        let color: Color
        
        var body: some View {
            VStack(spacing: 24) {
                // Dial circle
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.15), lineWidth: 8)
                    
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: progress)
                    
                    // Center text
                    VStack(spacing: 4) {
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 28, weight: .bold))
                        
                        Text("靠近开锁")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 180, height: 180)
                
                // Signal strength indicator
                HStack(spacing: 12) {
                    Text("信号强度:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if let rssi = SenseKit.shared.lastRssi {
                        Text("\(rssi) dBm")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(signalStrengthColor)
                    } else {
                        Text("未读取信号")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // 底部快捷操作区
    struct QuickActionsSection: View {
        let lockDevice: Device
        
        var body: some View {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                ActionButton(
                    icon: "arrow.clockwise",
                    label: "重连",
                    color: .blue,
                    action: {
                        BLEService.shared.connect(mac: lockDevice.mac)
                    }
                )
                
                ActionButton(
                    icon: "lock.open",
                    label: "手动开锁",
                    color: .green,
                    action: {
                        BLEService.shared.unlock(mac: lockDevice.mac)
                    }
                )
                
                ActionButton(
                    icon: "person.badge.plus",
                    label: "分享",
                    color: .purple,
                    action: {
                        // Navigate to share screen
                    }
                )
                
                ActionButton(
                    icon: "list.bullet",
                    label: "记录",
                    color: .orange,
                    action: {
                        // Navigate to records
                    }
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }
    
    // 浮动按钮 (FAB)
    struct FloatingActionButton: View {
        let isConnected: Bool
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                Image(systemName: isConnected ? "lock.open" : "lock")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 64, height: 64)
            .background(
                RoundedRectangle(cornerRadius: 32)
                    .fill(isConnected ? Color.green : Color.accentColor)
            )
            .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 4)
            .scaleEffect(isConnected ? 1.05 : 1.0, anchor: .center)
        }
    }
    
    // 通用动作按钮
    struct ActionButton: View {
        let icon: String
        let label: String
        let color: Color
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                VStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundStyle(color)
                    
                    Text(label)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .glassBackground(level: .ambient)
            }
            .buttonStyle(.plain)
            .hapticOnTap()
        }
    }
}

// MARK: - Preview
#if DEBUG
struct HeroLockCard_Previews: PreviewProvider {
    static var previews: some View {
        GeometryReader { geometry in
            HeroLockCard(lockDevice: Device.preview)
                .environmentObject(AppViewModel.preview)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color(UIColor.systemGroupedBackground))
    }
}
#endif
