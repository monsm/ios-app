// 差分回归 — Swift 重写 vs JS 核心金标 (fixtures/golden.json) 逐字节断言
// 这是「不要BUG」的核心闸门: 任何协议/密码学/解析偏差都会在这里被抓住
import XCTest
@testable import OfflineLock

final class GoldenDiffTests: XCTestCase {
    static var golden: [String: Any] = [:]

    override class func setUp() {
        super.setUp()
        if let url = Bundle(for: GoldenDiffTests.self).url(forResource: "golden", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            golden = obj
        }
    }
    private func g<T>(_ path: [String]) -> T {
        var cur: Any = Self.golden
        for p in path {
            cur = (cur as! [String: Any])[p]!
        }
        return cur as! T
    }

    // ================= AES-128-ECB =================
    func testAES() {
        if let v = Self.golden["aes"] as? [String: Any] {
            for (name, expectedRaw) in v {
                guard let expected = expectedRaw as? String else {
                    // decrypt_roundtrip 是对象? 不 — 是字符串; 跳过非字符串
                    continue
                }
                switch name {
                case "encrypt_16":
                    XCTAssertEqual(AESKit.encryptHex("00112233445566778899aabbccddeeff", keyHex: "00112233445566778899aabbccddeeff"), expected, "aes.\(name)")
                case "encrypt_padded":
                    XCTAssertEqual(AESKit.encryptHex("8800aabbccddeeff", keyHex: "00112233445566778899aabbccddeeff"), expected, "aes.\(name)")
                case "decrypt_roundtrip":
                    let cipher = AESKit.encryptHex("8800aabbccddeeff" + "0102030405060708", keyHex: "00112233445566778899aabbccddeeff")
                    XCTAssertEqual(AESKit.decryptHex(cipher, keyHex: "00112233445566778899aabbccddeeff"), expected, "aes.\(name)")
                case "nist_vector":
                    XCTAssertEqual(AESKit.encryptHex("00112233445566778899aabbccddeeff", keyHex: "000102030405060708090a0b0c0d0e0f"), expected, "aes.\(name)")
                default: break
                }
            }
        }
    }

