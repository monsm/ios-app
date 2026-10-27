// ZK 0x87 帧协议层 — JS utils/kernel/protocol.js 的逐行移植
//   请求帧 (8B 头, Java 生产链格式): 87 00 len:2 LE cmd 000000 [KLV...]
//   兼容变体: 10B 头 (87 00 len cmd ssToken:2 000000) / 7B 头 (87 01 len cmd dlen:2)
//   0x88 EKey 包络: 88 00 MAC反转 TrackId:4LE validFrom:4LE validTo:4LE cmd body
//   会话令牌注入: KLV#0xEE (固件 0x253FE 特判通道)
// 差分基准: golden.cmds.* / golden.parse.*
import Foundation

struct ZKLV: Equatable {
    var key: Int
    var val: String   // hex
    var vlen: Int
}

enum ZKProtocol {
    // 2026-10-27 审核说明 (AUDIT-C A13)：时间基准（本地 2010 基准 + 有效期到 2118 + 三条换算出口）
    // **只有本仓有** —— Android 完全不涉及（它不发 0E/05/0A/0B，也就不需要时间）。
    // 后果：Android 侧 rc=3（命令过期）只能报错不能自愈；
    // 本仓有 `AutoOpen.selfHealTime` → `syncTime()` 这条自愈链。
    // 协议时间基准 = **本地** 2010-01-01 00:00:00 (2026-10-17 全量盘点勘误: 旧值 1_262_304_000_000 是
    // 2010-01-01T00:00:00**Z**, 比 APK 少一个时区偏移)。
    //   依据 (逐字): APK `En.getProtocolTimeSecond(x) = An.getDate(x) − An.getDate('2010-01-01 00:00:00')`,
    //   而 `An.getDate` 是 `new Date(y, m-1, d, h, mi, s)` —— 被减数与减数都在**本地墙钟**上, 时区自己消掉。
    //   东八区里同一时刻的协议秒 = UTC 基准值 + 28800; 锁钟/0E/05/0A/0B/14 全用这一口径。
    static let epochMs: Int64 = {
        var c = DateComponents()
        c.year = 2010; c.month = 1; c.day = 1; c.hour = 0; c.minute = 0; c.second = 0
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        guard let d = cal.date(from: c) else { return 1_262_304_000_000 }   // 理论不可达; 回落旧值
        return Int64((d.timeIntervalSince1970 * 1000).rounded())
    }()
    static func protoSecondsFromMs(_ ms: Int64) -> Int64 { (ms - epochMs) / 1000 }
    static func nowProtoSeconds() -> Int64 { protoSecondsFromMs(Int64(Date().timeIntervalSince1970 * 1000)) }
    static func protoSecondsToMs(_ sec: Int64) -> Int64 { epochMs + sec * 1000 }
    /// 协议秒 → Unix 秒。**Swift 侧便利出口，JS 里没有对应函数**（JS 那边是 `protoTime(x)/1000` 就地写）。
    /// 与 `Double(protoSecondsToMs(sec)) / 1000` 逐值相等：`epochMs` 是整千毫秒 (1_262_304_000_000)，
    /// 绕一圈毫秒再除回来不丢任何位数。此前全仓 14 处各写一遍这条绕路，其中一处还把除法放进了
    /// `Int64` 里（靠"恰好整千"才没截断）—— 那种形状下次被人改成 `/1000.0` 或换常数基准就静默漂，
    /// 所以收成一份并由 `swiftlint` 检查⑩ 盯住 (§10.32)。
    static func protoSecondsToUnix(_ sec: Int64) -> Double { Double(sec) + Double(epochMs / 1000) }
    // 默认有效止 (buildEkey 的默认 VT) = JS protoTime('2118-01-01T00:00:00') 本地口径 = **3_408_134_400**。
    //   2026-10-17 对拍勘误: 旧写法 `protoSecondsFromMs(4_670_438_400_000)` 里的 4_670_438_400 是
    //   **2118-01-01T00:00:00Z** 的 Unix 秒, 拿它减"本地 2010"基准 ⇒ 凭空多一个时区偏移 (+28800),
    //   东八区算得 3_408_163_200, 而 JS `buildEkey` 的默认 vt 是 3_408_134_400 (= 本地 2118 − 本地 2010,
    //   108 年整, 与机器时区无关)。差 8 小时: 对 2118 年这个上界无害, 但 08/0A/0B/0E/13/14/15/16/18/19/
    //   20/21/24/25 的**包络 VT 与金标逐字节不一致** —— 而 cmdsshadow 的影子副本用的是 JS 值,
    //   于是这道闸门一直是"假绿"(它没有忠实复刻这一行)。
    static let validTo2118: UInt32 = 3_408_134_400

