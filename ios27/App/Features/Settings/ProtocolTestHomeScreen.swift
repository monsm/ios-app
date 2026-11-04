// ProtocolTestHomeScreen.swift —— 协议测试（V8 设计语言）
//
// 与 ProtocolTestScreen 的能力对齐：扫描附近全部蓝牙外设并列出 pid / 名称 / 信号 / DFU 态；
// 点一台发一次免令牌回声探测（不改锁内任何东西、不写台账）。
// 写命令不在这里 —— 各有自己的页面与二次确认。
//
// 与旧页的刻意差异：旧页把协议返回码直接拼进用户可见的结果行，本页只保留
// 「回声一致 / 不匹配 / 回帧异常 + 耗时」这三句人话；判定语义不变，协议词不上屏。
import SwiftUI

struct ProtocolTestHomeScreen: View {
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
    @State private var resultDevice: String?
    @State private var error: String?

    private var judgement: String {
        if scanning { return "正在扫描附近设备" }
        if devices.isEmpty { return "没有扫到设备" }
        return "扫到 \(devices.count) 台设备"
    }

    private var dfuCount: Int { devices.filter { $0.dfu }.count }

    var body: some View {
        VPage(title: judgement, lead: "只扫描与回声探测：不改锁、不写台账。列表按信号强弱排序，越靠前越近。") {
            chipRow
        } content: {
            scanCard
            if devices.isEmpty {
                VEmpty(
                    title: "没有扫到设备",
                    reason: "确认蓝牙已开、设备在广播；门锁被连上后会停止广播，先断开再扫。扫描只读广播，不连接、不发命令。",
                    actionTitle: "重新扫描"
                ) { Task { await scan() } }
            } else {
                listCard
            }
            noteCard
            errorCard
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { await scan() }
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: V8.S.gapChip) {
                VChip2(icon: .glyph("antenna.radiowaves.left.and.right"), label: "状态", value: scanning ? "扫描中" : "空闲")
                VChip2(icon: .ring(devices.isEmpty ? 0.02 : 1, devices.isEmpty ? V8.C.ink4 : V8.C.ok),
                       label: "设备", value: "\(devices.count) 台")
                VChip2(icon: .ring(devices.isEmpty ? 0.02 : Double(dfuCount) / Double(max(1, devices.count)),
                                   dfuCount == 0 ? V8.C.ink4 : V8.C.warn),
                       label: "DFU", value: "\(dfuCount) 台")
            }
            .padding(.leading, V8.S.gutterCard)
            .padding(.trailing, V8.S.gutterCard)
        }
        .scrollClipDisabled()
    }

    // MARK: - 扫描

    private var scanCard: some View {
        VCard2 {
            VCardHead(eyebrow: "附近设备", statement: scanning ? "正在扫描 8 秒" : "扫描窗口 8 秒", trailing: "\(devices.count) 台")
            VDivider2()
                .padding(.top, V8.S.gapM)
            if scanning {
                VBusy(text: "正在扫描 8 秒 · 把要测的设备放在手机旁")
                    .padding(.top, V8.S.gapM)
            } else {
                Button { Task { await scan() } } label: {
                    Text("重新扫描")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.chipOn)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.accent))
                }
                .buttonStyle(.plain)
                .padding(.top, V8.S.gapM)
            }
            Text("门锁被连上后会停止广播；先断开再扫。扫描只读广播，不连接、不发命令。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 扫描结果

    private var listCard: some View {
        VCard2 {
            VCardHead(eyebrow: "扫描结果", statement: devices.isEmpty ? "还没有设备" : "\(devices.count) 台按信号排序")
            VDivider2()
                .padding(.top, V8.S.gapM)
            if devices.isEmpty {
                Text("没有扫到设备。确认蓝牙已开、设备在广播；门锁被连上后会停止广播，先断开再扫。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(devices.enumerated()), id: \.element.id) { pair in
                        if pair.offset > 0 {
                            VDotRule()
                                .padding(.vertical, V8.S.gapS)
                        }
                        deviceBlock(pair.element)
                    }
                }
                .padding(.top, V8.S.gapS)
            }
        }
    }

    private func deviceBlock(_ d: Candidate) -> some View {
        VStack(alignment: .leading, spacing: V8.S.gapXS) {
            HStack(alignment: .firstTextBaseline, spacing: V8.S.gapS) {
                Text(d.name)
                    .font(V8.T.value)
                    .foregroundStyle(V8.C.ink1)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(d.rssi) dBm")
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
                    .monospacedDigit()
            }
            Text("pid \(d.pid) · \(d.mac.isEmpty ? "无 MAC" : d.mac)\(d.dfu ? " · DFU" : "")")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .fixedSize(horizontal: false, vertical: true)
            Button { probe(d) } label: {
                Text(probing == d.id ? "探测中…" : "发送回声探测")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.chipOn)
                    .padding(.horizontal, V8.S.gapL)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(probing == d.id ? V8.C.chipOff : V8.C.accent))
            }
            .buttonStyle(.plain)
            .disabled(probing != nil)
            .padding(.top, V8.S.gapXS)
            if let result, resultDevice == d.id, probing == nil {
                Text(result)
                    .font(V8.T.footnote)
                    .foregroundStyle(result.hasPrefix("回声一致") ? V8.C.ok : V8.C.danger)
                    .padding(.top, V8.S.gapXS)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: V8.H.min)
    }

    // MARK: - 边界

    private var noteCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "边界", statement: "这一页只读")
            Text("回声探测不需要令牌、不改锁内任何东西、不写本机台账 —— 对还没配对的设备也发得出去。本页不提供任何写命令（配对 / 改密 / 删指纹等都不在）。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Text("只读试验模式下这一页仍然可用：回声探测本来就属于放行的只读操作。")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 失败态

    @ViewBuilder
    private var errorCard: some View {
        if let error {
            VFailure(
                what: "扫描没有完成",
                why: error,
                next: "确认蓝牙已开、设备在广播；门锁被连上后会停止广播，先断开再扫。"
            ) { Task { await scan() } }
        }
    }

    // MARK: - 动作

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
        resultDevice = nil
        Task { @MainActor in
            do {
                let r = try await LockService.shared.probeEcho(deviceId: d.id)
                result = r.matched
                    ? "回声一致 · \(r.ms) ms"
                    : (r.ok ? "回声不匹配 · \(r.ms) ms" : "设备回帧异常 · \(r.ms) ms")
            } catch {
                result = "探测失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
            resultDevice = d.id
            probing = nil
        }
    }
}
