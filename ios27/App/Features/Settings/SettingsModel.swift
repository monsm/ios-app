// SettingsModel.swift —— 设置域的本机偏好与可替换数据模型。
//
// 这个域干什么：把「外观 / 安全 / 备份 / 靠近自动开锁 / 硬件 / 关于」的本机偏好收在一处，
// 供 7 个页面共用 —— 页面只读写这里，不各存一份 @State 副本（否则同一个开关在两页会显示两个值）。
// 数据从哪来：本文件是**可替换模型**；真实现由 Store/Engine 落盘（UserDefaults + SecretStore + 硬件台账）。
// 主动作：本文件不含交互；每个开关在对应页面里改这里的属性，改完立刻回读到 FieldRow 读数上。
//
// 诚实：标 TODO(engine) 的字段本版只在本机内存里成立（重进 App 回默认值），界面不假装已落盘。
import SwiftUI

// MARK: - 外观档位

/// 主题。只有三档：跟随系统 / 浅色 / 深色 —— 深色不是浅色的反相（两套独立取值）。
enum AppearanceTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

/// 布局密度。只缩放间距节奏，字号与 44pt 触达不动。
enum LayoutDensity: String, CaseIterable, Identifiable {
    case compact
    case standard
    case relaxed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return "紧凑"
        case .standard: return "标准"
        case .relaxed: return "宽松"
        }
    }
}

/// 动效强度。克制档取消数字滚动与逐格点亮；进度弧保留（它是信息，不是装饰）。
enum MotionTier: String, CaseIterable, Identifiable {
    case calm
    case standard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calm: return "克制"
        case .standard: return "标准"
        }
    }
}

/// 时间制式。这是时间线 / 详情 / 导出的**唯一**出口，页面不许各自覆盖。
enum TimeDisplayStyle: String, CaseIterable, Identifiable {
    case system
    case h24
    case h12

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .h24: return "24 小时"
        case .h12: return "12 小时"
        }
    }
}

/// 靠近自动开锁的确认档。两档：免额外验证 / 严格每次必刷面容。
enum FaceConfirmTier: String, CaseIterable, Identifiable {
    case free
    case strict

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: return "免额外验证"
        case .strict: return "严格每次必刷"
        }
    }

    var note: String {
        switch self {
        case .free: return "走到门前直接开，最快；适合一个人住、门内无人的场景。"
        case .strict: return "每次先刷面容再开；门口有人经过也不会替你开门。"
        }
    }
}

// MARK: - 蓝牙钥匙串台账（data.hardware: kf_keychain_dongles）

/// 一台蓝牙钥匙串（ZKBBV1）。读数来自 cmd43（电量 / 钥匙数 / 固件）。
struct DongleRecord: Identifiable, Hashable {
    let id: String
    let name: String
    /// 显示序 MAC（协议层字节序已归一）。
    let mac: String
    let battery: Int
    let keys: Int
    let firmware: String
    /// 本机这把锁的钥匙是否已写进硬件（cmd41 回执后置真）。
    let holdsThisLock: Bool

    /// 示例台账 —— TODO(engine) 真实现读 kf_keychain_dongles（按 mac 索引、空字段不覆盖旧值）。
    static let sample: [DongleRecord] = [
        DongleRecord(id: "d1", name: "随身钥匙串", mac: "C4:2B:1A:00:11:22",
                     battery: 82, keys: 2, firmware: "2.0.1", holdsThisLock: true)
    ]

    /// 扫描"发现"的一台（TODO(engine) 结果应来自 BLE 扫描，只认 pid 16289 且广播带 MAC）。
    static let discovered = DongleRecord(id: "d2", name: "新钥匙串", mac: "C4:2B:1A:00:33:44",
                                        battery: 100, keys: 0, firmware: "2.0.1", holdsThisLock: false)
}

// MARK: - 本机偏好

/// 设置域的本机偏好。本机生效、不上传、不写进锁。
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    // MARK: 外观
    var theme: AppearanceTheme = .system            // TODO(engine) 生效需 Design 令牌按档重建
    var density: LayoutDensity = .standard          // TODO(engine) 同上（只缩放间距）
    var motion: MotionTier = .standard              // TODO(engine) 同上
    var highContrast = false                        // TODO(engine) 与系统「增加对比度」并联
    var reduceTransparency = false                  // TODO(engine) 玻璃退化由系统材质层承担
    var timeStyle: TimeDisplayStyle = .system       // TODO(engine) TimeFormat 需读它（现在是常量格式）
    var showSeconds = false                         // TODO(engine) 只在日志原文真带秒时显示，缺位不补 :00
    var twoLineDate = false                         // TODO(engine) 台账行第二行完整日期

    // MARK: 安全
    var hasPasscode = false                         // TODO(engine) 摘要落 SecretStore（PBKDF2-HMAC-SHA256）
    var hasDuressCode = false                       // TODO(engine) 胁迫码空壳模式未接

    // MARK: 开锁确认（防误触）
    var holdConfirm = true                          // 按住确认开锁；关掉后退回轻点直开
    var autoRetry = true                            // 开锁失败后自动重试一次

    // MARK: 备份
    var encryptBackup = false
    var lastBackupAt: Int64? = nil                  // TODO(engine) 上次成功备份时刻（kf_backup_hist）

    // MARK: 靠近自动开锁
    var autoOpenEnabled = false                     // 默认关（fail-closed）
    var faceConfirm: FaceConfirmTier = .free
    var calibrationAt: Int64? = nil                 // TODO(engine) 距离标定要真采 RSSI 门槛
    var lastSkipReason: String? = nil               // TODO(engine) 上次没自动开的原因由 core-auto 记账

    // MARK: 硬件
    var dongles: [DongleRecord] = DongleRecord.sample
    var lastScanAt: Int64? = nil

    // MARK: 锁端时钟
    /// 上次校准门锁时间的时刻。nil = 从未校准。TODO(engine) 真实现读 cmd0E 回执后写本机。
    var lockClockSyncedAt: Int64? = nil

    // MARK: 累计
    /// 累计开锁次数（机械计数器）。TODO(engine) 真实现读 Milestones.unlockTotal。
    var unlockTotal = 1284

    /// 恢复默认外观：只重置外观偏好，不动安全 / 备份 / 硬件，也不动任何门锁数据。
    func resetAppearance() {
        theme = .system
        density = .standard
        motion = .standard
        highContrast = false
        reduceTransparency = false
        timeStyle = .system
        showSeconds = false
        twoLineDate = false
    }
}

// MARK: - 只读事实（版本 / 构建）

/// 关于页要的两个事实。取不到时给可读的兜底，不显示 "?"。
enum SettingsFacts {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
