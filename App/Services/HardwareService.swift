// 蓝牙钥匙串 (ZKBBV1 pid=16289) 与智能网关 (FE90) 服务 — JS services/{keychain,gateway}.js 移植
// 两者共用 BLE 单连接 (与 App 同一 BleLockConnector 通道): 切换目标时自动断旧连
import Foundation
import Combine

@MainActor
final class HardwareService: ObservableObject {
    static let shared = HardwareService()
    @Published private(set) var dongleState: DongleStat?
    @Published private(set) var gatewayState: GatewayState?
    @Published private(set) var busy = false
    @Published var logs: [String] = []

    private let ble = BLEService.shared
    struct Waiter {
        var cmd: UInt8
        var cont: CheckedContinuation<ZKProtocol.ParsedFrame, Error>
        var timer: DispatchWorkItem?
    }
    private var waiter: Waiter?
    private var connectedTargetId: String = "" // BLE deviceId — 连接复用判定

    struct GatewayState {
        var wifimac: String = ""
        var romVer: String = ""
        var eCtrlVer: String = ""
        var ssid: String = ""
        var wifiIP: String = ""
        var netState: Int = -1
    }

    init() {
        ble.onFrame { [weak self] frame in
            Task { @MainActor in
                guard let self, let w = self.waiter, frame.cmd == w.cmd else { return }
                self.waiter = nil
                w.cont.resume(returning: frame)
            }
        }
        ble.bootstrap()
    }
    var debugRaw: Bool { DB.store.getBool("kf_debug_raw") }
    func log(_ msg: String) {
        let t = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.append("\(t) \(msg)")
        if logs.count > 60 { logs.removeFirst(logs.count - 60) }
    }

    // ---------- 通用: 连到目标并执行一条命令 ----------
    private func connectTarget(_ mac: String, timeoutMs: Int = 20000) async throws {
        if ble.connectedMAC == connectedTargetId, !connectedTargetId.isEmpty { return }
        ble.disconnect()
        let cachedId: String? = dongleRecord(mac)?.bleId ?? gatewayRecord(mac)?.bleId
        if let cachedId, !cachedId.isEmpty {
            do {
                try await ble.connect(deviceId: cachedId, timeoutMs: timeoutMs)
                connectedTargetId = cachedId
                return
            } catch {
                log("缓存 deviceId 直连失败 (\(error.localizedDescription)), 回退扫描")
            }
        }
        let deviceId = try await scanForPID(pid: pidFor(mac), resetRequired: false, timeoutMs: timeoutMs)
        try await ble.connect(deviceId: deviceId, timeoutMs: timeoutMs)
        connectedTargetId = deviceId
    }
    private func dongleRecord(_ mac: String) -> Dongle? { DB.dongle(mac) }
    private func gatewayRecord(_ mac: String) -> Gateway? { DB.gateway(mac) }
    private func pidFor(_ mac: String) -> Int? {
        if dongleRecord(mac) != nil { return PidMap.ZKBBV1 }  // 钥匙串当前型号恒为 ZKBBV1 (原两分支同值)
        if let g = gatewayRecord(mac) { return g.pid }
        return nil
    }

