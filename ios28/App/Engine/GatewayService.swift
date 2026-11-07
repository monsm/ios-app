// GatewayService.swift —— 网关能力的一层抽象（B20）与请求合并。
//
// 网关命令（cmd30 名称 / cmd31 配网 / cmd32 IoT / cmd35 重启 / cmd38 状态）原先
// 散在 `HardwareService` 的几个私有方法里，界面上「这个网关支持什么」只能靠
// 一个个按钮试。cmd30/32 是厂商云能力，本 App 不提供 —— 以前只是「没有按钮」，
// 现在是**明确的一格「不支持」**并写清原因。
//
// 顺带做**请求合并**：同一把网关/同一把锁在几秒内被连读两次状态时，
// 第二次直接复用第一次的结果 —— BLE 链路一次只挂得下一个 waiter，
// 两次并发读必然有一个超时。
import Foundation

enum GatewayCapability: String, CaseIterable {
    case status      // cmd38 读状态
    case wifi        // cmd31 配 WiFi
    case reboot      // cmd35 重启
    case name        // cmd30 读名称
    case iot         // cmd32 写 IoT 凭据

    var title: String {
        switch self {
        case .status: return "读状态"
        case .wifi: return "配 WiFi"
        case .reboot: return "重启"
        case .name: return "读名称"
        case .iot: return "写 IoT 凭据"
        }
    }

    /// 本 App 支持吗？不支持的说清原因 —— 不做「藏起来当没有」。
    var isSupported: Bool {
        switch self {
        case .status, .wifi, .reboot: return true
        case .name: return true
        case .iot: return false
        }
    }

    var unsupportedReason: String? {
        switch self {
        case .iot: return "这是厂商云端的能力，需要厂商账号。本 App 完全离线，不提供。"
        default: return nil
        }
    }

    var command: UInt8 {
        switch self {
        case .status: return 0x38
        case .wifi: return 0x31
        case .reboot: return 0x35
        case .name: return 0x30
        case .iot: return 0x32
        }
    }
}

enum GatewayService {
    /// 网关支持的能力表（按型号过滤后的结果）。
    static func capabilities(pid: Int) -> [GatewayCapability] {
        GatewayCapability.allCases.filter { cap in
            guard cap.isSupported else { return false }
            // 网关型号白名单与 PidMap 同源；未知型号按宽松档（与锁的 canDefend 同口径）。
            if pid != 0 && !PidMap.gws.contains(pid) { return cap == .status }
            return true
        }
    }

    /// 不支持的能力（界面上要**如实显示**，而不是藏起来）。
    static func unsupported(pid: Int) -> [GatewayCapability] {
        GatewayCapability.allCases.filter { !$0.isSupported }
    }
}

// MARK: - 请求合并

/// 同键请求合并：同一时刻的同键请求**共用一次**真实动作。
///
/// 用在「读状态」「读日志」这类纯读命令上 —— 用户在两个页面各点一次，
/// 不该产生两次 BLE 往返。
actor RequestCoalescer {
    static let shared = RequestCoalescer()

    /// 键 → 进行中的任务。
    private var inFlight: [String: Task<Any, Never>] = [:]

    /// 合并执行。同一键的并发调用拿到**同一个结果**。
    func run<T: Sendable>(_ key: String, _ body: @escaping @Sendable () async -> T) async -> T {
        if let existing = inFlight[key] {
            guard let value = await existing.value as? T else {
                // 类型对不上（不该发生）—— 退回自己跑一次。
                return await body()
            }
            return value
        }
        let task = Task<T, Never> { await body() }
        inFlight[key] = Task<Any, Never> { await task.value }
        let value = await task.value
        inFlight[key] = nil
        return value
    }
}
