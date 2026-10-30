// 设置页子页：机械计数器 / 防尾随 / 安全模式
// 2026-10-29 从 SettingsView.swift（1209 行）拆出 —— 都是顶层 struct，非 private，跨文件可见
import SwiftUI

struct MechCounter: View {
    let value: Int
    var body: some View {
        HStack(spacing: DS.Space.xs) {
            ForEach(Array(String(value).enumerated()), id: \.offset) { _, ch in
                Text(String(ch))
                    .vkFont(.subheadline, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(DS.Palette.text)
                    .frame(width: 22)
                    // @layout-allow VK豁免 刻度点: 22pt 宽的控制零件，不是容器
                    .background(DS.Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(DS.Palette.hairline, lineWidth: 0.5)
                    )
            }
        }
        .accessibilityHidden(true)
    }
}


// ---------- 防尾随 (tailgate: cmd24 档位 = 秒数，2~6 秒（APK 索引即秒数）) ----------
struct TailgateView: View {
    @EnvironmentObject var app: AppState
    @State private var seconds = 6          // 初值 6 = APK 默认档；进页时用已存配置覆盖（见 .task）
    @State private var busy = false

    var body: some View { vkBody.destined(.tailgate) }
    /// 2026-10-30 补（第 115 轮）：本页原来**从不读 `DB.tailgate(mac)`** —— `seconds` 恒为初值 6。
    /// 后果：之前设成 3 秒的用户再进来看到的是 6 秒，直接点「设置」就把存值**改回 6 秒**（防尾随时间变长，安全相关）。
    private func loadSaved() {
        guard let mac = app.current?.mac, !mac.isEmpty, let c = DB.tailgate(mac) else { return }
        if (2...6).contains(c.interval) { seconds = c.interval }
    }
    var vkBody: some View {
        Form {
            Section {
                Picker("等待时长", selection: $seconds) {
                    // 2026-10-28 修（**安全相关 off-by-one**）：APK `TailgatePage.chooseBtnImgStrs`
                    // 是 `["","","off","off","off","off","checkmark"]`（长度 7，索引 0..6），
                    // `getCurrentChooseSecond()` 从索引 2 遍历到 6、**返回索引本身**，
                    // `execSetTailgate` 又把这个索引值直接 `new Hi(索引, mac)` 送 cmd24 ——
                    // 所以档位就是 **2/3/4/5/6 秒，默认 6 秒**（不是 1..6、也没有 7 秒）。
                    // 原实现 `2...7` + `seconds-1` 让「选 6 秒」实际下发 5 秒 —— 防尾随时间
                    // 比用户设定短 1 秒，正好是尾随者挤进门的那 1 秒。
                    ForEach(2...6, id: \.self) { Text("\($0) 秒").tag($0) }
                }
                .pickerStyle(.inline)
            } header: {
                Text("开锁后自动上锁等待时长")
            } footer: {
                Text("门锁默认使用蓝牙钥匙、密码、指纹等电控方式开锁，等待 6 秒后会自动上锁。您可以根据您的使用习惯设置等待时长，防止坏人利用等待时间尾随入室。")
            }
            Section {
                BusyButton(title: "设置", systemImage: "timer", isBusy: busy) {
                    Task { await run() }
                }
            }
        }
        .task { loadSaved() }
        .navigationTitle("防尾随入室")
        .variantList()
        .dsScreenBackground()
    }

