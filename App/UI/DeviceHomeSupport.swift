// 设备页附属页：校准时间 / LabeledRow / 二次开锁闸
// 2026-10-29 从 DeviceHomeView.swift（1465 行）拆出 —— 都是顶层 struct，非 private，跨文件可见
import SwiftUI

struct SyncTimeView: View {
    @EnvironmentObject var app: AppState
    @State private var busy = false
    @State private var result = ""
    @State private var failed = false
    /// 2026-10-27 (D-50)：冷却剩余秒数（0 = 无冷却）。
    /// 2026-10-30：校时的世代号 —— 只有最新那次有权写结果（与 AppState.statusTicket 同款）。
    @State private var syncTicket = 0
    @State private var coolLeft = 0

    private var resultTone: ToneColor { failed ? .danger : .ok }

    var body: some View { vkBody.destined(.syncTime) }
    var vkBody: some View {
        Form {
            Section {
                if app.current != nil {
                    Text("将手机时间同步到门锁内。校准前会先读锁钟并补偿偏差。")
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                    LabeledRow("锁钟", app.status?.lockTime.map { ProtoTime.localStr($0) } ?? "—")
                    LabeledRow("手机时间", DF.localTime())
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
        // 2026-10-30 修复（切锁竞态，与 AppState.statusTicket 同款）：
        // 校时页的 run 有两段 await，期间用户可能切到另一把锁 ——
        // 旧写法会把 B 锁的校时结果（成功 toast / result 文案）显示在 A 锁的页面上。
        // 世代号 + 返回前复核当前锁，过期的直接丢弃。
        syncTicket += 1
        let ticket = syncTicket
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
            guard ticket == syncTicket, app.currentMac == m else { return }   // 过期丢弃
            result = "同步成功"
            app.showToast("时间已同步")
        } catch {
            guard ticket == syncTicket, app.currentMac == m else { return }   // 过期丢弃
            failed = true
            result = "同步失败：\(error.localizedDescription)"
        }
        if ticket == syncTicket { busy = false }
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


// ================= 250 二次开锁应用锁闸 =================
// 同一锁 30 秒内再次开锁需先验证本机密码 (未设密码则无此闸)。
struct UnlockGateView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    @State private var pw = ""
    @State private var failed = false
    /// 2026-10-27 (D-50)：冷却剩余秒数（0 = 无冷却）。
    @State private var coolLeft = 0

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
                Text("为防误触， 请先验证本机密码")
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
            // 2026-10-27 (D-50)：冷却中优先显示冷却提示（比「密码错误」更准确 —— 这次根本没验）
            if coolLeft > 0 {
                Label("尝试次数过多，请等 \(coolLeft) 秒", systemImage: "clock.badge.exclamationmark")
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.warn)
                    .transition(.opacity)
            } else if failed {
                Label("密码错误， 请重新输入", systemImage: "exclamationmark.circle.fill")
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
        // 2026-10-27 审核修复 (AUDIT-D D-50)：接上失败计数与冷却。
        // 原先失败只清空输入框，可无限重试 —— 4 位数字码人工 1 万次可穷举，
        // 脚本化更快（本机 UI 没有系统级节流）。
        // 冷却梯度与 LockScreen 同一套（AppLock.cooldownSeconds）：3 次→30s，5 次→5min，7 次→30min。
        let lock = AppLock.shared
        let left = lock.cooldownRemaining()
        if left > 0 {
            coolLeft = left
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            withAnimation(DS.Motion.quick) { failed = true }
            pw = ""
            return
        }
        if DB.verifyPasscode(pw) {
            coolLeft = 0
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
            app.startUnlock()
        } else {
            // 走同一套计数：`recordFailure()` 会更新 failStreak 与 cooldownUntil
            coolLeft = lock.recordFailure()
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            withAnimation(DS.Motion.quick) { failed = true }
            pw = ""
        }
    }
}