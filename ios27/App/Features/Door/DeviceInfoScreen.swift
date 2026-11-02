// DeviceInfoScreen.swift —— 锁信息名片（诊断页）。
//
// 这屏干什么：只放**别处没有**的诊断事实 —— 身份（MAC / 型号 / 绑定于 / 链路验证）、容量族、
//   电量采样走势、连接环境。**电量 / 固件 / 安全模式 / 锁钟偏差** 四类读数归「锁实况」，本页不再重复；
//   电池型号与换电日期归「电池档案」，本页只留跳转入口。
// 数据从哪来：LockService.getStatus（真链路）+ DB 快照 + BatteryCare 采样 + LockArchive 档案。
// 主动作：「重新读取」（只读，不再隐式改锁 —— 进页自动校时已随「校时」并入锁实况）。
import SwiftUI

struct DeviceInfoScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    @State private var status: LockStatus?
    @State private var samples: [BattSample] = []
    @State private var busy = false
    @State private var outcome: String?
    @State private var link = LinkSenseModel()

    private var mac: String { app.lock?.id ?? "" }
    private var kc: Keychain? { app.currentKeychain }
    private var meta: LockMeta { LockArchive.meta(mac) }

    var body: some View {
        // 全换系统（2026-11-02）：整页容器是系统 `List`（与前几轮同一配方）。
        // 身份 / 容量 / 电池档案入口 / 连接环境四段是**行式内容** → `Section`；
        // 电量采样是图（VMiniBars），保持卡片用 `plainRow()`；动作与空态同理。
        // 本页仍是第 2 轮瘦身后的诊断名片：电量 / 固件以外的安全模式 / 锁钟偏差不在这里。
        List {
            header.plainRow()
            if let kc {
                identitySection(kc)
                capacitySection
                batteryCard.plainRow()
                batteryEntrySection
                environmentSection
                reloadPanel.plainRow()
            } else {
                noLockCard.plainRow()
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(V.S.gap16)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, V.S.gap16, for: .scrollContent)
        .contentMargins(.bottom, V.S.gapL, for: .scrollContent)
        .background(CanvasBackground())
        .navigationTitle("锁信息名片")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
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
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: 身份

    private func identitySection(_ kc: Keychain) -> some View {
        Section {
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
            .listRowInsets(EdgeInsets(top: V.S.gapS, leading: V.S.cardPad, bottom: V.S.gapS, trailing: V.S.cardPad))
            VFieldRow(label: "型号", value: PidMap.productName(kc.pid), mono: false)
            if let v = status?.verDFU, v > 0 {
                VFieldRow(label: "Boot 版本", value: "\(v)")
            }
            if let v = status?.verKeyboard, v > 0 {
                VFieldRow(label: "键盘版本", value: "\(v)")
            }
            // 固件版本文字走 Reading.firmware（本页原先自己取 status?.firmware / kc.fw）。
            VFieldRow(label: "固件", value: Reading.firmware(mac).text)
            VFieldRow(label: "固件服役", value: firmwareAge(kc))
            VFieldRow(label: "MAC", value: shortMAC(kc.mac))
            VOutlineButton(title: "复制完整 MAC", systemImage: "doc.on.doc") {
                Clip.set(kc.mac)
            }
            VFieldRow(label: "绑定于", value: boundText(kc))
            VFieldRow(label: "链路验证", value: verifiedText)
            Text("Boot / 键盘版本只在锁上报时出现；缺失表示该固件不报这两支，不是读取失败。")
                .font(V.F.unit)
                .foregroundStyle(V.C.text3)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("身份")
                .font(V.F.section)
                .foregroundStyle(V.C.text1)
                .textCase(nil)
        }
    }

    // MARK: 容量族（锁端存量 / 本机池对照）

    private var capacitySection: some View {
        Section {
            VFieldRow(label: "密码容量", value: capacityText(used: pwdUsed, cap: status?.pwdInfoCapacity ?? 0))
            VFieldRow(label: "指纹容量", value: capacityText(used: fpUsed, cap: status?.fpInfoCapacity ?? 0))
            // 2026-11-01：把「锁端存量」与「本机池」并排 —— 排障 rc=2 时第一眼看的就是这两个数：
            // 锁端已用 64 而本机池只有 20 ⇒ 池子被恢复/迁移污染或两台 App 打架，现签必败。
            VFieldRow(label: "PIN 容量", value: capacityText(used: pinUsed, cap: status?.pinInfoCapacity ?? 0))
            if let note = localPinNote {
                Text(note)
                    .font(V.F.unit)
                    .foregroundStyle(localPinMismatch ? V.C.warning : V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            HStack(spacing: V.S.gapS) {
                Text("容量")
                    .font(V.F.section)
                    .foregroundStyle(V.C.text1)
                    .textCase(nil)
                Spacer(minLength: 0)
                Text(sampleText)
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text3)
                    .textCase(nil)
            }
        }
    }

    // MARK: 电量采样

    private func batteryCard() -> some View {
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
                VFieldRow(label: "采样时间", value: sampleText)
                VFieldRow(label: "走势跨度", value: trendSpanText)
            }
        }
    }

    /// 走势跨度：采样点的首末时间差（没有采样就说没有，不编一个 0 天）。
    private var trendSpanText: String {
        guard let first = samples.first, let last = samples.last else { return "还没有采样" }
        let days = max(1, Int((last.t - first.t) / 86_400_000) + 1)
        return "跨 \(days) 天 · \(samples.count) 点"
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

    // MARK: 电池档案（型号与换电日期归「电池档案」页，这里只留入口，不再第二处编辑同一字段）

    private var batteryEntrySection: some View {
        Section {
            VFieldRow(label: "上次换电", value: batteryDateText)
            VOutlineButton(title: "打开电池档案（型号 / 换电日 / 低电阈值）", systemImage: "battery.75percent") {
                router.request(.dest(.batteryProfile))
            }
        } header: {
            HStack(spacing: V.S.gapS) {
                Text("电池档案")
                    .font(V.F.section)
                    .foregroundStyle(V.C.text1)
                    .textCase(nil)
                Spacer(minLength: 0)
                Text(meta.batteryModel.isEmpty ? "未记录型号" : meta.batteryModel)
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text3)
                    .textCase(nil)
            }
        }
    }

    // MARK: 连接环境

    private var environmentSection: some View {
        Section {
            // 连接状态与信号都走 Reading：dBm + 档位词的拼法、已连接/未连接的判据全仓各只有一处。
            VFieldRow(label: "当前链路", value: Reading.link(mac).text)
            VFieldRow(label: "最近信号", value: Reading.signal(mac).spoken)
            VFieldRow(label: "上次握手耗时", value: link.connectMs.map { "\($0) ms" } ?? "未测")
            Text("连接环境只看最近一次扫描与握手；读不到就写读不到，不拿邻近数值冒充。")
                .font(V.F.unit)
                .foregroundStyle(V.C.text3)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("连接环境")
                .font(V.F.section)
                .foregroundStyle(V.C.text1)
                .textCase(nil)
        }
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
            SettingsNote(text: "进页会自动读一次锁状态。本页只读：校时在「锁实况」，静音 / 安全模式 / 防尾随在「锁设置」，电池型号与换电日在「电池档案」。")
        }
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
    }

    // MARK: 读数

    private func firmwareAge(_ kc: Keychain) -> String {
        var fw = kc.fw
        if let f = status?.firmware, !f.isEmpty { fw = f }
        guard let since = BatteryCare.fwSince(kc.mac, fw: fw) else { return "首次读到后起算" }
        let days = max(0, Int(Date().timeIntervalSince1970 * 1000 - since.at) / 86_400_000)
        return days > 365 ? "\(days) 天 · 已超一年" : "\(days) 天"
    }

    private func boundText(_ kc: Keychain) -> String {
        guard let d = DF.iso().date(from: kc.pairedAt) else { return "—" }
        return DF.localDate(d)
    }

    /// MAC 只显示后 6 位：整串 12 位 hex 对用户没有意义，需要核对时用上面的「复制完整 MAC」。
    private func shortMAC(_ m: String) -> String {
        let h = DB.normalizeMac(m)
        guard h.count == 12 else { return m }
        return String(h.suffix(6)).uppercased()
    }

    private var verifiedText: String {
        let t = meta.verifiedAt
        guard t > 0 else { return "待验证（成功开一次锁即打标）" }
        return "已验证 · " + DF.localShort(Date(timeIntervalSince1970: t))
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

    /// 本机钥匙串的 PIN 数与锁端存量的对照说明（不一致 = 池子污染/两台 App 打架）。
    private var localPinNote: String? {
        let local = kc?.pins.filter { !$0.isEmpty }.count ?? 0
        guard let stock = status?.pinStock, let cap = status?.pinInfoCapacity, cap > 0 else { return nil }
        let onLock = max(cap - stock, 0)
        if local == 0 { return "本机池为空" }
        if local == onLock { return "本机池 \(local) 枚 · 与锁端一致" }
        return "本机池 \(local) 枚 · 锁端已用 \(onLock) 枚 —— 不一致，现签凭证会被拒（PIN 码无效）"
    }

    private var localPinMismatch: Bool {
        let local = kc?.pins.filter { !$0.isEmpty }.count ?? 0
        guard let stock = status?.pinStock, let cap = status?.pinInfoCapacity, cap > 0 else { return false }
        return local != max(cap - stock, 0)
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
        // E-07：await 期间换锁会把快照/电池采样写到另一把锁。
        let mac = self.mac
        guard !mac.isEmpty, !busy else { return }
        busy = true
        outcome = nil
        defer { busy = false }
        link.update(mac: mac)
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            let st = try await LockService.shared.getStatus(mac: mac)
            DB.writeStatus(mac, st)
            status = st
            samples = BatteryCare.samples(mac)
            // 2026-11-02：**进页自动校时已删**。它是个会改锁的隐式动作（用户只是来看容量），
            // 而「校时」已并入「锁实况」页、由那里的「同步门锁时间」按钮显式执行。
            // 本页现在只读：读不到时钟就如实说读不到，不替用户写一次锁钟。
            outcome = "已重新读取锁信息"
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
