//
//  DoorRoot.swift
//  全新 App 根视图 (2026-10-21)
//
//  这是彻底重写的入口: 用「门」替代 4 Tab。
//
//  ═══════════════════════════════════════════════════════════
//  结构
//  ═══════════════════════════════════════════════════════════
//
//  DoorRoot
//   ├─ 应用锁闸门 (LockGuard, 复用既有安全结构)
//   └─ DoorStage (门面)
//        ├─ 门外: DoorFront (锁体 + 连接进度 + 按住开锁)
//        └─ 门里: DoorBack (四域入口)
//
//  四域 → 既有页面 (全部保留, 一个不删):
//     钥匙 → CredentialsView / MemberCenterView
//     事件 → RecordsView / AlarmCenterView / StatsView
//     这台锁 → DeviceManageView / LockOverviewView / 固件 / 网关
//     这台手机 → SecurityCenterView / SettingsView / BackupView
//
//  ═══════════════════════════════════════════════════════════
//  为什么保留既有页面
//  ═══════════════════════════════════════════════════════════
//
//  "彻底重写"指的是交互范式与视觉语言, 不是把 52 个功能全删。
//  用户要的是"全新的 App", 不是"功能更少的 App"。
//  所以: 新外壳 (门) + 旧功能 (完整保留) + 逐步换内页。
//

import SwiftUI
import UIKit

/// 全新 App 根视图
struct DoorRoot: View {
    @EnvironmentObject private var app: AppState

    /// 门是否翻到里面
    @State private var flipped = false
    /// 门相位
    @State private var phase: DoorPhase = .closed
    /// 连接阶段
    @State private var stage: LinkStage = .idle
    /// 充能进度
    @State private var charge: CGFloat = 0
    /// 是否按住
    @State private var isPressing = false
    /// 失败文案
    @State private var failureText: String?

    /// 门里的导航栈
    @State private var navPath: [DoorDomain] = []

    /// 充能计时
    @State private var chargeTask: Task<Void, Never>?
    /// 连接阶段计时
    @State private var stageTask: Task<Void, Never>?

    /// 按住触发开锁的阈值
    private let holdThreshold: TimeInterval = 0.6

    var body: some View {
        DoorStage(flipped: $flipped, phase: $phase) {
            frontContent
        } back: {
            backContent
        }
        .background(XPalette.canvas)
        .onChange(of: flipped) { _, _ in
            // 翻面时清理开锁状态
            cancelCharge()
        }
    }

    // ── 门外 ──
    private var frontContent: some View {
        DoorFront(
            lastConfirmedAt: lastConfirmedAt,
            lastKnownOpen: lastKnownOpen,
            stage: stage,
            charge: charge,
            isPressing: isPressing,
            failureText: failureText,
            onPressChanged: handlePress
        )
        .overlay(alignment: .topTrailing) {
            DoorFlipButton(flipped: $flipped)
                .padding(.trailing, XSpace.s)
                .padding(.top, XSpace.s)
        }
    }

    // ── 门里 ──
    private var backContent: some View {
        NavigationStack(path: $navPath) {
            DoorBack(flipped: $flipped) { domain in
                enter(domain)
            }
            .navigationDestination(for: DoorDomain.self) { domain in
                domainDestination(domain)
            }
        }
    }

