// GatewayScreen.swift —— 网关（门 · 智能网关）
//
// 这屏干什么：一条独立的配网链（连网关 → 读设备名 → 写 WiFi → 写 IoT 三元组 → 重启上线），
// 配完之后这一页只剩状态：在线与否、ROM、WiFi、上次核对时刻。网关只能收状态与告警，不能远程开门。
// 数据从哪来：本机网关台账（Engine 未接，本页用可替换的 GatewayRow 列表）。
// 主动作：配网面板里那一个「开始配网」；列表行只读，动作走长按菜单。
import SwiftUI

struct GatewayScreen: View {
    private struct GatewayRow: Identifiable, Equatable {
        let id: String
        let name: String
        let mac: String
        let rom: String
        let ssid: String
        var online: Bool
        var lastCheckedAt: Int64?
        var rebooting: Bool = false
    }

    /// 配网五步。编号是真序列（契约 §11 允许）。
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

    @State private var rows: [GatewayRow] = []
    @State private var phase: ProvisionPhase = .idle
    @State private var steps: [String] = []
    @State private var ssid = ""
    @State private var pwd = ""
    @State private var showProvision = false
    @State private var armed = false
    @State private var confirmDelete: GatewayRow?
    @State private var banner: String?

    private static let stepTitles = ["连网关", "读设备名", "写 WiFi", "写 IoT", "重启上线"]

