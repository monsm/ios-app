// LinkSense.swift —— 连接感知（预热 / 重连阶梯 / RSSI 历史 / 信号条）。
//
// 来源：原 App/Core/LinkSenseKit.swift + LinkSenseReconnect.swift + LinkSenseViews.swift
//   （LinkSense 预热/回连节律、RSSI 四格信号条、蓝牙未开横幅）。
// 本文件只提供 LinkSenseModel：连接相位、最近 RSSI、握手耗时与 5/15/30/60/90 秒重连阶梯。
//   门页 V8 的「连接」卡直接消费它；「预热」只建立到就绪态，绝不下发开锁或凭证（96 铁律）。
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

    /// 重连阶梯：5 / 15 / 30 / 60 / 90 秒 —— 每按一次「重连」进一档。
    static let ladder: [Double] = [5, 15, 30, 60, 90]

    var phase: Phase = .down
    var lastRSSI: Int?
    /// RSSI 历史保留条数 —— 标题与裁剪共用这一个数。
    static let rssiHistoryCap = 24

    var history: [Int] = []
    var connectMs: Int?
    var connectSource = "预热"
    var attempt = 0
    var busy = false
    var lastEvent = "进页会自动预热一次，只建立连接，不开锁。"
    var bluetoothOn = BLEService.shared.isPoweredOn

    /// 当前链路对应的锁 MAC。`private(set)` 而不是 `private`：`Reading.signal(mac)`
    /// 需要它（信号口径的唯一出口），视图不能自己再拼 dBm。
    private(set) var mac = ""

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
            // 2026-11-03（整页截图实测）：这里原来把**裸错误串**直接甩到门页正文
            // （真机截图上是「预热失败：此设备不支持所需的蓝牙功能」）——
            // 而 LockServiceLink 的注释写明「预热失败不该打扰用户」。两处口径相反。
            // 预热只是"提前把链路准备好"，失败不影响手动开锁：说清后果 + 给出下一步即可，
            // 具体原因留在诊断页（God 模式 / 硬件页）看。
            lastEvent = "预连接没成功 —— 不影响手动开锁。下拉刷新或点「重连」可以再试。"
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
        // 2026-11-04（历史遗留数字）：标题写「最近 24 个采样」，这里也是 24 —— 但两处各写一遍，
        // 改一处另一处就漂。收到一个常量里。
        if history.count > Self.rssiHistoryCap { history.removeFirst(history.count - Self.rssiHistoryCap) }
        DB.store.set("kf_linkrssi_" + mac, value)
        DB.store.set("kf_rssi_hist_" + mac, history)
    }

    private func markReady() {
        busy = false
        phase = .ready
        bluetoothOn = BLEService.shared.isPoweredOn
    }
}