    // ================= 全部命令帧 (40 条字节级) =================
    func testCmds() throws {
        let cmds = try XCTUnwrap(Self.golden["cmds"] as? [String: String])
        let MAC = "aabbccddeeff"
        let SKEY = "00112233445566778899aabbccddeeff"
        var built: [String: String] = [:]
        built["cmd01Session"] = ZKCmdBuilder.cmd01Session().hex
        built["cmd03StatusPlain"] = ZKCmdBuilder.cmd03StatusPlain(MAC).hex
        built["cmd03StatusWrap"] = ZKCmdBuilder.cmd03StatusWrap(MAC, SKEY).hex
        built["cmd04Open_klv01"] = ZKCmdBuilder.cmd04Open(String(repeating: "cafebabe", count: 4), klv01Hex: "0000").hex
        built["cmd05Exchange"] = ZKCmdBuilder.cmd05Exchange(SKEY, timeSec: 0x5a).hex
        built["cmd08SyncPins"] = ZKCmdBuilder.cmd08SyncPinsBatch(MAC, SKEY, ["11223344", "55667788"], delPins: ["ffffffff"])!.hex
        built["cmd0ASyncPwd_add"] = try ZKCmdBuilder.cmd0ASyncPwd(MAC, SKEY, addPwd: "123456", validFrom: "2010-01-01 00:00:00", validTo: "2118-01-01 00:00:00").hex
        built["cmd0ASyncPwd_modify"] = try ZKCmdBuilder.cmd0ASyncPwd(MAC, SKEY, delAlias: 5, addPwd: "654321", validFrom: "2026-01-01 00:00:00", validTo: "2118-01-01 00:00:00").hex
        built["cmd0ASyncPwd_del"] = try ZKCmdBuilder.cmd0ASyncPwd(MAC, SKEY, delAlias: 0xFFFF, validFrom: "2010-01-01 00:00:00", validTo: "2118-01-01 00:00:00").hex
        built["cmd0BExpire"] = ZKCmdBuilder.cmd0BSyncPwdExpire(MAC, SKEY, 5, "2026-01-01 00:00:00", "2118-01-01 00:00:00").hex
        built["cmd0ESyncTime"] = ZKCmdBuilder.cmd0ESyncTime(MAC, SKEY, 530000000).hex
        built["cmd12Echo"] = ZKCmdBuilder.cmd12Echo("123456").hex
        built["cmd13AddFp"] = ZKCmdBuilder.cmd13AddFp(MAC, SKEY, 8, 15).hex
        built["cmd14FpConfirm"] = ZKCmdBuilder.cmd14FpConfirm(MAC, SKEY, 77, "2010-01-01 00:00:00", "2118-01-01 00:00:00").hex
        built["cmd15DeleteFp"] = ZKCmdBuilder.cmd15DeleteFp(MAC, SKEY, 77).hex
        built["cmd16GetLog"] = ZKCmdBuilder.cmd16GetLog(MAC, SKEY, orderType: 0, startIdx: 0xFFFFFFFF, pageSize: 5).hex
        built["cmd18Volume"] = ZKCmdBuilder.cmd18Volume(MAC, SKEY, true).hex
        built["cmd19OpenZotp"] = ZKCmdBuilder.cmd19OpenZotp(MAC, SKEY, true).hex
        built["cmd20Validation"] = ZKCmdBuilder.cmd20ValidationMode(MAC, SKEY, true).hex
        built["cmd21SetBkey"] = ZKCmdBuilder.cmd21SetBkey(MAC, SKEY, "aabbccddeeff00112233445566778899").hex
        built["cmd22EnableDfu"] = ZKCmdBuilder.cmd22EnableDfu(MAC, SKEY, 0).hex
        built["cmd23ExKeyWay"] = ZKCmdBuilder.cmd23ExKeyWay().hex
        built["cmd24AutoLock"] = ZKCmdBuilder.cmd24AutoLock(MAC, SKEY, 3).hex
        built["cmd25Defence_aperiodic"] = ZKCmdBuilder.cmd25Defence(MAC, SKEY, 1, 0, 0).hex
        built["cmd25Defence_period"] = ZKCmdBuilder.cmd25Defence(MAC, SKEY, 2, 21600, 43200).hex
        built["withToken"] = ZKProtocol.injectToken(ZKCmdBuilder.cmd12Echo("123456").hex, "beef")
        built["buildEkeyOpen"] = ZKCmdBuilder.buildEkeyOpen(SKEY, MAC, "123456", validFromSec: 0,
                                                            validToSec: ZKProtocol.validTo2118, trackId: 12345)
        // buildEkeyShare 确定性对照 (固定 TrackId=7 + 本地时区 2010/2118 窗口 — 金标同输入)
        built["buildEkeyShare"] = ZKCmdBuilder.buildEkeyShare(SKEY, MAC, "654321") { _ in 7 }
        built["cmd41WriteEkey"] = ZKCmdBuilder.cmd41WriteEkey(MAC, 16289, built["buildEkeyOpen"]!).hex
        built["cmd41WriteEkey_del"] = ZKCmdBuilder.cmd41WriteEkey(MAC, 16289, "").hex
        built["cmd44GetEkeyInfo_all"] = ZKCmdBuilder.cmd44GetEkeyInfo(nil).hex
        built["cmd44GetEkeyInfo_one"] = ZKCmdBuilder.cmd44GetEkeyInfo(MAC).hex
        built["cmd43KeychainStatus_empty"] = ZKCmdBuilder.cmd43KeychainStatus([]).hex
        built["cmd43KeychainStatus_two"] = ZKCmdBuilder.cmd43KeychainStatus([MAC, "112233445566"]).hex
        built["cmd38GWStatus"] = ZKCmdBuilder.cmd38GWStatus().hex
        built["cmd31GWSetWifi"] = ZKCmdBuilder.cmd31GWSetWifi("HomeWiFi", "pass1234").hex
        built["cmd31GWSetWifi_cn"] = ZKCmdBuilder.cmd31GWSetWifi("客厅网关", "密码88").hex
        built["cmd32GWSetIot"] = ZKCmdBuilder.cmd32GWSetIot("aabb", "cc", "dd").hex
        built["cmd35GWReboot"] = ZKCmdBuilder.cmd35GWReboot().hex
        built["cmd30GWDeviceName"] = ZKCmdBuilder.cmd30GWDeviceName().hex

        var mismatches: [String] = []
        for (name, expected) in cmds {
            guard let actual = built[name] else {
                mismatches.append("\(name): Swift 未实现该向量")
                continue
            }
            if actual != expected { mismatches.append("\(name):\n  js=\(expected)\n  sw=\(actual)") }
        }
        XCTAssertTrue(mismatches.isEmpty, "命令帧与 JS 金标不一致:\n" + mismatches.joined(separator: "\n"))
    }

