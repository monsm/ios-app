// GatewayHomeScreen.swift —— 网关（V8 设计语言）
//
// 与 GatewayScreen 的能力对齐：一条独立的配网链（连网关 → 读设备名 → 写 WiFi → 写 IoT → 重启上线），
// 配完之后这一页只剩状态：在线与否、ROM、WiFi、上次核对时刻。网关只能收状态与告警，不能远程开门。
// 只改渲染层：发现/配网/刷新/重启仍走 HardwareService，删除仍走 DB.removeGateway。
//
// 与旧页的刻意差异：
//   ① 空壳模式整页停用 —— 网关台账在空壳下返回空集，但配网会写真实台账与网关硬件。
//   ② 只读试验模式明确禁止开始配网与重启（写类命令被 assertReadOnly 拦死）。
import SwiftUI

struct GatewayHomeScreen: View {
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

    @Environment(AppModel.self) private var app
    @State private var rows: [GatewayRowVM] = []
    @State private var phase: ProvisionPhase = .idle
    @State private var steps: [String] = []
    @State private var ssid = ""
    @State private var pwd = ""
    @State private var showProvision = false
    @State private var armed = false
    @State private var confirmDelete: GatewayRowVM?
    @State private var rebootTarget: GatewayRowVM?
    @State private var banner: String?
    @State private var bannerOK = true

    private static let stepTitles = ["连网关", "读设备名", "写 WiFi", "写 IoT", "重启上线"]

    private var decoyed: Bool { DB.isDecoy }
    private var readOnly: Bool { app.trialGuard }

    private var onlineCount: Int { rows.filter { $0.online }.count }

    private var judgement: String {
        if decoyed { return "空壳模式不显示网关" }
        if phase.isRunning { return "正在给网关配网" }
        if rows.isEmpty { return "还没有添加网关" }
        return onlineCount == rows.count ? String(rows.count) + " 台网关全部在线" : String(rows.count) + " 台网关 · " + String(onlineCount) + " 台在线"
    }

    private var lead: String {
        if decoyed {
            return "空壳模式只隐藏数据，不改动数据。网关台账不显示，也不提供配网与重启。"
        }
        return "网关只接收门锁状态与告警，不能远程开门；配网会改写网关里的 WiFi 与 IoT 凭据。"
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            if decoyed {
                EmptyView()
            } else {
                chipRow
            }
        } content: {
            if decoyed {
                decoyCard
            } else {
                if let banner {
                    bannerCard(banner)
                }
                listSection
                if showProvision || phase != .idle {
                    provisionCard
                }
                noteCard
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { loadRows() }
        .v8Confirm(
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            ),
            title: "删除这个网关？",
            consequence: "只从本机台账里移除这条记录，网关硬件里的 WiFi 与 IoT 凭据还在。本机记录删除后无法恢复，要重配得先把它重置回橙灯。",
            confirmTitle: "删除记录",
            isDestructive: true
        ) {
            if let g = confirmDelete {
                confirmDelete = nil
                remove(g)
            }
        }
        .v8Confirm(
            isPresented: Binding(
                get: { rebootTarget != nil },
                set: { if !$0 { rebootTarget = nil } }
            ),
            title: "重启这个网关？",
            consequence: "重启期间网关会短暂离线 —— 如果你在外面靠它远程看门，这段时间会连不上。重启不会改配置，稍后刷新即可恢复。",
            confirmTitle: "重启",
            isDestructive: true
        ) {
            if let g = rebootTarget {
                rebootTarget = nil
                Task { await reboot(g) }
            }
        }
    }

