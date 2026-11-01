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
                let hdr = String(hexPart.prefix(16))          // 8 字节帧头（cmd 与长度）
                let rest = String(hexPart.dropFirst(16))     // 载荷
                let payloadBytes = rest.count / 2
                // 2026-11-01：从「一个字节数」升级成**结构骨架**。
                // 原因：用户要把流水发给开发者排查，"8 字节头 + N bytes"看不出帧结构对不对，
                // 而**字段号与长度**足以判断"缺字段 / 长度错 / 帧被截断"，且不含任何凭据值。
                out += hdr + Self.skeleton(rest) + "(\(payloadBytes) bytes 已脱敏)"
            } else {
                // 短 hex 也可能承载凭据（例如只打了一个 4 字节 PIN）—— 一并遮掉，不留明文。
                out += hexPart.isEmpty ? "" : "<redacted>"
            }
            cursor = i
        }
        out += msg[cursor..<msg.endIndex]
        return out
    }

    /// 从载荷 hex 里抽出 **KLV 结构骨架**：只保留「字段号:长度」，值一个字节都不留。
    ///
    /// 排查价值：帧的**结构**（有哪些字段、各多长、是否被截断）能定位绝大多数"命令没生效"，
    /// 而这些信息不含 skey / ekey / PIN / 密码 —— 与"永不记凭据明文"的纪律不冲突。
    /// 解析不完整时以 `…` 结尾，明确表示"后面的结构没读懂"，不假装完整。
    private static func skeleton(_ payloadHex: String) -> String {
        let even = payloadHex.count - (payloadHex.count % 2)
        guard even >= 4 else { return "" }
        let chars = Array(payloadHex.prefix(even))
        var bytes: [UInt8] = []
        bytes.reserveCapacity(even / 2)
        var k = 0
        while k + 1 < chars.count {
            if let v = UInt8(String(chars[k ... k + 1]), radix: 16) { bytes.append(v) }
            k += 2
        }
        var parts: [String] = []
        var idx = 0
        while idx + 1 < bytes.count, parts.count < 16 {
            let key = bytes[idx], len = Int(bytes[idx + 1])
            parts.append(String(format: "%02x:%d", key, len))
            let next = idx + 2 + len
            if next <= idx || next > bytes.count { parts.append("…"); break }
            idx = next
        }
        return parts.isEmpty ? "" : " KLV[\(parts.joined(separator: " "))] "
    }
}
