// ZOTP 临时密码生成器 — JS utils/zotp.js 的字符级移植 (App to.generateZOTPPwd)
//   6 位密码 = AES-ECB(skey,ZeroPadding)( 时间计数器(8hex) + MAC反序(12hex) + idx(2B) + "00000000" )
//            → 密文取前 24hex, 每 4hex 块 (b1^b2)%10 拼接
//   u = floor(nowProtoSeconds / (60*period)); 前提: 锁钟已同步 (0E)
// 差分基准: golden.zotp.*
import Foundation

nonisolated enum ZOTP {
    static func reversePairHex(_ hex: String) -> String { HexKit.reversePairs(hex) }
    // idx → 2B BE hex (App: toSmallByteOrder→toNormalByteOrder 双反转 = 恒等)
    static func le2be2(_ v: Int) -> String {
        let x = UInt32(truncatingIfNeeded: v)
        return String(format: "%04x", x & 0xffff).uppercased()
    }
    /// `periodSec` 这个名字是**沿用 JS 基线**的 (vendor/app/utils/zotp.js:19)，而它真正的单位是**分钟**：
    /// 计数器 = nowProtoSeconds / (60 * t)，t=30 ⇒ 窗口 30 分钟 (金标 case v30_*/v60_0 就是这个换算)。
    /// 不在 Swift 侧单独改名：那会让同一概念在两种语言里叫不同名字，而读基线的人比读这里更多。
    /// 改名要连 vendor 与金标 fixture 一起动，属于跨语言基线决定 (已记入 docs/DECISION-NEEDED.md)。
    static func generate(macHex: String, skeyHex: String, periodSec: Int, idx: Int, nowSec: Int64? = nil) -> String {
        let t = periodSec > 0 ? periodSec : 30
        let now = nowSec ?? ZKProtocol.nowProtoSeconds()
        let u = String(format: "%llx", now / Int64(60 * t)).uppercased()
        let uPadded = String(repeating: "0", count: max(0, 8 - u.count)) + u
        let r = macHex.replacingOccurrences(of: ":", with: "").uppercased()
        // MAC 必须是整 6 字节。少了这道 guard，一个畸形 (奇数长度/含脏字符) 的 mac 会让
        // `reversePairHex` 返回 ""，拼出来的明文只剩 20 hex ⇒ AESKit 补零到 16 字节 ⇒ 密文仍是 32 hex ⇒
        // 下面 `p.count == 32` 过得去，于是**界面给出一个六位码，而它注定开不了锁**。
        // 锁端会拒绝它 (fail-closed)，但「看着对、其实错」的输出比空值贵：用户会反复试、会以为是钟没同步。
        // vendor 基线在这里是逐对反向、对奇数长度会悄悄丢首字符 —— 那是一条跨语言分歧 (§10.44)。
        guard r.count == 12, r.allSatisfy({ $0.isHexDigit }) else { return "" }
        let a = idx > 0 ? le2be2(idx) : "0000"
        let c = uPadded + reversePairHex(r) + a + "00000000"
        let p = AESKit.encryptHex(c, keyHex: skeyHex).uppercased()
        guard p.count == 32 else { return "" }
        let body = String(p.prefix(p.count - 8)) // 前 24hex = 6 个 4hex 块
        let bytes = HexKit.bytes(body)
        var m = ""
        var i = 0
        while i + 1 < bytes.count {
            m += String((Int(bytes[i]) ^ Int(bytes[i + 1])) % 10)
            i += 2
        }
        return m
    }
    // 30 分钟窗口失效时刻 (JS credentials.nextWindow: 分钟>30 → 下一半点, 否则本半点)
    static func nextWindow(from now: Date = Date()) -> String {
        let cal = WeekCal.gregorian
        let comps = cal.dateComponents([.minute], from: now)
        let m = comps.minute ?? 0
        let minutePart = m > 30 ? 0 : 30
        var hour = cal.component(.hour, from: now)
        if m > 30 { hour += 1 }
        return String(format: "%02d:%02d", hour % 24, minutePart)
    }
}