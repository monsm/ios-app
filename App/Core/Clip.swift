// 剪贴板统一入口 —— 写入即设过期时间。
//
// 2026-10-27 审核修复（AUDIT-D D-37）：全仓 17 处 `UIPasteboard.general.string = …`，
// **0 处**设过期时间。复制密码后它一直留在剪贴板里，任何 App 都能读。
// 而注释里 8 处写着「405 自清」—— 那只是个 idea 编号，从来没有实现。
//
// 90 秒的选择：够用户切到微信/备忘录粘贴（正常 10 秒内完成），
// 又不至于让明文躺一整天。超时后剪贴板自动清空，用户重新复制即可。
import UIKit

enum Clip {
    /// 默认过期秒数。所有 `Clip.set` 调用共用这一个值。
    static let expireSeconds: Double = 90

    /// 写剪贴板并设过期时间。空串直接清空（不设过期，因为没有内容）。
    static func set(_ text: String) {
        guard !text.isEmpty else {
            UIPasteboard.general.string = ""
            return
        }
        UIPasteboard.general.setItems(
            [[UIPasteboard.typeAutomatic: text]],
            options: [
                .expirationDate: Date().addingTimeInterval(expireSeconds)
            ])
    }
}
