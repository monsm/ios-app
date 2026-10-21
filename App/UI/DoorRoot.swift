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
//        └─ 门里: 已由三棱柱取代 (B 管家台 / F 仪表)
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
    /// 当前面（BDF 三棱柱）。
    ///
    /// 取代旧的 `flipped: Bool` —— 那只能表达两面。
    /// 旧代码的 requestRoute / Tab 映射改走 faceForTab()（见下方），
    /// 所以不再需要 flipped 兼容属性。
    @State private var face: DoorFace = .d
    /// 连接阶段
    @State private var stage: LinkStage = .idle
    /// 充能进度
    @State private var charge: CGFloat = 0
    /// 是否按住
    @State private var isPressing = false
    /// 失败文案
    @State private var failureText: String?

    /// 门里的导航栈

    /// 充能计时
    @State private var chargeTask: Task<Void, Never>?
    /// 连接阶段计时

    /// 按住触发开锁的阈值
    private let holdThreshold: TimeInterval = 0.6

    var body: some View {
        DoorPrism(face: $face) {
            // B 管家台
            managerFace
        } faceD: {
            // D 就近 —— 门 + 锁
            frontContent
        } faceF: {
            // F 仪表 —— 锁数据 + 人的数据
            dashboardFace
        }
        .background(XPalette.canvas)
        .onChange(of: face) { _, _ in
            // 翻面时清理开锁状态
            cancelCharge()
        }
        // 旧 Tab 路由兼容: 别处仍调用 requestRoute(.credentials/.records/...),
        // 这里把它翻译成门里对应的域, 保证跨页跳转不断链。
        // 旧 Tab 路由兼容: 别处仍调用 requestRoute(.credentials/.records/...)。
        //
        // 旧的四域（锁/凭证/记录/设置）→ 新的三面:
        //   0 设备 → D 就近（门+锁）
        //   1 凭证 → B 管家台 · 台账组
        //   2 记录 → F 仪表
        //   3 设置 → B 管家台 · 备份外观组
        //
        // 映射不到具体组时只切面 —— 比切错页面好。
        .onChange(of: app.tabSelection) { _, newValue in
            if let f = faceForTab(newValue) {
                withAnimation(XMotion.soft) { face = f }
            }
        }
        .onAppear {
            if let f = faceForTab(app.tabSelection) { face = f }
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
            DoorFlipButton(face: $face)
                .padding(.trailing, XSpace.s)
                .padding(.top, XSpace.s)
        }
    }

    // ── B 管家台（底部液态玻璃分组，M4）──
    private var managerFace: some View {
        ManagerFace()
            .environmentObject(app)
    }

    // ── F 仪表（锁数据 + 人的数据，M4）──
    private var dashboardFace: some View {
        DashboardFace()
            .environmentObject(app)
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
                    stage = .ready
                }
                XHaptics.success()
            } else {
                let msg = "开锁失败"
                withAnimation(XMotion.soft) {
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
    // MARK: - Tab → 面（兼容旧路由）
    // ═══════════════════════════════════════════════════════

    /// 旧 Tab 序号 → BDF 三面。
    ///
    /// 全仓还有 40+ 处 requestRoute / tabSelection 调用
    /// （深链、粘贴条、自检黄条、销毁前备份闸…），
    /// 不能删 —— 只把「落到哪个面」重新映射。
    private func faceForTab(_ index: Int) -> DoorFace? {
        switch index {
        case 0: return .d        // 设备 → 就近（门+锁）
        case 1: return .b        // 凭证 → 管家台
        case 2: return .f        // 记录 → 仪表
        case 3: return .b        // 设置 → 管家台
        default: return nil
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
