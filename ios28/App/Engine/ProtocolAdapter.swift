// ProtocolAdapter.swift —— 协议变体与传输的统一接口（B16）。
//
// 协议层现在有三种帧头（8B / 10B / 7B）与四种传输（门锁 NUS / 网关 FE90 /
// DFU Secure / DFU Legacy）。它们散在命令构造器与 BLE 委托里：
// 换一个帧头要翻十几个 `header: 8`，换一条传输要改 BLE 委托里的三元判断。
//
// 现在收成一层：
//   · **帧变体**只在 `FrameVariant` 里登记，命令构造器问注册表要头长；
//   · **传输**只在 `TransportKind` 里登记，BLE 委托问它要服务/写/通知三个 UUID。
// 上层代码不再出现字面量帧头，也不再出现 UUID 三元判断。
import Foundation

// MARK: - 帧变体

enum FrameVariant: Int {
    /// 8 字节头：Java 生产链（本仓的默认口径，也是金标烘焙用的口径）。
    case standard8 = 8
    /// 10 字节头：旧 JS 格式，头里带 2 字节令牌位。
    case token10 = 10
    /// 7 字节头：精简头（回包解析里的兼容变体）。
    case compat7 = 7

    var headerBytes: Int { rawValue }

    /// 这一变体的帧头里是否带令牌位。
    var carriesTokenSlot: Bool { self == .token10 }

    var label: String {
        switch self {
        case .standard8: return "8B 标准"
        case .token10: return "10B 带令牌"
        case .compat7: return "7B 精简"
        }
    }
}

// MARK: - 传输

enum TransportKind: String {
    case lockNUS
    case gatewayFE90
    case dfuSecure
    case dfuLegacy

    /// 服务 UUID（引用 BLEUUID —— UUID 只有那一份，不在这里复写字符串）。
    var serviceUUID: CBUUID {
        switch self {
        case .lockNUS: return BLEUUID.svcMain
        case .gatewayFE90: return BLEUUID.svcGW
        case .dfuSecure: return BLEUUID.svcDfuSecure
        case .dfuLegacy: return BLEUUID.svcDfuLegacy
        }
    }

    var writeUUID: CBUUID {
        switch self {
        case .lockNUS: return BLEUUID.chrWrite
        case .gatewayFE90: return BLEUUID.chrGWWrite
        case .dfuSecure: return BLEUUID.dfuSecureControl
        case .dfuLegacy: return BLEUUID.dfuLegacyControl
        }
    }

    var notifyUUID: CBUUID {
        switch self {
        case .lockNUS: return BLEUUID.chrNotify
        case .gatewayFE90: return BLEUUID.chrGWNotify
        case .dfuSecure: return BLEUUID.dfuSecurePacket
        case .dfuLegacy: return BLEUUID.dfuLegacyPacket
        }
    }

    var label: String {
        switch self {
        case .lockNUS: return "门锁"
        case .gatewayFE90: return "网关"
        case .dfuSecure: return "固件升级（安全通道）"
        case .dfuLegacy: return "固件升级（旧通道）"
        }
    }

    /// 按服务 UUID 反查传输类型。
    static func of(serviceUUID: CBUUID) -> TransportKind? {
        switch serviceUUID {
        case BLEUUID.svcMain: return .lockNUS
        case BLEUUID.svcGW: return .gatewayFE90
        case BLEUUID.svcDfuSecure: return .dfuSecure
        case BLEUUID.svcDfuLegacy: return .dfuLegacy
        default: return nil
        }
    }
}

// MARK: - 适配器

/// 一条「命令 + 帧变体」的构造与解析适配器。
///
/// 变体只影响**帧头**；KLV 载荷与命令构造器无关，仍由 `ZKCmdBuilder` 负责。
struct FrameAdapter {
    var variant: FrameVariant = .standard8

    func build(cmd: UInt8, klvHex: String, ssToken: String = "0000") -> String {
        ZKProtocol.buildFrame(cmd, klvHex, ssToken: ssToken, header: variant.headerBytes)
    }

    /// 解析回包。三种头型都会试（协议无校验和，只能靠结构判断）。
    func parse(_ hex: String) -> ZKProtocol.ParsedFrame {
        ZKProtocol.parseResponse(hex)
    }
}

// MARK: - 注册表

enum ProtocolRegistry {
    /// 命令 → 帧变体。默认 8B；个别命令历史上用 10B 的在这里登记。
    private static var variants: [UInt8: FrameVariant] = [:]

    /// 某条命令用哪种帧变体。
    static func variant(for cmd: UInt8) -> FrameVariant {
        variants[cmd] ?? .standard8
    }

    /// 某条命令的帧头长度（字节）。
    static func header(for cmd: UInt8) -> Int {
        variant(for: cmd).headerBytes
    }

    /// 注册一条命令的帧变体。新变体只在这里加一行。
    static func register(cmd: UInt8, variant: FrameVariant) {
        variants[cmd] = variant
    }

    /// 已登记的命令（诊断页用；空表是正常的 —— 默认 8B 不必登记）。
    static func registeredVariants() -> [UInt8: FrameVariant] { variants }

    /// 某条命令走哪条传输。锁与网关的命令走各自的服务，其余（DFU、钥匙串）走 NUS。
    static func transport(for cmd: UInt8) -> TransportKind {
        switch cmd {
        case 0x30, 0x31, 0x32, 0x35, 0x38: return .gatewayFE90
        default: return .lockNUS
        }
    }
}
