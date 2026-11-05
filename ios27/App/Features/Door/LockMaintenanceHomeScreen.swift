// LockMaintenanceHomeScreen.swift —— 锁维护（02 分册 IA 归并 · 新页）
//
// 按 _plan/02-信息架构与功能归并.md §3.1，把四个降为段的 Dest 收进一张页：
//   网关（← gateway / GatewayHomeScreen）· 固件（← dfu / DFUHomeScreen）
//   电池（← batteryProfile / BatteryProfileHomeScreen）· 名片（← deviceInfo / DeviceInfoHomeScreen）
// 能力守恒：四个来源页的全部真链路函数（HardwareService 配网/刷新/重启、FirmwareKit 解包+降级闸、
// DFUSession 刷写、BatteryCare 采样、LockArchive 电池档案、LockService 读取与自动校时）逐条搬入，
// 全部状态分支（空 / 忙 / 失败 / 空壳 / 只读 / 危险确认）与用户文案的因果原样保留。
import SwiftUI
import UniformTypeIdentifiers

struct LockMaintenanceHomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    // MARK: - 网关段状态（源自 GatewayHomeScreen）

    private struct GatewayRowVM: Identifiable, Equatable {
        let id: String
        let name: String
        let mac: String
        var rom: String
        var ssid: String
        var online: Bool
        var lastCheckedAt: Int64?
        var rebooting: Bool = false
    }

    /// 配网五步。编号是真序列。
    private enum ProvisionPhase: Equatable {
        case idle
        case running(step: Int)
        case failed(String)
        case succeeded

        var isRunning: Bool {
            if case .running = self { return true }
            return false
        }
    }

    @State private var gwRows: [GatewayRowVM] = []
    @State private var gwPhase: ProvisionPhase = .idle
    @State private var gwSteps: [String] = []
    @State private var gwSsid = ""
    @State private var gwPwd = ""
    @State private var gwShowProvision = false
    @State private var gwArmed = false
    @State private var gwConfirmDelete: GatewayRowVM?
    @State private var gwRebootTarget: GatewayRowVM?
    @State private var gwBanner: String?
    @State private var gwBannerOK = true

    private static let gwStepTitles = ["连网关", "读设备名", "写 WiFi", "写 IoT", "重启上线"]

    // MARK: - 固件段状态（源自 DFUHomeScreen）

    private enum DFUPhase: Equatable {
        case idle
        case ready
        case running
        case done
        case failed
    }

    @State private var pkg: FirmwarePackage?
    @State private var fileName = ""
    @State private var dfuError = ""
    @State private var dfuPhase: DFUPhase = .idle
    @State private var askStart = false
    @State private var dfuProgress: Double = 0
    @State private var stateText = ""
    @State private var importing = false

    // MARK: - 电池段状态（源自 BatteryProfileHomeScreen）

    @State private var batteryModel = ""
    @State private var changedAt = Date()
    @State private var hasChangedAt = false
    @State private var threshold = 15
    @State private var batteryLoaded = false
    @State private var batteryOutcome: String?

    // MARK: - 名片段状态（源自 DeviceInfoHomeScreen）

    @State private var status: LockStatus?
    @State private var samples: [BattSample] = []
    @State private var clockDrift: Int?
    @State private var infoBusy = false
    @State private var infoOutcome: String?
    @State private var infoOutcomeIsFailure = false
    @State private var readError: String?
    @State private var syncError: String?
    @State private var infoBatteryModel = ""
    @State private var batterySaved = false
    @State private var batteryNote: String?
    @State private var expandedSection: String?

    private func openPendingSection() {
        guard case .dest(let dest) = router.pending else { return }
        switch dest {
        case .gateway: expandedSection = "gateway"
        case .dfu: expandedSection = "dfu"
        case .batteryProfile: expandedSection = "battery"
        case .deviceInfo: expandedSection = "info"
        default: break
        }
    }

    private var mac: String { app.lock?.id ?? "" }
    private var kc: Keychain? { app.currentKeychain }
    private var meta: LockMeta { LockArchive.meta(mac) }
    private var decoyed: Bool { DB.isDecoy }
    private var readOnly: Bool { app.trialGuard }

    private var onlineCount: Int { gwRows.filter { $0.online }.count }
    private var batterySamples: [BattSample] { BatteryCare.samples(mac) }
    private var pct: Int { BatteryCare.displayPct(mac, snapshot: DB.readStatus(mac)?.powerLevel ?? -1) }
    private var tier: BatteryCare.Tier { BatteryCare.tier(pct) }

    // MARK: - 判断句与副文

    private var judgement: String {
        if decoyed { return "空壳模式下不显示锁维护" }
        guard app.lock != nil else { return "还没有门锁可维护" }
        if dfuPhase == .running { return "正在刷写固件 · 不要离开这一页" }
        if gwPhase.isRunning { return "正在给网关配网" }
        return BatteryCare.faceText(pct) + " · " + firmwareText
    }

    private var lead: String {
        if decoyed {
            return "空壳模式只隐藏数据，不改动数据。固件刷写、网关配网与档案写入在空壳里全部停用。"
        }
        guard let lock = app.lock else {
            return "锁维护读的是具体一把锁的硬件：固件、电池、网关与名片。先添加门锁，再回这一页。"
        }
        return lock.name + " · 硬件动作都在这一页：固件刷写会真的改锁，网关配网会写网关硬件。"
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            if decoyed || app.lock == nil {
                EmptyView()
            } else {
                chipRow
            }
        } content: {
            if decoyed {
                decoyCard
            } else if app.lock == nil {
                VEmpty(
                    title: "添加一把门锁",
                    reason: "固件、电池、网关与名片都挂在具体一把锁上。先添加门锁，再回这一页。",
                    actionTitle: "添加门锁"
                ) { router.request(.dest(.addLock)) }
            } else {
                if let gwBanner { gwBannerCard(gwBanner) }
                gatewaySection
                firmwareSection
                batterySection
                infoSection
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        // 2026-11-05（全技能审核 · 合并页落点）：从设置索引点「锁信息名片 / 网关 / 固件 / 电池」
        // 时，本来都会落到这一页顶部且四段全折叠 —— 用户以为点错了。这里消费路由上下文，
        // 打开对应段。
        .onAppear { openPendingSection() }
        .onChange(of: router.pending) { _, _ in openPendingSection() }
        .task(id: app.currentMac) {
            loadBattery()
            infoBatteryModel = meta.batteryModel
            loadGwRows()
            await reloadInfo()
        }
        // 2026-11-05 (adversarial review): switching the current lock cleared nothing -
        // batteryLoaded kept the battery section showing the previous lock model and date.
        .onChange(of: app.currentMac) { _, _ in batteryLoaded = false }
        .interactiveDismissDisabled(dfuPhase == .running)
        .navigationBarBackButtonHidden(dfuPhase == .running)
        .toolbarVisibility(dfuPhase == .running ? .hidden : .visible, for: .navigationBar)
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.zip, .data],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .v8Confirm(
            isPresented: $askStart,
            title: "开始刷写固件？",
            consequence: "刷写一旦开始无法取消；中途失败锁会停在升级模式，那时无法开门，必须回到本页重刷到成功为止。刷写会覆盖锁内固件，本页不提供回滚。",
            confirmTitle: "开始升级",
            isDestructive: true
        ) {
            confirmStart()
        }
        .v8Confirm(
            isPresented: Binding(
                get: { gwConfirmDelete != nil },
                set: { if !$0 { gwConfirmDelete = nil } }
            ),
            title: "删除这个网关？",
            consequence: "只从本机台账里移除这条记录，网关硬件里的 WiFi 与 IoT 凭据还在。本机记录删除后无法恢复，要重配得先把它重置回橙灯。",
            confirmTitle: "删除记录",
            isDestructive: true
        ) {
            if let g = gwConfirmDelete {
                gwConfirmDelete = nil
                gwRemove(g)
            }
        }
        .v8Confirm(
            isPresented: Binding(
                get: { gwRebootTarget != nil },
                set: { if !$0 { gwRebootTarget = nil } }
            ),
            title: "重启这个网关？",
            consequence: "重启期间网关会短暂离线 —— 如果你在外面靠它远程看门，这段时间会连不上。重启不会改配置，稍后刷新即可恢复。",
            confirmTitle: "重启",
            isDestructive: true
        ) {
            if let g = gwRebootTarget {
                gwRebootTarget = nil
                Task { await gwReboot(g) }
            }
        }
    }

    // MARK: - 芯片行

    private var chipRow: some View {
        VHScroll {
            HStack(spacing: V8.S.gapChip) {
                VChip2(icon: .glyph("cpu"), label: "固件", value: firmwareText)
                VChip2(icon: .ring(batteryFraction, batteryTint), label: "电池", value: batteryChipText)
                VChip2(icon: .glyph("antenna.radiowaves.left.and.right"), label: "网关", value: gwRows.isEmpty ? "未添加" : String(onlineCount) + "/" + String(gwRows.count) + " 在线")
                VChip2(icon: .glyph("chart.bar.fill"), label: "采样点", value: String(samples.count) + " 个")
            }
            .padding(.leading, V8.S.gutterCard)
            .padding(.trailing, V8.S.gutterCard)
        }
        .scrollClipDisabled()
    }

    private var batteryFraction: Double {
        let p = BatteryCare.displayPct(mac, snapshot: status?.powerLevel ?? DB.readStatus(mac)?.powerLevel ?? -1)
        return p < 0 ? 0.02 : min(1, max(0.02, Double(p) / 100))
    }

    private var batteryTint: Color {
        let p = BatteryCare.displayPct(mac, snapshot: status?.powerLevel ?? DB.readStatus(mac)?.powerLevel ?? -1)
        return p >= 0 && p <= 20 ? V8.C.warn : V8.C.ok
    }

    private var batteryChipText: String {
        let p = BatteryCare.displayPct(mac, snapshot: status?.powerLevel ?? DB.readStatus(mac)?.powerLevel ?? -1)
        return p < 0 ? "未采样" : BatteryCare.faceText(p)
    }

    private var firmwareText: String {
        if let fw = status?.firmware, !fw.isEmpty { return fw }
        if let fw = app.lock?.firmware, !fw.isEmpty { return fw }
        if let fw = kc?.fw, !fw.isEmpty { return fw }
        return "未读到"
    }

    // MARK: - 段折叠头（四个段共用）

    private func sectionHeader(_ eyebrow: String, _ key: String, _ statement: String, trailing: String? = nil) -> some View {
        Button {
            expandedSection = expandedSection == key ? nil : key
        } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: V8.S.gapXS) {
                    Text(eyebrow)
                    .font(V8.T.label)
                    .foregroundStyle(V8.C.ink4)
                    Text(statement)
                        .font(V8.T.headline)
                        .foregroundStyle(V8.C.ink1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if let trailing {
                    Text(trailing)
                    .font(V8.T.label)
                    .foregroundStyle(V8.C.ink4)
                        .monospacedDigit()
                }
                Image(systemName: expandedSection == key ? "chevron.up" : "chevron.down")
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: V8.H.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(V8PressStyle())
        .accessibilityLabel(eyebrow + "：" + statement + (expandedSection == key ? "，已展开" : "，已收起"))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - 空壳

    private var decoyCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "锁维护", statement: "空壳模式只读")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("空壳模式（胁迫码进入）下，锁内固件、电池档案、网关台账与锁信息名片都不显示。固件刷写与网关配网会真的改硬件，档案写入会用空档案覆盖真实数据，这里一并停掉。")
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink3)
                .lineSpacing(V8.L.body - V8.T.body.size)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Text("退出空壳请在本机密码界面输入正常密码。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 段 1 网关（源自 GatewayHomeScreen，能力与文案逐条保留）

    private var gatewaySection: some View {
        VCard2 {
            sectionHeader(
                "网关",
                "gateway",
                gwPhase.isRunning ? "正在配网 · 请勿断电" : (gwRows.isEmpty ? "还没有添加网关" : String(gwRows.count) + " 台 · " + String(onlineCount) + " 台在线"),
                trailing: gwPhaseWord
            )
            if expandedSection == "gateway" {
                VDivider2()
                    .padding(.top, V8.S.gapM)
                Text("网关只接收门锁状态与告警，不能远程开门；配网会改写网关里的 WiFi 与 IoT 凭据。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
                gwListBlock
                if gwShowProvision || gwPhase != .idle {
                    gwProvisionBlock
                }
                VStack(alignment: .leading, spacing: V8.S.gapS) {
                    Text("网关能做什么 · 只收状态与告警")
                    .font(V8.T.label)
                    .foregroundStyle(V8.C.ink4)
                    VStack(alignment: .leading, spacing: V8.S.gapS) {
                        Text("· 建议离门锁不超过五米，中间不要有承重墙阻隔。")
                        Text("· 无需和门锁配对；配网时 IoT 凭据随 WiFi 一起写进网关。")
                        Text("· 只能接收门锁状态与告警，无法远程操作门锁 —— 开门永远只在门口发生。")
                    }
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, V8.S.gapM)
            }
        }
    }

    private var gwPhaseWord: String {
        switch gwPhase {
        case .idle: return gwShowProvision ? "待开始" : "—"
        case .running(let step): return "第 " + String(step + 1) + " / 5 步"
        case .failed: return "失败"
        case .succeeded: return "已接受"
        }
    }

    @ViewBuilder
    private var gwListBlock: some View {
        if gwRows.isEmpty {
            if gwShowProvision || gwPhase != .idle {
                VCard2(style: .well) {
                    Text("还没有已配好的网关。走完下面五步，这台网关就会出现在这里。")
                        .font(V8.T.footnote)
                        .foregroundStyle(V8.C.ink3)
                        .frame(minHeight: V8.H.min)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VCard2(style: .well) {
                    VCardHead(eyebrow: "还没有添加网关", statement: "先通电，再配网")
                    Text("先把网关通电、捅一下重置孔到橙灯闪烁，再点下面的「配网网关」走完五步。网关不是开锁的必需品：没有它也能开门，只是拿不到远程告警。")
                        .font(V8.T.footnote)
                        .foregroundStyle(V8.C.ink3)
                        .padding(.top, V8.S.gapM)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        gwOpenProvision()
                    } label: {
                        Text("配网网关")
                            .font(V8.T.tab)
                            .foregroundStyle(V8.C.chipOn)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: V8.H.min)
                            .background(Capsule(style: .continuous).fill(V8.C.accent))
                    }
                    .buttonStyle(V8PressStyle())
                    .padding(.top, V8.S.gapM)
                }
                .padding(.top, V8.S.gapM)
            }
        } else {
            VCard2(style: .well) {
                // 2026-11-05（值级重复）：trailing 原来是「N 台」，而顶部芯片「网关」已经给出「在线 M/N」。
                VCardHead(eyebrow: "我的网关", statement: "一行一台")
                VDivider2()
                    .padding(.top, V8.S.gapM)
                VStack(spacing: 0) {
                    ForEach(Array(gwRows.enumerated()), id: \.element.id) { index, g in
                        if index > 0 { VDivider2() }
                        gwRow(g)
                    }
                }
                .padding(.top, V8.S.gapS)
            }
            .padding(.top, V8.S.gapM)
        }
    }

    private func gwRow(_ g: GatewayRowVM) -> some View {
        VStack(alignment: .leading, spacing: V8.S.gapS) {
            HStack(spacing: V8.S.gapS) {
                Text(g.name)
                    .font(V8.T.value)
                    .foregroundStyle(V8.C.ink1)
                    .lineLimit(1)
                Text(g.rebooting ? "重启中" : (g.online ? "已联网" : "未联网"))
                    .font(V8.T.caption)
                    .foregroundStyle(g.online && !g.rebooting ? V8.C.ink3 : V8.C.warn)
                Spacer(minLength: 0)
            }
            VStack(spacing: 0) {
                VDataRow(tag: "ROM", tagTint: V8.C.ink4, title: "固件版本", value: g.rom.isEmpty ? "—" : g.rom)
                VDotRule()
                VDataRow(tag: "WiFi", tagTint: V8.C.ink4, title: "当前网络", value: g.ssid.isEmpty ? "—" : g.ssid)
                VDotRule()
                VDataRow(tag: "核对", tagTint: V8.C.ink4, title: "上次核对", value: g.lastCheckedAt.map { TimeDisplay.clock($0) } ?? "—")
            }
            .padding(.top, V8.S.gapXS)
            HStack(spacing: V8.S.gapL) {
                Button("刷新状态") { Task { await gwRefresh(g) } }
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.accent)
                Button("重启网关") { gwRebootTarget = g }
                    .font(V8.T.caption)
                    .foregroundStyle(readOnly ? V8.C.ink4 : V8.C.accent)
                    .disabled(readOnly)
                Button("删除记录") { gwConfirmDelete = g }
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.danger)
                Spacer(minLength: 0)
            }
            .frame(minHeight: V8.H.min)
        }
        .frame(minHeight: V8.H.min)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(g.name + "，" + DB.shortMac(g.mac) + "，" + (g.online ? "已联网" : "未联网") + "，ROM " + g.rom + "，WiFi " + g.ssid)
        .accessibilityAction(named: "刷新状态") { Task { await gwRefresh(g) } }
        .accessibilityAction(named: "重启网关") { Task { await gwReboot(g) } }
    }

    // MARK: - 网关配网（五步真序列）

    private var gwProvisionBlock: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "配网网关", statement: gwPhase.isRunning ? "写入中 · 请勿断电" : "五步", trailing: "2.4GHz")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("接通电源 → 捅重置孔约 5 秒 → 指示灯变橙 → 点开始。写入过程中网关会重启并清空原有网络配置。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(isOn: $gwArmed) {
                Text("橙灯闪烁中")
                    .font(V8.T.body)
                    .foregroundStyle(V8.C.ink1)
            }
            .tint(V8.C.accent)
            .frame(minHeight: V8.H.min)
            .accessibilityLabel("网关指示灯已变橙")
            .padding(.top, V8.S.gapS)
            TextField("WiFi 名称（只支持 2.4GHz）", text: $gwSsid)
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink1)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .frame(minHeight: V8.H.min)
                .padding(.horizontal, V8.S.gapM)
                .background(V8.C.card, in: .rect(cornerRadius: V8.R.inset))
                .padding(.top, V8.S.gapM)
            SecureField("WiFi 密码", text: $gwPwd)
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink1)
                .submitLabel(.done)
                .frame(minHeight: V8.H.min)
                .padding(.horizontal, V8.S.gapM)
                .background(V8.C.card, in: .rect(cornerRadius: V8.R.inset))
                .padding(.top, V8.S.gapM)
            Text("iOS 不允许 App 读当前 WiFi 名，请手动输入；要换网先去「设置 → Wi-Fi」连上目标网络再回来。")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
            VDivider2()
                .padding(.vertical, V8.S.gapM)
            gwLadder
            if case .failed(let reason) = gwPhase {
                VFailure(
                    what: "配网没有完成",
                    why: reason,
                    next: "确认网关橙灯闪烁、WiFi 名称与密码无误且是 2.4GHz 网络，再点重试。"
                ) {
                    Task { await gwProvision() }
                }
                .padding(.top, V8.S.gapM)
            } else if gwPhase == .succeeded {
                Text("指令已被网关接受 · 联网状态稍后在这里复核")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ok)
                    .padding(.top, V8.S.gapM)
            }
            if gwPhase.isRunning {
                VBusy(text: "正在写入，请勿断电")
                    .padding(.top, V8.S.gapM)
            } else {
                Button {
                    Task { await gwProvision() }
                } label: {
                    Text("开始配网")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.chipOn)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.accent))
                }
                .buttonStyle(V8PressStyle())
                .disabled(!gwCanProvision || readOnly)
                .opacity((gwCanProvision && !readOnly) ? 1 : 0.45)
                .padding(.top, V8.S.gapM)
                if !gwCanProvision {
                    Text("要先勾上「橙灯闪烁中」，并填好 WiFi 名称与密码。")
                        .font(V8.T.caption)
                        .foregroundStyle(V8.C.ink4)
                        .padding(.top, V8.S.gapS)
                }
                if readOnly {
                    Text(TrialCopy.blocked("配网与重启都"))
                        .font(V8.T.caption)
                        .foregroundStyle(V8.C.warn)
                        .padding(.top, V8.S.gapS)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var gwCanProvision: Bool {
        gwArmed
            && !gwSsid.trimmingCharacters(in: .whitespaces).isEmpty
            && !gwPwd.isEmpty
    }

    private var gwCurrentStep: Int {
        if case .running(let step) = gwPhase { return step }
        return gwPhase == .succeeded ? 4 : 0
    }

    private var gwLadder: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.gwStepTitles.enumerated()), id: \.offset) { index, title in
                if index > 0 { VDotRule() }
                VDataRow(
                    tag: DF.pad2(index + 1),
                    tagTint: gwStepReached(index) ? V8.C.ink3 : V8.C.ink4,
                    title: title,
                    value: gwStepWord(index)
                )
            }
            if !gwSteps.isEmpty {
                VDivider2()
                    .padding(.top, V8.S.gapS)
                VStack(alignment: .leading, spacing: V8.S.gapXS) {
                    ForEach(Array(gwSteps.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(V8.T.caption)
                            .foregroundStyle(V8.C.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, V8.S.gapS)
            }
        }
    }

    private func gwStepReached(_ index: Int) -> Bool {
        gwPhase != .idle && index <= gwCurrentStep
    }

    private func gwStepWord(_ index: Int) -> String {
        if index < gwCurrentStep || gwPhase == .succeeded { return "已完成" }
        if index == gwCurrentStep && gwPhase.isRunning { return "进行中" }
        return "待"
    }

    @ViewBuilder
    private func gwBannerCard(_ text: String) -> some View {
        if gwBannerOK {
            VCard2(style: .well) {
                Text(text)
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VFailure(
                what: "网关操作没有完成",
                why: text,
                next: "确认手机靠近网关、指示灯状态正确，再重试。"
            )
        }
    }

    // MARK: - 段 2 固件（源自 DFUHomeScreen，能力与文案逐条保留）

    private var firmwareSection: some View {
        VCard2 {
            sectionHeader(
                "固件",
                "dfu",
                dfuPhase == .running ? "正在刷写" : (pkg == nil ? "锁内固件 " + firmwareText : "包已就绪 · " + (pkg?.version ?? "版本未识别")),
                trailing: dfuPhaseWord
            )
            if expandedSection == "dfu" {
                VDivider2()
                    .padding(.top, V8.S.gapM)
                VStack(spacing: 0) {
                    VDataRow(tag: "锁内", tagTint: V8.C.ink4, title: "锁内固件", value: firmwareText)
                    VDotRule()
                    VDataRow(tag: "包内", tagTint: dfuVersionTint, title: "包内版本", value: pkg?.version ?? "未识别")
                }
                .padding(.top, V8.S.gapS)
                Text("本机离线，只能比对本地包与锁内版本；原版的服务端版本检查在离线版没有对应物。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
                if dfuPhase == .running {
                    VBusy(text: "升级进行中 · 请保持手机靠近门锁、不要切后台")
                        .padding(.top, V8.S.gapM)
                    ProgressView(value: dfuProgress)
                        .tint(V8.C.accent)
                        .padding(.top, V8.S.gapS)
                    Text(String(Int(dfuProgress * 100)) + "% · " + stateText)
                        .font(V8.T.footnote)
                        .foregroundStyle(V8.C.ink3)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("固件升级进度")
                        .accessibilityValue(String(Int(dfuProgress * 100)) + "%，" + stateText)
                        .padding(.top, V8.S.gapS)
                } else {
                    Button {
                        importing = true
                    } label: {
                        Text(pkg == nil ? "选择固件包 (.zip)" : "重新选择固件包")
                            .font(V8.T.tab)
                            .foregroundStyle(V8.C.chipOn)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: V8.H.min)
                            .background(Capsule(style: .continuous).fill(V8.C.accent))
                    }
                    .buttonStyle(V8PressStyle())
                    .disabled(readOnly)
                    .opacity(readOnly ? 0.45 : 1)
                    .padding(.top, V8.S.gapM)
                    if let p = pkg {
                        VCard2(style: .well) {
                            // 2026-11-05（对抗审查 · 设计冗余）：包版本在本段已经出现两次 ——
                            // 段标题「包已就绪 · <版本>」与数据行「包内版本」。这里再报一遍是第三次。
                            // 卡头改成描述「包内有什么」，版本由上面两处唯一承载。
                            VCardHead(eyebrow: "包内容", statement: "三类文件", trailing: p.sourceName)
                            VStack(spacing: 0) {
                                VDataRow(tag: "主体", tagTint: V8.C.ink4, title: "固件主体", value: String(p.binSize), unit: "B")
                                VDotRule()
                                VDataRow(tag: "init", tagTint: V8.C.ink4, title: "init packet", value: String(p.datSize), unit: "B")
                                VDotRule()
                                VDataRow(tag: "版本", tagTint: V8.C.ink4, title: "包内版本", value: p.version ?? "未识别")
                            }
                            .padding(.top, V8.S.gapS)
                        }
                        .padding(.top, V8.S.gapM)
                        Button {
                            askStart = true
                        } label: {
                            Text(dfuPhase == .done ? "再次升级" : "开始升级")
                                .font(V8.T.tab)
                                .foregroundStyle(V8.C.chipOn)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: V8.H.min)
                                .background(Capsule(style: .continuous).fill(V8.C.accent))
                        }
                        .buttonStyle(V8PressStyle())
                        .disabled(readOnly)
                        .opacity(readOnly ? 0.4 : 1)
                        .padding(.top, V8.S.gapM)
                    }
                    if dfuPhase == .done {
                        Text("升级完成。请回锁实况读一次，确认版本已变化。")
                            .font(V8.T.footnote)
                            .foregroundStyle(V8.C.ok)
                            .padding(.top, V8.S.gapS)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if dfuPhase == .failed {
                        VFailure(
                            what: "升级没有完成",
                            why: dfuError.isEmpty ? "刷写链中途失败，具体原因没有回报。" : dfuError,
                            next: "锁很可能仍停在升级模式 —— 此时无法开门。请保持手机靠近门锁，回到本页再点重试；若反复失败，换一部手机或用厂商工具重刷。"
                        ) {
                            importing = true
                        }
                        .padding(.top, V8.S.gapM)
                    }
                    Text("包内需要 manifest.json + bin + dat；解包后逐项校验 CRC 与尺寸。本仓没有厂商签名校验能力（锁内没有公钥），包的来源请自己确认。")
                        .font(V8.T.footnote)
                        .foregroundStyle(V8.C.ink3)
                        .padding(.top, V8.S.gapM)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("过程：校验包 → 让锁进升级模式（会断开连接，属预期）→ 连专用广播 → 传固件 → 校验。全程请保持手机靠近门锁、不要切后台。")
                        .font(V8.T.caption)
                        .foregroundStyle(V8.C.ink4)
                        .padding(.top, V8.S.gapM)
                        .fixedSize(horizontal: false, vertical: true)
                    if readOnly {
                        Text(TrialCopy.blocked("固件升级"))
                            .font(V8.T.caption)
                            .foregroundStyle(V8.C.warn)
                            .padding(.top, V8.S.gapS)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var dfuPhaseWord: String {
        switch dfuPhase {
        case .running: return "升级中"
        case .failed: return "失败"
        case .done: return "完成"
        case .idle, .ready: return pkg == nil ? "待选包" : "包已就绪"
        }
    }

    private var dfuVersionTint: Color {
        guard let target = pkg?.version else { return V8.C.ink4 }
        if FirmwareKit.versionLt(target, firmwareText) { return V8.C.danger }
        return V8.C.ok
    }

    // MARK: - 段 3 电池（源自 BatteryProfileHomeScreen，能力与文案逐条保留）

    private var batterySection: some View {
        VCard2 {
            sectionHeader(
                "电池",
                "battery",
                pct < 0 ? "还没采样" : BatteryCare.faceText(pct) + " · 五档 " + tier.label,
                trailing: String(batterySamples.count) + " 点"
            )
            if expandedSection == "battery" {
                VDivider2()
                    .padding(.top, V8.S.gapM)
                VStack(spacing: 0) {
                    VDataRow(tag: "最近采样", tagTint: V8.C.ink4, title: batterySampleTimeText, value: "")
                    VDotRule()
                    VDataRow(tag: "采样点数", tagTint: V8.C.ink4, title: String(batterySamples.count), value: "个")
                }
                .padding(.top, V8.S.gapS)
                Text("每次读锁状态自动追加一条，保留 90 天。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
                if batterySamples.count >= 2 {
                    VRangeCaption(text: "电量 % · 最近 " + String(batterySamples.count) + " 个采样")
                        .padding(.top, V8.S.gapM)
                    VSpark(values: batterySamples.suffix(24).map { Double($0.pct) }, tint: V8.C.okFill, cursor: nil, axis: .samples)
                        .padding(.top, V8.S.gapS)
                    Text(batteryTrendCaption)
                        .font(V8.T.footnote)
                        .foregroundStyle(V8.C.ink3)
                        .padding(.top, V8.S.gapS)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("还没有足够的采样点 —— 每次连接读一次状态，攒到 2 个点就能画出真实走势（不插值、不画假线）。")
                        .font(V8.T.footnote)
                        .foregroundStyle(V8.C.ink3)
                        .padding(.top, V8.S.gapM)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VDivider2()
                    .padding(.vertical, V8.S.gapM)
                VStack(alignment: .leading, spacing: V8.S.gapXS) {
                    Text("电池型号")
                    .font(V8.T.label)
                    .foregroundStyle(V8.C.ink4)
                    TextField("电池型号（如 CR123A × 2）", text: $batteryModel)
                        .font(V8.T.body)
                        .foregroundStyle(V8.C.ink1)
                        .frame(minHeight: V8.H.min)
                        .padding(.horizontal, V8.S.gapM)
                        .background(V8.C.well, in: .rect(cornerRadius: V8.R.inset))
                }
                Toggle(isOn: $hasChangedAt) {
                    VStack(alignment: .leading, spacing: V8.S.gapXS) {
                        Text("记录换电日期")
                            .font(V8.T.value)
                            .foregroundStyle(V8.C.ink1)
                        Text("换电池后回来更新，续航估算才有基准。")
                            .font(V8.T.caption)
                            .foregroundStyle(V8.C.ink4)
                    }
                }
                .frame(minHeight: V8.H.min)
                .padding(.top, V8.S.gapS)
                if hasChangedAt {
                    DatePicker("换电日期", selection: $changedAt, displayedComponents: .date)
                        .font(V8.T.body)
                        .frame(minHeight: V8.H.min)
                }
                Button { saveBattery() } label: {
                    Text("保存电池档案")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.chipOn)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.accent))
                }
                .buttonStyle(V8PressStyle())
                .padding(.top, V8.S.gapM)
                if let batteryOutcome {
                    Text(batteryOutcome)
                        .font(V8.T.footnote)
                        .foregroundStyle(batteryOutcome.hasPrefix("已") ? V8.C.ok : V8.C.danger)
                        .padding(.top, V8.S.gapS)
                }
                VDivider2()
                    .padding(.vertical, V8.S.gapM)
                VCard2(style: .well) {
                    VCardHead(eyebrow: "低电提醒", statement: "阈值 " + String(threshold) + "%")
                    VDivider2()
                        .padding(.top, V8.S.gapM)
                    HStack(spacing: V8.S.gapChip) {
                        ForEach([10, 15, 20], id: \.self) { value in
                            thresholdChip(value)
                        }
                    }
                    .padding(.top, V8.S.gapM)
                    // 2026-11-05（可折叠说明 · 第 2 处）：行为说明保留可见，口径表收进折叠 ——
                    // 档位边界是查表用的参考数据，选档之前不需要看。
                    Text("低于该电量时，本机发一条低电通知（每档只发一次，回电后重置）。")
                        .font(V8.T.footnote)
                        .foregroundStyle(V8.C.ink3)
                        .padding(.top, V8.S.gapM)
                        .fixedSize(horizontal: false, vertical: true)
                    VDisclosure(title: "五档口径") {
                        Text("0–10 空 / 11–20 低 / 21–35 低 / 36–60 中 / 61–80 高 / 81–100 满")
                    }
                    .padding(.top, V8.S.gapS)
                }
                .padding(.top, V8.S.gapM)
            }
        }
    }

    private var batterySampleTimeText: String {
        guard let last = batterySamples.last else { return "尚未采样" }
        return TimeFormat.ago(Int64(last.t))
    }

    private var batteryTrendCaption: String {
        let values = batterySamples.map(\.pct)
        let lo = values.min() ?? 0
        let hi = values.max() ?? 0
        let days = max(Int(((batterySamples.last?.t ?? 0) - (batterySamples.first?.t ?? 0)) / 86_400_000) + 1, 1)
        return "最近 " + String(batterySamples.count) + " 个采样点 · 跨 " + String(days) + " 天 · 最低 " + String(lo) + "% / 最高 " + String(hi) + "%"
    }

    private func thresholdChip(_ value: Int) -> some View {
        let selected = threshold == value
        return Button {
            threshold = value
            DB.store.set("kf_batt_threshold", value)
        } label: {
            Text(String(value) + "%")
                .font(V8.T.tab)
                .foregroundStyle(selected ? V8.C.chipOn : V8.C.ink1)
                .padding(.horizontal, V8.S.gapM)
                .frame(minHeight: V8.H.min)
                .background(Capsule(style: .continuous).fill(selected ? V8.C.okFill : V8.C.chipOff))
        }
        .buttonStyle(V8PressStyle())
        .accessibilityLabel("低电阈值 " + String(value) + "%")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - 段 4 名片（源自 DeviceInfoHomeScreen，能力与文案逐条保留）

    private var infoSection: some View {
        VCard2 {
            sectionHeader(
                "名片",
                "info",
                kc == nil ? "还没有门锁" : "「" + LockArchive.displayName(kc!) + "」",
                trailing: infoBusy ? "读取中" : nil
            )
            if expandedSection == "info" {
                VDivider2()
                    .padding(.top, V8.S.gapM)
                if let kc {
                    identityBlock(kc)
                    statusBlock
                }
                infoReloadBlock
            }
        }
    }

    private func identityBlock(_ kc: Keychain) -> some View {
        VStack(alignment: .leading, spacing: V8.S.gapS) {
            // 2026-11-05（对抗审查 · 设计冗余）：卡头 trailing 原来也写型号，而下面第一行就是
            // 「型号」—— 同一个值在卡头与首行各出现一次。型号由数据行承载，卡头只留名字。
            VCardHead(eyebrow: "身份", statement: LockArchive.displayName(kc))
            VStack(spacing: 0) {
                VDataRow(tag: "型号", tagTint: V8.C.ink4, title: PidMap.productName(kc.pid), value: "")
                VDotRule()
                VDataRow(tag: "固件", tagTint: V8.C.ink4, title: infoFirmwareText, value: "")
                VDotRule()
                VDataRow(tag: "Boot", tagTint: V8.C.ink4, title: bootText, value: "")
                VDotRule()
                VDataRow(tag: "键盘", tagTint: V8.C.ink4, title: keyboardText, value: "")
                VDotRule()
                VDataRow(tag: "固件服役", tagTint: V8.C.ink4, title: firmwareAge, value: "")
                VDotRule()
                VDataRow(tag: "MAC", tagTint: V8.C.ink4, title: kc.mac, value: "")
                VDotRule()
                VDataRow(tag: "绑定于", tagTint: V8.C.ink4, title: boundText, value: "")
                VDotRule()
                VDataRow(tag: "链路验证", tagTint: V8.C.ink4, title: verifiedText, value: "")
                VDotRule()
                VDataRow(tag: "锁钟偏差", tagTint: infoDriftTint, title: infoDriftText, value: "")
            }
            .padding(.top, V8.S.gapS)
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: V8.S.gapS) {
            VCardHead(eyebrow: "运行状态", statement: infoSampleTimeText)
            VStatPair2(items: [
                .init(label: "门锁电量", value: batteryChipText),
                .init(label: "安全模式", value: infoModeText)
            ])
            .padding(.top, V8.S.gapS)
            VStatPair2(items: [
                .init(label: "锁内时间", value: lockTimeText),
                .init(label: "信号", value: signalText)
            ])
            .padding(.top, V8.S.gapS)
            VStack(spacing: 0) {
                VDataRow(tag: "密码容量", tagTint: V8.C.ink4, title: pwdCapacityText, value: "")
                VDotRule()
                VDataRow(tag: "指纹容量", tagTint: V8.C.ink4, title: fpCapacityText, value: "")
                VDotRule()
                VDataRow(tag: "PIN 容量", tagTint: V8.C.ink4, title: pinCapacityText, value: "")
            }
            .padding(.top, V8.S.gapS)
            if let note = localPinNote {
                Text(note)
                    .font(V8.T.footnote)
                    .foregroundStyle(localPinMismatch ? V8.C.warn : V8.C.ink3)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Boot / 键盘版本只在锁上报时出现；缺失表示该固件不报这两支，不是读取失败。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var infoReloadBlock: some View {
        VStack(alignment: .leading, spacing: V8.S.gapS) {
            if infoBusy {
                VBusy(text: "正在与门锁通信…")
            } else if let readError {
                VFailure(
                    what: "读取锁信息失败",
                    why: readError,
                    next: "走近门锁、确认蓝牙开着，再点「重新读取」。",
                    retry: { Task { await reloadInfo() } }
                )
            } else if let syncError {
                VFailure(
                    what: "自动校时失败",
                    why: syncError,
                    next: "锁钟偏着会让临时码与时间窗凭证整段失效。到「锁设置」的校时入口手动同步一次，或再点「重新读取」。",
                    retry: { Task { await reloadInfo() } }
                )
            } else {
                Button {
                    Task { await reloadInfo() }
                } label: {
                    Text("重新读取")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.chipOn)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.accent))
                }
                .buttonStyle(V8PressStyle())
                .accessibilityLabel("重新读取锁信息")
                if let infoOutcome {
                    Text(infoOutcome)
                        .font(V8.T.footnote)
                        .foregroundStyle(infoOutcomeIsFailure ? V8.C.danger : V8.C.ok)
                        .padding(.top, V8.S.gapS)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("静音、安全模式、校时、防尾随与固件升级在「锁设置」里。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 名片读数

    private var infoFirmwareText: String {
        if let fw = status?.firmware, !fw.isEmpty { return fw }
        let f = kc?.fw ?? ""
        return f.isEmpty ? "未知" : f
    }

    private var bootText: String {
        let v = status?.verDFU ?? 0
        return v > 0 ? String(v) : "该固件未上报"
    }

    private var keyboardText: String {
        let v = status?.verKeyboard ?? 0
        return v > 0 ? String(v) : "该固件未上报"
    }

    private var firmwareAge: String {
        var fw = kc?.fw ?? ""
        if let f = status?.firmware, !f.isEmpty { fw = f }
        guard let since = BatteryCare.fwSince(mac, fw: fw) else { return "首次读到后起算" }
        let days = max(0, Int(Date().timeIntervalSince1970 * 1000 - since.at) / 86_400_000)
        if days == 0 { return "今天起算" }
        return days > 365 ? String(days) + " 天 · 已超一年" : String(days) + " 天"
    }

    private var boundText: String {
        // pairedAt 是 DF.iso() 写的 UTC 串，必须走本地化解析，不能 prefix 当本地时间。
        let s = DF.localMinute(fromISO: kc?.pairedAt ?? "")
        return s.isEmpty ? "—" : s
    }

    private var verifiedText: String {
        let t = meta.verifiedAt
        guard t > 0 else { return "待验证（成功开一次锁即打标）" }
        return "已验证 · " + DF.localShort(Date(timeIntervalSince1970: t))
    }

    private var infoDriftText: String {
        guard let d = clockDrift else { return "—" }
        if d == 0 { return "与手机一致" }
        return (d > 0 ? "+" : "") + String(d) + " 秒"
    }

    private var infoDriftTint: Color {
        guard let d = clockDrift else { return V8.C.ink4 }
        return abs(d) > 60 ? V8.C.warn : V8.C.ink4
    }

    private var infoModeText: String {
        guard let st = status else { return "—" }
        if st.verifyMode == 1 && st.broadcastMode != 0 { return "B · 双验" }
        if st.verifyMode == 1 { return "C · 广播+验证" }
        return "A · 单验"
    }

    private var lockTimeText: String {
        // 0 = 锁端没回时钟（不是 2010-01-01）；ProtoTime.localStr(0) 返回空串。
        guard let t = status?.lockTime, t > 0 else { return "—" }
        let s = ProtoTime.localStr(t)
        return s.isEmpty ? "—" : s
    }

    private var signalText: String {
        guard let r = DB.store.get(Int.self, "kf_linkrssi_" + mac) else { return "未测" }
        return String(r) + " dBm · " + LinkSenseModel.levelWord(LinkSenseModel.level(r))
    }

    private var infoSampleTimeText: String {
        let at = max(LockStats.snapAt(mac), samples.last?.t ?? 0)
        return at > 0 ? LockStats.sampleTimeText(at) : "尚未读取过快照"
    }

    private var liveStatus: LockStatus? { status }
    private var cachedStatus: StatusSnapshotData? { DB.readStatus(mac) }

    private var pwdUsed: Int {
        if let cap = liveStatus?.pwdInfoCapacity ?? cachedStatus?.pwdCap, cap > 0 {
            let stock = liveStatus?.pwdStock ?? cachedStatus?.pwdStock ?? 0
            return max(cap - stock, 0)
        }
        return DB.ledger(mac).pwds.count
    }

    private var fpUsed: Int {
        if let cap = liveStatus?.fpInfoCapacity ?? cachedStatus?.fpCap, cap > 0 {
            let stock = liveStatus?.fpStock ?? cachedStatus?.fpStock ?? 0
            return max(cap - stock, 0)
        }
        return DB.ledger(mac).fps.count
    }

    private var pinUsed: Int {
        if let cap = liveStatus?.pinInfoCapacity ?? cachedStatus?.pinCap, cap > 0 {
            let stock = liveStatus?.pinStock ?? cachedStatus?.pinStock ?? 0
            return max(cap - stock, 0)
        }
        return kc?.pins.count ?? 0
    }

    private var pwdCapacityText: String {
        capacityText(used: pwdUsed, cap: liveStatus?.pwdInfoCapacity ?? cachedStatus?.pwdCap ?? 0)
    }

    private var fpCapacityText: String {
        capacityText(used: fpUsed, cap: liveStatus?.fpInfoCapacity ?? cachedStatus?.fpCap ?? 0)
    }

    private var pinCapacityText: String {
        capacityText(used: pinUsed, cap: liveStatus?.pinInfoCapacity ?? cachedStatus?.pinCap ?? 0)
    }

    /// 容量读数两个数都要读成「已用 / 容量」；容量未读时只报已用，并说清容量确实没读到。
    private func capacityText(used: Int, cap: Int) -> String {
        cap > 0 ? String(max(used, 0)) + " / " + String(cap) : "已用 " + String(max(used, 0)) + " · 容量未读"
    }

    /// 本机钥匙串的 PIN 数与锁端存量的对照说明（不一致 = 池子污染 / 两台 App 打架）。
    private var localPinNote: String? {
        let local = kc?.pins.filter { !$0.isEmpty }.count ?? 0
        guard let stock = status?.pinStock, let cap = status?.pinInfoCapacity, cap > 0 else { return nil }
        let onLock = max(cap - stock, 0)
        if local == 0 { return "本机池为空" }
        if local == onLock { return "本机池 " + String(local) + " 枚 · 与锁端一致" }
        return "本机池 " + String(local) + " 枚 · 锁端已用 " + String(onLock) + " 枚 —— 不一致，现签凭证会被锁拒绝（凭证不在锁的名单里）"
    }

    private var localPinMismatch: Bool {
        let local = kc?.pins.filter { !$0.isEmpty }.count ?? 0
        guard let stock = status?.pinStock, let cap = status?.pinInfoCapacity, cap > 0 else { return false }
        return local != max(cap - stock, 0)
    }

    // MARK: - 网关真链路（源自 GatewayHomeScreen）

    private func gwOpenProvision() {
        gwShowProvision = true
        gwBanner = nil
    }

    private func loadGwRows() {
        guard !decoyed else { return }
        gwRows = DB.gateways().map { g in
            GatewayRowVM(id: g.mac,
                         name: g.name.isEmpty ? "智能网关 " + String(g.mac.prefix(4)) : g.name,
                         mac: g.mac,
                         rom: g.romVer,
                         ssid: g.ssid.isEmpty ? g.lastWifi : g.ssid,
                         online: g.netState == 1,
                         // 「上次核对」留空（显示「—」），真正的核对在 refresh() 里写。
                         lastCheckedAt: nil)
        }
    }

    @MainActor
    private func gwProvision() async {
        guard gwCanProvision, !gwPhase.isRunning, !decoyed, !readOnly else { return }
        gwBanner = nil
        gwSteps = []
        let sentSsid = gwSsid
        // 网关只支持 2.4GHz。名字里带 5G 的网段几乎一定是 5GHz —— 先拦下，别写进硬件再失败。
        if sentSsid.uppercased().contains("5G") {
            gwPhase = .failed("「" + sentSsid + "」看起来是 5GHz 网络。网关只支持 2.4GHz，请换成路由器 2.4GHz 那个 SSID 再试。")
            return
        }
        gwPhase = .running(step: 0)
        do {
            // 真链路：扫描网关 → 状态 → 写 WiFi → 重启 → 落库（HardwareService）。
            let rec = try await HardwareService.shared.provisionGateway(ssid: sentSsid, password: gwPwd) { msg in
                Task { @MainActor in self.gwSteps.append(self.cleanStep(msg)) }
            }
            gwSsid = ""
            gwPwd = ""
            gwArmed = false
            gwPhase = .succeeded
            loadGwRows()
            gwBannerOK = true
            gwBanner = "配网指令已被网关接受（" + rec.lastWifi + "）。它正在用新 WiFi 重连，联网状态看上面那一行 —— 橙色就是还没连上。"
        } catch {
            gwPhase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    @MainActor
    private func gwRefresh(_ g: GatewayRowVM) async {
        guard gwRows.contains(where: { $0.id == g.id }) else { return }
        do {
            // 真链路：读网关状态（ssid / romVer / eCtrlVer / netState）。
            let st = try await HardwareService.shared.readGatewayState(mac: g.mac)
            // await 期间 rows 可能被移除或重扫改短：下标必须在 await 之后重取。
            guard let index = gwRows.firstIndex(where: { $0.id == g.id }) else { return }
            gwRows[index].lastCheckedAt = Int64(Date().timeIntervalSince1970 * 1000)
            gwRows[index].online = st.netState == 1
            gwRows[index].ssid = st.ssid
            gwRows[index].rom = st.romVer
            gwBanner = nil
        } catch {
            gwBannerOK = false
            gwBanner = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    @MainActor
    private func gwReboot(_ g: GatewayRowVM) async {
        guard !readOnly, !decoyed else { return }
        guard let index = gwRows.firstIndex(where: { $0.id == g.id }) else { return }
        guard !gwRows[index].rebooting else { return }
        gwRows[index].rebooting = true
        gwRows[index].online = false
        do {
            // 真链路：重启网关；重启期间网关短暂离线（状态由下一次刷新确认）。
            try await HardwareService.shared.rebootGateway(mac: g.mac)
            gwBannerOK = true
            gwBanner = "重启指令已被网关接受；它重启期间会短暂离线，稍后刷新状态即可。"
        } catch {
            gwBannerOK = false
            gwBanner = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        guard let done = gwRows.firstIndex(where: { $0.id == g.id }) else { return }
        gwRows[done].rebooting = false
        gwRows[done].lastCheckedAt = Int64(Date().timeIntervalSince1970 * 1000)
    }

    private func gwRemove(_ g: GatewayRowVM) {
        guard !decoyed else { return }
        DB.removeGateway(g.mac)
        gwRows.removeAll { $0.id == g.id }
        gwConfirmDelete = nil
        gwBannerOK = true
        gwBanner = "已从本机台账移除「" + g.name + "」。网关硬件里的凭据还在，要重配得先把它重置回橙灯。"
    }

    /// 进度文案来自引擎，里面带协议命令号；用户界面不显示命令号。
    private func cleanStep(_ text: String) -> String {
        var s = text
        if let range = s.range(of: " \\(cmd [0-9A-Fa-f]+\\)", options: .regularExpression) {
            s.removeSubrange(range)
        }
        s = s.replacingOccurrences(of: "cmd [0-9A-Fa-f]+ ", with: "", options: .regularExpression)
        return s
    }

    // MARK: - 电池真链路（源自 BatteryProfileHomeScreen）

    private func loadBattery() {
        guard !batteryLoaded, !mac.isEmpty else { return }
        batteryLoaded = true
        let m = LockArchive.meta(mac)
        batteryModel = m.batteryModel
        hasChangedAt = m.batteryChangedAt > 0
        if m.batteryChangedAt > 0 { changedAt = Date(timeIntervalSince1970: m.batteryChangedAt) }
        threshold = CareSchedule.battThreshold
    }

    private func saveBattery() {
        guard !mac.isEmpty else { return }
        guard !DB.isDecoy else {
            batteryOutcome = DecoyCopy.blocked("写电池档案")
            return
        }
        var m = LockArchive.meta(mac)
        m.batteryModel = batteryModel.trimmingCharacters(in: .whitespaces)
        m.batteryChangedAt = hasChangedAt ? changedAt.timeIntervalSince1970 : 0
        LockArchive.save(mac, m)
        batteryOutcome = "已保存电池档案"
    }

    // MARK: - 名片真链路（源自 DeviceInfoHomeScreen）

    private func markBatteryToday() {
        guard !DB.isDecoy else {
            batteryNote = DecoyCopy.blocked("写电池档案")
            batterySaved = false
            return
        }
        guard !mac.isEmpty else { return }
        var m = LockArchive.meta(mac)
        m.batteryChangedAt = Date().timeIntervalSince1970
        m.batteryModel = infoBatteryModel.trimmingCharacters(in: .whitespaces)
        LockArchive.save(mac, m)
        batteryNote = nil
        batterySaved = true
    }

    private func saveInfoBatteryModel() {
        guard !DB.isDecoy else {
            batteryNote = DecoyCopy.blocked("写电池档案")
            batterySaved = false
            return
        }
        guard !mac.isEmpty else { return }
        var m = LockArchive.meta(mac)
        m.batteryModel = infoBatteryModel.trimmingCharacters(in: .whitespaces)
        LockArchive.save(mac, m)
        batteryNote = nil
        batterySaved = true
    }

    private func reloadInfo() async {
        // E-07：await 期间换锁会把快照 / 电池采样写到另一把锁。
        let mac = self.mac
        guard !decoyed, !mac.isEmpty, !infoBusy else { return }
        infoBusy = true
        infoOutcome = nil
        infoOutcomeIsFailure = false
        readError = nil
        syncError = nil
        defer { infoBusy = false }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            var st = try await LockService.shared.getStatus(mac: mac)
            DB.writeStatus(mac, st)
            status = st
            samples = BatteryCare.samples(mac)
            // lockTime == 0 是「锁端没回时钟」的占位值：直接算会得到 ≈ -531260264 秒的假偏差，
            // 而且会让下面每次进页都白写一次锁钟。读不到就是「不知道」。
            let drift = (st.lockTime ?? 0) > 0 ? Int((st.lockTime ?? 0) - ZKProtocol.nowProtoSeconds()) : nil
            clockDrift = drift
            if let drift, abs(drift) > 2 {
                if app.trialGuard {
                    // 只读试验模式拦的是下发到门锁的写命令；自动校时正是一条写命令。
                    infoOutcome = "检测到锁钟偏差 " + String(drift) + " 秒；只读试验模式已开启，不自动校时。"
                } else {
                    // 检测到漂移却校时失败时必须说出来，不能 try? 吞掉。
                    do {
                        let res = try await LockService.shared.syncTime()
                        st = try await LockService.shared.getStatus(mac: mac)
                        DB.writeStatus(mac, st)
                        status = st
                        clockDrift = (st.lockTime ?? 0) > 0 ? Int((st.lockTime ?? 0) - ZKProtocol.nowProtoSeconds()) : nil
                        infoOutcome = "已自动校时 · 校前偏差 " + String(res.before) + " 秒 / 校后 " + String(res.after) + " 秒"
                    } catch {
                        infoOutcomeIsFailure = true
                        syncError = "检测到锁钟偏差 " + String(drift) + " 秒，但校时没成功："
                            + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                    }
                }
            } else {
                infoOutcome = "已重新读取锁信息"
            }
            await app.reload(refreshStatus: false)
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            readError = msg
            infoOutcome = msg
            infoOutcomeIsFailure = true
        }
    }

    // MARK: - 固件真链路（源自 DFUHomeScreen）

    private func handleImport(_ result: Result<[URL], Error>) {
        dfuError = ""
        do {
            guard let url = try result.get().first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = [UInt8](try Data(contentsOf: url))
            let p = try FirmwareKit.parse(zipData: data, fileName: url.lastPathComponent)
            if let blocked = FirmwareKit.downgradeBlocked(current: app.lock?.firmware, pkg: p) {
                throw DFUTransportError.ble(blocked)
            }
            pkg = p
            fileName = url.lastPathComponent
            dfuPhase = .ready
            dfuProgress = 0
            stateText = ""
        } catch {
            self.dfuError = "读包失败：" + error.localizedDescription
            pkg = nil
            dfuPhase = .failed
        }
    }

    private func confirmStart() {
        guard dfuPhase != .running, !decoyed, !readOnly else { return }
        guard let p = pkg, app.lock != nil else { return }
        if let blocked = FirmwareKit.downgradeBlocked(current: app.lock?.firmware, pkg: p) {
            dfuError = blocked
            dfuPhase = .failed
            return
        }
        Task { await runDfu(p) }
    }

    @MainActor
    private func runDfu(_ p: FirmwarePackage) async {
        guard let kc = app.currentKeychain else { return }
        dfuPhase = .running
        dfuProgress = 0
        dfuError = ""
        stateText = "准备中"
        ScreenCare.keepingAwake(true)
        defer { ScreenCare.keepingAwake(false) }
        do {
            // 1) 让锁进 DFU（随后断链属预期）
            try await LockService.shared.enableDfu()
            LockService.shared.disconnect()
            try? await Task.sleep(for: .seconds(2))
            // 2) DFU 传输
            let session = DFUSession(macHex: kc.mac, pid: kc.pid, pkg: p)
            session.onState = { st, msg in
                Task { @MainActor in
                    stateText = msg
                    if st == .aborted { dfuError = msg }
                }
            }
            session.onProgress = { v in
                Task { @MainActor in dfuProgress = v }
            }
            try await BackgroundGuard.run("固件刷写") { try await session.run() }
            dfuProgress = 1
            dfuPhase = .done
            stateText = "升级完成"
            await app.refreshStatus()
            stateText = "完成 · 锁内版本 " + (app.lock?.firmware ?? "未读到")
        } catch {
            dfuPhase = .failed
            self.dfuError = "升级失败：" + error.localizedDescription
        }
    }
}
