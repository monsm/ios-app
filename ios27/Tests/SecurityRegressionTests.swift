// SecurityRegressionTests.swift —— 本次审核修掉的安全/正确性缺陷的**回归保护**。
//
// 为什么单独一个文件：这些修复都属于"改回去也没人发现"的类型 ——
//   剪贴板直写、备份明文、空壳模式可读、帧脱敏只处理第一个 hex=、KLV 超长静默截断、
//   CSV/vCard 注入、备份 schema 丢字段、口令摘要降级……
// 其中一部分有静态闸门（Gates/privacy.js）盯着，但闸门查的是"代码形状"，
// 查不出"行为对不对"。这里用可执行断言把行为钉住。
//
// 依赖：全部走 Engine 层纯逻辑（不碰 UI），所以能在 CI 上真跑。
import XCTest
@testable import LockKeeper

@MainActor
final class SecurityRegressionTests: XCTestCase {

    // MARK: - SEC-31：KLV 超长必须**拒绝**，不能静默截断

    func testKLVRejectsOversizedPayload() {
        // 协议 KLV 的长度字段只有 1 字节。旧实现超长时截到 255 字节后照常返回 ——
        // 结果是"看着成功、实际是半截口令"（超长 WiFi 密码 → 网关永远连不上）。
        let oversized = String(repeating: "ab", count: 256)   // 256 字节 > 255
        XCTAssertEqual(ZKProtocol.buildKLV(0x04, oversized), "",
                       "超过 255 字节的 KLV 必须返回空串（由成帧收口判失败），不能截断后继续发")
        // 边界：正好 255 字节仍然合法
        let exact = String(repeating: "ab", count: 255)
        let built = ZKProtocol.buildKLV(0x04, exact)
        XCTAssertFalse(built.isEmpty, "255 字节是合法上界")
        XCTAssertEqual(built.count, 2 + 2 + 255 * 2, "key(1B) + len(1B) + payload(255B)")
    }

    // MARK: - SEC-23：帧脱敏必须处理**每一个** hex=，且超长帧不能漏明文

    func testFrameRedactHandlesEveryHexSegment() {
        let payload = String(repeating: "deadbeef", count: 8)
        let msg = "TX hex=\(payload) 然后 hex=\(payload)"
        let redacted = FrameRedact.apply(msg)
        // 两个 hex 段都必须被遮：旧实现只处理第一个，第二个原样落盘。
        XCTAssertFalse(redacted.contains(payload), "第二个 hex= 段也必须脱敏")
        XCTAssertTrue(redacted.contains("已脱敏"))
        XCTAssertEqual(redacted.components(separatedBy: "已脱敏").count - 1, 2,
                       "两个 hex= 段应各自产出一处脱敏标记")
    }

    func testFrameRedactKeepsShortHexHidden() {
        // 短 hex（不足 8 字节帧头）也可能承载凭据（例如只打了 4 字节 PIN）——
        // 不能因为"不够一个帧头"就原样输出。
        let short = "TX hex=1234 结束"
        let redacted = FrameRedact.apply(short)
        XCTAssertFalse(redacted.contains("1234"), "短 hex 也必须遮掉，不留明文")
    }

    // MARK: - SEC-12：CSV 公式注入 / vCard 行注入

    /// 取出单元格的**实际内容**（去掉 CSV 外层引号与内部转义），
    /// 这样断言的是"Excel 会看到什么"，而不是"字符串长什么样"。
    private func csvCellValue(_ field: String) -> String {
        guard field.hasPrefix("\""), field.hasSuffix("\""), field.count >= 2 else { return field }
        let inner = String(field.dropFirst().dropLast())
        return inner.replacingOccurrences(of: "\"\"", with: "\"")
    }

    func testCSVFieldBlocksFormulaInjection() {
        for dangerous in ["=HYPERLINK(\"http://x\")", "+cmd|' /C calc'!A0", "-2+3", "@SUM(A1)"] {
            let cell = csvCellValue(RecordCSV.field(dangerous))
            // 关键：Excel/Numbers 拿到的单元格内容必须以单引号开头（那才是"按文本处理"），
            // 而不是断言原始 field 字符串 —— 含逗号/引号的值还会被外层加引号，
            // 直接 hasPrefix("'") 会误判。
            XCTAssertTrue(cell.hasPrefix("'"), "单元格内容必须以单引号开头：\(dangerous) → \(cell)")
        }
        // 普通值不应被加引号前缀（不能为了安全把正常数据弄脏）
        XCTAssertEqual(RecordCSV.field("门锁"), "门锁")
        XCTAssertEqual(RecordCSV.field("2026-01-01"), "2026-01-01")   // 以数字开头，不是危险首字符
    }

