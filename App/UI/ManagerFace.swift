import SwiftUI

// ═══════════════════════════════════════════════════════════════════════
// MARK: - B 管家台（底部液态玻璃分组）
// ═══════════════════════════════════════════════════════════════════════
//
// 21 个设置类页面塞进一个面会变成"入口列表"，又回到普通 App 的样子。
// 所以分 5 组，用**浮动液态玻璃胶囊**切换。
//
// ═══ 为什么复用 axGlass 而不是自己写 glassEffect ═══
//
// AccessibilityKit.swift 的 GlassModifier 已经做了:
//   正常      → content.glassEffect(.regular, in: Capsule())
//   降低透明度 → 降为实底 XPalette.surface + hairlineStrong 描边
//   高对比    → 同上
//
// 自己写 glassEffect 会绕开这三条降级，等于给无障碍挖坑。
//
// ═══ 与三棱柱的关系 ═══
//
//   三棱柱（顶层，3 面）
//     └─ B 面 ─→ 底部液态玻璃 Tab（5 组）─→ 页面
//
// 底部 Tab 是**域内导航**，不参与三棱柱旋转。
struct ManagerFace: View {
    @EnvironmentObject private var app: AppState
    @State private var group: ManagerGroup = .ledger
    @State private var path: [ManagerRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                XPalette.canvas.ignoresSafeArea()

                // ── 内容区 ──
                ScrollView {
                    VStack(spacing: XSpace.l) {
                        groupHeader
                        groupContent
                    }
                    .padding(.horizontal, XSpace.gutter)
                    .padding(.top, XSpace.s)
                    // 给底部浮动胶囊留空间
                    .padding(.bottom, 96)
                }

                // ── 浮动液态玻璃分组条 ──
                groupBar
            }
            .navigationTitle("管家台")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ManagerRoute.self) { r in
                routeDestination(r)
            }
        }
    }

    // ── 组标题（带动态摘要）──
    private var groupHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(group.rawValue)
                .xFont(.title2, weight: .semibold)
                .foregroundStyle(XPalette.text)
            Text(group.summary)
                .xFont(.caption)
                .foregroundStyle(XPalette.textSub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, XSpace.xs)
        .accessibilityElement(children: .combine)
    }

    // ── 当前组的内容 ──
    @ViewBuilder
    private var groupContent: some View {
        switch group {
        case .ledger:
            rows([
                (.keys, "凭证管理", "密码 / 指纹 / 临时码", "key.horizontal"),
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
                (.mergeMembers, "合并重复", "整理成员档案", "arrow.triangle.merge"),
                (.archivedMembers, "已归档", "查看归档成员", "archivebox"),
            ])
        case .security:
            rows([
                (.securityCenter, "隐私看板", "应用锁 / 授权总览", "lock.shield"),
                (.securityAudit, "安全审计", "变更记录", "list.bullet.rectangle"),
                (.securityDestroy, "销毁数据", "不可逆清除", "trash"),
                (.safemode, "安全模式", "变严方向", "shield.lefthalf.filled"),
            ])
        case .backupLook:
            rows([
                (.backup, "备份恢复", "导出 / 导入 / 校验", "externaldrive.badge.timemachine"),
                (.export, "导出中心", "PDF / CSV / 分享", "square.and.arrow.up"),
                (.appearance, "外观工作室", "主题 / 强调色 / 密度", "paintpalette"),
                (.me, "关于我", "个人与设备信息", "person.crop.circle"),
            ])
        }
    }

    private func rows(_ items: [(ManagerRoute, String, String, String)]) -> some View {
        VStack(spacing: XSpace.s) {
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

    // ── 浮动液态玻璃分组条 ──
    private var groupBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(ManagerGroup.allCases) { g in
                    Button {
                        withAnimation(XMotion.soft) { group = g }
                        XHaptics.tick.impactOccurred()
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: g.systemImage)
                                .font(.system(size: XIcon.sm, weight: .medium))
                            Text(g.rawValue)
                                .xFont(.caption2, weight: group == g ? .semibold : .regular)
                        }
                        .foregroundStyle(group == g ? XPalette.text : XPalette.textSub)
                        .frame(minWidth: 62, minHeight: 46)
                        .background {
                            if group == g {
                                Capsule().fill(XPalette.accent.opacity(XOpacity.badge))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(g.rawValue)
                    .accessibilityAddTraits(group == g ? [.isSelected] : [])
                }
            }
            .padding(6)
        }
        .scrollBounceBehavior(.basedOnSize)
        // 复用 axGlass —— 内部已处理降低透明度/高对比降级
        .axGlassCapsule()
        .padding(.horizontal, XSpace.gutter)
        .padding(.bottom, XSpace.s)
    }

    // ── 路由落地 ──
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
        case .appearance:     StudioPage()
        case .settings:       StudioPage()
        case .me:             MePage()
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
    case ledger = "台账"
    case devices = "设备"
    case members = "成员"
    case security = "安全"
    case backupLook = "备份外观"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .ledger: return "key.horizontal"
        case .devices: return "iphone.gen3"
        case .members: return "person.2"
        case .security: return "lock.shield"
        case .backupLook: return "externaldrive.badge.timemachine"
        }
    }

    /// 每组摘要 —— 与旧 DoorDomain.summary 同口径: 必须显示真实数字
    var summary: String {
        switch self {
        case .ledger:
            let n = DB.keychains().reduce(0) { acc, kc in
                acc + DB.listPwds(kc.mac).count + DB.listFps(kc.mac).count
            }
            return n > 0 ? "\(n) 份凭证" : "还没有凭证"
        case .devices:
            let n = DB.keychains().count
            return n > 0 ? "\(n) 把锁" : "还没有门锁"
        case .members:
            let n = DB.members().count
            return n > 0 ? "\(n) 位成员" : "还没有成员"
        case .security:
            return DB.store.getBool("kf_applock") ? "应用锁已开" : "应用锁未开"
        case .backupLook:
            return "备份 · 导出 · 外观"
        }
    }
}
