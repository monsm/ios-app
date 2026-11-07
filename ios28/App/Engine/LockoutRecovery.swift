// LockoutRecovery.swift —— 「我锁在门外了」的恢复编排（B31）。
//
// 用户被关在门外时，App 能做的事有几件、风险各不相同：
//   · 读电量/状态      —— 无风险
//   · 键盘复位         —— **有风险**：锁会清空自己的凭证，要重新配对
//   · 修复 PIN 池      —— 中风险：只换本机的 PIN 池，别人的旧钥匙失效
//   · 重新配对         —— 要用户到锁上按键
//
// 以前这些散在设置页的各个按钮里，用户不知道该点哪个、点了会丢什么。
// 现在收成一条**有顺序、有风险说明、可中断**的流程。
import Foundation

enum LockoutRecovery {
    enum Step: String, CaseIterable, Identifiable {
        case checkState
        case checkKeychain
        case repairPool
        case keypadReset
        case rePair

        var id: String { rawValue }

        var title: String {
            switch self {
            case .checkState: return "读一下门锁状态"
            case .checkKeychain: return "核对本机档案"
            case .repairPool: return "修复 PIN 池"
            case .keypadReset: return "键盘复位"
            case .rePair: return "重新配对"
            }
        }

        var detail: String {
            switch self {
            case .checkState: return "读一次电量与状态，确认门锁有电、不是被布防或反锁。"
            case .checkKeychain: return "核对本机保存的锁档案与钥匙是否还在。"
            case .repairPool: return "只换**本机**的 PIN 池。别人的旧钥匙会失效，你自己家的钥匙仍然有效。"
            case .keypadReset: return "让门锁清空自己的凭证。**之后必须重新配对**，否则这把锁谁都开不了。"
            case .rePair: return "到门锁上把它恢复到配网状态，手机靠近它，按开始配对。"
            }
        }

        /// 这一步会不会丢东西。界面必须写明。
        var risk: String {
            switch self {
            case .checkState, .checkKeychain: return "无风险"
            case .repairPool: return "别人的旧钥匙会失效"
            case .keypadReset: return "会清空门锁里的全部凭证，必须重新配对"
            case .rePair: return "要你到门锁上操作"
            }
        }

        /// 这一步要不要用户亲自在锁上操作。
        var needsUserAtLock: Bool {
            self == .keypadReset || self == .rePair
        }
    }

    enum Outcome: Equatable {
        case done
        case failed(String)
        /// 这一步要用户亲自做（等用户回来点「继续」）。
        case needsUser(Step)
    }

    /// 按当前症状排一条流程。
    ///
    /// - Parameter symptom: 用户描述的症状（钥匙打不开 / 连不上 / 凭证用不了）。
    static func plan(mac: String?, symptom: String) -> [Step] {
        var steps: [Step] = [.checkState, .checkKeychain]
        if symptom.contains("连不上") || symptom.contains("连接") {
            steps = [.checkState, .checkKeychain, .repairPool]
        }
        if symptom.contains("钥匙") || symptom.contains("指纹") || symptom.contains("打不开") {
            steps.append(.repairPool)
            steps.append(.keypadReset)
            steps.append(.rePair)
        }
        return steps
    }

    /// 跑一步。能自动做的自动做（读状态、修复 PIN 池），要人做的交回去。
    static func perform(_ step: Step, mac: String) async -> Outcome {
        switch step {
        case .checkState:
            guard !mac.isEmpty else { return .failed("还没有绑定门锁") }
            do {
                _ = try await LockService.shared.getStatus(mac: mac)
                return .done
            } catch {
                return .failed(error.localizedDescription)
            }
        case .checkKeychain:
            guard !mac.isEmpty, DB.keychain(mac) != nil else {
                return .failed("本机没有这把锁的档案 —— 需要重新配对")
            }
            return .done
        case .repairPool:
            guard !mac.isEmpty else { return .failed("还没有绑定门锁") }
            do {
                _ = try await LockService.shared.repairPool(m: mac) { _ in }
                return .done
            } catch {
                return .failed(error.localizedDescription)
            }
        case .keypadReset, .rePair:
            return .needsUser(step)
        }
    }

    /// 流程的总说明（界面顶部一句话）。
    static func intro(mac: String?) -> String {
        guard let mac, !mac.isEmpty else {
            return "你还没有绑定门锁。先到门锁上把它恢复到配网状态，然后在这里重新配对。"
        }
        return "按顺序走完下面这几步。每一步都会先说清风险 —— 有一半的步骤会改动门锁本身。"
    }
}
