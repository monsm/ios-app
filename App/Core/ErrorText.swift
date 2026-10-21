import Foundation

// ═══════════════════════════════════════════════════════════════════════
// MARK: - 错误翻译
// ═══════════════════════════════════════════════════════════════════════
//
// 背景：全仓有 15 处把 error.localizedDescription 直接放进 toast 或 Text。
// 其中蓝牙/协议层的错误是这样的：
//   "write failed" / "response timeout" / "rc=5"
// 用户读到的是一串工程术语，既不知道发生了什么、也不知道该做什么。
//
// 但**不能一律改写** —— 备份模块的错误本来就是说人话的
//（"口令错误或内容被篡改"、"此备份带口令 — 输入导出时设置的口令"），
// 生硬地套模板会把好文案改坏。
//
// 所以这里的策略是：只翻译**认得出的技术模式**，认不出就原样返回。
// 宁可留一句略技术的原文，也不要换成一句不准确的猜测。
enum ErrorText {
    /// 把底层错误翻成人话。认不出就原样返回。
    static func human(_ error: Error) -> String {
        let raw = error.localizedDescription
        return human(raw)
    }

    static func human(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let low = s.lowercased()
        if s.isEmpty { return "操作没有完成，请再试一次" }

        // ── 连接层 ──
        if low.contains("timeout") || s.contains("超时") {
            return "门锁没有响应 · 靠近一点再试"
        }
        if low.contains("disconnect") || s.contains("未连接") || s.contains("断开") {
            return "与门锁的连接断开了 · 请回到门边重试"
        }
        if low.contains("write failed") || s.contains("写入失败") {
            return "指令没有发到门锁 · 请靠近后重试"
        }
        if low.contains("bluetooth") || s.contains("蓝牙") {
            return "手机蓝牙不可用 · 请在系统设置里打开蓝牙"
        }
        if low.contains("already waiting") || s.contains("已有命令") {
            return "门锁正忙，上一次操作还没结束 · 稍等一下再试"
        }
        // ── 凭证 / 配对 ──
        if s.contains("钥匙串") || low.contains("skey") || s.contains("未配对") {
            return "本机没有这把锁的钥匙 · 请重新配对"
        }
        if low.contains("pin") || s.contains("密码") {
            return "密码不对"
        }
        if low.contains("battery") || s.contains("电量") {
            return "门锁电量不足"
        }
        // ── 兜底：认不出就原样返回，不猜 ──
        return s
    }
}
