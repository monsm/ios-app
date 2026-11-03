// 应用锁 —— 冷启动 / 回前台要求输本机密码，并支持**胁迫码**（伪装模式）。
//
// 2026-10-27 重建（AUDIT-D D-01 + D-48）：
//   早先 13 轮精简把“启动门禁”删了，`appUnlocked` 从此恒为 true，
//   于是所有拿它做判据的门禁（深链、明文密码、F0 前台门）全都恒为真 ——
//   代码看着有保护，实际一点也没有。当时的选择是“承认没有应用锁、把假门删掉”。
//   现在按用户决策**真做出来**，并把胁迫码接上（`decoyMode` 原先有 12 处读、0 处写）。
//
// 三种输入走三条路：
//   ① 本机密码   → 正常解锁，`decoyMode = false`
//   ② 胁迫码     → `decoyMode = true`，进空壳模式（门能开、数据看不见），不报警不阻止
//   ③ 其它       → 失败，计入 failStreak
//
// 为什么胁迫码不报警：被胁迫场景下任何“异常反应”、震动、红色提示都可能让胁迫者升级手段。
// 隐藏的是数据（凭证台账、成员、备份），不是开锁能力 —— 门照样能开，这是保命的前提。
import Foundation
import CryptoKit
// ObservableObject / @Published 属 Combine（不靠 SwiftUI 的隐式再导出）
import Combine

@MainActor
final class AppLock: ObservableObject {
    static let shared = AppLock()

    /// 是否已解锁。冷启动为 false（有密码时），解锁后置 true。
    @Published private(set) var unlocked: Bool = false
    /// 为 true 时界面进空壳模式：数据区显示为空，深链落点挂起。
    @Published private(set) var decoy: Bool = false
    /// 连续失败次数（成功解锁后清零；跨启动持久化，防止“杀进程重试”绕过冷却）。
    @Published private(set) var failStreak: Int = 0
    /// 冷却截止时刻（秒）。0 = 无冷却。
    @Published private(set) var cooldownUntil: Double = 0

    // ── 键名 ──
    private let decoyRecordKey = "kf_duress"       // 胁迫码摘要（与 kf_passcode 同结构）
    private let failStreakKey = "kf_lock_fail"
    private let cooldownKey = "kf_lock_cool"
    /// 2026-11-03（安全 · 全功能点排查）：**冷却改用「墙钟 + 单调时钟」双记**。
    /// 原来只存 `cooldownUntil`（墙钟绝对时刻）—— 把系统时间往前拨就能立刻绕过冷却，
    /// 而 4 位数字码只有 1 万种，冷却正是把它从"几秒穷举"拖成"不可行"的那道闸。
    /// systemUptime 单调递增、不受改时间影响（重启会归零，那种情况回退墙钟）。
    private let cooldownUptimeKey = "kf_lock_cool_up"
    private let cooldownBootKey = "kf_lock_cool_boot"

    /// 冷却梯度（用户拍板：3→30s，5→5min，7→30min）。
    /// 4 位数字码 10^4 次可穷举，加了冷却后脚本爆破被拖到无利可图。
    private func cooldownSeconds(for streak: Int) -> Double {
        switch streak {
        case ..<3: return 0
        case 3...4: return 30
        case 5...6: return 300
        default: return 1800
        }
    }

    private init() {
        failStreak = DB.store.getInt(failStreakKey, 0)
        cooldownUntil = DB.store.getDouble(cooldownKey, 0)
        // 有密码才需要锁；无密码时解锁态（与旧行为一致：没设密码就不该拦人）
        unlocked = !DB.hasPasscode()
    }

    /// 有本机密码（或胁迫码）时才需要门禁。
    var isEnabled: Bool { DB.hasPasscode() }

