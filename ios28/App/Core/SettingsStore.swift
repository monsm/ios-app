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

    private init() { load() }

    /// 把盘上的值读进内存。备份恢复写完盘后由 `notifyChanged()` 调用。
    private func load() {
        theme = DB.store.getString("kf_theme")
        homeName = DB.store.getString("kf_home_name", "我的家")
        haptics = DB.store.getBool("kf_haptics", true)
        keepScreenAwake = DB.store.getBool("kf_keep_awake", true)
        quickGridCount = max(3, min(6, DB.store.getInt("kf_quick_grid", 4)))
        autoRetry = DB.store.getBool("kf_auto_retry", true)
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

    /// 主题是否深色（供根视图覆盖系统外观）。
    var preferredScheme: ColorScheme? {
        switch theme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
