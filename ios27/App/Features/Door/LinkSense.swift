// LinkSense.swift —— 连接感知（预热 / 重连阶梯 / RSSI 历史 / 信号条）。
//
// 来源：原 App/Core/LinkSenseKit.swift + LinkSenseReconnect.swift + LinkSenseViews.swift
//   （LinkSense 预热/回连节律、RSSI 四格信号条、蓝牙未开横幅）。
// 这屏干什么：在设备页顶部常驻一条链路面板 —— 显示三态、最近 RSSI 与四格信号条、握手耗时、
//   5/15/30/60/90 秒重连阶梯；「预热」只建立到就绪态，绝不下发开锁或凭证（96 铁律）。
// 数据从哪来：BLEService（扫描 / readLinkRSSI / isPoweredOn）+ LockService.connectedMAC。
// 主动作：「预热」与「重连」都是只读协作，不改锁端任何东西。
import SwiftUI

@MainActor
@Observable
final class LinkSenseModel {
    enum Phase: String {
        case ready = "已连接"
        case connecting = "握手中"
        case down = "未连接"
        case noKey = "密钥未绑定"
    }

    static let ladder: [Double] = [5, 15, 30, 60, 90]

    var phase: Phase = .down
    var lastRSSI: Int?
    var history: [Int] = []
    var connectMs: Int?
    var connectSource = "预热"
    var attempt = 0
    var busy = false
    var lastEvent = "进页会自动预热一次，只建立连接，不开锁。"
    var bluetoothOn = BLEService.shared.isPoweredOn

    private var mac = ""

    func update(mac newMac: String) {
        if mac != newMac {
            mac = newMac
            history = DB.store.get([Int].self, "kf_rssi_hist_" + newMac) ?? []
            lastRSSI = LinkSenseModel.savedRSSI(newMac)
            attempt = 0
        }
        phase = resolvePhase()
        bluetoothOn = BLEService.shared.isPoweredOn
    }

    var rssiLevel: Int { LinkSenseModel.level(lastRSSI) }
    var rssiWord: String { LinkSenseModel.levelWord(rssiLevel) }
    var nextLadder: Double { LinkSenseModel.ladder[min(max(attempt, 0), LinkSenseModel.ladder.count - 1)] }

    static func level(_ rssi: Int?) -> Int {
        guard let r = rssi else { return 0 }
        if r >= -55 { return 4 }
        if r >= -65 { return 3 }
        if r >= -75 { return 2 }
        if r >= -85 { return 1 }
        return 0
    }

    static func levelWord(_ level: Int) -> String {
        ["不可测", "远", "中", "近", "满"][min(max(level, 0), 4)]
    }

    static func savedRSSI(_ mac: String) -> Int? {
        DB.store.get(Int.self, "kf_linkrssi_" + mac)
    }

    private func resolvePhase() -> Phase {
        guard !mac.isEmpty else { return .down }
        if DB.keychain(mac) == nil { return .noKey }
        if LockService.shared.connectedMAC == mac { return .ready }
        return busy ? .connecting : .down
    }