    // MARK: - 芯片行

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: V8.S.gapChip) {
                VChip2(icon: .ring(rows.isEmpty ? 0.02 : 1, rows.isEmpty ? V8.C.ink4 : V8.C.accent), label: "网关", value: rows.isEmpty ? "未添加" : String(rows.count) + " 台")
                VChip2(icon: .ring(rows.isEmpty ? 0.02 : Double(onlineCount) / Double(max(1, rows.count)), onlineCount == rows.count && !rows.isEmpty ? V8.C.ok : V8.C.warn), label: "在线", value: String(onlineCount) + " / " + String(rows.count))
                VChip2(icon: .glyph("wifi"), label: "配网", value: phaseWord)
            }
            .padding(.leading, V8.S.gutterCard)
            .padding(.trailing, V8.S.gutterCard)
        }
        .scrollClipDisabled()
    }

    private var phaseWord: String {
        switch phase {
        case .idle: return "待开始"
        case .running(let step): return "第 " + String(step + 1) + " / 5 步"
        case .failed: return "失败"
        case .succeeded: return "已接受"
        }
    }

    // MARK: - 我的网关

    @ViewBuilder
    private var listSection: some View {
        if rows.isEmpty {
            if showProvision || phase != .idle {
                VCard2(style: .well) {
                    Text("还没有已配好的网关。走完下面五步，这台网关就会出现在这里。")
                        .font(V8.T.footnote)
                        .foregroundStyle(V8.C.ink3)
                        .frame(minHeight: V8.H.min)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VEmpty(
                    title: "还没有添加网关",
                    reason: "先把网关通电、捅一下重置孔到橙灯闪烁，再点下面的「配网网关」走完五步。网关不是开锁的必需品：没有它也能开门，只是拿不到远程告警。",
                    actionTitle: "配网网关"
                ) { openProvision() }
            }
        } else {
            VCard2 {
                VCardHead(eyebrow: "我的网关", statement: "一行一台", trailing: String(rows.count) + " 台")
                VDivider2()
                    .padding(.top, V8.S.gapM)
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, g in
                        if index > 0 { VDivider2() }
                        gatewayRow(g)
                    }
                }
            }
        }
    }

    private func gatewayRow(_ g: GatewayRowVM) -> some View {
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
        }
        .frame(minHeight: V8.H.min)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                Task { await refresh(g) }
            } label: {
                Label("刷新状态", systemImage: "arrow.clockwise")
            }
            Button {
                rebootTarget = g
            } label: {
                Label("重启网关", systemImage: "power")
            }
            .disabled(readOnly)
            Button {
                confirmDelete = g
            } label: {
                Label("删除记录", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(g.name + "，" + DB.shortMac(g.mac) + "，" + (g.online ? "已联网" : "未联网") + "，ROM " + g.rom + "，WiFi " + g.ssid)
        .accessibilityAction(named: "刷新状态") { Task { await refresh(g) } }
        .accessibilityAction(named: "重启网关") { Task { await reboot(g) } }
    }

    // MARK: - 配网（五步真序列）

    private var provisionCard: some View {
        VCard2 {
            VCardHead(eyebrow: "配网网关", statement: phase.isRunning ? "写入中 · 请勿断电" : "五步", trailing: "2.4GHz")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("接通电源 → 捅重置孔约 5 秒 → 指示灯变橙 → 点开始。写入过程中网关会重启并清空原有网络配置。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(isOn: $armed) {
                Text("橙灯闪烁中")
                    .font(V8.T.body)
                    .foregroundStyle(V8.C.ink1)
            }
            .tint(V8.C.accent)
            .frame(minHeight: V8.H.min)
            .accessibilityLabel("网关指示灯已变橙")
            .padding(.top, V8.S.gapS)
            TextField("WiFi 名称（只支持 2.4GHz）", text: $ssid)
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink1)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .frame(minHeight: V8.H.min)
                .padding(.horizontal, V8.S.gapM)
                .background(V8.C.well, in: .rect(cornerRadius: V8.R.inset))
                .padding(.top, V8.S.gapM)
            SecureField("WiFi 密码", text: $pwd)
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink1)
                .submitLabel(.done)
                .frame(minHeight: V8.H.min)
                .padding(.horizontal, V8.S.gapM)
                .background(V8.C.well, in: .rect(cornerRadius: V8.R.inset))
                .padding(.top, V8.S.gapM)
            Text("iOS 不允许 App 读当前 WiFi 名，请手动输入；要换网先去「设置 → Wi-Fi」连上目标网络再回来。")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
            VDivider2()
                .padding(.vertical, V8.S.gapM)
            ladder
            if case .failed(let reason) = phase {
                VFailure(
                    what: "配网没有完成",
                    why: reason,
                    next: "确认网关橙灯闪烁、WiFi 名称与密码无误且是 2.4GHz 网络，再点重试。"
                ) {
                    Task { await provision() }
                }
                .padding(.top, V8.S.gapM)
            } else if phase == .succeeded {
                Text("指令已被网关接受 · 联网状态稍后在这里复核")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ok)
                    .padding(.top, V8.S.gapM)
            }
            if phase.isRunning {
                VBusy(text: "正在写入，请勿断电")
                    .padding(.top, V8.S.gapM)
            } else {
                Button {
                    Task { await provision() }
                } label: {
                    Text("开始配网")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.chipOn)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.accent))
                }
                .buttonStyle(.plain)
                .disabled(!canProvision || readOnly)
                .opacity((canProvision && !readOnly) ? 1 : 0.45)
                .padding(.top, V8.S.gapM)
                if !canProvision {
                    Text("要先勾上「橙灯闪烁中」，并填好 WiFi 名称与密码。")
                        .font(V8.T.caption)
                        .foregroundStyle(V8.C.ink4)
                        .padding(.top, V8.S.gapS)
                }
                if readOnly {
                    Text("只读试验模式已开启：配网与重启都会被拦下。到「设置 → 安全 → 只读试验模式」关掉再试。")
                        .font(V8.T.caption)
                        .foregroundStyle(V8.C.warn)
                        .padding(.top, V8.S.gapS)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var canProvision: Bool {
        armed
            && !ssid.trimmingCharacters(in: .whitespaces).isEmpty
            && !pwd.isEmpty
    }

    private var currentStep: Int {
        if case .running(let step) = phase { return step }
        return phase == .succeeded ? 4 : 0
    }

    private var ladder: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.stepTitles.enumerated()), id: \.offset) { index, title in
                if index > 0 { VDotRule() }
                VDataRow(
                    tag: DF.pad2(index + 1),
                    tagTint: stepReached(index) ? V8.C.ink3 : V8.C.ink4,
                    title: title,
                    value: stepWord(index)
                )
            }
            if !steps.isEmpty {
                VDivider2()
                    .padding(.top, V8.S.gapS)
                VStack(alignment: .leading, spacing: V8.S.gapXS) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, line in
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

    private func stepReached(_ index: Int) -> Bool {
        phase != .idle && index <= currentStep
    }

    private func stepWord(_ index: Int) -> String {
        if index < currentStep || phase == .succeeded { return "已完成" }
        if index == currentStep && phase.isRunning { return "进行中" }
        return "待"
    }

    // MARK: - 须知

    private var noteCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "网关能做什么", statement: "只收状态与告警")
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
    }

    // MARK: - 空壳

    private var decoyCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "网关", statement: "空壳模式只读")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("空壳模式（胁迫码进入）下，网关台账不显示，也不提供配网、刷新与重启。配网会真的写网关硬件，这一步没有撤销。")
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

    @ViewBuilder
    private func bannerCard(_ text: String) -> some View {
        if bannerOK {
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

    // MARK: - 交互

    private func openProvision() {
        showProvision = true
        banner = nil
    }

    private func loadRows() {
        guard !decoyed else { return }
        rows = DB.gateways().map { g in
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
    private func provision() async {
        guard canProvision, !phase.isRunning, !decoyed, !readOnly else { return }
        banner = nil
        steps = []
        let sentSsid = ssid
        // 网关只支持 2.4GHz。名字里带 5G 的网段几乎一定是 5GHz —— 先拦下，别写进硬件再失败。
        if sentSsid.uppercased().contains("5G") {
            phase = .failed("「" + sentSsid + "」看起来是 5GHz 网络。网关只支持 2.4GHz，请换成路由器 2.4GHz 那个 SSID 再试。")
            return
        }
        phase = .running(step: 0)
        do {
            // 真链路：扫描网关 → 状态 → 写 WiFi → 重启 → 落库（HardwareService）。
            let rec = try await HardwareService.shared.provisionGateway(ssid: sentSsid, password: pwd) { msg in
                Task { @MainActor in self.steps.append(self.cleanStep(msg)) }
            }
            ssid = ""
            pwd = ""
            armed = false
            phase = .succeeded
            loadRows()
            bannerOK = true
            banner = "配网指令已被网关接受（" + rec.lastWifi + "）。它正在用新 WiFi 重连，联网状态看上面那一行 —— 橙色就是还没连上。"
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    @MainActor
    private func refresh(_ g: GatewayRowVM) async {
        guard rows.contains(where: { $0.id == g.id }) else { return }
        do {
            // 真链路：读网关状态（ssid / romVer / eCtrlVer / netState）。
            let st = try await HardwareService.shared.readGatewayState(mac: g.mac)
            // await 期间 rows 可能被移除或重扫改短：下标必须在 await 之后重取。
            guard let index = rows.firstIndex(where: { $0.id == g.id }) else { return }
            rows[index].lastCheckedAt = Int64(Date().timeIntervalSince1970 * 1000)
            rows[index].online = st.netState == 1
            rows[index].ssid = st.ssid
            rows[index].rom = st.romVer
            banner = nil
        } catch {
            bannerOK = false
            banner = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    @MainActor
    private func reboot(_ g: GatewayRowVM) async {
        guard !readOnly, !decoyed else { return }
        guard let index = rows.firstIndex(where: { $0.id == g.id }) else { return }
        guard !rows[index].rebooting else { return }
        rows[index].rebooting = true
        rows[index].online = false
        do {
            // 真链路：重启网关；重启期间网关短暂离线（状态由下一次刷新确认）。
            try await HardwareService.shared.rebootGateway(mac: g.mac)
            bannerOK = true
            banner = "重启指令已被网关接受；它重启期间会短暂离线，稍后刷新状态即可。"
        } catch {
            bannerOK = false
            banner = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        guard let done = rows.firstIndex(where: { $0.id == g.id }) else { return }
        rows[done].rebooting = false
        rows[done].lastCheckedAt = Int64(Date().timeIntervalSince1970 * 1000)
    }

    private func remove(_ g: GatewayRowVM) {
        guard !decoyed else { return }
        DB.removeGateway(g.mac)
        rows.removeAll { $0.id == g.id }
        confirmDelete = nil
        bannerOK = true
        banner = "已从本机台账移除「" + g.name + "」。网关硬件里的凭据还在，要重配得先把它重置回橙灯。"
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
}
