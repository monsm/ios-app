// GoldenDiffTests.swift —— 引擎层差分回归：Swift 实现 vs JS 金标（fixtures/golden.json）逐字节断言。
//
// 为什么要有这个文件（G-07）：旧仓 `ios-app/Tests/GoldenDiffTests.swift` 一直存在，
// 但新工程 `ios27` **没有任何测试目标** —— README 却写着"有字节级差分金标已验证"。
// 也就是说：协议帧 / AES / 状态与日志解析 / ZOTP / 归属推断 这些最不该出错的地方，
// 唯一的保护只剩"CI 能不能编译"。本文件把它接回来，CI 跑 `xcodebuild test` 不过就是红。
//
// 纪律：所有断言都必须有"真加载到夹具"的前置检查（testGoldenFixtureLoaded），
// 否则资源没打进 bundle 时全套会**静默通过** —— 那比红更糟。
import XCTest
@testable import Threshold

final class GoldenDiffTests: XCTestCase {
    /// 夹具。Swift 6 下裸 static var 是非隔离可变全局状态，夹具本身又是 [String: Any]（非 Sendable），
    /// 所以用本仓的 Locked 持有，读写都过临界区。
    private static let goldenBox = Locked<[String: Any]>([:])
    static var golden: [String: Any] {
        get { goldenBox.withLock { $0 } }
        set { goldenBox.withLock { $0 = newValue } }
    }

    override class func setUp() {
        super.setUp()
        if let url = Bundle(for: GoldenDiffTests.self).url(forResource: "golden", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            golden = obj
        }
    }

    /// 夹具必须真加载到。为空时下面每条断言都会在空集合上"通过"，等于没测。
    func testGoldenFixtureLoaded() throws {
        XCTAssertFalse(GoldenDiffTests.golden.isEmpty,
                       "fixtures/golden.json 未加载进测试 bundle（检查 project.yml 的 resources 配置）")
        for k in ["aes", "cmds", "parse", "parseAdv", "zotp", "rcMsgTable", "pidTable", "time"] {
            XCTAssertNotNil(GoldenDiffTests.golden[k], "金标缺少顶层键 \(k)")
        }
        let cmds = GoldenDiffTests.golden["cmds"] as? [String: Any] ?? [:]
        XCTAssertEqual(cmds.count, 40, "金标 cmds 应为 40 条，实际 \(cmds.count)")
    }

    // MARK: - AES-128-ECB（含 NIST 向量）

    func testAES() throws {
        let v = try XCTUnwrap(Self.golden["aes"] as? [String: Any])
        let key = "00112233445566778899aabbccddeeff"
        XCTAssertEqual(AESKit.encryptHex("00112233445566778899aabbccddeeff", keyHex: key),
                       v["encrypt_16"] as? String, "aes.encrypt_16")
        XCTAssertEqual(AESKit.encryptHex("8800aabbccddeeff", keyHex: key),
                       v["encrypt_padded"] as? String, "aes.encrypt_padded")
        XCTAssertEqual(AESKit.encryptHex("00112233445566778899aabbccddeeff",
                                         keyHex: "000102030405060708090a0b0c0d0e0f"),
                       v["nist_vector"] as? String, "aes.nist_vector")
    }

    // MARK: - 40 条命令帧（字节级）

