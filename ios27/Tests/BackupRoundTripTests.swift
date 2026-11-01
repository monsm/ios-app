// BackupRoundTripTests.swift —— 备份"导出 → 解析 → 恢复"必须**原样带回**。
//
// 为什么值得单独测：备份是本 App 唯一的跨机数据通路。
// 恢复路径分支很多（merge / keep / skip、冲突裁决、成员重映射、SEC-08 密钥校验），
// 而任何一处漏写都是**静默丢数据** —— 不崩、不报错，用户换机后才发现凭证少了。
//
// 本文件不碰 UI，只走 Engine 的纯逻辑，所以能在 CI 上真跑。
//
// 注意隔离：这些用例会写同一台设备的台账（`DB` 是进程级单例），
// 所以每个用例前都要把该 MAC 的台账清成空表 —— 否则会互相污染
// （CI 实测：合并用例留下的 alias 9 让"两条密码"断言看到 3 条）。
import XCTest
@testable import LockKeeper

@MainActor
final class BackupRoundTripTests: XCTestCase {

    private let mac = "aabbccddeeff"

    /// 每个用例前清空该锁的台账，避免跨用例污染（DB 是进程级单例）。
    override func setUp() async throws {
        DB.setDecoy(false)
        DB.saveLedger(mac, Ledger())
    }

    private func sampleBundle() -> BackupBundle {
        let kc = Keychain(mac: mac, pid: 16289, pidName: "ZKBBV1", name: "前门",
                          skey: "00112233445566778899aabbccddeeff",
                          bkey: "aabbccddeeff00112233445566778899",
                          pins: ["11223344", "55667788"])
        var ledger = Ledger()
        ledger.pwds = [
            LedgerPwd(alias: 1, from: "2026-01-01 00:00:00", to: "2118-01-01 00:00:00",
                      temp: false, at: 1_700_000_000_000, pwd: "123456", owner: "m1", note: "门锁密码"),
            LedgerPwd(alias: 2, from: "2026-06-01 00:00:00", to: "2026-07-01 00:00:00",
                      temp: true, at: 1_700_000_000_000, pwd: "888888", owner: "m1", note: "临时"),
        ]
        ledger.fps = [LedgerFp(batch: 1, name: "右手食指", at: 1_700_000_000_000,
                               note: "", src: nil, owner: "m1", isAlarm: nil)]
        return BackupBundle(at: "2026-01-01T00:00:00Z", currentMac: mac,
                            devices: [BackupBundle.Device(mac: mac, kc: kc, ledger: ledger, meta: nil)],
                            members: nil, globals: nil)
    }

    /// canonical 导出必须**稳定**：同一份数据两次导出逐字节相同。
    /// 不稳定会让校验和永远对不上，恢复路径就会一直判 mismatch。
    func testCanonicalIsDeterministic() {
        let b = sampleBundle()
        XCTAssertEqual(BackupCanonical.exportText(b), BackupCanonical.exportText(b),
                       "同一份备份两次导出结果不同 —— 校验和会永远对不上")
        XCTAssertFalse(BackupCanonical.exportText(b).isEmpty)
    }

    /// 新加的两族（成员档案 / 到期提醒档位）必须真的**出现在导出文本里**。
    /// 判据不是"结构体有这个字段"，而是"canonical 会 emit 它" ——
    /// 本仓的导出文本由 `BackupCanonical.canonical` 逐字段构造，
    /// 字段存在但白名单没列 ⇒ 导出文本里没有 ⇒ 换机全丢，且**不报错**。
    func testNewFamiliesReachTheExportedText() throws {
        var b = sampleBundle()
        var ext = MemberExt()
        ext.role = "guest"
        ext.remark = "小张"
        ext.archived = true
        // 用"先建后赋值"而不是全参构造：成员逐一构造要求传齐所有字段，
        // 且实参顺序必须与声明一致 —— 测试里那样写会脆得没法维护。
        var g = b.globals ?? BackupBundle.Globals(keychainDongles: nil, gatewayList: nil,
                                                 memberExt: nil, passcode: nil, duress: nil,
                                                 trace: nil, appearance: nil, deviceOrg: nil)
        g.memberExt = ["m1": ext]
        b.globals = g
        let text = BackupCanonical.exportText(b)
        XCTAssertTrue(text.contains("memberExt"), "成员档案没进导出文本（canonical 白名单漏了）")
        XCTAssertTrue(text.contains("小张"), "备注名没进导出文本")
        XCTAssertTrue(text.contains("guest"), "角色没进导出文本")

        // 提醒档位走 Device.Meta
        var alert = CredAlert()
        alert.h2 = true
        let meta = BackupBundle.Device.Meta(defend: nil, tailgate: nil, synctime: nil,
                                           otpStatus: nil, otpIdx: nil, mobileKeys: nil,
                                           recNotes: nil, recFlags: nil, recDisps: nil,
                                           alerts: ["pwd:1": alert])
        let dev = BackupBundle.Device(mac: mac, kc: b.devices[0].kc, ledger: nil, meta: meta)
        b.devices = [dev]
        let text2 = BackupCanonical.exportText(b)
        XCTAssertTrue(text2.contains("alerts"), "提醒档位没进导出文本（canonical 白名单漏了）")
    }

