// DeviceScreens.swift —— 配对 / 自动开门 / 钥匙串与网关 / 固件 / 诊断。
//
// 这一组是"设备与工具"：低频、需要解释、失败要给出下一步。
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 配对

@MainActor
struct PairingScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var devices: [BLEAdvDevice] = []
    @State private var scanning = false
    @State private var pairing: String?
    @State private var progress = ""
    @State private var errorLine: String?
    @State private var done = false

    var body: some View {
        ScreenScroll {
            NavRow(kicker: "设置 / 配对门锁", back: { dismiss() })

            DisplayLine(text: done ? "配好了。" : "把锁\n叫醒。", size: 36)
                .padding(.top, 16)
            Text(done
                 ? "钥匙串已经写进本机。现在可以去「今日」开第一扇门。"
                 : "先把门锁恢复到配网状态（通常是长按设置键或拆开电池仓），再点开始搜索。整个过程不需要网络。")
                .type(T.F.footnote)
                .foregroundStyle(T.C.ink2)
                .lineSpacing(4)
                .padding(.top, 8)

            if done {
                PrimaryButton(title: "回到今日") { dismiss() }
                    .padding(.top, 24)
            } else {
                PrimaryButton(title: scanning ? "正在搜索…" : "开始搜索", busy: scanning) {
                    Task { await scan() }
                }
                .padding(.top, 22)

                if let pairing {
                    GlassSurface(radius: 20) {
                        HStack(spacing: 12) {
                            ProgressView().tint(T.C.brass)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("正在配对")
                                    .type(T.F.callout)
                                    .fontWeight(.medium)
                                    .foregroundStyle(T.C.ink)
                                Text(progress.isEmpty ? "正在握手…" : progress)
                                    .type(T.F.caption)
                                    .foregroundStyle(T.C.ink3)
                                    .lineLimit(3)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, 16)
                }

                if let errorLine {
                    Text(errorLine)
                        .type(T.F.caption)
                        .foregroundStyle(T.C.danger)
                        .padding(.top, 14)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SectionHead(index: "01", title: "附近的锁", trailing: "\(devices.count)")
                if devices.isEmpty {
                    EmptyNote(line: scanning ? "正在找…" : "还没有搜到。",
                              detail: scanning
                                ? "把手机靠近门锁，保持在 1 米以内。"
                                : "确认门锁已经进入配网状态，再点「开始搜索」。")
                } else {
                    ForEach(devices) { device in
                        deviceRow(device)
                    }
                }

                Text("安全说明：配对会把一把 128 位母钥写进这把锁。此后所有开锁都在本地完成，不经过服务器。")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
                    .lineSpacing(3)
                    .padding(.top, 20)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func deviceRow(_ device: BLEAdvDevice) -> some View {
        let adv = ZKProtocol.parseAdv(device.advertisHex)
        let mac = adv?.macDisplay ?? ""
        return Button {
            guard !mac.isEmpty else { return }
            Task { await pair(device: device, mac: mac) }
        } label: {
            ContentRow(symbol: "lock", title: device.name.isEmpty ? "未命名门锁" : device.name,
                       subtitle: "\(mac) · \(device.rssi) dBm" + (adv.map { " · pid \($0.pid)" } ?? ""),
                       chevron: true) {
                Text("配对")
                    .type(T.F.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(T.C.brass)
            }
        }
        .buttonStyle(.plain)
        .disabled(pairing != nil)
    }

    private func scan() async {
        scanning = true
        errorLine = nil
        devices = []
        do {
            try await BLEService.shared.startScan(allowDuplicates: false, timeoutMs: 8000)
            let deadline = Date().addingTimeInterval(8)
            while Date() < deadline {
                let found = BLEService.shared.allDiscovered().filter { adv in
                    ZKProtocol.parseAdv(adv.advertisHex)?.macDisplay != nil
                }
                if found.count != devices.count { devices = found }
                try? await Task.sleep(for: .milliseconds(300))
            }
            BLEService.shared.stopScan()
        } catch {
            errorLine = error.localizedDescription
        }
        scanning = false
    }

    private func pair(device: BLEAdvDevice, mac: String) async {
        pairing = mac
        errorLine = nil
        progress = ""
        do {
            _ = try await LockService.shared.pair(deviceId: device.deviceId, mac: mac) { line in
                Task { @MainActor in progress = line }
            }
            done = true
            await app.reload(refreshStatus: true)
        } catch {
            errorLine = error.localizedDescription
        }
        pairing = nil
    }
}

// MARK: - 自动开门

@MainActor
struct AutoOpenScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var on = AutoOpen.on
    @State private var tier = AutoOpen.faceTier
    @State private var base = -40
    @State private var lastReason: String?
    @State private var calibrating = false

    var body: some View {
        ScreenScroll {
            NavRow(kicker: "设置 / 自动开门", back: { dismiss() })

            DisplayLine(text: "走到门口，\n门自己开。", size: 34)
                .padding(.top, 16)
            Text("它只在合适的时候发生：App 在前台、本机已解锁、不在胁迫模式、不在布防时段、信号足够近、且距离上次开门超过 6 秒。")
                .type(T.F.footnote)
                .foregroundStyle(T.C.ink2)
                .lineSpacing(4)
                .padding(.top, 8)

            SwitchLine(title: "启用自动开门", detail: "默认关闭。开启后请先做一次距离标定。", isOn: $on)
                .onChange(of: on) { _, value in
                    AutoOpen.on = value
                    if value { AutoOpenController.shared.onForeground(mac: app.currentMac) }
                    else { AutoOpenController.shared.onBackground() }
                }

            SectionHead(index: "01", title: "验证档")
            SegmentedBar(items: ["靠近即开", "每次刷面容"], selected: Binding(
                get: { min(1, max(0, tier)) },
                set: { tier = $0; AutoOpen.faceTier = $0 }
            ))
            Text(tier == 0
                 ? "靠近即开：本机已解锁时不再额外验证。"
                 : "每次刷面容：进入前台后先刷一次，之后 30 秒内有效。")
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
                .padding(.top, 8)

            SectionHead(index: "02", title: "距离")
            ReadingRow(items: [
                (label: "触发", value: "\(base)", unit: "dBm"),
                (label: "释放", value: "\(AutoOpenKit.disarmThreshold(base: base))", unit: "dBm"),
                (label: "采样", value: "\(AutoOpen.autocal(app.currentMac) == nil ? 0 : 5)", unit: "次"),
            ])
            .padding(.top, 4)

            HStack(spacing: 10) {
                GhostButton(title: calibrating ? "请在门口走动…" : "重新标定", symbol: "dot.radiowaves.left.and.right") {
                    Task { await calibrate() }
                }
                GhostButton(title: "清除标定", symbol: "trash") {
                    AutoOpen.clearAutocal(app.currentMac)
                    base = AutoOpenKit.rssiBase(mac: app.currentMac)
                }
            }
            .padding(.top, 12)

            SectionHead(index: "03", title: "上次为什么没开")
            if let lastReason, !lastReason.isEmpty {
                Text(lastReason)
                    .type(T.F.callout)
                    .foregroundStyle(T.C.ink2)
                    .lineSpacing(3)
            } else {
                Text("还没有被否决过。")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
            }

            if AutoOpen.isSuspended(mac: app.currentMac) {
                Text("因防拆事件暂停中：到 \(When.ago(AutoOpen.suspendUntil(app.currentMac))) 之前不会自动开门。")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.danger)
                    .padding(.top, 10)
            }

            Text("风险：自动开门会在你不知情的时候把门打开。它默认关闭，并且永远不会在锁屏、空壳模式或布防时段触发。")
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
                .lineSpacing(3)
                .padding(.top, 20)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            base = AutoOpenKit.rssiBase(mac: app.currentMac)
            lastReason = AutoOpen.lastReject(app.currentMac)?.reason
        }
    }

    private func calibrate() async {
        calibrating = true
        defer { calibrating = false }
        var samples: [Int] = []
        try? await BLEService.shared.startScan(allowDuplicates: false, timeoutMs: 6000)
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            if let adv = BLEService.shared.allDiscovered().first(where: { device in
                guard let a = ZKProtocol.parseAdv(device.advertisHex), let mac = a.macDisplay else { return false }
                return DB.normalizeMac(mac) == DB.normalizeMac(app.currentMac)
            }) {
                samples.append(adv.rssi)
            }
            try? await Task.sleep(for: .milliseconds(350))
        }
        BLEService.shared.stopScan()
        if let p95 = AutoOpen.saveAutocal(app.currentMac, samples: samples) {
            base = p95
        } else {
            lastReason = "这次采样不到 5 个点，标定没保存。请站在门口，让手机靠近门锁再试。"
        }
    }
}

// MARK: - 钥匙串与网关

@MainActor
struct HardwareScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var busy = false
    @State private var message: String?
    @State private var ssid = ""
    @State private var password = ""

    private var dongles: [Dongle] { DB.dongles() }
    private var gateways: [Gateway] { DB.gateways() }

    var body: some View {
        ScreenScroll {
            NavRow(kicker: "设置 / 硬件", back: { dismiss() })

            DisplayLine(text: "钥匙串\n和网关。", size: 34)
                .padding(.top, 16)
            Text("钥匙串是一枚可以单独开门的硬件；网关让门锁连上你家的 WiFi。两者都是可选件。")
                .type(T.F.footnote)
                .foregroundStyle(T.C.ink2)
                .lineSpacing(4)
                .padding(.top, 8)

            SectionHead(index: "01", title: "钥匙串", trailing: "\(dongles.count)")
            ForEach(dongles) { dongle in
                ContentRow(symbol: "key", tone: .brass, title: dongle.name.isEmpty ? "钥匙串" : dongle.name,
                           subtitle: dongle.mac + (dongle.stat.map { " · \($0.power)% · \($0.ekeyCount) 把钥" } ?? ""))
            }
            HStack(spacing: 10) {
                GhostButton(title: busy ? "请稍等…" : "搜索钥匙串", symbol: "dot.radiowaves.left.and.right") {
                    Task { await scanDongle() }
                }
                GhostButton(title: "写入当前锁", symbol: "square.and.arrow.down") {
                    Task { await writeKey() }
                }
            }
            .padding(.top, 10)

            SectionHead(index: "02", title: "网关", trailing: "\(gateways.count)")
            ForEach(gateways) { gateway in
                ContentRow(symbol: "wifi.router", tone: .cool,
                           title: gateway.name.isEmpty ? "网关" : gateway.name,
                           subtitle: gateway.ssid.isEmpty ? "还未配网" : "\(gateway.ssid) · \(gateway.wifiIP)")
            }
            FieldInput(placeholder: "WiFi 名称（2.4G）", text: $ssid)
                .padding(.top, 10)
            FieldInput(placeholder: "WiFi 密码", text: $password, secure: true)
                .padding(.top, 8)
            HStack(spacing: 10) {
                GhostButton(title: busy ? "请稍等…" : "配网", symbol: "wifi") {
                    Task { await provision() }
                }
                GhostButton(title: "重启网关", symbol: "arrow.clockwise") {
                    Task { await reboot() }
                }
            }
            .padding(.top, 10)

            if let message {
                Text(message)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink2)
                    .padding(.top, 14)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("网关只把你家 WiFi 的账号密码直接交给它，不经过云端；本机只保留 SSID 与 IP。")
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
                .lineSpacing(3)
                .padding(.top, 18)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func scanDongle() async {
        busy = true
        defer { busy = false }
        do {
            let dongle = try await HardwareService.shared.scanForDongle()
            message = "找到 \(dongle.mac)，已登记。"
        } catch {
            message = error.localizedDescription
        }
    }

    private func writeKey() async {
        guard let lock = DB.keychainForUnlock(app.currentMac) else {
            message = "先配对一把锁。"
            return
        }
        guard let dongle = dongles.first else {
            message = "先搜到一枚钥匙串。"
            return
        }
        busy = true
        defer { busy = false }
        do {
            try await HardwareService.shared.writeDongleKey(dongleMac: dongle.mac, lock: lock, trackId: UInt32.random(in: 1 ... 0x7fff_ffff))
            message = "已把这把锁的 ekey 写进钥匙串。"
        } catch {
            message = error.localizedDescription
        }
    }

    private func provision() async {
        guard !ssid.isEmpty else { message = "先填 WiFi 名称。"; return }
        busy = true
        defer { busy = false }
        do {
            let gateway = try await HardwareService.shared.provisionGateway(ssid: ssid, password: password) { line in
                Task { @MainActor in message = line }
            }
            message = "网关已连上 \(gateway.ssid)。"
        } catch {
            message = error.localizedDescription
        }
    }

    private func reboot() async {
        guard let gateway = gateways.first else { message = "还没有网关。"; return }
        busy = true
        defer { busy = false }
        do {
            try await HardwareService.shared.rebootGateway(mac: gateway.mac)
            message = "重启命令已下发。"
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - 固件

@MainActor
struct DfuScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var picking = false
    @State private var package: FirmwarePackage?
    @State private var progress: Double = 0
    @State private var stateText = ""
    @State private var busy = false
    @State private var errorLine: String?

    var body: some View {
        ScreenScroll {
            NavRow(kicker: "设置 / 固件升级", back: { dismiss() })

            DisplayLine(text: "换一颗\n新的心脏。", size: 34)
                .padding(.top, 16)
            Text("支持 Nordic Secure / Legacy DFU 的厂商固件包（zip，含 manifest.json）。升级期间请留在锁旁边，不要杀 App。")
                .type(T.F.footnote)
                .foregroundStyle(T.C.ink2)
                .lineSpacing(4)
                .padding(.top, 8)

            if let package {
                GlassSurface(radius: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(package.sourceName)
                            .type(T.F.callout)
                            .fontWeight(.medium)
                            .foregroundStyle(T.C.ink)
                        Text("版本 \(package.version ?? "未知") · 固件 \(package.binSize / 1024) KB · init \(package.datSize) B")
                            .type(T.F.caption)
                            .foregroundStyle(T.C.ink3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 18)
            }

            if let current = app.lock?.firmware, !current.isEmpty {
                Text("当前锁内版本：\(current)")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
                    .padding(.top, 10)
            }

            PrimaryButton(title: package == nil ? "选择固件包" : "开始升级", busy: busy) {
                if package == nil { picking = true } else { Task { await flash() } }
            }
            .padding(.top, 22)

            if busy || !stateText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: progress)
                        .tint(T.C.brass)
                    Text(stateText)
                        .type(T.F.caption)
                        .foregroundStyle(T.C.ink3)
                }
                .padding(.top, 18)
            }

            if let errorLine {
                Text(errorLine)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.danger)
                    .padding(.top, 14)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("重要：固件包没有签名校验。只使用厂商官方渠道下载的包；升级中断可能让锁停在 bootloader。")
                .type(T.F.caption)
                .foregroundStyle(T.C.danger)
                .lineSpacing(3)
                .padding(.top, 22)
        }
        .toolbar(.hidden, for: .navigationBar)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.zip]) { result in
            handle(result)
        }
    }

    private func handle(_ result: Result<URL, Error>) {
        errorLine = nil
        switch result {
        case .success(let url):
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = [UInt8](try Data(contentsOf: url))
                package = try FirmwareKit.parse(zipData: data, fileName: url.lastPathComponent)
            } catch {
                errorLine = error.localizedDescription
            }
        case .failure(let error):
            errorLine = error.localizedDescription
        }
    }

    private func flash() async {
        guard let package, let lock = DB.keychainForUnlock(app.currentMac) else { return }
        let current = app.lock?.firmware ?? ""
        if let blocked = FirmwareKit.downgradeBlocked(current: current.isEmpty ? nil : current, pkg: package) {
            errorLine = blocked
            return
        }
        busy = true
        defer { busy = false }
        errorLine = nil
        progress = 0
        stateText = "正在让门锁进入 bootloader…"
        do {
            try await LockService.shared.enableDfu(param: 0)
            LockService.shared.disconnect()
            try? await Task.sleep(for: .seconds(2))
            let session = DFUSession(macHex: lock.mac, pid: lock.pid, pkg: package)
            session.onState = { state, text in
                Task { @MainActor in
                    stateText = text
                    if state == .completed { progress = 1 }
                }
            }
            session.onProgress = { value in
                Task { @MainActor in progress = value }
            }
            try await session.run()
            stateText = "升级完成。"
            await app.reload(refreshStatus: true)
        } catch {
            errorLine = error.localizedDescription
            stateText = "升级中断。"
        }
    }
}

