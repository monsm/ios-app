// 只读试验模式（kf_trial_guard）的开关与提示条 —— 补齐一段「只读不写」的死代码。
//
// 背景：`LockService.request` 里早就有
//     if DB.store.getBool("kf_trial_guard", false) { try ZKProtocol.assertReadOnly(cmd) }
// 但全仓**没有任何写点**，所以这道护栏永远打不开。
//
// 为什么值得给它一个开关（而不是删掉）：它是**真机排障**时唯一能保证"只看不改"的手段 ——
// 05 换钥会擦 flash 域 7+8、08 会重写 PIN 池、04 会开门。没有这道闸，
// 任何人拿着一台连着的锁做"只读探测"，一次误触就把锁的密钥换掉。
//
// 设计取舍：
//   · 开关放在**实验室**（低频入口），不放在「门锁」段 —— 它不是日常功能。
//   · 一旦开启，全 App 顶部常驻红条。**必须显眼**：否则用户第二天忘了，
//     会以为"App 坏了、什么都不能改"。
//   · 关闭也要二次确认？不要 —— 关闭是**恢复**能力，拦住它等于把人锁在只读里。
//     但要在条上直接给「关闭」按钮，一步可达。
import SwiftUI

enum TrialGuard {
    static let key = "kf_trial_guard"

    /// 当前是否处于只读试验模式。
    static var isOn: Bool { DB.store.getBool(key, false) }

    /// 打开/关闭。开启要求二次确认（说明后果），关闭不需要（恢复能力不该被拦）。
    static func set(_ on: Bool) {
        if on {
            DB.store.set(key, true)
        } else {
            DB.store.remove(key)
        }
    }

    /// 给用户看的一句话后果说明。
    static let warning = "开启后：开锁、写凭证、换钥、配网、网关、固件升级、导入导出全部被拦下，"
        + "只剩读状态/读日志/读钥匙串。这是给真机排障用的，日常请关掉。"
}

/// 全 App 顶部的只读常驻条。挂在 RootView 上，`TrialGuard.isOn` 为真时显示。
///
/// 为什么不复用普通 Toast：Toast 会消失，而"当前只读"是一个**持续状态**，
/// 必须一直看得见，且要能一步关掉。
struct TrialGuardBanner: View {
    @EnvironmentObject var app: AppState
    @State private var tick = 0        // 关闭后触发重算（DB 不是可观察源）

    var body: some View {
        VStack(spacing: 0) {
            if TrialGuard.isOn {
                HStack(spacing: DS.Space.s) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: DS.Icon.xs))
                        .accessibilityHidden(true)
                    Text("只读试验模式：写入类操作已全部停用")
                        .vkFont(.caption, weight: .medium)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: DS.Space.s)
                    Button("关闭") {
                        TrialGuard.set(false)
                        tick += 1
                        app.showToast("只读试验模式已关闭")
                    }
                    .vkFont(.caption, weight: .semibold)
                    .buttonStyle(.plain)
                    .frame(minHeight: DS.Hit.min)
                }
                .padding(.horizontal, DS.Space.m)
                .frame(minHeight: DS.Hit.min)
                .background(DS.Palette.danger.opacity(0.92))
                .foregroundStyle(DS.Palette.onSem)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("只读试验模式已开启，写入类操作全部停用。双击关闭。")
            }
        }
        .id(tick)
    }
}
