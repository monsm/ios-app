//
//  DefendPage.swift
//  布防 / 撤防 —— **2026-10-24 补齐原小程序移植缺口**
//
//  ## 为什么要新建这一页
//
//  原小程序（jzzns22561）有两个页面：
//    · DefendPage      —— 选布防开始/结束时间
//    · DefendhomePage  —— 布防状态 + 一键布防/撤防
//
//  移植到 iOS 时，**协议层与存储层全做了**：
//    · ZKCmdBuilder.cmd25Defence(control, startSec, endSec)  —— cmd 25 帧构造
//    · DB.DefendCfg / DB.defend(mac) / DB.saveDefend(mac, cfg)  —— 本机记忆
//    · AutoOpenKit.defendActive(control:startSec:endSec:now:)   —— 时段判定
//    · PidMap.canDefend(pid)  —— 型号能力闸（仅 KX / V1_Pro）
//    · AutoOpen 里 F4「布防时段内一票否决」                       —— 自动开锁判定
//    · 状态码 27「门锁处于布防状态」                              —— 错误文案
//
//  **唯独没有那一屏 UI 去调用 DB.saveDefend。** 用户买回来的布防功能无法设置。
//  这是本仓典型的「后端做完、前端断线」。
//
//  ## 界面照原 App 的两块合成一页
//
//  ① 状态卡：当前布防状态 + 时间段（原 DefendhomePage 的 top_defend_date_title）
//  ② 时段设置：开始/结束时间 + 布防/撤防按钮（原 DefendPage 的时段选择）
//
//  原 App 文案照抄（已从 main.js 提取）：
//    · 「布防模式下，触碰键盘、指纹和蓝牙开锁，键盘和验证指示灯会闪烁」
//    · 「进行撤防操作之后，门锁将会退出布防模式」
//    · 「布防时间段：」/「无布防」
//

import SwiftUI