    // ---------- KLV ----------
    static func buildKLV(_ key: Int, _ valHex: String) -> String {
        // 2026-10-27 审核修复 (AUDIT-D D-15)：长度字段只占 1 字节（协议规定），
        // 而 `hexPair(UInt32(len))` 对 len ≥ 256 会**静默截断**成低 8 位 ——
        // 帧长度对不上，锁端会按错误长度解析后面所有 KLV。
        //
        // 当前调用点最大值是 ekey（30 字节）、WiFi 口令（≤64 字节），都不触发。
        // 但这是定时炸弹：将来有人往 KLV 里塞固件分片或长日志就会踩。
        //
        // 处置：超长时**显式截到 255 字节**并记一条遥测（不用 assertionFailure ——
        // `project.yml` 的 Release 配置显式关断言，那种写法在真机包上等于没有校验）。
        // 截断而不是返回空串：空串会让上层构造出载荷为空的帧，反而更难定位。
        var v = valHex
        let rawLen = v.count / 2
        if rawLen > 0xFF {
            v = String(v.prefix(0xFF * 2))
            BleTelemetry.recordEvent("buildKLV 超长截断: key=\(key) \(rawLen)→255 字节", ok: false)
        }
        let len = v.count / 2
        return HexKit.hexPair(UInt32(key)) + HexKit.hexPair(UInt32(len)) + v
    }
    static func parseKLV(_ hex: String) -> [ZKLV]? {
        let b = HexKit.bytes(hex)
        var out = [ZKLV]()
        var off = 0
        while off < b.count {
            guard off + 2 <= b.count else { return nil }
            let key = Int(b[off])
            let len = Int(b[off + 1])
            guard off + 2 + len <= b.count else { return nil }
            let val = HexKit.hex(Array(b[(off + 2)..<(off + 2 + len)]))
            out.append(ZKLV(key: key, val: val, vlen: len))
            off += 2 + len
        }
        return out
    }

    // ---------- 帧构造 (JS buildFrame: header 8 = Java 生产链; 其余 = 10B 旧 JS 格式) ----------
    static func buildFrame(_ cmd: UInt8, _ klvHex: String, ssToken: String = "0000", header: Int = 8) -> String {
        let klv = klvHex
        let len = klv.count / 2
        // 出口统一大写: JS 侧 fillZeroHex 一律 toUpperCase()。字节层无差异 (radix16 不分成小写),
        // 但金标差分是**字符串级**比对, 大小写不同会造出假差异。
        if header == 8 {
            return ("87" + "00" + HexKit.hexPair(UInt32(len & 0xff)) + HexKit.hexPair(UInt32((len >> 8) & 0xff))
                + HexKit.hexPair(UInt32(cmd)) + "000000" + klv).uppercased()
        }
        return ("87" + "00" + HexKit.hexPair(UInt32(len & 0xff)) + HexKit.hexPair(UInt32((len >> 8) & 0xff))
            + HexKit.hexPair(UInt32(cmd)) + ssToken + "000000" + klv).uppercased()
    }

