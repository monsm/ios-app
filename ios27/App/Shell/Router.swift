// Router.swift —— 导航的唯一漏斗。
//
// 纪律：跨 Tab 跳转必须带上下文（要落到哪一条、哪一天），不许裸切 Tab。
// 上一版的教训：sheet 里 requestTab 会切一个不存在的 Tab，而 sheet 还盖在上面。
// 这里用枚举 + 单一入口，杜绝"裸切"。
import SwiftUI

/// 目的地（子页）。新增页面必须在这里登记，Gates/destmap.js 会对账。
enum Dest: String, CaseIterable, Identifiable, Hashable {
    case door
    case keys
    case records
    case household
    case settings

    // 门
    case lockStatus        // 锁实况（电量/固件/锁内时间）
    case addLock           // 配网
    case gateway           // 网关
    case syncTime          // 校时
    case defend            // 布防

    // 钥匙
    case keyDetail         // 凭证详情
    case keyCreate         // 凭证工坊（密码/指纹/临时码）
    case keyCalendar       // 到期月历
    case mobileKey         // 手机钥匙
    case shareToAndroid    // 分享给安卓

    // 台账
    case recordDetail      // 记录详情
    case recordExport      // 导出

    // 家
    case memberDetail      // 成员 360
    case memberCreate      // 建档向导
    case memberArchive     // 归档

    // 设置
    case appearance        // 外观
    case security          // 安全中心
    case backup            // 备份与恢复
    case autoOpen          // 靠近自动开锁
    case hardware          // 钥匙串 / 硬件
    case about             // 关于

    var id: String { rawValue }

    var title: String {
        switch self {
        case .door: return "门"
        case .keys: return "钥匙"
        case .records: return "台账"
        case .household: return "家"
        case .settings: return "设置"
        case .lockStatus: return "锁实况"
        case .addLock: return "添加门锁"
        case .gateway: return "网关"
        case .syncTime: return "校时"
        case .defend: return "布防"
        case .keyDetail: return "凭证详情"
        case .keyCreate: return "新增凭证"
        case .keyCalendar: return "到期月历"
        case .mobileKey: return "手机钥匙"
        case .shareToAndroid: return "分享给安卓"
        case .recordDetail: return "记录详情"
        case .recordExport: return "导出"
        case .memberDetail: return "成员"
        case .memberCreate: return "新建成员"
        case .memberArchive: return "归档"
        case .appearance: return "外观"
        case .security: return "安全"
        case .backup: return "备份与恢复"
        case .autoOpen: return "靠近自动开锁"
        case .hardware: return "硬件"
        case .about: return "关于"
        }
    }

    /// 该目的地归属哪个 Tab（决定跳转时切到哪一页）。
    var tab: TabSlot {
        switch self {
        case .door, .lockStatus, .addLock, .gateway, .syncTime, .defend: return .door
        case .keys, .keyDetail, .keyCreate, .keyCalendar, .mobileKey, .shareToAndroid: return .keys
        case .records, .recordDetail, .recordExport: return .records
        case .household, .memberDetail, .memberCreate, .memberArchive: return .household
        case .settings, .appearance, .security, .backup, .autoOpen, .hardware, .about: return .settings
        }
    }
}

/// Tab 槽位。与 Dest 的 rawValue 不同：这是"停在哪一页"，不是"打开哪个子页"。
enum TabSlot: Int, CaseIterable, Identifiable {
    case door = 0
    case keys = 1
    case records = 2
    case household = 3
    case settings = 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .door: return "门"
        case .keys: return "钥匙"
        case .records: return "台账"
        case .household: return "家"
        case .settings: return "设置"
        }
    }

    var symbol: String {
        switch self {
        case .door: return "door.left.hand.closed"
        case .keys: return "key.horizontal.fill"
        case .records: return "list.bullet.rectangle.portrait.fill"
        case .household: return "person.2.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

/// 跳转上下文。带上下文是本仓纪律：空手切 Tab 是上一版的老问题。
enum RouteContext: Hashable {
    case none
    /// 定位到某一条记录。
    case record(id: String)
    /// 定位到某一天的台账。
    case day(String)
    /// 定位到某一枚凭证。
    case key(id: String)
    /// 定位到某一位成员。
    case member(id: String)
    /// 打开某个子页。
    case dest(Dest)
    /// 只切到某个 Tab 的根（用于「整块可点 → 去那一页」这类入口）。
    /// 仍然走唯一漏斗，不是裸切 Tab。
    case tab(TabSlot)
}

/// 路由状态。整个 App 只有这一个入口改它。
@Observable
final class Router {
    var tab: TabSlot = .door
    /// 当前 Tab 的导航栈。每个 Tab 一条，互不干扰。
    var doorPath: [Dest] = []
    var keysPath: [Dest] = []
    var recordsPath: [Dest] = []
    var householdPath: [Dest] = []
    var settingsPath: [Dest] = []
    /// 挂起的上下文（落到页面后消费，消费完清空）。
    var pending: RouteContext = .none

    /// 唯一入口。要打开子页 → 自动切到它归属的 Tab 再 push。
    func request(_ context: RouteContext) {
        pending = context
        switch context {
        case .none:
            break
        case .record(let id):
            tab = .records
            recordsPath = []
            pending = .record(id: id)
        case .day(let key):
            tab = .records
            recordsPath = []
            pending = .day(key)
        case .key(let id):
            tab = .keys
            keysPath = []
            pending = .key(id: id)
        case .member(let id):
            tab = .household
            householdPath = []
            pending = .member(id: id)
        case .dest(let dest):
            tab = dest.tab
            path(for: dest.tab).wrappedValue = [dest]
        case .tab(let slot):
            tab = slot
            path(for: slot).wrappedValue = []
        }
    }

    /// 只切 Tab（用于 Tab 点击本身）。
    func select(_ slot: TabSlot) {
        tab = slot
    }

    func path(for slot: TabSlot) -> Binding<[Dest]> {
        switch slot {
        case .door: return Binding(get: { self.doorPath }, set: { self.doorPath = $0 })
        case .keys: return Binding(get: { self.keysPath }, set: { self.keysPath = $0 })
        case .records: return Binding(get: { self.recordsPath }, set: { self.recordsPath = $0 })
        case .household: return Binding(get: { self.householdPath }, set: { self.householdPath = $0 })
        case .settings: return Binding(get: { self.settingsPath }, set: { self.settingsPath = $0 })
        }
    }

    /// 消费挂起上下文（页面 onAppear 调用）。
    func consume() -> RouteContext {
        let p = pending
        pending = .none
        return p
    }
}
