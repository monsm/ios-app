//
//  DFUError.swift
//  通用错误类型 —— 2026-10-24 从已删的 DFUKit.swift 独立出来
//
//  ## 为什么单独保留
//
//  它原名 DFUError（固件升级用的错误），但 **BackupKit 也在用它**：
//  备份的 zip 解析、信封校验、schema 检查都靠这个类型抛错。
//  删 DFUKit.swift 时把它一起带走，BackupKit 立刻编译不过（8 处 cannot find 'DFUError'）。
//
//  它本来就不是固件专属：两个 case 是"zip 相关"与"一般消息"，与固件无关。
//  保留它、保留原名（避免动 BackupKit 的 8 处调用点），只把文件独立。
//
import Foundation

enum DFUError: LocalizedError {
    case zip(String)
    case msg(String)
    var errorDescription: String? {
        switch self {
        case .zip(let m): return m
        case .msg(let m): return m
        }
    }
}
