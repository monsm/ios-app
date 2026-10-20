// 协议命令的**唯一安全分类表** —— 每一条会上链的 cmd 都必须在这里登记一次。
//
// 为什么要有这张表:
//   296「只读安全模式」此前只有 7 个界面调用点 (开锁 / 销毁 / 导入导出), 而凭证写入、配网、DFU
//   三族一个守卫都没有 —— 开关关着照样能写密码、换钥、刷固件。根因不是"漏了三个 if", 是
//   **命令本身没有一处能回答'它算哪类动作'**。判据分散在 40 个构造器与上百个调用点里, 谁都可以忘。
//
// 现在的形状:
//   cmd → LockCommand.policy (nil = 只读) → SecurityPolicy 判定。
//   `request` / `send` 是 iOS 侧仅有的两条上链入口, 闸就装在那里; 新增命令若不在本表,
//   会在发包前被拒 (fail-closed), 而不是悄悄绕过只读模式。
//
// 与 `ZKProtocol.assertReadOnly` 的关系: 那一条是**只读试验模式** (kf_trial_guard, 厂商 JS 语义,
// 放行白名单), 与本表的用户级「只读安全模式」(kf.safe_mode) 是两个开关, 互不替代。
// 两者都在 request 里, 先判本表 (用户级), 再判试验模式 (开发者级)。
import Foundation

enum LockCommand: UInt8, CaseIterable {
    // ---- 只读面 (policy = nil) ----
    case session        = 0x01   // 01 会话令牌
    case status         = 0x03   // 03 状态 (明文/加密共用)
    case echo           = 0x12   // 12 回声探测
    case logs           = 0x16   // 16 读日志
    case gatewayName    = 0x30   // 30 网关名称 (读)
    case gatewayStatus  = 0x38   // 38 网关状态
    case keychainStatus = 0x43   // 43 钥匙串状态
    case keychainKeys   = 0x44   // 44 钥匙串查钥

    // ---- 开锁 ----
    case unlock         = 0x04   // 04 开锁

    // ---- 配网 / 换钥 ----
    case exKeyWay       = 0x23   // 23 交换方式
    case exchangeKey    = 0x05   // 05 换钥
    case syncPins       = 0x08   // 08 PIN 池
    case setBkey        = 0x21   // 21 bkey
    case gatewayWifi    = 0x31   // 31 网关 WiFi
    case gatewayIot     = 0x32   // 32 网关 IoT 密钥

    // ---- 凭证写入 ----
    case syncPwd        = 0x0A   // 0A 同步密码 (增/删/改)
    case syncPwdExpire  = 0x0B   // 0B 密码有效期
    case addFp          = 0x13   // 13 录指纹
    case confirmFp      = 0x14   // 14 确认指纹
    case deleteFp       = 0x15   // 15 删指纹
    case openZotp       = 0x19   // 19 临时密码开关
    case keychainWrite  = 0x41   // 41 钥匙串写 ekey

    // ---- 锁端运行参数 ----
    case syncTime       = 0x0E   // 0E 校时
    case volume         = 0x18   // 18 音量
    case validationMode = 0x20   // 20 单双验
    case autoLock       = 0x24   // 24 自动上锁
    case defence        = 0x25   // 25 布防
    case gatewayReboot  = 0x35   // 35 网关重启

    // ---- 固件 ----
    case enableDfu      = 0x22   // 22 进入升级模式

    /// nil = 只读 (不触发任何安全闸); 非 nil = 写类, 必须过 SecurityPolicy。
    var policy: LockAction? {
        switch self {
        case .session, .status, .echo, .logs,
             .gatewayName, .gatewayStatus, .keychainStatus, .keychainKeys:
            return nil
        case .unlock:
            return .unlock
        case .exKeyWay, .exchangeKey, .syncPins, .setBkey, .gatewayWifi, .gatewayIot:
            return .provision
        case .syncPwd, .syncPwdExpire, .addFp, .confirmFp, .deleteFp, .openZotp, .keychainWrite:
            return .writeCredential
        case .syncTime, .volume, .validationMode, .autoLock, .defence, .gatewayReboot:
            return .configure
        case .enableDfu:
            return .dfu
        }
    }

    /// 人话名字 (只用于日志/拒因, 不复用 ZKCmd.name —— 那张表在构造器里, 未成帧时拿不到)
    var label: String {
        switch self {
        case .session: return "01 会话令牌"
        case .status: return "03 状态"
        case .echo: return "12 回声"
        case .logs: return "16 读日志"
        case .gatewayName: return "30 网关名称"
        case .gatewayStatus: return "38 网关状态"
        case .keychainStatus: return "43 钥匙串状态"
        case .keychainKeys: return "44 钥匙串查钥"
        case .unlock: return "04 开锁"
        case .exKeyWay: return "23 交换方式"
        case .exchangeKey: return "05 换钥"
        case .syncPins: return "08 PIN 池"
        case .setBkey: return "21 bkey"
        case .gatewayWifi: return "31 网关 WiFi"
        case .gatewayIot: return "32 网关 IoT"
        case .syncPwd: return "0A 同步密码"
        case .syncPwdExpire: return "0B 密码有效期"
        case .addFp: return "13 录指纹"
        case .confirmFp: return "14 确认指纹"
        case .deleteFp: return "15 删指纹"
        case .openZotp: return "19 临时密码"
        case .keychainWrite: return "41 钥匙串写钥"
        case .syncTime: return "0E 校时"
        case .volume: return "18 音量"
        case .validationMode: return "20 单双验"
        case .autoLock: return "24 自动上锁"
        case .defence: return "25 布防"
        case .gatewayReboot: return "35 网关重启"
        case .enableDfu: return "22 进入升级"
        }
    }

    /// 上链前的唯一判据。未登记的命令一律拒绝 —— 新命令必须先在表里交代它属于哪一族。
    static func requireAllowed(_ raw: UInt8) throws {
        guard let c = LockCommand(rawValue: raw) else {
            throw BLEErrorX.msg(String(format: "命令 0x%02x 未在 LockCommand 安全表登记, 已拒绝下发 (新增命令请先声明动作族)", raw))
        }
        guard let action = c.policy else { return }
        guard SecurityPolicy.allows(action) else {
            throw BLEErrorX.msg("\(c.label): \(SecurityPolicy.denialMessage(action))")
        }
    }
}
