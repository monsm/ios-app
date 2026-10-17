import os
// 405/238 敏感内容剪贴板自清 —— 唯一出口 (choke point)。238 原句的"90 秒"是本文件这一个延时档，
// 不在别处再写第二个延时数 (两处各写一个秒数, 改一处就是谎)。
// 为什么不逐个调用点各写一份定时器: 20 处 pasteboard 写入迟早会漏一处 (本仓就是"两处路径口径不一致"的现场),
// 而且"清除"这一步必须共享同一个代数计数, 否则前一条的延迟会把后一条刚复制的内容清掉。
// 三条硬规矩:
//   1. **只在剪贴板内容仍等于当时那串时才清** —— 用户中途复制了别的东西, 绝不替他删;
//   2. 只有口令/OTP/备份信封这类可开门的东西走这里, 记录行、报告文本不走 (清了只会碍事);
//   3. 时长可关 (0 = 关), 默认 60 秒; 关闭时不注册任何延迟任务。
// 顺带承载 344 粘贴建议条的状态 (回前台时"刚复制的那串还在不在"), 因为两者判定用的是同一份
// 自清窗口与同一次复制事件 —— 分两处记就会出现"剪贴板早清了、快捷条还挂着"的假话。
import UIKit

@MainActor
enum ClipboardCare {
    static let ttlKey = "kf_cb_ttl"
    /// 0 = 关闭自清; 其余为秒数。上限 600 防手改出无意义的长挂。
    static var ttl: Int { min(max(DB.store.getInt(ttlKey, 60), 0), 600) }
    static var autoClearOn: Bool { ttl > 0 }
    static func setTTL(_ v: Int) { DB.store.set(ttlKey, min(max(v, 0), 600)) }

    // 代数计数: 每次复制 +1, 延迟任务只在自己仍是"最新一次"时才动手。
    // 全族都在 MainActor 上跑, 所以不需要额外的锁 (加了反而引入非 Sendable 全局)。
    private static var generation = 0

    // ---------- 344 粘贴建议条 (回前台快捷条) ----------
    // 三条口径是这一条能不能挂得住的前提:
    //   1. 状态**只在内存**, 绝不落盘 —— 落盘就等于把"刚复制了什么"写进偏好表, 而且重启后
    //      那条延时自清已经不存在了, 再说"N 秒后清除"就是假话;
    //   2. 判"还在不在"用 `changeCount` (不含内容), 不读剪贴板明文 —— 读内容会触发系统
    //      "某某 App 粘贴自…" 隐私横幅, 而 changeCount 只是整数, 别处一复制就变;
    //   3. 只有开启自清 (ttl>0) 才留待复制的原文, 寿命被 ttl 上限 600 秒钉死; 关掉自清时
    //      内存里也不留明文, 建议条随之不出现 (没有到点这回事, 就没有可提醒的东西)。
    struct Pending {
        let text: String
        let label: String
        let at: Double
        let change: Int
    }
    enum PasteStage: Equatable {
        case waiting(Int)   // 还在剪贴板, 附剩余秒数
        case cleared       // 到点已被自清抹掉, 需要时回凭证页再复制
    }
    struct Suggestion: Equatable {
        let label: String
        let stage: PasteStage
    }
    private static let pendingLock = OSAllocatedLock<Pending?>(nil)
    private static var clearedLabel: String?

    static var suggestion: Suggestion? {
        if let p = pendingLock.withLock({ $0 }) {
            guard UIPasteboard.general.changeCount == p.change else { return nil }   // 已被别处覆盖, 不冒充"还在"
            // 单位口径：秒 —— `Pending.at` 由本文件 `pending = Pending(` 那一行写入，取的就是
            // `Date().timeIntervalSince1970`，与 ttl/now 同一把尺（不是台账里那种 epoch 毫秒）。
            let left = Int(ceil(p.at + Double(ttl) - Date().timeIntervalSince1970))
            guard left > 0 else { return nil }
            return Suggestion(label: p.label, stage: .waiting(left))
        }
        if let l = clearedLabel { return Suggestion(label: l, stage: .cleared) }
        return nil
    }
    /// 一键再复制: 明文还在内存里才有这个按钮, 点完重新起算窗口。
    static func recopy() {
        guard let p = pendingLock.withLock({ $0 }) else { return }
        copySecret(p.text, via: p.label)
    }
    /// "知道了" / 跳走之后就地收起, 不挂成常驻广告。
    static func dismissSuggestion() {
        pendingLock.withLock { $0 = nil }
        clearedLabel = nil
    }

    /// 517 一键清除: 用户在粘贴建议条上点清除时, 不等 ttl 到点。
    /// 复用本文件同一代数守卫与 changeCount 口径: 只在剪贴板仍是当时那串时才抹,
    /// 用户中途复制了别的就只收起建议条, 绝不替他删 (与 copySecret 同款规矩)。
    static func clearNow() {
        if let p = pendingLock.withLock({ $0 }), UIPasteboard.general.changeCount == p.change {
            UIPasteboard.general.string = ""
            generation += 1        // 让在飞的延时任务认输 (不弹"已自动清除", 这不是自动的)
        }
        dismissSuggestion()
    }

    /// 写剪贴板并按 ttl 延时自清。`via` 只进提示文本，用于人肉排查"这串是谁写进去的"。
    static func copySecret(_ text: String, via: String) {
        UIPasteboard.general.string = text
        SensitiveLedger().record("复制", target: via)   // 388 覆盖所有复制路径 (含一键再复制)
        clearedLabel = nil
        let secs = ttl
        let change = UIPasteboard.general.changeCount
        guard secs > 0 else {
            pendingLock.withLock { $0 = nil }                    // 关自清 = 不在内存多留一份明文
            return
        }
        pendingLock.withLock { $0 = Pending(text: text, label: via, at: Date().timeIntervalSince1970, change: change) }
        generation += 1
        let my = generation
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(secs) * 1_000_000_000)
            guard my == generation else { return }                       // 后面又复制过新的, 不归本次管
            guard UIPasteboard.general.changeCount == change else {
                // 用户中途复制了别的东西: 绝不清, 也不再留本串和"还在剪贴板"的说法
                if my == generation { pendingLock.withLock { $0 = nil } }
                return
            }
            UIPasteboard.general.string = ""
            pendingLock.withLock { $0 = nil }
            clearedLabel = via
            // 只报"已清除", 不回显内容本身
            AppState.hostRef?.showToast("剪贴板内容已自动清除 (\(secs) 秒 · \(via))")
        }
    }
}
