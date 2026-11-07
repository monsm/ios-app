// SettingsStore.swift —— 应用偏好。Engine 的 BackupKit 会调用 notifyChanged()，
// 所以这个名字与调用形态必须保留。
import SwiftUI

@MainActor
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    /// 每次外部写入（备份恢复 / 引擎迁移）后 +1，界面据此重读。
    private(set) var revision: Int = 0

    /// 偏好放在**存储属性**上，不是「现读 UserDefaults」的计算属性。
    ///
    /// 原因：`@Observable` 只给存储属性建观察边。计算属性每次现读盘，
    /// 改了也没人收到通知 —— 界面要等下一次重画才认，于是出现
    /// 「在外观里把工具数量从 4 调到 6，回到今日还是 4 个」这种改了不生效的假设置。
    private(set) var theme = ""
    private(set) var homeName = "我的家"
    private(set) var haptics = true
    private(set) var keepScreenAwake = true
    private(set) var quickGridCount = 4
    private(set) var autoRetry = true
    /// 门禁页是否提供面容/指纹解锁按钮（G5）。默认开；设了胁迫码时门禁页
    /// 仍会强制隐藏 —— 那一条是安全判据，不是偏好，偏好只管"要不要"。
    private(set) var biometric = true
    /// 品牌色（H1）：六套预设 id（kf_accent）。"" = 默认黄铜。
    /// 令牌层（T.C.brass 族）直接读 DB.store 解析；这里的存储属性只供外观页
    /// 建观察边、以及备份恢复后界面重读。
    private(set) var accent = ""
    /// 自定义强调色（kf_accent_custom，0xRRGGBB；0 = 未启用）。优先于六套预设 —— 与 ios27 同口径。
    private(set) var accentCustom = 0
    /// 底栏形态（I6）：false = 浮岛玻璃胶囊（默认，像素与旧版一致）；
    /// true = 原生系统标签栏（真系统材质、滚动收起、VoiceOver 标签语义）。
    private(set) var nativeTabBar = false
    /// 首页显示哪些分区（F54）：readings / tray / recent。
    /// 默认三块都在 —— 可编排是给「屏幕小、只想看一样东西」的人准备的，不是默认形态。
    private(set) var homeSections: [String] = ["readings", "tray", "recent"]
    /// 音效开关（F30）。默认关 —— 门锁这个场景不该突然出声。
    private(set) var sound = false

    private init() { load() }

    /// 把盘上的值读进内存。备份恢复写完盘后由 `notifyChanged()` 调用。
    private func load() {
        theme = DB.store.getString("kf_theme")
        homeName = DB.store.getString("kf_home_name", "我的家")
        haptics = DB.store.getBool("kf_haptics", true)
        keepScreenAwake = DB.store.getBool("kf_keep_awake", true)
        quickGridCount = max(3, min(6, DB.store.getInt("kf_quick_grid", 4)))
        autoRetry = DB.store.getBool("kf_auto_retry", true)
        biometric = DB.store.getBool("kf_biometric", true)
        accent = DB.store.getString("kf_accent")
        accentCustom = DB.store.getInt("kf_accent_custom", 0)
        nativeTabBar = DB.store.getBool("kf_native_tabbar", false)
        let sections = DB.store.get([String].self, "kf_home_sections") ?? ["readings", "tray", "recent"]
        homeSections = sections.isEmpty ? ["readings", "tray", "recent"] : sections
        sound = DB.store.getBool("kf_sound", false)
    }

    /// Engine（BackupKit）恢复完外观偏好后调这个：界面据此重读。
    func notifyChanged() {
        revision &+= 1
        load()
    }

    // MARK: - 写

    func setTheme(_ value: String) {
        DB.store.set("kf_theme", value)
        theme = value
    }

    func setHomeName(_ value: String) {
        DB.store.set("kf_home_name", value)
        homeName = value
    }

    func setHaptics(_ value: Bool) {
        DB.store.set("kf_haptics", value)
        haptics = value
    }

    func setKeepScreenAwake(_ value: Bool) {
        DB.store.set("kf_keep_awake", value)
        keepScreenAwake = value
    }

    func setQuickGridCount(_ value: Int) {
        let n = max(3, min(6, value))
        DB.store.set("kf_quick_grid", n)
        quickGridCount = n
    }

    func setAutoRetry(_ value: Bool) {
        DB.store.set("kf_auto_retry", value)
        autoRetry = value
    }

    func setBiometric(_ value: Bool) {
        DB.store.set("kf_biometric", value)
        biometric = value
    }

    /// H1：选六套预设之一（"" = 回默认黄铜）。选预设时清掉自定义 —— 与 ios27 同口径。
    func setAccent(_ value: String) {
        DB.store.set("kf_accent", value)
        accent = value
        if accentCustom != 0 { setAccentCustom(0) }
    }

    /// H1：自定义强调色（0xRRGGBB；0 = 取消自定义）。会盖过六套预设。
    func setAccentCustom(_ value: Int) {
        DB.store.set("kf_accent_custom", value)
        accentCustom = value
    }

    /// I6：底栏形态开关。
    func setNativeTabBar(_ value: Bool) {
        DB.store.set("kf_native_tabbar", value)
        nativeTabBar = value
    }

    /// F54：首页分区。顺序即显示顺序。
    func setHomeSections(_ value: [String]) {
        let v = value.isEmpty ? ["readings", "tray", "recent"] : value
        DB.store.set("kf_home_sections", v)
        homeSections = v
    }

    /// F30：音效开关（默认关）。
    func setSound(_ value: Bool) {
        DB.store.set("kf_sound", value)
        sound = value
    }

    /// 主题是否深色（供根视图覆盖系统外观）。
    var preferredScheme: ColorScheme? {
        switch theme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
