// 备份包规范化序列化 — 与 JS storage.js canonicalBundle/checksum 逐字节互通
//   * canonicalString(b) 复刻 JS canonicalBundle: 固定顶层键序 + devices 按 mac 排序 + members 按 id 排序
//     + globals 键排序 (canonGlobals, 剔 null) + JSON.stringify 紧凑语义 (非 ASCII 原样, 控制符 \uXXXX)
//   * checksum = fnv1a32(canonical) — 小程序端 validateBundle 强校验, 缺它导入必拒
//   * JS 侧 kc/ledger/meta 是「原样透传」(键序保留写入序) → 只需 Swift 写出与自算 hash 同字节即可互通
import Foundation

enum JValue {
    case str(String)
    case num(Double)
    case bool(Bool)
    case null
    case arr([JValue])
    case obj([(String, JValue)])

    func stringify() -> String {
        switch self {
        case .str(let s): return JValue.escape(s)
        case .num(let d):
            if d.truncatingRemainder(dividingBy: 1) == 0, abs(d) < 9.007199254740992e15 {
                return String(Int64(d))
            }
            return String(d)
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .arr(let items): return "[" + items.map { $0.stringify() }.joined(separator: ",") + "]"
        case .obj(let pairs):
            let kv = pairs.map { JValue.escape($0.0) + ":" + $0.1.stringify() }
            return "{" + kv.joined(separator: ",") + "}"
        }
    }
    static func escape(_ s: String) -> String {
        var r = "\""
        for ch in s.unicodeScalars {
            switch ch {
            case "\"": r += "\\\""
            case "\\": r += "\\\\"
            case "\n": r += "\\n"
            case "\r": r += "\\r"
            case "\t": r += "\\t"
            case let u where u.value == 0x08: r += "\\b"
            case let u where u.value == 0x0c: r += "\\f"
            default:
                if ch.value < 0x20 { r += String(format: "\\u%04x", ch.value) }
                else { r.unicodeScalars.append(ch) }
            }
        }
        return r + "\""
    }
}

enum BackupCanonical {
    static func fnv1a32Hex(_ s: String) -> String {
        var hash: UInt32 = 0x811c9dc5
        for ch in Array(s.utf8) {
            hash ^= UInt32(ch)
            hash = hash &* 0x01000193
        }
        return String(hash, radix: 16)
    }

    // ---- 值构造辅助 (键序 = 数组顺序) ----
    private static func kcValue(_ kc: Keychain) -> JValue {
        // JS pickKc 白名单序: version,mac,pid,pidName,name,fw,pairedAt,skey,bkey,pins,ekey,trackid (defined 才带)
        var pairs: [(String, JValue)] = [
            ("version", .num(Double(kc.version))),
            ("mac", .str(kc.mac)),
            ("pid", .num(Double(kc.pid))),
            ("pidName", .str(kc.pidName)),
        ]
        if !kc.name.isEmpty { pairs.append(("name", .str(kc.name))) }
        pairs.append(("fw", .str(kc.fw)))
        if !kc.pairedAt.isEmpty { pairs.append(("pairedAt", .str(kc.pairedAt))) }
        pairs.append(("skey", .str(kc.skey)))
        if !kc.bkey.isEmpty { pairs.append(("bkey", .str(kc.bkey))) }
        if !kc.pins.isEmpty { pairs.append(("pins", .arr(kc.pins.map { .str($0) }))) }
        if !kc.ekey.isEmpty { pairs.append(("ekey", .str(kc.ekey))) }
        if !kc.trackid.isEmpty { pairs.append(("trackid", .str(kc.trackid))) }
        return .obj(pairs)
    }
    private static func ledgerValue(_ l: Ledger) -> JValue {
        .obj([
            ("pwds", .arr(l.pwds.map { p -> JValue in
                var pairs: [(String, JValue)] = [
                    ("alias", .num(Double(p.alias))),
                    ("from", .str(p.from)),
                    ("to", .str(p.to)),
                    ("temp", .bool(p.temp)),
                    ("at", .num(p.at)),
                ]
                if let pwd = p.pwd { pairs.append(("pwd", .str(pwd))) }
                pairs.append(("owner", p.owner.map { .str($0) } ?? .null))
                pairs.append(("note", .str(p.note)))
                return .obj(pairs)
            })),
            ("fps", .arr(l.fps.map { f -> JValue in
                var pairs: [(String, JValue)] = [
                    ("batch", .num(Double(f.batch))),
                    ("name", .str(f.name)),
                    ("at", .num(f.at)),
                    ("note", .str(f.note)),
                ]
                if let src = f.src { pairs.append(("src", .str(src))) }
                pairs.append(("owner", f.owner.map { .str($0) } ?? .null))
                if let alarm = f.isAlarm { pairs.append(("isAlarm", .bool(alarm))) }
                return .obj(pairs)
            })),
        ])
    }
    private static func metaValue(_ meta: BackupBundle.Device.Meta?) -> JValue {
        guard let meta else { return .null }
        var pairs: [(String, JValue)] = []
        if let c = meta.defend {
            pairs.append(("defend", .obj([("control", .num(Double(c.control))), ("startSec", .num(Double(c.startSec))), ("endSec", .num(Double(c.endSec))), ("at", .num(c.at))])))
        }
        if let c = meta.tailgate {
            pairs.append(("tailgate", .obj([("interval", .num(Double(c.interval))), ("at", .num(c.at))])))
        }
        if let t = meta.synctime { pairs.append(("synctime", .num(t))) }
        if let o = meta.otpStatus {
            pairs.append(("otpStatus", .obj([("on", .bool(o.on)), ("at", .num(o.at))])))
        }
        if let o = meta.otpIdx {
            pairs.append(("otpIdx", .obj([("idx", .num(Double(o.idx))), ("invalidTime", .str(o.invalidTime))])))
        }
        return pairs.isEmpty ? .null : .obj(pairs)
    }
    private static func dongleValue(_ d: Dongle) -> JValue {
        var pairs: [(String, JValue)] = [("mac", .str(d.mac))]
        if !d.name.isEmpty { pairs.append(("name", .str(d.name))) }
        if !d.boundAt.isEmpty { pairs.append(("boundAt", .str(d.boundAt))) }
        if !d.lastSeenAt.isEmpty { pairs.append(("lastSeenAt", .str(d.lastSeenAt))) }
        if !d.lastKeyLock.isEmpty { pairs.append(("lastKeyLock", .str(d.lastKeyLock))) }
        if !d.lastKeyAt.isEmpty { pairs.append(("lastKeyAt", .str(d.lastKeyAt))) }
        if let st = d.stat {
            pairs.append(("stat", .obj([
                ("power", .num(Double(st.power))), ("absPower", .num(Double(st.absPower))),
                ("ekeyCount", .num(Double(st.ekeyCount))), ("ekeyAmount", .num(Double(st.ekeyAmount))),
                ("firmware", .str(st.firmware)), ("pid", .num(Double(st.pid))), ("eCtrl", .str(st.eCtrl)),
            ])))
        }
        return .obj(pairs)
    }
    private static func gatewayValue(_ g: Gateway) -> JValue {
        .obj([
            ("mac", .str(g.mac)), ("name", .str(g.name)), ("pid", .num(Double(g.pid))),
            ("bleId", .str(g.bleId)), ("boundAt", .str(g.boundAt)), ("wifimac", .str(g.wifimac)),
            ("romVer", .str(g.romVer)), ("eCtrlVer", .str(g.eCtrlVer)), ("ssid", .str(g.ssid)),
            ("wifiIP", .str(g.wifiIP)), ("netState", .num(Double(g.netState))),
            ("lastWifi", .str(g.lastWifi)), ("provisionedAt", .str(g.provisionedAt)),
        ])
    }
    private static func memberValue(_ m: Member) -> JValue {
        .obj([
            ("id", .str(m.id)), ("name", .str(m.name)), ("relation", .str(m.relation)),
            ("phone", .str(m.phone)), ("color", .str(m.color)), ("at", .num(m.at)),
        ])
    }

