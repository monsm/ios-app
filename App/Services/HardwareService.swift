// 蓝牙钥匙串 (ZKBBV1 pid=16289) 与智能网关 (FE90) 服务 — JS services/{keychain,gateway}.js 移植
// 两者共用 BLE 单连接 (与 App 同一 BleLockConnector 通道): 切换目标时自动断旧连
import Foundation
import Combine

@MainActor
final class HardwareService: ObservableObject {
    static let shared = HardwareService()
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
        // 与 LockService 同口径脱敏: 帧 hex 内含 ekey / 网关 WiFi SSID+口令明文, 不得进任何可复制的日志数组
        // 2026-10-27 审核恢复：网关 SSID/口令也在帧里，同款脱敏。
        let shown = msg.contains("hex=") ? FrameRedact.apply(msg) : msg
        logs.append("\(t) \(shown)")
        if logs.count > 60 { logs.removeFirst(logs.count - 60) }
    }

    // ---------- 通用: 连到目标并执行一条命令 ----------
    private func connectTarget(_ mac: String, timeoutMs: Int = 20000) async throws {
        if ble.connectedPeripheralId == connectedTargetId, !connectedTargetId.isEmpty { return }
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
        // 2026-10-27 审核修复 (AUDIT-D D-45)：连接成立后**复核设备身份**。
        // 门锁那条路 (LockService.ensureConnected:97-121) 早就修过这个洞，而钥匙串/网关这条没修 ——
        // 后果：伪造一份含目标 MAC 的广播并暴露 6E400001 服务，App 就会连到他，
        // 之后把 ekey 与家里 WiFi 口令发过去。
        // 复核口径与门锁一致：读一次状态帧，用**设备自己的响应**对 pid（响应比广播难伪造得多）。
        do {
            let remotePid = try await readStatusFrame()
            let knownPid = pidFor(mac) ?? 0
            if knownPid > 0, remotePid > 0, remotePid != knownPid {
                ble.disconnect()
                connectedTargetId = ""
                log("连接后身份不符: 设备 pid=\(remotePid) 与登记的 \(knownPid) 不一致 → 已断开")
                throw BLEErrorX.msg("连到的设备与目标不是同一个 (pid 不符)，已断开。附近可能有伪造广播。")
            }
            if knownPid <= 0 { log("未登记 pid, 跳过连接后身份复核 (老记录)") }
        } catch let e as BLEErrorX {
            throw e
        } catch {
            ble.disconnect()
            connectedTargetId = ""
            log("连接后读状态失败 (\(error.localizedDescription)) → 断开")
            throw BLEErrorX.msg("连上后读不到设备状态，已断开重来")
        }
    }
    /// 读一次设备状态帧（cmd03），用于连接后的身份复核。
    /// 2026-10-27 审核新增 (AUDIT-D D-45)：与 LockService 的 `getStatus` 同口径 ——
    /// 用设备自己的响应去对 pid，而不是只信广播里的字段（广播谁都能伪造）。
    private func readStatusFrame() async throws -> Int {
        let target = connectedTargetId
        guard !target.isEmpty else { throw BLEErrorX.msg("内部错误: 复核时没有连接目标") }
        let f = try await send(ZKCmdBuilder.cmd03StatusPlain(), target: target, timeoutMs: 8000)
        return StatusParser.parseStatus(f.klvs).pid
    }

    private func dongleRecord(_ mac: String) -> Dongle? { DB.dongle(mac) }
    private func gatewayRecord(_ mac: String) -> Gateway? { DB.gateway(mac) }
    private func pidFor(_ mac: String) -> Int? {
        if dongleRecord(mac) != nil { return PidMap.ZKBBV1 }  // 钥匙串当前型号恒为 ZKBBV1 (原两分支同值)
        // 网关: 旧记录从未落 pid (见 provisionGateway 的对拍勘误), pid=0 时按 GW 家族首项回落,
        // 否则 scanForPID(pid: 0) 永远匹配不到广播 ⇒ 缓存 deviceId 失效后网关全部操作 20s 超时。
        if let g = gatewayRecord(mac) { return g.pid > 0 ? g.pid : PidMap.GW }
        return nil
    }

    /// 按**型号族**扫描 (网关有 GW / GW_commercial / GW2_commercial 三个 pid)。
    /// 原 APK gateway.js 的扫描就是 GW_PIDS 全族匹配, 只认 12193 会让另外两种网关永远搜不到。
    private func scanForPIDs(pids: [Int], resetRequired: Bool, timeoutMs: Int) async throws -> String {
        guard !pids.isEmpty else {
            throw BLEErrorX.msg("台账缺少该设备的型号 (pid), 拒绝按广播盲连 — 请先在 App 内连接门锁刷新档案")
        }
        try await ble.startScan(timeoutMs: timeoutMs)
        defer { ble.stopScan() }
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        while Date() < deadline {
            for d in ble.allDiscovered() {
                guard let a = ZKProtocol.parseAdv(d.advertisHex) else { continue }
                if !pids.contains(a.pid) { continue }
                if resetRequired && a.resetStatus == 0 { continue }
                ble.stopScan()
                return d.deviceId
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        throw BLEErrorX.code(.notFound)
    }

    private func scanForPID(pid: Int?, resetRequired: Bool, timeoutMs: Int) async throws -> String {
        // 旧实现在 pid==nil 时跳过型号与 MAC 校验, 直接返回**第一个**可解析广播的设备并连接
        // → cmd41 把 ekey 写进陌生人设备、cmd31 把家里 WiFi SSID+口令写进陌生网关。
        // JS 权威强制 macFilter/macRaw (gateway.js:62, keychain.js:69) — 无型号即拒绝。
        guard let pid else {
            throw BLEErrorX.msg("台账缺少该设备的型号 (pid), 拒绝按广播盲连 — 请先在 App 内连接门锁刷新档案")
        }
        return try await scanForPIDs(pids: [pid], resetRequired: resetRequired, timeoutMs: timeoutMs)
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
        // 忙判必须在写之前 (与 LockService.request 同款修复, 2026-10-14): 旧判据在 Task 内,
        // 而 writeFrameHex 在 Task 外无条件执行 => 判忙时帧仍被发出 -> 错帧。
        if waiter != nil { throw BLEErrorX.msg("已有命令在等待响应") }
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
    /// cmd 43 状态 (响应解析: 11/24/25 直读, 12/31/34/35 反转; 基线另有 36 逐字节的 applyPids，
    /// 本工程不解析也没有任何消费点 —— 理由与钉子见 parseshadow 打印的「口径差」与 docs/AUDIT-CODE.md §10.48)
    func readDongleState(mac: String) async throws -> DongleStat {
        let f = try await send(ZKCmdBuilder.cmd43KeychainStatus([]), target: mac)
        // 钥匙串返回码在 KLV#03 (vendor keychain.js 的 parseKCStatus 同一口径)。原先这里从不看 rc:
        // rc=1(解密失败)/rc=3(不在有效期) 那种回字里根本没有 11/24/25/31 这些读数，
        // parseKCStatus 于是全部给默认值，而这一份"全没读到"会被**当成一次真实读数覆盖上一次的好数据**，
        // 还会把 lastSeenAt 写成刚刚见过 —— 界面上是"钥匙串刚联系过，只是各项都是空"。
        // rc = -1 表示帧里没带返回码 (基线同样不判)，所以只在 rc 明确非 0 时才中止。
        let rc = rcOf(f)
        if rc > 0 {
            if rc == 3 { throw BLEErrorX.msg("命令不在有效期，请将手机时间同步到锁内") }
            throw BLEErrorX.msg("钥匙串返回失败码 " + StatusParser.rcMessage(rc) + "，本次读数未采纳 (上一次的好数据仍留着)")
        }
        let st = HardwareService.parseKCStatus(f.klvs)
        var rec = DB.dongle(mac) ?? Dongle(mac: mac)
        rec.stat = st
        rec.lastSeenAt = ISO8601DateFormatter().string(from: Date())
        DB.saveDongle(rec)
        log("状态: 电量 \(st.power), 钥匙 \(st.ekeyCount)/\(st.ekeyAmount), 固件 \(st.firmware)")
        return st
    }
    nonisolated static func parseKCStatus(_ klvs: [ZKLV]) -> DongleStat {
        var s = DongleStat()
        func direct(_ key: Int) -> Int? { klvs.first(where: { $0.key == key }).map { StatusParser.intHex($0.val) } }
        // KLV#03 (返回码) 不在这里落：DongleStat 没有 rc 字段，判 rc 的是调用方 readDongleState (走 rcOf)。
        // 原先这一行写的是 `if let v = direct(0x03) { _ = v }` —— 把值取出来再丢掉，
        // 看上去像"这里处理过返回码了"，实际什么都没做，而调用方也确实没看过 rc。
        s.power = direct(0x11) ?? -1
        s.absPower = klvs.first(where: { $0.key == 0x12 }).map { Int(StatusParser.leHexToU32($0.val)) } ?? -1
        s.ekeyCount = direct(0x24) ?? -1
        s.ekeyAmount = direct(0x25) ?? -1
        s.firmware = klvs.first(where: { $0.key == 0x31 }).map { HardwareService.dotted3($0.val) } ?? ""
        s.pid = klvs.first(where: { $0.key == 0x34 }).map { Int(StatusParser.leHexToU32($0.val)) } ?? 0
        s.eCtrl = klvs.first(where: { $0.key == 0x35 }).map { HardwareService.dotted3($0.val) } ?? ""
        return s
    }
    /// 3B 反转点分，**不是整 3 字节就回空**（对齐基线 keychain.js 的 0x31/0x35：只在 reversed 长度==6 时赋值，
    /// 否则保持默认 ''）。原先这里直接把 `dotted(...)` 的结果写进去，而 `dotted` 对不是 6 位的输入
    /// **原样返回那段十六进制** ⇒ 一次长度不对的读数会在界面上显示成一个假版本号，还会被写进备份包。
    nonisolated static func dotted3(_ hex: String) -> String {
        let r = HexKit.reversePairs(hex)
        return r.count == 6 ? dotted(r) : ""
    }
    nonisolated static func dotted(_ hex: String) -> String {
        guard hex.count == 6 else { return hex }
        func v(_ off: Int) -> Int { Int(hex.dropFirst(off).prefix(2), radix: 16) ?? 0 }
        return "\(v(4)).\(v(2)).\(v(0))"
    }
    /// cmd 41 写钥 (ekey = AES(skey)($t 包络); 空串 = 删除该锁钥匙)
    func writeDongleKey(dongleMac: String, lock: Keychain, trackId: UInt32) async throws {
        // protoSecU32: 东八区下 '2010-01-01 00:00:00' 原为 −28800, 直接 truncatingIfNeeded 会回绕成
        // 4294938496 (≈2146) ⇒ 写进硬件钥匙的凭证窗口永远不生效 (同 0A/14 的真机勘误)
        let vf = ZKCmdBuilder.protoSecU32("2010-01-01 00:00:00")
        let vt = ZKCmdBuilder.protoSecU32("2118-01-01 00:00:00")
        // 旧写法 `lock.pins.first ?? "1"`: PIN 池为空时**回落到 PIN "1"** 去签发硬件钥匙凭证 ——
        // 写进dongle 的是一条人人猜得到的凭证, 而流程显示"写入成功"。缺 PIN 必须直接拒绝。
        guard let pin = lock.pins.first, !pin.isEmpty else {
            throw BLEErrorX.msg("该锁的钥匙串没有 PIN 池, 无法为硬件钥匙签发凭证 (已拒绝, 不回落默认 PIN)")
        }
        let ekey = ZKCmdBuilder.buildEkeyOpen(lock.skey.lowercased(), lock.mac.lowercased(), pin,
                                             validFromSec: vf, validToSec: vt, trackId: trackId)
        // 签发失败 (skey 非法 / PIN 不可解析) 返回空串: 空 ekey 不能发给硬件钥匙
        guard !ekey.isEmpty else {
            throw BLEErrorX.msg("ekey 签发失败 (skey 非法或 PIN 不可解析), 已中止写入硬件钥匙")
        }
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
        // 返回码在 KLV#03；基线 keychain.js:176 写明"无 rc KLV (如 44/43 无状态位) — 调用层自行决定" ⇒
        // 只在明确非 0 时拒绝，帧里没带 (-1) 照常按读数处理。
        // 原先这里直接看 KLV#04：一次 rc=1(解密失败) 的回字里没有 04，于是返回空列表，
        // 界面弹的就是"没有查询到钥匙"——把一次失败说成一把钥匙都没有（与 §10.48 的 43 同一族）。
        let rc = rcOf(f)
        if rc > 0 { throw BLEErrorX.msg("查钥匙失败: " + StatusParser.rcMessage(rc) + " (这不代表硬件狗里没有钥匙)") }
        // 2026-10-26: 原先这里有一份**与 parseEkeyMacs 逐字相同**的内联解析（两份真相）。
        // 现在只保留 parseEkeyMacs 一份，这里直接调它 —— 改一处就够，不会一处改了一处没改。
        return Self.parseEkeyMacs(f.klvs)
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
            case 0x02: // 与 0x03 同式：整 3 字节才点分，否则按 ASCII 解（基线 gateway.js 两支都有 ASCII 回退；
                       // 原先这里少了那一半回退，长度不对时会把反转后的十六进制直接当版本号显示）
                let rev2 = HexKit.reversePairs(k.val)
                s.romVer = (rev2.count == 6) ? dotted(rev2) : HexKit.hexToAscii(k.val)
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
        let deviceId = try await scanForPIDs(pids: PidMap.gws, resetRequired: true, timeoutMs: 15000)
        try await ble.connect(deviceId: deviceId)
        connectedTargetId = deviceId   // 否则后续 readGatewayState→connectTarget 会自断重连,
                                       // 且台账未落盘 pidFor=nil → scanForPID 匹配任意广播设备
        // 读取广播 MAC → 台账键; 顺带把 pid 落库 (2026-10-17 对拍勘误: 旧写法只写 bleId/boundAt,
        // pid 恒为 Gateway.pid 默认值 0 ⇒ 缓存 deviceId 失效后 pidFor 返回 0, scanForPID 永不命中,
        // 网关的刷新状态/重启/重新配网全部 20s 超时失败)。
        var mac = ""
        var advPid = 0
        for d in ble.allDiscovered() {
            if d.deviceId == deviceId, let a = ZKProtocol.parseAdv(d.advertisHex) {
                if let m = a.macRaw { mac = m }
                advPid = a.pid
                break
            }
        }
        if mac.isEmpty { mac = deviceId } // 兜底: 以 deviceId 为键
        var rec = DB.gateway(mac) ?? Gateway(mac: mac)
        rec.bleId = deviceId
        if rec.pid <= 0 { rec.pid = advPid > 0 ? advPid : PidMap.GW }
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
    // 网关应答码: 缺 KLV#01 → 0 (App Co/So/Mo 构造器默认)。
    // ⚠ 只能用在**写类命令**的回字上 (31 写 WiFi / 35 重启)。cmd 38 状态帧里 KLV#01 是 wifimac，
    //   拿它当应答码读会把 MAC 的第一个字节当成错误码 —— 两套码制 (写:KLV#01 / 钥匙串:KLV#03) 不能混用。
    private func errCodeOf(_ f: ZKProtocol.ParsedFrame) -> Int {
        guard let k = f.klvs.first(where: { $0.key == 0x01 }) else { return 0 }
        return StatusParser.intHex(k.val)
    }
}