// LinkSense.swift —— 连接感知（RSSI 四档 / 预热 / 回连阶梯）。
//
// 它同时是 Engine/Reading.swift 的信号口径出口：Reading 只认这个类型上的三个静态函数。
import SwiftUI

@MainActor
@Observable
final class LinkSenseModel {
    static let shared = LinkSenseModel()

    enum Phase: String {
        case ready = "已连接"
        case connecting = "握手中"
        case down = "未连接"
        case noKey = "未绑定"
    }

    static let ladder: [Double] = [5, 15, 30, 60, 90]
    static let rssiHistoryCap = 24

    var phase: Phase = .down
    var lastRSSI: Int?
    var history: [Int] = []
    var connectMs: Int?
    var attempt = 0
    var busy = false
    var bluetoothOn = BLEService.shared.isPoweredOn
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

    func preheat() async {
        guard !mac.isEmpty, !busy else { return }
        busy = true
        phase = .connecting
        defer { busy = false; phase = resolvePhase() }
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
            if let rssi = hit?.rssi { record(rssi) }
            let t0 = Date()
            try await LockService.shared.ensureConnected(mac: mac)
            connectMs = Int(Date().timeIntervalSince(t0) * 1000)
            attempt = 0
            phase = .ready
        } catch {
            BLEService.shared.stopScan()
            attempt += 1
        }
    }

    func reconnect() async {
        guard !mac.isEmpty, !busy else { return }
        busy = true
        phase = .connecting
        defer { busy = false; phase = resolvePhase() }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            attempt = 0
            phase = .ready
        } catch {
            attempt = min(attempt + 1, LinkSenseModel.ladder.count)
        }
    }

    func readRSSI() {
        guard !mac.isEmpty else { return }
        BLEService.shared.readLinkRSSI { value in
            guard let value else { return }
            Task { @MainActor in LinkSenseModel.shared.record(value) }
        }
    }

    func record(_ value: Int) {
        lastRSSI = value
        history.append(value)
        if history.count > Self.rssiHistoryCap {
            history.removeFirst(history.count - Self.rssiHistoryCap)
        }
        DB.store.set("kf_linkrssi_" + mac, value)
        DB.store.set("kf_rssi_hist_" + mac, history)
    }
}
