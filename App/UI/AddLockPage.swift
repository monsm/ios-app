//
//  AddLockPage.swift
//  添加设备 · 全新重写 (2026-10-21)
//
//  ═══════════════════════════════════════════════════════════
//  视觉冲击力: 配网四步做成一条会走的脊梁
//  ═══════════════════════════════════════════════════════════
//
//  旧版: List + 四段 switch + 一堆 Section, 步骤感靠文字"步骤 1/4"
//
//  新版:
//    · 顶部一条 4 节点进度脊梁 (发现 → 校验 → 初始化 → 命名)
//    · 已过的节点填铜色 + 勾, 当前节点呼吸放大, 未到的空心
//    · 扫描时: 雷达波纹从中心扩散 (reduceMotion 时改静态)
//    · 设备行: 信号强度做 3 格竖条, 强信号铜色发光
//    · 配网中: 7 步日志以"打字机"方式逐行落下
//

import SwiftUI
import CoreBluetooth

/// 添加设备页
struct AddLockPage: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Flow { case scan, pairing, naming, done }

    @State private var flow: Flow = .scan
    @State private var step = 0
    @State private var devices: [BLEAdvDevice] = []
    @State private var scanning = false
    @State private var pairSteps: [String] = []
    @State private var pairError = ""
    @State private var pairedKC: Keychain?
    @State private var nickname = ""
    @State private var place = ""
    @State private var dupMac: (name: String, mac: String)?
    @State private var probingId: String?

    @State private var pulse = false
    @State private var scanTask: Task<Void, Never>?

    private let stepNames = ["发现", "校验", "初始化", "命名"]

    var body: some View {
        ZStack {
            XPalette.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                if flow != .done {
                    spine
                        .padding(.horizontal, XSpace.gutter)
                        .padding(.top, XSpace.m)
                        .padding(.bottom, XSpace.l)
                }

                ScrollView {
                    VStack(spacing: XSpace.l) {
                        switch flow {
                        case .scan:    scanStage
                        case .pairing: pairingStage
                        case .naming:  namingStage
                        case .done:    doneStage
                        }
                    }
                    .padding(.horizontal, XSpace.gutter)
                    .padding(.bottom, XSpace.xxl)
                }
            }
        }
        .navigationTitle("添加设备")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("关闭") {
                    if flow == .pairing { rollback(reason: "") }
                    scanTask?.cancel()
                    dismiss()
                }
            }
        }
        .confirmationDialog("这把锁已经添加过",
                            isPresented: Binding(get: { dupMac != nil },
                                                 set: { if !$0 { dupMac = nil } }),
                            titleVisibility: .visible) {
            Button("跳转到已有锁") {
                if let dup = dupMac {
                    app.loadDevices()
                    app.select(dup.mac)
                    app.requestRoute(.device)
                }
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let dup = dupMac {
                Text("「\(dup.name)」(\(dup.mac)) 已在本机台账中, 无需重新配网。重新配网会换掉门锁密钥, 旧手机钥匙将失效。")
            }
        }
        .onAppear {
            if !reduceMotion { pulse = true }
            if flow == .scan && devices.isEmpty {
                scanTask = Task { await scan() }
            }
        }
        .onDisappear { scanTask?.cancel() }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 进度脊梁
    // ═══════════════════════════════════════════════════════

    private var spine: some View {
        HStack(spacing: 0) {
            ForEach(0..<stepNames.count, id: \.self) { i in
                let done = i < step
                let current = i == step
                VStack(spacing: XSpace.xs) {
                    ZStack {
                        Circle()
                            .fill(done ? XPalette.accent
                                  : (current ? XPalette.accent.opacity(0.18) : XPalette.surfaceAlt))
                            .frame(width: 30, height: 30)
                            .overlay(
                                Circle().strokeBorder(
                                    done || current ? XPalette.accent : XPalette.hairline,
                                    lineWidth: current ? 2 : 1)
                            )
                            .scaleEffect(current && !reduceMotion && pulse ? 1.12 : 1.0)
                            .animation(reduceMotion ? nil
                                       : .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                                       value: pulse)

                        if done {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(XPalette.onAccent)
                        } else {
                            Text("\(i + 1)")
                                .xFont(.caption, weight: .semibold)
                                .foregroundStyle(current ? XPalette.accentText : XPalette.textTertiary)
                        }
                    }
                    Text(stepNames[i])
                        .xFont(.caption2, weight: current ? .semibold : .regular)
                        .foregroundStyle(done ? XPalette.text
                                         : (current ? XPalette.accentText : XPalette.textTertiary))
                }
                .frame(maxWidth: .infinity)

                if i < stepNames.count - 1 {
                    Rectangle()
                        .fill(i < step ? XPalette.accent : XPalette.hairline)
                        .frame(height: 2)
                        .offset(y: -14)
                        .animation(XMotion.standard, value: step)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("配网进度")
        .accessibilityValue("第 \(step + 1) 步, 共 4 步: \(stepNames[min(step, 3)])")
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - ① 发现
    // ═══════════════════════════════════════════════════════

    private var scanStage: some View {
        VStack(spacing: XSpace.l) {
            // 雷达
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(XPalette.accent.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 80 + CGFloat(i) * 44, height: 80 + CGFloat(i) * 44)
                        .scaleEffect(reduceMotion ? 1 : (pulse ? 1.06 : 0.94))
                        .opacity(scanning ? 1 : 0.25)
                        .animation(reduceMotion ? nil
                                   : .easeInOut(duration: 1.8).repeatForever(autoreverses: true)
                                     .delay(Double(i) * 0.18),
                                   value: pulse)
                }
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: XMetric.decorIcon(40), weight: .light))
                    .foregroundStyle(scanning ? XPalette.accent : XPalette.textTertiary)
            }
            .frame(height: 200)
            .accessibilityHidden(true)

            Text(scanning ? "正在搜索门锁…" : (devices.isEmpty ? "附近没有发现门锁" : "发现 \(devices.count) 把锁"))
                .xFont(.headline)
                .foregroundStyle(XPalette.text)
                .contentTransition(.opacity)

            Text("请让门锁上电, 并靠近手机 1 米内")
                .xFont(.footnote)
                .foregroundStyle(XPalette.textSub)
                .multilineTextAlignment(.center)

            if !pairError.isEmpty { errorBanner }

            VStack(spacing: XSpace.s) {
                ForEach(devices, id: \.deviceId) { d in
                    deviceRow(d)
                }
            }

            Button {
                scanTask = Task { await scan() }
            } label: {
                Label(scanning ? "搜索中…" : "重新扫描", systemImage: "arrow.clockwise")
            }
            .buttonStyle(XSecondaryButtonStyle())
            .disabled(scanning)
        }
    }

    private func deviceRow(_ d: BLEAdvDevice) -> some View {
        let adv = ZKProtocol.parseAdv(d.advertisHex)
        // ⚠ MAC 一律取显示序 (ZKProtocol.lockMac)。2026-10-17 真机教训: 用 adv.macRaw 时
        // 包络里还会 reversePairs 一次 ⇒ 锁收到反的 TargetMAC, 05 之后每步回 rc=12
        // "mac地址不正确", 且台账多一份永远对不上的幽灵记录。
        let lockMac = adv.flatMap { ZKProtocol.lockMac(fromAdv: $0) }
        let display = adv?.macDisplay ?? "—"
        let bars = signalBars(d.rssi)
        return Button {
            guard let mac = lockMac else {
                app.showToast("这把锁的广播里没有 MAC, 无法配对")
                return
            }
            // 255 去重拦截: 本地已有 → 不进配网
            if let existing = DB.keychain(mac) {
                dupMac = (LockArchive.displayName(existing), display)
                return
            }
            XHaptics.trigger.impactOccurred()
            Task { await pair(d, mac) }
        } label: {
            HStack(spacing: XSpace.m) {
                Image(systemName: "lock.fill")
                    .font(.system(size: XIcon.md, weight: .medium))
                    .foregroundStyle(XPalette.accentText)
                    .frame(width: 44, height: 44)
                    .background(XPalette.accent.opacity(XOpacity.badge), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(d.name.isEmpty ? "未知设备" : d.name)
                        .xFont(.body, weight: .medium)
                        .foregroundStyle(XPalette.text)
                        .lineLimit(1)
                    Text(lockMac == nil ? "广播无 MAC" : display)
                        .xFont(.caption.monospaced())
                        .foregroundStyle(XPalette.textSub)
                }

                Spacer(minLength: 0)

                // 信号 3 格
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(i < bars ? (bars == 3 ? XPalette.accent : XPalette.warn)
                                  : XPalette.hairline)
                            .frame(width: 3, height: 6 + CGFloat(i) * 4)
                    }
                }
                .accessibilityHidden(true)

                Image(systemName: "chevron.right")
                    .font(.system(size: XIcon.xs, weight: .semibold))
                    .foregroundStyle(XPalette.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(XSpace.card)
            .background(
                RoundedRectangle(cornerRadius: XRadius.card, style: .continuous)
                    .fill(XPalette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: XRadius.card, style: .continuous)
                            .strokeBorder(XPalette.hairline, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(d.name), 信号 \(bars) 格, 双击开始配对")
    }

    private func signalBars(_ rssi: Int) -> Int {
        if rssi >= -60 { return 3 }
        if rssi >= -75 { return 2 }
        return 1
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - ②③ 配网中
    // ═══════════════════════════════════════════════════════

    private var pairingStage: some View {
        VStack(spacing: XSpace.l) {
            ProgressView()
                .controlSize(.large)
                .padding(.top, XSpace.xl)

            Text(step == 1 ? "正在校验门锁…" : "正在初始化…")
                .xFont(.headline)
                .foregroundStyle(XPalette.text)

            Text("请保持手机靠近门锁, 不要锁屏")
                .xFont(.footnote)
                .foregroundStyle(XPalette.textSub)

            // 7 步日志
            VStack(alignment: .leading, spacing: XSpace.xs) {
                ForEach(Array(pairSteps.enumerated()), id: \.offset) { i, s in
                    HStack(spacing: XSpace.s) {
                        Image(systemName: "checkmark")
                            .font(.system(size: XIcon.xs, weight: .bold))
                            .foregroundStyle(XPalette.ok)
                        Text(s)
                            .xFont(.caption.monospaced())
                            .foregroundStyle(XPalette.textSub)
                        Spacer(minLength: 0)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .accessibilityLabel("第 \(i + 1) 步完成: \(s)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(XSpace.card)
            .background(XPalette.surfaceSunken,
                        in: RoundedRectangle(cornerRadius: XRadius.control, style: .continuous))
            .animation(XMotion.soft, value: pairSteps.count)

            if !pairError.isEmpty { errorBanner }
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - ④ 命名
    // ═══════════════════════════════════════════════════════

    private var namingStage: some View {
        VStack(spacing: XSpace.l) {
            ZStack {
                Circle()
                    .fill(XPalette.ok.opacity(XOpacity.badge))
                    .frame(width: 120, height: 120)
                Image(systemName: "checkmark")
                    .font(.system(size: XMetric.decorIcon(48), weight: .light))
                    .foregroundStyle(XPalette.ok)
            }
            .padding(.top, XSpace.l)

            Text("配网成功")
                .xFont(.title2, weight: .semibold)
                .foregroundStyle(XPalette.text)

            Text("给这把锁起个名字, 方便以后区分")
                .xFont(.footnote)
                .foregroundStyle(XPalette.textSub)

            XPanel(kind: .group) {
                VStack(alignment: .leading, spacing: XSpace.m) {
                    labeledField("昵称", text: $nickname, placeholder: "如 婆婆家·入户门")
                    labeledField("场所", text: $place, placeholder: "如 玄关 / 车库")
                }
            }

            XBusyButton(title: "完成添加", systemImage: "checkmark",
                        busy: false, style: .primary) {
                saveName()
            }
            .disabled(nickname.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(nickname.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
        }
    }

    private func labeledField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: XSpace.xs) {
            Text(label)
                .xFont(.caption)
                .foregroundStyle(XPalette.textSub)
            TextField(placeholder, text: text)
                .xFont(.body)
                .autocorrectionDisabled()
                .padding(XSpace.s)
                .background(XPalette.surfaceSunken,
                            in: RoundedRectangle(cornerRadius: XRadius.min, style: .continuous))
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 完成
    // ═══════════════════════════════════════════════════════

    private var doneStage: some View {
        VStack(spacing: XSpace.l) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: XMetric.decorIcon(72), weight: .light))
                .foregroundStyle(XPalette.ok)
                .padding(.top, XSpace.xxl)

            Text("已添加")
                .xFont(.title, weight: .semibold)
                .foregroundStyle(XPalette.text)

            Text(nickname)
                .xFont(.subheadline)
                .foregroundStyle(XPalette.textSub)

            Button("完成") { dismiss() }
                .buttonStyle(XPrimaryButtonStyle(fullWidth: false))
                .padding(.top, XSpace.l)
        }
    }

    private var errorBanner: some View {
        HStack(alignment: .top, spacing: XSpace.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: XIcon.sm, weight: .semibold))
                .foregroundStyle(XPalette.danger)
            Text(pairError)
                .xFont(.footnote)
                .foregroundStyle(XPalette.danger)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(XSpace.card)
        .background(XPalette.danger.opacity(XOpacity.wash),
                    in: RoundedRectangle(cornerRadius: XRadius.control, style: .continuous))
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 核心逻辑 (与旧实现等价)
    // ═══════════════════════════════════════════════════════

    @MainActor
    private func scan() async {
        guard !scanning, flow == .scan else { return }
        scanning = true
        pairError = ""
        devices.removeAll()
        do {
            try await BLEService.shared.startScan(allowDuplicates: true, timeoutMs: 10000)
            let deadline = Date().addingTimeInterval(10)
            while Date() < deadline, !Task.isCancelled {
                devices = BLEService.shared.allDiscovered()
                    .map { d -> (dev: BLEAdvDevice, score: Int) in (d, scoreAdv(d)) }
                    .sorted { a, b in
                        if a.score != b.score { return a.score > b.score }
                        if a.dev.rssi != b.dev.rssi { return a.dev.rssi > b.dev.rssi }
                        return a.dev.name < b.dev.name
                    }
                    .map { $0.dev }
                do { try await Task.sleep(nanoseconds: 400_000_000) } catch { break }
            }
        } catch {
            app.showToast(error.localizedDescription)
        }
        BLEService.shared.stopScan()
        scanning = false
    }

    private func scoreAdv(_ d: BLEAdvDevice) -> Int {
        let adv = ZKProtocol.parseAdv(d.advertisHex)
        let svcHit = d.serviceUUIDs.contains {
            $0.uppercased().contains("6E400001") || $0.uppercased().contains("FE90")
        }
        let nameHit = d.name.range(of: "ZK|KX|JZ|JINGZAO|ZELKOVA|LOCK|SMART",
                                   options: [.regularExpression, .caseInsensitive]) != nil
        return (svcHit ? 2 : 0) + (nameHit ? 2 : 0) + (adv != nil ? 4 : 0)
    }

    private func pair(_ d: BLEAdvDevice, _ mac: String) async {
        guard flow == .scan else { return }
        flow = .pairing
        step = 1
        pairSteps.removeAll()
        pairError = ""
        do {
            let kc = try await LockService.shared.pair(deviceId: d.deviceId, mac: mac) { progress in
                pairSteps.append(progress)
                if progress.hasPrefix("步骤") {
                    let numStr = progress.dropFirst(3).prefix(while: { $0.isNumber })
                    if let n = Int(numStr), n >= 4 { step = 2 }
                }
            }
            LockService.shared.disconnect()
            pairedKC = kc
            nickname = defaultName(for: kc)
            step = 3
            flow = .naming
            XHaptics.success()
        } catch {
            rollback(reason: error.localizedDescription)
            XHaptics.failure()
        }
    }

    private func rollback(reason: String) {
        LockService.shared.disconnect()
        if !pairTargetMac.isEmpty { DB.removeKeychain(pairTargetMac) }
        DB.lastDevice = ""
        pairSteps.removeAll()
        pairError = reason
        pairedKC = nil
        flow = .scan
        step = 0
    }

    private var pairTargetMac: String { pairedKC?.mac ?? "" }

    private func defaultName(for kc: Keychain) -> String {
        let model = kc.pidName.isEmpty ? PidMap.productName(kc.pid) : kc.pidName
        let siblings = DB.keychains().filter { $0.pid == kc.pid && $0.mac != kc.mac }.count
        return siblings > 0 ? "\(model) · \(siblings + 1)" : model
    }

    private func saveName() {
        guard let kc0 = pairedKC else { return }
        let name = nickname.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { app.showToast("昵称不能为空"); return }

        var kc = kc0
        kc.name = name
        DB.saveKeychain(kc)

        var meta = LockArchive.meta(kc.mac)
        meta.place = place.trimmingCharacters(in: .whitespaces)
        LockArchive.save(kc.mac, meta)

        app.loadDevices()
        app.select(kc.mac)
        XHaptics.success()
        flow = .done
    }
}