    func testCmds() throws {
        let cmds = try XCTUnwrap(Self.golden["cmds"] as? [String: String])
        let MAC = "aabbccddeeff"
        let SKEY = "00112233445566778899aabbccddeeff"
        var built: [String: String] = [:]
        built["cmd01Session"] = ZKCmdBuilder.cmd01Session().hex
        built["cmd03StatusPlain"] = ZKCmdBuilder.cmd03StatusPlain().hex
        built["cmd03StatusWrap"] = ZKCmdBuilder.cmd03StatusWrap(MAC, SKEY).hex
        built["cmd04Open_klv01"] = ZKCmdBuilder.cmd04Open(String(repeating: "cafebabe", count: 4), klv01Hex: "0000").hex
        built["cmd05Exchange"] = ZKCmdBuilder.cmd05Exchange(SKEY, timeSec: 0x5a).hex
        built["cmd08SyncPins"] = ZKCmdBuilder.cmd08SyncPinsBatch(MAC, SKEY, ["11223344", "55667788"],
                                                                delPins: ["ffffffff"])?.hex
        built["cmd0ASyncPwd_add"] = try ZKCmdBuilder.cmd0ASyncPwd(MAC, SKEY, addPwd: "123456",
                                                                  validFrom: "2010-01-01 00:00:00",
                                                                  validTo: "2118-01-01 00:00:00").hex
        built["cmd0ASyncPwd_modify"] = try ZKCmdBuilder.cmd0ASyncPwd(MAC, SKEY, delAlias: 5, addPwd: "654321",
                                                                     validFrom: "2026-01-01 00:00:00",
                                                                     validTo: "2118-01-01 00:00:00").hex
        built["cmd0ASyncPwd_del"] = try ZKCmdBuilder.cmd0ASyncPwd(MAC, SKEY, delAlias: 0xFFFF,
                                                                  validFrom: "2010-01-01 00:00:00",
                                                                  validTo: "2118-01-01 00:00:00").hex
        built["cmd0BExpire"] = ZKCmdBuilder.cmd0BSyncPwdExpire(MAC, SKEY, 5,
                                                              "2026-01-01 00:00:00", "2118-01-01 00:00:00").hex
        built["cmd0ESyncTime"] = ZKCmdBuilder.cmd0ESyncTime(MAC, SKEY, 530000000).hex
        built["cmd12Echo"] = ZKCmdBuilder.cmd12Echo("123456").hex
        built["cmd13AddFp"] = ZKCmdBuilder.cmd13AddFp(MAC, SKEY, 8, 15).hex
        built["cmd14FpConfirm"] = ZKCmdBuilder.cmd14FpConfirm(MAC, SKEY, 77,
                                                             "2010-01-01 00:00:00", "2118-01-01 00:00:00").hex
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
        built["cmd35GWReboot"] = ZKCmdBuilder.cmd35GWReboot().hex
        built["cmd30GWDeviceName"] = ZKCmdBuilder.cmd30GWDeviceName().hex
        built["cmd32GWSetIot"] = ZKCmdBuilder.cmd32GWSetIot("aabb", "cc", "dd").hex

        var mismatches: [String] = []
        for (name, expected) in cmds {
            guard let actual = built[name] else {
                mismatches.append("\(name): Swift 未实现该向量")
                continue
            }
            // 十六进制的大小写不是协议语义（JS 侧出小写、Swift 侧出大写），所以按**字节相等**判定。
            // 长度、顺序、内容仍逐字符比 —— 截断/多一字节/错序照样拦得住。
            if actual.lowercased() != expected.lowercased() {
                mismatches.append("\(name):\n  js=\(expected)\n  sw=\(actual)")
            }
        }
        XCTAssertTrue(mismatches.isEmpty, "命令帧与 JS 金标不一致:\n" + mismatches.joined(separator: "\n"))
    }

    // MARK: - 状态 / 日志解析

    func testParseStatus() throws {
        let parse = try XCTUnwrap(Self.golden["parse"] as? [String: Any])
        let frame = try XCTUnwrap(parse["status_frame"] as? String)
        let parsed = ZKProtocol.parseResponse(frame)
        XCTAssertTrue(parsed.ok)
        XCTAssertEqual(parsed.cmd, 0x03)
        XCTAssertEqual(parsed.header, 8)
        let st = StatusParser.parseStatus(parsed.klvs)
        let g = try XCTUnwrap(parse["status"] as? [String: Any])
        XCTAssertEqual(st.rc, g["rc"] as? Int)
        XCTAssertEqual(st.sKeyStatus, g["sKeyStatus"] as? Int)
        XCTAssertEqual(st.powerLevel, g["powerLevel"] as? Int)
        XCTAssertEqual(st.firmware, g["firmware"] as? String)
        XCTAssertEqual(st.pid, g["pid"] as? Int)
        XCTAssertEqual(st.pinStock, g["pinStock"] as? Int)
        XCTAssertEqual(st.pwdStock, g["pwdStock"] as? Int)
        XCTAssertEqual(st.fpStock, g["fpStock"] as? Int)
        XCTAssertEqual(st.securityLevel, g["securityLevel"] as? Int)
        XCTAssertEqual(st.verKeyboard, g["verKeyboard"] as? Int)
        XCTAssertEqual(st.eCtrlVer, g["eCtrlVer"] as? String)
        XCTAssertEqual(st.lockTime, (g["lockTime"] as? Int).map(Int64.init))
        XCTAssertEqual(st.fpInfoBatchNumber, g["fpInfoBatchNumber"] as? Int)
    }

