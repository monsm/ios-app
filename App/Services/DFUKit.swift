// Nordic DFU 传输层（Secure DFU + Legacy DFU）—— 补齐 iOS 侧被整体删除的升级链。
//
// 为什么必须自己写而不是引第三方库：本仓是**零外部依赖**的纯原生工程（README 明写"全原生 SwiftUI"、
// CI 只跑 xcodebuild），引入 NordicDFU 会把一个 SPM 依赖塞进只有 88 个文件的仓库，得不偿失。
//
// 协议要点（对齐 jzzns22561_out/sources/com/plugin/urlcsDfuPlugin 与 Nordic 官方 DFU 规范）：
//   · Secure DFU：服务 0xFE59，控制点 8EC90001、数据点 8EC90002，按钮特征 8EC90003（无响应的旧固件用）
//   · Legacy DFU：服务 0x1530，控制点 1531、数据点 1532
//   · 状态码：0 连接中 / 1 进程启动 / 2 切 DFU / 4 校验 / 5 断开中 / 6 完成 / 7 中止，-1 = 有事件无独立码
//     （与 APK 的 URLCSDfuPlugin 把 11 个回调压成这 8 个码完全同构）
//   · Secure DFU 的对象模型：先写 PRN(包计数) → 创建对象(命令 1) → 流式写数据(Create Object 后按 MTU 分批)
//     → 校验(命令 2 CRC) → 执行(命令 4)。Legacy 是 start(1) → init packet → 数据 → validate。
//
// 本文件只做**传输与状态机**，固件包解析在 ZipKit/FirmwareKit，UI 在 DFUView。
// 刻意不假装能做的：不校验固件签名（锁端没有公钥），所以 UI 上必须显示"未认证固件"。
import Foundation
import CoreBluetooth

/// DFU 状态码 —— 数值与 APK 插件的 state 一一对应，便于两边对日志。
enum DFUState: Int {
    case connecting = 0
    case processStarting = 1
    case enablingDfu = 2
    case validating = 4
    case disconnecting = 5
    case completed = 6
    case aborted = 7
    case eventOnly = -1      // 有事件但无独立码（Connected / ProcessStarted / Disconnected）

    var text: String {
        switch self {
        case .connecting: return "正在连接 DFU 设备"
        case .processStarting: return "升级进程启动"
        case .enablingDfu: return "正在切换到 DFU 模式"
        case .validating: return "正在校验固件"
        case .disconnecting: return "正在断开"
        case .completed: return "升级完成"
        case .aborted: return "升级已中止"
        case .eventOnly: return "连接事件"
        }
    }
}

enum DFUTransportError: LocalizedError {
    case ble(String)
    case protocolError(String)

    var errorDescription: String? {
        switch self {
        case .ble(let s): return s
        case .protocolError(let s): return "DFU 协议错误：\(s)"
        }
    }
}

/// DFU 目标（Secure / Legacy 二选一，由服务发现决定）
enum DFUMode {
    case secure      // 0xFE59
    case legacy      // 0x1530

    var service: CBUUID {
        switch self {
        case .secure: return BLEUUID.svcDfuSecure
        case .legacy: return BLEUUID.svcDfuLegacy
        }
    }
    var controlPoint: CBUUID {
        switch self {
        case .secure: return BLEUUID.dfuSecureControl
        case .legacy: return BLEUUID.dfuLegacyControl
        }
    }
    var packetPoint: CBUUID {
        switch self {
        case .secure: return BLEUUID.dfuSecurePacket
        case .legacy: return BLEUUID.dfuLegacyPacket
        }
    }
}

/// Nordic DFU 会话。一个实例只服务一次升级；失败即作废（与 APK 一致，不自动重试）。
///
/// 使用方式（DFUView 里）：
///   1. `let session = DFUSession(...)` 2. `try await session.run()` 3. 看 `onState` / `onProgress`
// 2026-10-26: 本类要同时满足 CBCentralManagerDelegate / CBPeripheralDelegate 两个**非隔离**协议，
// 标 @MainActor 会让这两个 conformance 报 "crosses into main actor-isolated code"。
// 而它的全部状态只在该一个线程上访问（CBCentralManager 用 .main 队列构造，delegate 回调也在主线程），
// 所以用 @unchecked Sendable 如实声明，而不是硬套 @MainActor。
final class DFUSession: NSObject, @unchecked Sendable {
    /// 状态回调（主线程）
    var onState: ((DFUState, String) -> Void)?
    /// 进度回调 0…1
    var onProgress: ((Double) -> Void)?

