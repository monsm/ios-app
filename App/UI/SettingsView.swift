// 设置 Tab (settings 页) — 门锁管理/安全/家人与钥匙/网关/固件/备份/应用锁/外观/关于
// 分组原则: 同一心智模型的动作放同一 Section, 不再出现"一个 Section 只有一行"的碎片。
// 所有破坏性动作统一走 confirmDestructive (全局助手), 本文件不自带弹窗实现。
import SwiftUI
import UIKit


/// 机械计数样式数字 (idea 1006): 每位一格, 等宽数字
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

// ---------- 布防 (defend 页: 外出/在家/撤防) ----------
struct DefendView: View {
    @EnvironmentObject var app: AppState
    @State private var mode = 1
    @State private var fromTime = Date()
    @State private var toTime = Date()
    @State private var fromDate = Date()
    @State private var toDate = Date()
    @State private var busy = false

    var body: some View { vkBody.destined(.defend) }
    var vkBody: some View {
        Form {
            Picker("模式", selection: $mode) {
                Text("外出布防").tag(1)
                Text("在家布防").tag(2)
                Text("撤防").tag(0)
            }
            .pickerStyle(.segmented)
            if mode == 1 {
                Section("布防时间段") {
                    DatePicker("开始", selection: $fromDate).datePickerStyle(.compact)
                    DatePicker("结束", selection: $toDate).datePickerStyle(.compact)
                }
            } else if mode == 2 {
                Section("在家时段") {
                    DatePicker("开始", selection: $fromTime, displayedComponents: .hourAndMinute)
                    DatePicker("结束", selection: $toTime, displayedComponents: .hourAndMinute)
                }
            } else {
                Section {
                    Label {
                        Text("进行撤防操作之后，门锁将会退出布防模式")
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "info.circle").accessibilityHidden(true)
                    }
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                }
            }
            Section {
                // BusyButton 自带 minHeight 与忙碌态, 避免 Text↔ProgressView 互换导致行高抖动
                BusyButton(title: mode == 0 ? "确认撤防" : "确认布防",
                           systemImage: "shield.lefthalf.filled",
                           isBusy: busy) {
                    Task { await apply() }
                }
            } footer: {
                Text(mode == 1 ? "外出布防模式下，在该时间段内，使用指纹、密码、蓝牙无法开启该门锁" :
                     (mode == 2 ? "在家布防模式下，在该时间段内，使用指纹、密码、蓝牙无法开启该门锁" : "请打开手机蓝牙，靠近门锁进行操作"))
            }
        }
        .navigationTitle("一键布防")
        .variantList()
        .dsScreenBackground()
    }

    private func apply() async {
        guard let kc = app.current, !busy else { return }
        busy = true
        defer { busy = false }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        do {
            switch mode {
            case 1:
                let s = Int(ZKCmdBuilder.protoSec(f.string(from: fromDate)))
                let e = Int(ZKCmdBuilder.protoSec(f.string(from: toDate)))
                guard e > s else { app.showToast("结束时间必须大于开始时间"); return }
                try await app.lock.ensureConnected(mac: kc.mac)
                try await app.lock.setDefence(control: 1, startSec: s, endSec: e)
                DB.saveDefend(kc.mac, DefendCfg(control: 1, startSec: s, endSec: e, at: Date().timeIntervalSince1970 * 1000))
                app.showToast("布防成功")
            case 2:
                let cal = WeekCal.gregorian
                let sHMS = cal.dateComponents([.hour, .minute, .second], from: fromTime)
                let eHMS = cal.dateComponents([.hour, .minute, .second], from: toTime)
                let s = ((sHMS.hour ?? 0) * 3600 + (sHMS.minute ?? 0) * 60 + (sHMS.second ?? 0)) / 2
                let e = ((eHMS.hour ?? 0) * 3600 + (eHMS.minute ?? 0) * 60 + (eHMS.second ?? 0)) / 2
                guard e != s else { app.showToast("结束时间不能等于开始时间"); return }
                try await app.lock.ensureConnected(mac: kc.mac)
                try await app.lock.setDefence(control: 2, startSec: s, endSec: e)
                DB.saveDefend(kc.mac, DefendCfg(control: 2, startSec: s, endSec: e, at: Date().timeIntervalSince1970 * 1000))
                app.showToast("布防成功")
            default:
                try await app.lock.ensureConnected(mac: kc.mac)
                try await app.lock.setDefence(control: 0, startSec: 0, endSec: 0)
                DB.saveDefend(kc.mac, DefendCfg(control: 0, startSec: 0, endSec: 0, at: Date().timeIntervalSince1970 * 1000))
                app.showToast("撤防成功")
            }
        } catch {
            app.showToast("失败: \(error.localizedDescription)")
        }
    }
}