    func testParseLogs() throws {
        let parse = try XCTUnwrap(Self.golden["parse"] as? [String: Any])
        let frame = try XCTUnwrap(parse["log_frame"] as? String)
        let logs = StatusParser.parseLogs(ZKProtocol.parseResponse(frame).klvs)
        let g = try XCTUnwrap(parse["log_parsed"] as? [[String: Any]])
        XCTAssertEqual(logs.count, g.count)
        for (i, item) in g.enumerated() {
            XCTAssertEqual(logs[i].type, item["type"] as? Int, "log[\(i)].type")
            XCTAssertEqual(logs[i].typeName, item["typeName"] as? String, "log[\(i)].typeName")
            XCTAssertEqual(logs[i].idxRaw, UInt32(item["idxRaw"] as? Int ?? 0), "log[\(i)].idxRaw")
            XCTAssertEqual(logs[i].lockTime, (item["lockTime"] as? Int).map(Int64.init), "log[\(i)].lockTime")
        }
    }

    func testHeaderVariants() throws {
        let parse = try XCTUnwrap(Self.golden["parse"] as? [String: Any])
        let variants = try XCTUnwrap(parse["status_parse_headers"] as? [String: Any])
        for (name, obj) in variants {
            let g = try XCTUnwrap(obj as? [String: Any])
            let frameName = name == "h8" ? "header8" : (name == "h7" ? "header7" : "header10")
            let frame = try XCTUnwrap(parse[frameName] as? String)
            let st = StatusParser.parseStatus(ZKProtocol.parseResponse(frame).klvs)
            XCTAssertEqual(st.rc, g["rc"] as? Int, "header \(name) rc")
        }
    }

