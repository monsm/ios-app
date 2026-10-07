// ZK 命令构造器 — JS utils/kernel/cmds.js 的逐行移植
// 密文面统一模式: body → EKey(cmd,mac) → AES-ECB(skey) → KLV#xx
// 差分基准: golden.cmds.* (40 个命令的完整帧 hex)
import Foundation

struct ZKCmd {
    let name: String
    let cmd: UInt8
    let hex: String
}

enum ZKCmdBuilder {
    static func u16leHex(_ v: Int) -> String { HexKit.u16leHex(v) }
    static func u32leHex(_ v: UInt32) -> String { HexKit.u32leHex(v) }

    // 日期串/ms/协议秒 → 协议秒 (JS protoSec: 字符串按本地时区解释)
    static func protoSec(_ v: String?) -> Int64 {
        guard let s = v, !s.isEmpty else { return ZKProtocol.nowProtoSeconds() }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = .current
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let d = fmt.date(from: s) { return ZKProtocol.protoSecondsFromMs(Int64(d.timeIntervalSince1970 * 1000)) }
        let f2 = DateFormatter()
        f2.locale = Locale(identifier: "en_US_POSIX")
        f2.timeZone = TimeZone(identifier: "UTC") // JS: 日期-only 追加 T00:00:00Z → UTC 解释
        f2.dateFormat = "yyyy-MM-dd"
        if let d = f2.date(from: s) { return ZKProtocol.protoSecondsFromMs(Int64(d.timeIntervalSince1970 * 1000)) }
        // ISO-T 变体 (…THH:mm 无秒): JS Date.parse 接受, 这里补一档避免回落 now
        let f3 = DateFormatter()
        f3.locale = Locale(identifier: "en_US_POSIX")
        f3.timeZone = .current
        f3.dateFormat = "yyyy-MM-dd'T'HH:mm"
        if let d = f3.date(from: s) { return ZKProtocol.protoSecondsFromMs(Int64(d.timeIntervalSince1970 * 1000)) }
        return ZKProtocol.nowProtoSeconds()
    }

    // ---- 明文面 ----
    static func cmd01Session() -> ZKCmd {
        ZKCmd(name: "01 会话令牌", cmd: 0x01, hex: ZKProtocol.buildFrame(0x01, "", header: 8))
    }
    static func cmd23ExKeyWay() -> ZKCmd {
        ZKCmd(name: "23 交换方式", cmd: 0x23, hex: ZKProtocol.buildFrame(0x23, "", header: 8))
    }
    static func cmd12Echo(_ valHex: String = "123456") -> ZKCmd {
        ZKCmd(name: "12 回声", cmd: 0x12, hex: ZKProtocol.buildFrame(0x12, ZKProtocol.buildKLV(0x01, valHex), header: 8))
    }
    static func cmd03StatusPlain(_ macHex: String) -> ZKCmd {
        // JS cmd03Status(8, macHex, wrap=false) → 裸 03 帧 (无 KLV)
        ZKCmd(name: "03 状态(明文)", cmd: 0x03, hex: ZKProtocol.buildFrame(0x03, "", header: 8))
    }
    static func cmd05Exchange(_ skeyHex: String, timeSec: Int64? = nil) -> ZKCmd {
        // JS: opts.timeSec || now — 0 也回落为 now
        let ts = UInt32(truncatingIfNeeded: timeSec.flatMap { $0 == 0 ? nil : $0 } ?? ZKProtocol.nowProtoSeconds())
        let klv = ZKProtocol.buildKLV(0x01, HexKit.u32leHex(ts))
            + ZKProtocol.buildKLV(0x02, "01")
            + ZKProtocol.buildKLV(0x03, skeyHex)
        return ZKCmd(name: "05 换钥", cmd: 0x05, hex: ZKProtocol.buildFrame(0x05, klv, header: 8))
    }

