// BLE 服务 — CoreBluetooth 实现 (JS services/ble.js 的 iOS 等价)
//   * 扫描: CBUUID 过滤 (NUS 6E400001 / 网关 FE90), 10s 自动停扫 (对齐 App BleScan/BleDfu)
//   * 连接: 20s 超时, 发现服务→特征→开 notify; MTU 由系统协商 (无需 setBLEMTU)
//   * 写: 20B 分片 + 30ms 间隔 (对齐 JS writeFrame); 5xx 错误码映射
//   * 粘包重组: ZKProtocol.FrameAssembler (与 JS makeAssembler 逐行一致)
import Foundation
import Combine
@preconcurrency import CoreBluetooth

// 服务/特征 UUID (依据 Java BleLockConnector + GateWayConnector)
// Java 缺陷注记: GateWayConnector 构造会覆盖静态 UUID 导致锁/网关不可共存 — 本实现按连接目标选对 UUID, 无此缺陷
enum BLEUUID {
    static let svcMain = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")   // 门锁 NUS
    static let chrWrite = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    static let chrNotify = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    static let svcGW = CBUUID(string: "0000FE90-0000-1000-8000-00805F9B34FB")     // 网关
    static let chrGWWrite = CBUUID(string: "0000FE92-0000-1000-8000-00805F9B34FB")
    static let chrGWNotify = CBUUID(string: "0000FE91-0000-1000-8000-00805F9B34FB")
    // DFU (Nordic): Secure FE59 / Legacy 1530 + 蓝牙钥匙串 (自定义 6E401001)
    static let svcDfuSecure = CBUUID(string: "0000FE59-0000-1000-8000-00805F9B34FB")
    static let dfuSecureControl = CBUUID(string: "8EC90001-F315-4F60-9FB8-838830DAEA50")
    static let dfuSecurePacket = CBUUID(string: "8EC90002-F315-4F60-9FB8-838830DAEA50")
    static let svcDfuLegacy = CBUUID(string: "00001530-1212-EFDE-1523-785FEABCD123")
    static let dfuLegacyControl = CBUUID(string: "00001531-1212-EFDE-1523-785FEABCD123")
    static let dfuLegacyPacket = CBUUID(string: "00001532-1212-EFDE-1523-785FEABCD123")
}

struct BLEAdvDevice: Identifiable {
    var id: String { deviceId }
    var deviceId: String
    var name: String
    var rssi: Int
    var advertisHex: String
    var serviceUUIDs: [String]
}

// 错误码 (JS ble.js classifyError/bleCodeMessage 词表 — 与 App 同套编号)
enum BLEError: Int {
    case notFound = 1001        // 未发现设备
    case ssTokenFail = 1006
    case responseTimeout = 1007
    case connectTimeout = 2003
    case parseFail = 5001
    case writeTimeout = 6001
    case underlying = 6004
    case writeFailed = 6005

    var message: String {
        switch self {
        case .notFound: return "未发现门锁，请靠近门锁重试"
        case .ssTokenFail: return "获取ssToken失败"
        case .responseTimeout: return "超时未收到返回数据"
        case .connectTimeout: return "连接设备超时"
        case .parseFail: return "解析数据失败"
        case .writeTimeout: return "超时未等到Rx写入确认"
        case .underlying: return "蓝牙底层失败"
        case .writeFailed: return "发送命令失败"
        }
    }
}

enum BLEErrorX: LocalizedError {
    case code(BLEError)
    case msg(String)
    var errorDescription: String? {
        switch self {
        case .code(let c): return c.message
        case .msg(let m): return m
        }
    }
}

final class BLEService: NSObject, ObservableObject, @unchecked Sendable {
    static let shared = BLEService()
    @Published private(set) var isPoweredOn = false
    @Published private(set) var scanning = false
    @Published private(set) var connectedMAC: String = ""

    private var manager: CBCentralManager!
    private var scanTimer: Timer?
    private var discovered = [String: BLEAdvDevice]()

    // 当前连接
    private var device: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var connectCompletion: ((Result<Void, Error>) -> Void)?
    private var connectTimeoutWork: DispatchWorkItem?
    private var writeAckCont: CheckedContinuation<Void, Error>?

    // 帧重组 + 订阅
    private let assembler = ZKProtocol.FrameAssembler()
    private var frameSubscribers: [(ZKProtocol.ParsedFrame) -> Void] = []

