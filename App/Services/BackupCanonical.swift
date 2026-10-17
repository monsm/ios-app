// 备份包规范化序列化 — 与 JS storage.js canonicalBundle/checksum 逐字节互通
//   * canonicalString(b) 复刻 JS canonicalBundle: 固定顶层键序 + devices 按 mac 排序 + members 按 id 排序
//     + globals 键排序 (canonGlobals, 剔 null) + JSON.stringify 紧凑语义 (非 ASCII 原样, 控制符 \uXXXX)
//   * checksum = fnv1a32(canonical) — 小程序端 validateBundle 强校验, 缺它导入必拒
//   * JS 侧 kc/ledger/meta 是「原样透传」(键序保留写入序) → 只需 Swift 写出与自算 hash 同字节即可互通
import Foundation

nonisolated enum JValue {
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

nonisolated enum BackupCanonical {
    /// 备份包校验和。**必须逐位复现小程序 `utils/storage.js` 的 fnv1a32**，而不是教科书 FNV-1a：
    /// JS 那侧 ① 按 **UTF-16 码元**逐个喂 `charCodeAt(i) & 0xff`（中文/emoji 与 UTF-8 字节流不同），
    /// ② `h ^ c` 是有符号 int32 运算（结果可为负），③ `h * 16777619` 走**双精度**，
    /// |积| 超过 2^53 就丢低位，④ 输出补零到 8 位十六进制。
    /// 旧实现按 UTF-8 逐字节 + `&*` 精确模乘 + 不补零，与权威侧**每一条都不一致**（实测含纯 ASCII 也 100% 不一致），
    /// 于是"备份包与小程序互通"那句承诺是假的：两侧互相判"内容被篡改"。
    /// 本段算术不在任何编译器覆盖范围内，唯一担保是 `tools/bundleshadow.js` 对 `fixtures/canonical.json`
    /// (由真 JS 现跑烘出) 的 18 条向量断言 —— 改这里任何一步，那道闸门必须变红。
    static func fnv1a32Hex(_ s: String) -> String {
        let mod: Double = 4294967296        // 2^32
        let half: Double = 2147483648       // 2^31
        var h: Double = 0x811c9dc5
        for unit in s.utf16 {
            // ToInt32(h)：h 恒在 [0, 2^32)，高位置 1 时按负数参与 ^
            let signed = h >= half ? h - mod : h
            let xored = Int64(signed) ^ Int64(unit & 0xff)
            let prod = Double(xored) * 16777619.0     // 与 JS 同一次双精度舍入
            var u = prod.truncatingRemainder(dividingBy: mod)
            if u < 0 { u += mod }
            h = u
        }
        return String(format: "%08x", UInt32(h))
    }
    /// 旧 (教科书式) 语义。只留给导入侧认旧包：本仓此前写出的 checksum 全按这条算，
    /// 直接换掉会把用户已有的备份判成篡改。新导出的包一律走上面那条与小程序一致的路。
    static func fnv1a32HexLegacy(_ s: String) -> String {
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
        // canonGlobals: 键按字母序 (appearance < gatewayList < keychainDongles < otpKeys < passcode < trace), 剔 null/空
        if let g = b.globals {
            var gp: [(String, JValue)] = []
            // 894 外观段进校验和：字段按**固定字母序**逐个 emit，缺字段就不 emit。
            // 不进校验和的话，改包体里的外观段既不会被发现，也让"同一份备份两次导出得到不同 canonical"
            // 有了新口子 —— 与 181 当初把 OTP 段拉进 canonical 是同一个理由。
            if let ap = g.appearance {
                var av: [(String, JValue)] = []
                func put(_ k: String, _ v: String?) { if let v { av.append((k, .str(v))) } }
                func putB(_ k: String, _ v: Bool?) { if let v { av.append((k, .bool(v))) } }
                put("accent", ap.accent)
                put("density", ap.density)
                put("heroTex", ap.heroTex)
                put("motion", ap.motion)
                put("radius", ap.radius)
                put("rowH", ap.rowH)
                put("theme", ap.theme)
                put("tlGap", ap.tlGap)
                put("weekStart", ap.weekStart)
                putB("festive", ap.festive)
                putB("hc", ap.hc)
                putB("launchLine", ap.launchLine)
                putB("plain", ap.plain)
                // 与 trace.savedAt 同型: 数字走 .num (stringify 对整数值输出整数形态)
                if let n = ap.recentCount { av.append(("recent", .num(Double(n)))) }
                if let hs = ap.heroStats, !hs.isEmpty {
                    av.append(("heroStats", .arr(hs.sorted().map { JValue.str($0) })))
                }
                if !av.isEmpty {
                    gp.append(("appearance", .obj(av.sorted { $0.0 < $1.0 })))
                }
            }
            // D-36 设备组织段进校验和 (与 894 appearance 同一理由: 不进就等于改包体不被人发现),
            // 内层按键名字母序 emit, groups 按 mac 排; 顶层位置在 appearance 之后、gatewayList 之前
            // —— 小程序 canonGlobals 对 globals 顶层键排序, 顺序必须一致。
            if let org = g.deviceOrg {
                var ov: [(String, JValue)] = []
                if let f = org.folded, !f.isEmpty {
                    ov.append(("folded", .arr(f.sorted().map { JValue.str($0) })))
                }
                if let gs = org.groups, !gs.isEmpty {
                    ov.append(("groups", .arr(gs.sorted { $0.mac < $1.mac }.map { r in
                        .obj([("mac", .str(r.mac)), ("name", .str(r.name))])
                    })))
                }
                if let h = org.hidden, !h.isEmpty {
                    ov.append(("hidden", .arr(h.sorted().map { JValue.str($0) })))
                }
                if let o = org.order, !o.isEmpty {
                    ov.append(("order", .arr(o.map { JValue.str($0) })))
                }
                if !ov.isEmpty { gp.append(("deviceOrg", .obj(ov))) }
            }
            if let list = g.gatewayList, !list.isEmpty {
                gp.append(("gatewayList", .arr(list.map(gatewayValue))))
            }
            if let list = g.keychainDongles, !list.isEmpty {
                gp.append(("keychainDongles", .arr(list.map(dongleValue))))
            }
            // 181 OTP 段进校验和: 键按字典序排, 值随键走 (否则同一包体两次导出会得到不同 canonical)
            if let otp = g.otpKeys, !otp.isEmpty {
                gp.append(("otpKeys", .obj(otp.keys.sorted().map { k in (k, .str(otp[k] ?? "")) })))
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