//
//  Alerts.swift
//  破坏性动作确认助手 (2026-10-21 从 CredentialsView.swift 迁出)
//
//  这些是**全仓共用**的弹窗助手, 不属于凭证页。
//  原文件被新 KeysPage 替代后, 这里仍有 4 个调用方, 所以独立成文件。
//

import SwiftUI
import UIKit

// 破坏性确认: 取消 / 标红确认
// UIAlertController 与 topViewController() 都是主 actor 的; 这两个助手只由界面动作调用,
// 所以整枚函数下沉到主 actor, action 也标 @MainActor (它执行的永远是界面上的"确认"动作)。
@MainActor
func confirmDestructive(_ title: String,
                        _ message: String,
                        confirmTitle: String = "确定",
                        action: @escaping @MainActor () -> Void) {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: confirmTitle, style: .destructive) { _ in action() })
    UIApplication.topViewController()?.present(alert, animated: true)
}

/// 109 删除冷静期: 比 confirmDestructive 更严一档 —— 必须**逐字键入指定词**才能提交,
/// 并把将被连带删除的数量写进正文 (破坏性动作的"后果预告"要可核对, 不能只说"将删除若干")。
@MainActor
func confirmDestructiveTyped(_ title: String,
                             _ message: String,
                             requireWord: String,
                             confirmTitle: String = "确认删除",
                             action: @escaping @MainActor () -> Void) {
    let alert = UIAlertController(title: title,
                                  message: message + "\n\n请输入「\(requireWord)」以解锁删除按钮:",
                                  preferredStyle: .alert)
    alert.addTextField { $0.placeholder = requireWord; $0.autocorrectionType = .no; $0.autocapitalizationType = .none }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    let ok = UIAlertAction(title: confirmTitle, style: .destructive) { _ in action() }
    ok.isEnabled = false
    alert.addAction(ok)
    // 只在逐字相符时放行 (去首尾空白): 手滑连点不可能通过
    alert.textFields?[0].addAction(UIAction { _ in
        ok.isEnabled = (alert.textFields?[0].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == requireWord
    }, for: .editingChanged)
    UIApplication.topViewController()?.present(alert, animated: true)
}

extension UIApplication {
    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var vc = scene?.keyWindow?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - 应用锁口令复核
// ═══════════════════════════════════════════════════════════════════════
/// 250: 同一把锁 30 秒内再次开锁要先复核应用锁口令。
///
/// 这条闸原来只写了 `showGate = true` 就 return —— 而**没有任何界面消费它**，
/// 于是设了应用锁的用户连按两次开锁时：第二次什么都不发生，像按钮坏了。
///
/// 用 `UIAlertController` 而不是 `.alert`：SwiftUI 的 alert 装输入框在 iOS 上不可靠。
@MainActor
func promptPasscode(_ title: String,
                    _ message: String,
                    confirmTitle: String = "验证",
                    onConfirm: @escaping @MainActor (String) -> Void,
                    onCancel: (() -> Void)? = nil) {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addTextField { tf in
        tf.isSecureTextEntry = true
        tf.placeholder = "应用锁口令"
        tf.textContentType = .password
        tf.autocapitalizationType = .none
        tf.autocorrectionType = .no
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in onCancel?() })
    alert.addAction(UIAlertAction(title: confirmTitle, style: .default) { _ in
        let pw = alert.textFields?.first?.text ?? ""
        onConfirm(pw)
    })
    UIApplication.topViewController()?.present(alert, animated: true)
}
