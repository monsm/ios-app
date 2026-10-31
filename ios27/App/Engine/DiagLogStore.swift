// 诊断日志的落盘层 —— 从 UserDefaults 迁到「Caches/被排除出备份」的文件。
//
// 2026-10-27 审核（AUDIT-A F-03 / D-04）：原来 `kf_diag_logs` 存在 UserDefaults，
// 而 UserDefaults 无法单独排除某个键 —— 整包随 iCloud / iTunes 备份出机。
// 日志里即便脱敏了帧，仍有 MAC、时间、失败原因这些可关联信息，不该跟着走。
//
// 选择 Caches 目录而不是 Documents：
//   · Caches 不被系统备份（Apple 约定），且可被系统在空间紧张时清理 —— 日志正该如此；
//   · 仍加 isExcludedFromBackup 显式声明，双保险（某些备份方式对 Caches 处理不一致）。
//
// 迁移：首次读取时若文件不存在而 UserDefaults 里还有旧键，搬一次并删旧键。
import Foundation

enum DiagLogStore {
    private static let legacyKey = "kf_diag_logs"

    private static var fileURL: URL? {
        guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        return dir.appendingPathComponent("kf_diag_logs.json")
    }

    static func load() -> [DiagLogEntry] {
        guard let url = fileURL else { return [] }
        if let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([DiagLogEntry].self, from: data) {
            return list
        }
        // 一次性迁移：老版本存在 UserDefaults 里
        if let old = DB.store.get([DiagLogEntry].self, legacyKey), !old.isEmpty {
            save(old)
            DB.store.remove(legacyKey)
            return old
        }
        return []
    }

    static func save(_ list: [DiagLogEntry]) {
        guard let url = fileURL else { return }
        guard let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var v = URLResourceValues()
        v.isExcludedFromBackup = true
        var mut = url
        try? mut.setResourceValues(v)
    }
}
