// LockSettingsScreens.swift —— 我的锁 / 门锁设置 / 门锁信息。
import SwiftUI

// MARK: - 我的锁

@MainActor
struct LocksScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var pendingDelete: LockSummary?
    @State private var errorLine: String?

    var body: some View {
        ScreenScroll {
            NavRow(kicker: "设置 / 我的锁", back: { dismiss() })

            DisplayLine(text: app.locks.isEmpty ? "还没有锁。" : "\(app.locks.count) 把锁，\n一个家。", size: 34)
                .padding(.top, 16)
            Text("长按不可用；点一行切换当前锁，右侧「默认」决定冷启动落点。")
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
                .padding(.top, 8)

            SectionHead(index: "01", title: "门锁", trailing: "\(app.locks.count)")
            ForEach(app.locks) { lock in
                lockRow(lock)
            }

            if let errorLine {
                Text(errorLine)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.danger)
                    .padding(.top, 12)
            }

            SectionHead(index: "02", title: "数据")
            Button {
                Task {
                    for lock in app.locks { DB.removeDevice(lock.id) }
                    app.overrideMac = nil
                    await app.reload()
                }
            } label: {
                ContentRow(symbol: "trash", tone: .danger, title: "删除全部本机数据",
                           subtitle: "锁端不受影响；本机钥匙串、台账、记录全部清掉", chevron: true)
            }
            .buttonStyle(.plain)
        }
        .toolbar(.hidden, for: .navigationBar)
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
                    .foregroundStyle(T.C.ink4)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("删除 \(lock.name)")
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
    @State private var defendMode: DefendMode = .off
    @State private var startHour = 22
    @State private var endHour = 7
    @State private var busy = false
    @State private var errorLine: String?
    @State private var loaded = false

    private let intervals = [6, 10, 15, 30, 60]

    var body: some View {
        ScreenScroll {
            NavRow(kicker: "设置 / 门锁设置", back: { dismiss() })

            DisplayLine(text: "把门锁\n调成你要的样子。", size: 34)
                .padding(.top, 16)
            Text("这里的每一项都是一条真实命令；失败会如实报出来，不会假装成功。")
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
                .padding(.top, 8)

            SectionHead(index: "01", title: "声音与验证")
            SwitchLine(title: "静音", detail: "门锁按键不再响；语音提示同时关闭。", isOn: $muted)
                .onChange(of: muted) { _, value in
                    guard loaded else { return }
                    Task { await apply(await app.setMuted(value), "静音") }
                }
            SwitchLine(title: "双验模式", detail: "开门需要两种方式：密码 + 指纹。", isOn: $safeMode)
                .onChange(of: safeMode) { _, value in
                    guard loaded else { return }
                    Task { await apply(await app.setSafeMode(value), "双验") }
                }

            SectionHead(index: "02", title: "自动上锁")
            HStack(spacing: 8) {
                ForEach(intervals, id: \.self) { value in
                    Button {
                        interval = value
                        Task { await apply(await app.setAutoLock(value), "自动上锁") }
                    } label: {
                        Text("\(value)s")
                            .type(T.F.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(interval == value ? .white : T.C.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(interval == value ? T.C.brass : T.C.glass, in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(interval == value ? .clear : T.C.glassEdge, lineWidth: 0.5)
                            }
                    }
                    .buttonStyle(PressStyle())
                }
            }

            SectionHead(index: "03", title: "布防")
            SegmentedBar(items: ["关闭", "本次", "时段"], selected: Binding(
                get: { defendMode.rawValue },
                set: { defendMode = DefendMode(rawValue: $0) ?? .off }
            ))
            .onChange(of: defendMode) { _, _ in saveDefence() }

            if defendMode == .period {
                HStack(spacing: 14) {
                    hourPicker("开始", $startHour)
                    hourPicker("结束", $endHour)
                }
                .padding(.top, 12)
                Text("跨午夜是允许的：22:00 到次日 07:00 也是合法时段。")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
                    .padding(.top, 8)
            }

            Text(defendHint)
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
                .padding(.top, 10)

            if app.lock.map({ PidMap.canDefend($0.pid) }) == false {
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

            SectionHead(index: "04", title: "相关")
            Button {
                router.pushSettings(.zotp)
            } label: {
                ContentRow(symbol: "clock.arrow.circlepath", tone: .cool, title: "动态密码",
                           subtitle: "锁端按周期生成的一串数字", chevron: true)
            }
            .buttonStyle(.plain)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { load() }
    }

    private var defendHint: String {
        switch defendMode {
        case .off: return "撤防：任何凭证都能开门。"
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() {
        guard !loaded else { return }
        muted = app.lock?.muted ?? false
        safeMode = app.lock?.safeMode ?? false
        interval = DB.tailgate(app.currentMac)?.interval ?? 6
        if let cfg = DB.defend(app.currentMac) {
            defendMode = DefendMode(rawValue: cfg.control) ?? .off
            if defendMode == .period {
                startHour = DefendKit.secFromProto(cfg.startSec) / 3600
                endHour = DefendKit.secFromProto(cfg.endSec) / 3600
            }
        }
        loaded = true
    }

    private func saveDefence() {
        guard loaded else { return }
        Task {
            busy = true
            defer { busy = false }
            let start = defendMode == .period ? startHour * 3600 : 0
            let end = defendMode == .period ? endHour * 3600 : 0
            let result = await app.applyDefence(defendMode, startSec: start, endSec: end)
            if case .failure(let error) = result { errorLine = error.localizedDescription }
        }
    }

    private func apply(_ result: Result<Void, Error>, _ name: String) async {
        switch result {
        case .success:
            errorLine = nil
        case .failure(let error):
            errorLine = "\(name)没有保存：\(error.localizedDescription)"
            if name == "静音" { muted = app.lock?.muted ?? muted }
            if name == "双验" { safeMode = app.lock?.safeMode ?? safeMode }
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
                infoRow("产品 ID", String(app.lock?.pid ?? 0))
                infoRow("验证模式", (snap?.verifyMode ?? 0) == 0 ? "单验" : "双验")
                infoRow("PIN 容量", capacity(snap?.pinStock, snap?.pinCap))
                infoRow("密码容量", capacity(snap?.pwdStock, snap?.pwdCap))
                infoRow("指纹容量", capacity(snap?.fpStock, snap?.fpCap))
                infoRow("动态码周期", snap?.zotpPeriod.map { "\($0) 分钟" } ?? "—")
                infoRow("最近读取", When.ago(Int64((app.lastStatus?.at ?? 0))))
            }
            .padding(.top, 10)

            SectionHead(index: "02", title: "动作")
            HStack(spacing: 10) {
                GhostButton(title: busy ? "处理中…" : "校准锁钟", symbol: "clock.arrow.circlepath") {
                    Task { await sync() }
                }
                GhostButton(title: "刷新读数", symbol: "arrow.clockwise") {
                    Task {
                        busy = true
                        await app.refreshStatus()
                        busy = false
                    }
                }
            }
            .padding(.top, 6)

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
        let seconds = snap?.lockTime ?? 0
        if seconds == 0 { return "没有时钟" }
        return When.clock(Int64(ZKProtocol.protoSecondsToUnix(seconds)))
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
        busy = true
        defer { busy = false }
        let result = await app.syncTime()
        switch result {
        case .success(let pair):
            message = pair.1 == 0 ? "锁钟已对齐。" : "锁钟仍有 \(pair.1) 秒偏差。"
        case .failure(let error):
            message = error.localizedDescription
        }
    }
}
