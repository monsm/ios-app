import Foundation

// ============================================================
// Route —— 目的地身份，取代"裸整数 Tab 号" (2026-10-16)
// ------------------------------------------------------------
// 为什么现在必须做：App 里并存两套完整界面之后，Tab 号这个概念**只在 legacy 里存在**。
// 本文件落地时全仓还有 40 处 `requestTab(<字面量>)` 与 74 处 `tabSelection`；前者已于
// 2026-10-16 全部改成 `requestRoute`（uicoverage 检查六守着不许回潮），其中三处曾被
// tools/sheetcover.js 抓到实证缺陷：`RecordsView` 被新变体用 sheet 端出来之后，
// 它内部的 `requestTab(1)` / `tabSelection = 0` 会去切一个不存在的 Tab，而 sheet 还盖在上面。
//
// 更危险的一条：访客门禁 `guestBlockedTabs: Set<Int> = [1, 3]` 是
// **同一个量的双实现**之一（另一处是主 TabView 里按序号摘除层级）。新容器没有序号，
// 两处同时失去指称对象 ⇒ **访客模式静默失去对"应用锁/访客/伪装/销毁"整块的覆盖**，
// 不崩、不报错、走查看不出来。
//
// 所以本文件不只加一个枚举，而是把**三处同源的东西收成一处**：
//   · 顺序      → Route.byHost 是唯一声明，deepLinkHosts 由它派生；
//   · 访客受限集 → Route.guestBlocked 是唯一声明，guestBlockedTabs 由它派生；
//   · 换页入口  → requestRoute 是唯一漏斗，requestTab(Int) 退化成兼容适配器。
// 以后再加一个变体或改一个顺序，只有一个地方要改。
// ============================================================

enum Route: String, CaseIterable, Identifiable {
    case device
    case credentials
    case records
    case settings

    var id: String { rawValue }

    /// **唯一**的顺序声明。深链 host 表、legacy 的 Tab 号都从这里推。
    static let byHost: [Route] = [.device, .credentials, .records, .settings]

    static func from(tab: Int) -> Route? {
        guard tab >= 0, tab < byHost.count else { return nil }
        return byHost[tab]
    }

    /// 仅 legacy 有意义：新变体里没有"第几个 Tab"这个东西。
    /// 越界返回 -1 而不是崩溃 —— 调用方 (markNav) 本来就靠"拿不到就不记账"来兜住脏值。
    var tabIndex: Int { Route.byHost.firstIndex(of: self) ?? -1 }

    /// 377 访客模式下受限的目的地。
    /// 原句口径：「只看设备 Tab / 进凭证要密码 / 退出需密码 / 落点应用锁」，
    /// 只拦 凭证/设置 两页；记录页不含凭证本体，照常可看。
    var guestBlocked: Bool { self == .credentials || self == .settings }

    /// 设置页/深链/语音里给用户看的那一行字。
    var title: String {
        switch self {
        case .device: return "设备"
        case .credentials: return "凭证"
        case .records: return "记录"
        case .settings: return "设置"
        }
    }


    /// kf:// 的 host 白名单。**由 byHost 派生**，不再手写一张 `["device":0, ...]`。
    static var deepLinkHosts: [String: Int] {
        var d = [String: Int]()
        for r in Route.allCases { d[r.rawValue] = r.tabIndex }
        return d
    }

    /// 访客受限 Tab 号集合。**由 guestBlocked 派生**，不再手写 `[1, 3]`。
    /// 留着它只为兼容仍按序号摘除层级的那两处视图代码；判据本身在 guestBlocked 里。
    static var guestBlockedTabs: Set<Int> {
        Set(Route.allCases.filter { $0.guestBlocked }.map { $0.tabIndex })
    }
}
