import SwiftUI

// ============================================================
// 界面变体开关 (2026-10-16)
// ------------------------------------------------------------
// 三套界面并存，App 内可切换：
//   · legacy —— 现有四 Tab（设备/凭证/记录/设置）。**默认值**，落地期间不动任何人的界面。
//   · core   —— 「一枚锁核」：零 Tab、一枚可变形玻璃核 + 三个环绕光点。方案见 design-system/aurora-lock/CORE.md
//   · gauge  —— 「近场仪表」：熄屏为默认态的一块仪表盘面。
//
// 为什么默认是 legacy 而不是新两套：新面还没在真机上跑过一次（本机无 Xcode/模拟器，
// 唯一验证途径是 CI 编译）。默认切过去 = 把没验过的东西推给日常使用，这是本仓最反对的那类"先显示后补数据"。
//
// ⚠ 切换必须走 applyAppearance 那条"重建全树"通道，不能只改内存值。
//   理由与 themeSeed 完全同一条病灶（见 LockKeeperApp.swift:72 那段注释）：
//   不重建树就会"按了没反应、重进 App 才变"。
//   同时 kf_ui_variant 必须进 reloadAppearance() 与 resetAppearance() 两张清单 ——
//   少一处就是"从备份恢复后界面还是旧变体"和"恢复默认外观漏掉这一档"。
// ============================================================

enum UIVariant: String, CaseIterable, Identifiable {
    case legacy
    case core
    case gauge

    var id: String { rawValue }

    /// 存储键。命名沿用本仓 `kf_` 前缀族。
    static let storeKey = "kf_ui_variant"

    /// 读当前变体。非法值（手改存储、旧版本残留）一律回落到 legacy，不猜。
    static var current: UIVariant {
        let raw = DB.store.getString(storeKey)
        return UIVariant(rawValue: raw) ?? .legacy
    }

    static func write(_ v: UIVariant) {
        DB.store.set(storeKey, v.rawValue)
    }

    /// ⚠ 这一档**故意不进** `resetAppearance()` 的那张清单，虽然本仓的口径是
    /// "键在役就必须进重置清单"。区别在于：那张清单的确认弹窗写的是"将**外观**重置为默认值"，
    /// 里面全是配色/密度/圆角/行高/动效这类档位；而变体换的是**整个导航模型**。
    /// 用户选了「一枚锁核」之后点"恢复默认外观"，被顺带弹回四标签 = 弹窗没承诺过的事。
    /// 要改回 legacy 请在切换器里明说地选，不藏在外观重置里。
    var canResetWithAppearance: Bool { false }

    // ---------- 设置页文案 ----------
    var title: String {
        switch self {
        case .legacy: return "现行四标签"
        case .core:   return "一枚锁核"
        case .gauge:  return "近场仪表"
        }
    }

    /// 一句话说明这套把什么当主角 —— 切换器里必须写清差别，否则三行字看着像三个皮肤名。
    var note: String {
        switch self {
        case .legacy: return "现有界面：设备 / 凭证 / 记录 / 设置 四个标签页"
        case .core:   return "零标签：一枚玻璃锁核 + 三个光点，拖向光点即进入该域"
        case .gauge:  return "一块仪表盘：不在场时熄屏，走近连上后逐段点亮"
        }
    }

    /// 尚未完成的部分。**切换器里必须照实写** —— 一套没做完的界面如果不自报边界，
    /// 用户切过去会以为功能消失了（本仓"宁撤虚假显示"那条纪律的反面教材）。
    var unfinished: String {
        switch self {
        case .legacy: return ""
        case .core:   return "首屏形态已完成，三个域的浮层与访客门禁仍在旧通道上"
        case .gauge:  return "首屏盘面已完成，域内列表仍复用现行页面"
        }
    }

    var isExperimental: Bool { self != .legacy }
}

// ============================================================
// 变体的环境值 (2026-10-16，行内排版接管批)
// ------------------------------------------------------------
// 为什么需要它、而不是像 `variantPlate` 那样读 `VK.current`：
//   `VK.current` 是从存储现读的（`UIVariant.current` → `DB.store.getString`），一次调用一次读取。
//   容器语法件只有 100 多处，那个代价看不出来；而 `.font(...)` 的调用点有 **1700+ 处**，
//   列表滚动时每帧要过几百次 —— 那就从"零行为改动"变成了"每帧几百次存储读取"。
//   环境注入一次、叶子读一次，是唯一既能覆盖全仓又不动每帧开销的形状。
//
// ⚠ 注入点在 `RootView.rootCore`（`LockKeeperApp.swift`）**一处**，两棵树共用：
//   legacy 树也显式注入自己的值，而不是留空 —— 留空就等于把"这套界面此刻是哪种"交给默认值猜。

private struct UIVariantKey: EnvironmentKey {
    /// ⚠ 默认必须是**字面量** `.legacy`，不能写 `UIVariant.current`：
    /// 后者会在"切到 core 之后又切回 legacy"的场景里被求值成 stale 值，
    /// 于是 legacy 的每一页都染上新变体的字重 —— 而这条没有任何闸门看得见。
    /// **未注入 = legacy = 逐字原样**，是这台机器上唯一安全的默认。
    static let defaultValue: UIVariant = .legacy
}

extension EnvironmentValues {
    var uiVariant: UIVariant {
        get { self[UIVariantKey.self] }
        set { self[UIVariantKey.self] = newValue }
    }
}