    // MARK: - 广播解析

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
        let dfuG = try XCTUnwrap(adv["dfumode"] as? [String: Any])
        let d = try XCTUnwrap(ZKProtocol.parseAdv(try XCTUnwrap(adv["dfumode_input"] as? String)))
        XCTAssertEqual(d.dfuState, dfuG["dfuState"] as? Int)
        XCTAssertEqual(d.macRaw, dfuG["macRaw"] as? String)
    }

    // MARK: - ZOTP（冻结时钟逐字节）

    func testZOTP() throws {
        let zotp = try XCTUnwrap(Self.golden["zotp"] as? [String: Any])
        let fixedSec = (zotp["fixedSec"] as? Int).map(Int64.init) ?? 1_800_000_000
        let cases: [(name: String, period: Int, idx: Int)] = [
            ("v30_0", 30, 0), ("v30_1", 30, 1), ("v30_99", 30, 99), ("v60_0", 60, 0)
        ]
        for c in cases {
            let expected = try XCTUnwrap(zotp[c.name] as? String, c.name)
            let actual = ZOTP.generate(macHex: "aabbccddeeff",
                                       skeyHex: "00112233445566778899aabbccddeeff",
                                       periodMin: c.period, idx: c.idx, nowSec: fixedSec)
            XCTAssertEqual(actual, expected, "zotp.\(c.name)")
        }
    }

    // MARK: - PID 能力矩阵

    func testPidCapabilities() throws {
        let caps = try XCTUnwrap(Self.golden["capabilities"] as? [String: Any])
        XCTAssertEqual(PidMap.canDefend(8098), caps["canDefend_KX"] as? Bool)
        XCTAssertEqual(PidMap.canDefend(7857), caps["canDefend_V1"] as? Bool)
        XCTAssertEqual(PidMap.canDefend(12193), caps["canDefend_GW"] as? Bool)
        XCTAssertEqual(PidMap.canTailgate(7858, fw: "1.0.2"), caps["canTailgate_V1Pro_oldFw"] as? Bool)
        XCTAssertEqual(PidMap.canTailgate(7858, fw: "1.0.3"), caps["canTailgate_V1Pro_newFw"] as? Bool)
        XCTAssertEqual(PidMap.canDeviceUpgrade(8098), caps["canDeviceUpgrade_KX"] as? Bool)
        let table = try XCTUnwrap(Self.golden["pidTable"] as? [String: Any])
        XCTAssertEqual(table["KX"] as? Int, 8098, "pidTable KX")
        XCTAssertEqual(table["ZKBBV1"] as? Int, 16289, "pidTable ZKBBV1")
    }

    // MARK: - 网关 38 / 钥匙串 43 应答

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
    }

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
        let macs = try XCTUnwrap(Self.golden["kcEkeyMacs"] as? [String])
        let parsed = HardwareService.parseEkeyMacs([ZKLV(key: 0x04, val: "aabbccddeeff112233445566", vlen: 12)])
        XCTAssertEqual(parsed, macs)
    }

    // MARK: - 归属推断

    func testAttribution() throws {
        let golden = try XCTUnwrap(Self.golden["attribution"] as? [[String: Any]])
        let st = try XCTUnwrap(Self.golden["attribution_status"] as? [String: Any])
        let now = Int64(st["lockTime"] as? Int ?? 0)
        // 夹具里的 type 是**修正前**的旧编号（4=临时码、3=指纹），而本仓权威表是
        // Attribution.openKind = [11:key, 16:temp, 17:pwd, 19:fp]（按 APK `We` 表勘误）。
        // 夹具真正承载的是**语义**（这一格该归给谁、凭什么归），所以这里按权威表喂对应事件，
        // 断言仍逐条对齐夹具的 kind/who/provable —— 既不失真，也不会把勘误退回去。
        let fixtureTypeToAuthoritative: [Int: Int] = [4: 16, 3: 19, 7: 7]
        let logs = [
            LogEntry(type: 16, typeName: "一次性密码开门", idx: 1, idxRaw: 1, lockTime: now - 60, lockTimeStr: "", body: ""),
            LogEntry(type: 19, typeName: "指纹开门", idx: 2, idxRaw: 2, lockTime: now - 120, lockTimeStr: "", body: ""),
            LogEntry(type: 7, typeName: "撬锁", idx: 3, idxRaw: 3, lockTime: now - 30, lockTimeStr: "", body: "")
        ]
        let rows = Attribution.classify(
            logs: logs,
            pwds: [LedgerPwd(alias: 0, from: "2026-01-01 00:00:00", to: "2118-01-01 00:00:00",
                             temp: true, at: 0, pwd: nil, owner: "m1", note: "")],
            fps: [LedgerFp(batch: 1, name: "指纹1", at: 0, note: "", src: nil, owner: "m2", isAlarm: false)],
            status: (1, 1, now))
        XCTAssertEqual(rows.count, golden.count)
        for (i, g) in golden.enumerated() {
            let fixtureType = g["type"] as? Int ?? -1
            XCTAssertEqual(rows[i].type, fixtureTypeToAuthoritative[fixtureType] ?? fixtureType,
                         "attribution[\(i)].type 未映射到权威表")
            XCTAssertEqual(rows[i].who, g["who"] as? String, "attribution[\(i)].who")
            XCTAssertEqual(rows[i].provable, g["provable"] as? String, "attribution[\(i)].provable")
            XCTAssertEqual(rows[i].kind, g["kind"] as? String, "attribution[\(i)].kind")
        }
    }

    // MARK: - 时间基准 / rc 文案 / inflate

    func testEpoch() throws {
        // epochMs 按**本地墙钟** 2010-01-01 00:00:00 计算（APK 语义：被减数与减数同时区，
        // 偏移自己抵消）。夹具里的 1_262_275_200_000 是**东八区**那一瞬间的 Unix 毫秒，
        // 在 UTC runner 上必然差 28800 秒 —— 那是夹具生成地的时区，不是实现的错。
        // 所以断言写**时区无关的不变量**，而不是某个时区下的绝对毫秒值。
        let t = try XCTUnwrap(Self.golden["time"] as? [String: Any])
        XCTAssertEqual(ZKProtocol.protoSecondsFromMs(ZKProtocol.epochMs), 0,
                       "epoch 自己换算成协议秒必须是 0")
        XCTAssertEqual(ZKProtocol.protoSecondsToMs(0), ZKProtocol.epochMs)
        XCTAssertEqual(ZKProtocol.protoSecondsToMs(123456), ZKProtocol.epochMs + 123456000)
        let fixtureEpoch = (t["epochMs"] as? Int64) ?? 0
        let deltaSec = (ZKProtocol.epochMs - fixtureEpoch) / 1000
        XCTAssertEqual(deltaSec % 3600, 0, "与夹具基准之差必须是整小时（时区偏移）")
        XCTAssertTrue(abs(deltaSec) <= 14 * 3600, "时区偏移超出 ±14 小时 —— 基准算错了")
    }

    func testRcMsg() throws {
        let table = try XCTUnwrap(Self.golden["rcMsgTable"] as? [String: String])
        for (k, v) in table {
            XCTAssertEqual(StatusParser.rcMessage(Int(k) ?? -1), v, "rc \(k)")
        }
    }

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

    func testFirmwareVersionCompare() throws {
        let g = try XCTUnwrap(Self.golden["dfuZip"] as? [String: Any])
        XCTAssertEqual(FirmwareKit.versionLt("5.2.8", "5.2.9"), g["versionLt_528_529"] as? Bool)
        XCTAssertEqual(FirmwareKit.versionLt("5.2.9", "5.2.9"), g["versionLt_529_529"] as? Bool)
    }
}
