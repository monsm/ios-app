// 设备 Tab — 门锁总控页。
// 层级: 设备身份 → 连接与电量 → 需要处理的异常 → 开锁主控 → 快捷操作 → 最近开门。
// 开锁是全App最高频动作, 因此占据最大视觉权重并置于拇指可达区中部。
import SwiftUI
import UIKit


// ================= 校时页 (App synctime) =================
struct SyncTimeView: View {
    @EnvironmentObject var app: AppState
    @State private var busy = false
    @State private var result = ""
    @State private var failed = false

    private var resultTone: ToneColor { failed ? .danger : .ok }

    var body: some View { vkBody.destined(.syncTime) }
    var vkBody: some View {
        Form {
            Section {
                if app.current != nil {
                    Text("将手机时间同步到门锁内 (cmd 0E)。校准前会先读锁钟并补偿偏差。")
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                    LabeledRow("锁钟", app.status?.lockTime.map { ProtoTime.localStr($0) } ?? "—")
                    LabeledRow("手机时间", DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))
                } else {
                    Text("请先在设备页选择一把门锁").foregroundStyle(DS.Palette.textSub)
                }
            } header: {
                Text("同步时间")
            }
            Section {
                BusyButton(title: "将手机时间同步到锁内",
                           systemImage: "clock.arrow.circlepath",
                           isBusy: busy,
                           disabled: app.current == nil) {
                    Task { await run() }
                }
                if !result.isEmpty {
                    Label(result, systemImage: failed ? "xmark.octagon.fill" : "checkmark.circle.fill")
                        .vkFont(.footnote)
                        .foregroundStyle(resultTone.color)
                }
            } footer: {
                Text("请将手机靠近门锁 · 请确保手机时间准确")
            }
        }
        .navigationTitle("同步时间")
        .variantList()
        .dsScreenBackground()
    }

    private func run() async {
        busy = true
        failed = false
        result = ""
        // 第八十八批: 校时页原先不先绑锁就直接 syncTime (服务层按自己的 curMac 取钥)，
        // 于是"在这个锁的页面点校时，19/0E 命令发向上次连过的那把锁"。入口钉住 + 非空才走。
        let m = app.currentMac
        guard !m.isEmpty else {
            busy = false
            failed = true
            result = "未选择门锁"
            app.showToast("未选择门锁")
            return
        }
        do {
            try await app.lock.ensureConnected(mac: m)
            // 留存口径：校时这一步本机**不落任何数** —— 记录的时间戳本来就来自锁端回包 (lockTimeStr)，
            // 与手机钟无关；把它抄一份进本机反而造出第二个"现在是几点"。AutoOpen 那条自动校时走 audit (0E 双确认)。
            try await app.lock.syncTime()
            result = "同步成功"
            app.showToast("时间已同步")
        } catch {
            failed = true
            result = "同步失败：\(error.localizedDescription)"
        }
        busy = false
    }
}

struct LabeledRow: View {
    var label: String
    var value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
            // 668: 这类"中文标签 + 英文缩写/数字"的行最容易看出中西文挤在一起, 统一走排版加距 (不插字符)
            cjkSpaced(label).foregroundStyle(DS.Palette.textSub)
            Spacer(minLength: DS.Space.m)
            cjkSpaced(value)
                .foregroundStyle(DS.Palette.text)
                .multilineTextAlignment(.trailing)
                .lineLimit(2) // MAC/时间等长值换行而不是溢出
                .fixedSize(horizontal: false, vertical: true)
        }
        .vkFont(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }
}