    // ================= 响应解析 =================
    func testParseStatus() throws {
        let parse = try XCTUnwrap(Self.golden["parse"] as? [String: Any])
        let frame = try XCTUnwrap(parse["status_frame"] as? String)
        let parsed = ZKProtocol.parseResponse(frame)
        XCTAssertTrue(parsed.ok)
        XCTAssertEqual(parsed.cmd, 0x03)
        XCTAssertEqual(parsed.header, 8)
        let st = StatusParser.parseStatus(parsed.klvs)
        let golden = try XCTUnwrap(parse["status"] as? [String: Any])
        XCTAssertEqual(st.rc, golden["rc"] as? Int)
        XCTAssertEqual(st.sKeyStatus, golden["sKeyStatus"] as? Int)
        XCTAssertEqual(st.powerLevel, golden["powerLevel"] as? Int)
        XCTAssertEqual(st.firmware, golden["firmware"] as? String)
        XCTAssertEqual(st.pid, golden["pid"] as? Int)
        XCTAssertEqual(st.pidName, golden["pidName"] as? String)
        XCTAssertEqual(st.pinStock, golden["pinStock"] as? Int)
        XCTAssertEqual(st.pwdStock, golden["pwdStock"] as? Int)
        XCTAssertEqual(st.fpStock, golden["fpStock"] as? Int)
        XCTAssertEqual(st.securityLevel, golden["securityLevel"] as? Int)
        XCTAssertEqual(st.verKeyboard, golden["verKeyboard"] as? Int)
        XCTAssertEqual(st.eCtrlVer, golden["eCtrlVer"] as? String)
        XCTAssertEqual(st.lockTime, (golden["lockTime"] as? Int).map(Int64.init))
        XCTAssertEqual(st.fpInfoBatchNumber, golden["fpInfoBatchNumber"] as? Int)
    }
    func testParseLogs() throws {
        let parse = try XCTUnwrap(Self.golden["parse"] as? [String: Any])
        let frame = try XCTUnwrap(parse["log_frame"] as? String)
        let logs = StatusParser.parseLogs(ZKProtocol.parseResponse(frame).klvs)
        let golden = try XCTUnwrap(parse["log_parsed"] as? [[String: Any]])
        XCTAssertEqual(logs.count, golden.count)
        for (i, g) in golden.enumerated() {
            XCTAssertEqual(logs[i].type, g["type"] as? Int, "log[\(i)].type")
            XCTAssertEqual(logs[i].typeName, g["typeName"] as? String, "log[\(i)].typeName")
            XCTAssertEqual(UInt32(logs[i].idxRaw), UInt32(g["idxRaw"] as? Int ?? 0), "log[\(i)].idxRaw")
            XCTAssertEqual(logs[i].lockTime, (g["lockTime"] as? Int).map(Int64.init), "log[\(i)].lockTime")
        }
    }
    func testHeaderVariants() throws {
        let parse = try XCTUnwrap(Self.golden["parse"] as? [String: Any])
        let variants = try XCTUnwrap(parse["status_parse_headers"] as? [String: Any])
        for (name, obj) in variants {
            let golden = try XCTUnwrap(obj as? [String: Any])
            let frameName = name == "h8" ? "header8" : (name == "h7" ? "header7" : "header10")
            let frame = try XCTUnwrap(parse[frameName] as? String)
            let st = StatusParser.parseStatus(ZKProtocol.parseResponse(frame).klvs)
            XCTAssertEqual(st.rc, golden["rc"] as? Int, "header \(name) rc")
        }
    }

