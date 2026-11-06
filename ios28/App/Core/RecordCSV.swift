// RecordCSV.swift —— CSV 单元格转义。Engine 的 StatsKit（周报）也复用它，
// 所以这里是唯一口径，不许在页面里再写一份。
import Foundation

enum RecordCSV {
    nonisolated static func field(_ value: String) -> String {
        var v = value.replacingOccurrences(of: "\r", with: " ")

        // 防公式注入：以 = + - @ 制表符开头时前置单引号（跳过前导空格再判）。
        if let first = v.drop(while: { $0 == " " }).first {
            switch first {
            case "=", "+", "-", "@", "\t":
                v = "'" + v
            default:
                break
            }
        }

        var needsQuote = false
        for ch in v where ch == "," || ch == "\"" || ch == "\n" {
            needsQuote = true
            break
        }
        if needsQuote {
            return "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return v
    }
}