    /// 预热：只扫描到目标锁 → 记录 RSSI → ensureConnected。绝不开锁。
    func preheat() async {
        guard !mac.isEmpty, !busy else { return }
        busy = true
        phase = .connecting
        lastEvent = "正在预热：先扫到这把锁，再握手…"
        let t0 = Date()
        do {
            try await BLEService.shared.startScan(allowDuplicates: false, timeoutMs: 3000)
            var hit: BLEAdvDevice?
            let deadline = Date().addingTimeInterval(3)
            while Date() < deadline, hit == nil {
                hit = BLEService.shared.allDiscovered().first { adv in
                    guard let a = ZKProtocol.parseAdv(adv.advertisHex),
                          let disp = a.macDisplay else { return false }
                    return DB.normalizeMac(disp) == DB.normalizeMac(mac)
                }
                if hit == nil { try? await Task.sleep(for: .milliseconds(200)) }
            }
            BLEService.shared.stopScan()
            if let rssi = hit?.rssi { recordRSSI(rssi) }
            try await LockService.shared.ensureConnected(mac: mac)
            connectMs = Int(Date().timeIntervalSince(t0) * 1000)
            connectSource = "预热"
            attempt = 0
            markReady()
            lastEvent = "预热完成 · \(connectMs ?? 0)ms · 只建立到就绪态，未开锁"
        } catch {
            BLEService.shared.stopScan()
            attempt += 1
            busy = false
            phase = resolvePhase()
            lastEvent = "预热失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// 重连阶梯：每按一次进一档，5/15/30/60/90 秒提示下一次自然重试的间隔。
    func reconnect() async {
        guard !mac.isEmpty, !busy else { return }
        busy = true
        phase = .connecting
        lastEvent = "重连第 \(attempt + 1) 轮（阶梯 \(Int(nextLadder)) 秒）…"
        let t0 = Date()
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            connectMs = Int(Date().timeIntervalSince(t0) * 1000)
            connectSource = "回连"
            attempt = 0
            markReady()
            lastEvent = "回连成功 · \(connectMs ?? 0)ms"
        } catch {
            attempt = min(attempt + 1, LinkSenseModel.ladder.count)
            busy = false
            phase = resolvePhase()
            lastEvent = "回连失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// 读一次连接上的 RSSI（系统 readRSSI，不占协议往返）。
    func readRSSI() {
        guard !mac.isEmpty else { return }
        BLEService.shared.readLinkRSSI { value in
            guard let value else { return }
            Task { @MainActor in self.recordRSSI(value) }
        }
    }

    func recordRSSI(_ value: Int) {
        lastRSSI = value
        history.append(value)
        if history.count > 24 { history.removeFirst(history.count - 24) }
        DB.store.set("kf_linkrssi_" + mac, value)
        DB.store.set("kf_rssi_hist_" + mac, history)
    }

    private func markReady() {
        busy = false
        phase = .ready
        bluetoothOn = BLEService.shared.isPoweredOn
    }
}

/// 设备页顶部常驻的链路条：信号条 + 三态 + 预热/重连 + RSSI 历史 + 阶梯。
struct LinkSenseBar: View {
    @Bindable var model: LinkSenseModel
    @State private var showHistory = false

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                HStack(alignment: .center, spacing: V.S.gapS) {
                    VStack(alignment: .leading, spacing: V.S.gapXXS) {
                        Text("连接感知")
                            .font(V.F.chipLabel)
                            .foregroundStyle(V.C.text4)
                        HStack(spacing: V.S.gapS) {
                            stateDot
                            Text(model.phase.rawValue)
                                .font(V.F.cardTitle)
                                .foregroundStyle(V.C.text1)
                            if let ms = model.connectMs {
                                Text("\(ms)ms · \(model.connectSource)")
                                    .font(V.F.micro).foregroundStyle(V.C.text3)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: V.S.gapXXS) {
                        RSSIBars(level: model.rssiLevel)
                        Text(model.lastRSSI.map { "\($0) dBm · \(model.rssiWord)" } ?? "RSSI 未测")
                            .font(V.F.micro)
                            .foregroundStyle(V.C.text3)
                            .monospacedDigit()
                    }
                }
                if !model.bluetoothOn {
                    HStack(spacing: V.S.gapS) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(V.F.rowDetailStrong)
                            .foregroundStyle(V.C.pink)
                            .accessibilityHidden(true)
                        Text("蓝牙已关闭 —— 打开系统蓝牙后门锁才能被唤醒。")
                            .font(V.F.footnote).foregroundStyle(V.C.text1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(V.S.gapS)
                    .background(V.C.pink.opacity(0.12), in: .rect(cornerRadius: V.R.action, style: .continuous))
                }
                HStack(spacing: V.S.gapS) {
                    Button {
                        Task { await model.preheat() }
                    } label: {
                        VTag(text: model.busy ? "预热中…" : "预热", tint: V.C.blue, filled: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.busy)
                    Button {
                        Task { await model.reconnect() }
                    } label: {
                        VTag(text: "重连 · \(Int(model.nextLadder))s", tint: V.C.text1)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.busy)
                    Button {
                        model.readRSSI()
                        showHistory.toggle()
                    } label: {
                        VTag(text: "信号", tint: V.C.text1)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }
                if showHistory {
                    VStack(alignment: .leading, spacing: V.S.gapXS) {
                        VRowDivider()
                        Text("RSSI 历史（最近 24 个采样）")
                            .font(V.F.chipLabel).foregroundStyle(V.C.text4)
                        if model.history.isEmpty {
                            Text("还没有采样 —— 预热或点「信号」读一次。")
                                .font(V.F.footnote).foregroundStyle(V.C.text3)
                        } else {
                            HStack(alignment: .bottom, spacing: V.S.gapXXS) {
                                ForEach(Array(model.history.enumerated()), id: \.offset) { pair in
                                    let h = CGFloat(max(1, min(24, 24 - (pair.element + 100) / 2)))
                                    RoundedRectangle(cornerRadius: V.S.hair, style: .continuous)
                                        .fill(V.C.blue.opacity(0.7))
                                        .frame(width: V.S.gapS, height: h)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text("每格 = 一次采样；越高越接近满格信号。")
                                .font(V.F.micro).foregroundStyle(V.C.text3)
                        }
                        Text("重连阶梯：5 / 15 / 30 / 60 / 90 秒 —— 当前第 \(model.attempt + 1) 档。")
                            .font(V.F.micro).foregroundStyle(V.C.text3)
                    }
                } else {
                    Text(model.lastEvent)
                        .font(V.F.micro).foregroundStyle(V.C.text3)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private var stateDot: some View {
        Circle()
            .fill(stateColor)
            .frame(width: V.List.dotSize, height: V.List.dotSize)
            .accessibilityHidden(true)
    }

    private var stateColor: Color {
        switch model.phase {
        case .ready: return V.C.rewardGreen
        case .connecting: return V.C.coral
        case .noKey: return V.C.coral
        case .down: return V.C.text3
        }
    }
}

/// 四格信号条：形状 + 档位文字双通道（色觉障碍也能读）。
struct RSSIBars: View {
    let level: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: V.S.gapXXS) {
            ForEach(0 ..< 4, id: \.self) { index in
                RoundedRectangle(cornerRadius: V.S.hair, style: .continuous)
                    .fill(index < level ? V.C.blue : V.C.grid)
                    .frame(width: V.S.gapS, height: V.S.gapS + CGFloat(index) * V.S.gapXS)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("信号" + LinkSenseModel.levelWord(level))
    }
}