    /// 冷却剩余秒数（0 = 可用）。
    ///
    /// 取「墙钟剩余」与「单调时钟剩余」的**较大者**：
    ///   · 把系统时间往前拨 → 墙钟剩余变负，但单调时钟仍然在走 ⇒ 冷却不被绕过；
    ///   · 重启过（uptime 比记录时小）→ 单调那一档不可信，回退墙钟。
    func cooldownRemaining(now: Date = Date()) -> Int {
        let wallLeft = cooldownUntil - now.timeIntervalSince1970
        let up = ProcessInfo.processInfo.systemUptime
        let bootMark = DB.store.getDouble(cooldownBootKey, 0)
        let upDeadline = DB.store.getDouble(cooldownUptimeKey, 0)
        // 同一次开机周期内才认单调时钟（记录时的 uptime 必须 ≤ 现在）
        let sameBoot = bootMark > 0 && up >= bootMark
        let upLeft = sameBoot ? (upDeadline - up) : 0
        let left = max(wallLeft, upLeft)
        return left > 0 ? Int(left.rounded(.up)) : 0
    }

    /// 验证输入。返回结果告诉调用方走哪条路。
    enum Outcome: Equatable {
        case success            // 正常解锁
        case decoy              // 胁迫码 → 伪装模式
        case wrong(remaining: Int)   // 失败，remaining = 冷却剩余秒（0 = 无冷却）
        case cooling(remaining: Int) // 冷却中，根本没验
    }

    func verify(_ input: String, now: Date = Date()) -> Outcome {
        // 冷却中直接拒，不验（防时序侧信道：验了就能从耗时区分“密码对不对”）
        let left = cooldownRemaining(now: now)
        if left > 0 { return .cooling(remaining: left) }

        // ① 正常密码
        if DB.verifyPasscode(input) {
            unlocked = true
            decoy = false
            failStreak = 0
            cooldownUntil = 0
            DB.store.setInt(failStreakKey, 0)
            DB.store.setDouble(cooldownKey, 0)
            return .success
        }

        // ② 胁迫码（只有设过才判）
        if DB.hasDuressCode(), DB.verifyDuress(input) {
            // 注意：**不清 failStreak、不记日志** —— 伪装模式下任何痕迹都可能暴露
            unlocked = true
            decoy = true
            return .decoy
        }

        // ③ 失败
        failStreak += 1
        let cd = cooldownSeconds(for: failStreak)
        cooldownUntil = cd > 0 ? now.timeIntervalSince1970 + cd : 0
        DB.store.setInt(failStreakKey, failStreak)
        DB.store.setDouble(cooldownKey, cooldownUntil)
        return .wrong(remaining: cd > 0 ? Int(cd) : 0)
    }

    /// 2026-10-29 新增：Face ID / Touch ID 通过后解锁（与密码成功同一条收尾路径）。
    ///
    /// **只在没设胁迫码时可用**（调用方 `LockKeeperApp` 用 `!DB.hasDuressCode()` 把关；
    /// 2026-11-01 Round 306：原注释写的是 `LockScreen` —— 全仓没有这个类型，读者会白找一趟）：
    /// 密码解锁可以输胁迫码进伪装模式，Face ID 不能 —— 若同时提供，被胁迫时刷脸会
    /// 直接暴露「这不是伪装模式」。宁可少一个便利入口，也不给胁迫场景留破绽。
    /// 返回是否真的解锁。调用方**必须**据此决定是否置 app 的解锁态 ——
    /// 旧实现是 Void，`LockKeeperApp` 无论这里做了什么都会 `app.unlocked = true`，
    /// 于是"模型层拒绝"根本传不出去。
    @discardableResult
    func unlockByBiometric() -> Bool {
        // 纵深防御：UI 只在没有胁迫码时提供入口（`LockKeeperApp:271` 的 bioAvailable），
        // 但"入口隐藏"不等于"能力禁用"。任何新调用点（小组件 / 深链 / 未来改动）
        // 都不该绕开这条判断 —— 有胁迫码时刷脸会直接暴露"这不是伪装模式"，
        // 是胁迫场景里最危险的一种破绽。
        guard !DB.hasDuressCode() else { return false }
        // 2026-11-01 修复（CI 告警 `code after return will never be executed` 抓到的真缺陷）：
        // 我把这四行清理**留在了 `return true` 之后** —— 于是它们永远不会执行，
        // 也就是"刷脸解锁成功"从来不清失败计数与冷却。后果：
        // 用密码错几次进入冷却 → 改用刷脸成功解锁 → 冷却仍然生效，
        // 下次刷脸会被立刻拒绝（用户看到"刚解锁过却又要等"）。
        failStreak = 0
        cooldownUntil = 0
        DB.store.setInt(failStreakKey, 0)
        DB.store.setDouble(cooldownKey, 0)
        DB.store.setDouble(cooldownBootKey, 0)
        DB.store.setDouble(cooldownUptimeKey, 0)
        unlocked = true
        decoy = false
        return true
    }

