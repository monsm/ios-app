// 设置 Tab (settings 页) — 门锁管理/安全/家人与钥匙/网关/固件/备份/应用锁/外观/关于
// 分组原则: 同一心智模型的动作放同一 Section, 不再出现"一个 Section 只有一行"的碎片。
// 所有破坏性动作统一走 confirmDestructive (全局助手), 本文件不自带弹窗实现。
import SwiftUI
import UIKit





// ---------- 安全模式说明 (safemodeintroduce) ----------
struct SafemodeIntroView: View {
    var mode = "safe"
    @EnvironmentObject var app: AppState
    @State private var switching = false      // 拍板 #2: cmd20 下发中, 防止连点重复改锁端策略
    private var isOtp: Bool { mode == "otp" }

    var body: some View { vkBody.destined(.safemodeIntro) }
    var vkBody: some View {
        Form {
            if isOtp {
                Section("临时密码 (ZOTP) 介绍") {
                    Text("ZOTP 是临时开锁密码：6 位数字密码，每 30 分钟更换一次，同一窗口内最多 99 个。").xFont(.footnote)
                    Text("生成前请先校准门锁时间 (0E)，否则手机与锁时间窗不同步会导致密码不匹配。").xFont(.footnote)
                }
            } else {
                Section("门锁的安全模式介绍") {
                    Text("门锁的安全模式分为A模式和B模式").xFont(.subheadline)
                    Text("A模式：只需要单一方式（密码／指纹／手机）验证通过就可以开锁").xFont(.footnote)
                    Text("B模式：需要用两种不同方式（指纹+密码／指纹+手机／手机+密码）组合验证通过才可开锁").xFont(.footnote)
                }
                Section("怎么设置门锁的安全模式？") {
                    Text("当前模式在「锁信息名片」(设备页) 读取后显示。本 App 只给变严的方向 (A→B)；"
                         + "要放宽回 A 模式请在门锁键盘上操作或联系管理员。").xFont(.footnote)
                    // 拍板 #2 (第六十六批): 给切换入口, 但只允许更严方向。
                    // 不给 B→A 的理由写在这: 放宽验证会让"两种组合验证"这条既有保护一指之间消失,
                    // 而锁端不记录是谁改的 —— 本机审计只会留下一条无法解释的降级。
                    if app.status == nil {
                        Text("还没读到锁状态 —— 先在设备页读一次锁信息，这里才会出现切换按钮。")
                            .xFont(.footnote)
                            .foregroundStyle(XPalette.textSub)
                    } else if app.status?.verifyMode == 1 {
                        Text("当前已是 B 模式（双验）。本 App 不提供改回 A 模式的入口。")
                            .xFont(.footnote)
                            .foregroundStyle(XPalette.ok)
                    } else {
                        Button(switching ? "切换中…" : "切换到 B 模式（双验，更严）(cmd 20)") {
                            confirmDestructive("切换到 B 模式（双验）",
                                "锁端将要求两种不同方式组合验证才能开锁 (cmd 20)。这一步会改变锁的验证策略："
                                + "切换后请先实测一次组合方式能开锁，再让其他人使用。本 App 不提供改回 A 模式的入口。",
                                confirmTitle: "切到 B 模式") {
                                switching = true
                                Task { await switchToDoubleVerify() }
                            }
                        }
                        .xFont(.subheadline, weight: .medium)
                        .foregroundStyle(XPalette.accentText)
                        .disabled(switching)
                        .frame(minHeight: XHit.min)
                    }
                }
            }
        }
        .navigationTitle(isOtp ? "临时密码介绍" : "安全模式说明")
        .xList()
        .xScreen()
    }

    /// 拍板 #2: 下发 cmd20 后**必须回读校验** —— rc=0 只说明锁收了命令, 不代表验证策略真的改了。
    /// 没回读就报"已切换"是拿猜测给用户信心; 回读到不是 B 模式就如实说"未生效", 让人重读再试。
    private func switchToDoubleVerify() async {
        defer { switching = false }
        do {
            try await app.lock.setValidationMode(true)
            // 留存口径：这个开关**以锁端为准**，本机不另存一份"我以为的状态"——
            // 下面立刻回读校验，读到不是 B 模式就如实报"未生效"。存一份本地副本只会造出第二个真相。
            // 这条是"下发后的回读校验" (拍板 #2), 属于用户刚做的手动动作; 不传 manual:true 的话
            // 静默排查档会把回读一起吞掉, 于是界面永远报"未生效" —— 那是把闸接错地方。
            await app.refreshStatusQuietly(manual: true)
            if app.status?.verifyMode == 1 {
                app.lock.log("warn", "安全模式已切换 A→B 双验 (cmd20, 回读确认 verifyMode=1)")
                app.showToast("已切到 B 模式（双验），锁状态已回读确认")
            } else {
                app.lock.log("warn", "cmd20 已下发但回读 verifyMode 仍不是 B —— 视为未生效 (不报成功)")
                app.showToast("命令已下发，但回读显示未生效 —— 请重读锁信息再试一次")
            }
        } catch {
            app.lock.log("warn", "切换安全模式失败 (cmd20): \(error.localizedDescription)")
            app.showToast("切换失败：命令没有成功下发，锁仍按原模式验证")
        }
    }
}