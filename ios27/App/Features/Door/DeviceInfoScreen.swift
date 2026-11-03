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
        .navigationBarTitleDisplayMode(.large)
        .task {
            batteryModel = meta.batteryModel
            await reload()
        }
    }

    // MARK: 页头

    private var header: some View {
        VStack(alignment: .leading, spacing: V.S.gapXS) {
            // 2026-11-03：标题改由系统导航栏承担（大标题模式，与其他子页一致）。
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
                VFieldRow(label: "密码容量", value: capacityText(used: pwdUsed, cap: liveStatus?.pwdInfoCapacity ?? cachedStatus?.pwdCap ?? 0))
                VFieldRow(label: "指纹容量", value: capacityText(used: fpUsed, cap: liveStatus?.fpInfoCapacity ?? cachedStatus?.fpCap ?? 0))
                // 2026-11-01：把「锁端存量」与「本机池」并排 —— 排障 rc=2 时第一眼看的就是这两个数：
                // 锁端已用 64 而本机池只有 20 ⇒ 池子被恢复/迁移污染或两台 App 打架，现签必败。
                VFieldRow(label: "PIN 容量", value: capacityText(used: pinUsed, cap: liveStatus?.pinInfoCapacity ?? cachedStatus?.pinCap ?? 0))
                if let note = localPinNote {
                    Text(note)
                        .font(V.F.unit)
                        .foregroundStyle(localPinMismatch ? V.C.warning : V.C.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                // 2026-11-03（同页去重）：当前电量在「运行状态」卡已有（门锁电量 76%），
                // 采样卡的职责是采样序列与换电记录，不再重复同一个读数。
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
            SettingsNote(text: "进页会自动读一次锁状态；锁钟偏差超过 2 秒时自动校时一次。静音、安全模式、校时、防尾随与固件升级在「锁设置」里。")
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
        // 2026-11-03：0 天读起来像"没服役"，实际是"今天第一次记到"。给个明确说法。
        if days == 0 { return "今天起算" }
        return days > 365 ? "\(days) 天 · 已超一年" : "\(days) 天"
    }

    private func boundText(_ kc: Keychain) -> String {
        // 2026-11-03（信息架构 QA · 时区）：`pairedAt` 是 `DF.iso()` 写的 **UTC** 串，
        // 原来 `prefix(16)` 直接当本地时间显示 —— +08:00 下早 8 小时（配对时间看着像凌晨）。
        let s = DF.localMinute(fromISO: kc.pairedAt)
        return s.isEmpty ? "—" : s
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
        // 0 = 锁端没回时钟（不是 2010-01-01）；`ProtoTime.localStr(0)` 返回空串，直接显示会是**一片空白**。
        guard let t = status?.lockTime, t > 0 else { return "—" }
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

    // 2026-11-04（截图实测 · 两页读数打架）：本页只认**实时读到的** `status`，
    // 而「锁设置」页读的是 `DB.readStatus` 快照。于是同一把锁、同一时刻：
    //   本页 → 「已用 1 · 容量未读」；锁设置 → 「64 / 64」。
    // 电量那一行早就做了 `status?.powerLevel ?? DB.readStatus(mac)?.powerLevel` 的回落，
    // 容量三行却没有 —— 同页两套口径。这里补齐同一个回落。
    private var liveStatus: LockStatus? { status }
    private var cachedStatus: StatusSnapshotData? { DB.readStatus(mac) }

    private var pwdUsed: Int {
        if let cap = liveStatus?.pwdInfoCapacity ?? cachedStatus?.pwdCap, cap > 0 {
            let stock = liveStatus?.pwdStock ?? cachedStatus?.pwdStock ?? 0
            return max(cap - stock, 0)
        }
        return DB.ledger(mac).pwds.count
    }

    private var fpUsed: Int {
        if let cap = liveStatus?.fpInfoCapacity ?? cachedStatus?.fpCap, cap > 0 {
            let stock = liveStatus?.fpStock ?? cachedStatus?.fpStock ?? 0
            return max(cap - stock, 0)
        }
        return DB.ledger(mac).fps.count
    }

    /// 本机钥匙串的 PIN 数与锁端存量的对照说明（不一致 = 池子污染/两台 App 打架）。
    private var localPinNote: String? {
        let local = kc?.pins.filter { !$0.isEmpty }.count ?? 0
        guard let stock = status?.pinStock, let cap = status?.pinInfoCapacity, cap > 0 else { return nil }
        let onLock = max(cap - stock, 0)
        if local == 0 { return "本机池为空" }
        if local == onLock { return "本机池 \(local) 枚 · 与锁端一致" }
        return "本机池 \(local) 枚 · 锁端已用 \(onLock) 枚 —— 不一致，现签凭证会被拒（rc=2）"
    }

    private var localPinMismatch: Bool {
        let local = kc?.pins.filter { !$0.isEmpty }.count ?? 0
        guard let stock = status?.pinStock, let cap = status?.pinInfoCapacity, cap > 0 else { return false }
        return local != max(cap - stock, 0)
    }

    private var pinUsed: Int {
        if let cap = liveStatus?.pinInfoCapacity ?? cachedStatus?.pinCap, cap > 0 {
            let stock = liveStatus?.pinStock ?? cachedStatus?.pinStock ?? 0
            return max(cap - stock, 0)
        }
        return kc?.pins.count ?? 0
    }

    /// 容量读数。**两个数都要读成"已用 / 容量"**：
    ///   · 有容量：`已用 / 总容量`（与读数格里的 "12 / 64" 同序）；
    ///   · 容量未读：只报**已用**，并说清容量确实没读到。
    ///
    /// 2026-11-03（全功能点排查 · 措辞）：旧写法是「容量未读 · 存量 1」——
    /// 一是"容量"在标签和值里各出现一次，二是"存量"在中文里指**剩余**，
    /// 而这里给的是**已用**（`cap - stock`）。方向读反了就会把"用了 1 个"
    /// 看成"还剩 1 个"，排障时结论正好相反。
    private func capacityText(used: Int, cap: Int) -> String {
        cap > 0 ? "\(max(used, 0)) / \(cap)" : "已用 \(max(used, 0)) · 容量未读"
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
        // E-07：await 期间换锁会把快照/电池采样写到另一把锁。
        let mac = self.mac
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
            // 2026-11-01（Round 245）：**`lockTime == 0` 是「锁端没回时钟」的占位值**（`StatusParser` 把 0 原样存 0）。
            // 直接算 `0 - nowProtoSeconds()` 会得到 ≈ **-531260264 秒**的假偏差 —— 正是用户报的「偏差 531260264 秒」。
            // 更糟的是下面 `abs(drift) > 2` 会因此**每次进设备页都自动写一次锁钟**（一个会改锁的操作），
            // 而写成功之后读数仍是 0（固件没回）⇒ 偏差照旧 ⇒ 每次进页都写一遍。
            // 正确语义：读不到时钟就是「不知道」，不显示偏差、不自动校时。
            let drift = (st.lockTime ?? 0) > 0 ? Int((st.lockTime ?? 0) - ZKProtocol.nowProtoSeconds()) : nil
            clockDrift = drift
            // 进页自动校时：只在真漂移 (>2s) 时写，与 APK 的无条件写终态一致但少一次广播。
            if let drift, abs(drift) > 2 {
                // 检测到漂移却校时失败时，**必须说出来**。
                // 旧实现用 `try?` 吞掉错误，outcome 保持空串 —— 用户看到的是
                // "偏差 37 秒"却什么也没发生，也无从知道校时没成功（HIG feedback：
                // 命令没做成要说清原因）。
                do {
                    let res = try await LockService.shared.syncTime()
                    st = try await LockService.shared.getStatus(mac: mac)
                    DB.writeStatus(mac, st)
                    status = st
                    clockDrift = (st.lockTime ?? 0) > 0 ? Int((st.lockTime ?? 0) - ZKProtocol.nowProtoSeconds()) : nil
                    outcome = "已自动校时 · 校前偏差 \(res.before) 秒 / 校后 \(res.after) 秒"
                } catch {
                    outcome = "检测到锁钟偏差 \(drift) 秒，但自动校时失败："
                        + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
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