    private let central: CBCentralManager
    private let macHex: String            // 目标锁 MAC（DFU 广播名是 ZkDFU + MAC 后 8 位）
    private let pkg: FirmwarePackage
    private var peripheral: CBPeripheral?
    private var mode: DFUMode?
    private var controlChar: CBCharacteristic?
    private var packetChar: CBCharacteristic?
    private var mtu = 20                  // 默认 20B；协商后更新
    private var prn = 0                   // Packet Receipt Notification 计数（0 = 不等待）
    private var sentSinceAck = 0
    private var waiters: [CheckedContinuation<Void, Error>] = []
    private var finished = false

    /// 目标锁的 pid —— APK 的 BleDfu 用它做广播过滤（pid 相同才算同一把锁的 DFU 态）。
    private let targetPid: Int

    init(macHex: String, pid: Int = 0, pkg: FirmwarePackage) {
        self.targetPid = pid
        self.macHex = macHex.replacingOccurrences(of: ":", with: "").lowercased()
        self.pkg = pkg
        self.central = CBCentralManager(delegate: nil, queue: nil)
        super.init()
        central.delegate = self
    }

    /// 跑完整个升级。抛错即失败，成功返回时状态已推到 .completed。
    func run() async throws {
        emit(.connecting, "准备连接升级模式设备")
        try await scanForDFUDevice()
        guard let target = scannedPeripheral else {
            throw DFUTransportError.ble("扫描结束但没有可用设备")
        }
        peripheral = target
        target.delegate = self
        try await connect()
        try await discover()
        try await performTransfer()
        emit(.completed, "升级完成")
    }

    // MARK: - 扫描