    // ---------- 0x88 包络里的 MAC 字节序 (per MAC, 真机裁定) ----------
    /// 0x88 包络里那 6 字节 MAC 有两个参照实现各写了一种取法, 而锁只认一种:
    ///   · `.display` — 原版 APK (main.js 的 `kt.getBytes`): `TargetMAC` 取 `BluetoothDevice.getAddress()`
    ///     (**显示序**, 也是页面/台账里那个值), 而 getBytes 自己会按字节对翻转一次 ⇒ 包络里落**线上序**;
    ///   · `.raw` — 小程序旁支 (services/ble.js 把 `adv.mac` 别名成 `macRaw`): TargetMAC 直接给**线上序**,
    ///     翻转后包络里落**显示序**。
    /// 差的就是这 6 字节的先后。认错的表现是锁回 rc=12「mac地址不正确」—— 而 rc≠0 的语义是
    /// "锁什么都没执行", 所以**试错本身不改锁** (见 docs/BRICK-AUDIT.md §10)。裁定不靠猜: 配网期拿
    /// **只读**的 03 当探针 (它同样带 MAC, 却不落任何状态), 谁 rc=0 谁对, 结果记在 `kf_macorder_<mac>`。
    /// 不认识时**默认 `.display`** = 原版 APK 语义, 于是未裁定的锁与金标 (`fixtures/golden.json` 的
    /// cmds.*, 逐字节按显示序烘的) 完全一致 —— 这也是本仓唯一的"生产链"口径。
    enum MacOrder: String { case display, raw }

    /// 内存注册表: 只有 DB 的落盘口与配网探针会写它 (协议层不读库, 免得 Core 里绕成环)。
    /// 进程重启后由 `DB.hydrateMacOrders()` 在启动窗口补上, 补不上的锁会走一次 rc=12 自愈再学习。
    private static let macOrdersLock = Locked([String: MacOrder]())
    /// 2026-10-27 审核合并 (AUDIT-C A11)：转调 `DB.normalizeMac`，不再各写一遍。
    /// 原先这里是 `lowercased() + 去冒号`（顺序与 DB 那版相反，且不去连字符）——
    /// 两份实现行为不同，是本仓「同一概念两处实现」的典型。
    static func normMac(_ s: String) -> String { DB.normalizeMac(s) }
    static func setMacOrder(_ mac: String, _ o: MacOrder) { macOrdersLock.withLock { $0[normMac(mac)] = o } }
    static func macOrder(_ mac: String) -> MacOrder { macOrdersLock.withLock { $0[normMac(mac)] } ?? .display }
    static func flipped(_ o: MacOrder) -> MacOrder { o == .display ? .raw : .display }
    /// 交给 `buildEkey` 的那个 TargetMAC 串 (它内部还会按字节对翻转一次)
    static func targetMac(_ macHex: String, order: MacOrder? = nil) -> String {
        let m = normMac(macHex)
        return (order ?? macOrder(m)) == .raw ? HexKit.reversePairs(m) : m
    }

    // ---------- 0x88 EKey 包络 ----------
    static func buildEkey(_ cmd: UInt8, _ macHex: String,
                          validFromSec: UInt32 = 0,
                          validToSec: UInt32? = nil,
                          trackIdVal: UInt32 = 0,
                          order: MacOrder? = nil) -> String {
        let vt = validToSec ?? validTo2118
        var mac = targetMac(macHex, order: order)
        if mac.isEmpty { mac = "000000000000" }
        return "8800" + HexKit.reversePairs(mac)
            + HexKit.u32leHex(trackIdVal)
            + HexKit.u32leHex(validFromSec)
            + HexKit.u32leHex(vt)
            + HexKit.hexPair(UInt32(cmd))
    }

