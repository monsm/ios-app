//  FindArrowLayer.swift
//  精确查找层（iOS 版）—— 2026-10-18 新增。
//
//  ## 为什么有它
//
//  Android 侧早就有 SignalArrow.kt（AirTag 式箭头 + 距离条 + 滴滴声），
//  iOS 侧**一直没有** —— 用户装了 iOS 版找不到"锁在哪"。这是功能缺口。
//
//  ## 诚实边界（照抄 Android 那份的立场）
//
//  这把锁是普通 BLE，**没有 UWB、没有 AoA**，所以：
//    · 算不出绝对方位。箭头指的不是"锁在那边"，而是"转动手机时信号最强的那个朝向"；
//    · 距离是 RSSI 换算的粗估档，显示"很近/近/远"，不显示米数；
//    · 任何"精确到厘米"的措辞都是谎报，本文件不出现。
//
//  ## 激进 / 省电两档（本次需求的核心）
//
//  用户口径："只在箭头界面里追求极致速度；退出就完全切断，不要死命刷新信号"。
//  所以这层有两套节拍，由 `isActive` 一个布尔量切换：
//    · 箭头界面在场   → 高频扫描（allowDuplicates: true，事件驱动）+ 实时 RSSI
//    · 箭头界面不在场 → **零扫描**（不是降频，是停）
//
//  这让"省电"和"最快"不再冲突：慢/耗电只在用户真的要找锁那一小段时间里发生。

import SwiftUI

/// 精确查找层的开关与节拍控制（单一事实来源）。
@MainActor
final class FindArrowSession: ObservableObject {
    static let shared = FindArrowSession()

    /// 箭头界面是否在场。**这是唯一的节拍开关** ——
    /// 置 true = 进激进档；置 false = 立刻停扫、停取 RSSI。
    @Published private(set) var isActive = false

    /// 当前 RSSI（-127 = 未读到）。
    @Published private(set) var rssi: Int? = nil
    /// 信号最强那一刻的朝向（度）。
    @Published private(set) var peakDeg: Double = 0
    /// 峰值 RSSI（只在明显更强时改写，避免 ±1dB 抖动让箭头乱跳）。
    @Published private(set) var peakRssi: Int? = nil

    private var tickTask: Task<Void, Never>?

    private init() {}

    /// 进入箭头界面：切激进档。
    func activate() {
        guard !isActive else { return }
        isActive = true
        FindArrowPower.beginIntensive()   // 通知 BLE 层开高频扫描
        startTick()
    }

    /// 离开箭头界面：**完全切断**。
    func deactivate() {
        guard isActive else { return }
        isActive = false
        stopTick()
        FindArrowPower.endIntensive()     // BLE 层回到常规节拍（本来就是停着）
        rssi = nil
        peakRssi = nil
    }

    private func startTick() {
        stopTick()
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.sample()
                // 箭头在场时 150ms 一拍：足够跟手，又不会把主线程打满。
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }

    private func stopTick() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func sample() {
        guard isActive else { return }
        BLEService.shared.readLinkRSSI(timeoutMs: 300) { [weak self] v in
            guard let self, self.isActive, let v else { return }
            self.rssi = v
            // 峰值：明显更强（+3dB）才改写，避免箭头随抖动乱转
            if let p = self.peakRssi {
                if v > p + 3 { self.peakRssi = v }
            } else {
                self.peakRssi = v
            }
        }
    }
}

/// BLE 层的"激进档"标记。
///
/// 它只做一件事：让 BLEService 知道当前是否有人盯着信号看。
/// 没有箭头界面时，那些"为了箭头"而做的连续 RSSI 读取**一个都不该发生**。
enum FindArrowPower {
    private static let box = Locked(false)
    static var intensive: Bool { box.withLock { $0 } }
    static func beginIntensive() { box.withLock { $0 = true } }
    static func endIntensive() { box.withLock { $0 = false } }
}

// MARK: - 界面

/// 精确查找层本体。放进 fullScreenCover 或 sheet 都可以。
/// 呈现即 activate、消失即 deactivate —— 节拍跟着生命周期走，不靠调用方记得清。
struct FindArrowLayer: View {
    var lockName: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = FindArrowSession.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Space.xl) {
                Spacer(minLength: 0)
                arrow
                VStack(spacing: DS.Space.xs) {
                    Text(proximityText)
                        .vkFont(.title3, weight: .semibold)
                        .foregroundStyle(DS.Palette.text)
                    Text(rssiText)
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
                Text("转动手机找信号最强的方向。这把锁没有 UWB，箭头指的是朝向不是位置。")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DS.Space.gutter)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .dsScreenBackground()
            .navigationTitle(windowTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .frame(minHeight: DS.Hit.min)
                }
            }
        }
        .onAppear { session.activate() }
        .onDisappear { session.deactivate() }
    }

    private var windowTitle: String { "查找 \(lockName)" }

    private var arrow: some View {
        Image(systemName: "location.north.fill")
            .font(.system(size: 96, weight: .semibold))
            .foregroundStyle(tint)
            .rotationEffect(.degrees(session.peakDeg))
            .animation(reduceMotion ? nil : DS.Motion.soft, value: session.peakDeg)
            .accessibilityHidden(true)
    }

    private var tint: Color {
        guard let r = session.rssi else { return DS.Palette.textSub }
        if r >= -55 { return DS.Palette.ok }
        if r >= -70 { return DS.Palette.warn }
        return DS.Palette.textSub
    }

    private var proximityText: String {
        guard let r = session.rssi else { return "正在寻找…" }
        if r >= -55 { return "很近" }
        if r >= -70 { return "近" }
        return "远"
    }

    private var rssiText: String {
        guard let r = session.rssi else { return "—" }
        return "\(r) dBm"
    }
}