    /// 扫描 DFU 设备：判据是「广播里的 pid 等于目标锁 pid」+「frameCtrl bit5 (dfuState) == 1」，
    /// **不是**靠广播名匹配。名字只作为附加兜底（少数固件在 DFU 态仍带 ZkDFU 前缀）。
    ///
    /// ## 并发注记（第 6 轮，终于找对根因）
    ///
    /// `CheckedContinuation<T, E>` 的 `resume(returning:)` **要求 T: Sendable**（Swift 6 的设计约束）。
    /// 而 `CBPeripheral` 不是 Sendable ⇒ `CheckedContinuation<CBPeripheral, _>` **根本不可能 resume**。
    /// 前五轮我一直在换「怎么把 CBPeripheral 传出去」（Result 容器 / 专用方法 / 原地 resume 续体），
    /// 但那些做法都改不了这个约束 —— 所以修一次报一次。
    ///
    /// 正解：**续体只携带 Void**，扫描到的 peripheral 存进类属性 `scannedPeripheral`
    /// （本类已声明 @unchecked Sendable，读写都在这一个线程上），调用方 await 完再从属性取。
    private func scanForDFUDevice() async throws {
        let wantPid = targetPid
        self.scanCont = nil
        self.scanDone = false
        self.scannedPeripheral = nil
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.scanCont = cont
            self.central.scanForPeripherals(withServices: nil,
                                           options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            // 10 秒窗口：与 APK BleDfu.doScan 的 handler.postDelayed(…, 10000) 同值
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.finishScan(found: nil)
            }
            self.scanHandler = { [weak self] p, adv in
                guard let self, !self.scanDone else { return }
                // ① 优先按 APK 判据：厂商段解析出 pid + dfuState
                if let mf = adv[CBAdvertisementDataManufacturerDataKey] as? Data {
                    let hex = HexKit.hex([UInt8](mf))
                    if let a = ZKProtocol.parseAdv(hex), a.dfuState == 1,
                       wantPid == 0 || a.pid == wantPid {
                        self.finishScan(found: p)
                        return
                    }
                }
                // ② 兜底：名字命中 ZkDFU（部分固件不带厂商段）
                let name = (adv[CBAdvertisementDataLocalNameKey] as? String)?.uppercased() ?? ""
                if name.contains("ZKDFU") { self.finishScan(found: p) }
            }
        }
    }

    private var scanCont: CheckedContinuation<Void, Error>?
    private var scanDone = false
    private var scannedPeripheral: CBPeripheral?
    private var scanHandler: ((CBPeripheral, [String: Any]) -> Void)?

    /// 收尾：记下 peripheral（或 nil）并 resume。续体只携带 Void，不违反 Sendable 约束。
    private func finishScan(found: CBPeripheral?) {
        guard !scanDone, let c = scanCont else { return }
        scanDone = true
        scanCont = nil
        scanHandler = nil
        central.stopScan()
        if let p = found {
            scannedPeripheral = p
            c.resume()
        } else {
            c.resume(throwing: DFUTransportError.ble(
                "10 秒内没发现升级模式设备。请确认门锁已通电、靠近手机，"
                + "且已下发 22 进 DFU（广播里 dfuState 位为 1）。"))
        }
    }


    // MARK: - 连接与发现

    /// 2026-10-26: 不再收 CBPeripheral 参数，直接读类属性 `peripheral`。
    /// （CBPeripheral 不是 Sendable，作为 async 函数参数传会被 Swift 6 判 sending risks data races。）
    private func connect() async throws {
        guard let p = peripheral else { throw DFUTransportError.ble("未选中升级设备") }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.connectCont = cont
            central.connect(p, options: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
                if self?.connectCont != nil {
                    self?.connectCont = nil
                    cont.resume(throwing: DFUTransportError.ble("连升级设备超时（20s）"))
                }
            }
        }
    }
    private var connectCont: CheckedContinuation<Void, Error>?

    private func discover() async throws {
        guard let p = peripheral else { throw DFUTransportError.ble("未连接") }
        emit(.enablingDfu, "发现 DFU 服务")
        p.discoverServices([DFUMode.secure.service, DFUMode.legacy.service])
        try await waitDiscover()
        guard let svc = p.services?.first(where: { $0.uuid == DFUMode.secure.service || $0.uuid == DFUMode.legacy.service }) else {
            // 用户可见文案不写 UUID（FE59 / 1530 对用户没有意义，只会挤占这句的唯一作用：
            // 告诉他"这台固件可能没有升级能力"）。技术细节留在下面的注释里。
            // 内部对照：Secure = 0xFE59，Legacy = 0x1530（见 DFUMode）。
            throw DFUTransportError.protocolError("这台门锁的固件没有升级模式，不支持 OTA")
        }
        mode = svc.uuid == DFUMode.secure.service ? .secure : .legacy
        p.discoverCharacteristics([DFUMode.secure.controlPoint, DFUMode.secure.packetPoint,
                                   DFUMode.legacy.controlPoint, DFUMode.legacy.packetPoint], for: svc)
        try await waitDiscover()
        guard let m = mode,
              let c = svc.characteristics?.first(where: { $0.uuid == m.controlPoint }),
              let d = svc.characteristics?.first(where: { $0.uuid == m.packetPoint }) else {
            throw DFUTransportError.protocolError("DFU 控制点/数据点缺失")
        }
        controlChar = c; packetChar = d
        p.setNotifyValue(true, for: c)
        // 协商 MTU：iOS 会在写时自动用最大 writeWithoutResponse 长度，这里取一个保守值
        mtu = max(20, min(244, p.maximumWriteValueLength(for: .withoutResponse)))
    }
    private func waitDiscover() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.discoverCont = cont
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                if self?.discoverCont != nil {
                    self?.discoverCont = nil
                    cont.resume(throwing: DFUTransportError.ble("服务发现超时（10s）"))
                }
            }
        }
    }
    private var discoverCont: CheckedContinuation<Void, Error>?

    // MARK: - 传输

    private func performTransfer() async throws {
        guard let m = mode else { throw DFUTransportError.protocolError("未确定 DFU 模式") }
        switch m {
        case .secure: try await secureTransfer()
        case .legacy: try await legacyTransfer()
        }
    }

    /// Secure DFU：Set PRN → Create Object(1=命令/2=数据) → 写 init packet → CRC → Execute → 写固件
    private func secureTransfer() async throws {
        // PRN = 12：每 12 包要一次回执，兼顾速度与可靠性（Nordic 推荐 12）
        prn = 12
        try await sendControl([0x02, UInt8(prn & 0xff), UInt8((prn >> 8) & 0xff)])
        try await waitAck()

        // ---- 1) init packet（.dat）----
        emit(.processStarting, "写入 init packet（\(pkg.datSize) B）")
        try await createObject(type: 1, size: pkg.datSize)
        try await writeData(hex: pkg.datHex, isInitPacket: true)
        try await crcCheck()
        try await execute()

        // ---- 2) 固件主体（.bin）----
        emit(.validating, "写入固件（\(pkg.binSize) B）")
        try await createObject(type: 2, size: pkg.binSize)
        try await writeData(hex: pkg.binHex, isInitPacket: false)
        try await crcCheck()
        try await execute()
    }

    private func createObject(type: UInt8, size: Int) async throws {
        var cmd: [UInt8] = [0x01, type]
        // 小端 4 字节长度
        cmd += [UInt8(size & 0xff), UInt8((size >> 8) & 0xff), UInt8((size >> 16) & 0xff), UInt8((size >> 24) & 0xff)]
        try await sendControl(cmd)
        try await waitAck()
    }

    /// 把 hex 切成 mtu 大小的块流式写入；每 prn 包等一次回执。
    private func writeData(hex: String, isInitPacket: Bool) async throws {
        guard let p = peripheral, let d = packetChar else { throw DFUTransportError.ble("未连接") }
        let chunkChars = mtu * 2
        var idx = hex.startIndex
        var packets = 0
        let total = hex.count / 2
        while idx < hex.endIndex {
            let end = hex.index(idx, offsetBy: chunkChars, limitedBy: hex.endIndex) ?? hex.endIndex
            let piece = String(hex[idx..<end])
            let bytes = HexKit.bytes(piece)
            p.writeValue(Data(bytes), for: d, type: .withoutResponse)
            idx = end
            packets += 1
            sentSinceAck += 1
            _ = total
            onProgress?(isInitPacket ? 0.05 : 0.05 + 0.9 * Double(hex.distance(from: hex.startIndex, to: idx)) / Double(max(1, hex.count)))
            if prn > 0 && sentSinceAck >= prn {
                try await waitAck()
                sentSinceAck = 0
            }
            // 让出时间片，避免把主线程写满（BLE 写本身是异步的）
            if packets % 64 == 0 { await Task.yield() }
        }
        // 末包不足 prn 时要补等一次
        if prn > 0 && sentSinceAck > 0 { try await waitAck(); sentSinceAck = 0 }
    }

    private func crcCheck() async throws {
        try await sendControl([0x03])
        try await waitAck()
    }
    private func execute() async throws {
        try await sendControl([0x04])
        try await waitAck()
    }

    /// Legacy DFU：start(1) + init packet + 数据 + validate(2)
    private func legacyTransfer() async throws {
        emit(.processStarting, "Legacy DFU：写入 init packet")
        // start packet: 0x01, 0x04 0x01(app) 0x00 0x00 0x00 0x00(timeout 0) 0x00 0x00,
        //               0x00 0x00 0x00(BIN CRC 占位) 0x00 0x00、0x00 0x00(数据大小占位)
        var start: [UInt8] = [0x01, 0x04, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        start[10] = UInt8(pkg.binSize & 0xff)     // 粗粒度占位（真实 CRC 由锁端自算）
        try await sendControl(start)
        try await waitAck()

        guard let p = peripheral, let d = packetChar else { throw DFUTransportError.ble("未连接") }
        let chunkChars = mtu * 2
        var idx = pkg.datHex.startIndex
        while idx < pkg.datHex.endIndex {
            let end = pkg.datHex.index(idx, offsetBy: chunkChars, limitedBy: pkg.datHex.endIndex) ?? pkg.datHex.endIndex
            let bytes = HexKit.bytes(String(pkg.datHex[idx..<end]))
            p.writeValue(Data(bytes), for: d, type: .withoutResponse)
            idx = end
        }
        emit(.validating, "Legacy DFU：写入固件（\(pkg.binSize) B）")
        idx = pkg.binHex.startIndex
        while idx < pkg.binHex.endIndex {
            let end = pkg.binHex.index(idx, offsetBy: chunkChars, limitedBy: pkg.binHex.endIndex) ?? pkg.binHex.endIndex
            let bytes = HexKit.bytes(String(pkg.binHex[idx..<end]))
            p.writeValue(Data(bytes), for: d, type: .withoutResponse)
            idx = end
            onProgress?(0.05 + 0.9 * Double(pkg.binHex.distance(from: pkg.binHex.startIndex, to: idx)) / Double(max(1, pkg.binHex.count)))
        }
        try await sendControl([0x02])   // validate
        try await waitAck()
    }

    // MARK: - 控制点应答

    private func sendControl(_ bytes: [UInt8]) async throws {
        guard let p = peripheral, let c = controlChar else { throw DFUTransportError.ble("控制点未就绪") }
        p.writeValue(Data(bytes), for: c, type: .withResponse)
    }

    /// 等一条控制点回执。成功（首字节 0x60/0x10）放行，失败（0x60 + 结果码）抛错。
    private func waitAck() async throws {
        if ackBuffer != nil { ackBuffer = nil; return }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.ackCont = cont
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                if self?.ackCont != nil {
                    self?.ackCont = nil
                    cont.resume(throwing: DFUTransportError.protocolError("等回执超时（15s）"))
                }
            }
        }
    }
    private var ackCont: CheckedContinuation<Void, Error>?
    private var ackBuffer: [UInt8]?

    private func emit(_ s: DFUState, _ msg: String) {
        DispatchQueue.main.async { self.onState?(s, msg) }
    }
}