    func testCSVFieldQuotesCommasAndQuotes() {
        XCTAssertEqual(RecordCSV.field("a,b"), "\"a,b\"")
        XCTAssertEqual(RecordCSV.field("a\"b"), "\"a\"\"b\"")
        // 回车必须被换掉，否则一行数据能伪造出额外的 CSV 行
        XCTAssertFalse(RecordCSV.field("a\rb").contains("\r"))
    }

    func testVCardEscapesCarriageReturn() {
        // 未转义的 \r 能伪造出额外的 vCard 行（注入 TEL/EMAIL 等字段）
        let escaped = MemberVCard.escape("x\rY:TEL:123")
        XCTAssertFalse(escaped.contains("\r"), "回车必须转义")
        XCTAssertTrue(escaped.contains("\\r"))
        XCTAssertEqual(MemberVCard.escape("a,b"), "a\\,b")
        XCTAssertEqual(MemberVCard.escape("a;b"), "a\\;b")
    }

    // MARK: - SEC-06：备份口令摘要不许降级成弱摘要

    func testMergedPasscodeRecordNeverDowngrades() {
        // 包里有 d2（强摘要）→ 直接用包的
        let withStrong = BackupBundle.Globals.PasscodeRec(s: "abcdef01", d: "deadbeef", d2: "strong0123")
        let merged = BackupStudio.mergedPasscodeRecord(withStrong, key: "kf_test_passcode")
        XCTAssertEqual(merged["d2"], "strong0123")
        XCTAssertEqual(merged["s"], "abcdef01")

        // 旧包没有 d2，且本机也没有同 salt 的 d2 → 只写 s/d（不伪造 d2）
        DB.store.remove("kf_test_passcode")
        let legacy = BackupBundle.Globals.PasscodeRec(s: "abcdef01", d: "deadbeef", d2: nil)
        let legacyMerged = BackupStudio.mergedPasscodeRecord(legacy, key: "kf_test_passcode")
        XCTAssertNil(legacyMerged["d2"], "没有强摘要时不许凭空造一个")
        XCTAssertEqual(legacyMerged["d"], "deadbeef")
    }

    // MARK: - SEC-02：备份包必须带得动 d2（CodingKeys 漏列会静默丢字段）

    func testAppearanceCodableRoundTripKeepsAllFields() throws {
        // 手写 CodingKeys 一旦漏列字段，Codable 会**完全忽略**它 ——
        // 备份包里就永远没有这一项，恢复时也永远读不到。
        var ap = BackupBundle.Globals.Appearance()
        ap.theme = "dark"
        ap.motion = "calm"
        ap.heroTex = "grain"
        ap.axBigOtp = true
        ap.axHold = "0.9"
        ap.dialSize = 176
        ap.gestureMode = "hold"
        ap.holdConfirm = false
        ap.elderMode = true

        let data = try JSONEncoder().encode(ap)
        let back = try JSONDecoder().decode(BackupBundle.Globals.Appearance.self, from: data)
        XCTAssertEqual(back.theme, "dark")
        XCTAssertEqual(back.motion, "calm", "motion 曾被 CodingKeys 漏列 ⇒ 备份里根本没有它")
        XCTAssertEqual(back.heroTex, "grain", "heroTex 同上")
        XCTAssertEqual(back.axBigOtp, true, "无障碍档曾整批漏列")
        XCTAssertEqual(back.axHold, "0.9")
        XCTAssertEqual(back.dialSize, 176)
        XCTAssertEqual(back.gestureMode, "hold")
        XCTAssertEqual(back.holdConfirm, false)
        XCTAssertEqual(back.elderMode, true)
    }

    // MARK: - SEC-14：校验和不一致必须能被判定出来

