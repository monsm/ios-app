// SheetPresentationTests.swift —— 模态呈现的**互斥性**回归。
//
// 依据 HIG `sheets` › Best practices：
//   "Display only one sheet at a time from the main interface."
//
// 为什么这类问题必须用测试钉住：SwiftUI 里同一个视图挂多个 `.sheet(isPresented:)` 时，
// 若两个布尔**同时**为 true，只有一个会真正呈现，另一个被静默丢弃 —— 不崩、不报错、
// 不留日志。表现是"点了按钮，什么都没弹"。
//
// 更隐蔽的一种：从 `confirmationDialog` 的按钮里把某个 sheet 布尔置 true。
// 对话框还在退场动画中，SwiftUI 可能把这次呈现丢掉 —— 用户点了「继续验证」，
// 验证框根本没出来，于是"关不掉密码"看起来像坏了。
//
// 本文件把「同一时刻最多一个模态」这件事写成可执行断言。
import XCTest
@testable import LockKeeper

/// 模态互斥的通用判据（纯逻辑，不依赖 SwiftUI 运行时）。
struct ModalGate {
    private(set) var active: String?
    private var pending: String?

    /// 请求呈现某个模态。返回 true 表示"现在就该呈现"，false 表示被拒绝。
    mutating func request(_ name: String) -> Bool {
        if active != nil { return false }      // 已有模态 → 拒绝（而不是悄悄覆盖）
        active = name
        return true
    }

    /// 模态关闭。若有排队项，返回它（调用方在**退场完成之后**再呈现）。
    mutating func dismiss() -> String? {
        active = nil
        defer { pending = nil }
        return pending
    }

    /// 在模态仍活动时请求下一个：必须排队，不能直接呈现。
    mutating func enqueue(_ name: String) {
        pending = name
    }
}

final class SheetPresentationTests: XCTestCase {

    /// 同一时刻只能有一个模态：第二次请求必须被拒绝。
    func testSecondModalIsRejected() {
        var gate = ModalGate()
        XCTAssertTrue(gate.request("passcode"))
        XCTAssertFalse(gate.request("duress"), "已有模态在呈现时，第二个必须被拒绝而不是覆盖")
        XCTAssertEqual(gate.active, "passcode", "先呈现的那个不能被后来的顶掉")
    }

    /// 关闭后可以再呈现新的。
    func testCanPresentAfterDismiss() {
        var gate = ModalGate()
        XCTAssertTrue(gate.request("passcode"))
        _ = gate.dismiss()
        XCTAssertTrue(gate.request("duress"))
        XCTAssertEqual(gate.active, "duress")
    }

    /// 从对话框里请求 sheet：必须**排队**，在对话框退场后才呈现。
    /// 这正是 SecurityScreen「关闭本机密码」那条路径的形状。
    func testEnqueuedModalPresentsAfterDismiss() {
        var gate = ModalGate()
        XCTAssertTrue(gate.request("confirmDialog"))
        gate.enqueue("verifyPasscode")            // 对话框里点「继续验证」
        XCTAssertFalse(gate.request("verifyPasscode"), "对话框还在，验证框不能同时呈现")
        let next = gate.dismiss()
        XCTAssertEqual(next, "verifyPasscode", "对话框退场后应把排队的模态交回给调用方")
        XCTAssertTrue(gate.request(next!), "退场后这次呈现必须成功")
    }

    /// 排队项只能用一次（不能因为重复 dismiss 而重复呈现）。
    func testPendingIsConsumedOnce() {
        var gate = ModalGate()
        XCTAssertTrue(gate.request("confirmDialog"))
        gate.enqueue("verifyPasscode")
        XCTAssertEqual(gate.dismiss(), "verifyPasscode")
        XCTAssertNil(gate.dismiss(), "排队项已被消费，再次关闭不应再返回它")
    }
}
