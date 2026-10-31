// SettingsModel.swift —— 设置域的本机偏好与可替换数据模型。
//
// 这个域干什么：把「外观 / 安全 / 备份 / 靠近自动开锁 / 硬件 / 关于」的本机偏好收在一处，
// 供 7 个页面共用 —— 页面只读写这里，不各存一份 @State 副本（否则同一个开关在两页会显示两个值）。
// 数据从哪来：本文件是**可替换模型**；真实现由 Store/Engine 落盘（UserDefaults + SecretStore + 硬件台账）。
// 主动作：本文件不含交互；每个开关在对应页面里改这里的属性，改完立刻回读到 FieldRow 读数上。
//
// 诚实：标 TODO(engine) 的字段本版只在本机内存里成立（重进 App 回默认值），界面不假装已落盘。
import SwiftUI
import UIKit

// MARK: - 外观档位

/// 主题。只有三档：跟随系统 / 浅色 / 深色 —— 深色不是浅色的反相（两套独立取值）。
enum AppearanceTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    /// 纯黑（AMOLED）：深色底再压到 #000，夜间与 OLED 省电档。
    case black

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        case .black: return "纯黑"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark, .black: return .dark
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
    /// 活泼档：结果态允许一次轻微弹跳（进度弧仍走线性，不拿弹簧骗人）。
    case lively

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calm: return "克制"
        case .standard: return "标准"
        case .lively: return "活泼"
        }
    }

    var resultAnimation: Animation? {
        switch self {
        case .calm: return nil
        case .standard: return V.M.snap
        case .lively: return V.M.settle
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

    /// 观察代次：@Observable 不能给带 didSet 的存储属性做追踪（宏会把属性改成计算属性），
    /// 所以这里用「计算属性 + revision」这一等价写法：setter 写库并 ++，getter 读它建立观察依赖。
    private var revision = 0

    // MARK: 外观（全部落盘：kf_theme / kf_density / …）

    var theme: AppearanceTheme {
        get { _ = revision; return AppearanceTheme(rawValue: DB.store.getString("kf_theme")) ?? .system }
        set { DB.store.set("kf_theme", newValue.rawValue); revision &+= 1 }
    }

    var density: LayoutDensity {
        get { _ = revision; return LayoutDensity(rawValue: DB.store.getString("kf_density")) ?? .standard }
        set { DB.store.set("kf_density", newValue.rawValue); revision &+= 1 }
    }

    var motion: MotionTier {
        get { _ = revision; return MotionTier(rawValue: DB.store.getString("kf_motion")) ?? .standard }
        set { DB.store.set("kf_motion", newValue.rawValue); revision &+= 1 }
    }

    var highContrast: Bool {
        get { _ = revision; return DB.store.getBool("kf_hc") }
        set { DB.store.set("kf_hc", newValue); revision &+= 1 }
    }

    var reduceTransparency: Bool {
        get { _ = revision; return DB.store.getBool("kf_reduce_trans") }
        set { DB.store.set("kf_reduce_trans", newValue); revision &+= 1 }
    }

    var timeStyle: TimeDisplayStyle {
        get { _ = revision; return TimeDisplayStyle(rawValue: DB.store.getString("kf_time_style")) ?? .system }
        set { DB.store.set("kf_time_style", newValue.rawValue); revision &+= 1 }
    }

    var showSeconds: Bool {
        get { _ = revision; return DB.store.getBool("kf_show_seconds") }
        set { DB.store.set("kf_show_seconds", newValue); revision &+= 1 }
    }

    var twoLineDate: Bool {
        get { _ = revision; return DB.store.getBool("kf_two_line_date") }
        set { DB.store.set("kf_two_line_date", newValue); revision &+= 1 }
    }

    // MARK: 安全（唯一真值在 DB 的 kf_passcode / kf_duress）

    /// 生物识别解锁开关（有胁迫码时 LockGate 自动不提供）。
    var bioUnlock: Bool {
        get { _ = revision; return DB.store.getBool("kf_bio_unlock", true) }
        set { DB.store.set("kf_bio_unlock", newValue); revision &+= 1 }
    }

    var hasPasscode: Bool { _ = revision; return DB.hasPasscode() }
    var hasDuressCode: Bool { _ = revision; return DB.hasDuressCode() }

    // MARK: 开锁确认（防误触）

    var holdConfirm: Bool {
        get { _ = revision; return DB.store.getBool("kf_hold_confirm", true) }
        set { DB.store.set("kf_hold_confirm", newValue); revision &+= 1 }
    }

    var autoRetry: Bool {
        get { _ = revision; return DB.store.getBool("kf_auto_retry", true) }
        set { DB.store.set("kf_auto_retry", newValue); revision &+= 1 }
    }

    // MARK: 备份

    var encryptBackup: Bool {
        get { _ = revision; return DB.store.getBool("kf_encrypt_backup") }
        set { DB.store.set("kf_encrypt_backup", newValue); revision &+= 1 }
    }

    /// 上次成功备份时刻（kf_backup_hist，Milestones 唯一真值）。
    var lastBackupAt: Int64? {
        _ = revision
        return Milestones.lastBackupAt.map { Int64($0.timeIntervalSince1970 * 1000) }
    }

    // MARK: 靠近自动开锁

    var autoOpenEnabled: Bool {
        get { _ = revision; return DB.store.getBool("kf_autoopen") }
        set { DB.store.set("kf_autoopen", newValue); revision &+= 1 }
    }

    var faceConfirm: FaceConfirmTier {
        get { _ = revision; return DB.store.getInt("kf_autoopen_face", 0) == 1 ? .strict : .free }
        set { DB.store.setInt("kf_autoopen_face", newValue == .strict ? 1 : 0); revision &+= 1 }
    }

    var calibrationAt: Int64? = nil                 // TODO(engine) 距离标定要真采 RSSI 门槛
    var lastSkipReason: String? = nil               // TODO(engine) 上次没自动开的原因由 core-auto 记账

    // MARK: 硬件

    /// 钥匙串台账：直接读 Engine 的 kf_keychain_dongles（空字段回落"未知"，不编造读数）。
    var dongles: [DongleRecord] {
        _ = revision
        return DB.dongles().map { d in
            DongleRecord(id: d.mac,
                         name: d.name.isEmpty ? "钥匙串 \(String(d.mac.prefix(4)))" : d.name,
                         mac: d.mac,
                         battery: d.stat?.power ?? -1,
                         keys: d.stat?.ekeyCount ?? 0,
                         firmware: d.stat?.firmware ?? "—",
                         holdsThisLock: !d.lastKeyLock.isEmpty)
        }
    }

    var lastScanAt: Int64? = nil

    // MARK: 无障碍（大字档位参与 RootView 的 dynamicTypeSize）

    var axBigText: Bool {
        get { _ = revision; return DB.store.getBool("kf_ax_bigtext") }
        set { DB.store.set("kf_ax_bigtext", newValue); revision &+= 1 }
    }

    // MARK: 快捷格（首页快捷操作 10 选 N；与 QuickPool 的选中集合同一份存储）

    var quickGridCount: Int {
        get { _ = revision; return DB.store.getInt("kf_quick_grid", 6) }
        set { DB.store.set("kf_quick_grid", newValue); revision &+= 1 }
    }

    // MARK: 外观 13 项（AUDIT-A §5 #28-#33 的真实写点与读点）

    /// 品牌色六套（kf_accent）。空 = indigo。
    var accent: String {
        get { _ = revision; return DB.store.getString("kf_accent") }
        set { DB.store.set("kf_accent", newValue); revision &+= 1 }
    }

    /// 自定义强调色（kf_accent_custom，0xRRGGBB；0 = 未启用）。
    var customAccent: Int {
        get { _ = revision; return DB.store.getInt("kf_accent_custom", 0) }
        set { DB.store.set("kf_accent_custom", newValue); revision &+= 1 }
    }

    var radius: String {
        get { _ = revision; return DB.store.getString("kf_radius") }
        set { DB.store.set("kf_radius", newValue); revision &+= 1 }
    }

    var rowHeight: String {
        get { _ = revision; return DB.store.getString("kf_row_h") }
        set { DB.store.set("kf_row_h", newValue); revision &+= 1 }
    }

    var timelineGap: String {
        get { _ = revision; return DB.store.getString("kf_tl_gap") }
        set { DB.store.set("kf_tl_gap", newValue); revision &+= 1 }
    }

    var digitFont: String {
        get { _ = revision; return DB.store.getString("kf_digit_font") }
        set { DB.store.set("kf_digit_font", newValue); revision &+= 1 }
    }

    var recentCount: Int {
        get { _ = revision; return DB.store.getInt("kf_recent_count", 5) }
        set { DB.store.set("kf_recent_count", newValue); revision &+= 1 }
    }

    /// 记录页开场策略（kf_filter_default，QueryFilters.policy 的唯一 UI 写点）。
    var recordPolicy: String {
        get { _ = revision; return QueryFilters.policy }
        set { QueryFilters.setPolicy(newValue); revision &+= 1 }
    }

    /// 开锁确认：长按时长（秒，0.4–1.6）。
    var holdDuration: Double {
        get { _ = revision; return min(1.6, max(0.4, DB.store.getDouble("kf_ax_hold", 0.9))) }
        set { DB.store.set("kf_ax_hold", min(1.6, max(0.4, newValue))); revision &+= 1 }
    }

    /// 双击直开（kf_tap_direct）：按住档下双击绕过按住确认。
    var tapDirect: Bool {
        get { _ = revision; return DB.store.getBool("kf_tap_direct") }
        set { DB.store.set("kf_tap_direct", newValue); revision &+= 1 }
    }

    /// 误触围栏（kf_fence）：先从边缘拖到中心解锁围栏。
    var fence: Bool {
        get { _ = revision; return DB.store.getBool("kf_fence") }
        set { DB.store.set("kf_fence", newValue); revision &+= 1 }
    }

    /// 双击防抖（kf_dbltap_guard，默认开）。
    var dbltapGuard: Bool {
        get { _ = revision; return DB.store.getBool("kf_dbltap_guard", true) }
        set { DB.store.set("kf_dbltap_guard", newValue); revision &+= 1 }
    }

    /// 夜间免扰（kf_quiet_night）：22:00–08:00 静音提示音。
    var quietNight: Bool {
        get { _ = revision; return CareSchedule.quietOn }
        set { DB.store.set("kf_quiet_night", newValue); revision &+= 1 }
    }

    /// 强调色解析：自定义色优先，其次六套预设。
    var accentColor: Color {
        _ = revision
        if customAccent != 0 { return Self.color(hex: customAccent) }
        switch accent {
        case "forest": return Self.color(hex: 0x1D6F5F)
        case "amber": return Self.color(hex: 0xB45309)
        case "graphite": return Self.color(hex: 0x5B6169)
        case "rose": return Self.color(hex: 0xBE123C)
        case "aurora": return Self.color(hex: 0x0E7490)
        default: return Self.color(hex: 0x4F46E5)
        }
    }

    static func color(hex: Int) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }

    /// 把 ColorPicker 的 Color 存成 0xRRGGBB（不做透明度；强调色必须压得住白字）。
    func setCustomAccent(_ color: Color) {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        customAccent = (Int((r * 255).rounded()) << 16) | (Int((g * 255).rounded()) << 8) | Int((b * 255).rounded())
    }

    func clearCustomAccent() { customAccent = 0 }

    // MARK: 锁端时钟

    /// 上次校准门锁时间的时刻。nil = 从未校准。
    var lockClockSyncedAt: Int64? = nil

    // MARK: 累计

    /// 累计开锁次数（机械计数器）。真实现读 Milestones 的持久计数。
    var unlockTotal: Int { Milestones.unlockTotal }

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
        accent = ""
        customAccent = 0
        radius = ""
        rowHeight = ""
        timelineGap = ""
        digitFont = ""
        recentCount = 5
        recordPolicy = ""
        holdDuration = 0.9
        tapDirect = false
        fence = false
        dbltapGuard = true
        quietNight = true
        HeroStats.setVisible(HeroStats.all)
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
