// 943 主屏长按快速操作 (2026-10-10 拍板补做)。
// 旧台账 (docs/DEFERRED.md 包17) 把这条记成"⚠DONE: 不建 Widget/快捷 target"—— 那是**混了两件事**:
// 主屏长按快捷项是 `UIApplication.shortcutItems`，不需要额外 target，也不需要付费 capability。
// 三项**全都不开锁** (拍板: 主屏/锁屏上一键开锁是新的误开面，与 AUTOOPEN 那套七道门的方向相反):
// 查看记录 / 生成临时码 / 查电量。
//
// 落地方式刻意走"深链中继"而不是给快捷项配闭包:
//   委托把被点的 type 写进 UserDefaults → 界面下一次出现在用户面前时读一次并交给
//   `AppState.handleDeepLink`。这样做的理由不是省事 ——
//   ① 复用**同一个**门禁: handleDeepLink 里"应用锁未解开时只挂起 pendingRoute"这条性质
//      由既有代码保证，快速操作因此自动不可能绕过应用锁 (Swift 6 下也不用再造一个跨隔离的可变闭包);
//   ② UserDefaults 是本仓唯一的存储层 (Store.swift)，本身就线程安全。
import SwiftUI
import UIKit

enum QuickActions {
    /// (type, 标题, SF Symbol, 目标深链) —— 图标全部 systemName，不引位图 (219 资源纪律)。
    static let table: [(type: String, title: String, icon: String, link: String)] = [
        ("records", "查看记录", "list.bullet.rectangle", "kf://records"),
        ("tempcode", "生成临时码", "number.square", "kf://credentials"),
        ("battery", "查电量", "battery.25", "kf://device"),
    ]
    /// 一次性中转键: 只存"哪个快捷项被点过"，不存任何数据内容 (值本身在消费后立即删除)。
    static let tappedKey = "kf_quick_action"

    static func install() {
        UIApplication.shared.shortcutItems = table.map {
            UIApplicationShortcutItem(type: $0.type, localizedTitle: $0.title, localizedSubtitle: "",
                                      icon: UIApplicationShortcutIcon(systemImageName: $0.icon), userInfo: nil)
        }
    }

    /// 读一次即清: 第二次进界面不该再跳一次。
    static func consume() -> URL? {
        let type = DB.store.getString(tappedKey)
        guard !type.isEmpty else { return nil }
        DB.store.remove(tappedKey)
        guard let row = table.first(where: { $0.type == type }), let url = URL(string: row.link) else { return nil }
        return url
    }
}

/// 只实现"快捷项被点"这一个回调，其余 UIApplicationDelegate 方法一律不接 (本 App 无后台任务需求)。
final class QuickActionDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        DB.store.set(QuickActions.tappedKey, shortcutItem.type)
        // 冷启动时界面还没出现，这条会留在键上，等 RootView 出现时被 consume() 取走
        completionHandler(true)
    }
}
