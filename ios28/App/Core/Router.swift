// Router.swift —— 导航的唯一漏斗。
//
// 三个 Tab 各自一条 NavigationStack path；设置是独立的一棵栈，从右上角头像进入。
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

    case settings
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
        case .settings: return "设置"
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

    func backToRoot() {
        switch tab {
        case .today: todayPath = []
        case .access: accessPath = []
        case .log: logPath = []
        }
    }
}