    // 密文包络封装 (JS wrapEnc): body → EKey(cmd,mac) → AES(skey) → KLV#klvKey
    // ---------- 试验模式硬护栏 (JS kernel/protocol.js:19-27 READONLY_CMDS / WRITE_CMDS_BLOCKED / assertReadOnly) ----------
    // Swift 侧此前整块缺失: 小程序用它在真机上做只读试验, 保证任何写入/危险命令 (05 换钥会擦 flash 域 7+8 作废旧钥匙、
    // 04 开门、08 同步 PIN、31 写网关 WiFi 口令等) 一律发不出去。缺了它 = 缺一道防误操作保险。
    static let readonlyCmds: Set<UInt8> = [0x01, 0x02, 0x03, 0x12, 0x16, 0x23, 0x30, 0x38]
    static let writeCmdsBlocked: [UInt8] = [0x04, 0x05, 0x08, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x13, 0x14, 0x15,
                                            0x18, 0x19, 0x20, 0x21, 0x22, 0x24, 0x25, 0x31, 0x32, 0x35, 0x41, 0x43, 0x44]
    /// 只读模式下放行只读命令, 其余抛错 (与 JS 同语义)
    static func assertReadOnly(_ cmd: UInt8) throws {
        guard readonlyCmds.contains(cmd) else {
            throw BLEErrorX.msg(String(format: "护栏拦截: cmd 0x%02x 是写入/危险命令, 只读试验模式禁止发送!", cmd))
        }
    }

    /// 密文管理面的**成帧收口**: wrapEnc 失败 (skey 非 16B / CCCrypt 失败 → 空密文) 时整帧返回 ""。
    /// 旧写法 buildFrame(cmd, wrapEnc(...)) 会把失败值包成"含空值 KLV 的完整帧", 于是
    /// `hex.isEmpty` 永不成立、08/0A/13/14/15/18/19/20/21/0B/0E/16/24/25 全部照样发给锁。
    static func wrapFrame(_ cmd: UInt8, _ macHex: String, _ skeyHex: String, _ bodyHex: String, _ klvKey: Int,
                          order: MacOrder? = nil) -> String {
        let enc = wrapEnc(cmd, macHex, skeyHex, bodyHex, klvKey, order: order)
        return enc.isEmpty ? "" : buildFrame(cmd, enc, header: 8)
    }

    static func wrapEnc(_ cmd: UInt8, _ macHex: String, _ skeyHex: String, _ bodyHex: String, _ klvKey: Int,
                        order: MacOrder? = nil) -> String {
        let env = buildEkey(cmd, macHex, order: order) + bodyHex
        let cipher = AESKit.encryptHex(env, keyHex: skeyHex)
        // AESKit 在 skey 非 16B / CCCrypt 失败时返回 "" (JS crypto.js 是 throw)。
        // 空串若继续 buildKLV 会得到 "key len=0" 的空值密文 KLV 并真的发给锁 (08/0A/13/14/18/24/25 写命令面)。
        // 这里以空帧作失败标记, 由 LockService.request 在下发前拦死。
        return cipher.isEmpty ? "" : buildKLV(klvKey, cipher)
    }

    // ---------- 令牌注入 (KLV#0xEE; 头型自适应 8B/10B) ----------
    // 2026-10-27 审核说明 (AUDIT-A F-48)：`injectToken` 的 8B/10B 自适应三端一致，
    // 但 Android 那侧有一处冗余（多判了一次长度），行为相同、代码略重复。
    // 不影响协议，仅代码整洁度问题。
    static func injectToken(_ hex: String, _ tokenHex: String) -> String {
        guard !tokenHex.isEmpty, hex.count >= 16 else { return hex }
        let len = HexKit.readU16LE(hex, byteOffset: 2)
        // 2026-10-27 审核说明 (AUDIT-A F-08)：cmd 字节位置在三种帧头（8/7/10 字节）下**都写死字节 4**。
        // 三端（iOS / Android / vendor JS）在此完全一致 —— 这是协议事实：长度字段恒在字节 2-3，
        // 所以 cmd 恒在 4。7 字节头的差异只在 KLV 起始位置，不在 cmd 位置。
        let cmd = HexKit.bytes(hex)[4]
        let header10 = hex.count >= 20 + len * 2
        let bodyStart = header10 ? 20 : 16
        guard hex.count >= bodyStart + len * 2 else { return hex }
        let body = String(hex.dropFirst(bodyStart).prefix(len * 2))
        let klv = body + buildKLV(0xEE, tokenHex)
        return header10 ? buildFrame(cmd, klv, ssToken: String(hex.dropFirst(10).prefix(4)), header: 10)
                        : buildFrame(cmd, klv, ssToken: "0000", header: 8)
    }

