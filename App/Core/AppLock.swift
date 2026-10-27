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
    func cooldownRemaining(now: Date = Date()) -> Int {
        let left = cooldownUntil - now.timeIntervalSince1970
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

    /// 手动上锁（设置页「立即锁定」、或回前台超时）。
    func lock() {
        guard isEnabled else { return }
        unlocked = false
        decoy = false
    }

    // 胁迫码的存储与验证在 `DB` 里（`setDuressCode` / `hasDuressCode` / `verifyDuress`）——
    // 那样能与 `kf_passcode` 共用摘要体系，且「改正常密码」不会连带影响胁迫码。
    // 本类只负责**运行时状态**（是否解锁、是否伪装、失败计数），不碰持久化细节。
}
