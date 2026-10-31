// 帧脱敏 —— 日志里出现 `hex=` 时把载荷遮掉，只留帧头。
//
// 2026-10-27 审核恢复（AUDIT-A F-03）：这道机制在三轮功能精简时被当无用代码删掉，
// 而帧里携带 skey（cmd05 换钥）/ 密码（cmd0A）/ PIN / ekey —— 全部是开锁凭据。
// 删除后 `logs` / `kf_diag_logs` / 导出中心 / 剪贴板全都能看到明文，且随系统备份出机。
//
// 帧结构：`87 00 len:2 cmd 000000` + KLV 载荷。头是 8 字节 = 16 个 hex 字符。
// 只保留头（cmd 号与长度对排查足够），载荷整段替换成 `…(N bytes)`。
//
// 保留完整帧的只有内存里的 `recentFrames` 环形缓冲（诊断页即时查看，不落盘、不可复制）。
// String.range(of:) 是 Foundation 的扩展；本文件原先一个 import 都没有，靠 wholemodule 隐式可见
import Foundation

enum FrameRedact {
    /// 把一条日志里的 `hex=<长串>` 遮成 `hex=<头>…(N bytes)`。
    /// 不含 `hex=` 或 hex 太短（不是帧）时原样返回。
    static func apply(_ msg: String) -> String {
        guard let r = msg.range(of: "hex=") else { return msg }
        let head = String(msg[msg.startIndex..<r.upperBound])
        let tail = String(msg[r.upperBound...])
        // 只取到最后一个 hex 字符（后面可能还有 " (12ms)" 这类尾巴）
        var hexPart = ""
        var rest = ""
        for ch in tail {
            if ch.isHexDigit, hexPart.count < 4096, rest.isEmpty { hexPart.append(ch) }
            else { rest.append(ch) }
        }
        guard hexPart.count >= 16 else { return msg }   // 不足一个帧头就不是帧
        let hdr = String(hexPart.prefix(16))           // 8 字节帧头
        let payloadBytes = (hexPart.count - 16) / 2
        return head + hdr + "…((payloadBytes) bytes 已脱敏)" + rest
    }
}