    // ================= 广播解析 =================
    func testParseAdv() throws {
        let adv = try XCTUnwrap(Self.golden["parseAdv"] as? [String: Any])
        let main = try XCTUnwrap(adv["out"] as? [String: Any])
        let a = try XCTUnwrap(ZKProtocol.parseAdv(try XCTUnwrap(adv["input"] as? String)))
        XCTAssertEqual(a.pid, main["pid"] as? Int)
        XCTAssertEqual(a.macRaw, main["macRaw"] as? String)
        XCTAssertEqual(a.macDisplay, main["macDisplay"] as? String)
        XCTAssertEqual(a.resetStatus, main["resetStatus"] as? Int)
        XCTAssertEqual(a.containNotify, main["containNotify"] as? Int)
        XCTAssertEqual(a.dfuState, main["dfuState"] as? Int)
        let dfuGolden = try XCTUnwrap(adv["dfumode"] as? [String: Any])
        let d = try XCTUnwrap(ZKProtocol.parseAdv(try XCTUnwrap(adv["dfumode_input"] as? String)))
        XCTAssertEqual(d.dfuState, dfuGolden["dfuState"] as? Int)
        XCTAssertEqual(d.macRaw, dfuGolden["macRaw"] as? String)
    }

    // ================= ZOTP (冻结时钟逐字节差分) =================
    func testZOTP() throws {
        let zotp = try XCTUnwrap(Self.golden["zotp"] as? [String: Any])
        let fixedSec = (zotp["fixedSec"] as? Int).map(Int64.init) ?? 1_800_000_000
        let cases: [(String, Int)] = [("v30_0", 0), ("v30_1", 1), ("v30_99", 99), ("v60_0", 0)]
        let periods: [String: Int] = ["v30_0": 30, "v30_1": 30, "v30_99": 30, "v60_0": 60]
        let idxs: [String: Int] = ["v30_0": 0, "v30_1": 1, "v30_99": 99, "v60_0": 0]
        for (name, _) in cases {
            let expected = try XCTUnwrap(zotp[name] as? String, name)
            let actual = ZOTP.generate(macHex: "aabbccddeeff",
                                       skeyHex: "00112233445566778899aabbccddeeff",
                                       periodSec: periods[name] ?? 30,
                                       idx: idxs[name] ?? 0, nowSec: fixedSec)
            XCTAssertEqual(actual, expected, "zotp.\(name)")
        }
    }

    // ================= PID 能力矩阵 =================
    func testPidCapabilities() throws {
        let caps = try XCTUnwrap(Self.golden["capabilities"] as? [String: Any])
        XCTAssertEqual(PidMap.canDefend(8098), caps["canDefend_KX"] as? Bool)
        XCTAssertEqual(PidMap.canDefend(7857), caps["canDefend_V1"] as? Bool)
        XCTAssertEqual(PidMap.canDefend(12193), caps["canDefend_GW"] as? Bool)
        XCTAssertEqual(PidMap.canTailgate(7858, fw: "1.0.2"), caps["canTailgate_V1Pro_oldFw"] as? Bool)
        XCTAssertEqual(PidMap.canTailgate(7858, fw: "1.0.3"), caps["canTailgate_V1Pro_newFw"] as? Bool)
        XCTAssertEqual(PidMap.canDeviceUpgrade(8098), caps["canDeviceUpgrade_KX"] as? Bool)
        let table = try XCTUnwrap(Self.golden["pidTable"] as? [String: Any])
        // golden.pidTable 是「名字→pid」表 (JS PID 枚举), Swift names 是「pid→名字」 — 两个方向都要验
        XCTAssertEqual(table["KX"] as? Int, 8098, "pidTable KX")
        XCTAssertEqual(table["ZKBBV1"] as? Int, 16289, "pidTable ZKBBV1")
        XCTAssertEqual(PidMap.names[8098], "KX", "names[KX pid]")
        XCTAssertEqual(PidMap.names[16289], "ZKBBV1", "names[ZKBBV1 pid]")
    }

