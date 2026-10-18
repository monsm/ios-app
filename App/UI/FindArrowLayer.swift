//  FindArrowLayer.swift
//  精确查找层（iOS 版）—— 2026-10-18 新增。
//
//  ## 为什么有它
//
//  Android 侧早就有 SignalArrow.kt（AirTag 式箭头 + 距离档 + 滴滴声），
//  iOS 侧一直没有 —— 装了 iOS 版找不到"锁在哪"。这是功能缺口。
//
//  ## 诚实边界（照抄 Android 那份的立场）
//
//  这把锁是普通 BLE，没有 UWB、没有 AoA，所以：
//    · 算不出绝对方位。箭头指的不是"锁在那边"，而是"转动手机时信号最强的那个朝向"；
//    · 距离是 RSSI 换算的粗估档，显示"很近/近/远"，不显示米数；
//    · 任何"精确到厘米"的措辞都是谎报，本文件不出现。
//
//  ## 激进 / 省电两档（本次需求核心）
//
//  用户口径："只在箭头界面里追求极致速度；退出就完全切断，不要死命刷新信号"。
//    · 箭头界面在场   → 150ms 一拍连续读 RSSI（激进）
//    · 箭头界面不在场 → **零轮询**（不是降频，是停）
//
//  实现上刻意**不用 ObservableObject**：
//  会话状态就是这个 View 自己的 @State，.task 在 @MainActor 上跑；
//  "现在是否激进"对外只暴露一个 Locked 静态标志（Sendable 安全）。
//  这样避开 Swift 6 里 @StateObject 默认值表达式引用 @MainActor 单例的隔离问题。

import SwiftUI

/// BLE 层的"激进档"标记。
///
/// 它只做一件事：让别的层知道当前是否有人盯着信号看。
/// 没有箭头界面时，那些"为了箭头"而做的连续 RSSI 读取一个都不该发生。
enum FindArrowPower {
    private static let box = Locked(false)
    static var intensive: Bool { box.withLock { $0 } }
    static func beginIntensive() { box.withLock { $0 = true } }
    static func endIntensive() { box.withLock { $0 = false } }
}

/// 精确查找层本体。
///
/// 呈现在 fullScreenCover 或 sheet 里都可以；**出现即开激进档、消失即全停**，
/// 节拍跟着视图生命周期走，不靠调用方记得清。
struct FindArrowLayer: View {
    var lockName: String

    @Environment(\.dismiss) private var dismiss

    @State private var rssi: Int? = nil

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
            .navigationTitle("查找 \(lockName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .frame(minHeight: DS.Hit.min)
                }
            }
        }
        // 出现: 开激进档 + 起轮询
        .task {
            FindArrowPower.beginIntensive()
            defer { FindArrowPower.endIntensive() }   // 视图消失时 task 被取消 → 这里立刻关档
            while !Task.isCancelled {
                sampleRssi()
                // 150ms 一拍：足够跟手，又不会把主线程打满。
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }

    /// 读一次链路 RSSI。回调一定回到主线程（BLEService 那边保证了）。
    private func sampleRssi() {
        BLEService.shared.readLinkRSSI(timeoutMs: 300) { v in
            guard let v else { return }
            rssi = v
        }
    }


    private var arrow: some View {
        Image(systemName: "location.north.fill")
            .font(.system(size: 96, weight: .semibold))
            .foregroundStyle(tint)
            // 2026-10-18: 这里**刻意不转**。
            // 方向要真朝向数据（磁力计 + 姿态融合），iOS 侧还没有这条数据源；
            // 拿 RSSI 最强的一帧去"假装"方向，箭头会乱指 —— 那是谎报能力。
            // 等真机批次接上 CMMotionManager 的姿态融合再补旋转。
            .accessibilityHidden(true)
    }

    private var tint: Color {
        guard let r = rssi else { return DS.Palette.textSub }
        if r >= -55 { return DS.Palette.ok }
        if r >= -70 { return DS.Palette.warn }
        return DS.Palette.textSub
    }

    private var proximityText: String {
        guard let r = rssi else { return "正在寻找…" }
        if r >= -55 { return "很近" }
        if r >= -70 { return "近" }
        return "远"
    }

    private var rssiText: String {
        guard let r = rssi else { return "—" }
        return "\(r) dBm"
    }
}