    // ---------- 响应解析 (三头型兼容; 8B 头首选 — Java 生产链恒按 8B 消费) ----------
    struct ParsedFrame {
        var ok: Bool
        var cmd: UInt8
        var header: Int
        var klvs: [ZKLV]
        var raw: String
    }
    static func parseResponse(_ hex: String) -> ParsedFrame {
        guard hex.count >= 14 else { return ParsedFrame(ok: false, cmd: 0, header: 0, klvs: [], raw: hex) }
        let b = HexKit.bytes(hex)
        let versionByte = Int(b[1])
        let len = HexKit.readU16LE(hex, byteOffset: 2)
        var orders: [Int]
        if versionByte == 0x01 { orders = [8, 7, 10] }
        else if versionByte == 0x10 { orders = [8, 10, 7] }
        else { orders = [8, 10, 7] }
        var results: [ParsedFrame] = []
        for bodyOff in orders {
            if b.count < bodyOff + len { continue }
            let klvHex = String(hex.dropFirst(bodyOff * 2).prefix(len * 2))
            guard let klvs = parseKLV(klvHex) else { continue }
            // cmd 字节位置: 三种帧头均为字节 4
            results.append(ParsedFrame(ok: true, cmd: b[4], header: bodyOff, klvs: klvs, raw: hex))
        }
        // 2026-10-27 审核补强 (AUDIT-D D-16)：三种头型**都会被尝试**，取第一个解析成功的 ——
        // 而畸形回包可能被"猜"成一个结构合法但语义错位的帧（KLV 从错误偏移开始读，
        // 恰好也能切出几个合法段）。协议没有校验和，客户端无法完全分辨。
        // 能做的是：**多个候选同时成立时记遥测** —— 正常帧只有一种头型能解析成功，
        // 出现多解说明收到的字节有问题，值得在日志里留痕（而不是静默取第一个）。
        if results.count > 1 {
            let others = results.dropFirst().map { String($0.header) }.joined(separator: "/")
            BleTelemetry.recordEvent(
                "回包帧头歧义: \(results.count) 种头型都能解析, 取 header=\(results[0].header), 其余 \(others)",
                ok: false)
        }
        if let first = results.first { return first }
        return ParsedFrame(ok: false, cmd: 0, header: 0, klvs: [], raw: hex)
    }

    // ---------- 粘包/多帧重组 (JS services/ble.js makeAssembler 逐行移植) ----------
    final class FrameAssembler {
        private var buf = ""
        func reset() { buf = "" }
        func push(_ chunkHex: String) -> [ParsedFrame] {
            buf += chunkHex
            var frames = [ParsedFrame]()
            while true {
                guard let idx = buf.range(of: "87") else { buf = ""; break }
                if idx.lowerBound > buf.startIndex { buf = String(buf[idx.lowerBound...]) }
                if buf.count < 14 { break }
                let len = HexKit.readU16LE(buf, byteOffset: 2)
                let vb = Int(HexKit.bytes(buf)[1])
                // 8B 头设首选 (Java 恒按 8B 消费), vb=0x01 帧若实为 8B 不被 7B 试切提前截断
                let prefs: [Int] = (vb == 0x01) ? [8 + len, 7 + len, 10 + len] : [8 + len, 10 + len, 7 + len]
                var cut = 0
                for total in prefs {
                    if buf.count < total * 2 { continue }
                    let parsed = parseResponse(String(buf.prefix(total * 2)))
                    if parsed.ok { cut = total; frames.append(parsed); break }
                }
                if cut == 0 { break }
                buf = String(buf.dropFirst(cut * 2))
            }
            return frames
        }
    }