    /// 四域各自的落地页
    @ViewBuilder
    private func domainDestination(_ domain: DoorDomain) -> some View {
        switch domain {
        case .lock:
            DevicePage()
        case .keys:
            CredentialsView().id(app.currentMac)
        case .events:
            RecordsView().id(app.currentMac)
        case .device:
            SettingsView()
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 按住开锁
    // ═══════════════════════════════════════════════════════

    private func handlePress(_ pressing: Bool) {
        if pressing {
            guard !isPressing else { return }
            isPressing = true
            failureText = nil
            XHaptics.tick.impactOccurred()
            startCharge()
        } else {
            guard isPressing else { return }
            isPressing = false
            cancelCharge()
            // 未充满就松手 → 回零
            if charge < 1 {
                withAnimation(XMotion.chargeReset) { charge = 0 }
                if stage != .idle {
                    withAnimation(XMotion.soft) { stage = .idle }
                }
            }
        }
    }

    private func startCharge() {
        charge = 0
        let step: CGFloat = 0.02
        let interval = holdThreshold * Double(step)
        chargeTask = Task { @MainActor in
            while charge < 1 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { return }
                charge = min(1, charge + step)
                // 每 20% 一次 tick
                let mark = Int(charge * 5)
                if mark != Int((charge - step) * 5) {
                    XHaptics.tick.impactOccurred()
                }
            }
            if !Task.isCancelled && charge >= 1 {
                await performUnlock()
            }
        }
    }

    private func cancelCharge() {
        chargeTask?.cancel()
        chargeTask = nil
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 开锁流程
    // ═══════════════════════════════════════════════════════

    private func performUnlock() async {
        XHaptics.trigger.impactOccurred()
        withAnimation(XMotion.soft) {
            phase = .unlocking
            stage = .scanning
        }

        // 连接阶段可视化 (真实连接由 LockService 承担)
        await runStageSequence()

        // 真正下发开锁 —— 走既有安全链路
        await MainActor.run {
            app.requestUnlock()
        }

        // 等待结果 (最多 8 秒)
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(200))
            if case .success = app.unlockState { break }
            if case .failed = app.unlockState { break }
        }

        await MainActor.run {
            if case .success = app.unlockState {
                withAnimation(XMotion.doorSwing) {
                    phase = .open
                    stage = .ready
                }
                XHaptics.success()
            } else {
                let msg = "开锁失败"
                withAnimation(XMotion.soft) {
                    phase = .failed(msg)
                    stage = .idle
                    failureText = msg
                    charge = 0
                }
                XHaptics.failure()
            }
            isPressing = false
        }
    }

    /// 连接阶段动画 —— 让 6 秒等待有可见进度
    private func runStageSequence() async {
        await MainActor.run { withAnimation(XMotion.soft) { stage = .scanning } }
        try? await Task.sleep(for: .milliseconds(900))
        guard !Task.isCancelled else { return }
        await MainActor.run { withAnimation(XMotion.soft) { stage = .connecting } }
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled else { return }
        await MainActor.run { withAnimation(XMotion.soft) { stage = .handshaking } }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 进入四域
    // ═══════════════════════════════════════════════════════

    private func enter(_ domain: DoorDomain) {
        // 377 访客门禁: 受限区未放开时, 凭证与设置两域必须走复核闸门。
        let restricted: Set<DoorDomain> = [.keys, .device]
        if app.guestAreaLocked && restricted.contains(domain) {
            app.guestGateTarget = tabIndex(for: domain)
            app.showGuestGate = true
            return
        }
        // 门里直接推入新页面 (NavigationStack), 不再切旧 Tab
        navPath.append(domain)
    }

    /// 四域 → 既有 Tab 序号 (与 mainTabView 的 value 一一对应)
    private func tabIndex(for domain: DoorDomain) -> Int {
        switch domain {
        case .lock: return 0      // 设备
        case .keys: return 1      // 凭证
        case .events: return 2    // 记录
        case .device: return 3    // 设置
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 状态派生
    // ═══════════════════════════════════════════════════════

    /// 上次确认时刻 —— 用最近一次开锁记录
    ///
    /// recentRecords 返回元组 (text/time/warn/key/whoId), 没有 type 字段。
    /// 协议无门磁, 无法知道门当前开合; 只能诚实表达"上次确认于何时"。
    private var lastConfirmedAt: Date? {
        guard let rec = app.recentRecords(count: 1).first else { return nil }
        guard !rec.time.isEmpty else { return nil }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.date(from: rec.time)
    }

    /// 上次已知状态 —— 有记录 = 曾成功开过门 (协议无门磁, 不猜当前开合)
    private var lastKnownOpen: Bool {
        guard let rec = app.recentRecords(count: 1).first else { return false }
        return !rec.text.isEmpty
    }
}
