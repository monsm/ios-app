// SettingsStore.swift —— 应用偏好。Engine 的 BackupKit 会调用 notifyChanged()，
// 所以这个名字与调用形态必须保留。
import SwiftUI

@MainActor
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    /// 每次外部写入（备份恢复 / 引擎迁移）后 +1，界面据此重读。
    private(set) var revision: Int = 0

    func notifyChanged() { revision &+= 1 }

    var theme: String {
        get { DB.store.getString("kf_theme") }
        set { DB.store.set("kf_theme", newValue); notifyChanged() }
    }

    var homeName: String {
        get { DB.store.getString("kf_home_name", "我的家") }
        set { DB.store.set("kf_home_name", newValue); notifyChanged() }
    }

    var autoRetry: Bool {
        get { DB.store.getBool("kf_auto_retry", true) }
        set { DB.store.set("kf_auto_retry", newValue); notifyChanged() }
    }

    var haptics: Bool {
        get { DB.store.getBool("kf_haptics", true) }
        set { DB.store.set("kf_haptics", newValue); notifyChanged() }
    }

    var keepScreenAwake: Bool {
        get { DB.store.getBool("kf_keep_awake", true) }
        set { DB.store.set("kf_keep_awake", newValue); notifyChanged() }
    }

    var quickGridCount: Int {
        get { max(3, min(6, DB.store.getInt("kf_quick_grid", 4))) }
        set { DB.store.set("kf_quick_grid", max(3, min(6, newValue))); notifyChanged() }
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
