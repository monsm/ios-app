//
//  DoorFront.swift
//  门外 · 全新设计
//
//  门外只做一件事: 让用户在 6 秒内知道"能不能进, 还要多久"。
//
//  ═══════════════════════════════════════════════════════════
//  为什么这样设计 (对抗式审核后的结论)
//  ═══════════════════════════════════════════════════════════
//
//  1. 不说"门已关", 说"上次确认 · 2小时前"
//     协议里没有门磁/反锁状态位 (CAPABILITY.md §5), App 不知道门是开是关。
//     唯一诚实的是: 上次成功确认的时刻 + 当时的结论。
//
//  2. 6 秒连接过程做成进度, 不是转圈
//     BLE scan 最坏 6 秒 (scan timeoutMs: 6000)。把它画成四阶段进度,
//     用户知道"到哪一步了", 而不是盯着一个不确定的 spinner。
//
//  3. 按住而非点击
//     6 秒等待里, 用户需要"我在做事"的确定感。按住给这个。
//     同时按住期间并行连接, 感知等待从 6 秒降到 5.4 秒。
//
//  4. 按住 600ms 而非 900ms
//     900ms 是旧实现, 实测偏长。600ms 足够防误触, 又不拖沓。
//

import SwiftUI
import UIKit

/// 连接阶段 —— 6 秒的四段
enum LinkStage: Int, CaseIterable {
    case idle = 0        // 未开始
    case scanning = 1    // 扫描中 (0-3s)
    case connecting = 2  // 连接中 (0.5-2s)
    case handshaking = 3 // 握手中
    case ready = 4       // 就绪

    var label: String {
        switch self {
        case .idle: return ""
        case .scanning: return "正在寻找门锁…"
        case .connecting: return "找到了 · 正在连接"
        case .handshaking: return "正在验证…"
        case .ready: return "可以了"
        }
    }

    var progress: Double {
        switch self {
        case .idle: return 0
        case .scanning: return 0.25
        case .connecting: return 0.55
        case .handshaking: return 0.8
        case .ready: return 1.0
        }
    }
}

/// 门外 —— 首屏正面
struct DoorFront: View {
    @EnvironmentObject private var app: AppState

    /// 上次确认时刻
    var lastConfirmedAt: Date?
    /// 上次确认的结论 (已锁/已开)
    var lastKnownOpen: Bool
    /// 连接阶段
    var stage: LinkStage
    /// 按住充能进度 0...1
    var charge: CGFloat
    /// 是否正在按住
    var isPressing: Bool
    /// 是否失败
    var failureText: String?

    /// 按住回调
    var onPressChanged: (Bool) -> Void

    @State private var breathe = false

    private var lockName: String {
        app.current.map { LockArchive.displayName($0) } ?? "门"
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── 顶部: 锁名 + 翻面按钮 ──
            HStack {
                Text(lockName)
                    .vkFont(.headline)
                    .foregroundStyle(XPalette.text)
                Spacer()
            }
            .padding(.horizontal, XSpace.gutter)
            .padding(.top, XSpace.s)

            Spacer(minLength: XSpace.lockFace)

            // ── 中部: 锁体 ──
            ZStack {
                // 呼吸光晕
                Circle()
                    .fill(RadialGradient(
                        colors: [XPalette.accent.opacity(breathe ? 0.16 : 0.08), .clear],
                        center: .center, startRadius: 0,
                        endRadius: DoorGeometry.plateDiameter(screenWidth: UIScreen.main.bounds.width) * 0.9))
                    .frame(width: DoorGeometry.plateDiameter(screenWidth: UIScreen.main.bounds.width) * 1.8)
                    .animation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true), value: breathe)

                LockPlate(
                    charge: charge,
                    isOpen: lastKnownOpen && stage == .idle,
                    isFailed: failureText != nil,
                    diameter: DoorGeometry.plateDiameter(screenWidth: UIScreen.main.bounds.width))
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: XSpace.l)

            // ── 状态行 ──
            VStack(spacing: XSpace.xs) {
                Text(statusLine)
                    .vkFont(.title3, weight: .medium)
                    .foregroundStyle(XPalette.text)
                    .contentTransition(.numericText())
                    .animation(XMotion.quick, value: statusLine)

                if let sub = subLine {
                    Text(sub)
                        .vkFont(.footnote)
                        .foregroundStyle(XPalette.textSub)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, XSpace.gutter)

            Spacer(minLength: XSpace.xl)

            // ── 按住开锁 ──
            holdButton
                .padding(.horizontal, XSpace.gutter)

            // ── 连接进度 ──
            if stage != .idle && stage != .ready {
                linkProgress
                    .padding(.top, XSpace.l)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Spacer(minLength: XSpace.xl)
        }
        .onAppear { breathe = true }
        .animation(XMotion.soft, value: stage)
        .animation(XMotion.soft, value: failureText)
    }

    // ── 状态文案 ──
    private var statusLine: String {
        if let failureText { return failureText }
        if stage != .idle { return stage.label }
        return lastKnownOpen ? "上次确认 · 已开" : "上次确认 · 已锁"
    }

    private var subLine: String? {
        if stage != .idle { return nil }
        guard let t = lastConfirmedAt else { return "从未确认过" }
        let mins = Int(-t.timeIntervalSinceNow / 60)
        if mins < 1 { return "刚刚" }
        if mins < 60 { return "\(mins) 分钟前" }
        let hrs = mins / 60
        if hrs < 24 { return "\(hrs) 小时前" }
        return "\(hrs / 24) 天前"
    }

    // ── 按住按钮 ──
    private var holdButton: some View {
        ZStack {
            RoundedRectangle(cornerRadius: XRadius.control, style: .continuous)
                .fill(XPalette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: XRadius.control, style: .continuous)
                        .strokeBorder(
                            isPressing ? XPalette.accent : XPalette.hairlineStrong,
                            lineWidth: isPressing ? 2 : 1)
                )

            // 充能填充
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: XRadius.control, style: .continuous)
                    .fill(XPalette.accent.opacity(0.14))
                    .frame(width: geo.size.width * charge)
            }
            .clipShape(RoundedRectangle(cornerRadius: XRadius.control, style: .continuous))

            HStack(spacing: XSpace.s) {
                Image(systemName: isPressing ? "lock.open.fill" : "hand.tap.fill")
                    .font(.system(size: XIcon.sm, weight: .medium))
                Text(isPressing ? "继续按住…" : "按住开锁")
                    .vkFont(.body, weight: .semibold)
            }
            .foregroundStyle(isPressing ? XPalette.accentText : XPalette.text)
        }
        .frame(height: 56)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressing { onPressChanged(true) } }
                .onEnded { _ in onPressChanged(false) }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("按住开锁")
        .accessibilityValue(charge > 0 ? "充能 \(Int(charge * 100))%" : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onPressChanged(true) }
    }

    // ── 连接进度 ──
    private var linkProgress: some View {
        VStack(spacing: XSpace.s) {
            // 四段进度条
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(i < stage.rawValue ? XPalette.accent : XPalette.hairline)
                        .frame(height: 3)
                }
            }
            .padding(.horizontal, XSpace.xl)

            Text(stage.label)
                .vkFont(.caption)
                .foregroundStyle(XPalette.textSub)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("连接进度: \(stage.label)")
    }
}