    // ================= 网关 38 应答解析 =================
    func testGatewayStatus() throws {
        let gs = try XCTUnwrap(Self.golden["gwStatus"] as? [String: Any])
        let klvs: [ZKLV] = [
            ZKLV(key: 0x01, val: "aabbccddeeff", vlen: 6),
            ZKLV(key: 0x02, val: "090205", vlen: 3),
            ZKLV(key: 0x03, val: HexKit.hex(Array("V5.2".utf8)), vlen: 4),
            ZKLV(key: 0x04, val: HexKit.hex(Array("MyWiFi".utf8)), vlen: 6),
            ZKLV(key: 0x05, val: HexKit.hex(Array("192.168.1.3".utf8)), vlen: 11),
            ZKLV(key: 0x06, val: "01", vlen: 1)
        ]
        let s = HardwareService.parseGWStatus(klvs)
        XCTAssertEqual(s.wifimac, gs["wifimac"] as? String)
        XCTAssertEqual(s.romVer, gs["romVer"] as? String)
        XCTAssertEqual(s.eCtrlVer, gs["eCtrlVer"] as? String)
        XCTAssertEqual(s.ssid, gs["ssid"] as? String)
        XCTAssertEqual(s.wifiIP, gs["wifiIP"] as? String)
        XCTAssertEqual(s.netState, gs["netState"] as? Int)
        let empty = try XCTUnwrap(Self.golden["gwStatus_empty"] as? [String: Any])
        let s0 = HardwareService.parseGWStatus([])
        XCTAssertEqual(s0.netState, empty["netState"] as? Int)
    }

    // ================= 钥匙串 43 应答解析 =================
    func testKeychainStatus() throws {
        let gs = try XCTUnwrap(Self.golden["kcStatus"] as? [String: Any])
        let klvs: [ZKLV] = [
            ZKLV(key: 0x03, val: "00", vlen: 1),
            ZKLV(key: 0x11, val: "55", vlen: 1),
            ZKLV(key: 0x12, val: "3c", vlen: 1),
            ZKLV(key: 0x24, val: "02", vlen: 1),
            ZKLV(key: 0x25, val: "08", vlen: 1),
            ZKLV(key: 0x31, val: "090205", vlen: 3),
            ZKLV(key: 0x34, val: "a13f0000", vlen: 4),
            ZKLV(key: 0x35, val: "010203", vlen: 3),
            ZKLV(key: 0x36, val: "82fa", vlen: 2)
        ]
        let s = HardwareService.parseKCStatus(klvs)
        XCTAssertEqual(s.power, gs["power"] as? Int)
        XCTAssertEqual(s.absPower, gs["absPower"] as? Int)
        XCTAssertEqual(s.ekeyCount, gs["ekeyCount"] as? Int)
        XCTAssertEqual(s.ekeyAmount, gs["ekeyAmount"] as? Int)
        XCTAssertEqual(s.firmware, gs["firmware"] as? String)
        XCTAssertEqual(s.pid, gs["pid"] as? Int)
        XCTAssertEqual(s.eCtrl, gs["eCtrl"] as? String)
        let macs = try XCTUnwrap(Self.golden["kcEkeyMacs"] as? [String])
        // 真实调用 parseEkeyMacs: KLV#04 每 6B 一台 (原断言是字面量比字面量, 恒真)
        let parsed = HardwareService.parseEkeyMacs([ZKLV(key: 0x04, val: "aabbccddeeff112233445566", vlen: 12)])
        XCTAssertEqual(parsed, macs)
    }

