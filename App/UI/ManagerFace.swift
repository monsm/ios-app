import SwiftUI

// ═══════════════════════════════════════════════════════════════════════
// MARK: - B 管家台（底部液态玻璃分组）
// ═══════════════════════════════════════════════════════════════════════
//
// 21 个设置类页面塞进一个面会变成"入口列表"，又回到普通 App 的样子。
// 所以分 5 组，用**浮动液态玻璃胶囊**切换。
//
// ═══ 为什么走 xGlass 而不是自己写 glassEffect ═══
//
// 玻璃的材质与降级**只有一处**实现 (App/Core/Components.swift 的 XGlassSurface):
//   正常      → .ultraThinMaterial + 8% 白填充 + 0.5pt 12% 白描边 + 顶部高光
//   降低透明度 → 降为实底 XPalette.surface + hairlineStrong 描边
//   高对比    → 同上
//
// 自己写 glassEffect 会绕开这三条降级，等于给无障碍挖坑。
// (2026-10-22: axGlass / axGlassCircle / axGlassCapsule 三个旧入口已改为
//  薄壳转调 xGlass —— 之前它们各自有一份降级判据, 两份判据迟早分家。)
//
// ═══ 与三棱柱的关系 ═══
//
//   三棱柱（顶层，3 面）
//     └─ B 面 ─→ 底部液态玻璃 Tab（5 组）─→ 页面
//
// 底部 Tab 是**域内导航**，不参与三棱柱旋转。
struct ManagerFace: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    /// 当前顶级 Tab。**用 AppState.tabSelection 而不是 @State** ——
    /// 门厅里的「管理」入口（以及深链、快捷指令、摇一摇）都要能切 Tab，
    /// 而它们拿不到本视图的 @State。放进 AppState 才有唯一的可写点。
    // 2026-10-24 修复底部导航瘫痪（用户真机反馈）：
    //
    // 症状：①点 Tab 无反应 ②子项点了没反应 ③切到别的 Tab 反而显示刚才点的子项。
    // 根因：**5 个 Tab 只有钥匙组绑了 path**，其余组的行点击 path.append(route)
    // 都 push 到钥匙组的栈 —— 在设备组点「固件升级」，push 发生在看不见的钥匙栈里；
    // 切回钥匙 Tab 才看到固件页（症状③的原话）。
    //
    // 修法：每个管理组一个独立栈。字典在组维度的 push 互不串台，
    // Tab 切换自然恢复（不再被"看似没反应"的栈污染）。

    // 2026-10-23：删掉 `init(initialGroup:)`。
    // 它是「从门厅带一个分组进来」的入口，而门厅现在是第一个 Tab ——
    // 不是「从外面弹进来一个面板」，所以没有「带一个分组进来」这回事了。
    // 切组走 `app.tabSelection`（见 openGroup）。

            var body: some View {
        // ═══════════════════════════════════════════════════════════
        // 2026-10-24 第六轮：**改回原生 TabView**（按用户指令「控件优先用 iOS 27 原生」）
        //
        // 演进记录（每次都是口径变化，不是反复横跳）：
        //   ① .tabItem + .tag(Int)  —— 真机出现"点设备跳钥匙"的吸附
        //   ② Tab(value: Int)       —— 同样吸附
        //   ③ 自建 VStack 底部栏    —— 吸附消失，但**不是原生控件**
        //   ④ **本轮：Tab(value: ManagerTab) 枚举值**
        //
        // ④ 与 ①② 的关键差别：**value 用 enum 而不是 Int**。
        // Apple 的 SwiftUI 指南明确写着：
        //   "When using TabView(selection:), use a binding to a property that stores
        //    an enum rather than an integer or string. For example,
        //    Tab("Home", systemImage: "house", value: .home) is better than value: 0."
        // ①② 都用 Int，selection 是 Binding<Int> —— 序号与 tag 的一致性只能靠人肉保证，
        // 一旦有任何一个 tag 漏写/写重，就会出现"点到相邻项"这种吸附现象。
        // 用 enum 之后，编译器保证 tag 唯一且 selection 类型匹配。
        //
        // 同时满足两条要求：
        //   · **审美**：原生 TabView 自带 iOS 26/27 Liquid Glass 浮动胶囊 ——
        //     正好是参考图 2 实测的形态（92.5% 宽、半透明、悬浮）。
        //     第 35 轮我手绘浮岛去模仿它，现在用原生就能得到同一个效果且更正确。
        //   · **原生优先**：不再自绘栏体、命中区、选中态。
        TabView(selection: tabIndex) {
            Tab(value: ManagerTab.home) {
                HomeConsole()
            } label: {
                Label(ManagerTab.home.label, systemImage: ManagerTab.home.icon)
            }

            Tab(value: ManagerTab.keys) {
                NavigationStack {
                    groupScreen(for: .ledger)
                        .navigationDestination(for: ManagerRoute.self) { r in
                            routeDestination(r).trackScreen("管理·\(r)")
                        }
                }
            } label: {
                Label(ManagerTab.keys.label, systemImage: ManagerTab.keys.icon)
            }

            Tab(value: ManagerTab.devices) {
                NavigationStack {
                    groupScreen(for: .devices)
                        .navigationDestination(for: ManagerRoute.self) { r in
                            routeDestination(r).trackScreen("管理·\(r)")
                        }
                }
            } label: {
                Label(ManagerTab.devices.label, systemImage: ManagerTab.devices.icon)
            }

            Tab(value: ManagerTab.members) {
                NavigationStack {
                    groupScreen(for: .members)
                        .navigationDestination(for: ManagerRoute.self) { r in
                            routeDestination(r).trackScreen("管理·\(r)")
                        }
                }
            } label: {
                Label(ManagerTab.members.label, systemImage: ManagerTab.members.icon)
            }

            Tab(value: ManagerTab.system) {
                NavigationStack {
                    groupScreen(for: .system)
                        .navigationDestination(for: ManagerRoute.self) { r in
                            routeDestination(r).trackScreen("管理·\(r)")
                        }
                }
            } label: {
                Label(ManagerTab.system.label, systemImage: ManagerTab.system.icon)
            }
        }
    }

    /// 当前选中页 —— **Binding<ManagerTab>**（enum 而非 Int）
    ///
    /// skill 的明确要求："use a binding to a property that stores an enum
    /// rather than an integer or string"。AppState 仍存 Int（深链/摇一摇等
    /// 存量接口都按序号），这里做**唯一**的类型换算点。
    private var tabIndex: Binding<ManagerTab> {
        Binding(
            get: { ManagerTab.from(index: app.tabSelection) ?? .home },
            set: { newTab in
                // ═══ 2026-10-24 修「访客通道开启后 Tab 点不中」的核心一处 ═══
                //
                // 原生 TabView 的点击**不经过 requestRoute** —— 它直接写这个 Binding。
                // 而访客闸只装在 requestRoute 里（那是编程式跳转的漏斗），
                // 于是"从底部导航点进去"这条最常用的路径**完全绕过了访客闸**。
                //
                // 反过来说，之前观察到"某些 Tab 点不中"也不是闸挡的 ——
                // 是这个 Binding 的 set 写入后，revokeSessionGrants 又把 tabSelection
                // 拽回 homeTab，两边打架，界面表现成"点了没反应"。
                //
                // 现在的口径：点进去先判访客闸。受限 → 记落点并弹口令复核（不切）；
                // 通过后由 commitUnlock(reauth:) 切过去。不受限 → 直接切。
                let target = newTab.index
                if app.guestAreaLocked, AppState.guestBlockedTabs.contains(target) {
                    app.guestGateTarget = target
                    app.showGuestGate = true
                    app.needGuestGatePrompt = true
                    return
                }
                app.tabSelection = target
            })
    }

    /// 一个管理组的页面。原生 TabView 下每组有自己的 NavigationStack，
    /// 所以这里只出内容，不再管栏体与选中态。
    @ViewBuilder
    /// 一个管理组的落地页 —— **按 HTML 02/03/04/05 的骨架**（2026-10-24 逐页对齐）
    ///
    /// HTML 的四个组页是同一个骨架：
    ///   ① 顶部三枚胶囊（该组的关键读数）
    ///   ② 页内大标题（30/Bold）+ 副标题（该组的一句话摘要，含真实数字）
    ///   ③ 一张主视觉卡（读数 + 环）
    ///   ④ 分组的行入口卡
    ///
    /// App 此前是 `.inline`（标题只在导航栏）+ **纯行入口**——
    /// 没有胶囊、没有副标题、没有主视觉卡。四个组页全都是"一列链接"，
    /// 与 HTML 的"仪表盘 + 入口"完全是两种界面。
    ///
    /// 这是**共性问题**（4 页同构），所以统一改：`.inline` → `.large` + 加胶囊行。
    private func groupScreen(for g: ManagerGroup) -> some View {
        XScreen(g.title, subtitle: g.summary, style: .large) {
            groupChips(g)
            rows(rowsFor(g))
        }
    }

    /// 组页顶部的三枚胶囊（HTML 02/03/04/05 的首块）
    ///
    /// 每组的三枚读数不同，但形态相同：`XStatChip` + 迷你环。
    @ViewBuilder
    private func groupChips(_ g: ManagerGroup) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: XSpace.s) {
                switch g {
                case .ledger:
                    XStatChip(label: "全部", value: String(groupLedgerTotal),
                              ringFraction: 1, tint: XPalette.accent, fillsWidth: false)
                    XStatChip(label: "密码", value: String(groupPwTotal),
                              ringFraction: groupLedgerTotal > 0 ? Double(groupPwTotal) / Double(groupLedgerTotal) : 0,
                              tint: XPalette.kindTemp, fillsWidth: false)
                    XStatChip(label: "指纹", value: String(groupFpTotal),
                              ringFraction: groupLedgerTotal > 0 ? Double(groupFpTotal) / Double(groupLedgerTotal) : 0,
                              tint: XPalette.kindFp, fillsWidth: false)
                case .devices:
                    XStatChip(label: "门锁", value: "\(DB.keychains().count) 把",
                              ringFraction: min(1, Double(DB.keychains().count) / 3),
                              tint: XPalette.accent, fillsWidth: false)
                    XStatChip(label: "电量", value: groupBatteryText,
                              ringFraction: 0.5, tint: XPalette.ok, fillsWidth: false)
                    XStatChip(label: "钥匙串", value: "\(DB.dongles().count) 台",
                              ringFraction: 0, tint: XPalette.textTertiary, fillsWidth: false)
                case .members:
                    XStatChip(label: "成员", value: String(DB.members().count),
                              ringFraction: 1, tint: XPalette.accent, fillsWidth: false)
                    XStatChip(label: "活跃", value: String(DB.members().count),
                              ringFraction: 1, tint: XPalette.ok, fillsWidth: false)
                    XStatChip(label: "归档", value: String(MemberHub.archivedIDs().count),
                              ringFraction: 0, tint: XPalette.textTertiary, fillsWidth: false)
                case .system:
                    XStatChip(label: "应用锁", value: DB.hasPasscode() ? "已开启" : "未开启",
                              ringFraction: DB.hasPasscode() ? 1 : 0,
                              tint: DB.hasPasscode() ? XPalette.ok : XPalette.warn, fillsWidth: false)
                    XStatChip(label: "备份", value: groupBackupText,
                              ringFraction: 0, tint: XPalette.warn, fillsWidth: false)
                    XStatChip(label: "审计", value: "\(groupAuditCount) 条",
                              ringFraction: 1, tint: XPalette.accent, fillsWidth: false)
                }
            }
            .padding(.horizontal, XSpace.gutter)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -XSpace.gutter)
    }

    // ── 组页胶囊的读数来源 ──
    private var groupLedgerTotal: Int {
        DB.keychains().reduce(0) { $0 + DB.listPwds($1.mac).count + DB.listFps($1.mac).count }
    }
    private var groupPwTotal: Int { DB.keychains().reduce(0) { $0 + DB.listPwds($1.mac).count } }
    private var groupFpTotal: Int { DB.keychains().reduce(0) { $0 + DB.listFps($1.mac).count } }
    private var groupBatteryText: String {
        // DB 没有 status(_:)；电量唯一来源是 readStatus(mac)?.powerLevel
        guard let p = DB.readStatus(app.currentMac)?.powerLevel, p >= 0 else { return "—" }
        return "\(p)%"
    }
    private var groupBackupText: String {
        let ms = DB.store.getInt("kf_bk_last_export", 0)
        guard ms > 0 else { return "从未" }
        let days = Int((Date().timeIntervalSince1970 * 1000 - Double(ms)) / 86_400_000)
        return days <= 0 ? "今天" : "\(days) 天前"
    }
    private var groupAuditCount: Int { AuditLog().load().count }


    // ── 当前组的内容 ──
    /// 一个组有哪些入口。原来是挂在 `group` 状态上的计算属性，
    /// 现在 TabView 下每组独立，所以要能按参数取。
    private func rowsFor(_ g: ManagerGroup) -> [(ManagerRoute, String, String, String)] {
        switch g {
        case .ledger:
            return [
                (.keys, "钥匙管理", "密码 / 指纹 / 临时码", "key.horizontal"),
                (.fingerprints, "指纹", "录入与管理", "touchid"),
                (.tempCodes, "临时密码", "一次性 / 周期", "clock.badge.checkmark"),
            ]
        case .devices:
            return [
                (.locks, "我的门锁", "设备列表与切换", "iphone.gen3"),
                (.firmware, "固件升级", "版本与升级向导", "arrow.down.circle"),
                (.gateway, "网关配网", "WiFi 与远程", "wifi.router"),
                (.dongles, "钥匙串", "随身开门", "key.viewfinder"),
                (.syncTime, "校准时间", "锁内时钟", "clock.arrow.circlepath"),
            ]
        case .members:
            return [
                (.members, "成员", "家人与角色 · 合并从这里发起", "person.2"),
                (.memberWizard, "添加成员", "三步向导", "person.badge.plus"),
                (.archivedMembers, "已归档", "查看归档成员", "archivebox"),
            ]
        case .system:
            // 5 组并成 4 组（规范 §7.10「项数 3–4」，不得出现 More）。
            // 合并的是「安全」+「数据与外观」—— 它们的共同点是**都在管这台手机**，
            // 而不是管那把锁。分两栏时用户要在两个 Tab 之间反复横跳才能配完一次备份。
            return [
                (.securityCenter, "隐私看板", "应用锁 / 授权总览", "lock.shield"),
                (.securityAudit, "安全审计", "变更记录", "list.bullet.rectangle"),
                (.securityDestroy, "销毁数据", "不可逆清除", "trash"),
                (.safemode, "安全模式", "变严方向", "shield.lefthalf.filled"),
                (.backup, "备份恢复", "导出 / 导入 / 校验", "externaldrive.badge.timemachine"),
                (.export, "导出中心", "PDF / CSV / 分享", "square.and.arrow.up"),
                (.appearance, "外观工作室", "强调色 / 密度 / 周起始", "paintpalette"),
                (.me, "本机设置", "应用锁 / 备份 / 关于", "person.crop.circle"),
                // ManagerRoute.diagnostics 之前**没有任何入口行**（死用例）：
                // routeDestination 里有它的落点，但 rowsFor 三个组都没列它，
                // 于是诊断页只能从「本机设置」里绕进去，路由表里那条永远走不到。
                (.diagnostics, "诊断与自检", "数据健康 / 稳定性 / 蓝牙", "stethoscope"),
            ]
        }
    }

    /// 一组入口。**一张卡，多行，行间细线**（规范 §7.6 的多段结构）。
    ///
    /// 2026-10-23 按参考图改。改前是**一行一张卡** —— 五个入口就是五张独立的卡，
    /// 卡与卡之间 12pt 空隙。图 3 里没有这种形态：它是一张卡装多段，段间一条细线。
    ///
    /// 差别不只是「看起来紧凑」：
    ///   · 一行一张卡 → 读成五个彼此无关的入口
    ///   · 一卡多行     → 读成「同一类东西的五个选项」
    ///
    /// 后者才是这几个管理组的真实关系。
    private func rows(_ items: [(ManagerRoute, String, String, String)]) -> some View {
        XPanel(kind: .group, padding: 0) {
            VStack(spacing: 0) {
                // id 用序号：这些元组没有天然唯一键，而 items 是常量数组顺序稳定。
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    let (route, title, subtitle, icon) = item
                    if idx > 0 {
                        // 行间细线：内缩到文字左边缘（对齐图标之后），
                        // 与系统列表同口径 —— 全宽线会把一列行切成一格一格。
                        XHairline(inset: XSpace.card + 28 + XSpace.m)
                    }
                    // 2026-10-24 重做：行 = NavigationLink(value:)——push 目标由
                    // 本 Tab 自己的 NavigationStack 解析，结构上不可能串台。
                    NavigationLink(value: route) {
                        XRow(systemImage: icon, title: title,
                             subtitle: subtitle, showsChevron: true)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, XSpace.card)
                }
            }
            .padding(.vertical, XSpace.xs)
        }
    }




    // ── 路由落地 ──
    private func consumePendingFocus() {
        // 重做后无共享 path：深链焦点退化为「切到系统 Tab」，
        // 目标入口行就在系统组首屏（备份恢复/诊断与自检都是常驻行）。
        guard app.pendingSettingsFocus != nil else { return }
        app.pendingSettingsFocus = nil
        app.tabSelection = ManagerTab.system.index
    }

    @ViewBuilder
    private func routeDestination(_ r: ManagerRoute) -> some View {
        switch r {
        case .keys:           KeysPage()
        case .fingerprints:   AddFingerPage()
        case .tempCodes:      TempCodeStudio()
        case .locks:          LocksPage()
        case .firmware:       FirmwarePage()
        case .gateway:        GatewayPage()
        case .dongles:        DonglesPage()
        case .syncTime:       SyncTimeView()
        case .members:        MembersPage()
        case .memberWizard:   MemberWizardView()
        case .archivedMembers: MemberArchivedView()
        // 2026-10-24: PrivacyDashboard 已删（用户裁定「不需要防窥功能」）。
        // 系统组首项改为「本机保护」—— 安全域的入口收在这一个页面上。
        // 2026-10-24: SecurityPage 已删（用户裁定）。系统组首项改为「应用锁」——
        // 安全域剩下的可配置项就是它；审计/销毁/回收站仍是本组独立入口。
        case .securityCenter: AppLockSetupView()
        case .securityAudit:  SecurityAuditView()
        case .securityDestroy: SecurityDestroyView()
        case .safemode:       SafemodeIntroView()
        case .backup:         BackupPage()
        case .export:         ExportCenterView(mac: app.currentMac)
                                  .environmentObject(app)
        // ⚠ 这里原来指向 StudioPage —— 而 StudioPage 是「钥匙工坊」（密码/临时/指纹/OTP），
            //   与「外观工作室 · 主题 / 强调色 / 密度」毫无关系。
            //   菜单名与实际页面不符，同时外观相关的 4 个 setter 全都没有入口。
            case .appearance:     AppearancePage().trackScreen("外观工作室")
            case .diagnostics:    DiagnosticsPage().trackScreen("诊断与自检")
        case .me:             MePage().trackScreen("本机设置")
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - B 域路由
// ═══════════════════════════════════════════════════════════════════════
//
// M4 阶段先用一个扁平枚举把 5 组的目标页接起来。
// M5 逐页重做时，这些落地页会被独立重写。
enum ManagerRoute: String, Hashable, Identifiable {
    case keys, fingerprints, tempCodes
    case locks, firmware, gateway, dongles, syncTime
    case members, memberWizard, archivedMembers
    case securityCenter, securityAudit, securityDestroy, safemode
    case backup, export, appearance, me
    case diagnostics

    var id: String { rawValue }

    /// 页面标题 —— 与 Tab 标签同字。单列一个属性是为了让调用点读起来是
    /// 「一个组的标题」而不是「一个枚举的 rawValue」。 */
    var title: String { rawValue }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - B 域 5 组
// ═══════════════════════════════════════════════════════════════════════
//
// 上一版这个定义在 DoorRoot.swift 里，M4 把它移到 ManagerFace 旁边 ——
// 谁用它就定义在谁那里。移的时候连带把 DoorRoot 里的副本删了，
// 结果两边都没有，swiftlint 报"仅出现 2 次且未声明"才发现。
/// 底部导航的五个页签 —— 2026-10-24 重做。
///
/// 用枚举而不是 Int 做 selection 的类型：
///   · tag 与 selection 类型一致由编译器保证（Int tag 配错不报错）
///   · openGroup/rememberTab 等存量 Int 接口在**唯一**的换算点转换
enum ManagerTab: Hashable, CaseIterable {
    case home, keys, devices, members, system

    var label: String {
        switch self {
        case .home: return "门厅"
        case .keys: return ManagerGroup.ledger.rawValue
        case .devices: return ManagerGroup.devices.rawValue
        case .members: return ManagerGroup.members.rawValue
        case .system: return ManagerGroup.system.rawValue
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .keys: return ManagerGroup.ledger.systemImage
        case .devices: return ManagerGroup.devices.systemImage
        case .members: return ManagerGroup.members.systemImage
        case .system: return ManagerGroup.system.systemImage
        }
    }

    /// 与 AppState.tabSelection(Int) 的唯一换算点
    var index: Int {
        switch self {
        case .home: return 0
        case .keys: return 1
        case .devices: return 2
        case .members: return 3
        case .system: return 4
        }
    }

    /// 选中态图标（实心版）—— 选中/未选中用两套字形是 iOS 的既有语言，
    /// 这里给门厅换成实心房子，其余沿用组图标（它们本身就是唯一的）。
    var selectedIcon: String {
        switch self {
        case .home: return "house.fill"
        default: return icon
        }
    }

    static func from(index: Int) -> ManagerTab? {
        allCases.first { $0.index == index }
    }
}

enum ManagerGroup: String, CaseIterable, Identifiable {
    case ledger = "钥匙"
    case devices = "设备"
    case members = "成员"
    case system = "系统"

    var id: String { rawValue }

    /// 页面标题 —— 与 Tab 标签同字。单列一个属性是为了让调用点读起来是
    /// 「一个组的标题」而不是「一个枚举的 rawValue」。
    var title: String { rawValue }

    var systemImage: String {
        switch self {
        case .ledger: return "key.horizontal"
        case .devices: return "iphone.gen3"
        case .members: return "person.2"
        case .system: return "gearshape"
        }
    }

    /// 377 访客模式下这个组受不受限。
    ///
    /// **单一声明处** —— 与 `Route.guestBlocked` 是同一条语义的两个落点:
    /// 那边的原话是「只看设备 Tab / 进凭证要密码 / 退出需密码 / 落点应用锁」,
    /// 即"谁在门里"与"怎么管这台手机"两块要拦。映射到管理组就是:
    ///   钥匙   —— 凭证本体, 拦
    ///   成员   —— 谁能开门, 拦
    ///   安全   —— 应用锁/销毁/审计, 拦
    ///   数据与外观 —— 备份/导出/外观, 拦
    ///   设备   —— 只看设备照常可看, 不拦 (与 Route.device 不拦同一条)
    ///
    /// 为什么不复用 `Route.guestBlocked`: 那一套是**四个 Tab 序号**的口径,
    /// 而单控制台里没有 Tab 序号 —— 硬映射回去会得到"一个 Route 对应好几个组",
    /// 判据就不再是判据了。所以在这里按同一句原话重新落一次, 数字由 Route 那边保。
    var guestBlocked: Bool {
        switch self {
        case .devices: return false
        case .ledger, .members, .system: return true
        }
    }

    /// 每组摘要 —— 与旧 DoorDomain.summary 同口径: 必须显示真实数字
    var summary: String {
        switch self {
        case .ledger:
            let n = DB.keychains().reduce(0) { acc, kc in
                acc + DB.listPwds(kc.mac).count + DB.listFps(kc.mac).count
            }
            return n > 0 ? "\(n) 项钥匙" : "还没有钥匙"
        case .devices:
            let n = DB.keychains().count
            return n > 0 ? "\(n) 把锁" : "还没有门锁"
        case .members:
            let n = DB.members().count
            return n > 0 ? "\(n) 位成员" : "还没有成员"
        case .system:
            let lock = DB.store.getBool("kf_applock") ? "应用锁已开" : "应用锁未开"
            return lock + " · 备份 · 外观"
        }
    }
}