    // ---- 密文管理面 ----
    static func cmd03StatusWrap(_ macHex: String, _ skeyHex: String) -> ZKCmd {
        let enc = AESKit.encryptHex(ZKProtocol.buildEkey(0x03, macHex), keyHex: skeyHex)
        let klv = ZKProtocol.buildKLV(0x01, enc) + ZKProtocol.buildKLV(0x02, "")
        return ZKCmd(name: "03 加密状态", cmd: 0x03, hex: ZKProtocol.buildFrame(0x03, klv, header: 8))
    }
    // cmd 04 OPEN: KLV#01 = 左补零 32; KLV#02 = 凭证密文
    static func cmd04Open(_ ekeyHex: String, klv01Hex: String = "0000") -> ZKCmd {
        let klv = ZKProtocol.buildKLV(0x01, HexKit.fillZeroLeft(klv01Hex, 32)) + ZKProtocol.buildKLV(0x02, ekeyHex)
        return ZKCmd(name: "04 开锁", cmd: 0x04, hex: ZKProtocol.buildFrame(0x04, klv, header: 8))
    }
    // pin → LE 4B hex (数字或已是 8 hex 皆可 — JS pinToLE 双兼容)
    static func pinToLE(_ pin: String) -> String {
        var h = pin.lowercased()
        if h.hasPrefix("0x") { h = String(h.dropFirst(2)) } // JS: replace(/^0x/i, '')
        if h.count == 8, h.allSatisfy({ $0.isHexDigit }) { return h }
        guard let v = UInt32(h) else { return "00000000" }
        return HexKit.u32leHex(v)
    }
    // ekey (开锁凭证) = AES(skey)($t 包络); JS buildEkeyOpen/buildEkeyShare
    static func buildEkeyOpen(_ skeyHex: String, _ macHex: String, _ pin: String,
                              validFromSec: UInt32 = 0, validToSec: UInt32? = nil, trackId: UInt32 = 0) -> String {
        let env = ZKProtocol.buildEkey(0x04, macHex, validFromSec: validFromSec, validToSec: validToSec, trackIdVal: trackId)
            + pinToLE(pin) + "00" + "00"
        return AESKit.encryptHex(env, keyHex: skeyHex)
    }
    // App generateEkey (分享/写钥匙串): 随机 TrackId + 本地时区 2010~2118 窗口
    static func buildEkeyShare(_ skeyHex: String, _ macHex: String, _ pin: String,
                               random: (UInt32) -> UInt32) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let vf = UInt32(truncatingIfNeeded: protoSec("2010-01-01 00:00:00")) // JS: '2010-01-01T00:00:00' 本地解释
        let vt = UInt32(truncatingIfNeeded: protoSec("2118-01-01 00:00:00"))
        return buildEkeyOpen(skeyHex, macHex, pin, validFromSec: vf, validToSec: vt, trackId: random(0x7fffffff))
    }
    // cmd 08: addCount(1B)+delCount(1B)+addPins(4B LE×N)+delPins(4B LE×M)
    static func cmd08SyncPinsBatch(_ macHex: String, _ skeyHex: String, _ addPins: [String], delPins: [String] = []) -> ZKCmd? {
        if addPins.count > 20 { return nil }
        var body = HexKit.hexPair(UInt32(addPins.count)) + HexKit.hexPair(UInt32(delPins.count))
        body += addPins.joined()
        body += delPins.joined()
        return ZKCmd(name: "08 PIN 批量", cmd: 0x08, hex: ZKProtocol.buildFrame(0x08, ZKProtocol.wrapEnc(0x08, macHex, skeyHex, body, 0x01), header: 8))
    }
    // cmd 21: skeyLen(1B=0x10)+bkey(16B)
    static func cmd21SetBkey(_ macHex: String, _ skeyHex: String, _ bkeyHex: String) -> ZKCmd {
        let body = "10" + bkeyHex
        return ZKCmd(name: "21 bkey", cmd: 0x21, hex: ZKProtocol.buildFrame(0x21, ZKProtocol.wrapEnc(0x21, macHex, skeyHex, body, 0x02), header: 8))
    }
    // cmd 0A: delAlias(2B LE, 0xFFFF=清空) + addPwd(8B ASCII 右补零) + validFrom/To(4B LE)
    static func cmd0ASyncPwd(_ macHex: String, _ skeyHex: String, delAlias: Int = 0, addPwd: String = "", validFrom: String? = nil, validTo: String? = nil) throws -> ZKCmd {
        guard addPwd.count <= 8 else { throw BLEErrorX.msg("密码最长 8 位") } // JS throw — 不静默截断
        let body = u16leHex(delAlias)
            + HexKit.asciiHex(addPwd, nBytes: 8)
            + HexKit.u32leHex(UInt32(truncatingIfNeeded: protoSec(validFrom)))
            + HexKit.u32leHex(UInt32(truncatingIfNeeded: protoSec(validTo)))
        return ZKCmd(name: "0A 同步密码", cmd: 0x0a, hex: ZKProtocol.buildFrame(0x0a, ZKProtocol.wrapEnc(0x0a, macHex, skeyHex, body, 0x01), header: 8))
    }
    // cmd 0B: alias(2B LE) + validFrom/To
    static func cmd0BSyncPwdExpire(_ macHex: String, _ skeyHex: String, _ alias: Int, _ validFrom: String?, _ validTo: String?) -> ZKCmd {
        let body = u16leHex(alias)
            + HexKit.u32leHex(UInt32(truncatingIfNeeded: protoSec(validFrom)))
            + HexKit.u32leHex(UInt32(truncatingIfNeeded: protoSec(validTo)))
        return ZKCmd(name: "0B 密码有效期", cmd: 0x0b, hex: ZKProtocol.buildFrame(0x0b, ZKProtocol.wrapEnc(0x0b, macHex, skeyHex, body, 0x01), header: 8))
    }
    // cmd 0E: syncTime(4B LE 协议秒)
    static func cmd0ESyncTime(_ macHex: String, _ skeyHex: String, _ timeSec: Int64) -> ZKCmd {
        let body = HexKit.u32leHex(UInt32(truncatingIfNeeded: timeSec))
        return ZKCmd(name: "0E 时间同步", cmd: 0x0e, hex: ZKProtocol.buildFrame(0x0e, ZKProtocol.wrapEnc(0x0e, macHex, skeyHex, body, 0x02), header: 8))
    }
    // cmd 13: times(1B) + timeout(1B)
    static func cmd13AddFp(_ macHex: String, _ skeyHex: String, _ times: Int = 8, _ timeout: Int = 15) -> ZKCmd {
        // 兜底对齐 JS cmds.js:119-120 (times||8, timeout<=0→15)
        let t = times > 0 ? times : 8
        let to = timeout > 0 ? timeout : 15
        let body = HexKit.hexPair(UInt32(t)) + HexKit.hexPair(UInt32(to))
        return ZKCmd(name: "13 录指纹", cmd: 0x13, hex: ZKProtocol.buildFrame(0x13, ZKProtocol.wrapEnc(0x13, macHex, skeyHex, body, 0x02), header: 8))
    }
    // cmd 14: batchNumber(4B LE) + validFrom/To
    static func cmd14FpConfirm(_ macHex: String, _ skeyHex: String, _ batchNumber: UInt32, _ validFrom: String?, _ validTo: String?) -> ZKCmd {
        let body = HexKit.u32leHex(batchNumber)
            + HexKit.u32leHex(UInt32(truncatingIfNeeded: protoSec(validFrom)))
            + HexKit.u32leHex(UInt32(truncatingIfNeeded: protoSec(validTo)))
        return ZKCmd(name: "14 指纹确认", cmd: 0x14, hex: ZKProtocol.buildFrame(0x14, ZKProtocol.wrapEnc(0x14, macHex, skeyHex, body, 0x02), header: 8))
    }
    // cmd 15: batchNumber(4B LE)
    static func cmd15DeleteFp(_ macHex: String, _ skeyHex: String, _ batchNumber: UInt32) -> ZKCmd {
        ZKCmd(name: "15 删指纹", cmd: 0x15, hex: ZKProtocol.buildFrame(0x15, ZKProtocol.wrapEnc(0x15, macHex, skeyHex, HexKit.u32leHex(batchNumber), 0x02), header: 8))
    }
    // cmd 16: orderType(1B) + startIdx(4B LE) + pageSize(1B)
    static func cmd16GetLog(_ macHex: String, _ skeyHex: String, orderType: Int = 0, startIdx: UInt32 = 0, pageSize: Int = 20) -> ZKCmd {
        // 兜底对齐 JS cmds.js:138 (pageSize||20)
        let size = pageSize > 0 ? pageSize : 20
        let body = HexKit.hexPair(UInt32(orderType)) + HexKit.u32leHex(startIdx) + HexKit.hexPair(UInt32(size))
        return ZKCmd(name: "16 日志", cmd: 0x16, hex: ZKProtocol.buildFrame(0x16, ZKProtocol.wrapEnc(0x16, macHex, skeyHex, body, 0x01), header: 8))
    }
    // cmd 18: vol(1B) — App setSilentMode 语义: 0=有声 1=静音
    static func cmd18Volume(_ macHex: String, _ skeyHex: String, _ silent: Bool) -> ZKCmd {
        ZKCmd(name: "18 音量", cmd: 0x18, hex: ZKProtocol.buildFrame(0x18, ZKProtocol.wrapEnc(0x18, macHex, skeyHex, HexKit.hexPair(UInt32(silent ? 1 : 0)), 0x02), header: 8))
    }
    // cmd 19: status(1B 0=关/1=开)
    static func cmd19OpenZotp(_ macHex: String, _ skeyHex: String, _ on: Bool) -> ZKCmd {
        ZKCmd(name: "19 ZOTP", cmd: 0x19, hex: ZKProtocol.buildFrame(0x19, ZKProtocol.wrapEnc(0x19, macHex, skeyHex, HexKit.hexPair(UInt32(on ? 1 : 0)), 0x02), header: 8))
    }
    // cmd 20: mode(1B 0=A单验/1=B双验)
    static func cmd20ValidationMode(_ macHex: String, _ skeyHex: String, _ bMode: Bool) -> ZKCmd {
        ZKCmd(name: "20 验证模式", cmd: 0x20, hex: ZKProtocol.buildFrame(0x20, ZKProtocol.wrapEnc(0x20, macHex, skeyHex, HexKit.hexPair(UInt32(bMode ? 1 : 0)), 0x02), header: 8))
    }
    // cmd 22: enableDFUstate param(1B, 0 → 重启进 bootloader)
    static func cmd22EnableDfu(_ macHex: String, _ skeyHex: String, _ param: Int = 0) -> ZKCmd {
        ZKCmd(name: "22 DFU", cmd: 0x22, hex: ZKProtocol.buildFrame(0x22, ZKProtocol.wrapEnc(0x22, macHex, skeyHex, HexKit.hexPair(UInt32(param & 0xff)), 0x02), header: 8))
    }
    // cmd 24: interval(1B 档位 1-6)
    static func cmd24AutoLock(_ macHex: String, _ skeyHex: String, _ interval: Int) -> ZKCmd {
        ZKCmd(name: "24 自动上锁", cmd: 0x24, hex: ZKProtocol.buildFrame(0x24, ZKProtocol.wrapEnc(0x24, macHex, skeyHex, HexKit.hexPair(UInt32(interval)), 0x01), header: 8))
    }
    // cmd 25: control(1B) + start(4B LE) + end(4B LE)
    static func cmd25Defence(_ macHex: String, _ skeyHex: String, _ control: Int, _ startSec: Int, _ endSec: Int) -> ZKCmd {
        let body = HexKit.hexPair(UInt32(control)) + HexKit.u32leHex(UInt32(truncatingIfNeeded: startSec)) + HexKit.u32leHex(UInt32(truncatingIfNeeded: endSec))
        return ZKCmd(name: "25 布防", cmd: 0x25, hex: ZKProtocol.buildFrame(0x25, ZKProtocol.wrapEnc(0x25, macHex, skeyHex, body, 0x01), header: 8))
    }

    // ---- 钥匙串硬件 (ZKBBV1 pid=16289; 87 帧明文 KLV, needToken=false) ----
    static func cmd41WriteEkey(_ lockMacHex: String, _ pid: Int, _ ekeyHex: String, type: Int = 1) -> ZKCmd {
        let klv = ZKProtocol.buildKLV(0x01, HexKit.reversePairs(lockMacHex))
            + ZKProtocol.buildKLV(0x02, HexKit.hexPair(UInt32(type)))
            + ZKProtocol.buildKLV(0x03, u16leHex(pid))
            + ZKProtocol.buildKLV(0x04, ekeyHex)
        return ZKCmd(name: "41 钥匙串写钥", cmd: 0x41, hex: ZKProtocol.buildFrame(0x41, klv, header: 8))
    }
    static func cmd44GetEkeyInfo(_ lockMacHex: String?) -> ZKCmd {
        let v = (lockMacHex?.isEmpty == false) ? HexKit.reversePairs(lockMacHex!) : ""
        return ZKCmd(name: "44 钥匙串查钥", cmd: 0x44, hex: ZKProtocol.buildFrame(0x44, ZKProtocol.buildKLV(0x01, v), header: 8))
    }
    static func cmd43KeychainStatus(_ lockMacList: [String]) -> ZKCmd {
        var v = ""
        for m in lockMacList { v += HexKit.reversePairs(m.replacingOccurrences(of: ":", with: "").lowercased()) }
        return ZKCmd(name: "43 钥匙串状态", cmd: 0x43, hex: ZKProtocol.buildFrame(0x43, ZKProtocol.buildKLV(0x01, v), header: 8))
    }

    // ---- 网关 (FE90 服务; 87 帧明文 KLV, needToken=false) ----
    static func cmd38GWStatus() -> ZKCmd {
        ZKCmd(name: "38 网关状态", cmd: 0x38, hex: ZKProtocol.buildFrame(0x38, "", header: 8))
    }
    static func cmd31GWSetWifi(_ ssid: String, _ password: String, authMode: Int = 8, encryptType: Int = 0) -> ZKCmd {
        let klv = ZKProtocol.buildKLV(0x01, HexKit.utf8Hex(ssid))
            + ZKProtocol.buildKLV(0x02, HexKit.utf8Hex(password))
            + ZKProtocol.buildKLV(0x03, HexKit.hexPair(UInt32(authMode)))
            + ZKProtocol.buildKLV(0x04, HexKit.hexPair(UInt32(encryptType)))
            + ZKProtocol.buildKLV(0x05, "00")
        return ZKCmd(name: "31 网关配网", cmd: 0x31, hex: ZKProtocol.buildFrame(0x31, klv, header: 8))
    }
    static func cmd32GWSetIot(_ iotpKey: String, _ iotdSec: String, _ devAccToken: String) -> ZKCmd {
        let klv = ZKProtocol.buildKLV(0x05, iotpKey) + ZKProtocol.buildKLV(0x06, iotdSec) + ZKProtocol.buildKLV(0x07, devAccToken)
        return ZKCmd(name: "32 网关 IoT", cmd: 0x32, hex: ZKProtocol.buildFrame(0x32, klv, header: 8))
    }
    static func cmd35GWReboot() -> ZKCmd {
        ZKCmd(name: "35 网关重启", cmd: 0x35, hex: ZKProtocol.buildFrame(0x35, "", header: 8))
    }
    static func cmd30GWDeviceName() -> ZKCmd {
        ZKCmd(name: "30 网关名称", cmd: 0x30, hex: ZKProtocol.buildFrame(0x30, "", header: 8))
    }
}