    var body: some View {
        ScrollView {
            VStack(spacing: T.S.l) {
                header
                if let banner { bannerPanel(banner) }
                listPanel
                if showProvision || phase != .idle {
                    provisionPanel
                }
                notePanel
            }
            .padding(.vertical, T.S.l)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("网关")
        .navigationBarTitleDisplayMode(.inline)
        .task { loadRows() }
        .alert("删除这个网关？", isPresented: Binding(
            get: { confirmDelete != nil },
            set: { if !$0 { confirmDelete = nil } }
        )) {
            Button("取消") { confirmDelete = nil }
            Button("删除") { if let g = confirmDelete { remove(g) } }
        } message: {
            Text("只会从本机台账里移除这条记录。网关硬件里的 WiFi 与 IoT 凭据还在，要重配得先把它重置回橙灯。")
        }
    }

    // MARK: 页头

    private var header: some View {
        VStack(alignment: .leading, spacing: T.S.xs) {
            Text("网关")
                .font(T.F.display())
                .foregroundStyle(Ink.ink)
            HStack(spacing: T.S.s) {
                StateDot(tone: headerTone, word: headerWord)
                Text(headerText)
                    .font(T.F.caption)
                    .foregroundStyle(Ink.inkSub)
                    // 状态行最多两行：宁可换行，不要截断或缩字（缩字会把 13pt 压到 10pt，低于可读下限）
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, T.S.gutter)
    }

    private var onlineCount: Int { rows.filter { $0.online }.count }

    private var headerTone: Tone {
        if phase.isRunning { return .live }
        if rows.isEmpty { return .neutral }
        return onlineCount == rows.count ? .ok : .attention
    }

    private var headerWord: String {
        if phase.isRunning { return "配网中" }
        if rows.isEmpty { return "未添加" }
        return onlineCount == rows.count ? "全部在线" : "部分离线"
    }

    private var headerText: String {
        if rows.isEmpty { return "还没有网关，这一页只剩配网" }
        return "\(rows.count) 台 · 在线 \(onlineCount) 台 · 只收状态，不能远程开门"
    }

    // MARK: 主角：我的网关（一行一台，读数是真字段）

    private var listPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "我的网关", trailing: rows.isEmpty ? nil : "\(rows.count) 台")
                if rows.isEmpty {
                    if showProvision || phase != .idle {
                        // 配网面板已经展开时不再放第二个主动作（同屏只许一个 PrimaryAction）。
                        Text("还没有已配好的网关。走完下面五步，这台网关就会出现在这里。")
                            .font(T.F.caption)
                            .foregroundStyle(Ink.inkSub)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: T.Hit.min)
                    } else {
                        EmptyPanel(
                            title: "还没有添加网关",
                            message: "先把网关通电、捅一下重置孔到橙灯闪烁，再点下面的「配网网关」走完五步。网关不是开锁的必需品：没有它也能开门，只是拿不到远程告警。",
                            actionTitle: "配网网关",
                            systemImage: "antenna.radiowaves.left.and.right"
                        ) {
                            openProvision()
                        }
                        .padding(.vertical, T.S.xl)
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, g in
                            if index > 0 { hairline }
                            gatewayRow(g)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    private func gatewayRow(_ g: GatewayRow) -> some View {
        VStack(alignment: .leading, spacing: T.S.s) {
            HStack(spacing: T.S.s) {
                Text(g.name)
                    .font(T.F.bodyStrong)
                    .foregroundStyle(Ink.ink)
                    .lineLimit(1)
                StateDot(tone: g.rebooting ? .live : (g.online ? .ok : .attention),
                         word: g.rebooting ? "重启中" : (g.online ? "已联网" : "未联网"))
                Text(g.rebooting ? "重启中" : (g.online ? "已联网" : "未联网"))
                    .font(T.F.unit)
                    .foregroundStyle(g.online && !g.rebooting ? Ink.inkSub : State.attention)
                Spacer(minLength: 0)
            }
            ReadingGrid(items: [
                .init(label: "ROM", value: g.rom.isEmpty ? "—" : g.rom),
                .init(label: "WiFi", value: g.ssid.isEmpty ? "—" : g.ssid,
                      tint: g.online ? Ink.ink : Ink.inkFaint),
                .init(label: "上次核对", value: g.lastCheckedAt.map { TimeFormat.clock($0) } ?? "—",
                      tint: Ink.inkSub),
            ], columns: 3)
        }
        .frame(minHeight: T.Hit.min)
        .contentShape(.rect)
        .contextMenu {
            Button {
                Task { await refresh(g) }
            } label: {
                Label("刷新状态", systemImage: "arrow.clockwise")
            }
            Button {
                Task { await reboot(g) }
            } label: {
                Label("重启网关", systemImage: "power")
            }
            Button {
                confirmDelete = g
            } label: {
                Label("删除记录", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(g.name)，\(g.mac)，\(g.online ? "已联网" : "未联网")，ROM \(g.rom)，WiFi \(g.ssid)")
        .accessibilityAction(named: "刷新状态") { Task { await refresh(g) } }
        .accessibilityAction(named: "重启网关") { Task { await reboot(g) } }
    }

    // MARK: 配网（五步真序列）

    private var provisionPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "配网网关", trailing: phase.isRunning ? "写入中" : "五步")
                Text("接通电源 → 捅重置孔约 5 秒 → 指示灯变橙 → 点开始。写入过程中网关会重启并清空原有网络配置。")
                    .font(T.F.caption)
                    .foregroundStyle(Ink.inkSub)
                    .fixedSize(horizontal: false, vertical: true)
                hairline
                HStack(spacing: T.S.s) {
                    Toggle("橙灯闪烁中", isOn: $armed)
                        .font(T.F.body)
                        .tint(Ink.ink)
                        .accessibilityLabel("网关指示灯已变橙")
                    Spacer(minLength: 0)
                    StateDot(tone: armed ? .ok : .attention, word: armed ? "已就绪" : "待重置")
                }
                .frame(minHeight: T.Hit.min)

                hairline
                TextField("WiFi 名称（只支持 2.4GHz）", text: $ssid)
                    .font(T.F.body)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .frame(minHeight: T.Hit.min)
                hairline
                SecureField("WiFi 密码", text: $pwd)
                    .font(T.F.body)
                    .textFieldStyle(.plain)
                    .submitLabel(.done)
                    .frame(minHeight: T.Hit.min)
                Text("iOS 不允许 App 读当前 WiFi 名，请手动输入；要换网先去「设置 → Wi-Fi」连上目标网络再回来。")
                    .font(T.F.unit)
                    .foregroundStyle(Ink.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)

                hairline
                ladder

                if case .failed(let reason) = phase {
                    StatusLine(tone: .critical, text: reason)
                } else if phase == .succeeded {
                    StatusLine(tone: .ok, text: "指令已被网关接受 · 联网状态稍后在这里复核")
                }

                if phase.isRunning {
                    BusyRow(text: "正在写入，请勿断电")
                } else {
                    PrimaryAction(title: "开始配网", systemImage: "wifi", busy: false) {
                        Task { await provision() }
                    }
                    .opacity(canProvision ? 1 : 0.5)
                    .disabled(!canProvision)
                    if !canProvision {
                        Text("要先勾上「橙灯闪烁中」，并填好 WiFi 名称与密码。")
                            .font(T.F.unit)
                            .foregroundStyle(Ink.inkFaint)
                    }
                }
            }
        }
        .padding(.horizontal, T.S.gutter)
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
                if index > 0 { hairline }
                HStack(spacing: T.S.m) {
                    Text(pad2(index + 1))
                        .font(T.F.reading(13, weight: .medium))
                        .foregroundStyle(stepReached(index) ? Ink.ink : Ink.inkFaint)
                        .monospacedDigit()
                        .frame(width: T.Icon.xl, alignment: .leading)
                    Text(title)
                        .font(T.F.body)
                        .foregroundStyle(stepReached(index) ? Ink.ink : Ink.inkFaint)
                    Spacer(minLength: T.S.s)
                    if index < currentStep || phase == .succeeded {
                        Image(systemName: "checkmark")
                            .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                            .font(T.F.icon(T.Icon.s, weight: .semibold))
                            .foregroundStyle(Ink.ink)
                    } else if index == currentStep, phase.isRunning {
                        StateDot(tone: .live, word: "进行中")
                    } else {
                        Text("待").font(T.F.unit).foregroundStyle(Ink.inkFaint)
                    }
                }
                .frame(minHeight: T.Hit.min)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("第 \(index + 1) 步 \(title)")
            }
            if !steps.isEmpty {
                hairline
                VStack(alignment: .leading, spacing: T.S.xxs) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(T.F.unit)
                            .foregroundStyle(Ink.inkSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, T.S.s)
            }
        }
    }

    private func stepReached(_ index: Int) -> Bool {
        phase != .idle && index <= currentStep
    }

    // MARK: 须知（能力边界：别让用户以为能远程开门）

    private var notePanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "网关能做什么")
                noteLine("建议离门锁不超过五米，中间不要有承重墙阻隔。")
                noteLine("无需和门锁配对；配网时 IoT 凭据随 WiFi 一起写进网关。")
                noteLine("只能接收门锁状态与告警，无法远程操作门锁 —— 开门永远只在门口发生。")
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    private func noteLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: T.S.s) {
            StateDot(tone: .neutral, word: "须知")
            Text(text)
                .font(T.F.caption)
                .foregroundStyle(Ink.inkSub)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func bannerPanel(_ text: String) -> some View {
        Panel {
            HStack(alignment: .top, spacing: T.S.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                    .font(T.F.icon(T.Icon.s, weight: .semibold))
                    .foregroundStyle(State.attention)
                Text(text)
                    .font(T.F.caption)
                    .foregroundStyle(Ink.inkSub)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    // MARK: 交互

    private func openProvision() {
        showProvision = true
        banner = nil
    }

    private func loadRows() {
        rows = DB.gateways().map { g in
            GatewayRow(id: g.mac,
                       name: g.name.isEmpty ? "智能网关 \(String(g.mac.prefix(4)))" : g.name,
                       mac: g.mac,
                       rom: g.romVer,
                       ssid: g.ssid.isEmpty ? g.lastWifi : g.ssid,
                       online: g.netState == 1,
                       lastCheckedAt: Int64(Date().timeIntervalSince1970 * 1000))
        }
    }

    @MainActor
    private func provision() async {
        guard canProvision, !phase.isRunning else { return }
        banner = nil
        steps = []
        let sentSsid = ssid
        // 网关只支持 2.4GHz。名字里带 5G 的网段几乎一定是 5GHz —— 与其写进硬件再失败，不如先拦下。
        if sentSsid.uppercased().contains("5G") {
            phase = .failed("「\(sentSsid)」看起来是 5GHz 网络。网关只支持 2.4GHz，请换成路由器 2.4GHz 那个 SSID 再试。")
            return
        }
        phase = .running(step: 0)
        do {
            // 真链路：扫描网关 → cmd38 状态 → cmd31 写 WiFi → cmd35 重启 → 落库（HardwareService）。
            let rec = try await HardwareService.shared.provisionGateway(ssid: sentSsid, password: pwd) { msg in
                Task { @MainActor in self.steps.append(msg) }
            }
            ssid = ""
            pwd = ""
            armed = false
            phase = .succeeded
            loadRows()
            banner = "配网指令已被网关接受（\(rec.lastWifi)）。它正在用新 WiFi 重连，联网状态看上面那一行 —— 橙色就是还没连上。"
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    @MainActor
    private func refresh(_ g: GatewayRow) async {
        guard let index = rows.firstIndex(where: { $0.id == g.id }) else { return }
        do {
            // 真链路：cmd38 读状态（ssid / romVer / eCtrlVer / netState）。
            let st = try await HardwareService.shared.readGatewayState(mac: g.mac)
            rows[index].lastCheckedAt = Int64(Date().timeIntervalSince1970 * 1000)
            rows[index].online = st.netState == 1
            rows[index].ssid = st.ssid
            rows[index].rom = st.romVer
            banner = nil
        } catch {
            banner = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    @MainActor
    private func reboot(_ g: GatewayRow) async {
        guard let index = rows.firstIndex(where: { $0.id == g.id }) else { return }
        rows[index].rebooting = true
        rows[index].online = false
        do {
            // 真链路：cmd35 重启；重启期间网关短暂离线（状态由下一次刷新确认）。
            try await HardwareService.shared.rebootGateway(mac: g.mac)
            banner = "重启指令已被网关接受；它重启期间会短暂离线，稍后刷新状态即可。"
        } catch {
            banner = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        guard let done = rows.firstIndex(where: { $0.id == g.id }) else { return }
        rows[done].rebooting = false
        rows[done].lastCheckedAt = Int64(Date().timeIntervalSince1970 * 1000)
    }

    private func remove(_ g: GatewayRow) {
        DB.removeGateway(g.mac)
        rows.removeAll { $0.id == g.id }
        confirmDelete = nil
        banner = "已从本机台账移除「\(g.name)」。网关硬件里的凭据还在，要重配得先把它重置回橙灯。"
    }

    private func pad2(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }

    private var hairline: some View {
        Rectangle()
            .fill(Ink.hairline)
            .frame(height: T.Stroke.hair)
    }
}
