// SettingsScreen.swift —— 设置（Tab 4）。v7 结构重写，参考 R4-settings.html 与 TOKENS.md。
//
// 实测来源：芯片行 left 19.3 / 高 53.3 r14；大标题 34pt/700；导语 17/23 #8E8E93；
// 双列 mini 卡（R4 302×170 级别 / v7 统一用 #232227 r16 小卡）；分组标题 20pt/700；
// 列表行 54pt 高、圆形图标 Ø30、标题 16pt、说明 13pt #8E8E93。
// 数据绑定保持原口径：SettingsStore.shared / AppModel / Router / trialGuardBinding 全部不变。
import SwiftUI
import UIKit

/// 设置页五组筛选（原 SettingsGroups.swift:18-78）。分组只影响本页显示，不改任何偏好。
enum SettingsGroup: String, CaseIterable, Identifiable {
    case daily
    case keys
    case data
    case look
    case help

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: return "日常"
        case .keys: return "安全与钥匙"
        case .data: return "数据"
        case .look: return "外观"
        case .help: return "帮助"
        }
    }
}

struct SettingsScreen: View {
    @Environment(AppModel.self) internal var app
    @Environment(Router.self) private var router
    internal var store: SettingsStore { SettingsStore.shared }

    @State private var deleteRequested = false
    @State private var search = ""
    @State private var groupFilter: SettingsGroup?
    @State private var notifyOff = false
    /// 交互流水（排障）：与门锁的原始 TX/RX 帧头 + 分级日志，可一键复制。
    @State private var showDiagStream = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V.S.gapM) {
                // 2026-11-02：阅读顺序 = 标题（导航栏）→ 导语 → 控件。
                // 原来是 chips → 导语 → 分组芯片，把一句解释夹在两排芯片中间。
                header
                chips
                groupChipsBlock
                if !search.trimmingCharacters(in: .whitespaces).isEmpty {
                    searchResults
                } else if app.lock != nil {
                    // 五组 chip 在「浏览」态也要真的过滤节 —— 旧实现只在搜索命中里用 groupFilter，
                    // 不搜时点任何分组都毫无反应（假筛选）。
                    if inGroup(.daily) { statusGrid; lockSection }
                    if inGroup(.keys) { securitySection }
                    if inGroup(.look) { lookSection }
                    if inGroup(.data) { dataSection; deleteSection }
                    if inGroup(.help) { helpSection }
                } else {
                    noLockCard
                    if inGroup(.keys) { securitySection }
                    if inGroup(.look) { lookSection }
                    if inGroup(.data) { dataSection }
                    if inGroup(.help) { helpSection }
                }
            }
            .padding(.top, V.Page.topSpace)
            .padding(.bottom, V.S.gapL)
        }
        .background(V.C.bg.ignoresSafeArea())
        .scrollEdgeEffectStyle(.soft, for: .top)
        // 2026-11-02：系统大标题 + 系统搜索栏 —— 两者都是「原生控件自带材质」的入口，
        // 大标题随滚动收成 inline 时导航栏出现液态玻璃，搜索栏自带系统玻璃背景。
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $search,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "搜设置：备份 / 外观 / 密码…")
        .task {
            await app.reload(refreshStatus: true)
            notifyOff = NotifyAuth.isOff
        }
        .sheet(isPresented: $showDiagStream) { DiagStreamScreen() }
        .sheet(isPresented: $deleteRequested) {
            DeleteDeviceSheet()
        }
    }

    // MARK: - 芯片行

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: V.S.chipGap) {
                VChip(
                    title: "应用锁",
                    value: store.hasPasscode ? "已开启" : "未开启",
                    tint: store.hasPasscode ? V.C.rewardGreen : V.C.pink,
                    style: .standard,
                    systemImage: "checkmark.shield.fill"
                )
                VChip(
                    title: "备份",
                    value: store.lastBackupAt.map { TimeFormat.dayShort($0) } ?? "从未",
                    tint: V.C.miniBlue,
                    style: .standard,
                    systemImage: "externaldrive.fill"
                )
            }
            .padding(.horizontal, V.S.chipLeftA)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - 标题（R4：34pt/700）

    private var header: some View {
        VStack(alignment: .leading, spacing: V.Page.titleToBody) {
            // 2026-11-02：标题改由系统导航栏的大标题承担（见 body 上的 .navigationTitle）——
            // 自己再画一遍就是同一屏两个「设置」。
            Text("这台锁的全部行为都在本机完成，不上传云端。")
                .font(V.F.pageLead)
                .foregroundStyle(V.C.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, V.S.pageGutter)
        .padding(.top, V.Page.chipToTitle)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - 搜索 + 五组筛选（原 SettingsView.swift:17,65,226-269）

    /// 2026-11-02：搜索框交给系统 `.searchable`（见 body 上的修饰符）——
    /// 系统搜索栏自带取消按钮、键盘处理、滚动收起，以及 **液态玻璃** 的搜索栏背景；
    /// 自绘的 TextField 这些都拿不到。这里只剩分组芯片（它是筛选，不是搜索）。
    private var groupChipsBlock: some View {
        VStack(alignment: .leading, spacing: V.S.gapS) {
            ScrollView(.horizontal) {
                HStack(spacing: V.S.gapS) {
                    groupChip(nil, title: "全部")
                    ForEach(SettingsGroup.allCases) { group in
                        groupChip(group, title: group.title)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, V.S.pageGutter)
        .padding(.top, V.S.gapS)
    }

    // 2026-11-03（回归修复）：分组芯片换 `GlassChip` 后**设置页整页白屏**（截图实测），
    // 先回退到原实现。玻璃化留待查明原因（可能是 GlassChip 的 glassEffect 在
    // .searchable + ScrollView 组合下的渲染问题），不在设置页冒险。
    private func groupChip(_ group: SettingsGroup?, title: String) -> some View {
        let on = groupFilter == group
        return Button {
            groupFilter = group
        } label: {
            Text(title)
                .font(V.F.footnote)
                .foregroundStyle(on ? V.C.text1 : V.C.text3)
                .padding(.horizontal, V.S.gapM)
                .padding(.vertical, V.S.gapS)
                .background(on ? V.C.card : Color.clear, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(on ? V.C.tabEdge : V.C.hairline, lineWidth: V.S.hair)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private struct SettingsHit: Identifiable {
        let id: String
        let title: String
        let detail: String
        let symbol: String
        let dest: Dest
        let group: SettingsGroup
    }

    private var settingsHits: [SettingsHit] {
        [
            .init(id: "lockStatus", title: "锁实况", detail: "电量 / 信号 / 固件", symbol: "gauge.with.dots.needle.50percent", dest: .lockStatus, group: .daily),
            .init(id: "deviceInfo", title: "锁信息名片", detail: "固件 / 容量 / 电量采样 / 链路验证", symbol: "info.circle", dest: .deviceInfo, group: .daily),
            .init(id: "lockSettings", title: "锁设置", detail: "临时码开关 / 自动上锁 / 清空密码", symbol: "slider.horizontal.3", dest: .lockSettings, group: .daily),
            .init(id: "syncTime", title: "校准门锁时间", detail: "锁钟 / 临时码有效期", symbol: "clock.arrow.circlepath", dest: .syncTime, group: .daily),
            .init(id: "gateway", title: "智能网关", detail: "远程访问与转发", symbol: "antenna.radiowaves.left.and.right", dest: .gateway, group: .daily),
            .init(id: "defend", title: "布防", detail: "离家后监控门锁状态", symbol: "shield.lefthalf.filled", dest: .defend, group: .daily),
            .init(id: "dfu", title: "固件升级", detail: "本地固件包 · Nordic DFU", symbol: "arrow.up.circle", dest: .dfu, group: .daily),
            .init(id: "security", title: "本机数据保护", detail: "密码 / 胁迫码 / 生物识别", symbol: "lock.shield", dest: .security, group: .keys),
            .init(id: "autoOpen", title: "靠近自动开锁", detail: "走到门前自动开门", symbol: "figure.walk", dest: .autoOpen, group: .keys),
            .init(id: "appearance", title: "外观", detail: "主题 / 品牌色 / 圆角 / 行高 / 数字字体", symbol: "paintbrush", dest: .appearance, group: .look),
            .init(id: "accessibility", title: "无障碍与操作辅助", detail: "大字 / 圆盘尺寸 / 手势", symbol: "figure.roll", dest: .accessibility, group: .look),
            .init(id: "backup", title: "备份与恢复", detail: "导出 / 从文件恢复", symbol: "externaldrive", dest: .backup, group: .data),
            .init(id: "backupStudio", title: "备份工作室", detail: "WebDAV / 多份 / 迁移 / 自检", symbol: "square.stack.3d.up.fill", dest: .backupStudio, group: .data),
            .init(id: "hardware", title: "钥匙串 / 硬件", detail: "蓝牙钥匙串与固件", symbol: "key.horizontal", dest: .hardware, group: .data),
            .init(id: "protocolTest", title: "协议测试", detail: "附近设备与回声探测", symbol: "waveform.path.ecg", dest: .protocolTest, group: .help),
            // 2026-11-03（全功能点 + 表现方式）：God 模式此前只能「设置 → 钥匙串/硬件 → 页底卡片」
            // 两跳才到，用户实测反馈「根本就没有 god 按钮」。入口本身存在（HardwareScreen:197），
            // 只是埋得太深。这里补一条直达入口，仍放在「帮助」组末尾 —— 可发现，但不挡路。
            // 本页只读为主，唯一写动作「修池」自带二级确认。
            .init(id: "godMode", title: "God 模式", detail: "锁端全量读数 / 台账对账 / 变更流水 / 修池", symbol: "crown.fill", dest: .godMode, group: .help),
            .init(id: "about", title: "关于", detail: "版本与构建", symbol: "info.circle", dest: .about, group: .help)
        ]
    }

    private var searchResults: some View {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let hits = settingsHits.filter { hit in
            (groupFilter == nil || hit.group == groupFilter)
                && (hit.title.lowercased().contains(q) || hit.detail.lowercased().contains(q))
        }
        return VStack(alignment: .leading, spacing: V.S.gapS) {
            VSectionLabel(text: "搜索结果", trailing: "\(hits.count) 项")
            if hits.isEmpty {
                VCard {
                    VStack(alignment: .leading, spacing: V.S.gapM) {
                        Text("没有找到「\(search)」")
                            .font(V.F.bodyStrong)
                            .foregroundStyle(V.C.text1)
                        Text("换个词试试：备份 / 外观 / 密码 / 钥匙串 / 固件。也可以点上面的分组，直接看那一组。")
                            .font(V.F.footnote)
                            .foregroundStyle(V.C.text2)
                            .fixedSize(horizontal: false, vertical: true)
                        VOutlineButton(title: "清除搜索", systemImage: "xmark.circle") { search = "" }
                    }
                }
                .padding(.horizontal, V.S.pageGutter)
            } else {
                VCard {
                    VStack(spacing: 0) {
                        ForEach(Array(hits.enumerated()), id: \.element.id) { pair in
                            if pair.offset > 0 { VDivider() }
                            VListRow(title: pair.element.title, detail: pair.element.detail,
                                     systemImage: pair.element.symbol, tint: V.C.rewardBlue) {
                                search = ""
                                router.request(.dest(pair.element.dest))
                            }
                        }
                    }
                }
                .padding(.horizontal, V.S.pageGutter)
            }
        }
    }

    private func groupFor(_ title: String) -> SettingsGroup {
        switch title {
        case "门锁": return .daily
        case "安全": return .keys
        case "外观与时间": return .look
        case "数据与硬件", "这台锁的本地数据": return .data
        default: return .help
        }
    }

    // MARK: - 锁状态双卡

    private var statusGrid: some View {
        HStack(alignment: .top, spacing: V.S.gapM) {
            VCard(style: .mini) {
                VStack(alignment: .leading, spacing: V.S.gapS) {
                    HStack {
                        Text(app.lock?.name ?? "门锁")
                            .font(V.F.footnote)
                            .foregroundStyle(V.C.text3)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(V.F.chipLabelStrong)
                            .foregroundStyle(V.C.text3)
                            .accessibilityHidden(true)
                    }
                    Text(app.lock?.isConnected == true ? "已连接" : "未连接")
                        .font(V.F.section)
                        .foregroundStyle(V.C.text1)
                    Text("固件 \(app.lock?.firmware ?? "—") · 信号 \(app.lock?.signal ?? 0)")
                        .font(V.F.footnote)
                        .foregroundStyle(V.C.text3)
                }
                .frame(minHeight: V.Metric.miniCardH / 2, alignment: .top)
            }
            VCard(style: .mini) {
                VStack(alignment: .leading, spacing: V.S.gapS) {
                    HStack {
                        Text("固件")
                            .font(V.F.footnote)
                            .foregroundStyle(V.C.text3)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(V.F.chipLabelStrong)
                            .foregroundStyle(V.C.text3)
                            .accessibilityHidden(true)
                    }
                    Text(app.lock?.firmware ?? "—")
                        .font(V.F.section)
                        .foregroundStyle(V.C.text1)
                    Text("当前版本")
                        .font(V.F.footnote)
                        .foregroundStyle(V.C.text3)
                }
                .frame(minHeight: V.Metric.miniCardH / 2, alignment: .top)
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    // MARK: - 分组（VCard + VListRow）

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        if groupFilter == nil || groupFilter == groupFor(title) {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                Text(title)
                    .font(V.F.section)
                    .foregroundStyle(V.C.text1)
                VCard {
                    content()
                }
            }
            .padding(.horizontal, V.S.cardGutter)
            .padding(.top, V.S.gapS)
        }
    }

    /// 2026-11-03（全维度整理）：**删除重复的导航树**。
    ///
    /// 原来这里 8 行里有 6 行（锁实况 / 锁信息名片 / 锁设置 / 校准门锁时间 / 智能网关 / 布防）
    /// 和「门」页的「门锁与入口」一模一样 —— 同一功能两个入口，用户不知道该走哪条，
    /// 两处还会各自维护文案与徽标。设置页只留**真正属于设置**的两项（模块排序、固件升级），
    /// 其余统一从门页进；再给一行明确的指路，避免用户在这里找不到。
    private var lockSection: some View {
        section("门锁") {
            VStack(spacing: 0) {
                VListRow(
                    title: "模块排序与显隐",
                    detail: "设备页三槽顺序 / 模块显隐 / 快捷格",
                    systemImage: "square.grid.2x2",
                    tint: V.C.purple,
                    value: ""
                ) { router.request(.dest(.moduleOrder)) }
                VDivider()
                VListRow(
                    title: "固件升级",
                    detail: "本地固件包 · Nordic DFU",
                    systemImage: "arrow.up.circle",
                    tint: V.C.rewardGreen,
                    value: pkgVersion
                ) { router.request(.dest(.dfu)) }
                VDivider()
                VListRow(
                    title: "锁实况 / 锁设置 / 网关 / 布防",
                    detail: "这些在「门」页的「门锁与入口」里，点这里直接过去",
                    systemImage: "door.left.hand.open",
                    tint: V.C.rewardBlue,
                    value: ""
                ) { router.tab = .door }
            }
        }
    }

    private var securitySection: some View {
        section("安全") {
            VStack(spacing: 0) {
                VListRow(
                    title: "本机数据保护",
                    detail: "密码只存在这台手机",
                    systemImage: "lock.shield",
                    tint: V.C.rewardBlue,
                    value: store.hasPasscode ? "已设" : "未设"
                ) { router.request(.dest(.security)) }
                VDivider()
                VListRow(
                    title: "靠近自动开锁",
                    detail: "走到门前自动开门",
                    systemImage: "figure.walk",
                    tint: V.C.rewardGreen,
                    value: store.autoOpenEnabled ? "开" : "关"
                ) { router.request(.dest(.autoOpen)) }
                if notifyOff {
                    VDivider()
                    VListRow(
                        // 2026-11-03（整页截图）：原标题「通知权限 · 到期提醒不会送达」在行内被省略号截断。
                        // 标题只留名词，后果放进 detail。
                        title: "通知权限",
                        detail: "到期提醒不会送达：系统里被拒绝或还没询问。点这里去系统设置打开。",
                        systemImage: "bell.slash",
                        tint: V.C.warning,
                        value: NotifyAuth.label
                    ) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                VDivider()
                VToggleRow(
                    title: "只读试验模式",
                    detail: "真机排障用：所有写入类命令停用，只看不改。关掉 App 也不会自动恢复 —— 记得回来关。",
                    isOn: trialGuardBinding(app)
                )
            }
        }
    }

    private var lookSection: some View {
        section("外观与时间") {
            VStack(spacing: 0) {
                VListRow(
                    title: "外观",
                    detail: "跟随系统 / 浅色 / 深色",
                    systemImage: "paintbrush",
                    tint: V.C.purple,
                    value: store.theme.title
                ) { router.request(.dest(.appearance)) }
                VDivider()
                VListRow(
                    title: "时间显示",
                    detail: "24 小时 / 12 小时",
                    systemImage: "clock",
                    tint: V.C.miniBlue,
                    value: store.timeStyle.title
                ) { router.request(.dest(.appearance)) }
                VDivider()
                // 来源：原 App/Core/AccessibilityKit.swift（AXPrefs / 操作辅助）。
                VListRow(
                    title: "无障碍与操作辅助",
                    detail: "大字 / 圆盘尺寸 / 手势 / 大格",
                    systemImage: "figure.roll",
                    tint: V.C.rewardGreen,
                    value: AXSettings.bigText ? "大字" : "标准"
                ) { router.request(.dest(.accessibility)) }
            }
        }
    }

    private var dataSection: some View {
        section("数据与硬件") {
            VStack(spacing: 0) {
                VListRow(
                    title: "备份与恢复",
                    detail: "导出或恢复本机数据",
                    systemImage: "externaldrive",
                    tint: V.C.rewardGreen,
                    value: store.lastBackupAt.map { TimeFormat.ago($0) } ?? "从未备份"
                ) { router.request(.dest(.backup)) }
                VDivider()
                // 来源：原 App/Services/BackupStudioKit.swift（WebDAV / 多份 / 迁移 / 自检）。
                VListRow(
                    title: "备份工作室",
                    detail: "WebDAV / 多份保留 / 换机迁移 / 自检",
                    systemImage: "square.stack.3d.up.fill",
                    tint: V.C.miniBlue,
                    // 2026-11-03（信息架构 QA）：原来这里读 kf_bk_keep（**保留上限**，默认 5），
                    // 于是"一份备份都没有"的新装机也显示「5 份」。份数要说真的。
                    value: BackupStudio.localFileCount == 0
                        ? "未备份"
                        : String(BackupStudio.localFileCount) + " 份"
                ) { router.request(.dest(.backupStudio)) }
                VDivider()
                VListRow(
                    title: "钥匙串 / 硬件",
                    detail: "蓝牙钥匙串与固件",
                    systemImage: "key.horizontal",
                    tint: V.C.coral,
                    value: "\(store.dongles.count) 台"
                ) { router.request(.dest(.hardware)) }
            }
        }
    }

    /// 帮助组（原 SettingsGroups 的 help 档）：协议测试与关于。
    private var helpSection: some View {
        section("帮助") {
            VStack(spacing: 0) {
                VListRow(
                    title: "协议测试",
                    detail: "附近设备与回声探测",
                    systemImage: "waveform.path.ecg",
                    tint: V.C.text3,
                    value: ""
                ) { router.request(.dest(.protocolTest)) }
                VDivider()
                // 2026-11-01 新增：把 `DiagLogs` 接出来。此前它每行都在写，但**没有任何界面读**，
                // 用户遇到"开锁失败"时无法把现场交互复制出来。
                VListRow(
                    title: "交互流水（排障）",
                    detail: "与门锁的原始 TX/RX 帧头，可复制发给开发者",
                    systemImage: "waveform.path",
                    tint: V.C.text3,
                    value: "\(DiagLogs.all().count) 行"
                ) { showDiagStream = true }
                VDivider()
                VListRow(
                    title: "关于",
                    detail: "版本与构建",
                    systemImage: "info.circle",
                    tint: V.C.text3,
                    value: SettingsFacts.version
                ) { router.request(.dest(.about)) }
            }
        }
    }

    /// 分组 chip 的浏览态判据（搜索态由 searchResults 自己按 hit.group 过滤）。
    private func inGroup(_ group: SettingsGroup) -> Bool {
        groupFilter == nil || groupFilter == group
    }

    /// 固件升级行右侧读数：没有包目录可读时给锁内当前固件版本（读不到就写「未读到」，不留空白）。
    private var pkgVersion: String {
        guard let fw = app.lock?.firmware else { return "未添加" }
        return fw.isEmpty ? "未读到" : fw
    }

    private var deleteSection: some View {
        VStack(alignment: .leading, spacing: V.S.gapS) {
            Text("这台锁的本地数据")
                .font(V.F.section)
                .foregroundStyle(V.C.text1)
            VCard {
                VStack(alignment: .leading, spacing: V.S.gapM) {
                    // 2026-11-03（整页截图）：原来只有一行红色文字 —— 看着像小标题，不像可点的危险操作。
                    // 换成带描边的 destructive 按钮，边界明确。
                    VOutlineButton(title: "删除这台锁的本机数据",
                                   systemImage: "trash",
                                   tint: V.C.red) {
                        deleteRequested = true
                    }
                    // 2026-11-01（Round 283）：原文案写「未做备份则无法找回」，暗示"做过备份就安全" ——
                    // 但 `DB.removeDevice` 会调 `BackupStudio.purgeLocalArtifacts`，把**本机备份文件与还原点
                    // 一并删掉**（备份是整库包，里面含这把锁的母钥，留着等于没删干净，SEC-19）。
                    // 用户"先备份再删锁"会连备份一起丢 —— 必须说清，并给出真正的留档办法。
                    // 2026-11-04（读实现发现 · 两类文件不同）：`purgeLocalArtifacts` 清的是两类：
                    //   · 本机备份 `backup-*.json` —— 经 `CryptoBox.encryptText` **加密**，没有口令打不开；
                    //   · 还原点 `roll-*.json` —— `JSONEncoder` 直写，**明文**，含整库 skey/pins。
                    // 原文案把两类混成一句「备份里含这把锁的母钥」，对加密备份不准确（也不公平：
                    // 用户会以为"我设了口令还是没用"）。分开说清。
                    Text("只删本机：锁端密钥与锁内日志不变，重配即可再添加。注意：本机的备份文件（加密的，需要你设的口令）与还原点（明文，含母钥）都会被一并删除；想留档请先把备份导出到别处（WebDAV 或复制文本）。")
                        .font(V.F.footnote)
                        .foregroundStyle(V.C.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
        .padding(.top, V.S.gapS)
    }

    private var noLockCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapM) {
                Text("还没有添加门锁")
                    .font(V.F.displayB)
                    .foregroundStyle(V.C.text1)
                Text("打开后面板，长按 RESET 直到三声嘀，然后在这里添加。添加后这一屏才会出现锁实况、校时与删除。")
                    .font(V.F.body)
                    .foregroundStyle(V.C.text2)
                    .fixedSize(horizontal: false, vertical: true)
                VActionButton(title: "添加门锁", systemImage: "plus") {
                    router.request(.dest(.addLock))
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }
}

// MARK: - 删除设备：键入锁名才放行（保留原有逻辑，视觉沿用 v7）

struct DeleteDeviceSheet: View {
    @Environment(AppModel.self) internal var app
    @Environment(\.dismiss) internal var dismiss
    @State private var typed = ""

    private var lockName: String { app.lock?.name ?? "" }
    private var canDelete: Bool { !lockName.isEmpty && typed == lockName }

    /// 真删除：钥匙串 + 该锁全部本机数据族（台账 / 日志缓存 / 快照 / 布防 / 自动上锁 /
    /// 锁档案 / 电池采样 / 校时 / OTP / 到期提醒…）一次清干净。
    /// 只执行 app.lock = nil 的旧实现会让数据留在本机 —— 用户以为删了，密钥还在。
    private func deleteLocalData() {
        let mac = app.lock?.id ?? app.currentMac
        guard !mac.isEmpty else { return }
        DB.removeDevice(mac)
        app.lock = nil
        app.keys = []
        app.entries = []
        app.lastStatus = nil
        AppToast.shared.show("已删除这台锁的本机数据（锁端不变）", tone: .ok)
        Task { await app.reload(refreshStatus: false) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: V.S.gapM) {
                    Text("删除「\(lockName)」")
                        .font(V.F.displayB)
                        .foregroundStyle(V.C.text1)
                    Text("只删本机数据 · 锁端密钥与锁内日志不变")
                        .font(V.F.footnote)
                        .foregroundStyle(V.C.text3)
                    VCard {
                        VStack(alignment: .leading, spacing: V.S.gapS) {
                            Text("会被删除")
                                .font(V.F.cardTitle)
                                .foregroundStyle(V.C.text6)
                            // 2026-11-04（读实现发现 · 清单不全）：`removeDevice` 实际还会清掉
                            // **回收站条目**（`CredBinStore.purgeSecretsForDevice`）、**版本快照**
                            // （`CredHistoryStore.purgeSecretsForDevice`，最多 10 份台账副本）、
                            // **手机钥匙**（`MobileKeyService.purgeSecretsForDevice`）—— 这三族都含
                            // 开锁口令/ekey 的钥匙串副本。而"会被删除"清单只列了三项，
                            // 用户可能以为回收站里还能捞回来。补齐。
                            VStatPair(items: [
                                ("凭证", "\(app.keys.count) 枚"),
                                ("记录缓存", "\(app.entries.count) 条"),
                                ("本机密码", SettingsStore.shared.hasPasscode ? "已设" : "未设")
                            ])
                            VStatPair(items: [
                                ("回收站", "\(CredBinStore.all(app.currentMac).count) 条 · 一并删除"),
                                ("版本快照", "\(CredHistoryStore.all(app.currentMac).count) 份 · 一并删除"),
                                ("手机钥匙", "\(MobileKeyService.list(app.currentMac).count) 把 · 一并删除")
                            ])
                            // 同上：备份文件会被这次删除一并清掉，不能暗示"有备份就安全"。
                            // 2026-11-04（与 :543 同口径）：备份是**加密**的、还原点是**明文**的，
                            // 不能合并成"备份里含母钥"—— 那会让设了口令的用户以为口令白设了。
                            Text("删除后本机的密码台账与缓存记录无法找回；本机的备份文件（加密的）与还原点（明文，含母钥）也会一并删除"
                                 + "—— 留着等于没删干净。想留档请先把备份导出到别处（WebDAV 或复制文本）。锁本身不需要重置，可以再次添加。")
                                .font(V.F.footnote)
                                .foregroundStyle(V.C.text3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    VCard {
                        VStack(alignment: .leading, spacing: V.S.gapS) {
                            Text("键入锁名确认")
                                .font(V.F.cardTitle)
                                .foregroundStyle(V.C.text6)
                            TextField(lockName, text: $typed)
                                .font(V.F.body)
                                .foregroundStyle(V.C.text1)
                                .textFieldStyle(.plain)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .frame(minHeight: V.Metric.searchRow)
                                .accessibilityLabel("键入锁名")
                            Rectangle().fill(V.C.hairline).frame(height: V.S.hair)
                            VActionButton(title: "删除本机数据", systemImage: "trash", tint: V.C.red) {
                                deleteLocalData()
                                dismiss()
                            }
                            .disabled(!canDelete)
                            .opacity(canDelete ? 1 : 0.4)
                            // 2026-11-03（信息架构 QA）：删除确认页里「取消」原本和「删除本机数据」
                            // 是**两个同级实心主按钮**上下堆叠，只靠颜色区分 —— 危险的实心、安全的也实心。
                            // 取消必须降级为次要样式（描边），让主按钮只有一个。
                            VOutlineButton(title: "取消", systemImage: "xmark") { dismiss() }
                        }
                    }
                }
                .padding(V.S.pageGutter)
            }
            .background(V.C.bg.ignoresSafeArea())
            .navigationTitle("删除设备")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview("SettingsScreen") {
    NavigationStack {
        SettingsScreen()
    }
    .environment(AppModel())
    .environment(Router())
}
