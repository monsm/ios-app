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
    @State private var group: ManagerGroup = .ledger

    /// 从门厅带一个分组进来（门厅的「管理」按钮点哪个组就开哪个组）
    init(initialGroup: ManagerGroup = .ledger) {
        _group = State(initialValue: initialGroup)
    }
    @State private var path: [ManagerRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                XPalette.canvas.ignoresSafeArea()

                // ── 内容区 (规范 5.3 屏幕骨架) ──
                //
                // 三档间距, 三档语义:
                //   pageTop(40)  → 页面顶部呼吸区
                //   section(28)  → 组标题与内容之间 (两个不同的簇)
                //   colGap(12)   → 行与行之间 (卡片纵向堆叠… 这里行是卡内的, 见 rows())
                //
                // 96 的底部留白不是为了"好看": 浮动胶囊高 56 + 距底 8 + 32 的呼吸 = 96。
                // 少给 8pt 就会出现"最后一行被胶囊压住", 而那恰好是最下面那行。
                ScrollView {
                    VStack(spacing: XSpace.section) {
                        groupHeader
                        groupContent
                    }
                    .padding(.horizontal, XSpace.gutter)
                    .padding(.top, XSpace.pageTop)
                    .padding(.bottom, 112)
                }

                // ── 浮动液态玻璃分组条 ──
                groupBar
            }
            .navigationTitle("管家台")
            .navigationBarTitleDisplayMode(.inline)
            // 作为 sheet 弹出时，必须有一个看得见的出口。
            // 只靠下滑关闭对不熟悉手势的人等于没有出口。
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .fontWeight(.medium)
                }
            }
            // ═══ 消费"带落点名过来"的跳转 ═══
        //
        // pendingSettingsFocus 是别人在跳转前写下的"到了之后开哪一屏"：
        //   · 通知「已生成本机还原点」→ backup
        //   · 销毁前备份闸的"先去备份" → backup
        // 这三处写入的注释都写着"由设置页收到即开并清空"，
        // 但三域合并成单一面板之后消费端丢了 —— 写了没人读，等于跳了个寂寞。
        .onAppear { consumePendingFocus() }
        .navigationDestination(for: ManagerRoute.self) { r in
                // 面包屑精确到分组路由：崩在这 20 条里的哪一条，重启后能直接看到名字。
                routeDestination(r).trackScreen("管理·\(r)")
            }
        }
    }

    // ── 组标题 (规范 7.1 LargeTitleHeader) ──
    //
    // 30 Bold / 字距 -0.4。旧值 .title2(22) semibold —— 那是卡片主标题的档,
    // 拿来当页面标题会让本页与它自己的卡片长得一样平。
    //
    // 对齐线: 大标题要落在 XSpace.align (29) 上? 本页容器已经给了 gutter(14),
    // 所以这里再加 (align - gutter) = 15 就正好压在那条线上。
    private var groupHeader: some View {
        VStack(alignment: .leading, spacing: XSpace.s) {
            Text(group.rawValue)
                .xFont(.largeTitle, weight: .bold)
                .tracking(-0.4)
                .foregroundStyle(XPalette.text)
            Text(group.summary)
                .xFont(.body)
                .foregroundStyle(XPalette.textSub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, XSpace.align - XSpace.gutter)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.rawValue)，\(group.summary)")
    }

    // ── 当前组的内容 ──
    @ViewBuilder
    private var groupContent: some View {
        switch group {
        case .ledger:
            rows([
                (.keys, "钥匙管理", "密码 / 指纹 / 临时码", "key.horizontal"),
                (.fingerprints, "指纹", "录入与管理", "touchid"),
                (.tempCodes, "临时密码", "一次性 / 周期", "clock.badge.checkmark"),
            ])
        case .devices:
            rows([
                (.locks, "我的门锁", "设备列表与切换", "iphone.gen3"),
                (.firmware, "固件升级", "版本与升级向导", "arrow.down.circle"),
                (.gateway, "网关配网", "WiFi 与远程", "wifi.router"),
                (.dongles, "钥匙串", "随身开门", "key.viewfinder"),
                (.syncTime, "校准时间", "锁内时钟", "clock.arrow.circlepath"),
            ])
        case .members:
            rows([
                (.members, "成员", "家人与角色", "person.2"),
                (.memberWizard, "添加成员", "三步向导", "person.badge.plus"),
                // ⚠ 这一行的落点是 **MembersPage**，不是 MergeMembersView ——
                // 合并本身要从「一条具体成员」发起（MergeMembersView 需要 `primary: Member`），
                // 路由层拿不到那个 Member（ManagerFace.swift 的 routeDestination 里已注明）。
                //
                // 改之前这里写的是「合并成员 / 先选一位作为主档案」，而点进去看到的是
                // 一个没有任何"合并"字样的成员列表 —— 与本仓自己记录过的前科
                // （「外观工作室」曾指向「钥匙工坊」）是同一类：**菜单名与落点不符**。
                // 现在文案如实描述落点与下一步，不再许诺一个这里进不去的页面。
                (.mergeMembers, "成员列表", "合并从这里选人发起", "arrow.triangle.merge"),
                (.archivedMembers, "已归档", "查看归档成员", "archivebox"),
            ])
        case .system:
            // 5 组并成 4 组（规范 §7.10「项数 3–4」，不得出现 More）。
            // 合并的是「安全」+「数据与外观」—— 它们的共同点是**都在管这台手机**，
            // 而不是管那把锁。分两栏时用户要在两个 Tab 之间反复横跳才能配完一次备份。
            rows([
                (.securityCenter, "隐私看板", "应用锁 / 授权总览", "lock.shield"),
                (.securityAudit, "安全审计", "变更记录", "list.bullet.rectangle"),
                (.securityDestroy, "销毁数据", "不可逆清除", "trash"),
                (.safemode, "安全模式", "变严方向", "shield.lefthalf.filled"),
                (.backup, "备份恢复", "导出 / 导入 / 校验", "externaldrive.badge.timemachine"),
                (.export, "导出中心", "PDF / CSV / 分享", "square.and.arrow.up"),
                (.appearance, "外观工作室", "强调色 / 密度 / 周起始", "paintpalette"),
                (.me, "本机设置", "应用锁 / 备份 / 关于", "person.crop.circle"),
            ])
        }
    }

    /// 一行一张卡 —— 规范 5.1 的**行间距 8**（`XSpace.rowGap`）。
    ///
    /// 为什么一行一张卡而不是"一卡包所有行":
    ///   规范 §8 模板 C（详情页）与 §7 的组件都是**一张卡一件事**;
    ///   把所有入口塞进一张卡会变成系统设置那种"长白条列表",
    ///   而那恰好是范式 §1.5 点名「它绝不等于」的第四项（Material You 卡片墙的反面）。
    ///
    /// 另外: 每张卡都可点, 所以每张都是独立触达面 —— 44pt 的下限由 XRow 自己保证。
    private func rows(_ items: [(ManagerRoute, String, String, String)]) -> some View {
        VStack(spacing: XSpace.rowGap) {
            ForEach(items, id: \.0) { item in
                let (route, title, subtitle, icon) = item
                XPanel(kind: .group) {
                    XRow(systemImage: icon, title: title,
                         subtitle: subtitle, showsChevron: true) {
                        path.append(route)
                    }
                }
            }
        }
    }

    // ── 浮动玻璃分组条 (规范 7.10 GlassTabBar) ──
    //
    // 旧实现的选中态是 "accent 12% 胶囊" —— 那是**语义色洗底**, 不是范式要的
    // "更亮的微光胶囊 + 图标与标签同时变语义色"。两者观感完全不同:
    //   洗底 = 一块有色玻璃贴在栏体上;
    //   微光 = 栏体本身被顶起一格, 用颜色指认"你在哪"。
    //
    // 规范把这个列为**最容易搞反的一处** (7.10 自检), 并给了实测依据:
    // 选中胶囊只比栏体亮 6 个色阶, 纯黑上几乎看不见 ⇒ **颜色才是主要识别信号**。
    // 所以这里图标与标签都跟着变语义色, 明度差只做辅助。
    private var groupBar: some View {
        XGlassTabBar(items: tabItems, selection: groupIndex) { idx in
            guard idx < ManagerGroup.allCases.count else { return }
            withAnimation(XMotion.standard) { group = ManagerGroup.allCases[idx] }
            XHaptics.tick.impactOccurred()
        }
        .padding(.horizontal, XSpace.gutter)
        .padding(.bottom, XSpace.s)
    }

    /// ManagerGroup → 规范 TabItem。**四项**，每项图标 + 标签（规范 §7.10：项数 3–4，不得出现 More）。
    ///
    /// 2026-10-22 审计修正：此处原本是 5 项，并用一句「规范说每组 3–7 项」给自己开脱 ——
    /// **规范里根本没有那一条**。那是我为了保留第 5 项编出来的依据。
    /// 已按 §7.10 合并为 4 项。
    private var tabItems: [XTabItem] {
        ManagerGroup.allCases.enumerated().map { idx, g in
            XTabItem(id: idx, title: g.rawValue, symbol: g.systemImage,
                     selectedSymbol: g.systemImage + ".fill",
                     tint: XPalette.accentText)
        }
    }

    private var groupIndex: Binding<Int> {
        Binding(
            get: { ManagerGroup.allCases.firstIndex(of: group) ?? 0 },
            set: { group = ManagerGroup.allCases[max(0, min($0, ManagerGroup.allCases.count - 1))] }
        )
    }

    // ── 路由落地 ──
    private func consumePendingFocus() {
        guard let f = app.pendingSettingsFocus else { return }
        app.pendingSettingsFocus = nil
        switch f {
        case "backup": path = [.backup]
        case "diag": path = [.diagnostics]
        default: break        // 认不出的落点名不做猜测，留在原地
        }
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
        // MergeMembersView 需要 primary: Member（它是 sheet 里的视图，
        // 从一条具体成员发起合并）。路由层拿不到那个 Member，
        // 所以落到成员列表 —— 在那儿选人再合并。
        case .mergeMembers:   MembersPage()
        case .archivedMembers: MemberArchivedView()
        case .securityCenter: PrivacyDashboard()
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
    case members, memberWizard, mergeMembers, archivedMembers
    case securityCenter, securityAudit, securityDestroy, safemode
    case backup, export, appearance, me
    case diagnostics

    var id: String { rawValue }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - B 域 5 组
// ═══════════════════════════════════════════════════════════════════════
//
// 上一版这个定义在 DoorRoot.swift 里，M4 把它移到 ManagerFace 旁边 ——
// 谁用它就定义在谁那里。移的时候连带把 DoorRoot 里的副本删了，
// 结果两边都没有，swiftlint 报"仅出现 2 次且未声明"才发现。
enum ManagerGroup: String, CaseIterable, Identifiable {
    case ledger = "钥匙"
    case devices = "设备"
    case members = "成员"
    case system = "系统"

    var id: String { rawValue }

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
