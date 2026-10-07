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
    // 协议时间基准 2010-01-01 00:00:00 UTC
    static let epochMs: Int64 = 1_262_304_000_000 // Date.parse('2010-01-01T00:00:00Z')
    static func protoSecondsFromMs(_ ms: Int64) -> Int64 { (ms - epochMs) / 1000 }
    static func nowProtoSeconds() -> Int64 { protoSecondsFromMs(Int64(Date().timeIntervalSince1970 * 1000)) }
    static func protoSecondsToMs(_ sec: Int64) -> Int64 { epochMs + sec * 1000 }
    // JS protoTime('2118-01-01T00:00:00Z') 的默认有效止 (buildEkey 默认 VT)
    static let validTo2118: UInt32 = UInt32(protoSecondsFromMs(4_670_438_400_000)) // 2118-01-01T00:00:00Z (node Date.parse 权威值)

    // ---------- KLV ----------
    static func buildKLV(_ key: Int, _ valHex: String) -> String {
        let v = valHex
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
        if header == 8 {
            return "87" + "00" + HexKit.hexPair(UInt32(len & 0xff)) + HexKit.hexPair(UInt32((len >> 8) & 0xff))
                + HexKit.hexPair(UInt32(cmd)) + "000000" + klv
        }
        return "87" + "00" + HexKit.hexPair(UInt32(len & 0xff)) + HexKit.hexPair(UInt32((len >> 8) & 0xff))
            + HexKit.hexPair(UInt32(cmd)) + ssToken + "000000" + klv
    }

    // ---------- 0x88 EKey 包络 ----------
    static func buildEkey(_ cmd: UInt8, _ macHex: String,
                          validFromSec: UInt32 = 0,
                          validToSec: UInt32? = nil,
                          trackIdVal: UInt32 = 0) -> String {
        let vt = validToSec ?? validTo2118
        var mac = macHex.lowercased().replacingOccurrences(of: ":", with: "")
        if mac.isEmpty { mac = "000000000000" }
        return "8800" + HexKit.reversePairs(mac)
            + HexKit.u32leHex(trackIdVal)
            + HexKit.u32leHex(validFromSec)
            + HexKit.u32leHex(vt)
            + HexKit.hexPair(UInt32(cmd))
    }

    // 密文包络封装 (JS wrapEnc): body → EKey(cmd,mac) → AES(skey) → KLV#klvKey
    static func wrapEnc(_ cmd: UInt8, _ macHex: String, _ skeyHex: String, _ bodyHex: String, _ klvKey: Int) -> String {
        let env = buildEkey(cmd, macHex) + bodyHex
        return buildKLV(klvKey, AESKit.encryptHex(env, keyHex: skeyHex))
    }

    // ---------- 令牌注入 (KLV#0xEE; 头型自适应 8B/10B) ----------
    static func injectToken(_ hex: String, _ tokenHex: String) -> String {
        guard !tokenHex.isEmpty, hex.count >= 16 else { return hex }
        let len = HexKit.readU16LE(hex, byteOffset: 2)
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
        if let first = results.first { return first }
        return ParsedFrame(ok: false, cmd: 0, header: 0, klvs: [], raw: hex)
    }

    // ---------- 粘包/多帧重组 (JS services/ble.js makeAssembler 逐行移植) ----------
    final class FrameAssembler {
        private var buf = ""
        var pendingBytes: Int { buf.count / 2 }
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
        let d = Date(timeIntervalSince1970: TimeInterval(ZKProtocol.protoSecondsToMs(sec) / 1000))
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }
}