    /// 导出 → 解析 → 恢复：凭证条数与内容必须回来。
    func testRestoreBringsBackCredentials() throws {
        let text = BackupCanonical.exportText(sampleBundle())
        let parsed = try BackupStudio.parsePreview(text: text, password: nil)
        XCTAssertEqual(parsed.preview.checksum, .ok, "自己导出的包必须自校验通过")
        XCTAssertEqual(parsed.preview.pwdCount, 2, "预览应报告 2 条密码")
        XCTAssertEqual(parsed.preview.fpCount, 1, "预览应报告 1 枚指纹")
        XCTAssertEqual(parsed.preview.macs, [mac])

        _ = BackupStudio.restore(parsed.bundle, makeSnapshot: false)
        let back = DB.ledger(mac)
        XCTAssertEqual(back.pwds.count, 2, "两条密码必须都在")
        XCTAssertEqual(back.fps.count, 1, "指纹必须也在")
        XCTAssertEqual(back.pwds.first { $0.alias == 1 }?.pwd, "123456",
                       "口令明文必须经密钥库回填出来（不是丢失）")
        XCTAssertEqual(back.pwds.first { $0.alias == 2 }?.temp, true, "临时档标记必须保留")
        XCTAssertEqual(back.pwds.first { $0.alias == 2 }?.note, "临时", "备注必须保留")
    }

    /// **归属的纪律**：成员不在本机时 owner 必须被丢弃（不猜、不指向不存在的人）。
    /// 这是 restore 里 `remap[o] ?? (DB.member(o) != nil ? o : nil)` 的语义。
    /// 第一版我把这条断言写反了（期望保留 m1），CI 用正确的产品行为把我判红 ——
    /// 是**测试错了**：备份包没带成员表，恢复后本机没有 m1，留着"m1"只会让
    /// 记录页显示一个不存在的成员。
    func testOwnershipIsDroppedWhenMemberAbsentLocally() throws {
        let text = BackupCanonical.exportText(sampleBundle())
        let parsed = try BackupStudio.parsePreview(text: text, password: nil)
        _ = BackupStudio.restore(parsed.bundle, makeSnapshot: false)
        let p1 = try XCTUnwrap(DB.ledger(mac).pwds.first { $0.alias == 1 })
        XCTAssertNil(p1.owner, "本机没有这位成员时不能留下悬空归属（宁可不归属，也不指向不存在的人）")
        XCTAssertEqual(p1.note, "门锁密码", "但凭证本身与备注必须完好带回")
    }

    /// merge 语义 = **只增不删**：本机已有的凭证不能被备份"删掉"。
    func testMergeNeverDeletesLocalCredentials() throws {
        var local = Ledger()
        local.pwds = [LedgerPwd(alias: 9, from: "2026-01-01 00:00:00", to: "2118-01-01 00:00:00",
                                temp: false, at: 0, pwd: nil, owner: nil, note: "本机独有")]
        DB.saveLedger(mac, local)

        let text = BackupCanonical.exportText(sampleBundle())
        let parsed = try BackupStudio.parsePreview(text: text, password: nil)
        _ = BackupStudio.restore(parsed.bundle, makeSnapshot: false)

        let back = DB.ledger(mac)
        XCTAssertTrue(back.pwds.contains { $0.alias == 9 },
                      "合并恢复把本机独有的凭证删掉了 —— 旧实现就是整表替换")
        XCTAssertTrue(back.pwds.contains { $0.alias == 1 }, "备份里的凭证也要进来")
        XCTAssertEqual(back.pwds.count, 3, "2 条来自备份 + 1 条本机独有，一条都不能少")
    }