    override init() {
        super.init()
    }
    // manager 必须延迟创建 (init 时主线程尚未就绪)
    func bootstrap() {
        if manager == nil {
            manager = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        }
    }
    /// 等待蓝牙就绪。首装时权限弹窗未答复期间 state 恒 .unknown, 直接判"未开启"会误导;
    /// 仿 DFUKit 的就绪等待, 超时后按真实 state 给可操作文案 (权限/开关/不支持分开)。
    func waitReady(timeoutMs: Int = 3000) async throws {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        while manager == nil || !isPoweredOn {
            if Date() > deadline { throw BLEErrorX.msg(readyMessage()) }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
    private func readyMessage() -> String {
        switch manager?.state {
        case .poweredOff: return "蓝牙未开启: 请到系统设置打开蓝牙后重试"
        case .unauthorized: return "未获得蓝牙权限: 请在系统设置 → 隐私与安全性 → 蓝牙 中允许本 App"
        case .unsupported: return "此设备不支持所需的蓝牙功能"
        default: return "蓝牙未就绪, 请稍候重试"
        }
    }

    // ---------- 帧订阅 ----------
    func onFrame(_ cb: @escaping (ZKProtocol.ParsedFrame) -> Void) {
        frameSubscribers.append(cb)
    }
    private func emit(_ f: ZKProtocol.ParsedFrame) {
        for cb in frameSubscribers { cb(f) }
    }

    // ---------- 扫描 ----------
    func startScan(allowDuplicates: Bool = false, intervalMs: Int = 500, timeoutMs: Int = 10000) async throws {
        try await waitReady()
        stopScanInternal()
        discovered.removeAll()
        scanning = true
        manager.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: allowDuplicates])
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: Double(timeoutMs) / 1000.0, repeats: false) { [weak self] _ in
            self?.stopScanInternal()
        }
    }
    func stopScan() { stopScanInternal() }
    private func stopScanInternal() {
        guard manager != nil else { return }
        if manager.isScanning { manager.stopScan() }
        scanTimer?.invalidate()
        scanTimer = nil
        scanning = false
    }
    func advDevice(_ deviceId: String) -> BLEAdvDevice? { discovered[deviceId] }
    /// 已发现设备快照 (供 MAC 扫描解析)
    func allDiscovered() -> [BLEAdvDevice] { Array(discovered.values) }

    // ---------- 连接 ----------
    func connect(deviceId: String, timeoutMs: Int = 20000) async throws {
        try await waitReady()
        if connectedMAC == deviceId, device?.state == .connected { return }
        disconnect()
        guard let devUUID = UUID(uuidString: deviceId) else { throw BLEErrorX.code(.notFound) }
        guard let target = manager.retrievePeripherals(withIdentifiers: [devUUID]).first
                ?? manager.retrieveConnectedPeripherals(withServices: [BLEUUID.svcMain, BLEUUID.svcGW]).first(where: { $0.identifier.uuidString == deviceId }) else {
            throw BLEErrorX.code(.notFound)
        }
        device = target
        connectCompletion = nil
        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                self.connectCompletion = { result in
                    self.connectTimeoutWork?.cancel()
                    self.connectTimeoutWork = nil
                    switch result {
                    case .success: cont.resume()
                    case .failure(let e): cont.resume(throwing: e)
                    }
                }
                // 超时定时器与本次连接绑定 (完成/失败/断开全路径取消) — 防误杀下一次连接
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.connectCompletion != nil else { return }
                    self.connectCompletion = nil
                    self.manager.cancelPeripheralConnection(target)
                    cont.resume(throwing: BLEErrorX.code(.connectTimeout))
                }
                self.connectTimeoutWork = work
                manager.connect(target, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(timeoutMs), execute: work)
            }
        } catch {
            if device?.identifier.uuidString == deviceId { device = nil }
            throw error
        }
        connectedMAC = deviceId
        assembler.reset()
    }
    func disconnect() {
        connectTimeoutWork?.cancel()
        connectTimeoutWork = nil
        if let c = connectCompletion {
            connectCompletion = nil
            c(.failure(BLEErrorX.msg("连接已取消")))
        }
        if let w = writeAckCont {
            writeAckCont = nil
            w.resume(throwing: BLEErrorX.msg("连接已断开"))
        }
        if let d = device { manager.cancelPeripheralConnection(d) }
        device = nil
        writeChar = nil
        notifyChar = nil
        connectedMAC = ""
        assembler.reset()
    }

    // ---------- 写 (20B 分片, 与 JS writeFrame 一致) ----------
    func writeFrameHex(_ hex: String) async throws {
        guard let device, let ch = writeChar else { throw BLEErrorX.code(.parseFail) }
        let bytes = HexKit.bytes(hex)
        var i = 0
        let chunk = 20
        while i < bytes.count {
            if device.state != .connected { throw BLEErrorX.code(.writeFailed) }
            let part = Data(bytes[i..<min(i + chunk, bytes.count)])
            i += chunk
            try await writeChunk(part, on: device, characteristic: ch)
            try? await Task.sleep(nanoseconds: 30_000_000) // 30ms 分片间隔
        }
    }
    private func writeChunk(_ data: Data, on device: CBPeripheral, characteristic ch: CBCharacteristic) async throws {
        // with-response 真流控 (JS writeBLECharacteristicValue 即此语义): 由 didWriteValueFor 收口。
        // 之前 withoutResponse + 20ms 假 ack — CoreBluetooth 无响应队列满时会静默丢包, 锁收到残帧
        // (cmd08 批量 13 分片最危险); writeAckCont/disconnect/didDisconnect 的失败恢复路径也随之变活。
        // 特征若不支持 with-response (属性里没有 .write), 退回无响应写 + 短歇限速
        guard ch.properties.contains(.write) else {
            device.writeValue(data, for: ch, type: .withoutResponse)
            try await Task.sleep(nanoseconds: 20_000_000)
            guard device.state == .connected else { throw BLEErrorX.code(.writeFailed) }
            return
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            // 超时兜底: didWriteValueFor 丢失时也能解挂 (manager queue = .main, 与回调串行无竞态)
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.writeAckCont != nil else { return }
                self.writeAckCont = nil
                cont.resume(throwing: BLEErrorX.code(.writeFailed))
            }
            self.writeAckCont = cont
            device.writeValue(data, for: ch, type: .withResponse)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
        }
    }

    // ---------- 底层连接辅助 (GateWayConnector/BleLockConnector 流程) ----------
    func ensureNotify(deviceId: String) async throws { _ = deviceId } // 兼容 JS ble.ensureOpen 调用点
}

