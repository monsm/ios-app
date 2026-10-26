// 应用锁安全族消费者 (389–395/398) — 这些键位原先只在设置页写与显示, 验证路径一个都不读,
// 于是"失败冷却 / 伪装码 / 胁迫码 / 失败留痕 / 锁定时机 / 免验窗口 / 救援码"全是死开关。
// 原则: 任何配置缺失都按**最严格**解释 (fail-closed), 不因为读不到值就放行。
import Foundation

// ---------- 安全策略判据口 ----------
/// 2026-10-26 精简说明：本文件原有五枚开关的判据（377 访客 / 376 分享遮半 / 383 sudo / 296 只读 / 398 会话），
/// 逐条核实后处置如下 ——
///   · **保留 guestActive（377）与 halfMasked（376）**：这两条是真实生效的行为，
///     `kf_speek_guest` / `kf_speek_sharehalf` 虽然也没有开关 UI，但默认值就决定了它们一直在起作用
///     （访客通道默认关所以不显示；分享遮半默认**开**，所以分享/复制出去的码值一直是遮半的）。
///   · **删除 readOnly（296）与其动作闸**：`SecKey.safeModeOn` 无写点 ⇒ 恒 false ⇒
///     `allows()` 永远放行、`denialMessage()` 永远不显示，是纯死逻辑。连同 `LockAction` 枚举一并删。
enum SecurityPolicy {
    /// 376 分享遮半（**默认开**，所以它一直在生效）：口述卡 / 复制 / 分享载荷里只给下半段遮码值。
    /// 原开关 UI 已删，键名直读 —— 与 guestActive 同一条处置（默认值即行为）。
    static var shareHalf: Bool { DB.store.getBool("kf_speek_sharehalf", true) }

    // ---------- 376: 遮下半段 ----------
    private static let maskChar: Character = "●"
    /// 前一半原样、后一半逐位糊掉 (奇数时多出来的那一位算上半段, 遮到的位数永不超过看得见的)。
    /// 两位以下没有"下半段"可言, 原样返回 —— 一位码遮完就等于把口令吞了却不给任何提示。
    static func masked(_ digits: String) -> String {
        let n = digits.count
        guard n >= 3 else { return digits }
        let keep = (n + 1) / 2
        return String(digits.prefix(keep)) + String(repeating: maskChar, count: n - keep)
    }
    /// 376 渲染侧的一行读法: 开关关着原样给, 开着遮下半段 (调用点不必自己写三目)
    static func halfMasked(_ digits: String) -> String { shareHalf ? masked(digits) : digits }
}
