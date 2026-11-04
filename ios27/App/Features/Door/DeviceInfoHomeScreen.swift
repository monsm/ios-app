// DeviceInfoHomeScreen.swift —— 锁信息名片（V8 设计语言）
//
// 与 DeviceInfoScreen 的能力对齐：身份（昵称 / 型号 / 固件 / Boot / 键盘 / 服役天数 / MAC / 绑定于 /
// 链路验证 / 锁钟偏差）、运行状态（电量 / 安全模式 / 锁内时间 / 信号 / 三类容量 / PIN 池对照）、
// 电量采样走势、电池档案（本机台账，可编辑）、重新读取。
// 只改渲染层：读仍走 LockService.ensureConnected → getStatus → DB.writeStatus；
// 电池档案仍走 LockArchive.meta / LockArchive.save；进页自动校时的分支与错误通道原样保留。
//
// 与旧页的两处刻意差异：
//   ① 删掉「连接环境」卡：它的三项在本页生命周期里从不刷新 —— 当前链路取自本页私有的
//      LinkSenseModel 副本（update 只在连接前调一次），握手耗时只有「预热 / 重连」动作才会写，
//      而本页没有这两个动作，所以那两行恒为「未测」。信号改读最近一次实测值（与门页同一来源），
//      不再拿一个不会更新的相位冒充「当前链路」。
//   ② 空壳模式（胁迫码进入）下整页只显示说明卡：旧页会把真实锁名、MAC、绑定时间与电池档案摊开。
import SwiftUI

