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
    // 2026-11-01（Round 270）：原文案写「导入导出全部被拦下」，而导出是**只读**、本来就该放行；
    // 导入此前则**完全没被拦**（强制点只在 BLE 命令层，导入是本机写操作）。
    // 现在导入已在 `BackupStudioKit.restore` 入口拦下，文案按实际行为改准：说清哪一半被拦、哪一半还能用。
    static let warning = "开启后：开锁、写凭证、换钥、配网、网关、固件升级、导入备份全部被拦下；导出备份仍可用（只读）。真机排障完记得回来关。"
}
