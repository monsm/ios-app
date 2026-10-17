import SwiftUI

// MARK: - 玻璃拟物背景系统 (Apple Material Design)
// 使用 UIBlurEffect 实现 iOS 原生毛玻璃效果 + 渐变底色 + 深度阴影

struct GlassBackground: ViewModifier {
    // MARK: - Properties
    let elevationLevel: Elevation  // 阴影层级：elevated / ambient / subtle
    
    enum Elevation {
        case elevated  // 主卡片层级：深阴影
        case ambient   // 次要层级：浅阴影
        case subtle    // 微交互层级：几乎无阴影
        
        var shadowRadius: CGFloat {
            switch self {
            case .elevated: return 12
            case .ambient: return 6
            case .subtle: return 2
            }
        }
        
        var shadowOffsetY: CGFloat {
            switch self {
            case .elevated: return 4
            case .ambient: return 2
            case .subtle: return 1
            }
        }
        
        var shadowOpacity: Double {
            switch self {
            case .elevated: return 0.08
            case .ambient: return 0.05
            case .subtle: return 0.03
            }
        }
        
        var cornerRadius: CGFloat {
            switch self {
            case .elevated: return 20
            case .ambient: return 16
            case .subtle: return 12
            }
        }
    }
    
    init() {
        self.init(level: .elevated)
    }
    
    init(level: Elevation) {
        self.elevationLevel = level
    }
    
    // MARK: - Body Implementation
    func body(content: Content) -> some View {
        content
            .background(
                ZStack(alignment: .topLeading) {
                    // Layer 1: 动态渐变底色 (响应主题色)
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.primary.opacity(0.06),      // 顶层渐变：主色极淡
                            Color.secondary.opacity(0.03)     // 底层渐变：副色更淡
                        ]),
                        startPoint: .topLeading,          // 从左上角开始
                        endPoint: .bottomTrailing         // 到右下角结束
                    )
                    
                    // Layer 2: iOS Material 毛玻璃 (hierarchical 模式有自适应透明度)
                    GeometryReader { geometry in
                        UIBlurEffectView(style: .systemMaterial)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .allowsHitTesting(false)       // 不阻挡触摸穿透
                    }
                    .ignoresSafeArea()                   // 延伸到安全区域外
                        
                    // Layer 3: 内边框高光 (增加质感)
                    RoundedRectangle(cornerRadius: elevationLevel.cornerRadius)
                        .strokeBorder(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.15),    // 左上高光
                                    Color.clear                    // 右下透明
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            // Apply rounded corners
            .cornerRadius(elevationLevel.cornerRadius)
            // Add depth shadow (spring physics feel)
            .shadow(
                color: .black.opacity(elevationLevel.shadowOpacity),
                radius: elevationLevel.shadowRadius,
                x: 0,
                y: elevationLevel.shadowOffsetY
            )
    }
}

// MARK: - View Extensions
extension View {
    /// 应用玻璃拟物背景
    /// - Parameter level: 阴影层级 (default: .elevated)
    /// - Returns: 修饰后的视图
    func glassBackground(level: GlassBackground.Elevation = .elevated) -> some View {
        modifier(GlassBackground(level: level))
    }
    
    /// 应用不同深度的卡片层级
    /// - Parameter level: 1-3 对应不同深度
    /// - Returns: 带有统一视觉层级的视图
    func cardElevation(_ level: Int) -> some View where Self : View {
        guard (1...3).contains(level) else {
            preconditionFailure("cardElevation level must be between 1 and 3")
        }
        
        let baseDepth = CGFloat(level) * 0.02  // 0.02 / 0.04 / 0.06 opacity
        let baseRadius = CGFloat(16 + level * 2)  // 18 / 20 / 22 pt
        
        return self
            .background(Color(.systemBackground))
            .cornerRadius(baseRadius)
            .shadow(color: .black.opacity(baseDepth), radius: 8 * CGFloat(level), x: 0, y: 2 * CGFloat(level))
            .overlay(
                RoundedRectangle(cornerRadius: baseRadius)
                    .stroke(Color.gray.opacity(0.06), lineWidth: 0.5)
            )
    }
}

// MARK: - Example Usage
#if DEBUG
struct GlassBackground_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            Text("🎨 玻璃拟物示例")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("使用 UIBlurEffect 模拟 iOS Material 设计语言")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Level 1: Elevated (默认)
            Card(title: "主卡片", subtitle: "深阴影层级")
                .glassBackground()
            
            Spacer().frame(height: 20)
            
            // Level 2: Ambient
            Card(title: "次要卡片", subtitle: "中等阴影层级")
                .glassBackground(level: .ambient)
            
            Spacer().frame(height: 20)
            
            // Level 3: Subtle
            Card(title: "微卡片", subtitle: "轻度阴影层级")
                .glassBackground(level: .subtle)
        }
        .padding()
        .background(Color(UIColor.systemGroupedBackground))
    }
}

// 辅助预览组件
struct Card: View {
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}
#endif