    /// 手动上锁（设置页「立即锁定」、或回前台超时）。
    /// 记一次失败并返回冷却秒数（0 = 无冷却）。
    /// 2026-10-27 新增（AUDIT-D D-50）：二次开锁口令验证也要接计数 ——
    /// 原先只有锁屏那里有，而「第二次开锁要验密码」那个入口同样可被暴力试。
    @discardableResult
    func recordFailure(now: Date = Date()) -> Int {
        failStreak += 1
        let cd = cooldownSeconds(for: failStreak)
        cooldownUntil = cd > 0 ? now.timeIntervalSince1970 + cd : 0
        DB.store.setInt(failStreakKey, failStreak)
        DB.store.setDouble(cooldownKey, cooldownUntil)
        // 单调时钟那一份（见 cooldownRemaining 的说明）
        let up = ProcessInfo.processInfo.systemUptime
        DB.store.setDouble(cooldownBootKey, cd > 0 ? up : 0)
        DB.store.setDouble(cooldownUptimeKey, cd > 0 ? up + cd : 0)
        return cd > 0 ? Int(cd) : 0
    }

    /// 退到后台的时刻（用于回前台超时上锁）。0 = 未记录。
    private var backgroundedAt: Double = 0

    /// 进入后台：记时刻并立即收起自动开锁武装。
    func didEnterBackground(now: Date = Date()) {
        backgroundedAt = now.timeIntervalSince1970
        AutoOpenController.shared.onBackground()
    }

    /// 回前台：超过 30 秒就重新要求本机密码（手机被拿走、放在别人手里时的真实场景），
    /// 30 秒内来回切（接个电话、看一眼通知）不打断。
    /// 2026-10-31 安全审核修复（SEC-21）：旧实现 lock() 全仓零调用点，解锁一次后进程不退出就再也不上锁。
    func willEnterForeground(now: Date = Date(), lockAfter: Double = 30) {
        defer { backgroundedAt = 0 }
        guard isEnabled, backgroundedAt > 0 else { return }
        if now.timeIntervalSince1970 - backgroundedAt >= lockAfter { lock() }
    }

    func lock() {
        guard isEnabled else { return }
        unlocked = false
        decoy = false
        // N-02（安全复核）：上锁必须同时把数据层的空壳标志复位 ——
        // 否则从胁迫码进入、再走一次「上锁」，DB.isDecoy 会永远停在 true，
        // 之后正常解锁也读不到任何数据（表现为"App 数据全没了"）。
        DB.setDecoy(false)
        // SEC-27：上锁即丢弃内存里的母钥缓存与令牌，别让它们常驻进程。
        DB.dropKeychainCache()
        LockService.shared.disconnect()
    }

    // 胁迫码的存储与验证在 `DB` 里（`setDuressCode` / `hasDuressCode` / `verifyDuress`）——
    // 那样能与 `kf_passcode` 共用摘要体系，且「改正常密码」不会连带影响胁迫码。
    // 本类只负责**运行时状态**（是否解锁、是否伪装、失败计数），不碰持久化细节。
}
