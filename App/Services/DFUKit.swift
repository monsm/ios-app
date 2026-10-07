// DFU 固件升级套件 — JS utils/dfu/{zip,nordic}.js + services/dfu.js 的 Swift 移植
//   * ZIP 解析 (CRC32 + 原生 inflate via Compression/COMPRESSION_ZLIB = RFC1951 raw deflate)
//   * Nordic DFU 双模式: Secure (FE59) / Legacy (1530), 操作码取自 APK 内嵌 Nordic 12.x 库
//   * 编排: cmd22 → 扫描 (MAC+1/ZkDFU 启发式) → 上传 → 进度 0-7
// 差分基准: golden.dfuZip.* (真实固件包 KX_V5.2.9), golden.inflate.*
import Foundation
import Compression

// ================= CRC32 (IEEE 802.3, 与 zlib 一致) =================
enum CRC32 {
    static let table: [UInt32] = {
        (0..<256).map { n -> UInt32 in
            var c = UInt32(n)
            for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
            return c
        }
    }()
    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in bytes { c = table[Int((c ^ UInt32(b)) & 0xff)] ^ (c >> 8) }
        return ~c
    }
}

// ================= ZIP 解析 (对抗上限: 单条目 8MB, ≤64 条目) =================
struct ZipEntry {
    var name: String
    var data: [UInt8]
    var crcOk: Bool
}
enum ZipKit {
    static let maxEntrySize = 8 * 1024 * 1024
    static let maxEntries = 64

    static func crc32(_ b: [UInt8]) -> UInt32 { CRC32.crc32(b) }