// ================= 81 全屏专注开锁 =================
// 只剩圆盘与状态文案的覆盖层, 手势/反馈与设备页完全同一份 UnlockDial。
struct FocusUnlockView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var lockSvc = LockService.shared
    @ObservedObject private var bleSvc = BLEService.shared

    var body: some View { vkBody.destined(.focusUnlock) }
    var vkBody: some View {
        ZStack {
            DS.Gradient.screen.ignoresSafeArea()
            VStack(spacing: DS.Space.l) {
                HStack(spacing: DS.Space.m) {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(app.displayName)
                            .vkFont(.headline)
                            .foregroundStyle(DS.Palette.text)
                            .lineLimit(1)
                        Text(linkReady ? "已就绪 · " + UnlockPrefs.gestureHint : "靠近门锁, 等待就绪")
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    Spacer(minLength: 0)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: DS.Icon.lg, weight: .medium))
                            .foregroundStyle(DS.Palette.textSub)
                            .frame(width: DS.Hit.min, height: DS.Hit.min)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel("退出专注模式")
                }
                Spacer(minLength: 0)
                UnlockDial(state: app.unlockState,
                           phase: app.phase,
                           connected: linkReady,
                           bleReady: bleSvc.isPoweredOn,
                           failStreak: app.failStreak,
                           retryText: retryText,
                           // 与设备页那台圆盘同一个读数口径: 少了这一行, VO 转子切到「电量」档时只会念"未知",
                           // 而本机明明读得到 —— 同一块盘在两个界面报两种状态里的一种。
                           batteryText: app.current.map {
                               BatteryCare.faceText(BatteryCare.facePct($0.mac, live: app.status?.powerLevel ?? -1))
                           } ?? "未知",
                           rssi: LinkSense.rssiFor(app.currentMac),
                           action: { app.requestUnlock() },
                           cancelAction: { app.cancelUnlock(notify: true) })
                Spacer(minLength: 0)
            }
            .padding(DS.Space.l)
        }
    }
    private var linkReady: Bool { lockSvc.connectedMAC == app.currentMac }
    private var retryText: String? {
        guard let w = app.retryWait else { return nil }
        return "第 \(app.retryAttempt) 次 · 等 \(w) 秒"
    }
}

// ================= 250 二次开锁应用锁闸 =================
// 同一锁 30 秒内再次开锁需先验证本机密码 (未设密码则无此闸)。
struct UnlockGateView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var pw = ""
    @State private var failed = false

    var body: some View { vkBody.destined(.unlockGate) }
    var vkBody: some View {
        VStack(spacing: DS.Space.l) {
            Image(systemName: "lock.shield")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(DS.Palette.accentText)
                .frame(width: 84, height: 84)
                .axGlassCircle()
                .accessibilityHidden(true)
            VStack(spacing: DS.Space.s) {
                Text("30 秒内再次开锁")
                    .vkFont(.title3, weight: .semibold)
                    .foregroundStyle(DS.Palette.text)
                Text("为防误触, 请先验证本机密码")
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
            }
            TextField("本机密码", text: Binding(
                get: { pw },
                set: { pw = $0; if failed { withAnimation(DS.Motion.quick) { failed = false } } }))
                .textContentType(.password)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .padding(.vertical, DS.Space.m)
                .padding(.horizontal, DS.Space.l)
                // 2026-10-14 材质统一: 与 AppLock 的口令框同一枚材质/同一条降级通道 (原先两处各写实底)
                .axGlass(DS.Radius.control)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.control)
                        .strokeBorder(failed ? DS.Palette.danger : DS.Palette.hairline, lineWidth: 0.5)
                )
                .frame(maxWidth: 280)
                .submitLabel(.go)
                .onSubmit(verify)
            if failed {
                Label("密码错误, 请重新输入", systemImage: "exclamationmark.circle.fill")
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.danger)
                    .transition(.opacity)
            }
            Button("验证并继续开锁", action: verify)
                .buttonStyle(PrimaryActionStyle())
                .frame(maxWidth: 280)
                .disabled(pw.isEmpty)
            Button("取消") { dismiss() }
                .buttonStyle(SecondaryActionStyle())
                .frame(maxWidth: 280)
            Spacer(minLength: DS.Space.xl)
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dsScreenBackground()
        .presentationDetents([.medium])
        .animation(DS.Motion.soft, value: failed)
    }

    private func verify() {
        guard !pw.isEmpty else { return }
        if DB.verifyPasscode(pw) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
            app.startUnlock()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            withAnimation(DS.Motion.quick) { failed = true }
            pw = ""
        }
    }
}