struct DeviceInfoHomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    @State private var status: LockStatus?
    @State private var samples: [BattSample] = []
    @State private var clockDrift: Int?
    @State private var busy = false
    @State private var outcome: String?
    @State private var outcomeIsFailure = false
    /// 读取失败单独一条 —— 失败卡只描述「读锁」，不把电池档案的提示混进来。
    @State private var readError: String?
    /// 自动校时失败单独一条 —— 它既不是「读锁失败」，也不能被 try? 吞掉。
    @State private var syncError: String?
    @State private var batteryModel = ""
    @State private var batterySaved = false
    @State private var batteryNote: String?

    private var mac: String { app.lock?.id ?? "" }
    private var kc: Keychain? { app.currentKeychain }
    private var meta: LockMeta { LockArchive.meta(mac) }
    private var decoyed: Bool { DB.isDecoy }

    // MARK: - 判断句与副文

    private var judgement: String {
        if decoyed { return "空壳模式下不显示锁信息" }
        guard let kc else { return "还没有门锁" }
        return "「" + LockArchive.displayName(kc) + "」"
    }

    private var lead: String {
        if decoyed { return "空壳模式只隐藏、不改动：这把锁的身份、绑定与电池档案都不显示，也不会写入。退出空壳后才能看。" }
        if kc == nil { return "锁信息名片读的是具体一把锁的固件与容量。先把门锁加进来，再回这一页。" }
        return "进页自动读一次锁端读数；锁钟偏差超过 2 秒时自动校时一次。只读页，不动锁端任何设置。"
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            if decoyed || kc == nil {
                EmptyView()
            } else {
                chipRow
            }
        } content: {
            if decoyed {
                decoyCard
            } else if let kc {
                identityCard(kc)
                statusCard
                batterySampleCard
                batteryArchiveCard
                reloadCard
            } else {
                VEmpty(
                    title: "还没有门锁",
                    reason: "锁信息名片读的是具体一把锁的固件与容量。先把门锁加进来，再回这一页。",
                    actionTitle: "添加门锁"
                ) { router.request(.dest(.addLock)) }
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task {
            batteryModel = meta.batteryModel
            await reload()
        }
    }

    // MARK: - 芯片行

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: V8.S.gapChip) {
                VChip2(icon: .ring(batteryFraction, batteryTintValue), label: "电量", value: batteryText)
                VChip2(icon: .glyph("lock.shield.fill"), label: "安全模式", value: modeText)
                VChip2(icon: .ring(driftFraction, driftTint), label: "锁钟偏差", value: driftText)
                VChip2(icon: .glyph("chart.bar.fill"), label: "采样点", value: "\(samples.count) 个")
            }
            .padding(.leading, V8.S.gutterCard)
            .padding(.trailing, V8.S.gutterCard)
        }
        .scrollClipDisabled()
    }

    // MARK: - 空壳

    private var decoyCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "锁信息名片", statement: "空壳模式只读")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("空壳模式（胁迫码进入）下，这把锁的昵称、MAC、绑定时间、链路验证与电池档案都不显示 —— 这些正是「这把锁是谁、在哪」的答案。")
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink3)
                .lineSpacing(V8.L.body - V8.T.body.size)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Text("退出空壳请在本机密码界面输入正常密码。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 卡 1 身份

    private func identityCard(_ kc: Keychain) -> some View {
        VCard2 {
            VCardHead(eyebrow: "身份", statement: LockArchive.displayName(kc), trailing: PidMap.productName(kc.pid))
            VDivider2()
                .padding(.top, V8.S.gapM)
            HStack(spacing: V8.S.gapM) {
                Image(systemName: LockArchive.symbolName(meta))
                    .font(V8.T.chipValue)
                    .foregroundStyle(swatchTint(meta.colorKey))
                    .frame(width: V8.S.gapXXL, height: V8.S.gapXXL)
                    .background(V8.C.well, in: Circle())
                    .accessibilityHidden(true)
                Text(LockArchive.subtitle(kc))
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                VDataRow(tag: "型号", tagTint: V8.C.ink4, title: PidMap.productName(kc.pid), value: "")
                VDotRule()
                VDataRow(tag: "固件", tagTint: V8.C.ink4, title: firmwareText, value: "")
                VDotRule()
                VDataRow(tag: "Boot", tagTint: V8.C.ink4, title: bootText, value: "")
                VDotRule()
                VDataRow(tag: "键盘", tagTint: V8.C.ink4, title: keyboardText, value: "")
                VDotRule()
                VDataRow(tag: "固件服役", tagTint: V8.C.ink4, title: firmwareAge, value: "")
                VDotRule()
                VDataRow(tag: "MAC", tagTint: V8.C.ink4, title: kc.mac, value: "")
                VDotRule()
                VDataRow(tag: "绑定于", tagTint: V8.C.ink4, title: boundText, value: "")
                VDotRule()
                VDataRow(tag: "链路验证", tagTint: V8.C.ink4, title: verifiedText, value: "")
                VDotRule()
                VDataRow(tag: "锁钟偏差", tagTint: driftTint, title: driftText, value: "")
            }
            .padding(.top, V8.S.gapL)
        }
    }

    // MARK: - 卡 2 运行状态

    private var statusCard: some View {
        VCard2 {
            VCardHead(eyebrow: "运行状态", statement: sampleTimeText)
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStatPair2(items: [
                .init(label: "门锁电量", value: batteryText),
                .init(label: "安全模式", value: modeText)
            ])
            .padding(.top, V8.S.gapM)
            VStatPair2(items: [
                .init(label: "锁内时间", value: lockTimeText),
                .init(label: "信号", value: signalText)
            ])
            .padding(.top, V8.S.gapM)
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                VDataRow(tag: "密码容量", tagTint: V8.C.ink4, title: pwdCapacityText, value: "")
                VDotRule()
                VDataRow(tag: "指纹容量", tagTint: V8.C.ink4, title: fpCapacityText, value: "")
                VDotRule()
                VDataRow(tag: "PIN 容量", tagTint: V8.C.ink4, title: pinCapacityText, value: "")
            }
            .padding(.top, V8.S.gapS)
            if let note = localPinNote {
                Text(note)
                    .font(V8.T.footnote)
                    .foregroundStyle(localPinMismatch ? V8.C.warn : V8.C.ink3)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Boot / 键盘版本只在锁上报时出现；缺失表示该固件不报这两支，不是读取失败。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 卡 3 电量采样

    private var batterySampleCard: some View {
        VCard2 {
            VCardHead(eyebrow: "电量采样", statement: samples.count >= 2 ? "\(samples.count) 个采样点" : "还不够画走势", trailing: batteryModel.isEmpty ? "未记录型号" : batteryModel)
            VDivider2()
                .padding(.top, V8.S.gapM)
            if samples.count >= 2 {
                VRangeCaption(text: "电量 % · 最近 \(samples.count) 个采样")
                    .padding(.top, V8.S.gapM)
                VSpark(values: samples.suffix(24).map { Double($0.pct) }, tint: V8.C.okFill, cursor: nil, axis: .samples)
                    .padding(.top, V8.S.gapS)
                Text(trendCaption)
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(samples.isEmpty
                     ? "还没有采样。每次连上锁读状态都会自动记一笔，曲线要积累几个点才画得出来。"
                     : "已积累 1 个采样点，再连几次就能画出走势。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VDivider2()
                .padding(.top, V8.S.gapM)
            VDataRow(tag: "采样时间", tagTint: V8.C.ink4, title: sampleTimeText, value: "")
            VDotRule()
            VDataRow(tag: "耗材提醒", tagTint: V8.C.ink4, title: batteryModel.isEmpty ? "未记录型号" : batteryModel, value: "")
        }
    }

    private var trendCaption: String {
        guard let first = samples.first, let last = samples.last else { return "" }
        let lo = samples.map(\.pct).min() ?? 0
        let hi = samples.map(\.pct).max() ?? 0
        let days = max(1, Int((last.t - first.t) / 86_400_000) + 1)
        return "走势：\(samples.count) 个采样点 · 跨 \(days) 天 · 最低 \(lo)% / 最高 \(hi)%"
    }

    // MARK: - 卡 4 电池档案

    private var batteryArchiveCard: some View {
        VCard2 {
            VCardHead(eyebrow: "电池档案", statement: batteryModel.isEmpty ? "未填型号" : batteryModel, trailing: batterySaved ? "已保存" : "本机")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(alignment: .leading, spacing: V8.S.gapXS) {
                Text("电池型号")
                    .font(V8.T.label)
                    .foregroundStyle(V8.C.ink4)
                TextField("如 CR123A × 2", text: $batteryModel)
                    .font(V8.T.body)
                    .foregroundStyle(V8.C.ink1)
                    .frame(minHeight: V8.H.min)
                    .padding(.horizontal, V8.S.gapM)
                    .background(V8.C.well, in: .rect(cornerRadius: V8.R.inset))
            }
            .padding(.top, V8.S.gapM)
            VDataRow(tag: "上次换电", tagTint: V8.C.ink4, title: batteryDateText, value: "")
                .padding(.top, V8.S.gapS)
            HStack(spacing: V8.S.gapS) {
                Button {
                    markBatteryToday()
                } label: {
                    Text("记为今天")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.accent)
                        .padding(.horizontal, V8.S.gapM)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.accentTrack))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("把上次换电记为今天")
                Button {
                    saveBatteryModel()
                } label: {
                    Text("保存型号")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.chipOn)
                        .padding(.horizontal, V8.S.gapM)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.accent))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("保存电池型号")
            }
            .padding(.top, V8.S.gapM)
            if let batteryNote {
                Text(batteryNote)
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.danger)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("档案只存本机，不写入门锁；换电日期只用来估续航。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 卡 5 重新读取

    private var reloadCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "读取", statement: busy ? "正在读取…" : "重新读一次锁端")
            VDivider2()
                .padding(.top, V8.S.gapM)
            if busy {
                VBusy(text: "正在与门锁通信…")
                    .padding(.top, V8.S.gapM)
            } else if let readError {
                VFailure(
                    what: "读取锁信息失败",
                    why: readError,
                    next: "走近门锁、确认蓝牙开着，再点「重新读取」。",
                    retry: { Task { await reload() } }
                )
                .padding(.top, V8.S.gapM)
            } else if let syncError {
                VFailure(
                    what: "自动校时失败",
                    why: syncError,
                    next: "锁钟偏着会让临时码与时间窗凭证整段失效。到「锁设置」的校时入口手动同步一次，或再点「重新读取」。",
                    retry: { Task { await reload() } }
                )
                .padding(.top, V8.S.gapM)
            } else {
                Button {
                    Task { await reload() }
                } label: {
                    Text("重新读取")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.chipOn)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.accent))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("重新读取锁信息")
                .padding(.top, V8.S.gapM)
                if let outcome {
                    Text(outcome)
                        .font(V8.T.footnote)
                        .foregroundStyle(outcomeIsFailure ? V8.C.danger : V8.C.ok)
                        .padding(.top, V8.S.gapS)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("静音、安全模式、校时、防尾随与固件升级在「锁设置」里。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 读数

    private func swatchTint(_ key: String) -> Color {
        switch key {
        case "ok": return V8.C.ok
        case "warn": return V8.C.warn
        case "danger": return V8.C.danger
        case "neutral": return V8.C.ink3
        default: return V8.C.accent
        }
    }

    private var firmwareText: String {
        if let fw = status?.firmware, !fw.isEmpty { return fw }
        let f = kc?.fw ?? ""
        return f.isEmpty ? "未知" : f
    }

    private var bootText: String {
        let v = status?.verDFU ?? 0
        return v > 0 ? "\(v)" : "该固件未上报"
    }

    private var keyboardText: String {
        let v = status?.verKeyboard ?? 0
        return v > 0 ? "\(v)" : "该固件未上报"
    }

    private var firmwareAge: String {
        var fw = kc?.fw ?? ""
        if let f = status?.firmware, !f.isEmpty { fw = f }
        guard let since = BatteryCare.fwSince(mac, fw: fw) else { return "首次读到后起算" }
        let days = max(0, Int(Date().timeIntervalSince1970 * 1000 - since.at) / 86_400_000)
        if days == 0 { return "今天起算" }
        return days > 365 ? "\(days) 天 · 已超一年" : "\(days) 天"
    }

    private var boundText: String {
        // pairedAt 是 DF.iso() 写的 UTC 串，必须走本地化解析，不能 prefix 当本地时间。
        let s = DF.localMinute(fromISO: kc?.pairedAt ?? "")
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
        guard let d = clockDrift else { return V8.C.ink4 }
        return abs(d) > 60 ? V8.C.warn : V8.C.ink4
    }

    private var driftFraction: Double {
        guard let d = clockDrift else { return 0 }
        return min(1, Double(abs(d)) / 120)
    }

    private var batteryText: String {
        let p = BatteryCare.displayPct(mac, snapshot: status?.powerLevel ?? DB.readStatus(mac)?.powerLevel ?? -1)
        return BatteryCare.faceText(p)
    }

    private var batteryTintValue: Color {
        let p = BatteryCare.displayPct(mac, snapshot: status?.powerLevel ?? DB.readStatus(mac)?.powerLevel ?? -1)
        return p >= 0 && p <= 20 ? V8.C.warn : V8.C.ok
    }

    private var batteryFraction: Double {
        let p = BatteryCare.displayPct(mac, snapshot: status?.powerLevel ?? DB.readStatus(mac)?.powerLevel ?? -1)
        return p < 0 ? 0 : Double(p) / 100
    }

    private var modeText: String {
        guard let st = status else { return "—" }
        if st.verifyMode == 1 && st.broadcastMode != 0 { return "B · 双验" }
        if st.verifyMode == 1 { return "C · 广播+验证" }
        return "A · 单验"
    }

    private var lockTimeText: String {
        // 0 = 锁端没回时钟（不是 2010-01-01）；ProtoTime.localStr(0) 返回空串。
        guard let t = status?.lockTime, t > 0 else { return "—" }
        let s = ProtoTime.localStr(t)
        return s.isEmpty ? "—" : s
    }

    private var signalText: String {
        guard let r = DB.store.get(Int.self, "kf_linkrssi_" + mac) else { return "未测" }
        return "\(r) dBm · " + LinkSenseModel.levelWord(LinkSenseModel.level(r))
    }

    private var sampleTimeText: String {
        let at = max(LockStats.snapAt(mac), samples.last?.t ?? 0)
        return at > 0 ? LockStats.sampleTimeText(at) : "尚未读取过快照"
    }

    private var batteryDateText: String {
        guard meta.batteryChangedAt > 0 else { return "未记录" }
        return DF.localDate(Date(timeIntervalSince1970: meta.batteryChangedAt))
    }

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

    private var pinUsed: Int {
        if let cap = liveStatus?.pinInfoCapacity ?? cachedStatus?.pinCap, cap > 0 {
            let stock = liveStatus?.pinStock ?? cachedStatus?.pinStock ?? 0
            return max(cap - stock, 0)
        }
        return kc?.pins.count ?? 0
    }

    private var pwdCapacityText: String {
        capacityText(used: pwdUsed, cap: liveStatus?.pwdInfoCapacity ?? cachedStatus?.pwdCap ?? 0)
    }

    private var fpCapacityText: String {
        capacityText(used: fpUsed, cap: liveStatus?.fpInfoCapacity ?? cachedStatus?.fpCap ?? 0)
    }

    private var pinCapacityText: String {
        capacityText(used: pinUsed, cap: liveStatus?.pinInfoCapacity ?? cachedStatus?.pinCap ?? 0)
    }

    /// 容量读数两个数都要读成「已用 / 容量」；容量未读时只报已用，并说清容量确实没读到。
    private func capacityText(used: Int, cap: Int) -> String {
        cap > 0 ? "\(max(used, 0)) / \(cap)" : "已用 \(max(used, 0)) · 容量未读"
    }

    /// 本机钥匙串的 PIN 数与锁端存量的对照说明（不一致 = 池子污染 / 两台 App 打架）。
    private var localPinNote: String? {
        let local = kc?.pins.filter { !$0.isEmpty }.count ?? 0
        guard let stock = status?.pinStock, let cap = status?.pinInfoCapacity, cap > 0 else { return nil }
        let onLock = max(cap - stock, 0)
        if local == 0 { return "本机池为空" }
        if local == onLock { return "本机池 \(local) 枚 · 与锁端一致" }
        return "本机池 \(local) 枚 · 锁端已用 \(onLock) 枚 —— 不一致，现签凭证会被锁拒绝（凭证不在锁的名单里）"
    }

    private var localPinMismatch: Bool {
        let local = kc?.pins.filter { !$0.isEmpty }.count ?? 0
        guard let stock = status?.pinStock, let cap = status?.pinInfoCapacity, cap > 0 else { return false }
        return local != max(cap - stock, 0)
    }

    // MARK: - 电池档案（本机台账）

    private func markBatteryToday() {
        guard !DB.isDecoy else {
            batteryNote = "空壳模式下不写电池档案 —— 先退出空壳再来改。"
            batterySaved = false
            return
        }
        guard !mac.isEmpty else { return }
        var m = LockArchive.meta(mac)
        m.batteryChangedAt = Date().timeIntervalSince1970
        m.batteryModel = batteryModel.trimmingCharacters(in: .whitespaces)
        LockArchive.save(mac, m)
        batteryNote = nil
        batterySaved = true
    }

    private func saveBatteryModel() {
        guard !DB.isDecoy else {
            batteryNote = "空壳模式下不写电池档案 —— 先退出空壳再来改。"
            batterySaved = false
            return
        }
        guard !mac.isEmpty else { return }
        var m = LockArchive.meta(mac)
        m.batteryModel = batteryModel.trimmingCharacters(in: .whitespaces)
        LockArchive.save(mac, m)
        batteryNote = nil
        batterySaved = true
    }

    // MARK: - 真链路

    private func reload() async {
        // E-07：await 期间换锁会把快照 / 电池采样写到另一把锁。
        let mac = self.mac
        guard !decoyed, !mac.isEmpty, !busy else { return }
        busy = true
        outcome = nil
        outcomeIsFailure = false
        readError = nil
        syncError = nil
        defer { busy = false }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            var st = try await LockService.shared.getStatus(mac: mac)
            DB.writeStatus(mac, st)
            status = st
            samples = BatteryCare.samples(mac)
            // lockTime == 0 是「锁端没回时钟」的占位值：直接算会得到 ≈ -531260264 秒的假偏差，
            // 而且会让下面每次进页都白写一次锁钟。读不到就是「不知道」。
            let drift = (st.lockTime ?? 0) > 0 ? Int((st.lockTime ?? 0) - ZKProtocol.nowProtoSeconds()) : nil
            clockDrift = drift
            if let drift, abs(drift) > 2 {
                if app.trialGuard {
                    // 只读试验模式拦的是下发到门锁的写命令；自动校时正是一条写命令。
                    outcome = "检测到锁钟偏差 \(drift) 秒；只读试验模式已开启，不自动校时。"
                } else {
                    // 检测到漂移却校时失败时必须说出来，不能 try? 吞掉。
                    do {
                        let res = try await LockService.shared.syncTime()
                        st = try await LockService.shared.getStatus(mac: mac)
                        DB.writeStatus(mac, st)
                        status = st
                        clockDrift = (st.lockTime ?? 0) > 0 ? Int((st.lockTime ?? 0) - ZKProtocol.nowProtoSeconds()) : nil
                        outcome = "已自动校时 · 校前偏差 \(res.before) 秒 / 校后 \(res.after) 秒"
                    } catch {
                        outcomeIsFailure = true
                        syncError = "检测到锁钟偏差 \(drift) 秒，但校时没成功："
                            + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                    }
                }
            } else {
                outcome = "已重新读取锁信息"
            }
            await app.reload(refreshStatus: false)
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            readError = msg
            outcome = msg
            outcomeIsFailure = true
        }
    }
}