// MARK: - 诊断

@MainActor
struct DiagnosticsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var busy = false
    @State private var message: String?
    @State private var raw = false

    private var frames: [String] {
        raw ? LockService.shared.recentFrames.map { FrameRedact.apply($0) } : []
    }

    var body: some View {
        ScreenScroll {
            NavRow(kicker: "设置 / 诊断", back: { dismiss() })

            DisplayLine(text: "看清\n发生了什么。", size: 34)
                .padding(.top, 16)
            Text("这里只读：不会改锁里的任何设置。")
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
                .padding(.top, 8)

            SectionHead(index: "01", title: "链路")
            ReadingRow(items: [
                (label: "状态", value: app.link.phase.rawValue, unit: nil),
                (label: "RSSI", value: app.link.lastRSSI.map { "\($0)" } ?? "—", unit: "dBm"),
                (label: "握手", value: app.link.connectMs.map { "\($0)" } ?? "—", unit: "ms"),
            ])
            .padding(.top, 4)

            HStack(spacing: 10) {
                GhostButton(title: "回声测试", symbol: "waveform") {
                    Task { await echo() }
                }
                GhostButton(title: "修复 PIN 池", symbol: "wrench") {
                    Task { await repair() }
                }
            }
            .padding(.top, 12)

            SectionHead(index: "02", title: "最近帧")
            SwitchLine(title: "显示脱敏帧", detail: "只保留帧头与 KLV 骨架，凭证值一律遮掉。", isOn: $raw)
            if frames.isEmpty {
                Text(raw ? "还没有帧。" : "打开上面的开关才会显示。")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
                    .padding(.vertical, 6)
            } else {
                let recentLines = Array(frames.suffix(8))
                ForEach(recentLines.indices, id: \.self) { index in
                    Text(recentLines[index])
                        .type(T.F.mono)
                        .foregroundStyle(T.C.ink2)
                        .lineLimit(2)
                        .padding(.vertical, 5)
                }
            }

            if let message {
                Text(message)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink2)
                    .padding(.top, 14)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SectionHead(index: "03", title: "本机")
            Text("App 版本 1.0 · 协议层 \(app.lock?.model ?? "—") · 数据全部在本机")
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
                .padding(.top, 4)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func echo() async {
        busy = true
        defer { busy = false }
        do {
            let probe = try await LockService.shared.sendEcho("123456")
            message = "回声测试通过 · rc=\(probe.rc)"
        } catch {
            message = error.localizedDescription
        }
    }

    private func repair() async {
        guard let kc = DB.keychainForUnlock(app.currentMac) else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await LockService.shared.repairPool(m: kc.mac) { line in
                Task { @MainActor in message = line }
            }
            message = "PIN 池已重写。其他设备上的旧钥匙会失效，本机钥匙仍然可用。"
            await app.reload()
        } catch {
            message = error.localizedDescription
        }
    }
}