    private func run() async {
        guard let kc = app.current, !busy else { return }
        // 2026-10-30 补（第 139 轮，**缺失门禁**）：`PidMap.canTailgate(pid:fw:)` 早就存在、
        // `LockSettingsView:117` 也在用，唯独本页没有 —— 不支持防尾随的锁照样能发 cmd24。
        guard PidMap.canTailgate(kc.pid, fw: kc.fw) else {
            app.showToast("这把锁不支持防尾随（型号不在白名单，或固件太旧）")
            return
        }
        busy = true
        defer { busy = false }
        do {
            try await app.lock.ensureConnected(mac: kc.mac)
            try await app.lock.setAutoLock(seconds) // cmd24 档位 = 秒数本身（见 Picker 上方注释）
            DB.saveTailgate(kc.mac, TailgateCfg(interval: seconds, at: Date().timeIntervalSince1970 * 1000))
            app.showToast("设置成功")
        } catch { app.showToast("设置失败： \(error.localizedDescription)") }
    }
}

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
                    // 2026-10-30 修复（第 92 轮）：原写「最多 99 个」—— 与生成侧 `if idx > 99 { 拒绝 }` 矛盾。
                    // `idx` 允许 0…99 共 **100** 个；`CredentialOtp` 的提示与注释也都写 100。
                    Text("ZOTP 是临时开锁密码：6 位数字密码，按锁端上报的周期自动更换（缺省 30 分钟），同一窗口内最多 100 个。").vkFont(.footnote)   // 2026-10-30：原来把缺省值 30 分钟写成固定值，而生成侧按锁端 zotpPeriod 计算
                    // 2026-10-30 修复（第 74 轮）：`(0E)` 是协议命令号，说明页不该让用户看到内部编号。
                    Text("生成前请先校准门锁时间，否则手机与锁的时间窗不同步会导致密码不匹配。").vkFont(.footnote)
                }
            } else {
                Section("怎么设置门锁的安全模式？") {
                    // 2026-10-28 补：APK 的 page-safemodeintroduce 有 A/B 两档的完整定义，
                    // iOS 这边只写「当前已是 B 模式」，用户不知道 A 和 B 到底差在哪。
                    Text("A 模式：只需要单一方式（密码 / 指纹 / 手机）验证通过就可以开锁。")
                        .vkFont(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("B 模式：需要两种不同方式组合验证（指纹+密码 / 指纹+手机 / 手机+密码）才能开锁。")
                        .vkFont(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("只有 A 模式下临时开锁密码（ZOTP）才有效。")
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.warn)
                        .fixedSize(horizontal: false, vertical: true)
                    // 2026-10-30 修复（第 116 轮，**文案自相矛盾**）：原文写「本 App 只给变严的方向 (A→B)」，
                    // 而下面 L137 就有货真价实的「改回 A 模式」按钮（2026-10-29 用户拍板加的）。
                    Text("两个方向都能切：切 B 更严、切回 A 更宽松（放宽方向会二次确认）。").vkFont(.footnote)
                    // 2026-10-30 更新：拍板改为「两个方向都能切，放宽方向二次确认」——
                    // 原「只允许更严方向」的口径已作废（用户 2026-10-29 拍板恢复 B→A 入口）。
                    if app.status == nil {
                        // 2026-10-29：给一个**就地重试**按钮，而不是让用户自己跑去设备页。
                        Button {
                            Task { await app.refreshStatusQuietly(manual: true) }
                        } label: {
                            Label("还没读到锁状态 —— 点这里读取", systemImage: "arrow.clockwise")
                        }
                        .frame(minHeight: DS.Hit.min)
                        .vkFont(.footnote)
                    } else if let s = app.status, s.verifyMode == 1, s.broadcastMode == 0 {
                        // 2026-10-30 修复（第 124 轮）：C 模式（verifyMode=1 且 broadcastMode=0）也被下面的
                        // `verifyMode == 1` 判成「当前已是 B 模式（双验）」，并给出「改回 A」按钮 —— 会误导用户降级。
                        // B 模式的判据是 `verifyMode == 1 且 broadcastMode != 0`（与 LockSettingsView:106 同口径）。
                        Text("当前是 C 模式（广播 + 验证）。本页只在 A / B 两档之间切换，C 模式请到「锁设置」里改。")
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                    } else if app.status?.verifyMode == 1 {
                        // 2026-10-29 补（用户拍板）：APK `page-setsafemode` 是 A/B 二选一，iOS 原先只给 A→B。
                        // 放宽方向保留二次确认与明确的安全等级警告 —— 不是无提示的降级。
                        Text("当前已是 B 模式（双验）。可以改回 A 模式（更宽松）。")
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.ok)
                        Button(switching ? "切换中…" : "改回 A 模式（单验，更宽松）") {
                            confirmDestructive("改回 A 模式（单验）",
                                "锁端将只需单一方式验证就能开锁：原来要两种组合，改回后一种即可。"
                                + "这是降低安全等级，请确认你确实需要这样。切换后请先实测。",
                                confirmTitle: "改回 A 模式") {
                                switching = true
                                Task { await switchToSingleVerify() }
                            }
                        }
                        .vkFont(.subheadline, weight: .medium)
                        .foregroundStyle(DS.Palette.accentText)
                        .disabled(switching)
                        .frame(minHeight: DS.Hit.min)
                    } else {
                        Button(switching ? "切换中…" : "切换到 B 模式（双验，更严）") {
                            confirmDestructive("切换到 B 模式（双验）",
                                "锁端将要求两种不同方式组合验证才能开锁。这一步会改变锁的验证策略："
                                + "切换后请先实测一次组合方式能开锁，再让其他人使用。可以随时用同一入口改回 A 模式（会二次确认）。",
                                confirmTitle: "切到 B 模式") {
                                switching = true
                                Task { await switchToDoubleVerify() }
                            }
                        }
                        .vkFont(.subheadline, weight: .medium)
                        .foregroundStyle(DS.Palette.accentText)
                        .disabled(switching)
                        .frame(minHeight: DS.Hit.min)
                    }
                }
            }
        }
        .navigationTitle(isOtp ? "临时密码介绍" : "安全模式说明")
        .variantList()
        .dsScreenBackground()
        // 2026-10-29 修复「A/B 只看到说明，没有实际切换」：
        // 切换按钮只在 `app.status != nil` 时出现，而本页原先不主动读状态 ——
        // 用户从设备页进来若还没读过锁信息，就只看到两段说明 + 一句"还没读到锁状态"。
        // 现在进页自读一次（manual: true 让静默排查档不吞掉这次回读）。
        .task {
            if app.status == nil {
                await app.refreshStatusQuietly(manual: true)
            }
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
                app.showToast("命令已下发，但回读显示未生效 —— 请重读锁信息再试一次")
            }
        } catch {
            app.lock.log("warn", "切换安全模式失败 (cmd20): \(error.localizedDescription)")
            app.showToast("切换失败：命令没有成功下发，锁仍按原模式验证")
        }
    }

    /// 2026-10-29：改回 A 模式（单验）。与 switchToDoubleVerify 同一条「下发后回读」纪律。
    private func switchToSingleVerify() async {
        defer { switching = false }
        do {
            try await app.lock.setValidationMode(false)
            await app.refreshStatusQuietly(manual: true)
            if app.status?.verifyMode == 0 {
                app.lock.log("warn", "安全模式已切换 B→A 单验 (cmd20, 回读确认 verifyMode=0)")
                app.showToast("已切回 A 模式（单验），锁状态已回读确认")
            } else {
                app.lock.log("warn", "cmd20 已下发但回读 verifyMode 仍不是 A —— 视为未生效 (不报成功)")
                app.showToast("命令已下发，但回读显示未生效 —— 请重读锁信息再试一次")
            }
        } catch {
            app.lock.log("warn", "切换安全模式失败 (cmd20): \(error.localizedDescription)")
            app.showToast("切换失败：命令没有成功下发，锁仍按原模式验证")
        }
    }
}