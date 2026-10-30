// BLE 基础类型 · UUID / 广播设备 / 错误码 / 扫描档
// 2026-10-29 从 BLEService.swift（617 行）拆出。
import Foundation
@preconcurrency import CoreBluetooth

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

enum BLEError: Int {
    case notFound = 1001        // 未发现设备
    case ssTokenFail = 1006
    case responseTimeout = 1007
    case unsupportedToken = 1008   // 2026-10-28 补：APK bleCodeMsg[1008]「不支持的ssToken方式」
    case connectTimeout = 2003
    case parseFail = 5001
    case linkNotReady = 5002     // 2026-10-30：写通道未就绪（device/writeChar 为空）—— 原来误报成 parseFail
    case writeTimeout = 6001
    case underlying = 6004
    case writeFailed = 6005

    var message: String {
        switch self {
        case .notFound: return "未发现门锁，请靠近门锁重试"
        case .ssTokenFail: return "获取ssToken失败"
        case .responseTimeout: return "超时未收到返回数据"
        case .unsupportedToken: return "不支持的ssToken方式"
        case .connectTimeout: return "连接设备超时"
        case .parseFail: return "解析数据失败"
        case .linkNotReady: return "门锁连接未就绪，请断开后重连"
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

