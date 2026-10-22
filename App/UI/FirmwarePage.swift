//
//  FirmwarePage.swift
//  固件升级 · 全新重写 (2026-10-21)
//
//  ═══════════════════════════════════════════════════════════
//  视觉冲击力: 三段进度成为主角
//  ═══════════════════════════════════════════════════════════
//
//  旧版: List + Section 若干, 进度是 ProgressView + 一行字
//
//  新版:
//    · 升级中: 中央一枚 160pt 圆环进度 (粗环 + 铜色渐变 + 百分比居中)
//    · 三段 (准备/传输/校验) 做成环外三个节点, 当前段呼吸
//    · 剩余时间与速率并排显示在环下
//    · 体检单: 四项做成可勾选的清单卡, 未满足项红字说明
//    · 从/到版本做成"v1.2.3 → v1.2.4"的大字对照
//

import SwiftUI
import UniformTypeIdentifiers

/// 固件升级页
struct FirmwarePage: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var bleSvc = BLEService.shared

    @State private var fw: FirmwarePackage?
    @State private var showPicker = false
    @State private var running = false
    @State private var failed = false
    @State private var failReason = ""
    @State private var showUpgradeConfirm = false
    @State private var showQueueConfirm = false
    @State private var stage = 0
    @State private var pct = 0.0
    @State private var remainText = ""
    @State private var tickBackup = false
    @State private var tickTime = false
    @State private var verifyText = ""
    @State private var verified = false
    @State private var lastProg: (pct: Double, at: TimeInterval)? = nil
    @State private var rate: Double = 0
    @State private var queueSel: Set<String> = []
    @State private var queueNote = ""
    @State private var queueOutcomes: [DFURunner.QueueOutcome] = []

    private static let bytes: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()
    private func sizeText(_ n: Int) -> String { Self.bytes.string(fromByteCount: Int64(n)) }

    private var mac: String { app.current?.mac ?? "" }
    private var curFw: String {
        let live = app.current?.fw ?? ""
        return live.isEmpty ? (app.snapshot?.firmware ?? "") : live
    }
    private var battPct: Int {
        if let s = BatteryCare.latest(mac)?.pct, s >= 0 { return s }
        return app.snapshot?.powerLevel ?? -1
    }
    private var battOk: Bool { battPct > 30 }
    private var checklistOk: Bool { battOk && bleSvc.isPoweredOn && tickBackup && tickTime }
    private var lastBackupText: String {
        let hist = DB.store.get([Double].self, "kf_backup_hist") ?? []
        guard let last = hist.last else { return "从未备份" }
        let d = Int(Date().timeIntervalSince1970 * 1000 - last) / 86_400_000
        return d <= 0 ? "今天备过" : "\(d) 天前"
    }

    var body: some View {
        ZStack {
            XPalette.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: XSpace.section) {
                    if running {
                        upgradeStage.xScrollLift()
                    } else if failed {
                        failedStage.xScrollLift()
                    } else {
                        versionCard.xScrollLift()
                        if let fw { packageCard(fw).xScrollLift() }
                        checklistCard.xScrollLift()
                        actionCard.xScrollLift()
                        if !queueSel.isEmpty || !queueOutcomes.isEmpty { queueCard.xScrollLift() }
                    }
                    historyCard.xScrollLift()
                }
                .padding(.horizontal, XSpace.gutter)
                .padding(.vertical, XSpace.l)
            }
        }
        .navigationTitle("固件升级")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showPicker,
                      allowedContentTypes: [.zip, .data],
                      allowsMultipleSelection: false) { importZip($0) }
        .confirmationDialog("开始升级?", isPresented: $showUpgradeConfirm) {
            Button("开始升级", role: .destructive) { Task { await upgrade() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("升级过程中请保持手机靠近门锁, 不要锁屏或离开本页。中断可能导致门锁需要重新配网。")
        }
        .confirmationDialog("批量升级 \(queueSel.count) 把锁?", isPresented: $showQueueConfirm) {
            Button("开始批量升级", role: .destructive) { Task { await runQueue() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("逐把串行升级, 一把失败不会中断其余。全程需要保持靠近。")
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 版本对照
    // ═══════════════════════════════════════════════════════

    private var versionCard: some View {
        XPanel(kind: .hero) {
            VStack(spacing: XSpace.m) {
                HStack(spacing: XSpace.l) {
                    versionPill("当前", curFw.isEmpty ? "—" : curFw, tone: .neutral)
                    Image(systemName: "arrow.right")
                        .font(.system(size: XIcon.sm, weight: .semibold))
                        .foregroundStyle(XPalette.textTertiary)
                        .accessibilityHidden(true)
                    versionPill("目标", fw?.version ?? "未选包",
                                tone: fw?.version == nil ? .neutral : .accent)
                }

                if let tag = compareTag {
                    XStatusPill(text: tag.text, tone: tag.tone)
                }
            }
        }
    }

    private func versionPill(_ label: String, _ value: String, tone: XToneColor) -> some View {
        VStack(spacing: XSpace.xxs) {
            Text(label)
                .xFont(.caption2)
                .foregroundStyle(XPalette.textSub)
            Text(value)
                .xFont(.title3, weight: .semibold)
                .monospacedDigit()
                .foregroundStyle(tone == .neutral ? XPalette.text : tone.color)
        }
        .frame(maxWidth: .infinity)
    }

    private var compareTag: (text: String, tone: XToneColor)? {
        guard let v = fw?.version else { return nil }
        if curFw.isEmpty { return ("可选升级", .neutral) }
        if FirmwareKit.versionLt(curFw, v) { return ("推荐升级", .ok) }
        if FirmwareKit.versionLt(v, curFw) { return ("低于当前版本", .warn) }
        return ("与当前版本相同", .neutral)
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 固件包
    // ═══════════════════════════════════════════════════════

    private func packageCard(_ p: FirmwarePackage) -> some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.s) {
                HStack(spacing: XSpace.s) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: XIcon.sm, weight: .medium))
                        .foregroundStyle(XPalette.accentText)
                        .accessibilityHidden(true)
                    Text(p.sourceName)
                        .xFont(.body, weight: .medium)
                        .foregroundStyle(XPalette.text)
                        .lineLimit(1)
                    Spacer()
                }
                Text("\(sizeText(p.binSize + p.datSize))\(p.version.map { " · v\($0)" } ?? "")")
                    .xFont(.caption)
                    .foregroundStyle(XPalette.textSub)
            }
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 体检单
    // ═══════════════════════════════════════════════════════

    private var checklistCard: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                sectionTitle("升级前检查", icon: "checklist")

                checkRow(icon: "battery.75", ok: battOk,
                         title: "电量充足",
                         detail: battPct < 0 ? "读不到电量" : "当前 \(battPct)%" + (battOk ? "" : " · 需 > 30%"))
                checkRow(icon: "antenna.radiowaves.left.and.right", ok: bleSvc.isPoweredOn,
                         title: "蓝牙已开启",
                         detail: bleSvc.isPoweredOn ? "已就绪" : "请在系统设置里打开蓝牙")

                XToggle("已生成升级前备份", isOn: $tickBackup)
                    .xFont(.footnote)
                if !tickBackup {
                    Text("上次备份: \(lastBackupText) — 建议先到「备份」页导出一份")
                        .xFont(.footnote)
                        .foregroundStyle(XPalette.warn)
                }

                XToggle("时间充足, 不会中途离开", isOn: $tickTime)
                    .xFont(.footnote)
            }
        }
    }

    private func checkRow(icon: String, ok: Bool, title: String, detail: String) -> some View {
        HStack(spacing: XSpace.s) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
                .font(.system(size: XIcon.sm, weight: .medium))
                .foregroundStyle(ok ? XPalette.ok : XPalette.danger)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .xFont(.footnote, weight: .medium)
                    .foregroundStyle(XPalette.text)
                Text(detail)
                    .xFont(.caption2)
                    .foregroundStyle(ok ? XPalette.textSub : XPalette.danger)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(ok ? "通过" : "未通过"), \(detail)")
    }

    private func sectionTitle(_ text: String, icon: String) -> some View {
        HStack(spacing: XSpace.s) {
            Image(systemName: icon)
                .font(.system(size: XIcon.sm, weight: .medium))
                .foregroundStyle(XPalette.accentText)
                .accessibilityHidden(true)
            Text(text)
                .xFont(.subheadline, weight: .medium)
                .foregroundStyle(XPalette.text)
            Spacer()
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 动作
    // ═══════════════════════════════════════════════════════

    private var actionCard: some View {
        VStack(spacing: XSpace.s) {
            Button {
                showPicker = true
            } label: {
                Label(fw == nil ? "选择固件包 (.zip)" : "换一个固件包",
                      systemImage: "doc.badge.plus")
            }
            .buttonStyle(XSecondaryButtonStyle())
            .disabled(running)

            XBusyButton(title: "开始升级", systemImage: "arrow.up.circle.fill",
                        busy: running, style: .primary) {
                showUpgradeConfirm = true
            }
            .disabled(!checklistOk || fw == nil)

            if !checklistOk {
                Text("请先完成上方全部检查项, 并选择固件包")
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.textSub)
                    .multilineTextAlignment(.center)
            }

            // 批量
            if app.devices.count > 1, fw != nil {
                Menu {
                    ForEach(app.devices) { d in
                        Button {
                            if queueSel.contains(d.mac) { queueSel.remove(d.mac) }
                            else { queueSel.insert(d.mac) }
                        } label: {
                            Label(LockArchive.displayName(d),
                                  systemImage: queueSel.contains(d.mac) ? "checkmark.circle.fill" : "circle")
                        }
                    }
                    Divider().overlay(XPalette.hairline)
                    Button("批量升级 \(queueSel.count) 把") { showQueueConfirm = true }
                        .disabled(queueSel.isEmpty)
                } label: {
                    Label("批量升级", systemImage: "square.stack.3d.up")
                }
                .buttonStyle(XSecondaryButtonStyle())
                .disabled(running)
            }
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 升级中 (视觉主角)
    // ═══════════════════════════════════════════════════════

    private var upgradeStage: some View {
        VStack(spacing: XSpace.l) {
            ZStack {
                // 底环
                //
                // 规范 §14-9「纯色（非渐变）描边画环」是**命中即返工**的一条；
                // §7.8 也写「所有环必须渐变或分色，纯色单环 = 不合格」。
                // 这里原来是 .stroke(XPalette.hairline, lineWidth: 14) —— 纯色。
                // 改成与开锁大环同一套凹槽渐变（DSRing.trackTop → trackBottom），
                // 两处的「环」才是同一种材质。
                Circle()
                    .strokeBorder(
                        LinearGradient(colors: [DSRing.trackTop, DSRing.trackBottom],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 14)
                    .frame(width: 180, height: 180)

                // 进度环
                Circle()
                    .trim(from: 0, to: CGFloat(min(pct, 100) / 100))
                    .stroke(
                        AngularGradient(
                            colors: [XPalette.accent.opacity(0.6), XPalette.accent],
                            center: .center),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .frame(width: 180, height: 180)
                    .rotationEffect(.degrees(-90))
                    .animation(XMotion.soft, value: pct)

                VStack(spacing: 2) {
                    Text("\(Int(pct))%")
                        .xFont(.display, weight: .semibold)
                        .monospacedDigit()
                        .foregroundStyle(XPalette.text)
                    Text(stageName)
                        .xFont(.caption)
                        .foregroundStyle(XPalette.textSub)
                }
            }
            .padding(.top, XSpace.l)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("升级进度")
            .accessibilityValue("\(Int(pct))%, \(stageName)")

            // 三段节点
            HStack(spacing: XSpace.s) {
                stageNode("准备", 0)
                Rectangle().fill(stage > 0 ? XPalette.accent : XPalette.hairline)
                    .frame(height: 2).offset(y: -10)
                stageNode("传输", 1)
                Rectangle().fill(stage > 1 ? XPalette.accent : XPalette.hairline)
                    .frame(height: 2).offset(y: -10)
                stageNode("校验", 2)
            }
            .padding(.horizontal, XSpace.l)

            HStack(spacing: XSpace.l) {
                if !remainText.isEmpty {
                    Text(remainText)
                        .xFont(.footnote.monospacedDigit())
                        .foregroundStyle(XPalette.textSub)
                }
                if rate > 0 {
                    Text(String(format: "%.1f %%/s", rate))
                        .xFont(.footnote.monospacedDigit())
                        .foregroundStyle(XPalette.textSub)
                }
            }

            Text("升级中请勿锁屏或离开本页")
                .xFont(.footnote)
                .foregroundStyle(XPalette.warn)
                .multilineTextAlignment(.center)
        }
    }

    private var stageName: String {
        switch stage {
        case 0: return "准备中"
        case 1: return "传输中"
        default: return "校验中"
        }
    }

    private func stageNode(_ label: String, _ i: Int) -> some View {
        let done = i < stage
        let current = i == stage
        return VStack(spacing: XSpace.xxs) {
            Circle()
                .fill(done ? XPalette.accent
                      : (current ? XPalette.accent.opacity(0.2) : XPalette.surfaceAlt))
                .frame(width: 22, height: 22)
                .overlay(
                    Group {
                        if done {
                            Image(systemName: "checkmark")
                                // 规范 §10：图标最小 12pt（原 11pt）。
                                .font(.system(size: XIcon.xs, weight: .bold))
                                .foregroundStyle(XPalette.onAccent)
                        } else {
                            Circle().strokeBorder(
                                current ? XPalette.accent : XPalette.hairline,
                                lineWidth: current ? 2 : 1)
                        }
                    }
                )
            Text(label)
                .xFont(.caption2, weight: current ? .semibold : .regular)
                .foregroundStyle(done || current ? XPalette.text : XPalette.textSub)
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 失败
    // ═══════════════════════════════════════════════════════

    private var failedStage: some View {
        XPanel(kind: .group, tone: .danger) {
            VStack(spacing: XSpace.m) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: XMetric.decorIcon(48), weight: .light))
                    .foregroundStyle(XPalette.danger)
                Text("升级失败")
                    .xFont(.headline)
                    .foregroundStyle(XPalette.text)
                Text(failReason.isEmpty ? "未提供原因" : failReason)
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.textSub)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button("重试") {
                    failed = false
                    showUpgradeConfirm = true
                }
                .buttonStyle(XSecondaryButtonStyle())
            }
            .frame(maxWidth: .infinity)
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 队列
    // ═══════════════════════════════════════════════════════

    private var queueCard: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.s) {
                sectionTitle("批量结果", icon: "square.stack.3d.up")
                if !queueNote.isEmpty {
                    Text(queueNote)
                        .xFont(.footnote)
                        .foregroundStyle(XPalette.text)
                }
                ForEach(Array(queueOutcomes.enumerated()), id: \.offset) { _, o in
                    HStack(spacing: XSpace.s) {
                        Image(systemName: o.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: XIcon.xs, weight: .medium))
                            .foregroundStyle(o.ok ? XPalette.ok : XPalette.danger)
                        Text(o.mac)
                            .xFont(.caption.monospaced())
                            .foregroundStyle(XPalette.textSub)
                        Spacer(minLength: 0)
                        if !o.ok, !o.note.isEmpty {
                            Text(o.note)
                                .xFont(.caption2)
                                .foregroundStyle(XPalette.danger)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 历史
    // ═══════════════════════════════════════════════════════

    private var historyCard: some View {
        let records = BatteryCare.dfuHist.filter { $0.mac == mac }.suffix(5).reversed()
        return Group {
            if !records.isEmpty {
                XPanel(kind: .group) {
                    VStack(alignment: .leading, spacing: XSpace.s) {
                        sectionTitle("升级历史", icon: "clock.arrow.circlepath")
                        ForEach(Array(records)) { r in
                            HStack(spacing: XSpace.s) {
                                Image(systemName: r.ok ? "checkmark.circle" : "xmark.circle")
                                    .font(.system(size: XIcon.xs, weight: .medium))
                                    .foregroundStyle(r.ok ? XPalette.ok : XPalette.danger)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(r.from.isEmpty ? "—" : r.from) → \(r.to)")
                                        .xFont(.caption.monospaced())
                                        .foregroundStyle(XPalette.text)
                                    Text(dateShort(r.at))
                                        .xFont(.caption2)
                                        .foregroundStyle(XPalette.textSub)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
        }
    }

    private func dateShort(_ tsMs: Double) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = WeekCal.gregorian
        return f.string(from: Date(timeIntervalSince1970: tsMs / 1000))
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 核心逻辑 (与旧实现等价)
    // ═══════════════════════════════════════════════════════

    private func importZip(_ result: Result<[URL], Error>) {
        guard running == false, let url = try? result.get().first else { return }
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let parsed = try FirmwareKit.parse(zipData: [UInt8](data), fileName: url.lastPathComponent)
            fw = parsed
            failed = false
            verified = false
            verifyText = ""
            BatteryCare.addFWLib(name: url.lastPathComponent,
                                 version: parsed.version,
                                 size: parsed.binSize + parsed.datSize)
            app.showToast("固件包已解析" + (parsed.version.map { " · v\($0)" } ?? ""))
        } catch {
            app.showToast("固件包无法识别: " + ErrorText.human(error))
        }
    }

    private func upgrade() async {
        guard let fw, let kc = app.current, !running else { return }
        running = true
        failed = false
        failReason = ""
        verified = false
        verifyText = ""
        stage = 0
        pct = 0
        remainText = ""
        rate = 0
        lastProg = nil
        defer { running = false }

        let startedAt = Date().timeIntervalSince1970
        do {
            try await app.lock.ensureConnected(mac: kc.mac)
            try await DFURunner.runUpgrade(lock: app.lock, mac: kc.mac, pid: kc.pid, firmware: fw) { p in
                switch p {
                case .switchingDfu, .connecting: stage = 0
                case .starting: stage = 1
                case .uploading(let v):
                    stage = 1
                    updateRate(Double(v))
                case .validating: stage = 2
                case .completed: stage = 2; pct = 100
                default: break
                }
            }
            BatteryCare.addDFURecord(DFURecord(mac: kc.mac, name: fw.sourceName,
                                               from: curFw, to: fw.version ?? "",
                                               at: Date().timeIntervalSince1970 * 1000, ok: true,
                                               ms: (Date().timeIntervalSince1970 - startedAt) * 1000))
            XHaptics.success()
            await verifyAfterUpgrade(kc, fw)
        } catch {
            failed = true
            failReason = error.localizedDescription
            BatteryCare.addDFURecord(DFURecord(mac: kc.mac, name: fw.sourceName,
                                               from: curFw, to: fw.version ?? "",
                                               at: Date().timeIntervalSince1970 * 1000, ok: false,
                                               ms: (Date().timeIntervalSince1970 - startedAt) * 1000))
            XHaptics.failure()
        }
    }

    private func runQueue() async {
        guard let fw, !running, !queueSel.isEmpty else { return }
        running = true
        queueOutcomes = []
        queueNote = ""
        defer { running = false }

        let targets = app.devices.filter { queueSel.contains($0.mac) }.sorted { $0.mac < $1.mac }
        guard !targets.isEmpty else { queueNote = "队列里选的那些锁已经不在了"; return }

        var startAt: [Int: Double] = [:]
        let outcomes = await DFURunner.runUpgradeQueue(
            lock: app.lock, macs: targets.map { $0.mac }, firmware: fw,
            onStep: { i, n, name in
                startAt[i - 1] = Date().timeIntervalSince1970
                queueNote = "第 \(i)/\(n) 把: \(name)"
            },
            onProgress: { p in
                switch p {
                case .switchingDfu, .connecting: stage = 0
                case .starting: stage = 1
                case .uploading(let v):
                    stage = 1
                    updateRate(Double(v))
                case .validating: stage = 2
                case .completed: stage = 2; pct = 100
                default: break
                }
            })
        queueOutcomes = outcomes
        let endAt = Date().timeIntervalSince1970
        var ok = 0
        for (i, pair) in zip(outcomes, targets).enumerated() {
            let (o, kc) = pair
            let t0 = startAt[i] ?? endAt
            let t1 = i + 1 < outcomes.count ? (startAt[i + 1] ?? endAt) : endAt
            if o.ok { ok += 1 }
            BatteryCare.addDFURecord(DFURecord(mac: o.mac, name: fw.sourceName,
                                               from: kc.fw, to: fw.version ?? "",
                                               at: t0 * 1000, ok: o.ok,
                                               ms: max(0, t1 - t0) * 1000))
        }
        queueNote = "队列结束: 成功 \(ok) / 共 \(outcomes.count) 把"
        if ok == outcomes.count { XHaptics.success() }
        for pair in zip(outcomes, targets) where pair.0.ok {
            await verifyAfterUpgrade(pair.1, fw)
        }
    }

    private func updateRate(_ v: Double) {
        pct = v
        let now = Date().timeIntervalSince1970
        defer { lastProg = (v, now) }
        guard let last = lastProg, v > last.pct else { return }
        let dt = now - last.at
        guard dt > 0.2 else { return }
        let inst = (v - last.pct) / dt
        rate = rate == 0 ? inst : rate * 0.7 + inst * 0.3
        guard v > 3, rate > 0.01 else { remainText = ""; return }
        let sec = Int((100 - v) / rate)
        remainText = sec >= 90 ? "约剩 \(Int(ceil(Double(sec) / 60))) 分钟" : "约剩 \(max(sec, 1)) 秒"
    }

    private func verifyAfterUpgrade(_ kc: Keychain, _ fw: FirmwarePackage) async {
        verifyText = "升级已提交 — 门锁重启中, 自动校验版本…"
        try? await Task.sleep(for: .seconds(9))
        do {
            try await app.lock.ensureConnected(mac: kc.mac)
            let st = try await app.lock.getStatus(mac: kc.mac)
            if let v = fw.version, !st.firmware.isEmpty {
                if FirmwareKit.versionLt(st.firmware, v) || FirmwareKit.versionLt(v, st.firmware) {
                    verifyText = "锁内版本 v\(st.firmware) 与包版本 v\(v) 不一致, 请到锁信息名片复核"
                } else {
                    verified = true
                    verifyText = "校验通过 · 锁内已是 v\(st.firmware)"
                    var kc2 = kc
                    kc2.fw = st.firmware
                    DB.saveKeychain(kc2)
                    app.loadDevices()
                }
            } else {
                verifyText = "已读到状态但版本为空, 请到锁信息名片复核"
            }
        } catch {
            verifyText = "门锁还在重启, 暂未读回版本 — 升级已提交, 稍后到锁信息名片复核即可"
        }
    }
}
