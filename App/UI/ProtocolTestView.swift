// 协议测试页 —— 2026-10-29 新增
//
// 来源：APK `page-testlockrom`（回声/协议自检）与 `page-romlist`（附近锁列表）两页，
// 在 APK 里都被 `showTest = !1` 硬编码关掉（不可达）；iOS 侧 `LockService.probeEcho`
// 也一直零调用。两边合起来看就是「能力有、入口没有」。
//
// 这里做成一个**隐藏诊断页**，入口在 设置-关于 连点版本号 5 次 —— 不占正常用户版面，
// 但真机排障时能用上。
//
// 安全边界：
//   · 回声探测（cmd12）**不改锁内任何东西、不写本机台账、免令牌**，对未配对设备也发得出去；
//   · 本页只提供扫描与回声，**不提供任何写命令**（不做“万能命令发送器”）。
import SwiftUI

struct ProtocolTestView: View {
    @EnvironmentObject var app: AppState

    @State private var devices: [BLEAdvDevice] = []
    @State private var scanning = false
    @State private var scanNote = ""

    @State private var targetId = ""
    @State private var echoHex = "123456"
    @State private var probe: LockService.EchoProbe?
    @State private var probeError = ""
    @State private var probing = false

    var body: some View { vkBody.destined(.protocolTest) }

    var vkBody: some View {
        Form {
            Section {
                BusyButton(title: scanning ? "扫描中…" : "扫描附近设备",
                           systemImage: "antenna.radiowaves.left.and.right",
                           isBusy: scanning) {
                    Task { await scan() }
                }
                if !scanNote.isEmpty {
                    Text(scanNote)
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("附近设备（原 RomList）")
            } footer: {
                Text("列出扫描到的全部蓝牙外设，标注 pid / 名称 / 信号 / DFU 态。pid 能解析出来说明广播里有 98ED 厂商段。")
            }

            if !devices.isEmpty {
                Section("扫描结果 (\(devices.count))") {
                    ForEach(devices) { d in
                        Button {
                            targetId = d.deviceId
                            echoHex = "123456"
                            probe = nil
                            probeError = ""
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(d.name).vkFont(.subheadline, weight: .medium)
                                    Spacer(minLength: 0)
                                    Text("\(d.rssi) dBm")
                                        .vkFont(.caption.monospacedDigit())
                                        .foregroundStyle(DS.Palette.textSub)
                                }
                                Text(describe(d))
                                    .vkFont(.caption2)
                                    .foregroundStyle(DS.Palette.textSub)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section {
                TextField("目标 deviceId", text: $targetId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .vkFont(.footnote)
                TextField("探测载荷（hex）", text: $echoHex)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .vkFont(.footnote.monospaced())
                BusyButton(title: "发送回声探测 (cmd12)", systemImage: "waveform.path",
                           isBusy: probing,
                           disabled: targetId.isEmpty || echoHex.isEmpty) {
                    Task { await runProbe() }
                }
            } header: {
                Text("回声探测（cmd12）")
            } footer: {
                Text("cmd12 不改锁内任何东西、不写本机台账、免令牌 —— 对还没配对的设备也发得出去。用来确认「链路通不通」而不是「锁状态对不对」。")
            }

            if let p = probe {
                Section("结果") {
                    LabeledContent("是否成功", value: p.ok ? "是" : "否")
                    LabeledContent("rc", value: "\(p.rc) · " + StatusParser.rcMessage(p.rc))
                    LabeledContent("耗时", value: "\(p.ms) ms")
                    LabeledContent("回显匹配", value: p.matched ? "一致" : "不一致")
                    Text(p.echoHex.isEmpty ? "（未读到回显）" : p.echoHex)
                        .vkFont(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
            if !probeError.isEmpty {
                Section {
                    Text(probeError)
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                Text("本页只提供扫描与回声探测。写命令（配对/改密/删指纹等）不在这里 —— 那些操作有各自的页面与二次确认，不该从一个「测试工具」旁路出去。")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle("协议测试")
        .variantList()
        .dsScreenBackground()
    }

    /// 一台设备的可读摘要：pid 能解析时说型号，解析不出就说明「无 98ED 段」。
    private func describe(_ d: BLEAdvDevice) -> String {
        var bits: [String] = []
        if let a = ZKProtocol.parseAdv(d.advertisHex) {
            let name = PidMap.modelName(a.pid)
            bits.append("pid=\(a.pid) (\(name))")
            if a.dfuState == 1 { bits.append("DFU 态") }
            if a.resetStatus == 1 { bits.append("重置态") }
            if let m = a.macDisplay { bits.append("MAC \(m)") }
        } else {
            bits.append("无 98ED 厂商段（pid 不可解析）")
        }
        if !d.serviceUUIDs.isEmpty {
            bits.append("服务 " + d.serviceUUIDs.prefix(2).joined(separator: ","))
        }
        return bits.joined(separator: " · ")
    }

    private func scan() async {
        guard !scanning else { return }
        scanning = true
        scanNote = ""
        devices = []
        defer { scanning = false }
        do {
            try await BLEService.shared.startScan(timeoutMs: 10_000)
            // startScan 到期自动停；这里读快照
            devices = BLEService.shared.allDiscovered()
                .sorted { $0.rssi > $1.rssi }
            scanNote = devices.isEmpty
                ? "10 秒内没有扫到设备 —— 确认蓝牙已开、锁在附近。"
                : "扫到 \(devices.count) 台（按信号从强到弱）。"
        } catch {
            scanNote = "扫描失败：\(error.localizedDescription)"
        }
    }

    private func runProbe() async {
        guard !probing else { return }
        probing = true
        probe = nil
        probeError = ""
        defer { probing = false }
        do {
            probe = try await app.lock.probeEcho(deviceId: targetId, valueHex: echoHex)
        } catch {
            probeError = "探测失败：\(error.localizedDescription)"
        }
    }
}
