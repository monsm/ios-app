// 手机钥匙（pk 池分配 / 有效期 / 撤销语义）纯逻辑单测 —— 不依赖真机 BLE。
//
// 只测「不发命令的那一半」：pin 分配、有效期标签、持久化编解码容错。
// 真正发 cmd08/cmd41 的部分要真锁，见 docs/DFU-AND-MOBILEKEY-DEVICE-CHECKLIST.md。
import XCTest
import Foundation
@testable import OfflineLock

/// 2026-10-26: 本类测的 MobileKeyService / DefendService / BackupPassphrase / TrialGuard
/// 都是 @MainActor 隔离的（它们直接读写 AppState 与 SwiftUI 状态），
/// 而 XCTestCase 子类默认非隔离 ⇒ 加 @MainActor 让测试方法与被测对象在同一隔离域。
@MainActor
final class MobileKeyServiceTests: XCTestCase {

    private func kc(pins: [String]) -> Keychain {
        Keychain(mac: "aabbccddeeff", pid: 8098, name: "前门", skey: "00112233445566778899aabbccddeeff", pins: pins)
    }
    private func key(pin: String, id: String = "k1") -> MobileKey {
        MobileKey(id: id, pin: pin, ekey: "deadbeef", memberID: "m1", memberName: "老妈",
                  forever: true, validFrom: "2010-01-01 00:00:00", validTo: "2118-01-01 00:00:00", at: 0)
    }

    // MARK: - pin 分配

    /// 取第一个没被占用的 pin —— 与 APK 的 getAvailablePin 同语义（线性扫描、第一个未占用）
    func testAvailablePinPicksFirstFree() {
        let k = kc(pins: ["00000001", "00000002", "00000003"])
        XCTAssertEqual(MobileKeyService.availablePin(k, used: []), "00000001")
        XCTAssertEqual(MobileKeyService.availablePin(k, used: [key(pin: "00000001")]), "00000002")
        XCTAssertEqual(MobileKeyService.availablePin(k, used: [key(pin: "00000001"), key(pin: "00000002", id: "k2")]),
                       "00000003")
    }

    /// 池用尽必须返回 nil，让调用方明确报错 —— 绝不回落到默认 PIN
    /// （HardwareService.writeDongleKey 里有同一条纪律的注释：回落 PIN "1" 等于发一把人人猜得到的钥匙）
    func testAvailablePinReturnsNilWhenExhausted() {
        let k = kc(pins: ["01", "02"])
        let used = [key(pin: "01"), key(pin: "02", id: "k2")]
        XCTAssertNil(MobileKeyService.availablePin(k, used: used))
    }

    /// 空 pin 串必须跳过（历史数据里可能有 ""）
    func testAvailablePinSkipsEmpty() {
        let k = kc(pins: ["", "00000002"])
        XCTAssertEqual(MobileKeyService.availablePin(k, used: []), "00000002")
    }

    func testAvailablePinEmptyPool() {
        XCTAssertNil(MobileKeyService.availablePin(kc(pins: []), used: []))
    }

    // MARK: - 有效期标签

    /// 永久判据与 APK 的 page-delblekey 一致：forever 或 validTo 前 4 位是 "2118"
    func testValidityLabel() {
        XCTAssertEqual(MobileKeyService.validityLabel(key(pin: "01")), "永久有效")
        var custom = key(pin: "02")
        custom.forever = false
        custom.validTo = "2026-12-31 23:59:59"
        XCTAssertEqual(MobileKeyService.validityLabel(custom), "有效至 2026-12-31 23:59:59")
        // 即便 forever=false，只要 validTo 是 2118 也判永久（历史数据容错）
        var legacy = key(pin: "03")
        legacy.forever = false
        legacy.validTo = "2118-01-01 00:00:00"
        XCTAssertEqual(MobileKeyService.validityLabel(legacy), "永久有效")
    }

    // MARK: - 常量与 APK 同值

    func testConstantsMatchAPK() {
        XCTAssertEqual(MobileKeyService.foreverTo, "2118-01-01 00:00:00",
                       "APK buildEkey 的默认 ValidTo（本地口径）")
        XCTAssertEqual(MobileKeyService.epochFrom, "2010-01-01 00:00:00",
                       "APK buildEkey 的默认 ValidFrom")
    }

    // MARK: - Codable 容错（这条是防"旧 JSON 静默回落"的回归）

    /// 缺字段的旧 JSON 必须能解出来并给默认值 —— 而不是 keyNotFound → DB.get 返回 nil
    /// → 界面上悄悄变成"没发过钥匙"。
    func testDecodeToleratesMissingFields() throws {
        let json = #"{"pin":"00000001","ekey":"aa"}"#.data(using: .utf8)!
        let k = try JSONDecoder().decode(MobileKey.self, from: json)
        XCTAssertEqual(k.pin, "00000001")
        XCTAssertEqual(k.ekey, "aa")
        XCTAssertEqual(k.id, "")
        XCTAssertEqual(k.memberName, "")
        XCTAssertTrue(k.forever, "缺 forever 时默认 true（与 init 默认值一致）")
        XCTAssertEqual(k.at, 0)
    }

    func testRoundTrip() throws {
        let k = key(pin: "00000007")
        let data = try JSONEncoder().encode([k])
        let back = try JSONDecoder().decode([MobileKey].self, from: data)
        XCTAssertEqual(back.count, 1)
        XCTAssertEqual(back[0].pin, "00000007")
        XCTAssertEqual(back[0].memberName, "老妈")
        XCTAssertEqual(back[0].id, "k1")
    }

    /// 空数组也要能解（DB.get 首次读到的是 nil，不是空数组；这里覆盖显式存过空表的情况）
    func testDecodeEmptyArray() throws {
        let back = try JSONDecoder().decode([MobileKey].self, from: "[]".data(using: .utf8)!)
        XCTAssertTrue(back.isEmpty)
    }
}