    func testChecksumMismatchIsDetected() {
        // 测试宿主里没有任何锁，collectAll() 会给出空包 —— 那样"改 MAC"就无从谈起。
        // 这里**显式构造**一个含单把锁的包：既确定有数据可改，也不依赖测试宿主的存储状态。
        let mac = "aabbccddeeff"
        let kc = Keychain(mac: mac, pid: 16289, pidName: "ZKBBV1", name: "前门",
                          skey: "00112233445566778899aabbccddeeff")
        var ledger = Ledger()
        ledger.pwds = [LedgerPwd(alias: 1, from: "2026-01-01 00:00:00", to: "2118-01-01 00:00:00",
                                 temp: false, at: 0, pwd: "123456", owner: "m1", note: "门锁密码")]
        let bundle = BackupBundle(at: "2026-01-01T00:00:00Z", currentMac: mac,
                                  devices: [BackupBundle.Device(mac: mac, kc: kc, ledger: ledger,
                                                                     meta: nil)],
                                  members: nil, globals: nil)
        let text = BackupCanonical.exportText(bundle)
        XCTAssertFalse(text.isEmpty, "导出文本不能为空")
        XCTAssertEqual(BackupStudio.checksumState(text), .ok, "自己导出的包必须自校验通过")

        // 改**数据**（不是格式）：canonical 会把 JSON 重新序列化，往空格里插字节不改变校验和。
        // 必须改一个真正进入 canonical 的值 —— 这里改设备 MAC。
        var tampered = text
        guard let macRange = tampered.range(of: "\"aabbccddeeff\"") else {
            return XCTFail("导出的包里没有预期 MAC，测试前提不成立")
        }
        tampered.replaceSubrange(macRange, with: "\"aabbccddee00\"")
        XCTAssertEqual(BackupStudio.checksumState(tampered), .mismatch,
                       "被改过数据的包必须判 mismatch —— 恢复路径据此拒绝覆盖真数据")
    }

    // MARK: - SEC-15：帧归属路由（两个服务共用一条连接）

    func testFrameOwnerRoutingIsolatesSubscribers() {
        let ble = BLEService.shared
        var lockSeen: [UInt8] = []
        var hwSeen: [UInt8] = []
        ble.onFrame(owner: "test-lock") { f in lockSeen.append(f.cmd) }
        ble.onFrame(owner: "test-hw") { f in hwSeen.append(f.cmd) }

        // 无归属：两边都收到（配网期两边都要看状态帧）
        ble.setFrameOwner(nil)
        ble.emit(ZKProtocol.ParsedFrame(ok: true, cmd: 0x03, header: 8, klvs: [], raw: "87"))
        XCTAssertEqual(lockSeen, [0x03])
        XCTAssertEqual(hwSeen, [0x03])

        // 归属给 lock：只有 lock 收到 —— 这正是 SEC-15 要防的"回包被错的服务拿走"
        ble.setFrameOwner("test-lock")
        ble.emit(ZKProtocol.ParsedFrame(ok: true, cmd: 0x44, header: 8, klvs: [], raw: "87"))
        XCTAssertEqual(lockSeen, [0x03, 0x44])
        XCTAssertEqual(hwSeen, [0x03], "非归属方不得收到这条回包")

        ble.setFrameOwner(nil)
    }

    // MARK: - SEC-16：协议解析必须对脏输入显式失败

    func testStrictHexRejectsNoise() {
        XCTAssertNil(HexKit.strictBytes("zz"))
        XCTAssertNil(HexKit.strictBytes("abc"))          // 奇数长度
        XCTAssertNil(HexKit.strictBytes("12g4"))
        XCTAssertEqual(HexKit.strictBytes("1234"), [0x12, 0x34])
        XCTAssertEqual(HexKit.strictBytes("ABCD"), [0xAB, 0xCD], "大写也必须接受")
        // parseKLV 对含噪声的输入必须返回 nil，而不是解出垃圾 KLV
        XCTAssertNil(ZKProtocol.parseKLV("01zz"))
        XCTAssertNil(ZKProtocol.parseKLV("0a05aabbcc"))
    }

    // MARK: - 台账口令：密钥库 往返（SEC-01 的核心行为）

    /// 密钥库 在**未签名**的单元测试宿主里通常不可用（errSecMissingEntitlement）。
    /// 所以这组断言在 密钥库 不可用时会显式跳过，而不是"失败"或"假装通过" ——
    /// 静默通过比红更糟，无差别红也会掩盖真问题。
    private var keychainAvailable: Bool {
        SecretStore.set("probe", for: "test.keychain.probe")
    }

