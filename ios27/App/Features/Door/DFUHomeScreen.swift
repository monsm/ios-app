// DFUHomeScreen.swift —— 固件升级（V8 设计语言）
//
// 与 DFUScreen 的能力对齐：查版本 → 选包 → 校验包 → 让锁进 DFU → 连广播 → 传固件 → 状态机回报。
// 只改渲染层：选包仍走 FirmwareKit.parse，刷写仍走 LockService.enableDfu + DFUSession + BackgroundGuard。
//
// 与旧页的刻意差异：
//   ① 空壳模式整页停用 —— 空壳下 app.lock 仍是真锁，固件升级会真的改写锁内固件。
//   ② 只读试验模式明确禁止开始升级（DFUSession 里有 assertReadOnly 兜底，页面先说清楚）。
import SwiftUI
import UniformTypeIdentifiers

struct DFUHomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    private enum Phase: Equatable {
        case idle
        case ready
        case running
        case done
        case failed
    }

    @State private var pkg: FirmwarePackage?
    @State private var fileName = ""
    @State private var error = ""
    @State private var phase: Phase = .idle
    /// 「开始升级」一点就刷，而刷写失败会把锁留在 bootloader —— 必须先说清后果再确认。
    @State private var askStart = false
    @State private var progress: Double = 0
    @State private var stateText = ""
    @State private var importing = false

    private var decoyed: Bool { DB.isDecoy }
    private var readOnly: Bool { app.trialGuard }

    private var firmwareText: String {
        if let fw = app.lock?.firmware, !fw.isEmpty { return fw }
        return "未读到"
    }

    private var judgement: String {
        if decoyed { return "空壳模式不提供固件升级" }
        guard app.lock != nil else { return "还没有门锁" }
        switch phase {
        case .running: return "正在刷写固件"
        case .failed: return "升级没有完成"
        case .done: return "升级完成"
        case .idle, .ready: return pkg == nil ? "待选择固件包" : "包已就绪"
        }
    }

    private var lead: String {
        if decoyed {
            return "空壳模式只隐藏数据，不改动数据。固件升级会真的改写锁内固件，所以这里不提供。"
        }
        guard let lock = app.lock else {
            return "固件升级是写给门锁的：先添加门锁，再回这一页选固件包。"
        }
        if phase == .running {
            return "刷写中不要离开本页、不要切后台、不要远离门锁。"
        }
        return lock.name + " · 锁内固件 " + firmwareText + "。刷写中途失败锁会停在升级模式。"
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            if decoyed {
                EmptyView()
            } else if app.lock != nil {
                chipRow
            } else {
                EmptyView()
            }
        } content: {
            if decoyed {
                decoyCard
            } else if app.lock == nil {
                VEmpty(
                    title: "还没有门锁可以升级",
                    reason: "固件升级是写给门锁的：先添加门锁，再回这一页选固件包。",
                    actionTitle: "添加门锁"
                ) { router.request(.dest(.addLock)) }
            } else {
                versionCard
                packageCard
                if let pkg {
                    packageDetailCard(pkg)
                }
                runCard
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(phase == .running)
        .navigationBarBackButtonHidden(phase == .running)
        .toolbar(phase == .running ? .hidden : .visible, for: .navigationBar)
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
    }

    // MARK: - 芯片行

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: V8.S.gapChip) {
                VChip2(icon: .glyph("cpu"), label: "锁内固件", value: firmwareText)
                VChip2(icon: .ring(pkg == nil ? 0.02 : 1, pkg == nil ? V8.C.ink4 : V8.C.ok), label: "包内版本", value: pkg?.version ?? "未识别")
                VChip2(icon: .glyph("arrow.up.circle"), label: "状态", value: phaseWord)
            }
            .padding(.leading, V8.S.gutterCard)
            .padding(.trailing, V8.S.gutterCard)
        }
        .scrollClipDisabled()
    }

    private var phaseWord: String {
        switch phase {
        case .running: return "升级中"
        case .failed: return "失败"
        case .done: return "完成"
        case .idle, .ready: return pkg == nil ? "待选包" : "包已就绪"
        }
    }

    // MARK: - 版本

    private var versionCard: some View {
        VCard2 {
            VCardHead(eyebrow: "版本", statement: "锁内固件 " + firmwareText, trailing: "锁端 / 本地")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                VDataRow(tag: "锁内", tagTint: V8.C.ink4, title: "锁内固件", value: firmwareText)
                VDotRule()
                VDataRow(tag: "包内", tagTint: versionTint, title: "包内版本", value: pkg?.version ?? "未识别")
            }
            .padding(.top, V8.S.gapS)
            Text("本机离线，只能比对本地包与锁内版本；原版的服务端版本检查在离线版没有对应物。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var versionTint: Color {
        guard let target = pkg?.version else { return V8.C.ink4 }
        if FirmwareKit.versionLt(target, firmwareText) { return V8.C.danger }
        return V8.C.ok
    }

    // MARK: - 固件包

    private var packageCard: some View {
        VCard2 {
            VCardHead(eyebrow: "固件包", statement: pkg == nil ? "还没选包" : fileName, trailing: "zip")
            VDivider2()
                .padding(.top, V8.S.gapM)
            if phase == .running {
                VBusy(text: "升级进行中 · 请保持手机靠近门锁、不要切后台")
                    .padding(.top, V8.S.gapM)
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
                .buttonStyle(.plain)
                .disabled(readOnly)
                .opacity(readOnly ? 0.45 : 1)
                .padding(.top, V8.S.gapM)
            }
            Text("包内需要 manifest.json + bin + dat；解包后逐项校验 CRC 与尺寸。本仓没有厂商签名校验能力（锁内没有公钥），包的来源请自己确认。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            if readOnly {
                Text("只读试验模式已开启：固件升级会被拦下。到「设置 → 安全 → 只读试验模式」关掉再试。")
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.warn)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func packageDetailCard(_ p: FirmwarePackage) -> some View {
        VCard2 {
            VCardHead(eyebrow: "包内容", statement: p.version ?? "版本未识别")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                VDataRow(tag: "主体", tagTint: V8.C.ink4, title: "固件主体", value: String(p.binSize), unit: "B")
                VDotRule()
                VDataRow(tag: "init", tagTint: V8.C.ink4, title: "init packet", value: String(p.datSize), unit: "B")
                VDotRule()
                VDataRow(tag: "版本", tagTint: V8.C.ink4, title: "包内版本", value: p.version ?? "未识别")
                VDotRule()
                VDataRow(tag: "来源", tagTint: V8.C.ink4, title: "来源文件", value: p.sourceName)
            }
            .padding(.top, V8.S.gapS)
        }
    }

    // MARK: - 升级

    private var runCard: some View {
        VCard2 {
            VCardHead(eyebrow: "升级", statement: phase == .running ? "刷写中" : "Nordic DFU", trailing: phaseWord)
            VDivider2()
                .padding(.top, V8.S.gapM)
            if phase == .running {
                ProgressView(value: progress)
                    .tint(V8.C.accent)
                    .padding(.top, V8.S.gapM)
                Text(String(Int(progress * 100)) + "% · " + stateText)
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("固件升级进度")
                    .accessibilityValue(String(Int(progress * 100)) + "%，" + stateText)
                    .padding(.top, V8.S.gapS)
            } else {
                Button {
                    askStart = true
                } label: {
                    Text(phase == .done ? "再次升级" : "开始升级")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.chipOn)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.accent))
                }
                .buttonStyle(.plain)
                .disabled(pkg == nil || readOnly)
                .opacity((pkg == nil || readOnly) ? 0.4 : 1)
                .padding(.top, V8.S.gapM)
            }
            if phase == .done {
                Text("升级完成。请回锁实况读一次，确认版本已变化。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ok)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            } else if phase == .failed {
                VFailure(
                    what: "升级没有完成",
                    why: error.isEmpty ? "刷写链中途失败，具体原因没有回报。" : error,
                    next: "锁很可能仍停在升级模式 —— 此时无法开门。请保持手机靠近门锁，回到本页再点重试；若反复失败，换一部手机或用厂商工具重刷。"
                ) {
                    importing = true
                }
                .padding(.top, V8.S.gapM)
            }
            Text("过程：校验包 → 让锁进升级模式（会断开连接，属预期）→ 连专用广播 → 传固件 → 校验。全程请保持手机靠近门锁、不要切后台。")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 空壳

    private var decoyCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "固件升级", statement: "空壳模式不刷写")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("空壳模式（胁迫码进入）下不显示锁内固件，也不提供选包与刷写。固件升级会真的改写锁内固件，失败时可能让门开不了。")
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

    // MARK: - 读写

    private func handleImport(_ result: Result<[URL], Error>) {
        error = ""
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
            phase = .ready
            progress = 0
            stateText = ""
        } catch {
            self.error = "读包失败：" + error.localizedDescription
            pkg = nil
            phase = .failed
        }
    }

    private func confirmStart() {
        guard phase != .running, !decoyed, !readOnly else { return }
        guard let p = pkg, app.lock != nil else { return }
        if let blocked = FirmwareKit.downgradeBlocked(current: app.lock?.firmware, pkg: p) {
            error = blocked
            phase = .failed
            return
        }
        Task { await run(p) }
    }

    @MainActor
    private func run(_ p: FirmwarePackage) async {
        guard let kc = app.currentKeychain else { return }
        phase = .running
        progress = 0
        error = ""
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
                    if st == .aborted { error = msg }
                }
            }
            session.onProgress = { v in
                Task { @MainActor in progress = v }
            }
            try await BackgroundGuard.run("固件刷写") { try await session.run() }
            progress = 1
            phase = .done
            stateText = "升级完成"
            await app.refreshStatus()
            stateText = "完成 · 锁内版本 " + (app.lock?.firmware ?? "未读到")
        } catch {
            phase = .failed
            self.error = "升级失败：" + error.localizedDescription
        }
    }
}
