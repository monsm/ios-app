// Dial.swift —— 本设计的 signature：蚀刻刻度盘。
//
// 它不是装饰：外圈 60 格蚀刻刻度真的在量"开锁链推进到哪一步"，
// 进度弧走的是真命令链（查钥匙 → 连 BLE → cmd04 → 回执），不是假动画。
// 失败时弧停在断开的位置并变朱红 —— 不假装成功。
import SwiftUI

/// 刻度盘相位。这些相位与真实命令链一一对应，不是随机进度。
enum DialPhase: Equatable {
    case idle            // 就绪，可以开
    case reaching        // 查钥匙 / 建链
    case sending         // 下发 cmd04
    case waiting         // 等回执
    case opened          // 成功（弧走满）
    case failed(String)  // 失败（弧停在断点）

    /// 真实进度 0...1。failed 停在断开处。
    var progress: Double {
        switch self {
        case .idle: return 0
        case .reaching: return 0.18
        case .sending: return 0.46
        case .waiting: return 0.72
        case .opened: return 1
        case .failed: return 0.72
        }
    }

    /// 中心读数（定宽词，换态只换词不换位置）。
    var word: String {
        switch self {
        case .idle: return "就绪"
        case .reaching: return "寻锁"
        case .sending: return "下发"
        case .waiting: return "等待"
        case .opened: return "已开"
        case .failed: return "失败"
        }
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    var isBusy: Bool {
        switch self {
        case .reaching, .sending, .waiting: return true
        default: return false
        }
    }
}

/// 蚀刻刻度盘。直径由环境值 `dialDiameter` 传入，页面不各写魔法数。
struct Dial: View {
    let phase: DialPhase
    /// 中心主读数下面的单位小字（例如「上次 3 小时前」）。
    let footnote: String
    /// 底部提示语（「轻点开锁」/「蓝牙未连接」）。
    let hint: String
    /// 是否可点（不可点时灰化，但仍显示刻度 —— 刻度是"这台锁还在"的证据）。
    let enabled: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dialDiameter) private var diameter

    private static let tickCount = 60

    /// 逐格点亮：只在推进过程中亮到当前进度那一格。
    private var litTicks: Int { Int(phase.progress * Double(Self.tickCount)) }

    var body: some View {
        Button(action: action) {
            ZStack {
                ticks
                progressArc
                hub
            }
            .frame(width: diameter, height: diameter)
            .contentShape(.circle)
        }
        .buttonStyle(DialPressStyle())
        .disabled(!enabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("开锁")
        .accessibilityValue("\(phase.word)。\(footnote)")
        .accessibilityHint(enabled ? "轻点开锁" : "当前不可开锁")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: 蚀刻刻度
    private var ticks: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = min(size.width, size.height) / 2
            for i in 0 ..< Self.tickCount {
                // 从正下方起顺时针一圈；每 5 格一根长刻度。
                let angle = Angle.degrees(90 + Double(i) / Double(Self.tickCount) * 360)
                let major = i % 5 == 0
                let length: CGFloat = major ? 10 : 5
                let lit = i <= litTicks && phase.progress > 0
                let color: Color = lit
                    ? (phase.isFailed ? V.C.critical : V.C.blue)
                    : V.C.text3.opacity(major ? 0.4 : 0.2)
                let inner = outer - length
                let p1 = CGPoint(x: center.x + cos(angle.radians) * inner,
                                 y: center.y + sin(angle.radians) * inner)
                let p2 = CGPoint(x: center.x + cos(angle.radians) * outer,
                                 y: center.y + sin(angle.radians) * outer)
                var path = Path()
                path.move(to: p1)
                path.addLine(to: p2)
                context.stroke(path, with: .color(color), lineWidth: major ? 1.4 : 0.7)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    // MARK: 真实进度弧
    //
    // 弧下面永远压一条轨道（rail）。这是仪器该有的东西：没有轨道，进度为 0 时
    // 表盘就只剩一圈刻度加浮在中间的字，读起来像"坏了"，而不像"待触发"。
    private var progressArc: some View {
        ZStack {
            // 轨道只在推进时出现。静止时画一圈灰环，读起来像"装饰圆"而不是"待触发的仪器"。
            Circle()
                .stroke(V.C.hairline, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: diameter - 28, height: diameter - 28)
                .opacity(phase.progress > 0 ? 1 : 0)
            Circle()
                .trim(from: 0, to: max(0.0001, phase.progress))
                .stroke(
                    phase.isFailed ? V.C.critical : V.C.blue,
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
                .frame(width: diameter - 28, height: diameter - 28)
                .animation(reduceMotion ? nil : V.M.sweep, value: phase.progress)
        }
        .accessibilityHidden(true)
    }

    // MARK: 中心读数
    //
    // 失败时中心词跟着变红：三处（红弧 / 中心词 / 横幅）如果只有弧在变，
    // 眼睛要先读到弧才明白"出事了"，而词还是黑的 —— 那是把最重要的信息放最后。
    private var hub: some View {
        VStack(spacing: V.S.gapXS) {
            Text(phase.word)
                .font(V.F.number30)
                .foregroundStyle(phase.isFailed ? V.C.critical : (enabled ? V.C.text1 : V.C.text3))
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(reduceMotion ? nil : V.M.snap, value: phase.word)
            Text(footnote)
                .font(V.F.unit)
                .foregroundStyle(V.C.text3)
                .tracking(0.6)
            Text(hint)
                .font(V.F.footnote)
                .foregroundStyle(enabled ? V.C.text2 : V.C.text3)
                .padding(.top, V.S.gapS)
        }
        .frame(width: diameter * 0.52)
    }
}

/// 按压：只做 transform，不改 bounds。可从当前值起跳。
struct DialPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.972 : 1)
            .animation(V.M.snap, value: configuration.isPressed)
    }
}

// MARK: - 直径通过 Environment 传递
//
// 用 iOS 17+ 的 @Entry 宏（一行替代手写 EnvironmentKey 的十行样板）。
// 页面只写 .environment(\.dialDiameter, 260)，不各写魔法数。
extension EnvironmentValues {
    @Entry var dialDiameter: CGFloat = 260
}