    private func scanForPID(pid: Int?, resetRequired: Bool, timeoutMs: Int) async throws -> String {
        try await ble.startScan(timeoutMs: timeoutMs)
        defer { ble.stopScan() }
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        while Date() < deadline {
            for d in ble.allDiscovered() {
                guard let a = ZKProtocol.parseAdv(d.advertisHex) else { continue }
                if let pid, a.pid != pid { continue }
                if resetRequired && a.resetStatus == 0 { continue }
                ble.stopScan()
                return d.deviceId
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        throw BLEErrorX.code(.notFound)
    }

    // 扫描并登记新硬件 (页面「搜索」动作)
    func scanForDongle() async throws -> Dongle {
        try await ble.startScan(timeoutMs: 15000)
        defer { ble.stopScan() }
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            for d in ble.allDiscovered() {
                guard let a = ZKProtocol.parseAdv(d.advertisHex), a.pid == PidMap.ZKBBV1, let mac = a.macRaw else { continue }
                var rec = DB.dongle(mac) ?? Dongle(mac: mac)
                rec.bleId = d.deviceId
                if rec.boundAt.isEmpty { rec.boundAt = ISO8601DateFormatter().string(from: Date()) }
                if d.name != "(未命名)" { rec.name = d.name }
                DB.saveDongle(rec)
                log("找到钥匙串: \(a.macDisplay ?? mac) (\(d.name))")
                return rec
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        throw BLEErrorX.msg("搜索设备超时")
    }

    private func send(_ cmdObj: ZKCmd, target: String, timeoutMs: Int = 8000) async throws -> ZKProtocol.ParsedFrame {
        try await connectTarget(target)
        let task = Task<ZKProtocol.ParsedFrame, Error> { @MainActor in
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ZKProtocol.ParsedFrame, Error>) in
                let timer = DispatchWorkItem {
                    guard let w = self.waiter, w.cmd == cmdObj.cmd else { return }
                    self.waiter = nil
                    w.cont.resume(throwing: BLEErrorX.code(.responseTimeout))
                }
                // 忙判 (与 LockService.request 同款): 覆盖会让旧 continuation 永不 resume,
                // 调用方 task.value 永久挂起、页面 busy 永转
                if self.waiter != nil {
                    cont.resume(throwing: BLEErrorX.msg("已有命令在等待响应"))
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(timeoutMs), execute: timer)
                self.waiter = Waiter(cmd: cmdObj.cmd, cont: cont, timer: timer)
            }
        }
        do {
            if debugRaw { log("TX hex=\(cmdObj.hex)") }
            try await ble.writeFrameHex(cmdObj.hex)
        } catch {
            if let w = waiter, w.cmd == cmdObj.cmd {
                w.timer?.cancel()
                waiter = nil
                w.cont.resume(throwing: error)
            }
            throw error
        }
        let frame = try await task.value
        if debugRaw { log("RX cmd=\(String(format: "%02x", frame.cmd)) hex=\(frame.raw)") }
        return frame
    }

    // ================= 钥匙串 (App addkeychain 页) =================
    /// cmd 43 状态 (响应解析: 11/24/25 直读, 12/31/34/35 反转, 36 逐字节)
    func readDongleState(mac: String) async throws -> DongleStat {
        let f = try await send(ZKCmdBuilder.cmd43KeychainStatus([]), target: mac)
        let st = HardwareService.parseKCStatus(f.klvs)
        var rec = DB.dongle(mac) ?? Dongle(mac: mac)
        rec.stat = st
        rec.lastSeenAt = ISO8601DateFormatter().string(from: Date())
        DB.saveDongle(rec)
        dongleState = st
        log("状态: 电量 \(st.power), 钥匙 \(st.ekeyCount)/\(st.ekeyAmount), 固件 \(st.firmware)")
        return st
    }
    nonisolated static func parseKCStatus(_ klvs: [ZKLV]) -> DongleStat {
        var s = DongleStat()
        func direct(_ key: Int) -> Int? { klvs.first(where: { $0.key == key }).map { StatusParser.intHex($0.val) } }
        if let v = direct(0x03) { _ = v } // rc
        s.power = direct(0x11) ?? -1
        s.absPower = klvs.first(where: { $0.key == 0x12 }).map { Int(StatusParser.leHexToU32($0.val)) } ?? -1
        s.ekeyCount = direct(0x24) ?? -1
        s.ekeyAmount = direct(0x25) ?? -1
        s.firmware = klvs.first(where: { $0.key == 0x31 }).map { HardwareService.dotted(HexKit.reversePairs($0.val)) } ?? ""
        s.pid = klvs.first(where: { $0.key == 0x34 }).map { Int(StatusParser.leHexToU32($0.val)) } ?? 0
        s.eCtrl = klvs.first(where: { $0.key == 0x35 }).map { HardwareService.dotted(HexKit.reversePairs($0.val)) } ?? ""
        return s
    }
    nonisolated static func dotted(_ hex: String) -> String {
        guard hex.count == 6 else { return hex }
        func v(_ off: Int) -> Int { Int(hex.dropFirst(off).prefix(2), radix: 16) ?? 0 }
        return "\(v(4)).\(v(2)).\(v(0))"
    }
    /// cmd 41 写钥 (ekey = AES(skey)($t 包络); 空串 = 删除该锁钥匙)
    func writeDongleKey(dongleMac: String, lock: Keychain, trackId: UInt32) async throws {
        let vf = UInt32(truncatingIfNeeded: ZKCmdBuilder.protoSec("2010-01-01 00:00:00"))
        let vt = UInt32(truncatingIfNeeded: ZKCmdBuilder.protoSec("2118-01-01 00:00:00"))
        let pin = lock.pins.first ?? "1"
        let ekey = ZKCmdBuilder.buildEkeyOpen(lock.skey.lowercased(), lock.mac.lowercased(), pin,
                                             validFromSec: vf, validToSec: vt, trackId: trackId)
        let f = try await send(ZKCmdBuilder.cmd41WriteEkey(lock.mac.lowercased(), lock.pid, ekey), target: dongleMac)
        let rc = rcOf(f)
        if rc != 0 {
            if rc == 3 { throw BLEErrorX.msg("命令不在有效期，请将手机时间同步到锁内") }
            throw BLEErrorX.msg(StatusParser.rcMessage(rc))
        }
        var rec = DB.dongle(dongleMac) ?? Dongle(mac: dongleMac)
        rec.lastKeyLock = lock.mac
        rec.lastKeyAt = ISO8601DateFormatter().string(from: Date())
        DB.saveDongle(rec)
    }
    func deleteDongleKey(dongleMac: String, lock: Keychain) async throws {
        let f = try await send(ZKCmdBuilder.cmd41WriteEkey(lock.mac.lowercased(), lock.pid, ""), target: dongleMac)
        let rc = rcOf(f)
        if rc != 0 { throw BLEErrorX.msg(StatusParser.rcMessage(rc)) }
    }
    /// cmd 44 查钥匙 (nil = 全部; lockMac = 本锁)
    func dongleKeys(dongleMac: String, lockMac: String?) async throws -> [String] {
        let f = try await send(ZKCmdBuilder.cmd44GetEkeyInfo(lockMac), target: dongleMac)
        guard let k = f.klvs.first(where: { $0.key == 0x04 }) else { return [] }
        let h = k.val
        var out = [String]()
        var i = h.startIndex
        while h.distance(from: i, to: h.endIndex) >= 12 {
            out.append(String(h[i..<h.index(i, offsetBy: 12)]).lowercased())
            i = h.index(i, offsetBy: 12)
        }
        return out
    }
    /// cmd 44 响应: KLV#04 = MAC 列表 (每 6B 一台)
    nonisolated static func parseEkeyMacs(_ klvs: [ZKLV]) -> [String] {
        guard let k = klvs.first(where: { $0.key == 0x04 }) else { return [] }
        let h = k.val
        var out = [String]()
        var i = h.startIndex
        while h.distance(from: i, to: h.endIndex) >= 12 {
            out.append(String(h[i..<h.index(i, offsetBy: 12)]).lowercased())
            i = h.index(i, offsetBy: 12)
        }
        return out
    }
    private func rcOf(_ f: ZKProtocol.ParsedFrame) -> Int {
        guard let k = f.klvs.first(where: { $0.key == 0x03 }) else { return -1 }
        return StatusParser.intHex(k.val)
    }

    // ================= 网关 (App 网关六页离线等价) =================
    /// cmd 38 状态 (App Oo.parseKlv: 01/04/05 双重反转即原始字节序 → ASCII)
    func readGatewayState(mac: String) async throws -> GatewayState {
        let f = try await send(ZKCmdBuilder.cmd38GWStatus(), target: mac)
        let st = HardwareService.parseGWStatus(f.klvs)
        gatewayState = st
        var rec = DB.gateway(mac) ?? Gateway(mac: mac)
        rec.wifimac = st.wifimac; rec.romVer = st.romVer; rec.eCtrlVer = st.eCtrlVer
        rec.ssid = st.ssid; rec.wifiIP = st.wifiIP; rec.netState = st.netState
        DB.saveGateway(rec)
        log("网关状态: rom \(st.romVer), ssid \(st.ssid), 联网 \(st.netState == 1 ? "是" : "否")")
        return st
    }
    nonisolated static func parseGWStatus(_ klvs: [ZKLV]) -> GatewayState {
        var s = GatewayState()
        for k in klvs {
            switch k.key {
            case 0x01: s.wifimac = k.val // 原始字节序 hex
            case 0x02: s.romVer = dotted(HexKit.reversePairs(k.val))
            case 0x03:
                let rev = HexKit.reversePairs(k.val)
                s.eCtrlVer = (rev.count == 6) ? dotted(rev) : HexKit.hexToAscii(k.val)
            case 0x04: s.ssid = HexKit.hexToAscii(k.val)
            case 0x05: s.wifiIP = HexKit.hexToAscii(k.val)
            case 0x06: s.netState = StatusParser.intHex(k.val)
            default: break
            }
        }
        return s
    }
    /// 网关配网全链 (App gwreset: 扫描 → 38 → 31 写 WiFi → 35 重启)
    func provisionGateway(ssid: String, password: String, progress: @escaping (String) -> Void) async throws -> Gateway {
        progress("步骤 1/5: 搜索网关 (请靠近网关, 橙色灯闪烁中)")
        let deviceId = try await scanForPID(pid: PidMap.GW, resetRequired: true, timeoutMs: 15000)
        try await ble.connect(deviceId: deviceId)
        connectedTargetId = deviceId   // 否则后续 readGatewayState→connectTarget 会自断重连,
                                       // 且台账未落盘 pidFor=nil → scanForPID 匹配任意广播设备
        // 读取广播 MAC → 台账键
        var mac = ""
        for d in ble.allDiscovered() {
            if d.deviceId == deviceId, let a = ZKProtocol.parseAdv(d.advertisHex), let m = a.macRaw { mac = m; break }
        }
        if mac.isEmpty { mac = deviceId } // 兜底: 以 deviceId 为键
        var rec = DB.gateway(mac) ?? Gateway(mac: mac)
        rec.bleId = deviceId
        if rec.boundAt.isEmpty { rec.boundAt = ISO8601DateFormatter().string(from: Date()) }

        progress("步骤 2/5: 读取网关信息 (cmd 38)")
        let st = try await readGatewayState(mac: mac)
        progress("步骤 3/5: 写入 WiFi 配置 (cmd 31)")
        let wf = try await send(ZKCmdBuilder.cmd31GWSetWifi(ssid, password), target: mac, timeoutMs: 10000)
        let ec = errCodeOf(wf)
        if ec != 0 { throw BLEErrorX.msg("WiFi 配置失败 (errCode \(ec))") }
        progress("步骤 4/5: 重启网关使其生效 (cmd 35)")
        let rb = try await send(ZKCmdBuilder.cmd35GWReboot(), target: mac)
        let ec2 = errCodeOf(rb)
        if ec2 != 0 { log("重启指令返回 errCode \(ec2) (网关可能已自行重启)") }
        rec.lastWifi = ssid
        rec.provisionedAt = ISO8601DateFormatter().string(from: Date())
        rec.ssid = st.ssid
        DB.saveGateway(rec)
        ble.disconnect()
        progress("添加成功! 网关正在用新 WiFi 重连")
        return rec
    }
    func rebootGateway(mac: String) async throws {
        let rb = try await send(ZKCmdBuilder.cmd35GWReboot(), target: mac)
        let ec = errCodeOf(rb)
        if ec != 0 { throw BLEErrorX.msg("重启失败 (errCode \(ec))") }
        ble.disconnect()
    }
    // 网关应答码: 缺 KLV#01 → 0 (App Co/So/Mo 构造器默认)
    private func errCodeOf(_ f: ZKProtocol.ParsedFrame) -> Int {
        guard let k = f.klvs.first(where: { $0.key == 0x01 }) else { return 0 }
        return StatusParser.intHex(k.val)
    }
}