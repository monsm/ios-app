// CachePolicy.swift —— 缓存失效矩阵（B46）、扫描生命周期（B45）、快照新鲜期（B38）。
//
// 缓存失效这件事以前靠「谁记得谁清」：换锁时清了 A，进空壳时清了 B，
// 恢复备份后忘了清 C。结果是「界面上显示的是上一把锁的读数」这类幽灵问题。
//
// 现在把「哪个事件作废哪些缓存」写成一张表，事件发生处**照表清**，
// 不再靠记性。新增缓存时只有一处要改：在这里登记它属于哪一类。
import Foundation
import SwiftUI

// MARK: - 缓存分类

enum CacheKind: String, CaseIterable {
    /// 锁端状态快照（电量 / 固件 / 容量）
    case statusSnapshot
    /// 锁内日志缓存
    case logCache
    /// 成员活跃度（按签名缓存的重活结果）
    case memberActivity
    /// RSSI 历史与最近读数
    case linkHistory
    /// 凭证台账（**源数据**，不在这里清）
    case credentialLedger
    /// 界面投影（今日页那一屏）
    case projection
    /// 命令时间线（诊断用，不参与功能）
    case timeline
}

// MARK: - 事件

enum CacheEvent {
    /// 换了一把锁
    case lockSwitched
    /// 进入空壳
    case decoyEntered
    /// 退出空壳
    case decoyExited
    /// 恢复了备份（本机数据整体被替换）
    case backupRestored
    /// 校时（锁端时间变了 ⇒ 带时间的读数要重算）
    case timeSynced
    /// 凭证增删改
    case credentialChanged
    /// 读到新日志
    case logsAppended
    /// 读了锁端状态
    case statusRefreshed
}

// MARK: - 失效矩阵

enum CachePolicy {
    /// **这张表就是真相**。事件 → 该作废的缓存。
    static func invalidates(_ event: CacheEvent) -> Set<CacheKind> {
        switch event {
        case .lockSwitched:
            // 换锁 ⇒ 上一把锁的状态快照、活跃度、信号历史全部不该出现在这一屏。
            return [.statusSnapshot, .memberActivity, .linkHistory, .projection]
        case .decoyEntered:
            // 空壳里不该留任何「这台手机平时怎么用门锁」的痕迹。
            return [.statusSnapshot, .logCache, .memberActivity, .linkHistory, .projection]
        case .decoyExited:
            // 出空壳 ⇒ 全部重新读一遍（数据还在，只是不许用缓存里的旧投影）。
            return [.statusSnapshot, .logCache, .memberActivity, .linkHistory, .projection]
        case .backupRestored:
            // 备份恢复替换了整本数据 ⇒ 一切派生缓存作废。
            return [.statusSnapshot, .logCache, .memberActivity, .linkHistory,
                    .credentialLedger, .projection]
        case .timeSynced:
            // 锁钟变了：带时间的读数（上次开门、日志时间）要重新算，
            // 但日志内容本身没变 —— 不清日志缓存，只让它重新取时间。
            return [.statusSnapshot, .memberActivity, .projection]
        case .credentialChanged:
            return [.memberActivity, .projection]
        case .logsAppended:
            return [.memberActivity, .projection]
        case .statusRefreshed:
            return [.projection]
        }
    }

    /// 照表清。`mac` 是当前锁（换锁事件里指**新**锁；旧锁的缓存自己会失配）。
    static func apply(_ event: CacheEvent, mac: String) {
        let kinds = invalidates(event)
        // 状态快照**不删**：它是按锁存的（kf_snap_<mac>），每把锁各有自己的一份，
        // 删了等于「完全不知道这把锁的电量」。「读到的是旧值」这件事由**徽标**说明（F38），
        // 不该靠空白掩盖，也不该靠标记 —— 换锁时显示的一直是**当前锁**那份快照。
        _ = kinds.contains(.statusSnapshot)
        if kinds.contains(.linkHistory) {
            // 换锁清的是「上一把锁的信号」；进/出空壳清的是「这台手机的使用痕迹」——
            // 两件事的量不一样，用各自的入口，别混用一个。
            switch event {
            case .lockSwitched: LinkSenseModel.shared.clearForLockSwitch()
            default: LinkSenseModel.shared.clearForDecoy()
            }
        }
        if kinds.contains(.memberActivity) {
            MemberActivityCache.invalidate()
        }
        if kinds.contains(.projection) {
            NotificationCenter.default.post(name: .cacheInvalidated, object: nil)
        }
    }
}

// MARK: - 通知

extension Notification.Name {
    /// 投影作废：页面据此重读，而不是各自判断「要不要刷新」。
    static let cacheInvalidated = Notification.Name("threshold.cacheInvalidated")
}

// MARK: - 成员活跃度缓存

/// 成员活跃度是 O(锁 × 日志) 的重活，按签名缓存。
/// 缓存的**结果**也要能整体作废 —— 否则换锁/恢复备份后拿到的还是上一把锁的活跃度。
enum MemberActivityCache {
    private static let token = Locked(0)

    static func invalidate() {
        token.withLock { $0 &+= 1 }
        NotificationCenter.default.post(name: .cacheInvalidated, object: nil)
    }

    /// 当前代次。AppModel 把它并进活跃度签名里。
    static var generation: Int { token.withLock { $0 } }
}

// MARK: - 扫描生命周期（B45）

/// 扫描策略：页面离开就停，后台不常驻。
///
/// 蓝牙扫描是耗电大户，而本 App 只在「配对 / 找锁 / 测距离」时需要它。
/// 过去靠各处记得 `stopScan()`，漏一处就常驻扫描 —— 用户看到的是「电池掉得快」。
enum ScanPolicy {
    private static let reasons = Locked(Set<String>())

    /// 申请扫描（引用计数式：多个理由都撤了才真停）。
    static func acquire(_ reason: String) {
        reasons.withLock { $0.insert(reason) }
    }

    static func release(_ reason: String) {
        reasons.withLock { $0.remove(reason) }
        if reasons.withLock({ $0.isEmpty }) {
            BLEService.shared.stopScan()
        }
    }

    /// 进后台：无论谁在申请，都停。
    static func stopAll() {
        reasons.withLock { $0.removeAll() }
        BLEService.shared.stopScan()
    }

    static var activeReasons: [String] {
        reasons.withLock { Array($0) }
    }
}