// MARK: - CBCentralManagerDelegate / CBPeripheralDelegate

extension DFUSession: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            connectCont?.resume(throwing: DFUTransportError.ble("蓝牙不可用（\(central.state.rawValue)）"))
            connectCont = nil
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        scanHandler?(peripheral, advertisementData)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectCont?.resume()
        connectCont = nil
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectCont?.resume(throwing: DFUTransportError.ble("连接失败：\(error?.localizedDescription ?? "未知")"))
        connectCont = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // DFU 成功后设备会主动断开 —— 这是预期，不是错误
        if let c = connectCont { c.resume(throwing: DFUTransportError.ble("连接被断开")); connectCont = nil }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let e = error { discoverCont?.resume(throwing: DFUTransportError.ble("服务发现失败：\(e.localizedDescription)")); discoverCont = nil; return }
        discoverCont?.resume()
        discoverCont = nil
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let e = error { discoverCont?.resume(throwing: DFUTransportError.ble("特征发现失败：\(e.localizedDescription)")); discoverCont = nil; return }
        discoverCont?.resume()
        discoverCont = nil
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, !data.isEmpty else { return }
        let bytes = [UInt8](data)
        // Secure DFU 应答：0x60 + 操作码 + 结果码；Legacy：0x10 + 结果码
        if bytes[0] == 0x60 && bytes.count >= 3 {
            let result = bytes[2]
            if result == 1 {          // 1 = 成功
                if let c = ackCont { c.resume(); ackCont = nil } else { ackBuffer = bytes }
            } else {
                // 结果码 2 = 操作码不支持 / 3 = 参数错 / 4 = 数据超限 / 6 = 操作失败
                ackCont?.resume(throwing: DFUTransportError.protocolError("锁端返回结果码 \(result)"))
                ackCont = nil
            }
        } else if bytes[0] == 0x10 && bytes.count >= 2 {
            if let c = ackCont { c.resume(); ackCont = nil } else { ackBuffer = bytes }
        }
    }
}