    func testLedgerPasswordRoundTripsThroughKeychain() throws {
        try XCTSkipUnless(keychainAvailable,
                          "密钥库 在本测试宿主不可用（未签名 bundle）—— 跳过而非假通过")
        SecretStore.remove("test.keychain.probe")
        let mac = "aabbccddeeff"
        let account = DB.pwdSecretAccount(mac, 7)
        XCTAssertEqual(account, "ledger.aabbccddeeff.pwd.7")

        // 写：口令进 密钥库，plist 副本里 pwd 变 nil
        XCTAssertTrue(SecretStore.set("123456", for: account), "密钥库 写入应成功（模拟器允许）")
        XCTAssertEqual(SecretStore.get(account), "123456")

        var ledger = Ledger()
        ledger.pwds = [LedgerPwd(alias: 7, from: "2026-01-01 00:00:00", to: "2118-01-01 00:00:00",
                                 temp: false, at: 0, pwd: "123456", owner: "m1", note: "门锁密码")]
        DB.saveLedger(mac, ledger)

        // 读：ledger() 必须把口令从 密钥库 回填出来
        let read = DB.ledger(mac)
        XCTAssertEqual(read.pwds.first?.pwd, "123456", "读路径必须从 密钥库 回填明文")
        XCTAssertEqual(read.pwds.first?.owner, "m1")

        // plist 副本（不经过 ledger()）里不该再有明文
        if let raw = DB.store.get(Ledger.self, "kf_ledger_" + mac) {
            XCTAssertNil(raw.pwds.first?.pwd, "plist 里的台账副本不许留明文口令")
        } else {
            XCTFail("台账没有落盘")
        }

        SecretStore.remove(account)
    }

    // MARK: - 空壳模式：读路径必须返回空，写路径必须拒绝

    func testDecoyModeHidesAndBlocksWrites() {
        let mac = "aabbccddeeff"
        var ledger = Ledger()
        ledger.pwds = [LedgerPwd(alias: 1, from: "2026-01-01 00:00:00", to: "2118-01-01 00:00:00",
                                 temp: false, at: 0, pwd: nil, owner: "m1", note: "保留")]
        DB.saveLedger(mac, ledger)
        XCTAssertEqual(DB.ledger(mac).pwds.count, 1)

        DB.setDecoy(true)
        XCTAssertTrue(DB.ledger(mac).pwds.isEmpty, "空壳模式必须读不到凭证")
        XCTAssertTrue(DB.members().isEmpty, "空壳模式必须读不到成员")
        XCTAssertTrue(DB.readLogs(mac).isEmpty, "空壳模式必须读不到台账")
        XCTAssertTrue(DB.keychains().isEmpty, "空壳模式必须读不到锁清单")
        XCTAssertNil(DB.keychain(mac), "空壳模式必须拿不到钥匙串")

        // 写路径必须拒绝：否则空台账会覆盖真台账，凭证全丢（N-01）
        var overwrite = Ledger()
        overwrite.pwds = []
        DB.saveLedger(mac, overwrite)

        DB.setDecoy(false)
        XCTAssertEqual(DB.ledger(mac).pwds.count, 1,
                       "空壳模式下的写入必须被拒绝，真实台账不能被空表覆盖")
    }

    // MARK: - 空壳模式的**通知面**（SEC-03 同一族的最后一个出口）

    /// 空壳模式必须把本 App 的通知**整族**清掉，因为两个生产者的文案都带真实名称：
    ///   · 凭证到期提醒 → 带凭证名（「密码临期 · 前门密码」）
    ///   · 低电提醒 → 带锁名（「<锁名>」只剩 20%）
    /// 数据层已清空（SEC-03），但通知中心还留着这些文案，等于当面把名字念出来。
    func testOwnNotificationIDsAreRecognisable() {
        // 真实标识形状（与生产者逐字一致）：
        XCTAssertTrue(CredentialOrg.isOwnNotification("c6.alert.aabbccddeeff.p1.d7"))
        XCTAssertTrue(CredentialOrg.isOwnNotification("c6.alert.aabbccddeeff.p12.t0"))
        XCTAssertTrue(CredentialOrg.isOwnNotification("c6.monthly"))
        XCTAssertTrue(CredentialOrg.isOwnNotification("c6.batt.aabbccddeeff.l2"),
                      "低电提醒正文带锁名，也必须被清")
        // 不是本 App 的标识不许被误杀
        XCTAssertFalse(CredentialOrg.isOwnNotification("com.example.other"))
        XCTAssertFalse(CredentialOrg.isOwnNotification(""))
    }