    // ---- canonicalBundle 同构 (JS storage.js) ----
    static func canonical(_ b: BackupBundle) -> String {
        var top: [(String, JValue)] = [
            ("type", .str(b.type)),
            ("bundleVer", .num(Double(b.bundleVer))),
            ("schema", .num(Double(b.schema))),
            ("at", .str(b.at)),
            ("currentMac", .str(b.currentMac)),
            ("devices", .arr(
                b.devices.sorted { $0.mac < $1.mac }.map { d -> JValue in
                    .obj([
                        ("mac", .str(d.mac)),
                        ("kc", kcValue(d.kc)),
                        ("ledger", d.ledger.map { ledgerValue($0) } ?? .null),
                        ("meta", metaValue(d.meta)),
                    ])
                }
            )),
            ("members", .arr((b.members ?? []).sorted { $0.id < $1.id }.map(memberValue))),
        ]
        // canonGlobals: 键排序 (gatewayList < keychainDongles < passcode < trace), 剔 null/空
        if let g = b.globals {
            var gp: [(String, JValue)] = []
            if let list = g.gatewayList, !list.isEmpty {
                gp.append(("gatewayList", .arr(list.map(gatewayValue))))
            }
            if let list = g.keychainDongles, !list.isEmpty {
                gp.append(("keychainDongles", .arr(list.map(dongleValue))))
            }
            if let pc = g.passcode, !pc.s.isEmpty, !pc.d.isEmpty {
                gp.append(("passcode", .obj([("s", .str(pc.s)), ("d", .str(pc.d))])))
            }
            if let tr = g.trace, let lines = tr.lines, !lines.isEmpty {
                gp.append(("trace", .obj([
                    ("savedAt", .num(tr.savedAt ?? 0)),
                    ("count", .num(Double(tr.count ?? 0))),
                    ("chars", .num(Double(tr.chars ?? 0))),
                    ("lines", .arr(lines.map { .str($0) })),
                ])))
            }
            if !gp.isEmpty {
                top.append(("globals", .obj(gp))) // 已按字母序构造
            }
        }
        return JValue.obj(top).stringify()
    }

    // 导出文本: canonical + checksum (末位键, JS buildBundlePayload 同序)
    static func exportText(_ b: BackupBundle) -> String {
        let canonical = canonical(b)
        let checksum = fnv1a32Hex(canonical)
        // 顶层重排: canonical 的 obj 已含全部键 — 把 checksum 追加到末尾 (JSON 对象键序 = JS 赋值序)
        guard canonical.hasSuffix("}") else { return "" }
        return String(canonical.dropLast()) + ",\"checksum\":\"" + checksum + "\"}"
    }
}