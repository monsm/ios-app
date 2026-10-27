// 收尾批新增模块的纯逻辑单测（2026-10-26）。
//
// 覆盖：TrialGuard / HeroTexture / DefendService 的纯逻辑部分。
// 不覆盖：DFUKit 的传输层（要真机 BLE，见 docs/DEVICE-CHECKLIST-2026-10-26.md）。
//
// 这些模块的共同点：逻辑极简，但**每一个都曾经"看着有、其实没有"** ——
// 所以测试的重点不是"算得对不对"，而是"这条通路真的连上了"。
import XCTest
import Foundation
@testable import OfflineLock

/// 2026-10-26: 本类测的 MobileKeyService / DefendService / TrialGuard
/// 都是 @MainActor 隔离的（它们直接读写 AppState 与 SwiftUI 状态），
/// 而 XCTestCase 子类默认非隔离 ⇒ 加 @MainActor 让测试方法与被测对象在同一隔离域。
@MainActor
final class NewModulesTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // 每个用例从干净状态开始：这些键都是全局单例
        TrialGuard.set(false)
        DB.store.set("kf_hero_tex", "")
    }

    override func tearDown() {
        TrialGuard.set(false)
        DB.store.set("kf_hero_tex", "")
        super.tearDown()
    }

    // MARK: - TrialGuard（只读试验模式）

    /// 关键回归：这个键此前**只有读、没有写**，护栏永远打不开。
    /// 这条测试盯的就是"写点存在且能改状态"。
    func testTrialGuardToggle() {
        XCTAssertFalse(TrialGuard.isOn, "默认必须是关（fail-safe 方向：关=正常可写）")

        TrialGuard.set(true)
        XCTAssertTrue(TrialGuard.isOn, "开启后必须读得到 —— 这就是原先缺失的那一环")

        TrialGuard.set(false)
        XCTAssertFalse(TrialGuard.isOn, "关闭后必须读得到 false")
    }

    /// 落盘键名必须与 LockService.request 里读的那个字符串一致
    func testTrialGuardKeyMatchesConsumer() {
        XCTAssertEqual(TrialGuard.key, "kf_trial_guard",
                       "LockService.request 读的就是这个字面量；改一处不改另一处 = 护栏又打不开")
    }

    /// 后果说明必须提到"写入类操作停用"，否则用户不知道开了会发生什么
    func testTrialGuardWarningText() {
        XCTAssertTrue(TrialGuard.warning.contains("停用") || TrialGuard.warning.contains("拦"),
                      "说明文案要点明写入被拦：\(TrialGuard.warning)")
    }

    // MARK: - HeroTexture（三档纹理）

    /// 三档的 rawValue 必须与 BackupKit 的白名单逐字一致 ——
    /// 不一致的话，备份恢复会把这个值当非法丢掉（`enumVal("kf_hero_tex", ["", "grid", "grain"])`）。
    func testHeroTextureRawValuesMatchBackupWhitelist() {
        XCTAssertEqual(HeroTexture.off.rawValue, "")
        XCTAssertEqual(HeroTexture.grid.rawValue, "grid")
        XCTAssertEqual(HeroTexture.grain.rawValue, "grain")
        XCTAssertEqual(HeroTexture.allCases.count, 3)
    }

    func testHeroTextureCurrent() {
        DB.store.set("kf_hero_tex", "grid")
        XCTAssertEqual(HeroTexture.current, .grid)
        DB.store.set("kf_hero_tex", "grain")
        XCTAssertEqual(HeroTexture.current, .grain)
        DB.store.set("kf_hero_tex", "")
        XCTAssertEqual(HeroTexture.current, .off)
    }

    /// 未知值一律当 off（fail-closed：宁可没有装饰，也不画一个没定义过的东西）
    func testHeroTextureUnknownFallsBackToOff() {
        DB.store.set("kf_hero_tex", "海市蜃楼")
        XCTAssertEqual(HeroTexture.current, .off, "未定义的值必须回落 off，不能乱画")
    }

    func testHeroTextureTitles() {
        XCTAssertEqual(HeroTexture.off.title, "无纹理")
        XCTAssertEqual(HeroTexture.grid.title, "网格")
        XCTAssertEqual(HeroTexture.grain.title, "颗粒")
    }


    // MARK: - DefendService 的门禁（纯逻辑部分，不发命令）

    /// DefendService.allowed 走 PidMap.canDefend；
    /// 网关与未知 pid 的行为要固定住（未知放行是刻意的：不认识的型号不能一律拦住）
    func testDefendGateByPid() {
        // KX=8098 / V1_Pro=7858 明确支持
        XCTAssertTrue(PidMap.canDefend(8098), "KX 应支持布防")
        XCTAssertTrue(PidMap.canDefend(7858), "V1_Pro 应支持布防")
        // 网关不支持
        XCTAssertFalse(PidMap.canDefend(PidMap.GW), "网关不应出现布防入口")
    }

    /// 与 APK 的白名单同源：canDefend 对未知 pid 放行（fail-open 是有意的，
    /// 因为"没登记的新型号"比"误拦一把能布防的锁"更少见且更容易被用户发现）
    func testDefendGateUnknownPidAllowed() {
        XCTAssertTrue(PidMap.canDefend(99999), "未知 pid 放行 —— 与 APK 的 canDefend 白名单同口径")
    }
}
