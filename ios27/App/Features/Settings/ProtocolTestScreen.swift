// ProtocolTestScreen.swift —— 协议测试（附近设备 + cmd12 回声探测）。
//
// 原版 page-testlockrom 的离线等价物：列出扫描到的全部蓝牙外设，标注 pid / 名称 / 信号 / DFU 态；
// 点一行发一次 cmd12 免令牌回声（不改锁内任何东西、不写台账）。写命令不在这里 —— 各有自己的页面与二次确认。
import SwiftUI

struct ProtocolTestScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    private struct Candidate: Identifiable {
        let id: String
        let name: String
        let pid: Int
        let mac: String
        let rssi: Int
        let dfu: Bool
    }

    @State private var devices: [Candidate] = []
    @State private var scanning = false
    @State private var probing: String?
    @State private var result: String?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: T.S.l) {
                header
                scanPanel
                listPanel
                notePanel
            }
            .padding(.vertical, T.S.l)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("协议测试")
        .navigationBarTitleDisplayMode(.inline)
        .task { await scan() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: T.S.xs) {
            Text("协议测试")
                .font(T.F.display())
                .foregroundStyle(Ink.ink)
            HStack(spacing: T.S.s) {
                StateDot(tone: scanning ? .live : (devices.isEmpty ? .neutral : .ok),
                         word: scanning ? "扫描中" : "空闲")
                Text("只做扫描与 cmd12 回声；不改锁、不写台账")
                    .font(T.F.caption)
                    .foregroundStyle(Ink.inkSub)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, T.S.gutter)
    }

    private var scanPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "附近设备", trailing: "\(devices.count) 台")
                if scanning {
                    BusyRow(text: "正在扫描 8 秒 · 把要测的设备放在手机旁")
                } else {
                    PrimaryAction(title: "重新扫描", systemImage: "antenna.radiowaves.left.and.right") {
                        Task { await scan() }
                    }
                }
                if let error {
                    StatusLine(tone: .critical, text: error)
                }
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    private var listPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "扫描结果")
                if devices.isEmpty {
                    Text("没有扫到设备。确认蓝牙已开、设备在广播；门锁被连上后会停止广播，先断开再扫。")
                        .font(T.F.caption)
                        .foregroundStyle(Ink.inkSub)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(devices) { d in
                        VStack(alignment: .leading, spacing: T.S.xs) {
                            HStack(alignment: .firstTextBaseline, spacing: T.S.s) {
                                Text(d.name)
                                    .font(T.F.bodyStrong)
                                    .foregroundStyle(Ink.ink)
                                Spacer(minLength: 0)
                                Text("\(d.rssi) dBm")
                                    .font(T.F.stamp)
                                    .foregroundStyle(Ink.inkSub)
                            }
                            Text("pid \(d.pid) · \(d.mac.isEmpty ? "无 MAC" : d.mac)\(d.dfu ? " · DFU" : "")")
                                .font(T.F.unit)
                                .foregroundStyle(Ink.inkFaint)
                            SecondaryAction(title: probing == d.id ? "探测中…" : "发送回声探测 (cmd12)",
                                            systemImage: "waveform.path") {
                                probe(d)
                            }
                            .disabled(probing != nil)
                            if let result, probing == nil {
                                Text(result)
                                    .font(T.F.caption)
                                    .foregroundStyle(Ink.inkSub)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, T.S.xs)
                        .frame(minHeight: T.Hit.min)
                    }
                }
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    private var notePanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "边界")
                SettingsNote(text: "cmd12 免令牌、不改锁内任何东西、不写本机台账 —— 对还没配对的设备也发得出去。本页不提供任何写命令（配对/改密/删指纹等）。")
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    @MainActor
    private func scan() async {
        guard !scanning else { return }
        scanning = true
        error = nil
        devices = []
        do {
            try await BLEService.shared.startScan(allowDuplicates: true, timeoutMs: 8000)
            var out: [Candidate] = []
            for d in BLEService.shared.allDiscovered() {
                guard let adv = ZKProtocol.parseAdv(d.advertisHex) else { continue }
                let mac = ZKProtocol.lockMac(fromAdv: adv) ?? ""
                out.append(Candidate(id: d.deviceId,
                                     name: d.name.isEmpty ? (PidMap.productNames[adv.pid] ?? "未知设备") : d.name,
                                     pid: adv.pid, mac: mac, rssi: d.rssi, dfu: adv.dfuState != 0))
            }
            devices = out.sorted { $0.rssi > $1.rssi }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        scanning = false
    }

    @MainActor
    private func probe(_ d: Candidate) {
        guard probing == nil else { return }
        probing = d.id
        result = nil
        Task { @MainActor in
            do {
                let r = try await LockService.shared.probeEcho(deviceId: d.id)
                result = r.matched ? "回声一致 · \(r.ms) ms · rc=\(r.rc)" : "回声不匹配 · \(r.ms) ms · rc=\(r.rc)"
            } catch {
                result = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            probing = nil
        }
    }
}