// MARK: - CBCentralManagerDelegate
extension BLEService: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async {
            self.isPoweredOn = (central.state == .poweredOn)
        }
    }
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                              advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // 厂商段必须在任何分支都捕获 — ZK 锁广播只带厂商段 (98ed...), 缺它扫描永远解析不出 pid/MAC
        let mfgHex = ((advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data).map { HexKit.hex($0) }) ?? ""
        let svcDataHex = ((advertisementData[CBAdvertisementDataServiceDataKey] as? Data).map { HexKit.hex($0) }) ?? ""
        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map { $0.uuidString.uppercased() } ?? []
        discovered[peripheral.identifier.uuidString] = BLEAdvDevice(
            deviceId: peripheral.identifier.uuidString,
            name: peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "(未命名)"),
            rssi: RSSI.intValue,
            advertisHex: mfgHex.isEmpty ? svcDataHex : mfgHex,
            serviceUUIDs: serviceUUIDs)
    }
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let cb = connectCompletion
        connectCompletion = nil
        cb?(.failure(BLEErrorX.code(.connectTimeout)))
    }
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral === device else { return } // 陈旧设备的迟到回调: 不影响新一轮连接
        writeChar = nil
        notifyChar = nil
        connectedMAC = ""
        assembler.reset()
        if let w = writeAckCont {
            writeAckCont = nil
            w.resume(throwing: BLEErrorX.msg("连接已断开"))
        }
        if let cb = connectCompletion {
            connectCompletion = nil
            cb(.failure(BLEErrorX.msg("连接已断开")))
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BLEService: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else {
            let cb = connectCompletion; connectCompletion = nil
            cb?(.failure(BLEErrorX.code(.parseFail)))
            return
        }
        // NUS 优先, 网关 FE90 回退 (与 JS discover 同序)
        let target = services.first { $0.uuid == BLEUUID.svcMain }?.uuid
            ?? services.first { $0.uuid == BLEUUID.svcGW }?.uuid
        guard let svc = target else {
            let cb = connectCompletion; connectCompletion = nil
            cb?(.failure(BLEErrorX.msg("未发现 6E400001/FE90 服务")))
            return
        }
        peripheral.discoverCharacteristics(nil, for: (services.first { $0.uuid == svc })!)
    }
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics, error == nil else {
            let cb = connectCompletion
            connectCompletion = nil
            cb?(.failure(BLEErrorX.msg("读取特征失败")))
            return
        }
        let isMain = service.uuid == BLEUUID.svcMain
        let wTarget = isMain ? BLEUUID.chrWrite : BLEUUID.chrGWWrite
        let nTarget = isMain ? BLEUUID.chrNotify : BLEUUID.chrGWNotify
        let w = chars.first { $0.uuid == wTarget }
        let n = chars.first { $0.uuid == nTarget }
        guard let wc = w else {
            let cb = connectCompletion; connectCompletion = nil
            cb?(.failure(BLEErrorX.code(.parseFail)))
            return
        }
        guard let nc = n else {
            let cb = connectCompletion
            connectCompletion = nil
            cb?(.failure(BLEErrorX.msg("未找到通知特征 (数据上行不可用)")))
            return
        }
        writeChar = wc
        notifyChar = nc
        peripheral.setNotifyValue(true, for: nc)
    }
    private func finishConnect() {
        let cb = connectCompletion
        connectCompletion = nil
        cb?(.success(()))
    }
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        // notify 开启完成 = 连接就绪 (JS ensureNotify 语义)
        if let e = error {
            let cb = connectCompletion
            connectCompletion = nil
            cb?(.failure(BLEErrorX.msg("notify 开启失败: \(e.localizedDescription)")))
            return
        }
        guard characteristic.uuid == notifyChar?.uuid else { return }
        finishConnect()
    }
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, error == nil else { return }
        let frames = assembler.push(HexKit.hex(data))
        for f in frames { emit(f) }
    }
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let w = writeAckCont {
            writeAckCont = nil
            if error != nil { w.resume(throwing: BLEErrorX.code(.writeFailed)) } else { w.resume() }
            return
        }
        if let cb = connectCompletion, writeChar != nil, error != nil {
            connectCompletion = nil
            cb(.failure(BLEErrorX.code(.writeFailed)))
        }
    }
    public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) { }
}