    // MARK: - 回收站/版本历史的写路径（空壳下不许覆盖）

    /// 写路径必须读**原始存储**。旧实现在 addPwds 里用 `all(mac)`，
    /// 而 `all()` 在空壳模式返回 `[]` ⇒ 空壳里一次删除级联会把整个回收站覆盖成只剩新条目。
    /// 这条用例直接在空壳下写一次，确认既有条目仍在。
    func testBinWriteDoesNotWipeHistoryInDecoyMode() {
        let mac = "aabbccddeeff"
        CredBinStore.clear(mac)
        let p1 = LedgerPwd(alias: 1, from: "2026-01-01 00:00:00", to: "2118-01-01 00:00:00",
                           temp: false, at: 0, pwd: nil, owner: nil, note: "旧条目")
        CredBinStore.addPwds(mac, [p1], batchId: "b1", source: "测试")
        XCTAssertEqual(CredBinStore.all(mac).count, 1)

        // 进空壳后再写一条（模拟空壳中的删除级联）
        DB.setDecoy(true)
        let p2 = LedgerPwd(alias: 2, from: "2026-01-01 00:00:00", to: "2118-01-01 00:00:00",
                           temp: false, at: 0, pwd: nil, owner: nil, note: "空壳里删的")
        CredBinStore.addPwds(mac, [p2], batchId: "b2", source: "测试")
        DB.setDecoy(false)

        let items = CredBinStore.all(mac)
        XCTAssertEqual(items.count, 2, "空壳里的写入把既有回收站条目覆盖掉了（写路径误用了展示层过滤）")
        XCTAssertTrue(items.contains { $0.pwd?.note == "旧条目" }, "旧条目必须还在")
        CredBinStore.clear(mac)
    }

    /// 回收站必须有上限（与版本历史的 10 份同一族：都是"最近删除"）。
    /// 旧实现无上限 ⇒ plist 数组与 Keychain 口令副本一起无限堆积。
    func testBinHasRetentionCap() {
        XCTAssertGreaterThan(CredBinStore.maxItems, 0)
        XCTAssertLessThanOrEqual(CredBinStore.maxItems, 500,
                                 "回收站上限过大就等于没有上限（口令副本会一起堆积）")
    }

    // MARK: - 记录页覆盖层：空壳一致性与写路径

    /// 备注/旗标/处置三族必须与空壳同口径（都按行键存在，都泄露"有这条记录"）。
    /// 旧实现里 `notes()` 判空壳、`flags()` 不判 —— 同一份数据两种待遇。
    func testRecordOverlayIsDecoyConsistent() {
        let mac = "aabbccddeeff"
        RecordOverlay.setNote(mac, "1", "备注甲")
        _ = RecordOverlay.toggleFlag(mac, "1")
        DB.setDecoy(true)
        defer { DB.setDecoy(false) }
        XCTAssertTrue(RecordOverlay.notes(mac).isEmpty, "空壳不该暴露备注")
        XCTAssertTrue(RecordOverlay.flags(mac).isEmpty, "空壳不该暴露旗标（旧实现这里漏了）")
        XCTAssertTrue(RecordOverlay.dispositions(mac).isEmpty, "空壳不该暴露处置")
        DB.setDecoy(false)
        _ = RecordOverlay.toggleFlag(mac, "1")   // 清掉，避免污染其它用例
    }

    /// 空壳里改一条备注，**不能**把整张备注表覆盖成只剩这一条。
    /// 旧实现 `setNote` 用 `notes(mac)` 读，而它在空壳返回 [:] —— 整表被抹。
    func testOverlayWriteInDecoyDoesNotWipeTable() {
        let mac = "aabbccddeeff"
        RecordOverlay.setNote(mac, "1", "旧备注")
        DB.setDecoy(true)
        RecordOverlay.setNote(mac, "2", "空壳里写的")
        DB.setDecoy(false)
        let table = RecordOverlay.notes(mac)
        XCTAssertEqual(table[RecordOverlay.oid(mac: mac, rowKey: "1")], "旧备注", "旧备注被抹掉了（写路径误用展示层读取器）")
        XCTAssertEqual(table[RecordOverlay.oid(mac: mac, rowKey: "2")], "空壳里写的")
        // 清理，避免污染其它用例
        RecordOverlay.setNote(mac, "1", "")
        RecordOverlay.setNote(mac, "2", "")
    }