    // ================= 归属推断 =================
    func testAttribution() throws {
        let golden = try XCTUnwrap(Self.golden["attribution"] as? [[String: Any]])
        let st = try XCTUnwrap(Self.golden["attribution_status"] as? [String: Any])
        let now = Int64(st["lockTime"] as? Int ?? 0)
        let logs = [
            LogEntry(type: 4, typeName: "临时密码开门", idx: 1, idxRaw: 1, lockTime: now - 60, lockTimeStr: "", body: ""),
            LogEntry(type: 3, typeName: "指纹开门", idx: 2, idxRaw: 2, lockTime: now - 120, lockTimeStr: "", body: ""),
            LogEntry(type: 7, typeName: "撬锁", idx: 3, idxRaw: 3, lockTime: now - 30, lockTimeStr: "", body: "")
        ]
        let rows = Attribution.classify(
            logs: logs,
            pwds: [LedgerPwd(alias: 0, from: "2026-01-01 00:00:00", to: "2118-01-01 00:00:00", temp: true, at: 0, pwd: nil, owner: "m1", note: "")],
            fps: [LedgerFp(batch: 1, name: "指纹1", at: 0, note: "", src: nil, owner: "m2", isAlarm: false)],
            status: (1, 1, now))
        XCTAssertEqual(rows.count, golden.count)
        for (i, g) in golden.enumerated() {
            XCTAssertEqual(rows[i].who, g["who"] as? String, "attribution[\(i)].who")
            XCTAssertEqual(rows[i].provable, g["provable"] as? String, "attribution[\(i)].provable")
            XCTAssertEqual(rows[i].kind, g["kind"] as? String, "attribution[\(i)].kind")
        }
    }

    // ================= 时间基准 =================
    func testEpoch() throws {
        let t = try XCTUnwrap(Self.golden["time"] as? [String: Any])
        XCTAssertEqual(ZKProtocol.epochMs, t["epochMs"] as? Int64)
        XCTAssertEqual(ZKProtocol.protoSecondsFromMs(1_262_304_000_000), (t["protoFromMs_zero"] as? Int).map(Int64.init))
    }

    // ================= inflate (Apple Compression vs node zlib 金标) =================
    func testInflate() throws {
        let vectors = try XCTUnwrap(Self.golden["inflate"] as? [[String: Any]])
        for (i, v) in vectors.enumerated() {
            let rawB64 = try XCTUnwrap(v["raw"] as? String)
            let defB64 = try XCTUnwrap(v["deflated"] as? String)
            let size = try XCTUnwrap(v["size"] as? Int)
            guard let raw = Data(base64Encoded: rawB64), let def = Data(base64Encoded: defB64) else {
                return XCTFail("inflate[\(i)] base64 解码失败")
            }
            let out = try ZipKit.inflate([UInt8](def), expected: size)
            XCTAssertEqual(out, [UInt8](raw), "inflate[\(i)] 往返不一致")
        }
    }

    // ================= 真实固件包解析 (KX_V5.2.9) =================
    func testDfuZipParse() throws {
        let g = try XCTUnwrap(Self.golden["dfuZip"] as? [String: Any])
        guard let url = Bundle(for: GoldenDiffTests.self).url(forResource: "KX_V5.2.9_180503183402", withExtension: "zip"),
              let data = try? Data(contentsOf: url) else {
            return XCTFail("测试 bundle 缺少固件包 fixture")
        }
        let fw = try FirmwareKit.parse(zipData: [UInt8](data), fileName: g["fileName"] as? String ?? "")
        XCTAssertEqual(fw.binSize, g["binSize"] as? Int)
        XCTAssertEqual(fw.datSize, g["datSize"] as? Int)
        XCTAssertEqual(fw.version, g["version"] as? String)
        XCTAssertEqual(CRC32.crc32(HexKit.bytes(fw.binHex)), UInt32(g["binCrc32"] as? Int ?? 0))
        XCTAssertEqual(fw.datHex, g["datHex"] as? String)
        XCTAssertEqual(FirmwareKit.nextMac("aabbccddeeff"), g["nextMac"] as? String)
        XCTAssertEqual(FirmwareKit.nextMac("aabbccddeeff0f"), g["nextMac_wrap"] as? String)
        XCTAssertEqual(FirmwareKit.versionLt("5.2.8", "5.2.9"), g["versionLt_528_529"] as? Bool)
        XCTAssertEqual(FirmwareKit.versionLt("5.2.9", "5.2.9"), g["versionLt_529_529"] as? Bool)
    }

    // ================= rc 文案表 =================
    func testRcMsg() throws {
        let table = try XCTUnwrap(Self.golden["rcMsgTable"] as? [String: String])
        for (k, v) in table {
            XCTAssertEqual(StatusParser.rcMessage(Int(k) ?? -1), v, "rc \(k)")
        }
    }
}