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

    private var resultTone: XToneColor { failed ? .danger : .ok }

    var body: some View { vkBody.destined(.syncTime) }
    var vkBody: some View {
        Form {
            Section {
                if app.current != nil {
                    Text("将手机时间同步到门锁内 (cmd 0E)。校准前会先读锁钟并补偿偏差。")
                        .xFont(.footnote)
                        .foregroundStyle(XPalette.textSub)
                    LabeledRow("锁钟", app.status?.lockTime.map { ProtoTime.localStr($0) } ?? "—")
                    LabeledRow("手机时间", DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))
                } else {
                    Text("请先在设备页选择一把门锁").foregroundStyle(XPalette.textSub)
                }
            } header: {
                Text("同步时间")
            }
            Section {
                XBusyButton(title: "将手机时间同步到锁内",
                            systemImage: "clock.arrow.circlepath",
                            busy: busy) {
                    Task { await run() }
                }
                .disabled(app.current == nil)
                if !result.isEmpty {
                    Label(result, systemImage: failed ? "xmark.octagon.fill" : "checkmark.circle.fill")
                        .xFont(.footnote)
                        .foregroundStyle(resultTone.color)
                }
            } footer: {
                Text("请将手机靠近门锁 · 请确保手机时间准确")
            }
        }
        .navigationTitle("同步时间")
        .xList()
        .xScreen()
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
        HStack(alignment: .firstTextBaseline, spacing: XSpace.s) {
            // 668: 这类"中文标签 + 英文缩写/数字"的行最容易看出中西文挤在一起, 统一走排版加距 (不插字符)
            cjkSpaced(label).foregroundStyle(XPalette.textSub)
            Spacer(minLength: XSpace.m)
            cjkSpaced(value)
                .foregroundStyle(XPalette.text)
                .multilineTextAlignment(.trailing)
                .lineLimit(2) // MAC/时间等长值换行而不是溢出
                .fixedSize(horizontal: false, vertical: true)
        }
        .xFont(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }
}

