// BackupRoundTripTests.swift —— 备份"导出 → 解析 → 恢复"必须**原样带回**。
//
// 为什么值得单独测：备份是本 App 唯一的跨机数据通路。
// 恢复路径有大量分支（merge / keep / skip、冲突裁决、成员重映射、SEC-08 密钥校验），
// 而其中任何一处漏写都是**静默丢数据** —— 不崩、不报错，用户换机后才发现凭证少了。
//
// 本文件不碰 UI，只走 Engine 的纯逻辑，所以能在 CI 上真跑。
import XCTest
@testable import LockKeeper

@MainActor
final class BackupRoundTripTests: XCTestCase {

    private let mac = "aabbccddeeff"

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
    /// 不稳定会让"校验和"永远对不上，恢复路径就会一直判 mismatch（拒绝恢复）。
    func testCanonicalIsDeterministic() {
        let b = sampleBundle()
        let a1 = BackupCanonical.exportText(b)
        let a2 = BackupCanonical.exportText(b)
        XCTAssertEqual(a1, a2, "同一份备份两次导出结果不同 —— 校验和会永远对不上")
        XCTAssertFalse(a1.isEmpty)
    }

    /// 导出 → 解析 → 恢复，凭证条数必须一致。
    /// 这是"备份能不能救回数据"的最基本断言。
    func testRestoreBringsBackCredentials() throws {
        DB.setDecoy(false)
        let b = sampleBundle()
        let text = BackupCanonical.exportText(b)
        let parsed = try BackupStudio.parsePreview(text: text, password: nil)
        XCTAssertEqual(parsed.preview.checksum, .ok, "自己导出的包必须自校验通过")
        XCTAssertEqual(parsed.preview.pwdCount, 2, "预览应报告 2 条密码")
        XCTAssertEqual(parsed.preview.macs, [mac])

        let r = BackupStudio.restore(parsed.bundle, makeSnapshot: false)
        XCTAssertGreaterThanOrEqual(r.imported + r.overwritten, 1, "恢复应至少写回一条")
        let back = DB.ledger(mac)
        XCTAssertEqual(back.pwds.count, 2, "两条密码必须都在")
        XCTAssertEqual(back.fps.count, 1, "指纹必须也在")
        XCTAssertEqual(back.pwds.first(where: { $0.alias == 1 })?.pwd, "123456",
                       "口令明文必须经 Keychain 回填出来（不是丢失）")
        XCTAssertEqual(back.pwds.first(where: { $0.alias == 1 })?.owner, "m1",
                       "归属必须保留")
    }

    /// merge 语义 = **只增不删**：本机已有的凭证不能被备份"删掉"。
    func testMergeNeverDeletesLocalCredentials() throws {
        DB.setDecoy(false)
        // 本机先有一条 alias 9
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
    }

    /// 同 ID 冲突未裁决时**保本机**（只增不删），裁决为取备份时才覆盖。
    func testConflictDefaultsToLocalUnlessAdjudicated() throws {
        DB.setDecoy(false)
        var local = Ledger()
        local.pwds = [LedgerPwd(alias: 1, from: "2026-01-01 00:00:00", to: "2118-01-01 00:00:00",
                                temp: false, at: 0, pwd: nil, owner: nil, note: "本机的 1 号")]
        DB.saveLedger(mac, local)

        let text = BackupCanonical.exportText(sampleBundle())
        let parsed = try BackupStudio.parsePreview(text: text, password: nil)

        // 未裁决 → 保留本机
        _ = BackupStudio.restore(parsed.bundle, makeSnapshot: false)
        XCTAssertEqual(DB.ledger(mac).pwds.first { $0.alias == 1 }?.note, "本机的 1 号",
                       "未裁决时不该覆盖本机凭证")

        // 裁决取备份 → 覆盖
        _ = BackupStudio.restore(parsed.bundle, conflictTakeBackup: ["\(mac):p:1"], makeSnapshot: false)
        XCTAssertEqual(DB.ledger(mac).pwds.first { $0.alias == 1 }?.note, "门锁密码",
                       "裁决为取备份时应覆盖")
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
