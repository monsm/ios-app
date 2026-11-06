// Router.swift —— 导航的唯一漏斗。
//
// 三个 Tab 各自一条 NavigationStack path；设置是独立的一棵栈，从底栏第 4 个按钮进入。
// 页面之间不互相引用，跨页跳转一律走这里。
import SwiftUI

enum TabSlot: Int, Hashable, CaseIterable {
    case today, access, log

    var title: String {
        switch self {
        case .today: return "今日"
        case .access: return "通行"
        case .log: return "记录"
        }
    }
}

enum Dest: String, Hashable, CaseIterable, Identifiable {
    case credential
    case credentialCreate
    case mobileKeys
    case zotp
    case member
    case memberCreate
    case event
    case insights

    case locks
    case lockPolicy
    case lockInfo
    case pairing
    case autoOpen
    case hardware
    case dfu
    case diagnostics
    case security
    case backup
    case appearance
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .credential: return "凭证"
        case .credentialCreate: return "新凭证"
        case .mobileKeys: return "手机钥匙"
        case .zotp: return "动态密码"
        case .member: return "成员"
        case .memberCreate: return "新成员"
        case .event: return "记录详情"
        case .insights: return "洞察"
        case .locks: return "我的锁"
        case .lockPolicy: return "门锁设置"
        case .lockInfo: return "门锁信息"
        case .pairing: return "配对门锁"
        case .autoOpen: return "自动开门"
        case .hardware: return "钥匙串与网关"
        case .dfu: return "固件升级"
        case .diagnostics: return "维护与诊断"
        case .security: return "安全"
        case .backup: return "备份与恢复"
        case .appearance: return "外观"
        case .about: return "关于"
        }
    }
}

@MainActor
@Observable
final class Router {
    var tab: TabSlot = .today
    var todayPath: [Dest] = []
    var accessPath: [Dest] = []
    var logPath: [Dest] = []
    var settingsPath: [Dest] = []
    var settingsOpen = false

    var pendingCredentialID: String?
    var pendingMemberID: String?
    var pendingEventID: String?
    /// 新凭证页打开时预选哪一类：`password` / `temp` / `fingerprint`。
    /// 由来源页写入、由新凭证页取走后清空（一次性意图，不该粘在路由上）。
    var pendingCreateKind: String?
    /// 新凭证页打开时预选归属成员（从成员详情「新建凭证」进来时用）。
    var pendingCreateOwnerID: String?
    /// 跨 Tab 跳到「通行」时指定分段（0 凭证 / 1 成员 / 2 手机钥匙）。
    /// 今日页的「凭证」快捷动作、设置页的「成员与分工」都要求落在对应分段，
    /// 否则用户上次停在「成员」，点「凭证」却还是成员页。
    var pendingAccessSegment: Int?

    func push(_ dest: Dest) {
        switch tab {
        case .today: todayPath.append(dest)
        case .access: accessPath.append(dest)
        case .log: logPath.append(dest)
        }
    }

    func pushSettings(_ dest: Dest) {
        settingsPath.append(dest)
    }

    func openSettings() {
        settingsPath = []
        settingsOpen = true
    }

    func openCredential(_ id: String) {
        pendingCredentialID = id
        tab = .access
        accessPath = [.credential]
    }

    func openMember(_ id: String) {
        pendingMemberID = id
        tab = .access
        accessPath = [.member]
    }

    func openEvent(_ id: String) {
        pendingEventID = id
        tab = .log
        logPath = [.event]
    }

    /// 跨 Tab 跳到某个 Tab 的**根**。
    ///
    /// 只改 `tab` 是不够的：目标 Tab 若还停在上次的详情页，用户点「凭证」「记录」
    /// 会落回那一条旧详情，而不是列表；`pendingAccessSegment` 也会被详情页挡住。
    /// 所有“去另一个 Tab 的某个列表”的入口都必须走这里。
    func goToAccessRoot(segment: Int? = nil) {
        accessPath = []
        tab = .access
        if let segment { pendingAccessSegment = segment }
    }

    func goToLogRoot() {
        logPath = []
        tab = .log
    }

    func backToRoot() {
        switch tab {
        case .today: todayPath = []
        case .access: accessPath = []
        case .log: logPath = []
        }
    }

    /// 进空壳时把导航清回根。
    ///
    /// 页面会把加载时的数据留在 `@State` 里（表单、已解出的台账、选中的凭证）。
    /// 如果胁迫码是在「上锁 → 解锁」之后输入的，而锁屏前正停在某个详情页，
    /// 不清栈就会直接回到那一屏 —— 空壳已经生效，屏幕上却还是上一会话的真实内容。
    func resetForDecoy() {
        todayPath = []
        accessPath = []
        logPath = []
        settingsPath = []
        settingsOpen = false
        pendingCredentialID = nil
        pendingMemberID = nil
        pendingEventID = nil
        pendingCreateKind = nil
        pendingCreateOwnerID = nil
        pendingAccessSegment = nil
        tab = .today
    }
}
