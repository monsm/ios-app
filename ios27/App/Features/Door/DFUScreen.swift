// DFUScreen.swift —— 固件升级（Nordic DFU）。
//
// 流程对齐 APK：查版本 → 选包 → 校验包 → 下发 cmd22 进 DFU → 连 ZkDFU 广播 → 传固件 → 状态机回报。
// 与原版差异：原版服务端版本比对/下载在离线版没有对应物；这里只比对本地包 vs 锁内版本。
// 本仓没有厂商签名校验能力（锁内没有公钥）—— 界面上明说，不假装验过。
import SwiftUI
import UniformTypeIdentifiers

struct DFUScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    private enum Phase: Equatable { case idle, ready, running, done, failed }

    @State private var pkg: FirmwarePackage?
    @State private var fileName = ""
    @State private var error = ""
    @State private var phase: Phase = .idle
    @State private var progress: Double = 0
    @State private var stateText = ""
    @State private var importing = false

    private var firmwareText: String {
        if let fw = app.lock?.firmware, !fw.isEmpty { return fw }
        return "未读到"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: V.S.gap16) {
                header
                if app.lock == nil {
                    noLockPanel
                } else {
                    versionPanel
                    packagePanel
                    if let pkg { packageDetailCard(pkg) }
                    runPanel
                }
            }
            .padding(.vertical, V.S.gap16)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("固件升级")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(phase == .running)
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.zip, .data],
                      allowsMultipleSelection: false) { result in
            handleImport(result)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: V.S.gapXS) {
            Text("固件升级")
                .font(V.F.displayHome)
                .foregroundStyle(V.C.text1)
            HStack(spacing: V.S.gapS) {
                VStateDot(tone: headerTone, word: headerWord)
                Text(headerText)
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, V.S.pageGutter)
    }

    private var headerTone: Tone {
        switch phase {
        case .running: return .live
        case .failed: return .critical
        case .done: return .ok
        default: return app.lock == nil ? .neutral : .attention
        }
    }

    private var headerWord: String {
        switch phase {
        case .running: return "升级中"
        case .failed: return "失败"
        case .done: return "完成"
        default: return pkg == nil ? "待选择固件包" : "包已就绪"
        }
    }

    private var headerText: String {
        guard let lock = app.lock else { return "还没有门锁" }
        return "\(lock.name) · 锁内固件 \(firmwareText)"
    }

    private var versionPanel: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "版本", trailing: "cmd03")
                VReadingGrid(items: [
                    .init(label: "锁内固件", value: firmwareText),
                    .init(label: "包内版本", value: pkg?.version ?? "未识别",
                          tint: versionColor),
                ], columns: 2)
                .padding(.top, V.S.gapXS)
                SettingsNote(text: "本机离线，只能比对本地包与锁内版本；原版的服务端版本检查在离线版没有对应物。")
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    private var versionColor: Color {
        guard let target = pkg?.version else { return V.C.text1 }
        if FirmwareKit.versionLt(target, firmwareText) { return V.C.critical }
        return V.C.rewardGreen
    }

    private var packagePanel: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "固件包", trailing: pkg == nil ? nil : fileName)
                if phase == .running {
                    VBusyRow(text: "升级进行中 · 请保持手机靠近门锁、不要切后台")
                } else {
                    VOutlineButton(title: pkg == nil ? "选择固件包 (.zip)" : "重新选择固件包",
                                    systemImage: "doc.badge.arrow.up") {
                        importing = true
                    }
                }
                SettingsNote(text: "包内需要 manifest.json + bin + dat；解包后逐项校验 CRC 与尺寸。本仓没有厂商签名校验能力（锁内没有公钥），包的来源请自己确认。")
                if !error.isEmpty {
                    VStatusLine(tone: .critical, text: error)
                }
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    private func packageDetailCard(_ p: FirmwarePackage) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "包内容")
                VFieldRow(label: "固件主体", value: "\(p.binSize) B")
                VFieldRow(label: "init packet", value: "\(p.datSize) B")
                VFieldRow(label: "包内版本", value: p.version ?? "未识别")
                VFieldRow(label: "来源文件", value: p.sourceName, mono: false)
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    private var runPanel: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "升级", trailing: "cmd22 / DFU")
                if phase == .running {
                    ProgressView(value: progress)
                    Text("\(Int(progress * 100))% · \(stateText)")
                        .font(V.F.footnote)
                        .foregroundStyle(V.C.text2)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("固件升级进度")
                        .accessibilityValue("\(Int(progress * 100))%，\(stateText)")
                } else {
                    VActionButton(title: phase == .done ? "再次升级" : "开始升级",
                                  systemImage: "arrow.up.circle") {
                        confirmStart()
                    }
                    .disabled(pkg == nil)
                    .opacity(pkg == nil ? 0.4 : 1)
                }
                if phase == .done {
                    VStatusLine(tone: .ok, text: "升级完成。请回锁实况读一次，确认版本已变化。")
                }
                SettingsNote(text: "过程：校验包 → 下发 22 让锁进 DFU（会断开连接，属预期）→ 连 ZkDFU 广播 → 传固件 → 校验。全程请保持手机靠近门锁、不要切后台。")
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    private var noLockPanel: some View {
        VCard {
            VEmptyState(title: "还没有门锁可以升级",
                       message: "固件升级是写给门锁的：先添加门锁，再回这一页选固件包。",
                       actionTitle: "添加门锁",
                       systemImage: "arrow.up.circle") {
                router.request(.dest(.addLock))
            }
            .padding(.vertical, V.S.gapXXL)
        }
        .padding(.horizontal, V.S.pageGutter)
    }

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
            self.error = "读包失败：\(error.localizedDescription)"
            pkg = nil
            phase = .failed
        }
    }

    private func confirmStart() {
        guard let p = pkg, app.lock != nil else { return }
        if let blocked = FirmwareKit.downgradeBlocked(current: app.lock?.firmware, pkg: p) {
            error = blocked
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
            stateText = "完成 · 锁内版本 \(app.lock?.firmware ?? "未读到")"
        } catch {
            phase = .failed
            self.error = "升级失败：\(error.localizedDescription)"
        }
    }
}
