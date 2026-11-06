// Projections.swift —— 界面用的只读投影。
//
// 纪律：这些类型只装"页面要显示的东西"，不装 Engine 的原始结构。
// 页面不许直接解 Keychain / Ledger / CachedLog；一律经过 AppModel 的投影。
import Foundation
import SwiftUI

// MARK: - 锁

struct LockSummary: Identifiable, Hashable {
    let id: String              // 归一化 MAC
    let name: String
    let model: String
    let pid: Int
    let battery: Int            // -1 = 未知
    let signal: Int             // 0 = 不可测
    let firmware: String
    let keyCount: Int
    let isConnected: Bool
    let safeMode: Bool
    let muted: Bool
    let hidden: Bool
    let group: String
}

// MARK: - 凭证

struct Credential: Identifiable, Hashable {
    enum Kind: String, CaseIterable {
        case password, temp, fingerprint, mobile

        var title: String {
            switch self {
            case .password: return "密码"
            case .temp: return "临时码"
            case .fingerprint: return "指纹"
            case .mobile: return "手机钥匙"
            }
        }

        var symbol: String {
            switch self {
            case .password: return "key"
            case .temp: return "clock"
            case .fingerprint: return "touchid"
            case .mobile: return "iphone"
            }
        }
    }

    let id: String
    let kind: Kind
    let name: String
    let ownerID: String?
    let ownerName: String?
    let masked: String?
    let expiresAt: Int64?       // ms；nil = 永久（引擎的 2118 哨兵已归一成 nil）
    let validFrom: Int64?       // ms；nil = 未记录
    let createdAt: Double       // ms
    let disabled: Bool
    let alias: Int?
    let batch: Int?
    let mobileID: String?
    let note: String

    var isExpiringSoon: Bool {
        guard let expiresAt else { return false }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let week: Int64 = 7 * 24 * 3600 * 1000
        return expiresAt > now && expiresAt - now <= week
    }

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt < Int64(Date().timeIntervalSince1970 * 1000)
    }
}

// MARK: - 成员

enum MemberRole: String, CaseIterable {
    case owner, member, guest

    var title: String {
        switch self {
        case .owner: return "管理员"
        case .member: return "成员"
        case .guest: return "访客"
        }
    }

    var fromEngine: String {
        switch self {
        case .owner: return "main"
        case .member: return "member"
        case .guest: return "guest"
        }
    }

    static func parse(_ raw: String) -> MemberRole {
        switch raw {
        case "main": return .owner
        case "guest": return .guest
        default: return .member
        }
    }
}

struct MemberCard: Identifiable, Hashable {
    let id: String
    let name: String
    let role: MemberRole
    let colorHex: String
    let groupTag: String
    let keyCount: Int
    let lastActiveAt: Int64?    // ms
    let archived: Bool
    let note: String
}

// MARK: - 记录

struct EventItem: Identifiable, Hashable {
    let id: String
    let mac: String
    let lockName: String
    let type: Int
    let typeName: String
    let idx: UInt32
    let time: Int64             // unix 秒；**0 = 锁端没读到时钟，这条记录没有日期**
    let whoID: String?
    let whoName: String?
    let provable: String?       // "temp" / "unique"
    let credential: String      // 给人看的说法（"指纹" / "密码" / …）
    /// 引擎的原始口径：fp / pwd / temp / key。
    /// 搜索按这个字段**精确**匹配 —— `credential` 是译过的中文，
    /// 拿中文去比对英文代号，永远 0 条（这一条踩过，见 `LogScreen.filtered`）。
    let credKind: String?
    let alarm: Bool
    let diff: String?
    let note: String?
    let flagged: Bool

    /// 锁端时钟读不到的记录没有日期，不参与按天分组，也不进「今天」。
    var hasTime: Bool { time > 0 }

    var isOpen: Bool {
        switch type {
        case 11, 16, 17, 19: return true
        default: return false
        }
    }
    var isAlarm: Bool {
        if alarm { return true }
        switch type {
        case 4, 10: return true
        default: return false
        }
    }
}

enum Statics {
    static let openTypes: Set<Int> = [11, 16, 17, 19]
    static let alarmTypes: Set<Int> = [4, 10]
}

