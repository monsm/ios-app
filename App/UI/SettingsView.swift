// 设置 Tab (settings 页) — 门锁管理/安全/家人与钥匙/网关/固件/备份/应用锁/外观/关于
// 分组原则: 同一心智模型的动作放同一 Section, 不再出现"一个 Section 只有一行"的碎片。
// 所有破坏性动作统一走 confirmDestructive (全局助手), 本文件不自带弹窗实现。
import SwiftUI
import UIKit





// ---------- 安全模式说明 (safemodeintroduce) ----------
struct SafemodeIntroView: View {
    var mode = "safe"
    @EnvironmentObject var app: AppState
    @State private var switching = false
    /// 静音下发中（防止连点）
    @State private var silentBusy = false      // 拍板 #2: cmd20 下发中, 防止连点重复改锁端策略
    private var isOtp: Bool { mode == "otp" }

    var body: some View { vkBody.destined(.safemodeIntro) }
    var vkBody: some View {
        ZStack {
            XPalette.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: XSpace.section) {
                    if isOtp {
                        XPanel(kind: .group) {
                            VStack(alignment: .leading, spacing: XSpace.m) {
                                secLabel("临时密码 (ZOTP) 介绍")
                                Text("ZOTP 是临时开锁密码：6 位数字密码，每 30 分钟更换一次，同一窗口内最多 99 个。")
                                    .xFont(.footnote)
                                    .foregroundStyle(XPalette.text)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("生成前请先校准门锁时间 (0E)，否则手机与锁时间窗不同步会导致密码不匹配。")
                                    .xFont(.footnote)
                                    .foregroundStyle(XPalette.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .xScrollLift()
                    } else {
                        // 锁端开关实况 —— StatusParser 解析了 broadcastMode / tempPwdMode,
                        // 但全仓界面从未显示过这两个位。
                        // 它们和 verifyMode 同属 KLV 0x08 的 securityLevel 位域, 是锁的真实策略。
                        lockSwitchCard
                        XPanel(kind: .group) {
                            VStack(alignment: .leading, spacing: XSpace.m) {
                                secLabel("门锁的安全模式介绍")
                                Text("门锁的安全模式分为 A 模式和 B 模式")
                                    .xFont(.subheadline, weight: .medium)
                                    .foregroundStyle(XPalette.text)
                                Text("A 模式：只需要单一方式（密码／指纹／手机）验证通过就可以开锁")
                                    .xFont(.footnote)
                                    .foregroundStyle(XPalette.textSub)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("B 模式：需要用两种不同方式（指纹+密码／指纹+手机／手机+密码）组合验证通过才可开锁")
                                    .xFont(.footnote)
                                    .foregroundStyle(XPalette.textSub)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        XPanel(kind: .group) {
                            VStack(alignment: .leading, spacing: XSpace.m) {
                                secLabel("怎么设置")
                                Text("当前模式在「锁信息名片」(设备页) 读取后显示。本 App 只给变严的方向 (A→B)；要放宽回 A 模式请在门锁键盘上操作或联系管理员。")
                                    .xFont(.footnote)
                                    .foregroundStyle(XPalette.textSub)
                                    .fixedSize(horizontal: false, vertical: true)
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
                                            "锁端将要求两种不同方式组合验证才能开锁 (cmd 20)。这一步会改变锁的验证策略：切换后请先实测一次组合方式能开锁，再让其他人使用。本 App 不提供改回 A 模式的入口。",
                                            confirmTitle: "切到 B 模式") {
                                            switching = true
                                            Task { await switchToDoubleVerify() }
                                        }
                                    }
                                    .buttonStyle(XSecondaryButtonStyle())
                                    .disabled(switching)
                                }
                            }
                        }
                        .xScrollLift()
                    }
                }
                .padding(.horizontal, XSpace.gutter)
                .padding(.vertical, XSpace.l)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(isOtp ? "临时密码介绍" : "安全模式说明")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 锁端三个开关的实况（KLV 0x08 的 securityLevel 位域）
    ///
    /// bit0 = verifyMode（A/B 验证）
    /// bit1 = broadcastMode（广播）
    /// bit2 = tempPwdMode（临时密码）
    ///
    /// 三个位都在 StatusParser 里解析好了，但界面只显示过 verifyMode，
    /// 另外两个位从未出现在任何页面上。
    @ViewBuilder
    private var lockSwitchCard: some View {
        if let st = app.status {
            XPanel(kind: .group) {
                VStack(alignment: .leading, spacing: XSpace.s) {
                    secLabel("锁端开关实况")
                    switchRow("验证方式", st.verifyMode == 1 ? "B · 双验" : "A · 单验",
                              on: st.verifyMode == 1)
                    switchRow("广播模式", st.broadcastMode == 1 ? "开启" : "关闭",
                              on: st.broadcastMode == 1)
                    switchRow("临时密码", st.tempPwdMode == 1 ? "开启" : "关闭",
                              on: st.tempPwdMode == 1)
                    XHairline(inset: 0)
                    // ═══ 静音（可改）═══
                    //
                    // cmd18 与状态字段 soundVolumn 用的是**同一个字节**
                    //（0=有声 / 1=静音），所以这个开关可以安全地双向绑定。
                    //
                    // 上面三行只读：广播模式与临时密码目前没有可改的入口
                    //（cmd19 对应的状态位是否就是 tempPwdMode 无法确认，故不接）；
                    // 自动落锁与防拆报警连"当前值"都读不到，写盲更不该做。
                    XToggle("静音模式", isOn: Binding(
                        get: { st.soundVolumn == 1 },
                        set: { on in Task { await setSilentMode(on) } }))
                        .disabled(silentBusy)
                        .xFont(.caption)
                }
            }
            .xScrollLift()
        }
    }

    private func switchRow(_ label: String, _ value: String, on: Bool) -> some View {
        HStack(spacing: XSpace.s) {
            Text(label)
                .xFont(.caption)
                .foregroundStyle(XPalette.textSub)
            Spacer(minLength: 0)
            Text(value)
                .xFontExact(.caption.monospacedDigit())
                .foregroundStyle(on ? XPalette.ok : XPalette.textSub)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label + " " + value)
    }

    private func secLabel(_ text: String) -> some View {
        Text(text)
            .xFont(.caption, weight: .semibold)
            .foregroundStyle(XPalette.textTertiary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 静音开关下发。
    ///
    /// 与 cmd20 同一套口径（拍板 #2）：**rc=0 只说明锁收了命令，不代表真的改了**。
    /// 所以下发后必须回读 soundVolumn，读到的和用户想要的不一致就如实说不生效，
    /// 而不是先把 UI 翻过去再让用户以为成了。
    private func setSilentMode(_ on: Bool) async {
        guard !silentBusy else { return }
        silentBusy = true
        defer { silentBusy = false }
        do {
            try await app.lock.setSilent(on)
            await app.refreshStatusQuietly(manual: true)
            let now = (app.status?.soundVolumn == 1)
            if now == on {
                app.lock.log("warn", "静音已切换为 \(on ? "静音" : "有声") (cmd18, 回读确认)")
                app.showToast(on ? "已切到静音" : "已恢复提示音")
                XHaptics.success()
            } else {
                app.lock.log("warn", "cmd18 已下发但回读 soundVolumn 与预期不符 —— 视为未生效")
                app.showToast("设置已发送，但门锁回报的还是旧值 —— 请重读一次锁信息再试")
            }
        } catch {
            app.lock.log("warn", "切换静音失败 (cmd18): \(error.localizedDescription)")
            app.showToast("切换失败：设置没有成功发到门锁")
        }
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
                app.showToast("设置已发送，但门锁回报的还是旧值 —— 请重读一次锁信息")
            }
        } catch {
            app.lock.log("warn", "切换安全模式失败 (cmd20): \(error.localizedDescription)")
            app.showToast("切换失败：命令没有成功下发，锁仍按原模式验证 · 请靠近门锁后重试")
        }
    }
}