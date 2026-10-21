import SwiftUI

// 881 字幕式过程条: 连接/开锁 验证/执行/完成 三步文字字幕
// 2026-10-20: 从被删除的 AccessibilityView.swift 中独立出来 (Q50 删面板, 但设备页仍用它显示过程字幕)。

// ---------- 881 字幕式过程条: 连接/开锁 验证/执行/完成 三步文字字幕 ----------
struct CaptionStepBar: View {
    var phase: Int
    var unlockState: AppState.UnlockState

    var body: some View {
        // 非过程态不显示, 听障用户可逐字跟读"现在进行到哪一步"
        if unlockState == .connecting || unlockState == .opening || unlockState == .success {
            captionRow
        }
    }
    private var captionRow: some View {
        HStack(spacing: XSpace.xs) {
            ForEach(0..<3, id: \.self) { i in
                captionStep(i)
            }
        }
        .vkFont(.caption)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(captionText)
    }
    @ViewBuilder
    private func captionStep(_ i: Int) -> some View {
        let done = (phase > i + 1) || unlockState == .success
        let active = phase == i + 1 && !done
        HStack(spacing: XSpace.xs) {
            Image(systemName: done ? "checkmark.circle.fill" : (active ? "ellipsis.circle" : "circle"))
                .font(.system(size: XIcon.xs, weight: .semibold))
            Text(captionName(i))
                .lineLimit(1)
        }
        .foregroundStyle(done ? XPalette.ok : (active ? XPalette.accentText : XPalette.textSub))
        .opacity(done || active ? 1 : 0.55)
        .accessibilityHidden(true)   // 组合朗读已含全部三步, 单步不重复
    }
    private func captionName(_ i: Int) -> String { ["验证", "执行", "完成"][i] }
    private var captionText: String {
        let done = phase > 0 ? "验证" : ""
        return "过程字幕: " + done + (phase > 1 ? " 执行, " : "") + (unlockState == .success ? " 完成" : (phase > 1 ? "执行中" : "进行中"))
    }
}