// ---------- 防尾随 (tailgate: cmd24 档位 1-6, 2~6 秒) ----------
struct TailgateView: View {
    @EnvironmentObject var app: AppState
    @State private var seconds = 6
    @State private var busy = false

    var body: some View { vkBody.destined(.tailgate) }
    var vkBody: some View {
        Form {
            Section {
                Picker("等待时长", selection: $seconds) {
                    ForEach(2...6, id: \.self) { Text("\($0) 秒").tag($0) }
                }
                .pickerStyle(.inline)
            } header: {
                Text("开锁后自动上锁等待时长")
            } footer: {
                Text("门锁默认使用蓝牙钥匙、密码、指纹等电控方式开锁，等待6秒后会自动上锁。您可以根据您的使用习惯设置等待时长，防止坏人利用等待时间尾随入室。")
            }
            Section {
                BusyButton(title: "设置", systemImage: "timer", isBusy: busy) {
                    Task { await run() }
                }
            }
        }
        .navigationTitle("防尾随入室")
        .variantList()
        .dsScreenBackground()
    }

    private func run() async {
        guard let kc = app.current, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await app.lock.ensureConnected(mac: kc.mac)
            try await app.lock.setAutoLock(seconds - 1) // cmd24 档位 = 秒数-1
            DB.saveTailgate(kc.mac, TailgateCfg(interval: seconds - 1, at: Date().timeIntervalSince1970 * 1000))
            app.showToast("设置成功")
        } catch { app.showToast("设置失败: \(error.localizedDescription)") }
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
                    Text("ZOTP 是临时开锁密码：6 位数字密码，每 30 分钟更换一次，同一窗口内最多 99 个。").vkFont(.footnote)
                    Text("生成前请先校准门锁时间 (0E)，否则手机与锁时间窗不同步会导致密码不匹配。").vkFont(.footnote)
                }
            } else {
                Section("门锁的安全模式介绍") {
                    Text("门锁的安全模式分为A模式和B模式").vkFont(.subheadline)
                    Text("A模式：只需要单一方式（密码／指纹／手机）验证通过就可以开锁").vkFont(.footnote)
                    Text("B模式：需要用两种不同方式（指纹+密码／指纹+手机／手机+密码）组合验证通过才可开锁").vkFont(.footnote)
                }
                Section("怎么设置门锁的安全模式？") {
                    Text("当前模式在「锁信息名片」(设备页) 读取后显示。本 App 只给变严的方向 (A→B)；"
                         + "要放宽回 A 模式请在门锁键盘上操作或联系管理员。").vkFont(.footnote)
                    // 拍板 #2 (第六十六批): 给切换入口, 但只允许更严方向。
                    // 不给 B→A 的理由写在这: 放宽验证会让"两种组合验证"这条既有保护一指之间消失,
                    // 而锁端不记录是谁改的 —— 本机审计只会留下一条无法解释的降级。
                    if app.status == nil {
                        Text("还没读到锁状态 —— 先在设备页读一次锁信息，这里才会出现切换按钮。")
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                    } else if app.status?.verifyMode == 1 {
                        Text("当前已是 B 模式（双验）。本 App 不提供改回 A 模式的入口。")
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.ok)
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