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

