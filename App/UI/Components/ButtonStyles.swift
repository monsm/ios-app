import SwiftUI

// MARK: - 统一按钮样式系统 (Apple Design Language)
// 所有按钮组件都包含：视觉反馈 + Haptic 触觉反馈 + Animation Spring Physics

// ============================================================================
// PRIMARY BUTTON STYLE - 主操作按钮
// 使用场景：页面级主要操作（开锁 / 添加设备 / 确认）
// 视觉特征：全屏宽度，主色调填充，圆角 14pt
// 交互反馈：缩放动画 + 中等震动
// ============================================================================
struct PrimaryButtonStyle: ButtonStyle {
    let title: String
    let icon: String?
    let action: () -> Void
    
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .frame(width: 24)
                    .foregroundColor(.white.opacity(0.9))
            }
            
            configuration.label
                .font(.headline.weight(.semibold))
                .tracking(0.5)
            
            Spacer()
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: configuration.isPressed ?
                            Color.accentColor.opacity(0.75) :
                            Color.accentColor,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .foregroundColor(.white)
        .scaleEffect(configuration.isPressed ? 0.97 : 1.0, anchor: .center)
        .animation(.spring(
            response: 0.35,
            dampingFraction: 0.65,
            blendDuration: 0.2
        ), value: configuration.isPressed)
        .onTapGesture(count: 1) {
            action()
            performHaptic(.medium)
        }
    }
}

// ============================================================================
// SECONDARY BUTTON STYLE - 次级按钮
// 使用场景：次要操作（取消 / 返回 / 查看更多）
// 视觉特征：边框风格，无填充，透明背景
// 交互反馈：轻微缩放 + 轻震动
// ============================================================================
struct SecondaryButtonStyle: ButtonStyle {
    let title: String
    let icon: String?
    let action: () -> Void
    
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
            }
            
            configuration.label
                .fontWeight(.medium)
                .tracking(0.3)
            
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    configuration.isPressed ?
                        Color.accentColor.opacity(0.6) :
                        Color.accentColor.opacity(0.25),
                    lineWidth: 1.5
                )
        )
        .foregroundStyle(
            configuration.isPressed ?
                Color.accentColor.opacity(0.8) :
                Color.accentColor
        )
        .scaleEffect(configuration.isPressed ? 0.98 : 1.0, anchor: .center)
        .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
        .onTapGesture(count: 1) {
            action()
            performHaptic(.light)
        }
    }
}

// ============================================================================
// DANGER BUTTON STYLE - 危险操作按钮
// 使用场景：删除 / 重置 / 注销等不可逆操作
// 视觉特征：红色填充，警告图标，需要二次确认
// 交互反馈：重震动 + 抖动动画
// ============================================================================
struct DangerButtonStyle: ButtonStyle {
    let action: () -> Void
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: configuration.isPressed ?
                                Color.red.opacity(0.7) :
                                Color.red,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0, anchor: .center)
            .animation(
                .spring(response: 0.25, dampingFraction: 0.5, blendDuration: 0.15),
                value: configuration.isPressed
            )
            .onTapGesture(count: 1) {
                performHaptic(.heavy)
                action()
            }
            .onLongPressGesture(minimumDuration: 0.3, pressing: { pressing in
                withAnimation(.easeInOut(duration: 0.2)) {
                    performHaptic(.heavy)
                }
            } onEnded: { _ in
                performHaptic(.heavy)
            })
    }
}

// ============================================================================
// ICON BUTTON STYLE - 图标按钮
// 使用场景：工具栏图标（分享/设置/更多）
// 视觉特征：圆形图标背景，居中布局
// 交互反馈：微震动 + 缩放
// ============================================================================
struct IconButtonStyle: ButtonStyle {
    let systemImage: String
    let color: Color
    let size: CGFloat = 28
    let action: () -> Void
    
    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Circle()
                .fill(configuration.isPressed ?
                    color.opacity(0.15) :
                    color.opacity(0.1))
                .frame(width: 40, height: 40)
            
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(color)
        }
        .scaleEffect(configuration.isPressed ? 0.92 : 1.0, anchor: .center)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
        .onTapGesture(count: 1) {
            action()
            performHaptic(.light)
        }
    }
}

// ============================================================================
// SWIFTUI INTEGRATION - 方便直接使用的构造器
// ============================================================================

extension View {
    /// 应用主按钮样式（带标题和图标）
    func primaryButton(title: String, icon: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .frame(width: 24)
                }
                Text(title)
                    .font(.headline)
                Spacer()
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .background(Color.accentColor.cornerRadius(14))
            .foregroundColor(.white)
        }
        .buttonStyle(PrimaryButtonStyle(title: title, icon: icon, action: action))
    }
    
    /// 应用次按钮样式
    func secondaryButton(title: String, icon: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                }
                Text(title)
                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor.opacity(0.25), lineWidth: 1.5)
            )
            .foregroundColor(.accentColor)
        }
        .buttonStyle(SecondaryButtonStyle(title: title, icon: icon, action: action))
    }
    
    /// 应用危险按钮样式
    func dangerButton(action: @escaping () -> Void) -> some View {
        self.buttonStyle(DangerButtonStyle(action: action))
    }
}

// MARK: - Example Usage
#if DEBUG
struct ButtonStyles_Previews: PreviewProvider {
    static var previews: some View {
        List {
            Section(header: Text("🎯 主按钮")) {
                Button("手动开锁", action: {})
                    .primaryButton(title: "手动开锁", icon: "lock.open")
                
                Button("连接设备", action: {})
                    .primaryButton(title: "连接设备", icon: "wifi")
            }
            
            Section(header: Text("⚪ 次级按钮")) {
                Button("取消", action: {})
                    .secondaryButton(title: "取消", icon: "xmark")
                
                Button("查看帮助", action: {})
                    .secondaryButton(title: "查看帮助", icon: "questionmark.circle")
            }
            
            Section(header: Text("🔴 危险按钮")) {
                Button("确认删除？", action: {})
                    .dangerButton { print("Delete triggered") }
            }
            
            Section(header: Text("🔘 图标按钮")) {
                Button(action: {})
                    .buttonStyle(IconButtonStyle(systemImage: "share", color: .blue))
                
                Button(action: {})
                    .buttonStyle(IconButtonStyle(systemImage: "gear", color: .orange))
                
                Button(action: {})
                    .buttonStyle(IconButtonStyle(systemImage: "heart", color: .red))
            }
        }
        .listStyle(.insetGrouped)
    }
}
#endif