    // ---------- 广播厂商段解析 (JS services/ble.js parseAdv; 依据 BLEAdData.java) ----------
    /// 台账 / 0x88 包络要用的门锁 MAC —— **显示序** (小写无冒号)。
    /// 广播厂商段里那 6 字节是**线上序** (`macRaw`), 两者逐字节相反:
    ///   macRaw = "95ccc593b9fb"  ⇔  锁的 MAC = "fbb993c5cc95"
    /// (与 Android `BluetoothDevice.getAddress()` 同序 —— 原版 APK 就是把那个值当 TargetMAC 用的,
    ///  再由 `kt.getBytes()` 反转成线上序; 见 docs/BRICK-AUDIT.md §10。)
    /// 单独立一个口的原因: 2026-10-17 真机配对在 PIN 批次第 1 批回 rc=12「mac地址不正确」——
    /// 拿 `macRaw` 当 MAC 用, 包络里又 reversePairs 一次 ⇒ 送出的 MAC 正好是**反的**。
    /// 锁因此什么都没写, 只是拒绝 (rc≠0)。
    static func lockMac(fromAdv adv: AdvData) -> String? {
        guard let d = adv.macDisplay else { return nil }
        let m = d.replacingOccurrences(of: ":", with: "").lowercased()
        return m.count == 12 ? m : nil
    }

    struct AdvData {
        var frameCtrl: Int
        var pid: Int
        var macRaw: String?      // 按接收序 hex
        var macDisplay: String?  // 反转冒号大写
        var resetStatus: Int
        var containNotify: Int
        var containPid: Int
        var containMac: Int
        var dfuState: Int
    }
    /// 2026-10-27 审核说明 (AUDIT-A F-09)：frameCtrl 的 ZK 门禁判据三端写法不同 ——
    /// Java 原版是 `fc >= 0x0C`，三端（iOS/Android/vendor JS）都是 `(fc & 0x0C) == 0x0C`。
    /// 两者在 fc 的 bit2/bit3 都置位时等价；差异只出现在高位有其他标志时。
    /// 本仓沿用 JS 口径（位与），因为它对「额外标志位」更宽容 —— 新固件加了标志不会失配。
    static func parseAdv(_ advHex: String) -> AdvData? {
        guard let range = advHex.range(of: "98ed") else { return nil }
        let from = advHex.distance(from: advHex.startIndex, to: range.lowerBound)
        // 需要 98ed + 10B = 24 hex 字符
        guard advHex.count - from >= 24 else { return nil }
        let seg = String(advHex.dropFirst(from + 4)) // seg[0]=fc seg[1]=b3 seg[2..3]=pid seg[4..9]=MAC
        guard seg.count >= 20 else { return nil }
        let frameCtrl = Int(HexKit.bytes(String(seg.prefix(2)))[0])
        guard (frameCtrl & 0x0c) == 0x0c else { return nil } // Java 门禁: containPid(bit2)+containMac(bit3)
        // JS: pid = seg[4..5] | seg[6..7]<<8 (LE u16); macRaw = seg[8..19]
        let pidLo = Int(HexKit.bytes(String(seg.dropFirst(4).prefix(2)))[0])
        let pidHi = Int(HexKit.bytes(String(seg.dropFirst(6).prefix(2)))[0])
        let pid = pidLo | (pidHi << 8)
        let macRaw = String(seg.dropFirst(8).prefix(12))
        var macDisplay = ""
        var ci = 0
        for ch in HexKit.reversePairs(macRaw) {
            if ci > 0 && ci % 2 == 0 { macDisplay.append(":") }
            macDisplay.append(ch)
            ci += 1
        }
        macDisplay = macDisplay.uppercased()
        return AdvData(
            frameCtrl: frameCtrl, pid: pid, macRaw: macRaw.lowercased(),
            macDisplay: macDisplay,
            resetStatus: (frameCtrl & 0x01) != 0 ? 1 : 0,
            containNotify: (frameCtrl & 0x02) != 0 ? 1 : 0,
            containPid: (frameCtrl & 0x04) != 0 ? 1 : 0,
            containMac: (frameCtrl & 0x08) != 0 ? 1 : 0,
            dfuState: (frameCtrl & 0x20) != 0 ? 1 : 0
        )
    }
}

// ---------- 时间显示 (JS utils/time.js) ----------
enum ProtoTime {
    static func localStr(_ sec: Int64) -> String {
        let d = Date(timeIntervalSince1970: ZKProtocol.protoSecondsToUnix(sec))
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }
}
