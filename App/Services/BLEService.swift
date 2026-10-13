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
    // 写槽串行化: writeAckCont 是单一槽位, 并发写时后者会覆盖前者的 continuation
    // → 前者永不 resume (挂死 + continuation 泄漏), 而 LockService 与 HardwareService 各有独立 waiter,
    // 共用本服务时确实可并发 (看门狗/回连循环 vs 用户手动操作)。didWriteValueFor 本就按序回调, 串起来即可。
    private var writeBusy = false
    private var writeBusyWaiters: [CheckedContinuation<Void, Never>] = []
    // 1b/拍板#1: 无响应写的"可发"就绪等待。单槽即可 —— 分片写 (cmd08) 本身逐片 await, 不会并发。
    private var readyCont: CheckedContinuation<Void, Never>?
    private var readyTimer: DispatchWorkItem?

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
    /// 供体检/诊断读**真实**蓝牙状态。nil = 中心管理尚未创建。
    /// 诊断侧不要自己 `CBCentralManager()`: 无代理的实例永远停在 .unknown, 会把"蓝牙正常"判成"蓝牙未开启"。
    var powerState: CBManagerState? { manager?.state }
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
    /// 123 扫描强度三档: **只作用于发现型扫描** (冷启动扫描 / 环境拥挤度), 不改连接与 AUTOOPEN 的时序，
    /// 免得一个"省电"档位把靠近自动开锁的判定窗口一起收窄。默认档 = 现状 (5s)。
    enum ScanProfile: String, CaseIterable {
        case eco, balanced, fast
        static let storeKey = "kf_scan_profile"
        static var current: ScanProfile { ScanProfile(rawValue: DB.store.getString(storeKey)) ?? .balanced }
        var timeoutMs: Int {
            switch self {
            case .eco: return 2_500
            case .balanced: return 5_000
            case .fast: return 10_000
            }
        }
        /// 只有极速档开重复广播: 拿满每个广播包用于密集环境清点, 代价是 CPU 与耗电
        var allowDuplicates: Bool { self == .fast }
        var label: String {
            switch self {
            case .eco: return "省电 · 每次扫 2.5 秒"
            case .balanced: return "均衡 · 每次扫 5 秒 (默认)"
            case .fast: return "极速 · 每次扫 10 秒 (含重复广播)"
            }
        }
    }

    // 2026-10-13 对抗式排查: 补 @MainActor。原写是非隔离 async func, 而**非隔离 async 函数被
    // @MainActor 上下文 await 时会跑到全局执行器** (Swift 不做 actor 继承) ⇒ 两件事一起坏:
    //   ① `scanning = true` 是 @Published 写入后台线程 (Combine 从后台 emit, SwiftUI 侧行为未定义);
    //   ② `Timer.scheduledTimer` 把定时器挂在**当前线程的 run loop** 上, GCD worker 没有 run loop
    //      ⇒ 超时回调永不触发 ⇒ 扫描窗口永不自动关, scanning 卡 true, 射频空转到下一次 startScan。
    //   冷启动 coldStartScan 没有 defer stopScan, 完全依赖这个定时器 —— 一启动即复现 (蓝牙长扫 = 耗电)。
    // 全部调用点 (LinkSenseKit/DFUKit/HardwareService/LockService/Sheets) 本就 `await` 它,
    // 标 @MainActor 后调用点无需改动, 而函数体 (含 Timer) 确定跑在主线程/main run loop 上。
    @MainActor
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
    /// 已发现设备快照 (供 MAC 扫描解析)
    func allDiscovered() -> [BLEAdvDevice] { Array(discovered.values) }
    // 曾另有 advDevice(_ deviceId:) 按 deviceId 单查: 全仓零调用 (连接走 CB 的
    // retrievePeripherals(withIdentifiers:), 不用这个表), 删。

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
        // 写槽随连接一起复位: 断链时若有调用方在 acquireWriteSlot 的队列里等槽,
        // 不唤醒它们就会永久挂死, 并且 writeBusy 卡 true 会阻塞之后每一次写。
        // 被唤醒者随后会撞上 writeFrameHex 的 `guard let device` 而快速失败, 不会误发。
        writeBusy = false
        let queued = writeBusyWaiters
        writeBusyWaiters.removeAll()
        for c in queued { c.resume() }
        if let d = device { manager.cancelPeripheralConnection(d) }
        device = nil
        writeChar = nil
        notifyChar = nil
        connectedMAC = ""
        assembler.reset()
    }

    // ---------- 写 (20B 分片, 与 JS writeFrame 一致) ----------
    func writeFrameHex(_ hex: String) async throws {
        // 演示模式红线收口: 此前 DemoKit.isOn 只在 UI 的个别入口判 (Services 层零引用),
        // 导致录密码/录指纹/DFU/钥匙串写删/网关写 WiFi 都能在演示态真发到设备。
        // 写入是唯一会改锁端状态的操作 —— 在这一处拦死即覆盖全部命令面。
        guard !DemoKit.isOn else {
            throw BLEErrorX.msg("演示模式禁止下发真实命令 (demo 数据不落锁)")
        }
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
    /// 取写槽 (FIFO): 同一特征值的 with-response 写必须串行, 否则 writeAckCont 单槽被后者覆盖,
    /// 前者的 continuation 永不完成 (挂死)。已在写的情况下把调用方排进等待队列。
    private func acquireWriteSlot() async {
        if !writeBusy { writeBusy = true; return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in writeBusyWaiters.append(c) }
        writeBusy = true
    }
    private func releaseWriteSlot() {
        guard let next = writeBusyWaiters.first else { writeBusy = false; return }
        writeBusyWaiters.removeFirst()
        next.resume()
    }
    /// 无响应写的真流控: 等 `peripheralIsReady(toSendWriteWithoutResponse:)`。
    /// 保留兜底超时 (默认 0.12s, 与旧的 20ms sleep 同量级但更宽) —— 个别固件不再回调时,
    /// "永远等下去"比原来的盲限速更糟, 所以到点也放行。
    private func waitWriteReady(_ device: CBPeripheral, maxSeconds: Double = 0.12) async {
        if device.canSendWriteWithoutResponse { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            // 单槽: 先放行上一位等待者, 绝不让它悬着 (悬着的 continuation 是永久泄漏)
            readyCont?.resume()
            readyCont = c
            readyTimer?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.readyCont != nil else { return }
                self.readyCont = nil
                c.resume()
            }
            readyTimer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + maxSeconds, execute: work)
        }
    }
    private func writeChunk(_ data: Data, on device: CBPeripheral, characteristic ch: CBCharacteristic) async throws {
        // with-response 真流控 (JS writeBLECharacteristicValue 即此语义): 由 didWriteValueFor 收口。
        // 之前 withoutResponse + 20ms 假 ack — CoreBluetooth 无响应队列满时会静默丢包, 锁收到残帧
        // (cmd08 批量 13 分片最危险); writeAckCont/disconnect/didDisconnect 的失败恢复路径也随之变活。
        // 特征若不支持 with-response (属性里没有 .write), 退回无响应写 + 短歇限速
        guard ch.properties.contains(.write) else {
            device.writeValue(data, for: ch, type: .withoutResponse)
            // 拍板 #1 (第六十五批): 用系统就绪信号替代原来的 20ms 盲 sleep。
            // 队列满时 CoreBluetooth 对 withoutResponse 写是**静默丢弃**的, 固定间隔只是在猜到达。
            await waitWriteReady(device)
            guard device.state == .connected else { throw BLEErrorX.code(.writeFailed) }
            return
        }
        await acquireWriteSlot()
        defer { releaseWriteSlot() }
        // 本轮定时器句柄外提, 函数退出 (成功/失败/抛错) 一律 cancel。
        // 旧实现从不 cancel: 上一片的 3s 定时器会在**下一次写**把 writeAckCont 当成自己的槽,
        // 以 .writeFailed 抛掉别人的 continuation → LockService 误判断链 → disconnect + 静默重连
        // → 配网在"换钥已成功、PIN 池未同步完、keychain 未落库"处中断 = 锁内新 skey 对不上本机, 软砖。
        var ackTimer: DispatchWorkItem?
        defer { ackTimer?.cancel() }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.writeAckCont != nil else { return }
                self.writeAckCont = nil
                cont.resume(throwing: BLEErrorX.code(.writeFailed))
            }
            ackTimer = work
            self.writeAckCont = cont
            device.writeValue(data, for: ch, type: .withResponse)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
        }
    }

    // ---------- 底层连接辅助 (GateWayConnector/BleLockConnector 流程) ----------
    // 第九十一批删掉 `ensureNotify(deviceId:)`：它是 `func ensureNotify… { _ = deviceId }` 这种
    // **名字像行为、体是空操作**的兼容口 (注释说给 JS 的 ble.ensureOpen 用)，而 iOS 侧零调用点。
    // 这类口最危险的地方在于"调用它就以为订阅了通知" —— 真要补 notify 订阅应在 connect 路径里
    // 显式 setNotifyValue，而不是留一个吞参数的同名函数。
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
        // 断开后系统不会再发 ready 回调: 等在 readyCont 上的那一路必须放行, 否则 continuation 就悬着
        // (waitWriteReady 的兜底超时也会救它, 但那是 0.12s 的无谓等待 —— 两个机制都留着才稳)。
        readyTimer?.cancel()
        readyTimer = nil
        if let r = readyCont {
            readyCont = nil
            r.resume()
        }
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
    /// 拍板 #1 (第六十五批): 这条回调就是上面 .withoutResponse 分支的正解 —— 本机队列满时系统不报错也不抛,
    /// 只是暂时不再接受写; 旧的 20ms 盲 sleep 分不清"对端慢"与"队列满", 分片写 (cmd08) 就可能残帧。
    /// 收到就绪信号即放行 waitWriteReady 里的等待者; 没有等待者时什么也不做。
    public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        readyTimer?.cancel()
        readyTimer = nil
        guard let c = readyCont else { return }
        readyCont = nil
        c.resume()
    }
}
