// LockSettingsScreens.swift —— 我的锁 / 门锁设置 / 门锁信息。
import SwiftUI

// MARK: - 我的锁

@MainActor
struct LocksScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var pendingDelete: LockSummary?
    @State private var errorLine: String?
    @State private var confirmingWipe = false

    var body: some View {
        ScreenScroll {
            NavRow(kicker: "设置 / 我的锁", back: { dismiss() })

            DisplayLine(text: app.locks.isEmpty ? "还没有锁。" : "\(app.locks.count) 把锁，\n一个家。", size: 34)
                .padding(.top, 16)
            Text(DB.isDecoy
                 ? "当前正在用的那把锁。"
                 : "点一行切换当前锁；右侧「设为默认」决定冷启动落点。")
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
                .padding(.top, 8)

            SectionHead(index: "01", title: "门锁", trailing: "\(app.locks.count)")
            ForEach(app.locks) { lock in
                lockRow(lock)
            }
            // 空态原先只有一句「还没有锁。」，整页没有任何下一步 —— 从设置首页
            // 「还没有门锁」点进来就是死路。给一个真的能去配对的入口。
            if app.locks.isEmpty {
                PrimaryButton(title: "配对新的门锁") {
                    router.pushSettings(.pairing)
                }
                .padding(.top, 18)
            }

            if let errorLine {
                Text(errorLine)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.danger)
                    .padding(.top, 12)
            }

            // 空壳里不提供任何"删除本机数据"的入口：这是不可逆的真实删除，
            // 而空壳的前提是胁迫者无论怎么点，都不会破坏主人的数据。
            // 一把锁都没有时也整段不摆 —— 一个恒被禁用的按钮只会让人以为它坏了。
            if !DB.isDecoy && !app.locks.isEmpty {
                SectionHead(index: "02", title: "数据")
                Button {
                    confirmingWipe = true
                } label: {
                    ContentRow(symbol: "trash", tone: .danger, title: "删除全部本机数据",
                               subtitle: "锁端不受影响；本机钥匙串、台账、记录全部清掉", chevron: true)
                }
                .buttonStyle(.plain)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        // 一把没有确认门的「删除全部」：点错了就是全部钥匙串、台账、记录一起没。
        .confirmationDialog("删除这台手机上全部门锁的数据？",
                            isPresented: $confirmingWipe,
                            titleVisibility: .visible) {
            Button("全部删除", role: .destructive) {
                Task {
                    for lock in app.locks { DB.removeDevice(lock.id) }
                    app.overrideMac = nil
                    await app.reload()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只删本机。锁里的凭证和钥匙仍然有效，但本机再也打不开它们了。")
        }
        .confirmationDialog("删除这把锁的本机数据？",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let lock = pendingDelete {
                    DB.removeDevice(lock.id)
                    if app.overrideMac == lock.id { app.overrideMac = nil }
                    Task { await app.reload() }
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("只删本机。锁里的凭证和钥匙仍然有效。")
        }
    }

    private func lockRow(_ lock: LockSummary) -> some View {
        let isCurrent = lock.id == app.currentMac
        return HStack(spacing: 12) {
            Button {
                app.overrideMac = lock.id
                Task { await app.reload() }
            } label: {
                HStack(spacing: 14) {
                    GlyphTile(symbol: isCurrent ? "lock.open" : "lock",
                              kind: isCurrent ? .brass : .cool, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lock.name)
                            .type(T.F.body)
                            .fontWeight(.medium)
                            .foregroundStyle(T.C.ink)
                            .lineLimit(1)   // 极端锁名不许把副标题与行高挤坏
                        Text(lockSubtitle(lock))
                            .type(T.F.caption)
                            .foregroundStyle(T.C.ink3)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 空壳里不写默认锁、不删锁：这两个动作都会留下真实、不可逆的本机后果。
            if !DB.isDecoy {
                if LockArchive.defaultMac == lock.id {
                    Badge(text: "默认")
                } else {
                    Button {
                        LockArchive.setDefaultMac(lock.id)
                        Task { await app.reload() }
                    } label: {
                        Text("设为默认")
                            .type(T.F.caption)
                            .foregroundStyle(T.C.brass)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(T.C.brassWash, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    pendingDelete = lock
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        // 这是可点的控件，不是装饰点：ink4 的 2.3:1 太淡。
                        .foregroundStyle(T.C.ink3)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除 \(lock.name)")
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(T.C.hair).frame(height: 0.5)
        }
    }

    private func lockSubtitle(_ lock: LockSummary) -> String {
        var parts: [String] = [lock.model]
        parts.append(lock.isConnected ? "已连接" : "未连接")
        if lock.battery >= 0 { parts.append("\(lock.battery)%") }
        if lock.hidden { parts.append("已隐藏") }
        if !lock.group.isEmpty { parts.append(lock.group) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - 门锁设置

@MainActor
struct LockPolicyScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var muted = false
    @State private var safeMode = false
    @State private var interval = 6
    @State private var autoRetry = SettingsStore.shared.autoRetry
    @State private var defendMode: DefendMode = .off
    @State private var startHour = 22
    @State private var endHour = 7
    @State private var busy = false
    @State private var errorLine: String?
    @State private var loaded = false
    /// 关闭双验要二次确认：它是把一道安全保险拆掉，不该跟开静音一样一点就生效。
    @State private var confirmOffSafe = false
    /// 程序性回写开关（载入配置、失败回退）不该再触发 `.onChange` 下发一条命令。
    /// 否则打开这一页时若锁里静音/双验是开的，会平白重发一次设置命令。
    @State private var skipMutedChange = false
    @State private var skipSafeChange = false
    /// 小时 Picker 同理：载入与失败回退都会改值，不能因此再下发一条布防命令。
    @State private var skipStartHour = false
    @State private var skipEndHour = false
    // E6：清空全部密码的键入确认与确认框。
    @State private var clearTyped = ""
    @State private var confirmingClear = false

    /// cmd24 的字段是 1 字节**档位**（厂商实现里就是 2–6 秒），不是任意秒数。
    /// 原先这里是 6/10/15/30/60 —— 后四档全在协议范围外，锁要么忽略、要么按截断值执行，
    /// 而本机仍把 30/60 记进 `TailgateCfg`，今日页还会照它倒计时。
    private let intervals = [2, 3, 4, 5, 6]

    private var canDefend: Bool {
        app.lock.map { PidMap.canDefend($0.pid) } ?? false
    }

    var body: some View {
        ScreenScroll {
            NavRow(kicker: "设置 / 门锁设置", back: { dismiss() })

            DisplayLine(text: "把门锁\n调成你要的样子。", size: 34)
                .padding(.top, 16)
            Text("锁端设置都是真实命令；失败会如实报出来，不会假装成功。「连不上时自动重试」只改本机行为。")
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
                .padding(.top, 8)

            SectionHead(index: "01", title: "声音与验证")
            SwitchLine(title: "静音", detail: "门锁按键不再响；语音提示同时关闭。", isOn: $muted)
                .disabled(busy)
                .onChange(of: muted) { _, value in
                    guard loaded else { return }
                    if skipMutedChange { skipMutedChange = false; return }
                    // 一条设置命令还在路上时，第二次拨动直接退回原值：
                    // 原先两个请求会并发下发，谁后回谁说了算，开关停在与锁不一致的位置。
                    guard !busy else {
                        let revert = app.lock?.muted ?? !value
                        if muted != revert { skipMutedChange = true; muted = revert }
                        return
                    }
                    busy = true
                    Task {
                        await apply(await app.setMuted(value), "静音")
                        busy = false
                    }
                }
            SwitchLine(title: "双验模式", detail: "开门需要两种凭证（例如密码 + 指纹）。", isOn: safeModeBinding)
                .disabled(busy)
                .onChange(of: safeMode) { _, value in
                    guard loaded else { return }
                    if skipSafeChange { skipSafeChange = false; return }
                    guard !busy else {
                        let revert = app.lock?.safeMode ?? !value
                        if safeMode != revert { skipSafeChange = true; safeMode = revert }
                        return
                    }
                    busy = true
                    Task {
                        await apply(await app.setSafeMode(value), "双验")
                        busy = false
                    }
                }

            SectionHead(index: "02", title: "自动上锁")
            HStack(spacing: 8) {
                ForEach(intervals, id: \.self) { value in
                    ChoiceChip(title: "\(value)s", on: interval == value,
                               height: 40, fillWidth: true) {
                        guard !busy else { return }
                        interval = value
                        busy = true
                        Task {
                            await apply(await app.setAutoLock(value), "自动上锁")
                            busy = false
                        }
                    }
                }
            }
            .disabled(busy)
            .opacity(busy ? 0.55 : 1)

            SectionHead(index: "03", title: "布防")
            SegmentedBar(items: ["关闭", "本次", "时段"], selected: Binding(
                get: { defendMode.rawValue },
                set: { value in
                    let target = DefendMode(rawValue: value) ?? .off
                    guard target != defendMode else { return }
                    Task { await changeDefence(to: target) }
                }
            ), enabled: canDefend && !busy)

            if defendMode == .period {
                HStack(spacing: 14) {
                    hourPicker("开始", $startHour)
                    hourPicker("结束", $endHour)
                }
                .padding(.top, 12)
                // 有命令在飞时两个小时选择器不能改：`saveDefence` 的忙守卫会静默
                // return，界面却把新选的小时留着 —— 看起来改了，锁上没改。
                .disabled(busy)
                .opacity(busy ? 0.55 : 1)
                // 改小时也要真的下发：原先只有切换模式才会调 saveDefence，
                // 两个 Picker 选完什么都不会发生 —— 一个看着能改、实际不生效的控件。
                .onChange(of: startHour) { _, _ in
                    if skipStartHour { skipStartHour = false; return }
                    saveDefence()
                }
                .onChange(of: endHour) { _, _ in
                    if skipEndHour { skipEndHour = false; return }
                    saveDefence()
                }
                Text("跨午夜是允许的：22:00 到次日 07:00 也是合法时段。")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
                    .padding(.top, 8)
            }

            Text(defendHint)
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
                .padding(.top, 10)

            if !canDefend {
                Text("这把锁的型号不支持布防。")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.danger)
                    .padding(.top, 6)
            }

            if let errorLine {
                Text(errorLine)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.danger)
                    .padding(.top, 14)
            }

            if busy { ProgressView().tint(T.C.brass).padding(.top, 14) }

            // 空壳里不摆这个本机开关：它会真实改写 `kf_auto_retry`，
            // 退出空壳后仍影响重连行为。它不是外观类偏好，没有理由允许伪装态写入。
            if !DB.isDecoy {
                SectionHead(index: "04", title: "开锁")
                SwitchLine(title: "连不上时自动重试", detail: "连上门锁失败时自动再连一次。命令已经发出、没等到回执时不重试 —— 那一刻锁可能已经开了。", isOn: $autoRetry)
                    .onChange(of: autoRetry) { _, value in SettingsStore.shared.setAutoRetry(value) }
                SectionHead(index: "05", title: "相关")
            } else {
                SectionHead(index: "04", title: "相关")
            }
            Button {
                router.pushSettings(.zotp)
            } label: {
                ContentRow(symbol: "clock.arrow.circlepath", tone: .cool, title: "动态密码",
                           subtitle: "锁端按周期生成的一串数字", chevron: true)
            }
            .buttonStyle(.plain)

            // E6：清空全部密码 —— 双闸危险动作。键入「清空」+ 二次确认，
            // 与 ios27 同口径：锁端所有密码作废（指纹保留），本机密码台账同步清空。
            if !DB.isDecoy {
                SectionHead(index: "06", title: "危险操作")
                Text("清空全部密码会把锁里所有密码作废（指纹保留），同时清空本机密码台账。清空后需要逐条重新添加，不能撤销。")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                FieldInput(placeholder: "键入「清空」确认", text: $clearTyped)
                    .padding(.top, 8)
                if canClearPwd {
                    Button { confirmingClear = true } label: {
                        ContentRow(symbol: "eraser.fill", tone: .danger,
                                   title: "清空全部密码",
                                   subtitle: "先键入「清空」，点下去还会再问一次")
                    }
                    .buttonStyle(.plain)
                    .disabled(clearTyped != "清空" || busy || app.trial)
                    .opacity(clearTyped == "清空" && !busy && !app.trial ? 1 : 0.45)
                } else {
                    Text("这把锁的型号不支持清空密码。")
                        .type(T.F.caption)
                        .foregroundStyle(T.C.ink3)
                        .padding(.top, 6)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { load() }
        .confirmationDialog("关闭双验？", isPresented: $confirmOffSafe, titleVisibility: .visible) {
            Button("关闭双验", role: .destructive) { safeMode = false }
            Button("取消", role: .cancel) {}
        } message: {
            Text("之后开门只需要一种凭证。这道保险拆掉后，被逼着开门的人只要拿到一项凭证就够了。")
        }
        .confirmationDialog("清空全部密码？", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("清空密码", role: .destructive) {
                Task { await runClearPwd() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会把锁里所有密码作废（指纹保留），本机密码台账同时清空。这一步不可撤销：清空后只能逐条重新添加。")
        }
    }

    private var canClearPwd: Bool {
        app.lock.map { PidMap.canClearPwd($0.pid) } ?? false
    }

    private func runClearPwd() async {
        // E-07：await 期间换锁不能把清空动作落到另一把锁的台账 —— 先把 mac 钉住。
        guard let mac = app.lock?.id, !mac.isEmpty, !busy else { return }
        guard !DB.isDecoy, canClearPwd else { return }
        busy = true
        defer { busy = false }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            try await LockService.shared.pwdClear()
            var l = DB.ledger(mac)
            l.pwds = []
            DB.saveLedger(mac, l)
            clearTyped = ""
            AppToast.shared.show("已清空全部密码（指纹保留）")
            await app.reload()
        } catch {
            errorLine = "清空失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// 打开：照常走 `.onChange` 下发。
    /// 关闭：先不翻转状态，等确认对话框；用户取消时开关会停在原位。
    private var safeModeBinding: Binding<Bool> {
        Binding(
            get: { safeMode },
            set: { on in
                if on {
                    safeMode = true
                } else if safeMode {
                    confirmOffSafe = true
                }
            }
        )
    }

    private var defendHint: String {
        switch defendMode {
        case .off: return "撤防：不再按布防时段拦截；双验模式仍然生效。"
        case .once: return "本次布防：直到你手动撤防。"
        case .period: return "时段布防：只在设定的小时内生效。"
        }
    }

    private func hourPicker(_ title: String, _ value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .type(T.F.kicker)
                .foregroundStyle(T.C.ink3)
            Picker(title, selection: value) {
                ForEach(0 ..< 24, id: \.self) { hour in
                    Text(String(format: "%02d:00", hour)).tag(hour)
                }
            }
            .pickerStyle(.menu)
            .tint(T.C.ink)
            .disabled(busy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() {
        guard !loaded else { return }
        // 空壳里不读真实的自动上锁/布防配置：它们会暴露主人几点回家、晚上有没有设防。
        // 一律显示默认值，动作本身由 AppModel 的同一道闸拦下。
        if DB.isDecoy {
            muted = false
            safeMode = false
            interval = 6
            defendMode = .off
            startHour = 22
            endHour = 7
            loaded = true
            return
        }
        let savedMuted = app.lock?.muted ?? false
        if muted != savedMuted { skipMutedChange = true; muted = savedMuted }
        let savedSafe = app.lock?.safeMode ?? false
        if safeMode != savedSafe { skipSafeChange = true; safeMode = savedSafe }
        interval = DB.tailgate(app.currentMac)?.interval ?? 6
        if let cfg = DB.defend(app.currentMac) {
            defendMode = DefendMode(rawValue: cfg.control) ?? .off
            if defendMode == .period {
                let savedStart = DefendKit.secFromProto(cfg.startSec) / 3600
                if startHour != savedStart { skipStartHour = true; startHour = savedStart }
                let savedEnd = DefendKit.secFromProto(cfg.endSec) / 3600
                if endHour != savedEnd { skipEndHour = true; endHour = savedEnd }
            }
        }
        loaded = true
    }

    /// 分段控件的用户动作：先乐观更新，失败再退回上一次的真实配置。
    /// 不走 `.onChange` —— 回退本身会再触发一次 onChange，等于重发一条注定失败的命令。
    private func changeDefence(to target: DefendMode) async {
        guard !busy else { return }
        let previous = defendMode
        defendMode = target
        busy = true
        defer { busy = false }
        errorLine = nil
        let start = target == .period ? startHour * 3600 : 0
        let end = target == .period ? endHour * 3600 : 0
        let result = await app.applyDefence(target, startSec: start, endSec: end)
        if case .failure(let error) = result {
            errorLine = error.localizedDescription
            defendMode = previous
        }
    }

    /// 改小时：重新下发当前模式。失败时把两个 Picker 退回已保存的值。
    private func saveDefence() {
        guard loaded, canDefend, !busy else { return }
        let target = defendMode
        guard target == .period else { return }
        // busy 必须在同步段就置上：两个 Picker 连着改会各起一个 Task，
        // 若等 Task 里才置，两个请求会同时发出去。
        busy = true
        Task {
            defer { busy = false }
            let result = await app.applyDefence(target, startSec: startHour * 3600, endSec: endHour * 3600)
            if case .failure(let error) = result {
                errorLine = error.localizedDescription
                if let cfg = DB.defend(app.currentMac) {
                    let savedStart = DefendKit.secFromProto(cfg.startSec) / 3600
                    if startHour != savedStart { skipStartHour = true; startHour = savedStart }
                    let savedEnd = DefendKit.secFromProto(cfg.endSec) / 3600
                    if endHour != savedEnd { skipEndHour = true; endHour = savedEnd }
                }
            }
        }
    }

    private func apply(_ result: Result<Void, Error>, _ name: String) async {
        switch result {
        case .success:
            errorLine = nil
        case .failure(let error):
            errorLine = "\(name)没有保存：\(error.localizedDescription)"
            // 回退也要跳过 onChange：否则「失败 → 退回旧值 → onChange 又下发旧值」
            // 会多打一条命令，甚至让用户以为开关自己动了一下。
            if name == "静音" {
                let revert = app.lock?.muted ?? muted
                if muted != revert { skipMutedChange = true; muted = revert }
            }
            if name == "双验" {
                let revert = app.lock?.safeMode ?? safeMode
                if safeMode != revert { skipSafeChange = true; safeMode = revert }
            }
            if name == "自动上锁" {
                // 失败后按钮不能停在没生效的档位上。空壳里不读真实档位（见 load）。
                interval = DB.isDecoy ? 6 : (DB.tailgate(app.currentMac)?.interval ?? interval)
            }
        }
    }
}

// MARK: - 门锁信息

@MainActor
struct LockInfoScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var busy = false
    @State private var message: String?

    private var snap: StatusSnapshotData? { app.lastStatus?.status }

    var body: some View {
        ScreenScroll {
            NavRow(kicker: "设置 / 门锁信息", back: { dismiss() })

            DisplayLine(text: app.lock?.name ?? "门锁", size: 34)
                .padding(.top, 16)
            Text(app.lock?.model ?? "未知型号")
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
                .padding(.top, 4)

            SectionHead(index: "01", title: "读数")
            ReadingRow(items: [
                (label: "电量", value: batteryText, unit: batteryUnit),
                (label: "信号", value: LinkSenseModel.levelWord(app.link.rssiLevel), unit: nil),
                (label: "固件", value: firmwareText, unit: nil),
            ])
            .padding(.top, 8)

            VStack(spacing: 0) {
                infoRow("锁钟", lockClockText)
                infoRow("产品 ID", DB.isDecoy ? "—" : (app.lock.map { String($0.pid) } ?? "—"))
                // 验证模式与三族容量都在说"这把锁里现在有多少枚凭证"。
                // 空壳里凭证页是空的，这里若照实印出 "12 / 100 已用"，
                // 等于当着胁迫者的面拆穿伪装。一律显示「—」。
                infoRow("验证模式", DB.isDecoy ? "—" : (snap.map { $0.verifyMode == 0 ? "单验" : "双验" } ?? "—"))
                infoRow("PIN 容量", DB.isDecoy ? "—" : capacity(snap?.pinStock, snap?.pinCap))
                infoRow("密码容量", DB.isDecoy ? "—" : capacity(snap?.pwdStock, snap?.pwdCap))
                infoRow("指纹容量", DB.isDecoy ? "—" : capacity(snap?.fpStock, snap?.fpCap))
                infoRow("动态码周期", DB.isDecoy ? "—" : (snap?.zotpPeriod.map { "\($0) 分钟" } ?? "—"))
                // 空壳里不显示真实的「最近读取」：精确到分钟的读数时间也是使用痕迹。
                infoRow("最近读取", DB.isDecoy ? "—" : When.ago(Int64((app.lastStatus?.at ?? 0))))
            }
            .padding(.top, 10)

            SectionHead(index: "02", title: "动作")
            HStack(spacing: 10) {
                GhostButton(title: busy ? "处理中…" : "校准锁钟", symbol: "clock.arrow.circlepath") {
                    Task { await sync() }
                }
                GhostButton(title: "刷新读数", symbol: "arrow.clockwise") {
                    guard !busy else { return }
                    // `refreshStatus()` 在没有当前锁时静默返回；不先拦住，
                    // 下面会照样报「读数已刷新」—— 一句什么也没发生的成功。
                    guard !app.currentMac.isEmpty else {
                        message = "还没有绑定门锁。"
                        return
                    }
                    Task {
                        busy = true
                        // `refreshStatus()` 失败时只写 `app.lastError`，这一页原先从不读它 ——
                        // 点了没反应，用户不知道是没连上还是读失败。
                        if DB.isDecoy {
                            message = "暂时无法读取，请稍后再试。"
                        } else {
                            await app.refreshStatus()
                            message = app.lastError ?? "读数已刷新。"
                        }
                        busy = false
                    }
                }
            }
            .padding(.top, 6)
            .disabled(busy)
            .opacity(busy ? 0.55 : 1)

            if let message {
                Text(message)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink2)
                    .padding(.top, 12)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await app.refreshStatus() }
    }

    private var batteryText: String {
        let value = app.lock?.battery ?? -1
        if value < 0 { return "—" }
        return value > 80 ? ">80" : "\(value)"
    }

    private var batteryUnit: String? {
        let value = app.lock?.battery ?? -1
        return value < 0 || value > 80 ? nil : "%"
    }

    private var firmwareText: String {
        let fw = app.lock?.firmware ?? ""
        return fw.isEmpty ? "—" : fw
    }

    private var lockClockText: String {
        // 空壳里其余读数全是「—」，只剩锁钟照实显示等于自曝快照来自真实设备。
        guard !DB.isDecoy, let snap else { return "—" }
        if snap.lockTime == 0 { return "没有时钟" }
        return When.clock(Int64(ZKProtocol.protoSecondsToUnix(snap.lockTime)))
    }

    private func capacity(_ stock: Int?, _ cap: Int?) -> String {
        guard let stock else { return "—" }
        guard let cap, cap > 0 else { return "\(stock) 剩余" }
        return "\(cap - stock) / \(cap) 已用"
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .type(T.F.callout)
                .foregroundStyle(T.C.ink2)
            Spacer()
            Text(value)
                .type(T.F.mono)
                .foregroundStyle(T.C.ink)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(T.C.hair).frame(height: 0.5)
        }
    }

    private func sync() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let result = await app.syncTime()
        switch result {
        case .success(let pair):
            if let after = pair.1 {
                message = after == 0 ? "锁钟已对齐。" : "锁钟仍有 \(after) 秒偏差。"
            } else {
                message = "校时指令已下发，但没能回读确认。"
            }
        case .failure(let error):
            message = error.localizedDescription
        }
    }
}
