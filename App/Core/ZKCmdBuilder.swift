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
    // u32 那一层的同名转发第九十二批删了：本文件自己都是直连 `HexKit.u32leHex` (见 :65/:95/:142)，
    // 零调用点的别名只会让人以为"协议侧有一套自己的小端编码"。与 `canDeviceInfo` 别名同口径处理。

    // 日期串/ms/协议秒 → 协议秒 (JS protoSec: 宽松 Date.parse, 字符串按本地时区解释, 带 Z 按 UTC)
    // 失败显式返回 nil, 由调用点决定中止 —— 旧写法失败回落"现在", 于是导入 `2026-01-05T08:00:00Z`
    // 这类台账时, 有效期被静默改写成当前时刻 (JS 得 505296000, Swift 旧版得"现在")。
    /// 解析结果 → 下发用的**无符号**协议秒收口。
    /// (2026-10-17 全量盘点: 基准改成"本地 2010-01-01"后, '2010-01-01 00:00:00' 自然解析为 0;
    ///  这里的 max(0,…) 仍是**护栏** —— 早于 2010 的输入不允许回绕成未来时间。)
    /// 2026-10-17 真机勘误 (「添加密码/指纹成功但解不开」): `protoSec` 对 '2010-01-01 00:00:00' 走的是
    /// 「按**本地时区**解析 − 2010-01-01T00:00:00**Z** 基准」, 在东八区得 −28800; 而旧的下发写法
    /// `UInt32(truncatingIfNeeded:)` 把它**静默回绕**成 4294938496 (≈2146-02-06)。于是「永久」有效期
    /// 被写成 [2146 … 2118] —— 锁照收 (rc=0)、台账照记「已添加」, 但任何时刻都不在窗口内 ⇒ 密码/指纹
    /// 添加成功却永远解不开。原 APK 同一字段走 getProtocolTimeSecond('2010-01-01 00:00:00') = **0**
    /// (被减数与减数是同一个本地时刻), 所以永久窗口下界就是 0。这里以 0 为下界收口,
    /// 顺带让任何早于 2010 的输入不再回绕到未来。
    static func protoSecU32(_ v: String?) -> UInt32 { UInt32(clamping: max(0, protoSec(v))) }
    static func protoSecOrNil(_ s: String?) -> Int64? { protoSecRawOrNil(s).map { max(0, $0) } }
    /// 原样解析 (可能为负, 只给 protoSecOrNil 用)
    private static func protoSecRawOrNil(_ s: String?) -> Int64? {
        guard let raw = s?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        // 纯数字: 秒或毫秒。**这一档是刻意比 JS 宽**，不是"同口径"：
        // JS 的 protoSec 只在 `typeof v === 'number'` 时当数字用，数字**字符串**会走 Date.parse
        // ("1760000000" → "1760000000T00:00:00Z") → 解析失败 → 静默回落"现在" (实测 JS 与本机时钟同值)。
        // 台账导入的 from/to 常以字符串形态存 epoch，跟着 JS 走就等于把有效期静默改写成今天 —— 宁可多认一种形态。
        if let n = Int64(raw) { return n > 1_000_000_000_000 ? n / 1000 : n }
        let iso = ISO8601DateFormatter()          // 含 …THH:mm:ssZ / 带偏移 形态
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return ZKProtocol.protoSecondsFromMs(Int64(d.timeIntervalSince1970 * 1000)) }
        let iso2 = ISO8601DateFormatter()
        iso2.formatOptions = [.withInternetDateTime]
        if let d = iso2.date(from: raw) { return ZKProtocol.protoSecondsFromMs(Int64(d.timeIntervalSince1970 * 1000)) }
        func f(_ fmt: String, _ tz: TimeZone) -> Int64? {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = tz
            df.dateFormat = fmt
            guard let d = df.date(from: raw) else { return nil }
            return ZKProtocol.protoSecondsFromMs(Int64(d.timeIntervalSince1970 * 1000))
        }
        let cur = TimeZone.current
        return f("yyyy-MM-dd HH:mm:ss", cur) ?? f("yyyy-MM-dd'T'HH:mm:ss", cur)
            ?? f("yyyy-MM-dd HH:mm", cur) ?? f("yyyy-MM-dd'T'HH:mm", cur)
            ?? f("yyyy-MM-dd", TimeZone(identifier: "UTC") ?? cur)   // JS: 日期-only 追加 T00:00:00Z → UTC
    }
    /// 允许回落"现在"的形态 (仅用于代码里的字面量与"未填=现在"语义)
    static func protoSec(_ v: String?) -> Int64 { protoSecOrNil(v) ?? ZKProtocol.nowProtoSeconds() }

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
    /// `order` 只有配网期的"MAC 字节序只读探针"会显式传 (见 LockService.calibrateMacOrder);
    /// 其余调用点一律 nil = 按本机对这把锁已裁定的顺序 (默认原版 APK 语义)。
    static func cmd03StatusWrap(_ macHex: String, _ skeyHex: String, order: ZKProtocol.MacOrder? = nil) -> ZKCmd {
        let enc = AESKit.encryptHex(ZKProtocol.buildEkey(0x03, macHex, order: order), keyHex: skeyHex)
        // 空密文 = skey 非法/CCCrypt 失败: 不能再包成帧 (旧写法会发出 KLV#01 长度为 0 的假请求)
        if enc.isEmpty { return ZKCmd(name: "03 加密状态", cmd: 0x03, hex: "") }
        let klv = ZKProtocol.buildKLV(0x01, enc) + ZKProtocol.buildKLV(0x02, "")
        return ZKCmd(name: "03 加密状态", cmd: 0x03, hex: ZKProtocol.buildFrame(0x03, klv, header: 8))
    }
    // cmd 04 OPEN: KLV#01 = 左补零 32; KLV#02 = 凭证密文
    static func cmd04Open(_ ekeyHex: String, klv01Hex: String = "0000") -> ZKCmd {
        // 空 ekey (签发时 AESKit 失败 / 钥匙串里 ekey 为空) 绝不能发给锁: 旧写法会组出
        // "KLV#02 长度 0" 的开锁帧, 既可能被固件当异常包丢弃, 也可能被误读成一次真实开锁尝试。
        if ekeyHex.isEmpty { return ZKCmd(name: "04 开锁", cmd: 0x04, hex: "") }
        let klv = ZKProtocol.buildKLV(0x01, HexKit.fillZeroLeft(klv01Hex, 32)) + ZKProtocol.buildKLV(0x02, ekeyHex)
        return ZKCmd(name: "04 开锁", cmd: 0x04, hex: ZKProtocol.buildFrame(0x04, klv, header: 8))
    }
    // pin → LE 4B hex (数字或已是 8 hex 皆可 — JS pinToLE 双兼容)
    // 旧写法解析失败时回落 "00000000": 那是一个**合法 PIN 值**, 于是"读不到的钥匙"会被签成
    // 一条 pin=0 的 ekey 发给锁 —— 既可能是错误凭证, 也会在锁端留下一次真实开锁尝试。改为显式失败。
    static func pinToLEOrNil(_ pin: String) -> String? {
        var h = pin.trimmingCharacters(in: .whitespaces).lowercased()
        if h.hasPrefix("0x") { h = String(h.dropFirst(2)) } // JS: replace(/^0x/i, '')
        if h.count == 8, h.allSatisfy({ $0.isHexDigit }) { return h }
        guard !h.isEmpty, let v = UInt32(h) else { return nil }
        return HexKit.u32leHex(v)
    }
    // ekey (开锁凭证) = AES(skey)($t 包络); JS buildEkeyOpen/buildEkeyShare
    static func buildEkeyOpen(_ skeyHex: String, _ macHex: String, _ pin: String,
                              validFromSec: UInt32 = 0, validToSec: UInt32? = nil, trackId: UInt32 = 0) -> String {
        // PIN 解析失败 = 凭证不可用, 整条 ekey 视为签发失败 (返回 "" 由 cmd04Open 的空值闸拦下)
        guard let pinLE = pinToLEOrNil(pin) else { return "" }
        let env = ZKProtocol.buildEkey(0x04, macHex, validFromSec: validFromSec, validToSec: validToSec, trackIdVal: trackId)
            + pinLE + "00" + "00"
        return AESKit.encryptHex(env, keyHex: skeyHex)
    }
    // App generateEkey (分享/写钥匙串): 随机 TrackId + 本地时区 2010~2118 窗口
    static func buildEkeyShare(_ skeyHex: String, _ macHex: String, _ pin: String,
                               random: (UInt32) -> UInt32) -> String {
        // 2026-10-14: 删掉从未使用的 DateFormatter f (实际解析走 protoSec) —— 免得误以为此处按本地时区解析。
        // JS: '2010-01-01T00:00:00' 本地解释 ⇒ 东八区为 −28800; 经 protoSecU32 收口成 0 (= APK 的取值)
        let vf = protoSecU32("2010-01-01 00:00:00")
        let vt = protoSecU32("2118-01-01 00:00:00")
        return buildEkeyOpen(skeyHex, macHex, pin, validFromSec: vf, validToSec: vt, trackId: random(0x7fffffff))
    }
    // cmd 08: addCount(1B)+delCount(1B)+addPins(4B LE×N)+delPins(4B LE×M)
    static func cmd08SyncPinsBatch(_ macHex: String, _ skeyHex: String, _ addPins: [String], delPins: [String] = []) -> ZKCmd? {
        if addPins.count > 20 { return nil }
        var body = HexKit.hexPair(UInt32(addPins.count)) + HexKit.hexPair(UInt32(delPins.count))
        body += addPins.joined()
        body += delPins.joined()
        return ZKCmd(name: "08 PIN 批量", cmd: 0x08, hex: ZKProtocol.wrapFrame(0x08, macHex, skeyHex, body, 0x01))
    }
    // cmd 21: skeyLen(1B=0x10)+bkey(16B)
    static func cmd21SetBkey(_ macHex: String, _ skeyHex: String, _ bkeyHex: String) -> ZKCmd {
        let body = "10" + bkeyHex
        return ZKCmd(name: "21 bkey", cmd: 0x21, hex: ZKProtocol.wrapFrame(0x21, macHex, skeyHex, body, 0x02))
    }
    // cmd 0A: delAlias(2B LE, 0xFFFF=清空) + addPwd(8B ASCII 右补零) + validFrom/To(4B LE)
    static func cmd0ASyncPwd(_ macHex: String, _ skeyHex: String, delAlias: Int = 0, addPwd: String = "", validFrom: String? = nil, validTo: String? = nil) throws -> ZKCmd {
        guard addPwd.utf16.count <= 8 else { throw BLEErrorX.msg("密码最长 8 位") } // JS throw — 不静默截断
        // 有效期: 未提供 (nil) 按 JS 口径取"现在"; 提供了但解析不出来则必须中止 ——
        // 旧写法一律回落"现在", 于是导入 ISO 形态 (`2026-01-05T08:00:00Z`) 的台账会把有效期静默改写。
        // 2026-10-14 对抗式排查: 上一批只把 validTo 改成了 throw, validFrom 仍静默回落 —— 补齐。
        func suppliedButUnparsed(_ s: String?) -> Bool {
            guard let s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            return protoSecOrNil(s) == nil
        }
        if suppliedButUnparsed(validFrom) {
            throw BLEErrorX.msg("密码生效时间无法解析: \(validFrom ?? "") (支持 ISO8601/带 Z、'yyyy-MM-dd HH:mm:ss'、秒/毫秒) — 已中止下发")
        }
        let from = protoSecOrNil(validFrom) ?? ZKProtocol.nowProtoSeconds()
        let to: Int64
        if let v = protoSecOrNil(validTo) { to = v }
        else if validTo == nil || validTo?.isEmpty == true { to = ZKProtocol.nowProtoSeconds() }
        else { throw BLEErrorX.msg("密码有效期无法解析: \(validTo ?? "") (支持 ISO8601/带 Z、'yyyy-MM-dd HH:mm:ss'、秒/毫秒) — 已中止下发") }
        let body = u16leHex(delAlias)
            + HexKit.asciiHex(addPwd, nBytes: 8)
            + HexKit.u32leHex(UInt32(clamping: max(0, from)))
            + HexKit.u32leHex(UInt32(clamping: max(0, to)))
        return ZKCmd(name: "0A 同步密码", cmd: 0x0a, hex: ZKProtocol.wrapFrame(0x0a, macHex, skeyHex, body, 0x01))
    }
    // cmd 0B: alias(2B LE) + validFrom/To
    static func cmd0BSyncPwdExpire(_ macHex: String, _ skeyHex: String, _ alias: Int, _ validFrom: String?, _ validTo: String?) -> ZKCmd {
        // 同 0A: 传了但解析不出 = 不组帧 (空 hex 由 LockService 的空帧闸拦下并报错), 不静默用"现在"顶替
        func suppliedButUnparsed(_ s: String?) -> Bool {
            guard let s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            return protoSecOrNil(s) == nil
        }
        if suppliedButUnparsed(validFrom) || suppliedButUnparsed(validTo) {
            return ZKCmd(name: "0B 密码有效期", cmd: 0x0b, hex: "")
        }
        let from = protoSecOrNil(validFrom) ?? ZKProtocol.nowProtoSeconds()
        let to = protoSecOrNil(validTo) ?? ZKProtocol.nowProtoSeconds()
        let body = u16leHex(alias)
            + HexKit.u32leHex(UInt32(clamping: max(0, from)))
            + HexKit.u32leHex(UInt32(clamping: max(0, to)))
        return ZKCmd(name: "0B 密码有效期", cmd: 0x0b, hex: ZKProtocol.wrapFrame(0x0b, macHex, skeyHex, body, 0x01))
    }
    // cmd 0E: syncTime(4B LE 协议秒)
    static func cmd0ESyncTime(_ macHex: String, _ skeyHex: String, _ timeSec: Int64) -> ZKCmd {
        let body = HexKit.u32leHex(UInt32(truncatingIfNeeded: timeSec))
        return ZKCmd(name: "0E 时间同步", cmd: 0x0e, hex: ZKProtocol.wrapFrame(0x0e, macHex, skeyHex, body, 0x02))
    }
    // cmd 13: times(1B) + timeout(1B)
    static func cmd13AddFp(_ macHex: String, _ skeyHex: String, _ times: Int = 8, _ timeout: Int = 15) -> ZKCmd {
        // 兜底对齐 JS cmds.js:119-120 (times||8, timeout<=0→15)
        let t = times > 0 ? times : 8
        let to = timeout > 0 ? timeout : 15
        let body = HexKit.hexPair(UInt32(truncatingIfNeeded: t)) + HexKit.hexPair(UInt32(truncatingIfNeeded: to))
        return ZKCmd(name: "13 录指纹", cmd: 0x13, hex: ZKProtocol.wrapFrame(0x13, macHex, skeyHex, body, 0x02))
    }
    // cmd 14: batchNumber(4B LE) + validFrom/To
    static func cmd14FpConfirm(_ macHex: String, _ skeyHex: String, _ batchNumber: UInt32, _ validFrom: String?, _ validTo: String?) -> ZKCmd {
        let body = HexKit.u32leHex(batchNumber)
            + HexKit.u32leHex(protoSecU32(validFrom))
            + HexKit.u32leHex(protoSecU32(validTo))
        return ZKCmd(name: "14 指纹确认", cmd: 0x14, hex: ZKProtocol.wrapFrame(0x14, macHex, skeyHex, body, 0x02))
    }
    // cmd 15: batchNumber(4B LE)
    static func cmd15DeleteFp(_ macHex: String, _ skeyHex: String, _ batchNumber: UInt32) -> ZKCmd {
        ZKCmd(name: "15 删指纹", cmd: 0x15, hex: ZKProtocol.wrapFrame(0x15, macHex, skeyHex, HexKit.u32leHex(batchNumber), 0x02))
    }
    // cmd 16: orderType(1B) + startIdx(4B LE) + pageSize(1B)
    static func cmd16GetLog(_ macHex: String, _ skeyHex: String, orderType: Int = 0, startIdx: UInt32 = 0, pageSize: Int = 20) -> ZKCmd {
        // 兜底对齐 JS cmds.js:138 (pageSize||20)
        let size = pageSize > 0 ? pageSize : 20
        let body = HexKit.hexPair(UInt32(truncatingIfNeeded: orderType)) + HexKit.u32leHex(startIdx) + HexKit.hexPair(UInt32(truncatingIfNeeded: size))
        return ZKCmd(name: "16 日志", cmd: 0x16, hex: ZKProtocol.wrapFrame(0x16, macHex, skeyHex, body, 0x01))
    }
    // cmd 18: vol(1B) — App setSilentMode 语义: 0=有声 1=静音
    static func cmd18Volume(_ macHex: String, _ skeyHex: String, _ silent: Bool) -> ZKCmd {
        ZKCmd(name: "18 音量", cmd: 0x18, hex: ZKProtocol.wrapFrame(0x18, macHex, skeyHex, HexKit.hexPair(UInt32(silent ? 1 : 0)), 0x02))
    }
    // cmd 19: status(1B 0=关/1=开)
    static func cmd19OpenZotp(_ macHex: String, _ skeyHex: String, _ on: Bool) -> ZKCmd {
        ZKCmd(name: "19 ZOTP", cmd: 0x19, hex: ZKProtocol.wrapFrame(0x19, macHex, skeyHex, HexKit.hexPair(UInt32(on ? 1 : 0)), 0x02))
    }
    // cmd 20: mode(1B 0=A单验/1=B双验)
    static func cmd20ValidationMode(_ macHex: String, _ skeyHex: String, _ bMode: Bool) -> ZKCmd {
        ZKCmd(name: "20 验证模式", cmd: 0x20, hex: ZKProtocol.wrapFrame(0x20, macHex, skeyHex, HexKit.hexPair(UInt32(bMode ? 1 : 0)), 0x02))
    }
    // cmd 22: enableDFUstate param(1B, 0 → 重启进 bootloader)
    static func cmd22EnableDfu(_ macHex: String, _ skeyHex: String, _ param: Int = 0) -> ZKCmd {
        ZKCmd(name: "22 DFU", cmd: 0x22, hex: ZKProtocol.wrapFrame(0x22, macHex, skeyHex, HexKit.hexPair(UInt32(param & 0xff)), 0x02))
    }
    // cmd 24: interval(1B 档位 1-6)
    static func cmd24AutoLock(_ macHex: String, _ skeyHex: String, _ interval: Int) -> ZKCmd {
        ZKCmd(name: "24 自动上锁", cmd: 0x24, hex: ZKProtocol.wrapFrame(0x24, macHex, skeyHex, HexKit.hexPair(UInt32(truncatingIfNeeded: interval)), 0x01))
    }
    // cmd 25: control(1B) + start(4B LE) + end(4B LE)
    static func cmd25Defence(_ macHex: String, _ skeyHex: String, _ control: Int, _ startSec: Int, _ endSec: Int) -> ZKCmd {
        let body = HexKit.hexPair(UInt32(truncatingIfNeeded: control)) + HexKit.u32leHex(UInt32(truncatingIfNeeded: startSec)) + HexKit.u32leHex(UInt32(truncatingIfNeeded: endSec))
        return ZKCmd(name: "25 布防", cmd: 0x25, hex: ZKProtocol.wrapFrame(0x25, macHex, skeyHex, body, 0x01))
    }

    // ---- 钥匙串硬件 (ZKBBV1 pid=16289; 87 帧明文 KLV, needToken=false) ----
    static func cmd41WriteEkey(_ lockMacHex: String, _ pid: Int, _ ekeyHex: String, type: Int = 1) -> ZKCmd {
        // 2026-10-14: 与 cmd43 / buildEkey 同口径先剥冒号, 否则带冒号 MAC 使 reversePairs 返回空串。
        let klv = ZKProtocol.buildKLV(0x01, HexKit.reversePairs(ZKProtocol.targetMac(lockMacHex)))
            + ZKProtocol.buildKLV(0x02, HexKit.hexPair(UInt32(truncatingIfNeeded: type)))
            + ZKProtocol.buildKLV(0x03, u16leHex(pid))
            + ZKProtocol.buildKLV(0x04, ekeyHex)
        return ZKCmd(name: "41 钥匙串写钥", cmd: 0x41, hex: ZKProtocol.buildFrame(0x41, klv, header: 8))
    }
    static func cmd44GetEkeyInfo(_ lockMacHex: String?) -> ZKCmd {
        // 2026-10-14: 去掉强解包 (空 = 查全部钥匙, 与旧口径一致), 并把剥冒号/小写收在前一行。
        let m = (lockMacHex ?? "").replacingOccurrences(of: ":", with: "").lowercased()
        let v = m.isEmpty ? "" : HexKit.reversePairs(ZKProtocol.targetMac(m))
        return ZKCmd(name: "44 钥匙串查钥", cmd: 0x44, hex: ZKProtocol.buildFrame(0x44, ZKProtocol.buildKLV(0x01, v), header: 8))
    }
    static func cmd43KeychainStatus(_ lockMacList: [String]) -> ZKCmd {
        var v = ""
        for m in lockMacList { v += HexKit.reversePairs(ZKProtocol.targetMac(m)) }
        return ZKCmd(name: "43 钥匙串状态", cmd: 0x43, hex: ZKProtocol.buildFrame(0x43, ZKProtocol.buildKLV(0x01, v), header: 8))
    }

    // ---- 网关 (FE90 服务; 87 帧明文 KLV, needToken=false) ----
    static func cmd38GWStatus() -> ZKCmd {
        ZKCmd(name: "38 网关状态", cmd: 0x38, hex: ZKProtocol.buildFrame(0x38, "", header: 8))
    }
    static func cmd31GWSetWifi(_ ssid: String, _ password: String, authMode: Int = 8, encryptType: Int = 0) -> ZKCmd {
        let klv = ZKProtocol.buildKLV(0x01, HexKit.utf8Hex(ssid))
            + ZKProtocol.buildKLV(0x02, HexKit.utf8Hex(password))
            + ZKProtocol.buildKLV(0x03, HexKit.hexPair(UInt32(truncatingIfNeeded: authMode)))
            + ZKProtocol.buildKLV(0x04, HexKit.hexPair(UInt32(truncatingIfNeeded: encryptType)))
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
