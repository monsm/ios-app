// AppModel.swift —— 应用级状态。
//
// 纪律：@Observable（iOS 17+ 现代写法），不用 ObservableObject。
// 这里只放"跨页面共享"的状态；页面自己的临时状态留在页面里。
import SwiftUI

@Observable
final class AppModel {
    /// 当前门锁（nil = 还没添加）。
    var lock: LockSummary? = LockSummary.sample
    /// 本机数据保护是否已解锁（冷启动才要求）。
    var unlocked: Bool = true
    /// 只读试验模式（顶部常驻红条，必须常驻 —— 用户第二天会忘了自己开过它）。
    var trialGuard: Bool = false
    /// 开锁链相位（门页刻度盘读它）。
    var dialPhase: DialPhase = .idle
    /// 最近一次动作的时刻（毫秒 epoch）。
    var lastActionAt: Int64? = Int64(Date().timeIntervalSince1970 * 1000) - 3 * 3600 * 1000
    /// 台账（真实现由 Engine/Store 提供；这里先给可替换的模型）。
    var entries: [LedgerEntry] = LedgerEntry.sample
    /// 凭证。
    var keys: [KeyItem] = KeyItem.sample
    /// 成员。
    var members: [MemberCard] = MemberCard.sample

    /// 最近一次读到的锁状态快照（EngineHost 要求）。
    var lastStatus: StatusSnapshot?
    /// 弱引用路由：EngineHost 的唯一跳转出口。由 RootView 在装配时注入。
    @ObservationIgnored weak var router: Router?

    /// 开锁链推进（真实链路由 Engine 驱动；这里演示相位机，失败就停在断点）。
    @MainActor
    func runUnlockChain() async {
        guard dialPhase == .idle || dialPhase.isFailed else { return }
        dialPhase = .reaching
        try? await Task.sleep(for: .milliseconds(240))
        dialPhase = .sending
        try? await Task.sleep(for: .milliseconds(320))
        dialPhase = .waiting
        try? await Task.sleep(for: .milliseconds(420))
        dialPhase = .opened
        lastActionAt = Int64(Date().timeIntervalSince1970 * 1000)
        try? await Task.sleep(for: .milliseconds(700))
        dialPhase = .idle
    }
}

// MARK: - 可替换的数据模型（真实现接 Engine）

struct LockSummary: Identifiable, Hashable {
    let id: String
    let name: String
    let model: String
    let battery: Int
    let signal: Int          // 0...4
    let firmware: String
    let keyCount: Int
    let isConnected: Bool
    let safeMode: Bool
    let muted: Bool

    static let sample = LockSummary(
        id: "AA:BB:CC:DD:EE:01",
        name: "前门",
        model: "KX 系列",
        battery: 76,
        signal: 3,
        firmware: "1.4.2",
        keyCount: 9,
        isConnected: true,
        safeMode: false,
        muted: true
    )
}

struct KeyItem: Identifiable, Hashable {
    enum Kind: String, CaseIterable {
        case password = "密码"
        case fingerprint = "指纹"
        case temp = "临时码"
        case mobile = "手机钥匙"
    }
    let id: String
    let kind: Kind
    let name: String
    let owner: String?
    let code: String?
    /// 到期时刻（毫秒 epoch）。nil = 永久。
    let expiresAt: Int64?
    let disabled: Bool

    static let sample: [KeyItem] = [
        KeyItem(id: "k1", kind: .password, name: "主门密码", owner: "我", code: "••••••", expiresAt: nil, disabled: false),
        KeyItem(id: "k2", kind: .fingerprint, name: "右手拇指", owner: "我", code: nil, expiresAt: nil, disabled: false),
        KeyItem(id: "k3", kind: .fingerprint, name: "左手食指", owner: "妈妈", code: nil, expiresAt: nil, disabled: false),
        KeyItem(id: "k4", kind: .temp, name: "保洁 周三", owner: "访客", code: "482913", expiresAt: Int64(Date().timeIntervalSince1970 * 1000) + 2 * 86400_000, disabled: false),
        KeyItem(id: "k5", kind: .mobile, name: "我的 iPhone", owner: "我", code: nil, expiresAt: nil, disabled: false),
    ]
}

struct MemberCard: Identifiable, Hashable {
    enum Role: String, CaseIterable {
        case owner = "管理员"
        case member = "成员"
        case guest = "访客"
    }
    let id: String
    let name: String
    let role: Role
    let keyCount: Int
    let lastActiveAt: Int64?
    let archived: Bool

    static let sample: [MemberCard] = [
        MemberCard(id: "m1", name: "我", role: .owner, keyCount: 3, lastActiveAt: Int64(Date().timeIntervalSince1970 * 1000) - 3 * 3600_000, archived: false),
        MemberCard(id: "m2", name: "妈妈", role: .member, keyCount: 2, lastActiveAt: Int64(Date().timeIntervalSince1970 * 1000) - 26 * 3600_000, archived: false),
        MemberCard(id: "m3", name: "小姨", role: .member, keyCount: 1, lastActiveAt: nil, archived: false),
        MemberCard(id: "m4", name: "保洁", role: .guest, keyCount: 1, lastActiveAt: Int64(Date().timeIntervalSince1970 * 1000) - 5 * 86400_000, archived: false),
    ]
}
// MARK: - EngineHost 桥接
//
// 引擎只声明它需要什么（见 Engine/EngineHost.swift），这里把界面状态喂给它。
// 这是**唯一**允许 Engine 与界面接触的地方 —— 上一版是把 AppState 整个塞进引擎函数，
// 结果引擎离不开界面层，搬到新 App 时整片悬空。
extension AppModel: EngineHost {
    /// 当前选中的门锁钥匙串。优先取当前锁，其次取本机偏好锁。
    var currentKeychain: Keychain? {
        if let mac = lock?.id, let kc = DB.keychain(mac) { return kc }
        let mac = DB.preferredMac()
        return mac.isEmpty ? nil : DB.keychain(mac)
    }

    /// 链路服务。
    var lockLink: LockService { LockService.shared }

    /// 把「点通知」翻成一次界面跳转（CredentialOrg.applyNotification 的落地端）。
    func requestCredentialRoute(alias: Int?) {
        router?.request(.key(id: alias.map(String.init) ?? ""))
    }
}
