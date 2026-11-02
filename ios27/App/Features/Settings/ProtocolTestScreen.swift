// ProtocolTestScreen.swift —— 协议测试（附近设备 + 回声探测）。
//
// 原版 page-testlockrom 的离线等价物：列出扫描到的全部蓝牙外设，标注 pid / 名称 / 信号 / DFU 态；
// 点一行发一次免令牌回声（不改锁内任何东西、不写台账）。写命令不在这里 —— 各有自己的页面与二次确认。
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
        // 全换系统（2026-11-02）：整页容器是系统 List。
        // 页头是整宽内容 → headerRow()；两张说明卡 → cardRow()（.plain 无系统留白）；
        // 「扫描结果」是行式内容，走 Section + 系统行。
        List {
            header.headerRow()
            scanPanel.cardRow()
            listSection
            notePanel.cardRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, V.S.gap16, for: .scrollContent)
        .contentMargins(.bottom, V.S.gap16, for: .scrollContent)
        .background(CanvasBackground())
        .navigationTitle("协议测试")
        .navigationBarTitleDisplayMode(.inline)
        .task { await scan() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: V.S.gapXS) {
            Text("协议测试")
                .font(V.F.displayHome)
                .foregroundStyle(V.C.text1)
            HStack(spacing: V.S.gapS) {
                VStateDot(tone: scanning ? .live : (devices.isEmpty ? .neutral : .ok),
                         word: scanning ? "扫描中" : "空闲")
                Text("只做扫描与回声探测；不改锁、不写台账")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text2)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scanPanel: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "附近设备", trailing: "\(devices.count) 台")
                if scanning {
                    VBusyRow(text: "正在扫描 8 秒 · 把要测的设备放在手机旁")
                } else {
                    VActionButton(title: "重新扫描", systemImage: "antenna.radiowaves.left.and.right") {
                        Task { await scan() }
                    }
                }
                if let error {
                    VStatusLine(tone: .critical, text: error)
                }
            }
        }
    }

    @ViewBuilder
    private var listSection: some View {
        Section {
            if devices.isEmpty {
                Text("没有扫到设备。确认蓝牙已开、设备在广播；门锁被连上后会停止广播，先断开再扫。")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(devices) { d in
                    VStack(alignment: .leading, spacing: V.S.gapXS) {
                        HStack(alignment: .firstTextBaseline, spacing: V.S.gapS) {
                            Text(d.name)
                                .font(V.F.bodyStrong)
                                .foregroundStyle(V.C.text1)
                            Spacer(minLength: 0)
                            // 扫描到的设备（不一定已绑定）→ rssiText，不读库。
                            let sig = Reading.rssiText(d.rssi)
                            Text(sig.spoken)
                                .font(V.F.stamp)
                                .foregroundStyle(sig.tone == .attention ? V.C.warning : V.C.text2)
                        }
                        Text("\(PidMap.productNames[d.pid] ?? "未知型号")\(d.mac.isEmpty ? "" : " · " + shortMAC(d.mac))\(d.dfu ? " · DFU" : "")")
                            .font(V.F.unit)
                            .foregroundStyle(V.C.text3)
                        VOutlineButton(title: probing == d.id ? "探测中…" : "发送回声探测",
                                        systemImage: "waveform.path") {
                            probe(d)
                        }
                        .disabled(probing != nil)
                        if let result, probing == nil {
                            Text(result)
                                .font(V.F.footnote)
                                .foregroundStyle(V.C.text2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, V.S.gapXS)
                }
            }
        } header: {
            Text("扫描结果 · \(devices.count) 台")
            .textCase(nil)
        }
    }

    private var notePanel: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "边界")
                SettingsNote(text: "回声探测免令牌、不改锁内任何东西、不写本机台账 —— 对还没配对的设备也发得出去。本页不提供任何写命令（配对/改密/删指纹等）。")
            }
        }
    }

    /// 只显示地址后 6 位：完整 12 位 hex 对用户没有意义，也不该被截图带走。
    private func shortMAC(_ m: String) -> String {
        let h = DB.normalizeMac(m)
        guard h.count == 12 else { return m }
        return String(h.suffix(6)).uppercased()
    }

    @MainActor
    private func scan() async {
        guard !scanning else { return }
        scanning = true
        error = nil
        devices = []
        do {
            // 扫满 8 秒窗口再取快照（旧实现 startScan 后立刻读，列表恒空）。
            let found = try await BLEService.shared.scanWindow(allowDuplicates: true, timeoutMs: 8000)
            var out: [Candidate] = []
            for d in found {
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
                result = r.matched ? "回声一致 · \(r.ms) ms" : "回声不匹配（锁没有应答）· \(r.ms) ms"
            } catch {
                result = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            probing = nil
        }
    }
}
