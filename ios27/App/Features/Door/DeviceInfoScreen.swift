// DeviceInfoScreen.swift —— 锁信息名片（原 DeviceInfoView.swift:6-307）。
//
// 这屏干什么：把这把锁的身份 / 运行读数 / 电量采样 / 电池档案 / 连接环境摊成一张诊断名片，
//   进页自动读一次 cmd03；锁钟偏差 > 2 秒时自动校时（原 APK RominfoPage 的进页同步口径）。
// 数据从哪来：LockService.getStatus（真链路）+ DB 快照 + BatteryCare 采样 + LockArchive 档案。
// 主动作：「重新读取」；进页自动校时是隐式动作，完成后在页面上如实写「已自动校时」。
import SwiftUI

struct DeviceInfoScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    @State private var status: LockStatus?
    @State private var samples: [BattSample] = []
    @State private var clockDrift: Int?
    @State private var busy = false
    @State private var outcome: String?
    @State private var batteryModel = ""
    @State private var batterySaved = false
    @State private var link = LinkSenseModel()

    private var mac: String { app.lock?.id ?? "" }
    private var kc: Keychain? { app.currentKeychain }
    private var meta: LockMeta { LockArchive.meta(mac) }

    var body: some View {
        ScrollView {
            VStack(spacing: V.S.gap16) {
                header
                if let kc {
                    identityCard(kc)
                    statusCard(kc)
                    batteryCard(kc)
                    batteryArchiveCard
                    environmentCard
                    reloadPanel
                } else {
                    noLockCard
                }
            }
            .padding(.vertical, V.S.gap16)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("锁信息名片")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            batteryModel = meta.batteryModel
            await reload()
        }
    }

    // MARK: 页头

    private var header: some View {
        VStack(alignment: .leading, spacing: V.S.gapXS) {
            Text("锁信息名片")
                .font(V.F.displayHome)
                .foregroundStyle(V.C.text1)
            Text(app.lock.map { "\($0.name) · \($0.model)" } ?? "还没有门锁")
                .font(V.F.footnote)
                .foregroundStyle(V.C.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, V.S.pageGutter)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: 身份

    private func identityCard(_ kc: Keychain) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                HStack(spacing: V.S.gapM) {
                    Image(systemName: LockArchive.symbolName(meta))
                        .font(V.F.displayD)
                        .foregroundStyle(swatch(meta.colorKey))
                        .frame(width: V.Icon.xl * 2, height: V.Icon.xl * 2)
                        .background(V.C.cardAlt, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: V.S.gapXXS) {
                        Text(LockArchive.displayName(kc))
                            .font(V.F.section)
                            .foregroundStyle(V.C.text1)
                            .lineLimit(1)
                        Text(LockArchive.subtitle(kc))
                            .font(V.F.footnote)
                            .foregroundStyle(V.C.text3)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                VDivider()
                VFieldRow(label: "型号", value: PidMap.productName(kc.pid), mono: false)
                VFieldRow(label: "固件版本", value: firmwareText(kc))
                if let v = status?.verDFU, v > 0 {
                    VFieldRow(label: "Boot 版本", value: "\(v)")
                }
                if let v = status?.verKeyboard, v > 0 {
                    VFieldRow(label: "键盘版本", value: "\(v)")
                }
                VFieldRow(label: "固件服役", value: firmwareAge(kc))
                VFieldRow(label: "MAC", value: kc.mac)
                VFieldRow(label: "绑定于", value: boundText(kc))
                VFieldRow(label: "链路验证", value: verifiedText)
                VFieldRow(label: "锁钟偏差", value: driftText, tint: driftTint)
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    // MARK: 运行状态

    private func statusCard(_ kc: Keychain) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VSectionLabel(text: "运行状态", trailing: sampleText)
                VReadingGrid(items: [
                    .init(label: "门锁电量", value: batteryText, tint: batteryTint),
                    .init(label: "安全模式", value: modeText),
                    .init(label: "锁内时间", value: lockTimeText),
                    .init(label: "信号", value: signalText),
                ], columns: 2)
                .padding(.top, V.S.gapXS)
                VDivider()
                VFieldRow(label: "密码容量", value: capacityText(used: pwdUsed, cap: status?.pwdInfoCapacity ?? 0))
                VFieldRow(label: "指纹容量", value: capacityText(used: fpUsed, cap: status?.fpInfoCapacity ?? 0))
                VFieldRow(label: "PIN 容量", value: capacityText(used: pinUsed, cap: status?.pinInfoCapacity ?? 0))
                VDivider()
                Text("Boot / 键盘版本只在锁上报时出现；缺失表示该固件不报这两支，不是读取失败。")
                    .font(V.F.unit)
                    .foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    // MARK: 电量采样

    private func batteryCard(_ kc: Keychain) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VSectionLabel(text: "电量采样", trailing: "\(samples.count) 点")
                if samples.count >= 2 {
                    VMiniBars(values: sampleBars, tint: V.C.rewardGreen)
                        .padding(.top, V.S.gapXS)
                    Text(trendCaption)
                        .font(V.F.unit)
                        .foregroundStyle(V.C.text3)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(samples.isEmpty
                         ? "还没有采样。每次连上锁读状态都会自动记一笔，曲线要积累几个点才画得出来。"
                         : "已积累 1 个采样点，再连几次就能画出走势。")
                        .font(V.F.footnote)
                        .foregroundStyle(V.C.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VDivider()
                VFieldRow(label: "电量读数", value: batteryText, tint: batteryTint)
                VFieldRow(label: "采样时间", value: sampleText)
                VFieldRow(label: "耗材提醒", value: batteryModel.isEmpty ? "未记录型号" : batteryModel)
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    private var sampleBars: [Double] {
        samples.suffix(V.Mini.gridCount).map { Double($0.pct) }
    }

    private var trendCaption: String {
        guard let first = samples.first, let last = samples.last else { return "" }
        let lo = samples.map(\.pct).min() ?? 0
        let hi = samples.map(\.pct).max() ?? 0
        let days = max(1, Int((last.t - first.t) / 86_400_000) + 1)
        return "走势：\(samples.count) 个采样点 · 跨 \(days) 天 · 最低 \(lo)% / 最高 \(hi)%"
    }

    // MARK: 电池档案（本机台账，可编辑）

    private var batteryArchiveCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VSectionLabel(text: "电池档案", trailing: batterySaved ? "已保存" : "本机")
                VTextFieldRow(label: "电池型号", text: $batteryModel, placeholder: "如 CR123A × 2")
                VFieldRow(label: "上次换电", value: batteryDateText)
                HStack(spacing: V.S.gapS) {
                    VOutlineButton(title: "记为今天", systemImage: "calendar.badge.checkmark") {
                        var m = meta
                        m.batteryChangedAt = Date().timeIntervalSince1970
                        m.batteryModel = batteryModel.trimmingCharacters(in: .whitespaces)
                        LockArchive.save(mac, m)
                        batterySaved = true
                    }
                    VOutlineButton(title: "保存型号", systemImage: "checkmark") {
                        var m = meta
                        m.batteryModel = batteryModel.trimmingCharacters(in: .whitespaces)
                        LockArchive.save(mac, m)
                        batterySaved = true
                    }
                }
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    // MARK: 连接环境

    private var environmentCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VSectionLabel(text: "连接环境")
                VFieldRow(label: "当前链路", value: link.phase.rawValue)
                VFieldRow(label: "最近信号", value: link.lastRSSI.map { "\($0) dBm · \(link.rssiWord)" } ?? "未读到")
                VFieldRow(label: "握手耗时", value: link.connectMs.map { "\($0) ms" } ?? "未测")
                Text("连接环境只看最近一次扫描与握手；读不到就写读不到，不拿邻近数值冒充。")
                    .font(V.F.unit)
                    .foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    private var reloadPanel: some View {
        VStack(spacing: V.S.gapS) {
            VActionButton(title: busy ? "正在读取…" : "重新读取", systemImage: "arrow.clockwise", busy: busy) {
                Task { await reload() }
            }
            .disabled(busy)
            if let outcome {
                Text(outcome)
                    .font(V.F.footnote)
                    .foregroundStyle(outcome.hasPrefix("已") ? V.C.rewardGreen : V.C.text2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SettingsNote(text: "进页会自动读一次 cmd03；锁钟偏差超过 2 秒时自动校时一次（与 APK RominfoPage 同口径）。静音、安全模式、校时、防尾随与固件升级在「锁设置」里。")
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    private var noLockCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapM) {
                Text("还没有门锁")
                    .font(V.F.displayB)
                    .foregroundStyle(V.C.text1)
                Text("锁信息名片读的是具体一把锁的固件与容量。先把门锁加进来，再回这一页。")
                    .font(V.F.body)
                    .foregroundStyle(V.C.text2)
                    .fixedSize(horizontal: false, vertical: true)
                VActionButton(title: "添加门锁", systemImage: "plus") {
                    router.request(.dest(.addLock))
                }
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    // MARK: 读数

    private func firmwareText(_ kc: Keychain) -> String {
        if let fw = status?.firmware, !fw.isEmpty { return fw }
        return kc.fw.isEmpty ? "未知" : kc.fw
    }

    private func firmwareAge(_ kc: Keychain) -> String {
        var fw = kc.fw
        if let f = status?.firmware, !f.isEmpty { fw = f }
        guard let since = BatteryCare.fwSince(kc.mac, fw: fw) else { return "首次读到后起算" }
        let days = max(0, Int(Date().timeIntervalSince1970 * 1000 - since.at) / 86_400_000)
        return days > 365 ? "\(days) 天 · 已超一年" : "\(days) 天"
    }

    private func boundText(_ kc: Keychain) -> String {
        let raw = String(kc.pairedAt.prefix(16)).replacingOccurrences(of: "T", with: " ")
        return raw.isEmpty ? "—" : raw
    }

    private var verifiedText: String {
        let t = meta.verifiedAt
        guard t > 0 else { return "待验证（成功开一次锁即打标）" }
        return "已验证 · " + DF.localShort(Date(timeIntervalSince1970: t))
    }

    private var driftText: String {
        guard let d = clockDrift else { return "—" }
        if d == 0 { return "与手机一致" }
        return (d > 0 ? "+" : "") + "\(d) 秒"
    }

    private var driftTint: Color {
        guard let d = clockDrift else { return V.C.text1 }
        return abs(d) > 60 ? V.C.warning : V.C.text1
    }

    private var batteryText: String {
        let p = BatteryCare.displayPct(mac, snapshot: status?.powerLevel ?? DB.readStatus(mac)?.powerLevel ?? -1)
        return BatteryCare.faceText(p)
    }

    private var batteryTint: Color {
        let p = BatteryCare.displayPct(mac, snapshot: status?.powerLevel ?? DB.readStatus(mac)?.powerLevel ?? -1)
        return p >= 0 && p <= 20 ? V.C.warning : V.C.text1
    }

    private var modeText: String {
        guard let st = status else { return "—" }
        if st.verifyMode == 1 && st.broadcastMode != 0 { return "B · 双验" }
        if st.verifyMode == 1 { return "C · 广播+验证" }
        return "A · 单验"
    }

    private var lockTimeText: String {
        guard let t = status?.lockTime else { return "—" }
        return ProtoTime.localStr(t)
    }

    private var signalText: String {
        guard let r = link.lastRSSI else { return "—" }
        return "\(r) dBm"
    }

    private var sampleText: String {
        let at = max(LockStats.snapAt(mac), samples.last?.t ?? 0)
        return at > 0 ? LockStats.sampleTimeText(at) : "尚未读取过快照"
    }

    private var batteryDateText: String {
        guard meta.batteryChangedAt > 0 else { return "未记录" }
        return DF.localDate(Date(timeIntervalSince1970: meta.batteryChangedAt))
    }

    private var pwdUsed: Int {
        if let cap = status?.pwdInfoCapacity, cap > 0 { return max(cap - (status?.pwdStock ?? 0), 0) }
        return DB.ledger(mac).pwds.count
    }

    private var fpUsed: Int {
        if let cap = status?.fpInfoCapacity, cap > 0 { return max(cap - (status?.fpStock ?? 0), 0) }
        return DB.ledger(mac).fps.count
    }

    private var pinUsed: Int {
        if let cap = status?.pinInfoCapacity, cap > 0 { return max(cap - (status?.pinStock ?? 0), 0) }
        return kc?.pins.count ?? 0
    }

    private func capacityText(used: Int, cap: Int) -> String {
        cap > 0 ? "\(max(used, 0)) / \(cap)" : "容量未读 · 存量 \(max(used, 0))"
    }

    private func swatch(_ key: String) -> Color {
        switch key {
        case "ok": return V.C.rewardGreen
        case "warn": return V.C.coral
        case "danger": return V.C.red
        case "neutral": return V.C.text3
        default: return V.C.blue
        }
    }

    // MARK: 真链路

    private func reload() async {
        guard !mac.isEmpty, !busy else { return }
        busy = true
        outcome = nil
        defer { busy = false }
        link.update(mac: mac)
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            var st = try await LockService.shared.getStatus(mac: mac)
            DB.writeStatus(mac, st)
            status = st
            samples = BatteryCare.samples(mac)
            let drift = st.lockTime.map { Int($0 - ZKProtocol.nowProtoSeconds()) }
            clockDrift = drift
            // 进页自动校时：只在真漂移 (>2s) 时写，与 APK 的无条件写终态一致但少一次广播。
            if let drift, abs(drift) > 2 {
                if let res = try? await LockService.shared.syncTime() {
                    st = try await LockService.shared.getStatus(mac: mac)
                    DB.writeStatus(mac, st)
                    status = st
                    clockDrift = st.lockTime.map { Int($0 - ZKProtocol.nowProtoSeconds()) }
                    outcome = "已自动校时 · 校前偏差 \(res.before) 秒 / 校后 \(res.after) 秒"
                }
            } else {
                outcome = "已重新读取锁信息"
            }
            await app.reload(refreshStatus: false)
        } catch {
            outcome = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview("DeviceInfoScreen") {
    NavigationStack { DeviceInfoScreen() }
        .environment(AppModel())
        .environment(Router())
}
