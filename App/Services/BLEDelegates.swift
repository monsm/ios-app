// BLE 代理 · CBCentralManagerDelegate / CBPeripheralDelegate（扫描 / 连接 / 发现 / 通知 / 写入回调）
// 2026-10-29 从 BLEService.swift 拆出。
import Foundation
@preconcurrency import CoreBluetooth

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
        connectedPeripheralId = ""
        assembler.reset()
        // 断开后系统不会再发 ready 回调: 等在 readyCont 上的那一路必须放行, 否则 continuation 就悬着
        // (waitWriteReady 的兜底超时也会救它, 但那是 0.12s 的无谓等待 —— 两个机制都留着才稳)。
        readyTimer?.cancel()
        readyTimer = nil
        if let r = readyCont {
            readyCont = nil
            r.resume()
        }
        if let w = writeAckLock.withLock({ c -> CheckedContinuation<Void, Error>? in
            let old = c; c = nil; return old
        }) {
            w.resume(throwing: BLEErrorX.msg("连接已断开"))
        }
        if let cb = connectCompletion {
            connectCompletion = nil
            cb(.failure(BLEErrorX.msg("连接已断开")))
        }
    }
}

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
        if let w = writeAckLock.withLock({ c -> CheckedContinuation<Void, Error>? in
            let old = c; c = nil; return old
        }) {
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
    /// 连接层测距的回执。本扩展的回调都跑在 CBCentralManager 的 .main 队列上 (见 init),
    /// 所以这里可以直接调 completion —— 而 completion 那头是 @MainActor 的 LinkSense 代码。
    public func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        let cb = rssiCompletion
        rssiCompletion = nil
        cb?(error == nil ? RSSI.intValue : nil)
    }
}

