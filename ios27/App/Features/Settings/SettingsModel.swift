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

    /// 2026-11-04（走查发现 · 假选项）：`.black` 的 `colorScheme` 与 `.dark` 完全一样，
    /// 而**深色档的页面底本来就是纯黑**（`V.C.bg = dual(0xF2F2EF, 0x000000)`，见 V7Tokens）。
    /// 也就是说「纯黑（AMOLED）」和「深色」是同一个外观 —— 设置里却摆成两个选项，
    /// 用户以为换了个更省电的档，实际什么也没变。
    /// 处置：**不再作为可选档展示**（`selectable` 不含它），但保留 case 以便旧值 `kf_theme=black`
    /// 仍能解码成深色（删掉 case 会让旧用户回落到「跟随系统」——那是更差的行为）。
    static var selectable: [AppearanceTheme] { [.system, .light, .dark] }
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

    /// 开锁成功后的结果动画。
    ///
    /// 2026-11-01：这个映射此前**零调用**，而且取值与真正的消费点（`LockKeeperApp` 里那段嵌套三元）
    /// **已经漂了** —— 这里 standard 给 `.snap`，线上给 `.move`。
    /// 现在把它对齐到线上实际行为，并让 `LockKeeperApp` 改为调用它：
    /// 一来映射只有一处，二来消掉了那段「枚举用嵌套三元」的写法（本仓纪律要求用 `switch`）。
    var resultAnimation: Animation? {
        switch self {
        case .calm: return nil
        case .standard: return V.M.move
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

    // 2026-11-04（清理 · 死示例数据）：这里原有 `sample` / `discovered` 两条**假钥匙串**，
    // 注释说「TODO(engine) 真实现读 kf_keychain_dongles」—— 而 `DB.dongles()` 早就实现了。
    // 两条**全仓零引用**，却带着假的电量 82 / 固件 2.0.1：一旦有人拿它做预览或空态示例，
    // 用户会看到一台不存在的设备。删掉；真数据走 `SettingsStore.dongles`。
}

// MARK: - 本机偏好

/// 设置域的本机偏好。本机生效、不上传、不写进锁。
/// @MainActor：全仓 8 个 @Observable 里最后一个补上的（E-04）。它被 20+ 视图从主线程读写，
/// 不标就没有编译期保证；切 Swift 6 语言模式时 static let shared 的非 Sendable 可变状态即报错。
@MainActor
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
        get { _ = revision; return Self.densityFromStore }
        set { DB.store.set("kf_density", newValue.rawValue); revision &+= 1 }
    }

    /// **nonisolated** 直读版本：给 `V.S` 这类非隔离的布局令牌用。
    /// 为什么需要它：`V.S.gapM` 在 `body`、`init`、非隔离 `static let` 里都会被求值，
    /// 而那些位置拿不到 MainActor。直接把 `SettingsStore.shared.density` 写进令牌会报
    /// "main actor-isolated property can not be referenced from a nonisolated context"（CI 实测）。
    /// 这里只读 UserDefaults（线程安全），不碰 `revision`，所以可以 nonisolated。
    /// 重绘仍由视图侧的 `settings.density` 读法驱动（见 AppearanceScreen 的 binding）。
    nonisolated static var densityFromStore: LayoutDensity {
        LayoutDensity(rawValue: DB.store.getString("kf_density")) ?? .standard
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

    /// 外部路径（备份恢复 / 迁移 / 重置）**直接写过底层存储**之后调用它，
    /// 让所有观察 `SettingsStore` 的视图重新取数。
    ///
    /// 2026-11-01（Round 255）：恢复路径直接写了一批可观察键（手势档 / 按住确认 / 大字 / 表盘尺寸…），
    /// 却从不 bump `revision` —— 恢复完成后设置页仍显示旧值，要等 App 重启才对。
    /// 直写存储只允许出现在这类非界面路径，但**必须**在这里补一次通知。
    func notifyChanged() { revision &+= 1 }

    // MARK: 开锁确认（防误触）

    var autoRetry: Bool {
        get { _ = revision; return DB.store.getBool("kf_auto_retry", true) }
        set { DB.store.set("kf_auto_retry", newValue); revision &+= 1 }
    }

    /// 开锁手势档：`hold` / `tap` / `double`（`kf_gesture_mode`）。
    ///
    /// 2026-11-01（Round 254）：门页 `effectiveGesture` 原来直接读 `AXSettings.gestureMode`（**静态 DB 读**），
    /// 而 `@Observable` 只跟踪这里 —— 于是无障碍页改档后门页**不会重算**，要等下一次别的原因刷新才生效。
    /// 收进 `SettingsStore` 后，改档即 bump `revision`，门页立刻跟上。
    var gestureMode: String {
        get { _ = revision; return DB.store.getString("kf_gesture_mode", "hold") }
        set { DB.store.set("kf_gesture_mode", newValue); revision &+= 1 }
    }

    // MARK: 备份

    // 2026-11-04（清理 · 假开关的遗骸）：`encryptBackup` 曾经驱动「加密备份」开关，
    // 那个开关在 2026-11-03 被删除（加密是唯一路径，见 `BackupScreen.exportPanel` 的注释）——
    // 但属性与它写的 `kf_encrypt_backup` 键留了下来，全仓零读取。
    // 保留它比删掉更危险：下一个做备份页的人会以为"加密是可选项"，从而重新引入明文路径。

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

    // 2026-11-04（走查发现 · 过时 TODO）：这两行原本各挂一条 `TODO(engine)`，说
    // 「距离标定要真采 RSSI 门槛」「上次没自动开的原因由 core-auto 记账」—— **两条都不成立**：
    // `AutoOpen.saveAutocal` 已按 5 次 RSSI 采样真算门槛、`AutoOpen.lastReject` 已记拒因，
    // `AutoOpenScreen` 的 `calibrationAt` / `lastSkipReason` 计算属性直接读引擎。
    // 这两个字段只是 `syncAutoOpenState()` 写进去的**纯镜像，全仓零读** —— 删掉，别留"未接线"的假象。

    // MARK: 硬件

    /// 钥匙串台账：直接读 Engine 的 kf_keychain_dongles（空字段回落"未知"，不编造读数）。
    var dongles: [DongleRecord] {
        _ = revision
        return DB.dongles().map { d in
            DongleRecord(id: d.mac,
                         name: d.name.isEmpty ? "钥匙串 \(String(d.mac.prefix(4)))" : d.name,
                         mac: d.mac,
                         battery: d.stat?.power ?? -1,
                         // `-1` = 没读到（`HardwareService` 读不到 0x24 就写 -1）；`0` 是合法值（一把都没签）。
                         keys: d.stat?.ekeyCount ?? -1,
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

    /// 上次校准门锁时间的时刻。**唯一真值在 DB.syncTime(mac)**（持久），
    /// 这里只是给页面读的便捷投影 —— 旧实现把它做成纯内存存储属性，
    /// 重启后恒「从未」，与门页「超 30 天未校时」提醒卡的判据互相矛盾（E-10）。
    // 2026-11-04（清理 · 死投影）：`lockClockSyncedAt` 全仓零读取 —— 门页的「超 30 天未校时」
    // 判断直接读 `DB.syncTime(mac)`（见 `DoorScreen` 的 lastSync 判据）。删掉投影，别留"两份真相"的入口。


    // MARK: 累计

    /// 累计开锁次数（机械计数器）。真实现读 Milestones 的持久计数。
    var unlockTotal: Int { Milestones.unlockTotal }

    /// 恢复默认外观：只重置外观偏好，不动安全 / 备份 / 硬件，也不动任何门锁数据。
    ///
    /// 2026-11-04（走查发现 · 漏了最显眼的那一项）：这函数重置了 22 个偏好，**独独漏了
    /// 无障碍页的四项**（`axBigText` 全局大字 / `kf_ax_bigotp` / `kf_bigtile` / `kf_dial_size`）。
    /// 而 `AccessibilityScreen:24` 的注释还写着「『恢复默认外观』会整体重置 axBigText」—— 那句话是假的。
    /// 用户开了全局大字（整棵树压到 accessibility2）再点「恢复默认外观」，字号纹丝不动 ——
    /// 而字号恰恰是外观里最显眼的一项。
    func resetAppearance() {
        axBigText = false
        DB.store.set("kf_ax_bigotp", false)
        DB.store.set("kf_bigtile", false)
        DB.store.set("kf_dial_size", "standard")
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
        // 2026-11-04（第二轮漏项 · 与 117 轮的无障碍四项同类）：`quickGridCount` 也在外观页可改
        // （「快捷格 10 选 N」），却没被这里重置 —— 用户点「恢复默认外观」后，
        // 主题/字号/密度全回去了，**首页还是只显示他上次选的 3 格**。
        quickGridCount = 6   // 与 `quickGridCount` 的缺省值同源（kf_quick_grid 默认 6）
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