    // 原生 inflate (raw deflate) — 上限防护
    static func inflate(_ data: [UInt8], expected: Int) throws -> [UInt8] {
        guard expected <= maxEntrySize else { throw DFUError.zip("声称输出 \(expected)B 超上限 — 疑似 zip 炸弹") }
        var dst = [UInt8](repeating: 0, count: max(expected, 1))
        let written = data.withUnsafeBufferPointer { srcBuf -> Int in
            dst.withUnsafeMutableBufferPointer { dstBuf -> Int in
                compression_decode_buffer(dstBuf.baseAddress!, dstBuf.count,
                                          srcBuf.baseAddress!, srcBuf.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { throw DFUError.zip("inflate 失败 (输出 \(written)B)") }
        return Array(dst.prefix(written))
    }

    static func parse(_ data: [UInt8]) throws -> [ZipEntry] {
        // EOCD: 从尾部向前找 0x06054b50
        var eocd = -1
        let minOff = max(0, data.count - 22 - 65535)
        if data.count >= 22 {
            var i = data.count - 22
            while i >= minOff {
                if data[i] == 0x50, data[i + 1] == 0x4b, data[i + 2] == 0x05, data[i + 3] == 0x06 { eocd = i; break }
                i -= 1
            }
        }
        guard eocd >= 0 else { throw DFUError.zip("未找到目录结尾 (不是有效的 zip 文件)") }
        // UInt32 累加: Int 拼接在 ≥0x80000000 时返回负数 → 上层 guard 误放行 → 数组越界崩溃
        func u16(_ off: Int) -> Int {
            guard off >= 0, off + 1 < data.count else { return 0 }
            return Int(data[off]) | (Int(data[off + 1]) << 8)
        }
        func u32(_ off: Int) -> Int {
            guard off >= 0, off + 3 < data.count else { return 0 }
            let v = UInt32(data[off]) | (UInt32(data[off + 1]) << 8) | (UInt32(data[off + 2]) << 16) | (UInt32(data[off + 3]) << 24)
            return Int(v)
        }
        let count = u16(eocd + 10)
        guard count <= maxEntries else { throw DFUError.zip("条目数异常 (\(count))") }
        var off = u32(eocd + 16)
        var entries = [ZipEntry]()
        for _ in 0..<count {
            guard off + 46 <= data.count, u32(off) == 0x02014b50 else { throw DFUError.zip("中央目录损坏") }
            let method = u16(off + 10)
            let crcExpect = UInt32(u32(off + 16))
            let csize = u32(off + 20)
            let usize = u32(off + 24)
            let nameLen = u16(off + 28)
            let extraLen = u16(off + 30)
            let cmtLen = u16(off + 32)
            let lho = u32(off + 42)
            guard off + 46 + nameLen + extraLen + cmtLen <= data.count else { throw DFUError.zip("中央目录越界") }
            let name = String(bytes: data[(off + 46)..<(off + 46 + nameLen)], encoding: .utf8) ?? ""
            guard usize <= maxEntrySize, csize <= data.count else { throw DFUError.zip("条目解压尺寸异常 (\(name) 声称 \(usize)B)") }
            guard lho + 30 <= data.count, u32(lho) == 0x04034b50 else { throw DFUError.zip("本地文件头损坏 (\(name))") }
            let lNameLen = u16(lho + 26)
            let lExtraLen = u16(lho + 28)
            let dataOff = lho + 30 + lNameLen + lExtraLen
            guard dataOff + csize <= data.count else { throw DFUError.zip("条目数据越界 (\(name))") }
            let cdata = Array(data[dataOff..<(dataOff + csize)])
            var content: [UInt8]
            if method == 0 {
                content = cdata
            } else if method == 8 {
                guard !cdata.isEmpty else { throw DFUError.zip("空 deflate 条目 (\(name))") }
                content = try inflate(cdata, expected: usize)
            } else {
                throw DFUError.zip("不支持的压缩方式 \(method) (\(name))")
            }
            if usize != 0 && content.count != usize { throw DFUError.zip("解压长度不符 (\(name))") }
            entries.append(ZipEntry(name: name, data: content, crcOk: CRC32.crc32(content) == crcExpect))
            off += 46 + nameLen + extraLen + cmtLen
        }
        return entries
    }
    static func find(_ entries: [ZipEntry], _ name: String) -> ZipEntry? {
        let base = name.split(separator: "/").last.map(String.init)?.lowercased() ?? name.lowercased()
        if let exact = entries.first(where: { $0.name == name }) { return exact }
        return entries.first { $0.name.split(separator: "/").last.map(String.init)?.lowercased() == base }
    }
}

// ================= 固件包解析 (JS services/dfu.js parseDfuZip) =================
enum DFUError: LocalizedError {
    case zip(String)
    case msg(String)
    var errorDescription: String? {
        switch self {
        case .zip(let m): return m
        case .msg(let m): return m
        }
    }
}
struct FirmwarePackage {
    var binHex: String
    var datHex: String
    var binSize: Int
    var datSize: Int
    var version: String?   // 文件名 KX_V5.2.9_* → 5.2.9
    var sourceName: String
}
enum FirmwareKit {
    static let limits = (manifest: 4096, dat: 4096, bin: 8 * 1024 * 1024)
    static func parse(zipData: [UInt8], fileName: String) throws -> FirmwarePackage {
        let entries = try ZipKit.parse(zipData)
        guard let manifestE = ZipKit.find(entries, "manifest.json") else { throw DFUError.zip("固件包缺少 manifest.json") }
        guard manifestE.data.count <= limits.manifest else { throw DFUError.zip("manifest.json 异常过大") }
        guard let raw = String(bytes: manifestE.data, encoding: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              let manifest = obj["manifest"] as? [String: Any],
              let app = (manifest["application"] as? [String: Any]) ?? (manifest["bootloader"] as? [String: Any]) else {
            throw DFUError.zip("manifest.json 不是有效结构")
        }
        // 别名对齐 vendor dfu.js: 个别厂商包用 binFilename/data_file
        let binName = app["bin_file"] as? String ?? app["binFilename"] as? String ?? ""
        let datName = app["dat_file"] as? String ?? app["data_file"] as? String ?? ""
        guard let binE = ZipKit.find(entries, binName), !binName.isEmpty else { throw DFUError.zip("固件包缺少固件文件 (\(binName))") }
        guard let datE = ZipKit.find(entries, datName), !datName.isEmpty else { throw DFUError.zip("固件包缺少 init packet (\(datName))") }
        guard binE.crcOk else { throw DFUError.zip("固件文件 CRC 校验失败 (包损坏)") }
        guard datE.crcOk else { throw DFUError.zip("init packet CRC 校验失败 (包损坏)") }
        guard binE.data.count >= 512, binE.data.count <= limits.bin else { throw DFUError.zip("固件尺寸异常 (\(binE.data.count)B)") }
        guard datE.data.count >= 16, datE.data.count <= limits.dat else { throw DFUError.zip("init packet 尺寸异常 (\(datE.data.count)B)") }
        return FirmwarePackage(binHex: HexKit.hex(binE.data), datHex: HexKit.hex(datE.data),
                               binSize: binE.data.count, datSize: datE.data.count,
                               version: versionFromFileName(fileName), sourceName: fileName)
    }
    static func versionFromFileName(_ name: String) -> String? {
        guard let m = name.range(of: "_?V?(\\d+\\.\\d+\\.\\d+)_", options: .regularExpression) else { return nil }
        let s = name[m]
        var digits = s.drop(while: { !$0.isNumber })
        while let last = digits.last, !last.isNumber { digits = digits.dropLast() } // 剥尾部 _ (P3-1)
        return digits.isEmpty ? nil : String(digits)
    }
    static func versionLt(_ a: String, _ b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<3 {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y }
        }
        return false
    }
    // DFU 模式 MAC 启发式: 末字节 +1 (255→0 回绕)
    static func nextMac(_ macHex: String) -> String {
        let m = macHex.replacingOccurrences(of: ":", with: "").lowercased()
        guard m.count == 12 else { return m }
        let last = UInt8(m.suffix(2), radix: 16) ?? 0
        let inc = String(format: "%02x", last &+ 1)
        return String(m.dropLast(2)) + inc
    }
}

// ================= Nordic DFU 会话 (JS utils/dfu/nordic.js 移植) =================
@preconcurrency import CoreBluetooth

final class DFUBleSession: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    enum Mode { case secure, legacy }
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var mode: Mode = .secure
    private var controlChar: CBCharacteristic?
    private var packetChar: CBCharacteristic?
    private var connectCont: CheckedContinuation<Void, Error>?
    private var responseBuffer: [String] = []
    private var responseWaiter: CheckedContinuation<String, Error>?
    private var writeAckCont: CheckedContinuation<Void, Error>?
    private var aborted = false
    var logFn: ((String) -> Void)?

    // 等待一条控制点响应 hex (超时随本次等待捕获 — 无共享 deadline, 陈旧定时器不会误杀)
    private var responseTimer: DispatchWorkItem?

    private func waitResponse(timeoutMs: Int) async throws -> String {
        if !responseBuffer.isEmpty { return responseBuffer.removeFirst() }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            // 定时器身份化: op() 循环跳过陈旧响应时会重入等待, 上一轮定时器若还挂着,
            // 其旧 deadline 恒已过期, 会把新一轮 waiter 提前"超时"误杀 — 每轮先作废旧定时器
            responseTimer?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, let w = self.responseWaiter else { return }
                self.responseWaiter = nil
                w.resume(throwing: DFUError.msg("超时: 未收到 DFU 响应"))
            }
            responseTimer = work
            self.responseWaiter = cont
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(timeoutMs), execute: work)
        }
    }
    func abort() { aborted = true }

    func connect(deviceId: String, timeoutMs: Int = 15000) async throws -> Mode {
        central = central ?? CBCentralManager(delegate: self, queue: .main)
        if central.state != .poweredOn {
            // 等待就绪 (最多 3s); 走 if 而非 guard — guard 体嵌套 guard 后贯穿非法 (CI 报 :226)
            for _ in 0..<30 {
                if central.state == .poweredOn { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard central.state == .poweredOn else { throw DFUError.msg("蓝牙未开启") }
        }
        guard let uuid = UUID(uuidString: deviceId),
              let target = central.retrievePeripherals(withIdentifiers: [uuid]).first else {
            throw DFUError.msg("DFU 设备已失联, 请重试")
        }
        peripheral = target
        let timeout = DispatchTime.now() + .milliseconds(timeoutMs)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.connectCont = cont
            central.connect(target)
            DispatchQueue.main.asyncAfter(deadline: timeout) { [weak self] in
                guard let self, self.connectCont != nil else { return }
                self.connectCont = nil
                self.central.cancelPeripheralConnection(target)
                cont.resume(throwing: DFUError.msg("连接 DFU 设备超时"))
            }
        }
        return mode
    }
    func disconnect() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        controlChar = nil
        packetChar = nil
    }

    // ---- 控制点操作 + 响应匹配 ----
    private func writeControl(_ hex: String) async throws {
        guard let ch = controlChar else { throw DFUError.msg("未连接 DFU 控制点") }
        try await writeRaw(hex, ch: ch)
    }
    private func writePacket(_ hex: String) async throws {
        guard let ch = packetChar else { throw DFUError.msg("未连接 DFU 数据点") }
        try await writeRaw(hex, ch: ch)
    }
    private func writeRaw(_ hex: String, ch: CBCharacteristic) async throws {
        let data = Data(HexKit.bytes(hex))
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.writeAckCont = cont
            // 超时兜底: peripheral 已断开时 writeValue 静默不执行 → 无回调 → 挂死
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                guard let self, let w = self.writeAckCont else { return }
                self.writeAckCont = nil
                w.resume(throwing: DFUError.msg("写入超时"))
            }
            guard let p = self.peripheral else {
                self.writeAckCont = nil
                cont.resume(throwing: DFUError.msg("设备已断开"))
                return
            }
            p.writeValue(data, for: ch, type: .withResponse)
        }
    }
    private func op(_ hex: String, _ what: String, timeoutMs: Int = 10000) async throws -> (status: Int, payload: String) {
        try await writeControl(hex)
        let req = Int(HexKit.bytes(hex)[0])
        let deadlineAt = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        while Date() < deadlineAt {
            let rHex = try await waitResponse(timeoutMs: Int(deadlineAt.timeIntervalSinceNow * 1000))
            guard let b = HexKit.bytes(rHex).first else { continue }
            let isResp = (mode == .secure && b == 0x60) || (mode == .legacy && b == 0x10)
            guard isResp, HexKit.bytes(rHex).count >= 3 else { continue }
            let reqGot = Int(HexKit.bytes(rHex)[1])
            let status = Int(HexKit.bytes(rHex)[2])
            if reqGot != req { continue } // 陈旧响应跳过
            if status != 1 {
                throw DFUError.msg("DFU 操作失败 (\(what)): status=\(status)")
            }
            return (status, String(rHex.dropFirst(6)))
        }
        throw DFUError.msg("超时: 未收到 \(what) 响应")
    }
    private func rdU32(_ payload: String, _ byteOff: Int, _ what: String) throws -> UInt32 {
        let need = (byteOff + 4) * 2
        guard payload.count >= need else { throw DFUError.msg("DFU 响应载荷过短 (\(what)): \(payload)") }
        return HexKit.readU32LE(payload, byteOffset: byteOff)
    }
    private func stream(_ hex: String, onProgress: ((Int, Int) -> Void)?) async throws {
        let bytes = HexKit.bytes(hex)
        let chunk = 20
        var i = 0
        let total = bytes.count
        while i < total {
            guard !aborted else { throw DFUError.msg("已中止") }
            let end = min(i + chunk, total)
            try await writePacket(HexKit.hex(Array(bytes[i..<end])))
            i = end
            if let cb = onProgress, i % 400 == 0 { cb(i, total) }
        }
        onProgress?(total, total)
    }

    // ---- Secure DFU ----
    func uploadSecure(binHex: String, datHex: String, onProgress: @escaping (Int, Int) -> Void) async throws {
        _ = try await op("02" + "0000", "PRN")                       // PRN=0
        let selCmd = try await op("06" + "01", "Select command")     // 选命令对象
        let cmdMax = try rdU32(selCmd.payload, 0, "Select command")
        guard datHex.count / 2 <= cmdMax else { throw DFUError.msg("init packet 大小超限 (\(datHex.count / 2)>\(cmdMax))") }
        _ = try await op("01" + "01" + HexKit.u32leHex(UInt32(datHex.count / 2)), "Create command")
        try await stream(datHex, onProgress: nil)
        let chk1 = try await op("03", "Checksum")
        let off1 = try rdU32(chk1.payload, 0, "Checksum")
        let crc1 = try rdU32(chk1.payload, 4, "Checksum")
        let localCrc = CRC32.crc32(HexKit.bytes(datHex))
        guard off1 == datHex.count / 2, crc1 == localCrc else {
            throw DFUError.msg(String(format: "init packet CRC 不匹配 (dev %08x vs local %08x)", crc1, localCrc))
        }
        _ = try await op("04", "Execute command")
        onProgress(0, 0)
        let selData = try await op("06" + "02", "Select data")
        let maxObj = Int(try rdU32(selData.payload, 0, "Select data"))
        guard maxObj > 0 else { throw DFUError.msg("外设对象尺寸为 0, 中止升级") }
        let total = binHex.count / 2
        var sent = 0
        while sent < total {
            guard !aborted else { throw DFUError.msg("已中止") }
            let objSize = min(maxObj, total - sent)
            _ = try await op("01" + "02" + HexKit.u32leHex(UInt32(objSize)), "Create data")
            let objHex = String(binHex.dropFirst(sent * 2).prefix(objSize * 2))
            try await stream(objHex) { n, t in
                onProgress(sent + n, t)
            }
            let chk = try await op("03", "Checksum")
            let off = try rdU32(chk.payload, 0, "Checksum")
            let crc = try rdU32(chk.payload, 4, "Checksum")
            let objCrc = CRC32.crc32(HexKit.bytes(objHex))
            guard off == objSize, crc == objCrc else {
                throw DFUError.msg(String(format: "数据对象 CRC 不匹配 (offset %d/%d)", off, objSize))
            }
            _ = try await op("04", "Execute data")
            sent += objSize
        }
    }

    // ---- Legacy DFU ----
    func uploadLegacy(binHex: String, datHex: String, onProgress: @escaping (Int, Int) -> Void) async throws {
        try await writeControl("01" + "04") // Start DFU (mode 4 = application)
        try await writePacket(HexKit.u32leHex(0) + HexKit.u32leHex(0) + HexKit.u32leHex(UInt32(binHex.count / 2)))
        _ = try await resp(1, "Start DFU", timeoutMs: 10000)
        _ = try await op("02" + "00", "Init start")
        try await stream(datHex, onProgress: nil)
        _ = try await op("02" + "01", "Init complete")
        try await writeControl("08" + "0000") // PRN=0 (库不等待响应)
        try await writeControl("03")          // Receive Firmware Image
        onProgress(0, 0)
        let total = binHex.count / 2
        let chunk = 20
        var lastPct = -1
        var i = 0
        while i < binHex.count {
            guard !aborted else { throw DFUError.msg("已中止") }
            try await writePacket(String(binHex.dropFirst(i).prefix(chunk * 2)))
            i += chunk * 2
            let done = min(total, i / 2)
            let pct = Int(Double(done) / Double(total) * 100)
            if pct != lastPct && (pct % 5 == 0 || done == total) {
                lastPct = pct
                onProgress(done, total)
            }
        }
        _ = try await resp(3, "Firmware received", timeoutMs: 60000) // 尾包后整段落盘
        onProgress(total, total)
        _ = try await op("04", "Validate")
        try await writeControl("05") // Activate & Reset (无响应)
    }
    private func resp(_ req: Int, _ what: String, timeoutMs: Int) async throws -> (status: Int, payload: String) {
        let deadlineAt = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        while Date() < deadlineAt {
            let rHex = try await waitResponse(timeoutMs: Int(max(1, deadlineAt.timeIntervalSinceNow * 1000)))
            let b = HexKit.bytes(rHex)
            guard b.count >= 3 else { continue }
            let isResp = (mode == .secure && b[0] == 0x60) || (mode == .legacy && b[0] == 0x10)
            guard isResp, Int(b[1]) == req else { continue }
            if Int(b[2]) != 1 { throw DFUError.msg("DFU 操作失败 (\(what)): status=\(b[2])") }
            return (1, String(rHex.dropFirst(6)))
        }
        throw DFUError.msg("超时: 未收到 \(what) 响应")
    }

    // MARK: CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) { }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) { }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if let c = writeAckCont { writeAckCont = nil; c.resume(throwing: DFUError.msg("连接失败")) }
        connectCont?.resume(throwing: DFUError.msg("连接失败"))
        connectCont = nil
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let c = writeAckCont {  // P1-3: 断连必须续跑挂起的写入 (否则升级中断后永久卡死)
            writeAckCont = nil
            c.resume(throwing: DFUError.msg("连接已断开"))
        }
        if let c = connectCont {
            connectCont = nil
            c.resume(throwing: DFUError.msg("连接已断开"))
        }
        if let w = responseWaiter {   // 升级中断连: 挂起的 op() 立即失败, 不等满 60s 超时
            responseWaiter = nil
            responseTimer?.cancel()
            w.resume(throwing: DFUError.msg("连接已断开"))
        }
    }
    // MARK: CBPeripheralDelegate
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        if let s = services.first(where: { $0.uuid == BLEUUID.svcDfuSecure }) {
            mode = .secure
            peripheral.discoverCharacteristics([BLEUUID.dfuSecureControl, BLEUUID.dfuSecurePacket], for: s)
        } else if let s = services.first(where: { $0.uuid == BLEUUID.svcDfuLegacy }) {
            mode = .legacy
            peripheral.discoverCharacteristics([BLEUUID.dfuLegacyControl, BLEUUID.dfuLegacyPacket], for: s)
        } else {
            connectCont?.resume(throwing: DFUError.msg("未发现 DFU 服务 (FE59/1530)"))
            connectCont = nil
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics,
              let ctrl = chars.first(where: { $0.uuid == (mode == .secure ? BLEUUID.dfuSecureControl : BLEUUID.dfuLegacyControl) }),
              let pkt = chars.first(where: { $0.uuid == (mode == .secure ? BLEUUID.dfuSecurePacket : BLEUUID.dfuLegacyPacket) }) else {
            connectCont?.resume(throwing: DFUError.msg("DFU 服务特征缺失"))
            connectCont = nil
            return
        }
        controlChar = ctrl
        packetChar = pkt
        peripheral.setNotifyValue(true, for: ctrl)
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let e = error {
            connectCont?.resume(throwing: DFUError.msg("notify 开启失败: \(e.localizedDescription)"))
            connectCont = nil
            return
        }
        if let c = connectCont {
            connectCont = nil
            c.resume()
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, error == nil else { return }
        let hex = HexKit.hex(data)
        if let w = responseWaiter {
            responseWaiter = nil
            w.resume(returning: hex)
        } else {
            responseBuffer.append(hex)
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let c = writeAckCont {
            writeAckCont = nil
            if let e = error { c.resume(throwing: DFUError.msg("写入失败: \(e.localizedDescription)")) }
            else { c.resume() }
        }
    }
}

// ================= 升级编排 (JS services/dfu.js runUpgrade) =================
enum DFUProgress {
    case connecting      // 0
    case starting        // 1
    case switchingDfu    // 2
    case uploading(percent: Int)  // 3
    case validating      // 4
    case disconnecting   // 5
    case completed       // 6
    case aborted         // 7
}

@MainActor
enum DFURunner {
    static func scanDfuDevice(lockMAC: String, pid: Int, timeoutMs: Int = 15000) async throws -> String {
        let ble = BLEService.shared
        try await ble.startScan(timeoutMs: timeoutMs)
        defer { ble.stopScan() }
        let wantA = lockMAC.replacingOccurrences(of: ":", with: "").lowercased()
        let wantB = FirmwareKit.nextMac(wantA)
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        while Date() < deadline {
            for d in ble.allDiscovered() {
                let adv = ZKProtocol.parseAdv(d.advertisHex)
                let nameHit = d.name.range(of: "ZkDFU", options: .caseInsensitive) != nil
                if let a = adv, let mac = a.macRaw {
                    let macHit = (mac == wantA || mac == wantB)
                    let dfuHit = a.dfuState == 1 && a.pid == pid
                    if (macHit && dfuHit) || (nameHit && a.pid == pid) { return d.deviceId }
                } else if nameHit {
                    return d.deviceId // 广播不可解析时才放行名称兜底
                }
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        throw BLEErrorX.code(.notFound)
    }

    static func runUpgrade(lock: LockService, mac: String, pid: Int, firmware: FirmwarePackage,
                           onProgress: @escaping (DFUProgress) -> Void) async throws {
        // 1. cmd 22 (锁重启进 bootloader; 断链属预期)
        onProgress(.switchingDfu)
        var cmd22Err: Error?
        do { try await lock.enableDfu() } catch { cmd22Err = error }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        lock.disconnect()
        // 2. 扫描 DFU 设备 (cmd22 未确认时也尝试 — 锁可能已处于 DFU 模式, 与 App reCheck 语义一致)
        onProgress(.connecting)
        let deviceId: String
        do {
            deviceId = try await scanDfuDevice(lockMAC: mac, pid: pid)
        } catch {
            if let e = cmd22Err { throw e } // 优先呈现 cmd22 的真实原因
            throw error
        }
        // 3. 连接 + 上传
        let session = DFUBleSession()
        let mode = try await session.connect(deviceId: deviceId)
        onProgress(.starting)
        do {
            switch mode {
            case .secure:
                try await session.uploadSecure(binHex: firmware.binHex, datHex: firmware.datHex) { done, total in
                    let pct = total > 0 ? Int(Double(done) / Double(total) * 100) : 0
                    Task { @MainActor in onProgress(.uploading(percent: pct)) }
                }
            case .legacy:
                try await session.uploadLegacy(binHex: firmware.binHex, datHex: firmware.datHex) { done, total in
                    let pct = total > 0 ? Int(Double(done) / Double(total) * 100) : 0
                    Task { @MainActor in onProgress(.uploading(percent: pct)) }
                }
            }
            onProgress(.completed)
        } catch {
            onProgress(.aborted)
            session.abort()
            throw error
        }
        session.disconnect()
    }
}