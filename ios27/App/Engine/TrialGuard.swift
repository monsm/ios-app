// TrialGuard.swift —— 只读试验模式（kf_trial_guard）的开关。
//
// LockService.request 里已有 assertReadOnly 护栏，但必须有一个真的写点；否则护栏永远打不开。
// 本文件只管存取；常驻条视图在 LockKeeperApp.swift。
import Foundation

enum TrialGuard {
    static let key = "kf_trial_guard"
    static var isOn: Bool { DB.store.getBool(key, false) }
    static func set(_ on: Bool) {
        DB.store.set(key, on)
    }
    static let warning = "开启后：开锁、写凭证、换钥、配网、网关、固件升级、导入导出全部被拦下，只能读状态。真机排障完记得回来关。"
}