    // MARK: - 手机钥匙：空壳一致性与写路径

    /// `list()` 是展示层（空壳返回空）；`rawList()` 是写路径用的原始读。
    /// 旧实现里 `issue` / `revoke` 都用 `list()` —— 空壳里一次发放或撤销，
    /// 会把整批手机钥匙覆盖成"只剩新的一条"或空表。
    func testMobileKeyRawListSurvivesDecoy() {
        let mac = "aabbccddeeff"
        MobileKeyService.save(mac, [])
        let k = MobileKey(id: "k1", pin: "11223344", ekey: "aabb",
                          memberID: "m1", memberName: "甲", forever: true,
                          validFrom: "2026-01-01 00:00:00", validTo: "2118-01-01 00:00:00",
                          at: 0)
        MobileKeyService.save(mac, [k])
        XCTAssertEqual(MobileKeyService.rawList(mac).count, 1)

        DB.setDecoy(true)
        XCTAssertTrue(MobileKeyService.list(mac).isEmpty, "空壳不该暴露手机钥匙")
        XCTAssertEqual(MobileKeyService.rawList(mac).count, 1,
                       "写路径必须能读到真实存储（否则 issue/revoke 会整批覆盖）")
        DB.setDecoy(false)

        // 清理
        MobileKeyService.save(mac, [])
        SecretStore.remove(MobileKeyService.pinAccount(mac, "k1"))
        SecretStore.remove(MobileKeyService.ekeyAccount(mac, "k1"))
    }

    // MARK: - 备份：类型/规模闸（SEC-30）

    func testBackupImportRejectsForeignAndOversizedPayloads() throws {
        // 非 kf-bundle：必须拒绝
        let foreign = "{\"type\":\"other\",\"bundleVer\":1,\"schema\":5,\"at\":\"\",\"currentMac\":\"\",\"devices\":[]}"
        XCTAssertThrowsError(try BackupStudio.parsePreview(text: foreign, password: nil)) { err in
            XCTAssertTrue((err as? LocalizedError)?.errorDescription?.contains("不是锁管家备份包") ?? false)
        }

        // 超过上限：必须在解析之前就拒绝
        let huge = String(repeating: "a", count: BackupStudio.maxImportBytes + 1)
        XCTAssertThrowsError(try BackupStudio.parsePreview(text: huge, password: nil)) { err in
            XCTAssertTrue((err as? LocalizedError)?.errorDescription?.contains("过大") ?? false)
        }
    }

    // MARK: - 密码校验：失败计数必须持久（SEC-28）

    func testPasscodeFailStreakIsPersistent() {
        // SEC-28：失败计数必须落盘并触发冷却 —— 关掉 sheet 不会清零。
        // 这里从**已知起点**开始（先把计数复位），否则会依赖其它用例留下的状态。
        let lock = AppLock.shared
        lock.unlockByBiometric()          // 清零 failStreak 与 cooldown
        XCTAssertEqual(lock.failStreak, 0)

        XCTAssertEqual(lock.recordFailure(), 0, "第 1 次失败不冷却")
        XCTAssertEqual(lock.recordFailure(), 0, "第 2 次失败不冷却")
        XCTAssertEqual(lock.recordFailure(), 30, "第 3 次失败进入 30 秒冷却")
        XCTAssertGreaterThan(lock.cooldownRemaining(), 0, "冷却必须真的生效")

        // 关键：计数与冷却都写进了持久层（新进程/新实例也读得到）
        XCTAssertEqual(DB.store.getInt("kf_lock_fail", 0), 3, "失败计数必须落盘")
        XCTAssertGreaterThan(DB.store.getDouble("kf_lock_cool", 0), 0, "冷却截止必须落盘")

        lock.unlockByBiometric()          // 复位，避免污染其它用例
    }
}
