// ToastCenter.swift —— 全局提示条（原 App/Core/ToastCenter.swift 的等价实现）。
//
// 来源：原 App/Core/ToastCenter.swift + AppState.showToast（全 App 顶部一条轻提示）。
// 用法：任意页面动作完成后调 AppToast.shared.show("已保存")；RootView 顶部常驻挂 ToastHost。
// 边界：只提示「刚发生了什么」，不用它承载需要用户决策的信息（那些走页面内说明/弹窗）。
import SwiftUI
import UIKit

enum ToastTone {
    case info, ok, warn

    var color: Color {
        switch self {
        case .info: return V.C.blue
        case .ok: return V.C.rewardGreen
        case .warn: return V.C.pink
        }
    }
}

@MainActor
@Observable
final class AppToast {
    static let shared = AppToast()
    private init() {}

    private(set) var message: String?
    private(set) var tone: ToastTone = .info
    private var hideTask: Task<Void, Never>?

    func show(_ text: String, tone: ToastTone = .info) {
        message = text
        self.tone = tone
        hideTask?.cancel()
        // 2026-11-05（全技能审核 · 无障碍）：Toast 2.6 秒自动消失，读屏用户来不及听。
        // VoiceOver 开启时延长到 6 秒，并主动播报一次；普通用户仍保持原来的节奏。
        let hold: Double = UIAccessibility.isVoiceOverRunning ? 6.0 : 2.6
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: text)
        }
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(hold))
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }
}

/// 顶部悬浮提示条（v7 卡片语言；不遮导航标题，只压在上缘安全区内）。
struct ToastHost: View {
    @State private var toast = AppToast.shared
    /// 2026-11-01 修复：提示条的 `transition(.move)` **没有减弱动态守卫** ——
    /// 用户开了「减弱动态效果」后它仍然从顶部滑入。`reducedmotion` 闸门只扫 `.animation(`，
    /// `transition(` 是它覆盖不到的第二类（已同步扩判据）。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 「减少透明度」：系统设置或 App 内同档开关任一开启，玻璃退化为不透明卡片。
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency

    var body: some View {
        VStack {
            if let message = toast.message {
                HStack(spacing: V.S.gapS) {
                    Circle()
                        .fill(toast.tone.color)
                        .frame(width: V.List.dotSize, height: V.List.dotSize)
                        .accessibilityHidden(true)
                    Text(message)
                        .font(V.F.footnote)
                        .foregroundStyle(V.C.text1)
                        // 2026-11-01：`lineLimit(2)` → `4`。
                        // 最长的一条 toast 是 45 字（「已归档 · 历史留在记录页，可随时恢复 TA」这类），
                        // 默认字号下 2 行刚好放下；但 `V.F.footnote` 随 Dynamic Type 缩放，
                        // AX 档下同一句要 4 行 —— 而 toast **会自己消失**，被截掉的部分用户永远读不到。
                        // 宁可多占两行，也不要把一条临时消息截断。
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, V.S.gapM)
                .padding(.vertical, V.S.gapS)
                // 2026-11-01：改用**原生液态玻璃**（与浮动 Tab 栏同一入口 `VGlassSurface`）。
                // 提示条是"浮在内容之上的临时层"，正是 Liquid Glass 的设计场景；
                // 旧的 `V.C.tabGlass` 只是一层半透明色，没有折射与高光。
                // 「减少透明度」时退化为不透明卡片（与 Tab 栏同一判据，不另写一套）。
                .background {
                    VGlassSurface(solid: systemReduceTransparency || SettingsStore.shared.reduceTransparency,
                                  cornerRadius: V.R.action,
                                  tint: V.C.tabGlass,
                                  stroke: V.C.tabEdge) {
                        Color.clear
                    }
                }
                .padding(.horizontal, V.S.cardGutter)
                .padding(.top, V.S.gapS)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(message)
            }
            Spacer(minLength: 0)
        }
        // 2026-11-05（全技能审核 · 动效）：Toast 的 .transition 一直没有动画驱动 ——
        // AppToast.show 只是改 @Observable 值，没有 withAnimation，ToastHost 也没挂 .animation，
        // 所以滑入/淡出从未播放过。这里补上值驱动，Reduce Motion 时退回无动画。
        .animation(reduceMotion ? nil : V8.M.move, value: toast.message)
        .allowsHitTesting(false)
    }
}
