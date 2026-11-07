// DeviceScreens.swift —— 配对 / 自动开门 / 钥匙串与网关 / 固件 / 诊断。
//
// 这一组是"设备与工具"：低频、需要解释、失败要给出下一步。
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 配对

@MainActor
struct PairingScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var devices: [BLEAdvDevice] = []
    @State private var scanning = false
    @State private var pairing: String?
    @State private var progress = ""
    @State private var errorLine: String?
    @State private var done = false
    // E7：配对流程防护 —— 可中止的任务句柄、命名步骤、连通探测。
    @State private var pairTask: Task<Void, Never>?
    @State private var naming = false
    @State private var pairedMac = ""
    @State private var nickname = ""
    @State private var place = ""
    @State private var probing: String?
    @State private var probeText: [String: String] = [:]
    /// F17：配对向导的结构化进度（引擎给的是「步骤 N/7: …」，这里解成可渲染的进度）。
    @State private var pairProgress: TaskProgress?
    /// F17：失败的结构化描述（给 FailureCard 用）。
    @State private var pairFailure: ScreenFailure?

    var body: some View {
        ScreenScroll {
            NavRow(kicker: "设置 / 配对门锁", back: { dismiss() })

            if naming {
                // E7 命名步骤：配对链已跑完，握手成功后才轮到起名。
                // 直接把锁顶进「当前锁」而不给名字，多锁用户会在门页看到两把「未命名门锁」。
                DisplayLine(text: "给它\n起个名字。", size: 36)
                    .padding(.top, 16)
                Text("配对已经完成，锁里已有你那把母钥。名字只是本机的标签。")
                    .type(T.F.footnote)
                    .foregroundStyle(T.C.ink2)
                    .lineSpacing(4)
                    .padding(.top, 8)

                SectionHead(index: "01", title: "称呼")
                FieldInput(placeholder: "例如：玄关·入户门", text: $nickname)
                    // 锁名会出现在页头 Kicker/记录行/切换器里（那些都 lineLimit(1)），
                    // 但输入侧也该有界：与成员建档（12 字）同一口径，取 16。
                    .onChange(of: nickname) { _, newValue in
                        if newValue.count > 16 { nickname = String(newValue.prefix(16)) }
                    }
                SectionHead(index: "02", title: "地点（可选）")
                FieldInput(placeholder: "玄关 / 车库 / 后门", text: $place)
                if let hint = duplicateNameHint {
                    Text(hint)
                        .type(T.F.caption)
                        .foregroundStyle(T.C.danger)
                        .lineSpacing(3)
                        .padding(.top, 8)
                }
                PrimaryButton(title: "完成", enabled: !nickname.trimmingCharacters(in: .whitespaces).isEmpty) {
                    commitName()
                }
                .padding(.top, 22)
            } else if done {
                // 这一页是设置栈里的 pushed 页：`dismiss()` 只弹回设置首页，
                // 按钮却写着「回到今日」。真的切 Tab 并关掉设置 sheet。
                PrimaryButton(title: "回到今日") {
                    router.tab = .today
                    router.todayPath = []
                    router.settingsOpen = false
                }
                .padding(.top, 24)
            } else {
                // F17：配对前检查清单。先把这几件事说清楚，再去搜 ——
                // 「搜不到锁」十有八九是其中一条没做到。
                preflightSection

                PrimaryButton(title: scanning ? "正在搜索…" : "开始搜索", busy: scanning) {
                    Task { await scan() }
                }
                .padding(.top, 22)

                if pairing != nil {
                    // F17/F42：进度用统一的进度条 —— 引擎给的是「步骤 N/7: …」，
                    // 这里解成「第 N 步 / 共 7 步」+ 这一步在做什么。
                    if let pairProgress {
                        ProgressMeter(progress: pairProgress) {
                            pairTask?.cancel()
                            rollback("已中止：配网没有跑完，锁未被改动。")
                        }
                        .padding(.top, 16)
                    } else {
                        GlassSurface() {
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
                    // E7：中止并回滚 —— 配网不是非跑完不可。cancel 之后锁侧要么没写、
                    // 要么停在可重来的重置态；本机则断开链路、退回发现列表。
                    GhostButton(title: L("pair.wizard.rollback"), symbol: "xmark.circle") {
                        pairTask?.cancel()
                        rollback("已中止：链路已断开，锁没有被改一半就留着。")
                    }
                    .padding(.top, 10)
                }

                // F17：失败走统一的失败卡（有分类、有下一步），不再是一行红字。
                if let pairFailure {
                    FailureCard(failure: pairFailure)
                        .padding(.top, 14)
                } else if let errorLine {
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
                Text("长按一台锁可以做连通探测：只发一条回声命令，不写入任何东西。")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
                    .lineSpacing(3)
                    .padding(.top, 6)

                Text("安全说明：配对会把一把 128 位母钥写进这把锁。此后所有开锁都在本地完成，不经过服务器。")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
                    .lineSpacing(3)
                    .padding(.top, 20)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        // 中途离开这一页 = 已中止。cancel + 断链路，别留半条配网连接挂着。
        .onDisappear {
            if pairTask != nil {
                pairTask?.cancel()
                LockService.shared.disconnect()
                pairTask = nil
                pairing = nil
                progress = ""
            }
        }
    }

    /// F17：配对前的检查清单。
    ///
    /// 每一条都给出**现在能不能确认**：
    ///  · 蓝牙 —— 系统状态，直接读；
    ///  · 门锁通电 / 恢复配网态 —— 只能靠「搜得到它」来间接确认，
    ///    所以搜到之前这两条永远是「待确认」，不假装已完成。
    private var preflightSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHead(index: "00", title: "配对前先确认")
            VStack(alignment: .leading, spacing: T.S.s) {
                checkRow(symbol: "dot.radiowaves.left.and.right",
                         title: "蓝牙已开启",
                         detail: BLEService.shared.isPoweredOn ? "已开启" : "没有蓝牙就搜不到锁",
                         ok: BLEService.shared.isPoweredOn)
                checkRow(symbol: "bolt.fill",
                         title: "门锁已通电",
                         detail: "门锁背面有电（一般就是电池仓）",
                         ok: nil)
                checkRow(symbol: "arrow.triangle.2.circlepath",
                         title: "门锁已恢复到配网状态",
                         detail: "在门锁键盘上按住重置键几秒，听到提示音",
                         ok: nil)
                checkRow(symbol: "figure.walk.arrival",
                         title: "手机就在门锁旁边",
                         detail: "1 米以内最稳",
                         ok: devices.isEmpty ? nil : true)
            }
            .padding(.vertical, T.S.s)
        }
    }

    private func checkRow(symbol: String, title: String, detail: String, ok: Bool?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ok == true ? "checkmark.circle" : (ok == false ? "xmark.circle" : "circle.dashed"))
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(ok == true ? T.C.ok : (ok == false ? T.C.danger : T.C.ink4))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .type(T.F.footnote)
                    .fontWeight(.medium)
                    .foregroundStyle(T.C.ink)
                Text(detail)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func deviceRow(_ device: BLEAdvDevice) -> some View {
        let adv = ZKProtocol.parseAdv(device.advertisHex)
        let mac = adv?.macDisplay ?? ""
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                guard !mac.isEmpty else { return }
                pair(device: device, mac: mac)
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
            .disabled(pairing != nil || naming)
            // E7：长按 = 连通探测。写之前先知道这条链路能不能说话。
            .contextMenu {
                Button {
                    Task { await probe(device, mac: mac) }
                } label: {
                    Label("连通探测", systemImage: "dot.radiowaves.left.and.right")
                }
            }
            if let line = probeText[mac] {
                Text((probing == mac ? "探测中… " : "") + line)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink2)
                    .lineSpacing(2)
                    .padding(.top, 4)
                    .padding(.bottom, 4)
            }
        }
    }

    private func scan() async {
        // 空壳里不扫描：这会真的开无线电，并把附近门锁的名称 / MAC / RSSI / pid
        // 列在屏幕上。`pair()` 的守卫发生在扫描之后，挡不住这一段。
        guard !DB.isDecoy else {
            errorLine = "当前无法搜索，请稍后再试。"
            return
        }
        scanning = true
        errorLine = nil
        devices = []
        // B45：这次扫描有理由（配对），离开页面时会释放。
        ScanPolicy.acquire("pairing")
        defer { ScanPolicy.release("pairing") }
        do {
            try await BLEService.shared.startScan(allowDuplicates: false, timeoutMs: 8000)
            let deadline = Date().addingTimeInterval(8)
            while Date() < deadline {
                let found = BLEService.shared.allDiscovered().filter { adv in
                    ZKProtocol.parseAdv(adv.advertisHex)?.macDisplay != nil
                }
                // 比「数量」而不是比「内容」：扫到一台换掉另一台时数量不变，
                // 列表却停在旧的那台上，用户点了配对会配错机器。
                if found.map(\.deviceId) != devices.map(\.deviceId) { devices = found }
                try? await Task.sleep(for: .milliseconds(300))
            }
            BLEService.shared.stopScan()
        } catch {
            errorLine = error.localizedDescription
        }
        scanning = false
    }

    private func pair(device: BLEAdvDevice, mac: String) {
        // 双击/两指同时点会各起一个 Task；两个握手流程交错会写下两套钥匙材料。
        // check-and-set 在 MainActor 上同步跑到第一个 await 前是原子的。
        guard pairing == nil, pairTask == nil else { return }
        // 空壳里不配对：配对会真的握手、写本机钥匙串，并让一台新锁进入这台手机的台账。
        // 界面看起来只是"连了一把锁"，退出空壳后却多出一条真实记录。
        guard !DB.isDecoy else {
            errorLine = "暂时无法配对，请稍后再试。"
            return
        }
        pairing = mac
        errorLine = nil
        progress = ""
        // E7：把链路握在手里 —— 中止按钮与 onDisappear 都靠这个句柄 cancel。
        pairTask = Task {
            do {
                let kc = try await LockService.shared.pair(deviceId: device.deviceId, mac: mac) { line in
                    Task { @MainActor in
                        progress = cleanStep(line)
                        // F17：把引擎的「步骤 N/7: …」解成结构化进度。
                        if let p = PairingScreen.progress(from: line) { pairProgress = p }
                    }
                }
                if Task.isCancelled { rollback("已中止：配网没有跑完，锁未被改动。"); return }
                pairing = nil
                pairProgress = nil
                pairedMac = mac
                // 命名预填型号：pidName 缺省时退到产品名。
                nickname = kc.pidName.isEmpty ? PidMap.productName(kc.pid) : kc.pidName
                place = ""
                naming = true
            } catch {
                if Task.isCancelled { rollback("已中止：配网没有跑完，锁未被改动。"); return }
                pairFailure = ErrorCopy.failure(error)
                rollback((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    /// 把引擎的进度行解成结构化进度。
    ///
    /// 引擎给的是「步骤 3/7: cmd 05 交换密钥 （先建通讯会话）」——
    /// 命令号对用户没有意义，这里只留「第几步」与「在做什么」。
    static func progress(from line: String) -> TaskProgress? {
        guard let r = line.range(of: #"步骤\s*(\d+)\s*/\s*(\d+)\s*[:：]\s*(.+)"#,
                                 options: .regularExpression) else { return nil }
        let parts = line[r].split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let head = String(parts[0])
        var detail = String(parts[1])
        // 去掉命令号（cmd 05 之类），留着纯人话。
        detail = detail.replacingOccurrences(of: #"cmd\s*[0-9A-Fa-f]+"#,
                                             with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let nums = head.split(whereSeparator: { $0 == "/" || $0 == " " || $0 == ":" })
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let step = nums.first ?? 0
        let total = nums.count > 1 ? (nums[1] == 0 ? 7 : nums[1]) : 7
        return TaskProgress(title: "第 \(step) 步 / 共 \(total) 步",
                            detail: detail,
                            step: step,
                            total: total,
                            cancellable: true,
                            fraction: total > 0 ? Double(step) / Double(total) : nil)
    }

    /// E7：中止/失败后的回滚。文案说「链路已断开」就必须真的断开 ——
    /// 否则再点一次配对会撞上「已有连接」。
    @MainActor
    private func rollback(_ reason: String) {
        pairTask = nil
        LockService.shared.disconnect()
        pairing = nil
        progress = ""
        pairProgress = nil
        naming = false
        pairedMac = ""
        errorLine = reason
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

    /// E7：连通探测 —— 对着一台还没配对的锁发回声命令，验证链路但不写任何东西。
    private func probe(_ device: BLEAdvDevice, mac: String) async {
        // probeEcho 内部会 connect + 用完即 disconnect —— 配对进行中调用会把配对链路掐断。
        // 行按钮有 .disabled，但 contextMenu 在部分系统版本不吃 .disabled，这里再守一道。
        guard probing == nil, pairing == nil, !naming else { return }
        probing = mac
        defer { probing = nil }
        do {
            let r = try await LockService.shared.probeEcho(deviceId: device.deviceId)
            probeText[mac] = r.matched
                ? "回声一致 · 往返 \(r.ms) ms —— 链路是通的，可以配对"
                : "回声不匹配 · 回执码 \(r.rc) —— 能连上，但握手存疑"
        } catch {
            probeText[mac] = "探测失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// 已有同名锁时的提醒（不拦）。比对的是显示名。
    private var duplicateNameHint: String? {
        let n = nickname.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return nil }
        let selfMac = DB.normalizeMac(pairedMac)
        guard let first = DB.keychains().first(where: {
            DB.normalizeMac($0.mac) != selfMac && LockArchive.displayName($0) == n
        }) else { return nil }
        let m = LockArchive.meta(first.mac)
        return "已经有另一把锁叫「\(n)」\(m.place.isEmpty ? "" : "（\(m.place)）")了 —— 两把同名在门页里分不出来。建议换个称呼，或把地点写清楚。"
    }

    /// E7：命名落库 —— 改钥匙串名、（可选）写地点副标题，设为当前锁，再整体重载。
    private func commitName() {
        let name = nickname.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let mac = pairedMac
        guard !mac.isEmpty else {
            naming = false
            done = true
            return
        }
        if var kc = DB.keychain(mac) {
            kc.name = name
            DB.saveKeychain(kc)
        }
        let p = place.trimmingCharacters(in: .whitespaces)
        if !p.isEmpty {
            var m = LockArchive.meta(mac)
            m.place = p
            LockArchive.save(mac, m)
        }
        DB.currentMac = mac
        naming = false
        done = true
        Task { await app.reload(refreshStatus: true) }
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
    @State private var calMessage: String?
    /// B21：标定 2.0 的采样点（近/远）。
    @State private var calSamples: [AutoOpenCalibration.Sample] = []

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
                (label: "标定", value: calText, unit: nil),
            ])
            .padding(.top, 4)

            HStack(spacing: 10) {
                GhostButton(title: calibrating ? "请在门口走动…" : "重新标定", symbol: "dot.radiowaves.left.and.right") {
                    Task { await calibrate() }
                }
                GhostButton(title: "清除标定", symbol: "trash") {
                    if AutoOpen.autocal(app.currentMac) == nil {
                        calMessage = "还没有标定可清除。"
                    } else {
                        AutoOpen.clearAutocal(app.currentMac)
                        base = AutoOpenKit.rssiBase(mac: app.currentMac)
                        calMessage = "已清除标定。"
                    }
                }
            }
            .padding(.top, 12)
            .disabled(calibrating)
            .opacity(calibrating ? 0.55 : 1)

            if let calMessage {
                Text(calMessage)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
                    .padding(.top, 8)
            }

            // B21：标定 2.0 —— 近处与远处**都要采**。
            //
            // 原来只采一处、取 P95：那样阈值是猜的（不知道「远」到底是多远）。
            // 现在两边都采，阈值取两者之间；再加上曲线，让用户看得见信号怎么变。
            SectionHead(index: "03", title: "标定曲线")
            Text("站在门口采「近」，走开两三米采「远」。两处都采过，阈值才算数。")
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
                .lineSpacing(3)
                .padding(.top, 4)

            if !calSamples.isEmpty {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(calSamples) { s in
                        VStack(spacing: 2) {
                            Rectangle()
                                .fill(s.phase == .near ? T.C.brass : T.C.ink4)
                                .frame(height: CGFloat(max(6, min(48, (s.rssi + 100) * 0.7))))
                            Text(s.phase == .near ? "近" : "远")
                                .type(T.F.caption)
                                .foregroundStyle(T.C.ink3)
                        }
                    }
                }
                .frame(height: 60, alignment: .bottom)
                .padding(.top, 10)
            }

            HStack(spacing: 10) {
                GhostButton(title: "采一个近点", symbol: "figure.walk.arrival") {
                    recordCalibration(.near)
                }
                GhostButton(title: "采一个远点", symbol: "figure.walk.departure") {
                    recordCalibration(.far)
                }
            }
            .padding(.top, 12)

            Text(AutoOpenCalibration.summary(mac: app.currentMac))
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
                .padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)

            SectionHead(index: "04", title: "上次为什么没开")
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
                // `suspendUntil` 是**未来**的时刻。原先喂给 `When.ago`，
                // 它算出差值、夹到 0、说「刚刚」—— 整句变成「到 刚刚 之前不会自动开门」。
                Text("因防拆事件暂停中：还要 \(When.until(AutoOpen.suspendUntil(app.currentMac))) 才会恢复自动开门。")
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
            calSamples = AutoOpenCalibration.plan(mac: app.currentMac).samples
        }
    }

    /// 标定状态。采样点数 Engine 没存（只存 p95 与时间），所以这里不编一个「5 次」出来 ——
    /// 显示的必须是真知道的东西。
    private var calText: String {
        guard let cal = AutoOpen.autocal(app.currentMac) else { return "未标定" }
        return "已标定 · " + When.ago(Int64(cal.at * 1000))
    }

    /// 采一个标定点（B21）。读一次当前信号，记进档案。
    private func recordCalibration(_ phase: AutoOpenCalibration.Phase) {
        guard !DB.isDecoy else {
            calMessage = "当前无法读取，请稍后再试。"
            return
        }
        LinkSenseModel.shared.readRSSI { value in
            Task { @MainActor in
                guard let value else {
                    calMessage = "没读到信号 —— 再靠近一点试一次。"
                    return
                }
                let plan = AutoOpenCalibration.record(mac: app.currentMac, phase: phase, rssi: value)
                calSamples = plan.samples
                calMessage = "采到 \(value) dBm · \(phase == .near ? "近点" : "远点")"
                // 标定变了 ⇒ 底噪基线也要跟着换，否则触发档位还用着旧的。
                base = AutoOpenKit.rssiBase(mac: app.currentMac)
            }
        }
    }

    private func calibrate() async {
        guard !calibrating else { return }
        calibrating = true
        calMessage = nil
        defer { calibrating = false }
        var samples: [Int] = []
        do {
            try await BLEService.shared.startScan(allowDuplicates: false, timeoutMs: 6000)
        } catch {
            // 原先 `try?` 把扫描起不来（蓝牙关着、没授权）吞成「采样不到 5 个点」——
            // 让用户站在门口白等 6 秒，还以为是位置不对。
            calMessage = "无法开始扫描：\(error.localizedDescription)"
            return
        }
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
            calMessage = "标定完成：触发线 \(p95) dBm。"
        } else {
            calMessage = "这次采样不到 5 个点，标定没保存。请站在门口，让手机靠近门锁再试。"
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
    // E5：钥匙串台账管理 —— 每台钥匙串一整组动作。
    @State private var busyId: String?
    /// 危险动作的待确认目标。三种确认共用一个枚举，一次只会有一个。
    @State private var ask: DongleAsk?
    /// 「查看已写入的钥匙」的读回结果（nil = 还没查过，[] = 查过、为空）。
    @State private var keysByDongle: [String: [String]] = [:]

    /// E5：危险动作确认。撤销 / 写未知钥匙 / 解绑都要先问一句。
    private enum DongleAsk: Identifiable {
        case revoke(Dongle)
        case fault(Dongle)
        case unbind(Dongle)
        var destructive: Bool {
            switch self {
            case .fault: return false   // 写假钥匙不是破坏 —— 它只是占一格
            default: return true
            }
        }
        var id: String {
            switch self {
            case .revoke(let d): return "revoke-" + d.mac
            case .fault(let d): return "fault-" + d.mac
            case .unbind(let d): return "unbind-" + d.mac
            }
        }
        var title: String {
            switch self {
            case .revoke: return "撤销这把锁的钥匙？"
            case .fault: return "写入一把未知钥匙？"
            case .unbind: return "从本机解绑这把钥匙串？"
            }
        }
        var confirm: String {
            switch self {
            case .revoke: return "撤销"
            case .fault: return "写入"
            case .unbind: return "解绑"
            }
        }
        var message: String {
            switch self {
            case .revoke:
                return "钥匙串里这把锁的钥匙会被删掉。以后要用它开门，必须把手机贴近钥匙串重新写一次 —— 这个动作不能撤销。"
            case .fault:
                return "写进去的是一把随机 PIN 的假钥匙：开不了任何锁、不绑成员、也不能远程收回。它只用来验证这枚钥匙串本身能收钥。"
            case .unbind:
                return "只删本机这条记录，钥匙串里已写入的钥匙仍然能开对应锁。"
            }
        }
    }

    private var dongles: [Dongle] { DB.dongles() }
    private var gateways: [Gateway] { DB.gateways() }

    /// 只读试验模式：写类动作（写钥 / 撤销 / 假钥匙 / 解绑）一律停。
    /// 读取类（状态 / 查钥匙）引擎会拦，但界面上先说明白。
    private var writesBlocked: Bool { DB.isDecoy || app.trial }

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
            if dongles.isEmpty {
                Text("还没有登记钥匙串。把钥匙串拿到手机旁，点下面的「搜索钥匙串」。")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
                    .padding(.vertical, 8)
            }
            ForEach(dongles) { dongle in
                dongleCard(dongle)
            }
            HStack(spacing: 10) {
                GhostButton(title: busy ? "请稍等…" : "搜索钥匙串", symbol: "dot.radiowaves.left.and.right") {
                    Task { await scanDongle() }
                }
            }
            .padding(.top, 10)
            .disabled(busy)
            .opacity(busy ? 0.55 : 1)
            Text("搜索只认厂商的钥匙串（pid 16289、广播带 MAC）。扫不到时先确认它有电，再靠近手机 30 厘米内。")
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
                .lineSpacing(3)
                .padding(.top, 6)
            if app.trial {
                Text("只读试验模式：钥匙串的写类动作（写钥、撤销、假钥匙、解绑）不会执行。")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.danger)
                    .lineSpacing(3)
                    .padding(.top, 6)
            }

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
            .disabled(busy)
            .opacity(busy ? 0.55 : 1)

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
        // iOS 27：直接以「要问的那件事」为状态（不再另配一个 Bool）。
        .itemConfirmationDialog(ask?.title ?? "", item: $ask, titleVisibility: .visible) { a in
            Button(a.confirm, role: a.destructive ? .destructive : nil) {
                switch a {
                case .revoke(let d): ask = nil; Task { await revoke(d) }
                case .fault(let d): ask = nil; Task { await writeFault(d) }
                case .unbind(let d): ask = nil; unbind(d)
                }
            }
            Button("取消", role: .cancel) { ask = nil }
        } message: { a in
            Text(a.message)
        }
    }

    /// E5：一台钥匙串的完整台账卡 —— 读数、动作、查回的钥匙列表。
    @ViewBuilder
    private func dongleCard(_ d: Dongle) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(d.name.isEmpty ? "钥匙串" : d.name)
                        .type(T.F.callout)
                        .foregroundStyle(T.C.ink)
                        .lineLimit(1)
                    Text(d.mac)
                        .type(T.F.caption)
                        .foregroundStyle(T.C.ink3)
                        .monospacedDigit()
                }
                Spacer()
                // 「已写这把锁」按台账里 lastKeyLock 对当前锁判断。
                if d.lastKeyLock == app.currentMac, !app.currentMac.isEmpty {
                    Text("已写这把锁")
                        .type(T.F.caption)
                        .foregroundStyle(T.C.ok)
                } else {
                    Text("未写这把锁")
                        .type(T.F.caption)
                        .foregroundStyle(T.C.ink3)
                }
            }
            .padding(.vertical, 8)

            HStack(spacing: 22) {
                statCol("电量", d.stat.map { $0.power >= 0 ? "\($0.power)%" : "—" } ?? "—")
                statCol("钥匙", d.stat.map { $0.ekeyCount >= 0 ? "\($0.ekeyCount)" : "—" } ?? "—")
                statCol("固件", d.stat?.firmware.isEmpty == false ? d.stat!.firmware : "—")
            }
            .padding(.bottom, 8)

            if busyId == d.mac {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(T.C.brass)
                    Text("正在与钥匙串通信 · 请贴近手机")
                        .type(T.F.caption)
                        .foregroundStyle(T.C.ink3)
                }
                .padding(.vertical, 8)
            }

            // 主动作：已写就给撤销，没写就给写入。
            if d.lastKeyLock == app.currentMac, !app.currentMac.isEmpty {
                GhostButton(title: "撤销这把锁的钥匙", symbol: "key.slash") {
                    ask = .revoke(d)
                }
                .padding(.top, 8)
                .disabled(busyId != nil || writesBlocked)
                .opacity(busyId != nil || writesBlocked ? 0.45 : 1)
            } else {
                GhostButton(title: "写入当前锁的钥匙", symbol: "key.fill") {
                    Task { await writeKey(d) }
                }
                .padding(.top, 8)
                .disabled(busyId != nil || writesBlocked)
                .opacity(busyId != nil || writesBlocked ? 0.45 : 1)
            }

            HStack(spacing: 8) {
                GhostButton(title: "读取状态", symbol: "gauge") {
                    Task { await readState(d) }
                }
                GhostButton(title: "已写入的钥匙", symbol: "list.bullet.rectangle") {
                    Task { await loadKeys(d) }
                }
            }
            .padding(.top, 8)
            .disabled(busyId != nil)

            GhostButton(title: "写入一把未知钥匙", symbol: "questionmark.key.fill") {
                ask = .fault(d)
            }
            .padding(.top, 8)
            .disabled(busyId != nil || writesBlocked)
            .opacity(busyId != nil || writesBlocked ? 0.45 : 1)

            GhostButton(title: "从本机解绑", symbol: "link.badge.plus") {
                ask = .unbind(d)
            }
            .padding(.top, 8)
            .disabled(busyId != nil || writesBlocked)
            .opacity(busyId != nil || writesBlocked ? 0.45 : 1)

            if let keys = keysByDongle[d.mac] {
                if keys.isEmpty {
                    Text("这枚钥匙串里还没有写入任何锁的钥匙。")
                        .type(T.F.caption)
                        .foregroundStyle(T.C.ink3)
                        .padding(.top, 10)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(keys, id: \.self) { mac in
                            HStack {
                                Text(DB.shortMac(mac))
                                    .type(T.F.caption)
                                    .foregroundStyle(T.C.ink)
                                    .monospacedDigit()
                                Spacer()
                                Text(DB.keychain(mac).map { LockArchive.displayName($0) } ?? "本机无这把锁的档案")
                                    .type(T.F.caption)
                                    .foregroundStyle(DB.keychain(mac) == nil ? T.C.danger : T.C.ink3)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .padding(.top, 10)
                }
            }

            Rectangle().fill(T.C.hair).frame(height: 0.5)
                .padding(.top, 14)
        }
    }

    private func statCol(_ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
            Text(value)
                .type(T.F.caption)
                .fontWeight(.medium)
                .foregroundStyle(T.C.ink)
                .monospacedDigit()
        }
    }

    private func scanDongle() async {
        guard !busy else { return }
        // 空壳里 `dongles()` 恒为空、`saveDongle` 也会被数据层拒绝 ——
        // 但下面那句「已登记」还是会照说。别让界面撒谎。
        //
        // 提示语**不能提「空壳」**：胁迫者正看着这一屏，一句「空壳模式下不……」
        // 等于当场告诉他这是假界面，胁迫码的全部意义就没了。用与其它写入拒绝同一句中性话。
        guard !DB.isDecoy else {
            message = "暂时无法登记钥匙串，请稍后再试。"
            return
        }
        busy = true
        defer { busy = false }
        do {
            let dongle = try await HardwareService.shared.scanForDongle()
            message = "找到 \(dongle.mac)，已登记。"
        } catch {
            message = error.localizedDescription
        }
    }

    private func writeKey(_ d: Dongle) async {
        guard busyId == nil else { return }
        // `keychainForUnlock` 是**不过滤**空壳的读法，而这一步会把锁的 ekey
        // 写进一枚可以带走的硬件 —— 与「安卓交付码」同一类泄露，守一道。
        // 提示语不提「空壳」（见 scanDongle）。
        guard !DB.isDecoy else {
            message = "暂时无法写入钥匙串，请稍后再试。"
            return
        }
        guard !app.trial else {
            message = "只读试验模式：写入不执行。"
            return
        }
        guard let lock = DB.keychainForUnlock(app.currentMac) else {
            message = "先配对一把锁。"
            return
        }
        busyId = d.mac
        defer { busyId = nil }
        do {
            try await HardwareService.shared.writeDongleKey(dongleMac: d.mac, lock: lock, trackId: UInt32.random(in: 1 ... 0x7fff_ffff))
            // 写完回读一次状态，台账的电量 / 钥匙数 / lastKeyLock 就地刷新。
            if let stat = try? await HardwareService.shared.readDongleState(mac: d.mac) {
                var rec = DB.dongle(d.mac) ?? d
                rec.stat = stat
                rec.lastKeyLock = lock.mac
                rec.lastKeyAt = DF.iso().string(from: Date())
                DB.saveDongle(rec)
            }
            AppToast.shared.show("钥匙已写入钥匙串")
        } catch {
            message = "写入失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// E5：撤销 —— 同一条写钥命令下发空 ekey 即删除。删了要重新写一遍才能用。
    private func revoke(_ d: Dongle) async {
        guard busyId == nil else { return }
        guard !DB.isDecoy else {
            message = "暂时无法撤销钥匙，请稍后再试。"
            return
        }
        guard !app.trial else {
            message = "只读试验模式：撤销不执行。"
            return
        }
        guard let lock = DB.keychainForUnlock(app.currentMac) else {
            message = "先配对一把锁。"
            return
        }
        busyId = d.mac
        defer { busyId = nil }
        do {
            try await HardwareService.shared.deleteDongleKey(dongleMac: d.mac, lock: lock)
            var rec = DB.dongle(d.mac) ?? d
            rec.lastKeyLock = ""
            DB.saveDongle(rec)
            AppToast.shared.show("已从钥匙串里删掉这把锁的钥匙")
        } catch {
            message = "撤销失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// E5：手动读状态 —— 不再只在写钥后顺带刷一次，单独给个入口。
    private func readState(_ d: Dongle) async {
        guard busyId == nil else { return }
        busyId = d.mac
        defer { busyId = nil }
        do {
            let stat = try await HardwareService.shared.readDongleState(mac: d.mac)
            var rec = DB.dongle(d.mac) ?? d
            rec.stat = stat
            DB.saveDongle(rec)
            AppToast.shared.show("状态已更新")
        } catch {
            message = "读状态失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// E5：查看这枚钥匙串里存了哪些锁的钥匙（逐把对回本机档案）。
    private func loadKeys(_ d: Dongle) async {
        guard busyId == nil else { return }
        busyId = d.mac
        defer { busyId = nil }
        do {
            keysByDongle[d.mac] = try await HardwareService.shared.dongleKeys(dongleMac: d.mac, lockMac: nil)
        } catch {
            message = "查钥匙失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// E5：写入未知/假钥匙 —— 随机 PIN、永久、不绑成员；开不了锁，只验证钥匙串本身能收钥。
    private func writeFault(_ d: Dongle) async {
        guard busyId == nil else { return }
        guard !DB.isDecoy else {
            message = "暂时无法写入钥匙串，请稍后再试。"
            return
        }
        guard !app.trial else {
            message = "只读试验模式：写入不执行。"
            return
        }
        guard let lock = DB.keychainForUnlock(app.currentMac) else {
            message = "未知钥匙也要按某把锁的身份写入 —— 先配对一把锁。"
            return
        }
        busyId = d.mac
        defer { busyId = nil }
        do {
            try await HardwareService.shared.writeFaultDongleKey(dongleMac: d.mac, lock: lock)
            AppToast.shared.show("未知钥匙已写入（随机 PIN，开不了锁）")
        } catch {
            message = "写假钥匙失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// E5：从本机解绑 —— 只删本机台账，不动实体钥匙里已写入的钥匙。
    private func unbind(_ d: Dongle) {
        guard !DB.isDecoy else {
            message = "暂时无法解绑，请稍后再试。"
            return
        }
        guard !app.trial else {
            message = "只读试验模式：解绑不执行。"
            return
        }
        DB.removeDongle(d.mac)
        keysByDongle[d.mac] = nil
        AppToast.shared.show("已从本机解绑（钥匙串里的钥匙不受影响）")
    }

    private func provision() async {
        guard !busy else { return }
        guard !ssid.isEmpty else { message = "先填 WiFi 名称。"; return }
        // 空壳里不配网：网关会真的连上这里输入的 WiFi，退出空壳后它还在网上。
        guard !DB.isDecoy else {
            message = "暂时无法配置网关，请稍后再试。"
            return
        }
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
        guard !busy else { return }
        guard let gateway = gateways.first else { message = "还没有网关。"; return }
        guard !DB.isDecoy else {
            message = "暂时无法重启网关，请稍后再试。"
            return
        }
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
                GlassSurface() {
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
        guard !busy else { return }
        guard let package else { return }
        // 空壳里绝不刷固件：这是把锁变砖风险最高的一个动作，且不可撤销。
        guard !DB.isDecoy else {
            errorLine = "暂时无法升级，请稍后再试。"
            return
        }
        guard let lock = DB.keychainForUnlock(app.currentMac) else {
            errorLine = "先配对一把锁，再刷固件。"
            return
        }
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
            // DFU 前主动断开了链路；不重连的话 `reload(refreshStatus: true)`
            // 会跳过 getStatus，「当前锁内版本」继续显示升级前的旧值。
            try? await LockService.shared.ensureConnected(mac: lock.mac)
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
    @State private var confirmingRepair: Bool? = nil
    // C7：帧骨架一旦贴出去就收不回来，复制前先确认一次。
    @State private var confirmingFrameCopy: Bool? = nil

    // F2：附近设备 —— 扫描广播 + 对任意候选设备发回声探测。
    private struct Candidate: Identifiable {
        let id: String
        let name: String
        let pid: Int
        let mac: String
        let rssi: Int
        let dfu: Bool
    }

    @State private var devices: [Candidate] = []
    @State private var scanning = false
    @State private var probing: String?
    @State private var probeResult: String?
    @State private var probeResultDevice: String?
    // 回声探测的**原始读数**（ok/matched/echoHex/rc/ms）—— 真机实测 cmd12 不带 rc KLV，
    // ok 恒 false 属引擎语义；原始值摆出来供现场核对。
    @State private var probeRaw: String?
    // 读日志读数节 + 写面命令台。
    @State private var logBusy = false
    @State private var consoleOpen = false

    // F1：God 档 —— 锁身份 / 全量读数 / 台账对账 / 变更流水。
    @State private var status: StatusSnapshotData?
    @State private var changeLogs: [LogEntry] = []
    @State private var godBusy = false
    // B71/B19/B73/B67/B68 的页面状态。
    @State private var health = HealthCheck.Report()
    @State private var storage = StoreIntegrity.Report()
    @State private var replayResult: String?
    @State private var bundleURL: URL?

    private var kc: Keychain? { DB.keychainForUnlock(app.currentMac) }

    private var frames: [String] {
        // 空壳里不显示帧：那是本次会话（包括锁屏前）真实下发过的命令骨架。
        if DB.isDecoy { return [] }
        return raw ? LockService.shared.recentFrames.map { FrameRedact.apply($0) } : []
    }

    var body: some View {
        ScreenScroll {
            NavRow(kicker: "设置 / 诊断", back: { dismiss() })

            DisplayLine(text: "看清\n发生了什么。", size: 34)
                .padding(.top, 16)
            Text("诊断页不主动写入门锁设置。两个例外都要你手动触发并二次确认：「修复 PIN 池」（会重写锁里的 PIN 池，让其他设备上的旧钥匙失效）和「写面命令台」（05/08/0A/… 逐条手发，后果自负）。")
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
                GhostButton(title: busy ? "处理中…" : "重连链路", symbol: "arrow.triangle.2.circlepath") {
                    guard !busy else { return }
                    guard !app.currentMac.isEmpty else {
                        message = "还没有绑定门锁。"
                        return
                    }
                    message = "正在重连…"
                    // busy 必须在同步段置上：两个 GhostButton 共用同一个忙守卫，
                    // 若等 Task 里才置，双击会各起一条 reconnect，后者看到 link.busy
                    // 立刻返回，并把“没连上”写到前一条仍在进行的连接上。
                    busy = true
                    Task {
                        await app.link.reconnect()
                        message = app.link.phase == .ready
                            ? "已连上 · 下一次自然重试间隔 \(Int(app.link.nextLadder)) 秒"
                            : "没连上 · 建议 \(Int(app.link.nextLadder)) 秒后再试"
                        busy = false
                    }
                }
                GhostButton(title: "读一次 RSSI", symbol: "antenna.radiowaves.left.and.right") {
                    guard !busy else { return }
                    guard !app.currentMac.isEmpty else {
                        message = "还没有绑定门锁。"
                        return
                    }
                    busy = true
                    message = "正在读取信号…"
                    // 用这次读数的回调，而不是等 1 秒后回读 `lastRSSI`：
                    // 读失败时后者仍是盘上的旧值，会被报成“当前信号”。
                    app.link.readRSSI { value in
                        message = value.map { "当前信号 \($0) dBm。" }
                            ?? "没读到信号 —— 先把手机靠近门锁。"
                        busy = false
                    }
                }
            }
            .padding(.top, 12)
            .disabled(busy)
            .opacity(busy ? 0.55 : 1)

            HStack(spacing: 10) {
                GhostButton(title: "回声测试", symbol: "waveform") {
                    Task { await echo() }
                }
                GhostButton(title: "修复 PIN 池", symbol: "wrench") {
                    confirmingRepair = true
                }
            }
            .padding(.top, 10)
            .disabled(busy)
            .opacity(busy ? 0.55 : 1)

            // 附近设备与下面的 God 档都会说出周围/本机的真实锁档案 —— 空壳里整段不摆。
            if !DB.isDecoy {
                SectionHead(index: "02", title: "附近设备")
                GhostButton(title: scanning ? "正在扫描 8 秒…" : "扫描附近设备",
                            symbol: "dot.radiowaves.left.and.right") {
                    Task { await scan() }
                }
                .disabled(scanning)
                .opacity(scanning ? 0.55 : 1)
                Text("门锁被连上后会停止广播；先断开再扫。扫描只读广播，不连接、不发命令；对扫到的任意设备可再发一条回声探测。")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
                    .lineSpacing(3)
                    .padding(.top, 8)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(devices) { d in
                    deviceRow(d)
                }
            }

            // 空壳里不摆「最近帧」：没有帧可看，开关就成了一个点了没反应的死控件。
            if !DB.isDecoy {
                SectionHead(index: "03", title: "最近帧")
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
                    // C7：帧只留在屏幕上等于没法交给人排障；复制走脱敏骨架 + 二次确认。
                    GhostButton(title: "复制脱敏帧", symbol: "doc.on.doc") {
                        confirmingFrameCopy = true
                    }
                    .padding(.top, 8)
                }
            }

            if let message {
                Text(message)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink2)
                    .padding(.top, 14)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // F1：God 档。空壳里整段不渲染（身份指纹与台账本身就是档案泄露）。
            if !DB.isDecoy, let kc {
                godSections(kc)
            }

            // B71：健康检查 —— 一项一项查，每项给出**修复入口**，
            // 而不只是「读数」。「诊断页只能读」这条纪律对**读**成立，
            // 这里的按钮跳到别的页面去修，不在这一页写门锁。
            if !DB.isDecoy {
                SectionHead(index: "04", title: "健康检查")
                Text(health.summary)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
                    .padding(.bottom, T.S.s)
                ForEach(health.items) { item in
                    healthRow(item)
                }
                GhostButton(title: L("common.refresh"), symbol: "arrow.clockwise") {
                    health = HealthCheck.run(mac: app.currentMac)
                }
                .padding(.top, T.S.s)
            }

            // B19/B69：命令时间线 + 只读回放。
            if !DB.isDecoy {
                SectionHead(index: "05", title: "最近的命令")
                ForEach(CommandTimeline.entries(12)) { r in
                    timelineRow(r)
                }
                if let last = CommandReplay.available.first {
                    GhostButton(title: "回放最近一帧（只解析，不发锁）", symbol: "play") {
                        replayResult = CommandReplay.replay(last.hex)
                    }
                    .padding(.top, T.S.s)
                    if let replayResult {
                        Text(replayResult)
                            .type(T.F.caption)
                            .foregroundStyle(T.C.ink2)
                            .padding(.top, 6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            // B73：本机存储完整性 —— 哪些数据读不出来，能不能救。
            if !DB.isDecoy {
                SectionHead(index: "06", title: "本机数据")
                Text(storage.summary)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
                    .padding(.bottom, T.S.s)
                ForEach(storage.issues) { issue in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.what)
                            .type(T.F.footnote)
                            .foregroundStyle(T.C.ink)
                        Text(issue.repairable ? "\(issue.problem) · 可以从备份恢复" : "\(issue.problem) · 备份里也没有")
                            .type(T.F.caption)
                            .foregroundStyle(issue.repairable ? T.C.ink3 : T.C.danger)
                    }
                    .padding(.vertical, 4)
                }
                if storage.issues.contains(where: { $0.repairable }) {
                    GhostButton(title: "从备份恢复", symbol: "arrow.down.to.line") {
                        let r = StoreIntegrity.repair()
                        storage = r
                        AppToast.shared.show(r.repaired.isEmpty ? "没有可恢复的项" : "已恢复 \(r.repaired.count) 项")
                        Task { await app.reload() }
                    }
                    .padding(.top, T.S.s)
                }
                if !storage.issues.isEmpty {
                    if let residue = StoreIntegrity.exportResidue() {
                        ShareLink(item: residue) {
                            Text("导出残片")
                                .type(T.F.footnote)
                                .fontWeight(.semibold)
                                .foregroundStyle(T.C.brass)
                        }
                        .padding(.top, T.S.s)
                    }
                }
            }

            // B67/B68：异常退出记录 + 一键诊断包。
            if !DB.isDecoy {
                SectionHead(index: "07", title: "异常退出与诊断包")
                Text(CrashLog.summary())
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
                Text("诊断包里只有设备、权限、链路与命令记录 —— 不含密码、密钥或任何凭证。")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
                    .padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
                if let bundleURL {
                    ShareLink(item: bundleURL) {
                        Text(L("diag.bundle.title"))
                            .type(T.F.footnote)
                            .fontWeight(.semibold)
                            .foregroundStyle(T.C.brass)
                    }
                    .padding(.top, T.S.s)
                } else {
                    GhostButton(title: "生成诊断包", symbol: "square.and.arrow.up") {
                        bundleURL = DiagnosticBundle.writeFile(mac: app.currentMac)
                    }
                    .padding(.top, T.S.s)
                }
            }

            SectionHead(index: DB.isDecoy ? "03" : "08", title: "本机")
            Text("App 版本 1.0 · 协议层 \(app.lock?.model ?? "—") · 数据全部在本机")
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
                .padding(.top, 4)

            // 09 读日志读数（只读展示）：真机锁日志约 2000 条滚存，readLogs 单轮最多 20 页。
            // 撞上限后锚点自动保留 —— 下一次点击从「已覆盖最低序号 − 1」继续往更早翻。
            if !DB.isDecoy {
                SectionHead(index: "09", title: "读日志读数")
                let hasCursor = RecordsSource.logCursor(mac: app.currentMac) != nil
                HStack(spacing: 10) {
                    GhostButton(title: logBusy ? "正在读…" : (hasCursor ? "继续读更早" : "读一次日志"),
                                symbol: hasCursor ? "arrow.down.to.line" : "list.bullet.rectangle") {
                        Task { await readLogsOnce() }
                    }
                    if hasCursor {
                        GhostButton(title: "从最新重读", symbol: "arrow.counterclockwise") {
                            Task { await restartLogs() }
                        }
                    }
                }
                .disabled(logBusy)
                .opacity(logBusy ? 0.55 : 1)
                .padding(.top, 6)
                if let s = app.lastLogRead {
                    godRow("已读页数", "\(s.pages) / 20 页上限")
                    godRow("已读条数", "\(s.read) 条（本轮）")
                    godRow("已覆盖到", s.lowest.map { "#\($0)" } ?? "—")
                    godRow("锁端剩余", s.remaining.map { "\($0) 条" } ?? "—")
                    godRow("历史读完", s.done ? "是" : "否 —— 再点一次继续往更早")
                    godRow("上次读取", When.ago(s.at))
                    if s.capped {
                        Text("撞上 20 页上限 —— 本轮已保存并留了断点；「继续读更早」会从断点续翻，不会重读。")
                            .type(T.F.caption)
                            .foregroundStyle(T.C.danger)
                            .lineSpacing(3)
                            .padding(.top, 6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("还没有读过 —— 点上面的按钮从门锁读一次。")
                        .type(T.F.caption)
                        .foregroundStyle(T.C.ink3)
                        .padding(.top, 6)
                }

                // 10 写面命令台：05/08/0A/0B/13-15/18-25/22、钥匙串 41-44、网关 —— 逐条手动触发。
                SectionHead(index: "10", title: "写面命令台")
                GhostButton(title: "打开命令台", symbol: "terminal") {
                    consoleOpen = true
                }
                .padding(.top, 6)
                Text("05 / 08 / 0A / 0B / 13–15 / 18–21 / 22 / 24 / 25 · 钥匙串 41 / 43 / 44 · 网关 30–38 —— 每条都要二次确认，由你决定何时发。")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
                    .lineSpacing(3)
                    .padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        // 修复 PIN 池会让**别的设备**上那把钥匙失效 —— 不可逆，值得先问一句。
        .itemConfirmationDialog("重写这把锁的 PIN 池？",
                                item: $confirmingRepair,
                            titleVisibility: .visible) {
            Button("重写", role: .destructive) { _ in
                Task { await repair() }
            }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("只换锁里的 PIN 池，不换母钥：本机的钥匙仍然有效，但其他设备上已配的旧钥匙会失效。")
        }
        .itemConfirmationDialog("复制这些帧骨架？",
                                item: $confirmingFrameCopy,
                            titleVisibility: .visible) {
            Button("复制") { _ in
                Clip.set(Array(frames.suffix(8)).joined(separator: "\n"))
                AppToast.shared.show("已复制 \(min(frames.count, 8)) 条脱敏帧")
            }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("帧骨架已脱敏，但仍含命令类型与 MAC。贴出去就收不回来 —— 确认接收方可信再复制。")
        }
        .task {
            // 进页先给盘上的缓存快照；要最新读数点「重新读取」。
            if let kc { status = DB.readStatus(kc.mac) }
            // B71/B73：健康检查与存储完整性各跑一次（纯本地读，不碰门锁）。
            health = HealthCheck.run(mac: app.currentMac)
            storage = StoreIntegrity.scan()
        }
        .sheet(isPresented: $consoleOpen) { WriteConsoleSheet() }
    }

    /// B71：健康检查的一行。图标 + 名称 + 结论；坏了的那几项用危险色。
    private func healthRow(_ item: HealthCheck.Item) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.status == .ok ? "checkmark.circle"
                                : (item.status == .warn ? "exclamationmark.circle" : "xmark.octagon"))
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(item.status == .ok ? T.C.ok : (item.status == .warn ? T.C.brass : T.C.danger))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .type(T.F.footnote)
                    .foregroundStyle(T.C.ink)
                Text(item.detail)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            if let fix = item.fix {
                Text(fix)
                    .type(T.F.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(T.C.brass)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// B19：命令时间线的一行。
    private func timelineRow(_ r: CommandRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: r.isFailure ? "xmark.circle" : "checkmark.circle")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(r.isFailure ? T.C.danger : T.C.ok)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(r.name)
                        .type(T.F.footnote)
                        .foregroundStyle(T.C.ink)
                    Text(r.outcome)
                        .type(T.F.caption)
                        .monospacedDigit()
                        .foregroundStyle(r.isFailure ? T.C.danger : T.C.ink3)
                    Text("\(r.ms)ms")
                        .type(T.F.caption)
                        .monospacedDigit()
                        .foregroundStyle(T.C.ink3)
                }
                if !r.note.isEmpty {
                    Text(r.note)
                        .type(T.F.caption)
                        .foregroundStyle(T.C.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if r.mayHaveExecuted {
                    Text("可能已经执行")
                        .type(T.F.caption)
                        .foregroundStyle(T.C.danger)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    /// 诊断页的「读一次日志」：走既有的 AppModel.readLogs（续读逻辑在引擎层），
    /// 结果落在 lastLogRead（只读读数）与 message 上。
    private func readLogsOnce() async {
        guard !logBusy else { return }
        logBusy = true
        defer { logBusy = false }
        if let r = await app.readLogs() {
            // 断链部分成功时 readLogs 会**带着结果返回**并把原因写进 lastError ——
            // 直接只报「读到 N 条」会把「已留断点、再点继续」这句关键提示吞掉。
            message = app.lastError ?? ("读到 \(r.read) 条" + (r.remaining.map { " · 锁端还有 \($0) 条" } ?? ""))
        } else {
            message = app.lastError ?? "读取失败，请稍后重试。"
        }
    }

    /// 丢掉断点，回到从最新开始读（缓存不丢，只刷新最新一段）。
    private func restartLogs() async {
        guard !logBusy else { return }
        RecordsSource.setLogCursor(mac: app.currentMac, nil)
        await readLogsOnce()
    }

    // MARK: - God 档

    @ViewBuilder
    private func godSections(_ kc: Keychain) -> some View {
        SectionHead(index: "04", title: "锁身份")
        godRow("锁名", LockArchive.displayName(kc))
        godRow("MAC", DB.normalizeMac(kc.mac))
        godRow("配对", kc.pairedAt.isEmpty ? "—" : DF.localMinute(fromISO: kc.pairedAt))
        godRow("skey 指纹", DiagSnapshot.fingerprint(kc.skey))
        godRow("ekey 指纹", DiagSnapshot.fingerprint(kc.ekey))
        godRow("ekey 内 PIN", DiagSnapshot.ekeyPinMasked(kc))
        Text("密钥只显示指纹（前 4 + 后 4 位）；贴给别人排障也不会出现明文。")
            .type(T.F.caption)
            .foregroundStyle(T.C.ink3)
            .lineSpacing(3)
            .padding(.top, 8)
            .fixedSize(horizontal: false, vertical: true)

        SectionHead(index: "05", title: "锁端读数")
        GhostButton(title: godBusy ? "读取中…" : "重新读取",
                    symbol: "arrow.clockwise") {
            Task { await refreshGod() }
        }
        .disabled(godBusy)
        .opacity(godBusy ? 0.55 : 1)
        if let st = status {
            godRow("固件", st.firmware.isEmpty ? "未上报" : st.firmware)
            godRow("电量", st.powerLevel >= 0 ? "\(st.powerLevel)%" : "未读到")
            godRow("锁钟", st.lockTime > 0 ? When.clock(ZKProtocol.protoSecondsToMs(st.lockTime) / 1000) : "未读到")
            godRow("安全", "验签\(st.verifyMode == 1 ? "开" : "关") · 广播\(st.broadcastMode == 1 ? "开" : "关") · 临时码\(st.tempPwdMode == 1 ? "开" : "关")")
            godRow("PIN 池", usedOfCap(cap: st.pinCap, stock: st.pinStock, local: localPinCount(kc)))
            godRow("密码", usedOfCap(cap: st.pwdCap, stock: st.pwdStock, local: DB.listPwds(kc.mac).count))
            godRow("指纹", usedOfCap(cap: st.fpCap, stock: st.fpStock, local: DB.listFps(kc.mac).count))
            godRow("通信密钥", sKeyStatusWord(st.sKeyStatus))
            godRow("动态码周期", st.zotpPeriod.map { "\($0) 分钟" } ?? "未上报")
        } else {
            Text("还没有快照 —— 点上面的「重新读取」连一次锁。")
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
                .padding(.top, 6)
        }

        SectionHead(index: "06", title: "台账对账")
        godRow("本机 PIN 池", "\(localPinCount(kc)) 枚（声明 \(kc.pins.count)）")
        godRow("本机密码", "\(DB.listPwds(kc.mac).count) 条")
        godRow("本机指纹", "\(DB.listFps(kc.mac).count) 枚")
        // 指纹明细：本机台账批次 vs 锁端已用。真机审计案例（2026-11-07）：本机 8 枚（批次 65545–65555）、
        // 锁端 fpStock=7 —— 差异 1 枚；锁不提供指纹枚列表（只读面无命令），具体批次需 13/15 或厂商 App 核对。
        let localFps = DB.listFps(kc.mac)
        godRow("本机指纹批次", localFps.isEmpty ? "空" : localFps.map { String($0.batch) }.joined(separator: " "))
        if let st = status {
            // KLV#22/25/28 = 已用（见 usedOfCap 注释）；旧写法 cap−stock 是反的。
            let used = st.pinStock
            let local = localPinCount(kc)
            godRow("锁端已用 vs 本机", "\(used) vs \(local)")
            let fpUsed = st.fpStock
            let fpDiff = localFps.count - fpUsed
            godRow("锁端指纹已用 vs 本机", "\(fpUsed) vs \(localFps.count)")
            Text(fpDiff == 0
                 ? "指纹数量一致（批次号仍需锁端日志的增删事件才能逐枚对齐）。"
                 : (fpDiff > 0
                    ? "本机台账比锁端多记 \(fpDiff) 枚 —— 锁上可能删过指纹而本机没同步；在锁上重录/删除（13/15）或用厂商 App 的指纹列表核对批次。"
                    : "锁端比本机多 \(abs(fpDiff)) 枚 —— 别处（网关/另一台手机）加过指纹；在本机重新添加一次即可入账。"))
                .type(T.F.caption)
                .foregroundStyle(fpDiff == 0 ? T.C.ink3 : T.C.danger)
                .lineSpacing(3)
                .padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)
            Text(used == local
                 ? "PIN 数量一致（但两批都满池时数量恒等，不能证明是同一批 —— 真正的判据是开锁时锁端是否拒收这枚 PIN）。"
                 : "PIN 数量不一致 —— 现在签发的凭证必被锁端拒绝，需要修池或重新导入。")
                .type(T.F.caption)
                .foregroundStyle(used == local ? T.C.ink3 : T.C.danger)
                .lineSpacing(3)
                .padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
        }

        SectionHead(index: "07", title: "凭证变更流水")
        Text("锁端自己记录的凭证操作 —— 别的手机或网关做的也算，是「对不上」时的第一手证据。")
            .type(T.F.caption)
            .foregroundStyle(T.C.ink3)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
        if changeLogs.isEmpty {
            Text("还没有读到变更流水 —— 「重新读取」会带最近一页（最多 20 条）。")
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
                .padding(.top, 6)
        } else {
            ForEach(Array(changeLogs.prefix(20).enumerated()), id: \.offset) { pair in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 10) {
                        Text(pair.element.lockTimeStr)
                            .type(T.F.caption)
                            .foregroundStyle(T.C.ink3)
                            .monospacedDigit()
                        Text(pair.element.typeName)
                            .type(T.F.caption)
                            .foregroundStyle(T.C.ink)
                        Spacer(minLength: 0)
                    }
                    if let diff = pair.element.diffDescription {
                        Text(diff)
                            .type(T.F.mono)
                            .foregroundStyle(T.C.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 5)
            }
        }
    }

    private func godRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
            Spacer(minLength: 8)
            Text(value)
                .type(T.F.mono)
                .foregroundStyle(T.C.ink)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 7)
    }

    /// 「已用 / 容量」的统一写法。容量未上报时报本机条数并说明容量没读到 —— 不能写死「已用 0」。
    private func usedOfCap(cap: Int?, stock: Int, local: Int) -> String {
        guard stock >= 0 else { return "未读到" }
        guard let c = cap, c > 0 else { return "本机 \(local) 条 · 容量未读" }
        // 2026-11-07 真机审计（对抗式复核）：KLV#22/25/28 是**已用**不是剩余 —— 三池互证：
        // 密码 stock=0（本机 0 条）、指纹 stock=7（本机 8 条，时间线见对账节）、PIN stock=64/64（本机 64 枚）。
        // 旧写法 `cap - stock` 把三个读数全部反了（PIN 会显示 0/64）。
        return "\(stock) / \(c)"
    }

    private func sKeyStatusWord(_ v: Int) -> String {
        switch v {
        case 0: return "未设置"
        case 3: return "已就绪"
        default: return "状态 \(v)"
        }
    }

    private func localPinCount(_ kc: Keychain) -> Int {
        kc.pins.filter { !$0.isEmpty }.count
    }

    // MARK: - 附近设备

    private func deviceRow(_ d: Candidate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(d.name)
                    .type(T.F.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(T.C.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(d.rssi) dBm")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
                    .monospacedDigit()
            }
            Text("pid \(d.pid) · \(d.mac.isEmpty ? "无 MAC" : d.mac)\(d.dfu ? " · DFU" : "")")
                .type(T.F.mono)
                .foregroundStyle(T.C.ink3)
            Button {
                Task { await probe(d) }
            } label: {
                Text(probing == d.id ? "探测中…" : "发送回声探测")
                    .type(T.F.footnote)
                    .fontWeight(.medium)
                    .foregroundStyle(T.C.brass)
            }
            .buttonStyle(.plain)
            .disabled(probing != nil)
            if probing == nil, probeResultDevice == d.id, let probeResult {
                Text(probeResult)
                    .type(T.F.caption)
                    .foregroundStyle(probeResult.hasPrefix("回声一致") ? T.C.ok : T.C.danger)
                    .fixedSize(horizontal: false, vertical: true)
                if let probeRaw {
                    Text(probeRaw)
                        .type(T.F.mono)
                        .foregroundStyle(T.C.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 10)
    }

    private func scan() async {
        guard !scanning else { return }
        scanning = true
        devices = []
        do {
            // 扫满 8 秒窗口再取快照 —— startScan 后立刻读，列表恒空。
            let found = try await BLEService.shared.scanWindow(allowDuplicates: true, timeoutMs: 8000)
            var out: [Candidate] = []
            for d in found {
                guard let adv = ZKProtocol.parseAdv(d.advertisHex) else { continue }
                let mac = ZKProtocol.lockMac(fromAdv: adv) ?? ""
                out.append(Candidate(id: d.deviceId,
                                     name: d.name.isEmpty ? (PidMap.productNames[adv.pid] ?? "未知设备") : d.name,
                                     pid: adv.pid, mac: mac, rssi: d.rssi, dfu: adv.dfuState != 0))
            }
            devices = out.sorted { $0.rssi > $1.rssi }
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        scanning = false
    }

    private func probe(_ d: Candidate) async {
        guard probing == nil else { return }
        probing = d.id
        probeResult = nil
        probeResultDevice = nil
        do {
            let r = try await LockService.shared.probeEcho(deviceId: d.id)
            // 2026-11-07 真机审计：cmd12 的回包**不带 rc KLV**（extractRc 恒 -1 → EchoProbe.ok 恒 false），
            // 「ok」不能作为"没回帧"的判据 —— 真机无论回什么，ok 都是 false。
            // 区分"回帧但值不一致"与"根本没回帧"要看 echoHex 是否非空。
            probeResult = r.matched
                ? "回声一致 · \(r.ms) ms"
                : (r.echoHex.isEmpty ? "设备回帧异常 · \(r.ms) ms" : "回声不匹配 · \(r.ms) ms")
            // 原始读数：ok/matched/echoHex/rc 一并在屏上摆开，现场核对不做二次解释。
            probeRaw = "ok=\(r.ok) · matched=\(r.matched) · echo=\(r.echoHex.isEmpty ? "—" : r.echoHex) · rc=\(r.rc) · \(r.ms)ms"
        } catch {
            probeResult = "探测失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            probeRaw = nil
        }
        probeResultDevice = d.id
        probing = nil
    }

    private func refreshGod() async {
        guard !godBusy else { return }
        guard let kc else {
            message = "先配对一把锁。"
            return
        }
        godBusy = true
        defer { godBusy = false }
        do {
            _ = try await LockService.shared.getStatus(mac: kc.mac)
        } catch {
            message = "读状态失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
        status = DB.readStatus(kc.mac)
        do {
            let page = try await LockService.shared.getLogs(startIdx: 0, pageSize: 20)
            // 14/15 = 密码/指纹变更，20/21 = 增删流水（口径与 ios27 God 档一致）。
            changeLogs = page.logs.filter { $0.type == 14 || $0.type == 15 || $0.type == 20 || $0.type == 21 }
        } catch {
            message = "读日志失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func echo() async {
        guard !busy else { return }
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
        guard !busy else { return }
        // 空壳里不重写 PIN 池：这是不可逆的真实写入，而且会让别的设备上的钥匙失效。
        guard !DB.isDecoy else {
            message = "暂时无法修复，请稍后再试。"
            return
        }
        guard let kc = DB.keychainForUnlock(app.currentMac) else {
            message = "先配对一把锁。"
            return
        }
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