// MARK: - 开锁相位

enum UnlockPhase: Equatable {
    case idle
    case reaching       // 连接
    case sending        // 下发
    case waiting        // 等回执
    case opened
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .reaching, .sending, .waiting: return true
        default: return false
        }
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    var line: String {
        switch self {
        case .idle: return ""
        case .reaching: return "正在连接"
        case .sending: return "已下发"
        case .waiting: return "等回执"
        case .opened: return "已打开"
        case .failed(let why): return why
        }
    }
}

// MARK: - 时间文案

enum When {
    static func unix(_ seconds: Int64) -> Date { Date(timeIntervalSince1970: TimeInterval(seconds)) }

    /// Date → Unix 秒。`Int64(Double)` 在越界/NaN 时 trap；搜索框里的时间短语
    /// 来自用户输入，必须在进比较前夹到可表示范围（NaN 归 0）。
    static func epochSeconds(_ date: Date) -> Int64 {
        let t = date.timeIntervalSince1970
        guard t.isFinite else { return 0 }
        let bound = Double(Int64.max / 2)
        return Int64(min(max(t, -bound), bound))
    }

    static func clock(_ seconds: Int64) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hans_CN")
        f.dateFormat = "HH:mm"
        return f.string(from: unix(seconds))
    }

    static func dayKey(_ seconds: Int64) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hans_CN")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: unix(seconds))
    }

    static func dayTitle(_ seconds: Int64) -> String {
        let cal = Calendar.current
        let d = unix(seconds)
        if cal.isDateInToday(d) { return "今天" }
        if cal.isDateInYesterday(d) { return "昨天" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hans_CN")
        f.dateFormat = cal.isDate(d, equalTo: Date(), toGranularity: .year) ? "M 月 d 日" : "yyyy 年 M 月 d 日"
        return f.string(from: d)
    }

    static func ago(_ millis: Int64?) -> String {
        guard let millis, millis > 0 else { return "还没有记录" }
        let then = Date(timeIntervalSince1970: Double(millis) / 1000)
        let sec = max(0, Date().timeIntervalSince(then))
        if sec < 60 { return "刚刚" }
        if sec < 3600 { return "\(Int(sec / 60)) 分钟前" }
        if sec < 86400 { return "\(Int(sec / 3600)) 小时前" }
        if sec < 86400 * 7 { return "\(Int(sec / 86400)) 天前" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hans_CN")
        f.dateFormat = "M 月 d 日"
        return f.string(from: then)
    }

    /// 距离某个**未来**时刻还有多久。`ago` 只能往回看：喂给它一个未来时间戳，
    /// 它会算出负数、夹到 0、然后说「刚刚」——「到 刚刚 之前不会自动开门」。
    static func until(_ millis: Int64) -> String {
        let left = millis - Int64(Date().timeIntervalSince1970 * 1000)
        if left <= 0 { return "已经结束" }
        if left < 60_000 { return "不到 1 分钟" }
        if left < 3_600_000 { return "\(left / 60_000) 分钟" }
        if left < 86_400_000 { return "\(left / 3_600_000) 小时" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hans_CN")
        f.dateFormat = "M 月 d 日 HH:mm"
        return f.string(from: Date(timeIntervalSince1970: Double(millis) / 1000))
    }

    /// 2100-01-01（毫秒）。引擎把「永久」写成 2118-01-01 这个哨兵值；
    /// 万一某条路径没把它归一成 nil，这里再兜一道 ——
    /// 否则界面上会出现「1 月 1 日到期」，看起来像下周就过期。
    static let permanentCutoff: Int64 = 4_102_444_800_000

    static func expiryLabel(_ millis: Int64?) -> String {
        guard let millis else { return "长期有效" }
        if millis >= permanentCutoff { return "长期有效" }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if millis <= now { return "已过期" }
        let days = Int(ceil(Double(millis - now) / 86_400_000))
        if days <= 1 { return "今天到期" }
        if days <= 30 { return "剩 \(days) 天" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hans_CN")
        f.dateFormat = "M 月 d 日"
        return f.string(from: Date(timeIntervalSince1970: Double(millis) / 1000))
    }
}
