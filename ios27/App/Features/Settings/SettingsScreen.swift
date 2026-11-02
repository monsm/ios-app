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
    /// 通知权限与流水行数都在 body 里显示，但取值是同步/读文件的 —— 读一次缓存，不在每次 body 重算。
    @State private var notifyLabel = ""
    @State private var diagLineCount = 0
    /// 交互流水（排障）：与门锁的原始 TX/RX 帧头 + 分级日志，可一键复制。
    @State private var showDiagStream = false

    var body: some View {
        // 全换系统：容器是系统 List，分组是系统 Section(header:)；
        // 行本身仍由 settingsRow 渲染（entries 是搜索索引的唯一来源，一行都不动）。
        List {
            Section {
                // 同 KeysScreen：页头的 pageGutterC 缩进由 `headerRow(gutter:)` 表达。
                header.headerRow(gutter: V.S.pageGutterC)
                chips
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                searchBlock
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            if !search.trimmingCharacters(in: .whitespaces).isEmpty {
                searchResults
            } else if app.lock != nil {
                // 五组 chip 在「浏览」态也要真的过滤节 —— 旧实现只在搜索命中里用 groupFilter，
                // 不搜时点任何分组都毫无反应（假筛选）。
                if inGroup(.daily) {
                    Section {
                        statusGrid
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    lockSection
                }
                if inGroup(.keys) { securitySection }
                if inGroup(.look) { lookSection }
                if inGroup(.data) {
                    dataSection
                    deleteSection
                }
                if inGroup(.help) { helpSection }
            } else {
                Section {
                    noLockCard
                        .listRowInsets(EdgeInsets(top: 0, leading: V.S.cardGutter, bottom: 0, trailing: V.S.cardGutter))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                if inGroup(.keys) { securitySection }
                if inGroup(.look) { lookSection }
                if inGroup(.data) { dataSection }
                if inGroup(.help) { helpSection }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(V.C.bg.ignoresSafeArea())
        // 系统导航栏 + 系统搜索栏：玻璃由系统在功能层自己加，不再自绘大标题与假搜索框。
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $search, prompt: Text("搜设置：备份 / 外观 / 密码…"))
        .task {
            await app.reload(refreshStatus: true)
            let auth = NotifyAuth.status
            notifyLabel = NotifyAuth.labelFor(auth)
            notifyOff = NotifyAuth.isOffFor(auth)
            diagLineCount = DiagLogs.all().count
        }
        .sheet(isPresented: $showDiagStream) {
            DiagStreamScreen()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $deleteRequested) {
            DeleteDeviceSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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

    // MARK: - 导语（标题已交给系统大标题 .navigationTitle("设置")）

    private var header: some View {
        VStack(alignment: .leading, spacing: V.Page.titleToBody) {
            // 2026-11-02（R7 收尾）：原文案「不上传云端」与实现不符 ——
            // 备份工作室有 WebDAV 上传（BackupStudioScreen 的 uploadDav），是用户自己配置的出口。
            // 承诺要么兑现要么改准：这里改成如实描述（默认不联网，唯一出口是你自己配的 WebDAV）。
            Text("默认全部在本机完成，不连任何服务器。唯一可能离开本机的，是你自己在「备份工作室」里配置的 WebDAV。")
                .font(V.F.pageLead)
                .foregroundStyle(V.C.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, V.S.gapS)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - 五组筛选（搜索框已交给系统搜索栏 .searchable）

    private var searchBlock: some View {
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
        .padding(.top, V.S.gapS)
    }

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

    /// 设置页唯一的数据源：**行渲染与搜索索引都从这份清单派生**。
    /// 旧实现把 21 行与 16 条搜索索引各写一遍，同一句 detail 维护两处 —— 改一处必漂。
    private struct SettingsEntry: Identifiable {
        let id: String
        let group: SettingsGroup
        let title: String
        let detail: String
        let symbol: String
        let tint: Color
        let value: String
        var dest: Dest? = nil
        var action: (() -> Void)? = nil
    }

    private var entries: [SettingsEntry] {
        [
            // 门锁
            .init(id: "lockStatus", group: .daily, title: "锁实况", detail: "电量 / 信号 / 固件",
                  symbol: "gauge.with.dots.needle.50percent", tint: V.C.rewardBlue,
                  value: batteryReading, dest: .lockStatus),
            .init(id: "deviceInfo", group: .daily, title: "锁信息名片", detail: "固件 / 容量 / 电量采样 / 链路验证",
                  symbol: "info.circle", tint: V.C.miniBlue, value: "", dest: .deviceInfo),
            .init(id: "moduleOrder", group: .daily, title: "模块排序与显隐", detail: "设备页三槽顺序 / 模块显隐 / 快捷格",
                  symbol: "square.grid.2x2", tint: V.C.purple, value: "", dest: .moduleOrder),
            .init(id: "lockSettings", group: .daily, title: "锁设置", detail: "临时码开关 / 自动上锁 / 清空密码",
                  symbol: "slider.horizontal.3", tint: V.C.coral, value: "", dest: .lockSettings),
            .init(id: "syncTime", group: .daily, title: "校准门锁时间", detail: "让锁内时钟与手机一致",
                  symbol: "clock.arrow.circlepath", tint: V.C.rewardGreen,
                  value: store.lockClockSyncedAt.map { TimeFormat.ago($0) } ?? "从未", dest: .syncTime),
            .init(id: "gateway", group: .daily, title: "智能网关", detail: "远程访问与转发",
                  symbol: "antenna.radiowaves.left.and.right", tint: V.C.purple,
                  value: DB.gateways().isEmpty ? "未绑定" : "\(DB.gateways().count) 台", dest: .gateway),
            .init(id: "defend", group: .daily, title: "布防", detail: "离家后监控门锁状态",
                  symbol: "shield.lefthalf.filled", tint: V.C.coral,
                  value: DefendKit.summary(DB.defend(app.currentMac)), dest: .defend),
            .init(id: "dfu", group: .daily, title: "固件升级", detail: "本地固件包 · Nordic DFU",
                  symbol: "arrow.up.circle", tint: V.C.rewardGreen, value: pkgVersion, dest: .dfu),
            // 安全
            .init(id: "security", group: .keys, title: "本机数据保护", detail: "密码只存在这台手机",
                  symbol: "lock.shield", tint: V.C.rewardBlue,
                  value: store.hasPasscode ? "已设" : "未设", dest: .security),
            .init(id: "autoOpen", group: .keys, title: "靠近自动开锁", detail: "走到门前自动开门",
                  symbol: "figure.walk", tint: V.C.rewardGreen,
                  value: store.autoOpenEnabled ? "开" : "关", dest: .autoOpen),
            .init(id: "notify", group: .keys, title: "通知权限 · 到期提醒不会送达",
                  detail: "系统里被拒绝或还没询问。点这里去系统设置打开。",
                  symbol: "bell.slash", tint: V.C.warning, value: notifyLabel,
                  action: {
                      if let url = URL(string: UIApplication.openSettingsURLString) {
                          UIApplication.shared.open(url)
                      }
                  }),
            // 外观
            .init(id: "appearance", group: .look, title: "外观", detail: "跟随系统 / 浅色 / 深色",
                  symbol: "paintbrush", tint: V.C.purple, value: store.theme.title, dest: .appearance),
            .init(id: "timeDisplay", group: .look, title: "时间显示", detail: "24 小时 / 12 小时",
                  symbol: "clock", tint: V.C.miniBlue, value: store.timeStyle.title, dest: .appearance),
            .init(id: "accessibility", group: .look, title: "无障碍与操作辅助", detail: "大字 / 圆盘尺寸 / 手势 / 大格",
                  symbol: "figure.roll", tint: V.C.rewardGreen,
                  value: AXSettings.bigText ? "大字" : "标准", dest: .accessibility),
            // 数据
            .init(id: "backup", group: .data, title: "备份与恢复", detail: "导出或恢复本机数据",
                  symbol: "externaldrive", tint: V.C.rewardGreen,
                  value: store.lastBackupAt.map { TimeFormat.ago($0) } ?? "从未备份", dest: .backup),
            .init(id: "backupStudio", group: .data, title: "备份工作室", detail: "WebDAV / 多份保留 / 换机迁移 / 自检",
                  symbol: "square.stack.3d.up.fill", tint: V.C.miniBlue,
                  value: "\(backupFileCount) 份", dest: .backupStudio),
            .init(id: "hardware", group: .data, title: "钥匙串 / 硬件", detail: "蓝牙钥匙串与固件",
                  symbol: "key.horizontal", tint: V.C.coral,
                  value: "\(store.dongles.count) 台", dest: .hardware),
            // 帮助
            .init(id: "protocolTest", group: .help, title: "协议测试", detail: "附近设备与 cmd12 回声",
                  symbol: "waveform.path.ecg", tint: V.C.text3, value: "", dest: .protocolTest),
            .init(id: "diagStream", group: .help, title: "交互流水（排障）", detail: "与门锁的原始 TX/RX 帧头，可复制发给开发者",
                  symbol: "waveform.path", tint: V.C.text3,
                  value: "\(diagLineCount) 行", action: { showDiagStream = true }),
            .init(id: "about", group: .help, title: "关于", detail: "版本与构建",
                  symbol: "info.circle", tint: V.C.text3, value: SettingsFacts.version, dest: .about)
        ]
    }

    /// 只显示当前真的该出现的行（通知权限只在被拒/未询问时出现）。
    private var visibleEntries: [SettingsEntry] {
        entries.filter { $0.id != "notify" || (notifyOff && !notifyLabel.isEmpty) }
    }

    /// 搜索索引 = 同一份清单里"能点/能做"的行，不再单独维护第二份文案。
    private var settingsHits: [SettingsEntry] {
        visibleEntries.filter { $0.dest != nil || $0.action != nil }
    }

    @ViewBuilder
    private var searchResults: some View {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let hits = settingsHits.filter { hit in
            (groupFilter == nil || hit.group == groupFilter)
                && (hit.title.lowercased().contains(q) || hit.detail.lowercased().contains(q))
        }
        if hits.isEmpty {
            Section {
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
                .listRowInsets(EdgeInsets(top: 0, leading: V.S.pageGutter, bottom: 0, trailing: V.S.pageGutter))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } header: {
                Text("搜索结果")
            }
        } else {
            Section {
                ForEach(hits) { hit in
                    settingsRow(hit)
                }
            } header: {
                Text("搜索结果 · \(hits.count) 项")
                .textCase(nil)
            }
        }
    }

    // MARK: - 锁状态双卡

    /// 信号读数走全仓唯一口径 `Reading.signal`（dBm + 档位词）。
    /// 旧实现按 `lock.signal`（0…4 档位）自己映射成「弱/中/强/满」，与门页/锁实况的 dBm 是两套说法；
    /// 现在三处同一份文字。
    private var signalReading: Reading.Value {
        guard app.lock != nil else { return Reading.Value(text: "--", tone: .neutral) }
        return Reading.signal(app.currentMac)
    }

    /// 固件读数走 `Reading.firmware`（空串 = 该固件不报这一项，显示「未上报」而不是空白）。
    private var firmwareReading: Reading.Value {
        guard app.lock != nil else { return Reading.Value(text: "--", tone: .neutral) }
        return Reading.firmware(app.currentMac)
    }

    /// 电量读数走全仓唯一口径 Reading.battery（与门页/锁实况/电池档案同一处算），不直读 lock.battery。
    private var batteryReading: String {
        guard app.lock != nil else { return "--" }
        return Reading.battery(app.currentMac, snapshot: DB.readStatus(app.currentMac)?.powerLevel ?? -1).spoken
    }

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
                    }
                    Text(Reading.link(app.currentMac).text)
                        .font(V.F.section)
                        .foregroundStyle(V.C.text1)
                    // 固件只在右边那张卡里出现一次（旧实现两张卡都写固件，同一个值看两遍）。
                    // 信号文字含 dBm 与档位词，与门页/锁实况同一份（Reading.signal）。
                    Text("信号 " + signalReading.spoken)
                        .font(V.F.footnote)
                        .foregroundStyle(signalReading.tone == .attention ? V.C.warning : V.C.text3)
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
                    }
                    Text(firmwareReading.text)
                        .font(V.F.section)
                        .foregroundStyle(V.C.text1)
                    Text("当前版本")
                        .font(V.F.footnote)
                        .foregroundStyle(V.C.text3)
                }
                .frame(minHeight: V.Metric.miniCardH / 2, alignment: .top)
            }
        }
    }

    // MARK: - 分组（VCard + VListRow，全部从 entries 派生）

    @ViewBuilder
    private func section(_ title: String, group: SettingsGroup) -> some View {
        let rows = visibleEntries.filter { $0.group == group }
        if groupFilter == nil || groupFilter == group, !rows.isEmpty {
            Section {
                ForEach(rows) { row in
                    settingsRow(row)
                }
            } header: {
                Text(title)
            }
        }
    }

    /// 一行设置：行渲染与搜索命中行共用同一个实现。
    @ViewBuilder
    private func settingsRow(_ e: SettingsEntry) -> some View {
        VListRow(title: e.title, detail: e.detail, systemImage: e.symbol, tint: e.tint, value: e.value) {
            if let dest = e.dest {
                router.request(.dest(dest))
            } else {
                e.action?()
            }
        }
    }

    private var lockSection: some View {
        section("门锁", group: .daily)
    }

    /// 安全组比别的组多一行「只读试验模式」开关（它不是跳转行，没有 Dest）。
    @ViewBuilder
    private var securitySection: some View {
        let rows = visibleEntries.filter { $0.group == .keys }
        if groupFilter == nil || groupFilter == .keys, !rows.isEmpty {
            Section {
                ForEach(rows) { row in
                    settingsRow(row)
                }
                VToggleRow(
                    title: "只读试验模式",
                    detail: "真机排障用：所有写入类命令停用，只看不改。关掉 App 也不会自动恢复 —— 记得回来关。",
                    isOn: trialGuardBinding(app)
                )
            } header: {
                Text("安全")
            }
        }
    }

    private var lookSection: some View {
        section("外观与时间", group: .look)
    }

    private var dataSection: some View {
        section("数据与硬件", group: .data)
    }

    /// 帮助组（原 SettingsGroups 的 help 档）：协议测试、交互流水与关于。
    private var helpSection: some View {
        section("帮助", group: .help)
    }

    /// 分组 chip 的浏览态判据（搜索态由 searchResults 自己按 hit.group 过滤）。
    private func inGroup(_ group: SettingsGroup) -> Bool {
        groupFilter == nil || groupFilter == group
    }

    /// 备份工作室行右侧读数：**真实 .json 份数**（旧实现读 kf_bk_keep = 保留份数设置，不是文件数）。
    private var backupFileCount: Int {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: BackupStudio.dir, includingPropertiesForKeys: nil) else { return 0 }
        return urls.filter { $0.pathExtension == "json" }.count
    }

    /// 固件升级行右侧读数：走 `Reading.firmware`（读不到写「未上报」，不留空白）。
    /// 与上面那张固件卡同一份文字 —— 旧实现这里是「未读到」、卡片里是「--」，同一件事两种说法。
    private var pkgVersion: String {
        guard app.lock != nil else { return "未添加" }
        return firmwareReading.text
    }

    private var deleteSection: some View {
        Section {
            VStack(alignment: .leading, spacing: V.S.gapM) {
                Button {
                    deleteRequested = true
                } label: {
                    Text("删除这台锁的本机数据")
                        .font(V.F.bodyStrong)
                        .foregroundStyle(V.C.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: V.List.rowMinHeight)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除这台锁的本机数据")
                // 2026-11-01（Round 283）：原文案写「未做备份则无法找回」，暗示"做过备份就安全" ——
                // 但 `DB.removeDevice` 会调 `BackupStudio.purgeLocalArtifacts`，把**本机备份文件与还原点
                // 一并删掉**（备份是整库包，里面含这把锁的母钥，留着等于没删干净，SEC-19）。
                // 用户"先备份再删锁"会连备份一起丢 —— 必须说清，并给出真正的留档办法。
                Text("只删本机：锁端密钥与锁内日志不变，重配即可再添加。注意：本机的备份文件与还原点也会一并删除（备份里含这把锁的母钥）；想留档请先把备份导出到别处（WebDAV 或复制文本）。")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("这台锁的本地数据")
        }
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
                            VStatPair(items: [
                                ("凭证", "\(app.keys.count) 枚"),
                                ("记录缓存", "\(app.entries.count) 条"),
                                ("本机密码", SettingsStore.shared.hasPasscode ? "已设" : "未设")
                            ])
                            // 同上：备份文件会被这次删除一并清掉，不能暗示"有备份就安全"。
                            Text("删除后本机的密码台账与缓存记录无法找回；本机的备份文件与还原点也会一并删除"
                                 + "（备份里含这把锁的母钥，留着等于没删干净）。"
                                 + "想留档请先把备份导出到别处（WebDAV 或复制文本）。锁本身不需要重置，可以再次添加。")
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
                            Divider()
                            VActionButton(title: "删除本机数据", systemImage: "trash", tint: V.C.red) {
                                deleteLocalData()
                                dismiss()
                            }
                            .disabled(!canDelete)
                            .opacity(canDelete ? 1 : 0.4)
                            VActionButton(title: "取消", systemImage: "xmark") { dismiss() }
                        }
                    }
                }
                .padding(V.S.pageGutterC)
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
