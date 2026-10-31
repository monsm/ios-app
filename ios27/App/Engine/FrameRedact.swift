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
        guard msg.contains("hex=") else { return msg }
        // SEC-23：逐段处理**每一个** hex=（旧实现只处理第一个，第二个原样落盘）；
        // 且不再用「4096 字符后把剩余 hex 塞进 rest」的写法 —— 那样超长帧的后半段会明文输出。
        var out = ""
        var cursor = msg.startIndex
        while let r = msg.range(of: "hex=", range: cursor..<msg.endIndex) {
            out += msg[cursor..<r.upperBound]
            var i = r.upperBound
            var hexPart = ""
            while i < msg.endIndex, msg[i].isHexDigit {
                hexPart.append(msg[i])
                i = msg.index(after: i)
            }
            if hexPart.count >= 16 {
                let hdr = String(hexPart.prefix(16))          // 8 字节帧头（cmd 与长度，够排查）
                let payloadBytes = (hexPart.count - 16) / 2
                out += hdr + "…(\(payloadBytes) bytes 已脱敏)"
            } else {
                // 短 hex 也可能承载凭据（例如只打了一个 4 字节 PIN）—— 一并遮掉，不留明文。
                out += hexPart.isEmpty ? "" : "<redacted>"
            }
            cursor = i
        }
        out += msg[cursor..<msg.endIndex]
        return out
    }
}