    /// 同 ID 冲突未裁决时**保本机**；裁决为取备份时才覆盖。
    func testConflictDefaultsToLocalUnlessAdjudicated() throws {
        var local = Ledger()
        local.pwds = [LedgerPwd(alias: 1, from: "2026-01-01 00:00:00", to: "2118-01-01 00:00:00",
                                temp: false, at: 0, pwd: nil, owner: nil, note: "本机的 1 号")]
        DB.saveLedger(mac, local)

        let text = BackupCanonical.exportText(sampleBundle())
        let parsed = try BackupStudio.parsePreview(text: text, password: nil)

        _ = BackupStudio.restore(parsed.bundle, makeSnapshot: false)
        XCTAssertEqual(DB.ledger(mac).pwds.first { $0.alias == 1 }?.note, "本机的 1 号",
                       "未裁决时不该覆盖本机凭证")

        _ = BackupStudio.restore(parsed.bundle, conflictTakeBackup: ["\(mac):p:1"], makeSnapshot: false)
        XCTAssertEqual(DB.ledger(mac).pwds.first { $0.alias == 1 }?.note, "门锁密码",
                       "裁决为取备份时应覆盖")
    }

    /// 校验和不一致时**只要求二次确认，不硬拒绝**。
    /// 我第 8 轮把它写成硬拒绝，那是过度收紧的回归：本仓早期版本导出的包用旧键序
    /// canonical，FNV 必然对不上，硬拒绝会把用户自己的合法备份彻底挡在门外。
    /// 这条断言把"旧版本包仍可恢复"这个性质钉住。
    func testMismatchRequiresAckNotHardBlock() {
        // .mismatch 必须是"需要确认"而不是"禁止恢复"
        XCTAssertTrue(BackupStudio.checksumNeedsAck(.mismatch),
                      "mismatch 应走二次确认（不能硬拒绝，也不能完全不提示）")
        XCTAssertFalse(BackupStudio.checksumNeedsAck(.ok), "校验和正常时不该多问一句")
        XCTAssertFalse(BackupStudio.checksumNeedsAck(.absent),
                       "没有校验和字段（更早的包）同样不该被硬拦")
    }

    /// 确认必须**绑定内容**：换一份包就要重新问。
    /// 第一版我用一个 Bool 做确认位 —— 它一旦置真就永远放行，
    /// 用户换一份坏包也不再提示，保护等于没有。改成按内容指纹后就要求这条性质。
    func testAckIsBoundToContentNotAToggle() {
        let a = BackupCanonical.fnv1a32Hex("{\"type\":\"kf-bundle\",\"n\":1}")
        let b = BackupCanonical.fnv1a32Hex("{\"type\":\"kf-bundle\",\"n\":2}")
        XCTAssertNotEqual(a, b, "不同内容必须得到不同指纹，否则确认会跨文件泄漏")
        XCTAssertEqual(a, BackupCanonical.fnv1a32Hex("{\"type\":\"kf-bundle\",\"n\":1}"),
                       "同一内容指纹必须稳定（否则每次都要重新确认）")
    }

    /// 非法 skey 的锁必须**整把跳过**，不能写进钥匙串（否则是软砖）。
    func testInvalidSkeyIsSkipped() throws {
        var b = sampleBundle()
        b.devices[0].kc.skey = "not-hex"
        let text = BackupCanonical.exportText(b)
        let parsed = try BackupStudio.parsePreview(text: text, password: nil)
        let before = DB.keychain(mac)?.skey
        let r = BackupStudio.restore(parsed.bundle, makeSnapshot: false)
        XCTAssertGreaterThanOrEqual(r.skipped, 1, "非法 skey 的锁必须计入 skipped")
        XCTAssertEqual(DB.keychain(mac)?.skey, before,
                       "非法 skey 绝不能覆盖本机真密钥（那会让锁再也开不了）")
    }
}