/// 布防 / 撤防页
struct DefendPage: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    /// 结束时间必须晚于开始 —— 用两个 DatePicker 绑到同一天的时刻
    // 取分量一律走 WeekCal.gregorian（本仓铁律：直接 Calendar.current 在跨时区/非公历地区会错位）
    @State private var startTime = WeekCal.gregorian.date(bySettingHour: 22, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var endTime = WeekCal.gregorian.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var busy = false
    @State private var loaded = false

    private var mac: String { app.currentMac }
    private var cfg: DefendCfg? { mac.isEmpty ? nil : DB.defend(mac) }
    private var armed: Bool { (cfg?.control ?? 0) != 0 }

    /// 型号能力：只有 KX / V1_Pro 支持布防（PidMap.canDefend）
    private var supported: Bool {
        guard let kc = app.current else { return false }
        return PidMap.canDefend(kc.pid)
    }

    var body: some View {
        XScreen("布防", subtitle: "出门布防 · 触碰键盘与指纹时指示灯闪烁") {
            if !supported {
                unsupportedCard.xScrollLift()
            } else {
                statusCard.xScrollLift()
                timeCard.xScrollLift()
                actionCard.xScrollLift()
            }
        }
        .onAppear(perform: load)
    }

    // MARK: - 加载

    private func load() {
        guard !loaded, let c = cfg else { loaded = true; return }
        // startSec / endSec 是"当天 0 点起的秒数"
        let cal = WeekCal.gregorian
        let base = cal.startOfDay(for: Date())
        startTime = base.addingTimeInterval(TimeInterval(c.startSec))
        endTime = base.addingTimeInterval(TimeInterval(c.endSec))
        loaded = true
    }

    // MARK: - 状态卡

    private var statusCard: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                Text("布防状态")
                    .xFont(.subheadline)
                    .foregroundStyle(XPalette.textTertiary)

                HStack(alignment: .firstTextBaseline, spacing: XSpace.xs) {
                    Text(armed ? "布防中" : "未布防")
                        .xFont(.title2, weight: .bold)
                        .foregroundStyle(armed ? XPalette.warn : XPalette.textSub)
                    Spacer(minLength: 0)
                    if armed {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: XIcon.sm, weight: .semibold))
                            .foregroundStyle(XPalette.warn)
                            .accessibilityHidden(true)
                    }
                }

                if armed, let c = cfg {
                    Text("布防时间段：" + bucketText(c.startSec, c.endSec))
                        .xFont(.footnote)
                        .foregroundStyle(XPalette.textSub)
                } else {
                    Text("无布防")
                        .xFont(.footnote)
                        .foregroundStyle(XPalette.textTertiary)
                }

                XHairline()

                // 原 App 原文
                Text("布防模式下，触碰键盘、指纹和蓝牙开锁，键盘和验证指示灯会闪烁。")
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func bucketText(_ s: Int, _ e: Int) -> String {
        func hhmm(_ sec: Int) -> String {
            String(format: "%02d:%02d", (sec / 3600) % 24, (sec / 60) % 60)
        }
        return hhmm(s) + " ~ " + hhmm(e)
    }

    // MARK: - 时段设置

    private var timeCard: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                Text("布防时间段")
                    .xFont(.subheadline)
                    .foregroundStyle(XPalette.textTertiary)

                DatePicker("开始时间", selection: $startTime, displayedComponents: .hourAndMinute)
                    .xFont(.body)
                    .tint(XPalette.accent)

                XHairline()

                DatePicker("结束时间", selection: $endTime, displayedComponents: .hourAndMinute)
                    .xFont(.body)
                    .tint(XPalette.accent)

                if !endAfterStart {
                    Text("结束时间必须大于开始时间")
                        .xFont(.footnote)
                        .foregroundStyle(XPalette.danger)
                }

                Text("跨零点也可用（例如 22:00 ~ 07:00）—— 门锁按「当天秒数」比较，本机照样传 22 点与 7 点。")
                    .xFont(.caption2)
                    .foregroundStyle(XPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 结束 ≠ 开始即可（跨零点合法：startSec 大、endSec 小，锁端自行处理）
    private var endAfterStart: Bool {
        Int(endTime.timeIntervalSince(startTime)) != 0
    }

    // MARK: - 动作

    private var actionCard: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                if armed {
                    XBusyButton(title: "撤防", systemImage: "shield.slash", busy: busy, style: .secondary) {
                        Task { await apply(control: 0) }
                    }
                    Text("进行撤防操作之后，门锁将会退出布防模式。")
                        .xFont(.footnote)
                        .foregroundStyle(XPalette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    XBusyButton(title: "一键布防", systemImage: "shield.lefthalf.filled", busy: busy) {
                        Task { await apply(control: 1) }
                    }
                    .disabled(!endAfterStart)
                    Text("布防后会按上面的时间段生效；时段外开锁不受影响。")
                        .xFont(.footnote)
                        .foregroundStyle(XPalette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var unsupportedCard: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.s) {
                Text("这把锁不支持布防")
                    .xFont(.subheadline, weight: .semibold)
                    .foregroundStyle(XPalette.text)
                Text("布防需要 KX 或 V1 Pro 型号（PidMap.canDefend）。当前设备型号不在支持列表内。")
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 下发

    @MainActor
    private func apply(control: Int) async {
        guard !mac.isEmpty else {
            app.showToast("请先在设备页选择一把门锁")
            return
        }
        let cal = WeekCal.gregorian
        let base = cal.startOfDay(for: Date())
        let s = Int(startTime.timeIntervalSince(base))
        let e = Int(endTime.timeIntervalSince(base))

        busy = true
        defer { busy = false }
        do {
            // 与 SettingsView 的 setSilentMode 同一调用方式：共享实例 app.lock
            try await app.lock.setDefence(control: control, startSec: s, endSec: e)
            // 只有命令被锁端接收才写本机记忆 —— 写早了会出现"本机显示布防、锁端没生效"
            DB.saveDefend(mac, DefendCfg(control: control, startSec: s, endSec: e, at: Date().timeIntervalSince1970))
            XHaptics.success()
            app.showToast(control == 1 ? "已布防（" + bucketText(s, e) + "）" : "已撤防")
        } catch {
            XHaptics.failure()
            app.showToast("设置失败：" + ErrorText.human(error))
        }
    }
}
