// 固件升级页（Nordic DFU）—— 原版 APK 的 page-checkfirmwareupdate 在 iOS 侧的对应实现。
//
// 流程对齐 APK：查版本 → 选包 → 校验包 → 下发 cmd22 进 DFU → 连 ZkDFU 广播 → 传固件 → 状态机回报。
// 与原版的差异（都写在页面上，不藏）：
//   · 原版有服务端版本比对（getFirmwareVersionFromServer）；本机离线，只能比对"本地包 vs 锁内版本"。
//   · 原版页内自带下载（downloadFile）；本机让用户从文件 App 选包（FileImporter）。
//   · 原版没有签名校验，本机也没有 —— 这一条必须在界面上明说，不能让人误以为验过。
import SwiftUI
import UniformTypeIdentifiers

struct DFUView: View {
    @EnvironmentObject var app: AppState

    @State private var importing = false
    @State private var pkg: FirmwarePackage?
    @State private var fileName = ""
    @State private var error = ""
    @State private var phase: DFUPhase = .idle
    @State private var progress: Double = 0
    @State private var stateText = ""

    private enum DFUPhase: Equatable {
        case idle
        case ready
        case running
        case done
        case failed
    }

    var body: some View { vkBody.destined(.dFU) }
    var vkBody: some View {
        Form {
            versionSection
            packageSection
            if let pkg { packageDetailSection(pkg) }
            runSection
            if !error.isEmpty {
                Section {
                    Text(error).vkFont(.footnote).foregroundStyle(DS.Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        // 失败文案用 .danger 色单独表达，VoiceOver 读不出"这是错误" —— 加标签补上这一层。
                        .accessibilityLabel("升级失败：\(error)")
                }
            }
        }
        .navigationTitle("固件升级")
        .variantList()
        .dsScreenBackground()
        // 2026-10-28 补：APK 升级中禁止返回（main.js pop() 被拦）+ 屏幕常亮（setKeepScreenOn）。
        // iOS 此前两条都没有 —— 升级中途误退出会让锁停在**半完成态**（22 已让锁进 bootloader，
        // 固件没传完就是一块不能用的锁），而自动锁屏会中断传输。
        .interactiveDismissDisabled(phase == .running)
        .navigationBarBackButtonHidden(phase == .running)
        .keepingScreenAwake(phase == .running)
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.zip, .data],
                      allowsMultipleSelection: false) { result in
            handleImport(result)
        }
    }

    // MARK: - 版本

    /// 2026-10-30 补（第 120 轮）：锁内固件名的三档兜底（档案 fw → 实时 status.firmware → "未读到"）。
    /// 原来只对 `fw` 判了空串、`firmware` 用 `??` —— 而 `??` 只处理 nil，不处理空串，锁端回空串时这一行**留白**。
    private var firmwareText: String {
        if let fw = app.current?.fw, !fw.isEmpty { return fw }
        if let fw = app.status?.firmware, !fw.isEmpty { return fw }
        return "未读到"
    }

    private var versionSection: some View {
        Section {
            HStack {
                Text("锁内固件").foregroundStyle(DS.Palette.textSub)
                Spacer()
                // 2026-10-30 修复（第 120 轮）：原来只对 `fw` 判了空串，`status.firmware` 用了 `??`
                // —— 而 `??` 只处理 nil，不处理空串 ⇒ 锁端回空串时这一行**留白**，用户看到的不是「未读到」。
                Text(firmwareText)
                    .monospacedDigit()
            }
            .frame(minHeight: DS.Hit.min)
            if let pkg, let v = pkg.version {
                HStack {
                    Text("包内版本").foregroundStyle(DS.Palette.textSub)
                    Spacer()
                    Text(v).monospacedDigit()
                        .foregroundStyle(versionColor(target: v))
                }
                .frame(minHeight: DS.Hit.min)
            }
        } header: {
            Text("版本")
        } footer: {
            Text("本机离线，只能比对本地包与锁内版本；原版的服务端版本检查在离线版没有对应物。")
                .vkFont(.caption)
        }
    }

    private func versionColor(target: String) -> Color {
        let cur = app.current?.fw ?? app.status?.firmware ?? ""
        guard !cur.isEmpty else { return DS.Palette.text }
        return FirmwareKit.versionLt(target, cur) ? DS.Palette.danger : DS.Palette.ok
    }

    // MARK: - 选包

    private var packageSection: some View {
        Section {
            Button {
                importing = true
            } label: {
                Label(pkg == nil ? "选择固件包 (.zip)" : "重新选择固件包", systemImage: "doc.badge.arrow.up")
            }
            .frame(minHeight: DS.Hit.min)
            if !fileName.isEmpty {
                Text(fileName).vkFont(.caption).foregroundStyle(DS.Palette.textSub)
            }
        } header: {
            Text("固件包")
        } footer: {
            Text("包内需要 manifest.json + bin + dat；解包后逐项校验 CRC 与尺寸。"
                 + "**本仓没有厂商签名校验能力**（锁内没有公钥），包的来源请自己确认。")
                .vkFont(.caption)
        }
    }

    private func packageDetailSection(_ p: FirmwarePackage) -> some View {
        Section {
            row("固件主体", "\(p.binSize) B")
            row("init packet", "\(p.datSize) B")
            row("包内版本", p.version ?? "未识别")
            row("来源文件", p.sourceName)
        } header: {
            Text("包内容")
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(DS.Palette.textSub)
            Spacer()
            Text(v).vkFont(.caption).monospacedDigit()
                .lineLimit(1).truncationMode(.middle)
        }
        .frame(minHeight: DS.Hit.min)
    }

    // MARK: - 执行

    private var runSection: some View {
        Section {
            if phase == .running {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    ProgressView(value: progress)
                    Text("\(Int(progress * 100))% · \(stateText)")
                        .vkFont(.caption).foregroundStyle(DS.Palette.textSub)
                }
                .frame(minHeight: DS.Hit.min)
                // 2026-10-26: DFU 是本次新增三页里唯一零无障碍标注的 —— 而它恰恰是
                // 最需要"不靠看屏幕也知道进度"的一页（全程要盯着锁，手机可能不在手上）。
                // 进度条本身对 VoiceOver 只是个无意义滑块，合并成一个可朗读的整体更实用。
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("固件升级进度")
                .accessibilityValue("\(Int(progress * 100))%，\(stateText)")
            } else {
                BusyButton(title: phase == .done ? "再次升级" : "开始升级",
                           systemImage: "arrow.up.circle",
                           isBusy: false) {
                    confirmStart()
                }
                .disabled(pkg == nil)
                .accessibilityHint(pkg == nil
                    ? "请先在上方选择固件包"
                    : "会先下发命令让门锁重启进入 DFU 模式，期间会断开蓝牙，属正常")
            }
            if phase == .done {
                Text("升级完成。请回到设备页读一次锁信息，确认版本已变化。")
                    .vkFont(.footnote).foregroundStyle(DS.Palette.ok)
            }
        } header: {
            Text("升级")
        } footer: {
            Text("过程：校验包 → 下发 22 让锁进 DFU（会断开连接，属预期）→ 连 ZkDFU 广播 → 传固件 → 校验。"
                 + "全程请保持手机靠近门锁、不要切后台。")
                .vkFont(.caption)
        }
    }

    // MARK: - 动作

    private func handleImport(_ result: Result<[URL], Error>) {
        error = ""
        do {
            guard let url = try result.get().first else { return }
            // 安全作用域资源：文件 App 选来的 URL 必须显式开启访问
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = [UInt8](try Data(contentsOf: url))
            let p = try FirmwareKit.parse(zipData: data, fileName: url.lastPathComponent)
            // 降级闸：在"开始升级"之前就拦住，不让用户点下去才失败
            if let blocked = FirmwareKit.downgradeBlocked(current: app.current?.fw ?? app.status?.firmware,
                                                          pkg: p) {
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
        guard let p = pkg, let kc = app.current else { return }
        // 2026-10-27 审核修复 (AUDIT-D D-47)：**开始前再判一次降级闸**。
        // 原先只在 importPackage 里判一次 —— 而 pkg 是 @State，
        // 从导入到点「开始升级」之间可能过了很久（用户去接了个电话），
        // 期间锁内固件若被别的途径升级过，那次判定就过期了。
        // 这里用**当前**的 app.status.fw 重判，与导入时同一套判据。
        if let blocked = FirmwareKit.downgradeBlocked(current: app.current?.fw ?? app.status?.firmware,
                                                      pkg: p) {
            error = blocked
            return
        }
        confirmDestructive("开始固件升级",
                          "将把「\(p.version ?? "未知版本")」写入门锁「\(kc.name.isEmpty ? kc.mac : kc.name)」。"
                          + "升级中门锁会重启并断开蓝牙，**中途断电有变砖风险**；"
                          + "本仓无法校验固件签名，请确认这个包来自可信来源。",
                          confirmTitle: "开始升级") {
            Task { await run(p, kc: kc) }
        }
    }

    @MainActor
    private func run(_ p: FirmwarePackage, kc: Keychain) async {
        phase = .running
        progress = 0
        error = ""
        stateText = "准备中"
        do {
            // 1) 先让锁进 DFU（随后断链属预期）
            try await app.lock.enableDfu()
            app.lock.disconnect()
            // 给锁 2 秒重启并开始广播 ZkDFU
            // 2026-10-30 修复（第 73 轮）：原来这里 `try?` 吞掉取消，用户中途退页后仍会跑完整条刷写链。
            // 刷机是**不可中断**的高危动作（半完成态 = 锁可能停在 bootloader），所以取消必须立刻停。
            do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { phase = .failed; return }

            // 2) 跑 DFU 传输
            let session = DFUSession(macHex: kc.mac, pid: kc.pid, pkg: p)   // pid 用于按 APK 的 BleDfu 判据过滤广播
            session.onState = { st, msg in
                stateText = msg
                if st == .aborted { error = msg }
            }
            session.onProgress = { v in progress = v }
            // 2026-10-27 审核 (AUDIT-D D-22)：刷机中途切后台会被系统挂起，锁留在半完成态。
        try await BackgroundGuard.run("固件刷写") { try await session.run() }

            progress = 1
            phase = .done
            stateText = "升级完成"
            // 3) 回读一次，确认版本真的变了（与 cmd20 的回读校验同口径）
            // 2026-10-30 修复（第 73 轮）：同上 —— 用户已离开页面就别再写 stateText / 弹 toast，
            // 否则会往一个已经消失的视图里写状态（SwiftUI 里表现为"退出后闪一下"）。
            do { try await Task.sleep(nanoseconds: 1_500_000_000) } catch { return }
            await app.refreshStatusQuietly(manual: true)
            let after = app.status?.firmware ?? app.current?.fw ?? "未读到"
            stateText = "完成 · 锁内版本 \(after)"
            app.showToast("固件升级完成")
        } catch {
            phase = .failed
            self.error = "升级失败：\(error.localizedDescription)"
            app.showToast("升级失败")
        }
    }
}
